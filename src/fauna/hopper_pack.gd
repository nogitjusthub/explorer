class_name HopperPack
extends Creature
## Стая скакунов (GDD §5.4): 2–3 зверя держатся тесной группой в одном тайле и ходят только по
## склонам (ни стенки вверх, ни обрыва вниз), в воду не заходят. Пока не заметили машину — стая медленно
## патрулирует окрестности места появления: обходит точки на кольце вокруг него, на каждой
## осматривается. Заметили (увидели машину ближе hopper_sight_r, услышали её шум или посадку челнока) —
## крик, и стая
## гонится (hopper_speed — быстрее танка, медленнее ровера) по общему полю путей вида HOPPER. Догнали —
## встают рядом с машиной, и передний бросается вперёд и кусает (раз в hopper_bite_cd_s); машину
## укусы не двигают — только раскачивают корпус. Кусают только на одном с машиной уровне (Creature.same_level):
## машина под скалой или на ней — стая обходит уступ по полю путей, а обхода нет — ждёт у края.
## Танк на ходу расшвыривает стаю. Не подобраться к машине
## fauna_give_up_s (или погоня дольше hopper_chase_s / дальше hopper_chase_dist), испугалась (смерч, молния, разлом
## рядом, капсула десанта) — стая отбегает от машины, затем возвращается к месту появления (не пройти — живёт, где
## застряла) и снова патрулирует; hopper_calm_s машину не замечает. На глазах не пропадает — уходит только вдали.
## Разбуженная шумным событием (посадка челнока) стая сначала бежит к нему — это ещё не погоня, её пределы
## не тратятся; заметила машину — погоня с этого места. Добежала, а машины не видно — ждёт, пока слышен
## шум, и остаётся патрулировать там; застряла по пути — патрулирует, где стоит.
## Облик — помесь «Чужого» и велоцираптора: чёрный глянцевый хитин с сине-фиолетовым отливом, наклонный
## корпус на «птичьих» ногах (бедро, голень, высокая стопа с поднятым когтем-серпом), короткие передние
## лапки с когтями, трубки на спине, короткий ребристый хвост; голова — длинный гладкий купол без глаз,
## только две красные искры, в пасти — костяные зубы, изнутри она алая. На ходу бегут (ноги враз, корпус
## покачивается, хвост — в противофазе), стоя озираются, склоняют голову, переступают, дёргают хвостом;
## заметив машину — встают на дыбы с разинутой пастью (крик), передний кусает броском.
## Таран: каждая особь — своё тело (RamBody), машина на скорости валки деревьев убивает её ram_hits_hopper
## ударами — убитая замирает, мигает и пропадает облачком, уцелевшие пригибаются (оглушены), кусает первая
## живая в строю; убиты все — стаи нет.

enum State { IDLE, ALERT, CHASE, RETREAT }

const SKIN_COLOR := Color(0.169, 0.149, 0.22)    ## #2B2638 — хитин: корпус, голова, хвост
const DARK_COLOR := Color(0.102, 0.09, 0.141)    ## #1A1724 — лапы, нижняя челюсть
const RIM_COLOR := Color(0.29, 0.267, 0.384)     ## #4A4462 — трубки на спине, когти: силуэт на тёмном грунте
const TOOTH_COLOR := Color(0.949, 0.922, 0.82)   ## #F2EBD1 — зубы
const EYE_COLOR := Color(1.0, 0.251, 0.2)        ## #FF4033 — глаза-искры (семейная черта фауны)
const MOUTH_COLOR := Color(0.702, 0.125, 0.165)  ## #B3202A — пасть изнутри
## Скелет особи (её оси: перед — по −Z, y — от земли; тайлы до масштаба SIZE).
const SIZE := 1.3                        ## звери крупные — в обычном масштабе читаются поодиночке
const HIP := Vector3(0, 0.22, 0.04)      ## таз — ось наклона корпуса; по бокам — бёдра
const HIP_X := 0.04
const THIGH := 0.1
const SHIN := 0.11
const HEEL := Vector3(0, 0.05, 0.075)    ## пятка стоящей ноги (стопа от неё — до земли)
const NECK_AT := Vector3(0, 0.1, -0.2)       ## шарнир головы — в осях корпуса
const JAW_AT := Vector3(0, -0.012, -0.03)    ## шарнир челюсти — в осях головы
const TAIL_AT := Vector3(0, 0.028, 0.075)    ## корень хвоста — в осях корпуса
const TAIL2_AT := Vector3(0, 0.03, 0.08)     ## второй сегмент хвоста — в осях первого
const ARM_AT := Vector3(0.032, 0.0, -0.14)   ## плечо (правое) — в осях корпуса
const JAW_OPEN := 0.8                    ## рад — пасть раскрыта до упора
const STEP_S := 0.3                      ## стоя переступает с ноги на ногу за столько
const TWITCH_S := 0.5                    ## хвост дёргается столько
const ALERT_S := 0.6
const SEE_R := 8.0                       ## тайлов: в погоне машину ближе этого стая видит и без шума
const STANDOFF := 0.8                    ## стая встаёт на таком расстоянии от центра машины
const REACH := 1.05                      ## отсюда передний достаёт машину броском
const HOME_STUCK_S := 2.0                ## не продвигается к дому столько — остаётся жить здесь
const LUNGE_S := 0.3
const LUNGE_LEN := 0.42
const STUN_S := 1.0
const BUMP_LEN := 1.6                    ## танк отшвыривает стаю на столько тайлов
const PATROL_PAUSE_MIN_S := 1.0          ## на точке патруля стая стоит столько…
const PATROL_PAUSE_MAX_S := 2.5          ## …до стольких секунд
const PATROL_STUCK_S := 1.0              ## не продвинулась столько — точка недоступна, берёт следующую
const RAM_R := 0.2                       ## радиус тела особи под тараном машины
const PUFF_COLOR := Color(0.42, 0.39, 0.55)   ## облачко гибели — светлее хитина
## Места в строю (x, z) относительно центра стаи; перед — по −z, первый — передний (он и кусает).
const FORMATION: Array[Vector2] = [Vector2(0, -0.2), Vector2(-0.17, 0.07), Vector2(0.17, 0.07), Vector2(0, 0.28)]

