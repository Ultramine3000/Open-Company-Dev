shader_type spatial;
render_mode specular_schlick_ggx;

// 3D Jungle Floor Spatial Shader with PBR
// Features: Normal mapping, roughness variation, height displacement, realistic lighting

varying vec3 world_position;
varying vec3 world_normal;

uniform float time_scale : hint_range(0.1, 2.0) = 1.0;
uniform float moss_coverage : hint_range(0.0, 1.0) = 0.6;
uniform float leaf_scatter : hint_range(0.0, 1.0) = 0.4;
uniform float moisture_amount : hint_range(0.0, 1.0) = 0.5;
uniform float texture_scale : hint_range(0.1, 5.0) = 0.5;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform float roughness_base : hint_range(0.3, 1.0) = 0.8;
uniform float metallic_base : hint_range(0.0, 0.2) = 0.05;
uniform float height_scale : hint_range(0.0, 0.1) = 0.02;

// Websafe PBR color palette
const vec3 SOIL_DARK = vec3(0.2, 0.1, 0.05);      // #331100
const vec3 SOIL_MEDIUM = vec3(0.4, 0.25, 0.1);    // #664400
const vec3 SOIL_LIGHT = vec3(0.6, 0.4, 0.2);      // #996633
const vec3 MOSS_DEEP = vec3(0.1, 0.3, 0.1);       // #114411
const vec3 MOSS_BRIGHT = vec3(0.2, 0.6, 0.2);     // #339933
const vec3 MOSS_YELLOW = vec3(0.4, 0.7, 0.1);     // #66BB11
const vec3 LEAF_BROWN = vec3(0.5, 0.3, 0.1);      // #884411
const vec3 LEAF_ORANGE = vec3(0.8, 0.4, 0.1);     // #CC6611
const vec3 LEAF_RED = vec3(0.7, 0.2, 0.1);        // #BB3311
const vec3 BARK_COLOR = vec3(0.3, 0.2, 0.1);      // #553311

