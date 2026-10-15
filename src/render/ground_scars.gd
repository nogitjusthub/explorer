class_name GroundScars
extends Node3D
## Временные следы угроз на земле (GDD §3.5): смерч — сплошная полоса содранного грунта по пути, молния —
## выжженное пятно. Рельеф не меняется — смерч и молния землю не копают. Квады в одном MultiMesh (кольцом по
## MAX_SCARS), шейдер ground_scar затемняет ими землю в пикселях её текстуры и гасит след за LIFE_S ступенями.
## Узел живёт у ThreatDirector, а не у угрозы: смерч ушёл — след ещё виден.

const MAX_SCARS := 400
const LIFE_S := 30.0
const LIFT := 0.02                       ## над землёй — не мерцает с ней
const STRIP := 0.0
const SPOT := 1.0

var query: TerrainQuery
var _mm: MultiMesh
var _mat: ShaderMaterial
var _head := 0
var _count := 0
var _time := 0.0
var _rng := RandomNumberGenerator.new()  ## зерно рисунка следа — внешний вид, не решения


func _init() -> void:
	name = "GroundScars"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://src/render/shaders/ground_scar.gdshader")
	_mat.set_shader_parameter(&"life_s", LIFE_S)
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	quad.material = _mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = quad
	_mm.instance_count = MAX_SCARS
	_mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-1e5, -1e3, -1e5), Vector3(2e5, 2e3, 2e5))
	add_child(mi)


func _process(dt: float) -> void:
	_time += dt
	_mat.set_shader_parameter(&"now", _time)


func count() -> int:
	return _count


## Полоса от a до b (мировые x, z) шириной width — кусок следа смерча.
func strip(a: Vector2, b: Vector2, width: float) -> void:
	var pa := Vector3(a.x, query.surface_y(a.x, a.y), a.y)
	var pb := Vector3(b.x, query.surface_y(b.x, b.y), b.y)
	var mid := (pa + pb) * 0.5
	var n := query.normal_at(mid.x, mid.z)
	var fwd := pb - pa
	var length := Vector2(fwd.x, fwd.z).length()      # куски встык: внахлёст умножение темнило бы стыки
	fwd = (fwd - n * fwd.dot(n)).normalized()
	_put(Basis(n.cross(fwd).normalized() * width, n, fwd * length), mid + n * LIFT, STRIP, 0.0)


## Пятно радиуса radius в точке at (мировые x, z) — след удара молнии.
func spot(at: Vector2, radius: float) -> void:
	var p := Vector3(at.x, query.surface_y(at.x, at.y), at.y)
	var n := query.normal_at(at.x, at.y)
	var fwd := (Vector3.FORWARD - n * Vector3.FORWARD.dot(n)).normalized()
	_put(Basis(n.cross(fwd).normalized() * radius * 2.0, n, fwd * radius * 2.0), p + n * LIFT, SPOT, _rng.randf() * 100.0)


## seed — зерно рваного края: у кусков полосы общее (край непрерывен через стыки), у пятен своё.
func _put(basis: Basis, origin: Vector3, kind: float, seed: float) -> void:
	_mm.set_instance_transform(_head, Transform3D(basis, origin))
	_mm.set_instance_custom_data(_head, Color(kind, seed, 0.0, _time))
	_head = (_head + 1) % MAX_SCARS
	_count = mini(_count + 1, MAX_SCARS)
	_mm.visible_instance_count = _count
