class_name LakeMonster
extends Creature
## Несса (GDD §5.6; облик — LKM-01 в docs/CREATURE_OPTIONS.md) — редкое озёрное чудовище больших озёр,
## водная пара песчаного червя. Живёт и ходит только по глубокой воде (habitat, 2+ яруса), на сушу не
## выходит. Пока не охотится — таится под водой у места появления, изредка пускает пузыри.
## Машина на воде или у кромки, и с глубокой воды до неё достать шеей — охота: под водой видны только
## пузыри и V-след пены, вершина которого идёт к машине со скоростью nessie_speed (медленнее ховера);
## изредка на секунду всплывает горб, как спина дельфина. Путь — поиском в ширину по глубоким тайлам
## (plan) к ближайшей точке, откуда машина на длине шеи.
## Дошла — бросок. Появление EMERGE_S (телеграф): шея-колонна из дисков-«позвонков» раскладывается диск
## за диском, за ней встают три полосатых горба. Поза POSE_S («фото хирурга»): шея изгибается буквой S,
## голова смотрит на машину, пасть раскрыта, глотка горит алым (шея не мигает — поза и так читается); направление и длина
## удара фиксируются (линии на воде нет — куда упадёт шея, видно по позе). Удар STRIKE_S: шея валится,
## как подрубленная колонна, голова бьёт в точку удара — всплеск и кольцо пены. Машина у этой точки
## (in_impact_zone) — урон nessie_damage; ховер подбрасывает на nessie_toss тайла по линии удара,
## колёсную раскачивает. Потом погружение SUBMERGE_S (шея отдёргивается и уходит прямо вниз, складываясь,
## горбы тонут последними, остаются пузыри), передышка COOLDOWN_S и новый подход.
## Машина ушла дальше длины шеи + ESCAPE_MARGIN, пока Несса появлялась или стояла в позе, — не бьёт:
## WATCH — шея выпрямляется, голова поднята и следит за машиной до WATCH_S. Вернулась в досягаемость —
## поза и удар; нет — погружение, передышка и снова погоня (если интерес не потерян).
## Спасение — уйти с места, пока Несса в позе, или уплыть: не подобраться fauna_give_up_s — уходит в
## глубину и пропадает (finished).

enum State { LURK, APPROACH, EMERGE, WATCH, POSE, STRIKE, LIE, SUBMERGE, COOLDOWN, LEAVE }

const DEEP := 1.95                       ## ярусов воды над центром тайла — глубоко (2+)
const LAKE_R := 6                        ## «большое озеро» — считаем глубокие тайлы в этом радиусе

const BONE_COLOR := Color(0.749, 0.663, 0.769)     ## #BFA9C4 — широкие диски: бледно-лиловая кость
const NARROW_COLOR := Color(0.62, 0.54, 0.65)     ## #9E8AA6 — узкие звенья чуть темнее: рёбра, а не полосы
const HOT_COLOR := Color(1.0, 0.251, 0.2)          ## #FF4033 — телеграф: глотка в раскрытой пасти, unshaded
const JAW_COLOR := Color(0.949, 0.922, 0.82)       ## #F2EBD1
const THROAT_COLOR := Color(0.161, 0.059, 0.071)   ## #290F12
const FOAM_COLOR := Color(0.86, 0.97, 0.94)        ## пена — как у водоворота

# Шея и голова: элементы 0…DISCS − 1 — диски снизу вверх, DISCS — голова.
const DISCS := 6                         ## чётные — широкие 10-гранные, нечётные — узкие 8-гранные
const DISC_STEP := 0.48                  ## звенья длинные…
const DISC_OVERLAP := 1.4                ## …и заходят друг в друга: на изгибе шея остаётся цельной
const DISC_R0 := 0.28                    ## радиус широкого диска у основания…
const DISC_R1 := 0.15                    ## …и у головы
const NARROW := 0.93                     ## узкий диск — такая доля широкого (разница мягкая — шея одна колонна)
const TWIST := 0.41                      ## каждый диск повёрнут вокруг оси на свой угол, как у червя
const HEAD_R := 0.2                      ## основание морды
const HEAD_H := 0.12
const JAW_LEN := 0.45
const HEAD_LEN := HEAD_H + JAW_LEN       ## от основания морды до кончика сомкнутого клюва
const JAW_OPEN := -1.0                   ## рад — челюсти раскрыты
const BASE_SINK := 0.12                  ## основание шеи — под зеркалом воды
const SINK_ARC := 1.4                    ## до появления шея сложена на столько ниже основания
const HIDE_DEPTH := 0.4                  ## деталь глубже под зеркалом скрыта: глубокая вода почти непрозрачна
# Спина — дуга из таких же звеньев, как шея, выгибается из воды за шеей (петля морского змея).
const ARCH_SEGS := 7
const ARCH_R := 0.8                      ## радиус дуги…
const ARCH_DROP := 0.45                  ## …её центр под зеркалом: над водой — верх дуги высотой ARCH_R − ARCH_DROP
const ARCH_BEHIND := 0.6                 ## ближний конец дуги — за основанием шеи на столько
const BACK_R := 0.25                     ## толщина спины — как шея у основания
# Поза «фото хирурга» — наклон шеи от вертикали (+ — к машине): у основания, в изгибе и у головы.
const POSE_LEAN := 0.3
const POSE_BACK := -0.4
const POSE_TOP := 1.05
const POSE_MID := 0.5

