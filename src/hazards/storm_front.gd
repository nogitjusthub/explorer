class_name StormFront
extends Node3D
## Грозовой фронт (GDD §5.1): тень облаков радиусом storm_radius ползёт через окрестность машины.
## Внутри — удар молнии каждые strike_interval_s: часть рядом с машиной (если она под фронтом),
## остальные — по фронту; точка выбирается с весом по высоте (вершины и деревья притягивают удары).
## Телеграф — светящийся круг и треск, удар через strike_telegraph_s: урон, воронка, поваленное дерево,
## из кристаллической породы выбиваются кристаллы. Тень рисуют шейдеры по глобальным параметрам
## storm_center / storm_radius.

signal damaged(amount: int, source: StringName)

const CANDIDATES := 6
const COLOR_TELEGRAPH := Color(1.0, 0.45, 0.2, 0.55)
const COLOR_BOLT := Color(0.85, 0.92, 1.0)

var rules: BalanceRules
var vehicle: Vehicle
var query: TerrainQuery
var terrain: TerrainData
var generator: TerrainGenerator
var streamer: WorldStreamer
var pickups: PickupField
var rng: RandomNumberGenerator

var center := Vector2.ZERO
var direction := Vector2.RIGHT
var ended := false                       ## фронт ушёл: новых ударов нет
var finished := false                    ## ушёл и отгремели начатые удары — узел можно убрать

var _strike_timer := 1.0
var _pending: Array[Dictionary] = []     ## {pos: Vector2, left: float, node: Node3D}
var _bolts: Array[Dictionary] = []       ## {node, left}


func _init() -> void:
	name = "StormFront"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## Фронт появляется на storm_spawn_dist от машины и идёт через неё с небольшим отклонением.
func begin() -> void:
	var from := Vector2.from_angle(rng.randf() * TAU)
	center = vehicle.state.pos + from * rules.storm_spawn_dist
	direction = (-from).rotated(rng.randf_range(-0.35, 0.35))
	_update_shadow()


func covers(p: Vector2) -> bool:
	return not ended and p.distance_to(center) <= rules.storm_radius


func step(dt: float) -> void:
	center += direction * rules.storm_speed * dt
	_update_shadow()
	var to_vehicle := vehicle.state.pos - center
	var away := to_vehicle.dot(direction) < 0.0
	if not ended:
		EventBus.threat_telegraphed.emit(&"storm", Vector3(center.x, 0.0, center.y), 0.0, direction)
	# Прошёл машину и удалился — кончился (новых ударов нет, ждём начатые).
	if away and to_vehicle.length() > rules.storm_radius + 6.0:
		_end()
	if not ended:
		_strike_timer -= dt
		if _strike_timer <= 0.0:
			_strike_timer = rules.strike_interval_s
			_telegraph(_pick_target())
	for i in range(_pending.size() - 1, -1, -1):
		var s: Dictionary = _pending[i]
		s["left"] -= dt
		var node: Node3D = s["node"]
		var left: float = s["left"]
		var k := 1.0 - left / rules.strike_telegraph_s
		node.scale = Vector3.ONE * lerpf(0.6, 1.0, k)
		(node.get_meta(&"mat") as StandardMaterial3D).albedo_color.a = 0.25 + 0.5 * k + 0.2 * sin(left * 40.0)
		if left <= 0.0:
			node.queue_free()
			_pending.remove_at(i)
			_strike(s["pos"])
	for i in range(_bolts.size() - 1, -1, -1):
		_bolts[i]["left"] -= dt
		if _bolts[i]["left"] <= 0.0:
			(_bolts[i]["node"] as Node3D).queue_free()
			_bolts.remove_at(i)
	finished = ended and _pending.is_empty() and _bolts.is_empty()


func _end() -> void:
	if ended:
		return
	ended = true
	RenderingServer.global_shader_parameter_set(&"storm_radius", 0.0)
	EventBus.threat_ended.emit(&"storm")


## Точка удара: рядом с машиной (если она под фронтом) или по фронту, выше — вероятнее.
func _pick_target() -> Vector2:
	var near := covers(vehicle.state.pos) and rng.randf() < rules.strike_near_frac
	var base := vehicle.state.pos if near else center
	var r := rules.strike_near_r if near else rules.storm_radius
	var best := base
	var best_score := -INF
	for _i in CANDIDATES:
		var p := base + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * r
		var t := Grid.tile_of_world(p.x, p.y)
		if not query.is_loaded(t.x, t.y):
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
	return best


func _telegraph(p: Vector2) -> void:
	var y := query.surface_y(p.x, p.y)
	var node := Node3D.new()
	node.position = Vector3(p.x, y + 0.06, p.y)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = COLOR_TELEGRAPH
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ring := TorusMesh.new()
	ring.inner_radius = rules.strike_radius - 0.12
	ring.outer_radius = rules.strike_radius
	ring.rings = 24
	ring.ring_segments = 4
	var ring_mi := MeshInstance3D.new()
	ring_mi.mesh = ring
	ring_mi.material_override = mat
	ring_mi.scale = Vector3(1, 0.3, 1)
	ring_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(ring_mi)
	var disc := CylinderMesh.new()
	disc.top_radius = rules.strike_core_r
	disc.bottom_radius = rules.strike_core_r
	disc.height = 0.02
	disc.radial_segments = 12
	disc.rings = 0
	var disc_mi := MeshInstance3D.new()
	disc_mi.mesh = disc
	disc_mi.material_override = mat
	disc_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(disc_mi)
	node.set_meta(&"mat", mat)
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
		if d <= rules.strike_core_r:
			damaged.emit(rules.strike_damage_center, &"lightning")
		elif d <= rules.strike_radius + VehicleKinematics.RADIUS:
			damaged.emit(rules.strike_damage_edge, &"lightning")
	# Дерево под ударом падает, кристаллическая порода выбрасывает кристаллы.
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var n := t + Vector2i(dx, dz)
			if query.has_standing_tree(n.x, n.y) and query.tree_position(n.x, n.y).distance_to(p) < 0.9:
				query.fell_tree(n.x, n.y)
	if query.material(t.x, t.y) == ChunkData.Mat.CRYSTAL:
		for _i in 1 + rng.randi() % 2:
			pickups.drop(&"crystal", p, 0.8)
	Deformation.crater(terrain, p, rules.strike_radius, rules.strike_crater_depth)


## Молния — ломаная из тонких ярких отрезков от облака до земли, гаснет за доли секунды.
func _spawn_bolt(ground: Vector3) -> void:
	var node := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = COLOR_BOLT
	var top := ground + Vector3(rng.randf_range(-1.5, 1.5), 14.0, rng.randf_range(-1.5, 1.5))
	var prev := top
	for i in range(1, 6):
		var k := i / 5.0
		var p := top.lerp(ground, k)
		if i < 5:
			p += Vector3(rng.randf_range(-0.6, 0.6), 0.0, rng.randf_range(-0.6, 0.6))
		var seg := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.09, prev.distance_to(p), 0.09)
		seg.mesh = box
		seg.material_override = mat
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		seg.position = (prev + p) * 0.5
		seg.basis = Basis(Quaternion(Vector3.UP, (p - prev).normalized()))
		node.add_child(seg)
		prev = p
	add_child(node)
	_bolts.append({"node": node, "left": 0.16})


func _update_shadow() -> void:
	RenderingServer.global_shader_parameter_set(&"storm_center", Vector3(center.x, 0.0, center.y))
	RenderingServer.global_shader_parameter_set(&"storm_radius", 0.0 if ended else rules.storm_radius)
