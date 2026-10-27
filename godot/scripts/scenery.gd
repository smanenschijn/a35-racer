class_name Scenery
extends RefCounted
## Roadside detail from OpenStreetMap (tools/osm/build_campaign.py): at-grade junctions with side roads,
## stop lines and traffic lights, signalled cycle crossings, slip roads closed off with barriers and an
## arrow trailer, railway crossings (a level crossing with booms and a passing train), and points of
## interest along the way: church towers, windmills, a water tower, petrol stations, snack bars, masts,
## chimneys and the theme parks. Static parts go through TrackBuilder's batching; what moves (lights,
## booms, the train, sails, wheels, beacons) lives under `root` and is driven by update().

const STOP_BACK := 4.0 # stop line this far before the junction's near edge
const TRAIN_SPEED := 32.0
const TRAIN_CARS := 3
const TRAIN_CAR_LEN := 26.0

var b: TrackBuilder
var t: Track
var root := Node3D.new()
## Per signalled junction: {s, stop, stop_opp, main: [r, a, g], cross: [r, a, g], t, state, single}
var lights: Array = []
## Level crossings: {s, booms: [Node3D], lamps: Material, train: Node3D, dir: Vector3, origin: Vector3, t, phase}
var crossings: Array = []
## Slip road arrow trailers (flashing).
var _arrows: Array = []
## Things that turn: [Node3D, axis, speed]
var _spinners: Array = []
## Things that blink: [Material, period, offset]
var _blinkers: Array = []
var _time := 0.0
var _mats := {}
var _fr := Track.Frame.new()


func _init(builder: TrackBuilder) -> void:
	b = builder
	t = builder.track


# ------------------------------------------------------------------ helpers

func _m(hex: String, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f" % [hex, rough, metal]
	if not _mats.has(key):
		_mats[key] = TrackBuilder.mat(Color(hex), rough, metal)
	return _mats[key]


func _tex_m(tex: Texture2D, glow := 0.0) -> StandardMaterial3D:
	var m := TrackBuilder.mat(Color.WHITE, 0.6, 0.0, tex)
	if glow > 0:
		m.emission_enabled = true
		m.emission = Color.WHITE
		m.emission_texture = tex
		m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		m.emission_energy_multiplier = glow
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _lamp_m(col: Color) -> StandardMaterial3D:
	var m := TrackBuilder.mat(col.darkened(0.75), 0.4)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.0
	return m


static func _box(w: float, h: float, d: float) -> BoxMesh:
	var bx := BoxMesh.new()
	bx.size = Vector3(w, h, d)
	return bx


static func _cyl(r_top: float, r_bot: float, h: float, seg := 10) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


static func _quad(w: float, h: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	return q


## World transform at road coordinates, yaw relative to the road heading (local +Z = forward, +X = left).
func _xf(s: float, d: float, up := 0.0, yaw := 0.0) -> Transform3D:
	return b._place_xf(s, d, up, yaw)


## Transform on the ground (y = 0) at road coordinates, facing the road.
func _ground_xf(s: float, d: float, y := 0.0) -> Transform3D:
	var fr := t.frame(clampf(s, 0.0, t.length), _fr)
	var p := Vector3(fr.x + fr.rx * d, y, fr.z + fr.rz * d)
	# Face the road: look back towards the centreline.
	var side := signf(d) if d != 0 else 1.0
	return Transform3D(Basis(Vector3.UP, atan2(-side * fr.rx, -side * fr.rz)), p)


## A flat strip along a polyline (centre points, half width), merged into the cell buckets.
func strip(pts: Array, half_w: float, m: Material, u_scale := 8.0) -> void:
	if pts.size() < 2:
		return
	var cur: TrackBuilder.Bucket = null
	var prev := {}
	var v := 0.0
	for i in pts.size():
		var p: Vector3 = pts[i]
		var nb: Vector3 = pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]
		var dir := Vector3(nb.x, 0, nb.z).normalized()
		var side := Vector3(dir.z, 0, -dir.x) * half_w
		if i > 0:
			v += (p - pts[i - 1]).length() / u_scale
		var row := {"l": p + side, "r": p - side, "n": Vector3.UP, "v": v}
		var bk := b._bucket(b._cell_key(p), m, false)
		if cur == null:
			cur = bk
			b._row(cur, row, 0.0, 1.0)
		elif bk == cur:
			b._row(cur, row, 0.0, 1.0)
			b._quad(cur)
		else:
			cur = bk
			b._row(cur, prev, 0.0, 1.0)
			b._row(cur, row, 0.0, 1.0)
			b._quad(cur)
		prev = row


# ------------------------------------------------------------------ build

func build() -> void:
	var f := t.features
	for j in f.junctions:
		_junction(j)
	for r in f.ramps:
		_ramp(r)
	for r in f.railways:
		if r.kind == "level":
			_level_crossing(r)
	for p in f.pois:
		match p.kind:
			"kerk": _church(p)
			"molen": _windmill(p)
			"watertoren": _water_tower(p)
			"tank": _petrol_station(p)
			"snack": _snack_bar(p)
			"mast": _mast(p)
			"schoorsteen": _chimney(p)
			"pretpark": _theme_park(p)
	b.root.add_child(root)


# ------------------------------------------------------------------ junctions

func _junction(j: Dictionary) -> void:
	var s: float = j.s
	var w: float = j.width
	var single := t.is_single(s)
	var asphalt := _m("3a3b3e", 0.9)
	for side in [1.0, -1.0]:
		if (side > 0 and j.right) or (side < 0 and j.left):
			_side_road(s, side, w, j.skew, asphalt, single)
	if j.kind == "cycle":
		_cycle_crossing(s, single)
	var stop: float = s - w / 2.0 - STOP_BACK
	var stop_opp: float = s + w / 2.0 + STOP_BACK
	var white := _m("e9e9e2", 0.7)
	var h := func(ss: float) -> float: return t.height_at(ss) + 0.015
	if j.lights:
		var e: Array = Config.LANE_EDGES
		var from: float = e[1] if single else e[0]
		b.ribbon({"s0": stop - 0.25, "s1": stop + 0.25, "dL": from, "dR": e[2], "yL": h, "yR": h, "step": 0.5}, white)
		if single:
			b.ribbon({"s0": stop_opp - 0.25, "s1": stop_opp + 0.25, "dL": e[0], "dR": e[1], "yL": h, "yR": h, "step": 0.5}, white)
		_signals(j, stop, stop_opp, single)
	# ANWB direction sign ahead of a named side road.
	var names: Array = j.get("names", [])
	if not names.is_empty() and j.kind == "road":
		var left_name: String = names[0] if j.left else ""
		var right_name: String = (names[1] if names.size() > 1 else names[0]) if j.right else ""
		var g := _xf(s - 150, Config.PAVED + 2.2)
		var board := _quad(3.4, 1.7)
		b.add_mesh(board, g * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 2.6, 0)), _tex_m(Tex.direction_sign(left_name, right_name), 0.25))
		for x in [-1.3, 1.3]:
			b.add_mesh(_cyl(0.05, 0.05, 2.6, 6), g * Transform3D(Basis(), Vector3(x, 1.3, 0.03)), _m("8a8d90", 0.5, 0.6))


