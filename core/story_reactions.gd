class_name StoryReactions
extends RefCounted
## 依死亡次數變化的劇情（伏筆 F19，見 design/04-story/FORESHADOWING.md）的資料規則，純靜態、不依賴全域單例。
## 劇本資料有三種寫法，都只影響措辭，不影響流程與難度：
##   場景的 variants：[{ "min_deaths": N, "lines": [...] }]，累計死亡達到 N 次時改用這組台詞（取達到的最高一組）。
##   章節的 death_notes：[{ "min_deaths": N, "text": "..." }]，死亡畫面多一行小字（取達到的最高一則）。
##   章節的 respawn_scenes：[{ "scene": id, "min_deaths": N, "max_deaths": M（可選）, "repeat": bool }]，死亡重生後（在復原點）播出的通訊。
##   章節的 death_scenes：死亡「之後、重生之前」要播的特殊過場（第一次死亡的診間）。依資料順序取第一個符合的，所以特殊場景排在前面：
##     { "scene": id, "min_deaths": N（預設 1）, "cause": 死因（可選）, "unless_flag": 旗標（已設就不播）, "requires_flag": 旗標（沒設就不播）,
##       "free": true（不扣復原費）, "register_checkpoint": true（播完在最近的電話亭登記復原點） }
##     過場完成才會寫入它自己的 set_flags，所以中途退出或讀檔會從頭再播，不會跳過解釋。
## 台詞裡的 {death_time} 會換成剛剛死亡的世界時間；台詞的 delay 是顯示前先沉默的秒數。
## 壞掉的資料一律略過、退回正常台詞；validate_* 會指出是哪個場景、第幾個。

const DEATH_TIME_TOKEN := "{death_time}"
const MAX_LINE_DELAY := 30.0


## 門檻次數；缺少或不是數字、小於 1 時回傳 0（視為無效）。
static func threshold(entry: Variant) -> int:
	if typeof(entry) != TYPE_DICTIONARY:
		return 0
	var value: Variant = (entry as Dictionary).get("min_deaths", 0)
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return 0
	return maxi(0, int(value))


## 這個場景在累計死亡 deaths 次時要改用的台詞；沒有適用的變化（或資料壞掉）回傳空陣列。
static func variant_lines(scene: Variant, deaths: int) -> Array:
	var best_threshold := 0
	var best: Array = []
	for entry in variants_of(scene):
		var needed := threshold(entry)
		if needed >= 1 and needed <= deaths and needed > best_threshold:
			best_threshold = needed
			best = (entry as Dictionary)["lines"]
	return best