# Бросок
const EMERGE_S := 1.0                    ## появление — телеграф
const UNFOLD_LAG := 0.05                 ## каждый диск трогается позже соседа сверху и догоняет
const POSE_S := 0.6                      ## поза — телеграф направления (не меньше 0,6 с — правило LKM)
const ESCAPE_MARGIN := 2.5               ## машина дальше nessie_reach + это — не бьёт, смотрит ей вслед
const WATCH_S := 2.5                     ## столько стоит с поднятой головой, потом уходит под воду
const WATCH_EASE_S := 0.35               ## шея выпрямляется из позы, пасть закрывается
const SNAP_S := 0.12                     ## шея изгибается в позу рывком
const STRIKE_S := 0.25                   ## шея валится
const LIE_S := 0.35                      ## лежит на воде после удара
const SUBMERGE_S := 1.0
const SINK_S := 0.75                     ## шея скрывается под водой за столько, горбы — позже
const COOLDOWN_S := 2.5
const BUBBLES_AFTER_S := 2.0             ## после погружения ещё пузырится
const LEAVE_S := 1.2                     ## сдалась: след гаснет, потом пропадает
const REACH_MIN := 2.0                   ## ближе к машине не бьёт — отплывает: шее нужен размах
const BAND_IN := 0.2                     ## точка подхода — машина в nessie_reach − BAND_OUT…REACH_MIN + BAND_IN
const BAND_OUT := 0.15
const HIT_BACK := 0.9                    ## зона головы: от точки удара назад…
const HIT_FRONT := 0.35                  ## …вперёд…
const HIT_HALF_W := 0.65                 ## …и в стороны
const CLIFF_MAX := 1.4                   ## машина выше воды больше чем на столько (мир) — шее не достать
const TOSS_APEX := 1.6
const TOSS_TILT := 0.45                  ## рад — наклон ховера в полёте

# Подход под водой
const PLAN_NODES := 900                  ## поиск пути — не больше стольких тайлов
const REPLAN_S := 0.5
const LURK_CHECK_S := 1.0
const LURK_R := 20.0                     ## таится: машину дальше не замечает
const LOSE_DIST := 30.0
const MEMO_S := 10.0                     ## память «глубоко ли» — забывается (рельеф меняется)
const TURN_RATE := 4.0                   ## рад/с — поворот V-следа
const WAKE_LEN := 2.4
const WAKE_ANGLE := 0.42                 ## рад — полураствор V-следа
const WAKE_W := 0.16
const HUMP_EVERY_MIN_S := 3.0            ## при подходе спина всплывает раз в столько…
const HUMP_EVERY_MAX_S := 5.5
const HUMP_SURFACE_S := 1.0              ## …на столько
const WATER_DROP := 0.06                 ## зеркало воды рисуется чуть ниже яруса (ChunkMesher)
const FOAM_LIFT := 0.03

const NEIGHBORS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
# Профиль челюсти (как у червя): доля радиуса морды на доле длины челюсти.
const JAW_U: Array[float] = [0.0, 0.25, 0.5, 0.72, 0.88, 1.0]
const JAW_R: Array[float] = [1.0, 0.97, 0.84, 0.62, 0.36, 0.0]


const FOAM_SHADER := preload("res://src/render/shaders/foam_strip.gdshader")   ## V-след

var state := State.LURK

var _timer := 0.0
var _time := 0.0
var _check := 0.0                        ## до следующей проверки (таится) или пересчёта пути (подход)
var _memo_age := 0.0
var _deep: Dictionary = {}               ## Vector2i → глубоко ли (память для plan)
var _path: Array[Vector2i] = []
var _path_i := 1
var _heading := Vector2.RIGHT            ## курс V-следа (сглаженный)
var _speed := 0.0                        ## фактическая скорость под водой, тайл/с
var _traveled := 0.0
var _wake_k := 0.0                       ## 0…1 — заметность V-следа
var _hump_wait := 0.0
var _dolphin := -1.0                     ## время всплытия горба при подходе (< 0 — горб под водой)
var _lurk_puff := 0.0
var met := false                         ## гналась за машиной — следующая Несса не раньше nessie_gap_s
var _watch_from := PackedFloat32Array()  ## WATCH: наклоны дисков, голова и пасть в начале — шея выпрямляется из них
var _watch_head := 0.0
var _watch_jaw := 0.0
var _water_y := 0.0                      ## мировая высота зеркала воды под Нессой

# Бросок
var _base := Vector2.ZERO                ## основание шеи — точка на глубокой воде
var _base3 := Vector3.ZERO
var _look := Vector2.RIGHT               ## плоскость шеи (голова смотрит сюда)
var _dir := Vector2.RIGHT                ## направление удара — зафиксировано с начала позы
var _length := 3.0                       ## длина удара: от основания шеи до точки удара
var _impact_at := Vector2.ZERO
var _impact_y := 0.0
var _fall := PI * 0.5                    ## наклон упавшей шеи от вертикали
var _scale := 1.0                        ## шея упавшая — от основания до кончика клюва ровно длина удара
var _pose_head := 0.0
var _head_theta := 0.0                   ## наклон головы в этом кадре
var _back := Vector2.LEFT                ## горбы — за шеей, сюда
var _theta := PackedFloat32Array()       ## наклон каждого диска от вертикали
var _arc := PackedFloat32Array()         ## положение элемента вдоль шеи от основания