## A side road leaving at s on one side, sloping down off the embankment to the fields.
func _side_road(s: float, side: float, w: float, skew: float, asphalt: Material, single: bool) -> void:
	var fr := t.frame(s)
	var right := Vector3(fr.rx, 0, fr.rz)
	var fwd := Vector3(fr.fx, 0, fr.fz)
	var dir := (right * side * cos(skew) + fwd * sin(skew)).normalized()
	var start_d := Config.PAVED - 0.2
	var h0 := t.height_at(s)
	var base := Vector3(fr.x, 0, fr.z) + right * side * start_d
	var pts := []
	var grass := []
	var k := 0.0
	while k <= 220.0:
		var y := h0 * (1.0 - smoothstep(6.0, 40.0 + h0 * 6.0, k)) - 0.03
		var p := base + dir * k
		pts.append(Vector3(p.x, maxf(0.04, y), p.z))
		grass.append(Vector3(p.x, maxf(0.0, y - 0.25), p.z))
		k += 4.0 if k < 50 else 10.0
	strip(grass, w / 2.0 + 3.0, b.grass_mat)
	strip(pts, w / 2.0, asphalt)
	# Centre line and the give-way triangles (haaientanden) where it meets the main road.
	var line := []
	for p: Vector3 in pts:
		line.append(p + Vector3(0, 0.012, 0))
	strip(line.slice(2), 0.06, _m("e9e9e2", 0.7))
	var teeth := _quad(0.45, 0.6)
	var tooth_m := _m("e9e9e2", 0.7)
	for i in int(w / 0.9):
		var off := -w / 2.0 + 0.45 + i * 0.9
		var p: Vector3 = base + dir * 2.5 + Vector3(dir.z, 0, -dir.x) * off
		var xf := Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)) * Basis(Vector3.RIGHT, -PI / 2), Vector3(p.x, h0 + 0.02, p.z))
		b.add_mesh(teeth, xf, tooth_m, false)


## Red cycle path across the road with block markings, and the paths running off on both sides.
func _cycle_crossing(s: float, single: bool) -> void:
	var red := _m("a3402f", 0.9)
	var white := _m("e9e9e2", 0.7)
	var h := func(ss: float) -> float: return t.height_at(ss) + 0.012
	var left := -Config.PAVED if single else Config.OPP_OUT
	b.ribbon({"s0": s - 1.6, "s1": s + 1.6, "dL": left, "dR": Config.PAVED, "yL": h, "yR": h, "step": 0.8}, red)
	var hb := func(ss: float) -> float: return t.height_at(ss) + 0.018
	for edge in [s - 1.75, s + 1.75]:
		var d := left
		while d < Config.PAVED:
			b.ribbon({"s0": edge - 0.2, "s1": edge + 0.2, "dL": d, "dR": d + 0.4, "yL": hb, "yR": hb, "step": 0.4}, white)
			d += 0.9
	for side in [1.0, -1.0]:
		var fr := t.frame(s)
		var right := Vector3(fr.rx, 0, fr.rz)
		var start := (Config.PAVED if side > 0 else -left) - 0.1
		var pts := []
		var h0 := t.height_at(s)
		for k in range(0, 120, 6):
			var p: Vector3 = Vector3(fr.x, 0, fr.z) + right * side * (start + k)
			pts.append(Vector3(p.x, maxf(0.04, h0 * (1.0 - smoothstep(4.0, 30.0, k)) - 0.03), p.z))
		strip(pts, 1.25, red)


