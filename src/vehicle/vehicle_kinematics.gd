class_name VehicleKinematics
extends RefCounted
## Один шаг движения машины по сетке, без физического движка (GDD §3.2, §4).
##
## - Управление относительно экрана: вход — направление в мире, длина — газ. Тормоза нет:
##   без ввода машина замедляется. С места (скорость ниже STOP_SPEED) машина сначала доворачивает
##   на месте к нужному направлению (до ALIGN_ANGLE) и только потом разгоняется. На ходу —
##   поворот по дуге; если нужное направление сзади, машина сбрасывает скорость, доворачивает на
##   месте и разгоняется. Танк и на ходу не едет, пока угол больше TANK_TURN_ANGLE.
## - Удар в стенку со скоростью «в стену» (поперёк ребра) от 2/3 max_speed — фиксированный урон
##   класса; касание по касательной и медленный упор урона не дают.
## - Стенку вверх не проезжает никто: составляющая скорости поперёк ребра обнуляется. Перепад
##   считается в точке пересечения ребра; ступенька до STEP_TOLERANCE (треть яруса) проезжается —
##   так частичная стенка (0 на одном конце ребра, ярус на другом) проходима у низкого конца.
## - Со стенки вниз — падение строго в соседний тайл, горизонтальная скорость ×0,5. Перепад
##   до STEP_TOLERANCE — не падение, машина просто съезжает.
## - В воду глубже допустимой для класса можно заехать или упасть, но машина тонет: управления
##   нет, за DROWN_TIME уходит на дно — гибель. Ховер не тонет.
## - Деревья валятся на скорости от порога класса (fells), иначе машина упирается. Тот же порог и та же
##   потеря скорости (after_felling) — у тарана фауны (FaunaDirector).
## - Внешние силы (ветер пылевой бури, тяга смерча) копятся в сносе push_vel, который затухает сам;
##   снос складывается со скоростью машины, стенки его гасят. Делить силу на массу — дело источника.
## - Разгон с места может быть сильнее обычного (launch_accel, танк): к LAUNCH_FADE·Vmax сходит к accel.
## - Зыбучий грунт вязкий: разгон × mire_accel_mult класса. Машина, что стоит на нём, прилипает —
##   за MIRE_STICK_S её засасывает (s.mire_stuck → 1): трогается совсем медленно и туго поворачивает,
##   вырывается за MIRE_UNSTICK_S езды. Ховеру (mire_accel_mult = 1) всё равно.
## - Пустой бак: предел скорости s.speed_cap (ползком). Корпуса севших челноков (s.obstacles) —
##   круглые препятствия: машина упирается и скользит вдоль, как у дерева, которое не валится.
## - Машина на подушке (ховер) держится на зеркале воды: рёбра и склоны для неё считаются по
##   высоте «не ниже воды»; её заносит — боковая скорость гаснет не сразу (cls.drift).

const GRAVITY := 20.0            ## мировых единиц/с²
const RADIUS := 0.3              ## радиус машины для стенок и деревьев, тайлов
const TREE_RADIUS := 0.35        ## радиус столкновения дерева, тайлов
const MIN_THROTTLE := 0.05
const CORNER_DIRS: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]   ## угол k → сосед по диагонали
const REVERSE_FRAC := 0.3		   ## задний ход (управление «относительно машины») — до такой доли Vmax
const UPHILL_SLOPE := 0.25       ## ярусов на тайл: склон считается подъёмом
const TANK_TURN_ANGLE := PI / 4.0
const STOP_SPEED := 1.0             ## тайл/с: медленнее — машина считается стоящей и разворачивается на месте
const ALIGN_ANGLE := deg_to_rad(12.0)   ## с места трогается, когда довернула до такого угла
const BRIDGE_EPS := 0.001           ## тайла: насколько за вершину «песочных часов» ставится центр (_bridge)
const STEP_TOLERANCE := 1.0 / 3.0   ## ярусов: такую ступеньку в точке пересечения машина берёт с ходу
const DROWN_TIME := 2.0             ## секунд от погружения до гибели
const SINK_SPEED := 0.35            ## мировых единиц/с — скорость погружения
const DEEP_MARGIN := 0.1            ## ярусов сверх допустимой глубины — уже тонет
const SURFACE_DRAG := 45.0          ## тайл/с²: въезд в воду, на неровный или зыбучий грунт гасит лишнюю скорость почти мгновенно
const PUSH_DAMP := 2.0              ## 1/с — затухание сноса: при силе a снос выходит на a / PUSH_DAMP
const LAUNCH_FADE := 0.6            ## доля Vmax, к которой разгон с места сходит к обычному
const MIRE_STICK_S := 1.0           ## секунд стоянки на зыбучем грунте — машину засосало полностью…
const MIRE_UNSTICK_S := 1.5         ## …и столько езды по нему, чтобы вырваться
const MIRE_STUCK_SPEED := 0.3       ## тайл/с: медленнее — машина стоит, её засасывает
const MIRE_STUCK_LOSS := 1.2        ## засосало: разгон слабее ещё на (1 − mire_accel_mult) × это


