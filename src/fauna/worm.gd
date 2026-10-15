class_name Worm
extends Creature
## Песчаный червь (GDD §5.4) — как в «Дюне». Живёт под рыхлым грунтом — песок (SAND) и грунт (GROUND)
## в любом биоме, не под камнем, кристаллической породой и водой — и только там ходит (habitat);
## под землёй уступы ему не помеха. Появляется только в песке (spawn_ground), гонится и по грунту.
## Слышит едущую машину дальше прочей фауны — как в «Дюне» на шаги: в радиусе worm_hear_r × шум (стоящую — нет,
## крадущуюся — только вблизи). Пока не слышит — ждёт на месте (не подкрадывается: иначе сидел бы под стоящей
## машиной и бросался, едва она тронется); не услышал за worm_wait_s — уходит в глубину.
## Слышит машину на своём грунте — идёт к ней под землёй: грунт над ним вспучивается валом (деформация рельефа,
## «обратная» борозде смерча, не выше яруса) и оседает обратно в RIDGE_KEEP тайлах позади; летит пыль,
## гудит. Деревья на пути валятся.
## Бросок — не раньше, чем вал шёл HUNT_MIN_S (до того червь держится в HOLD_OFF от машины): даже начав погоню
## рядом (после укуса, машина наехала на него), он сначала виден и слышен. Догнал — за worm_telegraph_s до
## броска песок вокруг машины трескается кольцом и дрожит. Бросок:
## огромный червь вырывается прямо под машиной — не строго вверх, а качаясь, как смерч, — с раскрытой
## пастью: три вытянутые челюсти с зазубренными краями (low-poly из треугольников), внутри кольцо зубов
## и глотка; челюсти захлопываются над машиной (урон worm_damage) и выплёвывают её на worm_toss тайла —
## в полёте машина наклонена в сторону броска; червь вздымается и уходит обратно, оставив яму.
## Сомкнутые челюсти — заострённая морда. Тело — «позвонки»: крупные 8-гранные и узкие 7-гранные
## диски вперемешку, каждый повёрнут вокруг оси на свой угол.
## Услышав машину, червь знает, где она, и погоню не бросает (потери интереса нет). Спасение — уйти с его грунта
## (камень, кристалл, вода) и переждать LOSE_S — тогда он уходит в глубину; или гнать и уворачиваться от бросков.
## Упёрся по прямой в камень — скользит вдоль; не сдвинуться совсем — тоже теряет след за LOSE_S.

enum State { IDLE, HUNT, TELEGRAPH, STRIKE, COOLDOWN }

const BODY_COLOR := Color(0.7, 0.6, 0.52)
const RING_COLOR := Color(0.47, 0.39, 0.34)
const THROAT_COLOR := Color(0.16, 0.06, 0.07)
const TOOTH_COLOR := Color(0.95, 0.92, 0.82)
const CRACK_COLOR := Color(0.18, 0.1, 0.12)

const R := 1.05                          ## радиус тела и пасти — машина помещается в пасть
const STRIKE_S := 2.4
const RISE_S := 0.35                     ## вырывается с раскрытой пастью
const BITE_S := 0.55                     ## челюсти захлопнулись
const HOLD_S := 1.6                      ## держится над песком, потом уходит
const TOP_Y := 3.6                       ## насколько вздымается голова над песком
const COOLDOWN_S := 4.0
const LOSE_S := 15.0                     ## машина вне его грунта (или к ней не сдвинуться) столько — уходит
const STRIKE_R := 1.6
const JAW_OPEN := -1.55                  ## лепесток откинут наружу почти плашмя
const DISCS := 18                        ## тело — диски-«позвонки», крупные и узкие вперемешку
const DISC_STEP := 0.31
const BODY_LEN := DISCS * DISC_STEP      ## от хвоста до основания головы
const JAW_LEN := 2.1                     ## длина челюсти: сомкнутые дают вытянутую заострённую морду
const TOSS_TILT := 0.55                  ## рад — наклон машины в полёте после броска
const LEAN := 0.12                       ## рад — бросок не строго вверх
const RIDGE_EVERY_S := 0.25
const HUNT_MIN_S := 1.5                  ## вал, пыль и гул идут хотя бы столько перед броском
const HOLD_OFF := 2.0                    ## пока HUNT_MIN_S не прошло, ближе к машине не подходит
const HUM_DB := -14.0                    ## гул под песком — заметно тише гула землетрясения (−2 дБ)
const HUM_HEAR_TILES := 14.0             ## дальше — не слышно (как остальную фауну)
const HUM_FADE_S := 0.4                  ## гул нарастает и стихает за столько
const RIDGE_HALF_W := 0.7
const RIDGE_KEEP := 3.5                  ## дальше позади вал оседает