## Traffic lights for our direction (right pole, overhead arm on wide roads, a pole on the left),
## for oncoming traffic on the N35, and for the side roads.
func _signals(j: Dictionary, stop: float, stop_opp: float, single: bool) -> void:
	var main := [_lamp_m(Color(1, 0.08, 0.05)), _lamp_m(Color(1, 0.55, 0.0)), _lamp_m(Color(0.1, 1, 0.35))]
	var cross := [_lamp_m(Color(1, 0.08, 0.05)), _lamp_m(Color(1, 0.55, 0.0)), _lamp_m(Color(0.1, 1, 0.35))]
	var pole_m := _m("5c6066", 0.5, 0.7)
	var box_m := _m("1a1b1d", 0.6, 0.2)
	var s := stop - 1.0
	# Right-hand pole with a mast arm over the lanes.
	var g := _xf(s, Config.PAVED + 0.9)
	b.add_mesh(_cyl(0.1, 0.13, 6.6, 8), g * Transform3D(Basis(), Vector3(0, 3.3, 0)), pole_m)
	var arm_len := Config.PAVED + 0.9 - Config.LANE_CENTERS[0]
	b.add_mesh(_box(arm_len, 0.14, 0.14), g * Transform3D(Basis(), Vector3(arm_len / 2.0, 6.35, 0)), pole_m)
	for lane in Config.LANE_CENTERS:
		if single and lane < 0:
			continue
		_head(_xf(s, lane, 5.6, PI), main, box_m)
	_head(g * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 3.2, -0.2)), main, box_m)
	# Left: on the median, or across the N35 (with the heads for oncoming traffic on its back).
	var ld := Config.MEDIAN_C if not single else -Config.PAVED - 0.9
	var lg := _xf(s, ld)
	b.add_mesh(_cyl(0.08, 0.1, 3.6, 8), lg * Transform3D(Basis(), Vector3(0, 1.8, 0)), pole_m)
	_head(lg * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 3.2, -0.2)), main, box_m)
	if single:
		var og := _xf(stop_opp + 1.0, -Config.PAVED - 0.9)
		b.add_mesh(_cyl(0.08, 0.1, 3.6, 8), og * Transform3D(Basis(), Vector3(0, 1.8, 0)), pole_m)
		_head(og * Transform3D(Basis(), Vector3(0, 3.2, 0.2)), main, box_m)
	# Side roads: heads facing the cross traffic.
	for side in [1.0, -1.0]:
		if (side > 0 and not j.right) or (side < 0 and not j.left):
			continue
		var d: float = side * (Config.PAVED + 1.5) if side > 0 or single else Config.OPP_OUT - 1.5
		var cs: float = j.s + side * (j.width / 2.0 + 2.0)
		var cg := _xf(cs, d)
		b.add_mesh(_cyl(0.08, 0.1, 3.6, 8), cg * Transform3D(Basis(), Vector3(0, 1.8, 0)), pole_m)
		# Face out along the side road (local +X is the road's left).
		_head(cg * Transform3D(Basis(Vector3.UP, side * PI / 2), Vector3(0, 3.2, 0)), cross, box_m)
	lights.append({"s": j.s, "stop": stop, "stop_opp": stop_opp, "main": main, "cross": cross,
		"t": randf() * 20.0, "state": "", "single": single, "right": j.right, "left": j.left, "width": j.width})


## One signal head: housing with red, amber and green lamps facing local +Z.
func _head(xf: Transform3D, lamps: Array, box_m: Material) -> void:
	b.add_mesh(_box(0.36, 1.0, 0.26), xf, box_m)
	b.add_mesh(_box(0.6, 1.25, 0.04), xf * Transform3D(Basis(), Vector3(0, 0, -0.15)), box_m)
	var lamp := _cyl(0.11, 0.11, 0.05, 12)
	for i in 3:
		b.add_mesh(lamp, xf * Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0.3 - i * 0.3, 0.14)), lamps[i], false)


# ------------------------------------------------------------------ slip roads

## An exit or entry slip road on the right, closed off along the edge of our carriageway with
## red/white barriers, cones and a flashing arrow trailer.
func _ramp(r: Dictionary) -> void:
	var s: float = r.s
	var off: bool = r.kind == "off"
	var asphalt := _m("3d3e41", 0.9)
	var P := Config.PAVED
	# Taper (the extra lane) and the slip road curving away and down to the fields.
	var t0 := s - 190.0 if off else s
	var t1 := s - 60.0 if off else s + 130.0
	var widen := func(ss: float) -> float:
		var k := smoothstep(t0, t1, ss)
		return P + 4.8 * (k if off else 1.0 - k)
	var hh := func(ss: float) -> float: return t.height_at(ss) - 0.02
	b.ribbon({"s0": t0, "s1": t1, "dL": P - 0.3, "dR": widen, "yL": hh, "yR": hh, "step": 2.0}, asphalt)
	var pts := []
	var start := s - 60.0 if off else s
	for i in 40:
		var k := i * 7.0
		var ss := start + k if off else start - k
		var d := P + 2.4 + pow(k / 260.0, 2.0) * 60.0
		var y := t.height_at(ss) * (1.0 - smoothstep(30.0, 230.0, k))
		var p := t.point_at(ss, d)
		pts.append(Vector3(p.x, maxf(0.04, y - 0.02), p.z))
	if not off:
		pts.reverse()
	strip(pts, 2.4, asphalt)
	var edge := []
	for p: Vector3 in pts:
		edge.append(p + Vector3(0, 0.012, 0))
	strip(edge, 0.08, _m("e9e9e2", 0.7))
	# Barrier boards along the carriageway edge, where the rail would be.
	var board := _box(3.3, 0.55, 0.05)
	var board_m := _tex_m(Tex.barrier_stripes(), 0.15)
	var foot := _box(0.35, 0.12, 0.7)
	var foot_m := _m("2b2b2b", 0.9)
	var a0 := (s - 195.0) if off else (s - 10.0)
	var a1 := (s + 15.0) if off else (s + 135.0)
	var ss := a0
	while ss < a1:
		var g := _xf(ss, Config.RAIL_D, 0.0, PI / 2)
		b.add_mesh(board, g * Transform3D(Basis(), Vector3(0, 0.75, 0)), board_m)
		b.add_mesh(foot, g * Transform3D(Basis(), Vector3(-1.5, 0.06, 0)), foot_m)
		ss += 3.4
	# Cones in front of the barriers.
	var cone := _cyl(0.02, 0.2, 0.75, 8)
	var cone_m := _m("ff5a00", 0.6)
	var stripe := _cyl(0.1, 0.13, 0.12, 8)
	ss = a0 + 1.5
	while ss < a1:
		var p := t.point_at(ss, Config.RAIL_D - 0.6)
		b.add_instance(cone, cone_m, Transform3D(Basis(), p + Vector3(0, 0.37, 0)), null, false)
		b.add_instance(stripe, _m("f2f2f2", 0.5), Transform3D(Basis(), p + Vector3(0, 0.45, 0)), null, false)
		ss += 6.0
	# "Afgesloten" board on the slip road itself, and the arrow trailer at the start of the taper.
	var sign_s := s - 40.0 if off else s + 40.0
	var sg := _xf(sign_s, P + 3.0)
	b.add_mesh(_quad(2.6, 1.3), sg * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 1.6, 0)), _tex_m(Tex.closed_sign(), 0.2))
	for x in [-1.0, 1.0]:
		b.add_mesh(_cyl(0.05, 0.05, 1.6, 6), sg * Transform3D(Basis(), Vector3(x, 0.8, 0.03)), _m("8a8d90", 0.5, 0.6))
	if off:
		_arrow_trailer(t0 + 12.0, P + 2.2)


