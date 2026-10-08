class_name Nest
extends Node3D
## Гнездо (GDD §3.4, §5.4): холм с норами в ущельях и у озёр, рядом — образцы и ядра (их ставит
## PickupGenerator по флагу FLAG_NEST). Машина подъехала ближе nest_wake_r — из гнезда выходит стая
## скакунов и сразу атакует; потом гнездо отдыхает nest_cooldown_s. С T ≥ 3 гнёзда активнее.

const MOUND_COLOR := Color(0.42, 0.3, 0.36)
const HOLE_COLOR := Color(0.08, 0.05, 0.07)
const BONE_COLOR := Color(0.85, 0.8, 0.68)

var tile := Vector2i.ZERO
var cooldown := 0.0


func _init(at: Vector2i) -> void:
	tile = at
	name = "Nest"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func center() -> Vector2:
	return Vector2(tile.x + 0.5, tile.y + 0.5)


func build(q: TerrainQuery) -> void:
	position = Vector3(tile.x + 0.5, q.surface_y(tile.x + 0.5, tile.y + 0.5), tile.y + 0.5)
	var mound := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.3
	sm.height = 1.3
	sm.is_hemisphere = true
	sm.radial_segments = 12
	sm.rings = 4
	mound.mesh = sm
	mound.material_override = Creature.material(MOUND_COLOR)
	mound.scale = Vector3(1.0, 0.45, 1.0)
	add_child(mound)
	var hole := Creature.material(HOLE_COLOR)
	for i in 3:
		var a := TAU * i / 3.0 + 0.4
		var h := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.2
		c.bottom_radius = 0.2
		c.height = 0.05
		c.radial_segments = 8
		c.rings = 0
		h.mesh = c
		h.material_override = hole
		h.position = Vector3(cos(a) * 0.65, 0.42, sin(a) * 0.65)
		h.rotation = Vector3(sin(a) * 0.5, 0, -cos(a) * 0.5)
		add_child(h)
	var bone := Creature.material(BONE_COLOR)
	for i in 4:
		var a := TAU * i / 4.0
		var spike := MeshInstance3D.new()
		var sc := CylinderMesh.new()
		sc.top_radius = 0.0
		sc.bottom_radius = 0.07
		sc.height = 0.6
		sc.radial_segments = 5
		sc.rings = 0
		spike.mesh = sc
		spike.material_override = bone
		spike.position = Vector3(cos(a) * 1.25, 0.2, sin(a) * 1.25)
		spike.rotation = Vector3(sin(a) * 0.6, 0, -cos(a) * 0.6)
		add_child(spike)
