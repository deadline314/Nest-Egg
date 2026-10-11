class_name BossPattern
extends RefCounted
## 頭目的打法資料（data/bosses/<頭目 id>.json）：招式、階段、攻擊習慣、鍊子（地盤）與部位何時打開。
## 格式與設計見 design/15-combat-feel/BOSS_FIGHTS.md。讀不到或欄位錯誤時記錄檔案與欄位，退回安全預設（只點射、不拴鍊），不讓遊戲崩潰。

const DIR := "res://data/bosses/%s.json"
## 程式提供的招式種類；新頭目先用資料組合這些，真的需要新動作才加種類（PatternBoss._act_* 對應）。
const KINDS: Array[StringName] = [&"lunge", &"burst", &"bark", &"missiles", &"pounce"]
const BANDS: Array[String] = ["close", "mid", "far", "after_yank"]
const MIN_TELEGRAPH := 0.5
const FALLBACK_MOVE := &"burst"

## 招式 id → {kind, telegraph, recover, weight, repeat, pose_windup, pose_act, params}
var moves: Dictionary = {}
## 依血量排列：{until, moves, speed, armored, leashed, weapon, hide_parts, enter_toast}
var phases: Array[Dictionary] = []
## 距離帶 → 招式 id 清單；close_range／far_range 為像素。
var habits: Dictionary = {}
var close_range := 48.0
var far_range := 260.0
## 鍊長（像素，從錨點量起）；0 代表沒有鍊子。
var leash_length := 0.0
## 被鍊子扯回後往錨點退幾秒再出招（喘口氣；也拉開與玩家的距離，不會貼著線一直吠）。
var leash_retreat := 0.0
## 部位 id → 何時打開：逗號分隔的條件，任一成立就打開——always、stagger（硬直時）、phase:N（第 N 階段）、move:<招式 id>（該招預兆與出招時）。
var parts_open: Dictionary = {}
## 部位 id → 關著時的樣子：armor（還在畫面上，子彈打到會被擋下彈開）或 hidden（不在畫面上，打不到）。
var parts_closed: Dictionary = {}
## 睡著直到玩家進入這個距離（0＝一出場就醒）。
var wake_range := 0.0
## 擊敗後解開的機關頻道與提示；頻道空白代表結束關卡（boss_defeated）。
var gate_channel: StringName = &""
var unlock_text := ""
## 部位 id → 硬直時是否關閉（例如被扯回時槍臂垂下，不擋住背部）。
var parts_close_in_stagger: Dictionary = {}
## 部位 id → 從第幾階段起不存在（例如槍臂被打壞後藏起來、打不到）；0＝一直都在。
var parts_gone_from: Dictionary = {}
## 每次讀檔的錯誤（測試與開發檢查用）；一般讀檔同時推 push_error，parse(quiet) 只記錄。
var errors: PackedStringArray = []
var _quiet := false

static var _cache: Dictionary = {}


## 讀取並快取某個頭目的打法；同一份資料共用，不在每次生成時重新解析。
static func load_for(id: StringName) -> BossPattern:
	var key := String(id)
	if _cache.has(key):
		return _cache[key]
	var pattern := BossPattern.new()
	pattern._load(DIR % key)
	_cache[key] = pattern
	return pattern


## 清掉快取（測試改資料後重讀用）。
static func clear_cache() -> void:
	_cache.clear()


## 從記憶體中的資料建立（工具與測試用）；quiet 時只記錄錯誤不輸出。
static func parse(source: Dictionary, where := "(memory)", quiet := false) -> BossPattern:
	var pattern := BossPattern.new()
	pattern._quiet = quiet
	pattern._apply(source, where)
	return pattern


func _load(path: String) -> void:
	if not FileAccess.file_exists(path):
		_error(path, "找不到檔案，改用安全預設")
		_apply({}, path)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		_error(path, "不是有效的 JSON 物件，改用安全預設")
		parsed = {}
	_apply(parsed, path)


