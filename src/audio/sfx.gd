class_name Sfx
extends RefCounted
## Процедурные звуки без ассетов (как и двигатель): AudioStreamWAV 16 бит, моно. Генерируются один
## раз при старте. Звуков угроз по GDD немного: молния (треск телеграфа и гром), гул землетрясения,
## смерч (вой с завываниями), гул пылевой бури, урон; у фауны — крик скакунов, мычание и топот панцирника; реактивный рёв капсулы и челноков,
## луч захвата; «дзынь» подбора находки и «би-бип» пейджера.

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


## Гул пылевой бури — бесшовная петля: ровный, без нарастаний — низкий гул ветра и шорох песка
## (полоса ~300–1500 Гц) на постоянной громкости. Кэш.
static func dust_loop(seconds: float) -> AudioStreamWAV:
	if _cache.has(&"dust"):
		return _cache[&"dust"]
	var n := int(seconds * RATE)
	var m := RATE / 4                      # перекрытие для бесшовной петли
	var raw := PackedFloat32Array()
	raw.resize(n + m)
	var rng := RandomNumberGenerator.new()
	rng.seed = 707
	var lp1 := 0.0
	var lp2 := 0.0
	var hi := 0.0
	var lo := 0.0
	for i in n + m:
		var noise := rng.randf_range(-1.0, 1.0)
		lp1 = lerpf(lp1, noise, 0.03)
		lp2 = lerpf(lp2, lp1, 0.05)
		hi = lerpf(hi, noise, 0.35)
		lo = lerpf(lo, noise, 0.08)
		raw[i] = lp2 * 9.0 + (hi - lo) * 0.35
	var wav := _loop(raw, n, m)
	_cache[&"dust"] = wav
	return wav


## Вой смерча — бесшовная петля: гул ветра, над ним завывания — шум через узкий резонансный фильтр,
## частота которого то взлетает, то опадает (300–750 Гц, «у-у-у»), и вой громче на подъёмах.
## Все колебания укладываются в петлю целым числом периодов. Кэш.
static func howl_loop(seconds: float) -> AudioStreamWAV:
	if _cache.has(&"howl"):
		return _cache[&"howl"]
	var n := int(seconds * RATE)
	var m := RATE / 4
	var raw := PackedFloat32Array()
	raw.resize(n + m)
	var rng := RandomNumberGenerator.new()
	rng.seed = 606
	var lp1 := 0.0
	var lp2 := 0.0
	var low := 0.0
	var band := 0.0
	for i in n + m:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		lp1 = lerpf(lp1, noise, 0.04)
		lp2 = lerpf(lp2, lp1, 0.06)
		var sweep := 0.5 + 0.35 * sin(TAU * t / (seconds * 0.5)) + 0.15 * sin(TAU * t / (seconds / 3.0) + 1.0)
		var fc := lerpf(300.0, 750.0, clampf(sweep, 0.0, 1.0))
		var f := 2.0 * sin(PI * fc / RATE)
		low += f * band
		var high := noise - low - 0.06 * band
		band += f * high
		var howl := band * 0.35 * (0.3 + 0.7 * clampf(sweep, 0.0, 1.0))
		raw[i] = lp2 * 5.0 + howl
	var wav := _loop(raw, n, m)
	_cache[&"howl"] = wav
	return wav


## Петля из n сэмплов: хвост длиной m (сверх n) плавно вводится в начало — шов не слышен.
static func _loop(raw: PackedFloat32Array, n: int, m: int) -> AudioStreamWAV:
	var data := PackedFloat32Array()
	data.resize(n)
	for i in n:
		data[i] = raw[i]
	for i in m:
		data[i] = lerpf(raw[n + i], raw[i], float(i) / m)
	var wav := _wav(data)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
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


## Реактивный рёв (тормозные двигатели капсулы десанта, спуск и взлёт челноков): ровный низкий рокот —
## шум через три фильтра (основная энергия ниже ~200 Гц), суббас 45–52 Гц, медленно и неровно
## «дышащая» громкость; немного полосы 200–600 Гц, чтобы рёв был слышен и на маленьких динамиках.
## Без треска и быстрой модуляции.
static func thrust(seconds: float) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var data := PackedFloat32Array()
	data.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 808
	var lp1 := 0.0
	var lp2 := 0.0
	var lp3 := 0.0
	var sway := 0.0
	var sub := 0.0
	for i in n:
		var t := float(i) / RATE
		var k := t / seconds
		var noise := rng.randf_range(-1.0, 1.0)
		lp1 = lerpf(lp1, noise, 0.06)
		lp2 = lerpf(lp2, lp1, 0.06)
		lp3 = lerpf(lp3, lp2, 0.08)
		sway = lerpf(sway, noise, 0.0004)
		sub += TAU * (48.0 + 4.0 * sin(t * 1.3)) / RATE
		var roar := lp3 * 9.0 + (lp1 - lp3) * 0.6 + sin(sub) * 0.3
		var env := minf(t / 0.12, 1.0) * (1.0 - smoothstep(0.85, 1.0, k))
		data[i] = tanh(roar * (0.85 + sway * 6.0) * env * 1.4)
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
## громкости, хрип на половине тона. Перегружено (tanh) — грубо, по-звериному. low — октавой ниже той же
## длины (рёв перед рывком), форманты — те же.
static func bellow(seconds: float, low: bool = false) -> AudioStreamWAV:
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
		if low:
			f *= 0.5
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


