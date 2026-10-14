class_name MireShark
extends Creature
## Илозуб (GDD §5.6, береговой засадчик) — хищный илистый прыгун. Живёт в зыбучем грунте и в воде у
## зыбуна — не дальше shark_home_r тайлов от него (habitat). Своё место (база, _den) — точка появления: от
## него не уходит дальше shark_chase_r. Оказался на глубокой воде (2+ яруса, DEEP_WATER) — плывёт к
## ближайшему мелководью (глубина — ярус) у берега, нет его — к ближайшему зыбуну; там теперь его место.
## Облик: тело в тон мокрого ила (тон берёт
## от зыбуна, в котором сидит); большая тупая голова-купол с широкой, опущенной углами книзу пастью —
## костяные зубы на тёмной глотке; на макушке, вплотную, выпученные глаза на стебельках (алые, как у
## скакунов); тело сужается к простому округлому хвосту; вдоль спины — низкий гребень с торчащими лучами;
## мускулистые грудные плавники-костыли с веером на конце.
## Покой (rest) решает, где он: в зыбуне — засада AMBUSH: сидит в иле носом кверху, над грунтом — только два
## тусклых полуприкрытых глаза. В воде (выманило туда прыжком, погоней) чередует (длительности — от rng)
## LIE — ждёт: неподвижно лежит у поверхности (видны спина и глаза), изредка чуть сдвигается, — и PATROL —
## не спеша плавает вокруг своего места, за макушкой — круги по воде; унесло дальше WANDER_R — плывёт к
## месту. Из воды в зыбун может заплыть (патруль, путь к месту) или запрыгнуть (прыжок там кончился) — и
## снова в засаде.
## В зыбуне — засада: не двигается. Услышал машину — приподнимает глаза-перископы и поворачивается к ней,
## но с места не сходит и не бросается, пока она не въедет в зону прыжка; машина вне досягаемости — сидит в
## засаде. Въехала — бросок, даже если подкралась тихо (не слышал). Из зыбуна выходит только прыжком.
## Интерес теряет, когда машина дальше shark_chase_r от его места.
## Оказался вне ареала (суша, рельеф изменился) — ползком к ближайшему тайлу ареала; с уступа, которого не
## сползти (землетрясение подняло грунт), — прыжком вниз, в воду или зыбун.
## В воде — охотник, плывёт как рыба: услышал машину (не дальше shark_hear_r × шум — близко, не через пол-экрана)
## у своего места (не дальше shark_chase_r) — решительно
## идёт к ней (shark_speed — быстрее танка, медленнее ровера и ховера; разгон, торможение и повороты —
## плавно, SWIM_ACCEL, напрямик, а не ступеньками по тайлам) водой ареала, не дальше shark_chase_r от
## места, к точке, откуда машина в досягаемости прыжка и стена не мешает (нет такого — к кромке ареала у
## машины). Машина ушла дальше shark_chase_r от его места — бросает погоню, CALM_S не слышит машину и
## возвращается. Машина в зоне прыжка — бросок и без шума. Макушка, что идёт к машине, и брызги с кругами
## за ней — телеграф. Бросок — только на машину на одном с ним уровне (Creature.same_level) и у его места
## (не дальше shark_chase_r): с воды на берег вровень с ней, но не на уступ. Машина ближе
## shark_lunge_dist + LEAP_SLACK —
## замах shark_telegraph_s: выныривает, задирает голову, глаза выскакивают на стебельках и разгораются,
## пасть разевается алым, гребень встаёт парусом с алой кромкой, хвост сгибается пружиной. Цель — точка
## машины в начале замаха: уехал с места — промах. Прыжок дугой (APEX) на shark_lunge_dist со скоростью
## shark_lunge_speed — может вылететь на сушу; в стену выше дуги — падает. Укус shark_damage (и отскок) —
## только на одном уровне с машиной: она на уровне, откуда он прыгнул, и тело пролетает рядом с ней (BITE_R)
## на высоте её корпуса (at_bite_height); над крышей на вершине дуги — мимо. Упал на сушу — шлёпается и
## ковыляет на грудных плавниках, как на костылях, к ближайшему тайлу ареала (зыбун или вода), там ныряет;
## до следующего замаха — RECOVER_S. Не подобраться fauna_give_up_s —
## ныряет и CALM_S не слышит машину. Опасен в паре с зыбуном: машина вязнет — илозуб успевает.
## Таран (RamBody) достаёт его, только когда он над поверхностью: вынырнул в замахе, на суше, в прыжке
## низко — на высоте корпуса машины; ram_hits_shark ударов — гибель (в прыжке падает наземь, мигает и
## пропадает облачком ила).

enum State { IDLE, STALK, WINDUP, LEAP, LANDED, CRAWL, DIVE }
## Покой (State.IDLE): засада в зыбуне; в воде — лежит у поверхности (ждёт) или патрулирует.
enum Rest { AMBUSH, LIE, PATROL }

const MUD_GROUND := Color(0.3, 0.19, 0.16)      ## тело в зыбуне на грунте — темнее мокрого грунта
const MUD_SAND := Color(0.4, 0.33, 0.24)        ## …и на песке — мокрый песок
const THROAT_COLOR := Color(0.16, 0.06, 0.07)   ## #290F12 — глотка и кромка гребня; в замахе разгораются алым
const THREAT_COLOR := Color(1.0, 0.25, 0.2)     ## #FF4033 — глаза; свечение глотки и кромки гребня
const EYE_DIM := Color(0.72, 0.17, 0.13)        ## #B82B21 — глаза, пока таится
const SAIL_COLOR := Color(0.7, 0.13, 0.16)      ## #B3202A — перепонка гребня в замахе
const TOOTH_COLOR := Color(0.95, 0.92, 0.82)    ## #F2EBD1
const FOAM_COLOR := Color(0.82, 0.92, 0.88)     ## брызги и круги над водой
const CLOD_GROUND := Color(0.45, 0.29, 0.23)    ## комья зыбуна на грунте…
const CLOD_SAND := Color(0.6, 0.5, 0.36)        ## …и на песке

const CRUISE_SPEED := 1.3               ## в покое плавает вокруг своего места не спеша
const CRUISE_PAUSE_MIN_S := 0.4          ## на точке держится столько…
const CRUISE_PAUSE_MAX_S := 1.2          ## …до стольких секунд
const DEEP_WATER := 1.95                 ## ярусов воды над центром тайла — глубоко (2+): плывёт к мелководью
const SHORE_RETRY_S := 2.0               ## мелководья не нашёл — ищет снова через столько
const LIE_MIN_S := 4.0                   ## в воде лежит у поверхности столько…
const LIE_MAX_S := 8.0                   ## …до стольких секунд,
const PATROL_MIN_S := 5.0                ## потом патрулирует столько…
const PATROL_MAX_S := 10.0               ## …до стольких
const SHIFT_MIN_S := 2.0                 ## лёжа, сдвигается раз в столько…
const SHIFT_MAX_S := 4.5                 ## …до стольких секунд…
const SHIFT_R := 0.5                     ## …не дальше стольких тайлов…
const SHIFT_SPEED := 0.6                 ## …с такой скоростью
const RETURN_SPEED := 2.5                ## бросил погоню (унесло прыжком) — плывёт к своему месту
const SWIM_ACCEL := 6.0                  ## тайл/с² — разгон, торможение и поворот в воде (дугой)
const LOOK_AHEAD := 6                    ## точек маршрута: к самой дальней видимой — напрямик
const CRAWL_SPEED := 2.6                 ## рывками на плавниках: в среднем ~2 тайл/с
const TURN_RATE := 6.0                   ## рад/с
const LEAP_SLACK := 0.3                  ## замах, когда машина ближе shark_lunge_dist + это
const BITE_R := 0.7                      ## пролетел так близко от машины (по плоскости) — укус…
const HULL_MID := 0.25                   ## …на высоте её корпуса: середина корпуса над поверхностью под машиной…
const BITE_DY := 0.5 * Grid.TIER_H       ## …и тело илозуба от неё не дальше этого (вершина дуги — выше крыши)
const BITE_STEP := 0.05                  ## полёт за кадр проверяется на укус шагами по столько тайлов
const APEX := 0.6                        ## высота дуги прыжка над прямой взлёт — посадка
const MAX_RISE := Grid.TIER_H * 1.08      ## чуть выше яруса: выше этого над взлётом на берег не запрыгнуть
const HOP_APEX := 0.9                    ## прыжок домой, если не доползти
const GRAVITY := 20.0
const MIN_GAP := 1.2                     ## ближе к машине не подплывает (ждёт замаха)
const LAND_S := 0.4                      ## шлёпнулся на сушу — бьётся
const DIVE_S := 0.5
const RECOVER_S := 1.5                   ## после прыжка до следующего замаха
const CALM_S := 10.0                     ## сдался — столько не слышит машину
const STUCK_S := 1.0                     ## не ползётся столько — прыгает домой
const MAX_HOPS := 3                      ## не выбрался столькими прыжками — зарывается и пропадает
const ROUTE_EVERY_S := 0.4
const REGION_R := 12                     ## путь по ареалу ищется в этом радиусе тайлов
const WANDER_R := 4                      ## в покое плавает не дальше этого от своего места
const HOME_R := 4                        ## ареал по умолчанию: вода не дальше стольких тайлов от зыбуна
const GROUND_MEMO := 4096                ## тайлов в памяти ареала — больше: забывает (в начале хода, не посреди поиска)…
const GROUND_MEMO_S := 5.0               ## …и раз в столько секунд: рельеф меняется (землетрясение, борозда, воронка)
const NEAREST_R := 5                     ## ближайший тайл ареала (ползком после прыжка) ищется в этом радиусе
const WATER_DROP := 0.06                 ## зеркало воды ниже яруса (как в ChunkMesher)
## Глубина тела под поверхностью (мировые единицы): в покое торчит только макушка с глазами, на охоте —
## чуть больше.
const SINK_IDLE := 0.14
const SINK_AMBUSH := 0.2                 ## засада в зыбуне: купол макушки вровень с илом, над ним — только глаза
const SINK_LIE := 0.02                   ## лежит у поверхности воды: видны спина и глаза
const SINK_STALK := 0.12
const SINK_UP := -0.08                   ## вынырнул в замахе
const ON_LAND := -0.12                   ## на суше — на брюхе, перёд на грудных плавниках
const LURK_PITCH := 0.2                  ## рад — сидит в иле носом кверху (хвост глубже)
const LAND_PITCH := 0.12                 ## рад — на суше перёд приподнят на плавниках
const HEAD_UP := 0.75                    ## рад — голова задрана в замахе: пасть разинута кверху, нёбо и язык видны
const JAW_OPEN := 0.9                    ## рад — челюсть отвисла (в замахе — почти горизонтально)
const CURL := 0.7                        ## рад — хвост согнут пружиной перед прыжком
const POSE_RATE := 14.0
const RAM_R := 0.3                       ## радиус тела под тараном машины

