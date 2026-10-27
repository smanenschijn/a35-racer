shader_type spatial;
render_mode cull_disabled;
// Trees and other vegetation: colour from the vertices (times the instance tint), crowns sway in the
// wind. Vertex alpha is the sway weight (0 at the trunk, 1 at the top of the crown).

uniform float wind = 1.0;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = dot(world.xz, vec2(0.13, 0.09));
	float w = COLOR.a * wind;
	VERTEX.x += sin(TIME * 1.3 + phase) * 0.18 * w;
	VERTEX.z += cos(TIME * 1.1 + phase * 1.3) * 0.12 * w;
	VERTEX.y += sin(TIME * 2.7 + phase * 3.0 + VERTEX.x) * 0.04 * w;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
	// Light through the leaves from behind.
	BACKLIGHT = vec3(0.18, 0.22, 0.08) * COLOR.a;
}
