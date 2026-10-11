class_name SceneBackdrop
extends ColorRect
## 資訊頁的底：把暫停當下的遊戲畫面模糊、去飽和並壓暗（左側清單處更暗），上面疊極淡格線與四角括號。
## 背景 HUD 的字被模糊到讀不出來，不會在分頁列後面透出；整頁仍看得出主角身處的場景。
## 只在尺寸改變時重畫；模糊由 GPU 取畫面的縮圖層，不配置圖片。沒有畫面可讀（無頭測試）時就是深色底。

const GRID := 24.0
## HDR 2D 在線性色彩混色，很低的不透明度看起來就夠明顯。
const GRID_COLOR := Color(0.21, 0.88, 1.0, 0.007)
const CORNER := 8.0
const CORNER_INSET := 6.0

static var _shader: Shader


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color(0.02, 0.035, 0.055)
	material = ShaderMaterial.new()
	(material as ShaderMaterial).shader = _blur_shader()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 格線與括號放在子節點：著色器會改寫本節點所有繪圖，子節點不繼承材質。
	var decor := Decor.new()
	decor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(decor)


class Decor extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var x := GRID
		while x < size.x:
			draw_line(Vector2(x, 0), Vector2(x, size.y), GRID_COLOR, 1)
			x += GRID
		var y := GRID
		while y < size.y:
			draw_line(Vector2(0, y), Vector2(size.x, y), GRID_COLOR, 1)
			y += GRID
		var edge := Color(Palette.CYAN_DIM, 0.9)
		for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
			var origin := Vector2(lerpf(CORNER_INSET, size.x - CORNER_INSET, corner.x), lerpf(CORNER_INSET, size.y - CORNER_INSET, corner.y))
			var dx := CORNER if corner.x == 0 else -CORNER
			var dy := CORNER if corner.y == 0 else -CORNER
			draw_line(origin, origin + Vector2(dx, 0), edge, 1)
			draw_line(origin, origin + Vector2(0, dy), edge, 1)


static func _blur_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """
shader_type canvas_item;
// 只模糊這個節點的填色；格線另由 _draw 畫。
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float blur_lod = 2.0;
uniform vec3 tint : source_color = vec3(0.02, 0.035, 0.055);

// 縮圖層再取一圈鄰近樣本平均，避免單取高層縮圖出現方塊狀色斑。
vec3 soft(vec2 uv, vec2 texel) {
	vec3 sum = vec3(0.0);
	float weight = 0.0;
	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			float w = exp(-float(x * x + y * y) / 4.0);
			sum += min(textureLod(screen_tex, uv + vec2(float(x), float(y)) * texel, blur_lod).rgb, vec3(1.2)) * w;
			weight += w;
		}
	}
	return sum / weight;
}

void fragment() {
	vec3 scene = soft(SCREEN_UV, SCREEN_PIXEL_SIZE * 6.0);
	float lum = dot(scene, vec3(0.299, 0.587, 0.114));
	scene = mix(vec3(lum), scene, 0.25);
	// 左側放清單與標題，壓得更暗；右側保留一點場景。
	float dim = mix(0.95, 0.87, smoothstep(0.15, 1.0, SCREEN_UV.x));
	COLOR = vec4(mix(scene, tint, dim), 1.0);
}
"""
	return _shader
