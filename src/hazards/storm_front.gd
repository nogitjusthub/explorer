class_name StormFront
extends Node3D
## Грозовой фронт (GDD §5.1): тень облаков радиусом storm_radius ползёт через окрестность машины,
## над ней — слои туч (MurkLayers), в тучах зарницы; под фронтом сцена темнеет и идёт дождь
## (через weather_changed — свет и экранный слой частиц).
## Внутри — удары молнии неравномерно, в среднем раз в strike_interval_s: паузы разной длины, иногда
## серия из двух-трёх ударов подряд (next_strike_gap); часть рядом с машиной (если она под фронтом),
## остальные — по фронту; точка выбирается с весом по высоте (вершины и деревья притягивают удары).
## Телеграф — светящийся круг и треск, удар через strike_telegraph_s: урон, поваленное дерево, из
## кристаллической породы выбиваются кристаллы; на суше — временное выжженное пятно (GroundScars; землю
## молния не копает). Тень рисуют шейдеры по глобальным параметрам
## storm_center / storm_radius.

signal damaged(amount: int, source: StringName)

const CANDIDATES := 6
const FAR_STRIKE_R := 22.0               ## остальные удары — по фронту не дальше этого от машины
const NO_TARGET := Vector2(INF, INF)
const FLICKER_S := 0.24                  ## период мерцания знака удара
const COLOR_BOLT := Color(0.85, 0.92, 1.0)
const COLOR_GLOW := Color(0.55, 0.7, 1.0, 0.35)
const COLOR_CLOUD := Color(0.2, 0.21, 0.28)
const BOLT_S := 0.22
const CLOUD_MARGIN := 8.0                ## тучи висят высоко и на экране видны раньше края тени — фронт рождается дальше
const FADE_S := 3.0                      ## тучи и тень проявляются в начале и тают в конце за столько
const ELMO_SHADER := preload("res://src/render/shaders/st_elmo.gdshader")

var rules: BalanceRules
var vehicle: Vehicle
var query: TerrainQuery
var terrain: TerrainData
var generator: TerrainGenerator
var streamer: WorldStreamer
var pickups: PickupField
var rng: RandomNumberGenerator
var scars: GroundScars                    ## временные следы на земле (ThreatDirector)

var center := Vector2.ZERO
var direction := Vector2.RIGHT
var radius := 15.0
var _age := 0.0
var ended := false                       ## фронт ушёл: новых ударов нет
var finished := false                    ## ушёл и отгремели начатые удары — узел можно убрать

var _strike_timer := 1.0
var _series := 0                         ## сколько ещё ударов в текущей серии
var _pending: Array[Dictionary] = []     ## {pos: Vector2, left: float, node: Node3D}
var _bolts: Array[Dictionary] = []       ## {node, left, light}
var _clouds: MurkLayers
var _sheet_timer := 2.0
var _sheet := 0.0
var coverage := 0.0                      ## насколько машина под тучами, 0…1
var _fade := 0.0                         ## проявление туч и тени, 0…1


func _init() -> void:
	name = "StormFront"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## Фронт появляется так, что его край — за краем экрана, и идёт через машину с небольшим отклонением.
func begin() -> void:
	var from := Vector2.from_angle(rng.randf() * TAU)
	radius = rules.storm_radius
	center = vehicle.state.pos + from * (radius + rules.murk_gap + CLOUD_MARGIN)
	direction = (-from).rotated(rng.randf_range(-0.35, 0.35))
	_clouds = MurkLayers.new()
	add_child(_clouds)
	var drift := direction * rules.storm_speed * 0.04
	_clouds.add_layer(COLOR_CLOUD, 0.42, 5.5, 0.05, drift, 1)
	_clouds.add_layer(COLOR_CLOUD.lightened(0.08), 0.36, 7.5, 0.035, drift * 1.4, 1)
	_update_shadow()


func covers(p: Vector2) -> bool:
	return not ended and p.distance_to(center) <= radius