var state := State.IDLE
var rest := Rest.PATROL                  ## что делает в покое (State.IDLE)
var target := Vector2.ZERO               ## точка машины в начале замаха — туда прыжок

static var _near: Array[Vector2i] = []   ## смещения тайлов не дальше NEAREST_R — по возрастанию расстояния

var _rest_t := 0.0                       ## в воде: до смены LIE ↔ PATROL
var _shore_wait := 0.0                   ## на глубокой воде: до следующего поиска мелководья
var _shift_t := 0.0                      ## LIE: до следующего сдвига
var _memo_t := 0.0                       ## память ареала (_ground) — с последней очистки
var _timer := 0.0
var _calm := 0.0
var _cooldown := 0.0
var _time := 0.0
var _goal := Vector2.ZERO
var _route: Array[Vector2i] = []
var _route_timer := 0.0
var _aim := Vector2.ZERO                 ## куда плыть после маршрута: к машине или на место для прыжка
var _moving := false
var _swim_v := Vector2.ZERO              ## скорость в воде, тайл/с (меняется плавно)
var _heading := Vector2(0, -1)
var _yaw := 0.0
var _dir := Vector2.ZERO                 ## направление прыжка (заперто в начале замаха)
var _home := Vector2.ZERO                ## откуда прыгнул в атаку; ползком — куда прыгать, если застрял
var _den := Vector2.INF                  ## своё место (база): точка появления, с глубины — мелководье (_seek_shore)
var _ground: Dictionary[Vector2i, bool] = {}   ## память ареала: тайл → habitat (проверка — скан вокруг)
var _hops := 0
var _stuck := 0.0
var _crawl_to := Vector2.ZERO
var _stranded := false
# Полёт.
var _leap_from := Vector2.ZERO           ## точка взлёта
var _leap_dist := 0.0
var _leap_speed := 0.0
var _apex := APEX
var _flown := 0.0
var _y := 0.0
var _y0 := 0.0
var _y1 := 0.0
var _vy := 0.0
var _falling := false
var _drop_v := Vector2.ZERO
var _bitten := false
# Поза (сглаженная).
var _sink := SINK_IDLE
var _head_up := 0.0
var _jaw_open := 0.0
var _eyes_up := 0.0
var _lid_open := 0.0                     ## 0 — глаза полуприкрыты и тусклы, 1 — распахнуты и горят
var _frill_up := 0.0
var _glow := 0.0
var _curl := 0.0
var _pitch := LURK_PITCH
var _phase := 0.0
var _stroke := 0.0                       ## фаза удара хвоста (частота — по ходу)
var _flop := 0.0
# Модель.
var _model: Node3D
var _body: Node3D
var _head: Node3D
var _jaw: Node3D
var _eyes: Array[Node3D] = []            ## глаз на стебельке (левый, правый)
var _lids: Array[Node3D] = []
var _frill: Node3D
var _tail: Node3D
var _pecs: Array[Node3D] = []
var _mud_mat: ShaderMaterial
var _fin_mat: ShaderMaterial
var _throat_mat: StandardMaterial3D
var _eye_mat: StandardMaterial3D
var _sail_mat: StandardMaterial3D        ## перепонка гребня
var _rim_mat: StandardMaterial3D         ## кромка гребня
var _wake: CPUParticles3D                ## комья из-под макушки (в воде — брызги)
var _ripples: CPUParticles3D             ## расходящиеся круги — след макушки
var _ripple_mat: ShaderMaterial
var _splash: CPUParticles3D
var _mud := MUD_GROUND
var _clod := CLOD_GROUND


func _init() -> void:
	name = "MireShark"


## Зыбучий грунт или вода (мелкая и глубокая) у зыбуна — не дальше near тайлов от него (rules.shark_home_r).
## Открытые озёра вдали от зыбуна — не его.
static func habitat(q: TerrainQuery, t: Vector2i, near: int = HOME_R) -> bool:
	if mire(q, t):
		return true
	if q.water_tier(t.x, t.y) == TerrainQuery.NO_WATER:
		return false
	for dz in range(-near, near + 1):
		for dx in range(-near, near + 1):
			if mire(q, t + Vector2i(dx, dz)):
				return true
	return false


## Зыбучий грунт — место засады.
static func mire(q: TerrainQuery, t: Vector2i) -> bool:
	return (q.flags(t.x, t.y) & ChunkData.FLAG_MIRE) != 0


## Ареал с памятью (проверка воды — скан вокруг тайла, а пути ищутся по сотням тайлов). Память забывается
## в начале хода (_forget), не посреди поиска.
func _habitat(t: Vector2i) -> bool:
	var known: Variant = _ground.get(t)
	if known != null:
		return known
	var ok := habitat(query, t, rules.shark_home_r)
	_ground[t] = ok
	return ok


## Память ареала — не дольше GROUND_MEMO_S (рельеф меняется: землетрясение, борозда смерча, воронка; сигнала
## о правке рельефа фауна не получает) и не больше GROUND_MEMO тайлов.
func _forget(dt: float) -> void:
	_memo_t += dt
	if _memo_t >= GROUND_MEMO_S or _ground.size() >= GROUND_MEMO:
		_memo_t = 0.0
		_ground.clear()


## Тайл ещё годится, чтобы сидеть или плыть: зыбун или вода (грунт не выше зеркала). Проверка без памяти
## ареала — землетрясение (сухой уступ на месте воды) замечается сразу; «у зыбуна ли вода» — по памяти
## (_habitat).
func _wet_or_mire(t: Vector2i) -> bool:
	if mire(query, t):
		return true
	return query.water_tier(t.x, t.y) != TerrainQuery.NO_WATER and query.water_depth(t.x + 0.5, t.y + 0.5) > -0.5


## Глубокая вода (не зыбун): 2+ яруса над центром тайла.
func _deep(t: Vector2i) -> bool:
	return query.water_tier(t.x, t.y) != TerrainQuery.NO_WATER and not mire(query, t) \
			and query.water_depth(t.x + 0.5, t.y + 0.5) >= DEEP_WATER


## Своё место (база) — точка появления (setup), а с глубокой воды — мелководье, к которому уплыл
## (_seek_shore). В покое в воде — жизнь вокруг него, погоня и бросок — не дальше shark_chase_r от него.
func _den_spot() -> Vector2:
	if _den == Vector2.INF:
		_den = pos
	return _den


## Машина у его места — не дальше shark_chase_r: за ней можно гнаться.
## Слышит машину за d тайлов: ближе прочей фауны — shark_hear_r × шум (стоящую — нет; в зону прыжка она
## и без шума не въедет незамеченной).
func _hears(d: float) -> bool:
	return d <= noise.vehicle_level * rules.shark_hear_r


func _in_reach_of_den(p: Vector2) -> bool:
	return p.distance_to(_den_spot()) <= rules.shark_chase_r


func setup(at: Vector2) -> void:
	pos = at
	_goal = at
	_den = at
	_heading = Vector2.from_angle(rng.randf() * TAU)
	_yaw = atan2(-_heading.x, -_heading.y)
	_set_rest(Rest.AMBUSH if _in_mire() else (Rest.LIE if rng.randf() < 0.5 else Rest.PATROL))
	_build()
	add_body(rules.ram_hits_shark, RAM_R, _model, _clod)
	_tint(1.0)
	_animate(0.0)
	_place()
	if is_inside_tree():
		_model.reset_physics_interpolation()


## Сразу охотится (услышал машину; отладка, --event=shark).
func start_hunt() -> void:
	_den_spot()
	aggressive = true
	_calm = 0.0
	reset_interest()
	_route_timer = 0.0
	_ground.clear()                        # рельеф мог измениться — ареал заново
	if state == State.IDLE:
		state = State.STALK
	EventBus.fauna_alerted.emit(&"shark", Vector3(pos.x, _surface(pos), pos.y))


