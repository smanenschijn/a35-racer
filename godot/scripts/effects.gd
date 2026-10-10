class_name Effects
extends RefCounted
## Particle pools (sparks and fire additive, smoke normal) drawn as camera-facing sprites in one
## MultiMesh each, plus the game's effect presets. Port of src/fx/Particles.ts.

## Point sprites in the web version were sized in pixels at a reference distance; this maps them to metres.
const SIZE_TO_METRES := 0.65


class Pool:
	var max := 0
	var n := 0
	var pos := PackedVector3Array()
	var vel := PackedVector3Array()
	var tint := PackedColorArray()
	var life := PackedFloat32Array()
	var max_life := PackedFloat32Array()
	var size := PackedFloat32Array()
	var grow := PackedFloat32Array()
	var alpha := PackedFloat32Array()
	var gravity := PackedFloat32Array()
	var drag := PackedFloat32Array()
	var buf := PackedFloat32Array()
	var mm := MultiMesh.new()
	var node := MultiMeshInstance3D.new()

	func _init(count: int, additive: bool, softness: float, parent: Node3D) -> void:
		max = count
		# (Packed arrays are values: each one is resized by name.)
		pos.resize(count)
		vel.resize(count)
		tint.resize(count)
		life.resize(count)
		max_life.resize(count)
		size.resize(count)
		grow.resize(count)
		alpha.resize(count)
		gravity.resize(count)
		drag.resize(count)
		buf.resize(count * 20)
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		mm.mesh = quad
		mm.instance_count = count
		mm.visible_instance_count = 0
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/particle_add.gdshader" if additive else "res://shaders/particle.gdshader")
		m.set_shader_parameter("softness", softness)
		node.multimesh = mm
		node.material_override = m
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.custom_aabb = AABB(Vector3(-1e5, -1e3, -1e5), Vector3(2e5, 2e3, 2e5))
		parent.add_child(node)

	func spawn(p: Vector3, v: Vector3, lf: float, sz: float, col: Color, grw := 0.0, alp := 1.0, grav := 0.0, drg := 0.0) -> void:
		var i := n
		if n < max:
			n += 1
		else:
			i = randi() % max
		pos[i] = p
		vel[i] = v
		tint[i] = col
		life[i] = lf
		max_life[i] = lf
		size[i] = sz
		grow[i] = grw
		alpha[i] = alp
		gravity[i] = grav
		drag[i] = drg

	func clear() -> void:
		n = 0
		mm.visible_instance_count = 0

	func update(dt: float) -> void:
		var i := 0
		while i < n:
			life[i] -= dt
			if life[i] <= 0:
				# Swap-remove: the pool stays packed, only the living get drawn.
				n -= 1
				pos[i] = pos[n]
				vel[i] = vel[n]
				tint[i] = tint[n]
				life[i] = life[n]
				max_life[i] = max_life[n]
				size[i] = size[n]
				grow[i] = grow[n]
				alpha[i] = alpha[n]
				gravity[i] = gravity[n]
				drag[i] = drag[n]
				continue
			var dg := exp(-drag[i] * dt)
			var v := vel[i] * dg
			v.y -= gravity[i] * dt
			vel[i] = v
			var p := pos[i] + v * dt
			pos[i] = p
			var t := 1.0 - life[i] / max_life[i]
			var k := i * 20
			buf[k] = 1.0
			buf[k + 1] = 0.0
			buf[k + 2] = 0.0
			buf[k + 3] = p.x
			buf[k + 4] = 0.0
			buf[k + 5] = 1.0
			buf[k + 6] = 0.0
			buf[k + 7] = p.y
			buf[k + 8] = 0.0
			buf[k + 9] = 0.0
			buf[k + 10] = 1.0
			buf[k + 11] = p.z
			var c := tint[i]
			var inten := maxf(c.r, maxf(c.g, c.b))
			buf[k + 12] = c.r / inten
			buf[k + 13] = c.g / inten
			buf[k + 14] = c.b / inten
			buf[k + 15] = 1.0
			buf[k + 16] = size[i] * (1 + grow[i] * t) * SIZE_TO_METRES
			buf[k + 17] = alpha[i] * (1 - t) * minf(1.0, t * 12 + 0.2)
			buf[k + 18] = inten
			buf[k + 19] = 0.0
			i += 1
		if n > 0:
			mm.buffer = buf
		mm.visible_instance_count = n