func _apply(source: Dictionary, where: String) -> void:
	_read_moves(source.get("moves", {}), where)
	_read_phases(source.get("phases", []), where)
	_read_habits(source.get("habits", {}), where)
	var leash: Variant = source.get("leash", {})
	leash_length = maxf(0.0, float((leash as Dictionary).get("length", 0.0))) if leash is Dictionary else 0.0
	leash_retreat = clampf(float((leash as Dictionary).get("retreat", 0.0)), 0.0, 3.0) if leash is Dictionary else 0.0
	var parts: Variant = source.get("parts", {})
	if parts is Dictionary:
		for id: Variant in parts:
			var entry: Variant = parts[id]
			var open := str((entry as Dictionary).get("open", "always")) if entry is Dictionary else "always"
			for token in open.split(",", false):
				var valid := token == "always" or token == "stagger" or (token.begins_with("phase:") and token.trim_prefix("phase:").is_valid_int()) \
						or (token.begins_with("move:") and moves.has(StringName(token.trim_prefix("move:"))))
				if not valid:
					_error(where, "parts.%s.open 的「%s」不是 always、stagger、phase:N 或 move:<已知招式>，改用 always" % [id, token])
					open = "always"
					break
			parts_open[StringName(str(id))] = open
			var closed := str((entry as Dictionary).get("closed", "armor")) if entry is Dictionary else "armor"
			if closed != "armor" and closed != "hidden":
				_error(where, "parts.%s.closed 只能是 armor 或 hidden（目前「%s」），改用 armor" % [id, closed])
				closed = "armor"
			parts_closed[StringName(str(id))] = closed
			parts_close_in_stagger[StringName(str(id))] = entry is Dictionary and bool((entry as Dictionary).get("close_in_stagger", false))
			parts_gone_from[StringName(str(id))] = maxi(0, int((entry as Dictionary).get("gone_from_phase", 0))) if entry is Dictionary else 0
	wake_range = maxf(0.0, float(source.get("wake_range", 0.0)))
	var defeat: Variant = source.get("defeat", {})
	if defeat is Dictionary:
		gate_channel = StringName(str((defeat as Dictionary).get("gate_channel", "")))
		unlock_text = str((defeat as Dictionary).get("unlock_text", ""))


func _read_moves(source: Variant, where: String) -> void:
	if source is Dictionary:
		for id: Variant in source:
			var entry: Variant = source[id]
			if not (entry is Dictionary):
				_error(where, "moves.%s 不是物件，略過" % id)
				continue
			var kind := StringName(str((entry as Dictionary).get("kind", "")))
			if not KINDS.has(kind):
				_error(where, "moves.%s.kind「%s」不是已知的招式種類 %s，略過" % [id, kind, KINDS])
				continue
			var params: Variant = (entry as Dictionary).get("params", {})
			moves[StringName(str(id))] = {
				"kind": kind,
				"telegraph": maxf(MIN_TELEGRAPH, float((entry as Dictionary).get("telegraph", 0.7))),
				"recover": maxf(0.0, float((entry as Dictionary).get("recover", 0.4))),
				"weight": maxf(0.01, float((entry as Dictionary).get("weight", 1.0))),
				"repeat": bool((entry as Dictionary).get("repeat", false)),
				"pose_windup": StringName(str((entry as Dictionary).get("pose_windup", ""))),
				"pose_act": StringName(str((entry as Dictionary).get("pose_act", ""))),
				"params": params if params is Dictionary else {},
			}
	if moves.is_empty():
		_error(where, "沒有可用的招式，改用安全預設（點射）")
		moves[FALLBACK_MOVE] = {"kind": &"burst", "telegraph": 0.7, "recover": 0.4, "weight": 1.0, "repeat": true,
				"pose_windup": &"", "pose_act": &"", "params": {}}


