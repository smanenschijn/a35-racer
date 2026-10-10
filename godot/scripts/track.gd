class_name Track
extends RefCounted
## The road: a centreline integrated from the OpenStreetMap curvature profile, with stages, bridges,
## tunnels and landmarks (port of src/track/Track.ts).
##
## Heading convention: forward = (sin θ, cos θ) in the XZ plane, so θ = 0 faces +Z.
## Increasing θ turns left; the right vector is (-cos θ, sin θ).

const ROUTE_FILE := "res://assets/route/campaign.json"

## Interpolated frame at a distance along the centreline.
class Frame:
	var x := 0.0
	var y := 0.0
	var z := 0.0
	var heading := 0.0
	var fx := 0.0
	var fz := 1.0
	var rx := -1.0
	var rz := 0.0
	var curvature := 0.0
	var slope := 0.0 # dy/ds


## Result of projecting a world point onto the road.
class Proj:
	var idx := -1
	var s := 0.0
	var d := 0.0


var spacing := Config.SAMPLE_SPACING
var count := 0
var length := 0.0
var name := ""
## startS, finishS, bridges, viaducts, gantries, exits, landmarks, checkpoints, stages, tunnels, single, waters
var features := {}
var stage := {}
var _xs := PackedFloat64Array()
var _zs := PackedFloat64Array()
var _ys := PackedFloat64Array()
var _hs := PackedFloat64Array()
var _ks := PackedFloat64Array()
var _single_mask := PackedByteArray()
var _tmp := Frame.new()


static func load_route() -> Dictionary:
	var f := FileAccess.open(ROUTE_FILE, FileAccess.READ)
	if f == null:
		push_error("Route ontbreekt: draai scripts/sync-godot-assets.sh")
		return {}
	return JSON.parse_string(f.get_as_text())


func _init(route: Dictionary) -> void:
	name = route.name
	var stages: Array = route.stages
	# Bridges before the first start line are left out so the grid stands on flat road.
	var bridges := []
	for b in route.bridges:
		if b.s0 > stages[0].startS + 150:
			bridges.append({"s0": float(b.s0), "s1": float(b.s1), "canal": b.canal,
				"height": 7.5 if b.canal else 6.5, "ramp": 200.0 if b.canal else 170.0})
	var viaducts := []
	for s in route.overpasses:
		var in_tunnel := false
		for t in route.tunnels:
			if s > t.s0 - 30 and s < t.s1 + 30:
				in_tunnel = true
		if s > 40 and s < route.length - 40 and not in_tunnel:
			viaducts.append(float(s))
	var single := []
	for p in route.profile:
		if p.type == "single":
			single.append({"s0": float(p.s0), "s1": float(p.s1)})
	features = {
		"startS": 0.0, "finishS": 0.0,
		"bridges": bridges,
		"viaducts": viaducts,
		"gantries": _gantries_for(route),
		"exits": route.exits,
		"landmarks": route.landmarks,
		"checkpoints": [],
		"stages": stages,
		"tunnels": route.tunnels,
		"single": single,
		"waters": route.waters,
	}
	var rl := int(route.length)
	_single_mask.resize(rl + 2)
	for p in single:
		for i in range(maxi(0, int(p.s0)), mini(rl + 1, int(p.s1))):
			_single_mask[i] = 1
	set_stage(stages.size() - 1)

	# Integrate the curvature profile into a centreline (x/z), with heading and height.
	var curv: Array = route.curvature
	count = curv.size()
	length = (count - 1) * spacing
	_ks.resize(count)
	_xs.resize(count)
	_zs.resize(count)
	_ys.resize(count)
	_hs.resize(count)
	var x := 0.0
	var z := 0.0
	var h := 0.0
	for i in count:
		var k: float = curv[i]
		_ks[i] = k
		_xs[i] = x
		_zs[i] = z
		_hs[i] = h
		_ys[i] = _elevation(i * spacing)
		h += k * spacing
		x += sin(h) * spacing
		z += cos(h) * spacing


## Overhead signs ~350 m before each exit: the through destination and the exit itself.
static func _gantries_for(route: Dictionary) -> Array:
	var out := []
	var exits: Array = route.exits
	var stages: Array = route.stages
	for i in exits.size():
		var e: Dictionary = exits[i]
		var s: float = e.s - 350
		if s < stages[0].startS + 80:
			continue
		var close := false
		for g in out:
			if absf(g.s - s) < 300:
				close = true
		if close:
			continue
		# Through destination: the next big town further along the route.
		var ahead = null
		for st in stages:
			if st.finishS > e.s:
				ahead = st
				break
		var through := "Enschede"
		if i >= exits.size() - 1:
			through = "Gronau (D)"
		elif ahead != null and ahead.to != e.name:
			through = ahead.to
		var exit_name: String = String(e.name).split(";")[0].strip_edges()
		out.append({"s": s, "text": [through, "%s  %s" % [exit_name, String(e.ref).split(";")[0]]], "route": "A35"})
	return out


