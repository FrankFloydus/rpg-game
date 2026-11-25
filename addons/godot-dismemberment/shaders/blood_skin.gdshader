shader_type spatial;
render_mode cull_disabled;
/** Base surface color. Multiplies Base Texture when enabled. */
uniform vec4 base_color : source_color = vec4(0.65, 0.68, 0.72, 1.0);
// Unreal vector parameters are linear values. Keep this parameter linear;
// source_color would reinterpret the source's 0.005 as an sRGB input.
/** Linear RGB tint for vertex paint and wound stains. Enter linear channel values. */
uniform vec4 blood_color = vec4(0.005, 0.0, 0.0, 1.0);
/** Scales the blood tint mixed into the surface color. */
uniform float dismember_emissive = 5.0;
/** Red-channel noise for vertex-paint edges and wound surface variation. */
uniform sampler2D blood_noise : filter_linear_mipmap, repeat_enable;
/** Samples Blood Noise in place of the built-in procedural variation. */
uniform bool use_blood_noise = false;
/** Albedo texture sampled using the first material UV set. */
uniform sampler2D base_texture : source_color, filter_linear_mipmap;
/** Multiplies Base Color by the sampled Base Texture. */
uniform bool use_base_texture = false;
/** Tangent-space normal map for the undamaged surface. */
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
/** Uses Normal Texture to shape the undamaged surface lighting. */
uniform bool use_normal_texture = false;
/** Strength of the tangent-space base normal map. */
uniform float normal_scale = 1.0;
/** Texture that multiplies the scalar or packed roughness using the selected channel. */
uniform sampler2D roughness_texture : filter_linear_mipmap, repeat_enable;
/** Multiplies surface roughness by the selected Roughness Texture channel. */
uniform bool use_roughness_texture = false;
/** Channel index for Roughness Texture. Use 0 to 3 for RGBA or 4 for the RGB average. */
uniform int roughness_texture_channel = 0;
/** Texture that multiplies the scalar or packed metalness using the selected channel. */
uniform sampler2D metallic_texture : filter_linear_mipmap, repeat_enable;
/** Multiplies surface metalness by the selected Metallic Texture channel. */
uniform bool use_metallic_texture = false;
/** Channel index for Metallic Texture. Use 0 to 3 for RGBA or 4 for the RGB average. */
uniform int metallic_texture_channel = 0;
/** Base surface metalness when the packed ORM texture is disabled. */
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
/** Base surface specular intensity before the wound material is applied. */
uniform float specular : hint_range(0.0, 1.0) = 0.5;
/** Separate ambient occlusion map. Its selected channel takes precedence over packed ORM occlusion. */
uniform sampler2D ao_texture : filter_linear_mipmap, repeat_enable;
/** Uses the separate AO Texture when Enable AO is on. */
uniform bool use_ao_texture = false;
/** Applies occlusion from AO Texture or the red channel of the packed ORM texture. */
uniform bool enable_ao = false;
/** Channel index for AO Texture. Use 0 to 3 for RGBA or 4 for the RGB average. */
uniform int ao_texture_channel = 0;
/** Amount of direct lighting influenced by the ambient occlusion map. */
uniform float ao_light_affect = 0.0;
/** Samples the separate AO Texture on the second material UV set. */
uniform bool ao_on_uv2 = false;
/** Packed surface maps. Red stores occlusion, green roughness, and blue metalness. */
uniform sampler2D orm_texture : filter_linear_mipmap, repeat_enable;
/** Reads packed roughness and metalness, plus occlusion when enabled, from ORM Texture. */
uniform bool use_orm_texture = false;
/** Horizontal and vertical tiling for material maps sampled on the first UV set. */
uniform vec3 uv1_scale = vec3(1.0);
/** Horizontal and vertical offset for material maps sampled on the first UV set. */
uniform vec3 uv1_offset = vec3(0.0);
/** Horizontal and vertical tiling for material maps sampled on the second UV set. */
uniform vec3 uv2_scale = vec3(1.0);
/** Horizontal and vertical offset for material maps sampled on the second UV set. */
uniform vec3 uv2_offset = vec3(0.0);
/** Lets transformed material UVs extend beyond the first tile. Turn off to clamp the UVs to that tile. */
uniform bool texture_repeat = true;
/** Faces to discard. Zero discards backs, one discards fronts, and two keeps both. */
uniform int cull_mode = 0;
/** Base glow color combined with the optional emission texture. */
uniform vec4 emission_color : source_color = vec4(0.0);
/** RGB glow map for the underlying surface. */
uniform sampler2D emission_texture : source_color, filter_linear_mipmap, repeat_enable;
/** Samples the surface glow from Emission Texture. */
uniform bool use_emission_texture = false;
/** Samples Emission Texture on the second material UV set. */
uniform bool emission_on_uv2 = false;
/** Multiplies the glow color by the texture sample. Turn off to add them. */
uniform bool emission_multiply = false;
/** Overall intensity of the underlying surface glow. */
uniform float emission_energy = 1.0;
/** Progress value supplied by the blood paint animation. */
uniform float blood_animation : hint_range(0.0, 1.0) = 1.0;
/** Base surface roughness when the packed ORM texture is disabled. */
uniform float roughness : hint_range(0.0, 1.0) = 0.65;
/** Vertex color channel that carries legacy blood paint. Indices 0 to 3 select RGBA. */
uniform int blood_vertex_channel : hint_range(0, 3) = 2;
/** Applies the per-surface wound mask assigned by GoreComponent. */
uniform bool use_skin_wound_mask = false;
/** Keeps vertex paint active alongside the wound mask. */
uniform bool use_legacy_blood_paint = false;
/** Uses the wound mask's depth information to shade repeatedly hit areas as cavities. */
uniform bool use_skin_wound_depth = false;
/** Uses accumulated erosion to shade the cavity floor and walls. Requires Use Skin Wound Depth. */
uniform bool use_skin_wound_erosion = false;
/** Maximum apparent depth of a wound cavity in metres. */
uniform float skin_wound_max_depth : hint_range(0.0, 0.2, 0.001) = 0.035;
const float reference_wound_depth = 0.035;
/** Runtime wound mask. Red stores pellet coverage, green stain, blue openings, and alpha depth or erosion. */
uniform sampler2D skin_wound_mask : filter_linear, repeat_disable;
/** Samples wound data and detail using the second UV set. */
uniform bool skin_wound_use_uv2 = false;
/** Tiled base-color texture for exposed wound surfaces. */
uniform sampler2D skin_wound_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
/** Tangent-space relief texture for exposed wound surfaces. */
uniform sampler2D skin_wound_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
/** Red-channel roughness detail for exposed wound surfaces. */
uniform sampler2D skin_wound_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
/** RGB multiplier for the exposed wound texture. */
uniform vec4 skin_wound_tissue_tint = vec4(1.0);
/** Multiplier for roughness detail on exposed wound surfaces. */
uniform float skin_wound_tissue_roughness = 1.0;
/** Strength of the normal relief on exposed wound surfaces. */
uniform float skin_wound_tissue_normal_strength = 1.0;
/** Uses the fabric mask to shade stains and wound edges differently on cloth and skin. */
uniform bool use_skin_gore_fabric_mask = false;
/** Red-channel cloth coverage sampled on the first UV set. White marks fabric and black marks skin. */
uniform sampler2D skin_gore_fabric_mask : hint_default_black, filter_linear_mipmap, repeat_disable;

