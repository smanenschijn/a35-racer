class_name TrackBuilder
extends RefCounted
## Builds the A35 environment: carriageways, rails, verges, embankments, bridges, overpasses,
## sign gantries, lamps, trees, farms and city blocks (port of src/track/TrackBuilder.ts).
## Everything static is merged into one mesh per (1 km cell, material), so whatever is out of view
## or past the far plane is skipped and the draw calls stay low on a phone.

const CELL := 1000.0
# Median between the carriageways.
const OPP_IN := -8.5 # inner edge of the opposite carriageway surface
const OPP_OUT := -20.5

var root := Node3D.new()
var track: Track
## Canal water planes, used to sail the barge: {s, holder, width}.
var canals: Array = []
var _spans: Array = []
var _buckets := {}
var _multi := {}
var _mat_ids := {}
var _fr := Track.Frame.new()


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
		_spans.append({"c": c, "half": maxf(24.0, (b.s1 - b.s0) / 2.0 + 4.0), "canal": b.canal})

	# --- Materials ---
	var road := mat(Color.WHITE, 0.82, 0.05, Tex.road())
	var grass := mat(Color.WHITE, 1.0, 0.0, Tex.grass())
	var concrete := mat(Color.WHITE, 0.9, 0.0, Tex.concrete())
	var metal := mat(Color("b8bcc0"), 0.35, 0.85)
	metal.cull_mode = BaseMaterial3D.CULL_DISABLED
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
		ribbon({"s0": d[0], "s1": d[1], "dL": -6.0, "dR": 6.0, "yL": h, "yR": h}, road)
		# u runs 1→0 so the markings mirror for traffic in the other direction.
		ribbon({"s0": d[0], "s1": d[1], "dL": OPP_OUT, "dR": OPP_IN, "yL": h, "yR": h, "uL": 1.0, "uR": 0.0}, road)
	for r in singles:
		ribbon({"s0": r.s0, "s1": r.s1, "dL": -6.0, "dR": 6.0, "yL": h, "yR": h}, road_single)

	# --- Median and verges ---
	var verge := func(s: float) -> float: return t.height_at(s) - 0.06
	var zero := func(_s: float) -> float: return 0.0
	ribbon({"dL": 6.0, "dR": 9.5, "yL": verge, "yR": verge, "vScale": 8.0, "uR": 0.4, "step": 4.0}, grass)
	for d in duals:
		ribbon({"s0": d[0], "s1": d[1], "dL": -8.5, "dR": -6.0, "yL": verge, "yR": verge, "vScale": 8.0, "uR": 0.3, "step": 4.0}, grass)
		ribbon({"s0": d[0], "s1": d[1], "dL": -24.0, "dR": OPP_OUT, "yL": verge, "yR": verge, "vScale": 8.0, "uR": 0.4, "step": 4.0}, grass)
	for r in singles:
		ribbon({"s0": r.s0, "s1": r.s1, "dL": -9.5, "dR": -6.0, "yL": verge, "yR": verge, "vScale": 8.0, "uR": 0.4, "step": 4.0}, grass)

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
		ribbon({"s0": seg[0], "s1": seg[1], "dL": 9.5, "dR": func(s: float) -> float: return 12.0 + t.height_at(s) * 1.8,
			"yL": verge, "yR": zero, "vScale": 8.0, "uR": 1.0, "step": 4.0}, grass)
		for ab in clip.call(seg[0], seg[1], duals):
			ribbon({"s0": ab[0], "s1": ab[1], "dL": func(s: float) -> float: return -26.5 - t.height_at(s) * 1.8, "dR": -24.0,
				"yL": zero, "yR": verge, "vScale": 8.0, "uR": 1.0, "step": 4.0}, grass)
		for ab in clip.call(seg[0], seg[1], single_runs):
			ribbon({"s0": ab[0], "s1": ab[1], "dL": func(s: float) -> float: return -12.0 - t.height_at(s) * 1.8, "dR": -9.5,
				"yL": zero, "yR": verge, "vScale": 8.0, "uR": 1.0, "step": 4.0}, grass)

	# --- Guard rails (vangrail) ---
	var rail0 := func(s: float) -> float: return t.height_at(s) + 0.42
	var rail1 := func(s: float) -> float: return t.height_at(s) + 0.78
	for d in [5.6, -5.6]:
		ribbon({"dL": d, "dR": d, "yL": rail0, "yR": rail1}, metal, true)
	for dd in duals:
		for d in [-9.0, -20.0]:
			ribbon({"s0": dd[0], "s1": dd[1], "dL": d, "dR": d, "yL": rail0, "yR": rail1}, metal, true)
	var post := BoxMesh.new()
	post.size = Vector3(0.12, 0.8, 0.12)
	_posts([5.6, -5.6], 4.0, post, metal, 0.4, func(_s): return true)
	_posts([-9.0, -20.0], 4.0, post, metal, 0.4, func(s): return not t.is_single(s))

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
		_noise_barrier(st.startS + 200, st.startS + 800, 11)
		_noise_barrier(st.finishS - 800, st.finishS - 150, 11)
		var left := func(s: float) -> float: return -12.0 if t.is_single(s) else -27.0
		_noise_barrier(st.startS + 300, st.startS + 700, left.call(st.startS + 500))
		_noise_barrier(st.finishS - 650, st.finishS - 150, left.call(st.finishS - 400))
	for tu in f.tunnels:
		_tunnel(tu.s0, tu.s1, concrete, grass)
	for lm in f.landmarks:
		if lm.id == "heuvelrug":
			_hills(lm.s, lm.d)
	_start_finish()
	_ground()
	for sp in _spans:
		_underpass(sp.c, sp.half, sp.canal)
	_trees()
	_farms()
	_city_blocks()
	_flush()
	return root


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
	ribbon({"s0": s0, "s1": s1, "dL": -24.0, "dR": 9.5, "yL": under, "yR": under}, m)
	ribbon({"s0": s0, "s1": s1, "dL": 9.5, "dR": 9.5, "yL": under, "yR": top}, m)
	ribbon({"s0": s0, "s1": s1, "dL": -24.0, "dR": -24.0, "yL": under, "yR": top}, m)
	# Abutments at both ends.
	for s in [c - half, c + half]:
		var hh := t.height_at(s)
		add_mesh(_box(38, hh, 3), _place_xf(s, -7.25, -hh / 2), concrete)
	# Middle piers
	for d in [3.0, -7.25, -17.0]:
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
	var g := Transform3D(Basis(Vector3.UP, fr.heading), Vector3(fr.x + fr.rx * -7.25, base, fr.z + fr.rz * -7.25))
	var deck_len := 64.0
	add_mesh(_box(deck_len, 1.3, 12), g * Transform3D(Basis(), Vector3(0, clearance + 0.65, 0)), concrete)
	add_mesh(_box(deck_len, 0.06, 10), g * Transform3D(Basis(), Vector3(0, clearance + 1.33, 0)), mat(Color("333438"), 0.85))
	for side in [-1, 1]:
		add_mesh(_box(deck_len, 0.9, 0.15), g * Transform3D(Basis(), Vector3(0, clearance + 1.8, side * 5.6)), metal)
	# Piers: right verge, median, left verge (local x = -d because right = -X when yaw = heading).
	for d in [10.5, -7.25, -25.0]:
		for zz in [-3.5, 3.5]:
			add_mesh(_box(1, clearance, 1), g * Transform3D(Basis(), Vector3(-(d + 7.25), clearance / 2, zz)), concrete)
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
	for d in [7.2, -7.0]:
		add_mesh(_box(0.35, height + 1.2, 0.35), g * Transform3D(Basis(), Vector3(-d, (height + 1.2) / 2, 0)), metal)
	add_mesh(_box(15, 0.9, 0.6), g * Transform3D(Basis(), Vector3(-0.1, height + 0.6, 0)), metal)
	# Two signs: through-route on the left lane, exit on the right.
	for sg in [[[text[0]], -2.75], [[text[1]], 2.0]]:
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
		add_instance(pole, metal, Transform3D(b, t.point_at(s, -7.25, 5.5)))
		add_instance(arm, metal, Transform3D(b, t.point_at(s, -7.25, 10.9)))
		add_instance(head, head_mat, Transform3D(b, t.point_at(s, -5.0, 10.8)), null, false)
		add_instance(head, head_mat, Transform3D(b, t.point_at(s, -9.5, 10.8)), null, false)


