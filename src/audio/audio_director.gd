class_name AudioDirector
extends Node
## Звуки событий (GDD §9): молния — треск телеграфа и гром, землетрясение — нарастающий гул и раскат
## при толчке, урон — удар по корпусу. Громкость падает с расстоянием до машины. Слушает EventBus;
## двигатель машины звучит сам (EngineSound).

const VOICES := 6
const HEAR_TILES := 30.0               ## дальше — не слышно

var vehicle: Vehicle

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _crackle: AudioStreamWAV
var _thunder: AudioStreamWAV
var _hit: AudioStreamWAV
var _rumble_build: AudioStreamWAV
var _rumble_hit: AudioStreamWAV
var _quake_heard := false              ## гул телеграфа текущего землетрясения уже запущен


func _ready() -> void:
	name = "AudioDirector"
	_crackle = Sfx.crackle(1.2)
	_thunder = Sfx.thunder(2.2)
	_hit = Sfx.hit(0.3)
	_rumble_build = Sfx.rumble(2.5, true)
	_rumble_hit = Sfx.rumble(2.4, false)
	for _i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	EventBus.threat_telegraphed.connect(_on_telegraphed)
	EventBus.lightning_struck.connect(_on_lightning)
	EventBus.threat_ended.connect(_on_threat_ended)
	EventBus.vehicle_damaged.connect(func(_amount: int, _source: StringName, _at: Vector3) -> void: _play(_hit, -4.0))


func _on_telegraphed(kind: StringName, at: Vector3, _seconds: float, _dir: Vector2) -> void:
	if kind == &"lightning":
		_play_at(_crackle, at, -8.0)
	elif kind == &"quake" and not _quake_heard:
		_quake_heard = true
		_play(_rumble_build, -2.0)


func _on_threat_ended(kind: StringName) -> void:
	if kind == &"quake":
		_quake_heard = false
		_play(_rumble_hit, 2.0)


func _on_lightning(at: Vector3) -> void:
	_play_at(_thunder, at, 0.0, 0.85 + 0.3 * fmod(at.x * 0.37 + at.z * 0.61, 1.0))


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