static var _kit := {}                    ## меши особи: строятся раз за игру, общие у всех стай (_build_kit)

var state := State.IDLE
var home := Vector2.ZERO
var source: Variant = null               ## шумное событие, к которому идёт стая (посадка челнока)
var _to_source := false                  ## бежит на шум: погоня (и её пределы) — с момента, когда заметит машину
var _spent: Variant = null               ## шум, на который уже бегала и осталась, — на него больше не просыпается

## Особи: узлы модели (node, body, head, jaw, throat, tail, tail2, arms, thighs, shins, feet), тело под
## тараном (ram) и состояние
## анимации (phase — фаза шага, clock, idle — до новой повадки, look/look_to — голова: поворот, наклон,
## склон набок; yaw/yaw_to — разворот корпуса, crouch/crouch_t — присед, rear — дыбы, jaw_open — пасть,
## step — переступает, twitch — хвост, react — запаздывание крика).
var _members: Array[Dictionary] = []
var _prev_pos := Vector2.ZERO
var _speed := 0.0                        ## сглаженная скорость стаи — темп бега
var _heading := Vector2(0, -1)
var _goal := Vector2.ZERO
var _moving := false
var _timer := 0.0
var _patrol_angle := 0.0
var _stuck := 0.0
var _chase_from := Vector2.ZERO
var _chase_t := 0.0
var _cd := 0.0
var _lunge := 0.0
var _stun := 0.0
var _calm := 0.0                         ## машину не замечает ещё столько (после отступления)


func _init() -> void:
	name = "HopperPack"


func setup(at: Vector2, count: int) -> void:
	home = at
	pos = at
	_goal = at
	_heading = Vector2.from_angle(rng.randf() * TAU)
	_patrol_angle = rng.randf() * TAU
	for i in clampi(count, 1, FORMATION.size()):
		var m := _build_model()
		add_child(m["node"])
		m["ram"] = add_body(rules.ram_hits_hopper, RAM_R, m["node"], PUFF_COLOR)
		_members.append(m)
	_place_all(0.0)
	for m in _members:
		(m["node"] as Node3D).reset_physics_interpolation()


## Бегство (испуг): стая уходит прочь и исчезает.
func flee() -> void:
	state = State.RETREAT
	aggressive = false
	_timer = rules.hopper_retreat_s
	_calm = rules.hopper_calm_s
	_stuck = 0.0


## Разбудить (шумное событие — посадка челнока): крик и бег на шум.
func wake(toward: Variant = null) -> void:
	if state == State.IDLE and _calm <= 0.0:
		source = toward
		_alert()


func step(dt: float) -> void:
	tick_bodies(dt)
	if dead:
		return
	_cd = maxf(_cd - dt, 0.0)
	_lunge = maxf(_lunge - dt, 0.0)
	_stun = maxf(_stun - dt, 0.0)
	_moving = false
	match state:
		State.IDLE:
			_patrol(dt)
			_calm = maxf(_calm - dt, 0.0)
			if _calm > 0.0:
				pass
			elif noise.hears_vehicle(pos) or pos.distance_to(vehicle.state.pos) < rules.hopper_sight_r:
				_alert()
			else:
				var heard: Variant = noise.heard_source(pos)
				if heard != null and heard != _spent:
					wake(heard)
		State.ALERT:
			_timer -= dt
			_face(vehicle.state.pos - pos)
			if _timer <= 0.0:
				state = State.CHASE
				aggressive = true
				_to_source = source != null
				_start_chase()
		State.CHASE:
			_chase(dt)
		State.RETREAT:
			_timer -= dt
			if _timer > 0.0:
				var away := (pos - vehicle.state.pos).normalized()
				_move_pack(pos + away * 3.0, rules.hopper_wander_speed * 2.5, dt)
			else:
				_go_home(dt)
	_place_all(dt)


func _alert() -> void:
	state = State.ALERT
	_timer = ALERT_S
	EventBus.fauna_alerted.emit(&"hopper", Vector3(pos.x, ground_y(pos), pos.y))