func _arrow_trailer(s: float, d: float) -> void:
	var g := _xf(s, d)
	b.add_mesh(_box(2.0, 0.9, 3.4), g * Transform3D(Basis(), Vector3(0, 0.75, 0)), _m("f7d117", 0.6))
	b.add_mesh(_box(2.4, 1.9, 0.12), g * Transform3D(Basis(), Vector3(0, 2.2, -1.2)), _m("111111", 0.6))
	for x in [-0.8, 0.8]:
		b.add_mesh(_cyl(0.3, 0.3, 0.25, 10), g * Transform3D(Basis(Vector3.FORWARD, PI / 2), Vector3(x, 0.3, 0.3)), _m("151515", 0.9))
	# The flashing arrow: lamps in a chevron pointing left (into the open lanes).
	var lamp_m := _lamp_m(Color(1.0, 0.75, 0.2))
	var dot := _cyl(0.07, 0.07, 0.04, 8)
	var pts := [Vector2(0.7, 0.0), Vector2(0.35, 0.0), Vector2(0.0, 0.0), Vector2(-0.35, 0.0), Vector2(-0.7, 0.0),
		Vector2(0.35, 0.35), Vector2(0.35, -0.35), Vector2(0.62, 0.55), Vector2(0.62, -0.55)]
	for p: Vector2 in pts:
		b.add_mesh(dot, g * Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(p.x, 2.2 + p.y, -1.27)), lamp_m, false)
	_blinkers.append([lamp_m, 1.0, randf()])


# ------------------------------------------------------------------ railways

## Level crossing (N35): rails across the road, flashing lights and booms on both sides,
## and a train that comes through now and then.
func _level_crossing(r: Dictionary) -> void:
	var s: float = r.s
	var fr := t.frame(s)
	var right := Vector3(fr.rx, 0, fr.rz)
	var fwd := Vector3(fr.fx, 0, fr.fz)
	var dir := (right * 0.96 + fwd * 0.28).normalized()
	var h0 := t.height_at(s)
	var centre := Vector3(fr.x, 0, fr.z)
	var ballast := []
	var rails := [[], []]
	for k in range(-400, 404, 8):
		var p := centre + dir * k
		var y := h0 * (1.0 - smoothstep(14.0, 70.0, absf(k)))
		ballast.append(Vector3(p.x, maxf(0.05, y - 0.04), p.z))
		for i in 2:
			var q := p + Vector3(dir.z, 0, -dir.x) * (0.72 if i == 0 else -0.72)
			rails[i].append(Vector3(q.x, maxf(0.05, y) + 0.1, q.z))
	strip(ballast, 2.2, _m("6b6258", 1.0))
	for rl in rails:
		strip(rl, 0.05, _m("9aa0a6", 0.35, 0.9))
	# Booms, posts and the red lights (andreaskruis) for both directions.
	var lamp_m := _lamp_m(Color(1, 0.1, 0.05))
	var booms := []
	var post_m := _m("f2f2f2", 0.6)
	var cross_m := _tex_m(Tex.barrier_stripes(), 0.1)
	for side in [1.0, -1.0]:
		var ps: float = s - side * 9.0
		var pd: float = side * (Config.PAVED + 0.8)
		var g := _xf(ps, pd)
		b.add_mesh(_cyl(0.08, 0.1, 3.4, 8), g * Transform3D(Basis(), Vector3(0, 1.7, 0)), post_m)
		var facing := Basis(Vector3.UP, PI if side > 0 else 0.0)
		for k in 2:
			var cx := Transform3D(facing * Basis(Vector3.FORWARD, (0.6 if k == 0 else -0.6)), Vector3(0, 3.0, 0))
			b.add_mesh(_box(1.4, 0.18, 0.04), g * cx, cross_m)
		for x in [-0.25, 0.25]:
			b.add_mesh(_cyl(0.12, 0.12, 0.06, 10), g * Transform3D(facing * Basis(Vector3.RIGHT, PI / 2), Vector3(x, 2.35, 0.0) + facing * Vector3(0, 0, 0.12)), lamp_m, false)
		# The boom pivots at the post and swings down across the lanes.
		var pivot := Node3D.new()
		pivot.transform = g * Transform3D(Basis(), Vector3(0, 1.1, 0))
		var arm := MeshInstance3D.new()
		var arm_len := Config.PAVED + 0.8 - (Config.LANE_EDGES[1] if side > 0 else -Config.LANE_EDGES[1])
		arm.mesh = _box(arm_len, 0.12, 0.08)
		arm.material_override = cross_m
		# Local +X is the road's left: the arm reaches inwards (towards the centre line).
		arm.position = Vector3(side * arm_len / 2.0, 0, 0)
		pivot.add_child(arm)
		root.add_child(pivot)
		booms.append({"node": pivot, "side": side, "base": pivot.transform})
	var train := _train()
	root.add_child(train)
	train.visible = false
	crossings.append({"s": s, "booms": booms, "lamps": lamp_m, "train": train, "dir": dir,
		"origin": Vector3(centre.x, maxf(0.05, h0) + 0.15, centre.z), "t": 0.0, "phase": "idle", "x": 0.0,
		"cooldown": 0.0, "sign": 1.0, "start_x": 260.0})


