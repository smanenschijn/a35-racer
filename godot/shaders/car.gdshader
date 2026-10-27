shader_type spatial;
render_mode cull_disabled;
// Batched car material: base colour, metalness, roughness, clearcoat and emission come from vertex
// attributes, so a car with twenty materials draws in a handful of calls. On the paint: the livery
// (stickers), metallic flake, scratches where it got hit, and road grime low on the body.

#include "res://shaders/car_common.gdshaderinc"

uniform bool use_tex = false;
uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic;
uniform bool use_livery = false;
// Top half: the side view (u rear → front, v roof → sill); bottom half: seen from above (u right → left side
// of the car as seen from behind, v nose → tail).
uniform sampler2D livery : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 livery_box = vec4(-2.0, 2.0, 0.2, 1.3); // z min, z max, y min, y max of the painted body
uniform float livery_half_w = 0.9;
uniform float dirt = 0.15; // 0 clean .. 1 filthy
uniform float flake = 0.6; // metallic flake in the paint

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

vec4 livery_at(vec3 p, vec3 n) {
	float u_side = (p.z - livery_box.x) / (livery_box.y - livery_box.x);
	// Seen from the right (-x) the nose is on the viewer's left: mirror so text reads the right way round.
	if (n.x < 0.0) u_side = 1.0 - u_side;
	float v_side = (livery_box.w - p.y) / (livery_box.w - livery_box.z);
	vec4 side = texture(livery, vec2(u_side, v_side * 0.5));
	float u_top = 0.5 - p.x / (2.0 * livery_half_w);
	float v_top = (livery_box.y - p.z) / (livery_box.y - livery_box.x);
	vec4 top = texture(livery, vec2(u_top, 0.5 + v_top * 0.5));
	float ws = smoothstep(0.45, 0.75, abs(n.x));
	float wt = smoothstep(0.5, 0.8, n.y);
	vec4 o = side * ws + top * wt * (1.0 - ws);
	// Inside the half rows: don't bleed over the edges of the projection.
	o.a *= step(0.0, v_side) * step(v_side, 1.0) * step(0.0, u_side) * step(u_side, 1.0);
	return o;
}

void fragment() {
	vec3 base = mix(COLOR.rgb, paint.rgb, v_pbr.z);
	if (use_tex) {
		base *= texture(tex, UV).rgb;
	}
	float metal = v_pbr.x;
	float rough = v_pbr.y;
	float coat = v_pbr.z;
	vec3 emission = v_emi.rgb * car_light_level(v_emi.w);
	if (v_pbr.z > 0.5) {
		// Metallic flake: tiny facets that catch the light at different angles.
		float fl = car_hash(floor(v_obj * 220.0));
		base *= 1.0 + (fl - 0.5) * 0.12 * flake;
		metal = max(metal, 0.35 * flake);
		if (use_livery) {
			vec4 l = livery_at(v_obj, normalize(v_objn));
			base = mix(base, l.rgb, l.a);
			metal = mix(metal, 0.05, l.a);
			rough = mix(rough, 0.32, l.a);
		}
		float sc = car_scratch(v_obj);
		// Bare steel in the deep scratches, grey primer around them.
		vec3 bare = mix(vec3(0.42, 0.42, 0.44), vec3(0.68, 0.68, 0.7), smoothstep(0.6, 0.95, sc));
		base = mix(base, bare, sc);
		metal = mix(metal, 0.85, sc * sc);
		rough = mix(rough, 0.5, sc);
		coat *= 1.0 - sc;
	}
	// Road grime: thrown up by the wheels, so heavier low down and behind the wheel arches.
	if (dirt > 0.0 && v_pbr.y < 0.95) {
		float low = 1.0 - smoothstep(livery_box.z, livery_box.z + 0.45, v_obj.y);
		float n = car_noise(v_obj * vec3(5.0, 14.0, 3.0));
		float g = clamp(dirt * (low * 0.9 + 0.15) * (0.55 + n * 0.7), 0.0, 0.85);
		base = mix(base, vec3(0.16, 0.13, 0.1), g * 0.75);
		rough = mix(rough, 0.95, g);
		coat *= 1.0 - g;
	}
	ALBEDO = base;
	METALLIC = metal;
	ROUGHNESS = rough;
	EMISSION = emission;
	CLEARCOAT = coat;
	CLEARCOAT_ROUGHNESS = 0.08;
	// A touch of rim light so dark cars still read against the asphalt.
	RIM = 0.25 * v_pbr.z;
	RIM_TINT = 0.6;
}