func step(dt: float) -> void:
	tick_bodies(dt)
	if dead:
		_fall_dead(dt)
		return
	_time += dt
	_cooldown = maxf(_cooldown - dt, 0.0)
	_moving = false
	_forget(dt)
	var vp := vehicle.state.pos
	var d := pos.distance_to(vp)
	match state:
		State.IDLE:
			_calm = maxf(_calm - dt, 0.0)
			# Вне ареала (землетрясение, воронка) — ползком (с уступа — прыжком) к нему. Машина в зоне прыжка —
			# бросок, даже если её не слышно; иначе — покой (_rest). Слышит машину у своего места — охота.
			if not _in_habitat():
				_crawl_home()
			elif _calm <= 0.0 and _cooldown <= 0.0 and _can_leap(vp, d):
				start_hunt()
				_windup(vp)
			else:
				_rest(dt)
			if state == State.IDLE and _calm <= 0.0 and _hears(d) and _in_reach_of_den(vp):
				start_hunt()
		State.STALK:
			if not _in_habitat():
				_crawl_home()
			else:
				_stalk(dt, vp, d)
		State.WINDUP:
			lost_interest(dt, d, true)
			_timer -= dt
			if _timer <= 0.0:
				_leap(_dir, rules.shark_lunge_dist, rules.shark_lunge_speed, APEX, true)
		State.LEAP:
			lost_interest(dt, d, true)
			_fly(dt)
		State.LANDED:
			lost_interest(dt, d, true)
			_timer -= dt
			if _timer <= 0.0:
				_start_crawl()
		State.CRAWL:
			lost_interest(dt, d, true)
			_crawl(dt)
		State.DIVE:
			lost_interest(dt, d, true)
			_timer -= dt
			if _timer <= 0.0:
				if _stranded:
					finished = true
				_cooldown = RECOVER_S
				_route.clear()
				_route_timer = 0.0
				_goal = pos
				_swim_v = Vector2.ZERO
				state = State.STALK if aggressive else State.IDLE
	_tint(dt)
	_animate(dt)
	_place()
	_update_wake()


# --- Поведение -----------------------------------------------------------------------------------


## Покой — по тому, где он: в зыбуне — засада (AMBUSH), сидит не шевелясь. В воде чередует LIE и PATROL
## (длительности — от rng: LIE_MIN_S…LIE_MAX_S, PATROL_MIN_S…PATROL_MAX_S); на глубокой воде — к мелководью
## у берега, там новое место (_seek_shore); унесло дальше WANDER_R от места — плывёт к нему (это — PATROL).
func _rest(dt: float) -> void:
	if _in_mire():
		rest = Rest.AMBUSH
		_route.clear()
		_swim_v = Vector2.ZERO
		return
	if rest == Rest.AMBUSH:                          # выманило из зыбуна в воду — ждёт или патрулирует
		_set_rest(Rest.LIE if rng.randf() < 0.5 else Rest.PATROL)
	_shore_wait = maxf(_shore_wait - dt, 0.0)
	if _route.is_empty() and _shore_wait <= 0.0 and _deep(_tile()):
		_seek_shore()
	if pos.distance_to(_den_spot()) > WANDER_R + 0.5:
		if rest != Rest.PATROL:
			_set_rest(Rest.PATROL)
		_cruise(dt, true)
		return
	_rest_t -= dt
	if _rest_t <= 0.0:
		_set_rest(Rest.PATROL if rest == Rest.LIE else Rest.LIE)
	if rest == Rest.LIE:
		_lie(dt)
	else:
		_cruise(dt, false)


## Новый покой r: маршрут сброшен, отсчёт до смены — заново.
func _set_rest(r: Rest) -> void:
	rest = r
	_route.clear()
	_goal = pos
	_timer = 0.0
	match r:
		Rest.LIE:
			_rest_t = rng.randf_range(LIE_MIN_S, LIE_MAX_S)
			_shift_t = rng.randf_range(SHIFT_MIN_S, SHIFT_MAX_S)
		Rest.PATROL:
			_rest_t = rng.randf_range(PATROL_MIN_S, PATROL_MAX_S)


## Лежит у поверхности (ждёт): не плывёт, раз в SHIFT_MIN_S…SHIFT_MAX_S чуть сдвигается — не дальше SHIFT_R,
## водой ареала (ни в зыбун, ни на глубину), не дальше WANDER_R от места.
func _lie(dt: float) -> void:
	_shift_t -= dt
	if _shift_t <= 0.0:
		_shift_t = rng.randf_range(SHIFT_MIN_S, SHIFT_MAX_S)
		var to := pos + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(SHIFT_R * 0.4, SHIFT_R)
		if to.distance_to(_den_spot()) <= WANDER_R and not _deep(Grid.tile_of_world(to.x, to.y)) \
				and _line_ok(pos, to):
			_goal = to
	_swim(_goal, SHIFT_SPEED, dt, true)


## На глубокой воде: плывёт к ближайшему по пути водой мелководью (не глубже DEEP_WATER — у берега), нет
## его — к ближайшему зыбуну; там теперь его место (_den). Патрулирует туда.
func _seek_shore() -> void:
	_shore_wait = SHORE_RETRY_S
	var parent := _region(REGION_R)
	var found := false
	var to := Vector2i.ZERO
	var bank_found := false
	var bank := Vector2i.ZERO
	for t: Vector2i in parent:                       # в порядке обхода — по длине пути
		if mire(query, t):
			if not bank_found:
				bank_found = true
				bank = t
		elif not _deep(t):
			found = true
			to = t
			break
	if not found:
		if not bank_found:
			return
		to = bank
	_set_rest(Rest.PATROL)
	_den = Vector2(to.x + 0.5, to.y + 0.5)
	_route = _path(parent, to)
	_goal = _den


## Вне ареала (суша: землетрясение подняло грунт, воронка) — ползком к ближайшему тайлу ареала; с уступа —
## прыжком вниз; не доползти — прыжками туда же (_crawl).
func _crawl_home() -> void:
	_hops = 0
	_route.clear()
	_swim_v = Vector2.ZERO
	_start_crawl()
	_home = _crawl_to


## Патруль (PATROL): плавает вокруг своего места (не дальше WANDER_R) от точки к точке, на каждой ненадолго
## замирает; точка в зыбуне — заплывает туда и садится в засаду. away — унесло дальше: плывёт к месту
## быстрее.
func _cruise(dt: float, away: bool) -> void:
	var den := _den_spot()
	var speed := RETURN_SPEED if away else CRUISE_SPEED
	if _route.is_empty() and pos.distance_to(_goal) < 0.15:
		_swim(_goal, speed, dt, true)                    # доплывает до точки без рывка
		_timer -= dt
		if _timer <= 0.0:
			_timer = ROUTE_EVERY_S if away else rng.randf_range(CRUISE_PAUSE_MIN_S, CRUISE_PAUSE_MAX_S)
			_pick_rest(den, away)
		return
	_follow(_goal, speed, dt)
	if not _moving:
		_route.clear()
		_goal = pos


## Куда плыть в покое: домой (away) — к своему месту по ареалу (не доплыть — к ближайшему к нему тайлу),
## иначе — на случайный тайл не дальше WANDER_R от места: мелководье или зыбун (глубокая вода — нет).
## Задаёт маршрут и _goal.
func _pick_rest(den: Vector2, away: bool) -> void:
	var parent := _region(REGION_R if away else 2 * WANDER_R)
	var to := Grid.tile_of_world(den.x, den.y)
	var goal := den
	if away and not parent.has(to):
		var best_d := INF
		for t: Vector2i in parent:
			var dd := Vector2(t.x + 0.5, t.y + 0.5).distance_to(den)
			if dd < best_d:
				best_d = dd
				to = t
		goal = Vector2(to.x + 0.5, to.y + 0.5)
	elif not away:
		var tiles: Array[Vector2i] = []
		for t: Vector2i in parent:
			if Vector2(t.x + 0.5, t.y + 0.5).distance_to(den) <= WANDER_R and not _deep(t):
				tiles.append(t)
		if tiles.is_empty():
			return
		to = tiles[rng.randi() % tiles.size()]
		goal = Vector2(to.x + 0.5, to.y + 0.5) + Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3))
	_route = _path(parent, to)
	_goal = goal


## В досягаемости — замах. Машина ушла дальше shark_chase_r от его места — бросает погоню. В зыбуне —
## засада: на месте, только смотрит на машину; в воде — плывёт к ней по воде ареала.
func _stalk(dt: float, vp: Vector2, d: float) -> void:
	if _cooldown <= 0.0 and _can_leap(vp, d):
		_windup(vp)
		return
	if not _in_reach_of_den(vp):
		_give_up()
		return
	if _in_mire():
		_route.clear()
		_swim_v = Vector2.ZERO
		_face(vp - pos)
		return
	_route_timer -= dt
	if _route_timer <= 0.0:
		_route_timer = ROUTE_EVERY_S
		_plan(vp)
	if d > MIN_GAP:
		_follow(_aim, rules.shark_speed, dt)
	else:
		_swim(pos, rules.shark_speed, dt, true)          # вплотную — гасит ход и ждёт замаха
		_face(vp - pos)
	if lost_interest(dt, d):
		_give_up()


## Машина в зоне прыжка, у его места (не дальше shark_chase_r — поводок и для броска), на одном уровне с ним
## (не на уступе и не под ним), и дуге не мешает стена.
func _can_leap(vp: Vector2, d: float) -> bool:
	var s := vehicle.state
	if d > rules.shark_lunge_dist + LEAP_SLACK or s.falling or s.launched or s.drowning or vehicle.wrecked \
			or not _in_reach_of_den(vp):
		return false
	return Creature.same_level(query, pos, vp) and leap_clear(pos, vp)


## Прыжок из from к to не упрётся в стену: дуга (как в полёте) над рельефом до машины.
func leap_clear(from: Vector2, to: Vector2) -> bool:
	if from.distance_to(to) < 0.01:
		return true
	var dir := (to - from).normalized()
	var dist := rules.shark_lunge_dist
	var y0 := _surface(from)
	var y1 := _landing_y(from + dir * dist, y0)
	var reach := minf(from.distance_to(to) + 0.3, dist)
	var n := ceili(reach / 0.2)
	for i in range(1, n + 1):
		var p := from + dir * reach * i / n
		var t := Grid.tile_of_world(p.x, p.y)
		if not query.is_loaded(t.x, t.y):
			return false
		var k := from.distance_to(p) / dist
		if _surface(p) > arc(y0, y1, APEX, k) + 0.05:
			return false
	return true