## A three-car regional train in Twente blue and yellow.
func _train() -> Node3D:
	var n := Node3D.new()
	var blue := _m("0f3f8c", 0.45, 0.3)
	var yellow := _m("ffc917", 0.5)
	var glass := _m("1b2530", 0.15, 0.4)
	var dark := _m("202020", 0.8)
	for i in TRAIN_CARS:
		var z := (i - (TRAIN_CARS - 1) / 2.0) * TRAIN_CAR_LEN
		var car := Node3D.new()
		car.position = Vector3(0, 0, z)
		n.add_child(car)
		var body := MeshInstance3D.new()
		body.mesh = _box(2.9, 3.0, TRAIN_CAR_LEN - 0.6)
		body.material_override = blue
		body.position.y = 2.3
		car.add_child(body)
		var band := MeshInstance3D.new()
		band.mesh = _box(2.92, 0.5, TRAIN_CAR_LEN - 0.6)
		band.material_override = yellow
		band.position.y = 1.2
		car.add_child(band)
		var win := MeshInstance3D.new()
		win.mesh = _box(2.94, 0.9, TRAIN_CAR_LEN - 3.0)
		win.material_override = glass
		win.position.y = 2.7
		car.add_child(win)
		var under := MeshInstance3D.new()
		under.mesh = _box(2.4, 0.7, TRAIN_CAR_LEN - 4.0)
		under.material_override = dark
		under.position.y = 0.45
		car.add_child(under)
		for e in [-1.0, 1.0]:
			if (i == 0 and e < 0) or (i == TRAIN_CARS - 1 and e > 0):
				var nose := MeshInstance3D.new()
				nose.mesh = _box(2.9, 2.6, 1.6)
				nose.material_override = yellow
				nose.position = Vector3(0, 2.1, e * (TRAIN_CAR_LEN / 2.0 + 0.4))
				car.add_child(nose)
				var front := MeshInstance3D.new()
				front.mesh = _box(2.4, 0.9, 0.1)
				front.material_override = glass
				front.position = Vector3(0, 2.9, e * (TRAIN_CAR_LEN / 2.0 + 1.22))
				car.add_child(front)
	return n


# ------------------------------------------------------------------ points of interest

## Village church: brick nave, tall tower with a slate spire, clock faces and a weathercock.
func _church(p: Dictionary) -> void:
	var g := _ground_xf(p.s, p.d)
	var brick := _m(["7a3b2a", "8a5a44", "6e4434"][int(p.s) % 3], 0.95)
	var roof := _m("2c2f33", 0.8)
	var spire_m := _m(["2c2f33", "4f7a68"][int(p.s / 7) % 2], 0.6, 0.3)
	b.add_mesh(_box(11, 9, 24), g * Transform3D(Basis(), Vector3(0, 4.5, -14)), brick)
	var nave_roof := PrismMesh.new()
	nave_roof.size = Vector3(12, 6, 24.5)
	b.add_mesh(nave_roof, g * Transform3D(Basis(), Vector3(0, 12, -14)), roof)
	b.add_mesh(_box(6, 26, 6), g * Transform3D(Basis(), Vector3(0, 13, 0)), brick)
	b.add_mesh(_cyl(0.0, 4.4, 18, 8), g * Transform3D(Basis(Vector3.UP, PI / 8), Vector3(0, 35, 0)), spire_m)
	b.add_mesh(_cyl(0.05, 0.05, 3, 4), g * Transform3D(Basis(), Vector3(0, 45.5, 0)), _m("c9a227", 0.3, 0.9))
	var clock := _cyl(1.1, 1.1, 0.1, 16)
	for k in 4:
		var a := k * PI / 2
		b.add_mesh(clock, g * Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, PI / 2), Vector3(sin(a) * 3.05, 21, cos(a) * 3.05)), _m("e8e2cf", 0.5))
	# Louvred belfry openings.
	for k in 4:
		var a := k * PI / 2
		b.add_mesh(_box(1.4, 2.6, 0.2), g * Transform3D(Basis(Vector3.UP, a), Vector3(sin(a) * 3.0, 24.5, cos(a) * 3.0)), _m("1d1d1d", 0.9))


## Dutch smock/tower mill on a gallery, sails turning slowly.
func _windmill(p: Dictionary) -> void:
	var g := _ground_xf(p.s, p.d)
	var body_m := _m(["3b3a36", "6b4a35", "50463b"][int(p.s) % 3], 0.95)
	b.add_mesh(_cyl(2.6, 4.4, 16, 8), g * Transform3D(Basis(), Vector3(0, 8, 0)), body_m)
	b.add_mesh(_cyl(5.6, 5.6, 0.3, 16), g * Transform3D(Basis(), Vector3(0, 6.5, 0)), _m("4a3a2a", 0.9))
	b.add_mesh(_box(9, 7, 7), g * Transform3D(Basis(), Vector3(9, 3.5, 2)), _m("7a3b2a", 0.95))
	var cap := SphereMesh.new()
	cap.radius = 3.0
	cap.height = 4.0
	cap.radial_segments = 10
	cap.rings = 4
	b.add_mesh(cap, g * Transform3D(Basis(), Vector3(0, 16.5, 0)), _m("2c2a26", 0.9))
	# Sails: a hub facing the road with four lattice blades.
	var hub := Node3D.new()
	hub.transform = g * Transform3D(Basis(), Vector3(0, 16.5, 3.2))
	var blade_m := _m("d8d0bd", 0.9)
	var spar_m := _m("3a2e24", 0.9)
	for k in 4:
		var arm := Node3D.new()
		arm.rotation.z = k * PI / 2
		hub.add_child(arm)
		var spar := MeshInstance3D.new()
		spar.mesh = _box(0.35, 12, 0.3)
		spar.material_override = spar_m
		spar.position = Vector3(0, 6, 0)
		arm.add_child(spar)
		var sail := MeshInstance3D.new()
		sail.mesh = _box(2.0, 9.5, 0.08)
		sail.material_override = blade_m
		sail.position = Vector3(1.15, 7, 0.1)
		arm.add_child(sail)
	root.add_child(hub)
	_spinners.append([hub, Vector3.FORWARD, 0.6 + randf() * 0.3])


