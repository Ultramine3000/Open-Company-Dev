shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Textures
uniform sampler2D snow_albedo : hint_default_white;
uniform sampler2D dirt_albedo : hint_default_white;
uniform sampler2D snow_normal : hint_normal;
uniform sampler2D dirt_normal : hint_normal;
uniform sampler2D height_map : hint_default_white;
uniform sampler2D roughness_map : hint_default_white;

// Snow Properties
uniform float snow_amount : hint_range(0.0, 1.0) = 0.7;
uniform float snow_depth : hint_range(0.0, 0.5) = 0.1;
uniform float snow_roughness : hint_range(0.0, 1.0) = 0.4;
uniform vec4 snow_tint = vec4(1.1, 1.1, 1.2, 1.0);
uniform float snow_brightness : hint_range(0.5, 3.0) = 1.8;

// Ground Properties
uniform vec4 dirt_tint = vec4(0.4, 0.3, 0.2, 1.0);
uniform float dirt_roughness : hint_range(0.0, 1.0) = 0.8;

// Detail and Scaling
uniform float texture_scale : hint_range(0.1, 10.0) = 1.0;
uniform float detail_scale : hint_range(0.1, 5.0) = 3.0;
uniform float normal_strength : hint_range(0.0, 3.0) = 1.0;
uniform float displacement_strength : hint_range(0.0, 0.1) = 0.02;

// Environmental Effects
uniform float snow_slope_factor : hint_range(0.0, 2.0) = 1.5;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;
uniform float specular_value : hint_range(0.0, 1.0) = 0.5;

// Animation (optional)
uniform float time_scale : hint_range(0.0, 1.0) = 0.1;

varying vec3 world_normal;
varying vec3 world_position;
varying float snow_factor;

// Improved noise functions
vec2 hash22(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    
    return mix(mix(dot(hash22(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0)),
                   dot(hash22(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
               mix(dot(hash22(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)),
                   dot(hash22(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    for(int i = 0; i < 5; i++) {
        value += amplitude * noise(p * frequency);
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    return value;
}

vec3 blend_normals(vec3 n1, vec3 n2) {
    return normalize(vec3(n1.xy + n2.xy, n1.z * n2.z));
}

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
    
    // Calculate snow accumulation based on surface angle
    float slope = 1.0 - abs(dot(world_normal, vec3(0.0, 1.0, 0.0)));
    slope = pow(slope, snow_slope_factor);
    
    // Sample height for additional variation
    vec2 world_uv = world_position.xz * 0.1;
    float height_sample = texture(height_map, world_uv).r;
    float noise_variation = fbm(world_uv * 2.0) * 0.5 + 0.5;
    
    // Combine factors for final snow placement
    snow_factor = snow_amount * (1.0 - slope) * height_sample * noise_variation;
    snow_factor = smoothstep(0.2, 0.8, snow_factor);
    
    // Vertex displacement for snow buildup
    vec3 displacement = world_normal * snow_factor * displacement_strength;
    VERTEX += (inverse(MODEL_MATRIX) * vec4(displacement, 0.0)).xyz;
}

void fragment() {
    vec2 base_uv = UV * texture_scale;
    vec2 detail_uv = UV * detail_scale;
    
    // Time-based variation for subtle animation
    float time_offset = TIME * time_scale;
    vec2 animated_uv = detail_uv + vec2(sin(time_offset * 0.1), cos(time_offset * 0.15)) * 0.01;
    
    // Sample base textures
    vec4 snow_tex = texture(snow_albedo, base_uv);
    vec4 dirt_tex = texture(dirt_albedo, base_uv);
    
    // Sample normal maps
    vec3 snow_norm = texture(snow_normal, base_uv).rgb * 2.0 - 1.0;
    vec3 dirt_norm = texture(dirt_normal, base_uv).rgb * 2.0 - 1.0;
    
    // Create procedural detail normal for snow
    float detail_noise1 = noise(animated_uv * 8.0);
    float detail_noise2 = noise(animated_uv * 16.0);
    vec3 detail_normal = vec3(
        detail_noise1 - noise(animated_uv * 8.0 + vec2(0.1, 0.0)),
        detail_noise2 - noise(animated_uv * 16.0 + vec2(0.0, 0.1)),
        1.0
    ) * 0.5;
    detail_normal = normalize(detail_normal);
    
    // Enhance snow normal with procedural detail
    vec3 enhanced_snow_normal = blend_normals(snow_norm, detail_normal);
    
    // Blend normals based on snow factor
    vec3 final_normal = mix(dirt_norm, enhanced_snow_normal, snow_factor);
    final_normal *= normal_strength;
    
    // Color blending with enhanced brightness
    vec4 brightened_snow = snow_tex * snow_tint * snow_brightness;
    vec4 final_albedo = mix(dirt_tex * dirt_tint, brightened_snow, snow_factor);
    
    // Add subtle color variation
    float color_noise = fbm(detail_uv * 3.0) * 0.1;
    final_albedo.rgb += vec3(color_noise * 0.5, color_noise * 0.3, color_noise * 0.2);
    
    // Additional brightness boost for snow areas
    final_albedo.rgb += vec3(snow_factor * 0.2);
    
    // Roughness blending
    float base_roughness = texture(roughness_map, base_uv).r;
    float final_roughness = mix(dirt_roughness * base_roughness, snow_roughness, snow_factor);
    
    // Enhanced sparkle effect for snow areas
    float sparkle = 0.0;
    if(snow_factor > 0.3) {
        float sparkle_noise = noise(detail_uv * 25.0 + time_offset);
        sparkle = smoothstep(0.85, 1.0, sparkle_noise) * snow_factor;
        final_albedo.rgb += vec3(sparkle * 0.5); // Increased sparkle brightness
        final_roughness -= sparkle * 0.4;
    }
    
    // Subsurface scattering effect for snow
    float subsurface = snow_factor * 0.3;
    
    // Output material properties
    ALBEDO = final_albedo.rgb;
    NORMAL = final_normal;
    ROUGHNESS = clamp(final_roughness, 0.0, 1.0);
    METALLIC = metallic_value;
    SPECULAR = specular_value + sparkle * 0.2;
}