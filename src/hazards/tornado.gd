class_name Tornado
extends Node3D
## Смерч (GDD §5.2): приходит сам по себе (с T ≥ 3) или из пылевой бури, блуждает с уклоном к машине, живёт tornado_life_s.
## Внешняя зона (tornado_pull_r) тянет к центру: a(r) = pull / масса × (1 − r / pull_r). Ядро
## (tornado_core_r): tornado_core_dps урона в секунду, через tornado_throw_after_s выбрасывает машину по
## дуге на tornado_throw_dist туда, где посадка не выше старта; приземление — по правилам падения.
## Пашет борозду (кроме скал), вырывает деревья, подхватывает находки и роняет их по пути. Гудит —
## громче с приближением.

signal damaged(amount: int, source: StringName)

const HEIGHT := 6.0
const FURROW_EVERY_S := 0.5
const DAMAGE_STEP := 5                   ## урон ядра приходит порциями, чтобы не мельтешить в HUD
const CATCH_R := 1.2                     ## находки ближе — подхвачены
const FADE_S := 1.5
const HEAR_TILES := 30.0
const COLOR_FUNNEL := Color(0.3, 0.22, 0.19, 0.8)

var rules: BalanceRules
var vehicle: Vehicle
var query: TerrainQuery
var terrain: TerrainData
var pickups: PickupField
var rng: RandomNumberGenerator

var pos := Vector2.ZERO
var drift := Vector2.ZERO                ## снос ветром бури, тайл/с
var finished := false

var _dir := Vector2.RIGHT
var _wander := Vector2.RIGHT
var _life := 0.0
var _core_time := 0.0
var _damage_acc := 0.0
var _furrow_from := Vector2.ZERO
var _furrow_timer := FURROW_EVERY_S
var _carried: Array[Dictionary] = []     ## {kind, left}
var _ploughed: Dictionary = {}           ## вершины, уже опущенные этим смерчем
var _fade := -1.0
var _funnel: Node3D
var _dust: CPUParticles3D                ## пыль у основания (PixelFx — как у всех), цвет грунта под смерчем
var _clods: CPUParticles3D               ## и комья из борозды
var _audio: AudioStreamPlayer
var _spin := 0.0


func _init() -> void:
	name = "Tornado"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func begin(at: Vector2) -> void:
	pos = at
	_furrow_from = at
	_life = rules.tornado_life_s
	_wander = (vehicle.state.pos - at).normalized().rotated(rng.randf_range(-0.8, 0.8))
	_dir = _wander
	_build()
	_place()


## Выброс из ядра: из восьми направлений — то, где посадка не выше старта (иначе — самое низкое).
static func throw_target(q: TerrainQuery, from: Vector2, dist: float, start_dir: float) -> Vector2:
	var start := q.surface_tier(from.x, from.y)
	var best := from
	var best_tier := INF
	for i in 8:
		var p := from + Vector2.from_angle(start_dir + i * TAU / 8.0) * dist
		var t := Grid.tile_of_world(p.x, p.y)
		if not q.is_loaded(t.x, t.y):
			continue
		var tier := q.surface_tier(p.x, p.y)
		if tier <= start + 0.01:
			return p
		if tier < best_tier:
			best_tier = tier
			best = p
	return best


func step(dt: float) -> void:
	if finished:
		return
	if _audio.stream == null:
		_start_sound()
	_spin += dt * 9.0
	_funnel.rotation.y = _spin
	_dust.color = PixelFx.dust_color(query, pos.x, pos.y)
	_clods.color = PixelFx.clod_color(query, pos.x, pos.y)
	if _fade >= 0.0:
		_fade -= dt
		_funnel.scale = Vector3.ONE * maxf(_fade / FADE_S, 0.01)
		_audio.volume_db = linear_to_db(maxf(_fade / FADE_S, 0.001)) - 6.0
		if _fade <= 0.0:
			finished = true
			for c in _carried:
				pickups.drop(c["kind"], pos, 0.0)
			EventBus.threat_ended.emit(&"tornado")
		return
	_life -= dt
	if _life <= 0.0:
		_fade = FADE_S
	_move(dt)
	_place()
	EventBus.threat_telegraphed.emit(&"tornado", position, 0.0, _dir)
	_affect_vehicle(dt)
	_furrow_timer -= dt
	if _furrow_timer <= 0.0:
		_furrow_timer = FURROW_EVERY_S
		_plough()
	for i in range(_carried.size() - 1, -1, -1):
		_carried[i]["left"] -= dt
		if _carried[i]["left"] <= 0.0:
			pickups.drop(_carried[i]["kind"], pos, 0.0)
			_carried.remove_at(i)
	var d := vehicle.state.pos.distance_to(pos)
	_audio.volume_db = linear_to_db(clampf(1.0 - d / HEAR_TILES, 0.02, 1.0)) - 2.0


## Блуждание с уклоном к машине (вблизи слабым, издалека сильнее — смерч не теряется) плюс снос
## ветром бури; в незагруженный рельеф не заходит.
func _move(dt: float) -> void:
	_wander = _wander.rotated(rng.randf_range(-1.6, 1.6) * dt)
	var offset := vehicle.state.pos - pos
	var bias := clampf((offset.length() - 6.0) / 12.0, 0.25, 0.85)
	_dir = (_wander * (1.0 - bias) + offset.normalized() * bias).normalized()
	var next := pos + (_dir * rules.tornado_speed + drift) * dt
	var t := Grid.tile_of_world(next.x, next.y)
	if query.is_loaded(t.x, t.y):
		pos = next
	else:
		_wander = -_wander


