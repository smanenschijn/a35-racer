class_name Props
## Procedural scenery models, built once and instanced all along the route: trees of the Twente and
## Salland landscape (oak, birch, poplar, Scots pine, spruce, pollard willow), Twentse farmhouses with a
## half-hipped roof, black barns, terraced and detached houses, business-park halls, and the farmland
## bits (Holstein cows, wrapped bales, maize). Trees carry their colours in the vertices (foliage shader);
## buildings have textured surfaces (brick, tiles, thatch, planks, cladding).

static var _cache := {}
static var _foliage: ShaderMaterial
static var _noise: FastNoiseLite


static func foliage_material() -> ShaderMaterial:
	if _foliage == null:
		_foliage = ShaderMaterial.new()
		_foliage.shader = load("res://shaders/foliage.gdshader")
	return _foliage


static func _n3(p: Vector3) -> float:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.frequency = 0.9
	return _noise.get_noise_3dv(p)


# ------------------------------------------------------------------ geometry helpers

## Unit icosphere, subdivided once (42 vertices, 80 triangles), as [verts, tris].
static func _icosphere(subdiv: int) -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v: Array = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for i in v.size():
		v[i] = (v[i] as Vector3).normalized()
	var f: Array = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
		[10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11],
		[6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for k in subdiv:
		var mids := {}
		var nf := []
		var mid := func(a: int, b: int) -> int:
			var key := Vector2i(mini(a, b), maxi(a, b))
			if mids.has(key):
				return mids[key]
			v.append(((v[a] as Vector3) + (v[b] as Vector3)).normalized())
			mids[key] = v.size() - 1
			return v.size() - 1
		for tri in f:
			var a: int = mid.call(tri[0], tri[1])
			var b: int = mid.call(tri[1], tri[2])
			var c: int = mid.call(tri[2], tri[0])
			nf.append_array([[tri[0], a, c], [tri[1], b, a], [tri[2], c, b], [a, b, c]])
		f = nf
	return [v, f]


## One leafy cluster: a lumpy sphere whose normals point away from the crown centre (soft, foliage-like
## shading), darker towards the inside and bottom of the crown.
static func _blob(st: SurfaceTool, c: Vector3, r: Vector3, crown: Vector3, crown_r: float, top: Color, bottom: Color, sway: float, seed_v: float) -> void:
	var ico := _icosphere(1)
	var verts: Array = ico[0]
	var pts := []
	for p: Vector3 in verts:
		var lump := 1.0 + 0.28 * _n3(p * 2.2 + Vector3(seed_v, seed_v * 1.7, -seed_v))
		pts.append(c + p * r * lump)
	for tri in ico[1]:
		for k in [0, 2, 1]:
			var p: Vector3 = pts[tri[k]]
			var out := (p - crown)
			var n := (out.normalized() * 0.75 + (verts[tri[k]] as Vector3) * 0.25).normalized()
			var hgt := clampf((p.y - (crown.y - crown_r)) / (2.0 * crown_r), 0.0, 1.0)
			var inner := clampf(out.length() / crown_r, 0.0, 1.0)
			var col := bottom.lerp(top, hgt) * (0.62 + 0.38 * inner)
			col.a = sway * clampf(p.y / (crown.y + crown_r), 0.2, 1.0)
			st.set_color(col)
			st.set_normal(n)
			st.add_vertex(p)


## Tapered cylinder from a to b (trunks and branches).
static func _limb(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float, col: Color, sides := 6, col_b := Color(-1, 0, 0)) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.FORWARD if absf(axis.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var up := side.cross(axis)
	var cb := col if col_b.r < 0 else col_b
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := side * cos(a0) + up * sin(a0)
		var d1 := side * cos(a1) + up * sin(a1)
		var quad := [[a + d0 * r0, d0, col], [b + d0 * r1, d0, cb], [b + d1 * r1, d1, cb], [a + d1 * r0, d1, col]]
		for k in [0, 1, 2, 0, 2, 3]:
			var c: Color = quad[k][2]
			c.a = 0.0
			st.set_color(c)
			st.set_normal(quad[k][1])
			st.add_vertex(quad[k][0])


static func _finish(st: SurfaceTool) -> ArrayMesh:
	st.index()
	return st.commit()


# ------------------------------------------------------------------ trees

const TREE_KINDS := ["eik", "berk", "populier", "den", "spar", "wilg"]


## A tree model (local origin at the foot of the trunk). Variant 0..2 changes the shape a little.
static func tree(kind: String, variant := 0) -> ArrayMesh:
	var key := "tree|%s|%d" % [kind, variant]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bark := Color("4a3a2c")
	match kind:
		"eik":
			# Oak: short, stout trunk, a broad irregular crown of many clusters.
			var crown := Vector3(0, 7.0, 0)
			_limb(st, Vector3.ZERO, Vector3(0, 4.2, 0), 0.42, 0.3, bark)
			for k in 4:
				var a := rng.randf() * TAU
				_limb(st, Vector3(0, 3.6, 0), crown + Vector3(cos(a) * 2.4, rng.randf_range(-0.5, 1.2), sin(a) * 2.4), 0.22, 0.08, bark)
			for k in 9:
				var a := rng.randf() * TAU
				var rr := rng.randf_range(0.5, 3.4)
				var c := crown + Vector3(cos(a) * rr, rng.randf_range(-1.2, 1.8), sin(a) * rr)
				_blob(st, c, Vector3.ONE * rng.randf_range(1.7, 2.5), crown, 4.6, Color("4a6624"), Color("1f3410"), 1.0, rng.randf() * 10)
		"berk":
			# Birch: slender white trunk with black marks, light airy crown.
			var crown := Vector3(0, 8.5, 0)
			for k in 7:
				var y0 := k * 1.3
				var col := Color("e8e6dd") if k % 3 != 1 else Color("2a2a28")
				_limb(st, Vector3(0, y0, 0), Vector3(0, y0 + 1.3, 0), 0.2 - k * 0.015, 0.2 - (k + 1) * 0.015, col)
			for k in 7:
				var a := rng.randf() * TAU
				var c := crown + Vector3(cos(a) * rng.randf_range(0.3, 1.7), rng.randf_range(-2.5, 2.6), sin(a) * rng.randf_range(0.3, 1.7))
				_blob(st, c, Vector3(1.3, 1.8, 1.3) * rng.randf_range(0.8, 1.15), crown, 3.6, Color("6f8a30"), Color("38541a"), 1.0, rng.randf() * 10)
		"populier":
			# Poplar: tall and columnar, in rows along farm lanes.
			var crown := Vector3(0, 12.0, 0)
			_limb(st, Vector3.ZERO, Vector3(0, 6, 0), 0.35, 0.22, Color("6b6658"))
			for k in 8:
				var c := Vector3(rng.randf_range(-0.5, 0.5), 5.5 + k * 1.7, rng.randf_range(-0.5, 0.5))
				var r := 1.9 * (1.0 - absf(k - 3.5) / 6.0)
				_blob(st, c, Vector3(r, 1.6, r), crown, 7.5, Color("587426"), Color("263f12"), 1.0, rng.randf() * 10)
		"den":
			# Scots pine (Sallandse Heuvelrug): tall bare red-brown trunk, flat dark clusters on top.
			var crown := Vector3(0, 12.5, 0)
			_limb(st, Vector3.ZERO, Vector3(0.3, 11.5, 0), 0.32, 0.16, Color("8a5236"), 6, Color("b86b3e"))
			for k in 5:
				var a := rng.randf() * TAU
				var c := crown + Vector3(cos(a) * rng.randf_range(0.5, 2.6), rng.randf_range(-1.2, 1.0), sin(a) * rng.randf_range(0.5, 2.6))
				_limb(st, Vector3(0.2, 10.5, 0), c, 0.1, 0.05, Color("7a4a32"))
				_blob(st, c, Vector3(1.9, 0.95, 1.9) * rng.randf_range(0.8, 1.2), crown, 3.4, Color("3f5a2c"), Color("1e3318"), 0.6, rng.randf() * 10)
		"spar":
			# Spruce: stacked dark cones.
			_limb(st, Vector3.ZERO, Vector3(0, 2.5, 0), 0.25, 0.2, bark)
			var tiers := 6
			for k in tiers:
				var y := 2.0 + k * 1.9
				var r := 3.0 * (1.0 - float(k) / tiers) + 0.5
				var col_top := Color("2f4a26")
				var col_bot := Color("16281a")
				var seg := 9
				for i in seg:
					var a0 := TAU * i / seg
					var a1 := TAU * (i + 1) / seg
					var p0 := Vector3(cos(a0) * r, y, sin(a0) * r)
					var p1 := Vector3(cos(a1) * r, y, sin(a1) * r)
					var tip := Vector3(0, y + 3.2, 0)
					for e in [[p0, col_bot], [tip, col_top], [p1, col_bot]]:
						var p: Vector3 = e[0]
						var c: Color = e[1]
						c.a = clampf(p.y / 14.0, 0.0, 1.0) * 0.5
						st.set_color(c)
						st.set_normal((Vector3(p.x, 0.6 * r, p.z)).normalized())
						st.add_vertex(p)
		"wilg":
			# Pollard willow along ditches: a fat gnarled stump with a ball of thin shoots.
			var crown := Vector3(0, 3.8, 0)
			_limb(st, Vector3.ZERO, Vector3(0.15, 2.6, 0), 0.5, 0.42, Color("5b5143"), 7)
			for k in 5:
				var c := crown + Vector3(rng.randf_range(-1.2, 1.2), rng.randf_range(-0.4, 1.0), rng.randf_range(-1.2, 1.2))
				_blob(st, c, Vector3(1.3, 1.5, 1.3) * rng.randf_range(0.8, 1.2), crown, 2.4, Color("7e9064"), Color("434f30"), 1.0, rng.randf() * 10)
	var mesh := _finish(st)
	_cache[key] = mesh
	return mesh


# ------------------------------------------------------------------ buildings

static func _mat(tex: Texture2D, rough := 0.9, glow: Texture2D = null) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = rough
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if glow != null:
		m.emission_enabled = true
		m.emission = Color.WHITE
		m.emission_texture = glow
		m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		m.emission_energy_multiplier = 1.2
	return m


## Adds a quad (p0..p3 counter-clockwise seen from outside) with UVs in metres / tile size.
static func _quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, tile: Vector2, uv_origin := Vector2.ZERO) -> void:
	var n := (p1 - p0).cross(p3 - p0).normalized()
	var u_dir := (p1 - p0).normalized()
	var v_dir := n.cross(u_dir)
	var uv := func(p: Vector3) -> Vector2:
		var rel := p - p0
		return uv_origin + Vector2(rel.dot(u_dir) / tile.x, -rel.dot(v_dir) / tile.y)
	for p in [p0, p1, p2, p0, p2, p3]:
		st.set_normal(n)
		st.set_uv(uv.call(p))
		st.add_vertex(p)


static func _tri(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, tile: Vector2) -> void:
	var n := (p1 - p0).cross(p2 - p0).normalized()
	var u_dir := (p1 - p0).normalized()
	var v_dir := n.cross(u_dir)
	for p in [p0, p1, p2]:
		var rel: Vector3 = p - p0
		st.set_normal(n)
		st.set_uv(Vector2(rel.dot(u_dir) / tile.x, -rel.dot(v_dir) / tile.y))
		st.add_vertex(p)


## Walls of a box (w across x, d along z) from y0 to y1, one texture tile = tile metres.
static func _walls(st: SurfaceTool, w: float, d: float, y0: float, y1: float, tile: Vector2, skip_front := false) -> void:
	var x := w / 2.0
	var z := d / 2.0
	if not skip_front:
		_quad(st, Vector3(-x, y0, z), Vector3(x, y0, z), Vector3(x, y1, z), Vector3(-x, y1, z), tile)
	_quad(st, Vector3(x, y0, -z), Vector3(-x, y0, -z), Vector3(-x, y1, -z), Vector3(x, y1, -z), tile)
	_quad(st, Vector3(x, y0, z), Vector3(x, y0, -z), Vector3(x, y1, -z), Vector3(x, y1, z), tile)
	_quad(st, Vector3(-x, y0, -z), Vector3(-x, y0, z), Vector3(-x, y1, z), Vector3(-x, y1, -z), tile)


## Gable roof along z: eaves at y_e (overhang o), ridge at y_r; gable triangles go to `gable`.
static func _gable_roof(roof: SurfaceTool, gable: SurfaceTool, w: float, d: float, y_e: float, y_r: float, o: float, tile: Vector2, gtile: Vector2) -> void:
	var x := w / 2.0 + o
	var z := d / 2.0 + o * 0.6
	var drop := o * (y_r - y_e) / (w / 2.0)
	_quad(roof, Vector3(x, y_e - drop, z), Vector3(x, y_e - drop, -z), Vector3(0, y_r, -z), Vector3(0, y_r, z), tile)
	_quad(roof, Vector3(-x, y_e - drop, -z), Vector3(-x, y_e - drop, z), Vector3(0, y_r, z), Vector3(0, y_r, -z), tile)
	for s in [1.0, -1.0]:
		var zz: float = s * d / 2.0
		if s > 0:
			_tri(gable, Vector3(-w / 2.0, y_e, zz), Vector3(w / 2.0, y_e, zz), Vector3(0, y_r, zz), gtile)
		else:
			_tri(gable, Vector3(w / 2.0, y_e, zz), Vector3(-w / 2.0, y_e, zz), Vector3(0, y_r, zz), gtile)


## Twentse "los hoes": long low brick walls, a huge roof with a half hip (wolfseind) over the front gable,
## the big barn doors in that gable and a white owl board (uilenbord) at the top. Front = +z.
static func farmhouse(thatch: bool) -> ArrayMesh:
	var key := "farm|%s" % thatch
	if _cache.has(key):
		return _cache[key]
	var W := 12.0
	var D := 24.0
	var eave := 3.0
	var ridge := 11.0
	var hip := 7.0 # height where the front half-hip starts
	var o := 0.6
	var wall := SurfaceTool.new()
	wall.begin(Mesh.PRIMITIVE_TRIANGLES)
	var front := SurfaceTool.new()
	front.begin(Mesh.PRIMITIVE_TRIANGLES)
	var roof := SurfaceTool.new()
	roof.begin(Mesh.PRIMITIVE_TRIANGLES)
	_walls(wall, W, D, 0, eave, Vector2(6, 3), true)
	# Front gable wall up to the half hip (one texture over the whole gable: barn doors, owl board).
	var x := W / 2.0
	var z := D / 2.0
	var xh := x * (ridge - hip) / (ridge - eave)
	var gt := Vector2(W, hip)
	var g0 := Vector3(-x, 0, z)
	var pts := [Vector3(-x, 0, z), Vector3(x, 0, z), Vector3(x, eave, z), Vector3(xh, hip, z), Vector3(-xh, hip, z), Vector3(-x, eave, z)]
	var n := Vector3(0, 0, 1)
	for tri in [[0, 1, 2], [0, 2, 5], [5, 2, 3], [5, 3, 4]]:
		for k in tri:
			var p: Vector3 = pts[k]
			front.set_normal(n)
			front.set_uv(Vector2((p.x + x) / gt.x, 1.0 - p.y / gt.y))
			front.add_vertex(p)
	# Rear gable: plain brick triangle under the full hip is hidden by the roof; close it with the wall tile.
	var rt := Vector2(6, 3)
	_tri(wall, Vector3(x, eave, -z), Vector3(-x, eave, -z), Vector3(0, eave, -z), rt)
	# Roof: long sides up to the ridge, a full hip at the back, a half hip at the front.
	var tile := Vector2(4, 4)
	var xo := x + o
	var ze := z + o * 0.5
	var zr0 := -z + (ridge - eave) * 0.55 # ridge ends where the rear hip starts
	var zr1 := z - (ridge - hip) * 0.7
	var drop := o * (ridge - eave) / x
	var ye := eave - drop
	_quad(roof, Vector3(xo, ye, ze), Vector3(xo, ye, -ze), Vector3(0, ridge, zr0), Vector3(0, ridge, zr1), tile)
	_quad(roof, Vector3(-xo, ye, -ze), Vector3(-xo, ye, ze), Vector3(0, ridge, zr1), Vector3(0, ridge, zr0), tile)
	_tri(roof, Vector3(-xo, ye, -ze), Vector3(0, ridge, zr0), Vector3(xo, ye, -ze), tile)
	# Front: the slopes meet the half-hip line, then a small hip from there to the ridge.
	_tri(roof, Vector3(xh + 0.2, hip, ze), Vector3(0, ridge, zr1), Vector3(-xh - 0.2, hip, ze), tile)
	var mesh := ArrayMesh.new()
	var wall_tex := Tex.brick_wall("farm")
	for e in [[wall, _mat(wall_tex[0], 0.95, wall_tex[1])], [front, _mat(Tex.farm_gable(), 0.9)],
			[roof, _mat(Tex.thatch() if thatch else Tex.roof_tiles("2b2a2a"), 0.95)]]:
		var sm: ArrayMesh = (e[0] as SurfaceTool).commit()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sm.surface_get_arrays(0))
		mesh.surface_set_material(mesh.get_surface_count() - 1, e[1])
	_cache[key] = mesh
	return mesh