## Патруль: стая медленно обходит точки на кольце вокруг места появления (по кругу, с разбросом),
## на каждой ненадолго встаёт и осматривается. Не пройти к точке (стенка, вода) — берёт следующую.
func _patrol(dt: float) -> void:
	if pos.distance_to(_goal) < 0.1 or _stuck > PATROL_STUCK_S:
		_timer -= dt
		if _timer <= 0.0:
			_timer = rng.randf_range(PATROL_PAUSE_MIN_S, PATROL_PAUSE_MAX_S)
			_patrol_angle += rng.randf_range(0.6, 1.3)
			_goal = home + Vector2.from_angle(_patrol_angle) * rng.randf_range(0.5, 1.0) * rules.hopper_patrol_r
			_stuck = 0.0
		return
	var before := pos
	_move_pack(_goal, rules.hopper_wander_speed, dt)
	_stuck = _stuck + dt if pos.distance_squared_to(before) < 0.0001 else 0.0


## Погоня — с этого места и момента: пределы hopper_chase_s, hopper_chase_dist и потеря интереса.
func _start_chase() -> void:
	_chase_from = pos
	_chase_t = 0.0
	reset_interest()


## Бег на шум: заметила машину — погоня отсюда; добежала — ждёт, пока шум слышен, затем патрулирует здесь;
## не продвигается к цели fauna_give_up_s — патрулирует, где стоит.
func _run_to_source(dt: float, hunting: bool) -> void:
	if hunting:
		_to_source = false
		source = null
		_start_chase()
		return
	var target: Vector2 = source
	var there := pos.distance_to(target) < 1.5
	if lost_interest(dt, pos.distance_to(target), there) or (there and noise.heard_source(pos) == null):
		_settle()
		return
	if not there:
		_move_pack(target, rules.hopper_speed, dt)


## Отступила — шагом домой: дошла — патрулирует там; не пройти (стенка, вода) — остаётся жить, где застряла.
func _go_home(dt: float) -> void:
	var before := pos
	_move_pack(home, rules.hopper_wander_speed * 1.5, dt)
	_stuck = _stuck + dt if pos.distance_squared_to(before) < 0.0001 else 0.0
	if pos.distance_to(home) < 0.5 or _stuck > HOME_STUCK_S:
		state = State.IDLE
		home = pos
		_goal = pos
		_timer = 0.0
		_stuck = 0.0


## Остаётся здесь: патрулирует вокруг этого места, машину замечает, как обычно.
func _settle() -> void:
	state = State.IDLE
	aggressive = false
	_to_source = false
	_spent = source
	source = null
	home = pos
	_goal = pos
	_timer = 0.0
	reset_interest()


func _chase(dt: float) -> void:
	var vp := vehicle.state.pos
	var d := pos.distance_to(vp)
	var hunting := noise.hears_vehicle(pos) or d < SEE_R
	if _to_source:
		_run_to_source(dt, hunting)
		if _to_source or state != State.CHASE:
			return
	_chase_t += dt
	# Вблизи и на одном уровне — прямо к машине; машина за уступом (под скалой или на ней) — в обход по полю
	# путей, а обхода нет — стоит у края, глядя на неё, пока не потеряет интерес.
	var level := d <= 2.0 and Creature.same_level(query, pos, vp)
	if _stun <= 0.0:
		var goal: Vector2
		if not level:
			var field: FlowField = director.call(&"field", FlowField.Mode.HOPPER)
			var t := Grid.tile_of_world(pos.x, pos.y)
			var next := field.next_tile(query, t) if field != null else t
			goal = Vector2(next.x + 0.5, next.y + 0.5) if next != t else vp
		else:
			goal = vp + (pos - vp).normalized() * STANDOFF
		_move_pack(goal, rules.hopper_speed, dt)
		if d < 2.0 and (level or not _moving):
			_face(vp - pos)                      # вблизи — передним к машине
	_tank_bump(vp)
	var reach := d <= REACH and level and not vehicle.state.falling and not vehicle.state.drowning
	if reach and _cd <= 0.0 and _stun <= 0.0:
		_bite(vp)
	if lost_interest(dt, d, reach) or _chase_t > rules.hopper_chase_s \
			or pos.distance_to(_chase_from) > rules.hopper_chase_dist:
		flee()


## Укус: передний бросается вперёд; машину не двигает — только раскачивает корпус.
func _bite(vp: Vector2) -> void:
	_cd = rules.hopper_bite_cd_s
	_lunge = LUNGE_S
	_face(vp - pos)
	damaged.emit(rules.hopper_bite, &"hopper")
	vehicle.rock(Vehicle.ROCK_BITE, (vp - pos).normalized())


## Танк на ходу расшвыривает стаю массой — только на одном с ней уровне (не через уступ). Толчок на
## BUMP_LEN — шагами меньше тайла (Creature.move_on_grid) по склонам вида: в воду и с обрыва не улетает,
## остаётся у края.
func _tank_bump(vp: Vector2) -> void:
	if vehicle.cls.mass < 2.0 or vehicle.state.vel.length() < 1.5 or pos.distance_to(vp) > 0.7 \
			or not Creature.same_level(query, pos, vp):
		return
	var away := (pos - vp).normalized() if pos.distance_to(vp) > 0.01 else Vector2.RIGHT
	pos = Creature.move_on_grid(query, FlowField.Mode.HOPPER, pos, pos + away * BUMP_LEN)
	_stun = STUN_S


