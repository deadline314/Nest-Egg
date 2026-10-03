shader_type canvas_item;
render_mode unshaded;
// 水窪的雨滴漣漪：自發光層（霓虹倒影）上，幾個同心圈由隨機點向外擴散並淡出。
// 圖的 alpha 是水窪範圍，圈只畫在水面內；共用一份材質，以道具位置錯開相位，沒有每影格腳本。
uniform vec4 ring_color : source_color = vec4(0.75, 0.9, 1.0, 1.0);
uniform float rate = 0.9;       // 每個發射點每秒的漣漪數
uniform float squash = 7.0;     // 垂直壓扁倍數（水窪是扁的，圈要變成橢圓）
uniform float ring_width = 0.018;

varying float phase;

void vertex() {
	phase = fract(MODEL_MATRIX[3].x * 0.011 + MODEL_MATRIX[3].y * 0.017);
}

float hash(float n) {
	return fract(sin(n * 91.3458) * 47453.5453);
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float water = smoothstep(0.02, 0.2, base.a);
	float rings = 0.0;
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float clock = TIME * rate * 0.5 + fi * 0.33 + phase;
		float cycle = floor(clock);
		float age = fract(clock);
		vec2 center = vec2(0.12 + 0.76 * hash(cycle * 3.1 + fi * 7.7 + phase * 31.0), 0.5);
		vec2 d = (UV - center) * vec2(1.0, squash);
		float radius = age * 0.28;
		float ring = smoothstep(ring_width, 0.0, abs(length(d) - radius)) * (1.0 - age);
		rings += ring;
	}
	COLOR.rgb = base.rgb + ring_color.rgb * rings * water * 0.9;
	COLOR.a = max(base.a, rings * water * 0.85);
}
