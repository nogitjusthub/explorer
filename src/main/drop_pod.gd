class_name DropPod
extends Node3D
## Десант (GDD §2.1): капсула с машиной падает с орбиты. На земле заранее растёт тень и мигает маркер
## посадки; капсула раскалена входом в атмосферу и тянет огненный след. Удар — пыль, тряска, вспышка,
## раскат (воронку делает GameFlow); затем капсула раскрывается тремя лепестками, и машина свободна.

signal landed                            ## касание земли
signal opened                            ## лепестки разлетелись — машина видна

const FALL_S := 2.2
const OPEN_S := 0.6
const START_H := 34.0
const SHELL_COLOR := Color(0.55, 0.57, 0.62)
const HEAT_COLOR := Color(1.0, 0.62, 0.25)
const MARK_COLOR := Color(0.45, 1.0, 0.95, 0.8)
const SHADOW_COLOR := Color(0.05, 0.03, 0.06, 0.5)

var _t := 0.0
var _ground := Vector3.ZERO
var _phase := 0                          ## 0 — падение, 1 — раскрытие, 2 — готово
var _pod: Node3D
var _petals: Array[Node3D] = []
var _heat_mat: StandardMaterial3D
var _trail: CPUParticles3D
var _shadow: MeshInstance3D
var _shadow_mat: StandardMaterial3D
var _marker: Node3D
var _marker_mat: StandardMaterial3D
var _dust: CPUParticles3D


func _init() -> void:
	name = "DropPod"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func start(ground: Vector3) -> void:
	_ground = ground
	_build()
	_update(0.0)


func _process(dt: float) -> void:
	if _phase == 2:
		return
	_t += dt
	_update(dt)


func _update(_dt: float) -> void:
	if _phase == 0:
		var k := clampf(_t / FALL_S, 0.0, 1.0)
		var h := START_H * (1.0 - k * k)             # разгоняется к земле
		_pod.position = _ground + Vector3(0, h, 0)
		_trail.position = _pod.position + Vector3(0, 0.6, 0)
		_shadow.scale = Vector3.ONE * lerpf(0.3, 1.0, k)
		_shadow_mat.albedo_color.a = SHADOW_COLOR.a * lerpf(0.3, 1.0, k)
		_marker_mat.albedo_color.a = MARK_COLOR.a * (0.5 + 0.5 * float(fmod(_t, 0.4) < 0.25))
		_heat_mat.albedo_color = HEAT_COLOR.lerp(Color(1, 0.95, 0.8), 0.3 + 0.3 * sin(_t * 40.0))
		if k >= 1.0:
			_phase = 1
			_t = 0.0
			_trail.emitting = false
			_marker.visible = false
			_shadow.visible = false
			_dust.restart()
			_dust.emitting = true
			landed.emit()
	elif _phase == 1:
		var k := clampf(_t / OPEN_S, 0.0, 1.0)
		_heat_mat.albedo_color = HEAT_COLOR.lerp(SHELL_COLOR, k)
		for i in _petals.size():
			var p := _petals[i]
			p.rotation.z = -1.9 * k * k
			p.position.y = -0.6 * k * k
		if k >= 1.0:
			_phase = 2
			_pod.visible = false
			opened.emit()
			get_tree().create_timer(1.5).timeout.connect(queue_free)


