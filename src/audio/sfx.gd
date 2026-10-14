class_name Sfx
extends RefCounted
## Процедурные звуки без ассетов (как и двигатель): AudioStreamWAV 16 бит, моно. Звуков угроз по GDD
## немного: молния (треск телеграфа и гром), гул землетрясения, смерч (вой с завываниями), гул пылевой
## бури, урон; у фауны — крик скакунов, мычание и топот панцирника; реактивный рёв капсулы и челноков,
## луч захвата; «дзынь» подбора находки и «би-бип» пейджера; щелчок механического тумблера в интерфейсе; лязг люка
## и гул гидропривода подъёмника в трюме на старте.
##
## Звуки — по именам (named, рецепты — _recipe), каждый синтезируется один раз за сессию (и после
## «Заново» не заново). Синтез в GDScript небыстрый, а в браузере всё в одном потоке: звук целиком за
## кадр — заметная запинка (вой смерча — около 130 тыс. сэмплов). Поэтому звуки синтезируются заранее
## и порциями (prepare, pump — не дольше бюджета за кадр), пока игрок в трюме; понадобился раньше —
## досинтезируется сразу. Генератор — сопрограмма над Synth: каждые CHUNK сэмплов ждёт следующей порции.

const RATE := 22050
const CHUNK := 256                       ## сэмплов генератора за порцию фонового синтеза…
const CHUNK_HEAVY := 32                  ## …у самых тяжёлых (десятки синусов на сэмпл) — меньше
const WRITE_CHUNK := 2048                ## сэмплов шва петли, поиска пика и записи в 16 бит за порцию
const THRUST_S := 3.0                    ## реактивный рёв спуска и взлёта челноков (тот же, что у капсулы)

static var _cache: Dictionary[StringName, AudioStreamWAV] = {}   ## готовые звуки по именам
static var _queue: Array[StringName] = []                        ## фоновый синтез: первый — в работе
static var _jobs: Dictionary[StringName, Synth] = {}             ## начатые в фоне, ещё не готовые


## Синтез одного звука — порциями. Генератор — сопрограмма gen(s, …): в фоне (chunked) каждые CHUNK
## сэмплов ждёт s.resume, в конце отдаёт сэмплы (output, output_loop). Потом шов петли, поиск пика и
## запись в 16 бит с нормировкой по пику — тоже порциями, по WRITE_CHUNK сэмплов.
class Synth:
	extends RefCounted

	signal resume

	enum Stage { IDLE, GEN, SEAM, PEAK, WRITE, DONE }

	var chunked := true                  ## false — без пауз: остаток работы — за один шаг
	var wav: AudioStreamWAV              ## готовый звук; null — ещё синтезируется

	var _gen: Callable
	var _stage := Stage.IDLE
	var _data := PackedFloat32Array()
	var _loop_n := 0                     ## петля: n сэмплов, хвост m сверх них плавно вводится в начало —
	var _loop_m := 0                     ## шов не слышен
	var _i := 0
	var _peak := 0.001
	var _bytes := PackedByteArray()


	func _init(gen: Callable) -> void:
		_gen = gen


	## Одна порция работы (без пауз — вся оставшаяся стадия).
	func step() -> void:
		match _stage:
			Stage.IDLE:
				_stage = Stage.GEN
				_gen.call(self)              # до первой паузы (без пауз — до конца)
			Stage.GEN:
				resume.emit()
			Stage.SEAM:
				var to := _until(_loop_m)
				for i in range(_i, to):
					_data[i] = lerpf(_data[_loop_n + i], _data[i], float(i) / _loop_m)
				_i = to
				if _i >= _loop_m:
					_data.resize(_loop_n)
					_next(Stage.PEAK)
			Stage.PEAK:
				var d := _data
				var to := _until(d.size())
				var peak := _peak
				for i in range(_i, to):
					peak = maxf(peak, absf(d[i]))
				_peak = peak
				_i = to
				if _i >= d.size():
					_bytes.resize(d.size() * 2)
					_next(Stage.WRITE)
			Stage.WRITE:
				var d := _data
				var to := _until(d.size())
				var peak := _peak
				for i in range(_i, to):
					_bytes.encode_s16(i * 2, int(clampf(d[i] / peak, -1.0, 1.0) * 26000.0))
				_i = to
				if _i >= d.size():
					_make_wav()


	## Досинтезировать сразу, без пауз.
	func finish() -> AudioStreamWAV:
		chunked = false
		while wav == null:
			step()
		return wav


	## Конец генератора: сэмплы звука.
	func output(data: PackedFloat32Array) -> void:
		_data = data
		_next(Stage.PEAK)


	## Конец генератора: петля из n сэмплов, хвост raw (m сэмплов сверх n) плавно вводится в начало.
	func output_loop(raw: PackedFloat32Array, n: int, m: int) -> void:
		_data = raw
		_loop_n = n
		_loop_m = m
		_next(Stage.SEAM)


	func _next(stage: Stage) -> void:
		_stage = stage
		_i = 0


	func _until(size: int) -> int:
		return mini(_i + WRITE_CHUNK, size) if chunked else size


	func _make_wav() -> void:
		wav = AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = RATE
		wav.stereo = false
		if _loop_n > 0:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = _loop_n
		wav.data = _bytes
		_data = PackedFloat32Array()
		_bytes = PackedByteArray()
		_stage = Stage.DONE


