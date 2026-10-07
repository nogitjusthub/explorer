class_name TreeField
extends RefCounted
## Заполняет MultiMesh деревьев чанка: стволы, кроны по типу, поваленные стволы.


static func build(node: ChunkNode, data: ChunkData, q: TerrainQuery, run_seed: int) -> void:
	var standing: Array[Transform3D] = []
	var standing_types := PackedInt32Array()
	var standing_colors: Array[Color] = []
	var felled: Array[Transform3D] = []
	var origin := Grid.chunk_origin(data.coord)
	var n := ChunkData.N
	for lz in range(Grid.APRON, Grid.APRON + Grid.CHUNK):
		for lx in range(Grid.APRON, Grid.APRON + Grid.CHUNK):
			var t := data.trees[lz * n + lx]
			if t == ChunkData.TREE_NONE:
				continue
			var tx := origin.x + lx - Grid.APRON
			var tz := origin.y + lz - Grid.APRON
			var p := q.tree_position(tx, tz)
			var y := q.surface_y(p.x, p.y)
			var local := Vector3(p.x - origin.x, y, p.y - origin.y)
			var scale := 0.85 + 0.35 * DetRng.unit(run_seed, tx, tz, 310)
			var yaw := TAU * DetRng.unit(run_seed, tx, tz, 311)
			var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale)
			if t & ChunkData.TREE_FELLED:
				var lying := Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, PI * 0.5)
				felled.append(Transform3D(lying, local + Vector3(0, 0.08, 0)))
			else:
				standing.append(Transform3D(basis, local))
				standing_types.append(((t & ChunkData.TREE_TYPE_MASK) - 1) % TerrainMaterials.TREE_TYPES)
				var tint := 0.85 + 0.3 * DetRng.unit(run_seed, tx, tz, 312)
				standing_colors.append(Color(tint, tint, tint))

	var trunk_mm := node.trunks.multimesh
	trunk_mm.instance_count = standing.size()
	for i in standing.size():
		var xf := standing[i]
		trunk_mm.set_instance_transform(i, xf.translated_local(Vector3(0, 0.32, 0)))
		trunk_mm.set_instance_color(i, Color.WHITE)

	for type in node.crowns.size():
		var mm := node.crowns[type].multimesh
		var count := 0
		for i in standing.size():
			if standing_types[i] == type:
				count += 1
		mm.instance_count = count
		var k := 0
		for i in standing.size():
			if standing_types[i] != type:
				continue
			mm.set_instance_transform(k, standing[i].translated_local(Vector3(0, 0.7, 0)))
			mm.set_instance_color(k, standing_colors[i])
			k += 1

	var log_mm := node.logs.multimesh
	log_mm.instance_count = felled.size()
	for i in felled.size():
		log_mm.set_instance_transform(i, felled[i])
		log_mm.set_instance_color(i, Color.WHITE)