func _windup(vp: Vector2) -> void:
	state = State.WINDUP
	_timer = rules.shark_telegraph_s
	target = vp
	_dir = (vp - pos).normalized() if vp.distance_to(pos) > 0.01 else _heading
	_heading = _dir
	_home = pos
	_hops = 0
	_swim_v = Vector2.ZERO
	_burst(pos, _surface(pos), 14, 2.5)


## Прыжок дугой: dist по направлению dir; bite — кусает, если пролетит рядом с машиной.
func _leap(dir: Vector2, dist: float, speed: float, apex: float, bite: bool) -> void:
	state = State.LEAP
	_dir = dir
	_heading = dir
	_leap_from = pos
	_leap_dist = maxf(dist, 0.3)
	_leap_speed = speed
	_apex = apex
	_flown = 0.0
	_y0 = _surface(pos)
	_y1 = _landing_y(pos + dir * _leap_dist, _y0)
	_y = _y0
	_vy = 0.0
	_falling = false
	_drop_v = Vector2.ZERO
	_bitten = not bite
	_burst(pos, _y0, 26, 3.5)
	if bite:
		EventBus.fauna_alerted.emit(&"shark_leap", Vector3(pos.x, _y0, pos.y))


## Высота посадки: поверхность в точке, но не выше взлёта + MAX_RISE (на высокий берег — в стену).
func _landing_y(p: Vector2, y0: float) -> float:
	var t := Grid.tile_of_world(p.x, p.y)
	if not query.is_loaded(t.x, t.y):
		return y0
	return minf(_surface(p), y0 + MAX_RISE)


## Высота тела на доле дуги k (0 — взлёт, 1 — посадка).
func _arc_y(k: float) -> float:
	return arc(_y0, _y1, _apex, k)


## Дуга прыжка от высоты y0 до y1 с подъёмом apex над ними, k — доля пути. Вверх и ровно — над прямой
## взлёт — посадка; вниз (с уступа) — снижение к концу, как у брошенного тела: над уступом дуга не ныряет в
## него же.
static func arc(y0: float, y1: float, apex: float, k: float) -> float:
	var drop := minf(y1 - y0, 0.0)
	return y0 + (y1 - y0 - drop) * k + drop * k * k + 4.0 * apex * k * (1.0 - k)


func _fly(dt: float) -> void:
	if not _falling:
		var step := minf(_leap_speed * dt, _leap_dist - _flown)
		var np := pos + _dir * step
		var k := minf((_flown + step) / _leap_dist, 1.0)
		var y := _arc_y(k)
		var t := Grid.tile_of_world(np.x, np.y)
		if not query.is_loaded(t.x, t.y) or _surface(np) > y + 0.05:
			_falling = true                            # в стену — падает, чуть отскочив
			_vy = 0.0
			_drop_v = -_dir * 0.8
		else:
			var flown := _flown
			_vy = (y - _y) / maxf(dt, 0.0001)
			_y = y
			pos = np
			_flown += step
			_check_bite(flown)
			if k >= 1.0 and not _falling:
				_land()
				return
	if _falling:
		_vy -= GRAVITY * dt
		_y += _vy * dt
		var np := pos + _drop_v * dt
		var t := Grid.tile_of_world(np.x, np.y)
		if query.is_loaded(t.x, t.y) and _surface(np) <= _y:
			pos = np
		var floor_y := _surface(pos)
		if _y <= floor_y:
			_y = floor_y
			_land()


## Тело на высоте body_y — на высоте корпуса машины над поверхностью ground_y под ней (грунт или зеркало
## воды): от середины корпуса (HULL_MID) не дальше BITE_DY. Склон под машиной сравнивается непрерывно, с
## этим допуском; на вершине дуги (APEX над прямой) тело выше крыши — мимо.
static func at_bite_height(body_y: float, ground_y: float) -> bool:
	return absf(body_y - (ground_y + HULL_MID)) <= BITE_DY


## Укус (раз за прыжок) — только на одном уровне с машиной: она на уровне, откуда он прыгнул
## (Creature.same_level; съехала под уступ или забралась на него — мимо), и тело пролетает рядом с ней
## (BITE_R) на высоте её корпуса (at_bite_height). Проверяется весь отрезок полёта за кадр от доли from_f
## (шагами BITE_STEP) — укус не проскакивает между кадрами. Укус: урон, раскачка, брызги; прыжок
## обрывается отскоком от места укуса.
func _check_bite(from_f: float) -> void:
	if _bitten:
		return
	var s := vehicle.state
	if s.falling or s.launched or s.drowning or vehicle.wrecked:
		return
	var ground := _surface(s.pos)
	var n := maxi(ceili((_flown - from_f) / BITE_STEP), 1)
	var at := Vector2.INF
	var at_y := 0.0
	for i in range(1, n + 1):
		var f := lerpf(from_f, _flown, float(i) / n)
		var p := _leap_from + _dir * f
		var y := _arc_y(f / _leap_dist)
		if p.distance_to(s.pos) <= BITE_R and at_bite_height(y, ground):
			at = p
			at_y = y
			break
	if at == Vector2.INF or not Creature.same_level(query, _leap_from, s.pos):
		return
	pos = at
	_y = at_y
	_bitten = true
	damaged.emit(rules.shark_damage, &"shark")
	vehicle.rock(Vehicle.ROCK_BITE * 2.0, _dir)
	EventBus.camera_shake_requested.emit(0.5, 0.25)
	_burst(s.pos.lerp(pos, 0.5), _y + 0.1, 30, 3.0)
	_jaw_open = 0.0                                    # челюсти захлопнулись
	_falling = true
	_vy = 1.5
	_drop_v = -_dir * 1.2


## Приземлился: в ареале (зыбун или вода у него) — ныряет; на суше — шлёпается и ползёт к ареалу.
func _land() -> void:
	_burst(pos, _surface(pos), 24, 3.0)
	_pitch = 0.0
	if _in_habitat():
		_dive()
	else:
		state = State.LANDED
		_timer = LAND_S
		_flop = 1.0


func _dive() -> void:
	state = State.DIVE
	_timer = DIVE_S


## Начинает ползти к ближайшему тайлу ареала; с уступа, которого не сползти (обрыв круче яруса —
## землетрясение подняло грунт), — сразу прыжком вниз, в воду или зыбун.
func _start_crawl() -> void:
	state = State.CRAWL
	_stuck = 0.0
	_crawl_to = _nearest_habitat()
	if _crawl_to != pos and pos.distance_to(_crawl_to) <= rules.shark_lunge_dist and not _crawlable(pos, _crawl_to):
		_hop(_crawl_to)


## По прямой от a до b можно доползти: поверхность (грунт или зеркало воды) нигде не скачет больше чем на
## ярус — ни стенки, ни обрыва (в воду с уступа — только прыжком).
func _crawlable(a: Vector2, b: Vector2) -> bool:
	var n := maxi(ceili(a.distance_to(b) / 0.25), 1)
	var prev := query.surface_tier_float(a.x, a.y)
	for i in range(1, n + 1):
		var p := a.lerp(b, float(i) / n)
		var t := Grid.tile_of_world(p.x, p.y)
		if not query.is_loaded(t.x, t.y):
			return false
		var h := query.surface_tier_float(p.x, p.y)
		if absf(h - prev) > 1.01:
			return false
		prev = h
	return true


## Прыжок без укуса к dest (домой, с уступа); прыжков без толку больше MAX_HOPS — зарывается и пропадает.
func _hop(dest: Vector2) -> void:
	_hops += 1
	if _hops > MAX_HOPS:
		_stranded = true
		_dive()
		return
	_leap((dest - pos).normalized() if dest.distance_to(pos) > 0.01 else _heading,
			pos.distance_to(dest) + 0.3, rules.shark_lunge_speed * 0.6, HOP_APEX, false)


## Ползёт на грудных плавниках (по воде — гребёт ими) к ближайшему тайлу ареала; застрял — прыгает домой, не
## вышло — зарывается.
func _crawl(dt: float) -> void:
	if _in_habitat():
		_burst(pos, _surface(pos), 12, 2.0)
		_dive()
		return
	_phase += dt * 9.0
	var surge := 0.3 + 1.4 * maxf(sin(_phase), 0.0)       # рывками: плавники упёрлись — бросок вперёд
	var before := pos
	_move(_crawl_to, CRAWL_SPEED * surge, dt)
	if pos.distance_to(before) < CRAWL_SPEED * 0.1 * dt:
		_stuck += dt
	else:
		_stuck = maxf(_stuck - dt, 0.0)
	if _stuck > STUCK_S or _crawl_to == pos:
		_hop(_home if _home.distance_to(pos) > 0.3 else _crawl_to)


## Центр ближайшего тайла ареала (зыбун или вода у него) не дальше NEAREST_R, или текущая точка, если нет.
## Тайлы — по возрастанию удалённости (_offsets): проверка (у воды — скан зыбуна вокруг) идёт только до
## первых найденных, а не по всему квадрату (раньше — до ~10 тыс. чтений флагов на посадку); среди соседних
## по удалённости — ближайший к нему самому.
func _nearest_habitat() -> Vector2:
	var c := _tile()
	var best := pos
	var best_d := INF
	var limit := INF
	for o in _offsets():
		var l := o.length()
		if l > limit:
			break
		var t := c + o
		if not query.is_loaded(t.x, t.y) or not _wet_or_mire(t) or not _habitat(t):
			continue
		var p := Vector2(t.x + 0.5, t.y + 0.5)
		var d := p.distance_to(pos)
		if d < best_d:
			best_d = d
			best = p
		limit = minf(limit, l + 1.5)               # дальше по смещению — дальше и от него (он в своём тайле)
	return best


## Смещения тайлов не дальше NEAREST_R — по возрастанию длины (строятся раз).
static func _offsets() -> Array[Vector2i]:
	if _near.is_empty():
		for dz in range(-NEAREST_R, NEAREST_R + 1):
			for dx in range(-NEAREST_R, NEAREST_R + 1):
				if dx * dx + dz * dz <= NEAREST_R * NEAREST_R:
					_near.append(Vector2i(dx, dz))
		_near.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.length_squared() < b.length_squared())
	return _near


