class_name TrackBuilder
extends RefCounted
## Builds the A35 environment: carriageways, rails, verges, embankments, bridges, overpasses,
## sign gantries, lamps, trees, farms and city blocks (port of src/track/TrackBuilder.ts).
## Everything static is merged into one mesh per (1 km cell, material), so whatever is out of view
## or past the far plane is skipped and the draw calls stay low on a phone.

const CELL := 1000.0
# Cross-section shorthands (see Config).
const PAVED := Config.PAVED
const OPP_IN := Config.OPP_IN
const OPP_OUT := Config.OPP_OUT
const VERGE := Config.VERGE_OUT
const LEFT_DUAL := Config.LEFT_EDGE_DUAL
const LEFT_SINGLE := Config.LEFT_EDGE_SINGLE
const MEDIAN := Config.MEDIAN_C

var root := Node3D.new()
var track: Track
## Canal water planes, used to sail the barge: {s, holder, width}.
var canals: Array = []
var _spans: Array = []
var _buckets := {}
var _multi := {}
var _mat_ids := {}
var _fr := Track.Frame.new()
var grass_mat: Material
## Junctions, slip roads, railways and points of interest (built from the route's OSM extras).
var scenery: Scenery


class Bucket:
	var mat: Material
	var origin := Vector3.ZERO
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	var colored := false
	var cast := false


func _init(t: Track) -> void:
	track = t


# ------------------------------------------------------------------ materials

static func mat(color: Color, rough := 0.9, metal := 0.0, tex: Texture2D = null) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if tex != null:
		m.albedo_texture = tex
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


