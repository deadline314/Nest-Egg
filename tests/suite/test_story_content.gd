class_name StoryContentSuite
extends TestSuite
## 劇本內容（NE-49、NE-50）：場景清單齊全、各場景類型的長度、講者各有各的聲音、
## 伏筆表（design/04-story/FORESHADOWING.md）列的埋設點都有對應的文字或細節，每條至少一顯一隱。

## 每章要有的場景（依 design/04-story/BIBLE.md 的場景清單）。
const REQUIRED_SCENES := {
	"chapter_01": [
		"prologue", "radio_start", "radio_roof", "npc_ahpo_1", "npc_ahpo_2", "radio_market", "radio_market_mei", "radio_forecast",
		"radio_shield", "radio_mech", "npc_worker_1", "npc_worker_2", "radio_facility", "radio_arm", "radio_last", "boss_intro", "epilogue",
	],
	"chapter_02": [
		"c2_prologue", "c2_radio_start", "c2_radio_barrel", "c2_radio_k1", "c2_npc_chen_1", "c2_npc_chen_2", "c2_memory",
		"c2_reclaimer_glass", "c2_radio_cloak", "c2_radio_wall", "c2_radio_corridor", "c2_npc_resident_1", "c2_npc_resident_2",
		"c2_radio_voice", "c2_radio_voice2", "c2_curtain", "c2_radio_power", "c2_radio_medic", "c2_radio_k2", "c2_radio_captain",
		"c2_npc_nurse_1", "c2_npc_nurse_2", "c2_obj_marks", "c2_radio_last", "c2_boss_intro", "c2_epilogue",
	],
}

