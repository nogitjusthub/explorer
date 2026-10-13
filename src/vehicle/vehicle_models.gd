class_name VehicleModels
extends RefCounted
## Модели техники из примитивов: перед — по −Z, размеры — в тайлах. Единый габарит ~0,85 × 0,65 тайла,
## один цвет экспедиции на всех, крупная ходовая, немного деталей. У всех одинаковый стеклянный
## купол-кабина (полусфера диаметром 0,3) и антенна.
## Ровер — квадратный корпус на шести колёсах почти вплотную, спереди бампер из тонких труб.
## Танк — гусеничный транспортёр (design_references: ТМ-140, ГАЗ-71): купол спереди — самая высокая
## точка, кузов сзади ниже, чтобы перед читался сразу; спереди кенгурятник по мотивам Humvee.
## Ховер — судно на воздушной подушке (Griffon): крупная чёрная юбка, палуба с надстройкой — прямой нос со
## скосами 60° по бокам, два вентилятора в кожухах.
##
## Для анимации хода (VehicleRide): ходовая (колёса, гусеницы) — прямо в root, корпус со всем
## остальным — в подрессоренном узле body, антенна — на шарнире antenna у своего основания.
##
## Силуэт сквозь стены: крупные окрашенные части — stencil XRAY (силуэт рисуется там, где в stencil
## не 1), остальные непрозрачные детали пишут в stencil ту же 1 — иначе силуэт корпуса ложился бы
## поверх них, и они казались бы прозрачными.
##
## Пиксельные узоры (M5, BodyMaterial): обшивка — по граням (MeshKit.face_mapped): кромка в пиксель,
## двери по бортам, крышки багажных люков, решётки моторных отсеков — симметрично по сетке грани;
## гусеницы — траки, юбка ховера — секции.

const XRAY_COLOR := Color(1.0, 0.75, 0.25, 0.75)
const TRIM := Color(0.1, 0.1, 0.12)
const RUBBER := Color(0.12, 0.11, 0.13)
const LAMP := Color(1.0, 0.95, 0.7)
const BODY := Color(0.92, 0.52, 0.16)       ## цвет экспедиции — общий для всех классов
const UNDER := Color(0.24, 0.24, 0.27)      ## днище, кант
const METAL := Color(0.58, 0.55, 0.5)       ## диски и катки — грязно-серые
const DOME_GLASS := Color(0.4, 0.82, 0.98, 0.7)
const DOME_R := 0.15
const ROD_R := 0.014                       ## толщина антенны — по ней трубы бамперов и кенгурятника
const BEACON := Color(1.0, 0.35, 0.25)       ## огонёк антенны: ярко — вызов аварийного челнока
const BEACON_DIM := Color(0.5, 0.15, 0.11)   ## обычно тлеет
const BOW_DEG := 60.0                      ## скосы носа ховера от поперечной линии
const PX := Grid.ART_PX                    ## пиксель узора — тот же, что у рельефа и всего мира


## Собранная модель: корень, все материалы (для потемнения при гибели) и вращающиеся части.
class Model:
	extends RefCounted
	var root: Node3D
	var body: Node3D                        ## корпус на подвеске (тряска хода); дочерний root, в покое — без смещения
	var antenna: Node3D                     ## шарнир у основания антенны (качается хлыстом), дочерний body
	var materials: Array[Material] = []        ## StandardMaterial3D и BodyMaterial (цвет — BodyMaterial.set_color)
	var spinners: Array[Node3D] = []        ## вращаются вокруг своей оси Z (вентиляторы)
	var hover_height := 0.0                 ## модель парит над поверхностью (ховер)
	var beacon: StandardMaterial3D          ## огонёк на конце антенны (мигает, пока летит аварийный челнок)
	var beacon_pos := Vector3.ZERO          ## его точка в координатах antenna


## Без силуэта сквозь препятствия (экраны вне игры: трюм, портреты) — stencil не нужен.
static func build_plain(id: StringName) -> Model:
	var m := build(id)
	for mat in m.materials:
		if mat is ShaderMaterial:
			mat.next_pass = null                  # запись в stencil без силуэта ничего не рисует
		else:
			(mat as BaseMaterial3D).stencil_mode = BaseMaterial3D.STENCIL_MODE_DISABLED
	return m


static func build(id: StringName) -> Model:
	var m := Model.new()
	m.root = Node3D.new()
	m.root.name = "Model"
	m.body = Node3D.new()
	m.body.name = "Body"
	m.root.add_child(m.body)
	match id:
		&"tank":
			_tank(m)
		&"hover":
			_hover(m)
		_:
			_rover(m)
	BodyMaterial.map_faces(m.root)
	return m


