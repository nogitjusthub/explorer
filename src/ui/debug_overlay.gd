class_name DebugOverlay
extends CanvasLayer
## Отладочная информация (F3 — показать/скрыть): FPS, время задач, чанки, позиция, скорость.

var run_seed: int
var vehicle: Vehicle
var streamer: WorldStreamer
var scheduler: JobScheduler
var query: TerrainQuery

var _label: Label
var _timer := 0.0


func _ready() -> void:
	layer = 10
	_label = Label.new()
	_label.position = Vector2(4, 40)   # под панелью HUD
	_label.add_theme_font_size_override(&"font_size", 8)
	_label.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override(&"shadow_offset_x", 1)
	_label.add_theme_constant_override(&"shadow_offset_y", 1)
	add_child(_label)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_F3:
		visible = not visible


func _process(dt: float) -> void:
	_timer -= dt
	if _timer > 0.0 or not visible:
		return
	_timer = 0.25
	var s := vehicle.state
	var tier := query.surface_tier(s.pos.x, s.pos.y)
	_label.text = "FPS %d   задачи %.1f мс (макс %.1f)   в очереди %d\nseed %d   чанки %d (генерация %d)%s\npos %.1f, %.1f   ярус %.1f   тайл %s\nскорость %.1f / %.1f   подъём %d%s" % [
		Engine.get_frames_per_second(), scheduler.last_frame_usec / 1000.0, scheduler.max_frame_usec / 1000.0,
		scheduler.pending(), run_seed, streamer.loaded_count(), streamer.generating_count(),
		"" if OS.has_feature("web") else "   F12 — снимок",
		s.pos.x, s.pos.y, tier, s.tile, s.vel.length(), vehicle.cls.max_speed, s.uphill_tiles,
		"   ПАДЕНИЕ" if s.falling else ""]