## Топот панцирника в рывке: ровные глухие удары лап (~7 в секунду) по тихому рокоту бега; к концу
## рывка стихают.
static func stomp(seconds: float) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var data := PackedFloat32Array()
	data.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1111
	var lp1 := 0.0
	var lp2 := 0.0
	var beat := 0.14
	for i in n:
		var t := float(i) / RATE
		var k := t / seconds
		var ht := fmod(t, beat)
		var noise := rng.randf_range(-1.0, 1.0)
		var thump := sin(TAU * 58.0 * ht * (1.0 - minf(ht * 3.0, 0.3))) * exp(-ht * 24.0) \
				+ noise * exp(-ht * 120.0) * 0.25
		lp1 = lerpf(lp1, noise, 0.04)
		lp2 = lerpf(lp2, lp1, 0.06)
		var env := minf(t / 0.04, 1.0) * exp(-k * 1.8)
		data[i] = tanh((thump + lp2 * 3.0) * env * 1.2)
	return _wav(data)


## «Дзынь» подбора находки: два чистых тона в квинту (1760 и 2637 Гц, второй вступает через 40 мс) и
## короткий негармоничный призвук 5,4 кГц — металлический блеск; быстрая атака, затухание.
static func chime(seconds: float) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var data := PackedFloat32Array()
	data.resize(n)
	for i in n:
		var t := float(i) / RATE
		var t2 := maxf(t - 0.04, 0.0)
		var a := sin(TAU * 1760.0 * t) * exp(-t * 7.0)
		var b := sin(TAU * 2637.0 * t2) * exp(-t2 * 6.0) * (1.0 if t >= 0.04 else 0.0)
		var c := sin(TAU * 5400.0 * t) * exp(-t * 25.0) * 0.3
		data[i] = (a * 0.6 + b * 0.5 + c) * minf(t / 0.003, 1.0)
	return _wav(data)


## «Би-бип» пейджера: два коротких писка (1,25 и 1,56 кГц) почти прямоугольной формы, слегка хриплые —
## дребезг 70 Гц по громкости, немного шума и мягкое ограничение.
static func pager_beep() -> AudioStreamWAV:
	var n := int(0.26 * RATE)
	var data := PackedFloat32Array()
	data.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1616
	var ph := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var on := 0.0
		var f := 1250.0
		if t < 0.075:
			on = 1.0
		elif t >= 0.125 and t < 0.21:
			on = 1.0
			f = 1560.0
		ph += TAU * f / RATE
		var square := sin(ph) + sin(ph * 3.0) / 3.0 + sin(ph * 5.0) / 5.0
		var rasp := 0.75 + 0.25 * sin(TAU * 70.0 * t) + rng.randf_range(-0.15, 0.15)
		var x := tanh(square * rasp * 1.6) * on
		lp = lerpf(lp, x, 0.5)                   # смягчает щелчки краёв
		data[i] = lp
	return _wav(data)


## Луч захвата (эвакуация): низкий гул с пульсацией, над ним тон, плавно взлетающий вверх (300 → 1200 Гц,
## с вибрато), и россыпь коротких высоких искорок; в конце стихает.
static func tractor(seconds: float) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var data := PackedFloat32Array()
	data.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1515
	var hum := 0.0
	var tone := 0.0
	var ping := 0.0
	var ping_f := 3000.0
	var ping_t := 1.0
	for i in n:
		var t := float(i) / RATE
		var k := t / seconds
		hum += TAU * 90.0 / RATE
		var drone := (sin(hum) + 0.5 * sin(hum * 2.0)) * (0.6 + 0.4 * sin(TAU * 9.0 * t))
		tone += TAU * 300.0 * pow(4.0, k) * (1.0 + 0.03 * sin(TAU * 7.0 * t)) / RATE
		var rise := sin(tone) + 0.3 * sin(tone * 1.5)
		if rng.randf() < 0.0015:
			ping_t = 0.0
			ping_f = rng.randf_range(2200.0, 4800.0)
		ping_t += 1.0 / RATE
		ping += TAU * ping_f / RATE
		var sparkle := sin(ping) * exp(-ping_t * 30.0)
		var env := minf(t / 0.15, 1.0) * (1.0 - smoothstep(0.8, 1.0, k))
		data[i] = tanh((drone * 0.35 + rise * 0.35 + sparkle * 0.25) * env * 1.4)
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
