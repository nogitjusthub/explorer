class_name Warmup
extends Node3D
## Прогрев шейдеров (ARCHITECTURE §10). В Compatibility — и особенно в браузере — материал компилируется
## при первом показе: первый смерч, червь или Несса заметно дёргали кадр. На старте (игрок ещё в трюме)
## отдельная невидимая камера (SubViewport с общим миром) по одному образцу за кадр снимает копии всего,
## что появится позже: эффекты погоды и угроз, существ, водоворот, челноки, капсулу десанта — со всеми
## частями (и спрятанными до поры) и частицами, под точечным светом (у освещённых им материалов свой
## вариант шейдера). Образцы — глубоко под миром, в кадр игрока не попадают. Компиляция переносится на
## старт и размазывается по кадрам; затем узел убирает себя.

const HOLD_FRAMES := 2                   ## кадров на образец
const DEPTH := 300.0                     ## образцы — на столько ниже точки старта
const VIEW_SIZE := 30.0                  ## тайлов в кадре камеры прогрева — с запасом: червь под землёй, шея Нессы, смерч

var at := Vector3.ZERO                   ## точка старта (суша, загружена)
var rules: BalanceRules
var vehicle: Vehicle
var query: TerrainQuery
var terrain: TerrainData
var pickups: PickupField
var noise: NoiseField

var _makers: Array[Callable] = []
var _sample: Node3D
var _hold := 0
var _spot := Vector3.ZERO                ## куда смотрит камера прогрева


func _ready() -> void:
	name = "Warmup"
	_spot = at + Vector3(0.0, -DEPTH, 0.0)
	var view := SubViewport.new()
	view.size = Vector2i(128, 128)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = VIEW_SIZE
	cam.near = 0.1
	cam.far = 120.0
	view.add_child(cam)
	cam.global_transform = Transform3D(Basis.looking_at(Vector3(0, -1, -1)), _spot + Vector3(0, 30, 30))
	var light := OmniLight3D.new()
	light.light_energy = 0.5
	light.omni_range = 6.0
	light.shadow_enabled = false
	light.position = _spot + Vector3(0, 1.5, 0)
	add_child(light)
	_makers = [_basics, _tornado, _worm, _hoppers, _shellback, _shark, _nessie, _stargazer,
			_whirlpool, _shuttle.bind(ShuttleCraft.Kind.MAIN), _shuttle.bind(ShuttleCraft.Kind.EMERGENCY), _drop_pod]


func _process(_dt: float) -> void:
	if _hold > 0:
		_hold -= 1
		return
	if _sample != null:
		_sample.queue_free()
		_sample = null
	if _makers.is_empty():
		queue_free()
		return
	var make: Callable = _makers.pop_front()
	_sample = make.call()
	if _sample == null:
		return
	_sample.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if _sample.get_parent() == null:
		add_child(_sample)
	_reveal(_sample)
	_sample.position += _spot - at       # образец строился у точки старта — уводим под мир, к камере
	_gather(_sample)
	_hold = HOLD_FRAMES


## Всё, что образец прячет до поры (тело червя, шея Нессы, пламя, знаки), — видно; частицы — летят.
func _reveal(n: Node) -> void:
	if n is Node3D:
		(n as Node3D).visible = true
	if n is CPUParticles3D:
		(n as CPUParticles3D).emitting = true
	for c in n.get_children():
		_reveal(c)


## Части, которые образец ещё не расставил по месту (тело червя, шея Нессы — до охоты стоят в начале
## координат), — переносим в кадр камеры прогрева, иначе они отсекаются и не компилируются.
func _gather(n: Node) -> void:
	if n is GeometryInstance3D:
		var g := n as GeometryInstance3D
		if g.global_position.distance_to(_spot) > VIEW_SIZE * 0.4:
			g.global_position = _spot + Vector3(0.0, 0.5, 0.0)
	for c in n.get_children():
		_gather(c)


func _at2() -> Vector2:
	return Vector2(at.x, at.z)


func _creature(c: Creature) -> Creature:
	c.rules = rules
	c.vehicle = vehicle
	c.query = query
	c.terrain = terrain
	c.noise = noise
	c.rng = RandomNumberGenerator.new()
	return c


