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
## - Деревья валятся на скорости от порога класса, иначе машина упирается.
## - Машина на подушке (ховер) держится на зеркале воды: рёбра и склоны для неё считаются по
##   высоте «не ниже воды»; её заносит — боковая скорость гаснет не сразу (cls.drift).

const GRAVITY := 20.0            ## мировых единиц/с²
const RADIUS := 0.3              ## радиус машины для стенок и деревьев, тайлов
const TREE_RADIUS := 0.35        ## радиус столкновения дерева, тайлов
const MIN_THROTTLE := 0.05
const UPHILL_SLOPE := 0.25       ## ярусов на тайл: склон считается подъёмом
const TANK_TURN_ANGLE := PI / 4.0
const STOP_SPEED := 1.0             ## тайл/с: медленнее — машина считается стоящей и разворачивается на месте
const ALIGN_ANGLE := deg_to_rad(12.0)   ## с места трогается, когда довернула до такого угла
const STEP_TOLERANCE := 1.0 / 3.0   ## ярусов: такую ступеньку в точке пересечения машина берёт с ходу
const DROWN_TIME := 2.0             ## секунд от погружения до гибели
const SINK_SPEED := 0.35            ## мировых единиц/с — скорость погружения
const DEEP_MARGIN := 0.1            ## ярусов сверх допустимой глубины — уже тонет


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
	if s.drowning:
		_drown_step(s, q, dt, r)
		return r
	if s.falling:
		_fall_step(s, cls, q, dt, r)
		return r

	var speed := s.vel.length()
	var throttle := clampf(inp.length(), 0.0, 1.0)
	s.throttle = throttle if throttle > MIN_THROTTLE else 0.0
	var target_speed := 0.0
	if s.throttle > 0.0:
		var target_heading := inp.angle()
		var diff := wrapf(target_heading - s.heading, -PI, PI)
		var max_turn := deg_to_rad(cls.turn_rate_deg) * dt
		s.heading = wrapf(s.heading + clampf(diff, -max_turn, max_turn), -PI, PI)
		var remaining := absf(wrapf(target_heading - s.heading, -PI, PI))
		var align := maxf(cos(remaining), 0.0)
		if speed < STOP_SPEED and remaining > ALIGN_ANGLE:
			align = 0.0   # с места: сначала довернуть на месте, потом разгон
		elif cls.turn_in_place and remaining > TANK_TURN_ANGLE:
			align = 0.0
		target_speed = cls.max_speed * s.throttle * align

	# Предел скорости: подъём подряд и вода.
	var limit := cls.max_speed * maxf(cls.uphill_floor, 1.0 - cls.uphill_loss_per_tile * s.uphill_tiles)
	if not cls.hovers and q.water_depth(s.pos.x, s.pos.y) > 0.05:
		limit *= cls.water_speed_mult
	target_speed = minf(target_speed, limit)

	var fwd := s.forward()
	var lateral := 0.0
	if cls.drift > 0.0:
		# Занос: вдоль курса — разгон и торможение как у всех, поперёк — скорость гаснет постепенно.
		var right := Vector2(-fwd.y, fwd.x)
		lateral = s.vel.dot(right) * exp(-lerpf(12.0, 1.5, cls.drift) * dt)
		speed = maxf(s.vel.dot(fwd), 0.0)
	if speed < target_speed:
		var accel := cls.accel
		if _slope(cls, q, s.pos, fwd) < -0.05:
			accel *= 1.0 + cls.downhill_accel_bonus
		speed = minf(speed + accel * dt, target_speed)
	else:
		speed = maxf(speed - cls.brake_decel * dt, target_speed)
	s.vel = fwd * speed
	if lateral != 0.0:
		s.vel = (s.vel + Vector2(-fwd.y, fwd.x) * lateral).limit_length(cls.max_speed)

	var delta := s.vel * dt
	_move_axis(s, cls, q, 0, delta.x, r)
	if not s.falling:
		_move_axis(s, cls, q, 1, delta.y, r)
	if s.falling:
		return r

	var t := Vector2i(floori(s.pos.x), floori(s.pos.y))
	if t != s.tile:
		s.tile = t
		var slope := _slope(cls, q, s.pos, fwd)
		s.uphill_tiles = s.uphill_tiles + 1 if slope > UPHILL_SLOPE else 0
	_collide_trees(s, cls, q, r)
	s.y = ground_y(s, cls, q)
	if _too_deep(s, cls, q):
		var w := q.water_tier(floori(s.pos.x), floori(s.pos.y))
		_start_drowning(s, w * Grid.TIER_H - 0.1)
	return r


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
		_slide_along_wall(s, axis)
		r.hit_wall = true
		s.pos = np
		return

	# Центр перешёл в соседний тайл: обрыв вниз — падение.
	var center_crosses: bool = np[axis] >= boundary if d > 0.0 else np[axis] < boundary
	if center_crosses:
		var drop := -_rise_at(cls, q, cur, dir, along)
		if drop > STEP_TOLERANCE:
			s.fall_from_tier = q.surface_tier_float(p.x, p.y) if cls.hovers else q.surface_tier(p.x, p.y)
			s.falling = true
			s.fall_vy = 0.0
			s.fall_tile = cur + Grid.DIR_OFFSETS[dir]
			s.vel *= 0.5
	s.pos = np


