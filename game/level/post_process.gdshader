shader_type canvas_item;
// 全螢幕後製：邊緣色差 → 調色（去飽和、對比、陰影／亮部色調）→ 暗角 → 玩家亮度設定 → 顆粒。
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
uniform float brightness = 1.0;
uniform float danger = 0.0;
uniform float grain_seed = 0.0;
// 全螢幕效果（受傷、格擋、擊殺…）：疊加色、強度、額外色差與暗角；強度已由 FlashGuard 限制。
uniform vec3 pulse_color = vec3(1.0);
uniform float pulse_amount = 0.0;
uniform float pulse_aberration = 0.0;
uniform float pulse_vignette = 0.0;

const float CONTRAST_PIVOT = 0.3;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 centered = uv - vec2(0.5);
	float edge = dot(centered, centered) * 4.0;

	vec3 color;
	vec2 shift = centered * (aberration + pulse_aberration) * edge;
	color.r = texture(screen_tex, uv + shift).r;
	color.g = texture(screen_tex, uv).g;
	color.b = texture(screen_tex, uv - shift).b;

	float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
	color = mix(vec3(luma), color, saturation);
	color = max((color - vec3(CONTRAST_PIVOT)) * contrast + vec3(CONTRAST_PIVOT), vec3(0.0));
	color *= mix(shadow_tint, highlight_tint, smoothstep(0.05, 0.6, luma));

	// 危險（低血量）：暗角收緊並帶紅色，強度由程式端脈動。
	float falloff = smoothstep(0.3 - danger * 0.12, 1.05 - danger * 0.2, length(centered) * 1.7);
	vec3 edge_color = mix(vignette_color, vec3(0.32, 0.015, 0.03), clamp(danger, 0.0, 1.0));
	color = mix(color, edge_color, clamp(falloff * (vignette + pulse_vignette + danger * 0.5), 0.0, 1.0));
	color += pulse_color * pulse_amount;

	// 玩家的亮度設定（gamma）：大於 1 提亮暗部，黑色與暗角的黑維持不變。
	color = pow(max(color, vec3(0.0)), vec3(1.0 / brightness));

	// 顆粒（只有特殊情境的光影設定才大於 0）：畫面是線性 HDR，直接相加會讓暗部變成一片雪花，
	// 所以換到接近螢幕顯示的亮度再加，暗部與亮部看起來一樣輕；亮部（子彈、霓虹）保持乾淨。
	if (grain > 0.0) {
		float noise = hash(floor(uv * vec2(640.0, 360.0)) + vec2(grain_seed)) - 0.5;
		vec3 shown = pow(max(color, vec3(0.0)), vec3(1.0 / 2.2));
		shown += vec3(noise * grain * (1.0 - clamp(dot(shown, vec3(0.2126, 0.7152, 0.0722)), 0.0, 1.0)));
		color = pow(max(shown, vec3(0.0)), vec3(2.2));
	}

	COLOR = vec4(color, 1.0);
}
