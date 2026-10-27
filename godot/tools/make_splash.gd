extends SceneTree
## Draws the boot splash logo (assets/splash.png): "A35" in yellow with a blue drop shadow, "RACER" in
## white, a road running into the distance, on a transparent background.
##   Godot --path godot -s res://tools/make_splash.gd

const W := 1200
const H := 900


class Logo:
	extends Control
	var font: Font

	func _draw() -> void:
		var big := 330
		var small := 150
		var text_a := "A35"
		var wa := font.get_string_size(text_a, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
		var pa := Vector2(W / 2.0 - wa / 2.0, 380)
		# Road towards the horizon behind the letters.
		draw_colored_polygon(PackedVector2Array([Vector2(W / 2.0 - 70, 560), Vector2(W / 2.0 + 70, 560),
			Vector2(W / 2.0 + 230, H), Vector2(W / 2.0 - 230, H)]), Color("2b2d30"))
		for side in [-1.0, 1.0]:
			draw_line(Vector2(W / 2.0 + side * 64, 560), Vector2(W / 2.0 + side * 212, H), Color("e9e9e2"), 6)
		for k in 4:
			var y0 := 590.0 + k * 80
			var w := 10.0 + k * 5
			draw_rect(Rect2(W / 2.0 - w / 2, y0, w, 40 + k * 8), Color("ffd400"))
		# A35: blue shadow, black outline, yellow face.
		draw_string_outline(font, pa + Vector2(16, 14), text_a, HORIZONTAL_ALIGNMENT_LEFT, -1, big, 22, Color("1f3fff"))
		draw_string(font, pa + Vector2(16, 14), text_a, HORIZONTAL_ALIGNMENT_LEFT, -1, big, Color("1f3fff"))
		draw_string_outline(font, pa, text_a, HORIZONTAL_ALIGNMENT_LEFT, -1, big, 22, Color("111111"))
		draw_string(font, pa, text_a, HORIZONTAL_ALIGNMENT_LEFT, -1, big, Color("ffd400"))
		var text_r := "RACER"
		var wr := font.get_string_size(text_r, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
		var pr := Vector2(W / 2.0 - wr / 2.0, 545)
		draw_string_outline(font, pr, text_r, HORIZONTAL_ALIGNMENT_LEFT, -1, small, 16, Color("111111"))
		draw_string(font, pr, text_r, HORIZONTAL_ALIGNMENT_LEFT, -1, small, Color.WHITE)


func _initialize() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var logo := Logo.new()
	logo.font = load("res://assets/fonts/Bangers-Regular.ttf")
	logo.size = Vector2(W, H)
	vp.add_child(logo)
	root.add_child(vp)
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.save_png("res://assets/splash.png")
	print("splash written: ", img.get_size())
	quit()
