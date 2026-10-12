class_name BodyMaterial
extends RefCounted
## Материалы техники и фауны с пиксельным узором (M5, body.gdshaderinc): цвет детали × яркость узора по
## координатам меша. Свет — как у StandardMaterial3D. Техника — вариант со stencil (body_xray.gdshader) и
## силуэтом сквозь препятствия следующим проходом — как STENCIL_MODE_XRAY у StandardMaterial3D.
## Цвет у таких материалов — параметр шейдера: менять через set_color (годится и для StandardMaterial3D).
## Обшивка техники (PLATES) — по граням: меш размечен MeshKit.face_mapped, на гранях — детали (Detail).

enum Pattern { NONE, PLATES, TRACK, SKIRT, SCUTES, HIDE, GROOVES, SCALES, MUD, PEBBLE }
enum Detail { NONE, DOOR, HATCH, VENT }   ## дверь, крышка люка, решётка моторного отсека

const SHADER := preload("res://src/render/shaders/body.gdshader")
const SHADER_XRAY := preload("res://src/render/shaders/body_xray.gdshader")


## Деталь фауны (или техники без stencil).
static func make(color: Color, pattern: Pattern, px: float, roughness: float = 0.8, metallic: float = 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	_setup(m, color, pattern, px, roughness, metallic)
	return m


## Деталь техники: пишет 1 в stencil (силуэт корпуса её не перекрывает); с xray_color — сама даёт силуэт
## сквозь препятствия.
static func stencil(color: Color, pattern: Pattern, px: float, roughness: float = 0.7,
		xray_color: Color = Color(0, 0, 0, 0)) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER_XRAY
	_setup(m, color, pattern, px, roughness, 0.3 if roughness < 0.5 else 0.0)
	if xray_color.a > 0.0:
		m.next_pass = xray_pass(xray_color)
	return m


## Деталь грани для MeshKit.face_mapped: прямоугольник от from до to (координаты меша) на грани с нормалью
## normal; toward — куда ручка двери или петли люка.
static func detail(kind: Detail, normal: Vector3, from: Vector3, to: Vector3,
		toward: Vector3 = Vector3.ZERO) -> Dictionary:
	return {"kind": kind, "normal": normal, "from": from, "to": to, "toward": toward}


## Силуэт сквозь препятствия: без теста глубины, только там, где stencil не 1 (деталь не видна).
static func xray_pass(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.render_priority = 1
	m.set_flag(BaseMaterial3D.FLAG_DISABLE_DEPTH_TEST, true)
	m.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
	m.stencil_flags = BaseMaterial3D.STENCIL_FLAG_READ
	m.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_NOT_EQUAL
	m.stencil_reference = 1
	return m


static func color_of(mat: Material) -> Color:
	if mat is ShaderMaterial:
		return (mat as ShaderMaterial).get_shader_parameter(&"base_color")
	return (mat as BaseMaterial3D).albedo_color


static func set_color(mat: Material, color: Color) -> void:
	if mat is ShaderMaterial:
		(mat as ShaderMaterial).set_shader_parameter(&"base_color", color)
	else:
		(mat as BaseMaterial3D).albedo_color = color


static func _setup(m: ShaderMaterial, color: Color, pattern: Pattern, px: float, roughness: float, metallic: float) -> void:
	m.set_shader_parameter(&"base_color", color)
	m.set_shader_parameter(&"pattern", pattern)
	m.set_shader_parameter(&"px", px)
	m.set_shader_parameter(&"roughness", roughness)
	m.set_shader_parameter(&"metallic", metallic)
