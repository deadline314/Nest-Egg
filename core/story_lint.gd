class_name StoryLint
extends RefCounted
## 劇本品質檢查：把文本風格指南（design/04-story/WRITING.md「自動檢查」）實作成規則，
## 掃描場景台詞、道具文字與章節卡文字。純靜態、不依賴任何全域單例，所以測試與命令列工具都能直接用。
##
## 檢查的最小單位是「文本單元」：{ "id": 場景或道具 id, "lines": [{ "speaker": 講者 id, "text": 文字 }] }。
## 場景內的規則（教學詞、對比句型、標點、單句長度…）逐單元檢查；
## 章節內的規則（空泛大詞合計、抽象名詞密度、凜與芽的句長比較）把同一章的單元加總。
## 講者定義帶 "formal": true（天穹廣播、廣告、監管者…）時，免除破折號與書面連接詞的限制。

enum Level { ERROR, WARNING }

const TEACHING_WORDS: PackedStringArray = ["瞄準線", "格擋", "衝刺", "預兆", "鎖定", "彈幕", "終結", "血量", "擊破", "破防", "冷卻", "關卡", "玩家", "任務目標"]
const WRITTEN_CONNECTIVES: PackedStringArray = ["然而", "因此", "儘管", "由於", "此外", "與此同時"]
const GRAND_WORDS: PackedStringArray = ["彷彿", "宛如", "仿佛", "如同", "命運", "宿命", "救贖", "靈魂", "深淵", "終將", "注定"]
const ABSTRACT_WORDS: PackedStringArray = ["希望", "絕望", "代價", "未來"]
## 每章容許的空泛大詞次數（用在關鍵的一句）。
const GRAND_WORD_BUDGET := 2
const ABSTRACT_WORD_LIMIT := 4
const MAX_DASHES := 1
const MAX_ELLIPSES := 2
const MAX_EXCLAMATIONS := 1
const SENTENCE_WARN_LENGTH := 40
const SENTENCE_ERROR_LENGTH := 56
## 同一講者連續幾句都很長就警告，以及「很長」的門檻。
const LONG_STREAK := 3
const LONG_LINE_LENGTH := 24
## 凜的平均句長要短於芽與監管者的這個比例，否則提醒人工檢視。
const VOICE_RATIO := 0.8
const VOICE_MIN_LINES := 4
const SENTENCE_BREAKS := "。！？!?\n"

static var _contrast_patterns: Array[RegEx] = []
static var _ellipsis: RegEx
static var _dash: RegEx


## 檢查一個文本單元（一個場景或一份道具文字）。
static func check_unit(unit_id: String, lines: Array, speakers: Dictionary) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	var dashes := 0
	var ellipses := 0
	var exclamations := 0
	var streak_speaker := ""
	var streak := 0
	var streak_reported := false
	for index in lines.size():
		var entry: Variant = lines[index]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var speaker_id := str(entry.get("speaker", ""))
		var text := str(entry.get("text", ""))
		var formal := _is_formal(speakers, speaker_id)
		var where := "%s 第 %d 句" % [unit_id, index + 1]
		for word in TEACHING_WORDS:
			if text.contains(word):
				issues.append(_issue(Level.ERROR, "教學詞", where, "對白出現操作用語「%s」：「%s」" % [word, text]))
		if _has_contrast(text):
			issues.append(_issue(Level.ERROR, "對比句型", where, "「不是……，是……」句型：「%s」" % text))
		if not formal:
			dashes += _count_dashes(text)
			for word in WRITTEN_CONNECTIVES:
				if text.contains(word):
					issues.append(_issue(Level.ERROR, "書面連接詞", where, "口語對白不用「%s」：「%s」" % [word, text]))
		ellipses += _count_ellipses(text)
		exclamations += text.count("！") + text.count("!")
		for sentence in split_sentences(text):
			var length := sentence_length(sentence)
			if length > SENTENCE_ERROR_LENGTH:
				issues.append(_issue(Level.ERROR, "單句長度", where, "一句 %d 字，超過 %d 字：「%s」" % [length, SENTENCE_ERROR_LENGTH, sentence]))
			elif length > SENTENCE_WARN_LENGTH:
				issues.append(_issue(Level.WARNING, "單句長度", where, "一句 %d 字，超過 %d 字建議拆開：「%s」" % [length, SENTENCE_WARN_LENGTH, sentence]))
		# 講者長度：同一個講者連續幾句都很長。
		if speaker_id == streak_speaker and text.length() > LONG_LINE_LENGTH:
			streak += 1
		else:
			streak_speaker = speaker_id
			streak = 1 if text.length() > LONG_LINE_LENGTH else 0
			streak_reported = false
		if streak >= LONG_STREAK and not streak_reported:
			streak_reported = true
			issues.append(_issue(Level.WARNING, "講者長度", where, "講者「%s」連續 %d 句都超過 %d 字" % [speaker_id, LONG_STREAK, LONG_LINE_LENGTH]))
	if dashes > MAX_DASHES:
		issues.append(_issue(Level.ERROR, "破折號", unit_id, "「——」出現 %d 次，一個場景最多 %d 次（廣告與公文除外）" % [dashes, MAX_DASHES]))
	if ellipses > MAX_ELLIPSES:
		issues.append(_issue(Level.ERROR, "省略號", unit_id, "「……」出現 %d 次，一個場景最多 %d 次" % [ellipses, MAX_ELLIPSES]))
	if exclamations > MAX_EXCLAMATIONS:
		issues.append(_issue(Level.ERROR, "驚嘆號", unit_id, "驚嘆號出現 %d 個，一個場景最多 %d 個" % [exclamations, MAX_EXCLAMATIONS]))
	return issues