## Что произошло за шаг — для урона, звука и событий.
class StepResult:
	extends RefCounted
	var hit_wall := false
	var wall_damage := 0             ## удар в стенку на скорости (один раз за удар)
	var landed := false
	var fell_tiers := 0
	var fall_damage := 0
	var felled_tree := false
	var tree_damage := 0
	var hit_tree := false
	var drowned := false             ## в этом шаге машина утонула (гибель)


static func step(s: VehicleState, inp: Vector2, cls: VehicleClass, q: TerrainQuery, dt: float) -> StepResult:
	var r := StepResult.new()
	if s.drowning or s.falling:
		s.ext_accel = Vector2.ZERO
		s.push_vel = Vector2.ZERO
	if s.drowning:
		_drown_step(s, q, dt, r)
		return r
	if s.falling:
		_fall_step(s, cls, q, dt, r)
		return r

	var speed := s.vel.length()
	var tile_flags := q.flags(s.tile.x, s.tile.y)
	_update_mire_stuck(s, cls, tile_flags, speed, dt)
	var throttle := clampf(inp.length(), 0.0, 1.0)
	s.throttle = throttle if throttle > MIN_THROTTLE else 0.0
	var target_speed := 0.0
	if s.throttle > 0.0:
		var target_heading := inp.angle()
		var diff := wrapf(target_heading - s.heading, -PI, PI)
		# Засосало зыбучим грунтом — и поворачивает туго.
		var max_turn := deg_to_rad(cls.turn_rate_deg) * dt * (1.0 - 0.5 * s.mire_stuck * (1.0 - cls.mire_accel_mult))
		s.heading = wrapf(s.heading + clampf(diff, -max_turn, max_turn), -PI, PI)
		var remaining := absf(wrapf(target_heading - s.heading, -PI, PI))
		var align := maxf(cos(remaining), 0.0)
		if speed < STOP_SPEED and remaining > ALIGN_ANGLE:
			align = 0.0   # с места: сначала довернуть на месте, потом разгон
		elif cls.turn_in_place and remaining > TANK_TURN_ANGLE:
			align = 0.0
		target_speed = cls.max_speed * s.throttle * align
	_drive(s, cls, q, dt, r, target_speed, tile_flags, speed, false)
	return r


## Шаг при управлении «относительно машины» (меню настроек): drive −1…1 — вперёд / назад (задний ход — до
## REVERSE_FRAC Vmax), turn −1…1 — нос вправо / влево (на ходу и на месте, со скоростью поворота класса).
## Скорость — со знаком: против хода сначала тормозит до нуля, потом разгоняется в другую сторону.
static func step_relative(s: VehicleState, drive: float, turn: float, cls: VehicleClass, q: TerrainQuery,
		dt: float) -> StepResult:
	var r := StepResult.new()
	if s.drowning or s.falling:
		s.ext_accel = Vector2.ZERO
		s.push_vel = Vector2.ZERO
	if s.drowning:
		_drown_step(s, q, dt, r)
		return r
	if s.falling:
		_fall_step(s, cls, q, dt, r)
		return r
	var speed := s.vel.length() * (-1.0 if s.vel.dot(s.forward()) < 0.0 else 1.0)
	var tile_flags := q.flags(s.tile.x, s.tile.y)
	_update_mire_stuck(s, cls, tile_flags, absf(speed), dt)
	drive = clampf(drive, -1.0, 1.0)
	s.throttle = absf(drive) if absf(drive) > MIN_THROTTLE else 0.0
	var max_turn := deg_to_rad(cls.turn_rate_deg) * dt * (1.0 - 0.5 * s.mire_stuck * (1.0 - cls.mire_accel_mult))
	s.heading = wrapf(s.heading + clampf(turn, -1.0, 1.0) * max_turn, -PI, PI)
	var target_speed := 0.0
	if s.throttle > 0.0:
		target_speed = cls.max_speed * drive * (REVERSE_FRAC if drive < 0.0 else 1.0)
	_drive(s, cls, q, dt, r, target_speed, tile_flags, speed, true)
	return r


