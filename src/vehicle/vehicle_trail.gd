class_name VehicleTrail
extends Node3D
## Следы и пыль от езды. Колёса ровера и гусеницы танка оставляют на земле колею — отпечатки-квады в
## одном MultiMesh (кольцом по MAX_MARKS), шейдер track_mark затемняет ими землю в пикселях её текстуры и
## гасит их за MARK_S секунд или дальше MARK_FAR тайлов от машины (за краем экрана). На ходу из-под колёс
## летят пыль (облачка 4×4 текселя) и комья (тексель) цвета грунта; ховер колеи не оставляет — поднимает
## пыль кольцом вокруг юбки. Сила следа и пыли — по материалу: песок сильнее всего, камень и кристалл —
## едва, зыбун — колея и комья грязи без пыли, вода — ничего.

const MAX_MARKS := 900
const TEXEL := 1.0 / 16.0                ## тексель рельефа — пиксельный шаг следов и пыли
const STEP := TEXEL * 2.0                ## новый отпечаток — каждые 2 текселя пути колеи
const MARK_S := 16.0
const MARK_FAR := 13.0
const LIFT := 0.012                      ## отпечаток чуть над землёй
const DUST_SPEED := 1.2                  ## тайл/с — с этой скорости колёса пылят
## Колеи класса: смещения колей от оси вбок, ширина колеи, вид рисунка (0 — колесо, 1 — гусеница).
const LINES := {
	&"rover": {"offsets": [-0.25, 0.25], "width": TEXEL * 2.0, "kind": 0},
	&"tank": {"offsets": [-0.245, 0.245], "width": TEXEL * 3.0, "kind": 1},
}

var cls: VehicleClass
var query: TerrainQuery

var _mm: MultiMesh
var _mat: ShaderMaterial
var _count := 0                          ## поставлено отпечатков (до MAX_MARKS)
var _head := 0                           ## куда ляжет следующий (кольцо)
var _time := 0.0
var _last: Array[Variant] = []           ## последняя точка каждой колеи (Vector3) или null — колея прервана
var _dist: Array[float] = []             ## путь вдоль колеи — непрерывный рисунок протектора
var _dust: CPUParticles3D
var _dirt: CPUParticles3D


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
	_dust = _particles(14, 0.8, TEXEL * 4.0, _puff_texture())
	_dirt = _particles(10, 0.5, TEXEL, null)
	_dirt.gravity = Vector3(0, -9.0, 0)
	_dirt.initial_velocity_min = 1.0
	_dirt.initial_velocity_max = 2.0
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
	var base: Color = ChunkMesher.MATERIAL_COLORS[clampi(mat, 0, 3)]
	var dusty := dust_amount(mat, flags) if ground else 0.0
	_dust.emitting = dusty > 0.0 and speed > DUST_SPEED * (0.5 if cls.hovers else 1.0)
	_dust.color = Color(base.lightened(0.18), clampf(0.45 + 0.4 * dusty, 0.0, 0.85))
	_dirt.emitting = ground and not cls.hovers and speed > DUST_SPEED and (mat <= 1 or (flags & ChunkData.FLAG_MIRE) != 0)
	_dirt.color = base.darkened(0.45 if (flags & ChunkData.FLAG_MIRE) != 0 else 0.3)


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
		_add_mark(a, p, float(spec["width"]), int(spec["kind"]), _dist[i], s)
		_dist[i] += d
		_last[i] = p


func _add_mark(a: Vector3, b: Vector3, width: float, kind: int, dist: float, s: float) -> void:
	var mid := (a + b) * 0.5
	var n := query.normal_at(mid.x, mid.z)
	var fwd := b - a
	var length := Vector2(fwd.x, fwd.z).length()
	fwd = (fwd - n * fwd.dot(n)).normalized()
	var right := n.cross(fwd).normalized()
	var basis := Basis(right * width, n, fwd * length)
	_mm.set_instance_transform(_head, Transform3D(basis, mid + n * LIFT))
	_mm.set_instance_color(_head, Color(1, 1, 1, s))
	_mm.set_instance_custom_data(_head, Color(kind, dist, length, _time))
	_head = (_head + 1) % MAX_MARKS
	_count = mini(_count + 1, MAX_MARKS)
	_mm.visible_instance_count = _count


func _particles(amount: int, lifetime: float, size: float, tex: Texture2D) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.emitting = false
	p.direction = Vector3(0, 1.0, 0.8)
	p.spread = 30.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.8
	p.gravity = Vector3(0, 0.15, 0)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if tex != null:
		m.albedo_texture = tex
	q.material = m
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


## Облачко пыли 4×4 текселя: круг без углов, середина плотнее.
static func _puff_texture() -> ImageTexture:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	for y in 4:
		for x in 4:
			var corner := (x == 0 or x == 3) and (y == 0 or y == 3)
			var inner := x >= 1 and x <= 2 and y >= 1 and y <= 2
			img.set_pixel(x, y, Color(1, 1, 1, 0.0 if corner else (1.0 if inner else 0.6)))
	return ImageTexture.create_from_image(img)


## Образец для прогрева шейдеров: один отпечаток (в начале координат узла отпечатков — прогрев переносит
## его к своей камере) и летящие пыль с комьями.
func preview(at: Vector3) -> void:
	_add_mark(Vector3.ZERO, Vector3(0, 0, STEP), TEXEL * 2.0, 0, 0.0, 1.0)
	for p in [_dust, _dirt]:
		p.global_position = at
		p.emitting = true
