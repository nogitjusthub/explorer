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
