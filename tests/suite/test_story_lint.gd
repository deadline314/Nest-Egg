class_name StoryLintSuite
extends TestSuite
## 劇本品質檢查（NE-49）：檢查器本身（好句通過、壞句被抓到、等級與門檻正確）、
## 所有章節劇本與道具文字通過檢查、整合進 Story.validate()。

const SPEAKERS := {
	"rin": {"name": "凜"},
	"mei": {"name": "芽"},
	"old_k": {"name": "老K"},
	"warden": {"name": "監管者", "formal": true},
	"system": {"name": "天穹廣播", "formal": true},
}


func run() -> void:
	_test_good_lines_pass()
	_test_teaching_words()
	_test_contrast_patterns()
	_test_punctuation_limits()
	_test_written_connectives()
	_test_grand_words()
	_test_sentence_length()
	_test_abstract_nouns_and_voices()
	_test_all_scripts_pass()
	_test_items_pass()
	_test_story_validation_integration()


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

func _say(speaker: String, text: String) -> Dictionary:
	return {"speaker": speaker, "text": text}


func _unit(lines: Array) -> Array[Dictionary]:
	return StoryLint.check_unit("測試", lines, SPEAKERS)


func _rules(issues: Array[Dictionary]) -> PackedStringArray:
	var rules := PackedStringArray()
	for issue in issues:
		rules.append(str(issue["rule"]))
	return rules


func _has_rule(issues: Array[Dictionary], rule: String, level: int) -> bool:
	for issue in StoryLint.with_rule(issues, rule):
		if int(issue["level"]) == level:
			return true
	return false


# ---------------------------------------------------------------------------
# 檢查器本身
# ---------------------------------------------------------------------------

func _test_good_lines_pass() -> void:
	# 風格指南「好」的寫法都必須通過。
	var good: Array = [
		_say("mei", "巷口兩個。你要是被打到我下個月的薪水就沒了。"),
		_say("rin", "貴的比較不會動。"),
		_say("old_k", "四萬三。"),
		_say("rin", "差多少。"),
		_say("old_k", "你自己不會算喔。"),
		_say("rin", "這次不用偷什麼。去接他而已。"),
		_say("warden", "七號小姐，您終於來取回它了。路上辛苦。"),
		_say("mei", "貨櫃那邊有東西在發熱。……我是說比你還熱。"),
		_say("system", "天穹集團提醒您，今日降雨持續。為您準備的傘，已放在每一個轉角。"),
	]
	check(_unit(good).is_empty(), "good lines from the style guide pass: %s" % [_rules(_unit(good))])
	check(_unit([]).is_empty(), "an empty unit passes")
	check(StoryLint.sentence_length("你好，世界") == 5 and StoryLint.split_sentences("一。二！三？四").size() == 4, "sentence splitting counts 。！？ and the tail")
	check(StoryLint.split_sentences("好……真的，可以嗎").size() == 1, "ellipsis and commas do not split a sentence")


func _test_teaching_words() -> void:
	for word in StoryLint.TEACHING_WORDS:
		var issues := _unit([_say("mei", "你看，這個%s不太對。" % word)])
		check(_has_rule(issues, "教學詞", StoryLint.Level.ERROR), "teaching word is an error: %s" % word)
	# 原本劇本裡的壞句子。
	check(_has_rule(_unit([_say("mei", "巷口有兩個天穹保全。紅色瞄準線一亮就閃，或者舉盾擋回去。")]), "教學詞", StoryLint.Level.ERROR), "the old tutorial line is caught")
	check(StoryLint.with_rule(_unit([_say("mei", "盾牌那隻看起來很貴欸。")]), "教學詞").is_empty(), "a normal line has no teaching word")


func _test_contrast_patterns() -> void:
	var bad := [
		"不是偷東西，是去接我弟弟回家。",
		"這不是治療，這是實驗。",
		"他不是壞人，而是被逼的。",
		"不是為了錢而是為了他。",
		"不是他，是我。",
	]
	for text in bad:
		check(_has_rule(_unit([_say("rin", text)]), "對比句型", StoryLint.Level.ERROR), "contrast pattern is an error: %s" % text)
	var fine := ["我不是去偷東西。", "他不是我弟。我們沒有血緣。", "這不是我的，我不要。", "不是每個人都有傘。"]
	for text in fine:
		check(StoryLint.with_rule(_unit([_say("rin", text)]), "對比句型").is_empty(), "a plain negation is fine: %s" % text)