## Испуг (удар капсулы десанта): если не в прыжке — ныряет и CALM_S не слышит машину.
func scare() -> void:
	if state == State.IDLE or state == State.STALK:
		_give_up()


## Таран достаёт илозуба над поверхностью: вынырнул в замахе, на суше; в прыжке — если низко (по высоте
## тело рядом с днищем машины, RamBody.REACH_DY). Затаившегося в иле или в воде — нет.
func ram_reachable(_b: RamBody) -> bool:
	return state == State.WINDUP or state == State.LEAP or state == State.LANDED or state == State.CRAWL


## Удар без гибели (если ram_hits_shark > 1): в прыжке — сбит наземь, в замахе — ныряет, на суше — бьётся.
func _on_rammed(_b: RamBody, dir: Vector2, killed: bool) -> void:
	if killed:
		return
	match state:
		State.LEAP:
			_bitten = true
			_falling = true
			_vy = 1.0
			_drop_v = dir * 1.5
		State.WINDUP:
			_dive()
		State.LANDED, State.CRAWL:
			state = State.LANDED
			_timer = LAND_S
			_flop = 1.0


## Убит тараном: след в иле стих, облачко гибели — цвета комьев его зыбуна (над водой — брызги).
func _on_died() -> void:
	_wake.emitting = false
	_ripples.emitting = false
	bodies[0].set_puff_color(FOAM_COLOR if _over_water(pos) else _clod)


## Убитый в прыжке падает наземь (мигая), на земле — лежит.
func _fall_dead(dt: float) -> void:
	if state != State.LEAP:
		return
	var floor_y := _surface(pos)
	_vy -= GRAVITY * dt
	_y = maxf(_y + _vy * dt, floor_y)
	if _y <= floor_y:
		_vy = 0.0
	_place()


## Сдался: ныряет, CALM_S не слышит машину; в зыбуне — снова в засаде, в воде — патрулирует (унесло —
## плывёт к месту).
func _give_up() -> void:
	state = State.IDLE
	aggressive = false
	_calm = CALM_S
	_set_rest(Rest.AMBUSH if _in_mire() else Rest.PATROL)


# --- Путь по ареалу ------------------------------------------------------------------------------


func _tile() -> Vector2i:
	return Grid.tile_of_world(pos.x, pos.y)


## Сидит в зыбуне (не в воде).
func _in_mire() -> bool:
	return mire(query, _tile())


## Его тайл — в ареале: зыбун или вода у зыбуна (сухой уступ после землетрясения — нет).
func _in_habitat() -> bool:
	var t := _tile()
	return _wet_or_mire(t) and _habitat(t)


func _mire_at(p: Vector2) -> bool:
	return mire(query, Grid.tile_of_world(p.x, p.y))


## Обход в ширину от своего тайла по ареалу (rad тайлов): тайл → родитель. Пути идут водой: тайл зыбуна —
## только конечная точка (заплыл — засада, дальше не плывёт). leash — не дальше стольких тайлов от своего
## места (оказался дальше — путь только ближе к нему).
func _region(rad: int, leash: float = INF) -> Dictionary:
	var start := _tile()
	var den := _den_spot()
	var parent := {start: start}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var t := queue[head]
		head += 1
		if t != start and mire(query, t):
			continue
		var limit := maxf(leash, Vector2(t.x + 0.5, t.y + 0.5).distance_to(den))
		for dir in 4:
			var n := t + Grid.DIR_OFFSETS[dir]
			if parent.has(n) or absi(n.x - start.x) > rad or absi(n.y - start.y) > rad \
					or Vector2(n.x + 0.5, n.y + 0.5).distance_to(den) > limit:
				continue
			if _edge_ok(t, dir, true):
				parent[n] = t
				queue.append(n)
	return parent


static func _path(parent: Dictionary, to: Vector2i) -> Array[Vector2i]:
	var route: Array[Vector2i] = []
	var t := to
	while parent[t] != t:
		route.push_front(t)
		t = parent[t]
	return route


## Куда плыть к машине vp: водой (в зыбун — только прыжком) не дальше shark_chase_r от своего места — на
## ближайшее по пути место, откуда машина в досягаемости прыжка, на одном с ним уровне и прыжку не мешает
## стена (обход с фланга), а нет такого — к кромке ареала, ближайшей к машине (в её тайле, к машине).
## Задаёт маршрут и _aim — точку, к которой идти после него: в тайле ареала и на поводке.
func _plan(vp: Vector2) -> void:
	var parent := _region(REGION_R, rules.shark_chase_r)
	var best := _tile()
	var best_d := Vector2(best.x + 0.5, best.y + 0.5).distance_to(vp)
	var spot: Array[Vector2i] = []
	var reach := rules.shark_lunge_dist + LEAP_SLACK - 0.3
	for t: Vector2i in parent:
		if mire(query, t):
			continue
		var c := Vector2(t.x + 0.5, t.y + 0.5)
		var d := c.distance_to(vp)
		if d < best_d - 0.01:
			best_d = d
			best = t
		if d <= reach and d >= MIN_GAP and Creature.same_level(query, c, vp) and leap_clear(c, vp):
			var route := _path(parent, t)
			if spot.is_empty() or route.size() < spot.size() - 1:
				spot = route
				spot.append(t)                     # последний — сам тайл (для пустого пути — свой)
	if spot.is_empty():
		var c := Vector2(best.x + 0.5, best.y + 0.5)
		_route = _path(parent, best)
		# К машине, не выходя из тайла кромки (сдвиг меньше полутайла) и не за поводок (иначе — центр тайла).
		var aim := c + (vp - c).limit_length(0.45)
		var den := _den_spot()
		_aim = aim if aim.distance_to(den) <= maxf(rules.shark_chase_r, c.distance_to(den)) else c
	else:
		var t: Vector2i = spot.pop_back()
		_route = spot
		_aim = Vector2(t.x + 0.5, t.y + 0.5)


## Плывёт по маршруту — напрямик к самой дальней видимой (до LOOK_AHEAD) его точке, а не ступеньками от
## центра к центру тайлов, и без остановок на них; маршрут кончился — прямо к final, пока пускает ареал.
func _follow(final: Vector2, speed: float, dt: float) -> void:
	var t := _tile()
	while not _route.is_empty() and _route[0] == t:
		_route.pop_front()
	if _route.is_empty():
		_swim(final, speed, dt, true)
		return
	var aim := Vector2(_route[0].x + 0.5, _route[0].y + 0.5)
	for i in range(mini(_route.size(), LOOK_AHEAD) - 1, 0, -1):
		var c := Vector2(_route[i].x + 0.5, _route[i].y + 0.5)
		if _line_ok(pos, c):
			aim = c
			break
	_swim(aim, speed, dt, false)


## Отрезок от a до b проходим по ареалу (шагами меньше тайла) и не задевает зыбун, если b — не в нём.
func _line_ok(a: Vector2, b: Vector2) -> bool:
	var into_mire := _mire_at(b)
	var n := ceili(a.distance_to(b) / 0.25)
	var p := a
	for i in range(1, n + 1):
		var np := a.lerp(b, float(i) / n)
		if not _can_pass(p, np, true) or (not into_mire and _mire_at(np) and not _mire_at(p)):
			return false
		p = np
	return true


## Плывёт к aim по ареалу: скорость меняется плавно (SWIM_ACCEL — разгон, торможение и поворот дугой;
## круто поворачивает — сбавляет ход, чтобы вписаться); arrive — к конечной точке, с торможением, иначе —
## на полном ходу. Упёрся в кромку ареала — скользит вдоль неё (поперечный ход гаснет); некуда — стоит.
## В зыбун из воды заплывает, только если aim — в нём (патруль, путь к месту): там — засада.
func _swim(aim: Vector2, speed: float, dt: float, arrive: bool) -> void:
	var may_mire := _mire_at(aim)
	var delta := aim - pos
	var dist := delta.length()
	var want := Vector2.ZERO
	if dist > 0.02:
		var dir := delta / dist
		var v := minf(speed, sqrt(2.0 * SWIM_ACCEL * dist)) if arrive else speed
		if _swim_v.length() > 0.5:
			v *= clampf(1.0 - absf(_swim_v.angle_to(dir)) / PI, 0.4, 1.0)
		want = dir * v
	_swim_v = _swim_v.move_toward(want, SWIM_ACCEL * dt)
	var step := _swim_v * dt
	if step.length_squared() < 1e-10:
		return
	for k in 3:
		var s := step if k == 0 else (Vector2(step.x, 0.0) if k == 1 else Vector2(0.0, step.y))
		if s.length_squared() < 1e-10 or not _can_pass(pos, pos + s, true) or (not may_mire and _mire_at(pos + s)):
			continue
		pos += s
		if k == 1:
			_swim_v.y = 0.0
		elif k == 2:
			_swim_v.x = 0.0
		_moving = true
		_face(_swim_v)
		return
	_swim_v = Vector2.ZERO


## Шаг ползком к aim: по воде — свободно, по суше — через рёбра не выше яруса. Упёрся — скользит вдоль
## кромки по одной из осей.
func _move(aim: Vector2, speed: float, dt: float) -> void:
	var delta := aim - pos
	if delta.length() < 0.02:
		return
	var step := delta.limit_length(speed * dt)
	for s: Vector2 in [step, Vector2(step.x, 0.0), Vector2(0.0, step.y)]:
		if s.length_squared() < 1e-8:
			continue
		var np := pos + s
		if _can_pass(pos, np, false):
			pos = np
			_moving = true
			_face(delta)
			return


