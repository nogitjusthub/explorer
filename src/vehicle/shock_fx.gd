class_name ShockFx
extends MeshInstance3D
## Разряд по машине (молния, электрошок, GDD §5.6), пока управление наоборот: по корпусу бегут длинные
## ломаные дуги — белая сердцевина в голубом ореоле, лентами к камере, новые каждые ARC_EVERY_S; корпус
## вспыхивает белым (наложение поверх материалов модели) — сразу ярко, потом неровным мерцанием.
## Материалы — те же, что у эффектов (без освещения, с прозрачностью): шейдеры уже прогреты.

const ARCS := 2
const ARC_EVERY_S := 0.07
const POINTS := 6                        ## изломов в дуге (с концами)
const CORE_W := 0.045
const GLOW_W := 0.14
const CORE_COLOR := Color(1.0, 1.0, 1.0)
const GLOW_COLOR := Color(0.3, 0.65, 1.0, 0.85)
const FLASH_COLOR := Color(1.0, 1.0, 1.0)
const FIRST_FLASH_S := 0.15              ## первая вспышка — сплошная
const FLASH_CHANCE := 0.4                ## дальше — вспышка на такой доле смен дуг
const HULL := Vector3(0.4, 0.24, 0.5)    ## полуоси эллипсоида, по которому бегут дуги (чуть больше корпуса)
const CENTER := Vector3(0, 0.26, 0)

var _mesh := ImmediateMesh.new()
var _core := StandardMaterial3D.new()
var _glow := StandardMaterial3D.new()
var _flash := StandardMaterial3D.new()
var _arcs: Array[PackedVector3Array] = []
var _flashed: Array[GeometryInstance3D] = []
var _active := false
var _age := 0.0
var _timer := 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	name = "ShockFx"
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core.albedo_color = CORE_COLOR
	_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow.albedo_color = GLOW_COLOR
	_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash.albedo_color = Color(FLASH_COLOR, 0.0)
	_rng.randomize()


## Разряд начался или кончился; model — корень модели машины (на её детали ложится белая вспышка).
func set_active(on: bool, model: Node3D) -> void:
	if on == _active:
		return
	_active = on
	_age = 0.0
	_timer = 0.0
	_unflash()
	if on:
		_collect(model)
		for g in _flashed:
			g.material_overlay = _flash
	else:
		_arcs.clear()
		_mesh.clear_surfaces()


func _process(dt: float) -> void:
	if not _active:
		return
	_age += dt
	_timer -= dt
	if _timer <= 0.0:
		_timer = ARC_EVERY_S
		_arcs.clear()
		for _i in ARCS:
			_arcs.append(_arc())
		var on := _age < FIRST_FLASH_S or _rng.randf() < FLASH_CHANCE
		_flash.albedo_color.a = (0.75 if _age < FIRST_FLASH_S else _rng.randf_range(0.35, 0.6)) if on else 0.0
	_draw()


## Дуга: от случайной точки верха корпуса к соседней — по эллипсоиду, с изломами наружу и вбок.
func _arc() -> PackedVector3Array:
	var a := _on_hull()
	var b := _on_hull()
	for _i in 8:
		if a.distance_to(b) > 0.5:
			break
		b = _on_hull()
	var pts := PackedVector3Array()
	for i in POINTS:
		var k := float(i) / (POINTS - 1)
		var dir := (a.lerp(b, k) - CENTER) / HULL
		var p := CENTER + dir.normalized() * HULL
		if i > 0 and i < POINTS - 1:
			p += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.5, 1), _rng.randf_range(-1, 1)) * 0.07
		pts.append(p)
	return pts


func _on_hull() -> Vector3:
	var d := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.2, 1), _rng.randf_range(-1, 1))
	if d.length_squared() < 0.01:
		d = Vector3.UP
	return CENTER + d.normalized() * HULL


## Ленты дуг развёрнуты к камере: ореол (шире, прозрачный), поверх — сердцевина.
func _draw() -> void:
	_mesh.clear_surfaces()
	if _arcs.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	var view := Vector3(0, -1, -1).normalized()
	if cam != null:
		view = -cam.global_basis.z
	view = (global_basis.inverse() * view).normalized()
	for layer in [[_glow, GLOW_W], [_core, CORE_W]]:
		var half: float = layer[1] * 0.5
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, layer[0])
		for pts in _arcs:
			for i in pts.size() - 1:
				var a: Vector3 = pts[i]
				var b: Vector3 = pts[i + 1]
				var side := (b - a).cross(view).normalized() * half
				for v in [a - side, a + side, b + side, a - side, b + side, b - side]:
					_mesh.surface_add_vertex(v)
		_mesh.surface_end()


func _collect(n: Node) -> void:
	if n == null:
		return
	if n is GeometryInstance3D:
		_flashed.append(n)
	for c in n.get_children():
		_collect(c)


func _unflash() -> void:
	for g in _flashed:
		if is_instance_valid(g):
			g.material_overlay = null
	_flashed.clear()