## Звук по имени: готов — сразу; синтезируется в фоне — досинтезировать сейчас; иначе — целиком сейчас.
static func named(key: StringName) -> AudioStreamWAV:
	if _cache.has(key):
		return _cache[key]
	var job: Synth = _jobs.get(key, null)
	if job == null:
		job = Synth.new(_recipe(key))
	_cache[key] = job.finish()
	_jobs.erase(key)
	_queue.erase(key)
	return _cache[key]


## Сколько звуков ещё ждут фонового синтеза (экран загрузки).
static func pending() -> int:
	return _queue.size()


## Звук готов (синтезирован).
static func is_ready(key: StringName) -> bool:
	return _cache.has(key)


## Звук со своим синтезом (двигатель — EngineSound): make() — один раз за сессию, дальше из кэша.
static func cached(key: StringName, make: Callable) -> AudioStreamWAV:
	if not _cache.has(key):
		_cache[key] = make.call()
	return _cache[key]


## Поставить звуки в фоновый синтез (готовые и уже стоящие в очереди — пропускаются); first — в начало
## очереди: нужны раньше прочих (начатый звук доделается потом).
static func prepare(keys: Array[StringName], first: bool = false) -> void:
	var at := 0
	for key in keys:
		if _cache.has(key) or (_queue.has(key) and not first):
			continue
		if first:
			_queue.erase(key)
			_queue.insert(at, key)
			at += 1
		else:
			_queue.append(key)


## Фоновый синтез: порции, пока не выйдет budget_usec (одна порция — доли миллисекунды). Зовётся каждый
## кадр. true — в очереди ещё есть работа.
static func pump(budget_usec: int) -> bool:
	var t0 := Time.get_ticks_usec()
	while not _queue.is_empty():
		var key := _queue[0]
		var job: Synth = _jobs.get(key, null)
		if job == null:
			job = Synth.new(_recipe(key))
			_jobs[key] = job
		job.step()
		if job.wav != null:
			_cache[key] = job.wav
			_jobs.erase(key)
			_queue.remove_at(0)
		if Time.get_ticks_usec() - t0 >= budget_usec:
			break
	return not _queue.is_empty()


## Синтез звука по рецепту: генератор-сопрограмма с параметрами (для тестов и фонового синтеза).
static func job(key: StringName) -> Synth:
	return Synth.new(_recipe(key))


## Щелчок тумблера (интерфейс).
static func toggle() -> AudioStreamWAV:
	return named(&"toggle")


## Люк и подъёмник трюма (старт).
static func hatch_lift() -> AudioStreamWAV:
	return named(&"hatch_lift")