func _can_pass(from: Vector2, to: Vector2, in_habitat: bool) -> bool:
	var a := Grid.tile_of_world(from.x, from.y)
	var b := Grid.tile_of_world(to.x, to.y)
	if a == b:
		return true
	var step := b - a
	if absi(step.x) + absi(step.y) == 1:
		return _edge_ok(a, Grid.DIR_OFFSETS.find(step), in_habitat)
	if absi(step.x) > 1 or absi(step.y) > 1:
		return false
	var dx := Grid.DIR_OFFSETS.find(Vector2i(step.x, 0))
	var dz := Grid.DIR_OFFSETS.find(Vector2i(0, step.y))
	return (_edge_ok(a, dx, in_habitat) and _edge_ok(a + Vector2i(step.x, 0), dz, in_habitat)) \
			or (_edge_ok(a, dz, in_habitat) and _edge_ok(a + Vector2i(0, step.y), dx, in_habitat))


## Ребро из t в сторону dir: в ареал (если нужно); по воде — плывёт, по суше — ступенька не выше яруса.
func _edge_ok(t: Vector2i, dir: int, in_habitat: bool) -> bool:
	var n := t + Grid.DIR_OFFSETS[dir]
	if not query.is_loaded(n.x, n.y):
		return false
	if in_habitat and not _habitat(n):
		return false
	if query.water_tier(t.x, t.y) != TerrainQuery.NO_WATER or query.water_tier(n.x, n.y) != TerrainQuery.NO_WATER:
		return true
	return query.edge_rise(t.x, t.y, dir) <= 1 and query.edge_drop(t.x, t.y, dir) <= 1


func _face(dir: Vector2) -> void:
	if dir.length_squared() > 0.0001:
		_heading = dir.normalized()


## Поверхность, по которой плывёт: грунт или зеркало воды (что выше).
func _surface(p: Vector2) -> float:
	var t := Grid.tile_of_world(p.x, p.y)
	if not query.is_loaded(t.x, t.y):
		return 0.0
	var y := query.surface_y(p.x, p.y)
	var w := query.water_tier(t.x, t.y)
	if w != TerrainQuery.NO_WATER:
		y = maxf(y, w * Grid.TIER_H - WATER_DROP)
	return y


# --- Облик ---------------------------------------------------------------------------------------


## Поза по состоянию: глубина, наклон, голова, пасть, глаза и веки, гребень, свечение, хвост; плавно.
func _animate(dt: float) -> void:
	var sink := SINK_IDLE
	var head := 0.0
	var jaw := 0.0
	var eyes := 0.0
	var lids := 0.0
	var frill := 0.0
	var glow := 0.0
	var curl := 0.0
	var pitch := LURK_PITCH
	var tremble := 0.0
	match state:
		State.IDLE:
			match rest:
				Rest.AMBUSH:
					sink = SINK_AMBUSH                       # над илом — только глаза
				Rest.LIE:
					sink = SINK_LIE                          # у поверхности, ровно: спина с гребнем и глаза
					pitch = 0.0
					eyes = 0.15
					frill = 0.25
		State.STALK:
			sink = SINK_STALK
			eyes = 0.45
		State.WINDUP:
			var k := clampf(1.0 - _timer / rules.shark_telegraph_s, 0.0, 1.0)
			sink = lerpf(SINK_STALK, SINK_UP, minf(k * 2.5, 1.0))
			head = HEAD_UP * minf(k * 2.0, 1.0)
			jaw = minf(k * 1.6, 1.0)
			eyes = 1.0
			lids = 1.0
			frill = minf(k * 2.0, 1.0)
			glow = k
			curl = CURL * k
			tremble = k
		State.LEAP:
			sink = 0.0
			head = 0.2
			jaw = 0.0 if _bitten else 1.0
			eyes = 1.0
			lids = 1.0
			frill = 0.8
			glow = 1.0 if not _bitten else 0.4
			curl = -0.3
			pitch = clampf(atan2(_vy, _leap_speed), -0.9, 0.9) if not _falling else _pitch
		State.LANDED, State.CRAWL:
			sink = SINK_STALK if _over_water(pos) else ON_LAND     # по воде — гребёт вплавь, у поверхности
			head = 0.15
			jaw = 0.2
			eyes = 1.0
			lids = 1.0
			frill = 0.3
			glow = 0.15
			pitch = LAND_PITCH
		State.DIVE:
			pitch = -0.35 if _timer > DIVE_S * 0.4 else LURK_PITCH
	var a := 1.0 - exp(-POSE_RATE * dt) if dt > 0.0 else 1.0
	_sink = sink if state == State.LEAP else lerpf(_sink, sink, a)
	_head_up = lerpf(_head_up, head, a)
	_jaw_open = lerpf(_jaw_open, jaw, minf(a * 2.0, 1.0))
	_eyes_up = lerpf(_eyes_up, eyes, a)
	_lid_open = lerpf(_lid_open, lids, minf(a * 1.5, 1.0))
	_frill_up = lerpf(_frill_up, frill, a)
	_glow = lerpf(_glow, glow, a)
	_curl = lerpf(_curl, curl, a)
	_pitch = lerpf(_pitch, pitch, minf(a * 1.5, 1.0))
	_flop = maxf(_flop - dt * 1.5, 0.0)
	var target_yaw := atan2(-_heading.x, -_heading.y)
	_yaw = rotate_toward(_yaw, target_yaw, TURN_RATE * dt) if dt > 0.0 else target_yaw

	var on_land := state == State.LANDED or state == State.CRAWL
	var bob := 0.0
	if state == State.CRAWL:
		bob = maxf(sin(_phase), 0.0) * 0.05                    # плавники упёрлись — перёд привстаёт
	# Плывёт: хвост бьёт чаще и шире по ходу, корпус чуть виляет в противофазе — как у рыбы.
	var beat := clampf(_swim_v.length() / rules.shark_speed, 0.0, 1.0) if _moving else 0.0
	_stroke += dt * lerpf(2.5, 11.0, beat)
	_body.position.y = -_sink + bob
	_body.rotation = Vector3(_pitch + (sin(_phase) * 0.08 if state == State.CRAWL else 0.0),
			_curl * -0.25 - sin(_stroke) * 0.07 * beat,
			sin(_time * 50.0) * 0.05 * tremble + sin(_time * 16.0) * 0.3 * _flop)
	_head.rotation.x = _head_up
	_jaw.rotation.x = -JAW_OPEN * _jaw_open
	for i in _eyes.size():
		var s := -1.0 if i == 0 else 1.0
		_eyes[i].position = Vector3(s * lerpf(EYE_X, EYE_X_UP, _eyes_up), lerpf(EYE_LOW, EYE_HIGH, _eyes_up), EYE_Z)
		_eyes[i].rotation.z = -s * EYE_SPLAY * _eyes_up                # стебельки врозь
		_lids[i].rotation.x = lerpf(LID_HALF, LID_OPEN, _lid_open)
	_frill.scale.y = lerpf(FRILL_FLAT, 1.0, _frill_up)
	var sway := lerpf(0.12, 0.42, beat) if not on_land else 0.25
	var wave := sin(_stroke) if not on_land else sin(_time * 8.0)
	_tail.rotation.y = _curl + wave * sway * (1.0 - absf(_curl) / CURL * 0.8)
	for i in _pecs.size():
		var s := -1.0 if i == 0 else 1.0
		var p := _pecs[i]
		if state == State.CRAWL:
			# Костыли: оба плавника разом — упор впереди, толчок назад (тело — рывком), подъём и вынос вперёд.
			var fwd := cos(_phase) * 0.6
			var lift := maxf(-sin(_phase), 0.0) * 0.5
			p.rotation = Vector3(0.0, s * fwd, s * lift)
		elif on_land:
			p.rotation = Vector3(0.0, s * 0.2, s * sin(_time * 16.0) * 0.5 * _flop)  # шлёпнулся — бьёт плавниками
		elif state == State.LEAP:
			p.rotation = Vector3(0.0, s * 0.3, s * 0.6)              # раскинуты в прыжке
		elif state == State.WINDUP:
			p.rotation = Vector3(0.0, s * 0.25, 0.0)                 # уперлись в ил
		else:
			p.rotation = Vector3(0.0, -s * 0.9, s * 0.4)             # прижаты к телу
	# Алое — свечением по тёмному: освещённый алый альбедо со свечением выгорает в оранжевый.
	_throat_mat.emission_energy_multiplier = _glow
	var fin := _mud.darkened(0.25)
	_sail_mat.albedo_color = fin.lerp(SAIL_COLOR, _glow)
	_sail_mat.emission_energy_multiplier = _glow * 0.35
	_rim_mat.albedo_color = fin.lerp(THROAT_COLOR, _glow)
	_rim_mat.emission_energy_multiplier = _glow
	_eye_mat.albedo_color = EYE_DIM.lerp(THREAT_COLOR, _lid_open)


func _place() -> void:
	var base := _y if state == State.LEAP else _surface(pos)
	_model.position = Vector3(pos.x, base, pos.y)
	_model.rotation.y = _yaw
	for b in bodies:
		b.pos = pos
		b.y = base


## Тон ила — от зыбуна, в котором сидит: на грунте бурый, на песке — мокрый песок.
func _tint(dt: float) -> void:
	var t := _tile()
	if (query.flags(t.x, t.y) & ChunkData.FLAG_MIRE) != 0:
		var sand := query.material(t.x, t.y) == ChunkData.Mat.SAND
		var k := minf(dt * 2.0, 1.0)
		_mud = _mud.lerp(MUD_SAND if sand else MUD_GROUND, k)
		_clod = _clod.lerp(CLOD_SAND if sand else CLOD_GROUND, k)
	BodyMaterial.set_color(_mud_mat, _mud)
	BodyMaterial.set_color(_fin_mat, _mud.darkened(0.25))