func _move_pack(goal: Vector2, speed: float, dt: float) -> void:
	var delta := goal - pos
	if delta.length() < 0.03:
		return
	var np := Creature.move_on_grid(query, FlowField.Mode.HOPPER, pos, pos + delta.limit_length(speed * dt))
	_moving = np != pos
	pos = np
	_face(delta)


func _face(dir: Vector2) -> void:
	if dir.length_squared() > 0.0001:
		_heading = dir.normalized()


## Таран убил особь (или ударил, если ram_hits_hopper > 1): уцелевшие пригибаются, оглушённые.
func _on_rammed(_b: RamBody, _dir: Vector2, _killed: bool) -> void:
	_stun = STUN_S


## Передний в строю — первый живой: он и бросается в укусе.
func _front() -> int:
	for i in _members.size():
		if (_members[i]["ram"] as RamBody).alive():
			return i
	return -1


## Строй вокруг центра стаи, развёрнутый по курсу; каждой особи — своя поза (_pose): на ходу бегут, стоя
## озираются, при крике встают на дыбы; передний при укусе бросается вперёд. Убитая тараном особь замирает,
## где её настигло (мигает и пропадает — RamBody).
func _place_all(dt: float) -> void:
	var yaw := atan2(-_heading.x, -_heading.y)
	var spd := 0.0
	if _moving and dt > 0.0:
		spd = minf(pos.distance_to(_prev_pos) / dt, rules.hopper_speed)
	_prev_pos = pos
	_speed = lerpf(_speed, spd, _ease(dt, 6.0))
	var go := clampf(_speed / 0.5, 0.0, 1.0)             # 0 — стоит, 1 — на ходу
	var run := clampf((_speed - rules.hopper_wander_speed) / (rules.hopper_speed - rules.hopper_wander_speed),
			0.0, 1.0)                                      # 0 — шаг патруля, 1 — бег погони
	var front := _front()
	for i in _members.size():
		var m := _members[i]
		var body: RamBody = m["ram"]
		if not body.alive():
			continue
		var off: Vector2 = FORMATION[i] * SIZE * 1.15      # строй раздвинут соразмерно росту
		var local := Vector3(off.x, 0, off.y).rotated(Vector3.UP, yaw)
		var p := pos + Vector2(local.x, local.z)
		var bite := 0.0
		var snap := false
		if i == front and _lunge > 0.0:
			var k := 1.0 - _lunge / LUNGE_S
			bite = sin(k * PI)
			snap = k > 0.6                                 # к концу броска пасть захлопывается
			p += _heading * bite * LUNGE_LEN
		var lift := _pose(m, dt, go, run, bite, snap)
		var node: Node3D = m["node"]
		var gy := ground_y(p)
		node.position = Vector3(p.x, gy + lift, p.y)
		node.rotation.y = yaw + m["yaw"]
		body.pos = p
		body.y = gy


