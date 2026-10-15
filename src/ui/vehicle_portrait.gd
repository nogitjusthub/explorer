class_name VehiclePortrait
extends SubViewportContainer
## Маленький портрет машины для экранов (итог, рекорды): модель класса в отдельном мире,
## прозрачный фон, медленно вращается. Названий классов игроку не показываем — только силуэт.

const SPIN := 0.8                        ## рад/с

var _model: VehicleModels.Model


func _init(class_id: StringName, px: Vector2i = Vector2i(64, 48)) -> void:
	stretch = true
	size = Vector2(px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.size = px
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.55, 0.75)
	env.ambient_light_energy = 0.6
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	vp.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(30.0), 0.0)
	sun.light_energy = 1.3
	vp.add_child(sun)
	# Невидимая лампа, как в трюме и в мире: варианты шейдеров машины — те же, что прогреты в трюме.
	var lamp := OmniLight3D.new()
	lamp.omni_range = 10.0
	lamp.light_energy = 0.001
	lamp.light_specular = 0.0
	lamp.position = Vector3(0, 3.0, 0)
	vp.add_child(lamp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.3
	var eye := Vector3(2.0, 2.0, 2.0)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, 0.22, 0) - eye), eye)
	vp.add_child(cam)
	_model = VehicleModels.build_plain(class_id)
	_model.root.position.y = _model.hover_height
	vp.add_child(_model.root)


func _process(dt: float) -> void:
	_model.root.rotation.y += SPIN * dt