var state := State.IDLE

var _timer := 0.0
var _lost := 0.0
var _hunt_t := 0.0                       ## сколько идёт погоня (вал виден)
var _wait := 0.0                         ## сколько ждёт, не слыша машину
var _strike_at := Vector2.ZERO
var _ground := 0.0
var _bitten := false
var _time := 0.0
var _heading := Vector2.RIGHT
var _wake: CPUParticles3D                ## пыль над валом (PixelFx.dust — как у всех)…
var _wake_clods: CPUParticles3D          ## …и комья
var _ridge_from := Vector2.ZERO
var _ridge_timer := 0.0
var _raised: Dictionary = {}             ## поднятые углы: Vector3i(tx, tz, угол) → исходный ярус
var _hum: AudioStreamPlayer               ## гул под песком (петля Sfx ground_hum)
var _hum_level := 0.0
var _ring: Node3D
var _ring_mat: StandardMaterial3D
var _burst: CPUParticles3D               ## бросок: комья…
var _burst_dust: CPUParticles3D          ## …и пыль
var _body: Node3D
var _jaws: Array[Node3D] = []
var _lean := Vector2.ZERO                ## наклон тела в этом броске (тангаж, крен)


func _init() -> void:
	name = "Worm"


func setup(at: Vector2) -> void:
	pos = at
	_build()
	_ring.visible = false
	_body.visible = false


## Слышит ли машину в p: едущую — в радиусе worm_hear_r × шум (0…1 по скорости), стоящую — нет.
func hears(p: Vector2) -> bool:
	return pos.distance_to(p) <= noise.vehicle_level * rules.worm_hear_r


func on_sand(p: Vector2) -> bool:
	return habitat(query, Grid.tile_of_world(p.x, p.y))


## Где червь может появиться: только в сухом песке.
static func spawn_ground(q: TerrainQuery, t: Vector2i) -> bool:
	return habitat(q, t) and q.material(t.x, t.y) == ChunkData.Mat.SAND


## Грунт червя: сухой песок или грунт (любой биом).
static func habitat(q: TerrainQuery, t: Vector2i) -> bool:
	if not q.is_loaded(t.x, t.y) or q.water_tier(t.x, t.y) != TerrainQuery.NO_WATER:
		return false
	var m := q.material(t.x, t.y)
	return m == ChunkData.Mat.SAND or m == ChunkData.Mat.GROUND