func _build() -> void:
	var shell := StandardMaterial3D.new()
	shell.albedo_color = SHELL_COLOR
	shell.roughness = 0.5
	shell.metallic = 0.4
	_heat_mat = StandardMaterial3D.new()
	_heat_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_heat_mat.albedo_color = HEAT_COLOR
	_pod = Node3D.new()
	add_child(_pod)
	# Капсула из трёх лепестков-секторов вокруг оси: при посадке они откидываются наружу.
	for i in 3:
		var turn := Node3D.new()
		turn.rotation.y = -TAU * i / 3.0
		_pod.add_child(turn)
		var hinge := Node3D.new()
		hinge.position = Vector3(0.45, 0.05, 0)
		turn.add_child(hinge)
		var petal := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.12, 1.1, 0.72)
		petal.mesh = box
		petal.material_override = shell
		petal.position = Vector3(-0.06, 0.55, 0)
		hinge.add_child(petal)
		var cap := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.42
		cone.height = 0.5
		cone.radial_segments = 3
		cone.rings = 0
		cap.mesh = cone
		cap.material_override = shell
		cap.position = Vector3(-0.3, 1.3, 0)
		cap.scale = Vector3(0.7, 1.0, 1.0)
		hinge.add_child(cap)
		_petals.append(hinge)
	var shield := MeshInstance3D.new()           # теплозащитный экран — светится при входе
	var dome := SphereMesh.new()
	dome.radius = 0.62
	dome.height = 0.62
	dome.is_hemisphere = true
	dome.radial_segments = 12
	dome.rings = 3
	shield.mesh = dome
	shield.material_override = _heat_mat
	shield.rotation.x = PI
	shield.scale = Vector3(1, 0.45, 1)
	_pod.add_child(shield)

	_trail = _particles(Color(1.0, 0.55, 0.2), 60, 0.5, Vector3.UP, 12.0, 6.0, 12.0, 0.22)
	_trail.emitting = true

	_shadow_mat = StandardMaterial3D.new()
	_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_mat.albedo_color = SHADOW_COLOR
	var disc := CylinderMesh.new()
	disc.top_radius = 1.1
	disc.bottom_radius = 1.1
	disc.height = 0.02
	disc.radial_segments = 16
	disc.rings = 0
	_shadow = MeshInstance3D.new()
	_shadow.mesh = disc
	_shadow.material_override = _shadow_mat
	_shadow.position = _ground + Vector3(0, 0.05, 0)
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow)

	_marker = Node3D.new()
	_marker.position = _ground + Vector3(0, 0.07, 0)
	add_child(_marker)
	_marker_mat = StandardMaterial3D.new()
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker_mat.albedo_color = MARK_COLOR
	_marker_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ring := TorusMesh.new()
	ring.inner_radius = 1.75
	ring.outer_radius = 1.9
	ring.rings = 24
	ring.ring_segments = 4
	var ring_mi := MeshInstance3D.new()
	ring_mi.mesh = ring
	ring_mi.material_override = _marker_mat
	ring_mi.scale = Vector3(1, 0.3, 1)
	_marker.add_child(ring_mi)
	for i in 4:     # перекрестье
		var tick := MeshInstance3D.new()
		var tb := BoxMesh.new()
		tb.size = Vector3(0.6, 0.02, 0.08)
		tick.mesh = tb
		tick.material_override = _marker_mat
		var a := TAU * i / 4.0
		tick.position = Vector3(cos(a), 0, sin(a)) * 1.3
		tick.rotation.y = -a
		_marker.add_child(tick)

	_dust = _particles(Color(0.62, 0.5, 0.45), 90, 1.4, Vector3.UP, 70.0, 2.0, 6.0, 0.2)
	_dust.one_shot = true
	_dust.explosiveness = 0.9
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_dust.emission_ring_axis = Vector3.UP
	_dust.emission_ring_radius = 1.6
	_dust.emission_ring_inner_radius = 0.6
	_dust.emission_ring_height = 0.1
	_dust.position = _ground + Vector3(0, 0.1, 0)
	_dust.emitting = false


func _particles(color: Color, amount: int, lifetime: float, direction: Vector3, spread: float,
		v_min: float, v_max: float, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.direction = direction
	p.spread = spread
	p.initial_velocity_min = v_min
	p.initial_velocity_max = v_max
	p.gravity = Vector3(0, -6.0, 0)
	p.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = color
	q.material = m
	p.mesh = q
	add_child(p)
	return p