var _body: Node3D
var _discs: Array[MeshInstance3D] = []
var _head: Node3D
var _jaws: Array[Node3D] = []
var _throat: MeshInstance3D
var _arch: Node3D                        ## спина-дуга; локальная +Z — вдоль спины
var _arch_segs: Array[MeshInstance3D] = []
var _arch_at := Vector2.ZERO
var _ring: MeshInstance3D                ## кольцо пены у основания шеи
var _wake: Node3D
var _arms: Array[MeshInstance3D] = []
var _bubbles: CPUParticles3D
var _splash: CPUParticles3D
var _bone: ShaderMaterial
var _narrow: ShaderMaterial
var _hot: StandardMaterial3D
var _throat_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D
var _wake_mat: ShaderMaterial


func _init() -> void:
	name = "LakeMonster"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## Глубокая вода (2+ яруса над центром тайла) — туда заходит только ховер.
static func habitat(q: TerrainQuery, t: Vector2i) -> bool:
	if q.water_tier(t.x, t.y) == TerrainQuery.NO_WATER:
		return false
	return q.water_depth(t.x + 0.5, t.y + 0.5) >= DEEP


## Большое озеро: в радиусе LAKE_R от тайла не меньше min_tiles глубоких тайлов.
static func big_lake(q: TerrainQuery, t: Vector2i, min_tiles: int) -> bool:
	var n := 0
	for dz in range(-LAKE_R, LAKE_R + 1):
		for dx in range(-LAKE_R, LAKE_R + 1):
			if dx * dx + dz * dz <= LAKE_R * LAKE_R and habitat(q, t + Vector2i(dx, dz)):
				n += 1
				if n >= min_tiles:
					return true
	return false


## Длина удара: до цели, но не короче REACH_MIN и не длиннее reach.
static func strike_length(base: Vector2, target: Vector2, reach: float) -> float:
	return clampf(base.distance_to(target), REACH_MIN, reach)


static func impact_point(base: Vector2, dir: Vector2, length: float) -> Vector2:
	return base + dir * length


## Точка p под головой: у точки удара (от length − HIT_BACK до length + HIT_FRONT вдоль dir) и
## не дальше HIT_HALF_W в сторону. Под самой шеей ближе к основанию — промах: бьёт голова.
static func in_impact_zone(base: Vector2, dir: Vector2, length: float, p: Vector2) -> bool:
	var rel := p - base
	var along := rel.dot(dir)
	return absf(rel.cross(dir)) <= HIT_HALF_W and along >= length - HIT_BACK and along <= length + HIT_FRONT


## Доля выдвижения элемента шеи j (0 — нижний диск, DISCS — голова) через t секунд появления: голова
## трогается первой, каждый диск ниже — на UNFOLD_LAG позже и догоняет; к EMERGE_S все на месте.
static func unfold(j: int, t: float) -> float:
	var k := clampf((t - (DISCS - j) * UNFOLD_LAG) / (EMERGE_S - DISCS * UNFOLD_LAG), 0.0, 1.0)
	return 1.0 - pow(1.0 - k, 3.0)


## Наклон шеи в позе на доле длины s (0 — основание, 1 — голова): буква S — у основания к машине,
## в середине назад, к голове снова вперёд.
static func pose_angle(s: float) -> float:
	if s < POSE_MID:
		return lerpf(POSE_LEAN, POSE_BACK, smoothstep(0.0, POSE_MID, s))
	return lerpf(POSE_BACK, POSE_TOP, smoothstep(POSE_MID, 1.0, s))


## Путь по глубокой воде от тайла from — к ближайшему по пути тайлу, откуда цель target в полосе
## lo…hi; такого нет — к тайлу, ближайшему к цели. Поиск в ширину по 8 соседям (по диагонали — если
## оба боковых тайла тоже глубокие), не больше max_nodes тайлов; deep — память «глубоко ли» между
## вызовами. Тайлы пути — от from до цели включительно; from не глубокий — пусто.
static func plan(q: TerrainQuery, from: Vector2i, target: Vector2, lo: float, hi: float,
		deep: Dictionary = {}, max_nodes: int = PLAN_NODES) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if not _deep_at(q, from, deep):
		return path
	var prev: Dictionary[Vector2i, Vector2i] = {from: from}
	var queue: Array[Vector2i] = [from]
	var head := 0
	var goal := from
	var goal_d := INF
	while head < queue.size() and head < max_nodes:
		var t := queue[head]
		head += 1
		var d := Vector2(t.x + 0.5, t.y + 0.5).distance_to(target)
		if d >= lo and d <= hi:
			goal = t
			break
		if d < goal_d:
			goal = t
			goal_d = d
		for o in NEIGHBORS:
			var n := t + o
			if prev.has(n) or not _deep_at(q, n, deep):
				continue
			if o.x != 0 and o.y != 0 and not (_deep_at(q, Vector2i(n.x, t.y), deep) and _deep_at(q, Vector2i(t.x, n.y), deep)):
				continue
			prev[n] = t
			queue.append(n)
	var t := goal
	while t != from:
		path.append(t)
		t = prev[t]
	path.append(from)
	path.reverse()
	return path


static func _deep_at(q: TerrainQuery, t: Vector2i, memo: Dictionary) -> bool:
	if memo.has(t):
		return memo[t]
	var ok := q.is_loaded(t.x, t.y) and habitat(q, t)
	memo[t] = ok
	return ok


func setup(at: Vector2) -> void:
	pos = at
	_theta.resize(DISCS)
	_arc.resize(DISCS + 1)
	_build()
	_water_y = _water_y_at(pos)
	_hide_body()