## Black wooden barn (Twentse schuur) with a corrugated roof.
static func barn() -> ArrayMesh:
	if _cache.has("barn"):
		return _cache["barn"]
	var wall := SurfaceTool.new()
	wall.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gable := SurfaceTool.new()
	gable.begin(Mesh.PRIMITIVE_TRIANGLES)
	var roof := SurfaceTool.new()
	roof.begin(Mesh.PRIMITIVE_TRIANGLES)
	_walls(wall, 10, 18, 0, 4, Vector2(4, 4))
	_gable_roof(roof, gable, 10, 18, 4, 8, 0.5, Vector2(3, 3), Vector2(4, 4))
	var planks := _mat(Tex.planks(), 0.95)
	var mesh := ArrayMesh.new()
	for e in [[wall, planks], [gable, planks], [roof, _mat(Tex.corrugated("5a5e60"), 0.6)]]:
		var sm: ArrayMesh = (e[0] as SurfaceTool).commit()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sm.surface_get_arrays(0))
		mesh.surface_set_material(mesh.get_surface_count() - 1, e[1])
	_cache["barn"] = mesh
	return mesh


## A row of five terraced houses (rijtjeshuizen): front (doors, windows) towards +z, ridge along x.
static func terrace(roof_hex: String) -> ArrayMesh:
	var key := "terrace|" + roof_hex
	if _cache.has(key):
		return _cache[key]
	var units := 5
	var uw := 5.6
	var W := units * uw
	var D := 9.0
	var wall := SurfaceTool.new()
	wall.begin(Mesh.PRIMITIVE_TRIANGLES)
	var facade := SurfaceTool.new()
	facade.begin(Mesh.PRIMITIVE_TRIANGLES)
	var roof := SurfaceTool.new()
	roof.begin(Mesh.PRIMITIVE_TRIANGLES)
	var eave := 5.8
	var ridge := 10.0
	var x := W / 2.0
	var z := D / 2.0
	# Front and back facades: one house per texture tile.
	_quad(facade, Vector3(-x, 0, z), Vector3(x, 0, z), Vector3(x, eave, z), Vector3(-x, eave, z), Vector2(uw, eave))
	_quad(facade, Vector3(x, 0, -z), Vector3(-x, 0, -z), Vector3(-x, eave, -z), Vector3(x, eave, -z), Vector2(uw, eave))
	# Side walls with the gables.
	for s in [1.0, -1.0]:
		var xx: float = s * x
		var a := Vector3(xx, 0, -s * z)
		var b := Vector3(xx, 0, s * z)
		_quad(wall, a, b, Vector3(xx, eave, s * z), Vector3(xx, eave, -s * z), Vector2(3, 3))
		_tri(wall, Vector3(xx, eave, -s * z), Vector3(xx, eave, s * z), Vector3(xx, ridge, 0), Vector2(3, 3))
	var o := 0.4
	var drop := o * (ridge - eave) / z
	_quad(roof, Vector3(-x - o, eave - drop, z + o), Vector3(x + o, eave - drop, z + o), Vector3(x + o, ridge, 0), Vector3(-x - o, ridge, 0), Vector2(3, 3))
	_quad(roof, Vector3(x + o, eave - drop, -z - o), Vector3(-x - o, eave - drop, -z - o), Vector3(-x - o, ridge, 0), Vector3(x + o, ridge, 0), Vector2(3, 3))
	var bw := Tex.brick_wall("plain")
	var fac := Tex.house_facade()
	var mesh := ArrayMesh.new()
	for e in [[wall, _mat(bw[0], 0.95)], [facade, _mat(fac[0], 0.9, fac[1])], [roof, _mat(Tex.roof_tiles(roof_hex), 0.85)]]:
		var sm: ArrayMesh = (e[0] as SurfaceTool).commit()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sm.surface_get_arrays(0))
		mesh.surface_set_material(mesh.get_surface_count() - 1, e[1])
	_cache[key] = mesh
	return mesh