static func glow_mat(color: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var m := mat(color, 0.5)
	m.emission_enabled = true
	m.emission = emission
	m.emission_energy_multiplier = energy
	return m


# ------------------------------------------------------------------ batching

func _cell_key(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


func _bucket(key: Vector2i, m: Material, cast: bool, colored := false) -> Bucket:
	if not _mat_ids.has(m):
		_mat_ids[m] = _mat_ids.size()
	var k := "%d|%d|%d|%d|%d" % [key.x, key.y, _mat_ids[m], int(cast), int(colored)]
	var b: Bucket = _buckets.get(k)
	if b == null:
		b = Bucket.new()
		b.mat = m
		b.cast = cast
		b.colored = colored
		b.origin = Vector3((key.x + 0.5) * CELL, 0, (key.y + 0.5) * CELL)
		_buckets[k] = b
	return b


## Merge a mesh (all surfaces get `m`) with a world transform into the cell it stands in.
func add_mesh(mesh: Mesh, xf: Transform3D, m: Material, cast := true) -> void:
	var b := _bucket(_cell_key(xf.origin), m, cast)
	var nb := xf.basis.inverse().transposed()
	var flip := xf.basis.determinant() < 0
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var uvs = arr[Mesh.ARRAY_TEX_UV]
		var ids = arr[Mesh.ARRAY_INDEX]
		var base := b.v.size()
		for i in verts.size():
			b.v.append(xf * verts[i] - b.origin)
			b.n.append((nb * norms[i]).normalized())
			b.uv.append(uvs[i] if uvs != null else Vector2.ZERO)
			if b.colored:
				b.col.append(Color.WHITE)
		if ids == null:
			ids = PackedInt32Array(range(verts.size()))
		for t in range(0, ids.size(), 3):
			if flip:
				b.idx.append_array([base + ids[t], base + ids[t + 2], base + ids[t + 1]])
			else:
				b.idx.append_array([base + ids[t], base + ids[t + 1], base + ids[t + 2]])


## Instances of one mesh, split per cell into MultiMeshes.
func add_instance(mesh: Mesh, m: Material, xf: Transform3D, color = null, cast := true) -> void:
	var key := _cell_key(xf.origin)
	var k := "%s|%d|%d" % [mesh.get_instance_id(), key.x, key.y]
	var e: Dictionary = _multi.get(k, {})
	if e.is_empty():
		e = {"mesh": mesh, "mat": m, "xfs": [], "cols": [], "cast": cast,
			"origin": Vector3((key.x + 0.5) * CELL, 0, (key.y + 0.5) * CELL)}
		_multi[k] = e
	e.xfs.append(xf)
	e.cols.append(color)


func _flush() -> void:
	for b: Bucket in _buckets.values():
		if b.idx.is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = b.v
		arr[Mesh.ARRAY_NORMAL] = b.n
		arr[Mesh.ARRAY_TEX_UV] = b.uv
		if b.colored:
			arr[Mesh.ARRAY_COLOR] = b.col
		arr[Mesh.ARRAY_INDEX] = b.idx
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		am.surface_set_material(0, b.mat)
		var mi := MeshInstance3D.new()
		mi.mesh = am
		mi.position = b.origin
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if b.cast else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	_buckets.clear()
	for e: Dictionary in _multi.values():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var colored: bool = e.cols[0] != null
		mm.use_colors = colored
		mm.mesh = e.mesh
		mm.instance_count = e.xfs.size()
		var o: Vector3 = e.origin
		for i in e.xfs.size():
			var xf: Transform3D = e.xfs[i]
			mm.set_instance_transform(i, Transform3D(xf.basis, xf.origin - o))
			if colored:
				mm.set_instance_color(i, e.cols[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if e.mat != null:
			mmi.material_override = e.mat
		mmi.position = o
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if e.cast else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
	_multi.clear()


# ------------------------------------------------------------------ ribbons

## A strip along the road between lateral offsets dL..dR (numbers or Callables of s),
## heights yL/yR (Callables of s). u runs uL→uR across, v = s / v_scale.
func ribbon(o: Dictionary, m: Material, cast := false) -> void:
	var t := track
	var s0: float = o.get("s0", 0.0)
	var s1: float = o.get("s1", t.length)
	var step: float = o.get("step", 2.0)
	var dl = o.dL
	var dr = o.dR
	var yl: Callable = o.yL
	var yr: Callable = o.yR
	var ul: float = o.get("uL", 0.0)
	var ur: float = o.get("uR", 1.0)
	var v_scale: float = o.get("vScale", 12.0)
	var rows := maxi(2, ceili((s1 - s0) / step) + 1)
	var cur: Bucket = null
	var prev := {}
	for r in rows:
		var s := minf(s1, s0 + r * step)
		var fr := t.frame(s, _fr)
		var d_l: float = dl.call(s) if dl is Callable else dl
		var d_r: float = dr.call(s) if dr is Callable else dr
		var pl := Vector3(fr.x + fr.rx * d_l, yl.call(s), fr.z + fr.rz * d_l)
		var pr := Vector3(fr.x + fr.rx * d_r, yr.call(s), fr.z + fr.rz * d_r)
		var along := Vector3(fr.fx, fr.slope, fr.fz)
		var across := pr - pl
		if Vector2(across.x, across.z).length() < 0.01:
			across = Vector3(0, 1.0 if across.y >= 0 else -1.0, 0)
		var nrm := across.cross(along).normalized()
		var row := {"l": pl, "r": pr, "n": nrm, "v": s / v_scale}
		var b := _bucket(_cell_key((pl + pr) * 0.5), m, cast)
		if cur == null:
			cur = b
			_row(cur, row, ul, ur)
		elif b == cur:
			_row(cur, row, ul, ur)
			_quad(cur)
		else:
			cur = b
			_row(cur, prev, ul, ur)
			_row(cur, row, ul, ur)
			_quad(cur)
		prev = row


func _row(b: Bucket, row: Dictionary, ul: float, ur: float) -> void:
	b.v.append(row.l - b.origin)
	b.v.append(row.r - b.origin)
	b.n.append(row.n)
	b.n.append(row.n)
	b.uv.append(Vector2(ul, row.v))
	b.uv.append(Vector2(ur, row.v))
	if b.colored:
		b.col.append(Color.WHITE)
		b.col.append(Color.WHITE)


## Two triangles between the last two rows of a bucket (clockwise = front face in Godot).
func _quad(b: Bucket) -> void:
	var bb := b.v.size() - 2
	var a := bb - 2
	b.idx.append_array([a, bb, a + 1, a + 1, bb, bb + 1])


# ------------------------------------------------------------------ build

func build() -> Node3D:
	var t := track
	var h := func(s: float) -> float: return t.height_at(s)
	var f := t.features
	# Open spans under each bridge (no embankment there: water or a road passes underneath).
	for b in f.bridges:
		var c: float = (b.s0 + b.s1) / 2.0
		_spans.append({"c": c, "half": maxf(24.0, (b.s1 - b.s0) / 2.0 + 4.0), "canal": b.canal, "rail": b.get("rail", false)})

	# --- Materials ---
	var road := mat(Color.WHITE, 0.82, 0.05, Tex.road())
	var grass := mat(Color.WHITE, 1.0, 0.0, Tex.grass())
	grass_mat = grass
	var concrete := mat(Color.WHITE, 0.9, 0.0, Tex.concrete())
	var metal := mat(Color("b8bcc0"), 0.35, 0.85)
	metal.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rail_m := mat(Color.WHITE, 0.45, 0.7, Tex.rail())
	rail_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var road_single := mat(Color.WHITE, 0.82, 0.05, Tex.single_road())

	# Cross-section runs: dual (motorway-style, separate carriageways) and single
	# (one carriageway, oncoming traffic in the left lane, no median).
	var singles: Array = f.single
	var duals := []
	var at := 0.0
	for r in singles:
		if r.s0 > at:
			duals.append([at, r.s0])
		at = r.s1
	if at < t.length:
		duals.append([at, t.length])

	# --- Road surfaces ---
	for d in duals:
		ribbon({"s0": d[0], "s1": d[1], "dL": -PAVED, "dR": PAVED, "yL": h, "yR": h}, road)
		# u runs 1→0 so the markings mirror for traffic in the other direction.
		ribbon({"s0": d[0], "s1": d[1], "dL": OPP_OUT, "dR": OPP_IN, "yL": h, "yR": h, "uL": 1.0, "uR": 0.0}, road)
	for r in singles:
		ribbon({"s0": r.s0, "s1": r.s1, "dL": -PAVED, "dR": PAVED, "yL": h, "yR": h}, road_single)

	# --- Median and verges ---
	var verge := func(s: float) -> float: return t.height_at(s) - 0.06
	var zero := func(_s: float) -> float: return 0.0
	ribbon({"dL": PAVED, "dR": VERGE, "yL": verge, "yR": verge, "vScale": 8.0, "uR": 0.4, "step": 4.0}, grass)
	for d in duals:
		ribbon({"s0": d[0], "s1": d[1], "dL": OPP_IN, "dR": -PAVED, "yL": verge, "yR": verge, "vScale": 8.0, "uR": 0.3, "step": 4.0}, grass)
		ribbon({"s0": d[0], "s1": d[1], "dL": LEFT_DUAL, "dR": OPP_OUT, "yL": verge, "yR": verge, "vScale": 8.0, "uR": 0.4, "step": 4.0}, grass)
	for r in singles:
		ribbon({"s0": r.s0, "s1": r.s1, "dL": LEFT_SINGLE, "dR": -PAVED, "yL": verge, "yR": verge, "vScale": 8.0, "uR": 0.4, "step": 4.0}, grass)

	# --- Embankments down to the fields (with a gap for the canal) ---
	var outside := []
	var from := 0.0
	var sorted := _spans.duplicate()
	sorted.sort_custom(func(a, b): return a.c < b.c)
	for sp in sorted:
		outside.append([from, sp.c - sp.half])
		from = sp.c + sp.half
	outside.append([from, t.length])
	var clip := func(a: float, b: float, runs: Array) -> Array:
		var out := []
		for run in runs:
			var c0 := maxf(a, run[0])
			var c1 := minf(b, run[1])
			if c1 - c0 > 2:
				out.append([c0, c1])
		return out
	var single_runs := []
	for r in singles:
		single_runs.append([r.s0, r.s1])
	for seg in outside:
		ribbon({"s0": seg[0], "s1": seg[1], "dL": VERGE, "dR": func(s: float) -> float: return VERGE + 2.5 + t.height_at(s) * 1.8,
			"yL": verge, "yR": zero, "vScale": 8.0, "uR": 1.0, "step": 4.0}, grass)
		for ab in clip.call(seg[0], seg[1], duals):
			ribbon({"s0": ab[0], "s1": ab[1], "dL": func(s: float) -> float: return LEFT_DUAL - 2.5 - t.height_at(s) * 1.8, "dR": LEFT_DUAL,
				"yL": zero, "yR": verge, "vScale": 8.0, "uR": 1.0, "step": 4.0}, grass)
		for ab in clip.call(seg[0], seg[1], single_runs):
			ribbon({"s0": ab[0], "s1": ab[1], "dL": func(s: float) -> float: return LEFT_SINGLE - 2.5 - t.height_at(s) * 1.8, "dR": LEFT_SINGLE,
				"yL": zero, "yR": verge, "vScale": 8.0, "uR": 1.0, "step": 4.0}, grass)

	# --- Guard rails (vangrail) ---
	var rail0 := func(s: float) -> float: return t.height_at(s) + 0.42
	var rail1 := func(s: float) -> float: return t.height_at(s) + 0.78
	# Gaps where a road joins at grade (junctions, slip roads) or the rail is replaced by a barrier.
	var rd := Config.RAIL_D
	for run in _rail_runs(1):
		ribbon({"s0": run[0], "s1": run[1], "dL": rd, "dR": rd, "yL": rail0, "yR": rail1, "vScale": 4.0}, rail_m, true)
	for run in _rail_runs(-1):
		ribbon({"s0": run[0], "s1": run[1], "dL": -rd, "dR": -rd, "yL": rail0, "yR": rail1, "vScale": 4.0}, rail_m, true)
	var left_runs := _rail_runs(-1)
	for dd in duals:
		for run in left_runs:
			var a := maxf(dd[0], run[0])
			var c := minf(dd[1], run[1])
			if c - a < 2:
				continue
			for d in Config.OPP_RAILS:
				ribbon({"s0": a, "s1": c, "dL": d, "dR": d, "yL": rail0, "yR": rail1, "vScale": 4.0}, rail_m, true)
	var post := BoxMesh.new()
	post.size = Vector3(0.12, 0.8, 0.12)
	_posts([rd], 4.0, post, metal, 0.4, func(s): return t.rail_drawn(s, 1))
	_posts([-rd], 4.0, post, metal, 0.4, func(s): return t.rail_drawn(s, -1))
	_posts(Config.OPP_RAILS, 4.0, post, metal, 0.4, func(s): return not t.is_single(s) and t.rail_drawn(s, -1))

	for sp in _spans:
		_bridge(sp.c, sp.half, concrete)
	for s in f.viaducts:
		_overpass(s, concrete, grass, metal)
	for g in f.gantries:
		_gantry(g.s, g.text, g.route, metal)
	_lamps(metal)
	_hectometer_posts()
	# Noise barriers where the road passes the towns.
	for st in f.stages:
		_noise_barrier(st.startS + 200, st.startS + 800, VERGE - 0.5)
		_noise_barrier(st.finishS - 800, st.finishS - 150, VERGE - 0.5)
		var left := func(s: float) -> float: return LEFT_SINGLE - 0.5 if t.is_single(s) else LEFT_DUAL - 0.5
		_noise_barrier(st.startS + 300, st.startS + 700, left.call(st.startS + 500))
		_noise_barrier(st.finishS - 650, st.finishS - 150, left.call(st.finishS - 400))
	for tu in f.tunnels:
		_tunnel(tu.s0, tu.s1, concrete, grass)
	for lm in f.landmarks:
		if lm.id == "heuvelrug":
			_hills(lm.s, lm.d)
	_start_finish()
	scenery = Scenery.new(self)
	scenery.build()
	track.scenery = scenery
	_ground()
	for sp in _spans:
		_underpass(sp.c, sp.half, sp.canal, sp.rail)
	_ditches()
	_trees()
	_farms()
	_farmland()
	_city_blocks()
	_flush()
	return root


## [s0, s1] stretches with a rail on this side (+1 right, -1 left): everything but the junction gaps.
func _rail_runs(side: float) -> Array:
	var out := []
	var s0 := -1.0
	var s := 0.0
	while s <= track.length:
		var gap := not track.rail_drawn(s, side)
		if not gap and s0 < 0:
			s0 = s
		elif gap and s0 >= 0:
			out.append([s0, s])
			s0 = -1.0
		s += 1.0
	if s0 >= 0:
		out.append([s0, track.length])
	return out


func _place_xf(s: float, d: float, up := 0.0, yaw := 0.0) -> Transform3D:
	var fr := track.frame(s, _fr)
	return Transform3D(Basis(Vector3.UP, fr.heading + yaw), Vector3(fr.x + fr.rx * d, fr.y + up, fr.z + fr.rz * d))


func _box(w: float, h: float, d: float, sub_w := 0) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(w, h, d)
	b.subdivide_width = sub_w
	return b


func _posts(ds: Array, spacing: float, mesh: Mesh, m: Material, up: float, keep: Callable) -> void:
	var s := 0.0
	while s < track.length:
		if keep.call(s):
			for d in ds:
				add_instance(mesh, m, _place_xf(s, d, up))
		s += spacing


## Is s in an open span, or near a viaduct or a landmark on that side? (keeps trees/farms clear)
func _blocked(s: float, d: float, margin := 45.0) -> bool:
	for sp in _spans:
		if absf(s - sp.c) < sp.half + margin:
			return true
	for v in track.features.viaducts:
		if absf(s - v) < 24:
			return true
	if track.in_tunnel(s, 30):
		return true
	for j in track.features.junctions:
		if absf(s - j.s) < 30 and ((d > 0 and j.right) or (d < 0 and j.left) or j.kind == "cycle"):
			return true
	if d > 0:
		for r in track.features.ramps:
			if s > r.s - 220 and s < r.s + 300:
				return true
	for p in track.features.pois:
		if absf(s - p.s) < 90 and signf(p.d) == signf(d):
			return true
	for r in track.features.railways:
		if absf(s - r.s) < 40:
			return true
	for lm in track.features.landmarks:
		if absf(s - lm.s) < (700.0 if lm.id == "heuvelrug" else 190.0) and signf(lm.d) == signf(d):
			return true
	return false


func _bridge(c: float, half: float, concrete: StandardMaterial3D) -> void:
	var t := track
	var under := func(s: float) -> float: return t.height_at(s) - 1.6
	var top := func(s: float) -> float: return t.height_at(s) - 0.06
	var s0 := c - half - 2
	var s1 := c + half + 2
	var m := concrete.duplicate() as StandardMaterial3D
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	ribbon({"s0": s0, "s1": s1, "dL": LEFT_DUAL, "dR": VERGE, "yL": under, "yR": under}, m)
	ribbon({"s0": s0, "s1": s1, "dL": VERGE, "dR": VERGE, "yL": under, "yR": top}, m)
	ribbon({"s0": s0, "s1": s1, "dL": LEFT_DUAL, "dR": LEFT_DUAL, "yL": under, "yR": top}, m)
	# Abutments at both ends.
	var mid := (LEFT_DUAL + VERGE) / 2.0
	for s in [c - half, c + half]:
		var hh := t.height_at(s)
		add_mesh(_box(VERGE - LEFT_DUAL, hh, 3), _place_xf(s, mid, -hh / 2), concrete)
	# Middle piers
	for d in [4.0, MEDIAN, -21.0]:
		var hh := t.height_at(c)
		var pier := CylinderMesh.new()
		pier.top_radius = 0.8
		pier.bottom_radius = 0.8
		pier.height = hh
		pier.radial_segments = 12
		add_mesh(pier, _place_xf(c, d, -hh / 2 - 1), concrete)


func _overpass(s: float, concrete: Material, grass: Material, metal: Material) -> void:
	var fr := track.frame(s)
	var base := fr.y
	var clearance := 6.4
	# Centre on the median, rotated so local X runs across the road.
	var g := Transform3D(Basis(Vector3.UP, fr.heading), Vector3(fr.x + fr.rx * MEDIAN, base, fr.z + fr.rz * MEDIAN))
	var deck_len := 76.0
	add_mesh(_box(deck_len, 1.3, 12), g * Transform3D(Basis(), Vector3(0, clearance + 0.65, 0)), concrete)
	add_mesh(_box(deck_len, 0.06, 10), g * Transform3D(Basis(), Vector3(0, clearance + 1.33, 0)), mat(Color("333438"), 0.85))
	for side in [-1, 1]:
		add_mesh(_box(deck_len, 0.9, 0.15), g * Transform3D(Basis(), Vector3(0, clearance + 1.8, side * 5.6)), metal)
	# Piers: right verge, median, left verge (local x = -d because right = -X when yaw = heading).
	for d in [VERGE - 1.0, MEDIAN, LEFT_DUAL + 2.0]:
		for zz in [-3.5, 3.5]:
			add_mesh(_box(1, clearance, 1), g * Transform3D(Basis(), Vector3(-(d - MEDIAN), clearance / 2, zz)), concrete)
	# Earth ramps at both ends (wedges sloping down to the fields).
	for side in [-1, 1]:
		var ramp_len := 70.0
		var H := clearance + 1.4 + base
		var box := _box(ramp_len, H, 16, 4)
		var arr := box.get_mesh_arrays()
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for i in verts.size():
			var x := verts[i].x
			if verts[i].y > 0:
				var k: float = 1.0 - (side * x) / (ramp_len / 2) if side * x > 0 else 1.0 # slope away from the deck
				verts[i].y = -H / 2 + H * maxf(0.02, k)
		arr[Mesh.ARRAY_VERTEX] = verts
		var st := SurfaceTool.new()
		st.create_from_arrays(arr)
		st.generate_normals()
		var ramp := st.commit()
		add_mesh(ramp, g * Transform3D(Basis(), Vector3(side * (deck_len / 2 + ramp_len / 2), H / 2 - base, 0)), grass, false)


func _gantry(s: float, text: Array, route: String, metal: Material) -> void:
	var g := _place_xf(s, 0)
	var height := 7.0
	for d in [Config.RAIL_D + 0.8, -Config.RAIL_D - 0.6]:
		add_mesh(_box(0.35, height + 1.2, 0.35), g * Transform3D(Basis(), Vector3(-d, (height + 1.2) / 2, 0)), metal)
	add_mesh(_box(2 * Config.RAIL_D + 1.6, 0.9, 0.6), g * Transform3D(Basis(), Vector3(-0.1, height + 0.6, 0)), metal)
	# Two signs: through-route over the left lane, exit over the right.
	for sg in [[[text[0]], Config.LANE_CENTERS[0]], [[text[1]], Config.LANE_CENTERS[1] + 1.6]]:
		var m := mat(Color.WHITE, 0.4, 0.0, Tex.sign(sg[0], route))
		m.emission_enabled = true
		m.emission = Color("0a1a3a")
		m.emission_energy_multiplier = 0.4
		var q := QuadMesh.new()
		q.size = Vector2(5.2, 2.6)
		# Face oncoming traffic.
		add_mesh(q, g * Transform3D(Basis(Vector3.UP, PI), Vector3(-sg[1], height + 0.6, -0.35)), m)


func _lamps(metal: Material) -> void:
	var t := track
	var spacing := 55.0
	var n := int(t.length / spacing)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.1
	pole.bottom_radius = 0.14
	pole.height = 11
	pole.radial_segments = 6
	var arm := _box(5.5, 0.12, 0.12)
	var head := _box(0.9, 0.18, 0.4)
	var head_mat := glow_mat(Color("ffe2a8"), Color("ffb84d"), 3.0)
	for k in n:
		var s := k * spacing + 20
		# Median lamps only where there is a median (and not inside the tunnel).
		if t.is_single(s) or t.in_tunnel(s, 15):
			continue
		var fr := t.frame(s)
		var b := Basis(Vector3.UP, fr.heading)
		add_instance(pole, metal, Transform3D(b, t.point_at(s, MEDIAN, 5.5)))
		add_instance(arm, metal, Transform3D(b, t.point_at(s, MEDIAN, 10.9)))
		add_instance(head, head_mat, Transform3D(b, t.point_at(s, MEDIAN + 2.5, 10.8)), null, false)
		add_instance(head, head_mat, Transform3D(b, t.point_at(s, MEDIAN - 2.5, 10.8)), null, false)


func _hectometer_posts() -> void:
	var t := track
	var m := mat(Color("1f7a3a"), 0.6)
	var b := _box(0.14, 0.9, 0.14)
	for i in int(t.length / 100):
		add_instance(b, m, _place_xf(i * 100, PAVED + 0.6, 0.45), null, false)


func _noise_barrier(s0: float, s1: float, d: float) -> void:
	var t := track
	# Leave a gap in front of landmarks on this side: they should be seen from the road.
	for lm in t.features.landmarks:
		if lm.id == "heuvelrug" or signf(lm.d) != signf(d):
			continue
		var a: float = lm.s - 170
		var b: float = lm.s + 170
		if b <= s0 or a >= s1:
			continue
		if a - s0 > 40:
			_noise_barrier(s0, a, d)
		if s1 - b > 40:
			_noise_barrier(b, s1, d)
		return
	var wall := mat(Color("6b5a45"), 0.9)
	wall.cull_mode = BaseMaterial3D.CULL_DISABLED
	var glass := mat(Color(0x9f / 255.0, 0xc4 / 255.0, 0xd0 / 255.0, 0.35), 0.1, 0.2)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	ribbon({"s0": s0, "s1": s1, "dL": d, "dR": d, "yL": func(s): return t.height_at(s) - 0.1, "yR": func(s): return t.height_at(s) + 2.6, "step": 4.0}, wall, true)
	ribbon({"s0": s0, "s1": s1, "dL": d, "dR": d, "yL": func(s): return t.height_at(s) + 2.6, "yR": func(s): return t.height_at(s) + 4.2, "step": 4.0}, glass)


func _start_finish() -> void:
	var t := track
	var f := t.features
	var checker := mat(Color.WHITE, 0.7, 0.0, Tex.checker())
	var post_mat := mat(Color("222222"), 0.4, 0.6)
	var grey := mat(Color("888888"), 0.6)
	var red := mat(Color("c4161c"), 0.6)
	var gate := func(s: float, text: String) -> void:
		var g := _place_xf(s, 0)
		for d in [PAVED + 0.6, -PAVED - 0.4]:
			add_mesh(_box(0.5, 7.5, 0.5), g * Transform3D(Basis(), Vector3(-d, 3.75, 0)), post_mat)
		var cloth := mat(Color.WHITE, 0.6, 0.0, Tex.banner(text))
		cloth.emission_enabled = true
		cloth.emission = Color(0.25, 0.25, 0.25)
		cloth.emission_texture = cloth.albedo_texture
		cloth.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
		var q := QuadMesh.new()
		q.size = Vector2(2 * PAVED + 1.5, 2.4)
		add_mesh(q, g * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 6.6, 0)), cloth)
	var line := func(s: float) -> void:
		var q := QuadMesh.new()
		q.size = Vector2(2 * Config.ROAD_HALF_WIDTH, 1.4)
		add_mesh(q, _place_xf(s, 0, 0.02) * Transform3D(Basis(Vector3.RIGHT, -PI / 2), Vector3.ZERO), checker, false)
	# Place-name signs: leaving a town at the start, entering the next before the finish.
	var place := func(s: float, place_name: String, sub: String, ended: bool) -> void:
		var g := _place_xf(s, PAVED + 1.6)
		var board := QuadMesh.new()
		board.size = Vector2(2.6, 1.15)
		add_mesh(board, g * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 2.6, 0)), mat(Color.WHITE, 0.4, 0.0, Tex.place_sign(place_name, sub)))
		if ended:
			var stripe := QuadMesh.new()
			stripe.size = Vector2(2.9, 0.14)
			add_mesh(stripe, g * Transform3D(Basis.from_euler(Vector3(0, PI, 0.38)), Vector3(0, 2.6, -0.01)), red)
		for x in [-0.9, 0.9]:
			var p := CylinderMesh.new()
			p.top_radius = 0.05
			p.bottom_radius = 0.05
			p.height = 2.2
			p.radial_segments = 8
			add_mesh(p, g * Transform3D(Basis(), Vector3(x, 1.1, 0.02)), grey)
	for st in f.stages:
		line.call(st.startS)
		line.call(st.finishS)
		gate.call(st.finishS, "FINISH  •  %s" % String(st.to).to_upper())
		for k in [0.27, 0.52, 0.77]:
			gate.call(roundf(st.startS + (st.finishS - st.startS) * k), "CHECKPOINT")
		place.call(st.startS + 30, st.from, "Etappe %d" % st.id, true)
		place.call(st.finishS - 160, st.to, "", false)