## Разгон и торможение к target_speed, предел скорости, перемещение по осям, деревья и препятствия, высота,
## вода. signed — скорость со знаком (задний ход), иначе — по модулю вдоль курса.
static func _drive(s: VehicleState, cls: VehicleClass, q: TerrainQuery, dt: float, r: StepResult,
		target_speed: float, tile_flags: int, speed: float, signed: bool) -> void:
	# Предел скорости: подъём подряд, вода, неровный и зыбучий грунт.
	var limit := cls.max_speed * maxf(cls.uphill_floor, 1.0 - cls.uphill_loss_per_tile * s.uphill_tiles)
	var wading := not cls.hovers and q.water_depth(s.pos.x, s.pos.y) > 0.05
	var ground := ground_speed_mult(cls, tile_flags)
	# Зыбучая кромка, частью под водой: действует сильнейшее из двух замедлений, а не оба сразу.
	limit *= minf(cls.water_speed_mult if wading else 1.0, ground)
	limit = minf(limit, s.speed_cap)
	target_speed = clampf(target_speed, -limit * REVERSE_FRAC, limit)

	var fwd := s.forward()
	var lateral := 0.0
	if cls.drift > 0.0:
		# Занос: вдоль курса — разгон и торможение как у всех, поперёк — скорость гаснет постепенно.
		var right := Vector2(-fwd.y, fwd.x)
		lateral = s.vel.dot(right) * exp(-lerpf(12.0, 1.5, cls.drift) * dt)
		speed = s.vel.dot(fwd) if signed else maxf(s.vel.dot(fwd), 0.0)
	if signed and (speed * target_speed < 0.0 or absf(speed) > absf(target_speed)):
		# Тормоз: против хода — до нуля (дальше — разгон в другую сторону), иначе — до нужной скорости.
		var decel := SURFACE_DRAG if (wading or ground < 1.0) and absf(speed) > limit else cls.brake_decel
		speed = move_toward(speed, 0.0 if speed * target_speed < 0.0 else target_speed, decel * dt)
	elif signed and target_speed < 0.0:
		speed = move_toward(speed, target_speed, cls.accel * mire_grip(cls, tile_flags, s.mire_stuck) * dt)
	elif speed < target_speed:
		var accel := cls.accel
		if cls.launch_accel > cls.accel:
			accel = lerpf(cls.launch_accel, cls.accel, clampf(speed / (LAUNCH_FADE * cls.max_speed), 0.0, 1.0))
		if _slope(cls, q, s.pos, fwd) < -0.05:
			accel *= 1.0 + cls.downhill_accel_bonus
		accel *= mire_grip(cls, tile_flags, s.mire_stuck)
		speed = minf(speed + accel * dt, target_speed)
	else:
		var decel := SURFACE_DRAG if (wading or ground < 1.0) and speed > limit else cls.brake_decel
		speed = maxf(speed - decel * dt, target_speed)
	s.vel = fwd * speed
	if lateral != 0.0:
		s.vel = (s.vel + Vector2(-fwd.y, fwd.x) * lateral).limit_length(cls.max_speed)

	s.push_vel = (s.push_vel + s.ext_accel * dt) * exp(-PUSH_DAMP * dt)
	s.ext_accel = Vector2.ZERO
	var delta := (s.vel + s.push_vel) * dt
	_move_axis(s, cls, q, 0, delta.x, r)
	if not s.falling:
		_move_axis(s, cls, q, 1, delta.y, r)
	if s.falling:
		return
	_keep_off_walls(s, cls, q)

	var t := Vector2i(floori(s.pos.x), floori(s.pos.y))
	if t != s.tile:
		s.tile = t
		var slope := _slope(cls, q, s.pos, fwd)
		s.uphill_tiles = s.uphill_tiles + 1 if slope > UPHILL_SLOPE else 0
	_collide_trees(s, cls, q, r)
	_collide_obstacles(s)
	var was_y := s.y
	s.y = ground_y(s, cls, q)
	if _too_deep(s, cls, q):
		# Тонет с той высоты, где был: съехал с мели под водой — с её дна, а не с поверхности.
		var w := q.water_tier(floori(s.pos.x), floori(s.pos.y))
		_start_drowning(s, minf(was_y, w * Grid.TIER_H - 0.1))


