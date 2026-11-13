shader_type canvas_item;
#include "res://art/shaders/character_light_response.gdshaderinc"
// 燒融：依世界座標的雜訊逐塊消失，消失的邊緣有一圈發光的炭火色。progress 0→1；rise＞0 時火從腳往上燒，＜0 從頭往下燒。
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 edge_color : source_color = vec4(1.0, 0.5, 0.1, 1.0);
uniform vec4 char_color : source_color = vec4(0.05, 0.03, 0.03, 1.0);
uniform float edge_width = 0.1;
uniform float noise_scale = 0.045;
uniform float rise = 0.0;
uniform float foot_y = 0.0;
uniform float body_height = 60.0;
uniform float glow = 3.0;
varying vec2 world_pos;
varying vec2 normal_surface_position;
varying vec4 base_tint;
varying vec3 surviving_albedo;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	base_tint = COLOR;
	normal_surface_position = VERTEX;
}

void fragment() {
	NORMAL_MAP = character_mesh_normal(texture(NORMAL_TEXTURE, UV).rgb, normal_surface_position, UV);
	vec4 tex = texture(TEXTURE, UV);
	float n = texture(noise_tex, world_pos * noise_scale).r;
	float height01 = clamp((foot_y - world_pos.y) / max(body_height, 1.0), 0.0, 1.0);
	float bias = rise > 0.0 ? (1.0 - height01) * 0.35 : height01 * 0.35;
	float level = clamp(n * (1.0 - 0.35) + bias * abs(rise), 0.0, 1.0);
	float t = progress * (1.0 + edge_width);
	float gone = step(level, t - edge_width);
	float edge = 1.0 - smoothstep(0.0, edge_width, level - (t - edge_width));
	edge *= step(t - edge_width, level) * step(0.0001, progress);
	vec3 col = mix(tex.rgb, char_color.rgb, clamp(edge * 0.8, 0.0, 1.0)) * base_tint.rgb;
	surviving_albedo = col;
	col += edge_color.rgb * edge * glow;
	COLOR = vec4(col, tex.a * base_tint.a * (1.0 - gone));
}

void light() {
	// Burn-edge emission remains in COLOR; lamps only light the surviving base.
	LIGHT = character_light_response(surviving_albedo, NORMAL, LIGHT_DIRECTION, LIGHT_COLOR, LIGHT_ENERGY);
}
