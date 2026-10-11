class_name BossPattern
extends RefCounted
## 頭目的打法資料（data/bosses/<頭目 id>.json）：招式、階段、攻擊習慣、鍊子（地盤）與部位何時打開。
## 格式與設計見 design/15-combat-feel/BOSS_FIGHTS.md。讀不到或欄位錯誤時記錄檔案與欄位，退回安全預設（只點射、不拴鍊），不讓遊戲崩潰。

const DIR := "res://data/bosses/%s.json"
## 程式提供的招式種類；新頭目先用資料組合這些，真的需要新動作才加種類（PatternBoss._act_* 對應）。
## 頭目專屬的動作由子類別實作，資料用 custom_kinds 宣告（見 custom_kinds）。
const KINDS: Array[StringName] = [&"lunge", &"burst", &"bark", &"missiles", &"pounce", &"slam", &"fan", &"rush"]
## 距離帶與兩個情境帶：after_yank（剛被鍊子扯回）、marked（玩家身上的標記到 marked_stacks 層）、pad（玩家帶著標記走向亮著的地墊）。
const BANDS: Array[String] = ["close", "mid", "far", "after_yank", "marked", "pad"]
const DEFAULT_SET := "default"
const MIN_TELEGRAPH := 0.5
const FALLBACK_MOVE := &"burst"

## 資料宣告、由 PatternBoss 子類別實作的招式種類（例如守門人的盾擊）；子類別沒實作時 PatternBoss 會記錄錯誤並略過那招。
var custom_kinds: Array[StringName] = []
## 頭目血條上的名稱；空白時用 EnemyData.display_name（例如守門人的血條是「門禁裝置穩定度」，不是人的生命）。
var bar_name := ""
## 招式 id → {kind, telegraph, recover, weight, repeat, pose_windup, pose_act, params}
var moves: Dictionary = {}
## 依血量排列：{until, moves, speed, armored, leashed, weapon, hide_parts, enter_toast, event, damage_bonus, recover_scale, summon}
## 這是 default 階段組；其他階段組（例如復原後、制伏中）在 phase_sets，由頭目自己的腳本切換。
var phases: Array[Dictionary] = []
## 階段組名稱 → 階段清單（default 就是 phases）。
var phase_sets: Dictionary = {}
## 距離帶 → 招式 id 清單；close_range／far_range 為像素。
var habits: Dictionary = {}
var close_range := 48.0
var far_range := 260.0
## 玩家身上的標記到幾層時改用 marked 帶的招式（攻擊習慣「你疊越多他越貪」）。
var marked_stacks := 3
## 玩家身上的標記到幾層、而且往亮著的地墊走時，改用 pad 帶的招式（搶地墊）。
var pad_stacks := 2
## 標記與地墊的設定（BossMark 解析）；空白代表這個頭目沒有標記機制。
var mark_config: Dictionary = {}
## 頭目自己的腳本用的接點（劇情場景、旗標、機關位置）；框架不解讀，只原樣保留。
var hooks: Dictionary = {}
## 鍊長（像素，從錨點量起）；0 代表沒有鍊子。
var leash_length := 0.0
## 被鍊子扯回後往錨點退幾秒再出招（喘口氣；也拉開與玩家的距離，不會貼著線一直吠）。
var leash_retreat := 0.0
## 部位 id → 何時打開：逗號分隔的條件，任一成立就打開——always、stagger（硬直時）、phase:N（第 N 階段）、move:<招式 id>（該招預兆與出招時）、
## tag:<名稱>（頭目腳本目前掛著這個標籤，例如制伏中）。
var parts_open: Dictionary = {}
## 部位 id → 關著時的樣子：armor（還在畫面上，子彈打到會被擋下彈開）或 hidden（不在畫面上，打不到）。
var parts_closed: Dictionary = {}
## 狀態（yanked、phase_shift、intro…）→ 骨架動作 id；招式自己的預兆／出招動作寫在 moves。
var state_poses: Dictionary = {}
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
	var custom: Variant = source.get("custom_kinds", [])
	if custom is Array:
		for kind: Variant in custom:
			if str(kind).is_empty() or KINDS.has(StringName(str(kind))):
				_error(where, "custom_kinds 的「%s」是空白或和內建種類同名，略過" % kind)
				continue
			custom_kinds.append(StringName(str(kind)))
	else:
		_error(where, "custom_kinds 不是陣列，略過")
	bar_name = str(source.get("bar_name", ""))
	_read_moves(source.get("moves", {}), where)
	phases = _read_phase_list(source.get("phases", []), where, "phases")
	phase_sets[DEFAULT_SET] = phases
	var sets: Variant = source.get("phase_sets", {})
	if sets is Dictionary:
		for name: Variant in sets:
			if str(name) == DEFAULT_SET:
				_error(where, "phase_sets 不能用 default 這個名字（就是 phases），略過")
				continue
			phase_sets[str(name)] = _read_phase_list(sets[name], where, "phase_sets.%s" % name)
	_read_habits(source.get("habits", {}), where)
	var mark: Variant = source.get("mark", {})
	mark_config = mark if mark is Dictionary else {}
	if not (mark is Dictionary):
		_error(where, "mark 不是物件，這個頭目不使用標記")
	var hook_table: Variant = source.get("hooks", {})
	hooks = hook_table if hook_table is Dictionary else {}
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
						or (token.begins_with("move:") and moves.has(StringName(token.trim_prefix("move:")))) \
						or (token.begins_with("tag:") and not token.trim_prefix("tag:").is_empty())
				if not valid:
					_error(where, "parts.%s.open 的「%s」不是 always、stagger、phase:N、move:<已知招式> 或 tag:<名稱>，改用 always" % [id, token])
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
	var poses: Variant = source.get("poses", {})
	if poses is Dictionary:
		for state: Variant in poses:
			state_poses[StringName(str(state))] = StringName(str(poses[state]))
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
			if not KINDS.has(kind) and not custom_kinds.has(kind):
				_error(where, "moves.%s.kind「%s」不是已知的招式種類 %s，也沒有在 custom_kinds 宣告，略過" % [id, kind, KINDS])
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