## 伏筆的埋設點：每個項目 [出處, 必須出現的字句]，出處是 "scene:場景 id" 或 "item:道具 id"。
## explicit 是玩家一定會看到的，hidden 要停下來看或讀道具才會發現。
const FORESHADOWING := {
	"F01 停雨一分鐘": {
		"explicit": [["scene:prologue", "暫停降雨"], ["scene:epilogue", "停了"]],
		"hidden": [["scene:npc_ahpo_2", "沒看過雨停"]],
	},
	"F02 芽的破綻": {
		"explicit": [["scene:radio_start", "聽得到嗎"], ["scene:c2_radio_start", "上面"], ["scene:c2_radio_corridor", "這條走廊我走過"]],
		"hidden": [["scene:radio_start", "一二三"], ["scene:c2_radio_start", "到……上面"], ["scene:c2_radio_wall", "管線吧"]],
	},
	"F03 七號資料夾": {
		"explicit": [["scene:radio_facility", "七號"], ["scene:radio_facility", "別點"]],
		"hidden": [["scene:radio_facility", "七年前"], ["item:doc_nest_log", "基準"]],
	},
	"F04 老K的手與立場": {
		"explicit": [["scene:prologue", "手沒事吧"], ["scene:radio_last", "手沒事吧"], ["scene:c2_prologue", "手沒事吧"], ["scene:c2_radio_k1", "天天爬"],
				["scene:c2_radio_k2", "別回頭"], ["scene:c2_epilogue", "是我接的"]],
		"hidden": [["item:doc_cargo_manifest", "K"], ["item:old_k_order", "青色"], ["scene:radio_mech", "你怎麼知道"], ["scene:radio_last", "算了"],
				["item:doc_nest_log", "技師簽名為 K"]],
	},
	"F05 航的照片": {
		"explicit": [["scene:prologue", "天空"], ["scene:c2_radio_voice", "天空是不是真的很藍"]],
		"hidden": [["item:wataru_photo", "接縫"], ["item:wataru_photo", "第七區景觀"]],
	},
	"F06 會看人的廣告": {
		"explicit": [["scene:radio_market", "軌道醫院"]],
		"hidden": [["scene:radio_market", "還沒決定嗎"], ["scene:radio_market_mei", "十一秒"], ["scene:radio_forecast", "霓虹市集"]],
	},
	"F07 回收部與歡迎回家": {
		"explicit": [["scene:boss_intro", "歡迎回家"], ["scene:c2_memory", "歡迎回家"], ["scene:c2_reclaimer_glass", "依規定"]],
		"hidden": [["scene:boss_intro", "十六號"], ["item:nest_roster", "05"]],
	},
	"F08 右臂記得": {
		"explicit": [["scene:radio_arm", "雜訊"], ["scene:c2_memory", "手在抖"]],
		"hidden": [["scene:radio_arm", "線也亮了"]],
	},
	"F09 巢蛋晶片的數字": {
		"explicit": [["scene:prologue", "四萬三"]],
		"hidden": [["item:nest_egg_chip", "91,000"], ["item:nest_roster", "91,000"]],
	},
	"F10 數到十六": {
		"explicit": [["scene:boss_intro", "十六號"], ["scene:c2_memory", "十六"]],
		"hidden": [["scene:npc_ahpo_2", "十年前"], ["scene:npc_ahpo_2", "兩個小的"], ["scene:c2_npc_chen_1", "有人在數數"], ["scene:c2_obj_marks", "數到十六"],
				["scene:c2_obj_marks", "07 那道，到我的肩膀"]],
	},
	"F11 航的夢": {
		"explicit": [["scene:c2_radio_voice", "很大的房間"], ["item:rec_wataru_1", "有人一直在哭"]],
		"hidden": [["scene:prologue", "嗯嗯嗯"]],
	},
	"F12 蠟筆畫的第三個人": {
		"explicit": [["scene:npc_ahpo_1", "畫了一張"]],
		"hidden": [["item:doc_crayon_drawing", "最淡的黃色"], ["item:doc_crayon_drawing", "兩個人撐一把紅傘"]],
	},
	"F13 前一個領貨的人": {
		"explicit": [["scene:npc_worker_1", "上禮拜"]],
		"hidden": [["item:doc_shift_note", "第三個"], ["scene:npc_worker_2", "第三個"]],
	},
	"F14 粥": {
		"explicit": [["scene:epilogue", "粥"], ["scene:c2_prologue", "粥"]],
		"hidden": [["item:rec_old_k_voicemail", "粥"], ["item:maintenance_pass", "粥已經涼了"]],
	},
	"F15 健康檢查": {
		"explicit": [["scene:c2_npc_resident_1", "健康檢查"]],
		"hidden": [["item:doc_resident_notice", "健康檢查"], ["item:doc_resident_notice", "定期前往轉運站"], ["item:nest_roster", "簽名欄"]],
	},
	"F16 房間裡的哭聲": {
		"explicit": [["scene:c2_radio_wall", "牆裡有人在哭"], ["scene:c2_npc_resident_2", "牆裡有聲音"]],
		"hidden": [["item:doc_power_log", "三樓就有人哭"], ["item:rec_wataru_2", "很輕的哭聲"]],
	},
	"F17 回收員的數字": {
		"explicit": [["scene:c2_boss_intro", "五號"], ["scene:c2_boss_intro", "第六個"]],
		"hidden": [["item:nest_roster", "補完上傳"]],
	},
	"F18 溫的手環": {
		"explicit": [["scene:c2_epilogue", "手環還是暖的"]],
		"hidden": [["scene:c2_npc_nurse_1", "三十七度"], ["item:doc_transfer_sheet", "37 度"], ["item:wataru_wristband", "接點"]],
	},
}

## 「必須存在的細節」（FORESHADOWING.md 驗收用）。
const REQUIRED_DETAILS := [
	["第一章開場，航在咳嗽之間哼一段沒有歌詞的旋律", "scene:prologue", "嗯嗯嗯"],
	["麵攤阿婆提到停雨", "scene:npc_ahpo_2", "停雨"],
	["麵攤阿婆提到老 K 十年前", "scene:npc_ahpo_2", "十年前"],
	["設施內右臂震動、畫面出雜訊", "scene:radio_arm", "雜訊"],
	["結尾雨停", "scene:epilogue", "停了"],
	["第二章夾層區，牆內有很輕的哭聲", "scene:c2_radio_wall", "牆裡有人在哭"],
	["芽說出「這條走廊我走過」", "scene:c2_radio_corridor", "這條走廊我走過"],
	["轉運站牆上有身高刻痕", "scene:c2_obj_marks", "刻痕"],
	["結尾手環是暖的", "scene:c2_epilogue", "手環還是暖的"],
]


