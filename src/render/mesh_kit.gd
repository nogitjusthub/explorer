class_name MeshKit
extends RefCounted
## Low-poly геометрия с плоскими гранями (каждый треугольник — своя нормаль): призмы по контуру,
## правильные многоугольники, треугольники с правильной лицевой стороной. Общая для техники и фауны.


## Призма: выпуклый контур poly (x, z), низ на y0, высота h.
static func prism_mesh(poly: PackedVector2Array, y0: float, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector2.ZERO
	for v in poly:
		center += v
	center /= poly.size()
	var y1 := y0 + h
	for i in range(1, poly.size() - 1):
		tri(st, Vector3(poly[0].x, y1, poly[0].y), Vector3(poly[i].x, y1, poly[i].y),
				Vector3(poly[i + 1].x, y1, poly[i + 1].y), Vector3.UP)
		tri(st, Vector3(poly[0].x, y0, poly[0].y), Vector3(poly[i].x, y0, poly[i].y),
				Vector3(poly[i + 1].x, y0, poly[i + 1].y), Vector3.DOWN)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var e := b - a
		var n2 := Vector2(e.y, -e.x).normalized()
		if n2.dot((a + b) * 0.5 - center) < 0.0:
			n2 = -n2
		var n := Vector3(n2.x, 0, n2.y)
		tri(st, Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y), n)
		tri(st, Vector3(a.x, y0, a.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y), n)
	return st.commit()


static func prism(parent: Node3D, poly: PackedVector2Array, y0: float, h: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = prism_mesh(poly, y0, h)
	mi.material_override = mat
	parent.add_child(mi)
	return mi


## Правильный n-угольник радиуса r (x, z), повёрнутый на phase.
static func ngon(n: int, r: float, phase: float = 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		pts.append(Vector2.from_angle(phase + TAU * i / n) * r)
	return pts


## Треугольник лицом к n: в Godot лицевая сторона — обход по часовой стрелке, если смотреть на неё.
static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var tmp := b
		b = c
		c = tmp
	for v: Vector3 in [a, b, c]:
		st.set_normal(n)
		st.add_vertex(v)


## Треугольник лицом от точки inside (нормаль — по грани).
static func tri_out(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, inside: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-10:
		return                                   # вырожденный (у вершины)
	n = n.normalized()
	if n.dot((a + b + c) / 3.0 - inside) < 0.0:
		n = -n
	tri(st, a, b, c, n)


## Меш с координатами граней — для узора, привязанного к граням (BodyMaterial.Pattern.PLATES). Грань —
## треугольники одной плоскости (у коробки — по два, у призмы — веер крышки). UV — точка относительно
## центра грани, UV2 — полуразмеры грани; оси грани: x — по горизонтали грани, y — вверх по ней, у
## горизонтальной — x и z меша. Детали грани (BodyMaterial.detail, до двух на грань) — прямоугольники на
## грани с её нормалью (и серединой на грани): в CUSTOM0 и CUSTOM1 — центр и полуразмеры в координатах грани, в COLOR.r и .g —
## код детали / 16: вид × 4 + 2, если ручка к −x грани, + 1, если петли к +y. Нормали вершин — прежние.
static func face_mapped(mesh: Mesh, details: Array[Dictionary] = []) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var index := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		index = arrays[Mesh.ARRAY_INDEX]
	if index.is_empty():
		index.resize(verts.size())
		for i in verts.size():
			index[i] = i
	# Треугольники по граням: ключ — нормаль и расстояние плоскости.
	var face_of := {}
	var face_n: Array[Vector3] = []
	var face_tris: Array[PackedInt32Array] = []
	for t in index.size() / 3:
		var a := verts[index[t * 3]]
		var n := (verts[index[t * 3 + 1]] - a).cross(verts[index[t * 3 + 2]] - a)
		if n.length_squared() < 1e-14:
			continue
		n = n.normalized()
		var vn := normals[index[t * 3]] + normals[index[t * 3 + 1]] + normals[index[t * 3 + 2]]
		if n.dot(vn) < 0.0:
			n = -n
		var key := "%d,%d,%d,%d" % [roundi(n.x * 100.0), roundi(n.y * 100.0), roundi(n.z * 100.0), roundi(n.dot(a) * 1000.0)]
		if not face_of.has(key):
			face_of[key] = face_n.size()
			face_n.append(n)
			face_tris.append(PackedInt32Array())
		face_tris[face_of[key]].append(t)
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	var out_uv := PackedVector2Array()
	var out_uv2 := PackedVector2Array()
	var out_c := PackedColorArray()
	var out_d0 := PackedFloat32Array()
	var out_d1 := PackedFloat32Array()
	for f in face_n.size():
		var n := face_n[f]
		var tx := Vector3.RIGHT
		var ty := Vector3.BACK
		if absf(n.y) <= 0.9:
			tx = Vector3(-n.z, 0.0, n.x).normalized()
			ty = tx.cross(n)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for t in face_tris[f]:
			for k in 3:
				var p := verts[index[t * 3 + k]]
				var uv := Vector2(p.dot(tx), p.dot(ty))
				lo = lo.min(uv)
				hi = hi.max(uv)
		var mid := (lo + hi) * 0.5
		var half := (hi - lo) * 0.5
		var codes := PackedFloat32Array([0.0, 0.0])
		var rects: Array[Vector4] = [Vector4.ZERO, Vector4.ZERO]
		var found := 0
		for d in details:
			if found == 2 or (d["normal"] as Vector3).normalized().dot(n) < 0.95:
				continue
			var a := Vector2((d["from"] as Vector3).dot(tx), (d["from"] as Vector3).dot(ty))
			var b := Vector2((d["to"] as Vector3).dot(tx), (d["to"] as Vector3).dot(ty))
			var c := (a + b) * 0.5 - mid
			if absf(c.x) > half.x or absf(c.y) > half.y:
				continue                         # деталь — на другой грани с той же нормалью
			rects[found] = Vector4(c.x, c.y, absf(b.x - a.x) * 0.5, absf(b.y - a.y) * 0.5)
			var toward: Vector3 = d["toward"]
			codes[found] = int(d["kind"]) * 4 + 2 * int(toward.dot(tx) < 0.0) + int(toward.dot(ty) > 0.0)
			found += 1
		var color := Color(codes[0] / 16.0, codes[1] / 16.0, 0.0, 1.0)
		for t in face_tris[f]:
			for k in 3:
				var i := index[t * 3 + k]
				var p := verts[i]
				out_v.append(p)
				out_n.append(normals[i])
				out_uv.append(Vector2(p.dot(tx), p.dot(ty)) - mid)
				out_uv2.append(half)
				out_c.append(color)
				out_d0.append_array([rects[0].x, rects[0].y, rects[0].z, rects[0].w])
				out_d1.append_array([rects[1].x, rects[1].y, rects[1].z, rects[1].w])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = out_v
	out[Mesh.ARRAY_NORMAL] = out_n
	out[Mesh.ARRAY_TEX_UV] = out_uv
	out[Mesh.ARRAY_TEX_UV2] = out_uv2
	out[Mesh.ARRAY_COLOR] = out_c
	out[Mesh.ARRAY_CUSTOM0] = out_d0
	out[Mesh.ARRAY_CUSTOM1] = out_d1
	var mapped := ArrayMesh.new()
	mapped.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out, [], {},
			(Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
			| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT))
	return mapped
