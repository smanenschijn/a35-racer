shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_opaque;
// Car windows: same vertex layout and per-car dents as car.gdshader, but see-through.

#include "res://shaders/car_common.gdshaderinc"

void vertex() {
	vec4 pbr;
	vec4 emi;
	vec3 rp;
	vec3 rn;
	car_vertex(VERTEX, NORMAL, CUSTOM0, CUSTOM1, pbr, emi, rp, rn);
	v_pbr = pbr;
	v_emi = emi;
	v_obj = rp;
	v_objn = rn;
}

void fragment() {
	// Hit hard enough nearby: crazed, milky safety glass.
	float sc = car_scratch(v_obj);
	float web = smoothstep(0.62, 0.66, car_noise(v_obj * 30.0)) + smoothstep(0.7, 0.72, car_noise(v_obj * 11.0 + 3.0));
	float crack = clamp(sc * (0.45 + web), 0.0, 1.0);
	ALBEDO = mix(COLOR.rgb, vec3(0.78, 0.8, 0.82), crack * 0.8);
	ALPHA = mix(COLOR.a, 0.92, crack * 0.85);
	METALLIC = v_pbr.x;
	ROUGHNESS = v_pbr.y;
}
