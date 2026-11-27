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
##   &  劇情通訊觸發點（由左至右依序對應 story_triggers）
## 裝飾字元由 decor 對應（例如 $ 直式霓虹招牌、% 橫式招牌、@ 全像看板、~ 排氣孔）。
##   .  或空白為空氣
## 其他字元由 legend 對應到 EnemyData / WeaponData / VehicleData / NpcData（場景人物）等資源。
## 實體字元代表「腳底所在的格子」。

const MAX_CHANNEL_RESULT_FLAGS := 64


@export var id: StringName = &"level"
@export var display_name: String = ""
@export var localized_names: Dictionary[String, String] = {}
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
@export_group("Story")
## 這一關屬於哪一章（data/story/chapter_XX.json 的 chapter.id）：章節標題、結尾卡與預告取自該章。
@export var chapter: StringName = &"chapter_01"
## 通關後接續的下一關（LevelData 的 .tres 路徑）；空白代表這是最後一關，通關後進入結算畫面。
@export_file("*.tres") var next_level: String = ""
## 進入關卡（非從檢查點重生）時播放的過場。
@export var intro_scene: StringName = &""
## 進入頭目戰場時播放的過場（播完才出現頭目）。
@export var boss_scene: StringName = &""
## 僅明確設計的特殊頭目空間封路與鎖鏡頭；一般關卡頭目出場不關住玩家。
@export var lock_boss_arena := false
## 擊敗頭目後播放的過場。
@export var outro_scene: StringName = &""
## 機關頻道被啟動時播放的場景（頻道 -> 場景 id），例如打倒迷你頭目後隔牆升起的通訊；每輪只播一次。
@export var channel_scenes: Dictionary[StringName, StringName] = {}
## 原生成機關完成後，先保存完整本輪再公開結果；需具備已驗證的來源契約。
@export var durable_channel_results := false
## 機關頻道「啟動」時寫入的劇情旗標（頻道 → 旗標），例如打倒看門狗、打開水閘；只在尚未成立時寫入。
@export var channel_done_flags: Dictionary[StringName, StringName] = {}
## 同一完成動作的其他旗標；和主旗標一起保存、一起發布。
@export var channel_done_extra_flags: Dictionary[StringName, PackedStringArray] = {}
## 機關頻道「解除」時寫入的劇情旗標，例如鎖場遭遇結束、路障打開。
@export var channel_cleared_flags: Dictionary[StringName, StringName] = {}
## 同一解除動作的其他旗標；和主旗標一起保存、一起發布。
@export var channel_cleared_extra_flags: Dictionary[StringName, PackedStringArray] = {}
## 可略過的區域（序章）：暫停選單出現略過按鈕，確認後寫入 skip_flags 並從 skip_portal 這個出入口離開。
@export var skip_portal: StringName = &""
@export var skip_flags: PackedStringArray = PackedStringArray()
@export var skip_label: String = ""
@export var skip_note: String = ""
@export var skip_label_i18n: Dictionary[String, String] = {}
@export var skip_note_i18n: Dictionary[String, String] = {}
## 地圖上 & 字元由左至右對應的劇情場景 id。
@export var story_triggers: PackedStringArray = PackedStringArray()
## 本區域剛成立的劇情交易收據可附帶一次回復。讀檔及已存在的收據不再回復。
@export var story_health_rewards: Dictionary[StringName, int] = {}
## 玩家確認才開始的電影入口，與 & 強制事件分開宣告，不改既有觸發語義。
@export var cinematic_entries: Array[CinematicEntryData] = []
@export_group("Area")
## 持久世界（區域組）：殺掉的敵人、撿過的東西、開過的機關與受傷的頭目在區域之間與死亡之後都保留；
## 死亡改為扣信用點而不是回溯成就之前的狀態。關閉＝舊式關卡（死後敵人重生、世界還原到檢查點）。
@export var persistent_world := false
## 返回固定的同章區域重新進場。留空時保存當前區域與玩家位置。
@export_file("*.tres") var safe_resume_level := ""
## 進入區域時是否顯示章節標題卡（只有章節的第一個區域需要）。
@export var show_chapter_card := true
## 穿過出入口進來時，是否在畫面上顯示區域名稱（display_name）。
@export var announce_area := true
## 進場過場播完後自動走出這個出入口（空白＝不自動離開）。
@export var after_intro_portal: StringName = &""
## 進場過場播完後直接結束本章（章末的區域用）。
@export var complete_after_intro := false
## 這個旗標成立時結束本章（章末是人物對話時用：對話的結果寫入旗標後，播章末卡並結算）。空白＝不使用。
@export var complete_on_flag: StringName = &""
## 死亡時扣掉的信用點比例（只在 persistent_world 生效）。
@export_range(0.0, 1.0) var death_credit_penalty := 0.05
## 單次死亡最多扣幾點信用點（0 = 不設上限）：死亡不會把存了很久的錢一次吃光。
@export var death_credit_cap := 0
## 死亡時，受傷的頭目（EnemyData.persists_damage）回復其已損血量的比例。
@export_range(0.0, 1.0) var death_boss_recovery := 0.3
## 同時攻擊的敵人數上限（攻擊令牌）：群組（melee、ranged）-> 上限；沒列出的用 data/combat/attack_tokens.json。前期區域調小。
@export var attack_caps: Dictionary = {}
## A room may author a noncombat avoidance activity with its own checkpoint.
@export var avoidance_encounter: Resource
## Optional local timed path. Only its completed conversation saves a result.
@export var traversal_trial: Resource
@export_group("Environment")
## 環境主題（地形材質、建築立面、道具、背景層）。留空時沿用單一金屬面板與程式繪製立面。
@export var environment: EnvironmentTheme
@export_group("Atmosphere")
@export var rain := true
## 這一區的場景燈可以射暗（NE-399）：打中燈具就熄掉，燈下變暗，沒察覺的敵人只看得到近處。
@export var shootable_lamps := false
## Horizontal span in authored columns where the camera reveals less of the hall.
## The zero vector disables this framing.
@export var restrained_view_columns := Vector2i.ZERO
## 沒有光影區段時使用的霧顏色（有 lighting_zones 時由各區段的光影設定決定）。
@export var fog_color := Color(0.55, 0.45, 0.85, 1.0)
@export_group("Lighting")
## 光影區段，依 start_tile 由小到大排列。沒有區段時整關使用預設（全亮）光影。
@export var lighting_zones: Array[LightingZone] = []
## 光影事件（停電、警報區段…）：玩家進入範圍時暫時覆蓋光影。
@export var lighting_events: Array[LightingEvent] = []
## 頭目戰開始時套用的光影（例如警報），擊敗頭目後淡回。
@export var boss_lighting: LightingProfile
## 教學看板文字，地圖字元 "1" 對應 hints[0]。請寫重點，一句話。
## 提到按鍵時請用 {動作} 佔位符（例如 {jump}），玩家改鍵後提示會自動更新。
@export var hints: PackedStringArray = PackedStringArray()