## Рецепты звуков по именам: генератор и его параметры.
static func _recipe(key: StringName) -> Callable:
	match key:
		&"crackle": return _crackle.bind(1.2)
		&"thunder": return _thunder.bind(2.2)
		&"hit": return _hit.bind(0.3)
		&"rumble_build": return _rumble.bind(2.5, true)
		&"rumble_hit": return _rumble.bind(2.4, false)
		&"wind": return _wind_loop.bind(2.0)      # гул водоворота
		&"howl": return _howl_loop.bind(6.0)      # вой смерча
		&"dust": return _dust_loop.bind(3.0)      # ровный гул пылевой бури
		&"ground_hum": return _ground_hum_loop.bind(3.0)   # червь идёт под песком
		&"screech": return _screech.bind(0.75)
		&"buzz": return _buzz.bind(1.2)
		&"bellow": return _bellow.bind(1.1, false)
		&"bellow_low": return _bellow.bind(1.1, true)
		&"stomp": return _stomp.bind(1.3)
		&"thrust": return _thrust.bind(THRUST_S)
		&"chime": return _chime.bind(0.6)
		&"pager": return _pager_beep
		&"tractor": return _tractor.bind(1.4)
		&"toggle": return _toggle
		&"hatch_lift": return _hatch_lift
	push_error("Sfx: unknown sound %s" % key)
	return _silence


static func _silence(s: Synth) -> void:
	var data := PackedFloat32Array()
	data.resize(1)
	s.output(data)


## Треск телеграфа молнии: щелчки чаще и громче к удару.
static func _crackle(s: Synth, seconds: float) -> void:
	var n := int(seconds * RATE)
	var data := PackedFloat32Array()
	data.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 101
	var lp := 0.0
	for i in n:
		if i % CHUNK == 0 and s.chunked:
			await s.resume
		var k := float(i) / n
		var click := 0.0
		if rng.randf() < 0.002 + 0.03 * k * k:
			click = rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, click + rng.randf_range(-0.08, 0.08) * k, 0.6)
		data[i] = lp * (0.25 + 0.75 * k)
	s.output(data)


## Гром: резкий щелчок разряда и низкий раскат, затухающий за seconds.
static func _thunder(s: Synth, seconds: float) -> void:
	var n := int(seconds * RATE)
	var data := PackedFloat32Array()
	data.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 202
	var lp1 := 0.0
	var lp2 := 0.0
	for i in n:
		if i % CHUNK == 0 and s.chunked:
			await s.resume
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		var crack := noise * exp(-t * 40.0)
		lp1 = lerpf(lp1, noise, 0.06)
		lp2 = lerpf(lp2, lp1, 0.08)
		var roll := lp2 * 9.0 * exp(-t * 2.2) * (0.6 + 0.4 * sin(t * 7.0 + sin(t * 2.3) * 3.0))
		data[i] = crack * 0.9 + roll
	s.output(data)


## Гул землетрясения: низкий шум с инфразвуковой «волной». rising — нарастает к концу (телеграф),
## иначе — резкий толчок и затухание.
static func _rumble(s: Synth, seconds: float, rising: bool) -> void:
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
		if i % CHUNK == 0 and s.chunked:
			await s.resume
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
	s.output(data)


## Подземный гул — бесшовная петля: тот же гул, что у землетрясения (низ до ~100 Гц, тон ~38 Гц с дрожью
## и дребезг 150–500 Гц), но ровный, без нарастания и спада — червь идёт под песком.
static func _ground_hum_loop(s: Synth, seconds: float) -> void:
	var n := int(seconds * RATE)
	var m := RATE / 4                      # перекрытие для бесшовной петли
	var raw := PackedFloat32Array()
	raw.resize(n + m)
	var rng := RandomNumberGenerator.new()
	rng.seed = 406
	var lp1 := 0.0
	var lp2 := 0.0
	var mid := 0.0
	var phase := 0.0
	for i in n + m:
		if i % CHUNK == 0 and s.chunked:
			await s.resume
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		lp1 = lerpf(lp1, noise, 0.03)
		lp2 = lerpf(lp2, lp1, 0.05)
		mid = lerpf(mid, noise, 0.15)
		phase += TAU * (38.0 + 6.0 * sin(t * 3.1)) / RATE
		var rattle := (mid - lp1) * (0.5 + 0.5 * sin(t * 13.0 + sin(t * 4.0) * 2.0))
		raw[i] = lp2 * 14.0 + sin(phase) * 0.35 * (0.7 + 0.3 * sin(t * 9.0)) + rattle * 0.9
	s.output_loop(raw, n, m)


