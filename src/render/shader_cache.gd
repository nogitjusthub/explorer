extends Node
## Автозагрузка ShaderCache: держит скомпилированные шейдеры всю сессию (ARCHITECTURE §10).
## У StandardMaterial3D шейдер общий на набор свойств («ключ»), и Godot выбрасывает его вместе с
## программами GPU, как только умирает последний материал с этим ключом. Без удержания образцы прогрева
## (Warmup) компилировали шейдеры впустую, а каждая молния, второй смерч или новый червь — заново
## (в браузере это сотни миллисекунд на программу). Прогрев складывает сюда материалы своих образцов;
## автозагрузка переживает «Заново» (перезагрузку сцены), повторный прогрев не нужен.

var warmed := false                      ## прогрев в этой сессии уже прошёл
var _kept: Dictionary = {}               ## Material → true


## Удержать все материалы узла и его потомков (переопределения, поверхности мешей, частицы, next_pass).
func keep(n: Node) -> void:
	for m in materials_of(n):
		_keep(m)
	for c in n.get_children():
		keep(c)


func kept_count() -> int:
	return _kept.size()


func _keep(m: Material) -> void:
	while m != null and not _kept.has(m):
		_kept[m] = true
		m = m.next_pass


## Материалы, которыми рисуется сам узел (без потомков).
static func materials_of(n: Node) -> Array[Material]:
	var out: Array[Material] = []
	if not n is GeometryInstance3D:
		return out
	var g := n as GeometryInstance3D
	var mesh: Mesh = null
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mesh = mi.mesh
		for i in mi.get_surface_override_material_count():
			out.append(mi.get_surface_override_material(i))
	elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
		mesh = (n as MultiMeshInstance3D).multimesh.mesh
	elif n is CPUParticles3D:
		mesh = (n as CPUParticles3D).mesh
	if mesh != null:
		for i in mesh.get_surface_count():
			out.append(mesh.surface_get_material(i))
	out.append(g.material_override)
	out.append(g.material_overlay)
	return out.filter(func(m: Material) -> bool: return m != null)


## Отладка (--shader-audit): приблизительный ключ шейдера — для StandardMaterial3D логические и
## перечислимые свойства, отличные от умолчаний, и наличие текстур (цвета и числа — параметры, шейдер не
## меняют), для ShaderMaterial — сам шейдер; плюс отрисовка пачкой (MultiMesh, частицы) — у неё своя программа.
static func key_of(m: Material, instanced: bool) -> String:
	var parts: Array[String] = ["inst" if instanced else "mesh", m.get_class()]
	if m is ShaderMaterial:
		var sh := (m as ShaderMaterial).shader
		parts.append(sh.resource_path if sh != null and sh.resource_path != "" else "inline")
	else:
		var base: Object = ClassDB.instantiate(m.get_class())
		for p in m.get_property_list():
			var pname: String = p["name"]
			if (p["usage"] & PROPERTY_USAGE_STORAGE) == 0 or pname in ["render_priority", "resource_local_to_scene"]:
				continue
			match p["type"]:
				TYPE_BOOL, TYPE_INT:
					if m.get(pname) != base.get(pname):
						parts.append("%s=%s" % [pname, m.get(pname)])
				TYPE_OBJECT:
					if pname.ends_with("_texture") and m.get(pname) != null:
						parts.append(pname)
	return " ".join(parts)
