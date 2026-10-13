class_name EngineSound
extends AudioStreamPlayer
## Звук двигателя: процедурный зацикленный WAV (без ассетов), тон и громкость — от скорости и газа.
## AudioStreamWAV работает и в веб-сборке (режим сэмплов), в отличие от AudioStreamGenerator.

const RATE := 22050
const BASE_HZ := 55.0
const LOOP_S := 2.0              ## длина петли: каждая составляющая (BASE_HZ, ×2, ×0,5) укладывается в неё
                                 ## целым числом периодов — стык петли без щелчка и сбоя гула

const VOLUME_TRIM_DB := -3.1     ## общая громкость двигателя: −30% по амплитуде (на фоне остальных звуков)

var pitch_mult := 1.0            ## тон класса (VehicleClass.engine_pitch, ставит Vehicle): танк ниже, ховер выше


func _ready() -> void:
	stream = make_loop()
	volume_db = -60.0
	pitch_scale = 0.55


## speed_ratio — доля от максимальной скорости, throttle — газ 0..1.
func update(speed_ratio: float, throttle: float, dt: float) -> void:
	var k := 1.0 - exp(-6.0 * dt)
	pitch_scale = lerpf(pitch_scale, (0.55 + 0.9 * speed_ratio + 0.1 * throttle) * pitch_mult, k)
	volume_db = lerpf(volume_db, lerpf(-22.0, -10.0, maxf(throttle, speed_ratio)) + VOLUME_TRIM_DB, k)


## Петля гула двигателя — одна на все машины и забеги, в кэше звуков (Sfx): 44 тыс. сэмплов в GDScript —
## в браузере заметная запинка, а машина создаётся заново на каждом забеге.
static func make_loop() -> AudioStreamWAV:
	return Sfx.cached(&"engine", _synth)


static func _synth() -> AudioStreamWAV:
	var n := int(RATE * LOOP_S)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in n:
		var t := float(i) / RATE
		var x := 0.45 * _saw(BASE_HZ * t) + 0.25 * _saw(BASE_HZ * 2.0 * t + 0.31) \
				+ 0.2 * sin(TAU * BASE_HZ * 0.5 * t) + 0.06 * rng.randf_range(-1.0, 1.0)
		data.encode_s16(i * 2, int(clampf(x, -1.0, 1.0) * 20000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	wav.data = data
	return wav


static func _saw(x: float) -> float:
	return 2.0 * (x - floorf(x + 0.5))