var sparks: Pool
var fire: Pool
var smoke: Pool


func _init(parent: Node3D) -> void:
	smoke = Pool.new(700, false, 0.0, parent)
	fire = Pool.new(450, true, 0.0, parent)
	sparks = Pool.new(1000, true, 0.1, parent)
	smoke.node.sorting_offset = -1
	sparks.node.sorting_offset = 1


func spark_burst(x: float, y: float, z: float, count: int, base_vx := 0.0, base_vz := 0.0, spread := 9.0) -> void:
	for i in count:
		var hot := randf()
		sparks.spawn(Vector3(x, y, z),
			Vector3(base_vx + (randf() - 0.5) * spread, randf() * spread * 0.6 + 1, base_vz + (randf() - 0.5) * spread),
			0.25 + randf() * 0.45, 0.09 + randf() * 0.08, Color(4, 1.6 + hot * 1.4, 0.35 * hot), 0.0, 1.0, 14.0, 1.5)


func debris(x: float, y: float, z: float, count: int, vx: float, vz: float) -> void:
	for i in count:
		smoke.spawn(Vector3(x, y, z), Vector3(vx * 0.6 + (randf() - 0.5) * 8, 2 + randf() * 5, vz * 0.6 + (randf() - 0.5) * 8),
			0.9, 0.12, Color(0.12, 0.12, 0.13), 0.0, 1.0, 16.0, 0.6)


func smoke_puff(x: float, y: float, z: float, darkness: float, vx := 0.0, vz := 0.0) -> void:
	var c := 0.55 - darkness * 0.45
	smoke.spawn(Vector3(x + (randf() - 0.5) * 0.4, y, z + (randf() - 0.5) * 0.4),
		Vector3(vx * 0.3 + randf() - 0.5, 1.5 + randf() * 1.5, vz * 0.3 + randf() - 0.5),
		1.4 + randf() * 1.2, 0.8 + randf() * 0.5, Color(c, c * 0.97, c * 0.95), 3.5, 0.5, 0.0, 0.8)


func tyre_smoke(x: float, y: float, z: float) -> void:
	smoke.spawn(Vector3(x, y, z), Vector3((randf() - 0.5) * 0.6, 0.4 + randf() * 0.5, (randf() - 0.5) * 0.6),
		1 + randf() * 0.6, 0.6, Color(0.85, 0.85, 0.88), 4.0, 0.28, 0.0, 1.0)


func flame(x: float, y: float, z: float) -> void:
	fire.spawn(Vector3(x + (randf() - 0.5) * 0.8, y, z + (randf() - 0.5) * 0.8),
		Vector3((randf() - 0.5) * 0.6, 2 + randf() * 2, (randf() - 0.5) * 0.6),
		0.35 + randf() * 0.35, 0.45 + randf() * 0.35, Color(2.2, 0.7 + randf() * 0.5, 0.1), -0.6, 0.7)


func nitro_flame(x: float, y: float, z: float, vx: float, vz: float) -> void:
	fire.spawn(Vector3(x, y, z), Vector3(vx * 0.85, 0, vz * 0.85), 0.12, 0.35, Color(0.6, 1.4, 4.5), -0.5, 0.9)


func clear() -> void:
	sparks.clear()
	fire.clear()
	smoke.clear()


func update(dt: float) -> void:
	sparks.update(dt)
	fire.update(dt)
	smoke.update(dt)