## Сразу охотится (заметила машину или отладка, --event=nessie).
func start_hunt() -> void:
	aggressive = true
	met = true
	reset_interest()
	_deep.clear()
	_begin(State.APPROACH)
	_check = 0.0
	_hump_wait = rng.randf_range(0.4, 1.2)          # первый горб — вскоре: «здесь кто-то большой»


func step(dt: float) -> void:
	_time += dt
	_timer += dt
	var vp := vehicle.state.pos
	var d := pos.distance_to(vp)
	match state:
		State.LURK:
			_check -= dt
			if _check <= 0.0:
				_check = LURK_CHECK_S
				if d <= LURK_R and _in_band(_plan_to(vp)):
					start_hunt()
		State.APPROACH:
			if lost_interest(dt, d) or d > LOSE_DIST:
				_leave()
			else:
				_approach(dt, vp)
				if _strikable(d):
					_emerge()
		State.EMERGE:
			lost_interest(dt, d, true)
			_turn_to(vp, dt)
			if _timer >= EMERGE_S:
				if _escaped(d):
					_watch()
				else:
					_pose(vp)
		State.WATCH:
			lost_interest(dt, d, true)
			_turn_to(vp, dt)
			if _timer >= WATCH_EASE_S and _strikable(d):
				_pose(vp)
			elif _timer >= WATCH_S:
				_fall = 0.0                     # погружение — из вертикали, не из лежачей позы
				_scale = 1.0
				_begin(State.SUBMERGE)
		State.POSE:
			lost_interest(dt, d, true)
			if _timer >= POSE_S:
				if _escaped(d):
					_watch()
				else:
					_begin(State.STRIKE)
		State.STRIKE:
			if _timer >= STRIKE_S:
				_impact()
		State.LIE:
			if _timer >= LIE_S:
				_begin(State.SUBMERGE)
				_throat.material_override = _throat_mat
		State.SUBMERGE:
			if _timer >= SUBMERGE_S:
				_begin(State.COOLDOWN)
				_hide_body()
		State.COOLDOWN:
			if lost_interest(dt, d) or d > LOSE_DIST:
				_leave()
			elif _timer >= COOLDOWN_S:
				_begin(State.APPROACH)
				_check = 0.0
		State.LEAVE:
			if _timer >= LEAVE_S:
				finished = true
	_animate(dt)


func _begin(s: State) -> void:
	state = s
	_timer = 0.0


## Потеряла интерес: уходит в глубину — след гаснет, Несса пропадает.
func _leave() -> void:
	aggressive = false
	_begin(State.LEAVE)


## Подход под водой: путь пересчитывается раз в REPLAN_S (машина движется), Несса плывёт по нему со
## скоростью nessie_speed.
func _approach(dt: float, vp: Vector2) -> void:
	_memo_age += dt
	if _memo_age > MEMO_S:
		_memo_age = 0.0
		_deep.clear()
	_check -= dt
	if _check <= 0.0:
		_path = _plan_to(vp)
		_path_i = 1 if _path.size() > 1 else 0          # цель — свой тайл: к его центру
		_check = REPLAN_S if _in_band(_path) else REPLAN_S * 3.0
	var from := pos
	var budget := rules.nessie_speed * dt
	while budget > 0.0 and _path_i < _path.size():
		var t := _path[_path_i]
		var wp := Vector2(t.x + 0.5, t.y + 0.5)
		var gap := pos.distance_to(wp)
		if gap <= budget:
			pos = wp
			budget -= gap
			_path_i += 1
		else:
			pos += (wp - pos) * (budget / gap)
			budget = 0.0
	var moved := pos - from
	_speed = moved.length() / maxf(dt, 0.0001)
	_traveled += moved.length()
	if moved.length() > 0.0001:
		_heading = _rotate_toward(_heading, moved.normalized(), TURN_RATE * dt)
	_water_y = _water_y_at(pos)


func _plan_to(vp: Vector2) -> Array[Vector2i]:
	return plan(query, Grid.tile_of_world(pos.x, pos.y), vp, REACH_MIN + BAND_IN,
			rules.nessie_reach - BAND_OUT, _deep)


## Путь кончается там, откуда машину достать шеей.
func _in_band(path: Array[Vector2i]) -> bool:
	if path.is_empty():
		return false
	var t := path[path.size() - 1]
	var d := Vector2(t.x + 0.5, t.y + 0.5).distance_to(vehicle.state.pos)
	return d >= REACH_MIN and d <= rules.nessie_reach


## Бить можно: машина на длине шеи, не в воздухе, не на скале над водой.
func _strikable(d: float) -> bool:
	var s := vehicle.state
	if vehicle.wrecked or s.falling or s.drowning or d < REACH_MIN or d > rules.nessie_reach:
		return false
	return s.y <= _water_y + CLIFF_MAX


## Машина ушла дальше длины шеи + ESCAPE_MARGIN (или бить нельзя совсем) — удара не будет.
func _escaped(d: float) -> bool:
	var s := vehicle.state
	return d > rules.nessie_reach + ESCAPE_MARGIN or vehicle.wrecked or s.drowning


## Не бьёт — стоит с поднятой головой и следит: шея выпрямляется из того положения, где была.
func _watch() -> void:
	_watch_from = _theta.duplicate()
	_watch_head = _head_theta
	_watch_jaw = _jaws[0].rotation.z if not _jaws.is_empty() else 0.0
	_throat.material_override = _throat_mat
	_begin(State.WATCH)


