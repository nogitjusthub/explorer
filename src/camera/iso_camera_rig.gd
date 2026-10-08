class_name IsoCameraRig
extends Node3D
## Изометрическая ортокамера (GDD §8): азимут 45°, наклон 45°; ромб тайла — 32 пикселя по ширине
## при рендере 480×320 (по высоте ≈ 23). Машина почти в центре кадра,
## небольшое упреждение по движению, поворот шагом 90° (Q/E) с анимацией 0,3 с.
## Камера следует за интерполированной позицией машины в _process и сдвигается шагом
## в целый пиксель — иначе низкое разрешение «рябит» при движении.

const ELEVATION_DEG := 45.0
const DISTANCE := 60.0
const TILE_PX := 32.0            ## ширина ромба тайла в пикселях рендера
const LEAD := 0.06               ## доля кадра, на которую камера смещается по ходу
const TURN_TIME := 0.3

var target: Vehicle
var camera: Camera3D
var zoom := 1.0                  ## крупность: 2 — вдвое ближе (отладка; пресеты зума — позже)
var turn_enabled := true         ## Q / E поворачивают камеру (выключено, пока открыт экран выбора)

var _quarter := 0
var _shake := 0.0                ## амплитуда тряски, пикселей рендера
var _shake_decay := 0.0          ## пикселей в секунду
var _shake_rng := RandomNumberGenerator.new()
var _yaw := deg_to_rad(45.0)
var _focus := Vector3.ZERO
var _ortho_size := 14.0


func _init() -> void:
	name = "IsoCameraRig"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _ready() -> void:
	# Диагональ тайла (√2 мировых единиц) должна занять TILE_PX пикселей по ширине.
	var render_h := float(ProjectSettings.get_setting("display/window/size/viewport_height", 320))
	_ortho_size = render_h * sqrt(2.0) / TILE_PX / zoom
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = _ortho_size
	camera.near = 1.0
	camera.far = 200.0
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(camera)
	if target != null:
		_focus = target.global_position
	EventBus.camera_shake_requested.connect(shake)
	_update_camera()


## Тряска (землетрясение, удар молнии рядом): strength 1 — смещение до 2 пикселей рендера,
## затухает за seconds. Отключается в настройках.
func shake(strength: float, seconds: float) -> void:
	if not Settings.camera_shake:
		return
	var amp := 2.0 * strength
	if amp > _shake:
		_shake = amp
		_shake_decay = amp / maxf(seconds, 0.05)


## Крупность камеры (экран выбора машины показывает её ближе).
func set_zoom(value: float) -> void:
	zoom = value
	if camera != null:
		var render_h := float(ProjectSettings.get_setting("display/window/size/viewport_height", 320))
		_ortho_size = render_h * sqrt(2.0) / TILE_PX / zoom
		camera.size = _ortho_size


## Сколько раз камера повёрнута на 90° (для отладочного снимка).
func quarter() -> int:
	return _quarter


func _process(dt: float) -> void:
	if turn_enabled and Input.is_action_just_pressed(&"cam_left"):
		_quarter -= 1
		EventBus.camera_rotated.emit(_quarter)
	if turn_enabled and Input.is_action_just_pressed(&"cam_right"):
		_quarter += 1
		EventBus.camera_rotated.emit(_quarter)
	var yaw_target := deg_to_rad(45.0) + _quarter * PI * 0.5
	_yaw = move_toward(_yaw, yaw_target, PI * 0.5 / TURN_TIME * dt)
	_shake = maxf(_shake - _shake_decay * dt, 0.0)

	if target != null:
		var p := target.get_global_transform_interpolated().origin
		var v := target.state.vel
		var lead := Vector3(v.x, 0.0, v.y) / target.cls.max_speed * _ortho_size * LEAD * 2.0
		_focus = _focus.lerp(p + lead, 1.0 - exp(-8.0 * dt))
	_update_camera()


func _update_camera() -> void:
	var el := deg_to_rad(ELEVATION_DEG)
	var dir := Vector3(sin(_yaw) * cos(el), sin(el), cos(_yaw) * cos(el))
	var basis := Basis.looking_at(-dir, Vector3.UP)
	# Привязка к пиксельной сетке в плоскости экрана: статичный мир не «плывёт» между пикселями.
	var pixel := _ortho_size / float(ProjectSettings.get_setting("display/window/size/viewport_height", 320))
	var right := basis.x
	var up := basis.y
	var a := _focus.dot(right)
	var b := _focus.dot(up)
	var snapped := _focus + right * (roundf(a / pixel) * pixel - a) + up * (roundf(b / pixel) * pixel - b)
	if _shake > 0.0:
		# Сдвиг целыми пикселями — картинка дёргается, но не «плывёт».
		snapped += right * roundf(_shake_rng.randf_range(-_shake, _shake)) * pixel \
				+ up * roundf(_shake_rng.randf_range(-_shake, _shake)) * pixel
	camera.global_transform = Transform3D(basis, snapped + dir * DISTANCE)
