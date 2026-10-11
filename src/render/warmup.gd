class_name Warmup
extends Node3D
## Прогрев шейдеров эффектов (ARCHITECTURE §10): в Compatibility материал компилируется при первом
## показе, и первая гроза или туман дёргали кадр. На старте на несколько кадров рядом с машиной
## показываются невидимые копии: слои облачного шума (оба шейдера), разряд, телеграф-круг, знак посадки
## челнока, водоворот, пена Нессы, искры и вспышка света — потом узел убирает себя.

const FRAMES := 4

var at := Vector3.ZERO

var _frames := 0


func _ready() -> void:
	name = "Warmup"
	position = at
	var layers := MurkLayers.new()
	add_child(layers)
	layers.add_layer(Color.WHITE, 0.0, 1.0, 0.1, Vector2.ZERO)
	layers.add_layer(Color.WHITE, 0.0, 0.0, 0.1, Vector2.ZERO, 0, true)
	var unshaded := StandardMaterial3D.new()
	unshaded.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var glow := unshaded.duplicate() as StandardMaterial3D
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.albedo_color = Color(1, 1, 1, 0.01)
	var two_sided := glow.duplicate() as StandardMaterial3D     # воронка смерча, телеграфы, клубы
	two_sided.cull_mode = BaseMaterial3D.CULL_DISABLED
	for mat in [unshaded, glow, two_sided]:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3.ONE * 0.01
		mi.mesh = box
		mi.material_override = mat
		mi.position = Vector3(0, -0.5, 0)
		add_child(mi)
	var elmo := MeshInstance3D.new()                          # знак удара молнии
	var eq := QuadMesh.new()
	eq.size = Vector2.ONE * 0.01
	elmo.mesh = eq
	var em := ShaderMaterial.new()
	em.shader = load("res://src/render/shaders/st_elmo.gdshader")
	em.set_shader_parameter("intensity", 0.0)
	elmo.material_override = em
	add_child(elmo)
	# Знак посадки челнока, водоворот, пена Нессы — свои шейдеры, первый показ иначе дёргает кадр.
	for path in ["res://src/render/shaders/landing_hazard.gdshader", "res://src/render/shaders/whirlpool.gdshader",
			"res://src/render/shaders/foam_strip.gdshader"]:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2.ONE * 0.01
		mi.mesh = q
		var sm := ShaderMaterial.new()
		sm.shader = load(path)
		mi.material_override = sm
		mi.position = Vector3(0, -0.5, 0)
		add_child(mi)
	var light := OmniLight3D.new()
	light.light_energy = 0.01
	light.omni_range = 2.0
	light.position = Vector3(0, 0.5, 0)
	add_child(light)
	var sparks := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.01
	var billboard := unshaded.duplicate() as StandardMaterial3D
	billboard.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = billboard
	sparks.mesh = quad
	sparks.amount = 1
	add_child(sparks)


func _process(_dt: float) -> void:
	_frames += 1
	if _frames >= FRAMES:
		queue_free()