## Появление: Несса замирает на месте — здесь основание шеи; шея раскладывается, встают горбы.
func _emerge() -> void:
	_begin(State.EMERGE)
	_base = pos
	_water_y = _water_y_at(pos)
	_base3 = Vector3(_base.x, _water_y - BASE_SINK, _base.y)
	var to := vehicle.state.pos - _base
	_look = to.normalized() if to.length() > 0.01 else _heading
	_back = -_look
	_arch_at = _base + _back * (ARCH_BEHIND + ARCH_R)
	_body.visible = true
	_ring.visible = true
	_ring.position = Vector3(_base.x, _water_y + FOAM_LIFT, _base.y)
	_splash.position = Vector3(_base.x, _water_y, _base.y)
	_splash.restart()
	_splash.emitting = true
	EventBus.camera_shake_requested.emit(0.25, 0.6)
	EventBus.fauna_alerted.emit(&"nessie", _base3)


## Поза: направление и длина удара зафиксированы — уйти с места можно до самого удара.
func _pose(vp: Vector2) -> void:
	_begin(State.POSE)
	var to := vp - _base
	_dir = to.normalized() if to.length() > 0.01 else _look
	_length = strike_length(_base, vp, rules.nessie_reach)
	_impact_at = impact_point(_base, _dir, _length)
	_impact_y = _top_y(_impact_at)
	var e := Vector3(_impact_at.x, _impact_y + 0.06, _impact_at.y) - _base3
	_fall = atan2(Vector2(e.x, e.z).length(), e.y)
	_scale = clampf((e.length() - HEAD_LEN) / _rest_arc(DISCS), 0.4, 1.25)
	_throat.material_override = _hot


## Удар: голова в точке удара — всплеск и кольцо пены; машина под головой — урон и бросок.
func _impact() -> void:
	_begin(State.LIE)
	_splash.position = Vector3(_impact_at.x, _impact_y, _impact_at.y)
	_splash.restart()
	_splash.emitting = true
	EventBus.fauna_alerted.emit(&"nessie_strike", Vector3(_impact_at.x, _impact_y, _impact_at.y))
	var s := vehicle.state
	var hit := not (vehicle.wrecked or s.falling or s.drowning) and in_impact_zone(_base, _dir, _length, s.pos)
	EventBus.camera_shake_requested.emit(1.0 if hit else 0.5, 0.4 if hit else 0.3)
	if not hit:
		return
	damaged.emit(rules.nessie_damage, &"nessie")
	if vehicle.cls.hovers:
		var target := s.pos + _dir * rules.nessie_toss
		var t := Grid.tile_of_world(target.x, target.y)
		if query.is_loaded(t.x, t.y):
			VehicleKinematics.launch(s, target, TOSS_APEX, vehicle.cls, query)
			vehicle.tumble(_dir, TOSS_TILT)
			return
	vehicle.rock(Vehicle.ROCK_RAM, _dir)


## Голова при появлении поворачивается к машине — не мгновенно.
func _turn_to(vp: Vector2, dt: float) -> void:
	var to := vp - _base
	if to.length() > 0.01:
		_look = _rotate_toward(_look, to.normalized(), 3.5 * dt)


static func _rotate_toward(from: Vector2, to: Vector2, max_angle: float) -> Vector2:
	var a := from.angle_to(to)
	return from.rotated(clampf(a, -max_angle, max_angle))


static func _ease_out(k: float) -> float:
	return 1.0 - pow(1.0 - clampf(k, 0.0, 1.0), 3.0)


## Положение элемента вдоль выпрямленной шеи: центр диска j или основание морды (j = DISCS).
static func _rest_arc(j: int) -> float:
	return (j + 0.5) * DISC_STEP if j < DISCS else DISCS * DISC_STEP


func _water_y_at(p: Vector2) -> float:
	var t := Grid.tile_of_world(p.x, p.y)
	var w := query.water_tier(t.x, t.y)
	return ground_y(p) if w == TerrainQuery.NO_WATER else Grid.tier_to_y(w) - WATER_DROP


## Высота пены в точке: на зеркале воды или на грунте, что выше.
func _top_y(p: Vector2) -> float:
	var t := Grid.tile_of_world(p.x, p.y)
	if not query.is_loaded(t.x, t.y):
		return _water_y + FOAM_LIFT
	var g := query.surface_y(p.x, p.y)
	var w := query.water_tier(t.x, t.y)
	if w != TerrainQuery.NO_WATER and Grid.tier_to_y(w) - WATER_DROP >= g:
		return Grid.tier_to_y(w) - WATER_DROP + FOAM_LIFT
	return g + FOAM_LIFT * 1.5


# --- Анимация ---------------------------------------------------------------------------------------

func _animate(dt: float) -> void:
	_animate_neck()
	_animate_back(dt)
	_animate_wake(dt)
	_animate_foam()


