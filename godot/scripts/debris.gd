class_name Debris
extends RefCounted
## Bits that came off cars: bumpers, mirrors, spoilers, exhausts, a whole front wheel, and shards of
## bodywork. They tumble through the air, bounce on the road, slide to a stop and lie there for a while.
## Drive into one and it gets kicked on, with sparks.

const MAX := 80
const LIFE := 16.0
const GRAVITY := 18.0


class Piece:
	var node: Node3D
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var rot := Basis()
	var spin := Vector3.ZERO
	var life := 0.0
	var radius := 0.25
	var wheel := false
	var hint := -1
	var kicked := -9.0


var _parent: Node3D
var _track: Track
var _pieces: Array = []
var _proj := Track.Proj.new()
var _shard_mesh: BoxMesh
var _shard_mats := {}
var _time := 0.0
## Called when a car kicks a piece: (position, strength).
var on_kick: Callable


func _init(parent: Node3D, track: Track) -> void:
	_parent = parent
	_track = track
	_shard_mesh = BoxMesh.new()
	_shard_mesh.size = Vector3(0.34, 0.03, 0.22)


func clear() -> void:
	for p: Piece in _pieces:
		p.node.queue_free()
	_pieces.clear()


func _add(node: Node3D, pos: Vector3, vel: Vector3, radius: float, wheel := false) -> Piece:
	if _pieces.size() >= MAX:
		var old: Piece = _pieces.pop_front()
		old.node.queue_free()
	var p := Piece.new()
	p.node = node
	p.pos = pos
	p.vel = vel
	p.radius = radius
	p.wheel = wheel
	p.rot = node.transform.basis.orthonormalized()
	p.spin = Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * (16.0 if not wheel else 6.0)
	_parent.add_child(node)
	_pieces.append(p)
	return p


## A loose part of a car breaks off and flies away from the car.
func spawn_part(model: CarModel, index: int, v: Vehicle, strength: float) -> void:
	var info := model.loose_part(index)
	var mesh: Mesh = info.mesh
	if mesh == null:
		return
	var body_xf: Transform3D = model.body.global_transform
	var centre: Vector3 = info.centre
	var holder := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = -centre
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mats: Dictionary = info.mats
	for si in mesh.get_surface_count():
		var src := mesh.surface_get_material(si)
		if mats.has(src):
			mi.set_surface_override_material(si, mats[src])
	holder.add_child(mi)
	var world := body_xf * centre
	holder.transform = Transform3D(body_xf.basis.orthonormalized(), world)
	var out := Vector3(world.x - v.x, 0, world.z - v.z)
	out = out.normalized() if out.length() > 0.05 else Vector3(randf() - 0.5, 0, randf() - 0.5).normalized()
	var kick := 3.0 + minf(9.0, strength * 0.35)
	var vel := Vector3(v.vx, 0, v.vz) * 0.85 + out * kick + Vector3(0, 3.0 + randf() * 3.0 + strength * 0.08, 0)
	var size := mesh.get_aabb().size
	_add(holder, world, vel, clampf(minf(size.x, minf(size.y, size.z)) * 0.5 + 0.05, 0.05, 0.35))


## A front wheel comes off and rolls away on its own.
func spawn_wheel(info: Dictionary, v: Vehicle, side: float) -> void:
	var holder := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = info.mesh
	holder.add_child(mi)
	var xf: Transform3D = info.xf
	holder.transform = xf
	var fx := sin(v.heading)
	var fz := cos(v.heading)
	# Out to its own side (right = (-fz, fx)), carried along with the car.
	var out := Vector3(-fz, 0, fx) * side
	var vel := Vector3(v.vx, 0, v.vz) * 0.95 + out * 5.0 + Vector3(0, 4.0, 0)
	var p := _add(holder, xf.origin, vel, 0.32, true)
	p.life = -6.0 # a wheel rolling down the road is worth watching a bit longer