## Подброс по дуге к точке target (землетрясение, смерч): высота дуги apex над стартом,
## приземление — по правилам падения: урон по разнице высот старта и посадки, вода, деревья.
static func launch(s: VehicleState, target: Vector2, apex: float, cls: VehicleClass, q: TerrainQuery) -> void:
	s.fall_from_tier = q.surface_tier_float(s.pos.x, s.pos.y) if cls.hovers else q.surface_tier(s.pos.x, s.pos.y)
	var land := q.surface_tier_float(target.x, target.y) if cls.hovers else q.surface_tier(target.x, target.y)
	var top := s.y + apex
	var vy := sqrt(2.0 * GRAVITY * apex)
	var t := vy / GRAVITY + sqrt(2.0 * maxf(top - Grid.tier_to_y(land), 0.0) / GRAVITY)
	s.falling = true
	s.launched = true
	s.fall_vy = vy
	s.fall_tile = Grid.tile_of_world(target.x, target.y)
	s.vel = (target - s.pos) / maxf(t, 0.1)
	s.uphill_tiles = 0


## Скорость валки: с неё машина валит дерево — и таранит зверя (GDD §3.6, §5.4); порог — доля Vmax класса.
static func fells(cls: VehicleClass, speed: float) -> bool:
	return speed >= cls.tree_fell_speed_frac * cls.max_speed - 0.01


## После валки дерева (и тарана зверя) скорость не выше доли Vmax класса.
static func after_felling(s: VehicleState, cls: VehicleClass) -> void:
	s.vel = s.vel.limit_length(cls.tree_speed_after_frac * cls.max_speed)


## Предел скорости на грунте тайла: неровный или зыбучий — по данным класса (ховеру — 1).
static func ground_speed_mult(cls: VehicleClass, tile_flags: int) -> float:
	if (tile_flags & ChunkData.FLAG_MIRE) != 0:
		return cls.mire_speed_mult
	if (tile_flags & ChunkData.FLAG_ROUGH) != 0:
		return cls.rough_speed_mult
	return 1.0


## Множитель разгона на грунте тайла: зыбучий вязкий (mire_accel_mult класса), а засосало (stuck → 1) —
## разгон ещё слабее. Ровер, засосанный полностью, — 0,3 × 0,16 ≈ 0,05 от обычного.
static func mire_grip(cls: VehicleClass, tile_flags: int, stuck: float) -> float:
	if (tile_flags & ChunkData.FLAG_MIRE) == 0:
		return 1.0
	return cls.mire_accel_mult * maxf(1.0 - stuck * (1.0 - cls.mire_accel_mult) * MIRE_STUCK_LOSS, 0.0)


## Прилипание к зыбучему грунту: стоит — засасывает за MIRE_STICK_S, едет — вырывается за
## MIRE_UNSTICK_S; сошла с зыбучего — отпускает вдвое быстрее.
static func _update_mire_stuck(s: VehicleState, cls: VehicleClass, tile_flags: int, speed: float, dt: float) -> void:
	if (tile_flags & ChunkData.FLAG_MIRE) == 0 or cls.mire_accel_mult >= 1.0:
		s.mire_stuck = maxf(s.mire_stuck - 2.0 * dt / MIRE_UNSTICK_S, 0.0)
	elif speed < MIRE_STUCK_SPEED:
		s.mire_stuck = minf(s.mire_stuck + dt / MIRE_STICK_S, 1.0)
	else:
		s.mire_stuck = maxf(s.mire_stuck - dt / MIRE_UNSTICK_S, 0.0)


