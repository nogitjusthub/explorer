class_name AudioDirector
extends Node
## Звуки событий (GDD §9): молния — треск телеграфа и гром, землетрясение — нарастающий гул и раскат
## при толчке, урон — удар по корпусу, разряд по машине — гудение помех. Громкость падает с расстоянием до машины. Слушает EventBus;
## двигатель машины звучит сам (EngineSound).
## Звуки синтезируются заранее, порциями — не дольше SYNTH_BUDGET_USEC за кадр, пока игрок в трюме
## (Sfx.prepare, Sfx.pump), а не на старте: в браузере все сразу — почти секунда чёрного экрана, а даже
## один звук целиком за кадр — заметная запинка. Порядок — какой вероятнее понадобится раньше;
## понадобился до очереди — досинтезируется сразу (Sfx.named). Синтезированные живут всю сессию.

const VOICES := 6
const HEAR_TILES := 30.0               ## дальше — не слышно (гром, гул землетрясения)
const FAUNA_HEAR_TILES := 14.0         ## звуки фауны — чуть дальше края экрана (~8 тайлов от машины)
const THUNDER_SPEED := 30.0            ## тайлов в секунду — гром приходит позже вспышки
const SHUTTLE_HEAR_TILES := 45.0       ## челнок слышно издалека — прилёт к площадке за краем экрана
const SYNTH_BUDGET_USEC := 3000        ## фоновый синтез звуков за кадр, мкс
const SOUNDS: Array[StringName] = [&"hit", &"rumble_hit", &"pager", &"chime", &"crackle", &"thunder", &"screech",
		&"buzz", &"rumble_build", &"dust", &"wind", &"bellow", &"bellow_low", &"stomp", &"thrust", &"tractor",
		&"howl", &"ground_hum"]
const DUST_DB := -6.0                  ## гул пылевой бури в массе; вдали — тише (lerp от 0,12 по амплитуде)

var vehicle: Vehicle

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _quake_heard := false              ## гул телеграфа текущего землетрясения уже запущен
var _dust_wind: AudioStreamPlayer      ## гул пылевой бури — петля ветра, громкость по плотности у машины
var _dust_level := 0.0                 ## плотность пылевой бури у машины (последний weather_changed)


func _ready() -> void:
	name = "AudioDirector"
	Sfx.prepare(SOUNDS)
	for _i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	EventBus.threat_telegraphed.connect(_on_telegraphed)
	EventBus.lightning_struck.connect(_on_lightning)
	EventBus.sheet_lightning.connect(func(at: Vector3) -> void: _delayed(_sfx(&"thunder"), at, -10.0, 0.7))
	EventBus.threat_ended.connect(_on_threat_ended)
	EventBus.fauna_alerted.connect(_on_fauna_alerted)
	EventBus.drop_landed.connect(_on_drop_landed)
	EventBus.shuttle_sound.connect(_on_shuttle_sound)
	EventBus.pickup_collected.connect(_on_pickup)
	EventBus.weather_changed.connect(_on_weather)
	_dust_wind = AudioStreamPlayer.new()
	add_child(_dust_wind)
	EventBus.pager_alert.connect(func(_kind: StringName) -> void: _play(_sfx(&"pager"), -17.0))
	EventBus.vehicle_damaged.connect(func(_amount: int, _source: StringName, _at: Vector3) -> void: _play(_sfx(&"hit"), -4.0))
	EventBus.controls_inverted.connect(func(_seconds: float) -> void: _play(_sfx(&"buzz"), -8.0))


## Фоновый синтез звуков (свои и чужие — люк трюма, гул угроз): очередь общая, в Sfx.
func _process(_dt: float) -> void:
	Sfx.pump(SYNTH_BUDGET_USEC)


func _sfx(key: StringName) -> AudioStreamWAV:
	return Sfx.named(key)