func step(dt: float) -> void:
	_time += dt
	var vp := vehicle.state.pos
	match state:
		State.IDLE:
			if on_sand(vp) and hears(vp):
				start_hunt()
			else:
				_wait += dt
				if _wait > rules.worm_wait_s:
					_leave()
		State.HUNT:
			_hunt_t += dt
			var stuck := not on_sand(vp)
			if not stuck:
				var delta := vp - pos
				if delta.length() > 0.01:
					_heading = delta.normalized()
				var keep := HOLD_OFF if _hunt_t < HUNT_MIN_S else 0.0
				stuck = not _advance(delta.limit_length(minf(rules.worm_speed * dt, maxf(delta.length() - keep, 0.0))))
				_ridge_timer -= dt
				if _ridge_timer <= 0.0:
					_ridge_timer = RIDGE_EVERY_S
					_raise_ridge()
			_lost = _lost + dt if stuck else 0.0
			if _lost > LOSE_S:
				_leave()
			elif pos.distance_to(vp) < 1.0 and on_sand(vp) and _hunt_t >= HUNT_MIN_S:
				state = State.TELEGRAPH
				_timer = rules.worm_telegraph_s
				_strike_at = vp
				_ground = ground_y(_strike_at)
				_ring.visible = true
				_ring.position = Vector3(_strike_at.x, _ground + 0.04, _strike_at.y)
		State.TELEGRAPH:
			_timer -= dt
			var k := 1.0 - _timer / rules.worm_telegraph_s
			_place_cracks(lerpf(0.5, 1.0, k))
			_ring.rotation.y = sin(_time * 30.0) * 0.03 * k            # песок дрожит
			_ring_mat.albedo_color.a = 0.3 + 0.6 * minf(floorf(k * 4.0), 3.0) / 3.0   # ярче ступенями
			if fmod(_time, 0.2) < dt:
				EventBus.camera_shake_requested.emit(0.15 + 0.4 * k, 0.25)
			if _timer <= 0.0:
				_strike()
		State.STRIKE:
			_timer += dt
			_animate_strike(_timer)
			if not _bitten and _timer >= BITE_S:
				_bitten = true
				_bite()
			if _timer >= STRIKE_S:
				_body.visible = false
				state = State.COOLDOWN
				_timer = COOLDOWN_S
		State.COOLDOWN:
			_timer -= dt
			_lost = _lost + dt if not on_sand(vp) else 0.0
			if _lost > LOSE_S:
				_leave()
			elif _timer <= 0.0:
				state = State.HUNT                   # знает, где машина, — снова в погоню (бросок — после HUNT_MIN_S)
				_hunt_t = 0.0
				_ridge_from = pos
	var underground := state == State.HUNT or state == State.TELEGRAPH
	_update_hum(dt, underground)
	if not underground:
		_settle(-1.0)            # ушёл в глубину — вал оседает целиком
	_wake.emitting = underground
	_wake_clods.emitting = underground
	if underground:
		_tint_dust()
		_wake.position = Vector3(pos.x, ground_y(pos) + 0.1, pos.y)
		_wake.rotation.y = atan2(-_heading.x, -_heading.y)
		_wake_clods.transform = _wake.transform


## Шаг погони по своему грунту: прямо, а упёрся (камень, вода) — вдоль препятствия по одной из осей.
## false — не сдвинуться никуда (нулевой шаг — не упёрся: червь сам держит дистанцию).
func _advance(move: Vector2) -> bool:
	if move.length_squared() < 1e-8:
		return true
	for m: Vector2 in [move, Vector2(move.x, 0.0), Vector2(0.0, move.y)]:
		if m.length_squared() > 1e-8 and on_sand(pos + m):
			pos += m
			return true
	return false


## Гул под песком: ровная петля, пока червь идёт под землёй (охота, телеграф), — тише гула землетрясения,
## громкость по расстоянию до машины; бросок и уход — стихает за HUM_FADE_S.
func _update_hum(dt: float, underground: bool) -> void:
	_hum_level = move_toward(_hum_level, 1.0 if underground else 0.0, dt / HUM_FADE_S)
	if _hum_level <= 0.0:
		if _hum.playing:
			_hum.stop()
		return
	if not _hum.playing:
		_hum.stream = Sfx.named(&"ground_hum")
		_hum.play()
	var near := clampf(1.0 - vehicle.state.pos.distance_to(pos) / HUM_HEAR_TILES, 0.0, 1.0)
	_hum.volume_db = linear_to_db(maxf(_hum_level * near, 0.001)) + HUM_DB


## Вал за червём: песок поднимается на ярус вдоль пройденного отрезка, деревья рядом валятся.
func _raise_ridge() -> void:
	if _ridge_from.distance_to(pos) > 0.3:
		Deformation.raise_vertices(terrain, Deformation.vertices_near_segment(_ridge_from, pos, RIDGE_HALF_W), _raised)
		_ridge_from = pos
	_settle(RIDGE_KEEP)
	_fell_trees(pos, 1.2)


## Вал позади оседает: углы дальше keep от червя возвращаются к исходной высоте (keep < 0 — все).
func _settle(keep: float) -> void:
	if _raised.is_empty():
		return
	var verts: Array[Vector2i] = []
	var seen := {}
	for key: Vector3i in _raised:
		var v := Deformation.recorded_vertex(key)
		if not seen.has(v) and (keep < 0.0 or Vector2(v).distance_to(pos) > keep):
			seen[v] = true
			verts.append(v)
	if not verts.is_empty():
		Deformation.restore_vertices(terrain, verts, _raised)


func _exit_tree() -> void:
	_settle(-1.0)


