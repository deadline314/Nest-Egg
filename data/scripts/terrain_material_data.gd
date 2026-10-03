class_name TerrainMaterialData
extends Resource
## 地形材質：本體（可雙向平鋪）、頂面（沿頂端的橫條）、側邊（沿左右邊緣的直條）三張貼圖。
## 貼圖解析度由 texture_scale 決定（每個邏輯像素對應幾個貼圖像素，預設 4）：
## 一格 16 像素的地形，預設本體貼圖是 64 像素；免費素材加工的高解析版本用 8（見 design/11-free-assets）。
## 每張貼圖可附同名的 `_n.png`（法線）；缺圖時顯示替代圖並記錄路徑。

const TEXTURE_SCALE := 4

@export var id: StringName = &""
@export var display_name: String = ""
## 貼圖像素 ÷ 邏輯像素。本體貼圖的邊長 = texture_scale × 每次重複涵蓋的邏輯像素。
@export_range(1, 16) var texture_scale: int = TEXTURE_SCALE
@export_file("*.png") var body: String = ""
@export_file("*.png") var top: String = ""
@export_file("*.png") var side: String = ""
## 頂面與側邊的厚度（邏輯像素）。
@export var top_height: float = 6.0
@export var side_width: float = 6.0
## 頂端亮邊的顏色（自發光細線）；alpha 為 0 時沿用預設亮邊。
@export var edge_color: Color = Color(0, 0, 0, 0)


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("地形材質缺少 id")
	for entry in [["本體", body], ["頂面", top], ["側邊", side]]:
		if entry[1].is_empty() or not ResourceLoader.exists(entry[1]):
			problems.append("地形材質 %s 的%s貼圖不存在：%s" % [id, entry[0], entry[1]])
		else:
			var normal := normal_path(entry[1])
			if not ResourceLoader.exists(normal):
				problems.append("地形材質 %s 的%s缺法線貼圖：%s" % [id, entry[0], normal])
	return problems


static func normal_path(path: String) -> String:
	return path.get_basename() + "_n." + path.get_extension()