## Cut-and-cover tunnel (Nijverdal): walls, roof with grass on top, ceiling lights, portals.
func _tunnel(s0: float, s1: float, concrete: StandardMaterial3D, grass: Material) -> void:
	var t := track
	var roof_y := func(s: float) -> float: return t.height_at(s) + 6.4
	var wall := concrete.duplicate() as StandardMaterial3D
	wall.cull_mode = BaseMaterial3D.CULL_DISABLED
	wall.albedo_color = Color("b8b4ac")
	var dual := not t.is_single((s0 + s1) / 2)
	var outer := [OPP_OUT + 0.5, PAVED + 1.0] if dual else [-PAVED - 1.0, PAVED + 1.0]
	var walls := outer.duplicate()
	if dual:
		walls.append(MEDIAN)
	for d in walls:
		ribbon({"s0": s0, "s1": s1, "dL": d, "dR": d, "yL": func(s): return t.height_at(s) - 0.2, "yR": roof_y, "step": 4.0}, wall)
	# Concrete kerbs over the grass verges inside the tube.
	var kerb := concrete.duplicate() as StandardMaterial3D
	kerb.albedo_color = Color("8f8b84")
	var kerb_y := func(s: float) -> float: return t.height_at(s) - 0.03
	ribbon({"s0": s0, "s1": s1, "dL": PAVED, "dR": outer[1], "yL": kerb_y, "yR": kerb_y, "vScale": 8.0, "step": 4.0}, kerb)
	ribbon({"s0": s0, "s1": s1, "dL": MEDIAN if dual else outer[0], "dR": -PAVED, "yL": kerb_y, "yR": kerb_y, "vScale": 8.0, "step": 4.0}, kerb)
	if dual:
		ribbon({"s0": s0, "s1": s1, "dL": OPP_IN, "dR": MEDIAN, "yL": kerb_y, "yR": kerb_y, "vScale": 8.0, "step": 4.0}, kerb)
	ribbon({"s0": s0, "s1": s1, "dL": outer[0], "dR": outer[1], "yL": roof_y, "yR": roof_y, "step": 4.0}, wall, true)
	var cover_y := func(s: float) -> float: return t.height_at(s) + 7.1
	var zero := func(_s: float) -> float: return 0.0
	ribbon({"s0": s0 - 4, "s1": s1 + 4, "dL": outer[0] - 6, "dR": outer[1] + 6, "yL": cover_y, "yR": cover_y, "vScale": 8.0, "step": 4.0}, grass, true)
	# Earth slopes over the portal walls, so the tunnel reads as a park on top.
	for side in [outer[0] - 6, outer[1] + 6]:
		var out: float = side - 10 if side < 0 else side + 10
		if side < 0:
			ribbon({"s0": s0 - 4, "s1": s1 + 4, "dL": out, "dR": side, "yL": zero, "yR": cover_y, "vScale": 8.0, "step": 4.0}, grass)
		else:
			ribbon({"s0": s0 - 4, "s1": s1 + 4, "dL": side, "dR": out, "yL": cover_y, "yR": zero, "vScale": 8.0, "step": 4.0}, grass)
	# Ceiling light strips
	var light := _box(0.5, 0.08, 4)
	var light_mat := glow_mat(Color("fff1d0"), Color("ffe2a8"), 3.5)
	for i in int((s1 - s0) / 8):
		var s := s0 + 4 + i * 8
		var b := Basis(Vector3.UP, t.frame(s).heading)
		for d in [-3.4, 0.8, 5.0]:
			add_instance(light, light_mat, Transform3D(b, t.point_at(s, d, 6.3)), null, false)
	# Portal headers.
	for sy in [[s0, 0.0], [s1, PI]]:
		add_mesh(_box(outer[1] - outer[0] + 1, 1.6, 0.8), _place_xf(sy[0], (outer[0] + outer[1]) / 2, 7.0, sy[1]), wall)


