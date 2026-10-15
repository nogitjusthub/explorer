class_name VehicleTrail
extends Node3D
## Следы и пыль от езды. Колёса ровера и гусеницы танка оставляют на земле колею — отпечатки-квады в
## одном MultiMesh (кольцом по MAX_MARKS), шейдер track_mark затемняет ими землю в пикселях её текстуры и
## гасит их за MARK_S секунд или дальше MARK_FAR тайлов от машины (за краем экрана). На ходу из-под колёс
## летят пыль и комья цвета грунта (PixelFx — как у всех эффектов); ховер колеи не оставляет — поднимает
## пыль кольцом вокруг юбки. Сила следа и пыли — по материалу: песок сильнее всего, камень и кристалл —
## едва, зыбун — колея и комья грязи без пыли. По воде (вброд или на подушке) — как у Нессы, только меньше:
## V-волна пены от носа (по ходу, задним ходом — от кормы) и брызги; тонет — пузыри над ней.

const MAX_MARKS := 900
const TEXEL := Grid.ART_PX              ## пиксель — шаг следов и пыли
const STEP := TEXEL * 2.0                ## новый отпечаток — каждые 2 текселя пути колеи
const MARK_S := 16.0
const MARK_FAR := 13.0
const LIFT := 0.012                      ## отпечаток чуть над землёй
const DUST_SPEED := 1.2                  ## тайл/с — с этой скорости колёса пылят
const WAKE_SPEED := 0.4                  ## тайл/с — с этой скорости по воде расходится волна
const WAKE_LEN := 1.6                    ## длина плеча V-волны на полном ходу, тайлов (у Нессы — 2,4)
const WAKE_ANGLE := 0.42                 ## рад — раствор плеч (как у Нессы)
const WAKE_LIFT := 0.03                  ## пена чуть над зеркалом
const WATER_DROP := 0.06                 ## зеркало воды ниже яруса на столько (как у Нессы)
## Колеи класса: смещения колей от оси вбок и ширина колеи; рисунок у всех один — траки.
const LINES := {
	&"rover": {"offsets": [-0.25, 0.25], "width": TEXEL * 2.0},
	&"tank": {"offsets": [-0.245, 0.245], "width": TEXEL * 3.0},
}

var cls: VehicleClass
var query: TerrainQuery

var _mm: MultiMesh
var _mat: ShaderMaterial
var _count := 0                          ## поставлено отпечатков (до MAX_MARKS)
var _head := 0                           ## куда ляжет следующий (кольцо)
var _time := 0.0
var _last: Array[Variant] = []           ## последняя точка каждой колеи (Vector3) или null — колея прервана
var _dist: Array[float] = []             ## путь вдоль колеи — непрерывный рисунок траков
var _dust: CPUParticles3D
var _dirt: CPUParticles3D
var _wake: Node3D                        ## V-волна по воде: два плеча пены (шейдер foam_strip)
var _wake_mat: ShaderMaterial
var _arms: Array[MeshInstance3D] = []
var _wake_k := 0.0
var _traveled := 0.0                     ## путь по воде — бег штрихов пены
var _spray: CPUParticles3D               ## брызги из-под машины в воде
var _bubbles: CPUParticles3D             ## пузыри над тонущей


func setup(vehicle_class: VehicleClass, terrain_query: TerrainQuery) -> void:
	cls = vehicle_class
	query = terrain_query
	name = "Trail"
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://src/render/shaders/track_mark.gdshader")
	_mat.set_shader_parameter(&"mark_s", MARK_S)
	_mat.set_shader_parameter(&"far", MARK_FAR)
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	quad.material = _mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = quad
	_mm.instance_count = MAX_MARKS
	_mm.visible_instance_count = 0
	var marks := MultiMeshInstance3D.new()
	marks.multimesh = _mm
	marks.top_level = true                       # отпечатки — в мире, не едут за машиной
	marks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marks.custom_aabb = AABB(Vector3(-1e5, -1e3, -1e5), Vector3(2e5, 2e3, 2e5))
	add_child(marks)
	_dust = PixelFx.dust(14, 0.6)
	_dust.initial_velocity_min = 0.3
	_dust.initial_velocity_max = 0.8
	add_child(_dust)
	_dirt = PixelFx.clods(8, 0.3)
	_dirt.direction = Vector3(0, 1.0, 0.8)
	_dirt.spread = 30.0
	_dirt.initial_velocity_min = 1.0
	_dirt.initial_velocity_max = 2.0
	add_child(_dirt)
	_build_water()
	set_class(vehicle_class)


