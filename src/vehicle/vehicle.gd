class_name Vehicle
extends Node3D
## Машина игрока: модель, кинематика по сетке (VehicleKinematics), звук двигателя.
## Позиция обновляется в _physics_process; плавность на высоких FPS даёт physics interpolation.

signal landed(tiers: int, damage: int)

const BODY_COLOR := Color(0.88, 0.55, 0.18)
const GLASS_COLOR := Color(0.45, 0.85, 0.9)
const WHEEL_COLOR := Color(0.16, 0.14, 0.18)
const XRAY_COLOR := Color(1.0, 0.75, 0.25, 0.75)

var cls: VehicleClass
var query: TerrainQuery
var state := VehicleState.new()
var camera: Camera3D
var autopilot: Autopilot
var control_enabled := true
var total_distance := 0.0
var engine: EngineSound

var _tilt := Basis.IDENTITY


func _init(vehicle_class: VehicleClass, terrain_query: TerrainQuery) -> void:
	cls = vehicle_class
	query = terrain_query
	name = "Vehicle"


func _ready() -> void:
	add_child(_build_model())
	engine = EngineSound.new()
	add_child(engine)


func place(pos: Vector2, heading: float = 0.0) -> void:
	state.pos = pos
	state.heading = heading
	state.tile = Grid.tile_of_world(pos.x, pos.y)
	state.y = VehicleKinematics.ground_y(state, cls, query)
	_tilt = _ground_basis()
	_apply_transform()
	reset_physics_interpolation()


func _physics_process(dt: float) -> void:
	var inp := Vector2.ZERO
	if control_enabled:
		inp = autopilot.direction(state, dt) if autopilot != null else VehicleInput.world_direction(camera)
	var before := state.pos
	var r := VehicleKinematics.step(state, inp, cls, query, dt)
	total_distance += before.distance_to(state.pos)
	if r.landed:
		landed.emit(r.fell_tiers, r.fall_damage)
		EventBus.vehicle_fell.emit(r.fell_tiers, r.fall_damage)
	if not state.falling:
		_tilt = _tilt.slerp(_ground_basis(), minf(1.0, 12.0 * dt))
	_apply_transform()
	engine.update(state.vel.length() / cls.max_speed, state.throttle, dt)


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


## Модель ровера из примитивов; перед — по −Z.
func _build_model() -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	root.scale = Vector3.ONE * 1.25
	var body_mat := _material(BODY_COLOR)
	body_mat.stencil_mode = BaseMaterial3D.STENCIL_MODE_XRAY
	body_mat.stencil_color = XRAY_COLOR
	_box(root, Vector3(0.5, 0.18, 0.8), Vector3(0, 0.24, 0), body_mat)
	_box(root, Vector3(0.38, 0.14, 0.3), Vector3(0, 0.4, -0.12), _material(GLASS_COLOR))
	var wheel_mat := _material(WHEEL_COLOR)
	for x in [-0.28, 0.28]:
		for z in [-0.27, 0.27]:
			var wheel := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.13
			cyl.bottom_radius = 0.13
			cyl.height = 0.1
			cyl.radial_segments = 8
			cyl.rings = 0
			wheel.mesh = cyl
			wheel.material_override = wheel_mat
			wheel.rotation = Vector3(0, 0, PI * 0.5)
			wheel.position = Vector3(x, 0.13, z)
			root.add_child(wheel)
	var mast := MeshInstance3D.new()
	var mast_mesh := CylinderMesh.new()
	mast_mesh.top_radius = 0.012
	mast_mesh.bottom_radius = 0.012
	mast_mesh.height = 0.35
	mast.mesh = mast_mesh
	mast.material_override = wheel_mat
	mast.position = Vector3(0.16, 0.5, 0.3)
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
