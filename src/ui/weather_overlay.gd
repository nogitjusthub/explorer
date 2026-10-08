class_name WeatherOverlay
extends CanvasLayer
## Частицы погоды на весь экран — поверх картинки, под HUD: косой дождь под грозой и пыль по ветру
## в пылевой буре. Сила — из weather_changed (насколько машина внутри), направление пыли — ветер
## бури, повёрнутый в экранные координаты (как радар и управление).

const VIEW := Vector2(480, 320)

var camera: Camera3D

var _rain: CPUParticles2D
var _dust: CPUParticles2D
var _rain_k := 0.0
var _dust_k := 0.0
var _wind := Vector2.RIGHT


func _ready() -> void:
	layer = 4
	name = "WeatherOverlay"
	_rain = _particles(_streak(Color(0.75, 0.82, 1.0, 0.55), 7), 260, 0.55, Vector2(-0.22, 1.0), 430.0, 540.0)
	_dust = _particles(_streak(Color(0.82, 0.64, 0.46, 0.6), 5), 240, 1.1, Vector2.RIGHT, 260.0, 420.0)
	EventBus.weather_changed.connect(_on_weather)
	EventBus.wind_changed.connect(func(dir: Vector2, _strength: float) -> void: _wind = dir)


func _on_weather(kind: StringName, intensity: float) -> void:
	match kind:
		&"storm":
			_rain_k = intensity
		&"dust":
			_dust_k = intensity
		&"fog", &"acid":
			_dust_k = 0.0


func _process(_dt: float) -> void:
	_rain.emitting = _rain_k > 0.05
	_rain.modulate.a = _rain_k
	_dust.emitting = _dust_k > 0.05
	_dust.modulate.a = _dust_k
	if camera != null and _dust.emitting:
		var b := camera.global_transform.basis
		var right := Vector2(b.x.x, b.x.z).normalized()
		var up := Vector2(-b.z.x, -b.z.z).normalized()
		var s := Vector2(_wind.dot(right), -_wind.dot(up))
		if s.length() > 0.01:
			_dust.direction = s.normalized()


## Источник частиц на весь экран (с запасом за краями — поток не начинается с пустой полосы).
func _particles(texture: Texture2D, amount: int, lifetime: float, direction: Vector2, v_min: float, v_max: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = texture
	p.amount = amount
	p.lifetime = lifetime
	p.position = VIEW * 0.5
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = VIEW * 0.75
	p.direction = direction.normalized()
	p.spread = 4.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = v_min
	p.initial_velocity_max = v_max
	p.particle_flag_align_y = true
	p.emitting = false
	add_child(p)
	return p


## Штрих в пиксель шириной.
static func _streak(color: Color, length: int) -> Texture2D:
	var img := Image.create(1, length, false, Image.FORMAT_RGBA8)
	for y in length:
		img.set_pixel(0, y, Color(color, color.a * (0.5 + 0.5 * y / float(length - 1))))
	return ImageTexture.create_from_image(img)