## 結構正確的變化（門檻有效、lines 是非空陣列）。壞的略過。
static func variants_of(scene: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if typeof(scene) != TYPE_DICTIONARY:
		return result
	var raw: Variant = (scene as Dictionary).get("variants", [])
	if typeof(raw) != TYPE_ARRAY:
		return result
	for entry: Variant in raw:
		if threshold(entry) < 1:
			continue
		var lines: Variant = (entry as Dictionary).get("lines", [])
		if typeof(lines) == TYPE_ARRAY and not (lines as Array).is_empty():
			result.append(entry)
	return result


## 死亡畫面的小字：達到次數的最高一則；沒有回傳空字串。
static func pick_note(notes: Array, deaths: int) -> String:
	var best_threshold := 0
	var best := ""
	for entry: Variant in notes:
		var needed := threshold(entry)
		var text := str((entry as Dictionary).get("text", "")) if typeof(entry) == TYPE_DICTIONARY else ""
		if needed >= 1 and needed <= deaths and needed > best_threshold and not text.is_empty():
			best_threshold = needed
			best = text
	return best


## 這個次數下要播的重生通訊（依資料順序）。max_deaths（可選）讓前幾次與之後幾次用不同的句子。
static func eligible_respawns(entries: Array, deaths: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Variant in entries:
		if typeof(entry) == TYPE_DICTIONARY and threshold(entry) >= 1 and threshold(entry) <= deaths \
				and deaths <= max_deaths(entry) and not str((entry as Dictionary).get("scene", "")).is_empty():
			result.append(entry)
	return result


## 上限次數；沒寫或不是數字視為沒有上限。
static func max_deaths(entry: Variant) -> int:
	if typeof(entry) != TYPE_DICTIONARY:
		return 0
	var value: Variant = (entry as Dictionary).get("max_deaths", null)
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return 0x7fffffff
	return int(value)


## 死亡後、重生前要播的特殊過場：依資料順序取第一個符合的（次數、死因、旗標），沒有回傳空字典。
## has_flag：Callable(旗標 StringName) -> bool。壞掉的項目略過。
static func pick_death_scene(entries: Variant, deaths: int, cause: StringName, has_flag: Callable) -> Dictionary:
	if typeof(entries) != TYPE_ARRAY:
		return {}
	for entry: Variant in entries:
		if typeof(entry) != TYPE_DICTIONARY or str((entry as Dictionary).get("scene", "")).is_empty():
			continue
		var data := entry as Dictionary
		if deaths < maxi(1, threshold(entry)) or deaths > max_deaths(entry):
			continue
		var wanted_cause := str(data.get("cause", ""))
		if not wanted_cause.is_empty() and wanted_cause != String(cause):
			continue
		var blocked := str(data.get("unless_flag", ""))
		if not blocked.is_empty() and bool(has_flag.call(StringName(blocked))):
			continue
		var needed := str(data.get("requires_flag", ""))
		if not needed.is_empty() and not bool(has_flag.call(StringName(needed))):
			continue
		return data
	return {}


## 台詞顯示前的沉默秒數（不是正數或不是數字當作沒有，最多 MAX_LINE_DELAY）。
static func line_delay(entry: Variant) -> float:
	if typeof(entry) != TYPE_DICTIONARY:
		return 0.0
	var value: Variant = (entry as Dictionary).get("delay", 0.0)
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return 0.0
	return clampf(float(value), 0.0, MAX_LINE_DELAY)


static func fill_placeholders(text: String, death_clock: String) -> String:
	return text.replace(DEATH_TIME_TOKEN, death_clock)


# ---------------------------------------------------------------------------
# 資料檢查
# ---------------------------------------------------------------------------

## 檢查一個場景的 variants：結構、門檻、句數上限、講者與文字。limit 是該場景類型的句數上限。
static func validate_variants(scene_id: String, scene: Dictionary, limit: int, speakers: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	if not scene.has("variants"):
		return problems
	var raw: Variant = scene["variants"]
	if typeof(raw) != TYPE_ARRAY:
		problems.append("場景 %s 的 variants 必須是陣列" % scene_id)
		return problems
	var index := 0
	for entry: Variant in raw:
		index += 1
		var where := "場景 %s 的第 %d 個死亡變化" % [scene_id, index]
		if typeof(entry) != TYPE_DICTIONARY:
			problems.append("%s 不是物件" % where)
			continue
		if threshold(entry) < 1:
			problems.append("%s 的 min_deaths 必須是 1 以上的數字" % where)
		var lines: Variant = (entry as Dictionary).get("lines", [])
		if typeof(lines) != TYPE_ARRAY or (lines as Array).is_empty():
			problems.append("%s 沒有任何台詞" % where)
			continue
		if (lines as Array).size() > limit:
			problems.append("%s 有 %d 句，上限 %d 句" % [where, (lines as Array).size(), limit])
		for line: Variant in lines:
			if typeof(line) != TYPE_DICTIONARY:
				problems.append("%s 有一句不是物件" % where)
				continue
			if not speakers.has(str((line as Dictionary).get("speaker", ""))):
				problems.append("%s 的講者「%s」未定義" % [where, (line as Dictionary).get("speaker", "")])
			if str((line as Dictionary).get("text", "")).is_empty():
				problems.append("%s 有一句沒有文字" % where)
	return problems


static func validate_notes(chapter_id: String, notes: Variant) -> PackedStringArray:
	var problems := PackedStringArray()
	if typeof(notes) != TYPE_ARRAY:
		problems.append("章節 %s 的 death_notes 必須是陣列" % chapter_id)
		return problems
	var index := 0
	for entry: Variant in notes:
		index += 1
		if threshold(entry) < 1 or typeof(entry) != TYPE_DICTIONARY or str((entry as Dictionary).get("text", "")).is_empty():
			problems.append("章節 %s 的第 %d 則死亡畫面小字需要 min_deaths（1 以上）與 text" % [chapter_id, index])
	return problems


## has_scene：回傳場景 id 是否存在。
static func validate_respawns(chapter_id: String, entries: Variant, has_scene: Callable) -> PackedStringArray:
	var problems := PackedStringArray()
	if typeof(entries) != TYPE_ARRAY:
		problems.append("章節 %s 的 respawn_scenes 必須是陣列" % chapter_id)
		return problems
	var index := 0
	for entry: Variant in entries:
		index += 1
		var where := "章節 %s 的第 %d 個重生通訊" % [chapter_id, index]
		if typeof(entry) != TYPE_DICTIONARY:
			problems.append("%s 不是物件" % where)
			continue
		if threshold(entry) < 1:
			problems.append("%s 的 min_deaths 必須是 1 以上的數字" % where)
		var scene_id := str((entry as Dictionary).get("scene", ""))
		if scene_id.is_empty() or not bool(has_scene.call(StringName(scene_id))):
			problems.append("%s 的場景「%s」不存在" % [where, scene_id])
	return problems


## 檢查 death_scenes：結構、場景存在；unless_flag／requires_flag 的旗標必須有某個場景會寫入（否則永遠不會變），
## 而且特殊場景自己的 set_flags 必須包含它的 unless_flag（否則每次死亡都會再播一次）。
## scene_flags：Callable(場景 id) -> 該場景 set_flags 的 Array。
static func validate_death_scenes(chapter_id: String, entries: Variant, has_scene: Callable, scene_flags: Callable) -> PackedStringArray:
	var problems := PackedStringArray()
	if typeof(entries) != TYPE_ARRAY:
		problems.append("章節 %s 的 death_scenes 必須是陣列" % chapter_id)
		return problems
	var index := 0
	for entry: Variant in entries:
		index += 1
		var where := "章節 %s 的第 %d 個死亡場景" % [chapter_id, index]
		if typeof(entry) != TYPE_DICTIONARY:
			problems.append("%s 不是物件" % where)
			continue
		var data := entry as Dictionary
		var scene_id := str(data.get("scene", ""))
		if scene_id.is_empty() or not bool(has_scene.call(StringName(scene_id))):
			problems.append("%s 的場景「%s」不存在" % [where, scene_id])
			continue
		var blocked := str(data.get("unless_flag", ""))
		if not blocked.is_empty() and not (scene_flags.call(StringName(scene_id)) as Array).has(blocked):
			problems.append("%s（%s）的 unless_flag「%s」沒有被這個場景自己的 set_flags 寫入，每次死亡都會再播一次" % [where, scene_id, blocked])
		if blocked.is_empty() and not bool(data.get("repeat", false)):
			problems.append("%s（%s）沒有 unless_flag 也沒有 repeat：每次死亡都會播，請明確寫 repeat 或加旗標" % [where, scene_id])
	return problems
