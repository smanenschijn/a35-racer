// Shared by the car shaders: per-car paint, light levels, lost parts, up to eight dents, the livery
// (stickers projected from the side and from above) and wear (scratches at the dents, dirt low down).
// CUSTOM0 = (metallic, roughness, paint, deform), CUSTOM1 = (emission rgb, light class + 8 * loose part).
// Per-car state lives in plain uniforms on a per-car copy of the material (instance uniforms run out
// on WebGL with ~90 cars on the road).
#ifdef CAR_STATIC
const vec4 paint = vec4(1.0);
const vec4 lights = vec4(2.2, 1.2, 0.0, 0.0);
const int gone = 0;
const vec4 dent0 = vec4(0.0);
const vec4 dent1 = vec4(0.0);
const vec4 dent2 = vec4(0.0);
const vec4 dent3 = vec4(0.0);
const vec4 dent4 = vec4(0.0);
const vec4 dent5 = vec4(0.0);
const vec4 dent6 = vec4(0.0);
const vec4 dent7 = vec4(0.0);
#else
uniform vec4 paint : source_color = vec4(1.0);
uniform vec4 lights = vec4(2.2, 1.2, 0.0, 0.0); // head, brake, beacon L, beacon R
uniform int gone = 0; // bit n set: loose part n + 1 has broken off
uniform vec4 dent0 = vec4(0.0); // (x, z, strength, -) in body space
uniform vec4 dent1 = vec4(0.0);
uniform vec4 dent2 = vec4(0.0);
uniform vec4 dent3 = vec4(0.0);
uniform vec4 dent4 = vec4(0.0);
uniform vec4 dent5 = vec4(0.0);
uniform vec4 dent6 = vec4(0.0);
uniform vec4 dent7 = vec4(0.0);
#endif

varying vec4 v_pbr;
varying vec4 v_emi;
varying vec3 v_obj; // undented position in body space (+x = the car's left, +z = forward)
varying vec3 v_objn;

float car_hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

float car_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = car_hash(i);
	float n100 = car_hash(i + vec3(1.0, 0.0, 0.0));
	float n010 = car_hash(i + vec3(0.0, 1.0, 0.0));
	float n110 = car_hash(i + vec3(1.0, 1.0, 0.0));
	float n001 = car_hash(i + vec3(0.0, 0.0, 1.0));
	float n101 = car_hash(i + vec3(1.0, 0.0, 1.0));
	float n011 = car_hash(i + vec3(0.0, 1.0, 1.0));
	float n111 = car_hash(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y), mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

// (Varyings can only be written in vertex() itself: pbr, emi and the rest pose come back out.)
void car_vertex(inout vec3 vertex, inout vec3 normal, vec4 c0, vec4 c1, out vec4 pbr, out vec4 emi, out vec3 rest_pos, out vec3 rest_n) {
	pbr = c0;
	float loose = floor(c1.w / 8.0 + 0.01);
	emi = vec4(c1.rgb, c1.w - loose * 8.0);
	vec3 rest = vertex;
	rest_pos = vertex;
	rest_n = normal;
	if (c0.w > 0.5) {
		vec4 dents[8] = vec4[8](dent0, dent1, dent2, dent3, dent4, dent5, dent6, dent7);
		for (int i = 0; i < 8; i++) {
			vec4 d = dents[i];
			if (d.z <= 0.0) continue;
			float dist = length(vertex.xz - d.xy);
			if (dist > 1.1) continue;
			// Push towards the car's centre line, plus a little random crumple.
			float f = pow(1.0 - dist / 1.1, 2.0) * d.z;
			vec2 dir = vertex.xz / max(length(vertex.xz), 0.001);
			vertex.xz -= dir * f * 0.8;
			vertex.y -= f * 0.25 * car_hash(rest);
			normal = normalize(normal + (vec3(car_hash(rest + 1.3), car_hash(rest + 2.7), car_hash(rest + 4.1)) - 0.5) * f * 2.5);
		}
	}
	if (loose > 0.5 && ((gone >> (int(loose) - 1)) & 1) != 0) {
		vertex = vec3(0.0); // collapsed: the part is gone (a copy flies off as debris), still one draw call
	}
}

// How badly the paint is scraped here: strongest around the dents, in streaks along the car.
float car_scratch(vec3 p) {
#ifdef CAR_STATIC
	return 0.0;
#else
	vec4 dents[8] = vec4[8](dent0, dent1, dent2, dent3, dent4, dent5, dent6, dent7);
	float s = 0.0;
	for (int i = 0; i < 8; i++) {
		vec4 d = dents[i];
		if (d.z <= 0.0) continue;
		float dist = length(p.xz - d.xy);
		s = max(s, (1.0 - smoothstep(0.15, 0.95, dist)) * min(1.0, d.z * 3.0));
	}
	if (s <= 0.0) return 0.0;
	// Long thin streaks (scraped along a rail or another car) plus blotches of bare primer.
	float streak = car_noise(vec3(p.x * 6.0, p.y * 70.0, p.z * 2.5));
	float blotch = car_noise(p * 9.0);
	return clamp(s * (smoothstep(0.45, 0.8, streak) * 0.9 + smoothstep(0.55, 0.75, blotch)), 0.0, 1.0);
#endif
}

float car_light_level(float cls) {
	return cls < 0.5 ? 1.0 : cls < 1.5 ? lights.x : cls < 2.5 ? lights.y : cls < 3.5 ? lights.z : lights.w;
}