## Шея: наклоны дисков (_theta), их места вдоль шеи (_arc), голова и челюсти — по состоянию.
func _animate_neck() -> void:
	if not _body.visible:
		return
	var head_theta := 0.0
	var aim := 0.0
	var jaw := 0.0
	match state:
		State.EMERGE:
			for j in DISCS + 1:
				_arc[j] = lerpf(-SINK_ARC, _rest_arc(j), unfold(j, _timer))
			for j in DISCS:
				_theta[j] = _sway(j)
			head_theta = _theta[DISCS - 1]
		State.WATCH:
			var k := _ease_out(_timer / WATCH_EASE_S)
			for j in DISCS + 1:
				_arc[j] = _rest_arc(j)
			for j in DISCS:
				_theta[j] = lerpf(_watch_from[j], _sway(j), k)
			head_theta = lerpf(_watch_head, _theta[DISCS - 1], k)
			jaw = lerpf(_watch_jaw, 0.0, k)
		State.POSE:
			var k := _ease_out(_timer / SNAP_S)
			_look = _look.slerp(_dir, k)
			for j in DISCS + 1:
				_arc[j] = _rest_arc(j)
			for j in DISCS:
				_theta[j] = lerpf(_sway(j), pose_angle(j / (DISCS - 1.0)), k)
			head_theta = _theta[DISCS - 1]
			aim = k
			jaw = JAW_OPEN * k
		State.STRIKE:
			var k := pow(clampf(_timer / STRIKE_S, 0.0, 1.0), 2.0)    # валится с ускорением, как дерево
			for j in DISCS + 1:
				_arc[j] = _rest_arc(j) * lerpf(1.0, _scale, k)
			for j in DISCS:
				_theta[j] = lerpf(pose_angle(j / (DISCS - 1.0)), _fall, k)
			head_theta = lerpf(_pose_head, _fall, k)
			jaw = JAW_OPEN * (1.0 - clampf((k - 0.6) / 0.4, 0.0, 1.0))
		State.LIE:
			var sag := 0.06 * _ease_out(_timer / LIE_S)       # голова оседает в воду
			for j in DISCS + 1:
				_arc[j] = _rest_arc(j) * _scale
			for j in DISCS:
				_theta[j] = _fall + sag
			head_theta = _fall + sag * 2.0
		State.SUBMERGE:
			# Шея отдёргивается из воды к вертикали и уходит прямо вниз, складываясь: нижние диски
			# скрываются первыми, голова — последней.
			var rear := _ease_out(_timer / 0.3)
			var f := clampf(_timer / SINK_S, 0.0, 1.0)
			var sc := lerpf(_scale, 1.0, rear) * lerpf(1.0, 0.55, f)
			var down := (_rest_arc(DISCS) + HEAD_LEN + HIDE_DEPTH) * pow(f, 1.5)
			for j in DISCS + 1:
				_arc[j] = _rest_arc(j) * sc - down
			for j in DISCS:
				_theta[j] = lerpf(_fall + 0.06, _sway(j), rear)
			head_theta = lerpf(_fall + 0.12, 0.0, rear)
	_layout(head_theta, aim)
	if state == State.POSE:
		_pose_head = _head_theta
	for hinge in _jaws:
		hinge.rotation.z = jaw


## Лёгкое покачивание вертикальной шеи.
func _sway(j: int) -> float:
	return 0.05 * sin(_time * 2.2 + j * 0.45)


## Расставляет диски и голову по цепочке: от основания каждый следующий — на (_arc[j] − _arc[j − 1])
## вдоль среднего наклона соседей; всё — в вертикальной плоскости через _look. aim — доля поворота
## головы к точке удара.
func _layout(head_theta: float, aim: float) -> void:
	var d3 := Vector3(_look.x, 0.0, _look.y)
	var axis := Vector3.UP.cross(d3).normalized()
	var p := _base3
	var prev_arc := 0.0
	var prev_th := _theta[0]
	for j in DISCS:
		var th := _theta[j]
		var mid := (prev_th + th) * 0.5
		p += (Vector3.UP * cos(mid) + d3 * sin(mid)) * (_arc[j] - prev_arc)
		prev_arc = _arc[j]
		prev_th = th
		var disc := _discs[j]
		disc.transform = Transform3D(Basis(axis, th) * Basis(Vector3.UP, j * TWIST), p)
		disc.visible = p.y > _water_y - HIDE_DEPTH
	p += (Vector3.UP * cos(prev_th) + d3 * sin(prev_th)) * (_arc[DISCS] - prev_arc)
	var th := head_theta
	if aim > 0.0:
		var v := Vector3(_impact_at.x, _impact_y, _impact_at.y) - p
		th = lerpf(th, atan2(Vector2(v.x, v.z).dot(_look), v.y), aim)
	_head_theta = th
	_head.transform = Transform3D(Basis(axis, th), p)
	_head.visible = p.y > _water_y - HIDE_DEPTH


## Спина: в броске выгибается из воды за шеей (после неё) и тонет последней; при подходе изредка
## всплывает на секунду и уходит под воду, перекатываясь вперёд, как спина дельфина.
func _animate_back(dt: float) -> void:
	var attack := state >= State.EMERGE and state <= State.SUBMERGE
	if state == State.APPROACH:
		if _dolphin < 0.0:
			_hump_wait -= dt
			if _hump_wait <= 0.0 and _speed > 0.5:
				_dolphin = 0.0
		else:
			_dolphin += dt
			if _dolphin >= HUMP_SURFACE_S:
				_dolphin = -1.0
				_hump_wait = rng.randf_range(HUMP_EVERY_MIN_S, HUMP_EVERY_MAX_S)
	elif not attack:
		_dolphin = -1.0
	var hidden := -(ARCH_R - ARCH_DROP) - 0.1      # верх дуги под водой
	var rise := hidden
	var at := _arch_at
	var along := _back
	if attack:
		match state:
			State.EMERGE:
				rise = lerpf(hidden, 0.0, _ease_out((_timer - 0.3) / 0.5))
			State.SUBMERGE:
				rise = lerpf(0.0, hidden, _ease_out((_timer - 0.5) / 0.5))
			_:
				rise = 0.02 * sin(_time * 3.0)
	elif _dolphin >= 0.0:
		var u := _dolphin / HUMP_SURFACE_S
		rise = lerpf(hidden, -0.12, sin(PI * u))
		along = _heading
		at = pos - _heading * (0.9 - 0.6 * u)
	_arch.visible = rise > hidden + 0.03 and query.water_tier(floori(at.x), floori(at.y)) != TerrainQuery.NO_WATER
	if not _arch.visible:
		return
	_arch.position = Vector3(at.x, _water_y - ARCH_DROP + rise, at.y)
	_arch.rotation = Vector3(0.0, atan2(along.x, along.y), 0.0)
	for s in _arch_segs:
		s.visible = s.global_position.y > _water_y - HIDE_DEPTH


