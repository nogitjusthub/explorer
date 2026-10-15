class_name Stargazer
extends Creature
## Троеглазка (GDD §5.6; облик — SHK-04 в docs/CREATURE_OPTIONS.md) — донный электрошокер мелкой воды.
## Плоское треугольное тело зарыто в дно вровень с грунтом: под водой видны лишь три века-«камешка»
## по углам крышки, и на них изредка мелькает блик. Не двигается и не гонится (aggressive не бывает).
## Машина ближе EYE1_R — открывается алый глаз (ближний к ней), ближе EYE2_R — второй: глаза — шкала
## дистанции. Машина в воде (или ховер над водой) ближе ray_shock_r — мгновенный разряд: открывается
## третий глаз, крышка откидывается на шарнире на 30° к машине, пластины за глазами вспыхивают янтарём,
## голубые дуги бьют в машину (ховеру — в днище), со дна поднимается облачко песка; урон ray_damage и инверсия управления на shock_invert_s. Перезарядка
## ray_cooldown_min_s…max_s от разряда: крышка ложится, глаза закрываются, пластины тлеют и гаснут; заряд
## готов — веки вспыхивают по очереди и снова поблёскивают. На суше, в полёте и тонущую машину не бьёт.
## Светящиеся части (глаза, блики, пластины) сдвинуты к камере вдоль луча зрения до зеркала воды: камера
## ортографическая, на экране они там же, но вода их не гасит. Вдали от машины — только таймер бликов.

enum State { READY, DISCHARGE, RECHARGE }

const SHALLOW_MIN := 0.15                ## ярусов воды над центром тайла — уже «вода»…
const SHALLOW_MAX := 1.0                 ## …и не глубже яруса

const LID_COLOR := Color(0.557, 0.525, 0.627)     ## #8E86A0 — в тон песчаного дна
const RIM_COLOR := Color(0.357, 0.31, 0.42)       ## #5B4F6B
const GLINT_COLOR := Color(1.0, 0.95, 0.816)      ## #FFF2D0 — блик на мокром веке
const EYE_COLOR := Color(1.0, 0.25, 0.2)          ## #FF4033 — как глаза скакунов
const PLATE_COLOR := Color(1.0, 0.69, 0.25)       ## #FFB040 — пластины в разряде
const EMBER_COLOR := Color(0.6, 0.32, 0.12)       ## пластины тлеют
const ARC_COLOR := Color(0.85, 0.92, 1.0)         ## #D9EBFF — как молния
const ARC_GLOW := Color(0.55, 0.7, 1.0, 0.45)
const SAND_PUFF := Color(0.66, 0.58, 0.68)        ## муть со дна: песок…
const GROUND_PUFF := Color(0.55, 0.4, 0.33)       ## …или грунт

const R_LID := 0.26                      ## крышка: радиус описанной окружности (сторона ≈ 0,45 тайла)
const R_RIM := 0.29                      ## кромка — чуть шире и ниже крышки
const R_IN := R_LID * 0.5                ## до середины стороны — там шарнир
const LID_H := 0.04
const LID_TOP := 0.01                    ## верх крышки над грунтом — вровень с дном
const EYE_AT := 0.16                     ## глаз — от центра к углу
const EYE_R := 0.05
const PLATE_AT := 0.07                   ## пластина — за глазом, ближе к центру
const EYELID_OPEN := 1.9                 ## рад — веко откидывается назад
const LID_TILT := 0.5236                 ## рад (30°) — крышка на шарнире при разряде
const WATER_DROP := 0.06                 ## меш воды ниже яруса зеркала на столько (ChunkMesher.build_water)
const REST_TOP := LID_TOP + 0.02         ## верх век в покое — должен быть под водой
const CLEAR := 0.01
const GLOW_LIFT := 0.015                 ## светящиеся части — над зеркалом воды на столько

