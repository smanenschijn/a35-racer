shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;
// Soft round billboard sprites for the particle pools. Size in INSTANCE_CUSTOM.x, colour * intensity in COLOR.
uniform float softness = 0.0;
uniform float turbulence = 0.0; // 0 = round sprites, 1 = ragged flame/smoke edges

varying float v_alpha;
varying float v_intensity;
varying float v_seed;

void vertex() {
	// Billboard: keep the instance position, face the camera, scale by the particle size.
	float size = INSTANCE_CUSTOM.x;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX *= size;
	v_alpha = INSTANCE_CUSTOM.y;
	v_intensity = INSTANCE_CUSTOM.z;
	v_seed = INSTANCE_CUSTOM.w;
}

float p_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float p_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(p_hash(i), p_hash(i + vec2(1, 0)), f.x), mix(p_hash(i + vec2(0, 1)), p_hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	// Ragged, turbulent edge instead of a perfect disc (each particle its own pattern).
	vec2 q = UV - 0.5;
	float n = p_noise(q * 5.0 + v_seed * 17.0) * 0.6 + p_noise(q * 11.0 - v_seed * 9.0) * 0.4;
	float d = length(q) * 2.0 * (0.8 + turbulence * (n - 0.5) * 1.2);
	float a = smoothstep(1.0, softness, d) * v_alpha;
	a *= mix(1.0, 0.55 + n * 0.9, turbulence);
	if (a < 0.003) discard;
	ALBEDO = COLOR.rgb * v_intensity;
	ALPHA = a;
}