## Поза особи за кадр: походка, повадки на месте, крик, бросок. Возвращает подъём над землёй (прыжок).
func _pose(m: Dictionary, dt: float, go: float, run: float, bite: float, snap: bool) -> float:
	m["clock"] += dt
	var t: float = m["clock"]
	var alert := state == State.ALERT
	var hunt := state == State.CHASE and go < 0.5        # у машины: низкая стойка, пасть приоткрыта
	var calm := go < 0.5 and not alert and bite == 0.0
	if calm:
		m["idle"] -= dt
		if m["idle"] <= 0.0:
			_idle_act(m, hunt)
	var stun := _stun / STUN_S
	var crouch_to := 0.0
	if calm and m["crouch_t"] > 0.0:
		m["crouch_t"] -= dt
		crouch_to = 1.0
	if hunt:
		crouch_to = maxf(crouch_to, 0.6)
	crouch_to = maxf(crouch_to, stun)
	var rear_to := 1.0 if alert and ALERT_S - _timer > m["react"] else 0.0
	var jaw_to := rear_to
	if hunt:
		jaw_to = 0.2 + 0.15 * sin(t * 9.0 + m["react"] * 40.0)     # шипит
	if bite > 0.0:
		jaw_to = 0.0 if snap else 1.0
	m["crouch"] = lerpf(m["crouch"], crouch_to, _ease(dt, 7.0))
	m["rear"] = lerpf(m["rear"], rear_to, _ease(dt, 14.0))
	m["jaw_open"] = lerpf(m["jaw_open"], jaw_to, _ease(dt, 30.0 if jaw_to > m["jaw_open"] else 20.0))
	m["look"] = (m["look"] as Vector3).lerp(m["look_to"] if calm else Vector3.ZERO, _ease(dt, 12.0))
	m["yaw"] = lerpf(m["yaw"], m["yaw_to"] if calm else 0.0, _ease(dt, 6.0))
	var crouch: float = m["crouch"]
	var rear: float = m["rear"]
	var jaw: float = m["jaw_open"]
	var look: Vector3 = m["look"]

	# Шаг: ноги враз, на бегу — шире и выше; стоя — переступает с ноги на ногу.
	var step := 0.0
	if m["step"] > 0.0:
		m["step"] = maxf(m["step"] - dt, 0.0)
		step = sin(m["step"] / STEP_S * PI)
	var hz := 2.0 + 0.75 * _speed
	m["phase"] = fmod(m["phase"] + dt * (TAU * hz * go + (PI / STEP_S if step > 0.0 else 0.0)), TAU)
	var ph: float = m["phase"]
	var stride := (0.045 + 0.03 * run) * go
	var lift := (0.03 + 0.03 * run) * go + 0.025 * step
	var bob := (0.006 + 0.01 * run) * go

	# Корпус: на бегу наклонён вперёд (в погоне — сильнее), на дыбах — назад; голова держится ровно.
	var hip_y := HIP.y - bob * cos(2.0 * ph) - 0.05 * crouch + 0.025 * rear + 0.02 * bite
	var lean := -(0.08 + 0.22 * run) * go - 0.12 * crouch + 0.6 * rear - 0.3 * bite
	var body: Node3D = m["body"]
	body.position = Vector3(0, hip_y, HIP.z)
	body.rotation = Vector3(lean, 0.08 * sin(ph) * go, 0.05 * sin(ph) * go + stun * 0.3 * sin(t * 15.0))
	var head: Node3D = m["head"]
	head.rotation = Vector3(-0.75 * lean + look.y + 0.4 * rear + rear * 0.05 * sin(t * 55.0) - 0.04 * cos(2.0 * ph) * go,
			look.x - 0.08 * sin(ph) * go, look.z)
	(m["jaw"] as Node3D).rotation.x = -JAW_OPEN * jaw
	var throat: Node3D = m["throat"]
	throat.visible = jaw > 0.03
	throat.scale.y = maxf(tan(JAW_OPEN * jaw), 0.01)

	# Хвост — в противофазе шагу; стоя покачивается и изредка дёргается.
	var twitch := 0.0
	if m["twitch"] > 0.0:
		m["twitch"] = maxf(m["twitch"] - dt, 0.0)
		twitch = 0.6 * sin(m["twitch"] * 45.0) * m["twitch"] / TWITCH_S
	var sway := -0.3 * sin(ph) * go + 0.15 * sin(t * 1.7 + m["react"] * 20.0) * (1.0 - go) + twitch
	(m["tail"] as Node3D).rotation = Vector3(-0.15 * run * go - 0.45 * rear + 0.06 * cos(2.0 * ph) * go, sway, 0.0)
	(m["tail2"] as Node3D).rotation = Vector3(-0.1 * go - 0.2 * rear, sway * 0.8 + twitch * 0.6, 0.0)

	# Лапки: на бегу ходят в такт, на дыбах — раскинуты, в броске — вперёд; ноги — по пяткам.
	var arms: Array = m["arms"]
	var thighs: Array = m["thighs"]
	var shins: Array = m["shins"]
	var feet: Array = m["feet"]
	var trail := Vector3(0, 0.03, 0.07) * bite           # в прыжке ноги поджаты назад
	for s in 2:
		var sx := -1.0 if s == 0 else 1.0
		var lp := ph + PI * s
		(arms[s] as Node3D).rotation = Vector3(0.25 * sin(lp) * go + 0.3 * crouch + 0.9 * rear + 1.1 * bite, 0.0,
				sx * (0.45 * rear + 0.2 * bite))
		var swing := maxf(cos(lp), 0.0)
		var hip := Vector3(sx * HIP_X, hip_y, HIP.z)
		var heel := Vector3(sx * HIP_X, HEEL.y + lift * swing, HEEL.z - stride * sin(lp) - 0.02 * crouch) + trail
		_leg(thighs[s], shins[s], feet[s], hip, heel, -0.6 * swing * go - 0.5 * bite)
	return bite * 0.06


## Новая повадка стоящей особи: озирается (иногда склоняет голову набок), переступает с разворотом,
## дёргает хвостом или приседает. У машины (hunt) взгляд от неё почти не отводит.
func _idle_act(m: Dictionary, hunt: bool) -> void:
	m["idle"] = rng.randf_range(0.35, 1.3)
	var k := 0.35 if hunt else 1.0
	var roll := rng.randf()
	if roll < 0.45:
		var tilt := rng.randf_range(-0.45, 0.45) if rng.randf() < 0.4 else 0.0
		m["look_to"] = Vector3(rng.randf_range(-0.9, 0.9) * k, rng.randf_range(-0.15, 0.3), tilt)
	elif roll < 0.7:
		m["step"] = STEP_S
		m["phase"] = PI * (0.5 if rng.randf() < 0.5 else 1.5)    # середина шага — одна нога поднята
		m["yaw_to"] = rng.randf_range(-0.45, 0.45) * k
	elif roll < 0.88:
		m["twitch"] = TWITCH_S
	else:
		m["crouch_t"] = rng.randf_range(0.6, 1.4)


