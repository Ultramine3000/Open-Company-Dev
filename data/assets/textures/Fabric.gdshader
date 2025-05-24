shader_type spatial;

// Simple fabric properties
uniform vec3 fabric_color : source_color = vec3(0.6, 0.4, 0.3);
uniform float fabric_roughness : hint_range(0.5, 1.0) = 0.8;
uniform float fabric_scale : hint_range(200, 400) = 200.0;

// UV Override settings
uniform bool override_uvs = false;
uniform int uv_mode : hint_range(0, 2) = 0; // 0=XY, 1=XZ, 2=YZ
uniform float uv_scale : hint_range(0.1, 10.0) = 1.0;
uniform vec2 uv_offset = vec2(0.0, 0.0);

// Dirt and wear
uniform float dirt_base : hint_range(0.0, 1.0) = 0.1;
uniform float dirt_scale : hint_range(20, 40) = 20.0;
uniform vec3 dirt_color : source_color = vec3(0.2, 0.15, 0.1);
uniform float wear_amount : hint_range(0.0, 1.0) = 0.2;
uniform float wear_scale : hint_range(0.5, 5.0) = 1.5;

// Time-based dirt accumulation
uniform float dirt_time : hint_range(0.0, 100.0) = 0.0;

// Smooth noise function
float smooth_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f); // Smooth interpolation
    
    float a = fract(sin(dot(i, vec2(12.9898, 78.233))) * 43758.5453);
    float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(12.9898, 78.233))) * 43758.5453);
    float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(12.9898, 78.233))) * 43758.5453);
    float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(12.9898, 78.233))) * 43758.5453);
    
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

varying vec3 world_position;

void vertex() {
    // Calculate and pass world position to fragment shader
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec2 uv;
    
    // Override UVs if enabled
    if (override_uvs) {
        if (uv_mode == 0) {
            uv = world_position.xy; // XY plane
        } else if (uv_mode == 1) {
            uv = world_position.xz; // XZ plane (top-down)
        } else {
            uv = world_position.yz; // YZ plane (side view)
        }
        uv = uv * uv_scale + uv_offset;
    } else {
        uv = UV; // Use mesh UVs
    }
    
    // Clean fabric base with subtle variation
    float fabric_variation = smooth_noise(uv * fabric_scale) * 0.1;
    
    // Time-based dirt accumulation
    float dirt_progress = clamp(dirt_time / 100.0, 0.0, 1.0);
    float total_dirt = dirt_base + dirt_progress * 0.8; // Max dirt at 90%
    
    // Smooth dirt pattern
    float dirt_pattern = smooth_noise(uv * dirt_scale);
    float dirt_mask = smoothstep(0.6 - dirt_progress * 0.4, 0.9, dirt_pattern) * total_dirt;
    
    // Smooth wear pattern
    float wear_pattern = smooth_noise(uv * wear_scale);
    float wear_mask = smoothstep(0.7, 1.0, wear_pattern) * wear_amount;
    
    // Combine colors cleanly
    vec3 base_color = fabric_color + fabric_variation;
    vec3 final_color = mix(base_color, dirt_color, dirt_mask);
    final_color = mix(final_color, final_color * 1.4, wear_mask);
    
    ALBEDO = final_color;
    ROUGHNESS = fabric_roughness;
    METALLIC = 0.0;
}