const EYE1_R := 2.5                      ## машина ближе — открыт первый глаз…
const EYE2_R := 1.7                      ## …ближе — второй; третий — только в разряде
const FAR_R := 6.0                       ## дальше — только блики
const WET_DEPTH := 0.05                  ## ярусов воды под машиной — она в воде (как вброд в кинематике)
const ABOVE_MAX := 0.35                  ## днище выше зеркала больше чем на столько — не «над водой»
const EYE_SPEED := 12.0                  ## доля раскрытия глаза в секунду
const BLINK_S := 0.3                     ## глаз открывается с морганием:
const BLINK_FROM := 0.33                 ## …с этой доли BLINK_S веко снова закрыто…
const BLINK_TO := 0.6                    ## …до этой
const GLINT_EVERY_MIN := 1.0             ## блик на веке — раз в 1–2 с, на одном глазу
const GLINT_EVERY_MAX := 2.0
const GLINT_S := 0.1
const READY_STEP_S := 0.15               ## заряд готов — веки вспыхивают по очереди
const DISCHARGE_S := 0.45
const ARCS := 2
const ARC_SEGS := 4
const ARC_S := 0.32
const ARC_JAG_S := 0.05                  ## дуги перескакивают
const ARC_W := Grid.ART_PX               ## толщина дуги разряда — пиксель мира
const LIGHT_S := 0.12
const LID_UP_SPEED := 12.0               ## рад/с — крышка откидывается рывком…
const LID_DOWN_SPEED := 0.9              ## …и ложится медленно
const EMBER_S := 1.6
const PLACE_S := 1.0                     ## тело ложится на дно заново раз в столько (рельеф меняется)

const DOME_OFF := 0
const DOME_GLINT := 1
const DOME_EYE := 2

var state := State.READY

var _phase := 0.0                        ## поворот треугольника
var _dirs := PackedVector3Array()        ## единичные направления на углы (в плоскости тела)
var _water_y := 0.0                      ## высота меша воды над троеглазкой
var _lift := 0.0                         ## на столько светящиеся части поднимаются к зеркалу воды
var _fx_rng := RandomNumberGenerator.new()   ## для внешнего вида: решения (перезарядка) — от rng
var _time := 0.0
var _idle := true                        ## покой: заряжена, глаза закрыты, эффекты погасли
var _far := true                         ## в прошлом шаге машина была далеко
var _place_t := PLACE_S                  ## до следующей укладки тела на дно (_place)
var _charge := 0.0                       ## до готовности разряда, с
var _timer := 0.0
var _order := PackedInt32Array()         ## открытые глаза — в порядке открытия
var _open := PackedFloat32Array([0.0, 0.0, 0.0])
var _shown := PackedFloat32Array([0.0, 0.0, 0.0])    ## раскрытие с учётом моргания
var _blink := PackedFloat32Array([0.0, 0.0, 0.0])
var _dome_mode := PackedInt32Array([DOME_OFF, DOME_OFF, DOME_OFF])
var _glint_eye := -1
var _glint_t := 0.0
var _glint_wait := 0.0
var _ready_seq := -1.0
var _hinge := 0                          ## угол, который поднимается при разряде
var _tilt := 0.0
var _ember := 0.0
var _arc_t := -1.0
var _arc_jag := 0.0

var _root: Node3D                        ## тело на дне (наклон по дну)
var _lid: Node3D                         ## крышка на шарнире
var _eyelids: Array[Node3D] = []
var _glow: Node3D                        ## светящиеся части — копия позы крышки, сдвинутая к камере
var _domes: Array[MeshInstance3D] = []
var _plates: Node3D
var _eye_mat: StandardMaterial3D
var _glint_mat: StandardMaterial3D
var _plate_mat: StandardMaterial3D
var _fx: Node3D                          ## дуги, вспышка, муть — строятся, когда машина подъехала
var _arc_core: Array[MeshInstance3D] = []
var _arc_glow: Array[MeshInstance3D] = []
var _light: OmniLight3D
var _puff: CPUParticles3D


func _init() -> void:
	name = "Stargazer"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## Мелкая вода: глубина над центром тайла от SHALLOW_MIN до SHALLOW_MAX.
static func habitat(q: TerrainQuery, t: Vector2i) -> bool:
	if q.water_tier(t.x, t.y) == TerrainQuery.NO_WATER:
		return false
	var d := q.water_depth(t.x + 0.5, t.y + 0.5)
	return d >= SHALLOW_MIN and d <= SHALLOW_MAX