## Shards of bodywork in the car's colour.
func spawn_shards(at: Vector3, vel: Vector3, color: Color, count: int) -> void:
	var key := color.to_html(false)
	var m: StandardMaterial3D = _shard_mats.get(key)
	if m == null:
		m = StandardMaterial3D.new()
		m.albedo_color = color
		m.metallic = 0.5
		m.roughness = 0.35
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_shard_mats[key] = m
	for i in count:
		var mi := MeshInstance3D.new()
		mi.mesh = _shard_mesh
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sc := 0.5 + randf() * 1.1
		mi.scale = Vector3(sc, 1, sc * (0.6 + randf() * 0.8))
		var holder := Node3D.new()
		holder.add_child(mi)
		holder.position = at
		var v := vel * 0.7 + Vector3((randf() - 0.5) * 9, 2 + randf() * 6, (randf() - 0.5) * 9)
		var p := _add(holder, at, v, 0.04)
		p.life = 6.0


func _ground(p: Piece) -> float:
	_track.project(p.pos.x, p.pos.z, p.hint, _proj)
	p.hint = _proj.idx
	var ad := absf(_proj.d)
	var h := _track.height_at(_proj.s)
	if ad < Config.PAVED:
		return h
	if ad < Config.VERGE_OUT:
		return h - 0.06
	# Down the embankment to the fields.
	return maxf(0.0, h * (1.0 - (ad - Config.VERGE_OUT) / (2.5 + h * 1.8)))


func update(dt: float, cars: Array, player: Vehicle) -> void:
	_time += dt
	var i := 0
	while i < _pieces.size():
		var p: Piece = _pieces[i]
		p.life += dt
		var far := Vector2(p.pos.x - player.x, p.pos.z - player.z).length_squared() > 450.0 * 450.0
		if p.life > LIFE or far:
			p.node.queue_free()
			_pieces.remove_at(i)
			continue
		p.vel.y -= GRAVITY * dt
		p.pos += p.vel * dt
		var g := _ground(p) + p.radius
		if p.pos.y < g:
			p.pos.y = g
			if p.vel.y < -2.5:
				# Bounce, losing most of it, and tumble less.
				p.vel.y = -p.vel.y * (0.42 if p.wheel else 0.3)
				p.vel.x *= 0.82
				p.vel.z *= 0.82
				p.spin *= 0.65
			else:
				p.vel.y = 0.0
				var fr := exp(-(0.4 if p.wheel else 2.6) * dt)
				p.vel.x *= fr
				p.vel.z *= fr
				if p.wheel:
					# Rolling: spin about its axle at the speed it moves.
					var spd := Vector2(p.vel.x, p.vel.z).length()
					p.spin = p.rot.x * (spd / 0.32)
				else:
					p.spin *= exp(-5.0 * dt)
					# Settle flat: ease towards lying on the road.
					var up := p.rot.y
					var target := Basis(Quaternion(up, Vector3.UP if up.y >= 0 else Vector3.DOWN)) * p.rot
					p.rot = p.rot.slerp(target.orthonormalized(), minf(1.0, dt * 3.0))
		var w := p.spin.length()
		if w > 0.001:
			p.rot = (Basis(p.spin / w, w * dt) * p.rot).orthonormalized()
		# Kicked by a car driving into it.
		if p.pos.y - g < 0.6 and _time - p.kicked > 0.4:
			for v: Vehicle in cars:
				if not v.active:
					continue
				var dx := p.pos.x - v.x
				var dz := p.pos.z - v.z
				if dx * dx + dz * dz > (v.half_l + 0.4) * (v.half_l + 0.4):
					continue
				var fx := sin(v.heading)
				var fz := cos(v.heading)
				if absf(dx * -fz + dz * fx) > v.half_w + 0.3:
					continue
				var spd := v.speed
				if spd < 3:
					continue
				p.kicked = _time
				p.vel = Vector3(v.vx, 0, v.vz) * 1.12 + Vector3((randf() - 0.5) * 6, 2.5 + spd * 0.08, (randf() - 0.5) * 6)
				p.spin = Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 18.0
				if on_kick.is_valid():
					on_kick.call(p.pos, spd)
				break
		var fade := clampf((LIFE - p.life) / 1.5, 0.0, 1.0)
		p.node.transform = Transform3D(p.rot.scaled(Vector3.ONE * fade), p.pos)
		i += 1