func avoidance_skin() -> String:
	const Spec := preload("res://data/scripts/avoidance_encounter_data.gd")
	var activity := avoidance_encounter as Spec
	return activity.rig_id if activity != null else ""


func display_name_for(language: String) -> String:
	return StoryLocale.optional_text(localized_names, language, display_name)


## 地圖 JSON 路徑，格式：{ "segments": [ ["列0", "列1", ...], [...] ] }，分段由左至右串接。
@export_file("*.json") var layout_path: String = ""


func story_health_reward(transaction: StringName) -> int:
	var amount: int = story_health_rewards.get(transaction, 0)
	if amount < 0 or amount > 1000:
		push_warning("[LevelData] %s/story_health_rewards/%s: invalid heal amount %s" % [resource_path, transaction, amount])
		return 0
	return amount


## 讀取地圖 JSON 的 props 清單：{ "id": 道具 id, "x": 欄, "y": 底邊所在列, "flip": 是否左右翻轉, "ground": true 時 y 取該欄地表 }。
## 壞掉的項目略過並記錄，不影響其他道具。
func load_props() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if layout_path.is_empty() or not ResourceLoader.exists(layout_path):
		return result
	var json := load(layout_path) as JSON
	if json == null or typeof(json.data) != TYPE_DICTIONARY:
		return result
	var raw: Variant = (json.data as Dictionary).get("props", [])
	if typeof(raw) != TYPE_ARRAY:
		push_warning("[LevelData] %s 的 props 必須是陣列" % id)
		return result
	var index := 0
	for entry: Variant in raw:
		index += 1
		if typeof(entry) != TYPE_DICTIONARY or not (entry as Dictionary).has("id") or not (entry as Dictionary).has("x"):
			push_warning("[LevelData] %s 的第 %d 個道具缺少 id 或 x，已略過" % [id, index])
			continue
		result.append(entry)
	return result


