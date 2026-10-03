class_name FeelRecord
extends RefCounted
## 事件錄放（NE-151）：錄下一段戰鬥裡的回饋、聲音與材質事件（含位置與方向），之後可以用不同參數重複播放比較（調參用）；
## 另可錄放輸入（每個物理步驟哪些動作被按著，回歸用）。亂數固定種子，相同種子播出來的亂數序列一致；
## 錄檔是 JSON，可匯出到資料夾；煙霧測試載入錄檔重播並檢查預算（data/feel/budgets.json），能偵測超標。

const BUDGETS_PATH := "res://data/feel/budgets.json"
const INPUT_ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"jump", &"shoot", &"melee", &"dash", &"block"]

## 目前正在錄的錄檔（沒有錄就是 null）；Feel、Sfx、HitFeedback 在播放時呼叫 capture。
static var active: FeelRecord = null

var seed_value := 12345
var events: Array[Dictionary] = []
var inputs: Array[Dictionary] = []
var _start_msec := 0
var _input_frame := 0


func start() -> void:
	events.clear()
	inputs.clear()
	_start_msec = Time.get_ticks_msec()
	_input_frame = 0
	active = self


func stop() -> void:
	if active == self:
		active = null


## 播放時的記錄入口：kind 是 feel、sound、material；payload 只放重播需要的資料（位置、方向、旗標）。
static func capture(kind: String, id: String, payload: Dictionary = {}) -> void:
	if active == null:
		return
	var entry := {"t": snappedf(float(Time.get_ticks_msec() - active._start_msec) * 0.001, 0.001), "kind": kind, "id": id}
	for key: String in payload.keys():
		entry[key] = payload[key]
	active.events.append(entry)


## 錄輸入：每個物理步驟呼叫一次，記下被按著的動作。
func capture_inputs() -> void:
	var pressed: Array = []
	for action in INPUT_ACTIONS:
		if Input.is_action_pressed(action):
			pressed.append(String(action))
	inputs.append({"f": _input_frame, "a": pressed})
	_input_frame += 1


func to_dict() -> Dictionary:
	return {"version": 1, "seed": seed_value, "events": events, "inputs": inputs}


static func from_dict(data: Dictionary) -> FeelRecord:
	var record := FeelRecord.new()
	record.seed_value = int(data.get("seed", 12345))
	for entry: Variant in data.get("events", []):
		if typeof(entry) == TYPE_DICTIONARY and (entry as Dictionary).has("kind") and (entry as Dictionary).has("id"):
			record.events.append(entry)
	for entry: Variant in data.get("inputs", []):
		if typeof(entry) == TYPE_DICTIONARY:
			record.inputs.append(entry)
	return record


## 匯出到資料夾；回傳路徑（失敗回傳空字串並記錄）。
func save(dir: String, label := "record") -> String:
	DirAccess.make_dir_recursive_absolute(dir)
	var path := "%s/%s.json" % [dir, label]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[FeelRecord] 無法寫入錄檔：%s（錯誤 %d）" % [path, FileAccess.get_open_error()])
		return ""
	file.store_string(JSON.stringify(to_dict(), " "))
	file.close()
	return path


static func load_file(path: String) -> FeelRecord:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[FeelRecord] 讀不出錄檔：%s" % path)
		return null
	return from_dict(parsed as Dictionary)


# ---------------------------------------------------------------------------
# 重播與預算檢查
# ---------------------------------------------------------------------------