func _affect_vehicle(dt: float) -> void:
	var s := vehicle.state
	if s.falling or s.drowning:
		_core_time = 0.0
		return
	var to_center := pos - s.pos
	var d := to_center.length()
	if d < rules.tornado_pull_r and d > 0.01:
		var a := rules.tornado_pull_accel / vehicle.cls.mass * (1.0 - d / rules.tornado_pull_r)
		s.ext_accel += to_center / d * a
	if d > rules.tornado_core_r:
		_core_time = 0.0
		return
	_core_time += dt
	_damage_acc += rules.tornado_core_dps * dt
	if _damage_acc >= DAMAGE_STEP:
		_damage_acc -= DAMAGE_STEP
		damaged.emit(DAMAGE_STEP, &"tornado")
	if _core_time >= rules.tornado_throw_after_s:
		_core_time = 0.0
		var target := throw_target(query, s.pos, rules.tornado_throw_dist, rng.randf() * TAU)
		VehicleKinematics.launch(s, target, 1.6, vehicle.cls, query)
		vehicle.tumble(target - s.pos, 0.4)


## След: борозда (скалы не берёт), вырванные деревья, подхваченные находки.
func _plough() -> void:
	if _furrow_from.distance_to(pos) > 0.2:
		# Под водой дно не трогаем: борозда сквозь водоём выглядела криво и ломала берега.
		if not _wet(_furrow_from) and not _wet(pos):
			Deformation.furrow(terrain, _furrow_from, pos, 0.6, _ploughed)
			# Камень смерч не пашет, но крошит: на скалах за ним остаётся россыпь обломков.
			var t := Grid.tile_of_world(pos.x, pos.y)
			var m := query.material(t.x, t.y)
			if m == ChunkData.Mat.ROCK or m == ChunkData.Mat.CRYSTAL:
				Deformation.mark_ground(terrain, [t] as Array[Vector2i], ChunkData.FLAG_ROUGH)
		_furrow_from = pos
	var c := Grid.tile_of_world(pos.x, pos.y)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var t := c + Vector2i(dx, dz)
			if query.has_standing_tree(t.x, t.y) and query.tree_position(t.x, t.y).distance_to(pos) < CATCH_R:
				query.fell_tree(t.x, t.y)
	for p in pickups.near(pos, CATCH_R):
		pickups.take(p["key"])
		_carried.append({"kind": p["kind"], "left": rng.randf_range(2.0, 5.0)})


## Вода в точке или рядом (в полутайле) — борозду там не копаем.
func _wet(p: Vector2) -> bool:
	for o in [Vector2.ZERO, Vector2(0.6, 0), Vector2(-0.6, 0), Vector2(0, 0.6), Vector2(0, -0.6)]:
		var t := Grid.tile_of_world(p.x + o.x, p.y + o.y)
		if query.water_tier(t.x, t.y) != TerrainQuery.NO_WATER:
			return true
	return false


func _place() -> void:
	var t := Grid.tile_of_world(pos.x, pos.y)
	var y := query.surface_y(pos.x, pos.y) if query.is_loaded(t.x, t.y) else position.y
	position = Vector3(pos.x, y, pos.y)


## Воронка — три конуса, расширяющихся кверху, крутится; у основания — пыль. Гул — петля.
func _build() -> void:
	_funnel = Node3D.new()
	add_child(_funnel)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = COLOR_FUNNEL
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var parts := [[0.0, 1.5, 0.35, 0.8], [1.5, 3.6, 0.8, 1.5], [3.6, HEIGHT, 1.5, 2.3]]
	for i in parts.size():
		var p: Array = parts[i]
		var cone := CylinderMesh.new()
		cone.bottom_radius = p[2]
		cone.top_radius = p[3]
		cone.height = p[1] - p[0]
		cone.radial_segments = 10
		cone.rings = 1
		cone.cap_top = false
		cone.cap_bottom = false
		var mi := MeshInstance3D.new()
		mi.mesh = cone
		mi.material_override = mat
		mi.position = Vector3(0.15 * sin(i * 2.1), (p[0] + p[1]) * 0.5, 0.15 * cos(i * 2.1))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_funnel.add_child(mi)
	# Пыль и комья у основания закручиваются вокруг воронки (касательное ускорение).
	_dust = PixelFx.dust(40, 1.0)
	_clods = PixelFx.clods(16, 0.8)
	for p: CPUParticles3D in [_dust, _clods]:
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		p.emission_ring_axis = Vector3.UP
		p.emission_ring_radius = 1.2
		p.emission_ring_inner_radius = 0.4
		p.emission_ring_height = 0.1
		p.spread = 30.0
		p.tangential_accel_min = 5.0
		p.tangential_accel_max = 8.0
		add_child(p)
		p.emitting = true                   # после add_child: частицы в мировых координатах берут позицию узла
	_dust.initial_velocity_min = 1.0
	_dust.initial_velocity_max = 2.5
	_clods.initial_velocity_min = 2.0
	_clods.initial_velocity_max = 4.0
	_audio = AudioStreamPlayer.new()
	_audio.volume_db = -40.0
	add_child(_audio)


## Вой включается с первым шагом: образец смерча в прогреве шейдеров (Warmup) не шагает — молчит и не
## заставляет синтезировать вой раньше очереди (Sfx).
func _start_sound() -> void:
	_audio.stream = Sfx.named(&"howl")
	_audio.play()
