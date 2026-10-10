class_name Tex
## Procedural textures (port of src/track/textures.ts and the canvas textures in CarModel.ts).
## Each one is drawn like a 2D canvas in a SubViewport that renders once; the returned ImageTexture
## is a placeholder until flush() has copied the pixels in, so materials can use it right away.

static var host: Node
static var _pending: Array = [] # [viewport, texture, mipmaps]
static var _cache := {}
static var font_sign: Font
static var font_banner: Font


class Painter:
	extends Control
	var fn: Callable

	func _draw() -> void:
		fn.call(self)


## Queue a w×h texture drawn by fn(canvas: Control).
static func paint(w: int, h: int, fn: Callable, mipmaps := true) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.5, 0.5))
	var tex := ImageTexture.create_from_image(img)
	var vp := SubViewport.new()
	vp.size = Vector2i(w, h)
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var c := Painter.new()
	c.fn = fn
	c.size = Vector2(w, h)
	vp.add_child(c)
	host.add_child(vp)
	_pending.append([vp, tex, mipmaps])
	return tex


## Wait until every queued texture has been rendered and copied.
static func flush() -> void:
	if _pending.is_empty():
		return
	var jobs := _pending
	_pending = []
	if DisplayServer.get_name() == "headless":
		# Nothing gets drawn without a GPU (tests): keep the grey placeholders.
		for j in jobs:
			j[0].queue_free()
		return
	await RenderingServer.frame_post_draw
	for j in jobs:
		var vp: SubViewport = j[0]
		var img := vp.get_texture().get_image()
		if img != null and not img.is_empty():
			img.convert(Image.FORMAT_RGBA8)
			if j[2]:
				img.generate_mipmaps()
			(j[1] as ImageTexture).set_image(img)
		vp.queue_free()


static func cached(key: String, w: int, h: int, fn: Callable, mipmaps := true) -> ImageTexture:
	if not _cache.has(key):
		_cache[key] = paint(w, h, fn, mipmaps)
	return _cache[key]


static func _fonts() -> void:
	if font_sign == null:
		font_sign = load("res://assets/fonts/LiberationSans-Bold.ttf")
		font_banner = load("res://assets/fonts/Bangers-Regular.ttf")


static func _noise(c: Control, w: float, h: float, amount: int, alpha: float) -> void:
	for i in amount:
		var v := randf()
		c.draw_rect(Rect2(randf() * w, randf() * h, 1 + randf() * 2, 1 + randf() * 2), Color(v, v, v, alpha))


