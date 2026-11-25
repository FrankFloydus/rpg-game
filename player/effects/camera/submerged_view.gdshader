shader_type canvas_item;

uniform sampler2D scene_screen : hint_screen_texture, repeat_disable, filter_linear;
uniform float immersion : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 waves = vec2(sin(SCREEN_UV.y * 37.0 + TIME * 1.65),
		cos(SCREEN_UV.x * 29.0 - TIME * 1.46));
	vec2 distortion = waves * SCREEN_PIXEL_SIZE * 3.2 * immersion;
	vec2 uv = clamp(SCREEN_UV + distortion, SCREEN_PIXEL_SIZE, vec2(1.0) - SCREEN_PIXEL_SIZE);
	vec3 view_color = texture(scene_screen, uv).rgb;
	vec3 tint = vec3(0.039, 0.121, 0.125);
	vec3 through_water = view_color * vec3(0.58, 0.84, 0.88) + tint * 0.29;
	COLOR = vec4(mix(view_color, through_water, immersion), 1.0);
}