## Тайл осушен: воды нет или над центром мельче SHALLOW_MIN (засыпка ямы, вал, разлом подняли дно).
static func dried(q: TerrainQuery, t: Vector2i) -> bool:
	return q.water_tier(t.x, t.y) == TerrainQuery.NO_WATER or q.water_depth(t.x + 0.5, t.y + 0.5) < SHALLOW_MIN


## Сколько глаз открыто на дистанции d (вне разряда): 0, 1 или 2.
static func eyes_for(d: float) -> int:
	return 2 if d < EYE2_R else (1 if d < EYE1_R else 0)


## Разряд достаёт машину: ближе shock_r, в воде или над ней (не на суше), не в полёте и не тонет.
static func in_reach(q: TerrainQuery, at: Vector2, s: VehicleState, shock_r: float) -> bool:
	if s.falling or s.launched or s.drowning:
		return false
	if at.distance_squared_to(s.pos) >= shock_r * shock_r:
		return false
	var w := q.water_tier(floori(s.pos.x), floori(s.pos.y))
	if w == TerrainQuery.NO_WATER or q.water_depth(s.pos.x, s.pos.y) <= WET_DEPTH:
		return false
	return s.y <= Grid.tier_to_y(w) + ABOVE_MAX


## Перезарядка после разряда, с.
static func cooldown(r: BalanceRules, g: RandomNumberGenerator) -> float:
	return g.randf_range(r.ray_cooldown_min_s, r.ray_cooldown_max_s)


func setup(at: Vector2) -> void:
	pos = at
	_phase = rng.randf() * TAU
	_fx_rng.seed = rng.randi()
	_glint_wait = _fx_rng.randf_range(0.0, GLINT_EVERY_MAX)
	_place_t = _fx_rng.randf_range(0.0, PLACE_S)       # укладки троеглазок — вразнобой, не в одном кадре
	for i in 3:
		var a := _phase + TAU * i / 3.0
		_dirs.append(Vector3(cos(a), 0.0, sin(a)))
	_build()
	_place()
	_pose_glow()


## Сколько глаз открыто сейчас (в разряде — три).
func open_eyes() -> int:
	return _order.size()


func step(dt: float) -> void:
	var s := vehicle.state
	var d2 := pos.distance_squared_to(s.pos)
	# Рельеф могли изменить (засыпка ямы после сборки чанка, воронка, землетрясение, борозда смерча) — тело
	# ложится на дно заново раз в PLACE_S и вдали (оно видно и оттуда), и вблизи. Тайл осушило — троеглазка
	# уходит (углубило — остаётся на новом дне).
	_place_t -= dt
	var replace := _place_t <= 0.0
	if replace:
		_place_t = PLACE_S
		if dried(query, Grid.tile_of_world(pos.x, pos.y)):
			_leave()
			return
		_place()
	if _idle and d2 > FAR_R * FAR_R:
		_far = true
		if replace:
			_pose_glow()
		if _tick_glint(dt):
			_show_domes()
		return
	if _far:
		_far = false
		_place()
		_ensure_fx()
	_time += dt
	match state:
		State.READY:
			if not vehicle.wrecked and in_reach(query, pos, s, rules.ray_shock_r):
				_discharge()
		State.DISCHARGE:
			_charge -= dt
			_timer -= dt
			if _timer <= 0.0:
				state = State.RECHARGE
				_ember = EMBER_S
		State.RECHARGE:
			_charge -= dt
			if _charge <= 0.0:
				state = State.READY
				_ready_seq = 0.0
				_glint_wait = _fx_rng.randf_range(GLINT_EVERY_MIN, GLINT_EVERY_MAX)
	if state != State.DISCHARGE:
		_ember = maxf(_ember - dt, 0.0)
	if _ready_seq >= 0.0:
		_ready_seq += dt
		if _ready_seq > 3.0 * READY_STEP_S + GLINT_S:
			_ready_seq = -1.0
	_tick_glint(dt)
	_update_eyes(dt, sqrt(d2))
	_update_lid(dt)
	_pose_glow()
	_update_plates()
	_update_fx(dt)
	_idle = state == State.READY and _order.is_empty() and _tilt <= 0.0 and _ember <= 0.0 \
			and _arc_t < 0.0 and _ready_seq < 0.0 and _eyes_shut()


