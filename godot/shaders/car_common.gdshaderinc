// Shared by the car shaders: per-car paint, light levels, lost parts and up to eight dents.
// CUSTOM0 = (metallic, roughness, paint, deform), CUSTOM1 = (emission rgb, light class + 8 * loose part).
#ifdef CAR_STATIC
// Wheels and calipers: no per-car state, so no per-instance slots (those are a limited resource).
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
instance uniform vec4 paint : source_color, instance_index(0) = vec4(1.0);
instance uniform vec4 lights : instance_index(1) = vec4(2.2, 1.2, 0.0, 0.0); // head, brake, beacon L, beacon R
instance uniform int gone : instance_index(2) = 0; // bit n set: loose part n + 1 has broken off
instance uniform vec4 dent0 : instance_index(3) = vec4(0.0); // (x, z, strength, -) in body space
instance uniform vec4 dent1 : instance_index(4) = vec4(0.0);
instance uniform vec4 dent2 : instance_index(5) = vec4(0.0);
instance uniform vec4 dent3 : instance_index(6) = vec4(0.0);
instance uniform vec4 dent4 : instance_index(7) = vec4(0.0);
instance uniform vec4 dent5 : instance_index(8) = vec4(0.0);
instance uniform vec4 dent6 : instance_index(9) = vec4(0.0);
instance uniform vec4 dent7 : instance_index(10) = vec4(0.0);
#endif

varying vec4 v_pbr;
varying vec4 v_emi;

float car_hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

// (Varyings can only be written in vertex() itself: pbr and emi come back out.)
void car_vertex(inout vec3 vertex, inout vec3 normal, vec4 c0, vec4 c1, out vec4 pbr, out vec4 emi) {
	pbr = c0;
	float loose = floor(c1.w / 8.0 + 0.01);
	emi = vec4(c1.rgb, c1.w - loose * 8.0);
	vec3 rest = vertex;
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
		vertex = vec3(0.0); // collapsed: the part is gone, the mesh stays one draw call
	}
}

float car_light_level(float cls) {
	return cls < 0.5 ? 1.0 : cls < 1.5 ? lights.x : cls < 2.5 ? lights.y : cls < 3.5 ? lights.z : lights.w;
}