## Detached house: brick, a steep tiled roof, ridge along x, front to +z.
static func villa(roof_hex: String) -> ArrayMesh:
	var key := "villa|" + roof_hex
	if _cache.has(key):
		return _cache[key]
	var W := 10.0
	var D := 9.0
	var eave := 3.2
	var ridge := 9.0
	var facade := SurfaceTool.new()
	facade.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wall := SurfaceTool.new()
	wall.begin(Mesh.PRIMITIVE_TRIANGLES)
	var roof := SurfaceTool.new()
	roof.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x := W / 2.0
	var z := D / 2.0
	_quad(facade, Vector3(-x, 0, z), Vector3(x, 0, z), Vector3(x, eave, z), Vector3(-x, eave, z), Vector2(W / 2.0, eave))
	_quad(facade, Vector3(x, 0, -z), Vector3(-x, 0, -z), Vector3(-x, eave, -z), Vector3(x, eave, -z), Vector2(W / 2.0, eave))
	for s in [1.0, -1.0]:
		var xx: float = s * x
		_quad(wall, Vector3(xx, 0, -s * z), Vector3(xx, 0, s * z), Vector3(xx, eave, s * z), Vector3(xx, eave, -s * z), Vector2(3, 3))
		_tri(wall, Vector3(xx, eave, -s * z), Vector3(xx, eave, s * z), Vector3(xx, ridge, 0), Vector2(3, 3))
	var o := 0.5
	var drop := o * (ridge - eave) / z
	_quad(roof, Vector3(-x - o, eave - drop, z + o), Vector3(x + o, eave - drop, z + o), Vector3(x + o, ridge, 0), Vector3(-x - o, ridge, 0), Vector2(3, 3))
	_quad(roof, Vector3(x + o, eave - drop, -z - o), Vector3(-x - o, eave - drop, -z - o), Vector3(-x - o, ridge, 0), Vector3(x + o, ridge, 0), Vector2(3, 3))
	var bw := Tex.brick_wall("plain")
	var fac := Tex.villa_facade()
	var mesh := ArrayMesh.new()
	for e in [[wall, _mat(bw[0], 0.95)], [facade, _mat(fac[0], 0.9, fac[1])], [roof, _mat(Tex.roof_tiles(roof_hex), 0.85)]]:
		var sm: ArrayMesh = (e[0] as SurfaceTool).commit()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sm.surface_get_arrays(0))
		mesh.surface_set_material(mesh.get_surface_count() - 1, e[1])
	_cache[key] = mesh
	return mesh


