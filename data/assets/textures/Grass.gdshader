shader_type spatial;
render_mode specular_schlick_ggx, vertex_lighting, cull_disabled, depth_draw_opaque, shadows_disabled;

// Detailed Grass Shader for Plane Mesh
// Features: Individual grass blades, wind animation, color variation, realistic lighting

varying vec3 world_position;
varying vec3 world_normal;
varying float blade_height;
varying float blade_width;
varying vec2 blade_uv;

uniform float grass_density : hint_range(0.1, 2.0) = 1.0;
uniform float grass_height : hint_range(0.1, 2.0) = 0.8;
uniform float grass_width : hint_range(0.01, 0.1) = 0.03;
uniform float wind_strength : hint_range(0.0, 2.0) = 0.5;
uniform float wind_speed : hint_range(0.1, 3.0) = 1.0;
uniform vec2 wind_direction = vec2(1.0, 0.0);
uniform float color_variation : hint_range(0.0, 1.0) = 0.3;
uniform float grass_bend : hint_range(0.0, 1.0) = 0.4;
uniform float texture_scale : hint_range(0.1, 10.0) = 2.0;
uniform float roughness_grass : hint_range(0.6, 1.0) = 0.9;

// Websafe grass color palette
const vec3 GRASS_DARK = vec3(0.0, 0.4, 0.0);       // #006600
const vec3 GRASS_MEDIUM = vec3(0.2, 0.6, 0.1);     // #339911
const vec3 GRASS_BRIGHT = vec3(0.4, 0.8, 0.2);     // #66CC33
const vec3 GRASS_YELLOW = vec3(0.6, 0.8, 0.2);     // #99CC33
const vec3 GRASS_BROWN = vec3(0.4, 0.6, 0.2);      // #669933
const vec3 GRASS_TIPS = vec3(0.8, 0.9, 0.4);       // #CCE566

// Advanced noise functions
float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 hash22(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)),
             dot(p, vec2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453123);
}