## Урон от падения со стенки высотой h ярусов (GDD §3.2).
static func fall_damage(cls: VehicleClass, h: int) -> int:
	if h < 2:
		return 0
	if cls.fall_damage_mode == "linear":
		return roundi(cls.fall_damage_base * (h - 1))
	return roundi(cls.fall_damage_base * pow(2.0, h - 2))


## Расход топлива, ед./с: холостой + (ходовой − холостой) × газ.
static func fuel_per_second(cls: VehicleClass, throttle: float) -> float:
	return (cls.fuel_idle_per_min + (cls.fuel_drive_per_min - cls.fuel_idle_per_min) * clampf(throttle, 0.0, 1.0)) / 60.0


## Наклон поверхности вдоль направления, ярусов на тайл (> 0 — подъём).
static func slope_along(q: TerrainQuery, pos: Vector2, dir: Vector2) -> float:
	var a := q.surface_tier(pos.x - dir.x * 0.4, pos.y - dir.y * 0.4)
	var b := q.surface_tier(pos.x + dir.x * 0.4, pos.y + dir.y * 0.4)
	return (b - a) / 0.8


## Наклон с учётом класса: машина на подушке считает склоны по зеркалу воды.
static func _slope(cls: VehicleClass, q: TerrainQuery, pos: Vector2, dir: Vector2) -> float:
	if not cls.hovers:
		return slope_along(q, pos, dir)
	var a := q.surface_tier_float(pos.x - dir.x * 0.4, pos.y - dir.y * 0.4)
	var b := q.surface_tier_float(pos.x + dir.x * 0.4, pos.y + dir.y * 0.4)
	return (b - a) / 0.8


## Подъём ребра в точке пересечения с учётом класса (машина на подушке — по зеркалу воды).
static func _rise_at(cls: VehicleClass, q: TerrainQuery, tile: Vector2i, dir: int, along: float) -> float:
	if cls.hovers:
		return q.edge_rise_float_at(tile.x, tile.y, dir, along)
	return q.edge_rise_at(tile.x, tile.y, dir, along)


## Мировая высота днища: поверхность; ховер — не ниже зеркала воды.
static func ground_y(s: VehicleState, cls: VehicleClass, q: TerrainQuery) -> float:
	var y := q.surface_y(s.pos.x, s.pos.y)
	if cls.hovers:
		var w := q.water_tier(floori(s.pos.x), floori(s.pos.y))
		if w != TerrainQuery.NO_WATER:
			y = maxf(y, w * Grid.TIER_H)
	return y


## Сдвиг по одной оси (0 — x, 1 — z) с проверкой рёбер тайлов.
static func _move_axis(s: VehicleState, cls: VehicleClass, q: TerrainQuery, axis: int, d: float, r: StepResult) -> void:
	if is_zero_approx(d):
		return
	var p := s.pos
	var cur := Vector2i(floori(p.x), floori(p.y))
	var np := p
	np[axis] += d
	var dir: int
	if axis == 0:
		dir = Grid.DIR_E if d > 0.0 else Grid.DIR_W
	else:
		dir = Grid.DIR_S if d > 0.0 else Grid.DIR_N
	var boundary: float = float(cur[axis] + 1) if d > 0.0 else float(cur[axis])

	# Стенка: проверяем ребро, когда передний край машины (центр ± радиус) заходит за границу тайла.
	var lead: float = np[axis] + (RADIUS if d > 0.0 else -RADIUS)
	var lead_crosses: bool = lead > boundary if d > 0.0 else lead < boundary
	# Точка ребра под машиной: для рёбер N/S — доля по x, для E/W — по z.
	var along: float = p[1 - axis] - cur[1 - axis]
	if lead_crosses and _blocked(cls, q, cur, dir, along):
		if absf(s.vel[axis]) >= cls.wall_hit_speed_frac * cls.max_speed - 1e-3:
			r.wall_damage = cls.wall_hit_damage
		# Подъезжаем вплотную; если машина уже ближе к стенке (после поворота), дальше не пускаем.
		if d > 0.0:
			np[axis] = minf(np[axis], maxf(p[axis], boundary - RADIUS))
		else:
			np[axis] = maxf(np[axis], minf(p[axis], boundary + RADIUS))
		if s.vel[axis] * d > 0.0:
			_slide_along_wall(s, axis)
		else:
			# В стенку прижимает только снос (смерч, ветер), сама машина туда не едет: гасим снос, а курс и скорость
			# не трогаем — иначе каждый кадр курс выравнивался вдоль стенки, и прижатая машина не могла развернуться.
			s.push_vel[axis] = 0.0
		r.hit_wall = true
		s.pos = np
		return

	# Центр перешёл в соседний тайл: обрыв вниз — падение (если у вершины нет «мостика» на диагональный тайл).
	var center_crosses: bool = np[axis] >= boundary if d > 0.0 else np[axis] < boundary
	if center_crosses:
		var drop := -_rise_at(cls, q, cur, dir, along)
		if drop > STEP_TOLERANCE and _bridge(s, cls, q, cur, axis, d, along, np):
			return
		if drop > STEP_TOLERANCE:
			s.fall_from_tier = q.surface_tier_float(p.x, p.y) if cls.hovers else q.surface_tier(p.x, p.y)
			s.falling = true
			s.fall_vy = 0.0
			s.fall_tile = cur + Grid.DIR_OFFSETS[dir]
			s.vel *= 0.5
	s.pos = np


