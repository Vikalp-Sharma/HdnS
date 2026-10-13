## Free-roam spectator camera with auto-tracking director modes.
## WASD to move, mouse to look, Q/E or Space/Shift for up/down.
## F: Track Seeker | G: Track Hider | H: Facility Overview | C: Lock Mouse
class_name FreeCamera
extends Camera3D

@export var base_speed: float = 16.0
@export var sprint_multiplier: float = 2.5
@export var mouse_sensitivity: float = 0.002
@export var smooth_factor: float = 12.0

var _velocity: Vector3 = Vector3.ZERO
var _target_velocity: Vector3 = Vector3.ZERO
var _speed_mult: float = 1.0
var _is_right_clicking: bool = false
var _mouse_captured: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.0

# Tracking Targets
var hider_target: Node3D = null
var seeker_target: Node3D = null
var overview_pos: Vector3 = Vector3.ZERO
var _tracking_mode: int = 0  # 0=free, 1=seeker, 2=hider, 3=overview


func setup_targets(h: Node3D, s: Node3D, ov_pos: Vector3) -> void:
	hider_target = h
	seeker_target = s
	overview_pos = ov_pos


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_mouse_captured = false
	_yaw = rotation.y
	_pitch = rotation.x


func _unhandled_input(event: InputEvent) -> void:
	# Right mouse button to look around
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_is_right_clicking = event.pressed
			if _is_right_clicking:
				_tracking_mode = 0  # Manual control breaks tracking
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_speed_mult = minf(_speed_mult * 1.2, 10.0)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_speed_mult = maxf(_speed_mult / 1.2, 0.1)

	# Mouse look when right-clicking or captured
	if event is InputEventMouseMotion and (_is_right_clicking or _mouse_captured):
		_tracking_mode = 0  # Manual mouse movement breaks tracking
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch -= event.relative.y * mouse_sensitivity
		_pitch = clampf(_pitch, -PI * 0.45, PI * 0.45)
		rotation = Vector3(_pitch, _yaw, 0)

	# Keyboard commands
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_C:
				_mouse_captured = !_mouse_captured
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _mouse_captured else Input.MOUSE_MODE_VISIBLE
			KEY_ESCAPE:
				_mouse_captured = false
				_is_right_clicking = false
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_F:
				_tracking_mode = 1  # Track Seeker
			KEY_G:
				_tracking_mode = 2  # Track Hider
			KEY_H:
				_tracking_mode = 3  # Facility Overview


func _process(delta: float) -> void:
	# Check manual WASD movement input
	var input_dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): input_dir -= transform.basis.z
	if Input.is_key_pressed(KEY_S): input_dir += transform.basis.z
	if Input.is_key_pressed(KEY_A): input_dir -= transform.basis.x
	if Input.is_key_pressed(KEY_D): input_dir += transform.basis.x
	if Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_E): input_dir += Vector3.UP
	if Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_Q): input_dir -= Vector3.UP

	if input_dir.length_squared() > 0.001:
		_tracking_mode = 0  # User moving manually overrides auto-tracking
		input_dir = input_dir.normalized()

	if _tracking_mode != 0:
		_handle_auto_tracking(delta)
	else:
		# Sprint
		var speed := base_speed * _speed_mult
		if Input.is_key_pressed(KEY_CTRL):
			speed *= sprint_multiplier

		_target_velocity = input_dir * speed
		_velocity = _velocity.lerp(_target_velocity, smooth_factor * delta)
		position += _velocity * delta


func _handle_auto_tracking(delta: float) -> void:
	var target_node: Node3D = null
	if _tracking_mode == 1:
		target_node = seeker_target
	elif _tracking_mode == 2:
		target_node = hider_target

	if target_node != null and is_instance_valid(target_node):
		var desired_pos: Vector3 = target_node.global_position + Vector3(0, 8.5, 7.5)
		position = position.lerp(desired_pos, 4.0 * delta)
		var look_target: Vector3 = target_node.global_position + Vector3(0, 1.0, 0)
		var cur_rot := transform.looking_at(look_target, Vector3.UP).basis.get_rotation_quaternion()
		quaternion = quaternion.slerp(cur_rot, 5.0 * delta)
		_pitch = rotation.x
		_yaw = rotation.y
	elif _tracking_mode == 3 and overview_pos != Vector3.ZERO:
		position = position.lerp(overview_pos, 3.5 * delta)
		var look_target := Vector3(overview_pos.x, 0, overview_pos.z - 6.0)
		var cur_rot := transform.looking_at(look_target, Vector3.UP).basis.get_rotation_quaternion()
		quaternion = quaternion.slerp(cur_rot, 4.0 * delta)
		_pitch = rotation.x
		_yaw = rotation.y
