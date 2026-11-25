shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

/** Red-channel opacity mask for spray sprites. Used when Velocity Aligned is off. */
uniform sampler2D splatter_mask : filter_linear_mipmap, repeat_disable;
/** Aligns sprites with projected motion and draws a round footprint. Turn off to use the spray mask and growth curve. */
uniform bool velocity_aligned = false;
/** Smallest horizontal and vertical sprite scale. Each particle varies between these ratios and full size. */
uniform vec2 minimum_size_ratio = vec2(1.0);
/** Cubic growth curve packed as middle-key age (X), middle-key scale (Y), and final scale (Z). */
uniform vec3 size_curve = vec3(0.2, 0.45, 1.0);
/** Slope of the middle growth key. The first and final keys have zero slope. */
uniform float size_curve_tangent = 1.0;
/** Range of initial mask allowances. Larger values reveal more of the spray texture. */
uniform vec2 erosion_range = vec2(0.6);
/** Scales initial erosion allowance by the particle's lifetime in seconds. */
uniform bool erosion_from_lifetime = false;
/** Emitter lifetime in seconds used to decode the particle lifetime fraction for erosion. */
uniform float maximum_lifetime = 1.0;
/** Exponent applied to the spray mask. Higher values shrink its faint edges and thinner features. */
uniform float thinness = 1.0;
/** Width of the opacity transition at the spray mask's dissolve threshold. */
uniform float softness = 0.01;
/** Linear red intensity of the unlit sprite. The other two color channels are zero. */
uniform float linear_red = 0.05;
varying float erosion;

// The exported Niagara size curves each have three cubic keys, with zero
// tangent at both endpoints and an authored tangent at the middle key.
float sprite_growth(float age) {
    float middle_time = size_curve.x;
    float middle_value = size_curve.y;
    if (age < middle_time) {
        float t = age / middle_time;
        return t * t * ((3.0 - 2.0 * t) * middle_value +
            (t - 1.0) * middle_time * size_curve_tangent);
    }
    float t = (age - middle_time) / (1.0 - middle_time);
    return mix(middle_value, size_curve.z, smoothstep(0.0, 1.0, t)) +
        t * (t - 1.0) * (t - 1.0) * (1.0 - middle_time) * size_curve_tangent;
}

void vertex() {
    // CPU particles store age and lifetime as fractions of the emitter lifetime.
    float lifetime_fraction = max(INSTANCE_CUSTOM.w, 0.00001);
    float age = clamp(INSTANCE_CUSTOM.y / lifetime_fraction, 0.0, 1.0);
    float roll = INSTANCE_CUSTOM.x;
    vec2 up = vec2(-sin(roll), cos(roll));
    vec2 sprite_size = mix(minimum_size_ratio, vec2(1.0), INSTANCE_CUSTOM.z);
    if (velocity_aligned) {
        vec2 projected_velocity = (VIEW_MATRIX * vec4(MODEL_MATRIX[1].xyz, 0.0)).xy;
        if (dot(projected_velocity, projected_velocity) > 0.000001) {
            up = normalize(projected_velocity);
        }
        erosion = 0.0;
    } else {
        sprite_size *= sprite_growth(age);
        float initial_erosion = mix(erosion_range.x, erosion_range.y, roll / TAU);
        if (erosion_from_lifetime) {
            initial_erosion *= maximum_lifetime * lifetime_fraction;
        }
        erosion = initial_erosion * (1.0 - smoothstep(0.0, 1.0, age));
    }

    vec2 right = vec2(up.y, -up.x);
    vec4 center = VIEW_MATRIX * MODEL_MATRIX[3];
    MODELVIEW_MATRIX = mat4(vec4(right * sprite_size.x, 0.0, 0.0),
        vec4(up * sprite_size.y, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), center);
}

void fragment() {
    if (velocity_aligned) {
        float distance_from_center = length(UV - vec2(0.5));
        float edge = max(fwidth(distance_from_center), 0.00001);
        ALPHA = 1.0 - smoothstep(0.5 - edge, 0.5 + edge, distance_from_center);
    } else {
        float mask = pow(texture(splatter_mask, UV).r, thinness);
        ALPHA = clamp((mask - (1.0 - erosion)) / max(softness, 0.00001), 0.0, 1.0);
    }
    float red = OUTPUT_IS_SRGB ? 1.055 * pow(linear_red, 1.0 / 2.4) - 0.055 : linear_red;
    ALBEDO = vec3(red, 0.0, 0.0);
}