static func _rover(m: Model) -> void:
	var paint := _paint(m, BODY)
	var under := _solid(m, UNDER)
	var tire := _solid(m, RUBBER)
	var hub := _solid(m, METAL)
	var lamp := _lamp(m)
	var b := m.body
	# Квадратный корпус на шести колёсах почти вплотную, купол-кабина.
	for x in [-0.25, 0.25]:
		for z in [-0.28, 0.0, 0.28]:
			_cyl(m.root, 0.13, 0.12, Vector3(x, 0.13, z), tire, Vector3(0, 0, PI * 0.5), 8)
			_cyl(m.root, 0.05, 0.126, Vector3(x, 0.13, z), hub, Vector3(0, 0, PI * 0.5), 6)
	_box(b, Vector3(0.34, 0.08, 0.62), Vector3(0, 0.17, 0.0), under)
	var hull := _box(b, Vector3(0.44, 0.2, 0.64), Vector3(0, 0.29, 0.0), paint)
	# Двери под куполом, багажник в корме (петли сверху), решётка мотора на крыше за куполом.
	var details := _doors(0.22, -0.2, 0.02, -0.065, 0.065)
	details.append(BodyMaterial.detail(BodyMaterial.Detail.HATCH, Vector3.BACK,
			Vector3(-0.13, -0.065, 0.32), Vector3(0.13, 0.065, 0.32), Vector3.UP))
	details.append(BodyMaterial.detail(BodyMaterial.Detail.VENT, Vector3.UP,
			Vector3(-0.12, 0.1, 0.1), Vector3(0.12, 0.1, 0.28)))
	hull.set_meta(&"details", details)
	_dome(m, Vector3(0, 0.39, -0.08))
	for x in [-0.12, 0.12]:
		_box(b, Vector3(0.06, 0.04, 0.02), Vector3(x, 0.3, -0.325), lamp)
	# Бампер: перекладина между передними колёсами, две стойки, крепления к корпусу.
	var bar := _solid(m, UNDER, 0.4)
	const BZ := -0.4
	_rod(b, Vector3(-0.18, 0.2, BZ), Vector3(0.18, 0.2, BZ), bar)
	for x in [-0.06, 0.06]:
		_rod(b, Vector3(x, 0.15, BZ), Vector3(x, 0.29, BZ), bar)
		_rod(b, Vector3(x, 0.26, BZ), Vector3(x, 0.26, -0.32), bar)
	_antenna(m, Vector3(0.15, 0.39, 0.22))