func _water_tower(p: Dictionary) -> void:
	var g := _ground_xf(p.s, p.d)
	var c := _m("b9b2a6", 0.9)
	b.add_mesh(_cyl(3.0, 3.6, 30, 12), g * Transform3D(Basis(), Vector3(0, 15, 0)), c)
	b.add_mesh(_cyl(7.5, 4.0, 6, 16), g * Transform3D(Basis(), Vector3(0, 32, 0)), c)
	b.add_mesh(_cyl(7.5, 7.5, 5, 16), g * Transform3D(Basis(), Vector3(0, 37.5, 0)), _m("8f8b84", 0.9))
	b.add_mesh(_cyl(1.0, 7.8, 2.5, 16), g * Transform3D(Basis(), Vector3(0, 41.2, 0)), _m("4a4d52", 0.7, 0.3))


const FUEL_COLOURS := {
	"Shall": ["ffd200", "d71920"], "BV": ["0b8a3c", "ffe600"], "Esse": ["1f3f9a", "ffffff"],
	"TotaalEnergie": ["e3002b", "ffffff"], "Tanq": ["111111", "6cd400"], "Tanga": ["1e8c3a", "ffffff"],
	"Texako": ["e00000", "ffffff"], "Avio": ["c8102e", "ffffff"], "Golf": ["f47920", "0a2a6b"],
	"Argus": ["d71920", "ffffff"], "Vuurzone": ["111111", "ff6a00"], "K8": ["1a3c8c", "ffd200"],
}


## Petrol station by the road: canopy over the pumps, a shop and a tall price pylon.
func _petrol_station(p: Dictionary) -> void:
	var g := _ground_xf(p.s, p.d)
	var brand: String = p.name if FUEL_COLOURS.has(p.name) else "Shall"
	var cols: Array = FUEL_COLOURS[brand]
	var bg := Color(cols[0])
	var fg := Color(cols[1])
	var h0 := t.height_at(p.s)
	var y := h0 - 0.05
	b.add_mesh(_box(26, 0.2, 18), g * Transform3D(Basis(), Vector3(0, y - 0.1, -4)), _m("4a4b4e", 0.9))
	b.add_mesh(_box(16, 0.9, 10), g * Transform3D(Basis(), Vector3(0, y + 5.6, -2)), _m("f2f2f2", 0.5))
	b.add_mesh(_box(16.1, 0.4, 10.1), g * Transform3D(Basis(), Vector3(0, y + 5.4, -2)), TrackBuilder.mat(bg, 0.5))
	for x in [-6.0, 6.0]:
		for z in [-5.5, 1.5]:
			b.add_mesh(_box(0.4, 5.2, 0.4), g * Transform3D(Basis(), Vector3(x, y + 2.6, z)), _m("d9d9d9", 0.5, 0.4))
	for x in [-3.0, 3.0]:
		b.add_mesh(_box(0.8, 1.7, 0.5), g * Transform3D(Basis(), Vector3(x, y + 0.85, -2)), TrackBuilder.mat(bg, 0.5))
	b.add_mesh(_box(12, 4.0, 7), g * Transform3D(Basis(), Vector3(0, y + 2.0, -13)), _m("e6e2da", 0.8))
	b.add_mesh(_box(11.8, 2.0, 0.1), g * Transform3D(Basis(), Vector3(0, y + 2.0, -9.45)), _m("26323b", 0.15, 0.3))
	# Pylon with the brand and fuel prices, facing the traffic.
	var py := g * Transform3D(Basis(), Vector3(9, 0, 6))
	b.add_mesh(_box(0.5, 9, 0.5), py * Transform3D(Basis(), Vector3(0, y + 4.5, 0)), _m("d9d9d9", 0.5, 0.4))
	var board := _tex_m(Tex.brand(brand, bg, fg), 0.6)
	b.add_mesh(_box(3.2, 1.6, 0.4), py * Transform3D(Basis(), Vector3(0, y + 8.2, 0)), TrackBuilder.mat(bg, 0.5))
	for k in [-1.0, 1.0]:
		b.add_mesh(_quad(3.1, 1.55), py * Transform3D(Basis(Vector3.UP, (PI / 2) * (1 - k)), Vector3(0, y + 8.2, k * 0.21)), board, false)
	var prices := _tex_m(Tex.text("1,99  E10", Color("111111"), Color("ffd400"), 512, 128, 76), 0.8)
	b.add_mesh(_quad(3.0, 0.75), py * Transform3D(Basis(), Vector3(0, y + 6.8, 0.26)), prices, false)


