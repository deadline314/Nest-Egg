shader_type canvas_item;
// 全螢幕後製：邊緣色差 → 調色（去飽和、對比、陰影／亮部色調）→ 暗角 → 顆粒。
// 一個 pass 完成，讀取已繪製好的場景畫面；HUD 與選單畫在它上面，不受影響。
// 輸出不夾在 0~1，保留 HDR 亮度讓泛光正常運作。

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float saturation = 1.0;
uniform float contrast = 1.0;
uniform vec3 shadow_tint = vec3(1.0);
uniform vec3 highlight_tint = vec3(1.0);
uniform float vignette = 0.0;
uniform vec3 vignette_color = vec3(0.0);
uniform float grain = 0.0;
uniform float aberration = 0.0;
uniform float grain_seed = 0.0;

const float CONTRAST_PIVOT = 0.3;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 centered = uv - vec2(0.5);
	float edge = dot(centered, centered) * 4.0;

	vec3 color;
	vec2 shift = centered * aberration * edge;
	color.r = texture(screen_tex, uv + shift).r;
	color.g = texture(screen_tex, uv).g;
	color.b = texture(screen_tex, uv - shift).b;

	float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
	color = mix(vec3(luma), color, saturation);
	color = max((color - vec3(CONTRAST_PIVOT)) * contrast + vec3(CONTRAST_PIVOT), vec3(0.0));
	color *= mix(shadow_tint, highlight_tint, smoothstep(0.05, 0.6, luma));

	float falloff = smoothstep(0.3, 1.05, length(centered) * 1.7);
	color = mix(color, vignette_color, clamp(falloff * vignette, 0.0, 1.0));

	// 顆粒在暗部較明顯，亮部（子彈、霓虹）保持乾淨。
	float noise = hash(floor(uv * vec2(640.0, 360.0)) + vec2(grain_seed)) - 0.5;
	color += vec3(noise * grain * (1.0 - clamp(luma, 0.0, 1.0)));

	COLOR = vec4(color, 1.0);
}