## V-след: вершина — над Нессой, два пенных гребня расходятся назад; гаснет, когда она стоит или
## всплывает. Пузыри — над ней при подходе, у основания шеи в броске и ещё BUBBLES_AFTER_S после.
func _animate_wake(dt: float) -> void:
	var want := 0.0
	if state == State.APPROACH:
		want = clampf(_speed / maxf(rules.nessie_speed, 0.1), 0.0, 1.0)
	_wake_k = move_toward(_wake_k, want, dt * (3.0 if want > _wake_k else 1.5))
	_wake.visible = _wake_k > 0.03
	if _wake.visible:
		_wake.position = Vector3(pos.x, _water_y + FOAM_LIFT, pos.y)
		_wake.rotation.y = atan2(-_heading.x, -_heading.y)
		for arm in _arms:
			arm.scale = Vector3(1.0, 1.0, WAKE_LEN * (0.4 + 0.6 * _wake_k))
		_wake_mat.set_shader_parameter(&"alpha", _wake_k)
		_wake_mat.set_shader_parameter(&"flow", _traveled / WAKE_LEN * 5.0)
	var bubbling := false
	var at := pos
	match state:
		State.LURK:
			_lurk_puff -= dt
			if _lurk_puff <= -0.6:
				_lurk_puff = rng.randf_range(3.0, 6.0)
			bubbling = _lurk_puff < 0.0
		State.APPROACH:
			bubbling = true
			at = pos - _heading * 0.3
		State.EMERGE, State.SUBMERGE:
			bubbling = true
			at = _base
		State.COOLDOWN:
			bubbling = _timer < BUBBLES_AFTER_S
			at = _base
	_bubbles.emitting = bubbling
	if bubbling:
		_bubbles.position = Vector3(at.x, _water_y, at.y)


## Пена у основания шеи: разгорается при появлении, гаснет при погружении. Точку удара ничто не
## отмечает — ни до удара, ни после (только брызги).
func _animate_foam() -> void:
	match state:
		State.EMERGE:
			var k := _ease_out(_timer / 0.5)
			_ring.scale = Vector3(0.4 + 0.6 * k, 0.3, 0.4 + 0.6 * k)
			_ring_mat.albedo_color.a = 0.85 * k
		State.WATCH, State.POSE, State.STRIKE, State.LIE:
			pass                                  # пена у основания держится
		State.SUBMERGE:
			_ring_mat.albedo_color.a = 0.85 * (1.0 - clampf((_timer - 0.4) / 0.6, 0.0, 1.0))
		_:
			_ring.visible = false


func _hide_body() -> void:
	_body.visible = false
	_arch.visible = false
	_ring.visible = false


# --- Сборка -----------------------------------------------------------------------------------------

## Шея — 9 дисков-«позвонков» (low-poly призмы, широкие светлые и узкие тёмные вперемешку), голова —
## основание морды, глотка и три челюсти, как у червя; спина — дуга из таких же звеньев; пена: кольцо у основания, два гребня
## V-следа; пузыри и всплеск. 20 деталей и 2 системы частиц.
func _build() -> void:
	_bone = Creature.skin(BONE_COLOR, BodyMaterial.Pattern.SCALES, Grid.ART_PX)
	_narrow = Creature.skin(NARROW_COLOR, BodyMaterial.Pattern.SCALES, Grid.ART_PX)
	_hot = StandardMaterial3D.new()
	_hot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hot.albedo_color = HOT_COLOR
	_throat_mat = Creature.material(THROAT_COLOR)
	_body = Node3D.new()
	add_child(_body)
	for j in DISCS:
		var wide := j % 2 == 0
		var r := lerpf(DISC_R0, DISC_R1, j / (DISCS - 1.0)) * (1.0 if wide else NARROW)
		var h := DISC_STEP * DISC_OVERLAP * (1.0 if wide else 0.92)
		_discs.append(MeshKit.prism(_body, MeshKit.ngon(10 if wide else 8, r), -h * 0.5, h, _bone if wide else _narrow))
	_build_head()
	_build_back()
	_ring_mat = _foam_material()
	_ring = _torus(0.32, 0.46, _ring_mat)
	_build_wake()
	_bubbles = _particles(28, 0.8, 1, 0.3, 0.8, -1.2)
	_bubbles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_bubbles.emission_box_extents = Vector3(0.4, 0.02, 0.4)
	_bubbles.spread = 25.0
	_splash = _particles(56, 0.9, 2, 2.5, 4.6, -9.0)
	_splash.one_shot = true
	_splash.explosiveness = 0.85
	_splash.spread = 30.0
	_splash.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_splash.emission_ring_axis = Vector3.UP
	_splash.emission_ring_radius = 0.55
	_splash.emission_ring_inner_radius = 0.2
	_splash.emission_ring_height = 0.05
	_splash.emitting = false