## Гул ветра — бесшовная петля: шумовой «вой», который то нарастает, то стихает (водоворот играет его
## ниже тоном).
static func _wind_loop(s: Synth, seconds: float) -> void:
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
		if i % CHUNK == 0 and s.chunked:
			await s.resume
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		lp1 = lerpf(lp1, noise, 0.04)
		lp2 = lerpf(lp2, lp1, 0.06)
		mid = lerpf(mid, noise, 0.12 + 0.06 * sin(t * TAU * 1.5))
		raw[i] = lp2 * 8.0 + (mid - lp1) * (0.6 + 0.4 * sin(t * TAU * 0.5))
	s.output_loop(raw, n, m)


## Гул пылевой бури — бесшовная петля: ровный, без нарастаний — низкий гул ветра и шорох песка
## (полоса ~300–1500 Гц) на постоянной громкости.
static func _dust_loop(s: Synth, seconds: float) -> void:
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
		if i % CHUNK == 0 and s.chunked:
			await s.resume
		var noise := rng.randf_range(-1.0, 1.0)
		lp1 = lerpf(lp1, noise, 0.03)
		lp2 = lerpf(lp2, lp1, 0.05)
		hi = lerpf(hi, noise, 0.35)
		lo = lerpf(lo, noise, 0.08)
		raw[i] = lp2 * 9.0 + (hi - lo) * 0.35
	s.output_loop(raw, n, m)


## Вой смерча — бесшовная петля: гул ветра, над ним завывания — шум через узкий резонансный фильтр,
## частота которого то взлетает, то опадает (300–750 Гц, «у-у-у»), и вой громче на подъёмах.
## Все колебания укладываются в петлю целым числом периодов.
static func _howl_loop(s: Synth, seconds: float) -> void:
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
		if i % CHUNK == 0 and s.chunked:
			await s.resume
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
	s.output_loop(raw, n, m)


## Электрошок по машине: гудение сети с треском разрядов, к концу стихает.
static func _buzz(s: Synth, seconds: float) -> void:
	var n := int(seconds * RATE)
	var data := PackedFloat32Array()
	data.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 707
	var phase := 0.0
	var lp := 0.0
	for i in n:
		if i % CHUNK == 0 and s.chunked:
			await s.resume
		var t := float(i) / RATE
		var k := t / seconds
		phase += TAU * 110.0 / RATE
		var saw := fmod(phase / TAU, 1.0) * 2.0 - 1.0
		var hum := saw * 0.35 * (0.6 + 0.4 * sin(t * 37.0))
		var click := rng.randf_range(-1.0, 1.0) if rng.randf() < 0.01 * (1.0 - k) + 0.002 else 0.0
		lp = lerpf(lp, click, 0.5)
		data[i] = (hum + lp * 1.4) * minf(t / 0.01, 1.0) * (1.0 - k * k)
	s.output(data)


## Реактивный рёв (тормозные двигатели капсулы десанта, спуск и взлёт челноков): ровный низкий рокот —
## шум через три фильтра (основная энергия ниже ~200 Гц), суббас 45–52 Гц, медленно и неровно
## «дышащая» громкость; немного полосы 200–600 Гц, чтобы рёв был слышен и на маленьких динамиках.
## Без треска и быстрой модуляции.
static func _thrust(s: Synth, seconds: float) -> void:
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
		if i % CHUNK == 0 and s.chunked:
			await s.resume
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
	s.output(data)


## Крик скакуна — хищный: резкий визг, как у ястреба (высокий тон с быстрым подъёмом и долгим спадом,
## хрип и дрожание), и под ним низкий хриплый рык — как имитировали крик рапторов. Перегружен по краям
## (tanh) — звучит грубо, «живо».
static func _screech(s: Synth, seconds: float) -> void:
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
		if i % CHUNK == 0 and s.chunked:
			await s.resume
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
	s.output(data)