## Sallandse Heuvelrug: soft heather-and-pine hills beside the road.
func _hills(s_centre: float, d_centre: float) -> void:
	var t := track
	var len_along := 1600.0
	var width := 520.0
	var seg_a := 64
	var seg_w := 26
	var heather := Color("6b4a6e")
	var green := Color("3f5f2a")
	var sand := Color("9c8a5c")
	var bumps := [
		{"x": -380.0, "z": 40.0, "r": 260.0, "h": 48.0}, {"x": 120.0, "z": 90.0, "r": 300.0, "h": 62.0},
		{"x": 520.0, "z": 10.0, "r": 220.0, "h": 38.0}, {"x": -40.0, "z": -60.0, "r": 180.0, "h": 22.0},
	]
	var side := signf(d_centre) if d_centre != 0 else 1.0
	var grid := []
	for j in seg_w + 1:
		var row := []
		for i in seg_a + 1:
			var lx := -len_along / 2 + len_along * i / seg_a # along the road
			var lz := -width / 2 + width * j / seg_w # away from the road (+ = further)
			var y := 0.0
			for b in bumps:
				y += b.h * exp(-((lx - b.x) ** 2 + (lz - b.z) ** 2) / (b.r * b.r))
			# Fade to flat at the edges so it meets the fields.
			var edge := minf(1.0, (len_along / 2 - absf(lx)) / 220) * minf(1.0, (width / 2 - absf(lz)) / 120)
			y *= maxf(0.0, edge)
			var s := s_centre + lx
			var d := d_centre + side * lz
			var fr := t.frame(clampf(s, 0, t.length))
			var c := green.lerp(heather, clampf((sin(lx / 90) + cos(lz / 70)) * 0.35 + y / 60.0, 0, 1))
			if y < 3:
				c = c.lerp(sand, 0.15)
			row.append([Vector3(fr.x + fr.rx * d, y, fr.z + fr.rz * d), c])
		grid.append(row)
	# Flat-shaded triangles with vertex colours.
	var m := mat(Color.WHITE, 1.0)
	m.vertex_color_use_as_albedo = true
	var key := _cell_key(grid[seg_w / 2][seg_a / 2][0])
	var b := _bucket(key, m, true, true)
	var tri := func(p0: Array, p1: Array, p2: Array) -> void:
		var n: Vector3 = (p2[0] - p0[0]).cross(p1[0] - p0[0]).normalized()
		if n.y < 0:
			n = -n
			var tmp := p1
			p1 = p2
			p2 = tmp
		var base := b.v.size()
		for p in [p0, p1, p2]:
			b.v.append(p[0] - b.origin)
			b.n.append(n)
			b.uv.append(Vector2.ZERO)
			b.col.append(p[1])
		b.idx.append_array([base, base + 1, base + 2])
	for j in seg_w:
		for i in seg_a:
			tri.call(grid[j][i], grid[j][i + 1], grid[j + 1][i])
			tri.call(grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i])
	# Pines on the slopes.
	var pine := CylinderMesh.new()
	pine.top_radius = 0.0
	pine.bottom_radius = 2.2
	pine.height = 9
	pine.radial_segments = 6
	pine.rings = 1
	var pine_mat := mat(Color("24401f"), 1.0)
	var placed := 0
	for i in 260 * 3:
		if placed >= 260:
			break
		var p: Vector3 = grid[randi() % (seg_w + 1)][randi() % (seg_a + 1)][0]
		if p.y < 6 or randf() < 0.3:
			continue
		add_instance(pine, pine_mat, Transform3D(Basis().scaled(Vector3(1, 0.8 + randf() * 0.6, 1)), p + Vector3(0, 4, 0)))
		placed += 1