func run() -> void:
	_test_required_scenes()
	_test_scene_shapes()
	_test_voices()
	_test_variant_answers()
	_test_foreshadowing()
	_test_required_details()
	_test_old_sentences_are_gone()


# ---------------------------------------------------------------------------
# 取文字
# ---------------------------------------------------------------------------

func _source_text(source: String) -> String:
	if source.begins_with("scene:"):
		var id := source.trim_prefix("scene:")
		var scene: Variant = Story._scenes.get(id, null)
		if scene == null:
			return ""
		var parts := PackedStringArray()
		for text_line: Variant in Story._scene_text_lines(scene):
			parts.append(str((text_line as Dictionary).get("text", "")))
		return "\n".join(parts)
	if source.begins_with("item:"):
		var item := StoryItems.find(StringName(source.trim_prefix("item:")))
		if item == null:
			return ""
		return "\n".join(PackedStringArray([item.display_name, item.description, item.body]))
	return ""


func _has(entry: Array) -> bool:
	return _source_text(str(entry[0])).contains(str(entry[1]))


# ---------------------------------------------------------------------------
# 測試
# ---------------------------------------------------------------------------

func _test_required_scenes() -> void:
	for chapter in REQUIRED_SCENES:
		for id: String in REQUIRED_SCENES[chapter]:
			check(Story.has_scene(StringName(id)), "%s has the scene: %s" % [chapter, id])
			check(Story._scene_chapter.get(id, &"") == StringName(chapter), "the scene belongs to its chapter: %s" % id)


func _test_scene_shapes() -> void:
	var modes: Dictionary[String, int] = {}
	for id: String in Story.scene_ids():
		var scene: Dictionary = Story._scenes[id]
		var mode := str(scene.get("mode", "radio"))
		modes[mode] = modes.get(mode, 0) + 1
		if mode == "animated":
			continue
		var lines: Array = scene.get("lines", [])
		match mode:
			"radio":
				check(lines.size() >= 1 and lines.size() <= 2, "a radio scene has one or two lines: %s (%d)" % [id, lines.size()])
			"cinematic":
				check(lines.size() >= 3 and lines.size() <= 6, "a cinematic has three to six lines: %s (%d)" % [id, lines.size()])
			"dialogue":
				check(lines.size() >= 3 and lines.size() <= 8, "a conversation has three to eight lines: %s (%d)" % [id, lines.size()])
		for entry: Variant in lines:
			check(Story.speaker_ids().has(str((entry as Dictionary).get("speaker", ""))), "scene %s uses a defined speaker" % id)
			check(not str((entry as Dictionary).get("text", "")).strip_edges().is_empty(), "scene %s has no empty line" % id)
	check(modes.get("radio", 0) >= 12 and modes.get("dialogue", 0) >= 4 and modes.get("cinematic", 0) >= 4, "scripts have radios, conversations and cinematics %s" % [modes])
	# 每位講者的名字與顏色不重複，方便分辨。
	var names: Dictionary[String, bool] = {}
	for id: String in Story.speaker_ids():
		var speaker: Dictionary = Story.speaker(id)
		check(not names.has(str(speaker["name"])), "speaker names are unique: %s" % speaker["name"])
		names[str(speaker["name"])] = true