## Мычание панцирника — низкое, модулированное: пила 95 → 125 → 80 Гц (подъём и долгий спад, «мууу»),
## через два фильтра-форманты, которые раскрываются к середине («му» → «ооо»); дрожание 7 Гц по тону и
## громкости, хрип на половине тона. Перегружено (tanh) — грубо, по-звериному. low — октавой ниже той же
## длины (рёв перед рывком), форманты — те же.
static func _bellow(s: Synth, seconds: float, low: bool) -> void:
	var n := int(seconds * RATE)
	var data := PackedFloat32Array()
	data.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1010
	var ph := 0.0
	var lp1 := 0.0
	var lp2 := 0.0
	for i in n:
		if i % CHUNK == 0 and s.chunked:
			await s.resume
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
	s.output(data)


## Топот панцирника в рывке: ровные глухие удары лап (~7 в секунду) по тихому рокоту бега; к концу
## рывка стихают.
static func _stomp(s: Synth, seconds: float) -> void:
	var n := int(seconds * RATE)
	var data := PackedFloat32Array()
	data.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1111
	var lp1 := 0.0
	var lp2 := 0.0
	var beat := 0.14
	for i in n:
		if i % CHUNK == 0 and s.chunked:
			await s.resume
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
	s.output(data)


## «Дзынь» подбора находки: два чистых тона в квинту (1760 и 2637 Гц, второй вступает через 40 мс) и
## короткий негармоничный призвук 5,4 кГц — металлический блеск; быстрая атака, затухание.
static func _chime(s: Synth, seconds: float) -> void:
	var n := int(seconds * RATE)
	var data := PackedFloat32Array()
	data.resize(n)
	for i in n:
		if i % CHUNK == 0 and s.chunked:
			await s.resume
		var t := float(i) / RATE
		var t2 := maxf(t - 0.04, 0.0)
		var a := sin(TAU * 1760.0 * t) * exp(-t * 7.0)
		var b := sin(TAU * 2637.0 * t2) * exp(-t2 * 6.0) * (1.0 if t >= 0.04 else 0.0)
		var c := sin(TAU * 5400.0 * t) * exp(-t * 25.0) * 0.3
		data[i] = (a * 0.6 + b * 0.5 + c) * minf(t / 0.003, 1.0)
	s.output(data)


## «Би-бип» пейджера: два коротких писка (1,25 и 1,56 кГц) почти прямоугольной формы, слегка хриплые —
## дребезг 70 Гц по громкости, немного шума и мягкое ограничение.
static func _pager_beep(s: Synth) -> void:
	var n := int(0.26 * RATE)
	var data := PackedFloat32Array()
	data.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1616
	var ph := 0.0
	var lp := 0.0
	for i in n:
		if i % CHUNK == 0 and s.chunked:
			await s.resume
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
	s.output(data)