## Нога от сустава hip до пятки heel: бедро и голень — двухзвенная ИК в плоскости y–z, колено — вперёд;
## стопа висит на пятке, toe — наклон пальцев.
func _leg(thigh: Node3D, shin: Node3D, foot: Node3D, hip: Vector3, heel: Vector3, toe: float) -> void:
	var d := Vector2(heel.z - hip.z, heel.y - hip.y)
	var dist := clampf(d.length(), SHIN - THIGH + 0.005, THIGH + SHIN - 0.002)
	var dir := d.normalized()
	var a := acos(clampf((THIGH * THIGH + dist * dist - SHIN * SHIN) / (2.0 * THIGH * dist), -1.0, 1.0))
	var k1 := dir.rotated(a)
	var k2 := dir.rotated(-a)
	var k := (k1 if k1.x < k2.x else k2) * THIGH
	var knee := hip + Vector3(0, k.y, k.x)
	var end := hip + Vector3(0, dir.y, dir.x) * dist
	thigh.position = hip
	thigh.rotation.x = atan2(-k.x, -k.y)
	shin.position = knee
	shin.rotation.x = atan2(-(end.z - knee.z), -(end.y - knee.y))
	foot.position = end
	foot.rotation.x = toe


static func _ease(dt: float, rate: float) -> float:
	return 1.0 - exp(-rate * dt)


## Особь из 14 частей; шарниры — сами части (корпус, голова, челюсть, хвост, лапки, звенья ног), меши — общие
## у всех стай. Тень отбрасывают только крупные: корпус, голова, хвост.
func _build_model() -> Dictionary:
	if _kit.is_empty():
		_build_kit()
	var root := Node3D.new()
	root.scale = Vector3.ONE * SIZE
	var body := _part(root, &"torso", HIP, true)
	var head := _part(body, &"skull", NECK_AT, true)
	var tail := _part(body, &"tail", TAIL_AT, true)
	var m := {"node": root, "body": body, "head": head, "jaw": _part(head, &"jaw", JAW_AT),
			"throat": _part(head, &"throat", JAW_AT), "tail": tail, "tail2": _part(tail, &"tail2", TAIL2_AT),
			"arms": [], "thighs": [], "shins": [], "feet": [],
			"phase": rng.randf() * TAU, "clock": 0.0, "idle": rng.randf_range(0.2, 1.5),
			"look": Vector3.ZERO, "look_to": Vector3.ZERO, "yaw": 0.0, "yaw_to": 0.0, "crouch": 0.0, "crouch_t": 0.0,
			"rear": 0.0, "jaw_open": 0.0, "step": 0.0, "twitch": 0.0, "react": rng.randf_range(0.0, 0.15)}
	for sx: float in [-1.0, 1.0]:
		(m["arms"] as Array).append(_part(body, &"arm", Vector3(sx * ARM_AT.x, ARM_AT.y, ARM_AT.z)))
		(m["thighs"] as Array).append(_part(root, &"thigh", Vector3.ZERO))
		(m["shins"] as Array).append(_part(root, &"shin", Vector3.ZERO))
		(m["feet"] as Array).append(_part(root, &"foot", Vector3.ZERO))
	return m