func _on_telegraphed(kind: StringName, at: Vector3, _seconds: float, _dir: Vector2) -> void:
	if kind == &"lightning":
		_play_at(_sfx(&"crackle"), at, -8.0)
	elif kind == &"quake" and not _quake_heard:
		_quake_heard = true
		_play(_sfx(&"rumble_build"), -2.0)
	elif kind == &"dust" and not _dust_wind.playing and is_inside_tree():
		# Буря идёт (её телеграф — каждый кадр, пока она не кончилась): гул. Включает его только
		# телеграф — сводка плотности (weather_changed) лишь задаёт громкость и после конца бури
		# (threat_ended) гул не воскрешает.
		_dust_wind.stream = _sfx(&"dust")
		_dust_wind.volume_db = _dust_db(_dust_level)
		_dust_wind.play()


## Посадка капсулы десанта — глухой удар опор о грунт и короткий гул.
func _on_drop_landed(_at: Vector3) -> void:
	_play(_sfx(&"hit"), 4.0, 0.55)
	_play(_sfx(&"rumble_hit"), -6.0, 1.1)


## Фауна: крик стаи скакунов, гул червя под песком и раскат его броска, мычание и топот панцирника,
## бульканье и шлепок прыжка илозуба, гул и удар Нессы, треск разряда троеглазки; таран зверя машиной —
## глухой удар.
func _on_fauna_alerted(kind: StringName, at: Vector3) -> void:
	match kind:
		&"rammed":
			_play_at(_sfx(&"hit"), at, -2.0, 0.7, FAUNA_HEAR_TILES)
		&"hopper":
			_play_at(_sfx(&"screech"), at, -6.0, 0.9 + 0.2 * fmod(absf(at.x * 0.13), 1.0), FAUNA_HEAR_TILES)
		&"worm":
			_play_at(_sfx(&"rumble_build"), at, -4.0, 0.7, FAUNA_HEAR_TILES)
		&"worm_strike":
			_play_at(_sfx(&"rumble_hit"), at, 2.0, 0.75, FAUNA_HEAR_TILES)
		&"shark":
			_play_at(_sfx(&"rumble_build"), at, -10.0, 1.5, FAUNA_HEAR_TILES)  # илозуб учуял машину — бульканье в зыбуне
		&"shark_leap":
			_play_at(_sfx(&"hit"), at, -6.0, 1.7, FAUNA_HEAR_TILES)            # выпрыгнул — шлепок
		&"nessie":
			_play_at(_sfx(&"rumble_build"), at, -4.0, 0.6, FAUNA_HEAR_TILES)   # Несса выныривает — низкий гул
		&"nessie_strike":
			_play_at(_sfx(&"rumble_hit"), at, 0.0, 1.2, FAUNA_HEAR_TILES)      # шея падает — удар и всплеск
		&"shellback":
			_play_at(_sfx(&"bellow"), at, -13.0, 0.95, FAUNA_HEAR_TILES)   # панцирник услышал машину — короткое мычание
		&"shellback_dig":
			_play_at(_sfx(&"bellow_low"), at, -8.0, 0.75, FAUNA_HEAR_TILES)   # роет перед рывком — рёв на октаву ниже
		&"shellback_charge":
			_play_at(_sfx(&"stomp"), at, -8.0, 0.9, FAUNA_HEAR_TILES)      # рывок — ровный затухающий топот
		&"ray_shock":
			_play_at(_sfx(&"crackle"), at, -4.0, 2.2, FAUNA_HEAR_TILES)        # разряд троеглазки — короткий треск