## Snack bar: a tall pole sign seen from far away, and the restaurant.
func _snack_bar(p: Dictionary) -> void:
	var g := _ground_xf(p.s, p.d)
	var name: String = p.name
	var bg := Color("d71920") if name != "Burger Koning" else Color("f5a623")
	var board := _tex_m(Tex.brand(name, bg, Color("ffd200")), 0.9)
	var py := g * Transform3D(Basis(), Vector3(6, 0, 8))
	b.add_mesh(_cyl(0.35, 0.45, 20, 10), py * Transform3D(Basis(), Vector3(0, 10, 0)), _m("bfbfbf", 0.4, 0.6))
	b.add_mesh(_box(6.2, 3.2, 0.5), py * Transform3D(Basis(), Vector3(0, 20.5, 0)), TrackBuilder.mat(bg, 0.5))
	for k in [-1.0, 1.0]:
		b.add_mesh(_quad(6.0, 3.0), py * Transform3D(Basis(Vector3.UP, (PI / 2) * (1 - k)), Vector3(0, 20.5, k * 0.26)), board, false)
	b.add_mesh(_box(16, 4.5, 12), g * Transform3D(Basis(), Vector3(0, 2.25, -8)), _m("8a5a44", 0.9))
	b.add_mesh(_box(16.4, 0.8, 12.4), g * Transform3D(Basis(), Vector3(0, 4.8, -8)), TrackBuilder.mat(bg, 0.6))
	b.add_mesh(_box(14, 1.8, 0.1), g * Transform3D(Basis(), Vector3(0, 2.0, -1.95)), _m("26323b", 0.15, 0.3))


## Radio mast: red and white sections with blinking red aircraft lights.
func _mast(p: Dictionary) -> void:
	var g := _ground_xf(p.s, p.d)
	var red := _m("c4161c", 0.6)
	var white := _m("f2f2f2", 0.6)
	var sections := 10
	for i in sections:
		var r0 := 2.2 - i * 0.18
		b.add_mesh(_cyl(r0 - 0.18, r0, 14, 6), g * Transform3D(Basis(), Vector3(0, 7 + i * 14, 0)), red if i % 2 == 0 else white)
	var beacon := _lamp_m(Color(1, 0.05, 0.05))
	for h in [50.0, 100.0, 141.0]:
		b.add_mesh(SphereMesh.new(), g * Transform3D(Basis().scaled(Vector3(0.7, 0.7, 0.7)), Vector3(0, h, 0)), beacon, false)
	_blinkers.append([beacon, 1.5, randf()])


func _chimney(p: Dictionary) -> void:
	var g := _ground_xf(p.s, p.d)
	b.add_mesh(_cyl(1.4, 2.6, 46, 12), g * Transform3D(Basis(), Vector3(0, 23, 0)), _m("7a3b2a", 0.95))
	b.add_mesh(_cyl(1.6, 1.6, 1.5, 12), g * Transform3D(Basis(), Vector3(0, 45.5, 0)), _m("2b2b2b", 0.9))
	b.add_mesh(_box(28, 10, 18), g * Transform3D(Basis(), Vector3(-14, 5, -6)), _m("8a6a54", 0.95))


## Theme park on the horizon: a big wheel, a looping coaster and colourful roofs.
func _theme_park(p: Dictionary) -> void:
	var g := _ground_xf(p.s, p.d)
	var steel := _m("e8e8ec", 0.4, 0.6)
	# Big wheel.
	var wheel := Node3D.new()
	wheel.transform = g * Transform3D(Basis(), Vector3(-30, 32, 0))
	var rim := TorusMesh.new()
	rim.inner_radius = 27.0
	rim.outer_radius = 28.0
	rim.rings = 32
	rim.ring_segments = 6
	var rim_mi := MeshInstance3D.new()
	rim_mi.mesh = rim
	rim_mi.material_override = steel
	rim_mi.rotation.x = PI / 2
	wheel.add_child(rim_mi)
	var gondola_cols := ["e4002b", "ffd400", "1d4fd8", "2bb24c", "ff7a00", "b03a7a"]
	for k in 16:
		var a := k * TAU / 16
		var spoke := MeshInstance3D.new()
		spoke.mesh = _box(0.3, 27.5, 0.3)
		spoke.material_override = steel
		spoke.rotation.z = a
		spoke.position = Vector3(-sin(a) * 13.75, cos(a) * 13.75, 0)
		wheel.add_child(spoke)
		var gon := MeshInstance3D.new()
		gon.mesh = _box(2.2, 2.0, 2.2)
		gon.material_override = _m(gondola_cols[k % gondola_cols.size()], 0.6)
		gon.position = Vector3(-sin(a) * 28.5, cos(a) * 28.5, 0)
		wheel.add_child(gon)
	root.add_child(wheel)
	_spinners.append([wheel, Vector3.FORWARD, 0.12])
	for side in [-1.0, 1.0]:
		b.add_mesh(_box(1.2, 34, 1.2), g * Transform3D(Basis(Vector3.FORWARD, side * 0.28), Vector3(-30 + side * 4.6, 16, 0)), steel)
	# Looping coaster: a loop and a lift hill.
	var loop := TorusMesh.new()
	loop.inner_radius = 13.0
	loop.outer_radius = 14.2
	loop.rings = 32
	loop.ring_segments = 6
	var red := _m("d71920", 0.5, 0.3)
	b.add_mesh(loop, g * Transform3D(Basis(Vector3.UP, 0.4) * Basis(Vector3.RIGHT, PI / 2), Vector3(40, 15, -20)), red)
	b.add_mesh(_box(70, 1.0, 1.6), g * Transform3D(Basis(Vector3.FORWARD, 0.55), Vector3(70, 20, -20)), red)
	for k in 6:
		b.add_mesh(_box(0.6, 6 + k * 6.5, 0.6), g * Transform3D(Basis(), Vector3(45 + k * 9.5, (6 + k * 6.5) / 2.0, -20)), steel)
	# Big-top tents.
	for k in 5:
		var tent := _cyl(0.0, 7.0, 7.0, 10)
		b.add_mesh(tent, g * Transform3D(Basis(), Vector3(-80 + k * 22, 7, -40 - (k % 2) * 14)), _m(gondola_cols[k], 0.7))
		b.add_mesh(_cyl(7.0, 7.0, 4.0, 10), g * Transform3D(Basis(), Vector3(-80 + k * 22, 2, -40 - (k % 2) * 14)), _m("f2f2f2", 0.8))
	# Its name on a big board towards the road.
	var board := _tex_m(Tex.banner(String(p.name).to_upper()), 0.6)
	b.add_mesh(_quad(46, 7.2), g * Transform3D(Basis(), Vector3(0, 9, 30)), board)
	for x in [-20.0, 20.0]:
		b.add_mesh(_box(0.6, 12, 0.6), g * Transform3D(Basis(), Vector3(x, 6, 29.7)), _m("444444", 0.6, 0.4))