func _test_punctuation_limits() -> void:
	# 破折號：一個場景最多 1 次，廣告與公文（formal 講者）除外。
	check(StoryLint.with_rule(_unit([_say("rin", "等等——")]), "破折號").is_empty(), "one dash is allowed")
	check(_has_rule(_unit([_say("rin", "等等——"), _say("mei", "什麼——")]), "破折號", StoryLint.Level.ERROR), "two dashes in a scene are an error")
	check(StoryLint.with_rule(_unit([_say("system", "請注意——"), _say("system", "請注意——"), _say("system", "請注意——")]), "破折號").is_empty(), "formal speakers are exempt from the dash limit")
	# 省略號：最多 2 次，半形三點也算。
	check(StoryLint.with_rule(_unit([_say("rin", "……"), _say("rin", "嗯……")]), "省略號").is_empty(), "two ellipses are allowed")
	check(_has_rule(_unit([_say("rin", "……"), _say("rin", "嗯……"), _say("mei", "喔……")]), "省略號", StoryLint.Level.ERROR), "three ellipses are an error")
	check(_has_rule(_unit([_say("rin", "……"), _say("rin", "嗯..."), _say("mei", "喔......")]), "省略號", StoryLint.Level.ERROR), "ASCII dots count as ellipses")
	check(StoryLint.with_rule(_unit([_say("rin", "………………")]), "省略號").is_empty(), "one long run of dots is a single ellipsis")
	# 驚嘆號：最多 1 個，全形半形都算。
	check(StoryLint.with_rule(_unit([_say("rin", "快跑！")]), "驚嘆號").is_empty(), "one exclamation mark is allowed")
	check(_has_rule(_unit([_say("rin", "快跑！"), _say("mei", "等等！")]), "驚嘆號", StoryLint.Level.ERROR), "two exclamation marks are an error")
	check(_has_rule(_unit([_say("rin", "快跑!"), _say("mei", "等等！")]), "驚嘆號", StoryLint.Level.ERROR), "half-width marks count too")


func _test_written_connectives() -> void:
	for word in StoryLint.WRITTEN_CONNECTIVES:
		var spoken := _unit([_say("rin", "%s他沒來。" % word)])
		check(_has_rule(spoken, "書面連接詞", StoryLint.Level.ERROR), "written connective is an error in speech: %s" % word)
		var formal := _unit([_say("warden", "%s請隨我來。" % word)])
		check(StoryLint.with_rule(formal, "書面連接詞").is_empty(), "the warden and broadcasts may use it: %s" % word)


func _test_grand_words() -> void:
	var two := [{"id": "a", "lines": [_say("rin", "命運。"), _say("mei", "靈魂。")]}]
	check(StoryLint.with_rule(StoryLint.check_chapter("c", two, SPEAKERS), "空泛大詞").is_empty(), "two grand words per chapter are allowed")
	var three := [{"id": "a", "lines": [_say("rin", "命運。")]}, {"id": "b", "lines": [_say("mei", "靈魂。"), _say("mei", "彷彿。")]}]
	var issues := StoryLint.check_chapter("c", three, SPEAKERS)
	check(_has_rule(issues, "空泛大詞", StoryLint.Level.ERROR), "a third grand word in the chapter is an error")
	check(StoryLint.with_rule(issues, "空泛大詞")[0]["message"].contains("a（命運）"), "the message names where each one is")
	for word in StoryLint.GRAND_WORDS:
		var many := [{"id": "x", "lines": [_say("rin", word), _say("rin", word), _say("rin", word)]}]
		check(_has_rule(StoryLint.check_chapter("c", many, SPEAKERS), "空泛大詞", StoryLint.Level.ERROR), "grand word is tracked: %s" % word)