## Мелкой воды под троеглазкой больше нет: закапывается — облачко пыли и комья грунта (живут у родителя:
## саму троеглазку директор сразу убирает по finished).
func _leave() -> void:
	finished = true
	visible = false
	if get_parent() == null:
		return
	var at := Vector3(pos.x, ground_y(pos), pos.y)
	var dust := PixelFx.dust(10, 0.9)
	dust.color = PixelFx.dust_color(query, pos.x, pos.y)
	var clods := PixelFx.clods(6, 0.5)
	clods.color = PixelFx.clod_color(query, pos.x, pos.y)
	for p: CPUParticles3D in [dust, clods]:
		p.one_shot = true
		p.explosiveness = 1.0
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = R_LID
		p.spread = 60.0
		p.initial_velocity_min = 0.5
		p.initial_velocity_max = 1.3
		p.finished.connect(p.queue_free)
		get_parent().add_child(p)
		p.global_position = at
		p.emitting = true


## Разряд: урон и инверсия машине, третий глаз, крышка на шарнире, пластины, дуги, муть.
func _discharge() -> void:
	state = State.DISCHARGE
	_timer = DISCHARGE_S
	_charge = cooldown(rules, rng)
	_ember = 0.0
	_ready_seq = -1.0
	_glint_eye = -1
	for i in 3:
		_blink[i] = 0.0
	var s := vehicle.state
	var to := s.pos - pos
	# Поднимается дальний от машины угол: шарнир — у ближней стороны, крышка смотрит на машину.
	var best := INF
	for i in 3:
		var k := Vector2(_dirs[i].x, _dirs[i].z).dot(to)
		if k < best:
			best = k
			_hinge = i
	_tilt = 0.0
	_ensure_fx()
	_arc_t = 0.0
	_arc_jag = 0.0
	_light.visible = true
	_puff.position = _root.position + Vector3(0, 0.05, 0)
	_puff.restart()
	_puff.emitting = true
	damaged.emit(rules.ray_damage, &"ray")
	vehicle.invert_controls(rules.shock_invert_s)
	vehicle.rock(Vehicle.ROCK_BITE, to)
	EventBus.camera_shake_requested.emit(0.35, 0.25)
	EventBus.fauna_alerted.emit(&"ray_shock", Vector3(pos.x, _water_y, pos.y))


## Блик на закрытом веке раз в 1–2 с (только заряженная). true — какой глаз блестит, изменилось.
func _tick_glint(dt: float) -> bool:
	if _glint_eye >= 0:
		_glint_t -= dt
		if _glint_t > 0.0:
			return false
		_glint_eye = -1
		return true
	if state != State.READY:
		return false
	_glint_wait -= dt
	if _glint_wait > 0.0:
		return false
	_glint_wait = _fx_rng.randf_range(GLINT_EVERY_MIN, GLINT_EVERY_MAX)
	var e := _fx_rng.randi() % 3
	if _order.has(e):
		return false                      # открытый глаз не блестит
	_glint_eye = e
	_glint_t = GLINT_S
	if _far:
		_pose_glow()                      # камеру могли повернуть
	return true


## Глаза: сколько открыто — по дистанции (в разряде все три, в перезарядке ни одного); новый — ближний
## к машине, открывается с морганием; веко откидывается.
func _update_eyes(dt: float, d: float) -> void:
	var n := 0
	if state == State.READY:
		n = eyes_for(d)
	elif state == State.DISCHARGE:
		n = 3
	while _order.size() < n:
		var e := _nearest_closed()
		_order.append(e)
		if state == State.READY:
			_blink[e] = BLINK_S
		if e == _glint_eye:
			_glint_eye = -1
	while _order.size() > n:
		_order.remove_at(_order.size() - 1)
	for i in 3:
		var target := 1.0 if _order.has(i) else 0.0
		_open[i] = target if state == State.DISCHARGE else move_toward(_open[i], target, EYE_SPEED * dt)
		var k := _open[i]
		if _blink[i] > 0.0:
			_blink[i] = maxf(_blink[i] - dt, 0.0)
			var b := 1.0 - _blink[i] / BLINK_S
			if b > BLINK_FROM and b < BLINK_TO:
				k = 0.0
		_shown[i] = k
		_eyelids[i].rotation.x = -k * EYELID_OPEN
	_show_domes()