func _read_phases(source: Variant, where: String) -> void:
	if source is Array:
		for i in (source as Array).size():
			var entry: Variant = source[i]
			if not (entry is Dictionary):
				_error(where, "phases[%d] 不是物件，略過" % i)
				continue
			var listed: Array[StringName] = []
			for id: Variant in (entry as Dictionary).get("moves", []):
				if moves.has(StringName(str(id))):
					listed.append(StringName(str(id)))
				else:
					_error(where, "phases[%d].moves 的「%s」不存在，略過" % [i, id])
			var hidden := PackedStringArray()
			for part: Variant in (entry as Dictionary).get("hide_parts", []):
				hidden.append(str(part))
			phases.append({
				"until": clampf(float((entry as Dictionary).get("until", 0.0)), 0.0, 1.0),
				"moves": listed,
				"speed": clampf(float((entry as Dictionary).get("speed", 1.0)), 0.5, 2.0),
				"armored": bool((entry as Dictionary).get("armored", false)),
				"leashed": bool((entry as Dictionary).get("leashed", false)),
				"weapon": (entry as Dictionary).get("weapon", null),
				"hide_parts": hidden,
				"enter_toast": str((entry as Dictionary).get("enter_toast", "")),
			})
	if phases.is_empty():
		phases.append({"until": 0.0, "moves": _all_moves(), "speed": 1.0, "armored": false,
				"leashed": false, "weapon": null, "hide_parts": PackedStringArray(), "enter_toast": ""})
	for i in phases.size():
		if (phases[i]["moves"] as Array).is_empty():
			_error(where, "phases[%d] 沒有可用招式，補上全部招式" % i)
			phases[i]["moves"] = _all_moves()
	phases[phases.size() - 1]["until"] = 0.0


func _read_habits(source: Variant, where: String) -> void:
	var table: Dictionary = source if source is Dictionary else {}
	close_range = maxf(0.0, float(table.get("close_range", close_range)))
	far_range = maxf(close_range, float(table.get("far_range", far_range)))
	for band in BANDS:
		var listed: Array[StringName] = []
		for id: Variant in table.get(band, []):
			if moves.has(StringName(str(id))):
				listed.append(StringName(str(id)))
			else:
				_error(where, "habits.%s 的「%s」不存在，略過" % [band, id])
		habits[band] = listed


func _all_moves() -> Array[StringName]:
	var all: Array[StringName] = []
	for id: StringName in moves:
		all.append(id)
	return all


## 血量比例對應的階段（0 起算）：第一個 until 小於目前比例的階段。
func phase_for(ratio: float) -> int:
	for i in phases.size():
		if ratio > float(phases[i]["until"]):
			return i
	return phases.size() - 1


## 部位在這個階段、這招（預兆或出招中的招式 id，沒有就空白）、是否硬直時應該打開。
func part_open(id: StringName, phase: int, staggered: bool, move: StringName = &"") -> bool:
	if is_part_gone(id, phase):
		return false
	if staggered and bool(parts_close_in_stagger.get(id, false)):
		return false
	for token in str(parts_open.get(id, "always")).split(",", false):
		if token == "always" or (token == "stagger" and staggered):
			return true
		if token.begins_with("phase:") and int(token.trim_prefix("phase:")) == phase + 1:
			return true
		if token.begins_with("move:") and move != &"" and StringName(token.trim_prefix("move:")) == move:
			return true
	return false


## 部位關著時是否還在畫面上（擋下子彈）；false 代表藏起來、打不到。
## 硬直時標 close_in_stagger 的部位（垂下的槍臂）也不擋子彈。
func part_armored_when_closed(id: StringName, phase := 0, staggered := false) -> bool:
	if staggered and bool(parts_close_in_stagger.get(id, false)):
		return false
	return not is_part_gone(id, phase) and str(parts_closed.get(id, "armor")) == "armor"


## 部位在這個階段是否已經不存在（壞掉脫落）。
func is_part_gone(id: StringName, phase: int) -> bool:
	var from := int(parts_gone_from.get(id, 0))
	return from > 0 and phase + 1 >= from


func _error(where: String, message: String) -> void:
	var text := "[BossPattern] %s：%s" % [where, message]
	errors.append(text)
	if not _quiet:
		push_error(text)
