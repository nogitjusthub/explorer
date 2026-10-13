class_name MurkLayers
extends Node3D
## Объём непогоды: несколько полупрозрачных слоёв облачного шума (fog_layer*.gdshader) над землёй.
## Узор привязан к миру и течёт, слои на разной высоте с разным масштабом и дрейфом — при движении
## камеры они смещаются друг относительно друга, получается объём. Плотность и край массы берёт шейдер
## из глобальных параметров погоды (или грозового фронта), так что масса заползает в кадр сама.
## Дыра вокруг машины сдвинута для каждого слоя к камере на его высоту — на экране она совпадает с машиной.

const SIZE := 90.0                       ## сторона слоя, тайлов — с запасом на весь экран

var _layers: Array[Dictionary] = []      ## {mi, mat, h, absolute, color}


func _init() -> void:
	name = "MurkLayers"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## Слой: height — над машиной (или абсолютная мировая высота, если absolute); source 0 — масса
## погоды, 1 — тучи грозы; depth_test — слой прячется за рельефом (кислотный газ в низинах).
func add_layer(color: Color, strength: float, height: float, scale: float, drift: Vector2,
		source: int = 0, depth_test: bool = false, absolute: bool = false) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(SIZE, SIZE)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/render/shaders/fog_layer_depth.gdshader" if depth_test else "res://src/render/shaders/fog_layer.gdshader")
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("strength", strength)
	mat.set_shader_parameter("scale", scale)
	mat.set_shader_parameter("drift", drift)
	mat.set_shader_parameter("source", source)
	mat.render_priority = _layers.size()
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 20.0
	add_child(mi)
	_layers.append({"mi": mi, "mat": mat, "h": height, "absolute": absolute, "color": color})


## Подсветка слоёв (зарница в тучах): 0 — обычный цвет, 1 — бело-голубой.
func set_flash(amount: float) -> void:
	for l in _layers:
		var base: Color = l["color"]
		(l["mat"] as ShaderMaterial).set_shader_parameter("color", base.lerp(Color(0.8, 0.86, 1.0), clampf(amount, 0.0, 1.0)))


## Каждый кадр: слои следуют за машиной, дыра — под машиной на экране; fade — общее проявление.
func update(viewer: Vector3, hole_r: float, fade: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var back := Vector2(0.0, 0.0)
	if cam != null:
		var z := cam.global_basis.z
		back = Vector2(z.x, z.z) / maxf(z.y, 0.01)          # на единицу высоты — ctg наклона камеры
	for l in _layers:
		var y: float = l["h"] if l["absolute"] else viewer.y + l["h"]
		(l["mi"] as MeshInstance3D).position = Vector3(viewer.x, y, viewer.z)
		var mat: ShaderMaterial = l["mat"]
		# Камера смотрит под углом φ: точка на высоте h над землёй видна там же, где земля на h·ctg φ ближе к камере.
		mat.set_shader_parameter("hole_offset", back * (y - viewer.y))
		mat.set_shader_parameter("hole_r", hole_r)
		mat.set_shader_parameter("fade", fade)