func _part(parent: Node3D, mesh: StringName, at: Vector3, shadow: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _kit[mesh]
	mi.position = at
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Меши особи — раз за игру, общие у всех стай: стаи появляются каждые пару секунд, а ~12 мешей и
## материал на каждую — заминка в вебе. Делить их можно: мигание тарана — наложение material_overlay на
## MeshInstance3D особи (RamBody), гибель — скрытие её узла; сами меши и материалы не меняются.
## Каждая часть — в осях своего шарнира, из плоскогранных труб; цвет — в вершинах (хитин, кромка, кость —
## один материал с пиксельным узором хитина, пиксель — пиксель мира с поправкой на SIZE), у глаз и пасти —
## свои материалы.
static func _build_kit() -> void:
	# Хитин с мягким отливом: блик неширокий и неяркий.
	var skin := BodyMaterial.tinted(BodyMaterial.Pattern.CHITIN, Grid.ART_PX / SIZE, 0.6, 0.3, 0.35)
	var eye := StandardMaterial3D.new()
	eye.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye.albedo_color = EYE_COLOR
	var mouth := Creature.material(MOUTH_COLOR)
	mouth.emission_enabled = true
	mouth.emission = EYE_COLOR
	mouth.emission_energy_multiplier = 0.25

	# Корпус: от крупа к шее, изгиб вверх; на плечах — две пары трубок назад-вверх.
	var st := _begin()
	_tube(st, SKIN_COLOR, [Vector3(0, 0.028, 0.075), Vector3(0, 0.024, 0.02), Vector3(0, 0.012, -0.045),
			Vector3(0, 0.014, -0.115), Vector3(0, 0.034, -0.16), Vector3(0, 0.068, -0.185), Vector3(0, 0.104, -0.198)],
			[Vector2(0.026, 0.028), Vector2(0.05, 0.055), Vector2(0.054, 0.062), Vector2(0.048, 0.057),
			Vector2(0.037, 0.041), Vector2(0.025, 0.027), Vector2(0.02, 0.02)])
	for sx: float in [-1.0, 1.0]:
		_tube(st, RIM_COLOR, [Vector3(sx * 0.02, 0.062, -0.155), Vector3(sx * 0.034, 0.125, -0.118)],
				[Vector2(0.01, 0.01), Vector2(0.008, 0.008)], 4)
		_tube(st, RIM_COLOR, [Vector3(sx * 0.024, 0.062, -0.1), Vector3(sx * 0.036, 0.112, -0.058)],
				[Vector2(0.009, 0.009), Vector2(0.007, 0.007)], 4)
	_kit[&"torso"] = _commit(st, skin)

	# Голова: купол от морды назад-вверх, по краю пасти — клыки; глаза — две красные искры.
	st = _begin()
	_tube(st, SKIN_COLOR, [Vector3(0, 0.003, -0.12), Vector3(0, 0.005, -0.106), Vector3(0, 0.01, -0.07),
			Vector3(0, 0.019, -0.032), Vector3(0, 0.031, 0.006), Vector3(0, 0.047, 0.042), Vector3(0, 0.061, 0.074),
			Vector3(0, 0.072, 0.1)],
			[Vector2(0.009, 0.009), Vector2(0.016, 0.017), Vector2(0.022, 0.025), Vector2(0.028, 0.031),
			Vector2(0.031, 0.034), Vector2(0.027, 0.029), Vector2(0.018, 0.02), Vector2.ZERO])
	for sx: float in [-1.0, 1.0]:
		for z: float in [-0.1, -0.084, -0.068, -0.052]:
			_tube(st, TOOTH_COLOR, [Vector3(sx * 0.017, -0.004, z), Vector3(sx * 0.017, -0.021, z - 0.003)],
					[Vector2(0.004, 0.004), Vector2.ZERO], 3)
	var skull := _commit(st, skin)
	st = _begin()
	for sx: float in [-1.0, 1.0]:
		_tube(st, EYE_COLOR, [Vector3(sx * 0.017, 0.024, -0.085), Vector3(sx * 0.021, 0.031, -0.05)],
				[Vector2(0.007, 0.007), Vector2(0.007, 0.007)], 4)
	_kit[&"skull"] = _commit(st, eye, skull)

	# Нижняя челюсть: верх — по линии пасти, зубы вверх.
	st = _begin()
	_tube(st, DARK_COLOR, [Vector3(0, -0.01, 0.012), Vector3(0, -0.012, -0.02), Vector3(0, -0.011, -0.05),
			Vector3(0, -0.008, -0.075), Vector3(0, -0.004, -0.088)],
			[Vector2(0.022, 0.011), Vector2(0.02, 0.012), Vector2(0.017, 0.011), Vector2(0.011, 0.008), Vector2.ZERO])
	for sx: float in [-1.0, 1.0]:
		for z: float in [-0.065, -0.045, -0.025]:
			_tube(st, TOOTH_COLOR, [Vector3(sx * 0.011, -0.004, z), Vector3(sx * 0.011, 0.01, z - 0.002)],
					[Vector2(0.0035, 0.0035), Vector2.ZERO], 3)
	_kit[&"jaw"] = _commit(st, skin)

	# Пасть изнутри: клин от шарнира челюсти вперёд, высота — по раскрытию (scale.y = tg угла).
	st = _begin()
	var wedge: Array[Vector2] = [Vector2(0.008, 0.0), Vector2(-0.085, 0.0), Vector2(-0.085, -0.085)]   # (z, y)
	var w := 0.013
	var inside := Vector3(0, -0.028, -0.054)
	for sx: float in [-w, w]:
		_tri(st, Vector3(sx, wedge[0].y, wedge[0].x), Vector3(sx, wedge[1].y, wedge[1].x),
				Vector3(sx, wedge[2].y, wedge[2].x), inside)
	for i in 3:
		var a := wedge[i]
		var b := wedge[(i + 1) % 3]
		_tri(st, Vector3(-w, a.y, a.x), Vector3(w, a.y, a.x), Vector3(w, b.y, b.x), inside)
		_tri(st, Vector3(-w, a.y, a.x), Vector3(w, b.y, b.x), Vector3(-w, b.y, b.x), inside)
	_kit[&"throat"] = _commit(st, mouth)

	# Хвост — короткий, из двух ребристых сегментов; на конце — плоское лезвие.
	st = _begin()
	_tube(st, SKIN_COLOR, [Vector3(0, 0, -0.01), Vector3(0, 0.01, 0.028), Vector3(0, 0.016, 0.042),
			Vector3(0, 0.022, 0.056), Vector3(0, 0.03, 0.08)],
			[Vector2(0.026, 0.028), Vector2(0.02, 0.022), Vector2(0.015, 0.016), Vector2(0.017, 0.018),
			Vector2(0.013, 0.014)])
	_kit[&"tail"] = _commit(st, skin)
	st = _begin()
	_tube(st, SKIN_COLOR, [Vector3(0, 0, -0.005), Vector3(0, 0.004, 0.02), Vector3(0, 0.008, 0.032),
			Vector3(0, 0.01, 0.05), Vector3(0, 0.008, 0.072)],
			[Vector2(0.013, 0.014), Vector2(0.009, 0.01), Vector2(0.01, 0.011), Vector2(0.003, 0.013), Vector2.ZERO])
	_kit[&"tail2"] = _commit(st, skin)

	# Лапка: плечо — локоть назад — запястье вперёд, коготь.
	st = _begin()
	_tube(st, DARK_COLOR, [Vector3(0, 0.005, 0.005), Vector3(0, -0.045, 0.014), Vector3(0, -0.05, -0.035)],
			[Vector2(0.014, 0.014), Vector2(0.012, 0.012), Vector2(0.01, 0.01)], 4)
	_tube(st, RIM_COLOR, [Vector3(0, -0.05, -0.035), Vector3(0, -0.062, -0.058)], [Vector2(0.007, 0.007), Vector2.ZERO], 3)
	_kit[&"arm"] = _commit(st, skin)

	# Нога: мощное бедро, тонкая голень, высокая стопа на пальцах с поднятым когтем-серпом.
	st = _begin()
	_tube(st, SKIN_COLOR, [Vector3(0, 0.012, 0), Vector3(0, -0.03, 0), Vector3(0, -THIGH, 0)],
			[Vector2(0.028, 0.034), Vector2(0.025, 0.03), Vector2(0.015, 0.016)])
	_kit[&"thigh"] = _commit(st, skin)
	st = _begin()
	_tube(st, DARK_COLOR, [Vector3(0, 0.005, 0), Vector3(0, -SHIN, 0)], [Vector2(0.015, 0.017), Vector2(0.012, 0.013)], 4)
	_kit[&"shin"] = _commit(st, skin)
	st = _begin()
	_tube(st, DARK_COLOR, [Vector3(0, 0.004, 0), Vector3(0, -0.046, -0.006)], [Vector2(0.012, 0.012), Vector2(0.011, 0.011)], 4)
	_tube(st, DARK_COLOR, [Vector3(0, -0.044, -0.004), Vector3(0, -0.049, -0.03), Vector3(0, -0.05, -0.048)],
			[Vector2(0.016, 0.008), Vector2(0.013, 0.006), Vector2.ZERO], 4)
	_tube(st, RIM_COLOR, [Vector3(0, -0.04, -0.012), Vector3(0, -0.024, -0.032)], [Vector2(0.006, 0.006), Vector2.ZERO], 3)
	_kit[&"foot"] = _commit(st, skin)


static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


## Поверхность из st с материалом mat — новым мешем или ещё одной поверхностью меша into.
static func _commit(st: SurfaceTool, mat: Material, into: ArrayMesh = null) -> ArrayMesh:
	st.set_material(mat)
	return st.commit(into)


## Труба по точкам path: сечения — эллипсы radii (полуширина, полувысота) из sides плоских граней, ребро —
## сверху. Нулевой радиус — острие, ненулевой на конце — плоская крышка.
static func _tube(st: SurfaceTool, color: Color, path: Array, radii: Array, sides: int = 5) -> void:
	st.set_color(color)
	var n := path.size()
	var rings: Array[PackedVector3Array] = []
	var prev_side := Vector3.RIGHT
	for i in n:
		var c: Vector3 = path[i]
		var r: Vector2 = radii[i]
		var t := ((path[mini(i + 1, n - 1)] as Vector3) - (path[maxi(i - 1, 0)] as Vector3)).normalized()
		var side := Vector3.UP.cross(t)
		side = side.normalized() if side.length_squared() > 0.04 else prev_side
		if side.dot(prev_side) < 0.0 and i > 0:
			side = -side                   # без перекрутки между сечениями
		prev_side = side
		var up := t.cross(side).normalized()
		var ring := PackedVector3Array()
		for k in sides:
			var ang := PI * 0.5 + TAU * k / sides
			ring.append(c + side * cos(ang) * r.x + up * sin(ang) * r.y)
		rings.append(ring)
	for i in n - 1:
		var inside := ((path[i] as Vector3) + (path[i + 1] as Vector3)) * 0.5
		for k in sides:
			var k2 := (k + 1) % sides
			_tri(st, rings[i][k], rings[i + 1][k], rings[i + 1][k2], inside)
			_tri(st, rings[i][k], rings[i + 1][k2], rings[i][k2], inside)
	for e: int in [0, n - 1]:
		if (radii[e] as Vector2).length_squared() > 0.0:
			var c: Vector3 = path[e]
			var inside := c.lerp(path[1] if e == 0 else path[n - 2], 0.5)
			for k in sides:
				_tri(st, c, rings[e][k], rings[e][(k + 1) % sides], inside)


## Треугольник лицом от точки inside, нормаль — по грани.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, inside: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-16:
		return
	n = n.normalized()
	if n.dot((a + b + c) / 3.0 - inside) < 0.0:
		n = -n
	MeshKit.tri(st, a, b, c, n)