func _nearest_closed() -> int:
	var vp := vehicle.state.pos
	var best := -1
	var best_d := INF
	for i in 3:
		if _order.has(i):
			continue
		var d := (pos + Vector2(_dirs[i].x, _dirs[i].z) * EYE_AT).distance_squared_to(vp)
		if d < best_d:
			best_d = d
			best = i
	return best


func _eyes_shut() -> bool:
	for i in 3:
		if _open[i] > 0.0 or _blink[i] > 0.0:
			return false
	return true


## Купола глаз: алый — открыт, бледный — блик на веке, иначе скрыт.
func _show_domes() -> void:
	for i in 3:
		var k := _shown[i]
		var mode := DOME_OFF
		if k > 0.3:
			mode = DOME_EYE
		elif i == _glint_eye or _ready_glint(i):
			mode = DOME_GLINT
		var dome := _domes[i]
		if mode != _dome_mode[i]:
			_dome_mode[i] = mode
			dome.visible = mode != DOME_OFF
			if mode == DOME_GLINT:
				dome.material_override = _glint_mat
				dome.scale = Vector3.ONE * 0.8
			elif mode == DOME_EYE:
				dome.material_override = _eye_mat
		if mode == DOME_EYE:
			dome.scale = Vector3.ONE * (0.6 + 0.4 * k)


func _ready_glint(i: int) -> bool:
	if _ready_seq < 0.0 or _order.has(i):
		return false
	var t := _ready_seq - i * READY_STEP_S
	return t >= 0.0 and t < GLINT_S


## Крышка: в разряде рывком откидывается на шарнире у ближней к машине стороны, потом медленно ложится.
func _update_lid(dt: float) -> void:
	var target := LID_TILT if state == State.DISCHARGE else 0.0
	var speed := LID_UP_SPEED if state == State.DISCHARGE else LID_DOWN_SPEED
	var t := move_toward(_tilt, target, speed * dt)
	if t == _tilt:
		return
	_tilt = t
	var c := _dirs[_hinge]
	var b := Basis(c.cross(Vector3.UP).normalized(), _tilt)
	var pivot := -c * R_IN
	_lid.transform = Transform3D(b, pivot - b * pivot)


## Светящиеся части — поза крышки, сдвинутая к камере вдоль луча зрения до зеркала воды.
func _pose_glow() -> void:
	var back := Vector3.UP
	if is_inside_tree():
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			back = cam.global_basis.z
	var shift := back * (_lift / maxf(back.y, 0.2))
	_glow.transform = Transform3D(Basis(), shift) * _root.transform * _lid.transform


## Пластины: вспышка янтарём в разряде, тлеют и гаснут в начале перезарядки.
func _update_plates() -> void:
	if state == State.DISCHARGE:
		_plates.visible = true
		_plate_mat.albedo_color = PLATE_COLOR.lightened(0.45) if fmod(_time, 0.08) < 0.04 else PLATE_COLOR
	elif _ember > 0.0:
		var k := _ember / EMBER_S
		_plate_mat.albedo_color = EMBER_COLOR.lerp(PLATE_COLOR, k * k)
		_plates.visible = k > 0.45 or fmod(_time, 0.1 + (1.0 - k) * 0.25) < 0.06    # гаснут, мигая
	else:
		_plates.visible = false


## Дуги перескакивают за машиной, вспышка света.
func _update_fx(dt: float) -> void:
	if _arc_t >= 0.0:
		_arc_t += dt
		if _arc_t >= ARC_S:
			_arc_t = -1.0
			for m in _arc_core:
				m.visible = false
			for m in _arc_glow:
				m.visible = false
		else:
			_arc_jag -= dt
			if _arc_jag <= 0.0:
				_arc_jag = ARC_JAG_S
				_pose_arcs()
		_light.visible = _arc_t >= 0.0 and _arc_t < LIGHT_S