float fallback_noise(vec2 p) {
    return 0.5 + 0.17 * sin(p.x * 39.0 + sin(p.y * 27.0)) + 0.14 * sin(p.y * 53.0 + cos(p.x * 31.0));
}
float texture_channel(vec4 value, int channel) {
    if (channel == 4) return dot(value.rgb, vec3(0.333333333));
    return value[clamp(channel, 0, 3)];
}
vec2 material_uv(vec2 uv, vec3 scale, vec3 offset) {
    vec2 mapped = uv * scale.xy + offset.xy;
    return texture_repeat ? mapped : clamp(mapped, vec2(0.0), vec2(1.0));
}
float overlay(float base, float detail) {
    return base < 0.5 ? 2.0 * base * detail : 1.0 - 2.0 * (1.0 - base) * (1.0 - detail);
}

vec3 wound_direction(vec3 direction) {
    return direction * inversesqrt(max(dot(direction, direction), 1e-14));
}

vec3 wound_slope(vec2 uv, vec2 uv_dx, vec2 uv_dy, vec3 surface_dx, vec3 surface_dy) {
    vec2 bump = textureGrad(skin_wound_normal, uv, uv_dx, uv_dy).rg * 2.0 - 1.0;
    vec3 along_u = wound_direction(surface_dx * uv_dx.x + surface_dy * uv_dy.x);
    vec3 along_v = wound_direction(surface_dx * uv_dx.y + surface_dy * uv_dy.y);
    return (along_u * bump.x - along_v * bump.y) * skin_wound_tissue_normal_strength;
}

// Easing the stored amount of lost material gives shallow marks a flatter
// profile and preserves the visible change at the deep end of the range.
float erosion_height(float amount) {
    return amount * amount;
}

