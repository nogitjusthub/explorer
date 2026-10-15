class_name Whirlpool
extends Node3D
## Водоворот (GDD §5.6) — 2×2 тайла глубокой воды (туда заходит только ховер), центр — в вершине сетки.
## Появляется за кадром по курсу машины (SPAWN_MIN…SPAWN_MAX тайлов). Сначала whirlpool_form_s телеграфа: на
## воде проступают круги и кольцо пены, гул — тяги ещё нет.
## Потом живёт whirlpool_life_min…max_s: тянет к центру, как смерч, но только машину на воде —
## a(r) = pull / масса × (1 − r / pull_r), с закруткой (машину ведёт по спирали). В ядре
## (whirlpool_core_r) топит: машина уходит в воду (VehicleState.pull_under — только модель) и получает
## whirlpool_core_dps урона в секунду, пока не вырвется. Ховер (а на глубокую воду заходит только он)
## уходит в воду почти целиком — до HOVER_SINK полного погружения, и его болтает, как на неровном грунте
## (VehicleState.churn → VehicleRide); машина без подушки — целиком. Вырвалась — всплывает; воронка
## угасает — глубина ядра слабеет вместе с ней, живую машину отпускает плавно. Погибла в ядре (утонула) —
## уходит под воду целиком и там остаётся. Спасение — пройти по краю на полном ходу или выйти на берег.
## На пейджере его нет — видно и так.
## Не стоит на месте: плавно ходит по петле (эллипс до DRIFT_R тайлов, период DRIFT_PERIOD_S), не сходя
## с глубокой воды — петля выбирается так, чтобы на всём пути под ним было 2×2 глубоких тайла.
## Всё крутится в одну сторону — к убыванию угла atan(z, x): закрутка тяги, пена по краю (узел частиц
## поворачивается), клочья пены по рукавам спирали в шейдере.

signal damaged(amount: int, source: StringName)

const DEEP := 1.95                       ## ярусов воды над центром тайла — глубоко
const SIZE := 1.6                        ## радиус воронки на воде, тайлов: круг накрывает квадрат 2×2 целиком
const SWIRL := 0.45                      ## закрутка: доля тяги поперёк — машину ведёт по спирали
const DAMAGE_STEP := 5                   ## урон ядра порциями, как у смерча
const SINK_S := 1.5                      ## за столько в ядре машину затягивает полностью…
const SURFACE_S := 0.8                   ## …и за столько выносит на поверхность, когда вырвалась
const HOVER_SINK := 0.8                  ## ховер в ядре уходит в воду на эту долю полного погружения (над водой — купол)
const FADE_S := 1.5
const HEAR_TILES := 25.0
const SPOT_TRIES := 24
const SPAWN_MIN := 14.0                  ## появляется за кадром: дальше угла кадра (~11 тайлов) плюс радиус воронки…
const SPAWN_MAX := 18.0                  ## …и не так далеко, чтобы машина по курсу на него не вышла
const DRIFT_R: Array[float] = [1.5, 1.0, 0.5]   ## радиусы петли смещения — наибольший, при котором путь весь над глубокой водой
const DRIFT_PERIOD_S := 16.0
const DRIFT_SAMPLES := 16
const FOAM_TURN := 0.18                  ## доля _spin — поворот кольца пены, рад
const COLOR_FOAM := Color(0.86, 0.97, 0.94)
const COLOR_FOAM_DOTS := Color(0.55, 0.75, 0.76)   ## брызги по краю — тусклее пены в шейдере
const COLOR_DEEP := Color(0.06, 0.3, 0.36)
const SWIRL_SHADER := preload("res://src/render/shaders/whirlpool.gdshader")


var rules: BalanceRules
var vehicle: Vehicle
var query: TerrainQuery
var rng: RandomNumberGenerator
var sight: Callable                      ## (pos, y, clear) → радиус обзора в непогоду (ThreatDirector.visibility)

var pos := Vector2.ZERO
var finished := false

var _form := 0.0                         ## секунд телеграфа осталось
var _life := 0.0
var _fade := -1.0
var _damage_acc := 0.0
var _spin := 0.0
var _drift := Transform2D()              ## петля смещения: эллипс в своих осях → смещение от точки появления
var _drift_t := 0.0
var _drift_phase := 0.0
var _origin := Vector2.ZERO              ## точка появления (вершина сетки)
var _lost: VehicleState = null           ## машина погибла (её состояние) — воронка её не отпускает
var _mat: ShaderMaterial
var _foam: CPUParticles3D
var _audio: AudioStreamPlayer


func _init() -> void:
	name = "Whirlpool"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## Глубокая вода: 2+ яруса над центром тайла.
static func deep(q: TerrainQuery, t: Vector2i) -> bool:
	if q.water_tier(t.x, t.y) == TerrainQuery.NO_WATER:
		return false
	return q.water_depth(t.x + 0.5, t.y + 0.5) >= DEEP


## Вершина сетки v годится под водоворот: все четыре тайла вокруг неё — глубокая вода.
static func fits(q: TerrainQuery, v: Vector2i) -> bool:
	for o: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		if not deep(q, v + o):
			return false
	return true