## 檢查一整章：每個單元各自的規則，加上章節合計的規則。units 為 [{ "id", "lines" }]。
static func check_chapter(chapter_id: String, units: Array, speakers: Dictionary) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	var grand := 0
	var grand_places := PackedStringArray()
	var abstract_total := 0
	var length_sum: Dictionary = {}
	var length_count: Dictionary = {}
	for unit: Variant in units:
		var unit_id := str((unit as Dictionary).get("id", "?"))
		var lines: Array = (unit as Dictionary).get("lines", [])
		issues.append_array(check_unit(unit_id, lines, speakers))
		for entry: Variant in lines:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var text := str(entry.get("text", ""))
			for word in GRAND_WORDS:
				var hits := text.count(word)
				if hits > 0:
					grand += hits
					grand_places.append("%s（%s）" % [unit_id, word])
			for word in ABSTRACT_WORDS:
				abstract_total += text.count(word)
			var speaker_id := str(entry.get("speaker", ""))
			length_sum[speaker_id] = int(length_sum.get(speaker_id, 0)) + text.length()
			length_count[speaker_id] = int(length_count.get(speaker_id, 0)) + 1
	if grand > GRAND_WORD_BUDGET:
		issues.append(_issue(Level.ERROR, "空泛大詞", chapter_id, "本章空泛大詞 %d 次，容許 %d 次（只用在關鍵的一句）：%s" % [grand, GRAND_WORD_BUDGET, "、".join(grand_places)]))
	if abstract_total > ABSTRACT_WORD_LIMIT:
		issues.append(_issue(Level.WARNING, "抽象名詞密度", chapter_id, "希望、絕望、代價、未來 合計 %d 次，超過 %d 次" % [abstract_total, ABSTRACT_WORD_LIMIT]))
	issues.append_array(_check_voice_balance(chapter_id, length_sum, length_count))
	return issues


## 凜的平均句長應明顯短於芽與監管者（資料太少時不檢查）。
static func _check_voice_balance(chapter_id: String, sums: Dictionary, counts: Dictionary) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	if int(counts.get("rin", 0)) < VOICE_MIN_LINES:
		return issues
	var rin_average := float(sums["rin"]) / float(counts["rin"])
	for other: String in ["mei", "warden"]:
		if int(counts.get(other, 0)) < VOICE_MIN_LINES:
			continue
		var average := float(sums[other]) / float(counts[other])
		if rin_average > average * VOICE_RATIO:
			issues.append(_issue(Level.WARNING, "講者一致", chapter_id, "凜平均 %.1f 字，應明顯短於「%s」的 %.1f 字（請人工檢視）" % [rin_average, other, average]))
	return issues


## 切成單句（以。！？與換行為界，省略號與逗號不算斷句）。
static func split_sentences(text: String) -> PackedStringArray:
	var result := PackedStringArray()
	var current := ""
	for ch in text:
		if SENTENCE_BREAKS.contains(ch):
			if not current.strip_edges().is_empty():
				result.append(current.strip_edges())
			current = ""
		else:
			current += ch
	if not current.strip_edges().is_empty():
		result.append(current.strip_edges())
	return result


## 句子長度：不計空白。
static func sentence_length(sentence: String) -> int:
	return sentence.replace(" ", "").replace("　", "").length()


static func format(issue: Dictionary) -> String:
	return "[%s／%s] %s：%s" % ["錯誤" if int(issue["level"]) == Level.ERROR else "警告", issue["rule"], issue["where"], issue["message"]]


static func errors_of(issues: Array[Dictionary]) -> Array[Dictionary]:
	return issues.filter(func(issue: Dictionary) -> bool: return int(issue["level"]) == Level.ERROR)


static func warnings_of(issues: Array[Dictionary]) -> Array[Dictionary]:
	return issues.filter(func(issue: Dictionary) -> bool: return int(issue["level"]) == Level.WARNING)


## 找出所有符合某規則的問題（測試用）。
static func with_rule(issues: Array[Dictionary], rule: String) -> Array[Dictionary]:
	return issues.filter(func(issue: Dictionary) -> bool: return issue["rule"] == rule)


static func _issue(level: int, rule: String, where: String, message: String) -> Dictionary:
	return {"level": level, "rule": rule, "where": where, "message": message}


static func _is_formal(speakers: Dictionary, speaker_id: String) -> bool:
	var info: Variant = speakers.get(speaker_id, {})
	return typeof(info) == TYPE_DICTIONARY and bool((info as Dictionary).get("formal", false))


static func _has_contrast(text: String) -> bool:
	if _contrast_patterns.is_empty():
		# 「不是……而是……」「不是……，是……」「這不是……，這是……」（同一句內）。
		for pattern in ["不是[^。！？!?\\n]*而是", "不是[^。！？!?\\n]*[，,、]\\s*(這|那|它|他|她)?是"]:
			var regex := RegEx.new()
			regex.compile(pattern)
			_contrast_patterns.append(regex)
	for regex in _contrast_patterns:
		if regex.search(text) != null:
			return true
	return false


static func _count_ellipses(text: String) -> int:
	if _ellipsis == null:
		_ellipsis = RegEx.new()
		_ellipsis.compile("…+|\\.{3,}")
	return _ellipsis.search_all(text).size()


static func _count_dashes(text: String) -> int:
	if _dash == null:
		_dash = RegEx.new()
		_dash.compile("—+")
	return _dash.search_all(text).size()
