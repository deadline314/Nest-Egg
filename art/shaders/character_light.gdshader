shader_type canvas_item;
// 角色專用的受光（NE-213）：每一盞光對角色的貢獻有柔和上限，而且不跟著補光倍率放大。
// 為什麼：環境很暗時，角色零件的 modulate 會乘上補光倍率（最高 4 倍）讓角色看得見；預設的受光公式是「零件顏色 × 光」，
// 光也被同一個倍率放大，白色頭髮在燈下就變成 HDR 的數倍亮度，被泛光暈成一大團白。
// 這裡把光的貢獻除回補光倍率（補光只用在環境光），再把單盞光的亮度用 tanh 壓在 light_cap 以內（亮度小的時候幾乎不變）。
uniform float fill = 1.0;
uniform float light_cap : hint_range(0.05, 4.0) = 0.5;

// 區域擺動（NE-257）：頭髮、衣襬烤在整張零件圖裡的角色，不重切零件，讓圖上的一個區域繞著根部跟彈簧彎。
// sway_x = 根部與末端（貼圖像素），sway_x_shape = (區域半寬, 目前角度)。半寬為 0 時完全不動，走引擎原本的取樣。
// 角度很小（上限約 0.3 弧度），所以用「輸出像素往回找來源像素」的近似；四邊各加 SWAY_PAD 像素，彎出去的部分才不會被零件圖的邊界切掉。
instance uniform vec4 sway_a = vec4(0.0);
instance uniform vec2 sway_a_shape = vec2(0.0);
instance uniform vec4 sway_b = vec4(0.0);
instance uniform vec2 sway_b_shape = vec2(0.0);
// Sprite quads need a border; weighted meshes retain their authored topology and UVs.
instance uniform float sway_padding = 24.0;
varying vec4 sway_tint;

vec2 sway_source(vec2 p, vec4 seg, vec2 shape) {
	if (shape.x <= 0.0) {
		return p;
	}
	vec2 axis = seg.zw - seg.xy;
	float len = max(length(axis), 1.0);
	vec2 dir = axis / len;
	vec2 rel = p - seg.xy;
	float weight = smoothstep(0.0, 1.0, dot(rel, dir) / len) * (1.0 - smoothstep(shape.x * 0.6, shape.x, abs(dot(rel, vec2(-dir.y, dir.x)))));
	float angle = -shape.y * weight;
	float c = cos(angle);
	float s = sin(angle);
	return seg.xy + vec2(rel.x * c - rel.y * s, rel.x * s + rel.y * c);
}

void vertex() {
	sway_tint = COLOR;
	if (sway_a_shape.x > 0.0 || sway_b_shape.x > 0.0) {
		vec2 corner = step(0.5, UV) * 2.0 - 1.0;
		VERTEX += corner * sway_padding;
		UV += corner * sway_padding * TEXTURE_PIXEL_SIZE;
	}
}

void fragment() {
	// NORMAL_MAP is a compile-time shader output: initialize every fragment, including regions with no sway.
	NORMAL_MAP = texture(NORMAL_TEXTURE, UV).rgb;
	if (sway_a_shape.x > 0.0 || sway_b_shape.x > 0.0) {
		vec2 uv = sway_source(sway_source(UV / TEXTURE_PIXEL_SIZE, sway_a, sway_a_shape), sway_b, sway_b_shape) * TEXTURE_PIXEL_SIZE;
		float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
		COLOR = texture(TEXTURE, uv) * sway_tint * vec4(1.0, 1.0, 1.0, inside);
		NORMAL_MAP = texture(NORMAL_TEXTURE, uv).rgb;
	}
}

void light() {
	float n_dot_l = max(0.0, dot(NORMAL, LIGHT_DIRECTION));
	vec3 lit = LIGHT_COLOR.rgb * LIGHT_ENERGY * COLOR.rgb * n_dot_l / max(fill, 0.0001);
	float peak = max(lit.r, max(lit.g, lit.b));
	float keep = peak > 0.0001 ? light_cap * tanh(peak / light_cap) / peak : 1.0;
	LIGHT = vec4(lit * keep, LIGHT_COLOR.a);
}
