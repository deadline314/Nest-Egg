shader_type canvas_item;
// 角色專用的受光（NE-213）：每一盞光對角色的貢獻有柔和上限，而且不跟著補光倍率放大。
// 為什麼：環境很暗時，角色零件的 modulate 會乘上補光倍率（最高 4 倍）讓角色看得見；預設的受光公式是「零件顏色 × 光」，
// 光也被同一個倍率放大，白色頭髮在燈下就變成 HDR 的數倍亮度，被泛光暈成一大團白。
// 這裡把光的貢獻除回補光倍率（補光只用在環境光），再把單盞光的亮度用 tanh 壓在 light_cap 以內（亮度小的時候幾乎不變）。
uniform float fill = 1.0;
uniform float light_cap : hint_range(0.05, 4.0) = 0.5;

void light() {
	float n_dot_l = max(0.0, dot(NORMAL, LIGHT_DIRECTION));
	vec3 lit = LIGHT_COLOR.rgb * COLOR.rgb * n_dot_l / max(fill, 0.0001);
	float peak = max(lit.r, max(lit.g, lit.b));
	float keep = peak > 0.0001 ? light_cap * tanh(peak / light_cap) / peak : 1.0;
	LIGHT = vec4(lit * keep, LIGHT_COLOR.a);
}