func step(dt: float) -> void:
	center += direction * rules.storm_speed * dt
	_age += dt
	if _age > rules.storm_max_s and not ended:
		radius = rules.storm_radius * clampf(1.0 - (_age - rules.storm_max_s) / rules.dissipate_s, 0.0, 1.0)
		if radius <= 1.0:
			_end()
	_fade = clampf(_fade + dt / FADE_S * (-1.0 if ended else 1.0), 0.0, 1.0)
	_update_shadow()
	var to_vehicle := vehicle.state.pos - center
	coverage = (1.0 - smoothstep(radius - 8.0, radius, to_vehicle.length())) * _fade
	EventBus.weather_changed.emit(&"storm", coverage)
	_clouds.update(Vector3(vehicle.state.pos.x, vehicle.state.y, vehicle.state.pos.y), 3.0, _fade)
	_step_sheet(dt)
	var away := to_vehicle.dot(direction) < 0.0
	if not ended:
		EventBus.threat_telegraphed.emit(&"storm", Vector3(center.x, 0.0, center.y), 0.0, direction)
	# Прошёл машину и удалился — кончился (новых ударов нет, ждём начатые).
	if away and to_vehicle.length() > radius + rules.murk_gap + CLOUD_MARGIN:
		_end()
	if not ended:
		_strike_timer -= dt
		if _strike_timer <= 0.0:
			_strike_timer = _next_strike_gap()
			var target := _pick_target()
			if target != NO_TARGET:
				_telegraph(target)
	for i in range(_pending.size() - 1, -1, -1):
		var s: Dictionary = _pending[i]
		s["left"] -= dt
		var node: Node3D = s["node"]
		var left: float = s["left"]
		# Корона разгорается и мерцает — пара вспышек, и удар.
		var k := 1.0 - left / rules.strike_telegraph_s
		var flick := 0.6 + 0.4 * float(fmod(rules.strike_telegraph_s - left, FLICKER_S) < FLICKER_S * 0.6)
		(node.get_meta(&"mat") as ShaderMaterial).set_shader_parameter("intensity", (0.5 + 0.9 * k) * flick)
		(node.get_meta(&"light") as OmniLight3D).light_energy = (0.6 + 1.4 * k) * flick
		if left <= 0.0:
			node.queue_free()
			_pending.remove_at(i)
			_strike(s["pos"])
	for i in range(_bolts.size() - 1, -1, -1):
		var b: Dictionary = _bolts[i]
		b["left"] -= dt
		var k: float = b["left"] / BOLT_S
		(b["node"] as Node3D).visible = k > 0.55 or (k > 0.15 and k < 0.35)   # мерцание разряда
		(b["light"] as OmniLight3D).light_energy = 6.0 * maxf(k, 0.0)
		if b["left"] <= 0.0:
			(b["node"] as Node3D).queue_free()
			(b["light"] as Node3D).queue_free()
			_bolts.remove_at(i)
	finished = ended and _pending.is_empty() and _bolts.is_empty() and _fade <= 0.0


## Пауза до следующего удара: в серии — короткая (0,35–0,9 с); иначе 0,5–2 × strike_interval_s, и с
## шансом 30% после неё начинается серия ещё из одного-двух ударов. В среднем — около strike_interval_s.
func _next_strike_gap() -> float:
	if _series > 0:
		_series -= 1
		return rng.randf_range(0.35, 0.9)
	if rng.randf() < 0.3:
		_series = rng.randi_range(1, 2)
	return rng.randf_range(0.5, 2.0) * rules.strike_interval_s


func _end() -> void:
	if ended:
		return
	ended = true                         # тучи и тень тают за FADE_S (step), потом фронт убирается
	EventBus.threat_ended.emit(&"storm")


## Точка удара: рядом с машиной (если она под фронтом) или по фронту в окрестности машины — дальние
## удары во фронте размером с полкарты никто бы не увидел; выше — вероятнее.
func _pick_target() -> Vector2:
	var near := covers(vehicle.state.pos) and rng.randf() < rules.strike_near_frac
	var r := rules.strike_near_r if near else FAR_STRIKE_R
	var best := vehicle.state.pos
	var best_score := -INF
	for _i in CANDIDATES * 2:
		var p := vehicle.state.pos + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * r
		var t := Grid.tile_of_world(p.x, p.y)
		if not query.is_loaded(t.x, t.y) or not covers(p):
			continue
		var score := query.surface_tier(p.x, p.y) + rng.randf() * 1.5
		if query.has_standing_tree(t.x, t.y):
			score += 1.5
		if score > best_score:
			best_score = score
			best = p
	if near:
		# Машина на вершине — громоотвод.
		var own := query.surface_tier(vehicle.state.pos.x, vehicle.state.pos.y) + 1.0 + rng.randf() * 1.5
		if own > best_score:
			best = vehicle.state.pos
	elif best_score == -INF:
		return NO_TARGET               # фронт далеко от машины — удар никто не увидит
	return best


