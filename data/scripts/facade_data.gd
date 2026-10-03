class_name FacadeData
extends Resource
## 建築立面：以「模組」組成一棟樓，每個模組寬 4 格（64 邏輯像素）。
##   ground：一樓（店面、鐵捲門、入口），高 GROUND_HEIGHT
##   body：標準樓層，往上重複，高 BODY_HEIGHT
##   cap：女兒牆／屋簷，高 CAP_HEIGHT
## 每個欄位可放多個變化，依位置固定挑選。每張貼圖可附 `_glow.png`（窗光、霓虹，自發光）與 `_n.png`（法線）。

const MODULE_WIDTH := 64.0
const GROUND_HEIGHT := 40.0
const BODY_HEIGHT := 32.0
const CAP_HEIGHT := 8.0

@export var id: StringName = &""
@export var display_name: String = ""
@export_file("*.png") var ground: PackedStringArray = PackedStringArray()
@export_file("*.png") var body: PackedStringArray = PackedStringArray()
@export_file("*.png") var cap: PackedStringArray = PackedStringArray()


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("立面缺少 id")
	if ground.is_empty() or body.is_empty() or cap.is_empty():
		problems.append("立面 %s 的 ground／body／cap 都至少要有一張" % id)
	for group in [ground, body, cap]:
		for path in group:
			if not ResourceLoader.exists(path):
				problems.append("立面 %s 的貼圖不存在：%s" % [id, path])
	return problems


static func glow_path(path: String) -> String:
	return path.get_basename() + "_glow." + path.get_extension()


static func pick(paths: PackedStringArray, key: int) -> String:
	return paths[absi(key) % paths.size()] if not paths.is_empty() else ""