## След макушки, пока плывёт под поверхностью: комья ила или — в воде — брызги усами по бокам (чем быстрее,
## тем дальше летят), и расходящиеся круги.
func _update_wake() -> void:
	if not is_inside_tree():
		return
	var under := state == State.IDLE or state == State.STALK
	_wake.emitting = under and _moving
	_ripples.emitting = _wake.emitting
	if not _wake.emitting:
		return
	var crown := pos + _heading * CROWN_AHEAD
	var at := Vector3(crown.x, _surface(crown) + 0.02, crown.y)
	var wet := _over_water(crown)
	var fast := clampf(_swim_v.length() / rules.shark_speed, 0.0, 1.0)
	_wake.position = at
	_wake.direction = Vector3(-_heading.x, 1.2 - 0.5 * fast if wet else 1.2, -_heading.y).normalized()
	_wake.spread = lerpf(35.0, 70.0, fast) if wet else 35.0
	_wake.initial_velocity_min = 0.6 + 0.6 * fast if wet else 0.6
	_wake.initial_velocity_max = 1.4 + 1.2 * fast if wet else 1.4
	_ripples.position = at
	((_wake.mesh as QuadMesh).material as StandardMaterial3D).albedo_color = FOAM_COLOR if wet else _clod
	_ripple_mat.set_shader_parameter(&"tint", FOAM_COLOR if wet else _mud)


## Брызги ила или воды в точке p.
func _burst(p: Vector2, y: float, amount: int, speed: float) -> void:
	if not is_inside_tree():
		return
	_splash.amount = amount
	_splash.initial_velocity_min = speed * 0.5
	_splash.initial_velocity_max = speed
	_splash.position = Vector3(p.x, y + 0.05, p.y)
	((_splash.mesh as QuadMesh).material as StandardMaterial3D).albedo_color = FOAM_COLOR if _over_water(p) else _clod
	_splash.restart()
	_splash.emitting = true


func _over_water(at: Vector2) -> bool:
	var t := Grid.tile_of_world(at.x, at.y)
	return query.is_loaded(t.x, t.y) and query.water_tier(t.x, t.y) != TerrainQuery.NO_WATER \
			and query.water_depth(at.x, at.y) > 0.1


# --- Модель --------------------------------------------------------------------------------------

const HEAD_AT := Vector3(0, -0.03, -0.12)       ## шарнир головы — углы рта, у шеи
const CROWN_AHEAD := 0.3                 ## макушка впереди центра тела (за ней след по илу)
const RIPPLE_SHADER := preload("res://src/render/shaders/ripple_ring.gdshader")
const RIPPLE_R0 := 0.15                  ## круг за макушкой расходится от такого радиуса…
const RIPPLE_R1 := 0.5                   ## …до такого (2–8 пикселей мира)
const RIPPLE_W_PX := 1.0                 ## толщина кольца — пикселей мира
const EYE_R := 0.068
const EYE_Z := -0.18                     ## глаза — над передней частью купола
const EYE_X := 0.072                     ## вплотную друг к другу…
const EYE_X_UP := 0.085                  ## …на стебельках чуть врозь
const EYE_LOW := 0.2                     ## глаза выпучены из купола…
const EYE_HIGH := 0.3                    ## …и выскочили на стебельках
const EYE_SPLAY := 0.3                   ## рад — стебельки врозь, когда подняты
const STALK_LEN := 0.14
const LID_HALF := -0.25                  ## рад — веко прикрывает верх глаза…
const LID_OPEN := 1.9                    ## …и откинуто назад
const FRILL_Y := 0.065                   ## основание гребня — чуть ниже линии спины
const FRILL_FLAT := 0.1                  ## гребень сложен (доля высоты): в иле не торчит
const FRILL_LEAN := 0.35                 ## лучи гребня отклонены назад: на высоту h — на h·это
## Лучи гребня (z основания, сдвиг основания по y от FRILL_Y, высота): выше всего за головой, к хвосту ниже.
const FRILL: Array[Vector3] = [Vector3(-0.03, 0.0, 0.26), Vector3(0.05, 0.0, 0.33), Vector3(0.13, -0.007, 0.3),
		Vector3(0.21, -0.014, 0.21), Vector3(0.29, -0.027, 0.12)]
## Сечения (z, полуширина, полувысота, центр по y): туловище от шеи к хвосту (сжато с боков к хвосту),
## голова — от шеи к морде; центры сечений головы к шее ниже — углы рта опущены.
const TORSO: Array[Vector4] = [Vector4(-0.14, 0.15, 0.12, -0.03), Vector4(0.04, 0.135, 0.115, -0.025),
		Vector4(0.22, 0.095, 0.09, -0.015), Vector4(0.38, 0.045, 0.06, -0.01)]
const SKULL: Array[Vector4] = [Vector4(0.04, 0.15, 0.16, -0.035), Vector4(-0.07, 0.17, 0.21, -0.028),
		Vector4(-0.18, 0.165, 0.195, -0.015), Vector4(-0.27, 0.13, 0.135, -0.004), Vector4(-0.33, 0.08, 0.07, 0.0)]
const JAW: Array[Vector4] = [Vector4(0.04, 0.14, 0.085, -0.035), Vector4(-0.07, 0.16, 0.085, -0.028),
		Vector4(-0.18, 0.155, 0.07, -0.015), Vector4(-0.27, 0.12, 0.05, -0.004), Vector4(-0.32, 0.075, 0.03, 0.0)]


## Илозуб из 21 детали: туловище и голова — низкополигональные лофты, плавники — клинья и веера, гребень —
## лучи с перепонкой. Перед — по −Z.
func _build() -> void:
	_mud_mat = Creature.skin(_mud, BodyMaterial.Pattern.MUD, Grid.ART_PX, 0.45)    # мокрый — чуть блестит
	_fin_mat = Creature.skin(_mud.darkened(0.25), BodyMaterial.Pattern.MUD, Grid.ART_PX, 0.45)
	_throat_mat = Creature.material(THROAT_COLOR)
	_throat_mat.emission_enabled = true
	_throat_mat.emission = THREAT_COLOR
	_throat_mat.emission_energy_multiplier = 0.0
	_throat_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_sail_mat = Creature.material(_mud.darkened(0.25))
	_sail_mat.emission_enabled = true
	_sail_mat.emission = THREAT_COLOR
	_sail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rim_mat = Creature.material(_mud.darkened(0.25))
	_rim_mat.emission_enabled = true
	_rim_mat.emission = THREAT_COLOR
	_rim_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var tooth := Creature.material(TOOTH_COLOR)
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_mat.albedo_color = EYE_DIM

	_model = Node3D.new()
	add_child(_model)
	_body = Node3D.new()
	_model.add_child(_body)
	_mesh(_body, _loft(TORSO, 8, PI * 0.5, PI * 2.5, Vector3(0, -0.01, 0.48)), _mud_mat)

	# Голова-купол: верх (череп) и нижняя челюсть — половинки лофта на шарнире в углах рта; изнутри —
	# нёбо и язык (глотка).
	_head = _node(_body, HEAD_AT)
	_mesh(_head, _loft(SKULL, 6, 0.0, PI), _mud_mat)
	_mesh(_head, _palate(SKULL, 0.96, 0.012), _throat_mat)
	_mesh(_head, _teeth(SKULL, -1.0), tooth)
	_jaw = _node(_head, Vector3.ZERO)
	_mesh(_jaw, _loft(JAW, 4, PI, TAU), _mud_mat)
	_mesh(_jaw, _palate(JAW, 0.96, -0.012), _throat_mat)
	_mesh(_jaw, _teeth(JAW, 1.0), tooth)

	# Глаза-перископы на макушке: шар на стебельке, сверху — тёмное веко-полусфера (прикрывает верх глаза).
	var ball := SphereMesh.new()
	ball.radius = EYE_R
	ball.height = EYE_R * 2.0
	ball.radial_segments = 6
	ball.rings = 3
	var lid := SphereMesh.new()
	lid.radius = EYE_R * 1.12
	lid.height = EYE_R * 0.8
	lid.is_hemisphere = true
	lid.radial_segments = 6
	lid.rings = 2
	for s: float in [-1.0, 1.0]:
		var eye := _node(_head, Vector3(s * EYE_X, EYE_LOW, EYE_Z))
		Creature.rod(eye, Vector3(0, -STALK_LEN, 0), Vector3.ZERO, 0.024, _mud_mat)
		_mesh(eye, ball, _eye_mat)
		var hinge := _node(eye, Vector3.ZERO)
		_mesh(hinge, lid, _fin_mat).position.y = EYE_R * 0.3
		hinge.rotation.x = LID_HALF
		_eyes.append(eye)
		_lids.append(hinge)

	# Гребень вдоль спины: лучи и перепонка между ними — парус, по верху — кромка фестонами.
	_frill = _node(_body, Vector3(0, FRILL_Y, 0))
	_mesh(_frill, _frill_rays(), _fin_mat)
	_mesh(_frill, _frill_web(0.0, 0.55, 0.55), _sail_mat)
	_mesh(_frill, _frill_web(0.55, 0.85, 0.7), _rim_mat)

	# Хвост: простой округлый веер, сжатый с боков; нижняя половина чуть шире.
	_tail = _node(_body, Vector3(0, -0.01, 0.39))
	var tail_pts: Array[Vector3] = []
	for s: float in [-1.0, 1.0]:
		tail_pts.append(Vector3(s * 0.016, 0.045, 0.0))
		tail_pts.append(Vector3(s * 0.016, -0.05, 0.0))
	for t: float in [-1.35, -0.7, 0.0, 0.7, 1.35]:
		tail_pts.append(Vector3(0, -0.015 + 0.13 * sin(t), 0.04 + 0.19 * cos(t)))
	_mesh(_tail, _hull_mesh(tail_pts), _fin_mat)

	# Грудные плавники-костыли: мускулистая «рука» и веер на конце.
	for s: float in [-1.0, 1.0]:
		var pec := _node(_body, Vector3(s * 0.12, -0.09, -0.08))
		var arm: Array[Vector3] = []
		for y: float in [-0.03, 0.03]:
			for z: float in [-0.03, 0.03]:
				arm.append(Vector3(0, y, z))
		for y: float in [-0.04, -0.07]:
			for z: float in [-0.06, -0.02]:
				arm.append(Vector3(s * 0.14, y, z))
		_mesh(pec, _hull_mesh(arm), _mud_mat)
		var c := Vector3(s * 0.14, -0.06, -0.04)
		var fan: Array[Vector3] = [c + Vector3(0, 0.006, -0.02), c + Vector3(0, -0.006, -0.02),
				c + Vector3(0, 0.006, 0.02), c + Vector3(0, -0.006, 0.02)]
		for t: float in [-0.9, -0.2, 0.5, 1.2]:
			fan.append(c + Vector3(s * 0.1 * cos(t), 0.0, 0.1 * sin(t)))
		_mesh(pec, _hull_mesh(fan), _fin_mat)
		_pecs.append(pec)

	_wake = _particles(12, 0.5, 1, 0.6, 1.4, 35.0)
	_ripples = _ripple_trail()
	_splash = _particles(30, 0.7, 2, 1.5, 3.0, 55.0)
	_splash.one_shot = true
	_splash.explosiveness = 0.9
	_splash.emitting = false