## Отладка (--event=strike): удар прямо в машину.
func strike_vehicle() -> void:
	_telegraph(vehicle.state.pos)


## Знак удара — «огни святого Эльма»: мерцающая голубая корона, искры и подсветка там, куда ударит.
## Бьёт в машину — светится конец антенны, в дерево — его макушка.
func _telegraph(p: Vector2) -> void:
	var t := Grid.tile_of_world(p.x, p.y)
	var y := query.surface_y(p.x, p.y) + 0.2
	if p == vehicle.state.pos:
		y = vehicle.state.y + 0.75
	elif query.has_standing_tree(t.x, t.y) and query.tree_position(t.x, t.y).distance_to(p) < 0.9:
		y += 0.8
	var node := Node3D.new()
	node.position = Vector3(p.x, y, p.y)
	var corona := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	corona.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = ELMO_SHADER
	mat.set_shader_parameter("seed", rng.randf() * 100.0)
	corona.material_override = mat
	corona.scale = Vector3(1.1, 1.1, 1.0)
	corona.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(corona)
	var sparks := CPUParticles3D.new()
	sparks.amount = 16
	sparks.lifetime = 0.3
	sparks.direction = Vector3.UP
	sparks.spread = 180.0
	sparks.initial_velocity_min = 0.4
	sparks.initial_velocity_max = 1.4
	sparks.gravity = Vector3.ZERO
	sparks.mesh = PixelFx.quad(1, Color(0.75, 0.85, 1.0))
	node.add_child(sparks)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.6, 0.7, 1.0)
	glow.omni_range = 2.5
	glow.light_energy = 1.0
	glow.shadow_enabled = false
	node.add_child(glow)
	node.set_meta(&"mat", mat)
	node.set_meta(&"light", glow)
	add_child(node)
	_pending.append({"pos": p, "left": rules.strike_telegraph_s, "node": node})
	EventBus.threat_telegraphed.emit(&"lightning", node.position, rules.strike_telegraph_s, Vector2.ZERO)


func _strike(p: Vector2) -> void:
	var t := Grid.tile_of_world(p.x, p.y)
	if not query.is_loaded(t.x, t.y):
		return
	var ground := Vector3(p.x, query.surface_y(p.x, p.y), p.y)
	_spawn_bolt(ground)
	EventBus.lightning_struck.emit(ground)
	var d := vehicle.state.pos.distance_to(p)
	EventBus.screen_flash_requested.emit(clampf(1.0 - d / 14.0, 0.0, 1.0))
	EventBus.camera_shake_requested.emit(clampf(1.0 - d / 8.0, 0.0, 1.0) * 0.8, 0.3)
	if not vehicle.state.drowning:
		var hit := true
		if d <= rules.strike_core_r:
			damaged.emit(rules.strike_damage_center, &"lightning")
		elif d <= rules.strike_radius + VehicleKinematics.RADIUS:
			damaged.emit(rules.strike_damage_edge, &"lightning")
		else:
			hit = false
		if hit:
			vehicle.invert_controls(rules.shock_invert_s)    # разряд по машине — управление наоборот
	# Дерево под ударом падает, кристаллическая порода выбрасывает кристаллы.
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var n := t + Vector2i(dx, dz)
			if query.has_standing_tree(n.x, n.y) and query.tree_position(n.x, n.y).distance_to(p) < 0.9:
				query.fell_tree(n.x, n.y)
	if query.material(t.x, t.y) == ChunkData.Mat.CRYSTAL:
		for _i in 1 + rng.randi() % 2:
			pickups.drop(&"crystal", p, 0.8)
	# Выжженное пятно — на суше, временное: землю молния не копает (воронки складывались в ямы у машины).
	if scars != null and query.water_tier(t.x, t.y) == TerrainQuery.NO_WATER:
		scars.spot(p, rules.strike_radius * 0.8)