static func _tank(m: Model) -> void:
	var paint := _paint(m, BODY)
	var track := _patterned(m, RUBBER, BodyMaterial.Pattern.TRACK)
	var wheel := _solid(m, METAL)
	var lamp := _lamp(m)
	var r := m.body
	# Купол-кабина спереди — самая высокая точка, кузов сзади ниже купола: перед читается сразу.
	const TRACK_W := 0.15
	const WHEEL_W := 0.03
	for x in [-0.245, 0.245]:
		_side_prism(m.root, _octagon(0.18, 0.84, 0.06), x, TRACK_W, track)   # гусеница: углы срезаны под 45°
		var side := signf(x)
		# Катки равномерно, крайние — у концов гусеницы; утоплены в ленту, наружу — едва (как диски ровера).
		var wx: float = x + side * (TRACK_W * 0.5 + 0.003 - WHEEL_W * 0.5)
		for z in [-0.33, -0.11, 0.11, 0.33]:
			_cyl(m.root, 0.065, WHEEL_W, Vector3(wx, 0.085, z), wheel, Vector3(0, 0, PI * 0.5), 8)
	_box(r, Vector3(0.62, 0.03, 0.8), Vector3(0, 0.195, 0.0), paint)       # полки над гусеницами
	var hull := _box(r, Vector3(0.4, 0.19, 0.82), Vector3(0, 0.275, 0.0), paint)   # корпус
	# Двери под куполом над полками, решётка мотора в корме.
	var details := _doors(0.2, -0.33, -0.1, -0.055, 0.055)
	details.append(BodyMaterial.detail(BodyMaterial.Detail.VENT, Vector3.BACK,
			Vector3(-0.12, -0.04, 0.41), Vector3(0.12, 0.04, 0.41)))
	hull.set_meta(&"details", details)
	_dome(m, Vector3(0, 0.37, -0.2))
	# Трюм — вровень с кормой, ниже купола; на крыше — люк, петли спереди.
	var hold := _box(r, Vector3(0.42, 0.11, 0.38), Vector3(0, 0.425, 0.22), paint)
	hold.set_meta(&"details", [BodyMaterial.detail(BodyMaterial.Detail.HATCH, Vector3.UP,
			Vector3(-0.1, 0.055, -0.13), Vector3(0.1, 0.055, 0.13), Vector3.FORWARD)])
	for x in [-0.12, 0.12]:
		_box(r, Vector3(0.06, 0.04, 0.02), Vector3(x, 0.3, -0.415), lamp)
	# Кенгурятник как у Humvee (design_references/tank/front_guard*): плоская прямоугольная рамка перед
	# корпусом, верх — вровень с крышей корпуса; вертикальные планки, две широкие пластины креплений
	# выступают вперёд на толщину трубы и уходят ниже рамки. Трубы — толщиной в антенну.
	var bar := _solid(m, UNDER, 0.4)
	const GZ := -0.47                  # плоскость рамки
	const GX := 0.245                  # полуширина: края — по середине гусениц
	const GTOP := 0.37                 # крыша корпуса
	const GY1 := GTOP - ROD_R          # ось верхней трубы: её верх — вровень с корпусом
	const GY0 := GY1 - 0.141           # высота рамки
	const PLATE_H := 0.205             # пластины — от крыши корпуса вниз, ниже рамки
	for y in [GY0, GY1]:
		_rod(r, Vector3(-GX, y, GZ), Vector3(GX, y, GZ), bar)
	for x in [-GX, -0.05, 0.05, GX]:                          # торцы и планки (фары — между средними и пластинами)
		_rod(r, Vector3(x, GY0, GZ), Vector3(x, GY1, GZ), bar)
	for s: float in [-1.0, 1.0]:
		_box(r, Vector3(0.05, PLATE_H, ROD_R * 2.0), Vector3(0.17 * s, GTOP - PLATE_H * 0.5, GZ - ROD_R * 2.0), bar)
		_rod(r, Vector3(0.17 * s, 0.2, GZ), Vector3(0.17 * s, 0.2, -0.41), bar)   # крепление к корпусу (за пластиной)
	_antenna(m, Vector3(0.14, 0.48, 0.32))


static func _hover(m: Model) -> void:
	m.hover_height = 0.05
	var skirt := _paint(m, Color(0.13, 0.13, 0.15), BodyMaterial.Pattern.SKIRT)
	var paint := _paint(m, BODY)
	var under := _solid(m, UNDER)
	var fan := _solid(m, BODY)
	var blade := _solid(m, TRIM)
	var r := m.body                       # юбка — часть корпуса: ховер колышется и кренится целиком
	# Юбка — сплюснутая капсула во весь габарит; палуба, надстройка с куполом, вентиляторы на корме.
	var cushion := CapsuleMesh.new()
	cushion.radius = 0.34
	cushion.height = 0.94
	cushion.radial_segments = 12
	cushion.rings = 2
	var sk := _mesh(r, cushion, Vector3(0, 0.15, 0), skirt)
	sk.rotation = Vector3(PI * 0.5, 0, 0)
	sk.scale = Vector3(1, 1, 0.45)
	# Корпус — призмы с прямым носом и скосами по бокам (BOW_DEG от поперечной линии).
	MeshKit.prism(r, _bow(0.25, -0.37, 0.37, 0.11), 0.27, 0.035, under)          # кант палубы
	MeshKit.prism(r, _bow(0.23, -0.35, 0.35, 0.1), 0.3, 0.05, paint)              # палуба
	# Надстройка; на крыше за куполом — люк, петли спереди.
	var cabin := MeshKit.prism(r, _bow(0.18, -0.25, 0.21, 0.09), 0.35, 0.1, paint)
	cabin.set_meta(&"details", [BodyMaterial.detail(BodyMaterial.Detail.HATCH, Vector3.UP,
			Vector3(-0.08, 0.45, 0.07), Vector3(0.08, 0.45, 0.17), Vector3.FORWARD)])
	_dome(m, Vector3(0, 0.45, -0.08))
	# Два вентилятора в длинных кожухах на корме; лопасти вращаются.
	for x in [-0.13, 0.13]:
		var ring := TorusMesh.new()
		ring.inner_radius = 0.08
		ring.outer_radius = 0.13
		ring.rings = 12
		ring.ring_segments = 4
		var duct := _mesh(r, ring, Vector3(x, 0.47, 0.3), fan)
		duct.rotation = Vector3(PI * 0.5, 0, 0)
		duct.scale = Vector3(1, 2.4, 1)      # кожух вытянут вдоль оси вентилятора
		var rotor := Node3D.new()
		rotor.position = Vector3(x, 0.47, 0.3)
		rotor.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		r.add_child(rotor)
		_box(rotor, Vector3(0.17, 0.03, 0.01), Vector3.ZERO, blade)
		_box(rotor, Vector3(0.03, 0.17, 0.01), Vector3.ZERO, blade)
		m.spinners.append(rotor)
	_antenna(m, Vector3(0.12, 0.45, 0.14))