vec3 trace_wound_relief(vec2 uv, vec2 sweep, float center_depth) {
    float previous_depth = 0.0;
    float previous_gap = -center_depth;
    // March a bounded distance across this wound and interpolate the first
    // crossing so the inner wall can hide the floor at an oblique angle.
    for (int sample_index = 1; sample_index <= 7; sample_index++) {
        float ray_depth = float(sample_index) / 7.0;
        float surface_depth = erosion_height(textureLod(skin_wound_mask, uv + sweep * ray_depth, 0.0).a);
        float gap = ray_depth - surface_depth;
        if (gap >= 0.0) {
            float hit_depth = mix(previous_depth, ray_depth, -previous_gap / max(gap - previous_gap, 0.00001));
            return vec3(uv + sweep * hit_depth, hit_depth);
        }
        previous_depth = ray_depth;
        previous_gap = gap;
    }
    return vec3(uv + sweep, 1.0);
}

float wound_blood_spill(float profile, float edge, float width, vec2 gradient, float grain) {
    float field = profile + (grain - 0.5) * width * 1.45;
    float filter_width = min(dot(abs(gradient), vec2(0.40)), width * 0.40);
    return smoothstep(edge - width - filter_width, edge + width * 0.26, field);
}

void fragment() {
    if ((cull_mode == 0 && !FRONT_FACING) || (cull_mode == 1 && FRONT_FACING)) discard;
    float mask = 0.0;
    if (!use_skin_wound_mask || use_legacy_blood_paint) {
        // Reconstructed from MF_DIS_ApplyBlood / MF_DIS_BloodMask. The source uses
        // a custom primitive float; this port passes the same value as a uniform.
        float animation = clamp((blood_animation + 0.9) * ceil(blood_animation), 0.0, 1.0);
        float painted = COLOR[blood_vertex_channel] * animation;
        float noise = use_blood_noise ? texture(blood_noise, UV / 0.5).r : fallback_noise(UV / 0.5);
        float contrast_input = noise + pow(max(painted, 0.0), 50.0) * 10.0;
        mask = clamp(contrast_input * 21.0 - 10.0, 0.0, 1.0) * painted;
    }
    vec2 uv1 = material_uv(UV, uv1_scale, uv1_offset);
    vec2 uv2 = material_uv(UV2, uv2_scale, uv2_offset);
    vec4 base = base_color;
    if (use_base_texture) base *= texture(base_texture, uv1);
    vec3 orm = use_orm_texture ? texture(orm_texture, uv1).rgb : vec3(1.0);
    float original_roughness = use_orm_texture ? orm.g : roughness;
    if (use_roughness_texture) original_roughness *= texture_channel(texture(roughness_texture, uv1), roughness_texture_channel);
    float original_metallic = use_orm_texture ? orm.b : metallic;
    if (use_metallic_texture) original_metallic *= texture_channel(texture(metallic_texture, uv1), metallic_texture_channel);
    ALBEDO = mix(base.rgb, blood_color.rgb * dismember_emissive * 2.0, clamp(mask, 0.0, 1.0));
    ROUGHNESS = mix(original_roughness, 0.2 * (1.0 - mask), clamp(mask, 0.0, 1.0));
    METALLIC = original_metallic;
    SPECULAR = specular;
    AO = !enable_ao ? 1.0 : (use_ao_texture ? texture_channel(texture(ao_texture, ao_on_uv2 ? uv2 : uv1), ao_texture_channel) : orm.r);
    AO_LIGHT_AFFECT = ao_light_affect;
    vec3 tangent_normal = use_normal_texture ? texture(normal_texture, uv1).rgb : vec3(0.5, 0.5, 1.0);
    // MF_DIS_ApplyBlood preserves the incoming normal outside a wound and
    // blends it toward tangent-space +Z inside the blood mask.
    NORMAL_MAP = mix(tangent_normal, vec3(0.5, 0.5, 1.0), clamp(mask, 0.0, 1.0));
    NORMAL_MAP_DEPTH = normal_scale;
    vec3 emission_sample = use_emission_texture ? texture(emission_texture, emission_on_uv2 ? uv2 : uv1).rgb : vec3(0.0);
    EMISSION = (emission_multiply ? emission_color.rgb * emission_sample : emission_color.rgb + emission_sample) * emission_energy;
    if (use_skin_wound_mask) {
        // Use the same persistent surface coordinates for the wound and its
        // detail, including on a posed limb or a recentered slice fragment.
        vec2 damage_uv = skin_wound_use_uv2 ? UV2 : UV;
        vec4 damage = texture(skin_wound_mask, damage_uv);
        // Derivatives of the filtered masks give a rim direction
        // without sampling neighboring UV charts or relying on UV tangents.
        vec2 opening_gradient = vec2(dFdx(damage.b), dFdy(damage.b));
        vec2 pellet_gradient = vec2(dFdx(damage.r), dFdy(damage.r));
        bool erosion_enabled = use_skin_wound_depth && use_skin_wound_erosion;
        float depth_scale = skin_wound_max_depth / reference_wound_depth;
        float material_loss = erosion_enabled ? damage.a : 0.0;
        float eroded_height = erosion_height(material_loss);
        vec2 height_gradient = vec2(dFdx(eroded_height), dFdy(eroded_height));
        vec2 fabric_dx = dFdx(UV);
        vec2 fabric_dy = dFdy(UV);
        vec2 tissue_uv = damage_uv * 14.0;
        vec2 tissue_dx = dFdx(tissue_uv);
        vec2 tissue_dy = dFdy(tissue_uv);
        vec2 detail_uv = damage_uv * 20.0;
        vec2 detail_dx = dFdx(detail_uv);
        vec2 detail_dy = dFdy(detail_uv);
        vec3 position_dx = dFdx(VERTEX);
        vec3 position_dy = dFdy(VERTEX);
        if (max(max(damage.r, damage.g), max(damage.b, material_loss)) > 0.001) {
            float detail = use_blood_noise ? textureGrad(blood_noise, detail_uv, detail_dx, detail_dy).r : fallback_noise(detail_uv * 0.32);
            // Explicit openings retain their own appearance at overlaps.
            float progressive = use_skin_wound_depth ? 1.0 - smoothstep(0.015, 0.12, damage.b) : 0.0;
            float recess = 0.0;
            float late_depth = 0.0;
            float core_depth = 0.0;
            float apparent_depth = damage.a * depth_scale;
            if (!erosion_enabled && progressive > 0.0 && apparent_depth > 0.075) {
                // Normalize by the compact cap used by the native brush. The
                // absolute A gate keeps weak or interpolated edges shallow.
                float local_cap = max(0.25, (damage.r * 255.0 - 96.0) / 159.0);
                float severity = apparent_depth / local_cap;
                float core_recess = smoothstep(0.075, 0.51, apparent_depth);
                float rim_recess = smoothstep(0.11, 0.55, severity) * smoothstep(0.075, 0.22, apparent_depth);
                recess = max(core_recess, rim_recess) * progressive;
                late_depth = smoothstep(0.30, 0.99, severity) * smoothstep(0.12, 0.24, apparent_depth) * progressive;
                // A high fraction of a small local cap still makes a shallow
                // edge. Reserve the deepest shadow for high absolute depth.
                core_depth = smoothstep(0.735, 0.91, apparent_depth) * progressive;
            }
            float fabric = 0.0;
            if (use_skin_gore_fabric_mask && max(max(damage.g, damage.b), max(recess, material_loss)) > 0.001) {
                fabric = textureGrad(skin_gore_fabric_mask, UV, fabric_dx, fabric_dy).r;
            }
            vec3 blood_tint = blood_color.rgb * dismember_emissive * 2.0;
            if (damage.g > 0.001) {
                float skin_stain = 0.44 * smoothstep(0.06, 0.78, damage.g);
                vec3 skin_tint = mix(ALBEDO * vec3(0.71, 0.46, 0.47), blood_tint, 0.37);
                vec3 stained_skin = mix(ALBEDO, skin_tint, skin_stain);
                float skin_roughness = mix(ROUGHNESS, max(0.52, ROUGHNESS), 0.42 * skin_stain);
                float skin_specular = mix(SPECULAR, 0.33, 0.36 * skin_stain);
                float skin_wetness = 0.0;
                float local_wound = max(damage.r, 0.88 * damage.b);
                if (fabric < 1.0) {
                    // A surface hit can leave a wet center with or without a wound.
                    float contact = max(smoothstep(0.06, 0.78, local_wound),
                        0.78 * smoothstep(0.10, 0.46, damage.g));
                    float blood_available = smoothstep(0.04, 0.67, damage.g);
                    skin_wetness = blood_available * contact * mix(0.40, 0.68, detail);
                    vec3 coating = clamp(blood_tint * 2.65, vec3(0.0), vec3(0.32))
                        + ALBEDO * vec3(0.08, 0.035, 0.040);
                    stained_skin = mix(stained_skin, coating, skin_wetness);
                    skin_roughness = mix(skin_roughness, 0.33, skin_wetness);
                    skin_specular = mix(skin_specular, 0.41, skin_wetness);
                }
                vec3 soaked_fabric = ALBEDO;
                float fabric_stain = 0.0;
                if (fabric > 0.0) {
                    // Let the original cloth texture show through absorption.
                    // Tiled detail belongs at the edge, where a UV chart
                    // boundary cannot split a large area of the stain.
                    float cloth_value = dot(base.rgb, vec3(0.2126, 0.7152, 0.0722));
                    float uptake = damage.g * mix(0.79, 0.96, smoothstep(0.18, 0.63, cloth_value));
                    float density = uptake * smoothstep(0.26, 0.80, uptake);
                    float tint_peak = max(max(blood_tint.r, blood_tint.g), blood_tint.b);
                    vec3 pigment = clamp(blood_tint / max(tint_peak, 0.05), vec3(0.0), vec3(1.0));
                    vec3 absorption = vec3(3.55, 3.75, 4.12) - pigment * 1.18;
                    soaked_fabric *= exp2(-absorption * density);
                    fabric_stain = 1.0 - exp2(-2.5 * density);
                }
                ALBEDO = mix(stained_skin, soaked_fabric, fabric);
                float damp_roughness = mix(ROUGHNESS, max(0.66, ROUGHNESS), 0.48 * fabric_stain);
                ROUGHNESS = mix(skin_roughness, damp_roughness, fabric);
                METALLIC = mix(METALLIC, 0.0, mix(mix(skin_stain, 1.0, skin_wetness), fabric_stain, fabric));
                SPECULAR = mix(skin_specular, SPECULAR * (1.0 - 0.58 * fabric_stain), fabric);
            }

            float opening_field = 0.0;
            float opening_coverage = 0.0;
            float opening_edge = mix(0.38, 0.32, fabric);
            float fray_noise = 0.5;
            float tear_shape = 0.5;
            if (damage.b > 0.08) {
                vec2 fray_uv = detail_uv * 2.8 + vec2(0.31, -0.43);
                fray_noise = use_blood_noise ? textureGrad(blood_noise, fray_uv, detail_dx * 2.8, detail_dy * 2.8).r
                    : fallback_noise(fray_uv * 0.32);
                tear_shape = fallback_noise(detail_uv * 0.115 + vec2(0.43, -0.73));
                float contour_breakup = (tear_shape - 0.5) * 0.61 + (detail - 0.5) * 0.25 + (fray_noise - 0.5) * 0.09;
                opening_field = damage.b + contour_breakup * (4.0 * damage.b * (1.0 - damage.b));
                opening_coverage = smoothstep(opening_edge, 0.46, opening_field);
            }

            float shaped = overlay(overlay(damage.r, detail), detail);
            float coverage = smoothstep(0.25, 0.75, shaped);
            float compact = mix(damage.r, shaped, 0.12);
            float compact_edge = mix(0.74, 0.66, recess);
            if (progressive > 0.0) {
                float compact_coverage = smoothstep(compact_edge, mix(0.96, 0.90, recess), compact);
                coverage = mix(coverage, min(coverage, compact_coverage), progressive);
            }

            // Repeated contacts can open the shoulder independently of the
            // compact pellet mark. A faint irregularity breaks the rim.
            float eroded_contour = material_loss + (detail - 0.5) * 0.08 * smoothstep(0.09, 0.20, material_loss);
            float erosion_coverage = smoothstep(0.13, 0.32, eroded_contour) * progressive;
            coverage = max(coverage, erosion_coverage);

            if (fabric > 0.0 && damage.g > 0.001 && max(damage.r, damage.b) > 0.07 && max(coverage, opening_coverage) < 1.0) {
                // Break up the blood that wicks along the fabric edge.
                float streak = fallback_noise(detail_uv * vec2(0.70, 1.55) + vec2(0.63, 0.12));
                float grain = fallback_noise(detail_uv * 2.4 + vec2(-0.31, 0.59));
                float wicking = smoothstep(0.36, 0.68, mix(streak, detail, 0.27));
                float fringe = smoothstep(0.27, 0.70, grain);
                float wick_width = mix(0.32, 1.32, wicking) * mix(0.56, 1.16, fringe);
                float pellet_spill = wound_blood_spill(mix(shaped, compact, progressive), mix(0.25, compact_edge, progressive),
                    mix(0.14, 0.19, progressive) * wick_width, pellet_gradient, grain) * smoothstep(0.07, 0.26, damage.r);
                float opening_spill = wound_blood_spill(opening_field, opening_edge, 0.14 * wick_width,
                    opening_gradient, mix(grain, fray_noise, 0.35));
                float blood_available = smoothstep(0.012, 0.43, damage.g);
                float exposed = 1.0 - smoothstep(0.32, 0.96, max(coverage, opening_coverage));
                float wet_film = max(pellet_spill, opening_spill) * blood_available * exposed
                    * mix(0.08, 0.76, wicking) * mix(0.30, 1.0, fringe) * fabric;
                vec3 wet_tint = clamp(blood_tint * mix(1.45, 2.85, wicking), vec3(0.0), vec3(0.35)) + vec3(0.004, 0.0020, 0.0024);
                wet_tint = mix(wet_tint, ALBEDO * vec3(0.94, 0.72, 0.68), 0.24 * fabric);
                ALBEDO = mix(ALBEDO, wet_tint, wet_film);
                ROUGHNESS = mix(ROUGHNESS, mix(0.52, 0.40, wicking), wet_film);
                METALLIC = mix(METALLIC, 0.0, wet_film);
                SPECULAR = mix(SPECULAR, 0.23, wet_film);

                float feather = blood_available * mix(0.60, 0.20, fringe) * fabric;
                coverage *= 1.0 - feather * pellet_spill * (1.0 - smoothstep(0.35, 0.86, coverage));
                opening_coverage *= 1.0 - feather * opening_spill * (1.0 - smoothstep(0.35, 0.86, opening_coverage));
            }
            vec3 wound_normal = normalize(NORMAL);
            vec3 surface_dx = vec3(0.0);
            vec3 surface_dy = vec3(0.0);
            if (max(coverage, opening_coverage) > 0.0) {
                // Convert screen derivatives to surface directions for the
                // normal map and rim lighting on the current pose.
                vec3 gradient_x = cross(position_dy, wound_normal);
                float orientation = sign(dot(position_dx, gradient_x));
                surface_dx = gradient_x * orientation;
                surface_dy = cross(wound_normal, position_dx) * orientation;
            }
            if (coverage > 0.0 && opening_coverage < 1.0) {
                float rim = 1.0 - smoothstep(0.62, 0.87, shaped);
                vec3 wall_direction = vec3(0.0);
                float floor_coverage = 1.0;
                if (recess > 0.0) {
                    vec3 view_tangent = VIEW - wound_normal * dot(wound_normal, VIEW);
                    wall_direction = wound_direction(surface_dx * pellet_gradient.x + surface_dy * pellet_gradient.y);
                    float side = clamp(-dot(wall_direction, view_tangent), -0.65, 0.75);
                    float wall_edge = mix(0.52, 0.73, late_depth) + side * mix(0.10, 0.22, late_depth) + (detail - 0.5) * 0.12;
                    wall_edge += core_depth * (0.09 + side * 0.18);
                    float floor_width = mix(0.20, 0.13, core_depth);
                    floor_coverage = smoothstep(wall_edge, wall_edge + floor_width, mix(damage.r, shaped, 0.20));
                }
                vec3 erosion_slope = vec3(0.0);
                float cavity_depth = eroded_height;
                vec2 sample_uv = tissue_uv;
                if (erosion_coverage > 0.0) {
                    // Convert the depth derivatives into a surface slope in
                    // view space, with depth measured in scene units.
                    float inv_area = 1.0 / max(abs(dot(position_dx, surface_dx)), 1e-10);
                    erosion_slope = (surface_dx * height_gradient.x + surface_dy * height_gradient.y) * (inv_area * skin_wound_max_depth);
                    erosion_slope /= max(1.0, length(erosion_slope) / 1.45);

                    float normal_view = dot(wound_normal, VIEW);
                    vec3 view_tangent = VIEW - wound_normal * normal_view;
                    vec2 uv_dx = tissue_dx / 14.0;
                    vec2 uv_dy = tissue_dy / 14.0;
                    vec2 uv_along_view = vec2(dot(surface_dx * uv_dx.x + surface_dy * uv_dy.x, view_tangent),
                        dot(surface_dx * uv_dx.y + surface_dy * uv_dy.y, view_tangent)) * inv_area;
                    vec2 sweep = -uv_along_view * (skin_wound_max_depth / max(abs(normal_view), 0.30));
                    sweep /= max(1.0, length(sweep) / 0.035);
                    float pixel_footprint = max(length(uv_dx), length(uv_dy));
                    float relief = smoothstep(0.22, 0.38, material_loss) * (1.0 - smoothstep(0.002, 0.006, pixel_footprint));
                    if (relief > 0.0 && dot(sweep, sweep) > 1e-8) {
                        vec3 hit = trace_wound_relief(damage_uv, sweep, eroded_height);
                        sample_uv = mix(tissue_uv, hit.xy * 14.0, relief);
                        cavity_depth = mix(eroded_height, hit.z, relief);
                    }
                }
                vec3 tissue_map = textureGrad(skin_wound_albedo, sample_uv, tissue_dx, tissue_dy).rgb * skin_wound_tissue_tint.rgb;
                vec3 tissue = tissue_map * (vec3(0.55, 0.28, 0.27) * mix(1.0, 0.48, rim));
                float roughness_detail = textureGrad(skin_wound_roughness, sample_uv, tissue_dx, tissue_dy).r * skin_wound_tissue_roughness;
                float tissue_roughness = mix(0.38 + roughness_detail * 0.44, 0.69, rim);
                float tissue_specular = 0.29;
                vec3 view_slope = wound_slope(sample_uv, tissue_dx, tissue_dy, surface_dx, surface_dy);
                if (progressive > 0.0) {
                    vec3 shallow_tissue = tissue_map * vec3(0.35, 0.27, 0.26) * mix(0.88, 0.54, rim);
                    float tissue_value = dot(shallow_tissue, vec3(0.2126, 0.7152, 0.0722));
                    shallow_tissue = mix(shallow_tissue, tissue_value * vec3(1.23, 0.85, 0.78), 0.25);
                    tissue = mix(tissue, shallow_tissue, progressive);
                    tissue_roughness = mix(tissue_roughness, mix(0.56 + roughness_detail * 0.27, 0.76, rim), progressive);
                    tissue_specular = mix(tissue_specular, 0.17, progressive);
                    view_slope *= mix(1.0, 0.69, progressive);
                }
                if (recess > 0.0) {
                    vec3 wall = vec3(0.010, 0.0028, 0.0037) + blood_tint * 0.08;
                    // Leave a few broken patches of the source weave along a
                    // cloth rim while the inner wall falls into shadow.
                    float cloth_edge = (1.0 - smoothstep(0.46, 0.66, shaped)) * smoothstep(0.42, 0.70, detail);
                    wall = mix(wall, base.rgb * vec3(0.20, 0.09, 0.075), 0.60 * fabric * cloth_edge);
                    float floor_shade = mix(0.80, 0.53, late_depth);
                    vec3 floor_color = tissue * (vec3(floor_shade) + vec3(0.0, 0.07, 0.10));
                    if (late_depth > 0.0 && floor_coverage > 0.0) {
                        // Blend a coarser projection into the deepest floor.
                        // The wall and shallower marks keep the original tile.
                        vec2 coarse_uv = tissue_uv * 0.57 + vec2(0.39, 0.17);
                        vec3 coarse = textureGrad(skin_wound_albedo, coarse_uv, tissue_dx * 0.57, tissue_dy * 0.57).rgb * skin_wound_tissue_tint.rgb;
                        coarse *= vec3(0.24, 0.20, 0.19);
                        float tissue_value = dot(coarse, vec3(0.2126, 0.7152, 0.0722));
                        coarse = mix(coarse, tissue_value * vec3(1.12, 0.88, 0.82), 0.45);
                        floor_color = mix(floor_color, coarse, late_depth);
                    }
                    wall *= mix(1.0, 0.53, core_depth);
                    floor_color *= mix(1.0, 0.35, core_depth);
                    tissue = mix(tissue, mix(wall, floor_color, floor_coverage), recess);
                    float cavity_roughness = mix(0.76, 0.59 + roughness_detail * 0.24, floor_coverage);
                    tissue_roughness = mix(tissue_roughness, mix(cavity_roughness, 0.87, core_depth), recess);
                    float cavity_specular = mix(0.09, 0.14, floor_coverage);
                    tissue_specular = mix(tissue_specular, mix(cavity_specular, 0.045, core_depth), recess);
                    view_slope *= 1.0 - recess * (0.68 - floor_coverage * 0.28 + 0.15 * core_depth);
                    float wall_slope = mix(0.42, 0.82, late_depth) + 0.54 * core_depth;
                    view_slope += wall_direction * (recess * (1.0 - floor_coverage) * wall_slope * min(depth_scale, 2.0));
                    float cavity_ao = mix(0.60, 0.91, floor_coverage) * mix(1.0, 0.64, core_depth);
                    AO *= mix(1.0, cavity_ao, recess * coverage);
                }
                if (erosion_coverage > 0.0) {
                    float deep_floor = smoothstep(0.18, 0.74, cavity_depth * depth_scale);
                    float wall = smoothstep(0.10, 0.74, length(erosion_slope));
                    float eroded_rim = (1.0 - smoothstep(0.13, 0.32, eroded_contour)) * erosion_coverage;
                    vec3 exposed_tissue = tissue_map * mix(vec3(0.31, 0.19, 0.16), vec3(0.085, 0.074, 0.079), deep_floor);
                    exposed_tissue = mix(exposed_tissue, tissue_map * vec3(0.34, 0.21, 0.19), wall * (1.0 - deep_floor * 0.62));
                    vec3 cloth_edge = base.rgb * vec3(0.29, 0.16, 0.13);
                    exposed_tissue = mix(exposed_tissue, cloth_edge, eroded_rim * fabric * smoothstep(0.37, 0.68, detail));
                    tissue = mix(tissue, exposed_tissue, erosion_coverage);
                    tissue_roughness = mix(tissue_roughness, mix(0.52 + roughness_detail * 0.24, 0.86, deep_floor), erosion_coverage);
                    tissue_specular = mix(tissue_specular, mix(0.26, 0.07, deep_floor), erosion_coverage);
                    view_slope *= 1.0 - erosion_coverage * mix(0.35, 0.73, deep_floor);
                    erosion_slope *= erosion_coverage;
                    AO *= 1.0 - erosion_coverage * mix(0.14, 0.54, deep_floor);
                }
                // Fade the original material's bump out inside the wound.
                NORMAL = normalize(NORMAL + view_slope * (coverage * 0.46) + erosion_slope * coverage);
                NORMAL_MAP = mix(NORMAL_MAP, vec3(0.5, 0.5, 1.0), coverage);
                ALBEDO = mix(ALBEDO, tissue, coverage);
                ROUGHNESS = mix(ROUGHNESS, tissue_roughness, coverage);
                METALLIC = mix(METALLIC, 0.0, coverage);
                SPECULAR = mix(SPECULAR, tissue_specular, coverage);
            }

            if (opening_coverage > 0.0) {
                vec3 view_tangent = VIEW - wound_normal * dot(wound_normal, VIEW);
                float aperture = smoothstep(0.45, 0.54, opening_field);

                vec3 skin_lip = mix(base.rgb * vec3(0.40, 0.13, 0.14), blood_tint * 0.9, 0.5);
                vec3 lip = skin_lip;
                if (fabric > 0.0 && aperture < 1.0) {
                    // Break the threads into short segments and filter them
                    // out as their width drops below a pixel.
                    vec2 thread_direction = vec2(102.0, -46.0);
                    float thread_phase = dot(detail_uv, thread_direction) + detail * 6.0 + fray_noise * 9.0;
                    float thread_footprint = max(abs(dot(detail_dx, thread_direction)), abs(dot(detail_dy, thread_direction)));
                    float fibers = smoothstep(0.62, 0.95, sin(thread_phase)) * smoothstep(0.44, 0.70, fray_noise)
                        * smoothstep(0.39, 0.62, detail)
                        * (1.0 - smoothstep(0.80, 2.75, thread_footprint));
                    float lifted_cloth = smoothstep(0.52, 0.75, tear_shape) * smoothstep(0.25, 0.58, fray_noise);
                    vec3 cloth_lip = base.rgb * (mix(vec3(0.13, 0.066, 0.064), vec3(0.35, 0.24, 0.20), lifted_cloth)
                        + vec3(0.45, 0.32, 0.26) * fibers);
                    lip = mix(skin_lip, cloth_lip, fabric);
                }

                vec3 opening_albedo = lip;
                float opening_roughness = mix(0.61, 0.84, fabric);
                float opening_specular = mix(0.22, 0.13, fabric);
                if (aperture > 0.0) {
                    vec3 wall_direction = wound_direction(surface_dx * opening_gradient.x + surface_dy * opening_gradient.y);
                    float side = clamp(-dot(wall_direction, view_tangent), -0.6, 0.8);
                    float wall_shape = (tear_shape - 0.5) * 0.19 + (detail - 0.5) * 0.05;
                    float floor_coverage = smoothstep(0.60 + side * 0.20 + wall_shape, 0.80 + side * 0.16 + wall_shape, opening_field);
                    vec3 cavity = vec3(0.008, 0.0025, 0.003) + blood_tint * 0.08;
                    float cavity_roughness = 0.68;
                    vec3 view_slope = wall_direction * (0.48 * (1.0 - floor_coverage));
                    if (floor_coverage > 0.0) {
                        vec3 tissue = textureGrad(skin_wound_albedo, tissue_uv, tissue_dx, tissue_dy).rgb * skin_wound_tissue_tint.rgb;
                        tissue *= vec3(0.32, 0.24, 0.23);
                        float tissue_value = dot(tissue, vec3(0.2126, 0.7152, 0.0722));
                        tissue = mix(tissue, tissue_value * vec3(1.16, 0.86, 0.79), 0.35);
                        cavity = mix(cavity, tissue, floor_coverage);
                        float roughness_detail = textureGrad(skin_wound_roughness, tissue_uv, tissue_dx, tissue_dy).r * skin_wound_tissue_roughness;
                        cavity_roughness = mix(cavity_roughness, 0.51 + roughness_detail * 0.35, floor_coverage);
                        view_slope += wound_slope(tissue_uv, tissue_dx, tissue_dy, surface_dx, surface_dy) * (floor_coverage * 0.30);
                    }
                    float inside = aperture * opening_coverage;
                    NORMAL = normalize(mix(NORMAL, normalize(wound_normal + view_slope), inside));
                    NORMAL_MAP = mix(NORMAL_MAP, vec3(0.5, 0.5, 1.0), inside);
                    AO *= mix(1.0, mix(0.58, 0.88, floor_coverage), inside);
                    opening_albedo = mix(lip, cavity, aperture);
                    opening_roughness = mix(opening_roughness, cavity_roughness, aperture);
                    opening_specular = mix(opening_specular, mix(0.10, 0.18, floor_coverage), aperture);
                }
                ALBEDO = mix(ALBEDO, opening_albedo, opening_coverage);
                ROUGHNESS = mix(ROUGHNESS, opening_roughness, opening_coverage);
                METALLIC = mix(METALLIC, 0.0, opening_coverage);
                SPECULAR = mix(SPECULAR, opening_specular, opening_coverage);
            }
        }
    }
    // TRANSPARENCY_OUTPUT: native conversion inserts alpha only for transparent
    // source materials, so opaque characters keep the opaque render pipeline.
}
