shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_opaque;
// Car windows: same vertex layout and per-car dents as car.gdshader, but see-through.

#include "res://shaders/car_common.gdshaderinc"

void vertex() {
	vec4 pbr;
	vec4 emi;
	car_vertex(VERTEX, NORMAL, CUSTOM0, CUSTOM1, pbr, emi);
	v_pbr = pbr;
	v_emi = emi;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a;
	METALLIC = v_pbr.x;
	ROUGHNESS = v_pbr.y;
}
