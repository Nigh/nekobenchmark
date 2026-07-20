shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Overwatch practice-range style: muted surface + thin grid lines that fade with distance.
uniform vec3 base_color: source_color = vec3(0.62, 0.63, 0.65);
uniform vec3 line_color: source_color = vec3(0.50, 0.51, 0.54);
uniform float tile_size = 3.0;
uniform float line_width = 0.04;
uniform float fade_start = 10.0;
uniform float fade_end = 26.0;
uniform float roughness_val = 0.92;

varying vec3 world_pos;
varying vec3 world_nrm;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = MODEL_NORMAL_MATRIX * NORMAL;
}

float line_mask(float coord, float width_world) {
	float cell = abs(fract(coord / tile_size) - 0.5) * 2.0;
	float half_w = width_world / tile_size;
	float aa = fwidth(coord / tile_size) * 1.5;
	return 1.0 - smoothstep(half_w, half_w + aa, cell);
}

void fragment() {
	vec3 n = normalize(abs(world_nrm));
	float wx = pow(n.x, 8.0);
	float wy = pow(n.y, 8.0);
	float wz = pow(n.z, 8.0);
	float wsum = max(wx + wy + wz, 1e-5);
	wx /= wsum;
	wy /= wsum;
	wz /= wsum;

	float lx = line_mask(world_pos.x, line_width);
	float ly = line_mask(world_pos.y, line_width);
	float lz = line_mask(world_pos.z, line_width);
	// Face-aligned grid: floor uses XZ, walls use the two tangent axes.
	float grid = clamp((lx + lz) * wy + (ly + lz) * wx + (lx + ly) * wz, 0.0, 1.0);

	float dist = distance(world_pos, CAMERA_POSITION_WORLD);
	float fade = 1.0 - smoothstep(fade_start, fade_end, dist);

	ALBEDO = mix(base_color, line_color, grid * fade);
	ROUGHNESS = roughness_val;
	SPECULAR = 0.15;
}
