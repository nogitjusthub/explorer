class_name Sfx
extends RefCounted
## Процедурные звуки без ассетов (как и двигатель): AudioStreamWAV 16 бит, моно. Генерируются один
## раз при старте. Звуков угроз по GDD немного: молния (треск телеграфа и гром), гул землетрясения,
## смерч, урон.

const RATE := 22050

static var _cache: Dictionary[StringName, AudioStreamWAV] = {}


## Треск телеграфа молнии: щелчки чаще и громче к удару.
static func crackle(seconds: float) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var data := PackedFloat32Array()
	data.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 101
	var lp := 0.0
	for i in n:
		var k := float(i) / n
		var click := 0.0
		if rng.randf() < 0.002 + 0.03 * k * k:
			click = rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, click + rng.randf_range(-0.08, 0.08) * k, 0.6)
		data[i] = lp * (0.25 + 0.75 * k)
	return _wav(data)


## Гром: резкий щелчок разряда и низкий раскат, затухающий за seconds.
static func thunder(seconds: float) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var data := PackedFloat32Array()
	data.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 202
	var lp1 := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		var crack := noise * exp(-t * 40.0)
		lp1 = lerpf(lp1, noise, 0.06)
		lp2 = lerpf(lp2, lp1, 0.08)
		var roll := lp2 * 9.0 * exp(-t * 2.2) * (0.6 + 0.4 * sin(t * 7.0 + sin(t * 2.3) * 3.0))
		data[i] = crack * 0.9 + roll
	return _wav(data)


## Гул землетрясения: низкий шум с инфразвуковой «волной». rising — нарастает к концу (телеграф),
## иначе — резкий толчок и затухание.
static func rumble(seconds: float, rising: bool) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var data := PackedFloat32Array()
	data.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 404 if rising else 405
	var lp1 := 0.0
	var lp2 := 0.0
	var mid := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var k := t / seconds
		var noise := rng.randf_range(-1.0, 1.0)
		lp1 = lerpf(lp1, noise, 0.03)
		lp2 = lerpf(lp2, lp1, 0.05)
		mid = lerpf(mid, noise, 0.15)
		phase += TAU * (38.0 + 6.0 * sin(t * 3.1)) / RATE
		# Низ (до ~100 Гц) — гул; полоса 150–500 Гц — дребезг, чтобы было слышно и на ноутбуке.
		var rattle := (mid - lp1) * (0.5 + 0.5 * sin(t * 13.0 + sin(t * 4.0) * 2.0))
		var body := lp2 * 14.0 + sin(phase) * 0.35 * (0.7 + 0.3 * sin(t * 9.0)) + rattle * 0.9
		var env := pow(k, 1.4) if rising else minf(t / 0.04, 1.0) * exp(-t * 1.6)
		data[i] = body * env
	return _wav(data)


## Гул смерча — бесшовная петля: шумовой «вой», который то нарастает, то стихает.
## Один на все смерчи (генерация не бесплатна — кэш).
static func wind_loop(seconds: float) -> AudioStreamWAV:
	if _cache.has(&"wind"):
		return _cache[&"wind"]
	var n := int(seconds * RATE)
	var m := RATE / 8                      # перекрытие для бесшовной петли
	var raw := PackedFloat32Array()
	raw.resize(n + m)
	var rng := RandomNumberGenerator.new()
	rng.seed = 505
	var lp1 := 0.0
	var lp2 := 0.0
	var mid := 0.0
	for i in n + m:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		lp1 = lerpf(lp1, noise, 0.04)
		lp2 = lerpf(lp2, lp1, 0.06)
		mid = lerpf(mid, noise, 0.12 + 0.06 * sin(t * TAU * 1.5))
		raw[i] = lp2 * 8.0 + (mid - lp1) * (0.6 + 0.4 * sin(t * TAU * 0.5))
	var data := PackedFloat32Array()
	data.resize(n)
	for i in n:
		data[i] = raw[i]
	for i in m:
		var k := float(i) / m
		data[i] = lerpf(raw[n + i], raw[i], k)
	var wav := _wav(data)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	_cache[&"wind"] = wav
	return wav


## Удар по корпусу: глухой низкий «бум» со щелчком.
static func hit(seconds: float) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var data := PackedFloat32Array()
	data.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 303
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := lerpf(140.0, 45.0, minf(t / seconds, 1.0))
		phase += TAU * f / RATE
		var body := sin(phase) * exp(-t * 14.0)
		var click := rng.randf_range(-1.0, 1.0) * exp(-t * 120.0)
		data[i] = body * 0.9 + click * 0.5
	return _wav(data)


static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.001
	for s in samples:
		peak = maxf(peak, absf(s))
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i] / peak, -1.0, 1.0) * 26000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	return wav
