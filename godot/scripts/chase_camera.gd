class_name ChaseCamera
extends RefCounted
## Spring-damped chase cam with impact shake and a wider FOV on nitro. Port of src/game/ChaseCamera.ts.

var camera := Camera3D.new()
var _pos := Vector3.ZERO
var _look := Vector3.ZERO
var _yaw := 0.0
var _shake := 0.0
var _initialized := false
## Held by the player: look over the rear bumper.
var look_back := false
var _was_looking_back := false


func _init() -> void:
	camera.fov = Config.T.camFov
	camera.near = 0.3
	camera.far = 2800.0 # fog ends at 2600


func add_shake(amount: float) -> void:
	_shake = minf(1.2, _shake + amount)


func snap() -> void:
	_initialized = false


func update(v: Vehicle, dt: float, time: float) -> void:
	var T := Config.T
	# Follow the direction of travel rather than the nose, so drifts show the car sideways.
	var spd := v.speed
	var vel_yaw := atan2(v.vx, v.vz) if spd > 4 and v.forward_speed > 0 else v.heading
	var diff := wrapf(vel_yaw - v.heading, -PI, PI)
	var target_yaw := v.heading + diff * 0.55
	if not _initialized:
		_yaw = target_yaw
	_yaw += wrapf(target_yaw - _yaw, -PI, PI) * minf(1.0, dt * 3.5)

	var speed_t := minf(1.0, spd / 70.0)
	var dist: float = T.camDistance + speed_t * 1.4
	var height: float = T.camHeight + speed_t * 0.3
	# Looking back: the same rig turned around, a little closer so the car stays out of the way.
	var back := look_back
	var cam_yaw := v.heading + PI if back else _yaw
	var fx := sin(cam_yaw)
	var fz := cos(cam_yaw)
	var cam_dist := dist * 0.8 if back else dist
	var target := Vector3(v.x - fx * cam_dist, v.y + height, v.z - fz * cam_dist)
	var look_target := Vector3(v.x + fx * 6, v.y + 1.1, v.z + fz * 6)

	# Cut, don't swing, when switching between forward and backward views.
	if back != _was_looking_back:
		_was_looking_back = back
		_initialized = false
	if not _initialized:
		_pos = target
		_look = look_target
		_initialized = true
	_pos = _pos.lerp(target, minf(1.0, dt * 6))
	_pos.y += (target.y - _pos.y) * minf(1.0, dt * 4)
	_look = _look.lerp(look_target, minf(1.0, dt * 14))

	var p := _pos
	if _shake > 0.001:
		var s := _shake * _shake * 0.35
		p.x += (sin(time * 71) + sin(time * 37)) * s
		p.y += sin(time * 53) * s
		_shake *= exp(-dt * 6)
	camera.look_at_from_position(p, _look)

	var fov: float = T.camFovNitro if v.nitro_active else T.camFov + speed_t * 6
	camera.fov += (fov - camera.fov) * minf(1.0, dt * 4)