# ------------------------------------------------------------------ runtime

## Light cycle for our direction: green, amber, red (the side roads get the rest).
const GREEN := 11.0
const AMBER := 3.0
const RED := 9.0


static func _main_state(tt: float) -> String:
	var c := fmod(tt, GREEN + AMBER + RED)
	return "green" if c < GREEN else ("amber" if c < GREEN + AMBER else "red")


func light_state(i: int) -> String:
	return lights[i].state


## Stop line of the next red/amber light for our direction between s and s + reach (INF if none).
func red_ahead(s: float, reach: float) -> float:
	for l in lights:
		if l.stop > s and l.stop < s + reach and l.state != "green":
			return l.stop
	return INF


## A level crossing that's closed (booms coming down or a train on it) between s and s + reach:
## where to stop (INF if open).
func crossing_closed(s: float, reach: float) -> float:
	for c in crossings:
		var stop: float = c.s - 12.0
		if stop > s and stop < s + reach and (c.phase == "train" or (c.phase == "warn" and c.t > 1.5)):
			return stop
	return INF


func update(dt: float, player_s: float, player_speed := 40.0) -> void:
	_time += dt
	for l in lights:
		l.t += dt
		var st := _main_state(l.t)
		if st == l.state:
			continue
		l.state = st
		var main: Array = l.main
		var cross: Array = l.cross
		var on: int = {"red": 0, "amber": 1, "green": 2}[st]
		for k in 3:
			(main[k] as StandardMaterial3D).emission_energy_multiplier = 5.0 if k == on else 0.0
		# Cross traffic: green while we have red (minus a clearance second), red otherwise.
		var c_on := 2 if st == "red" else 0
		for k in 3:
			(cross[k] as StandardMaterial3D).emission_energy_multiplier = 5.0 if k == c_on else 0.0
	for sp in _spinners:
		(sp[0] as Node3D).rotate_object_local(sp[1], sp[2] * dt)
	for bl in _blinkers:
		var on := fmod(_time / bl[1] + bl[2], 1.0) < 0.5
		(bl[0] as StandardMaterial3D).emission_energy_multiplier = 6.0 if on else 0.0
	for c in crossings:
		_update_crossing(c, dt, player_s, player_speed)


## Level crossing: when the player gets close (and not too often), the lights flash, the booms come
## down and a train rolls through.
func _update_crossing(c: Dictionary, dt: float, player_s: float, player_speed: float) -> void:
	c.cooldown = maxf(0.0, c.cooldown - dt)
	var ahead: float = c.s - player_s
	match c.phase:
		"idle":
			if ahead > 450 and ahead < 900 and c.cooldown <= 0:
				c.phase = "warn"
				c.t = 0.0
				c.sign = 1.0 if randf() < 0.5 else -1.0
				# Time it so the train reaches the road when the player is ~150 m short of it: plenty of
				# warning (lights, booms), but you'll have to brake.
				var eta := (ahead - 150.0) / maxf(25.0, player_speed)
				c.start_x = clampf(TRAIN_SPEED * (eta - 4.0), 60.0, 420.0)
		"warn", "train", "clear":
			c.t += dt
	var down := 0.0
	var flashing: bool = c.phase != "idle"
	if c.phase == "warn":
		down = clampf((c.t - 1.5) / 3.0, 0.0, 1.0)
		if c.t > 4.0:
			c.phase = "train"
			c.t = 0.0
			c.x = -c.sign * c.start_x
			(c.train as Node3D).visible = true
	elif c.phase == "train":
		down = 1.0
		c.x += c.sign * TRAIN_SPEED * dt
		if c.x * c.sign > TRAIN_CARS * TRAIN_CAR_LEN + 60.0:
			c.phase = "clear"
			c.t = 0.0
			(c.train as Node3D).visible = false
	elif c.phase == "clear":
		down = clampf(1.0 - c.t / 3.0, 0.0, 1.0)
		if c.t > 3.0:
			c.phase = "idle"
			c.cooldown = 25.0
			flashing = false
	for bm in c.booms:
		# Up is 82° (pointing at the sky), down is level across the lanes.
		var base: Transform3D = bm.base
		(bm.node as Node3D).transform = base * Transform3D(Basis(Vector3.FORWARD, -bm.side * deg_to_rad(82.0) * (1.0 - down)), Vector3.ZERO)
	var lamp: StandardMaterial3D = c.lamps
	lamp.emission_energy_multiplier = (6.0 if fmod(_time, 1.0) < 0.5 else 0.0) if flashing else 0.0
	var train: Node3D = c.train
	if train.visible:
		var dir: Vector3 = c.dir
		train.transform = Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), c.origin + dir * c.x)


## The train as a box for the collision check: {centre, dir, half_len, half_w, vel} (empty when away).
func train_box() -> Array:
	var out := []
	for c in crossings:
		if c.phase != "train":
			continue
		var dir: Vector3 = c.dir
		out.append({"centre": c.origin + dir * c.x, "dir": dir, "half_len": TRAIN_CARS * TRAIN_CAR_LEN / 2.0 + 1.0,
			"half_w": 1.6, "vel": dir * c.sign * TRAIN_SPEED})
	return out