## «Песочные часы»: два ската касаются одной вершиной, боковые тайлы ниже. Центр пересёк ребро с обрывом у самой
## вершины (ближе RADIUS), машина едет к этой вершине и по второй оси, а угол тайла по диагонали в ней вровень со
## своим: круг опоры лежит на обоих скатах. Машина проходит через вершину на диагональный тайл, а не
## соскальзывает в низкий боковой; сдвиг по второй оси — не больше RADIUS. true — прошла (s.pos уже за вершиной).
static func _bridge(s: VehicleState, cls: VehicleClass, q: TerrainQuery, cur: Vector2i, axis: int, d: float,
		along: float, np: Vector2) -> bool:
	var other := 1 - axis
	var side := -1 if along < 0.5 else 1                # к какой вершине ребра ближе центр
	var gap := along if side < 0 else 1.0 - along
	if gap >= RADIUS or (s.vel[other] + s.push_vel[other]) * side <= 0.0:
		return false
	var dv := Vector2i.ZERO
	dv[axis] = 1 if d > 0.0 else -1
	dv[other] = side
	if absf(_corner_rise(cls, q, cur, CORNER_DIRS.find(dv))) > STEP_TOLERANCE:
		return false
	np[other] = cur[other] + (1.0 + BRIDGE_EPS if side > 0 else -BRIDGE_EPS)
	s.pos = np
	return true


## Удар о стенку по оси axis: скорость теряется один раз по углу удара, курс выравнивается вдоль
## стенки. Без выравнивания машина каждый кадр снова упиралась бы носом и почти останавливалась.
static func _slide_along_wall(s: VehicleState, axis: int) -> void:
	s.push_vel[axis] = 0.0
	var tangent := s.forward()
	tangent[axis] = 0.0
	if tangent.length() < 0.1:
		s.vel = Vector2.ZERO          # удар в лоб — стоп
		return
	var speed := s.vel.length() * tangent.length()
	var back := s.vel.dot(s.forward()) < 0.0	  # задний ход: вдоль стенки — тоже задом
	tangent = tangent.normalized()
	s.heading = tangent.angle()
	s.vel = tangent * (-speed if back else speed)