## Луч захвата: среднечастотное волнообразное гудение — тон около 420 Гц с обертонами, громкость и
## высота плавают волнами 3,2 раза в секунду («воу-воу»), второй голос чуть выше даёт биение. Звучит
## перегруженно и рычит: субгармоника октавой ниже, «рык» — рваная амплитудная модуляция ~38 Гц, сигнал
## загнан в несимметричный клип, срезан жёстко и огрублён по разрядности; раз в 0,3–0,7 с — броски
## перегруза (громче, треск, разрядность ещё ниже). Нарастает и гаснет плавно.
static func _tractor(s: Synth, seconds: float) -> void:
	var n := int(seconds * RATE)
	var data := PackedFloat32Array()
	data.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1515
	var p1 := 0.0
	var p2 := 0.0
	var lp := 0.0
	var surge := 0.0                                    # бросок перегруза 0…1, гаснет
	var next_surge := 0.2
	var growl_ph := 0.0                                 # фаза «рыка»: частота гуляет 30…46 Гц
	var growl_f := 38.0
	for i in n:
		if i % CHUNK == 0 and s.chunked:
			await s.resume
		var t := float(i) / RATE
		var k := t / seconds
		var wave := sin(TAU * 3.2 * t)
		var f := 420.0 * (1.0 + 0.035 * wave)
		p1 += TAU * f / RATE
		p2 += TAU * f * 1.007 / RATE
		var voice := sin(p1) + 0.5 * sin(p1 * 2.0) + 0.25 * sin(p1 * 3.0) + 0.6 * sin(p2) + 0.3 * sin(p2 * 2.0) \
				+ 0.7 * sin(p1 * 0.5)                     # субгармоника — низ рыка
		if i % 220 == 0:
			growl_f = rng.randf_range(30.0, 46.0)
		growl_ph += TAU * growl_f / RATE
		var growl := 0.35 + 0.65 * clampf(sin(growl_ph) * 3.0, 0.0, 1.0)   # рваные «хрипы» ~38 раз в секунду
		lp = lerpf(lp, voice * growl, 0.45)
		if t >= next_surge:
			surge = 1.0
			next_surge = t + rng.randf_range(0.3, 0.7)
		surge = maxf(surge - 9.0 / RATE, 0.0)
		var amp := 0.62 + 0.38 * sin(TAU * 3.2 * t - 0.6)
		var x := lp * amp * (4.5 + 2.5 * surge) + rng.randf_range(-1.0, 1.0) * 0.9 * surge * surge
		var y := tanh(x + 0.35) - tanh(0.35)           # несимметричный клип — «рваный» верх
		y = clampf(y * 1.6, -0.75, 0.75)               # жёсткий срез сверху — рычание, не гул
		var bits := lerpf(24.0, 6.0, surge)            # разрядность: грубее в броске
		y = roundf(y * bits) / bits
		var env := smoothstep(0.0, 0.2, t) * (1.0 - smoothstep(0.82, 1.0, k))
		data[i] = y * env
	s.output(data)


## Старый механический тумблер: тихий взвод рычага, через 18 мс — главный щелчок защёлки, ещё через 9 мс —
## дребезг пружины. Каждое событие — корпус (низ ~190 Гц) и металл (1,2–4 кГц), затухающие с разной
## скоростью, плюс короткий шумовой удар.
static func _toggle(s: Synth) -> void:
	var n := int(0.09 * RATE)
	var data := PackedFloat32Array()
	data.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2207
	# Моды: частота, затухание (1/с), громкость.
	var modes: Array[Vector3] = [Vector3(190.0, 45.0, 0.8), Vector3(1180.0, 110.0, 0.55),
			Vector3(2350.0, 170.0, 0.45), Vector3(3900.0, 320.0, 0.3)]
	var events: Array[Vector2] = [Vector2(0.0, 0.25), Vector2(0.018, 1.0), Vector2(0.027, 0.3)]
	var phases: Array[float] = []
	for m in modes.size() * events.size():
		phases.append(rng.randf() * TAU)
	for i in n:
		if i % CHUNK_HEAVY == 0 and s.chunked:
			await s.resume
		var t := float(i) / RATE
		var v := 0.0
		for e in events.size():
			var dt := t - events[e].x
			if dt < 0.0:
				continue
			var x := rng.randf_range(-1.0, 1.0) * exp(-dt * 1800.0) * 0.8
			for m in modes.size():
				var md := modes[m]
				x += md.z * sin(TAU * md.x * dt + phases[e * modes.size() + m]) * exp(-dt * md.y)
			v += x * events[e].y
		data[i] = tanh(v * 0.8)
	s.output(data)