float noise2d(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm2d(vec2 p, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    
    for(int i = 0; i < octaves; i++) {
        value += amplitude * noise2d(p * frequency);
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    return value;
}

// Generate grass blade shape
float grass_blade_shape(vec2 uv, float width_factor) {
    // Blade tapers from bottom to top
    float blade_width_local = width_factor * (1.0 - uv.y * 0.8);
    
    // Create blade edges
    float blade_shape = smoothstep(blade_width_local, blade_width_local * 0.7, abs(uv.x));
    
    // Taper to point at tip
    blade_shape *= smoothstep(1.0, 0.9, uv.y);
    
    // Add some blade texture/ridges
    float ridge = sin(uv.y * 20.0) * 0.1;
    blade_shape *= (1.0 + ridge * uv.y);
    
    return blade_shape;
}

void vertex() {
    vec4 world_pos = MODEL_MATRIX * vec4(VERTEX, 1.0);
    world_position = world_pos.xyz;
    world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
    
    // Create grass blade coordinates
    vec2 grass_coord = world_position.xz * texture_scale * grass_density;
    vec2 cell = floor(grass_coord);
    vec2 local_uv = fract(grass_coord);
    
    // Multiple grass blades per cell
    vec2 blade_id = floor(local_uv * 3.0); // 3x3 blades per cell
    vec2 blade_local = fract(local_uv * 3.0);
    
    vec2 blade_seed = cell + blade_id * 0.1;
    vec2 blade_random = hash22(blade_seed);
    
    // Grass blade properties
    blade_height = grass_height * (0.7 + blade_random.x * 0.6);
    blade_width = grass_width * (0.8 + blade_random.y * 0.4);
    
    // Skip some blades for natural variation by making them very small
    if(blade_random.x < 0.3) {
        blade_height *= 0.001;
        blade_width *= 0.001;
    }
    
    // Position blade within cell with some randomness
    vec2 blade_offset = (blade_random - 0.5) * 0.3;
    vec2 final_pos = (blade_local - 0.5 + blade_offset) / (texture_scale * grass_density);
    
    // Create blade geometry
    blade_uv = UV;
    blade_uv.x = (blade_uv.x - 0.5) * 2.0; // -1 to 1 for blade width
    
    // Scale and position the blade
    VERTEX.x = world_position.x + final_pos.x + blade_uv.x * blade_width;
    VERTEX.z = world_position.z + final_pos.y;
    VERTEX.y = world_position.y + blade_uv.y * blade_height;
    
    // Wind animation
    float time = TIME * wind_speed;
    vec2 wind_pos = world_position.xz * 0.1;
    float wind_noise = fbm2d(wind_pos + vec2(time * 0.5), 4);
    float wind_turbulence = fbm2d(wind_pos * 2.0 + vec2(time * 1.2), 3);
    
    // Wind affects grass more at the top
    float wind_factor = blade_uv.y * blade_uv.y * wind_strength;
    vec2 wind_offset = normalize(wind_direction) * wind_noise * wind_factor * 0.3;
    wind_offset += vec2(sin(time * 3.0 + blade_random.x * 6.28), 
                       cos(time * 2.0 + blade_random.y * 6.28)) * wind_turbulence * wind_factor * 0.1;
    
    VERTEX.x += wind_offset.x;
    VERTEX.z += wind_offset.y;
    
    // Natural grass bend (gravity effect)
    float bend_factor = blade_uv.y * blade_uv.y * grass_bend;
    VERTEX.x += bend_factor * blade_random.x * 0.1;
    VERTEX.z += bend_factor * blade_random.y * 0.1;
    
    // Recalculate world position after transformation
    world_position = VERTEX;
    
    // Calculate normal for blade (pointing mostly up with slight variation)
    vec3 blade_normal = vec3(blade_uv.x * 0.3, 1.0, 0.0);
    blade_normal += vec3(wind_offset.x * 2.0, 0.0, wind_offset.y * 2.0);
    NORMAL = normalize(blade_normal);
    world_normal = NORMAL;
}

void fragment() {
    // Early discard for blade shape
    float blade_alpha = grass_blade_shape(blade_uv, 1.0);
    if(blade_alpha < 0.1) discard;
    
    // Get grass position for variation
    vec2 grass_pos = world_position.xz * texture_scale;
    vec2 cell_pos = floor(grass_pos);
    
    // Color variation based on position and height
    float color_noise = fbm2d(grass_pos * 0.5, 4);
    float height_factor = blade_uv.y;
    
    // Base grass color
    vec3 grass_color = mix(GRASS_DARK, GRASS_MEDIUM, color_noise);
    grass_color = mix(grass_color, GRASS_BRIGHT, height_factor * 0.7);
    
    // Add color variation
    float variation = hash21(cell_pos) * color_variation;
    if(variation < 0.33) {
        grass_color = mix(grass_color, GRASS_YELLOW, variation * 3.0 * 0.4);
    } else if(variation < 0.66) {
        grass_color = mix(grass_color, GRASS_BROWN, (variation - 0.33) * 3.0 * 0.3);
    }
    
    // Grass tips are lighter
    grass_color = mix(grass_color, GRASS_TIPS, smoothstep(0.7, 1.0, height_factor) * 0.6);
    
    // Add subtle blade striping
    float stripe = sin(blade_uv.y * 15.0) * 0.1 + 1.0;
    grass_color *= stripe;
    
    // Fresnel effect for more realistic look
    vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_position);
    float fresnel = 1.0 - max(0.0, dot(world_normal, view_dir));
    grass_color = mix(grass_color, grass_color * 1.2, fresnel * 0.3);
    
    // Shadow at base of grass
    grass_color = mix(grass_color * 0.7, grass_color, smoothstep(0.0, 0.2, blade_uv.y));
    
    // Ensure websafe colors
    grass_color = floor(grass_color * 255.0 / 51.0) * 51.0 / 255.0;
    
    // Output material properties
    ALBEDO = grass_color;
    ALPHA = blade_alpha;
    ROUGHNESS = roughness_grass;
    METALLIC = 0.0;
}