## 重播事件：固定亂數種子，依錄下的時間間隔套用「目前」的參數播放；回傳峰值統計。
## speed 是時間倍率（煙霧測試用大於 1 加速）。
func replay_events(host: Node, speed := 1.0) -> Dictionary:
	var stats := {"particles": 0, "voices": 0, "flash_per_second": 0, "frozen": 0, "events": 0}
	# 固定亂數種子與粒子預算的起點，同一份錄檔從同樣的狀態開始播。rng_probe 是種子起點的第一個亂數（驗證用）。
	seed(seed_value)
	stats["rng_probe"] = randi()
	seed(seed_value)
	HitFeedback.reset_budget()
	FlashGuard.reset()
	var previous := active
	active = null  # 重播時不再錄
	var last_t := 0.0
	for entry in events:
		var wait := (float(entry["t"]) - last_t) / maxf(0.01, speed)
		last_t = float(entry["t"])
		if wait > 0.0:
			await host.get_tree().create_timer(wait, true, false, true).timeout
		_apply(entry)
		stats["events"] += 1
		stats["particles"] = maxi(int(stats["particles"]), Fx.particle_count())
		stats["voices"] = maxi(int(stats["voices"]), Sfx.voices_playing())
		stats["flash_per_second"] = maxi(int(stats["flash_per_second"]), FlashGuard.rate())
		stats["frozen"] = maxi(int(stats["frozen"]), Fx.frozen_count())
	active = previous
	return stats


func _apply(entry: Dictionary) -> void:
	match str(entry["kind"]):
		"feel":
			var ctx: Dictionary = {}
			if entry.has("dir"):
				ctx["dir"] = Vector2(float(entry["dir"][0]), float(entry["dir"][1]))
			if entry.has("origin"):
				ctx["origin"] = Vector2(float(entry["origin"][0]), float(entry["origin"][1]))
			Feel.play(StringName(str(entry["id"])), ctx)
		"sound":
			Sfx.play_event(StringName(str(entry["id"])))
		"material":
			var pos := Vector2(float(entry.get("x", 0.0)), float(entry.get("y", 0.0)))
			HitFeedback.play(StringName(str(entry["id"])), pos, Vector2.UP, Palette.CYAN, {"weak": bool(entry.get("weak", false)), "ricochet": bool(entry.get("ricochet", false))})


## 預算：回傳超標訊息清單（空 = 都在預算內）。stats 來自 replay_events，另外靜態分析錄檔本身的事件密度。
func check_budgets(stats: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	var json: JSON = load(BUDGETS_PATH) as JSON if ResourceLoader.exists(BUDGETS_PATH) else null
	if json == null or typeof(json.data) != TYPE_DICTIONARY:
		return PackedStringArray(["無法讀取預算：%s" % BUDGETS_PATH])
	var budget: Dictionary = (json.data as Dictionary).get("budgets", {})
	for key in ["particles", "voices", "flash_per_second", "frozen"]:
		if int(stats.get(key, 0)) > int(budget.get(key, 1 << 30)):
			problems.append("%s 超標：%d（預算 %d）" % [key, int(stats[key]), int(budget[key])])
	# 事件密度：任何一秒內的頓幀、震動與全螢幕閃光事件數。
	var per_second := {"hitstop": [], "shake": [], "screen": []}
	for entry in events:
		if str(entry["kind"]) != "feel":
			continue
		var def := Feel.event_def(StringName(str(entry["id"])))
		for key: String in per_second.keys():
			if (key == "hitstop" and (def.has("hitstop") or def.has("freeze"))) or (key == "shake" and def.has("shake")) or (key == "screen" and def.has("screen")):
				(per_second[key] as Array).append(float(entry["t"]))
	var limits := {"hitstop": int(budget.get("hitstops_per_second", 1 << 30)), "shake": int(budget.get("shakes_per_second", 1 << 30)), "screen": int(budget.get("screen_effects_per_second", 1 << 30))}
	for key: String in per_second.keys():
		var times: Array = per_second[key]
		for i in times.size():
			var count := 0
			for j in range(i, times.size()):
				if float(times[j]) - float(times[i]) < 1.0:
					count += 1
			if count > int(limits[key]):
				problems.append("%s 事件密度超標：%.2f 秒起的一秒內有 %d 次（預算 %d）" % [key, float(times[i]), count, int(limits[key])])
				break
	return problems


## 輸入回放：依錄下的步驟按住／放開動作（每個物理步驟呼叫一次，傳入目前步驟號）。
func apply_inputs(frame: int) -> void:
	if frame >= inputs.size():
		for action in INPUT_ACTIONS:
			Input.action_release(action)
		return
	var pressed: Array = (inputs[frame] as Dictionary).get("a", [])
	for action in INPUT_ACTIONS:
		if pressed.has(String(action)):
			Input.action_press(action)
		else:
			Input.action_release(action)
