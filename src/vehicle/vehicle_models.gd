class_name VehicleModels
extends RefCounted
## Модели техники из примитивов: перед — по −Z, размеры — в тайлах. Единый габарит ~0,85 × 0,65 тайла,
## один цвет экспедиции на всех, крупная ходовая, немного деталей. У всех одинаковый стеклянный
## купол-кабина (полусфера диаметром 0,3) и антенна.
## Ровер — квадратный корпус на шести колёсах почти вплотную.
## Танк — гусеничный транспортёр (design_references: ТМ-140, ГАЗ-71): купол спереди — самая высокая
## точка, кузов сзади ниже, чтобы перед читался сразу.
## Ховер — судно на воздушной подушке (Griffon): чёрная юбка, палуба с надстройкой, два вентилятора в кожухах.
##
## Силуэт сквозь стены: крупные окрашенные части — stencil XRAY (силуэт рисуется там, где в stencil
## не 1), остальные непрозрачные детали пишут в stencil ту же 1 — иначе силуэт корпуса ложился бы
## поверх них, и они казались бы прозрачными.

const XRAY_COLOR := Color(1.0, 0.75, 0.25, 0.75)
const TRIM := Color(0.1, 0.1, 0.12)
const RUBBER := Color(0.12, 0.11, 0.13)
const LAMP := Color(1.0, 0.95, 0.7)
const BODY := Color(0.92, 0.52, 0.16)       ## цвет экспедиции — общий для всех классов
const UNDER := Color(0.24, 0.24, 0.27)      ## днище, кант
const METAL := Color(0.72, 0.72, 0.76)      ## диски и катки
const DOME_GLASS := Color(0.4, 0.82, 0.98, 0.7)
const DOME_R := 0.15


## Собранная модель: корень, все материалы (для потемнения при гибели) и вращающиеся части.
class Model:
	extends RefCounted
	var root: Node3D
	var materials: Array[StandardMaterial3D] = []
	var spinners: Array[Node3D] = []        ## вращаются вокруг своей оси Z (вентиляторы)
	var hover_height := 0.0                 ## модель парит над поверхностью (ховер)


static func build(id: StringName) -> Model:
	var m := Model.new()
	m.root = Node3D.new()
	m.root.name = "Model"
	match id:
		&"tank":
			_tank(m)
		&"hover":
			_hover(m)
		_:
			_rover(m)
	return m


static func _rover(m: Model) -> void:
	var paint := _paint(m, BODY)
	var under := _solid(m, UNDER)
	var tire := _solid(m, RUBBER)
	var hub := _solid(m, METAL)
	var lamp := _lamp(m)
	var r := m.root
	# Квадратный корпус на шести колёсах почти вплотную, купол-кабина.
	for x in [-0.25, 0.25]:
		for z in [-0.28, 0.0, 0.28]:
			_cyl(r, 0.13, 0.12, Vector3(x, 0.13, z), tire, Vector3(0, 0, PI * 0.5), 10)
			_cyl(r, 0.05, 0.126, Vector3(x, 0.13, z), hub, Vector3(0, 0, PI * 0.5), 8)
	_box(r, Vector3(0.34, 0.08, 0.62), Vector3(0, 0.17, 0.0), under)
	_box(r, Vector3(0.44, 0.2, 0.64), Vector3(0, 0.29, 0.0), paint)
	_dome(m, Vector3(0, 0.39, -0.08))
	for x in [-0.12, 0.12]:
		_box(r, Vector3(0.06, 0.04, 0.02), Vector3(x, 0.3, -0.325), lamp)
	_antenna(m, Vector3(0.15, 0.39, 0.22))


static func _tank(m: Model) -> void:
	var paint := _paint(m, BODY)
	var track := _solid(m, RUBBER)
	var wheel := _solid(m, METAL)
	var lamp := _lamp(m)
	var r := m.root
	# Купол-кабина спереди — самая высокая точка, кузов сзади ниже купола: перед читается сразу.
	for x in [-0.245, 0.245]:
		_box(r, Vector3(0.15, 0.18, 0.84), Vector3(x, 0.09, 0.0), track)
		var side := signf(x)
		for z in [-0.27, -0.09, 0.09, 0.27]:
			_cyl(r, 0.065, 0.03, Vector3(x + side * 0.08, 0.085, z), wheel, Vector3(0, 0, PI * 0.5), 8)
	_box(r, Vector3(0.62, 0.03, 0.8), Vector3(0, 0.195, 0.0), paint)       # полки над гусеницами
	_box(r, Vector3(0.4, 0.19, 0.82), Vector3(0, 0.275, 0.0), paint)       # корпус
	_dome(m, Vector3(0, 0.37, -0.2))
	_box(r, Vector3(0.42, 0.11, 0.38), Vector3(0, 0.425, 0.22), paint)     # трюм — вровень с кормой, ниже купола
	for x in [-0.12, 0.12]:
		_box(r, Vector3(0.06, 0.04, 0.02), Vector3(x, 0.3, -0.415), lamp)
	# Пуш-бар: намёк, что танк таранит деревья и прочее.
	var bar := _solid(m, UNDER)
	_box(r, Vector3(0.48, 0.05, 0.04), Vector3(0, 0.2, -0.47), bar)
	for x in [-0.16, 0.16]:
		_box(r, Vector3(0.04, 0.16, 0.04), Vector3(x, 0.24, -0.46), bar)
		_box(r, Vector3(0.04, 0.04, 0.06), Vector3(x, 0.3, -0.43), bar)
	_antenna(m, Vector3(0.14, 0.48, 0.32))