func _fell_trees(at: Vector2, radius: float) -> void:
	var c := Grid.tile_of_world(at.x, at.y)
	var r := ceili(radius)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var t := c + Vector2i(dx, dz)
			if query.has_standing_tree(t.x, t.y) and query.tree_position(t.x, t.y).distance_to(at) < radius:
				query.fell_tree(t.x, t.y)


## Начать охоту (услышал машину или отладка): гул и вал по песку.
func start_hunt() -> void:
	state = State.HUNT
	aggressive = true
	_lost = 0.0
	_hunt_t = 0.0
	reset_interest()
	_ridge_from = pos
	EventBus.fauna_alerted.emit(&"worm", Vector3(pos.x, ground_y(pos), pos.y))


## Потерял интерес: уходит в глубину — вал оседает, червя больше нет.
func _leave() -> void:
	state = State.IDLE
	aggressive = false
	finished = true


func _strike() -> void:
	state = State.STRIKE
	_timer = 0.0
	_bitten = false
	_ring.visible = false
	_body.visible = true
	_lean = Vector2.from_angle(rng.randf() * TAU) * LEAN
	_pose(-4.0, 0.0)
	for p: CPUParticles3D in [_burst, _burst_dust]:
		p.position = Vector3(_strike_at.x, _ground + 0.1, _strike_at.y)
		p.restart()
		p.emitting = true
	EventBus.camera_shake_requested.emit(1.2, 0.8)
	_fell_trees(_strike_at, R + 0.8)
	EventBus.fauna_alerted.emit(&"worm_strike", Vector3(_strike_at.x, _ground, _strike_at.y))


## Бросок: вырывается с раскрытой пастью, захлопывает её, вздымается, качается и уходит в песок.
func _animate_strike(t: float) -> void:
	var head_y: float          # высота основания головы над песком
	var jaw: float
	if t < RISE_S:
		head_y = lerpf(-4.0, 0.3, _ease_out(t / RISE_S))
		jaw = JAW_OPEN
	elif t < BITE_S:
		var k := (t - RISE_S) / (BITE_S - RISE_S)
		head_y = lerpf(0.3, 1.4, k)
		jaw = lerpf(JAW_OPEN, 0.0, k * k)
	elif t < HOLD_S:
		var k := (t - BITE_S) / (HOLD_S - BITE_S)
		head_y = lerpf(1.4, TOP_Y, _ease_out(minf(k * 1.6, 1.0)))
		jaw = 0.0
	else:
		var k := (t - HOLD_S) / (STRIKE_S - HOLD_S)
		head_y = lerpf(TOP_Y, -6.0, k * k)
		jaw = 0.0
	_pose(head_y, t)
	for hinge in _jaws:
		hinge.rotation.z = jaw


## Челюсти захлопнулись: если машина ещё в пасти — урон, червь выплёвывает её; в песке остаётся яма.
func _bite() -> void:
	EventBus.camera_shake_requested.emit(0.9, 0.4)
	Deformation.crater(terrain, _strike_at, 2.2, 1)
	var s := vehicle.state
	var d := s.pos.distance_to(_strike_at)
	if d > STRIKE_R or s.falling or s.drowning:
		return
	damaged.emit(rules.worm_damage, &"worm")
	var dir := (s.pos - _strike_at).normalized() if d > 0.05 else Vector2.from_angle(rng.randf() * TAU)
	var target := _strike_at + dir * rules.worm_toss
	var t := Grid.tile_of_world(target.x, target.y)
	if query.is_loaded(t.x, t.y):
		VehicleKinematics.launch(s, target, 2.4, vehicle.cls, query)
		vehicle.tumble(dir, TOSS_TILT)
	else:
		vehicle.rock(Vehicle.ROCK_RAM, dir)


## Поза тела: голова (основание челюстей) на высоте head_y над грунтом в точке броска; тело качается
## вокруг неё, как смерч, — наклон броска плюс раскачка, лёгкое кручение и дрожь головы.
func _pose(head_y: float, t: float) -> void:
	var sway := 0.06 + 0.1 * clampf(t / RISE_S, 0.0, 1.0)
	var rx := _lean.x + sin(_time * 2.3 + 0.7) * sway
	var rz := _lean.y + sin(_time * 1.7) * sway * 1.2
	var basis := Basis.from_euler(Vector3(rx, t * 0.5, rz))
	var head := Vector3(_strike_at.x + sin(_time * 3.1) * 0.1, _ground + head_y, _strike_at.y + cos(_time * 2.7) * 0.1)
	_body.basis = basis
	_body.position = head - basis * Vector3(0, BODY_LEN, 0)