func _ground() -> void:
	var t := track
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var s := 0.0
	while s <= t.length:
		var p := t.point_at(s, 0)
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
		s += 50
	var size := hi - lo
	var center := (lo + hi) / 2
	var extent := maxf(size.x, size.y) + 6000
	var m := mat(Color.WHITE, 1.0, 0.0, Tex.field())
	m.uv1_scale = Vector3(extent / 900, extent / 900, 1)
	var plane := PlaneMesh.new()
	plane.size = Vector2(extent, extent)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = m
	mi.position = Vector3(center.x, 0, center.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## What passes under a bridge: the Twentekanaal, or a local road.
func _underpass(c: float, half: float, canal: bool, rail := false) -> void:
	var fr := track.frame(c)
	var holder := Node3D.new()
	holder.position = Vector3(fr.x, 0, fr.z)
	# Long axis is local X; laid across the motorway with a slight skew.
	holder.rotation.y = fr.heading + 0.25
	if canal:
		var width := minf(34.0, half * 2 - 10)
		var water := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(3000, width)
		water.mesh = plane
		water.material_override = mat(Color("1d3f55"), 0.08, 0.6)
		water.position.y = 0.08
		holder.add_child(water)
		var bank_mat := mat(Color("7a776f"), 0.9)
		for side in [-1, 1]:
			var bank := MeshInstance3D.new()
			bank.mesh = _box(3000, 0.5, 1.2)
			bank.material_override = bank_mat
			bank.position = Vector3(0, 0.1, side * (width / 2 + 0.5))
			holder.add_child(bank)
		canals.append({"s": c, "holder": holder, "width": width})
	elif rail:
		# Railway underneath: ballast, two tracks and catenary masts.
		var bed := MeshInstance3D.new()
		var bp := PlaneMesh.new()
		bp.size = Vector2(1600, 9.0)
		bed.mesh = bp
		bed.material_override = mat(Color("6b6258"), 1.0)
		bed.position.y = 0.06
		holder.add_child(bed)
		var steel := mat(Color("9aa0a6"), 0.35, 0.9)
		for z in [-2.9, -1.5, 1.5, 2.9]:
			var r := MeshInstance3D.new()
			r.mesh = _box(1600, 0.16, 0.08)
			r.material_override = steel
			r.position = Vector3(0, 0.16, z)
			holder.add_child(r)
		for x in range(-780, 800, 60):
			var m := MeshInstance3D.new()
			m.mesh = _box(0.25, 7.0, 0.25)
			m.material_override = mat(Color("6f7378"), 0.5, 0.6)
			m.position = Vector3(x, 3.5, 5.2)
			holder.add_child(m)
			var arm := MeshInstance3D.new()
			arm.mesh = _box(0.12, 0.12, 6.0)
			arm.material_override = m.material_override
			arm.position = Vector3(x, 6.8, 2.4)
			holder.add_child(arm)
	else:
		var road := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(1600, 7.5)
		road.mesh = plane
		road.material_override = mat(Color("38393c"), 0.85)
		road.position.y = 0.06
		var line := MeshInstance3D.new()
		var lp := PlaneMesh.new()
		lp.size = Vector2(1600, 0.15)
		line.mesh = lp
		line.material_override = mat(Color("dddddd"), 0.8)
		line.position.y = 0.07
		holder.add_child(road)
		holder.add_child(line)
	root.add_child(holder)


## Ditches (sloten) along the foot of the embankments, broken where something crosses.
func _ditches() -> void:
	var t := track
	var water := mat(Color("23333a"), 0.06, 0.4)
	var y := func(_s: float) -> float: return 0.02
	var s0 := 0.0
	var s := 0.0
	var runs := []
	while s < t.length:
		var stop := _blocked(s, 1.0, 0.0) or s >= t.length - 4
		if stop and s - s0 > 30:
			runs.append([s0, s])
		if stop:
			s0 = s + 4
		s += 4.0
	for run in runs:
		var toe := func(ss: float) -> float: return VERGE + 3.5 + t.height_at(ss) * 1.8
		ribbon({"s0": run[0], "s1": run[1], "dL": toe, "dR": func(ss: float) -> float: return VERGE + 5.6 + t.height_at(ss) * 1.8,
			"yL": y, "yR": y, "step": 6.0}, water)
		var left := func(ss: float) -> float: return (LEFT_SINGLE if t.is_single(ss) else LEFT_DUAL) - 3.5 - t.height_at(ss) * 1.8
		ribbon({"s0": run[0], "s1": run[1], "dL": func(ss: float) -> float: return left.call(ss) - 2.1, "dR": left,
			"yL": y, "yR": y, "step": 6.0}, water)


## Which kind of tree grows here: pines and spruce on the Sallandse Heuvelrug, willows by the water,
## oak and birch in the wooded banks (houtwallen) everywhere else.
func _tree_kind(s: float) -> String:
	var r := randf()
	for lm in track.features.landmarks:
		if lm.id == "heuvelrug" and absf(s - lm.s) < 1100:
			return "den" if r < 0.6 else ("spar" if r < 0.75 else "berk")
	for w in track.features.waters:
		if absf(s - w.s) < 160:
			return "wilg" if r < 0.55 else "eik"
	if r < 0.52:
		return "eik"
	if r < 0.74:
		return "berk"
	if r < 0.82:
		return "populier"
	if r < 0.88:
		return "wilg"
	return "spar" if r < 0.94 else "den"


func _tree_at(kind: String, p: Vector3, scale := 1.0) -> void:
	var sc := scale * (0.75 + randf() * 0.5)
	var b := Basis(Vector3.UP, randf() * TAU).scaled(Vector3(sc, sc * (0.9 + randf() * 0.2), sc))
	var tint := Color(0.8 + randf() * 0.25, 0.82 + randf() * 0.2, 0.75 + randf() * 0.2)
	add_instance(Props.tree(kind, randi() % 3), Props.foliage_material(), Transform3D(b, Vector3(p.x, 0, p.z)), tint)


func _trees() -> void:
	var t := track
	# Wooded banks (houtwallen) in clumps with gaps for the fields.
	var s := 0.0
	while s < t.length:
		for side in [1, -1]:
			if _blocked(s, side):
				continue
			var density := 0.5 + 0.5 * sin(s / 70 + side * 2.1) * sin(s / 23 + side)
			if randf() > density * 0.62:
				continue
			var left_near := LEFT_SINGLE - 6.0 if t.is_single(s) else LEFT_DUAL - 6.0
			var near := VERGE + 7.0 + t.height_at(s) * 1.8 if side > 0 else left_near - t.height_at(s) * 1.8
			var d: float = near + side * pow(randf(), 1.6) * 80
			_tree_at(_tree_kind(s), t.point_at(s + randf() * 4, d))
		s += 4
	# Poplar windbreaks running away from the road now and then.
	s = 300.0
	while s < t.length - 300:
		var side := 1 if randf() < 0.5 else -1
		if not _blocked(s, side, 40) and t.features.landmarks.all(func(lm): return lm.id != "heuvelrug" or absf(s - lm.s) > 1100):
			var fr := t.frame(s)
			var base := t.point_at(s, side * (40.0 + randf() * 30))
			var dir := Vector3(fr.rx, 0, fr.rz) * side
			var along := Vector3(fr.fx, 0, fr.fz) * (randf() - 0.5) * 0.4
			for k in 10 + randi() % 8:
				_tree_at("populier", base + (dir + along).normalized() * k * 7.5, 1.1)
		s += 450 + randf() * 500
	# Avenue trees along the side roads at junctions.
	for j in t.features.junctions:
		if j.kind != "road":
			continue
		var fr := t.frame(j.s)
		var right := Vector3(fr.rx, 0, fr.rz)
		var fwd := Vector3(fr.fx, 0, fr.fz)
		for side in [1.0, -1.0]:
			if (side > 0 and not j.right) or (side < 0 and not j.left):
				continue
			var dir: Vector3 = (right * side * cos(j.skew) + fwd * sin(j.skew)).normalized()
			var across := Vector3(dir.z, 0, -dir.x)
			var start: float = Config.PAVED + 14.0 if side > 0 or t.is_single(j.s) else -Config.OPP_OUT + 10.0
			var base: Vector3 = Vector3(fr.x, 0, fr.z) + right * side * start
			for k in 14:
				for e in [-1.0, 1.0]:
					_tree_at("eik", base + dir * k * 11.0 + across * e * (j.width / 2.0 + 3.0), 1.05)


## Farmsteads: a Twentse farmhouse, a black barn, oaks around the yard and a row of wrapped bales.
func _farms() -> void:
	var t := track
	var placed := 0
	for tries in 110 * 4:
		if placed >= 110:
			break
		var s := 150 + randf() * (t.length - 300)
		var side := 1 if randf() < 0.5 else -1
		if _blocked(s, side, 80) or _in_town(s):
			continue
		placed += 1
		var d := 70 + randf() * 220 if side > 0 else -90 - randf() * 220
		var p := t.point_at(s, d)
		var fr := t.frame(s)
		# Mostly gable end to the road, like the old farms along the lanes.
		var yaw := fr.heading + (PI / 2 if side > 0 else -PI / 2) + (randf() - 0.5) * 0.5
		var b := Basis(Vector3.UP, yaw)
		var at := Vector3(p.x, 0, p.z)
		add_instance(Props.farmhouse(randf() < 0.3), null, Transform3D(b, at))
		var barn_at := at + b * Vector3(16 + randf() * 6, 0, -8 - randf() * 8)
		add_instance(Props.barn(), null, Transform3D(Basis(Vector3.UP, yaw + (PI / 2 if randf() < 0.5 else 0.0)), barn_at))
		# Yard trees.
		for k in 5 + randi() % 4:
			var a := randf() * TAU
			_tree_at("eik", at + Vector3(cos(a), 0, sin(a)) * (17 + randf() * 10), 1.15)
		# Bales along the yard.
		var bale_col := "f2f2f0" if randf() < 0.75 else ("1a1a1a" if randf() < 0.5 else "3f6a2e")
		var row := at + b * Vector3(-14, 0, -6)
		for k in 4 + randi() % 6:
			var bp := row + b * Vector3(0, 0, -k * 1.3)
			add_instance(Props.bale(bale_col), Props.foliage_material(), Transform3D(b, bp))
			if randf() < 0.4:
				add_instance(Props.bale(bale_col), Props.foliage_material(), Transform3D(b, bp + Vector3(0, 1.22, 0)))


## Cows in the meadows and maize fields along the road.
func _farmland() -> void:
	var t := track
	var cows := 0
	for tries in 90 * 4:
		if cows >= 90:
			break
		var s := 200 + randf() * (t.length - 400)
		var side := 1 if randf() < 0.5 else -1
		if _blocked(s, side, 60) or _in_town(s):
			continue
		cows += 1
		var centre := t.point_at(s, side * (35 + randf() * 90))
		var fr := t.frame(s)
		var variant := randi() % 3
		for k in 5 + randi() % 10:
			var off := Vector3((randf() - 0.5) * 50, 0, (randf() - 0.5) * 50)
			var yaw := fr.heading + randf() * TAU
			var sc := 0.95 + randf() * 0.1
			add_instance(Props.cow(variant if randf() < 0.8 else (randi() % 2)), Props.foliage_material(),
				Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc)), Vector3(centre.x + off.x, 0, centre.z + off.z)), null, false)
	# Maize: tall blocks of green, right up to the ditch now and then.
	var maize := mat(Color.WHITE, 0.95, 0.0, Tex.maize())
	maize.uv1_triplanar = true
	maize.uv1_world_triplanar = true
	maize.uv1_scale = Vector3(0.25, 0.25, 0.25)
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	var fields := 0
	for tries in 70 * 4:
		if fields >= 70:
			break
		var s := 200 + randf() * (t.length - 400)
		var side := 1 if randf() < 0.5 else -1
		if _blocked(s, side, 70) or _in_town(s):
			continue
		fields += 1
		var w := 30 + randf() * 50
		var l := 40 + randf() * 80
		var near := (VERGE + 9.0 + t.height_at(s) * 1.8) if side > 0 else ((LEFT_SINGLE if t.is_single(s) else LEFT_DUAL) - 9.0 - t.height_at(s) * 1.8)
		var p := t.point_at(s, near + side * (w / 2 + randf() * 40))
		var fr := t.frame(s)
		add_instance(unit, maize, Transform3D(Basis(Vector3.UP, fr.heading).scaled(Vector3(w, 2.4, l)), Vector3(p.x, 1.2, p.z)))