## Место: вершина в r_min…r_max от машины, где водоворот помещается; ahead — направление движения
## машины (водоворот ставится по курсу — машина на него выйдет; в игре — за кадром, не проступает на
## глазах). Не нашлось — Vector2.INF.
static func find_spot(q: TerrainQuery, from: Vector2, ahead: Vector2, r_min: float, r_max: float,
		r: RandomNumberGenerator) -> Vector2:
	for i in SPOT_TRIES:
		var dir := Vector2.from_angle(r.randf() * TAU)
		if ahead.length_squared() > 0.01 and i < SPOT_TRIES / 2:
			dir = ahead.normalized().rotated(r.randf_range(-0.9, 0.9))
		var p := from + dir * r.randf_range(r_min, r_max)
		var v := Vector2i(roundi(p.x), roundi(p.y))
		if fits(q, v):
			return Vector2(v)
	return Vector2.INF


## Тяга водоворота в точке p, тайл/с²: к центру a(r) = pull / масса × (1 − r / pull_r) × k и вбок на
## SWIRL от неё (по спирали); дальше pull_r — ноль.
static func pull(r: BalanceRules, center: Vector2, p: Vector2, mass: float, k: float) -> Vector2:
	var d := p.distance_to(center)
	if d >= r.whirlpool_pull_r or d < 0.01:
		return Vector2.ZERO
	var a := r.whirlpool_pull_accel / mass * (1.0 - d / r.whirlpool_pull_r) * k
	var n := (center - p) / d
	return (n + Vector2(-n.y, n.x) * SWIRL) * a


func begin(center: Vector2) -> void:
	pos = center
	_origin = center
	_pick_drift()
	_form = rules.whirlpool_form_s
	_life = rng.randf_range(rules.whirlpool_life_min_s, rules.whirlpool_life_max_s)
	var t := Grid.tile_of_world(pos.x, pos.y)
	position = Vector3(pos.x, Grid.tier_to_y(query.water_tier(t.x, t.y)) + 0.02, pos.y)
	_build()
	EventBus.vehicle_died.connect(_on_vehicle_died)


func step(dt: float) -> void:
	if finished:
		return
	if _audio.stream == null:
		_start_sound()
	var k := 1.0                           # сила: телеграф — растёт, конец — гаснет
	if _fade >= 0.0:
		_fade -= dt
		k = maxf(_fade / FADE_S, 0.0)
		if _fade <= 0.0:
			# Угасла. Глубина ядра слабела вместе с воронкой — живая машина почти всплыла, всплывает до
			# конца; утонувшая (погибла в ядре) или разбитая так и остаётся под водой.
			_affect_vehicle(dt, 0.0)
			finished = vehicle.state.pull_under <= 0.0 or _gone()
			return
	elif _form > 0.0:
		_form -= dt
		k = 1.0 - maxf(_form / rules.whirlpool_form_s, 0.0)
	else:
		_life -= dt
		if _life <= 0.0:
			_fade = FADE_S
			_foam.emitting = false
	_drift_t += dt
	pos = _drift_at(_drift_t)
	position.x = pos.x
	position.z = pos.y
	_affect_vehicle(dt, k if _form <= 0.0 else 0.0)
	_spin += dt * (2.0 + 6.0 * k)
	_foam.rotation.y = _spin * FOAM_TURN      # поворот вокруг +Y — частицы к убыванию угла, как и тяга
	_mat.set_shader_parameter(&"grow", k)
	_mat.set_shader_parameter(&"spin", _spin)
	_foam.emitting = _form <= 0.0 and _fade < 0.0
	var d := vehicle.state.pos.distance_to(pos)
	# Точки пены — обычный материал, пелена их не гасит: дальше обзора в тумане и пыли — не видны (диск прячет шейдер).
	_foam.visible = not sight.is_valid() or d - SIZE <= float(sight.call(vehicle.state.pos, vehicle.state.y, INF))
	_audio.volume_db = linear_to_db(clampf((1.0 - d / HEAR_TILES) * maxf(k, 0.2), 0.02, 1.0)) - 8.0


## Петля смещения: эллипс (полуоси R и 0,6 R) со случайным поворотом и фазой, сдвинутый так, что в начале
## воронка — в точке появления. Берётся наибольший из DRIFT_R, при котором на всём пути под центром
## 2×2 глубоких тайла; ни один не годится — стоит на месте.
func _pick_drift() -> void:
	var turn := rng.randf() * TAU
	_drift_phase = rng.randf() * TAU
	for radius in DRIFT_R:
		_drift = Transform2D(turn, Vector2.ZERO).scaled_local(Vector2(radius, radius * 0.6))
		var ok := true
		for i in DRIFT_SAMPLES:
			var p := _drift_at(DRIFT_PERIOD_S * i / DRIFT_SAMPLES)
			if not fits(query, Vector2i(roundi(p.x), roundi(p.y))):
				ok = false
				break
		if ok:
			return
	_drift = Transform2D(0.0, Vector2.ZERO).scaled_local(Vector2.ZERO)