## Люк и подъёмник трюма на старте (около 1,25 с), как сервисный подъёмник: лязг защёлки люка с дребезгом,
## шипение сброса давления, гул гидропривода — мотор насоса раскручивается до ~100 Гц (жужжащие нечётные
## обертоны), пульсация поршней и вой шестерён насоса, шум масла в трубах; в конце хода — мотор сбегает
## вниз, платформа глухо встаёт на упор.
static func _hatch_lift(s: Synth) -> void:
	var n := int(1.25 * RATE)
	var data := PackedFloat32Array()
	data.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4411
	# Металл люка: частота, затухание (1/с), громкость — неровный ряд, звенит «железом», а не колоколом.
	var modes: Array[Vector3] = [Vector3(97.0, 16.0, 1.0), Vector3(233.0, 26.0, 0.7), Vector3(517.0, 38.0, 0.55),
			Vector3(1130.0, 60.0, 0.4), Vector3(2210.0, 95.0, 0.3), Vector3(3470.0, 150.0, 0.2)]
	# Удары: время, сила, высота (множитель частот) — защёлка, дребезг, упор платформы внизу.
	var hits: Array[Vector3] = [Vector3(0.0, 1.0, 1.0), Vector3(0.034, 0.45, 1.06), Vector3(0.105, 0.22, 0.97),
			Vector3(0.93, 0.8, 0.62)]
	var phases: Array[float] = []
	for m in modes.size() * hits.size():
		phases.append(rng.randf() * TAU)
	var motor := 0.0
	var gear := 0.0
	var hiss_hp := 0.0
	var hiss_prev := 0.0
	var flow := 0.0
	for i in n:
		if i % CHUNK_HEAVY == 0 and s.chunked:
			await s.resume
		var t := float(i) / RATE
		var v := 0.0
		for h in hits.size():
			var dt := t - hits[h].x
			if dt < 0.0:
				continue
			var x := rng.randf_range(-1.0, 1.0) * exp(-dt * 700.0) * 0.9
			for m in modes.size():
				var md := modes[m]
				x += md.z * sin(TAU * md.x * hits[h].z * dt + phases[h * modes.size() + m]) * exp(-dt * md.y)
			if h == hits.size() - 1:
				x += 1.4 * sin(TAU * 55.0 * dt) * exp(-dt * 11.0)       # упор — глухой низ
			v += x * hits[h].y
		# Шипение: белый шум без низа, вспыхивает при отпирании и гаснет за ~0,3 с.
		var noise := rng.randf_range(-1.0, 1.0)
		hiss_hp = 0.85 * (hiss_hp + noise - hiss_prev)
		hiss_prev = noise
		v += hiss_hp * 0.35 * smoothstep(0.02, 0.06, t) * exp(-maxf(t - 0.06, 0.0) * 9.0)
		# Гидропривод: с 0,12 с разгон, с 0,85 с — сбег; частота мотора 60 → 100 Гц и обратно вниз.
		var run := smoothstep(0.12, 0.3, t) * (1.0 - smoothstep(0.85, 1.12, t))
		var f := lerpf(60.0, 100.0, smoothstep(0.12, 0.35, t)) * lerpf(1.0, 0.7, smoothstep(0.85, 1.12, t))
		motor += TAU * f / RATE
		gear += TAU * f * 4.2 / RATE
		var buzz := sin(motor) + 0.55 * sin(motor * 3.0) + 0.35 * sin(motor * 5.0) + 0.2 * sin(motor * 7.0) \
				+ 0.3 * sin(motor * 2.0)
		var ripple := 0.75 + 0.25 * sin(motor * 0.5)                   # поршни насоса
		flow = lerpf(flow, noise, 0.08)                                  # масло в трубах — глухой шум
		v += run * (buzz * ripple * 0.42 + sin(gear) * 0.12 + flow * 0.9)
		data[i] = tanh(v * 0.9)
	s.output(data)


## Удар по корпусу: глухой низкий «бум» со щелчком.
static func _hit(s: Synth, seconds: float) -> void:
	var n := int(seconds * RATE)
	var data := PackedFloat32Array()
	data.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 303
	var phase := 0.0
	for i in n:
		if i % CHUNK == 0 and s.chunked:
			await s.resume
		var t := float(i) / RATE
		var f := lerpf(140.0, 45.0, minf(t / seconds, 1.0))
		phase += TAU * f / RATE
		var body := sin(phase) * exp(-t * 14.0)
		var click := rng.randf_range(-1.0, 1.0) * exp(-t * 120.0)
		data[i] = body * 0.9 + click * 0.5
	s.output(data)