## Молния — ломаная от тучи до земли с ответвлениями: яркая сердцевина и голубое свечение, вспышка
## света над точкой удара и искры. Гаснет, мерцая, за BOLT_S.
func _spawn_bolt(ground: Vector3) -> void:
	var node := Node3D.new()
	var core := StandardMaterial3D.new()
	core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core.albedo_color = COLOR_BOLT
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.albedo_color = COLOR_GLOW
	var top := ground + Vector3(rng.randf_range(-2.0, 2.0), 16.0, rng.randf_range(-2.0, 2.0))
	var points: Array[Vector3] = [top]
	for i in range(1, 7):
		var p := top.lerp(ground, i / 6.0)
		if i < 6:
			p += Vector3(rng.randf_range(-0.9, 0.9), 0.0, rng.randf_range(-0.9, 0.9))
		points.append(p)
	for i in range(1, points.size()):
		_bolt_segment(node, points[i - 1], points[i], Grid.ART_PX * 2.0, core, glow)
	# Ответвления от средних изломов — короткие, вниз и в сторону.
	for j in [2, 3]:
		var from: Vector3 = points[j]
		var side := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized()
		var a := from + side * 1.4 + Vector3(0, -1.6, 0)
		var b := a + side * 1.0 + Vector3(rng.randf_range(-0.4, 0.4), -1.4, rng.randf_range(-0.4, 0.4))
		_bolt_segment(node, from, a, Grid.ART_PX, core, glow)
		_bolt_segment(node, a, b, Grid.ART_PX, core, glow)
	add_child(node)
	var light := OmniLight3D.new()
	light.light_color = Color(0.75, 0.85, 1.0)
	light.light_energy = 6.0
	light.omni_range = 10.0
	light.shadow_enabled = false
	light.position = ground + Vector3(0, 1.5, 0)
	add_child(light)
	_spawn_sparks(ground)
	_bolts.append({"node": node, "left": BOLT_S, "light": light})


func _bolt_segment(parent: Node3D, a: Vector3, b: Vector3, width: float, core: Material, glow: Material) -> void:
	for layer in [[width, core], [width + Grid.ART_PX * 2.0, glow]]:    # ореол — пиксель мира с каждой стороны
		var seg := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(layer[0], a.distance_to(b), layer[0])
		seg.mesh = box
		seg.material_override = layer[1]
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		seg.position = (a + b) * 0.5
		seg.basis = Basis(Quaternion(Vector3.UP, (b - a).normalized()))
		parent.add_child(seg)


## Искры в точке удара — короткий выброс.
func _spawn_sparks(ground: Vector3) -> void:
	var sparks := CPUParticles3D.new()
	sparks.position = ground + Vector3(0, 0.1, 0)
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.amount = 24
	sparks.lifetime = 0.6
	sparks.direction = Vector3.UP
	sparks.spread = 70.0
	sparks.initial_velocity_min = 2.5
	sparks.initial_velocity_max = 6.0
	sparks.gravity = Vector3(0, -12.0, 0)
	sparks.mesh = PixelFx.quad(1, Color(1.0, 0.95, 0.7))
	add_child(sparks)
	sparks.emitting = true
	get_tree().create_timer(1.0).timeout.connect(sparks.queue_free)


## Зарницы: тучи вспыхивают изнутри, далёкий гром; вспышка экрана — когда машина под фронтом.
func _step_sheet(dt: float) -> void:
	_sheet = maxf(_sheet - dt * 6.0, 0.0)
	_clouds.set_flash(_sheet)
	if ended:
		return
	_sheet_timer -= dt
	if _sheet_timer <= 0.0:
		_sheet_timer = rng.randf_range(1.5, 4.0)
		_sheet = 1.0
		var p := center + Vector2.from_angle(rng.randf() * TAU) * rng.randf() * radius
		EventBus.sheet_lightning.emit(Vector3(p.x, 0.0, p.y))
		EventBus.screen_flash_requested.emit(0.18 * coverage)


func _update_shadow() -> void:
	RenderingServer.global_shader_parameter_set(&"storm_center", Vector3(center.x, 0.0, center.y))
	RenderingServer.global_shader_parameter_set(&"storm_radius", radius if _fade > 0.0 else 0.0)
	RenderingServer.global_shader_parameter_set(&"storm_dark", rules.storm_dark * _fade)


## Сцену закрыли посреди грозы («Заново»): глобальные параметры шейдеров живут дольше сцены — без сброса
## тень туч и сами тучи остались бы и в новом забеге. Сброс — как после растаявшего фронта.
func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set(&"storm_radius", 0.0)
	RenderingServer.global_shader_parameter_set(&"storm_dark", 0.0)
