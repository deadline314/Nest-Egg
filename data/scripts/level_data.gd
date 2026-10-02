class_name LevelData
extends Resource
## 關卡資料：中繼資訊與字元對照表放在 .tres（可在編輯器中拖拉資源），
## 地圖本體放在 JSON（每一列一個字串，編輯器存檔不會把排版打亂）。
##
## 固定字元：
##   #  實心地形      =  單向平台（↓+跳 可落下）  ^  尖刺
##   |  雷射柵欄      P  玩家起點                  C  檢查點
##   H  回復道具      B  頭目戰場左界（進入後鎖鏡頭）
##   *  場景燈        1~9  教學看板（文字取自 hints[n-1]）
## 裝飾字元由 decor 對應（例如 $ 直式霓虹招牌、% 橫式招牌、@ 全像看板、~ 排氣孔）。
##   .  或空白為空氣
## 其他字元由 legend 對應到 EnemyData / WeaponData / VehicleData。
## 實體字元代表「腳底所在的格子」。

@export var id: StringName = &"level"
@export var display_name: String = ""
@export var tile_size: int = 16
## 每一段地圖的列數，所有分段必須一致。
@export var height: int = 23
## 單一字元 -> Resource。
@export var legend: Dictionary[String, Resource] = {}
## 單一字元 -> 裝飾種類：neon_sign、neon_sign_h、billboard、steam_vent。
@export var decor: Dictionary[String, String] = {}
## 霓虹招牌文字（依位置固定挑選）。
@export var sign_texts: PackedStringArray = PackedStringArray(["拉麵", "薬", "酒場", "義体", "電腦"])
## 全像看板廣告，格式「標題|副標」。
@export var billboard_ads: PackedStringArray = PackedStringArray(["天穹集團|讓天空屬於每個人"])
@export var rain := true
@export var fog_color := Color(0.55, 0.45, 0.85, 1.0)
## 教學看板文字，地圖字元 "1" 對應 hints[0]。請寫重點，一句話。
## 提到按鍵時請用 {動作} 佔位符（例如 {jump}），玩家改鍵後提示會自動更新。
@export var hints: PackedStringArray = PackedStringArray()
## 地圖 JSON 路徑，格式：{ "segments": [ ["列0", "列1", ...], [...] ] }，分段由左至右串接。
@export_file("*.json") var layout_path: String = ""


## 讀取地圖分段。失敗時回傳空陣列並輸出錯誤，不會讓遊戲崩潰。
func load_segments() -> Array[PackedStringArray]:
	var result: Array[PackedStringArray] = []
	if layout_path.is_empty() or not ResourceLoader.exists(layout_path):
		push_error("[LevelData] %s 找不到地圖檔：%s" % [id, layout_path])
		return result
	var json := load(layout_path) as JSON
	if json == null or typeof(json.data) != TYPE_DICTIONARY:
		push_error("[LevelData] %s 地圖檔格式錯誤：%s" % [id, layout_path])
		return result
	var raw_segments: Variant = (json.data as Dictionary).get("segments", [])
	if typeof(raw_segments) != TYPE_ARRAY:
		push_error("[LevelData] %s 的 segments 必須是陣列" % id)
		return result
	for raw in raw_segments:
		if typeof(raw) != TYPE_ARRAY:
			push_warning("[LevelData] %s 有一個分段不是陣列，已略過" % id)
			continue
		var rows := PackedStringArray()
		for row in raw:
			rows.append(str(row))
		result.append(rows)
	return result
