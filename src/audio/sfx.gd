class_name Sfx
extends RefCounted
## Процедурные звуки без ассетов (как и двигатель): AudioStreamWAV 16 бит, моно. Генерируются один
## раз при старте. Звуков угроз по GDD немного: молния (треск телеграфа и гром), гул землетрясения,
## смерч, урон; у фауны — крик скакунов, мычание и топот панцирника.

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


## Электрошок по машине: гудение сети с треском разрядов, к концу стихает.
static func buzz(seconds: float) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var data := PackedFloat32Array()
	data.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 707
	var phase := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var k := t / seconds
		phase += TAU * 110.0 / RATE
		var saw := fmod(phase / TAU, 1.0) * 2.0 - 1.0
		var hum := saw * 0.35 * (0.6 + 0.4 * sin(t * 37.0))
		var click := rng.randf_range(-1.0, 1.0) if rng.randf() < 0.01 * (1.0 - k) + 0.002 else 0.0
		lp = lerpf(lp, click, 0.5)
		data[i] = (hum + lp * 1.4) * minf(t / 0.01, 1.0) * (1.0 - k * k)
	return _wav(data)


## Рёв тормозных двигателей капсулы десанта: широкий шумовой рёв с треском, быстро нарастает и к концу
## обрывается.
static func thrust(seconds: float) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var data := PackedFloat32Array()
	data.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 808
	var lp1 := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var k := t / seconds
		var noise := rng.randf_range(-1.0, 1.0)
		lp1 = lerpf(lp1, noise, 0.2)
		lp2 = lerpf(lp2, lp1, 0.25)
		var crackle := (noise - lp1) * (0.3 + 0.3 * sin(t * 61.0))
		var env := minf(t / 0.06, 1.0) * (1.0 - smoothstep(0.85, 1.0, k))
		data[i] = (lp2 * 3.0 + crackle) * env
	return _wav(data)


## Крик скакуна — хищный: резкий визг, как у ястреба (высокий тон с быстрым подъёмом и долгим спадом,
## хрип и дрожание), и под ним низкий хриплый рык — как имитировали крик рапторов. Перегружен по краям
## (tanh) — звучит грубо, «живо».
static func screech(seconds: float) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var data := PackedFloat32Array()
	data.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	var hi := 0.0
	var lo := 0.0
	var air_lp := 0.0
	var air_hp := 0.0
	for i in n:
		var t := float(i) / RATE
		var k := t / seconds
		# Визг: 2,4 кГц → 3,4 кГц за первую десятую, потом сползает к 1,9 кГц; дрожание 38 Гц.
		var f := lerpf(2400.0, 3400.0, minf(k / 0.1, 1.0)) if k < 0.1 else lerpf(3400.0, 1900.0, (k - 0.1) / 0.9)
		f *= 1.0 + 0.035 * sin(TAU * 38.0 * t)
		hi += TAU * f / RATE
		var shriek := sin(hi) + 0.45 * sin(hi * 2.0 + 0.4) + 0.25 * sin(hi * 3.0 + 1.1)
		# Хрип визга — шум в полосе около тона.
		var noise := rng.randf_range(-1.0, 1.0)
		air_lp = lerpf(air_lp, noise, 0.55)
		air_hp = air_lp - lerpf(air_hp, air_lp, 0.15)
		shriek += air_hp * 0.8
		# Рык: 140 → 85 Гц, пила с «дребезгом» 23 Гц.
		var g := lerpf(140.0, 85.0, k)
		lo += TAU * g / RATE
		var saw := fmod(lo / TAU, 1.0) * 2.0 - 1.0
		var growl := saw * (0.55 + 0.45 * sin(TAU * 23.0 * t)) + 0.3 * rng.randf_range(-1.0, 1.0) * (0.5 + 0.5 * sin(TAU * 23.0 * t))
		var env_hi := minf(t / 0.015, 1.0) * pow(1.0 - k, 1.4)
		var env_lo := minf(t / 0.05, 1.0) * (1.0 - smoothstep(0.55, 1.0, k))
		var x := shriek * 0.55 * env_hi + growl * 0.6 * env_lo
		data[i] = tanh(x * 1.8)
	return _wav(data)


## Мычание панцирника — низкое, модулированное: пила 95 → 125 → 80 Гц (подъём и долгий спад, «мууу»),
## через два фильтра-форманты, которые раскрываются к середине («му» → «ооо»); дрожание 7 Гц по тону и
## громкости, хрип на половине тона. Перегружено (tanh) — грубо, по-звериному.
static func bellow(seconds: float) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var data := PackedFloat32Array()
	data.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1010
	var ph := 0.0
	var lp1 := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var k := t / seconds
		var f := lerpf(95.0, 125.0, smoothstep(0.0, 0.3, k)) if k < 0.3 else lerpf(125.0, 80.0, (k - 0.3) / 0.7)
		var wobble := sin(TAU * 7.0 * t)
		f *= 1.0 + 0.045 * wobble
		ph += TAU * f / RATE
		var saw := fmod(ph / TAU, 1.0) * 2.0 - 1.0
		var cut := lerpf(0.07, 0.2, sin(PI * minf(k * 1.3, 1.0)))
		lp1 = lerpf(lp1, saw, cut)
		lp2 = lerpf(lp2, lp1, cut)
		var voice := lp2 * 2.5 + (lp1 - lp2) * 1.4
		var rasp := rng.randf_range(-1.0, 1.0) * 0.25 * maxf(sin(ph * 0.5), 0.0)
		var env := minf(t / 0.12, 1.0) * (1.0 - smoothstep(0.7, 1.0, k)) * (0.75 + 0.25 * wobble)
		data[i] = tanh((voice + rasp) * env * 1.8)
	return _wav(data)


## Топот панцирника в рывке: шесть ног — глухие удары тройками, как галоп (та-та-там), по низкому
## рокоту бега; к концу рывка стихает.
static func stomp(seconds: float) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var data := PackedFloat32Array()
	data.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1111
	var lp1 := 0.0
	var lp2 := 0.0
	var hit_t := -1.0
	var hit_f := 60.0
	var next_hit := 0.0
	var beat := 0
	for i in n:
		var t := float(i) / RATE
		var k := t / seconds
		if t >= next_hit:
			hit_t = t
			hit_f = rng.randf_range(48.0, 72.0)
			next_hit = t + (0.2 if beat % 3 == 2 else 0.085) * rng.randf_range(0.85, 1.15)
			beat += 1
		var ht := t - hit_t
		var noise := rng.randf_range(-1.0, 1.0)
		# Удар лапы: тон с провалом высоты и щелчок грунта.
		var thump := sin(TAU * hit_f * ht * (1.0 - minf(ht * 4.0, 0.45))) * exp(-ht * 20.0) \
				+ noise * exp(-ht * 90.0) * 0.5
		lp1 = lerpf(lp1, noise, 0.04)
		lp2 = lerpf(lp2, lp1, 0.06)
		var roll := lp2 * 10.0 * (0.7 + 0.3 * sin(TAU * 5.0 * t))
		var env := minf(t / 0.05, 1.0) * (1.0 - smoothstep(0.7, 1.0, k))
		data[i] = tanh((thump + roll * 0.6) * env * 1.5)
	return _wav(data)


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
