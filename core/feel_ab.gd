class_name FeelAB
extends RefCounted
## 實驗室的 A／B 比較與盲測（NE-150）：兩個槽各存一份「目前的回饋參數＋預設組合」，一鍵切換立即生效；
## 依序重播同一個事件（A 後 B）；盲測十次：每輪隨機決定先播哪一組，玩家選比較喜歡的是第幾個，最後統計並寫進使用者資料夾。

const SLOTS: PackedStringArray = ["A", "B"]
const BLIND_ROUNDS := 10
const OUTPUT_DIR := "user://feel_lab"

var slots: Dictionary = {}
var active := ""
## 盲測狀態：每輪的 [先播的槽, 玩家選了第幾個（0 = 還沒選）]。
var blind_rounds: Array = []
var blind_event: StringName = &""
var _rng := RandomNumberGenerator.new()


## 把目前記憶體中的回饋參數與預設組合存進槽。
func save_slot(slot: String) -> bool:
	if not SLOTS.has(slot):
		push_error("[FeelAB] 沒有這個槽：%s（只有 A、B）" % slot)
		return false
	slots[slot] = {"events": Feel.all_events().duplicate(true), "preset": String(Feel.preset)}
	active = slot
	return true


func has_slot(slot: String) -> bool:
	return slots.has(slot)


## 一鍵切到某個槽：把槽裡的參數套回 Feel，立即生效。
func activate(slot: String) -> bool:
	if not slots.has(slot):
		push_error("[FeelAB] 槽 %s 還沒有存過參數" % slot)
		return false
	var saved: Dictionary = slots[slot]
	var events := Feel.all_events()
	events.clear()
	for key: String in (saved["events"] as Dictionary).keys():
		events[key] = (saved["events"] as Dictionary)[key].duplicate(true)
	Feel.set_preset(StringName(saved["preset"]))
	active = slot
	return true


func toggle() -> String:
	var next := "B" if active == "A" else "A"
	if activate(next):
		return next
	return active


## 依序重播同一個事件：A 一次、間隔、B 一次；播完回到原本的槽。
func replay_sequence(host: Node, event_id: StringName, play: Callable, gap := 0.6) -> void:
	var original := active
	for slot in SLOTS:
		if not has_slot(slot):
			continue
		activate(slot)
		play.call(event_id)
		await host.get_tree().create_timer(gap, true, false, true).timeout
	if original != "" and has_slot(original):
		activate(original)


# ---------------------------------------------------------------------------
# 盲測
# ---------------------------------------------------------------------------

func start_blind(event_id: StringName, seed_value := 0) -> bool:
	if not has_slot("A") or not has_slot("B"):
		push_error("[FeelAB] 盲測需要 A、B 兩個槽都存過參數")
		return false
	_rng.seed = seed_value if seed_value != 0 else Time.get_ticks_usec()
	blind_event = event_id
	blind_rounds.clear()
	for i in BLIND_ROUNDS:
		blind_rounds.append(["A" if _rng.randf() < 0.5 else "B", 0])
	return true


func round_count() -> int:
	return blind_rounds.size()


func pending_round() -> int:
	for i in blind_rounds.size():
		if int((blind_rounds[i] as Array)[1]) == 0:
			return i
	return -1


## 播放某一輪的兩個選項：先播 first，再播另一個（玩家不知道哪個是 A、哪個是 B）。
func play_round(index: int, host: Node, play: Callable, gap := 0.8) -> void:
	var first: String = (blind_rounds[index] as Array)[0]
	var second := "B" if first == "A" else "A"
	for slot in [first, second]:
		activate(slot)
		play.call(blind_event)
		await host.get_tree().create_timer(gap, true, false, true).timeout


## 玩家選了第幾個（1 或 2）。
func answer(index: int, choice: int) -> bool:
	if index < 0 or index >= blind_rounds.size() or choice not in [1, 2]:
		return false
	(blind_rounds[index] as Array)[1] = choice
	return true


## 統計：A、B 各被選了幾次。尚未回答的不算。
func tally() -> Dictionary:
	var result := {"A": 0, "B": 0, "answered": 0}
	for entry: Array in blind_rounds:
		var choice := int(entry[1])
		if choice == 0:
			continue
		var first: String = entry[0]
		var second := "B" if first == "A" else "A"
		result[first if choice == 1 else second] += 1
		result["answered"] += 1
	return result


## 結果寫進使用者資料夾（user://feel_lab/blind_時間.json），回傳檔案路徑；沒有全部回答完時不寫。
func save_results(dir := OUTPUT_DIR) -> String:
	if pending_round() != -1:
		push_error("[FeelAB] 盲測還沒做完，不寫入結果")
		return ""
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := "%s/blind_%s.json" % [dir, stamp]
	var payload := {"event": String(blind_event), "tally": tally(), "rounds": blind_rounds, "presets": {"A": (slots["A"] as Dictionary)["preset"], "B": (slots["B"] as Dictionary)["preset"]}}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[FeelAB] 無法寫入盲測結果：%s（錯誤 %d）" % [path, FileAccess.get_open_error()])
		return ""
	file.store_string(JSON.stringify(payload, " "))
	file.close()
	return path


## 存對照截圖到使用者資料夾；回傳路徑（沒有畫面時回傳空字串）。
static func save_screenshot(viewport: Viewport, label: String, dir := OUTPUT_DIR) -> String:
	if DisplayServer.get_name() == "headless":
		return ""  # 無頭環境沒有畫面
	var image := viewport.get_texture().get_image() if viewport != null and viewport.get_texture() != null else null
	if image == null or image.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(dir)
	var path := "%s/ab_%s_%d.png" % [dir, label, Time.get_ticks_msec()]
	return path if image.save_png(path) == OK else ""
