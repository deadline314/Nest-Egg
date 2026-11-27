shader_type canvas_item;
render_mode unshaded;
// 近前景剪影（BG-68、BG-71）：貼圖只取形狀（alpha），填成比走道最暗處還暗的環境色；
// 亮邊只在朝主光（上方、稍微偏向主光那側）的邊緣，一像素寬，而且背後要是實心的一塊（細網格與細線條本身不吃亮邊）。
// rim_all_sides：葉緣這種背光透亮的邊，四周都帶一點主光色（垂葉壓在深色背景上才分得出來）。
// 懸掛物另外被風吹（頂端固定、底部擺動）並可被經過的角色帶動（kick，與 sway.gdshader 相同的做法）。
uniform vec4 fill_color : source_color = vec4(0.02, 0.018, 0.022, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.7, 0.45, 1.0);
uniform vec2 rim_direction = vec2(-0.33, -0.94);
uniform float rim_strength = 0.12;
uniform bool rim_all_sides = false;
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
	vec2 step_uv = TEXTURE_PIXEL_SIZE * rim_texels;
	// 朝主光那側：外面是透明、往內三倍寬還是實心，才算是一塊面的邊（細線條、網格不算）。
	float rim = (1.0 - texture(TEXTURE, UV + rim_direction * step_uv).a) * step(0.5, texture(TEXTURE, UV - rim_direction * step_uv * 3.0).a);
	if (rim_all_sides) {
		float right = (1.0 - texture(TEXTURE, UV + vec2(step_uv.x, 0.0)).a) * step(0.5, texture(TEXTURE, UV - vec2(step_uv.x * 3.0, 0.0)).a);
		float left = (1.0 - texture(TEXTURE, UV - vec2(step_uv.x, 0.0)).a) * step(0.5, texture(TEXTURE, UV + vec2(step_uv.x * 3.0, 0.0)).a);
		float below = (1.0 - texture(TEXTURE, UV + vec2(0.0, step_uv.y)).a) * step(0.5, texture(TEXTURE, UV - vec2(0.0, step_uv.y * 3.0)).a);
		rim = max(rim, 0.6 * max(max(right, left), below));
	}
	rim = clamp(rim * alpha, 0.0, 1.0) * rim_strength;
	COLOR = vec4(mix(fill_color.rgb, rim_color.rgb, rim), alpha * fill_color.a);
}