func _hectometer_posts() -> void:
	var t := track
	var m := mat(Color("1f7a3a"), 0.6)
	var b := _box(0.14, 0.9, 0.14)
	for i in int(t.length / 100):
		add_instance(b, m, _place_xf(i * 100, 6.6, 0.45), null, false)


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
		for d in [6.6, -6.4]:
			add_mesh(_box(0.5, 7.5, 0.5), g * Transform3D(Basis(), Vector3(-d, 3.75, 0)), post_mat)
		var cloth := mat(Color.WHITE, 0.6, 0.0, Tex.banner(text))
		cloth.emission_enabled = true
		cloth.emission = Color(0.25, 0.25, 0.25)
		cloth.emission_texture = cloth.albedo_texture
		cloth.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
		var q := QuadMesh.new()
		q.size = Vector2(13.5, 2.1)
		add_mesh(q, g * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 6.6, 0)), cloth)
	var line := func(s: float) -> void:
		var q := QuadMesh.new()
		q.size = Vector2(11, 1.4)
		add_mesh(q, _place_xf(s, 0, 0.02) * Transform3D(Basis(Vector3.RIGHT, -PI / 2), Vector3.ZERO), checker, false)
	# Place-name signs: leaving a town at the start, entering the next before the finish.
	var place := func(s: float, place_name: String, sub: String, ended: bool) -> void:
		var g := _place_xf(s, 7.6)
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
	var outer := [-22.0, 7.0] if dual else [-7.0, 7.0]
	var walls := outer.duplicate()
	if dual:
		walls.append(-7.3)
	for d in walls:
		ribbon({"s0": s0, "s1": s1, "dL": d, "dR": d, "yL": func(s): return t.height_at(s) - 0.2, "yR": roof_y, "step": 4.0}, wall)
	# Concrete kerbs over the grass verges inside the tube.
	var kerb := concrete.duplicate() as StandardMaterial3D
	kerb.albedo_color = Color("8f8b84")
	var kerb_y := func(s: float) -> float: return t.height_at(s) - 0.03
	ribbon({"s0": s0, "s1": s1, "dL": 6.0, "dR": outer[1], "yL": kerb_y, "yR": kerb_y, "vScale": 8.0, "step": 4.0}, kerb)
	ribbon({"s0": s0, "s1": s1, "dL": -7.3 if dual else outer[0], "dR": -6.0, "yL": kerb_y, "yR": kerb_y, "vScale": 8.0, "step": 4.0}, kerb)
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
		for d in [-2.5, 2.5]:
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
func _underpass(c: float, half: float, canal: bool) -> void:
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


