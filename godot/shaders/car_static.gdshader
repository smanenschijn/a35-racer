shader_type spatial;
render_mode cull_disabled;
// Wheels and brake calipers: the batched car material without per-car state.


#define CAR_STATIC
#include "res://shaders/car_common.gdshaderinc"

uniform bool use_tex = false;
uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic;

void vertex() {
	vec4 pbr;
	vec4 emi;
	car_vertex(VERTEX, NORMAL, CUSTOM0, CUSTOM1, pbr, emi);
	v_pbr = pbr;
	v_emi = emi;
}

void fragment() {
	vec3 base = mix(COLOR.rgb, paint.rgb, v_pbr.z);
	if (use_tex) {
		base *= texture(tex, UV).rgb;
	}
	ALBEDO = base;
	METALLIC = v_pbr.x;
	ROUGHNESS = v_pbr.y;
	EMISSION = v_emi.rgb * car_light_level(v_emi.w);
	CLEARCOAT = v_pbr.z;
	CLEARCOAT_ROUGHNESS = 0.12;
}