func _test_sentence_length() -> void:
	var forty := "字".repeat(40)
	var forty_one := "字".repeat(41)
	var fifty_six := "字".repeat(56)
	var fifty_seven := "字".repeat(57)
	check(_unit([_say("mei", forty + "。")]).is_empty(), "a 40 character sentence passes")
	var warn := _unit([_say("mei", forty_one + "。")])
	check(_has_rule(warn, "單句長度", StoryLint.Level.WARNING) and not _has_rule(warn, "單句長度", StoryLint.Level.ERROR), "41 characters is a warning")
	var still_warn := _unit([_say("mei", fifty_six + "。")])
	check(not _has_rule(still_warn, "單句長度", StoryLint.Level.ERROR), "56 characters is still only a warning")
	check(_has_rule(_unit([_say("mei", fifty_seven + "。")]), "單句長度", StoryLint.Level.ERROR), "57 characters is an error")
	# 句子以。！？斷開，所以兩個 30 字的句子沒問題。
	check(_unit([_say("mei", "字".repeat(30) + "。" + "字".repeat(30) + "。")]).is_empty(), "two 30 character sentences pass")
	check(StoryLint.errors_of(warn).is_empty() and StoryLint.warnings_of(warn).size() == 1, "errors_of and warnings_of split by level")
	check(StoryLint.format(warn[0]).begins_with("[警告／單句長度]"), "the message says level, rule and place: %s" % StoryLint.format(warn[0]))


func _test_abstract_nouns_and_voices() -> void:
	var four := [{"id": "a", "lines": [_say("rin", "希望。"), _say("rin", "絕望。"), _say("rin", "代價。"), _say("rin", "未來。")]}]
	check(StoryLint.with_rule(StoryLint.check_chapter("c", four, SPEAKERS), "抽象名詞密度").is_empty(), "four abstract nouns are allowed")
	var five := [{"id": "a", "lines": [_say("rin", "希望。希望。"), _say("rin", "絕望。"), _say("rin", "代價。"), _say("rin", "未來。")]}]
	var dense := StoryLint.check_chapter("c", five, SPEAKERS)
	check(_has_rule(dense, "抽象名詞密度", StoryLint.Level.WARNING) and StoryLint.errors_of(dense).is_empty(), "five abstract nouns are a warning, not an error")
	# 同一個講者連續 3 句都很長：警告；中間換人就不算。
	var long_text := "字".repeat(30) + "。"
	var streak := _unit([_say("mei", long_text), _say("mei", long_text), _say("mei", long_text)])
	check(_has_rule(streak, "講者長度", StoryLint.Level.WARNING), "three long lines in a row from one speaker is a warning")
	var broken := _unit([_say("mei", long_text), _say("mei", long_text), _say("rin", "嗯。"), _say("mei", long_text)])
	check(StoryLint.with_rule(broken, "講者長度").is_empty(), "another speaker in between resets the streak")
	var once := _unit([_say("mei", long_text), _say("mei", long_text), _say("mei", long_text), _say("mei", long_text)])
	check(StoryLint.with_rule(once, "講者長度").size() == 1, "a long streak is reported once")
	# 凜的句子應明顯短於芽：太長時提醒人工檢視；資料太少不檢查。
	var rin_long: Array = []
	var mei_short: Array = []
	for i in 4:
		rin_long.append(_say("rin", "這是一句比較長的話啊。"))
		mei_short.append(_say("mei", "短短的。"))
	var voices := StoryLint.check_chapter("c", [{"id": "a", "lines": rin_long + mei_short}], SPEAKERS)
	check(_has_rule(voices, "講者一致", StoryLint.Level.WARNING), "rin talking longer than mei is flagged for review")
	var fine: Array = []
	for i in 4:
		fine.append(_say("rin", "嗯。"))
		fine.append(_say("mei", "這是一句比較長的話啊，連珠炮。"))
		fine.append(_say("warden", "您好，請隨我來，路上辛苦了。"))
	check(StoryLint.with_rule(StoryLint.check_chapter("c", [{"id": "a", "lines": fine}], SPEAKERS), "講者一致").is_empty(), "a short-spoken rin passes")
	check(StoryLint.with_rule(StoryLint.check_chapter("c", [{"id": "a", "lines": [_say("rin", "很長很長很長的一句話啊。"), _say("mei", "短。")]}], SPEAKERS), "講者一致").is_empty(), "too little data is not judged")


# ---------------------------------------------------------------------------
# 實際劇本
# ---------------------------------------------------------------------------

