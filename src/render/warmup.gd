class_name Warmup
extends Node3D
## Прогрев шейдеров (ARCHITECTURE §10). В Compatibility — и особенно в браузере — материал компилируется
## при первом показе: первый червь в браузере вешал игру на пару секунд. На старте (игрок ещё в трюме)
## отдельная невидимая камера (SubViewport с общим миром) по одному образцу снимает копии всего, что
## появится позже: эффекты погоды и угроз, существ, водоворот, челноки, капсулу десанта, все три машины —
## со всеми частями (и спрятанными до поры) и частицами. Вариант шейдера зависит от того, задевает ли объект
## точечный свет; в мире всегда горит фонарь машины (GameFlow, LAMP_*) — поэтому образцы снимаются только под
## точечным светом (свой свет камеры прогрева на весь её кадр), без второй половины «без света». Образцы —
## глубоко под миром, в кадр игрока не попадают; их материалы остаются в ShaderCache, иначе Godot выбросил бы
## шейдеры вместе с образцом. Последним, когда мир вокруг старта догружен (look_at_world), камера смотрит на
## настоящий рельеф, воду, деревья и находки. Затем finished, узел убирает себя; экран загрузки ждёт его.

signal finished

const HOLD_FRAMES := 2                   ## кадров на образец…
## …и потом столько кадров подряд без программ в фоновой сборке (веб, ShaderCache.pending_programs): пока
## основная программа объекта не готова, Godot не заказывает его следующие проходы (свет солнца с тенью) —
## образец держим, пока не соберётся всё
const QUIET_FRAMES := 2
const DEPTH := 300.0                     ## образцы — на столько ниже точки старта
const VIEW_SIZE := 30.0                  ## тайлов в кадре камеры прогрева — с запасом: червь под землёй, шея Нессы, смерч
const WORLD_VIEW_SIZE := 60.0            ## взгляд на настоящий мир — шире: побольше разных чанков
const WORLD_LIGHT_R := 30.0              ## свет над точкой старта задевает почти всё в кадре

var at := Vector3.ZERO                   ## точка старта (суша, загружена)
var rules: BalanceRules
var vehicle: Vehicle
var query: TerrainQuery
var terrain: TerrainData
var pickups: PickupField
var noise: NoiseField
var materials: TerrainMaterials          ## рельеф, вода, деревья — их материалы
var streamer: WorldStreamer

var wait_world := false                  ## дождаться look_at_world (трюм: мир догружается в фоне)
var done := false

var _makers: Array[Callable] = []
var _sample: Node3D
var _hold := 0
var _quiet := 0
var _spot := Vector3.ZERO                ## куда смотрит камера прогрева
var _cam: Camera3D
var _light: OmniLight3D
var _t0 := 0
var _total := 1                          ## образцов всего (с взглядом на мир) — для экрана загрузки
var _taken := 0


func _ready() -> void:
	name = "Warmup"
	_spot = at + Vector3(0.0, -DEPTH, 0.0)
	var view := SubViewport.new()
	view.size = Vector2i(128, 128)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = VIEW_SIZE
	_cam.near = 0.1
	_cam.far = 120.0
	view.add_child(_cam)
	_cam.global_transform = Transform3D(Basis.looking_at(Vector3(0, -1, -1)), _spot + Vector3(0, 30, 30))
	_light = OmniLight3D.new()
	_light.light_energy = 0.5
	_light.omni_range = VIEW_SIZE            # задевает весь образец: шея Нессы, смерч, тело червя
	_light.shadow_enabled = false
	_light.position = _spot + Vector3(0, 1.5, 0)
	add_child(_light)
	_makers = [_basics, _world_kit, _trail, _scars, _tornado, _worm, _hoppers, _shellback, _shark, _nessie, _stargazer,
			_whirlpool, _shuttle.bind(ShuttleCraft.Kind.MAIN), _shuttle.bind(ShuttleCraft.Kind.EMERGENCY), _drop_pod,
			_vehicles]
	_t0 = Time.get_ticks_msec()
	_total = _makers.size() + (1 if wait_world else 0)


## Доля пройденных образцов (экран загрузки): 1 — прогрев закончен.
func progress() -> float:
	return 1.0 if done else clampf(float(_taken) / maxi(_total, 1), 0.0, 0.99)


## Мир вокруг старта догружен: последним образцом — взгляд на него (p — точка старта на рельефе).
func look_at_world(p: Vector3) -> void:
	_makers.append(_world.bind(p))
	wait_world = false


func _process(_dt: float) -> void:
	if _hold > 0:
		_hold -= 1
		return
	if _sample != null or not _makers.is_empty():
		# Образец (или прошлый взгляд на мир) ещё собирается в фоне — ждём тишины QUIET_FRAMES кадров.
		_quiet = 0 if ShaderCache.pending_programs() > 0 else _quiet + 1
		if _quiet < QUIET_FRAMES:
			return
	_quiet = 0
	if _sample != null:
		_sample.queue_free()
		_sample = null
	if _makers.is_empty():
		if not wait_world:
			_finish()
		return
	var make: Callable = _makers.pop_front()
	_taken += 1
	DevTools.mark("warmup:" + make.get_method())
	_sample = make.call()
	_hold = HOLD_FRAMES
	if _sample == null:
		return
	_sample.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if _sample.get_parent() == null:
		add_child(_sample)
	_reveal(_sample)
	_sample.position += _spot - at       # образец строился у точки старта — уводим под мир, к камере
	_gather(_sample)
	ShaderCache.keep(_sample)


