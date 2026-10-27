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
	## Pass the velocity to the shader (sparks are drawn as streaks).
	var streaks := false
	## Fire: colour runs from a white-hot core through orange to dark red over the particle's life.
	var fire_ramp := false
	var seeds := PackedFloat32Array()

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
		seeds.resize(count)
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
		seeds[i] = randf()

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
				seeds[i] = seeds[n]
				continue
			var dg := exp(-drag[i] * dt)
			var v := vel[i] * dg
			v.y -= gravity[i] * dt
			vel[i] = v
			var p := pos[i] + v * dt
			pos[i] = p
			var t := 1.0 - life[i] / max_life[i]
			var k := i * 20
			buf[k] = v.x if streaks else 1.0
			buf[k + 1] = 0.0
			buf[k + 2] = 0.0
			buf[k + 3] = p.x
			buf[k + 4] = v.y if streaks else 0.0
			buf[k + 5] = 1.0
			buf[k + 6] = 0.0
			buf[k + 7] = p.y
			buf[k + 8] = v.z if streaks else 0.0
			buf[k + 9] = 0.0
			buf[k + 10] = 1.0
			buf[k + 11] = p.z
			var c := tint[i]
			if fire_ramp:
				# White-yellow core → orange → deep red, dimming as it burns out.
				var age := clampf(t * 1.4, 0.0, 1.0)
				var hot := Color(3.2, 2.4, 1.2).lerp(Color(2.6, 0.9, 0.12), smoothstep(0.0, 0.45, age)).lerp(Color(0.9, 0.12, 0.03), smoothstep(0.45, 1.0, age))
				c = Color(hot.r * c.r / 2.4, hot.g * c.r / 2.4, hot.b * c.r / 2.4)
			var inten := maxf(c.r, maxf(c.g, c.b))
			buf[k + 12] = c.r / inten
			buf[k + 13] = c.g / inten
			buf[k + 14] = c.b / inten
			buf[k + 15] = 1.0
			buf[k + 16] = size[i] * (1 + grow[i] * t) * SIZE_TO_METRES
			buf[k + 17] = alpha[i] * (1 - t) * minf(1.0, t * 12 + 0.2)
			buf[k + 18] = inten
			buf[k + 19] = seeds[i]
			i += 1
		if n > 0:
			mm.buffer = buf
		mm.visible_instance_count = n


var sparks: Pool
var fire: Pool
var smoke: Pool
## Short bright flashes from explosions and big hits.
var _flashes: Array = [] # [OmniLight3D, life]


func _init(parent: Node3D) -> void:
	smoke = Pool.new(900, false, 0.0, parent)
	fire = Pool.new(600, true, 0.0, parent)
	sparks = Pool.new(1400, true, 0.1, parent)
	sparks.streaks = true
	fire.fire_ramp = true
	(fire.node.material_override as ShaderMaterial).set_shader_parameter("turbulence", 1.0)
	(smoke.node.material_override as ShaderMaterial).set_shader_parameter("turbulence", 0.8)
	(sparks.node.material_override as ShaderMaterial).set_shader_parameter("stretch", 0.05)
	smoke.node.sorting_offset = -1
	sparks.node.sorting_offset = 1
	for i in 3:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.6, 0.25)
		l.omni_range = 18.0
		l.light_energy = 0.0
		l.shadow_enabled = false
		l.visible = false
		parent.add_child(l)
		_flashes.append([l, 0.0])


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


## Metal grinding on metal (a rail, another car, a wheel hub on the asphalt): a fountain of sparks, grey
## friction smoke and, when it's really going at it, licks of flame.
func grind(x: float, y: float, z: float, intensity: float, vx: float, vz: float, nx := 0.0, nz := 0.0) -> void:
	var n := 1 + int(intensity * 4.0)
	for i in n:
		var hot := randf()
		sparks.spawn(Vector3(x, y, z),
			Vector3(vx * 0.75 + nx * 2.5 + (randf() - 0.5) * 5, 0.5 + randf() * 3.5, vz * 0.75 + nz * 2.5 + (randf() - 0.5) * 5),
			0.2 + randf() * 0.35, 0.07 + randf() * 0.06, Color(4, 1.4 + hot * 1.6, 0.3 * hot), 0.0, 1.0, 12.0, 1.2)
	if randf() < intensity * 0.5:
		var c := 0.62 + randf() * 0.15
		smoke.spawn(Vector3(x, y, z), Vector3(vx * 0.4 + randf() - 0.5, 0.8 + randf(), vz * 0.4 + randf() - 0.5),
			0.9 + randf() * 0.8, 0.5 + randf() * 0.4, Color(c, c, c * 0.98), 3.0, 0.35, 0.0, 1.4)
	if intensity > 0.45 and randf() < (intensity - 0.45) * 0.9:
		fire.spawn(Vector3(x, y + 0.1, z), Vector3(vx * 0.6, 1.2 + randf() * 1.5, vz * 0.6),
			0.18 + randf() * 0.2, 0.3 + randf() * 0.25, Color(2.6, 0.9 + randf() * 0.5, 0.15), -0.4, 0.8)


