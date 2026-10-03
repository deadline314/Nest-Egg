shader_type canvas_item;
render_mode unshaded;
// 螢幕掃描：看板、螢幕、販賣機的自發光層上，一條較亮的橫帶由下往上緩慢掃過，並帶細微的掃描線。
// 共用一份材質（同強度的道具共用），沒有每影格腳本；以道具位置錯開相位，並排的看板不會同步。
uniform float strength = 0.4;
uniform float speed = 0.3;
uniform float lines = 180.0;  // 掃描線密度（整張貼圖高度內的線數）

varying float phase;

void vertex() {
	phase = fract(MODEL_MATRIX[3].x * 0.013 + MODEL_MATRIX[3].y * 0.029);
}

void fragment() {
	float sweep = pow(1.0 - fract(UV.y + TIME * speed + phase), 3.0);
	float scan = 0.5 + 0.5 * sin(UV.y * lines * 6.2831);
	float k = 1.0 - strength * 0.5 + strength * 0.9 * sweep;
	k *= 1.0 - strength * 0.25 * scan;
	COLOR.rgb *= k;
}