func _finish() -> void:
	DevTools.mark("warmup_done")
	done = true
	ShaderCache.warmed = true
	print("warmup: %d materials kept, %d ms" % [ShaderCache.kept_count(), Time.get_ticks_msec() - _t0])
	finished.emit()
	queue_free()


## Всё, что образец прячет до поры (тело червя, шея Нессы, пламя, знаки), — видно; частицы — летят
## (разовые — с начала, иначе им нечего рисовать).
func _reveal(n: Node) -> void:
	if n is Node3D:
		(n as Node3D).visible = true
	if n is CPUParticles3D:
		(n as CPUParticles3D).restart()
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


## Следы смерча и молнии на земле (GroundScars: MultiMesh — свой вариант шейдера).
func _scars() -> Node3D:
	var scars := GroundScars.new()
	scars.query = query
	var a := _at2()
	scars.strip(a + Vector2(-1.0, 0.0), a, Tornado.SCAR_WIDTH)
	scars.spot(a + Vector2(1.0, 0.0), 0.6)
	return scars


## Колея, пыль и комья из-под колёс (VehicleTrail).
func _trail() -> Node3D:
	var t := VehicleTrail.new()
	t.setup(vehicle.cls if vehicle != null else Balance.vehicle(&"rover"), query)
	add_child(t)
	t.preview(at)
	return t


func _worm() -> Node3D:
	var w := _creature(Worm.new()) as Worm
	add_child(w)
	w.setup(_at2())
	return w


## Звери под тараном — с белым наложением мигания (RamBody) поверх материалов; облачко гибели летит.
func _hoppers() -> Node3D:
	var h := _creature(HopperPack.new()) as HopperPack
	add_child(h)
	h.setup(_at2(), rules.pack_max)
	h.preview_flash()
	return h


func _shellback() -> Node3D:
	var s := _creature(Shellback.new()) as Shellback
	add_child(s)
	s.setup(_at2())
	s.preview_flash()
	return s


func _shark() -> Node3D:
	var s := _creature(MireShark.new()) as MireShark
	add_child(s)
	s.setup(_at2())
	s.preview_flash()
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
	s.quiet = true                       # образец — без звуков спуска и посадки
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


## Мир в миниатюре: клочок рельефа и воды, деревья всех видов и все находки (пачками, как в игре) — на
## случай, если у точки старта нет воды или леса, а молния ударит рядом с ними.
func _world_kit() -> Node3D:
	var root := Node3D.new()
	root.position = at
	if materials != null:
		for i in 2:
			var mi := MeshInstance3D.new()
			var q := PlaneMesh.new()
			q.size = Vector2.ONE
			mi.mesh = q
			mi.material_override = materials.terrain if i == 0 else materials.water
			mi.position = Vector3(i * 1.2 - 3.0, 0.2, -1.5)
			root.add_child(mi)
		var trees: Array[Mesh] = [materials.trunk_mesh, materials.log_mesh]
		trees.append_array(materials.crown_meshes)
		_batches(root, trees, -1.0)
		# Мелочь на земле — пачкой с цветом и данными экземпляра, как в чанке.
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = materials.sprite_mesh
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D.IDENTITY)
		mm.set_instance_color(0, Color.WHITE)
		mm.set_instance_custom_data(0, Color(0, 0, 0, 0))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.position = Vector3(1.0, 0.2, -1.0)
		root.add_child(mmi)
	if pickups != null:
		_batches(root, pickups.meshes(), 1.0)
	return root


## По пачке (MultiMesh из одного экземпляра) на каждый меш — ряд вдоль X на глубине z.
func _batches(root: Node3D, meshes: Array[Mesh], z: float) -> void:
	for i in meshes.size():
		if meshes[i] == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[i]
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D.IDENTITY)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.position = Vector3(i * 0.8 - 3.0, 0.3, z)
		root.add_child(mmi)


## Все три машины (в трюме их рисует свой мир под своим светом — варианты шейдеров другие; силуэт
## сквозь препятствия — отдельный проход).
func _vehicles() -> Node3D:
	var root := Node3D.new()
	root.position = at
	var ids := Balance.vehicle_ids()
	for i in ids.size():
		var m := VehicleModels.build(ids[i])
		m.root.position = Vector3((i - 1) * 1.2, 0.3, 0)
		root.add_child(m.root)
	return root


## Настоящий мир вокруг старта: рельеф, вода, деревья, камни, находки, своя машина — камера прогрева
## смотрит на точку старта сверху шире обычного, свет над ней задевает почти всё в кадре. Мир в это
## время закрыт трюмом или затемнением.
func _world(p: Vector3) -> Node3D:
	# Материалы рельефа и находок — тоже на всю сессию: после «Заново» сцена строится заново, а шейдеры
	# с их вариантами под светом остаются.
	if streamer != null:
		ShaderCache.keep(streamer)
	if pickups != null:
		ShaderCache.keep(pickups)
	_cam.size = WORLD_VIEW_SIZE
	_cam.far = 200.0
	_cam.global_transform = Transform3D(Basis.looking_at(Vector3(0, -1, -1)), p + Vector3(0, 60, 60))
	_light.position = p + Vector3(0, 3.0, 0)
	_light.omni_range = WORLD_LIGHT_R
	return null
