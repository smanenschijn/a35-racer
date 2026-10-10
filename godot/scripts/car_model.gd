class_name CarModel
extends RefCounted
## A car on screen: the detailed Blender model (or a procedural truck), flattened once per model into
## one batched mesh whose dents, lost parts, paint and lights are per-car shader parameters.
## Port of src/vehicle/CarModel.ts.

const MAX_LOOSE := 30
const MODELS := ["rx7", "supremo", "golv", "civik", "corso", "calibro", "volvi", "spacewagen",
	"tr_sedan", "tr_hatch", "tr_estate", "tr_van", "police"]

static var _scenes := {}
static var _templates := {}
static var _mat_uber: ShaderMaterial
static var _mat_glass: ShaderMaterial
static var _mat_static: ShaderMaterial
static var _mat_tex := {}


## Everything that is the same for every car of one kind.
class Template:
	var body: ArrayMesh
	var loose: Array = [] # {zone, centre: Vector3}
	var steer_hubs: Array = [] # {pos, wheel: ArrayMesh, wheel_xf, caliper: ArrayMesh}
	var axles: Array = [] # {pos, mesh}
	var fixed: ArrayMesh # calipers that don't steer (on the root, they don't lean)
	var wheel_r := 0.31
	var car_offset := 0.0


static func preload_models() -> void:
	for name in MODELS:
		var path := "res://assets/models/%s.glb" % name
		if ResourceLoader.exists(path):
			_scenes[name] = load(path)
		else:
			push_warning("Model %s ontbreekt, val terug op procedureel model" % name)


static func _materials() -> void:
	if _mat_uber != null:
		return
	_mat_uber = ShaderMaterial.new()
	_mat_uber.shader = load("res://shaders/car.gdshader")
	_mat_glass = ShaderMaterial.new()
	_mat_glass.shader = load("res://shaders/car_glass.gdshader")
	_mat_static = ShaderMaterial.new()
	_mat_static.shader = load("res://shaders/car_static.gdshader")


static func _tex_material(tex: Texture2D) -> ShaderMaterial:
	if not _mat_tex.has(tex):
		var m := ShaderMaterial.new()
		m.shader = _mat_uber.shader
		m.set_shader_parameter("use_tex", true)
		m.set_shader_parameter("tex", tex)
		_mat_tex[tex] = m
	return _mat_tex[tex]


var root := Node3D.new()
## Body: leans and pitches on top of the root transform.
var body := Node3D.new()
var _body_mi: MeshInstance3D
var _wheels: Array = [] # Node3D spinning about local X
var _front_pivots: Array = []
var _details: Array = []
var _detail_on := true
var _wheel_spin := 0.0
var _tpl: Template
var _spec: Dictionary
var _color: Color
var _paint: Color
var _gone := 0
var _loose_gone: Array = []
var _dents: Array = [] # 8 × Vector4(x, z, strength, 0)
var _pending: Array = [] # [lx, lz, amount]
var _lights := Vector4(2.2, 1.2, 0, 0)
# Suspension springs (angle + angular velocity) for roll and pitch.
var _roll := 0.0
var _roll_vel := 0.0
var _pitch_body := 0.0
var _pitch_vel := 0.0
var _bounce := 0.0
var _bounce_vel := 0.0


func _init(spec: Dictionary, parent: Node3D) -> void:
	_materials()
	_spec = spec
	_color = Config.color(spec.color)
	_paint = _color
	_tpl = _template(spec)
	for i in 8:
		_dents.append(Vector4.ZERO)
	_loose_gone.resize(_tpl.loose.size())
	_loose_gone.fill(false)
	root.add_child(body)
	body.position.z = _tpl.car_offset
	_body_mi = MeshInstance3D.new()
	_body_mi.mesh = _tpl.body
	body.add_child(_body_mi)
	for h in _tpl.steer_hubs:
		var pivot := Node3D.new()
		pivot.position = h.pos + Vector3(0, 0, _tpl.car_offset)
		root.add_child(pivot)
		var holder := Node3D.new()
		holder.transform = h.wheel_xf
		pivot.add_child(holder)
		holder.add_child(_mi(h.wheel, false))
		if h.caliper != null:
			pivot.add_child(_mi(h.caliper, false))
		_front_pivots.append(pivot)
		_wheels.append(holder)
		_details.append(pivot)
	for a in _tpl.axles:
		var axle := Node3D.new()
		axle.position = a.pos + Vector3(0, 0, _tpl.car_offset)
		axle.add_child(_mi(a.mesh, false))
		root.add_child(axle)
		_wheels.append(axle)
		_details.append(axle)
	if _tpl.fixed != null:
		var f := _mi(_tpl.fixed, false)
		f.position.z = _tpl.car_offset
		root.add_child(f)
		_details.append(f)
	_body_mi.set_instance_shader_parameter("paint", _paint)
	_body_mi.set_instance_shader_parameter("lights", _lights)
	parent.add_child(root)


