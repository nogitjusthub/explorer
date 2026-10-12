extends SceneTree
## Генератор текстуры воды для перебора палитры (GDD §11, M5): assets/textures/water_cycle.png, 16×16
## текселей на тайл, бесшовная. В каждом текселе — номер фазы волны 0…CYCLE−1 (значение / CYCLE):
## полоса вдоль x + y (одна на тайл) с изгибом. Шейдер воды сдвигает фазу со временем и берёт оттенок из
## короткой палитры — гребни бегут по воде без плавных градиентов (palette cycling).
## Запуск: godot --headless --path . --script res://tools/textures/gen_water_cycle.gd

const S := 16
const CYCLE := 8
const OUT := "res://assets/textures/water_cycle.png"


func _initialize() -> void:
	var img := Image.create(S, S, false, Image.FORMAT_RGB8)
	for y in S:
		for x in S:
			# Фаза периодична по обеим осям: (x + y) / S — одна полоса на тайл, синусы — изгиб.
			var phase := float(x + y) / S + 0.18 * sin(TAU * x / S) + 0.12 * sin(TAU * 2.0 * y / S)
			var idx := posmod(floori(fposmod(phase, 1.0) * CYCLE), CYCLE)
			var g := (idx + 0.5) / CYCLE
			img.set_pixel(x, y, Color(g, g, g))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var err := img.save_png(OUT)
	print("water cycle: %s, error %d" % [OUT, err])
	quit()