## Удар о стенку по оси axis: скорость теряется один раз по углу удара, курс выравнивается вдоль
## стенки. Без выравнивания машина каждый кадр снова упиралась бы носом и почти останавливалась.
static func _slide_along_wall(s: VehicleState, axis: int) -> void:
	var tangent := s.forward()
	tangent[axis] = 0.0
	if tangent.length() < 0.1:
		s.vel = Vector2.ZERO          # удар в лоб — стоп
		return
	var speed := s.vel.length() * tangent.length()
	tangent = tangent.normalized()
	s.heading = tangent.angle()
	s.vel = tangent * speed


static func _blocked(cls: VehicleClass, q: TerrainQuery, tile: Vector2i, dir: int, along: float) -> bool:
	return _rise_at(cls, q, tile, dir, along) > STEP_TOLERANCE


## Вода в точке машины глубже допустимой для класса (ховер не тонет).
static func _too_deep(s: VehicleState, cls: VehicleClass, q: TerrainQuery) -> bool:
	if cls.max_water_depth < 0:
		return false
	return q.water_depth(s.pos.x, s.pos.y) > cls.max_water_depth + DEEP_MARGIN


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
	# Падение строго в соседний тайл: по горизонтали машина остаётся в его пределах.
	var p := s.pos + s.vel * dt
	p.x = clampf(p.x, s.fall_tile.x + 0.05, s.fall_tile.x + 0.95)
	p.y = clampf(p.y, s.fall_tile.y + 0.05, s.fall_tile.y + 0.95)
	s.pos = p
	var ground := ground_y(s, cls, q)
	# Падение в глубокую воду: удар смягчает вода, но машина тонет.
	if cls.max_water_depth >= 0:
		var w := q.water_tier(s.fall_tile.x, s.fall_tile.y)
		if w != TerrainQuery.NO_WATER and s.y <= w * Grid.TIER_H \
				and w - ground / Grid.TIER_H > cls.max_water_depth + DEEP_MARGIN:
			s.falling = false
			s.tile = s.fall_tile
			r.landed = true
			_start_drowning(s, w * Grid.TIER_H - 0.1)
			return
	if s.y > ground:
		return
	s.y = ground
	s.falling = false
	s.tile = s.fall_tile
	s.uphill_tiles = 0
	r.landed = true
	r.fell_tiers = roundi(s.fall_from_tier - ground / Grid.TIER_H)
	var on_water := cls.hovers and q.water_tier(s.tile.x, s.tile.y) != TerrainQuery.NO_WATER
	r.fall_damage = 0 if on_water else fall_damage(cls, r.fell_tiers)
	if q.has_standing_tree(s.tile.x, s.tile.y):
		q.fell_tree(s.tile.x, s.tile.y)   # упавшая машина валит дерево без урона
		r.felled_tree = true


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
			var speed := s.vel.length()
			if speed >= cls.tree_fell_speed_frac * cls.max_speed - 0.01:
				q.fell_tree(t.x, t.y)
				s.vel = s.vel.limit_length(cls.tree_speed_after_frac * cls.max_speed)
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