## Дуги — ломаные от пластин к машине: в борт у ватерлинии, ховеру — снизу в днище.
func _pose_arcs() -> void:
	var s := vehicle.state
	var hit := Vector3(s.pos.x, maxf(s.y + 0.22, _water_y + 0.05), s.pos.y)
	if vehicle.cls.hovers:
		hit = Vector3(s.pos.x, s.y + 0.02, s.pos.y)
	var first := _fx_rng.randi() % 3
	for a in ARCS:
		var shown := _arc_t < ARC_JAG_S or _fx_rng.randf() < 0.85
		var j := (first + a) % 3
		var from := _glow.transform * (_dirs[j] * PLATE_AT + Vector3(0, LID_TOP + 0.01, 0))
		var to := hit + Vector3(_fx_rng.randf_range(-0.15, 0.15), _fx_rng.randf_range(-0.04, 0.04),
				_fx_rng.randf_range(-0.15, 0.15))
		if a == 0:
			_light.position = (from + to) * 0.5
		var prev := from
		for k in ARC_SEGS:
			var p := to
			if k < ARC_SEGS - 1:
				p = from.lerp(to, float(k + 1) / ARC_SEGS) + Vector3(_fx_rng.randf_range(-0.1, 0.1),
						_fx_rng.randf_range(-0.06, 0.06), _fx_rng.randf_range(-0.1, 0.1))
			_segment(a * ARC_SEGS + k, prev, p, shown)
			prev = p


func _segment(i: int, a: Vector3, b: Vector3, shown: bool) -> void:
	var core := _arc_core[i]
	var glow := _arc_glow[i]
	core.visible = shown
	glow.visible = shown
	if not shown:
		return
	var d := b - a
	var l := d.length()
	var rot := Basis(Quaternion(Vector3.UP, d / l)) if l > 0.001 else Basis()
	var mid := (a + b) * 0.5
	core.transform = Transform3D(rot * Basis.from_scale(Vector3(ARC_W, l + ARC_W, ARC_W)), mid)
	glow.transform = Transform3D(rot * Basis.from_scale(Vector3(ARC_W * 3.0, l + ARC_W, ARC_W * 3.0)), mid)   # ореол — пиксель вокруг


## Тело на дне: наклон по нормали дна; зарыто глубже, если иначе веки высунутся из мелкой воды.
func _place() -> void:
	var y := ground_y(pos)
	var b := Basis(Quaternion(Vector3.UP, query.normal_at(pos.x, pos.y)))
	_root.transform = Transform3D(b, Vector3(pos.x, y, pos.y))
	var t := Grid.tile_of_world(pos.x, pos.y)
	var w := query.water_tier(t.x, t.y)
	_water_y = Grid.tier_to_y(w) - WATER_DROP if w != TerrainQuery.NO_WATER else y + 1.0
	var hi := -INF
	var lo := INF
	for i in 3:
		hi = maxf(hi, (_root.transform * (_dirs[i] * R_LID + Vector3(0, REST_TOP, 0))).y)
		lo = minf(lo, (_root.transform * (_dirs[i] * EYE_AT + Vector3(0, LID_TOP, 0))).y)
	var sink := maxf(hi - (_water_y - CLEAR), 0.0)
	_root.position.y -= sink
	_lift = maxf(_water_y + GLOW_LIFT - (lo - sink), 0.0)