## Круг опоры (RADIUS) не заходит на высокие соседние тайлы. Сбоку: ребро ближе RADIUS — стенка вверх
## (в точке против центра) — центр отодвигается на RADIUS от ребра. По диагонали: угол соседа по диагонали выше
## своего угла в общей вершине — центр отодвигается на RADIUS от вершины. По ходу движения то же раньше делает
## _move_axis (с ударом о стенку и скольжением); здесь — только положение: бок и угол корпуса не залезают в стену.
static func _keep_off_walls(s: VehicleState, cls: VehicleClass, q: TerrainQuery) -> void:
	var cur := Vector2i(floori(s.pos.x), floori(s.pos.y))
	var f := s.pos - Vector2(cur)
	if f.y < RADIUS and _blocked(cls, q, cur, Grid.DIR_N, f.x):
		s.pos.y = cur.y + RADIUS
	elif f.y > 1.0 - RADIUS and _blocked(cls, q, cur, Grid.DIR_S, f.x):
		s.pos.y = cur.y + 1.0 - RADIUS
	if f.x < RADIUS and _blocked(cls, q, cur, Grid.DIR_W, f.y):
		s.pos.x = cur.x + RADIUS
	elif f.x > 1.0 - RADIUS and _blocked(cls, q, cur, Grid.DIR_E, f.y):
		s.pos.x = cur.x + 1.0 - RADIUS
	for k in 4:                                       # углы тайла: 0 — СЗ, 1 — СВ, 2 — ЮВ, 3 — ЮЗ
		var d: Vector2i = CORNER_DIRS[k]
		var vertex := Vector2(cur.x + maxi(d.x, 0), cur.y + maxi(d.y, 0))
		var off := s.pos - vertex
		if off.length_squared() >= RADIUS * RADIUS or not _corner_blocked(cls, q, cur, k):
			continue
		var away := off.normalized() if off.length_squared() > 1e-8 else -Vector2(d).normalized()
		s.pos = vertex + away * RADIUS


## Угол k тайла (Grid: 0 — СЗ … 3 — ЮЗ): сосед по диагонали в общей вершине выше своего угла больше чем на
## STEP_TOLERANCE (не загружен — тоже стена).
static func _corner_blocked(cls: VehicleClass, q: TerrainQuery, tile: Vector2i, k: int) -> bool:
	return _corner_rise(cls, q, tile, k) > STEP_TOLERANCE


## Перепад в вершине угла k тайла: угол соседа по диагонали минус свой, ярусов (сосед не загружен — INF).
## Машина на подушке — над водой опорой служит её зеркало.
static func _corner_rise(cls: VehicleClass, q: TerrainQuery, tile: Vector2i, k: int) -> float:
	var diag: Vector2i = tile + CORNER_DIRS[k]
	if not q.is_loaded(diag.x, diag.y):
		return INF
	var own := float(q.corner(tile.x, tile.y, k))
	var other := float(q.corner(diag.x, diag.y, (k + 2) % 4))
	if cls.hovers:
		var ow := q.water_tier(tile.x, tile.y)
		var dw := q.water_tier(diag.x, diag.y)
		if ow != TerrainQuery.NO_WATER:
			own = maxf(own, ow)
		if dw != TerrainQuery.NO_WATER:
			other = maxf(other, dw)
	return other - own


static func _blocked(cls: VehicleClass, q: TerrainQuery, tile: Vector2i, dir: int, along: float) -> bool:
	return _rise_at(cls, q, tile, dir, along) > STEP_TOLERANCE


## Вода в точке машины глубже допустимой для класса (ховер не тонет).
static func _too_deep(s: VehicleState, cls: VehicleClass, q: TerrainQuery) -> bool:
	if cls.max_water_depth < 0:
		return false
	return q.water_depth(s.pos.x, s.pos.y) > cls.max_water_depth + DEEP_MARGIN


## Разбитая на воде машина (ховер над водой — тоже) идёт ко дну, как тонущая, но без новой гибели: забег
## уже кончен.
static func sink_wreck(s: VehicleState) -> void:
	_start_drowning(s, s.y)
	s.drowned = true


static func _start_drowning(s: VehicleState, start_y: float) -> void:
	s.drowning = true
	s.drown_time = 0.0
	s.y = start_y
	s.vel *= 0.3


## Тонет: дрейф по инерции в пределах тайла, погружение до дна, через DROWN_TIME — гибель.
static func _drown_step(s: VehicleState, q: TerrainQuery, dt: float, r: StepResult) -> void:
	s.throttle = 0.0
	s.drown_time += dt
	s.vel = s.vel.move_toward(Vector2.ZERO, 4.0 * dt)
	var p := s.pos + s.vel * dt
	s.pos = Vector2(clampf(p.x, s.tile.x + 0.05, s.tile.x + 0.95), clampf(p.y, s.tile.y + 0.05, s.tile.y + 0.95))
	s.y = maxf(s.y - SINK_SPEED * dt, q.surface_y(s.pos.x, s.pos.y))
	if s.drown_time >= DROWN_TIME and not s.drowned:
		s.drowned = true
		r.drowned = true