static func _ease_out(k: float) -> float:
	return 1.0 - pow(1.0 - clampf(k, 0.0, 1.0), 3.0)


func _build() -> void:
	_hum = AudioStreamPlayer.new()
	_hum.volume_db = -80.0
	add_child(_hum)
	_wake = _ground_fx(PixelFx.dust(40, 1.2), 60.0, 0.8, 2.0)
	_wake_clods = _ground_fx(PixelFx.clods(30, 0.8), 45.0, 1.5, 3.0)
	for p: CPUParticles3D in [_wake, _wake_clods]:
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(0.8, 0.05, 1.4)
	_build_ring()
	_build_body()
	_burst = _ground_fx(PixelFx.clods(60, 1.2), 30.0, 4.0, 9.0)
	_burst_dust = _ground_fx(PixelFx.dust(40, 1.4), 50.0, 1.5, 3.5)
	for p: CPUParticles3D in [_burst, _burst_dust]:
		p.one_shot = true
		p.explosiveness = 0.8
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		p.emission_ring_axis = Vector3.UP
		p.emission_ring_radius = R + 0.3
		p.emission_ring_inner_radius = R * 0.6
		p.emission_ring_height = 0.1
		p.emitting = false


## Кольцо трещин вокруг точки броска.
func _build_ring() -> void:
	_ring = Node3D.new()
	add_child(_ring)
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.albedo_color = CRACK_COLOR
	for i in 12:
		var crack := MeshInstance3D.new()
		var cb := BoxMesh.new()
		cb.size = Vector3(Grid.ART_PX, 0.02, Grid.ART_PX * 14.0)     # трещина — пиксель мира шириной
		crack.mesh = cb
		crack.material_override = _ring_mat
		crack.rotation.y = -TAU * i / 12.0 + PI * 0.5
		_ring.add_child(crack)
	_place_cracks(1.0)


## Кольцо трещин расходится (k — доля полного радиуса): трещины разъезжаются от центра целыми пикселями мира,
## сами не масштабируются — ширина остаётся пикселем.
func _place_cracks(k: float) -> void:
	var r := snappedf(k * (R + 0.2), Grid.ART_PX)
	for i in _ring.get_child_count():
		var a := TAU * i / 12.0
		(_ring.get_child(i) as Node3D).position = Vector3(cos(a), 0.0, sin(a)) * r


## Тело — диски-«позвонки» (low-poly призмы), каждый повёрнут на свой угол; голова — три вытянутые
## челюсти, внутри — глотка и кольцо зубов.
func _build_body() -> void:
	_body = Node3D.new()
	add_child(_body)
	var mat := Creature.skin(BODY_COLOR, BodyMaterial.Pattern.GROOVES, Grid.ART_PX)
	var ring := Creature.skin(RING_COLOR, BodyMaterial.Pattern.GROOVES, Grid.ART_PX)
	for i in DISCS:
		var big := i % 2 == 0
		var disc := MeshKit.prism(_body, MeshKit.ngon(8 if big else 7, R * (1.0 if big else 0.84)),
				0.0, 0.36 if big else 0.22, mat if big else ring)
		disc.position.y = i * DISC_STEP + (0.0 if big else 0.07)
		disc.rotation.y = i * 0.41
	var throat := MeshKit.prism(_body, MeshKit.ngon(8, R * 0.9), 0.0, 0.04, Creature.material(THROAT_COLOR))
	throat.position.y = BODY_LEN
	var tooth := Creature.material(TOOTH_COLOR)
	for i in 16:     # кольцо зубов по краю глотки, остриём внутрь и вверх
		var a := TAU * i / 16.0
		_tooth(_body, Vector3(cos(a) * R * 0.8, BODY_LEN + 0.1, sin(a) * R * 0.8), Vector3(0, -a, 0.9), 0.24, tooth)
	var jaw_mesh := _jaw_mesh()
	var jaw_mat := Creature.material(BODY_COLOR.darkened(0.08))
	jaw_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 3:
		var turn := Node3D.new()
		turn.position = Vector3(0, BODY_LEN, 0)
		turn.rotation.y = -TAU * i / 3.0
		_body.add_child(turn)
		var hinge := Node3D.new()
		hinge.position = Vector3(R, 0, 0)
		turn.add_child(hinge)
		var jaw := MeshInstance3D.new()
		jaw.mesh = jaw_mesh
		jaw.material_override = jaw_mat
		hinge.add_child(jaw)
		for j in 3:      # зубы на внутренней стороне челюсти
			var u: float = [0.2, 0.42, 0.62][j]
			var r := R * _jaw_radius(u)
			_tooth(hinge, Vector3(r - R - 0.06, JAW_LEN * u, (j - 1) * 0.25 * r / R), Vector3(0, 0, PI * 0.5), 0.2, tooth)
		_jaws.append(hinge)


