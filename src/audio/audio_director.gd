class_name AudioDirector
extends Node
## Звуки событий (GDD §9): молния — треск телеграфа и гром, землетрясение — нарастающий гул и раскат
## при толчке, урон — удар по корпусу, разряд по машине — гудение помех. Громкость падает с расстоянием до машины. Слушает EventBus;
## двигатель машины звучит сам (EngineSound).

const VOICES := 6
const HEAR_TILES := 30.0               ## дальше — не слышно
const THUNDER_SPEED := 30.0            ## тайлов в секунду — гром приходит позже вспышки

var vehicle: Vehicle

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _crackle: AudioStreamWAV
var _thunder: AudioStreamWAV
var _hit: AudioStreamWAV
var _rumble_build: AudioStreamWAV
var _rumble_hit: AudioStreamWAV
var _quake_heard := false              ## гул телеграфа текущего землетрясения уже запущен
var _squeal: AudioStreamWAV
var _buzz: AudioStreamWAV


func _ready() -> void:
	name = "AudioDirector"
	_crackle = Sfx.crackle(1.2)
	_thunder = Sfx.thunder(2.2)
	_hit = Sfx.hit(0.3)
	_rumble_build = Sfx.rumble(2.5, true)
	_rumble_hit = Sfx.rumble(2.4, false)
	Sfx.wind_loop(2.0)        # гул смерча — в кэш заранее, иначе первый смерч дёрнет кадр
	_squeal = Sfx.squeal(0.6)
	_buzz = Sfx.buzz(1.2)
	for _i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	EventBus.threat_telegraphed.connect(_on_telegraphed)
	EventBus.lightning_struck.connect(_on_lightning)
	EventBus.sheet_lightning.connect(func(at: Vector3) -> void: _delayed(_thunder, at, -10.0, 0.7))
	EventBus.threat_ended.connect(_on_threat_ended)
	EventBus.fauna_alerted.connect(_on_fauna_alerted)
	EventBus.drop_landed.connect(_on_drop_landed)
	EventBus.vehicle_damaged.connect(func(_amount: int, _source: StringName, _at: Vector3) -> void: _play(_hit, -4.0))
	EventBus.controls_inverted.connect(func(_seconds: float) -> void: _play(_buzz, -8.0))


func _on_telegraphed(kind: StringName, at: Vector3, _seconds: float, _dir: Vector2) -> void:
	if kind == &"lightning":
		_play_at(_crackle, at, -8.0)
	elif kind == &"quake" and not _quake_heard:
		_quake_heard = true
		_play(_rumble_build, -2.0)


## Посадка капсулы десанта — глухой удар опор о грунт и короткий гул.
func _on_drop_landed(_at: Vector3) -> void:
	_play(_hit, 4.0, 0.55)
	_play(_rumble_hit, -6.0, 1.1)


## Фауна: визг стаи скакунов, гул червя под песком и раскат его броска, бульканье и шлепок прыжка
## илозуба, гул и удар Нессы, треск разряда троеглазки.
func _on_fauna_alerted(kind: StringName, at: Vector3) -> void:
	match kind:
		&"hopper":
			_play_at(_squeal, at, -6.0, 0.9 + 0.2 * fmod(absf(at.x * 0.13), 1.0))
		&"worm":
			_play_at(_rumble_build, at, -4.0, 0.7)
		&"worm_strike":
			_play_at(_rumble_hit, at, 2.0, 0.75)
		&"shark":
			_play_at(_rumble_build, at, -10.0, 1.5)  # илозуб учуял машину — бульканье в зыбуне
		&"shark_leap":
			_play_at(_hit, at, -6.0, 1.7)            # выпрыгнул — шлепок
		&"nessie":
			_play_at(_rumble_build, at, -4.0, 0.6)   # Несса выныривает — низкий гул
		&"nessie_strike":
			_play_at(_rumble_hit, at, 0.0, 1.2)      # шея падает — удар и всплеск
		&"ray_shock":
			_play_at(_crackle, at, -4.0, 2.2)      # разряд троеглазки — короткий треск


func _on_threat_ended(kind: StringName) -> void:
	if kind == &"quake":
		_quake_heard = false
		_play(_rumble_hit, 2.0)


## Гром запаздывает: чем дальше удар, тем позже (звук «медленнее» вспышки).
func _on_lightning(at: Vector3) -> void:
	_delayed(_thunder, at, 0.0, 0.85 + 0.3 * fmod(at.x * 0.37 + at.z * 0.61, 1.0))


func _delayed(stream: AudioStream, at: Vector3, volume_db: float, pitch: float) -> void:
	if vehicle == null:
		return
	var delay := Vector2(at.x, at.z).distance_to(vehicle.state.pos) / THUNDER_SPEED
	if delay < 0.05:
		_play_at(stream, at, volume_db, pitch)
	else:
		get_tree().create_timer(delay).timeout.connect(func() -> void: _play_at(stream, at, volume_db, pitch))


func _play_at(stream: AudioStream, at: Vector3, volume_db: float, pitch: float = 1.0) -> void:
	if vehicle == null:
		return
	var d := Vector2(at.x, at.z).distance_to(vehicle.state.pos)
	if d > HEAR_TILES:
		return
	_play(stream, volume_db + linear_to_db(clampf(1.0 - d / HEAR_TILES, 0.05, 1.0)), pitch)


func _play(stream: AudioStream, volume_db: float, pitch: float = 1.0) -> void:
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()