func _test_all_scripts_pass() -> void:
	var issues := Story.lint()
	var errors := StoryLint.errors_of(issues)
	var lines := PackedStringArray()
	for issue in issues:
		lines.append(StoryLint.format(issue))
	check(errors.is_empty(), "every script scene passes the quality check: %s" % ["\n".join(lines)])
	check(issues.is_empty(), "the scripts also have no warnings: %s" % ["\n".join(lines)])
	check(Story.validate().is_empty(), "Story.validate() is clean: %s" % [Story.validate()])
	# 檢查範圍：每個章節的所有場景與章節卡都有被掃到。
	for chapter_id in Story.chapter_ids():
		var units := Story.text_units(chapter_id)
		var scene_units := 0
		var card := false
		for unit in units:
			if str(unit["id"]).ends_with("章節卡"):
				card = true
				check((unit["lines"] as Array).size() == 4, "the chapter card checks title, subtitle, end title and teaser: %s" % chapter_id)
			else:
				scene_units += 1
		check(card and scene_units >= 10, "%s: %d scenes and the chapter card are scanned" % [chapter_id, scene_units])
	var scanned := 0
	for chapter_id in Story.chapter_ids():
		scanned += Story.text_units(chapter_id).size()
	check(scanned == Story.scene_ids().size() + Story.chapter_ids().size(), "every scene is in exactly one chapter's scan (%d)" % scanned)
	# 章節卡的預告文字沒有破折號。
	for chapter_id in Story.chapter_ids():
		check(not str(Story.chapter_info(chapter_id).get("teaser", "")).contains("——"), "the teaser has no dash: %s" % chapter_id)


func _test_items_pass() -> void:
	var issues := StoryItems.lint()
	var lines := PackedStringArray()
	for issue in issues:
		lines.append(StoryLint.format(issue))
	check(issues.is_empty(), "every story item text passes the quality check: %s" % ["\n".join(lines)])
	for item in StoryItems.catalog():
		if item.is_collectible():
			check(item.body.length() <= StoryItemData.MAX_BODY_LENGTH, "item text fits the inventory (220 characters): %s %d" % [item.id, item.body.length()])
	# 壞的道具文字會被抓到。
	var units: Array[Dictionary] = [{"id": "道具 test_bad", "lines": [{"speaker": "", "text": "然而這是命運。命運，注定。"}]}]
	var bad := StoryLint.check_chapter("道具文字", units, {})
	check(_has_rule(bad, "書面連接詞", StoryLint.Level.ERROR) and _has_rule(bad, "空泛大詞", StoryLint.Level.ERROR), "bad item text is caught")


func _test_story_validation_integration() -> void:
	# 在章節裡塞一個壞場景：validate() 會指出是哪個場景、哪一句、什麼規則。
	Story._scenes["test_lint_scene"] = {"mode": "radio", "lines": [{"speaker": "rin", "text": "鎖定目標！"}, {"speaker": "mei", "text": "不是他，是我！"}]}
	Story._scene_chapter["test_lint_scene"] = &"chapter_01"
	var problems := Story.validate()
	var joined := "\n".join(problems)
	check(joined.contains("test_lint_scene 第 1 句") and joined.contains("教學詞"), "validate() points at the scene, line and rule: %s" % joined)
	check(joined.contains("對比句型") and joined.contains("驚嘆號"), "validate() reports every rule that was broken")
	Story._scenes.erase("test_lint_scene")
	Story._scene_chapter.erase("test_lint_scene")
	check(Story.validate().is_empty(), "validate() is clean again after removing the bad scene")
	# 動畫場景的 say 與 narrate 也在檢查範圍內。
	Story._scenes["test_lint_anim"] = {"mode": "animated", "steps": [
		{"do": "say", "speaker": "rin", "text": "快跑！"}, {"do": "say", "speaker": "mei", "text": "等等！"},
		{"do": "narrate", "lines": ["然而天亮了。"]},
	]}
	Story._scene_chapter["test_lint_anim"] = &"chapter_01"
	var anim_rules := _rules(StoryLint.errors_of(Story.lint()))
	check(anim_rules.has("驚嘆號"), "animated say steps are checked")
	Story._scenes.erase("test_lint_anim")
	Story._scene_chapter.erase("test_lint_anim")
	# 章節卡文字也會被檢查。
	var info: Dictionary = Story._chapters[&"chapter_01"]
	var original: Variant = info.get("teaser", "")
	info["teaser"] = "下一章——命運——"
	check(_has_rule(Story.lint(), "破折號", StoryLint.Level.ERROR), "chapter card text is checked")
	info["teaser"] = original
	check(StoryLint.errors_of(Story.lint()).is_empty(), "the chapter card is clean again")