func _tooth(parent: Node3D, at: Vector3, rot: Vector3, length: float, mat: Material) -> void:
	var t := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = length * 0.25
	cone.height = length
	cone.radial_segments = 4
	cone.rings = 0
	t.mesh = cone
	t.material_override = mat
	t.position = at
	t.rotation = rot
	parent.add_child(t)


## Профиль челюсти: доля радиуса R на доле длины u (0 — основание, 1 — кончик морды).
const JAW_U := [0.0, 0.25, 0.5, 0.72, 0.88, 1.0]
const JAW_R := [1.0, 0.97, 0.84, 0.62, 0.36, 0.0]


static func _jaw_radius(u: float) -> float:
	for k in JAW_U.size() - 1:
		if u <= JAW_U[k + 1]:
			return lerpf(JAW_R[k], JAW_R[k + 1], (u - JAW_U[k]) / (JAW_U[k + 1] - JAW_U[k]))
	return 0.0


## Челюсть — вытянутый сектор в 120° вокруг оси Y, сходящийся к кончику морды: low-poly, грани из
## треугольников, края зазубрены (вершины кромки по очереди выступают за сектор и западают внутрь).
## Координаты шарнира: шарнир — середина нижней кромки, ось поворота — касательная к ней (локальная Z).
static func _jaw_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := [-60.0, -20.0, 20.0, 60.0]
	var shift := Vector3(R, 0, 0)
	var grid: Array = []
	for ri in JAW_U.size():
		var row: Array[Vector3] = []
		for ci in cols.size():
			var deg: float = cols[ci]
			if (ci == 0 or ci == cols.size() - 1) and ri > 0 and ri < JAW_U.size() - 1:
				deg += signf(deg) * (10.0 if ri % 2 == 1 else -7.0)     # зазубрины по кромке
			var a := deg_to_rad(deg)
			var r: float = R * JAW_R[ri]
			row.append(Vector3(r * cos(a), JAW_LEN * JAW_U[ri], r * sin(a)) - shift)
		grid.append(row)
	for ri in JAW_U.size() - 1:
		var inside := Vector3(0, JAW_LEN * (JAW_U[ri] + JAW_U[ri + 1]) * 0.5, 0) - shift
		for ci in cols.size() - 1:
			var a: Vector3 = grid[ri][ci]
			var b: Vector3 = grid[ri][ci + 1]
			var c: Vector3 = grid[ri + 1][ci]
			var d: Vector3 = grid[ri + 1][ci + 1]
			MeshKit.tri_out(st, a, c, b, inside)
			MeshKit.tri_out(st, b, c, d, inside)
	return st.commit()


## Пыль — в цвет грунта под червём: песочная над песком, терракотовая над грунтом равнин.
func _tint_dust() -> void:
	var dust := PixelFx.dust_color(query, pos.x, pos.y)
	var clod := PixelFx.clod_color(query, pos.x, pos.y)
	_wake.color = dust
	_burst_dust.color = dust
	_wake_clods.color = clod
	_burst.color = clod


## Пыль или комья (PixelFx) из-под земли вверх: разброс и скорость — свои у вала и броска.
func _ground_fx(p: CPUParticles3D, spread: float, v_min: float, v_max: float) -> CPUParticles3D:
	p.spread = spread
	p.initial_velocity_min = v_min
	p.initial_velocity_max = v_max
	add_child(p)
	return p