## Двери по обоим бортам коробки полушириной hx: от z0 до z1, по высоте от y0 до y1 (координаты коробки);
## ручка — к корме.
static func _doors(hx: float, z0: float, z1: float, y0: float, y1: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s: float in [-1.0, 1.0]:
		out.append(BodyMaterial.detail(BodyMaterial.Detail.DOOR, Vector3(s, 0, 0), Vector3(s * hx, y0, z0),
				Vector3(s * hx, y1, z1), Vector3.BACK))
	return out


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
	dome.radial_segments = 10
	dome.rings = 3
	_mesh(m.body, dome, pos, glass)


## Антенна: тонкий штырь с огоньком на конце; шарнир m.antenna — в основании pos (на корпусе).
static func _antenna(m: Model, pos: Vector3) -> void:
	m.antenna = Node3D.new()
	m.antenna.name = "Antenna"
	m.antenna.position = pos
	m.body.add_child(m.antenna)
	var rod := _solid(m, TRIM)
	_cyl(m.antenna, ROD_R, 0.24, Vector3(0, 0.12, 0), rod)
	m.beacon = _lamp(m, BEACON_DIM)
	m.beacon_pos = Vector3(0, 0.25, 0)
	_box(m.antenna, Vector3(0.035, 0.035, 0.035), m.beacon_pos, m.beacon)


## Труба от a до b (толщиной в антенну).
static func _rod(parent: Node3D, a: Vector3, b: Vector3, mat: Material, radius: float = ROD_R) -> MeshInstance3D:
	if b.y < a.y:
		var tmp := a
		a = b
		b = tmp
	var d := b - a
	var mi := _cyl(parent, radius, d.length() + radius, (a + b) * 0.5, mat)
	mi.basis = Basis(Quaternion(Vector3.UP, d.normalized()))
	return mi


## Контур палубы с носом: прямой нос шириной 2·nose, по бокам скосы под BOW_DEG к поперечной линии.
## Точки — (x, z), перед — по −Z.
static func _bow(half_w: float, z_front: float, z_back: float, nose: float) -> PackedVector2Array:
	var d := (half_w - nose) * tan(deg_to_rad(BOW_DEG))
	return PackedVector2Array([Vector2(-nose, z_front), Vector2(nose, z_front), Vector2(half_w, z_front + d),
			Vector2(half_w, z_back), Vector2(-half_w, z_back), Vector2(-half_w, z_front + d)])


## Профиль сбоку (y, z) высотой h от земли и длиной len по центру, углы срезаны на c под 45°.
static func _octagon(h: float, len: float, c: float) -> PackedVector2Array:
	var l := len * 0.5
	return PackedVector2Array([Vector2(c, -l), Vector2(h - c, -l), Vector2(h, -l + c), Vector2(h, l - c),
			Vector2(h - c, l), Vector2(c, l), Vector2(0, l - c), Vector2(0, -l + c)])


## Призма по профилю сбоку (y, z), шириной width по x вокруг x_center: MeshKit.prism, повёрнутая так,
## что её ось выдавливания смотрит вбок.
static func _side_prism(parent: Node3D, profile: PackedVector2Array, x_center: float, width: float,
		mat: Material) -> MeshInstance3D:
	var mi := MeshKit.prism(parent, profile, -width * 0.5, width, mat)
	mi.rotation = Vector3(0, 0, PI * 0.5)     # локальные (x, y, z) → мировые (−y, x, z)
	mi.position = Vector3(x_center, 0, 0)
	return mi


## Крупная окрашенная часть: даёт силуэт сквозь препятствия.
static func _paint(m: Model, color: Color, pattern := BodyMaterial.Pattern.PLATES) -> ShaderMaterial:
	var mat := BodyMaterial.stencil(color, pattern, PX, 0.7, XRAY_COLOR)
	m.materials.append(mat)
	return mat


## Деталь с узором: как _solid, пишет 1 в stencil.
static func _patterned(m: Model, color: Color, pattern: BodyMaterial.Pattern) -> ShaderMaterial:
	var mat := BodyMaterial.stencil(color, pattern, PX)
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
