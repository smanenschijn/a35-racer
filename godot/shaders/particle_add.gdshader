shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, fog_disabled;
// Additive variant (sparks, fire) for the particle pools. Size in INSTANCE_CUSTOM.x, colour * intensity in COLOR.
uniform float softness = 0.0;

varying float v_alpha;
varying float v_intensity;

void vertex() {
	// Billboard: keep the instance position, face the camera, scale by the particle size.
	float size = INSTANCE_CUSTOM.x;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX *= size;
	v_alpha = INSTANCE_CUSTOM.y;
	v_intensity = INSTANCE_CUSTOM.z;
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = smoothstep(1.0, softness, d) * v_alpha;
	if (a < 0.003) discard;
	ALBEDO = COLOR.rgb * v_intensity;
	ALPHA = a;
}