## Смена класса: колеи по ширине нового, старые отпечатки остаются гаснуть.
func set_class(vehicle_class: VehicleClass) -> void:
	cls = vehicle_class
	var n := 0
	if LINES.has(cls.id):
		n = (LINES[cls.id]["offsets"] as Array).size()
	_last.resize(n)
	_last.fill(null)
	_dist.resize(n)
	_dist.fill(0.0)
	if cls.hovers:
		_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING     # подушка дует во все стороны
		_dust.emission_ring_axis = Vector3.UP
		_dust.emission_ring_radius = 0.42
		_dust.emission_ring_inner_radius = 0.3
		_dust.emission_ring_height = 0.02
		_dust.direction = Vector3.UP
		_dust.spread = 80.0
		_dust.radial_accel_min = 1.5
		_dust.radial_accel_max = 2.5
	else:
		_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX      # из-под задних колёс
		_dust.emission_box_extents = Vector3(0.26, 0.02, 0.05)
		_dust.direction = Vector3(0, 1.0, 0.8)
		_dust.spread = 30.0
		_dust.radial_accel_min = 0.0
		_dust.radial_accel_max = 0.0


## Сила следа на тайле: 0 — не остаётся (вода), 1 — песок.
static func strength(material: int, flags: int) -> float:
	if (flags & ChunkData.FLAG_MIRE) != 0:
		return 1.0
	var s: float = [0.85, 1.0, 0.3, 0.35][clampi(material, 0, 3)]
	return s * (0.8 if (flags & ChunkData.FLAG_ROUGH) != 0 else 1.0)


## Пыль на тайле: 0…1 (в зыбуне — нет, только грязь).
static func dust_amount(material: int, flags: int) -> float:
	if (flags & ChunkData.FLAG_MIRE) != 0:
		return 0.0
	var d: float = [0.6, 1.0, 0.35, 0.4][clampi(material, 0, 3)]
	return d * (1.2 if (flags & ChunkData.FLAG_ROUGH) != 0 else 1.0)


## Шаг: колеи за машиной state, пыль и комья по скорости и грунту. on_ground — машина на земле (не летит,
## не тонет, не в луче).
func track(state: VehicleState, on_ground: bool, dt: float) -> void:
	_time += dt
	_mat.set_shader_parameter(&"now", _time)
	_mat.set_shader_parameter(&"center", Vector3(state.pos.x, 0.0, state.pos.y))
	var t := state.tile
	var loaded := query.is_loaded(t.x, t.y)
	var wet := not loaded or query.water_tier(t.x, t.y) != TerrainQuery.NO_WATER
	var mat := query.material(t.x, t.y) if loaded else 0
	var flags := query.flags(t.x, t.y) if loaded else 0
	var ground := on_ground and not wet
	_lay_marks(state, ground)
	if not is_inside_tree():
		return                                   # частицы — только в сцене (в тестах колея без них)
	var speed := state.vel.length()
	var yaw := Basis(Vector3.UP, atan2(-state.forward().x, -state.forward().y))
	var at := Vector3(state.pos.x, state.y + 0.04, state.pos.y)
	var back := Vector3(-state.forward().x, 0.0, -state.forward().y) * (0.0 if cls.hovers else 0.36)
	_dust.global_transform = Transform3D(yaw, at + back)
	_dirt.global_transform = _dust.global_transform
	var dusty := dust_amount(mat, flags) if ground else 0.0
	_dust.emitting = dusty > 0.0 and speed > DUST_SPEED * (0.5 if cls.hovers else 1.0)
	_dust.color = PixelFx.dust_color(query, state.pos.x, state.pos.y)
	_dirt.emitting = ground and not cls.hovers and speed > DUST_SPEED and (mat <= 1 or (flags & ChunkData.FLAG_MIRE) != 0)
	_dirt.color = PixelFx.clod_color(query, state.pos.x, state.pos.y)
	_water(state, loaded and query.water_tier(t.x, t.y) != TerrainQuery.NO_WATER, speed, dt)


func mark_count() -> int:
	return _count


func _lay_marks(state: VehicleState, ground: bool) -> void:
	if not LINES.has(cls.id):
		return
	var spec: Dictionary = LINES[cls.id]
	var offsets: Array = spec["offsets"]
	var f := state.forward()
	var side := Vector2(-f.y, f.x)
	for i in offsets.size():
		var p2 := state.pos + side * float(offsets[i])
		if not ground:
			_last[i] = null
			continue
		var p := Vector3(p2.x, query.surface_y(p2.x, p2.y), p2.y)
		if _last[i] == null:
			_last[i] = p
			continue
		var a: Vector3 = _last[i]
		var d := Vector2(p.x - a.x, p.z - a.z).length()
		if d < STEP:
			continue
		if d > 1.0:                                  # скачок (рывок, перенос) — колею не тянем
			_last[i] = p
			continue
		var tile := Grid.tile_of_world(p2.x, p2.y)
		var s := strength(query.material(tile.x, tile.y), query.flags(tile.x, tile.y))
		_add_mark(a, p, float(spec["width"]), _dist[i], s)
		_dist[i] += d
		_last[i] = p