## Мелочь эффектов: слои облаков и газа, прозрачные и двусторонние материалы, знак удара молнии, знак
## посадки, водоворот и пена (свои шейдеры), частицы-«билборды».
func _basics() -> Node3D:
	var root := Node3D.new()
	root.position = at
	var layers := MurkLayers.new()
	root.add_child(layers)
	layers.add_layer(Color.WHITE, 0.0, 1.0, 0.1, Vector2.ZERO)
	layers.add_layer(Color.WHITE, 0.0, 0.0, 0.1, Vector2.ZERO, 0, true)
	var unshaded := StandardMaterial3D.new()
	unshaded.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var glow := unshaded.duplicate() as StandardMaterial3D
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.albedo_color = Color(1, 1, 1, 0.5)
	var two_sided := glow.duplicate() as StandardMaterial3D     # воронка смерча, телеграфы, клубы
	two_sided.cull_mode = BaseMaterial3D.CULL_DISABLED
	var materials: Array[Material] = [unshaded, glow, two_sided]
	var elmo := ShaderMaterial.new()                             # знак удара молнии
	elmo.shader = load("res://src/render/shaders/st_elmo.gdshader")
	elmo.set_shader_parameter("intensity", 0.5)
	materials.append(elmo)
	for path in ["res://src/render/shaders/landing_hazard.gdshader", "res://src/render/shaders/whirlpool.gdshader",
			"res://src/render/shaders/foam_strip.gdshader"]:
		var sm := ShaderMaterial.new()
		sm.shader = load(path)
		sm.render_priority = 1
		materials.append(sm)
	for i in materials.size():
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2.ONE * 0.5
		mi.mesh = q
		mi.material_override = materials[i]
		mi.position = Vector3(i * 0.6 - 2.0, 0.5, 0)
		root.add_child(mi)
	for billboard_alpha in [false, true]:
		var p := CPUParticles3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * 0.2
		var m := (glow if billboard_alpha else unshaded).duplicate() as StandardMaterial3D
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		quad.material = m
		p.mesh = quad
		p.amount = 4
		p.position = Vector3(1.5 + float(billboard_alpha), 0.5, 0)
		root.add_child(p)
	return root


func _tornado() -> Node3D:
	var t := Tornado.new()
	t.rules = rules
	t.vehicle = vehicle
	t.query = query
	t.terrain = terrain
	t.pickups = pickups
	t.rng = RandomNumberGenerator.new()
	add_child(t)                        # звук и расстановка — в дереве сцены
	t.begin(_at2())
	return t


func _worm() -> Node3D:
	var w := _creature(Worm.new()) as Worm
	add_child(w)
	w.setup(_at2())
	return w


func _hoppers() -> Node3D:
	var h := _creature(HopperPack.new()) as HopperPack
	add_child(h)
	h.setup(_at2(), rules.pack_max)
	return h


func _shellback() -> Node3D:
	var s := _creature(Shellback.new()) as Shellback
	add_child(s)
	s.setup(_at2())
	return s


func _shark() -> Node3D:
	var s := _creature(MireShark.new()) as MireShark
	add_child(s)
	s.setup(_at2())
	return s


func _nessie() -> Node3D:
	var n := _creature(LakeMonster.new()) as LakeMonster
	add_child(n)
	n.setup(_at2())
	return n


func _stargazer() -> Node3D:
	var s := _creature(Stargazer.new()) as Stargazer
	add_child(s)
	s.setup(_at2())
	return s


func _whirlpool() -> Node3D:
	var w := Whirlpool.new()
	w.rules = rules
	w.vehicle = vehicle
	w.query = query
	w.rng = RandomNumberGenerator.new()
	add_child(w)
	w.begin(_at2())
	w.position = at                     # на суше у воронки нет зеркала воды — ставим на точку старта
	return w


func _shuttle(kind: ShuttleCraft.Kind) -> Node3D:
	var s := ShuttleCraft.new(kind, rules.shuttle_zone_r)
	add_child(s)
	s.descend(at)
	s.touch_down()
	return s


func _drop_pod() -> Node3D:
	var pod := DropPod.new()
	add_child(pod)
	pod.start(at)
	pod.preview()
	return pod
