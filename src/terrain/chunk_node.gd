class_name ChunkNode
extends Node3D
## Визуальная часть чанка: 4 секции рельефа, вода, деревья (стволы, кроны двух типов, поваленные).
## Узлы переиспользуются через пул WorldStreamer; стоят в мировом углу чанка.

var sections: Array[MeshInstance3D] = []
var water: MeshInstance3D
var trunks: MultiMeshInstance3D
var crowns: Array[MultiMeshInstance3D] = []
var logs: MultiMeshInstance3D


func _init(mats: TerrainMaterials) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # чанки не двигаются
	for s in 4:
		var mi := MeshInstance3D.new()
		mi.mesh = ArrayMesh.new()
		mi.material_override = mats.terrain
		add_child(mi)
		sections.append(mi)
	water = MeshInstance3D.new()
	water.mesh = ArrayMesh.new()
	water.material_override = mats.water
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	trunks = _multimesh(mats.trunk_mesh)
	for mesh in mats.crown_meshes:
		crowns.append(_multimesh(mesh))
	logs = _multimesh(mats.log_mesh)


func set_section(s: int, arrays: Array) -> void:
	var mesh: ArrayMesh = sections[s].mesh
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func set_water(arrays: Array) -> void:
	var mesh: ArrayMesh = water.mesh
	mesh.clear_surfaces()
	if not arrays.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


## Очистка перед повторным использованием из пула.
func clear() -> void:
	for mi in sections:
		(mi.mesh as ArrayMesh).clear_surfaces()
	(water.mesh as ArrayMesh).clear_surfaces()
	trunks.multimesh.instance_count = 0
	for c in crowns:
		c.multimesh.instance_count = 0
	logs.multimesh.instance_count = 0


func _multimesh(mesh: Mesh) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	return mmi