func _trees() -> void:
	var t := track
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.18
	trunk.bottom_radius = 0.28
	trunk.height = 3
	trunk.radial_segments = 5
	trunk.rings = 1
	var trunk_mat := mat(Color("4a3626"), 1.0)
	var crown := SphereMesh.new()
	crown.radius = 2.4
	crown.height = 6.0 # 1.25× taller than wide
	crown.radial_segments = 7
	crown.rings = 4
	var crown_mat := mat(Color.WHITE, 0.95)
	crown_mat.vertex_color_use_as_albedo = true
	# Clumps of trees ("houtwallen") with gaps for fields.
	var s := 0.0
	while s < t.length:
		for side in [1, -1]:
			if _blocked(s, side):
				continue
			var density := 0.5 + 0.5 * sin(s / 70 + side * 2.1) * sin(s / 23 + side)
			if randf() > density * 0.55:
				continue
			var left_near := -16.0 if t.is_single(s) else -30.0
			var near := 16 + t.height_at(s) * 1.8 if side > 0 else left_near - t.height_at(s) * 1.8
			var d: float = near + side * pow(randf(), 1.6) * 70
			var p := t.point_at(s + randf() * 4, d)
			var sc := 0.8 + randf() * 0.9
			var b := Basis(Vector3.UP, randf() * PI).scaled(Vector3(sc, sc, sc))
			add_instance(trunk, trunk_mat, Transform3D(b, Vector3(p.x, 1.5 * sc, p.z)))
			add_instance(crown, crown_mat, Transform3D(b, Vector3(p.x, 4.6 * sc, p.z)),
				Color.from_hsv(0.22 + randf() * 0.08, 0.6 + randf() * 0.2, 0.3 + randf() * 0.15))
		s += 4


## Apartment and office blocks where the road passes the towns.
func _city_blocks() -> void:
	var t := track
	var f := t.features
	var zones := []
	for st in f.stages:
		zones.append([maxf(0, st.startS - 300), st.startS + 900])
		zones.append([st.finishS - 1300, st.finishS + 250])
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
		for tries in 110 * 8:
			if placed >= 110:
				break
			var z: Array = zones[randi() % zones.size()]
			var s: float = z[0] + randf() * (z[1] - z[0])
			var side := 1 if randf() < 0.5 else -1
			if _blocked(s, side, 60):
				continue
			var d := 75 + randf() * 260 if side > 0 else -85 - randf() * 260
			var p := t.point_at(s, d)
			p.y = 0
			var fr := t.frame(s)
			var b := Basis(Vector3.UP, fr.heading + (0.0 if randf() < 0.5 else PI / 2))
			var hh := 9 + pow(randf(), 2) * 38
			add_instance(unit, m, Transform3D(b.scaled(Vector3(14 + randf() * 22, hh, 12 + randf() * 14)), p))
			placed += 1


func _farms() -> void:
	var t := track
	var walls := _box(10, 4, 18)
	var wall_mat := mat(Color("8e4a32"), 0.9)
	var roof := PrismMesh.new()
	roof.size = Vector3(12.4, 4.3, 18.6)
	var roof_mat := mat(Color("2f2a28"), 0.8)
	var placed := 0
	for tries in 60 * 4:
		if placed >= 60:
			break
		var s := 100 + randf() * (t.length - 200)
		var side := 1 if randf() < 0.5 else -1
		if _blocked(s, side, 80):
			continue
		placed += 1
		var d := 90 + randf() * 180 if side > 0 else -110 - randf() * 180
		var p := t.point_at(s, d)
		var b := Basis(Vector3.UP, randf() * PI)
		add_instance(walls, wall_mat, Transform3D(b, Vector3(p.x, 2, p.z)))
		add_instance(roof, roof_mat, Transform3D(b, Vector3(p.x, 4 + 2.15, p.z)))