static func _fall_step(s: VehicleState, cls: VehicleClass, q: TerrainQuery, dt: float, r: StepResult) -> void:
	s.fall_vy -= GRAVITY * dt
	s.y += s.fall_vy * dt
	var p := s.pos + s.vel * dt
	if s.launched:
		# Подброс: летит по дуге, садится там, где встретит поверхность.
		s.fall_tile = Grid.tile_of_world(p.x, p.y)
		if not q.is_loaded(s.fall_tile.x, s.fall_tile.y):
			p = s.pos
			s.fall_tile = Grid.tile_of_world(p.x, p.y)
	else:
		# Падение строго в соседний тайл: по горизонтали машина остаётся в его пределах.
		p.x = clampf(p.x, s.fall_tile.x + 0.05, s.fall_tile.x + 0.95)
		p.y = clampf(p.y, s.fall_tile.y + 0.05, s.fall_tile.y + 0.95)
	s.pos = p
	var ground := ground_y(s, cls, q)
	# Падение в глубокую воду: удар смягчает вода, но машина тонет — с той высоты, где она сейчас
	# (с уступа под водой — от него, а не с поверхности).
	if cls.max_water_depth >= 0:
		var w := q.water_tier(s.fall_tile.x, s.fall_tile.y)
		if w != TerrainQuery.NO_WATER and s.y <= w * Grid.TIER_H \
				and w - ground / Grid.TIER_H > cls.max_water_depth + DEEP_MARGIN:
			s.falling = false
			s.launched = false
			s.tile = s.fall_tile
			r.landed = true
			_start_drowning(s, minf(s.y, w * Grid.TIER_H - 0.1))
			return
	if s.y > ground:
		return
	s.y = ground
	s.falling = false
	if s.launched:
		s.launched = false
		s.vel *= 0.3
	s.tile = s.fall_tile
	s.uphill_tiles = 0
	r.landed = true
	r.fell_tiers = roundi(s.fall_from_tier - ground / Grid.TIER_H)
	var on_water := cls.hovers and q.water_tier(s.tile.x, s.tile.y) != TerrainQuery.NO_WATER
	r.fall_damage = 0 if on_water else fall_damage(cls, r.fell_tiers)
	if q.has_standing_tree(s.tile.x, s.tile.y):
		q.fell_tree(s.tile.x, s.tile.y)   # упавшая машина валит дерево без урона
		r.felled_tree = true


## Корпуса челноков: выталкиваем из круга и гасим скорость в его сторону.
static func _collide_obstacles(s: VehicleState) -> void:
	for o in s.obstacles:
		var c := Vector2(o.x, o.y)
		var min_d := o.z + RADIUS
		var delta := s.pos - c
		var dist := delta.length()
		if dist >= min_d:
			continue
		var n := delta / dist if dist > 0.001 else -s.forward()
		s.pos = c + n * min_d
		var vn := s.vel.dot(n)
		if vn < 0.0:
			s.vel -= n * vn


static func _collide_trees(s: VehicleState, cls: VehicleClass, q: TerrainQuery, r: StepResult) -> void:
	var min_d := RADIUS + TREE_RADIUS
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var t := s.tile + Vector2i(dx, dz)
			if not q.has_standing_tree(t.x, t.y):
				continue
			var tp := q.tree_position(t.x, t.y)
			var delta := s.pos - tp
			var dist := delta.length()
			if dist >= min_d:
				continue
			if fells(cls, s.vel.length()):
				q.fell_tree(t.x, t.y)
				after_felling(s, cls)
				r.felled_tree = true
				r.tree_damage += cls.tree_fell_damage
			else:
				# Упор: выталкиваем из дерева и гасим скорость в его сторону.
				var n := delta / dist if dist > 0.001 else -s.forward()
				s.pos = tp + n * min_d
				var vn := s.vel.dot(n)
				if vn < 0.0:
					s.vel -= n * vn
				r.hit_tree = true