## Луч гребня i: основание и вершина.
static func _ray(i: int) -> Array[Vector3]:
	var r := FRILL[i]
	var base := Vector3(0, r.y, r.x)
	return [base, base + Vector3(0, r.z, r.z * FRILL_LEAN)]


## Лучи гребня — тонкие клинья, торчат над перепонкой.
static func _frill_rays() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in FRILL.size():
		var r := _ray(i)
		_hull(st, [r[0] + Vector3(-0.009, 0, -0.01), r[0] + Vector3(0.009, 0, -0.01), r[0] + Vector3(0, 0, 0.012),
				r[1]])
	return st.commit()


## Перепонка гребня между лучами от доли высоты k0 до k1; верх между лучами провисает до доли dip (фестоны).
static func _frill_web(k0: float, k1: float, dip: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in FRILL.size() - 1:
		var a := _ray(i)
		var b := _ray(i + 1)
		var a0 := a[0].lerp(a[1], k0)
		var b0 := b[0].lerp(b[1], k0)
		var mid := (a[0].lerp(a[1], dip) + b[0].lerp(b[1], dip)) * 0.5
		MeshKit.tri(st, a0, b0, mid, Vector3.RIGHT)
		MeshKit.tri(st, a0, mid, a[0].lerp(a[1], k1), Vector3.RIGHT)
		MeshKit.tri(st, b0, b[0].lerp(b[1], k1), mid, Vector3.RIGHT)
	return st.commit()


static func _node(parent: Node3D, at: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = at
	parent.add_child(n)
	return n


static func _mesh(parent: Node3D, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	return mi


## Лофт: кольца-сечения вдоль Z, между ними плоские грани. Сечение — дуга эллипса от a0 до a1 (угол 0 —
## бок +X, PI/2 — верх) из sides отрезков; полный круг — замкнутое кольцо, половина — открыта по линии рта.
## Торцы плоские; tip (если задан) — остриё вместо последнего торца.
static func _loft(stations: Array[Vector4], sides: int, a0: float, a1: float, tip := Vector3.INF) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var closed := is_equal_approx(a1 - a0, TAU)
	var count := sides if closed else sides + 1
	var rings: Array[PackedVector3Array] = []
	for s in stations:
		var ring := PackedVector3Array()
		for i in count:
			var a := a0 + (a1 - a0) * i / sides
			ring.append(Vector3(cos(a) * s.y, s.w + sin(a) * s.z, s.x))
		rings.append(ring)
	for r in rings.size() - 1:
		var axis := Vector3(0, (stations[r].w + stations[r + 1].w) * 0.5, (stations[r].x + stations[r + 1].x) * 0.5)
		for i in sides:
			var j := (i + 1) % count
			MeshKit.tri_out(st, rings[r][i], rings[r + 1][i], rings[r + 1][j], axis)
			MeshKit.tri_out(st, rings[r][i], rings[r + 1][j], rings[r][j], axis)
	var last := rings.size() - 1
	_cap(st, rings[0], Vector3(0, 0, signf(stations[0].x - stations[1].x)))
	if tip == Vector3.INF:
		_cap(st, rings[last], Vector3(0, 0, signf(stations[last].x - stations[last - 1].x)))
	else:
		var inside := Vector3(0, stations[last].w, stations[last].x)
		for i in sides:
			MeshKit.tri_out(st, rings[last][i], rings[last][(i + 1) % count], tip, inside)
	return st.commit()


static func _cap(st: SurfaceTool, ring: PackedVector3Array, n: Vector3) -> void:
	var c := Vector3.ZERO
	for v in ring:
		c += v
	c /= ring.size()
	for i in ring.size():
		MeshKit.tri(st, c, ring[i], ring[(i + 1) % ring.size()], n)


## Нёбо (dy > 0) или язык (dy < 0) — полоса по линии рта между кромками (k — доля полуширины).
static func _palate(stations: Array[Vector4], k: float, dy: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := Vector3.DOWN if dy > 0.0 else Vector3.UP
	for i in stations.size() - 1:
		var a := stations[i]
		var b := stations[i + 1]
		var al := Vector3(-a.y * k, a.w + dy, a.x)
		var ar := Vector3(a.y * k, a.w + dy, a.x)
		var bl := Vector3(-b.y * k, b.w + dy, b.x)
		var br := Vector3(b.y * k, b.w + dy, b.x)
		MeshKit.tri(st, al, ar, br, n)
		MeshKit.tri(st, al, br, bl, n)
	return st.commit()


## Ряд костяных зубов по кромке рта, от середины боков вокруг морды: остриём вниз (up = −1) или вверх.
static func _teeth(stations: Array[Vector4], up: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim: Array[Vector3] = []                  # кромка: правый бок → морда → левый бок
	for i in range(1, stations.size()):
		rim.append(Vector3(stations[i].y * 0.92, stations[i].w, stations[i].x))
	for i in range(stations.size() - 1, 0, -1):
		rim.append(Vector3(-stations[i].y * 0.92, stations[i].w, stations[i].x))
	var mid := (stations[0].x + stations[stations.size() - 1].x) * 0.5   # зубы смотрят внутрь, к середине рта
	var total := 0.0
	for i in rim.size() - 1:
		total += rim[i].distance_to(rim[i + 1])
	const COUNT := 9
	for k in COUNT:
		var want := total * (k + 0.5) / COUNT
		var i := 0
		while i < rim.size() - 2 and want > rim[i].distance_to(rim[i + 1]):
			want -= rim[i].distance_to(rim[i + 1])
			i += 1
		var along := (rim[i + 1] - rim[i]).normalized()
		var c := rim[i] + along * want
		var inward := Vector3(-c.x, 0, mid - c.z).normalized()
		_hull(st, [c - along * 0.024, c + along * 0.024, c + inward * 0.03, c + Vector3(0, 0.075 * up, 0) + inward * 0.012])
	return st.commit()


static func _hull_mesh(pts: Array[Vector3]) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_hull(st, pts)
	return st.commit()


## Выпуклая оболочка нескольких точек (перебор троек — точек мало): грани плоские, лицом наружу.
static func _hull(st: SurfaceTool, pts: Array[Vector3]) -> void:
	var n := pts.size()
	for i in n:
		for j in range(i + 1, n):
			for k in range(j + 1, n):
				var nrm := (pts[j] - pts[i]).cross(pts[k] - pts[i])
				if nrm.length_squared() < 1e-12:
					continue
				nrm = nrm.normalized()
				var above := false
				var below := false
				for m in n:
					var s := nrm.dot(pts[m] - pts[i])
					if s > 1e-5:
						above = true
					elif s < -1e-5:
						below = true
				if above == below:
					continue                        # не грань (или все точки в одной плоскости)
				MeshKit.tri(st, pts[i], pts[j], pts[k], -nrm if above else nrm)


func _particles(amount: int, lifetime: float, texels: int, v_min: float, v_max: float, spread: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = v_min
	p.initial_velocity_max = v_max
	p.gravity = Vector3(0, -9.0, 0)
	p.local_coords = false
	p.mesh = PixelFx.quad(texels, _mud)
	add_child(p)
	return p


## Круги по воде и илу за макушкой: кольцо в пиксель мира (шейдер ripple_ring) растёт от RIPPLE_R0 до
## RIPPLE_R1 целыми пикселями (радиус — масштаб частицы) и гаснет ступенями прозрачности.
func _ripple_trail() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 8
	p.lifetime = 1.1
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.0
	p.local_coords = false
	p.scale_amount_min = RIPPLE_R1
	p.scale_amount_max = RIPPLE_R1
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, RIPPLE_R0 / RIPPLE_R1))
	grow.add_point(Vector2(1.0, 1.0))
	p.scale_amount_curve = grow
	var quad := PlaneMesh.new()                  # кольцо радиуса 1 в осях меша — с запасом на округление
	quad.size = Vector2.ONE * 2.5
	_ripple_mat = ShaderMaterial.new()
	_ripple_mat.shader = RIPPLE_SHADER
	_ripple_mat.set_shader_parameter(&"tint", _mud)
	_ripple_mat.set_shader_parameter(&"width_px", RIPPLE_W_PX)
	_ripple_mat.set_shader_parameter(&"r0", RIPPLE_R0)
	_ripple_mat.set_shader_parameter(&"r1", RIPPLE_R1)
	_ripple_mat.set_shader_parameter(&"alpha", 0.8)
	_ripple_mat.render_priority = 1               # поверх прозрачной воды, а не под ней
	quad.material = _ripple_mat
	p.mesh = quad
	p.emitting = false
	add_child(p)
	return p
