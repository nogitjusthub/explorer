extends TestCase
## Надписи о конце забега (DeathText): три набора с одними и теми же причинами; каждая надпись заголовка
## помещается в экран (кегль UiKit.TITLE, рендер 480 пикселей); неизвестная причина — «прочее».


func test_three_styles_cover_the_same_causes() -> void:
	var keys: Array = (DeathText.CAUSES[DeathText.Style.VEHICLE] as Dictionary).keys()
	keys.sort()
	for style: DeathText.Style in DeathText.CAUSES:
		var k: Array = (DeathText.CAUSES[style] as Dictionary).keys()
		k.sort()
		assert_eq(k, keys, "style %d has every cause" % style)
		for kind: StringName in [&"wrecked", &"sunk"]:
			assert_false(DeathText.banner(kind, style).is_empty(), "banner %s in style %d" % [kind, style])
	assert_eq(DeathText.cause("no such cause", DeathText.Style.JOKE), DeathText.cause("", DeathText.Style.JOKE))
	assert_eq(DeathText.STYLE, DeathText.Style.JOKE, "the joke set is active for now")


func test_titles_fit_the_screen() -> void:
	for style: DeathText.Style in DeathText.CAUSES:
		for id: String in DeathText.CAUSES[style]:
			var w := UiKit.FONT.get_string_size(DeathText.cause(id, style), HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.TITLE).x
			assert_true(w <= 460.0, "%s fits: %.0f px" % [DeathText.cause(id, style), w])
