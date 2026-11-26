shader_type canvas_item;

// Basic Effect Parameters
group_uniforms Basic;
uniform float pixel_size : hint_range(1.0, 1920.0) = 768.0;
uniform int color_depth : hint_range(1, 12) = 5;

// Color Palette Settings
group_uniforms Palette;
uniform bool use_custom_palette = false;
uniform sampler2D color_palette;
uniform int palette_size : hint_range(1, 256) = 256;
uniform int palette_columns : hint_range(1, 256) = 16;
uniform bool use_single_row = false;
uniform int palette_row : hint_range(0, 15) = 0;
uniform float merge_threshold : hint_range(0.0, 1.0) = 0.0;

// Hue Shift Controls
group_uniforms HueShift;
uniform float hue_shift_range : hint_range(0.0, 1.0) = 0.2;
uniform float contrast_threshold : hint_range(0.0, 1.0) = 0.5;

// Dithering Effect
group_uniforms Dithering;
uniform float dither_strength : hint_range(0.0, 1.0) = 0.01;

// Jitter Effect
group_uniforms Jitter;
uniform float jitter_intensity : hint_range(0.0, 1.0) = 0.1;

// Vignette Effect
group_uniforms Vignette;
uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.346;
uniform float vignette_opacity : hint_range(0.0, 1.0) = 0.917;

// Chromatic Aberration
group_uniforms ChromaticAberration;
uniform float aberration_strength : hint_range(0.0, 5.0) = 0.25;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture;

const mat4 dither_pattern = mat4(
    vec4(0.0, 12.0, 3.0, 15.0),
    vec4(8.0, 4.0, 11.0, 7.0),
    vec4(2.0, 14.0, 1.0, 13.0),
    vec4(10.0, 6.0, 9.0, 5.0)
) / 16.0;

vec3 rgb_to_hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

float get_dither_value(vec2 screen_pos) {
    ivec2 dith_pos = ivec2(mod(screen_pos, 4.0));
    return dither_pattern[dith_pos.x][dith_pos.y];
}

vec3 apply_hue_shift(vec3 color) {
    vec3 hsv = rgb_to_hsv(color);
    float contrast_factor = (hsv.z - contrast_threshold) / 0.5;
    float hue_shift = contrast_factor * hue_shift_range;
    hsv.x = fract(hsv.x + hue_shift);
    return hsv_to_rgb(hsv);
}

vec3 apply_custom_palette(vec3 color) {
    vec3 closest_color = color;
    float min_distance = 1.0e10;

    for (int i = 0; i < palette_size; i++) {
        int x = i % palette_columns;
        int y = use_single_row ? palette_row : i / palette_columns;
        vec2 uv = (vec2(float(x), float(y)) + 0.5) / vec2(float(palette_columns), use_single_row ? 16.0 : ceil(float(palette_size) / float(palette_columns)));
        vec3 palette_color = texture(color_palette, uv).rgb;
        float distance = length(color - palette_color);

        if (distance < min_distance) {
            min_distance = distance;
            closest_color = palette_color;
        }
    }

    if (merge_threshold > 0.0) {
        vec3 merged_color = vec3(0.0);
        float total_weight = 0.0;

        for (int i = 0; i < palette_size; i++) {
            int x = i % palette_columns;
            int y = use_single_row ? palette_row : i / palette_columns;
            vec2 uv = (vec2(float(x), float(y)) + 0.5) / vec2(float(palette_columns), use_single_row ? 16.0 : ceil(float(palette_size) / float(palette_columns)));
            vec3 palette_color = texture(color_palette, uv).rgb;
            float distance = length(closest_color - palette_color);
            float influence = 1.0 - smoothstep(0.0, merge_threshold, sqrt(distance));

            if (influence > 0.0) {
                merged_color += palette_color * influence;
                total_weight += influence;
            }
        }

        if (total_weight > 0.0) {
            return merged_color / total_weight;
        }
    }

    return closest_color;
}

vec3 quantize_color(vec3 color) {
    if (use_custom_palette) {
        return apply_custom_palette(color);
    }
    float color_levels = pow(2.0, float(color_depth));
    return floor(color * color_levels + 0.5) / (color_levels - 1.0);
}

void vertex() {
    // Apply jitter in vertex shader
    VERTEX += vec2(
        sin(TIME * 2.0 + UV.y * 4.0) * 0.5 +
        sin(TIME * 0.8 + UV.x * 2.0) * 0.3,
        cos(TIME * 1.2 + UV.x * 3.0) * 0.4 +
        cos(TIME * 2.4 + UV.y * 2.5) * 0.4
    ) * jitter_intensity;
}

void fragment() {
    // Get the size of a single pixel on screen
    vec2 screenpixel_size = SCREEN_PIXEL_SIZE;

    // Calculate aspect ratio
    float aspect = screenpixel_size.y / screenpixel_size.x;

    // Create square pixels by scaling UVs
    vec2 uv = SCREEN_UV;
    uv.y *= aspect;

    // Calculate the size of our squares
    vec2 pixelated = round(uv * pixel_size) / pixel_size;

    // Restore the aspect ratio
    pixelated.y /= aspect;

    // Apply chromatic aberration
    vec4 color;
    if (aberration_strength > 0.0) {
        vec2 offset = (pixelated - 0.5) * 2.0 * aberration_strength / 100.0;
        color.r = texture(SCREEN_TEXTURE, pixelated - offset).r;
        color.g = texture(SCREEN_TEXTURE, pixelated).g;
        color.b = texture(SCREEN_TEXTURE, pixelated + offset).b;
        color.a = 1.0;
    } else {
        color = texture(SCREEN_TEXTURE, pixelated);
    }

    // Apply dithering before color quantization
    if (dither_strength > 0.0) {
        float dither = get_dither_value(FRAGCOORD.xy);
        color.rgb += (dither - 0.5) * dither_strength;
    }

    // Apply color quantization
    color.rgb = quantize_color(color.rgb);

    // Apply hue shift
    color.rgb = apply_hue_shift(color.rgb);

    // Apply vignette last
    if (vignette_opacity > 0.0) {
        vec2 vignette_uv = pixelated * (1.0 - pixelated.yx);
        float vignette = vignette_uv.x * vignette_uv.y * 15.0;
        vignette = clamp(pow(vignette, vignette_intensity), 0.0, 1.0);
        color.rgb = mix(color.rgb, color.rgb * vignette, vignette_opacity);
    }

    COLOR = color;
}