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
uniform float pulse_edge_mix = 0.0;
uniform float pulse_aberration = 0.0;
uniform float pulse_vignette = 0.0;

const float CONTRAST_PIVOT = 0.3;
// 鮮豔到多少開始保留飽和度、多少完全保留；太暗的像素（接近黑）不算鮮豔。
const float VIVID_FROM = 0.45;
const float VIVID_TO = 0.7;
const float VIVID_MIN_VALUE = 0.12;
const float VIVID_TINT_SPARE = 0.8;
// 遊戲性顏色的色相帶（度）：暖色帶以 340 為中心（270～50：紅、粉紅、洋紅、紫紅的頭髮與鞋、橘紅），
// 青色帶以 187 為中心（169～205：互動標記、主角衣服的霓虹）。場景的藍色玻璃（約 210～220）不在帶裡。
const float WARM_HUE = 340.0;
const float WARM_HALF = 70.0;
const float CYAN_HUE = 187.0;
const float CYAN_HALF = 18.0;
const float HUE_EDGE = 10.0;
// 遊戲性顏色的最高亮度（線性）。
const float GAMEPLAY_PEAK = 1.3;
const float RED_HALF = 18.0;

// 這個顏色落在遊戲性顏色色相帶裡的程度（0～1，帶的邊緣漸變）。
float gameplay_hue(vec3 c) {
	float top = max(max(c.r, c.g), c.b);
	float span = top - min(min(c.r, c.g), c.b);
	if (span < 0.0001) {
		return 0.0;
	}
	float hue;
	if (top == c.r) {
		hue = mod((c.g - c.b) / span, 6.0);
	} else if (top == c.g) {
		hue = (c.b - c.r) / span + 2.0;
	} else {
		hue = (c.r - c.g) / span + 4.0;
	}
	hue *= 60.0;
	float warm = abs(mod(hue - WARM_HUE + 180.0, 360.0) - 180.0);
	float cyan = abs(hue - CYAN_HUE);
	return max(1.0 - smoothstep(WARM_HALF, WARM_HALF + HUE_EDGE, warm), 1.0 - smoothstep(CYAN_HALF, CYAN_HALF + HUE_EDGE, cyan));
}

// 這個顏色是不是危險紅（色相 RED_HALF 度以內，邊緣漸變）。
float danger_hue(vec3 c) {
	float top = max(max(c.r, c.g), c.b);
	float span = top - min(min(c.r, c.g), c.b);
	if (span < 0.0001 || top != c.r) {
		return 0.0;
	}
	float hue = abs(mod((c.g - c.b) / span, 6.0) * 60.0);
	float distance = min(hue, 360.0 - hue);
	return 1.0 - smoothstep(RED_HALF, RED_HALF + HUE_EDGE, distance);
}

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
	// 區域的降飽和只作用在場景（BG-78）：本來就很鮮豔的顏色（危險預兆的紅、主角的霓虹與頭髮、敵人的識別色、互動標記）
	// 保留原本的飽和度；判斷鮮不鮮豔用接近螢幕顯示的值（線性值會把暗淡的木頭也算成很鮮豔）。
	vec3 shown = pow(max(color, vec3(0.0)), vec3(1.0 / 2.2));
	float top = max(max(shown.r, shown.g), shown.b);
	float vivid = top > 0.0001 ? (top - min(min(shown.r, shown.g), shown.b)) / top : 0.0;
	// 只保留遊戲性顏色的兩個色相帶：紅／粉紅／洋紅（危險預兆、主角的頭髮與霓虹、敵人的識別色）與青（互動標記）。
	// 場景裡的藍色玻璃、綠色招牌等照樣跟著區域降飽和（冷白的區域仍然冷白）。
	float keep = smoothstep(VIVID_FROM, VIVID_TO, vivid) * step(VIVID_MIN_VALUE, top) * gameplay_hue(shown);
	color = mix(vec3(luma), color, mix(saturation, max(saturation, 1.0), keep));
	// 很亮的遊戲性顏色（發光的落點圈、雷射）在螢幕上每個色版都會到頂、紅色就變成白色：把它的亮度壓到 GAMEPLAY_PEAK，
	// 色相保住，最亮的色版仍略高於 1（泛光照樣有一點）。
	// 只對危險紅（色相 0 附近）做：走道邊緣的青色亮邊、鈉燈的琥珀亮邊要維持原本的亮度（可讀性量的就是它們）。
	float peak = max(max(color.r, color.g), color.b);
	if (peak > GAMEPLAY_PEAK) {
		color *= mix(1.0, GAMEPLAY_PEAK / peak, keep * danger_hue(shown));
	}
	color = max((color - vec3(CONTRAST_PIVOT)) * contrast + vec3(CONTRAST_PIVOT), vec3(0.0));
	// 陰影／亮部的色調同樣大半不套在鮮豔的顏色上（冷藍或青綠的區域不會把紅色預兆推成洋紅或灰）。
	color *= mix(mix(shadow_tint, highlight_tint, smoothstep(0.05, 0.6, luma)), vec3(1.0), keep * VIVID_TINT_SPARE);

	// 光影設定的暗角（不變）。
	float radius = length(centered) * 1.7;
	float falloff = smoothstep(0.3, 1.05, radius);
	color = mix(color, vignette_color, clamp(falloff * vignette, 0.0, 1.0));
	// 受傷與低血量只出現在外圈（NE-428）：中間的角色、敵人與提示文字保持乾淨。
	// 低血量：外圈先去飽和再壓暗，紅色只留一點，在任何色調的場景都看得出來；脈動由程式端控制。
	float rim = smoothstep(0.56, 1.12, radius);
	float threat = clamp(danger, 0.0, 1.0);
	float rim_luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
	color = mix(color, vec3(rim_luma) * 0.45, rim * threat * 0.95);
	vec3 rim_color = mix(vignette_color, vec3(0.3, 0.02, 0.03), threat);
	color = mix(color, rim_color, clamp(rim * (pulse_vignette + threat * 0.25), 0.0, 1.0));
	color += pulse_color * pulse_amount * mix(1.0, rim, pulse_edge_mix);

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