## Тело: кромка и крышка — треугольные призмы, на крышке три века; светящиеся части — отдельно (_glow).
func _build() -> void:
	_root = Node3D.new()
	add_child(_root)
	_mesh_off(MeshKit.prism(_root, MeshKit.ngon(3, R_RIM, _phase), LID_TOP - 0.03, 0.02,
			Creature.skin(RIM_COLOR, BodyMaterial.Pattern.PEBBLE, Grid.ART_PX / 2.0)))   # галька — 2×2 px узора
	_lid = Node3D.new()
	_root.add_child(_lid)
	_mesh_off(MeshKit.prism(_lid, MeshKit.ngon(3, R_LID, _phase), LID_TOP - LID_H, LID_H,
			Creature.skin(LID_COLOR, BodyMaterial.Pattern.PEBBLE, Grid.ART_PX / 2.0)))
	var pebble := Creature.skin(LID_COLOR.lightened(0.15), BodyMaterial.Pattern.PEBBLE, Grid.ART_PX / 2.0)
	var lid_box := BoxMesh.new()
	lid_box.size = Vector3(0.1, 0.02, 0.09)
	for i in 3:
		var hinge := Node3D.new()           # шарнир века — у внутреннего края, веко откидывается к центру
		hinge.position = _dirs[i] * (EYE_AT - 0.045) + Vector3(0, LID_TOP, 0)
		hinge.rotation.y = PI * 0.5 - (_phase + TAU * i / 3.0)
		_lid.add_child(hinge)
		var eyelid := MeshInstance3D.new()
		eyelid.mesh = lid_box
		eyelid.material_override = pebble
		eyelid.position = Vector3(0, 0.01, 0.045)
		_mesh_off(eyelid)
		hinge.add_child(eyelid)
		_eyelids.append(hinge)
	_glow = Node3D.new()
	add_child(_glow)
	_eye_mat = _unshaded(EYE_COLOR)
	_glint_mat = _unshaded(GLINT_COLOR)
	_plate_mat = _unshaded(PLATE_COLOR)
	var dome_mesh := SphereMesh.new()
	dome_mesh.radius = EYE_R
	dome_mesh.height = EYE_R
	dome_mesh.is_hemisphere = true
	dome_mesh.radial_segments = 6
	dome_mesh.rings = 2
	for i in 3:
		var dome := MeshInstance3D.new()
		dome.mesh = dome_mesh
		dome.material_override = _glint_mat
		dome.position = _dirs[i] * EYE_AT + Vector3(0, LID_TOP, 0)
		dome.visible = false
		_mesh_off(dome)
		_glow.add_child(dome)
		_domes.append(dome)
	_plates = Node3D.new()
	_plates.visible = false
	_glow.add_child(_plates)
	var plate_box := BoxMesh.new()
	plate_box.size = Vector3(0.12, 0.012, 0.05)
	for i in 3:
		var plate := MeshInstance3D.new()
		plate.mesh = plate_box
		plate.material_override = _plate_mat
		plate.position = _dirs[i] * PLATE_AT + Vector3(0, LID_TOP + 0.006, 0)
		plate.rotation.y = PI * 0.5 - (_phase + TAU * i / 3.0)
		_mesh_off(plate)
		_plates.add_child(plate)


## Эффекты разряда — один раз, когда машина впервые подъехала (вдали троеглазка — только тело).
func _ensure_fx() -> void:
	if _fx != null:
		return
	_fx = Node3D.new()
	add_child(_fx)
	var unit := BoxMesh.new()
	var core := _unshaded(ARC_COLOR)
	var glow := _unshaded(ARC_GLOW)
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.render_priority = 1              # поверх воды
	for i in ARCS * ARC_SEGS:
		_arc_core.append(_fx_mesh(unit, core))
		_arc_glow.append(_fx_mesh(unit, glow))
	_light = OmniLight3D.new()
	_light.light_color = Color(0.75, 0.85, 1.0)
	_light.light_energy = 0.7
	_light.omni_range = 1.8
	_light.shadow_enabled = false
	_light.visible = false
	_fx.add_child(_light)
	_puff = CPUParticles3D.new()
	_puff.one_shot = true
	_puff.explosiveness = 0.85
	_puff.emitting = false
	_puff.amount = 14
	_puff.lifetime = 1.1
	_puff.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_puff.emission_sphere_radius = 0.18
	_puff.direction = Vector3.UP
	_puff.spread = 70.0
	_puff.initial_velocity_min = 0.4
	_puff.initial_velocity_max = 0.9
	_puff.damping_min = 1.5            # муть всплывает и зависает в воде
	_puff.damping_max = 2.5
	_puff.gravity = Vector3.ZERO
	_puff.local_coords = false
	var t := Grid.tile_of_world(pos.x, pos.y)
	var sand := not query.is_loaded(t.x, t.y) or query.material(t.x, t.y) == ChunkData.Mat.SAND
	_puff.mesh = PixelFx.quad(2, SAND_PUFF if sand else GROUND_PUFF)
	_fx.add_child(_puff)


func _fx_mesh(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.visible = false
	_mesh_off(mi)
	_fx.add_child(mi)
	return mi


static func _unshaded(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	return m


## Без теней: светящиеся части сдвинуты к камере — их тень легла бы не туда; тело плоское.
static func _mesh_off(mi: MeshInstance3D) -> void:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
