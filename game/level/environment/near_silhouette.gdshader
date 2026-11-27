shader_type canvas_item;
render_mode unshaded;
// 近前景剪影（BG-68）：貼圖只取形狀（alpha），填成很暗的環境色；朝主光那一側的邊緣亮一圈邊緣光。
// 懸掛物另外被風吹（頂端固定、底部擺動）並可被經過的角色帶動（kick，與 sway.gdshader 相同的做法）。
uniform vec4 fill_color : source_color = vec4(0.03, 0.025, 0.03, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.7, 0.45, 1.0);
// 主光在哪個方向（畫面方向的單位向量）；邊緣光畫在朝它的那一側。
uniform vec2 rim_direction = vec2(-0.6, -0.8);
uniform float rim_strength = 0.38;
uniform float amplitude = 0.0;
uniform float speed = 1.1;
uniform bool hang = false;
instance uniform float kick = 0.0;
// 邊緣光的寬度換成貼圖像素（每件的縮放不同）。
instance uniform float rim_texels = 6.0;

void vertex() {
	float height = clamp(hang ? UV.y : 1.0 - UV.y, 0.0, 1.0);
	float phase = MODEL_MATRIX[3].x * 0.07;
	float pixels_per_unit = max(length(MODEL_MATRIX[0].xy), 0.0001);
	VERTEX.x += (amplitude * sin(TIME * speed + phase) + kick) / pixels_per_unit * height * height;
}

void fragment() {
	float alpha = texture(TEXTURE, UV).a;
	// 往主光方向看過去是透明的地方，就是朝光的邊緣。
	vec2 step_uv = rim_direction * TEXTURE_PIXEL_SIZE * rim_texels;
	float outside = 1.0 - texture(TEXTURE, UV + step_uv).a;
	float rim = clamp(outside * alpha, 0.0, 1.0) * rim_strength;
	COLOR = vec4(mix(fill_color.rgb, rim_color.rgb, rim), alpha * fill_color.a);
}
