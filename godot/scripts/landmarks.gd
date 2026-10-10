class_name Landmarks
extends RefCounted
## Places the Blender landmarks along the route (each turned to face the motorway) and sails
## a barge on the Twentekanaal. Port of src/track/Landmarks.ts.

const MODELS := ["lm_raadhuis", "lm_tokkolocco", "lm_ravijn", "lm_gemeentehuis", "lm_stoomweverij", "lm_watertoren",
	"lm_heraklus", "lm_bauhaus", "lm_ikea", "lm_metropool", "lm_utwente", "lm_veste", "lm_brouwerij", "lm_thuisbesteld", "lm_barge"]
## Landmarks that stand closer to the road than the usual 30 m (front edge to road centre).
const CLOSE_TO_ROAD := {"tokkolocco": 15.0}

var root := Node3D.new()
var _barges: Array = [] # {obj, phase, width}
var _time := 0.0


## Merge a static model into one mesh with a surface per material (far fewer draw calls).
static func merge_static(src: Node) -> ArrayMesh:
	var by_mat := {}
	for mi: MeshInstance3D in src.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D()
		var n: Node = mi
		while n != src and n is Node3D:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var nb := xf.basis.inverse().transposed()
		for si in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(si)
			if not by_mat.has(mat):
				by_mat[mat] = [PackedVector3Array(), PackedVector3Array(), PackedInt32Array()]
			var e: Array = by_mat[mat]
			var arr := mi.mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var ids = arr[Mesh.ARRAY_INDEX]
			var base: int = e[0].size()
			for i in verts.size():
				e[0].append(xf * verts[i])
				e[1].append((nb * norms[i]).normalized())
			if ids == null:
				ids = PackedInt32Array(range(verts.size()))
			for i in ids:
				e[2].append(base + i)
	var am := ArrayMesh.new()
	for mat in by_mat:
		var e: Array = by_mat[mat]
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = e[0]
		arr[Mesh.ARRAY_NORMAL] = e[1]
		arr[Mesh.ARRAY_INDEX] = e[2]
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		am.surface_set_material(am.get_surface_count() - 1, mat)
	return am


static func _load(name: String) -> ArrayMesh:
	var path := "res://assets/models/%s.glb" % name
	if not ResourceLoader.exists(path):
		return null
	var scene: Node = load(path).instantiate()
	var mesh := merge_static(scene)
	scene.free()
	return mesh


func _init(track: Track, builder: TrackBuilder) -> void:
	for lm in track.features.landmarks:
		var mesh := _load("lm_%s" % lm.id)
		if mesh == null:
			continue
		# Model front is +Z; its depth decides how far back it must stand from the road.
		var box := mesh.get_aabb()
		var side := signf(lm.d) if lm.d != 0 else 1.0
		# Keep the front edge (max z) at least ~30 m from the road centre (clear of verge and trees);
		# the roadside restaurant stands right behind the railing.
		var dist := maxf(absf(lm.d), CLOSE_TO_ROAD.get(lm.id, 30.0) + box.end.z)
		var fr := track.frame(lm.s)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = Vector3(fr.x + fr.rx * dist * side, 0, fr.z + fr.rz * dist * side)
		# Face the road: the road lies opposite to our side.
		mi.rotation.y = atan2(-side * fr.rx, -side * fr.rz)
		root.add_child(mi)

	var barge := _load("lm_barge")
	if barge != null:
		for canal in builder.canals:
			var mi := MeshInstance3D.new()
			mi.mesh = barge
			mi.position = Vector3(0, 0.08, 0)
			(canal.holder as Node3D).add_child(mi)
			_barges.append({"obj": mi, "phase": randf() * TAU, "width": canal.width})


func update(dt: float) -> void:
	_time += dt
	for b in _barges:
		# Slowly back and forth along the canal, passing under the bridge.
		var x := sin(_time * 0.012 + b.phase) * 260
		var back := cos(_time * 0.012 + b.phase) < 0
		var obj: Node3D = b.obj
		obj.position = Vector3(x, 0.08, b.width * 0.18 * (-1.0 if back else 1.0))
		obj.rotation.y = PI if back else 0.0
