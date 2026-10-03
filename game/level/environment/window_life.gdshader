shader_type canvas_item;
render_mode unshaded;
// 窗光的生命：一部分窗戶區塊緩慢閃爍（像電壓不穩、有人開關燈），紅色的點是屋頂信標、會規律明滅。
// 用在建築立面與遠中景的自發光層；全部由著色器處理，沒有每影格腳本、沒有額外節點。
// 以世界座標切格決定哪些區塊會閃，所以同一扇窗永遠同一組節奏，換畫面也不會跳。
uniform float cell = 16.0;          // 閃爍區塊的大小（邏輯像素）
uniform float flicker_share = 0.22; // 會閃的區塊比例
uniform float depth = 0.6;          // 閃爍時最暗降到多少（0 = 不閃）
uniform float beacon_rate = 1.1;    // 信標每秒明滅次數

varying vec2 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float h = hash(floor(world_pos / cell));
	float flicker = step(1.0 - flicker_share, h);
	float wave = 0.5 + 0.5 * sin(TIME * (1.2 + h * 5.0) + h * 40.0) * sin(TIME * 0.6 + h * 11.0);
	float level = 1.0 - flicker * depth * wave;
	// 純紅像素 = 信標
	float beacon = step(0.7, COLOR.r) * (1.0 - step(0.35, COLOR.g)) * (1.0 - step(0.35, COLOR.b));
	float blink = step(0.0, sin(TIME * beacon_rate * 6.2831 + h * 20.0));
	COLOR.rgb *= mix(level, blink, beacon);
	COLOR.a *= mix(1.0, blink, beacon);
}