## The engine bay is on fire: flames out of the bonnet and thick black smoke.
func engine_fire(x: float, y: float, z: float, vx: float, vz: float, level: float) -> void:
	if randf() < 0.6 * level:
		fire.spawn(Vector3(x + (randf() - 0.5) * 0.7, y, z + (randf() - 0.5) * 0.7),
			Vector3(vx * 0.85 + (randf() - 0.5), 1.8 + randf() * 2, vz * 0.85 + (randf() - 0.5)),
			0.3 + randf() * 0.3, 0.4 + randf() * 0.3, Color(2.4, 0.75 + randf() * 0.5, 0.12), -0.5, 0.75)
	if randf() < 0.5 * level:
		var c := 0.08 + randf() * 0.06
		smoke.spawn(Vector3(x, y + 0.4, z), Vector3(vx * 0.5 + randf() - 0.5, 2.2 + randf() * 1.5, vz * 0.5 + randf() - 0.5),
			1.8 + randf() * 1.4, 0.9 + randf() * 0.5, Color(c, c, c), 3.8, 0.7, 0.0, 0.9)


## A car blowing up: fireball, debris sparks, a column of black smoke and a flash of light.
func explosion(x: float, y: float, z: float, vx: float, vz: float) -> void:
	for i in 70:
		var dir := Vector3(randf() - 0.5, randf() * 0.8, randf() - 0.5).normalized()
		fire.spawn(Vector3(x, y, z) + dir * 0.5, Vector3(vx * 0.5, 0, vz * 0.5) + dir * (4 + randf() * 7),
			0.45 + randf() * 0.5, 0.8 + randf() * 0.9, Color(3.0, 1.0 + randf() * 0.7, 0.2), 1.2, 0.9, -2.0, 2.2)
	for i in 40:
		var c := 0.06 + randf() * 0.08
		smoke.spawn(Vector3(x + (randf() - 0.5) * 2, y + randf(), z + (randf() - 0.5) * 2),
			Vector3(vx * 0.3 + (randf() - 0.5) * 4, 3 + randf() * 5, vz * 0.3 + (randf() - 0.5) * 4),
			2.5 + randf() * 2, 1.4 + randf() * 1.2, Color(c, c * 0.95, c * 0.9), 4.0, 0.85, -0.5, 1.0)
	spark_burst(x, y, z, 90, vx * 0.5, vz * 0.5, 22)
	flash(x, y + 1.0, z, 9.0)


## Broken glass: a glittering spray.
func glass_burst(x: float, y: float, z: float, vx: float, vz: float, count: int) -> void:
	for i in count:
		sparks.spawn(Vector3(x, y, z), Vector3(vx * 0.6 + (randf() - 0.5) * 7, 1 + randf() * 4, vz * 0.6 + (randf() - 0.5) * 7),
			0.5 + randf() * 0.5, 0.05 + randf() * 0.04, Color(1.6, 1.9, 2.2), 0.0, 0.9, 16.0, 1.0)


func flash(x: float, y: float, z: float, energy: float) -> void:
	var best: Array = _flashes[0]
	for f in _flashes:
		if f[1] <= 0.0:
			best = f
			break
	var l: OmniLight3D = best[0]
	l.position = Vector3(x, y, z)
	l.light_energy = energy
	l.visible = true
	best[1] = 0.35


func clear() -> void:
	sparks.clear()
	fire.clear()
	smoke.clear()


func update(dt: float) -> void:
	sparks.update(dt)
	fire.update(dt)
	smoke.update(dt)
	for f in _flashes:
		if f[1] <= 0.0:
			continue
		f[1] -= dt
		var l: OmniLight3D = f[0]
		l.light_energy *= exp(-9.0 * dt)
		if f[1] <= 0.0:
			l.visible = false