func _read_phase_list(source: Variant, where: String, label: String) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	if source is Array:
		for i in (source as Array).size():
			var entry: Variant = source[i]
			if not (entry is Dictionary):
				_error(where, "%s[%d] 不是物件，略過" % [label, i])
				continue
			var listed: Array[StringName] = []
			for id: Variant in (entry as Dictionary).get("moves", []):
				if moves.has(StringName(str(id))):
					listed.append(StringName(str(id)))
				else:
					_error(where, "%s[%d].moves 的「%s」不存在，略過" % [label, i, id])
			var hidden := PackedStringArray()
			for part: Variant in (entry as Dictionary).get("hide_parts", []):
				hidden.append(str(part))
			list.append({
				"until": clampf(float((entry as Dictionary).get("until", 0.0)), 0.0, 1.0),
				"moves": listed,
				"speed": clampf(float((entry as Dictionary).get("speed", 1.0)), 0.5, 2.0),
				"armored": bool((entry as Dictionary).get("armored", false)),
				"leashed": bool((entry as Dictionary).get("leashed", false)),
				"weapon": (entry as Dictionary).get("weapon", null),
				"hide_parts": hidden,
				"enter_toast": str((entry as Dictionary).get("enter_toast", "")),
				# 進入這個階段時交給頭目腳本的事件（例如血量門檻的劇情暫停）；空白代表沒有。
				"event": str((entry as Dictionary).get("event", "")),
				# 招式傷害加成（整數，加在招式自己的傷害上）與收招時間倍率（越大硬直越長）。
				"damage_bonus": clampi(int((entry as Dictionary).get("damage_bonus", 0)), 0, 3),
				"recover_scale": clampf(float((entry as Dictionary).get("recover_scale", 1.0)), 0.5, 3.0),
				"summon": _read_summon((entry as Dictionary).get("summon", {}), where, "%s[%d].summon" % [label, i]),
			})
	if list.is_empty():
		list.append({"until": 0.0, "moves": _all_moves(), "speed": 1.0, "armored": false, "leashed": false, "weapon": null,
				"hide_parts": PackedStringArray(), "enter_toast": "", "event": "", "damage_bonus": 0, "recover_scale": 1.0, "summon": {}})
	for i in list.size():
		if (list[i]["moves"] as Array).is_empty():
			_error(where, "%s[%d] 沒有可用招式，補上全部招式" % [label, i])
			list[i]["moves"] = _all_moves()
	list[list.size() - 1]["until"] = 0.0
	return list


## 階段的增援：每 every 秒補一隻 EnemyData.summon，同時最多 max_alive 隻，整場最多 total 隻；spawn_tiles 是出現的欄。
func _read_summon(source: Variant, where: String, label: String) -> Dictionary:
	if not (source is Dictionary) or (source as Dictionary).is_empty():
		return {}
	var tiles := PackedFloat32Array()
	for tile: Variant in (source as Dictionary).get("spawn_tiles", []):
		tiles.append(float(tile))
	if tiles.is_empty():
		_error(where, "%s 沒有 spawn_tiles，這個階段不增援" % label)
		return {}
	return {
		"every": maxf(1.0, float((source as Dictionary).get("every", 8.0))),
		"max_alive": clampi(int((source as Dictionary).get("max_alive", 2)), 1, 4),
		"total": clampi(int((source as Dictionary).get("total", 2)), 1, 12),
		"spawn_tiles": tiles,
	}


func _read_habits(source: Variant, where: String) -> void:
	var table: Dictionary = source if source is Dictionary else {}
	close_range = maxf(0.0, float(table.get("close_range", close_range)))
	far_range = maxf(close_range, float(table.get("far_range", far_range)))
	marked_stacks = maxi(1, int(table.get("marked_stacks", marked_stacks)))
	pad_stacks = maxi(1, int(table.get("pad_stacks", pad_stacks)))
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


## 階段組；不存在時退回 default（並記錄一次）。
func phase_list(set_name := DEFAULT_SET) -> Array[Dictionary]:
	if phase_sets.has(set_name):
		return phase_sets[set_name]
	if set_name != DEFAULT_SET:
		_error("(phase_list)", "沒有階段組「%s」，改用 default" % set_name)
	return phases


## 血量比例對應的階段（0 起算）：第一個 until 小於目前比例的階段。
func phase_for(ratio: float, set_name := DEFAULT_SET) -> int:
	var list := phase_list(set_name)
	for i in list.size():
		if ratio > float(list[i]["until"]):
			return i
	return list.size() - 1


## 部位在這個階段、這招（預兆或出招中的招式 id，沒有就空白）、是否硬直時、頭目掛著的標籤下應該打開。
func part_open(id: StringName, phase: int, staggered: bool, move: StringName = &"", tags := PackedStringArray()) -> bool:
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
		if token.begins_with("tag:") and tags.has(token.trim_prefix("tag:")):
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
