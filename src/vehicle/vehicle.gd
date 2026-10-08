class_name Vehicle
extends Node3D
## Машина игрока: модель, кинематика по сетке (VehicleKinematics), звук двигателя.
## Позиция обновляется в _physics_process; плавность на высоких FPS даёт physics interpolation.

signal landed(tiers: int, damage: int)
signal damaged(amount: int, source: StringName)   ## урон от падения или валки дерева (до учёта HP)
signal died(cause: StringName)                    ## гибель, которую решает кинематика (утонула)

const BODY_COLOR := Color(0.88, 0.55, 0.18)
const GLASS_COLOR := Color(0.4, 0.82, 0.98, 0.7)
const WHEEL_COLOR := Color(0.16, 0.14, 0.18)
const XRAY_COLOR := Color(1.0, 0.75, 0.25, 0.75)
const WRECK_COLOR := Color(0.22, 0.18, 0.17)

var cls: VehicleClass
var query: TerrainQuery
var state := VehicleState.new()
var camera: Camera3D
var autopilot: Autopilot
var control_enabled := true
var engine_running := true      ## false — двигатель заглох (пустой бак): газа нет, машина катится до остановки
var wrecked := false
var total_distance := 0.0
var engine: EngineSound

var _tilt := Basis.IDENTITY
var _body_mat: StandardMaterial3D


func _init(vehicle_class: VehicleClass, terrain_query: TerrainQuery) -> void:
	cls = vehicle_class
	query = terrain_query
	name = "Vehicle"


func _ready() -> void:
	add_child(_build_model())
	engine = EngineSound.new()
	add_child(engine)


func place(pos: Vector2, heading: float = 0.0) -> void:
	state = VehicleState.new()
	state.pos = pos
	state.heading = heading
	state.tile = Grid.tile_of_world(pos.x, pos.y)
	state.y = VehicleKinematics.ground_y(state, cls, query)
	_tilt = _ground_basis()
	_apply_transform()
	reset_physics_interpolation()


func _physics_process(dt: float) -> void:
	var inp := Vector2.ZERO
	if control_enabled and engine_running and not wrecked:
		inp = autopilot.direction(state, dt) if autopilot != null else VehicleInput.world_direction(camera)
	var before := state.pos
	var r := VehicleKinematics.step(state, inp, cls, query, dt)
	total_distance += before.distance_to(state.pos)
	if r.landed:
		landed.emit(r.fell_tiers, r.fall_damage)
		EventBus.vehicle_fell.emit(r.fell_tiers, r.fall_damage)
		if r.fall_damage > 0:
			damaged.emit(r.fall_damage, &"fall")
	if r.tree_damage > 0:
		damaged.emit(r.tree_damage, &"tree")
	if r.drowned:
		died.emit(&"drowned")
	if not state.falling and not state.drowning:
		_tilt = _tilt.slerp(_ground_basis(), minf(1.0, 12.0 * dt))
	_apply_transform()
	if engine_running and not wrecked:
		engine.update(state.vel.length() / cls.max_speed, state.throttle, dt)
	elif engine.playing:
		engine.volume_db = move_toward(engine.volume_db, -60.0, 40.0 * dt)
		if engine.volume_db <= -59.0:
			engine.stop()


## Машина разбита: управление отключено, корпус темнеет, двигатель стихает.
func wreck() -> void:
	wrecked = true
	_body_mat.albedo_color = WRECK_COLOR


func _apply_transform() -> void:
	transform = Transform3D(_tilt, Vector3(state.pos.x, state.y, state.pos.y))


## Ориентация по курсу и наклону поверхности (4 точки контакта).
func _ground_basis() -> Basis:
	var f := state.forward()
	var fwd := Vector3(f.x, 0.0, f.y)
	var right := Vector3(-f.y, 0.0, f.x)
	var p := state.pos
	var hf := query.surface_y(p.x + f.x * 0.45, p.y + f.y * 0.45)
	var hb := query.surface_y(p.x - f.x * 0.45, p.y - f.y * 0.45)
	var hr := query.surface_y(p.x + right.x * 0.3, p.y + right.z * 0.3)
	var hl := query.surface_y(p.x - right.x * 0.3, p.y - right.z * 0.3)
	var f3 := Vector3(fwd.x * 0.9, hf - hb, fwd.z * 0.9).normalized()
	var r3 := Vector3(right.x * 0.6, hr - hl, right.z * 0.6).normalized()
	var up := r3.cross(f3).normalized()
	return Basis.looking_at(f3, up)


## Модель ровера из примитивов; перед — по −Z. Шесть колёс, кабина — стеклянная полусфера.
## Корпус виден сквозь препятствия силуэтом (stencil XRAY: силуэт рисуется там, где в stencil не 1).
## Колёса и мачта пишут в stencil ту же 1 — иначе силуэт корпуса ложился бы поверх них и колёса
## казались бы прозрачными. Стекло прозрачное само и в stencil не пишет.
func _build_model() -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	root.scale = Vector3.ONE * 1.25
	var body_mat := _material(BODY_COLOR)
	_body_mat = body_mat
	body_mat.stencil_mode = BaseMaterial3D.STENCIL_MODE_XRAY
	body_mat.stencil_color = XRAY_COLOR
	body_mat.stencil_reference = 1
	_box(root, Vector3(0.52, 0.16, 0.68), Vector3(0, 0.22, 0), body_mat)

	var glass := StandardMaterial3D.new()
	glass.albedo_color = GLASS_COLOR
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.1
	glass.metallic = 0.3
	var dome := MeshInstance3D.new()
	var dome_mesh := SphereMesh.new()
	dome_mesh.radius = 0.17
	dome_mesh.height = 0.17
	dome_mesh.is_hemisphere = true
	dome_mesh.radial_segments = 12
	dome_mesh.rings = 4
	dome.mesh = dome_mesh
	dome.material_override = glass
	dome.position = Vector3(0, 0.30, -0.08)
	root.add_child(dome)

	var wheel_mat := _material(WHEEL_COLOR)
	wheel_mat.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
	wheel_mat.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
	wheel_mat.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
	wheel_mat.stencil_reference = 1
	# Колёса почти вплотную: шаг 0,235 при диаметре 0,22.
	for x in [-0.3, 0.3]:
		for z in [-0.235, 0.0, 0.235]:
			var wheel := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.11
			cyl.bottom_radius = 0.11
			cyl.height = 0.09
			cyl.radial_segments = 8
			cyl.rings = 0
			wheel.mesh = cyl
			wheel.material_override = wheel_mat
			wheel.rotation = Vector3(0, 0, PI * 0.5)
			wheel.position = Vector3(x, 0.11, z)
			root.add_child(wheel)
	var mast := MeshInstance3D.new()
	var mast_mesh := CylinderMesh.new()
	mast_mesh.top_radius = 0.012
	mast_mesh.bottom_radius = 0.012
	mast_mesh.height = 0.35
	mast.mesh = mast_mesh
	mast.material_override = wheel_mat
	mast.position = Vector3(0.17, 0.45, 0.24)
	root.add_child(mast)
	return root


static func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.7
	return m


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