## Business-park hall: cladding, a coloured band and the company name, flat roof. Front = +z.
static func hall(company: String, band: Color) -> ArrayMesh:
	var key := "hall|%s" % company
	if _cache.has(key):
		return _cache[key]
	var W := 46.0
	var D := 30.0
	var H := 11.0
	var wall := SurfaceTool.new()
	wall.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sign := SurfaceTool.new()
	sign.begin(Mesh.PRIMITIVE_TRIANGLES)
	_walls(wall, W, D, 0, H, Vector2(4, H))
	_quad(top, Vector3(-W / 2, H, D / 2), Vector3(W / 2, H, D / 2), Vector3(W / 2, H, -D / 2), Vector3(-W / 2, H, -D / 2), Vector2(8, 8))
	var sz := D / 2.0 + 0.05
	_quad(sign, Vector3(-W * 0.4, H - 3.2, sz), Vector3(W * 0.4, H - 3.2, sz), Vector3(W * 0.4, H - 0.6, sz), Vector3(-W * 0.4, H - 0.6, sz), Vector2(W * 0.8, 2.6))
	var mesh := ArrayMesh.new()
	var sign_tex := Tex.text(company, band, Color.WHITE, 1024, 128, 84)
	for e in [[wall, _mat(Tex.cladding(band), 0.55)], [top, _mat(Tex.corrugated("6b6e70"), 0.7)], [sign, _mat(sign_tex, 0.5, sign_tex)]]:
		var sm: ArrayMesh = (e[0] as SurfaceTool).commit()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sm.surface_get_arrays(0))
		mesh.surface_set_material(mesh.get_surface_count() - 1, e[1])
	_cache[key] = mesh
	return mesh


