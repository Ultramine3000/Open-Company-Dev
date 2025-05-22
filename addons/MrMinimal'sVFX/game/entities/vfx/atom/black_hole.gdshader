shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;
render_mode unshaded;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform float black_hole_radius : hint_range(0.0, 1.0) = 0.02;
uniform float distortion_strength : hint_range(0.0, 2.0) = 2.0;

uniform float glitch_intensity : hint_range(0.0, 1.0) = 0.5;
uniform float time_scale : hint_range(0.1, 5.0) = 1.0;
uniform float noise_scale : hint_range(0.1, 10.0) = 2.0;
uniform float noise_intensity : hint_range(0.0, 1.0) = 0.5;


uniform bool enable_glitch = false;
uniform float outer_fade_start : hint_range(0.0, 1.0) = 0.0;
uniform float outer_fade_end : hint_range(0.0, 1.0) = 0.5;

varying vec2 world_uv;
varying vec3 world_position;
varying vec4 screen_position;

float random(vec2 st) {
	return fract(sin(dot(st.xy, vec2(12.9898,78.233))) * 43758.5453123);
}

vec2 rotate(vec2 uv, float angle) {
	float s = sin(angle);
	float c = cos(angle);
	mat2 rotation = mat2(vec2(c, -s), vec2(s, c));
	return uv * rotation;
}

void vertex() {
	screen_position = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_uv = UV;

	mat4 modified_model_view = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);
	MODELVIEW_MATRIX = modified_model_view;
}

void fragment() {
	vec2 uv = world_uv;
	vec2 centered_uv = uv - vec2(0.5);
	float dist = length(centered_uv);
	
	vec2 screen_uv = screen_position.xy / screen_position.w;
	screen_uv = screen_uv * 0.5 + 0.5;
	
	// Black hole distortion
	vec2 distorted_uv = screen_uv;
	if (dist > black_hole_radius) {
		vec2 dir = normalize(centered_uv);
		float distortion = 1.0 - (black_hole_radius / dist);
		distorted_uv = screen_uv - dir * distortion * distortion_strength * 0.1;
	}
	
	// Rotating UV for ring
	float rotation_speed = TIME * 0.2;
	vec2 rotated_uv = rotate(centered_uv, rotation_speed);
	
	// Ring effect

	// Glitch effect (only if enabled)
	float glitch_offset = 0.0;
	if (enable_glitch) {
		float time = TIME * time_scale;
		float glitch = random(vec2(floor(time * 10.0), floor(uv.y * 20.0)));
		glitch_offset = (glitch - 0.5) * glitch_intensity * 0.1;
	}
	
	// Ring color
	vec3 ring_color = mix(
		vec3(1.0, 0.0, 0.0),  // Red
		vec3(1.0),            // White
		step(0.5, random(vec2(floor(TIME * 5.0), floor(dist * 20.0))))
	);
	
	// Final color composition
	vec3 screen_color = texture(SCREEN_TEXTURE, distorted_uv + vec2(glitch_offset, 0.0)).rgb;
	vec3 final_color = screen_color;
	
	// Black hole center with soft edges
	float black_hole_edge = black_hole_radius;
	if (dist < black_hole_edge) {
		float edge_fade = smoothstep(black_hole_edge, black_hole_edge, dist);
		final_color = mix(vec3(0.0), screen_color, edge_fade * 0.2);
	}
	
	// Glow effect
	float glow = smoothstep(black_hole_radius, black_hole_radius * 2.0, dist);
	final_color += vec3(0.0, 0.0, 0.0) * (1.0 - glow);
	
	// Soft outer edge fade
	float edge_fade = 1.0 - smoothstep(outer_fade_start, outer_fade_end, dist);
	
	ALBEDO = final_color;
	ALPHA = edge_fade;
}