## Центр воронки через t секунд после появления.
func _drift_at(t: float) -> Vector2:
	var a := _drift_phase + TAU * t / DRIFT_PERIOD_S
	var on := _drift.basis_xform(Vector2(cos(a), sin(a)))
	var start := _drift.basis_xform(Vector2(cos(_drift_phase), sin(_drift_phase)))
	return _origin + on - start


## Тяга по воде к центру с закруткой (сила k — гаснет к концу); ядро топит — машина уходит в воду
## (ховер — отчасти, и его болтает) и получает урон, пока не вырвется.
func _affect_vehicle(dt: float, k: float) -> void:
	if _gone():
		return                             # утонувшую и разбитую не трогаем: остаются под водой
	var s := vehicle.state
	var on_water := query.water_tier(s.tile.x, s.tile.y) != TerrainQuery.NO_WATER
	var d := s.pos.distance_to(pos)
	var in_core := k > 0.0 and on_water and d <= rules.whirlpool_core_r and not s.falling and not s.drowning
	s.pull_under = sink_step(s.pull_under, sink_depth(vehicle.cls, k) if in_core else 0.0, dt)
	s.churn = clampf(s.pull_under / HOVER_SINK, 0.0, 1.0) if vehicle.cls.hovers else 0.0
	if in_core:
		_damage_acc += rules.whirlpool_core_dps * dt
		if _damage_acc >= DAMAGE_STEP:
			_damage_acc -= DAMAGE_STEP
			damaged.emit(DAMAGE_STEP, &"whirlpool")
	if k <= 0.0 or not on_water or s.falling or s.drowning:
		return
	s.ext_accel += pull(rules, pos, s.pos, vehicle.cls.mass, k)


## Глубина, на которую ядро воронки силы k затягивает машину класса cls (доля полного погружения):
## ховер — до HOVER_SINK, без подушки — целиком; слабеющая воронка отпускает.
static func sink_depth(cls: VehicleClass, k: float) -> float:
	return (HOVER_SINK if cls.hovers else 1.0) * clampf(k, 0.0, 1.0)


## Погружение за шаг: к depth — вниз за SINK_S на всю глубину, вверх за SURFACE_S.
static func sink_step(pull_under: float, depth: float, dt: float) -> float:
	if pull_under < depth:
		return minf(pull_under + dt / SINK_S, depth)
	return maxf(pull_under - dt / SURFACE_S, depth)


## Машина погибла (утонула в ядре — или что угодно ещё) или разбита: воронка её больше не трогает.
func _gone() -> bool:
	return vehicle.wrecked or _lost == vehicle.state


## Конец забега: погибла в ядре — уходит под воду целиком и там остаётся, болтанка стихает. Шаги угроз
## после конца забега не идут — погружение доигрывает твин.
func _on_vehicle_died(_cause: StringName) -> void:
	if vehicle == null or finished or not is_inside_tree():
		return
	var s := vehicle.state
	_lost = s
	s.churn = 0.0
	if s.pull_under > 0.0:
		create_tween().tween_property(s, ^"pull_under", 1.0, (1.0 - s.pull_under) * SINK_S)


## Воронка — плоский диск со спиралью пены (шейдер), пена по кругу сбегается к центру, гул — петля
## ветра смерча, ниже тоном.
func _build() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = SWIRL_SHADER
	_mat.render_priority = 1               # поверх прозрачной воды, а не под ней
	_mat.set_shader_parameter(&"foam", COLOR_FOAM)
	_mat.set_shader_parameter(&"deep", COLOR_DEEP)
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * SIZE * 2.0
	_mat.set_shader_parameter(&"size", SIZE * 2.0)
	var disc := MeshInstance3D.new()
	disc.mesh = plane
	disc.material_override = _mat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
	_foam = CPUParticles3D.new()
	_foam.amount = 18
	_foam.lifetime = 1.2
	_foam.emitting = false
	_foam.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_foam.emission_ring_axis = Vector3.UP
	_foam.emission_ring_radius = SIZE
	_foam.emission_ring_inner_radius = SIZE * 0.8
	_foam.emission_ring_height = 0.02
	_foam.direction = Vector3.UP
	_foam.spread = 10.0
	_foam.initial_velocity_min = 0.05
	_foam.initial_velocity_max = 0.15
	_foam.gravity = Vector3.ZERO
	_foam.radial_accel_min = -1.6
	_foam.radial_accel_max = -1.0
	_foam.local_coords = true                # кольцо пены поворачивается вместе с узлом (step)
	_foam.mesh = PixelFx.quad(1, COLOR_FOAM_DOTS)
	_foam.position = Vector3(0, 0.03, 0)
	add_child(_foam)
	_audio = AudioStreamPlayer.new()
	_audio.pitch_scale = 0.55
	_audio.volume_db = -40.0
	add_child(_audio)


## Гул включается с первым шагом: образец воронки в прогреве шейдеров (Warmup) не шагает — молчит и не
## заставляет синтезировать гул раньше очереди (Sfx).
func _start_sound() -> void:
	_audio.stream = Sfx.named(&"wind")
	_audio.play()
