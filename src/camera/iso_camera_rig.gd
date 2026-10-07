class_name IsoCameraRig
extends Node3D
## Изометрическая ортокамера (GDD §8): азимут 45°, наклон 33°, машина почти в центре кадра,
## небольшое упреждение по движению, поворот шагом 90° (Q/E) с анимацией 0,3 с.
## Камера следует за интерполированной позицией машины в _process, сама не интерполируется.

const ELEVATION_DEG := 33.0
const DISTANCE := 60.0
const ORTHO_SIZE := 13.0
const LEAD := 0.06               ## доля размера кадра, на которую камера смещается по ходу
const TURN_TIME := 0.3

var target: Vehicle
var camera: Camera3D

var _quarter := 0
var _yaw := deg_to_rad(45.0)
var _focus := Vector3.ZERO


func _init() -> void:
	name = "IsoCameraRig"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _ready() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = ORTHO_SIZE
	camera.near = 1.0
	camera.far = 200.0
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(camera)
	if target != null:
		_focus = target.global_position
	_update_camera()


func _process(dt: float) -> void:
	if Input.is_action_just_pressed(&"cam_left"):
		_quarter -= 1
		EventBus.camera_rotated.emit(_quarter)
	if Input.is_action_just_pressed(&"cam_right"):
		_quarter += 1
		EventBus.camera_rotated.emit(_quarter)
	var yaw_target := deg_to_rad(45.0) + _quarter * PI * 0.5
	_yaw = move_toward(_yaw, yaw_target, PI * 0.5 / TURN_TIME * dt)

	if target != null:
		var p := target.get_global_transform_interpolated().origin
		var v := target.state.vel
		var lead := Vector3(v.x, 0.0, v.y) / target.cls.max_speed * ORTHO_SIZE * LEAD * 2.0
		_focus = _focus.lerp(p + lead, 1.0 - exp(-8.0 * dt))
	_update_camera()


func _update_camera() -> void:
	var el := deg_to_rad(ELEVATION_DEG)
	var dir := Vector3(sin(_yaw) * cos(el), sin(el), cos(_yaw) * cos(el))
	camera.global_position = _focus + dir * DISTANCE
	camera.look_at(_focus, Vector3.UP)