## Челноки: спуск и взлёт — реактивный рёв, как у капсулы десанта (у аварийного выше); спуск начинается
## так, чтобы рёв кончился в момент касания. Касание — глухой удар и гул, как у капсулы. Эвакуация —
## луч захвата.
func _on_shuttle_sound(event: StringName, at: Vector3, small: bool, seconds: float) -> void:
	var pitch := 1.15 if small else 1.0
	var volume := -3.0 if small else 0.0
	match event:
		&"descend":
			_play_at(_sfx(&"thrust"), at, volume, pitch, SHUTTLE_HEAR_TILES, maxf(Sfx.THRUST_S - seconds * pitch, 0.0))
		&"land":
			_play_at(_sfx(&"hit"), at, volume + 4.0, 0.55 * pitch, SHUTTLE_HEAR_TILES)
			_play_at(_sfx(&"rumble_hit"), at, volume - 6.0, 1.1 * pitch, SHUTTLE_HEAR_TILES)
		&"ascend":
			_play_at(_sfx(&"thrust"), at, volume, pitch, SHUTTLE_HEAR_TILES)
		&"tractor":
			_play_at(_sfx(&"tractor"), at, volume - 15.0, 1.0, SHUTTLE_HEAR_TILES)


## Подбор: кристалл — «дзынь», остальной груз — то же ниже, топливо и ремкомплект — ещё ниже.
func _on_pickup(kind: StringName, _value: int) -> void:
	var pitch: float = {&"crystal": 1.0, &"sample": 0.89, &"core": 0.79}.get(kind, 0.67)
	_play(_sfx(&"chime"), -10.0, pitch)


## Пылевая буря гудит, пока идёт: фронт вдали — едва слышно, машина в массе — в полную силу (ровный
## гул без нарастаний). Гул включает телеграф бури (_on_telegraphed), здесь — только громкость;
## кончилась — гул стихает (threat_ended).
func _on_weather(kind: StringName, intensity: float) -> void:
	if kind != &"dust":
		return
	_dust_level = intensity
	_dust_wind.volume_db = _dust_db(intensity)


static func _dust_db(intensity: float) -> float:
	return linear_to_db(lerpf(0.12, 1.0, clampf(intensity, 0.0, 1.0))) + DUST_DB


func _on_threat_ended(kind: StringName) -> void:
	if kind == &"dust":
		_dust_wind.stop()
		_dust_level = 0.0
	if kind == &"quake":
		_quake_heard = false
		_play(_sfx(&"rumble_hit"), 2.0)


## Гром запаздывает: чем дальше удар, тем позже (звук «медленнее» вспышки).
func _on_lightning(at: Vector3) -> void:
	_delayed(_sfx(&"thunder"), at, 0.0, 0.85 + 0.3 * fmod(at.x * 0.37 + at.z * 0.61, 1.0))


## Звук с задержкой по расстоянию. Таймер дерева зовёт метод узла (bind), а не лямбду: «Заново» удаляет
## директор вместе со сценой — связь с таймером рвётся сама, и гром не играет на удалённом узле.
func _delayed(stream: AudioStream, at: Vector3, volume_db: float, pitch: float) -> void:
	if not is_instance_valid(vehicle):
		return
	var delay := Vector2(at.x, at.z).distance_to(vehicle.state.pos) / THUNDER_SPEED
	if delay < 0.05:
		_play_at(stream, at, volume_db, pitch)
	else:
		get_tree().create_timer(delay).timeout.connect(_play_at.bind(stream, at, volume_db, pitch))


## Звук в точке: дальше hear — не слышно, громкость падает по квадрату (за краем экрана — уже тихо).
func _play_at(stream: AudioStream, at: Vector3, volume_db: float, pitch: float = 1.0, hear: float = HEAR_TILES,
		from: float = 0.0) -> void:
	if not is_instance_valid(vehicle) or not is_inside_tree():
		return
	var d := Vector2(at.x, at.z).distance_to(vehicle.state.pos)
	if d > hear:
		return
	var k := 1.0 - d / hear
	_play(stream, volume_db + linear_to_db(clampf(k * k, 0.03, 1.0)), pitch, from)


func _play(stream: AudioStream, volume_db: float, pitch: float = 1.0, from: float = 0.0) -> void:
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play(from)