func _add_mark(a: Vector3, b: Vector3, width: float, dist: float, s: float) -> void:
	var mid := (a + b) * 0.5
	var n := query.normal_at(mid.x, mid.z)
	var fwd := b - a
	var length := Vector2(fwd.x, fwd.z).length()
	fwd = (fwd - n * fwd.dot(n)).normalized()
	var right := n.cross(fwd).normalized()
	var basis := Basis(right * width, n, fwd * length)
	_mm.set_instance_transform(_head, Transform3D(basis, mid + n * LIFT))
	_mm.set_instance_color(_head, Color(1, 1, 1, s))
	_mm.set_instance_custom_data(_head, Color(0.0, dist, length, _time))
	_head = (_head + 1) % MAX_MARKS
	_count = mini(_count + 1, MAX_MARKS)
	_mm.visible_instance_count = _count


## Образец для прогрева шейдеров: один отпечаток (в начале координат узла отпечатков — прогрев переносит
## его к своей камере) и летящие пыль с комьями.
func preview(at: Vector3) -> void:
	_add_mark(Vector3.ZERO, Vector3(0, 0, STEP), TEXEL * 2.0, 0.0, 1.0)
	for p in [_dust, _dirt, _spray, _bubbles]:
		p.global_position = at
		p.emitting = true
	_wake.global_position = at
	_wake.visible = true



# --- Вода ---------------------------------------------------------------------------------------------------


func _build_water() -> void:
	_wake = Node3D.new()
	_wake.top_level = true
	_wake.visible = false
	add_child(_wake)
	_wake_mat = ShaderMaterial.new()
	_wake_mat.shader = LakeMonster.FOAM_SHADER
	_wake_mat.set_shader_parameter(&"foam", LakeMonster.FOAM_COLOR)
	_wake_mat.render_priority = 1                # поверх прозрачной воды
	var strip := LakeMonster._strip_mesh(TEXEL * 2.0)   # два пикселя шириной, как у Нессы, но короче
	for side: float in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		arm.mesh = strip
		arm.material_override = _wake_mat
		arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		arm.rotation.y = WAKE_ANGLE * side
		_wake.add_child(arm)
		_arms.append(arm)
	_spray = PixelFx.clods(14, 0.45)             # капли — как комья (PixelFx), цвета пены
	_spray.color = LakeMonster.FOAM_COLOR
	_spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_spray.emission_box_extents = Vector3(0.3, 0.02, 0.06)
	_spray.direction = Vector3(0, 1.0, -0.6)
	_spray.spread = 45.0
	_spray.initial_velocity_min = 0.8
	_spray.initial_velocity_max = 1.8
	add_child(_spray)
	_bubbles = PixelFx.clods(16, 0.8)
	_bubbles.color = LakeMonster.FOAM_COLOR
	_bubbles.gravity = Vector3(0, -1.2, 0)       # всплывают и лопаются, как у Нессы
	_bubbles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_bubbles.emission_box_extents = Vector3(0.3, 0.02, 0.3)
	_bubbles.spread = 25.0
	_bubbles.initial_velocity_min = 0.3
	_bubbles.initial_velocity_max = 0.8
	add_child(_bubbles)


## Вода под машиной: по ходу — волна и брызги (сила — от скорости), тонет — пузыри над ней.
func _water(state: VehicleState, wet: bool, speed: float, dt: float) -> void:
	var w := query.water_tier(state.tile.x, state.tile.y) if wet else TerrainQuery.NO_WATER
	var surface := Grid.tier_to_y(w) - WATER_DROP if wet else state.y
	var moving := wet and not state.drowning and not state.falling and speed > WAKE_SPEED
	# Сила — от скорости в воде (вброд машина вдвое медленнее): на её пределе волна полная.
	var top := cls.max_speed * (1.0 if cls.hovers else cls.water_speed_mult)
	var want := clampf(speed / top, 0.0, 1.0) if moving else 0.0
	_wake_k = move_toward(_wake_k, want, dt * (3.0 if want > _wake_k else 1.5))
	_wake.visible = _wake_k > 0.03
	var dir := state.vel.normalized() if speed > 0.01 else state.forward()
	if _wake.visible:
		_traveled += speed * dt
		var bow := state.pos + dir * 0.35            # волна — от носа по ходу (задним ходом — от кормы)
		_wake.global_position = Vector3(bow.x, surface + WAKE_LIFT, bow.y)
		_wake.rotation = Vector3(0.0, atan2(-dir.x, -dir.y), 0.0)
		for arm in _arms:
			arm.scale = Vector3(1.0, 1.0, WAKE_LEN * (0.4 + 0.6 * _wake_k))
		_wake_mat.set_shader_parameter(&"alpha", _wake_k)
		_wake_mat.set_shader_parameter(&"flow", _traveled / WAKE_LEN * 5.0)
	_spray.emitting = moving
	if moving:
		var bow := state.pos + dir * 0.3
		_spray.global_transform = Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), Vector3(bow.x, surface, bow.y))
		_spray.initial_velocity_max = lerpf(1.0, 2.2, _wake_k)
	var sinking := wet and state.drowning
	_bubbles.emitting = sinking
	if sinking:
		_bubbles.global_position = Vector3(state.pos.x, surface, state.pos.y)
