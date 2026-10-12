extends SceneTree
## Генератор спрайтов мелочи на земле (GDD §11, M5): атлас assets/textures/ground_sprites.png —
## 8 спрайтов 8×8 в ряд (RGBA). Тексель — 1/16 тайла, как у текстуры рельефа: спрайт полтайла.
## Спрайт — в оттенках серого с прозрачностью: значение v = яркость / GAIN, цвет даёт экземпляр
## (тон грунта, растения). Рисунки — прямо здесь, символами: «.» — пусто, «o» — тень у основания,
## «d» — тёмный, «m» — основа, «l» — светлый, «h» — блик. Нижняя строка — земля.
## Порядок — GroundSprites.Kind: трава, высокая трава, кустик, камешек, галька, камень, осколки
## кристалла, луковица.
## Запуск: godot --headless --path . --script res://tools/textures/gen_ground_sprites.gd

const N := 8
const GAIN := 1.5
const OUT := "res://assets/textures/ground_sprites.png"
const LEVELS := {"o": 0.45, "d": 0.78, "m": 1.0, "l": 1.15, "h": 1.32}

const SPRITES := [
	[   # 0 — трава
		"........",
		"....l...",
		"..l.m...",
		"..m.m.l.",
		"..m.m.m.",
		".dm.m.m.",
		".dmdmdmd",
		"..odoodo",
	],
	[   # 1 — высокая трава, стебли изогнуты
		".l......",
		"..m...l.",
		"..m..m..",
		"...m.m..",
		"...m.m.l",
		".l.mdm.m",
		".mdmdmdm",
		"..ododo.",
	],
	[   # 2 — кустик
		"........",
		"........",
		"..llm...",
		".llmmmd.",
		".lmmmmdd",
		".mmmmddd",
		"..dddddo",
		"...ooo..",
	],
	[   # 3 — камешек
		"........",
		"........",
		"........",
		"........",
		"...ll...",
		"..lmmd..",
		"..mmdd..",
		"...oo...",
	],
	[   # 4 — галька
		"........",
		"........",
		"........",
		"........",
		"........",
		".lm..ll.",
		".md.lmmd",
		"..o..oo.",
	],
	[   # 5 — камень
		"........",
		"........",
		"...lll..",
		"..lmmmd.",
		".lmmmmdd",
		".mmmmddd",
		".ddddddd",
		"..ooooo.",
	],
	[   # 6 — осколки кристалла
		"........",
		"...h....",
		"...l..h.",
		"..lmd.l.",
		"..lmd.md",
		".hlmdlmd",
		".lmmdmmd",
		"..oo.oo.",
	],
	[   # 7 — луковица на стебле
		"........",
		"...ll...",
		"..lhml..",
		"..lmmd..",
		"...md...",
		"....d...",
		"...ld...",
		"...oo...",
	],
]


func _initialize() -> void:
	var img := Image.create(N * SPRITES.size(), N, false, Image.FORMAT_RGBA8)
	for k in SPRITES.size():
		var rows: Array = SPRITES[k]
		for y in N:
			var line: String = rows[y]
			for x in N:
				var ch := line[x]
				if ch == ".":
					img.set_pixel(k * N + x, y, Color(0, 0, 0, 0))
				else:
					var g: float = LEVELS[ch] / GAIN
					img.set_pixel(k * N + x, y, Color(g, g, g, 1.0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var err := img.save_png(OUT)
	print("ground sprites: %s (%d×%d), error %d" % [OUT, img.get_width(), img.get_height(), err])
	quit()