# ------------------------------------------------------------------ farmland

## Holstein cow (black and white, or the odd red one), ~2.4 m long, facing +z. Vertex colours.
static func cow(variant: int) -> ArrayMesh:
	var key := "cow|%d" % variant
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 + variant
	var dark := Color("161616") if variant != 2 else Color("6b2f1c")
	var light := Color("eeeae2")
	var patch := func(p: Vector3) -> Color:
		var n := _n3(p * 1.6 + Vector3(variant * 7.0, 0, 0))
		return dark if n > (0.05 if variant == 1 else 0.25) else light
	var box := func(c: Vector3, s: Vector3, colf) -> void:
		var bx := BoxMesh.new()
		bx.size = s
		bx.subdivide_width = 2
		bx.subdivide_depth = 3
		bx.subdivide_height = 1
		var arr := bx.get_mesh_arrays()
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var ids: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for i in ids:
			var p: Vector3 = vs[i] + c
			var col: Color = colf.call(p) if colf is Callable else colf
			col.a = 0.0
			st.set_color(col)
			st.set_normal(ns[i])
			st.add_vertex(p)
	box.call(Vector3(0, 1.05, 0), Vector3(0.75, 0.75, 1.75), patch)
	box.call(Vector3(0, 1.25, 1.05), Vector3(0.4, 0.45, 0.6), patch)
	box.call(Vector3(0, 1.08, 1.38), Vector3(0.3, 0.25, 0.12), Color("d8a8a0"))
	for lx in [-0.25, 0.25]:
		for lz in [-0.65, 0.65]:
			box.call(Vector3(lx, 0.36, lz), Vector3(0.16, 0.72, 0.16), patch)
	box.call(Vector3(0, 0.72, -0.4), Vector3(0.3, 0.12, 0.3), Color("e6b0a8"))
	var mesh := _finish(st)
	_cache[key] = mesh
	return mesh


## Wrapped silage bale ("boerenkaviaar"): white, sometimes black or green. Lies on its side.
static func bale(hex: String) -> ArrayMesh:
	var key := "bale|" + hex
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := Color(hex)
	_limb(st, Vector3(-0.6, 0.62, 0), Vector3(0.6, 0.62, 0), 0.62, 0.62, col, 12)
	# Flat round ends.
	for s in [-1.0, 1.0]:
		for i in 12:
			var a0 := TAU * i / 12
			var a1 := TAU * (i + 1) / 12
			var c0 := Vector3(s * 0.6, 0.62, 0)
			var p0 := c0 + Vector3(0, cos(a0), sin(a0)) * 0.62
			var p1 := c0 + Vector3(0, cos(a1), sin(a1)) * 0.62
			var tri := [c0, p0, p1] if s > 0 else [c0, p1, p0]
			for p in tri:
				var cc := col.darkened(0.08)
				cc.a = 0.0
				st.set_color(cc)
				st.set_normal(Vector3(s, 0, 0))
				st.add_vertex(p)
	var mesh := _finish(st)
	_cache[key] = mesh
	return mesh