## 每個講者有自己的聲音：凜的句子最短，芽與監管者比較長；老 K 愛碎念、句尾拖「喔」。
func _test_voices() -> void:
	var lengths: Dictionary[String, Array] = {}
	for id: String in Story.scene_ids():
		for entry: Variant in Story._scene_text_lines(Story._scenes[id]):
			var speaker := str((entry as Dictionary).get("speaker", ""))
			var text := str((entry as Dictionary).get("text", ""))
			if not lengths.has(speaker):
				lengths[speaker] = []
			lengths[speaker].append(text.length())
	var average := func(speaker: String) -> float:
		var values: Array = lengths.get(speaker, [])
		if values.is_empty():
			return 0.0
		var sum := 0
		for value: int in values:
			sum += value
		return float(sum) / float(values.size())
	var rin: float = average.call("rin")
	check(rin > 0.0 and rin < 12.0, "rin speaks in very short lines (average %.1f)" % rin)
	check(float(average.call("mei")) > rin * 1.5, "mei talks clearly more than rin (%.1f vs %.1f)" % [average.call("mei"), rin])
	check(float(average.call("warden")) > rin * 1.5, "the warden talks clearly more than rin (%.1f)" % average.call("warden"))
	# 老 K 的毛病：句尾拖「喔」，而且常問手。
	var old_k_text := ""
	for id: String in Story.scene_ids():
		for entry: Variant in Story._scene_text_lines(Story._scenes[id]):
			if (entry as Dictionary).get("speaker", "") == "old_k":
				old_k_text += str((entry as Dictionary).get("text", ""))
	check(old_k_text.contains("喔") and old_k_text.contains("手沒事吧"), "old K drags his sentences and keeps asking about the hand")
	# 阿婆、工人說話絮絮叨叨、帶口語助詞。
	check(_source_text("scene:npc_ahpo_1").contains("啦") and _source_text("scene:npc_ahpo_2").contains("喔"), "the noodle lady uses spoken particles")
	# 第二章的人：老陳斷斷續續、滿口數字、叫年輕人「囝仔」；護理師客氣、重複；回收員先唸流程。
	check(_source_text("scene:c2_npc_chen_1").contains("囝仔") and _source_text("scene:c2_npc_chen_1").contains("十七層") and _source_text("scene:c2_npc_chen_1").contains("……"), "the old repairman halts, counts floors and says 囝仔")
	check(_source_text("scene:c2_npc_nurse_1").contains("您") and _source_text("scene:c2_npc_nurse_2").contains("七號"), "the nurse is polite and keeps calling her seven")
	check(_source_text("scene:c2_boss_intro").begins_with("依規定"), "the reclaimer recites the procedure first")


func _test_foreshadowing() -> void:
	for name: String in FORESHADOWING:
		var entry: Dictionary = FORESHADOWING[name]
		var explicit: Array = entry["explicit"]
		var hidden: Array = entry["hidden"]
		check(explicit.size() >= 1 and hidden.size() >= 1, "%s has at least one explicit and one hidden source" % name)
		for source: Array in explicit + hidden:
			check(_has(source), "%s: %s contains 「%s」" % [name, source[0], source[1]])
		var places: Dictionary[String, bool] = {}
		for source: Array in explicit + hidden:
			places[str(source[0])] = true
		check(places.size() >= 1 and explicit.size() + hidden.size() >= 2, "%s is planted at two or more points" % name)


func _test_required_details() -> void:
	for detail: Array in REQUIRED_DETAILS:
		check(_has([detail[1], detail[2]]), "required detail: %s" % detail[0])


## 風格指南對照表裡的壞句子都不能留在劇本。
func _test_old_sentences_are_gone() -> void:
	var old_lines: PackedStringArray = [
		"紅色瞄準線一亮就閃", "正面的盾打不穿", "熱源……很大一個", "有錢人住在雲上面", "我只想帶我弟去看一次真正的天空",
		"這不是治療", "你以為……是你偷走了它", "可是我要買的，從來就不是船票", "航的病，只有軌道醫院治得好",
		"一路都是他們的人", "這條路要付多少，我都付", "這條井是我年輕時天天爬的路", "我不是去偷東西", "那排紅色油桶是燃料。打爆它",
		"留意閃爍的空氣", "通電的格子會先閃黃燈", "先打掉它，不然你永遠打不完", "代價是你也得摸黑走",
	]
	var everything := ""
	for id: String in Story.scene_ids():
		everything += _source_text("scene:" + id)
	for item in StoryItems.catalog():
		everything += _source_text("item:" + String(item.id))
	for sentence in old_lines:
		check(not everything.contains(sentence), "the old line is gone: %s" % sentence)


## 重複地點的記憶異常不是問價錢；否認必須回應同一個問題。
func _test_variant_answers() -> void:
	var checked := 0
	for id: String in Story.scene_ids():
		for variant in StoryReactions.variants_of(Story._scenes[id]):
			var lines: Array = variant.get("lines", [])
			for i in range(1, lines.size()):
				if str(lines[i - 1].get("text", "")).contains("你是不是在這裡停過"):
					var answer := str(lines[i].get("text", ""))
					check(answer.contains("沒有在這裡停過") and not answer.contains("錢"), "memory variant answers the location question: %s" % id)
					checked += 1
	check(checked >= 6, "all six memory-question variants are checked")