// Advanced noise functions
float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float hash13(vec3 p) {
    return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

vec3 hash33(vec3 p) {
    p = vec3(dot(p, vec3(127.1, 311.7, 74.7)),
             dot(p, vec3(269.5, 183.3, 246.1)),
             dot(p, vec3(113.5, 271.9, 124.6)));
    return fract(sin(p) * 43758.5453123);
}

float noise3d(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    float n000 = hash13(i);
    float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
    float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
    float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
    float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
    float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
    float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
    float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
    
    float nx00 = mix(n000, n100, f.x);
    float nx10 = mix(n010, n110, f.x);
    float nx01 = mix(n001, n101, f.x);
    float nx11 = mix(n011, n111, f.x);
    
    float nxy0 = mix(nx00, nx10, f.y);
    float nxy1 = mix(nx01, nx11, f.y);
    
    return mix(nxy0, nxy1, f.z);
}

float fbm3d(vec3 p, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    
    for(int i = 0; i < octaves; i++) {
        value += amplitude * noise3d(p * frequency);
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    return value;
}

// Generate normal from height (higher detail)
vec3 calculate_normal(vec3 pos, float scale) {
    float eps = 0.0005; // Smaller epsilon for finer detail
    float h0 = fbm3d(pos, 6); // More octaves
    float hx = fbm3d(pos + vec3(eps, 0.0, 0.0), 6);
    float hz = fbm3d(pos + vec3(0.0, 0.0, eps), 6);
    
    vec3 normal;
    normal.x = (h0 - hx) / eps * scale;
    normal.z = (h0 - hz) / eps * scale;
    normal.y = 1.0;
    
    return normalize(normal);
}

// Leaf shape with proper falloff
float leaf_shape_3d(vec2 p, float size, float rotation) {
    // Rotate point
    float c = cos(rotation);
    float s = sin(rotation);
    vec2 rotated = vec2(c * p.x - s * p.y, s * p.x + c * p.y);
    
    // Leaf shape (more realistic)
    vec2 centered = rotated / size;
    float dist = length(centered);
    float leaf_body = smoothstep(0.6, 0.2, dist);
    
    // Add leaf stem and veins
    float stem = smoothstep(0.02, 0.0, abs(centered.x)) * 
                 smoothstep(0.0, 0.5, centered.y + 0.5);
    float main_vein = smoothstep(0.008, 0.0, abs(centered.x)) * leaf_body;
    
    // Side veins
    float side_veins = 0.0;
    for(int i = 1; i <= 3; i++) {
        float y_pos = float(i) * 0.15 - 0.3;
        float vein_dist = abs(length(centered - vec2(0.0, y_pos)) - abs(centered.x) * 0.5);
        side_veins += smoothstep(0.01, 0.0, vein_dist) * 0.3;
    }
    
    return clamp(leaf_body + stem + main_vein + side_veins, 0.0, 1.0);
}

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
    
    // Add some height displacement (static variation only, finer detail)
    vec3 noise_pos = world_position * texture_scale * 2.0;
    float height_noise = fbm3d(noise_pos, 6);
    VERTEX.y += height_noise * height_scale;
}

void fragment() {
    vec2 uv = UV;
    float time = TIME * time_scale;
    
    // Scale coordinates for texturing
    vec3 world_pos = world_position * texture_scale;
    vec2 surface_uv = world_pos.xz;
    
    // Base soil noise patterns (higher detail)
    float soil_base = fbm3d(world_pos, 8);
    float soil_detail = fbm3d(world_pos * 4.0, 6);
    float soil_micro = fbm3d(world_pos * 8.0, 4);
    float soil_macro = fbm3d(world_pos * 0.3, 5);
    
    // Create soil color variation (more detailed)
    vec3 soil_color = mix(SOIL_DARK, SOIL_MEDIUM, soil_base);
    soil_color = mix(soil_color, SOIL_LIGHT, soil_detail * 0.6);
    soil_color = mix(soil_color, BARK_COLOR, soil_macro * 0.3);
    // Add fine micro detail
    soil_color = mix(soil_color, soil_color * 1.1, soil_micro * 0.2);
    
    // Moss growth pattern (higher detail)
    float moss_noise = fbm3d(world_pos * 2.5, 8);
    float moss_density = fbm3d(world_pos * 1.2, 6);
    float moss_fine = fbm3d(world_pos * 6.0, 4);
    float moss_mask = smoothstep(0.4, 0.8, moss_noise * moss_density) * moss_coverage;
    
    // Moss appears more in crevices and damp areas
    float crevice_factor = 1.0 - abs(world_normal.y);
    moss_mask *= (1.0 + crevice_factor * 0.5);
    
    vec3 moss_color = mix(MOSS_DEEP, MOSS_BRIGHT, moss_noise);
    moss_color = mix(moss_color, MOSS_YELLOW, moss_noise * 0.3);
    // Add fine moss detail
    moss_color = mix(moss_color, moss_color * 0.9, moss_fine * 0.4);
    
    // Scattered leaves with proper placement (higher density)
    vec2 leaf_grid = floor(surface_uv * 12.0);
    vec2 leaf_local = fract(surface_uv * 12.0);
    vec3 leaf_seed = vec3(leaf_grid, 0.0);
    vec3 leaf_rand = hash33(leaf_seed);
    
    float leaf_presence = 0.0;
    vec3 leaf_color = LEAF_BROWN;
    float leaf_roughness = 0.9;
    
    if(leaf_rand.x < leaf_scatter) {
        float leaf_size = 0.15 + leaf_rand.y * 0.25;
        float leaf_rotation = leaf_rand.z * 6.28;
        vec2 leaf_offset = (leaf_rand.xy - 0.5) * 0.4;
        
        leaf_presence = leaf_shape_3d(leaf_local - 0.5 - leaf_offset, leaf_size, leaf_rotation);
        
        // Vary leaf colors based on decomposition
        float decomp = leaf_rand.x;
        if(decomp < 0.3) {
            leaf_color = LEAF_RED;
            leaf_roughness = 0.7;
        } else if(decomp < 0.6) {
            leaf_color = LEAF_ORANGE;
            leaf_roughness = 0.8;
        } else {
            leaf_color = mix(LEAF_BROWN, SOIL_MEDIUM, 0.5);
            leaf_roughness = 0.95;
        }
        
        // Weather the leaves
        leaf_color = mix(leaf_color, soil_color, decomp * 0.3);
    }
    
    // Moisture and wetness (finer detail)
    float moisture_pattern = fbm3d(world_pos * 1.5, 6);
    float moisture_fine = fbm3d(world_pos * 4.0, 4);
    float wet_areas = smoothstep(0.6, 0.9, moisture_pattern * moisture_fine) * moisture_amount;
    
    // Water pools in low areas
    wet_areas *= (1.0 + crevice_factor * 0.8);
    
    // Combine all surface elements
    vec3 final_albedo = soil_color;
    float final_roughness = roughness_base;
    float final_metallic = metallic_base;
    
    // Apply moss
    final_albedo = mix(final_albedo, moss_color, moss_mask);
    final_roughness = mix(final_roughness, 0.9, moss_mask);
    
    // Apply leaves
    final_albedo = mix(final_albedo, leaf_color, leaf_presence);
    final_roughness = mix(final_roughness, leaf_roughness, leaf_presence);
    final_metallic = mix(final_metallic, 0.0, leaf_presence);
    
    // Apply moisture (darkening and reduced roughness)
    final_albedo = mix(final_albedo, final_albedo * 0.6, wet_areas);
    final_roughness = mix(final_roughness, 0.1, wet_areas);
    
    // Calculate surface normal
    vec3 surface_normal = calculate_normal(world_pos, normal_strength);
    surface_normal = mix(vec3(0.0, 1.0, 0.0), surface_normal, normal_strength);
    
    // Add leaf normal details
    if(leaf_presence > 0.1) {
        surface_normal = mix(surface_normal, vec3(0.0, 1.0, 0.0), leaf_presence * 0.5);
    }
    
    // Ensure websafe colors
    final_albedo = floor(final_albedo * 255.0 / 51.0) * 51.0 / 255.0;
    
    // Output PBR properties
    ALBEDO = final_albedo;
    ROUGHNESS = final_roughness;
    METALLIC = final_metallic;
    NORMAL = surface_normal;
}