static func _hover(m: Model) -> void:
	m.hover_height = 0.05
	var skirt := _paint(m, Color(0.13, 0.13, 0.15))
	var paint := _paint(m, BODY)
	var under := _solid(m, UNDER)
	var fan := _solid(m, BODY)
	var blade := _solid(m, TRIM)
	var r := m.root
	# Юбка — сплюснутая капсула во весь габарит; палуба, надстройка с куполом, вентиляторы на корме.
	var cushion := CapsuleMesh.new()
	cushion.radius = 0.31
	cushion.height = 0.86
	cushion.radial_segments = 16
	cushion.rings = 4
	var sk := _mesh(r, cushion, Vector3(0, 0.13, 0), skirt)
	sk.rotation = Vector3(PI * 0.5, 0, 0)
	sk.scale = Vector3(1, 1, 0.42)
	_box(r, Vector3(0.5, 0.035, 0.74), Vector3(0, 0.265, 0.0), under)      # кант палубы
	_box(r, Vector3(0.46, 0.05, 0.7), Vector3(0, 0.3, 0.0), paint)         # палуба
	_box(r, Vector3(0.36, 0.1, 0.46), Vector3(0, 0.37, -0.02), paint)      # надстройка
	_dome(m, Vector3(0, 0.42, -0.08))
	# Два вентилятора в длинных кожухах на корме; лопасти вращаются.
	for x in [-0.13, 0.13]:
		var ring := TorusMesh.new()
		ring.inner_radius = 0.08
		ring.outer_radius = 0.13
		ring.rings = 12
		ring.ring_segments = 6
		var duct := _mesh(r, ring, Vector3(x, 0.45, 0.3), fan)
		duct.rotation = Vector3(PI * 0.5, 0, 0)
		duct.scale = Vector3(1, 2.4, 1)      # кожух вытянут вдоль оси вентилятора
		var rotor := Node3D.new()
		rotor.position = Vector3(x, 0.45, 0.3)
		rotor.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		r.add_child(rotor)
		_box(rotor, Vector3(0.17, 0.03, 0.01), Vector3.ZERO, blade)
		_box(rotor, Vector3(0.03, 0.17, 0.01), Vector3.ZERO, blade)
		m.spinners.append(rotor)
	_antenna(m, Vector3(0.12, 0.42, 0.14))


## Купол-кабина — у всех классов одинаковый: прозрачная полусфера, в stencil не пишет.
static func _dome(m: Model, pos: Vector3) -> void:
	var glass := StandardMaterial3D.new()
	glass.albedo_color = DOME_GLASS
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.1
	glass.metallic = 0.3
	m.materials.append(glass)
	var dome := SphereMesh.new()
	dome.radius = DOME_R
	dome.height = DOME_R
	dome.is_hemisphere = true
	dome.radial_segments = 12
	dome.rings = 4
	_mesh(m.root, dome, pos, glass)


## Антенна: тонкий штырь с огоньком на конце (основание — pos).
static func _antenna(m: Model, pos: Vector3) -> void:
	var rod := _solid(m, TRIM)
	_cyl(m.root, 0.014, 0.24, pos + Vector3(0, 0.12, 0), rod)
	_box(m.root, Vector3(0.035, 0.035, 0.035), pos + Vector3(0, 0.25, 0), _lamp(m, Color(1.0, 0.35, 0.25)))


## Крупная окрашенная часть: даёт силуэт сквозь препятствия.
static func _paint(m: Model, color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	mat.stencil_mode = BaseMaterial3D.STENCIL_MODE_XRAY
	mat.stencil_color = XRAY_COLOR
	mat.stencil_reference = 1
	m.materials.append(mat)
	return mat


## Деталь: пишет 1 в stencil, чтобы силуэт корпуса не перекрывал её.
static func _solid(m: Model, color: Color, roughness: float = 0.7) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	if roughness < 0.5:
		mat.metallic = 0.3
	mat.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
	mat.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
	mat.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
	mat.stencil_reference = 1
	m.materials.append(mat)
	return mat


static func _lamp(m: Model, color: Color = LAMP) -> StandardMaterial3D:
	var mat := _solid(m, color)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


static func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	var mi := _mesh(parent, b, pos, mat)
	mi.rotation = rot
	return mi


static func _cyl(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material,
		rot: Vector3 = Vector3.ZERO, segments: int = 6) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = segments
	c.rings = 0
	var mi := _mesh(parent, c, pos, mat)
	mi.rotation = rot
	return mi