static func _text(c: Control, font: Font, text: String, x: float, y: float, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var px := x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		width = 2000.0
		px = x - 1000.0
	c.draw_string(font, Vector2(px, y), text, align, width, size, col)


## Carriageway texture: u spans the road width (-6..6 m), v repeats every 12 m.
## Dutch motorway markings: solid edge lines, 3 m dash / 9 m gap between lanes.
static func road() -> ImageTexture:
	return cached("road", 512, 512, func(c: Control) -> void:
		var W := 512.0
		var H := 512.0
		c.draw_rect(Rect2(0, 0, W, H), Color("3b3c3f"))
		_noise(c, W, H, 26000, 0.08)
		var m := func(d: float) -> float: return (d + 6.0) / 12.0 * W
		var w05: float = m.call(0.5) - m.call(0.0)
		for lane in [-2.75, 0.75]:
			c.draw_rect(Rect2(m.call(lane - 1.1), 0, w05, H), Color(20 / 255.0, 20 / 255.0, 22 / 255.0, 0.18))
			c.draw_rect(Rect2(m.call(lane + 0.6), 0, w05, H), Color(20 / 255.0, 20 / 255.0, 22 / 255.0, 0.18))
		# Shoulder (outside the rails) a touch lighter.
		c.draw_rect(Rect2(0, 0, m.call(-5.5), H), Color(120 / 255.0, 120 / 255.0, 110 / 255.0, 0.25))
		c.draw_rect(Rect2(m.call(5.5), 0, W - m.call(5.5), H), Color(120 / 255.0, 120 / 255.0, 110 / 255.0, 0.25))
		var line := func(d: float, wid: float, dash: bool) -> void:
			var lw: float = m.call(wid) - m.call(0.0)
			c.draw_rect(Rect2(m.call(d) - lw / 2.0, 0, lw, H * 0.25 if dash else H), Color("e9e9e2"))
		line.call(-4.5, 0.15, false)
		line.call(-1.0, 0.15, true)
		line.call(2.5, 0.2, false)
	)


## Single-carriageway N-road (N35): edge lines, and the Dutch "groene as" in the centre:
## two solid lines with green paint between them. Same width/UV layout as road().
static func single_road() -> ImageTexture:
	return cached("single_road", 512, 512, func(c: Control) -> void:
		var W := 512.0
		var H := 512.0
		c.draw_rect(Rect2(0, 0, W, H), Color("3e3f42"))
		_noise(c, W, H, 26000, 0.08)
		var m := func(d: float) -> float: return (d + 6.0) / 12.0 * W
		var w05: float = m.call(0.5) - m.call(0.0)
		for lane in [-2.75, 0.75]:
			c.draw_rect(Rect2(m.call(lane - 1.1), 0, w05, H), Color(20 / 255.0, 20 / 255.0, 22 / 255.0, 0.18))
			c.draw_rect(Rect2(m.call(lane + 0.6), 0, w05, H), Color(20 / 255.0, 20 / 255.0, 22 / 255.0, 0.18))
		c.draw_rect(Rect2(0, 0, m.call(-4.5), H), Color(120 / 255.0, 120 / 255.0, 110 / 255.0, 0.22))
		c.draw_rect(Rect2(m.call(2.6), 0, W - m.call(2.6), H), Color(120 / 255.0, 120 / 255.0, 110 / 255.0, 0.22))
		c.draw_rect(Rect2(m.call(-1.25), 0, m.call(-0.75) - m.call(-1.25), H), Color("3f7d3a"))
		var line := func(d: float, wid: float) -> void:
			var lw: float = m.call(wid) - m.call(0.0)
			c.draw_rect(Rect2(m.call(d) - lw / 2.0, 0, lw, H), Color("e9e9e2"))
		line.call(-1.25, 0.12)
		line.call(-0.75, 0.12)
		line.call(-4.5, 0.15)
		line.call(2.55, 0.15)
	)


static func grass() -> ImageTexture:
	return cached("grass", 256, 256, func(c: Control) -> void:
		c.draw_rect(Rect2(0, 0, 256, 256), Color("4f6f2a"))
		for i in 9000:
			c.draw_rect(Rect2(randf() * 256, randf() * 256, 1, 2 + randf() * 3),
				Color.from_hsv((70 + randf() * 40) / 360.0, 0.45, 0.25 + randf() * 0.2, 0.5))
	)


## Large-scale patchwork of Twente fields, used on the ground plane.
static func field() -> ImageTexture:
	return cached("field", 1024, 1024, func(c: Control) -> void:
		var colors := ["5a7a2e", "6b8a35", "4e6b28", "8a8a3a", "6f7f30", "7d6a3c", "557833"]
		for y in range(0, 1024, 128):
			for x in range(0, 1024, 128):
				var ox := randf() * 30 - 15
				c.draw_rect(Rect2(x + ox, y, 128 + 30, 128), Color(colors[randi() % colors.size()]))
		for i in range(0, 1025, 128):
			c.draw_line(Vector2(i, 0), Vector2(i, 1024), Color(40 / 255.0, 55 / 255.0, 20 / 255.0, 0.6), 3)
			c.draw_line(Vector2(0, i), Vector2(1024, i), Color(40 / 255.0, 55 / 255.0, 20 / 255.0, 0.6), 3)
		_noise(c, 1024, 1024, 60000, 0.05)
	)


static func concrete() -> ImageTexture:
	return cached("concrete", 256, 256, func(c: Control) -> void:
		c.draw_rect(Rect2(0, 0, 256, 256), Color("9c9a94"))
		_noise(c, 256, 256, 12000, 0.12)
	)


static func checker() -> ImageTexture:
	return cached("checker", 256, 64, func(c: Control) -> void:
		for y in 2:
			for x in 8:
				c.draw_rect(Rect2(x * 32, y * 32, 32, 32), Color("111111") if (x + y) % 2 else Color("f2f2f2"))
	, false)


## Blue Dutch motorway sign (ANWB style) with a red route shield.
static func sign(lines: Array, route: String) -> ImageTexture:
	_fonts()
	return cached("sign|%s|%s" % ["|".join(lines), route], 512, 256, func(c: Control) -> void:
		c.draw_rect(Rect2(0, 0, 512, 256), Color("123f8c"))
		c.draw_rect(Rect2(10, 10, 492, 236), Color("f2f2f2"), false, 6)
		for i in lines.size():
			c.draw_set_transform(Vector2(36, 90 + i * 72), 0, Vector2(0.86, 1))
			_text(c, font_sign, lines[i], 0, 0, 54, Color.WHITE)
		c.draw_set_transform(Vector2.ZERO)
		# Route shield
		c.draw_rect(Rect2(390, 168, 96, 56), Color("c4161c"))
		c.draw_rect(Rect2(392, 170, 92, 52), Color.WHITE, false, 4)
		_text(c, font_sign, route, 438, 210, 38, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		# Arrow
		c.draw_colored_polygon(PackedVector2Array([Vector2(438, 40), Vector2(468, 80), Vector2(448, 80), Vector2(448, 140),
			Vector2(428, 140), Vector2(428, 80), Vector2(408, 80)]), Color.WHITE)
	)


## Dutch place-name sign: blue with white border.
static func place_sign(place: String, sub := "") -> ImageTexture:
	_fonts()
	return cached("place|%s|%s" % [place, sub], 512, 224, func(c: Control) -> void:
		c.draw_rect(Rect2(0, 0, 512, 224), Color("123f8c"))
		c.draw_rect(Rect2(14, 14, 484, 196), Color.WHITE, false, 10)
		var size := 78
		while size > 40 and font_sign.get_string_size(place, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * 0.86 > 460:
			size -= 4
		c.draw_set_transform(Vector2(256, 120 if sub != "" else 140), 0, Vector2(0.86, 1))
		_text(c, font_sign, place, 0, 0, size, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		c.draw_set_transform(Vector2.ZERO)
		if sub != "":
			_text(c, font_sign, sub, 256, 180, 40, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	)


static func banner(text: String) -> ImageTexture:
	_fonts()
	return cached("banner|" + text, 1024, 160, func(c: Control) -> void:
		c.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(1024, 0), Vector2(1024, 160), Vector2(0, 160)]),
			PackedColorArray([Color("ff3d00"), Color("ffb300"), Color("ffb300"), Color("ff3d00")]))
		for x in range(0, 1024, 40):
			var odd := (x / 40) % 2 == 1
			c.draw_rect(Rect2(x, 0, 40, 18), Color("111111") if odd else Color.WHITE)
			c.draw_rect(Rect2(x, 142, 40, 18), Color.WHITE if odd else Color("111111"))
		var size := 104
		while size > 50 and font_banner.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > 960:
			size -= 4
		var w := font_banner.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		c.draw_string_outline(font_banner, Vector2(512 - w / 2, 118), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 16, Color("111111"))
		c.draw_string(font_banner, Vector2(512 - w / 2, 118), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.WHITE)
	, false)


## Apartment/office facade: a window grid, some windows lit (returns [colour map, emission map]).
static func facade(seed_value: int, wall: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 9301 + 49297
	var lit := []
	for i in 72:
		lit.append(rng.randf() < 0.35)
	var draw_grid := func(c: Control, glow: bool) -> void:
		var W := 128.0
		var H := 256.0
		if glow:
			c.draw_rect(Rect2(0, 0, W, H), Color.BLACK)
		else:
			c.draw_rect(Rect2(0, 0, W, H), Color(wall))
			_noise(c, W, H, 1500, 0.06)
		for y in 12:
			for x in 6:
				var px := 6 + x * (W - 12) / 6.0
				var py := 6 + y * (H - 12) / 12.0
				var w := (W - 12) / 6.0 - 6
				var h := (H - 12) / 12.0 - 8
				var on: bool = lit[y * 6 + x]
				if glow:
					if on:
						c.draw_rect(Rect2(px, py, w, h), Color("ffb860"))
				else:
					c.draw_rect(Rect2(px, py, w, h), Color("ffd9a0") if on else Color("1c2733"))
	var map := cached("facade%d" % seed_value, 128, 256, func(c: Control) -> void: draw_grid.call(c, false))
	var glow := cached("facade_glow%d" % seed_value, 128, 256, func(c: Control) -> void: draw_grid.call(c, true))
	return [map, glow]


## Dutch number plate: yellow with the blue NL strip.
static func plate(text: String) -> ImageTexture:
	_fonts()
	return cached("plate|" + text, 256, 56, func(c: Control) -> void:
		c.draw_rect(Rect2(0, 0, 256, 56), Color("f4c400"))
		c.draw_rect(Rect2(0, 0, 30, 56), Color("1b3fa0"))
		_text(c, font_sign, "NL", 6, 48, 14, Color("f4c400"))
		var size := 38
		while size > 20 and font_sign.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * 0.86 > 214:
			size -= 2
		c.draw_set_transform(Vector2(143, 42), 0, Vector2(0.86, 1))
		_text(c, font_sign, text, 0, 0, size, Color("111111"), HORIZONTAL_ALIGNMENT_CENTER)
		c.draw_set_transform(Vector2.ZERO)
		c.draw_rect(Rect2(1.5, 1.5, 253, 53), Color("111111"), false, 3)
	)


## Lettering for liveries and trailers.
static func text(label: String, bg: Color, fg: Color, w := 512, h := 128, size := 72, italic := false) -> ImageTexture:
	_fonts()
	return cached("text|%s|%s|%s|%d|%d|%d" % [label, bg.to_html(), fg.to_html(), w, h, size], w, h, func(c: Control) -> void:
		c.draw_rect(Rect2(0, 0, w, h), bg)
		var s := size
		while s > 16 and font_sign.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > w * 0.94:
			s -= 4
		var tw := font_sign.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x
		var skew := Transform2D(Vector2(1, 0), Vector2(-0.2 if italic else 0.0, 1), Vector2(w / 2.0, h / 2.0 + s * 0.36))
		c.draw_set_transform_matrix(skew)
		c.draw_string(font_sign, Vector2(-tw / 2, 0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, s, fg)
		c.draw_set_transform(Vector2.ZERO)
	)