## Built-up areas near the start and finish of every stage.
func _in_town(s: float) -> bool:
	for st in track.features.stages:
		if (s > st.startS - 300 and s < st.startS + 900) or (s > st.finishS - 1300 and s < st.finishS + 250):
			return true
	return false


const COMPANIES := [["Tukker Transport", "1d4fd8"], ["Twentse Kabel", "c4161c"], ["Storq Hengelo", "0b6b2e"],
	["Ten Kaat Textiel", "6a2c8c"], ["Boekelo Bier", "c9a227"], ["Saksen Staal", "444b52"], ["Almelo Logistiek", "e36a00"],
	["Hengelose Koek", "a0522d"], ["Thuisbesteld.nl", "ff7a00"], ["Salland Zuivel", "2a7ab8"]]


## Towns: terraced streets and detached houses, apartment blocks closer in, and business-park halls along
## the motorway stretches.
func _city_blocks() -> void:
	var t := track
	var f := t.features
	var zones := []
	for st in f.stages:
		zones.append([maxf(0, st.startS - 300), st.startS + 900])
		zones.append([st.finishS - 1300, st.finishS + 250])
	var roofs := ["9a3b22", "3a3a3e", "7a2f1c"]
	for tries in 260 * 5:
		var z: Array = zones[randi() % zones.size()]
		var s: float = z[0] + randf() * (z[1] - z[0])
		var side := 1 if randf() < 0.5 else -1
		if _blocked(s, side, 50):
			continue
		var fr := t.frame(s)
		var d := (85 + randf() * 240) * side if side > 0 else -(100 + randf() * 240)
		var p := t.point_at(s, d)
		var at := Vector3(p.x, 0, p.z)
		var face := fr.heading + (PI / 2 if side > 0 else -PI / 2) # front towards the road
		var r := randf()
		if r < 0.45:
			# A street of terraced rows, fronts to the road, back to back further out.
			for k in 3:
				var off := Basis(Vector3.UP, face) * Vector3(0, 0, -k * 26.0)
				add_instance(Props.terrace(roofs[randi() % roofs.size()]), null,
					Transform3D(Basis(Vector3.UP, face + (PI if k % 2 == 1 else 0.0)), at + off))
		elif r < 0.75:
			for k in 3:
				var off := Basis(Vector3.UP, face) * Vector3((k - 1) * 18.0, 0, randf() * 6)
				add_instance(Props.villa(roofs[randi() % roofs.size()]), null, Transform3D(Basis(Vector3.UP, face + (randf() - 0.5) * 0.2), at + off))
				_tree_at("berk" if randf() < 0.5 else "eik", at + off + Basis(Vector3.UP, face) * Vector3(8, 0, 6))
		elif s > f.stages[min(2, f.stages.size() - 1)].startS:
			var c: Array = COMPANIES[randi() % COMPANIES.size()]
			add_instance(Props.hall(c[0], Color(c[1])), null, Transform3D(Basis(Vector3.UP, face), at))
	# A few apartment and office blocks closer to the centres.
	var walls := ["8c7c6c", "b9b2a6", "5e4a40"]
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var arr := box.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i].y += 0.5
	arr[Mesh.ARRAY_VERTEX] = verts
	var unit := ArrayMesh.new()
	unit.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	for ki in walls.size():
		var tex := Tex.facade(ki + 1, "#" + walls[ki])
		var m := mat(Color.WHITE, 0.85, 0.0, tex[0])
		m.emission_enabled = true
		m.emission = Color.WHITE
		m.emission_texture = tex[1]
		m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		m.emission_energy_multiplier = 1.4
		var placed := 0
		for tries in 40 * 8:
			if placed >= 40:
				break
			var z: Array = zones[randi() % zones.size()]
			var s: float = z[0] + randf() * (z[1] - z[0])
			var side := 1 if randf() < 0.5 else -1
			if _blocked(s, side, 60):
				continue
			var d := 180 + randf() * 260 if side > 0 else -200 - randf() * 260
			var p := t.point_at(s, d)
			p.y = 0
			var fr := t.frame(s)
			var b := Basis(Vector3.UP, fr.heading + (0.0 if randf() < 0.5 else PI / 2))
			var hh := 12 + pow(randf(), 2) * 34
			add_instance(unit, m, Transform3D(b.scaled(Vector3(16 + randf() * 20, hh, 12 + randf() * 12)), p))
			placed += 1