## Голова: узел в основании морды, ось Y — вперёд (к кончику клюва). Сомкнутые челюсти — клюв-конус.
func _build_head() -> void:
	_head = Node3D.new()
	_body.add_child(_head)
	MeshKit.prism(_head, MeshKit.ngon(10, HEAD_R), 0.0, HEAD_H, _bone)
	_throat = MeshKit.prism(_head, MeshKit.ngon(10, HEAD_R * 0.75), HEAD_H - 0.01, 0.03, _throat_mat)
	var jaw_mesh := _jaw_mesh(HEAD_R, JAW_LEN)
	var jaw_mat := Creature.material(JAW_COLOR)
	jaw_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 3:
		var turn := Node3D.new()
		turn.position = Vector3(0, HEAD_H, 0)
		turn.rotation.y = -TAU * i / 3.0
		_head.add_child(turn)
		var hinge := Node3D.new()
		hinge.position = Vector3(HEAD_R, 0, 0)
		turn.add_child(hinge)
		var jaw := MeshInstance3D.new()
		jaw.mesh = jaw_mesh
		jaw.material_override = jaw_mat
		hinge.add_child(jaw)
		_jaws.append(hinge)


## V-след: узел на вершине (локальная −Z — курс), два гребня-полосы уходят назад под ±WAKE_ANGLE.
func _build_wake() -> void:
	_wake = Node3D.new()
	_wake.visible = false
	add_child(_wake)
	_wake_mat = ShaderMaterial.new()
	_wake_mat.shader = FOAM_SHADER
	_wake_mat.set_shader_parameter(&"foam", FOAM_COLOR)
	_wake_mat.render_priority = 1
	var strip := _strip_mesh(WAKE_W)
	for s: float in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		arm.mesh = strip
		arm.material_override = _wake_mat
		arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		arm.rotation.y = WAKE_ANGLE * s
		_wake.add_child(arm)
		_arms.append(arm)


func _foam_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = FOAM_COLOR
	m.render_priority = 1                # поверх прозрачной воды, а не под ней
	return m


## Плоское кольцо пены.
func _torus(inner: float, outer: float, mat: Material) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 14
	t.ring_segments = 4
	var mi := MeshInstance3D.new()
	mi.mesh = t
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(1.0, 0.3, 1.0)
	mi.visible = false
	add_child(mi)
	return mi


func _particles(amount: int, lifetime: float, texels: int, v_min: float, v_max: float, gravity: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.direction = Vector3.UP
	p.initial_velocity_min = v_min
	p.initial_velocity_max = v_max
	p.gravity = Vector3(0, gravity, 0)
	p.local_coords = false
	p.emitting = false
	p.mesh = PixelFx.quad(texels, FOAM_COLOR)
	add_child(p)
	return p


## Полоса единичной длины вдоль +Z (UV.y — от 0 у вершины до 1 у хвоста), ширина width.
static func _strip_mesh(width: float) -> ArrayMesh:
	var w := width * 0.5
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-w, 0, 0), Vector3(w, 0, 0), Vector3(w, 0, 1), Vector3(-w, 0, 1)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## Спина: дуга-полукольцо из ARCH_SEGS звеньев шеи (широкие и узкие вперемешку, внахлёст) в плоскости
## локальных Y–Z; центр дуги — в начале координат узла.
func _build_back() -> void:
	_arch = Node3D.new()
	_arch.visible = false
	add_child(_arch)
	var step := PI * ARCH_R / ARCH_SEGS
	for k in ARCH_SEGS:
		var wide := k % 2 == 0
		var r := BACK_R * (1.0 if wide else NARROW)
		var h := step * DISC_OVERLAP * (1.0 if wide else 0.92)
		var seg := MeshKit.prism(_arch, MeshKit.ngon(10 if wide else 8, r, k * TWIST), -h * 0.5, h,
				_bone if wide else _narrow)
		var a := PI * (k + 0.5) / ARCH_SEGS
		seg.position = Vector3(0.0, ARCH_R * sin(a), ARCH_R * cos(a))
		seg.rotation.x = -a                              # ось звена — по касательной к дуге
		_arch_segs.append(seg)


## Челюсть (как у червя, в масштабе морды): сектор в 120° вокруг оси Y, сходящийся к кончику клюва;
## грани — треугольники, края зазубрены. Шарнир — середина нижней кромки, ось поворота — локальная Z.
static func _jaw_mesh(r0: float, length: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols: Array[float] = [-60.0, -20.0, 20.0, 60.0]
	var shift := Vector3(r0, 0, 0)
	var grid: Array[PackedVector3Array] = []
	for ri in JAW_U.size():
		var row := PackedVector3Array()
		for ci in cols.size():
			var deg := cols[ci]
			if (ci == 0 or ci == cols.size() - 1) and ri > 0 and ri < JAW_U.size() - 1:
				deg += signf(deg) * (10.0 if ri % 2 == 1 else -7.0)     # зазубрины по кромке
			var a := deg_to_rad(deg)
			var r := r0 * JAW_R[ri]
			row.append(Vector3(r * cos(a), length * JAW_U[ri], r * sin(a)) - shift)
		grid.append(row)
	for ri in JAW_U.size() - 1:
		var inside := Vector3(0, length * (JAW_U[ri] + JAW_U[ri + 1]) * 0.5, 0) - shift
		for ci in cols.size() - 1:
			MeshKit.tri_out(st, grid[ri][ci], grid[ri + 1][ci], grid[ri][ci + 1], inside)
			MeshKit.tri_out(st, grid[ri][ci + 1], grid[ri + 1][ci], grid[ri + 1][ci + 1], inside)
	return st.commit()