func _mi(mesh: Mesh, shadow: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ------------------------------------------------------------------ templates

static func _template(spec: Dictionary) -> Template:
	var model: String = spec.get("model", "")
	var key := "%s|%s|%s|%s" % [model if _scenes.has(model) else spec.get("kind", "car"), spec.plate, spec.get("trailerText", ""), spec.get("trailerLength", 0)]
	if _templates.has(key):
		return _templates[key]
	var car: Node3D
	var wheel_r := 0.31
	if _scenes.has(model):
		var scene: Node3D = _scenes[model].instantiate()
		car = scene.get_child(0) if scene.get_child_count() == 1 else scene
		wheel_r = car.get_meta("extras", {}).get("wheel_r", 0.31)
	elif spec.get("kind", "") == "truck":
		car = _build_truck(spec)
		wheel_r = 0.52
	else:
		car = _build_box_car(spec)
		wheel_r = 0.33
	var car_offset := 0.0
	if spec.get("trailerLength", 0.0) > 0:
		car_offset = Config.total_length(spec) / 2.0 - spec.length / 2.0
		car.add_child(_build_caravan(spec, car_offset))
	# Traffic and the police don't show steering or brake calipers.
	var lite := model == "" or model.begins_with("tr_") or model == "police"
	var tpl := _flatten(car, Tex.plate(spec.plate), lite)
	tpl.wheel_r = wheel_r
	tpl.car_offset = car_offset
	if car.get_parent() != null:
		car.get_parent().free()
	else:
		car.free()
	_templates[key] = tpl
	return tpl


## Vertex streams for one target surface.
class Stream:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	var idx := PackedInt32Array()


## What a source material turns into: target surface + per-vertex attributes.
static func _classify(m: Material, plate_tex: Texture2D) -> Dictionary:
	var name := m.resource_name if m != null else ""
	var sm := m as BaseMaterial3D
	var col := Color.WHITE
	var metal := 0.0
	var rough := 0.6
	var emi := Color.BLACK
	var cls := 0.0
	var target := "uber"
	var tex: Texture2D = null
	if sm != null:
		col = sm.albedo_color
		metal = sm.metallic
		rough = sm.roughness
		if sm.emission_enabled:
			emi = sm.emission.srgb_to_linear() * sm.emission_energy_multiplier
		tex = sm.albedo_texture
	var paint := 0.0
	match name:
		"Paint":
			paint = 1.0
		"BrakeLight":
			col = Color("550000")
			emi = Color("ff1a1a").srgb_to_linear()
			cls = 2.0
		"HeadLight":
			col = Color("fff6dd")
			emi = Color("fff2cc").srgb_to_linear()
			cls = 1.0
		"BeaconL", "BeaconR":
			col = Color("0a1a66")
			emi = Color("2a5cff").srgb_to_linear()
			cls = 3.0 if name == "BeaconL" else 4.0
		"Plate":
			col = Color.WHITE
			tex = plate_tex
	if name == "Glass" or (sm != null and sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and cls < 3):
		target = "glass"
	elif tex != null:
		target = "tex"
	var lin := col.srgb_to_linear()
	lin.a = col.a
	return {"target": target, "tex": tex, "col": lin, "c0": [metal, rough, paint, 0.0], "c1": [emi.r, emi.g, emi.b, cls]}


## Merge every mesh under `node` into streams, in the space of `space` (a transform from the car root).
static func _gather(node: Node, to_space: Transform3D, streams: Dictionary, plate_tex: Texture2D, deform: bool, loose: int, skip: Callable) -> void:
	if skip.call(node):
		return
	var extras: Dictionary = node.get_meta("extras", {})
	var d: bool = deform or extras.get("deform", 0.0) > 0.5
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var xf := to_space * _xf_to_car(mi)
		var nb := xf.basis.inverse().transposed()
		var flip := xf.basis.determinant() < 0
		for si in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(si)
			var c := _classify(mat, plate_tex)
			var key: String = c.target if c.target != "tex" else "tex%d" % c.tex.get_instance_id()
			if not streams.has(key):
				streams[key] = {"s": Stream.new(), "target": c.target, "tex": c.tex}
			var st: Stream = streams[key].s
			var arr := mi.mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var uvs = arr[Mesh.ARRAY_TEX_UV]
			var ids = arr[Mesh.ARRAY_INDEX]
			var base := st.v.size()
			var c0: Array = c.c0.duplicate()
			c0[3] = 1.0 if d else 0.0
			var c1: Array = c.c1.duplicate()
			c1[3] += 8.0 * loose
			var col: Color = c.col
			for i in verts.size():
				st.v.append(xf * verts[i])
				st.n.append((nb * norms[i]).normalized())
				st.uv.append(uvs[i] if uvs != null else Vector2.ZERO)
				st.col.append(col)
				st.c0.append_array(c0)
				st.c1.append_array(c1)
			if ids == null:
				ids = PackedInt32Array(range(verts.size()))
			for t in range(0, ids.size(), 3):
				if flip:
					st.idx.append_array([base + ids[t], base + ids[t + 2], base + ids[t + 1]])
				else:
					st.idx.append_array([base + ids[t], base + ids[t + 1], base + ids[t + 2]])
	for c in node.get_children():
		_gather(c, to_space, streams, plate_tex, d, loose, skip)


## Transform of a node relative to the car root (the node that holds the parts).
static func _xf_to_car(n: Node3D) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p != null and p is Node3D and not p.has_meta("car_root"):
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


## Static meshes (wheels, calipers) use the shader without per-car parameters.
static func _commit(streams: Dictionary, static_mesh := false) -> ArrayMesh:
	var am := ArrayMesh.new()
	var flags := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	var order := streams.keys()
	order.sort_custom(func(a, b): return (1 if streams[a].target == "glass" else 0) < (1 if streams[b].target == "glass" else 0))
	for k in order:
		var e: Dictionary = streams[k]
		var st: Stream = e.s
		if st.idx.is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = st.v
		arr[Mesh.ARRAY_NORMAL] = st.n
		arr[Mesh.ARRAY_TEX_UV] = st.uv
		arr[Mesh.ARRAY_COLOR] = st.col
		arr[Mesh.ARRAY_CUSTOM0] = st.c0
		arr[Mesh.ARRAY_CUSTOM1] = st.c1
		arr[Mesh.ARRAY_INDEX] = st.idx
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
		var m: Material = _mat_static if static_mesh else _mat_uber
		if e.target == "glass":
			m = _mat_glass
		elif e.target == "tex":
			m = _tex_material(e.tex)
		am.surface_set_material(am.get_surface_count() - 1, m)
	return am if am.get_surface_count() > 0 else null


static func _flatten(car: Node3D, plate_tex: Texture2D, lite: bool) -> Template:
	var tpl := Template.new()
	car.set_meta("car_root", true)
	var hubs := []
	var detach := []
	for c in car.get_children():
		if String(c.name).begins_with("hub_"):
			hubs.append(c)
		elif c.get_meta("extras", {}).get("detach", 0.0) > 0.5:
			detach.append(c)
	# Loose parts: grouped by zone, name and side, each group one bit.
	var groups := {}
	for c: Node3D in detach:
		var extras: Dictionary = c.get_meta("extras", {})
		var centre := _centre(c)
		var side := "L" if centre.x > 0.3 else ("R" if centre.x < -0.3 else "C")
		var key := "%s|%s|%s" % [extras.get("zone", ""), String(c.name).split("_")[0], side]
		if not groups.has(key):
			if groups.size() >= MAX_LOOSE:
				key = groups.keys()[groups.size() - 1]
			else:
				groups[key] = {"zone": extras.get("zone", ""), "nodes": [], "centre": Vector3.ZERO}
		groups[key].nodes.append(c)
		groups[key].centre += centre
	var loose_of := {}
	var gi := 0
	for k in groups:
		var g: Dictionary = groups[k]
		gi += 1
		tpl.loose.append({"zone": g.zone, "centre": g.centre / g.nodes.size()})
		for n in g.nodes:
			loose_of[n] = gi

	# Body: everything except the hubs, each loose group tagged.
	var streams := {}
	for c in car.get_children():
		if hubs.has(c):
			continue
		_gather(c, Transform3D(), streams, plate_tex, false, loose_of.get(c, 0), func(_n): return false)
	tpl.body = _commit(streams)

	# Wheels: steered fronts keep their own pivots (racers), the rest merge per axle.
	var axles := {}
	var fixed := {}
	for h: Node3D in hubs:
		var steer: bool = h.get_meta("extras", {}).get("steer", 0.0) > 0.5 and not lite
		var wheel: Node3D = null
		for w in h.get_children():
			if w.get_meta("extras", {}).get("spin", 0.0) > 0.5:
				wheel = w
		if wheel == null:
			continue
		if steer:
			var ws := {}
			_gather(wheel, _xf_to_car(wheel).affine_inverse(), ws, plate_tex, false, 0, func(_n): return false)
			var cs := {}
			_gather(h, _xf_to_car(h).affine_inverse(), cs, plate_tex, false, 0, func(n): return n == wheel)
			tpl.steer_hubs.append({"pos": h.position, "wheel": _commit(ws, true), "wheel_xf": wheel.transform, "caliper": _commit(cs, true) if not lite else null})
			continue
		var key := "%.3f|%.3f" % [h.position.y, h.position.z]
		if not axles.has(key):
			axles[key] = {"pos": Vector3(0, h.position.y, h.position.z), "streams": {}}
		var a: Dictionary = axles[key]
		_gather(wheel, Transform3D(Basis(), -a.pos), a.streams, plate_tex, false, 0, func(_n): return false)
		if not lite:
			_gather(h, Transform3D(), fixed, plate_tex, false, 0, func(n): return n == wheel)
	for k in axles:
		tpl.axles.append({"pos": axles[k].pos, "mesh": _commit(axles[k].streams, true)})
	if not fixed.is_empty():
		tpl.fixed = _commit(fixed, true)
	return tpl


static func _centre(n: Node3D) -> Vector3:
	var aabb := AABB()
	var first := true
	var list: Array = [n]
	list.append_array(n.find_children("*", "MeshInstance3D", true, false))
	for mi in list:
		if mi is MeshInstance3D:
			var box: AABB = _xf_to_car(mi) * (mi as MeshInstance3D).mesh.get_aabb()
			aabb = box if first else aabb.merge(box)
			first = false
	return aabb.get_center() if not first else _xf_to_car(n).origin


# ------------------------------------------------------------------ procedural vehicles

static func _part(parent: Node3D, mesh: Mesh, mat_name: String, color: Color, pos: Vector3, extras := {}, rot := Vector3.ZERO, metal := 0.0, rough := 0.6, tex: Texture2D = null) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.resource_name = mat_name
	m.albedo_color = color
	m.metallic = metal
	m.roughness = rough
	m.albedo_texture = tex
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	if not extras.is_empty():
		mi.set_meta("extras", extras)
	parent.add_child(mi)
	return mi


static func _boxm(w: float, h: float, d: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(w, h, d)
	return b


static func _quad(w: float, h: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	return q


static func _add_wheel(car: Node3D, x: float, z: float, r: float, steer: bool, width := 0.24) -> void:
	var hub := Node3D.new()
	hub.name = "hub_%d" % car.get_child_count()
	hub.position = Vector3(x, r, z)
	hub.set_meta("extras", {"steer": 1.0 if steer else 0.0})
	car.add_child(hub)
	var wheel := Node3D.new()
	wheel.set_meta("extras", {"spin": 1.0})
	hub.add_child(wheel)
	var tyre := CylinderMesh.new()
	tyre.top_radius = r
	tyre.bottom_radius = r
	tyre.height = width
	tyre.radial_segments = 16
	tyre.rings = 1
	var rim := CylinderMesh.new()
	rim.top_radius = r * 0.6
	rim.bottom_radius = r * 0.6
	rim.height = width + 0.01
	rim.radial_segments = 8
	rim.rings = 1
	_part(wheel, tyre, "Tyre", Color("111111"), Vector3.ZERO, {}, Vector3(0, 0, PI / 2), 0.0, 0.9)
	_part(wheel, rim, "Chrome", Color("cccccc"), Vector3.ZERO, {}, Vector3(0, 0, PI / 2), 1.0, 0.25)


static func _build_truck(spec: Dictionary) -> Node3D:
	var car := Node3D.new()
	var L := Config.total_length(spec)
	var W: float = spec.width
	var cab_len := 2.3
	var paint := Config.color(spec.color)
	_part(car, _boxm(W * 0.98, 2.6, cab_len), "Paint", paint, Vector3(0, 0.65 + 1.3, L / 2 - cab_len / 2), {"deform": 1.0, "zone": "front"})
	_part(car, _quad(W * 0.85, 0.9), "Glass", Color(0.05, 0.08, 0.09, 0.8), Vector3(0, 2.55, L / 2 + 0.01))
	_part(car, _boxm(W * 0.9, 0.6, 0.06), "Trim", Color("151515"), Vector3(0, 1.1, L / 2 + 0.02))
	for side in [-1, 1]:
		_part(car, _boxm(0.4, 0.18, 0.05), "HeadLight", Color.WHITE, Vector3(side * (W / 2 - 0.35), 0.75, L / 2 + 0.03))
	# Trailer with company lettering.
	var tl := L - cab_len - 0.4
	var company: String = spec.get("trailerText", "Tukker Transport")
	var lettering := Tex.text(company, Color("eeeeee"), Color("1d3f7a"), 1024, 192, 110, true)
	_part(car, _boxm(W, 2.9, tl), "Trailer", Color("e6e6e6"), Vector3(0, 1.15 + 1.45, -L / 2 + tl / 2), {"deform": 1.0})
	for side in [-1, 1]:
		_part(car, _quad(tl * 0.98, 2.8), "Lettering", Color.WHITE, Vector3(side * (W / 2 + 0.01), 1.15 + 1.45, -L / 2 + tl / 2),
			{}, Vector3(0, side * PI / 2, 0), 0.0, 0.6, lettering)
	_part(car, _boxm(W * 0.7, 0.35, L - 0.4), "Trim", Color("151515"), Vector3(0, 0.9, 0))
	for sx in [-1, 1]:
		_part(car, _boxm(0.4, 0.16, 0.05), "BrakeLight", Color.WHITE, Vector3(sx * (W / 2 - 0.3), 1.0, -L / 2 - 0.02))
	_part(car, _quad(0.52, 0.115), "Plate", Color.WHITE, Vector3(0, 0.8, -L / 2 - 0.03), {}, Vector3(0, PI, 0))
	for sx in [-1, 1]:
		_add_wheel(car, sx * (W / 2 - 0.2), L / 2 - 1.2, 0.52, false, 0.32)
		_add_wheel(car, sx * (W / 2 - 0.2), L / 2 - 4.2, 0.52, false, 0.32)
		for z in [-L / 2 + 1.2, -L / 2 + 2.5, -L / 2 + 3.8]:
			_add_wheel(car, sx * (W / 2 - 0.2), z, 0.52, false, 0.32)
	return car


## Fallback when a Blender model is missing: a simple boxy car.
static func _build_box_car(spec: Dictionary) -> Node3D:
	var car := Node3D.new()
	var L: float = spec.length
	var W: float = spec.width
	var H: float = spec.bodyHeight
	var ride := 0.3
	_part(car, _boxm(W, H, L), "Paint", Color.WHITE, Vector3(0, ride + H / 2, 0), {"deform": 1.0})
	_part(car, _boxm(W * 0.8, spec.cabinHeight, spec.cabinLength), "Glass", Color(0.05, 0.08, 0.09, 0.8), Vector3(0, ride + H + spec.cabinHeight / 2, spec.cabinOffset), {"deform": 1.0})
	for side in [-1, 1]:
		_part(car, _boxm(0.42, 0.12, 0.05), "HeadLight", Color.WHITE, Vector3(side * (W / 2 - 0.3), ride + H * 0.62, L / 2 + 0.005))
		_part(car, _boxm(0.5, 0.14, 0.05), "BrakeLight", Color.WHITE, Vector3(side * (W / 2 - 0.32), ride + H * 0.7, -L / 2 - 0.005))
	_part(car, _quad(0.52, 0.115), "Plate", Color.WHITE, Vector3(0, ride + 0.32, -L / 2 - 0.09), {}, Vector3(0, PI, 0))
	for p in [[-1, 1], [1, 1], [-1, -1], [1, -1]]:
		_add_wheel(car, p[0] * (W / 2 - 0.12), p[1] * (L / 2 - 0.75), 0.33, p[1] > 0)
	return car


## A towed caravan behind the car (positions in the car's body space).
static func _build_caravan(spec: Dictionary, car_offset: float) -> Node3D:
	var T: float = spec.trailerLength
	var L := Config.total_length(spec)
	var g := Node3D.new()
	g.name = "caravan"
	g.position.z = -L / 2 + T / 2 - car_offset
	_part(g, _boxm(2.2, 2.2, T), "White", Color("f2f2f2"), Vector3(0, 0.45 + 1.1, 0), {"deform": 1.0}, Vector3.ZERO, 0.0, 0.5)
	_part(g, _boxm(2.22, 0.18, T * 0.98), "Stripe", Color("9a6a3a"), Vector3(0, 1.1, 0))
	_part(g, _boxm(2.23, 0.5, T * 0.5), "Glass", Color(0.05, 0.08, 0.09, 0.8), Vector3(0, 1.75, 0.2))
	_part(g, _boxm(0.1, 0.1, 1.1), "Trim", Color("151515"), Vector3(0, 0.45, T / 2 + 0.5))
	for sx in [-1, 1]:
		_part(g, _boxm(0.3, 0.12, 0.04), "BrakeLight", Color.WHITE, Vector3(sx * 0.85, 0.75, -T / 2 - 0.02))
		# Wheels sit in the body: a caravan doesn't steer, and its axle is drawn with it.
		var tyre := CylinderMesh.new()
		tyre.top_radius = 0.3
		tyre.bottom_radius = 0.3
		tyre.height = 0.24
		tyre.radial_segments = 12
		tyre.rings = 1
		_part(g, tyre, "Tyre", Color("111111"), Vector3(sx * 1.0, 0.3, 0), {}, Vector3(0, 0, PI / 2), 0.0, 0.9)
	return g


# ------------------------------------------------------------------ runtime

## New paint colour (recycled traffic).
func recolor(hex: int) -> void:
	_color = Config.color(hex)
	_set_paint(_color)


func _set_paint(c: Color) -> void:
	_paint = c
	_body_mi.set_instance_shader_parameter("paint", c)


## Jolt the suspension from an impact at world offset (wx, wz) from the car centre.
func kick(wx: float, wz: float, v: Vehicle, strength: float) -> void:
	var fx := sin(v.heading)
	var fz := cos(v.heading)
	var lx := wx * -fz + wz * fx
	var lz := wx * fx + wz * fz
	var s := minf(1.2, strength * 0.06)
	_roll_vel += signf(lx) * s * (1.0 if absf(lx) > 0.5 else 0.3)
	_pitch_vel += signf(lz) * s * 0.6
	_bounce_vel += s * 0.8


## Queue a dent at a local contact point (lx right, lz forward).
func dent(amount: float, lx: float, lz: float) -> void:
	_pending.append([lx, lz, amount])


func _apply_dents() -> void:
	if _pending.is_empty():
		return
	# Merge tiny scrape dents so we don't touch the shader every frame.
	var total := 0.0
	for p in _pending:
		total += p[2]
	if total < 1.2 and _pending.size() < 30:
		return
	for p in _pending:
		# Model space: +x is the car's left (right = -X), and the body may sit forward of the centre.
		var c := Vector2(-p[0], p[1] - _tpl.car_offset)
		var strength := minf(0.5, p[2] * 0.012)
		var best := -1
		var best_d := INF
		for i in 8:
			var dd: Vector4 = _dents[i]
			if dd.z <= 0:
				continue
			var dist := Vector2(dd.x, dd.y).distance_to(c)
			if dist < best_d:
				best_d = dist
				best = i
		if best >= 0 and best_d < 0.55:
			var dd: Vector4 = _dents[best]
			var w := strength / (dd.z + strength)
			_dents[best] = Vector4(lerpf(dd.x, c.x, w), lerpf(dd.y, c.y, w), minf(0.9, dd.z + strength), 0)
			continue
		var slot := -1
		var weakest := INF
		for i in 8:
			if _dents[i].z < weakest:
				weakest = _dents[i].z
				slot = i
		if weakest <= 0 or strength > weakest:
			_dents[slot] = Vector4(c.x, c.y, strength, 0)
		elif best >= 0:
			_dents[best].z = minf(0.9, _dents[best].z + strength * 0.5)
	_pending.clear()
	for i in 8:
		_body_mi.set_instance_shader_parameter("dent%d" % i, _dents[i])


## Called by the game when a zone gets heavily damaged: drop a loose part.
func zone_damaged(zone: String, level: float) -> bool:
	if level < 60:
		return false
	for i in _tpl.loose.size():
		if _loose_gone[i]:
			continue
		var l: Dictionary = _tpl.loose[i]
		var c: Vector3 = l.centre
		var hit := false
		if l.zone != "" and l.zone != "top":
			hit = l.zone == zone
		elif zone == "front":
			hit = c.z > 1
		elif zone == "rear":
			hit = c.z < -1 or c.y > 1
		elif zone == "left":
			hit = c.x > 0.5
		else:
			hit = c.x < -0.5
		if hit:
			_loose_gone[i] = true
			_gone |= 1 << i
			_body_mi.set_instance_shader_parameter("gone", _gone)
			return true
	return false


func repair() -> void:
	for i in 8:
		_dents[i] = Vector4.ZERO
		_body_mi.set_instance_shader_parameter("dent%d" % i, Vector4.ZERO)
	_loose_gone.fill(false)
	_gone = 0
	_body_mi.set_instance_shader_parameter("gone", 0)
	_pending.clear()
	_set_paint(_color)


func _set_lights(l: Vector4) -> void:
	if l.is_equal_approx(_lights):
		return
	_lights = l
	_body_mi.set_instance_shader_parameter("lights", l)


func sync(v: Vehicle, dt: float, time: float) -> void:
	_apply_dents()
	root.transform = Transform3D(Basis(Vector3.UP, v.heading) * Basis(Vector3.RIGHT, v.pitch), Vector3(v.x, v.y, v.z))

	# Body roll and pitch on soft, slightly underdamped springs: the car feels heavy.
	var lat_acc := v.forward_speed * v.ang_vel
	var roll_target := clampf(lat_acc * 0.009, -0.11, 0.11)
	var pitch_target := clampf(v.accel_long * -0.0035, -0.05, 0.06)
	var k := 55.0 # stiffness
	var c := 7.0 # damping
	if dt > 0:
		_roll_vel += ((roll_target - _roll) * k - _roll_vel * c) * dt
		_roll += _roll_vel * dt
		_pitch_vel += ((pitch_target - _pitch_body) * k - _pitch_vel * c) * dt
		_pitch_body += _pitch_vel * dt
		_bounce_vel += (-_bounce * 90 - _bounce_vel * 9) * dt
		_bounce += _bounce_vel * dt
	body.rotation = Vector3(_pitch_body, 0, _roll) # positive pitch = nose down (braking)
	body.position = Vector3(0, _bounce, _tpl.car_offset)

	_wheel_spin += v.forward_speed / _tpl.wheel_r * dt
	if _detail_on:
		for w: Node3D in _wheels:
			w.rotation.x = _wheel_spin
		for p: Node3D in _front_pivots:
			p.rotation.y = -v.input.steer * 0.45

	var l := Vector4(0.0 if v.wrecked else 2.2, 5.0 if v.braking else 1.2, 0, 0)
	if v.siren_on:
		# Alternating blue flashes, two quick pulses per side.
		var phase := fmod(time * 2.2, 1.0)
		var pulse := 6.0 if sin(phase * PI * 8) > 0.2 else 0.0
		l.z = pulse if phase < 0.5 else 0.0
		l.w = pulse if phase >= 0.5 else 0.0
	_set_lights(l)
	if v.wrecked and dt > 0:
		_set_paint(_paint.lerp(Color("221a16"), minf(1.0, dt * 0.6)))


## Level of detail: far away, drop the parts nobody can see anyway.
func set_detail(on: bool) -> void:
	if on == _detail_on:
		return
	_detail_on = on
	for o: Node3D in _details:
		o.visible = on


## For kinematic (oncoming) traffic that isn't a physics Vehicle.
func place(x: float, y: float, z: float, heading: float, spd: float, dt: float) -> void:
	root.transform = Transform3D(Basis(Vector3.UP, heading), Vector3(x, y, z))
	_wheel_spin += spd / _tpl.wheel_r * dt
	if _detail_on:
		for w: Node3D in _wheels:
			w.rotation.x = _wheel_spin