## Make stage i (0-based) the current one: start/finish lines and checkpoints.
func set_stage(i: int) -> void:
	var st: Dictionary = features.stages[i]
	stage = st
	features.startS = float(st.startS)
	features.finishS = float(st.finishS)
	var cps := []
	for f in [0.27, 0.52, 0.77]:
		cps.append(float(roundi(st.startS + (st.finishS - st.startS) * f)))
	features.checkpoints = cps


## One carriageway with oncoming traffic in the left lane?
func is_single(s: float) -> bool:
	return _single_mask[clampi(roundi(s), 0, _single_mask.size() - 1)] == 1


func in_tunnel(s: float, margin := 0.0) -> bool:
	for t in features.tunnels:
		if s > t.s0 - margin and s < t.s1 + margin:
			return true
	return false


static func _smoothstep(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## How much a bridge lifts the road at s (0..height).
func bridge_lift(s: float) -> float:
	var lift := 0.0
	for b in features.bridges:
		var up := _smoothstep(b.s0 - b.ramp, b.s0, s)
		var down := 1.0 - _smoothstep(b.s1, b.s1 + b.ramp, s)
		lift = maxf(lift, b.height * minf(up, down))
	return lift


func _elevation(s: float) -> float:
	var bridge := bridge_lift(s)
	var roll := 0.9 * sin(s / 240.0) + 0.5 * sin(s / 97.0 + 1.3)
	# Flatten the gentle undulation where the road climbs onto a bridge.
	var flat := 1.0 - minf(1.0, bridge / 2.0)
	return 1.4 + roll * flat + bridge


## Interpolated frame at distance s along the centreline.
func frame(s: float, out: Frame = null) -> Frame:
	if out == null:
		out = Frame.new()
	var f := clampf(s / spacing, 0.0, count - 1.0001)
	var i := int(f)
	var t := f - i
	out.x = _xs[i] + (_xs[i + 1] - _xs[i]) * t
	out.z = _zs[i] + (_zs[i + 1] - _zs[i]) * t
	out.y = _ys[i] + (_ys[i + 1] - _ys[i]) * t
	out.heading = _hs[i] + (_hs[i + 1] - _hs[i]) * t
	out.curvature = _ks[i] + (_ks[i + 1] - _ks[i]) * t
	out.slope = (_ys[i + 1] - _ys[i]) / spacing
	out.fx = sin(out.heading)
	out.fz = cos(out.heading)
	out.rx = -out.fz
	out.rz = out.fx
	return out


func height_at(s: float) -> float:
	var f := clampf(s / spacing, 0.0, count - 1.0001)
	var i := int(f)
	return _ys[i] + (_ys[i + 1] - _ys[i]) * (f - i)


func curvature_at(s: float) -> float:
	return _ks[clampi(roundi(s / spacing), 0, count - 1)]


## World position for track coordinates (s, d), with optional height offset.
func point_at(s: float, d: float, up := 0.0) -> Vector3:
	var fr := frame(s, _tmp)
	return Vector3(fr.x + fr.rx * d, fr.y + up, fr.z + fr.rz * d)


## Project a world XZ point onto the track. Uses hill climbing from the hint index,
## which is safe because the road never comes close to itself.
func project(x: float, z: float, hint := -1, out: Proj = null) -> Proj:
	if out == null:
		out = Proj.new()
	var i := hint
	if i < 0 or i >= count:
		var best := INF
		for j in range(0, count, 4):
			var dd := (_xs[j] - x) * (_xs[j] - x) + (_zs[j] - z) * (_zs[j] - z)
			if dd < best:
				best = dd
				i = j
	var cur := (_xs[i] - x) * (_xs[i] - x) + (_zs[i] - z) * (_zs[i] - z)
	for _guard in 4000:
		if i + 1 < count:
			var n := (_xs[i + 1] - x) * (_xs[i + 1] - x) + (_zs[i + 1] - z) * (_zs[i + 1] - z)
			if n < cur:
				i += 1
				cur = n
				continue
		if i > 0:
			var p := (_xs[i - 1] - x) * (_xs[i - 1] - x) + (_zs[i - 1] - z) * (_zs[i - 1] - z)
			if p < cur:
				i -= 1
				cur = p
				continue
		break
	# Refine within the segment around i.
	var h := _hs[i]
	var fx := sin(h)
	var fz := cos(h)
	var dx := x - _xs[i]
	var dz := z - _zs[i]
	var along := dx * fx + dz * fz
	out.idx = i
	out.s = clampf(i * spacing + along, 0.0, length)
	out.d = dx * -fz + dz * fx
	return out