## 讀取地圖 JSON 的 regions 清單：{ "x0", "x1", "y0", "y1"（格，含頭尾）, "material": 材質 id }。
## 這些範圍內的實心格改用指定材質（貨櫃、天花板…），不受區段材質限制。
func load_regions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if layout_path.is_empty() or not ResourceLoader.exists(layout_path):
		return result
	var json := load(layout_path) as JSON
	if json == null or typeof(json.data) != TYPE_DICTIONARY:
		return result
	var raw: Variant = (json.data as Dictionary).get("regions", [])
	if typeof(raw) != TYPE_ARRAY:
		push_warning("[LevelData] %s 的 regions 必須是陣列" % id)
		return result
	for entry: Variant in raw:
		if typeof(entry) == TYPE_DICTIONARY:
			result.append(entry)
	return result


## 地圖 JSON 的頂層欄位（例如 key_light）；沒有地圖或沒有這個欄位時回傳 null。
func load_layout_value(key: String) -> Variant:
	if layout_path.is_empty() or not ResourceLoader.exists(layout_path):
		return null
	var json := load(layout_path) as JSON
	if json == null or typeof(json.data) != TYPE_DICTIONARY:
		return null
	return (json.data as Dictionary).get(key)


## 檢查光影區段的設定，回傳問題清單（空代表沒問題）。
func validate_lighting() -> PackedStringArray:
	var problems := PackedStringArray()
	var last_start := -1
	for zone in lighting_zones:
		if zone == null:
			problems.append("%s 的光影區段清單裡有空項目" % id)
			continue
		for problem in zone.validate():
			problems.append("%s：%s" % [id, problem])
		if zone.start_tile < last_start:
			problems.append("%s 的光影區段沒有依起點由小到大排列（起點 %d）" % [id, zone.start_tile])
		last_start = maxi(last_start, zone.start_tile)
	for event in lighting_events:
		if event == null:
			problems.append("%s 的光影事件清單裡有空項目" % id)
			continue
		for problem in event.validate():
			problems.append("%s：%s" % [id, problem])
	if boss_lighting != null:
		for problem in boss_lighting.validate():
			problems.append("%s：頭目光影：%s" % [id, problem])
	return problems


## 指定欄所在區段的光影設定（不插值，生成場景燈與招牌時用）。沒有區段時回傳 null。
func profile_at_tile(tile: int) -> LightingProfile:
	var result: LightingProfile = null
	for zone in lighting_zones:
		if zone != null and zone.profile != null and zone.start_tile <= tile:
			result = zone.profile
	return result


func load_layout_document() -> JSON:
	if layout_path.is_empty() or not ResourceLoader.exists(layout_path):
		push_error("[LevelData] %s 找不到地圖檔：%s" % [id, layout_path])
		return null
	var document := load(layout_path) as JSON
	if document == null or not document.data is Dictionary:
		push_error("[LevelData] %s 地圖檔格式錯誤：%s" % [id, layout_path])
		return null
	return document


## 讀取地圖分段。共用同一份文件時不必再次讀檔。
func load_segments(document: JSON = null) -> Array[PackedStringArray]:
	var result: Array[PackedStringArray] = []
	if document == null:
		document = load_layout_document()
	if document == null or not document.data is Dictionary:
		return result
	var raw_segments: Variant = (document.data as Dictionary).get("segments", [])
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
