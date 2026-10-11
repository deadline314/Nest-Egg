class_name StoryContentSuite
extends TestSuite

const CONDITION_TREE = preload("res://core/story_condition_tree.gd")
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
	_test_condition_contract()
	_test_required_scenes()
	_test_scene_shapes()
	_test_voices()
	_test_variant_answers()
	_test_foreshadowing()
	_test_required_details()
	_test_old_sentences_are_gone()
	_test_release_story_sources()


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


## 從正式 NE-231 資源取得測試定義，fixture 不另寫金額或指紋。
func _condition_context() -> Dictionary:
	var definitions := {}
	for name in ["daily_dinner", "commission_settled", "revival_meal_order", "revival_meal_paid", "revival_meal_tab", "revival_meal_gift", "revival_meal_later_pay"]:
		var path := "res://data/story_transactions/ch1_%s.tres" % name
		var resource: Variant = load(path) if ResourceLoader.exists(path) else null
		check(resource != null and resource.has_method("descriptor"), "condition contract has canonical resource " + path)
		if resource == null or not resource.has_method("descriptor"):
			return {}
		var descriptor: Dictionary = resource.descriptor()
		check(not descriptor.has("error"), "condition descriptor is valid " + path)
		if descriptor.has("error"):
			return {}
		definitions[descriptor["id"]] = descriptor
	return {"ledger_locked": false, "transaction_definitions": definitions}


func _condition_facts(context: Dictionary, ids: Array = []) -> Dictionary:
	var receipts := {}
	for id: String in ids:
		var definition: Dictionary = context["transaction_definitions"][id]
		receipts[id] = {"definition_fingerprint": definition["fingerprint"], "credits_delta": definition["credits_delta"]}
	return {"flags": {"ready": true, "blocked": false, "choice": "unset", "count": 1},
		"items": {"ch1_data_disk": false, "ch1_grey_cloth": true}, "ledger": {"version": 1, "receipts": receipts}}


func _condition_check(result: Dictionary, valid: bool, value: bool, label: String) -> void:
	check(result["valid"] == valid and result["value"] == value and (result["error"].is_empty() == valid), label)


func _condition_refresh_fingerprint(definition: Dictionary) -> void:
	definition["fingerprint"] = JSON.stringify([definition["id"], 1, int(definition["credits_delta"]), definition["required"], definition["excluded"]]).sha256_text()


func _test_condition_contract() -> void:
	var context := _condition_context()
	if context.is_empty():
		return
	var facts := _condition_facts(context)
	var ready := {"flag": "ready", "equals": true}
	var blocked := {"flag": "blocked", "equals": true}
	var none := {"account": "ch1_lounge", "equals": "none"}
	var verified := CONDITION_TREE.verify_ledger(facts, context)
	check(verified["valid"] and verified["account"] == "none", "public ledger proof verifies unconditional result batch")
	for malformed: Variant in [null, [], {"account": "paid200"}, {"ledger": {"version": 1, "receipts": {"unknown": {}}}}]:
		check(not CONDITION_TREE.verify_ledger(malformed, context)["valid"], "public ledger proof refuses malformed facts")
	check(not CONDITION_TREE.verify_ledger(facts, {"ledger_locked": true, "transaction_definitions": context["transaction_definitions"]})["valid"], "public ledger proof refuses locked ledger")
	var proof_before := JSON.stringify([facts, context])
	verified["account"] = "paid200"
	check(CONDITION_TREE.verify_ledger(facts, context)["account"] == "none" and JSON.stringify([facts, context]) == proof_before, "public ledger proof is independent and does not mutate source facts")
	_condition_check(CONDITION_TREE.evaluate({}, {}), true, true, "author empty condition is unconditional")
	_condition_check(CONDITION_TREE.evaluate({"all": [ready, {"not": blocked}]}, facts), true, true, "nested all/not accepts complete facts")
	_condition_check(CONDITION_TREE.evaluate({"any": [blocked, ready]}, facts), true, true, "any evaluates declared flags")
	_condition_check(CONDITION_TREE.evaluate({"flag": "choice", "equals": "unset"}, facts), true, true, "author string flag default is exact")
	_condition_check(CONDITION_TREE.evaluate({"flag": "count", "equals": true}, facts), true, false, "numeric flag cannot impersonate boolean")
	_condition_check(CONDITION_TREE.evaluate({"flag": "count", "equals": 1.0}, facts), true, true, "JSON numeric representations compare numerically")
	_condition_check(CONDITION_TREE.evaluate({"item": "ch1_data_disk"}, facts), true, false, "item means current holds after disk transfer")
	_condition_check(CONDITION_TREE.evaluate({"item": "ch1_grey_cloth"}, facts), true, true, "item reads actual held cloth")
	_condition_check(CONDITION_TREE.evaluate({"not": {"flag": "unknown", "equals": true}}, facts), false, false, "missing flag cannot become eligible under not")
	_condition_check(CONDITION_TREE.evaluate({"not": {"item": "unknown"}}, facts), false, false, "missing item declaration is invalid")
	for bad: Variant in [null, false, [], {"all": []}, {"any": []}, {"not": []}, {"flag": "ready"}, {"flag": "ready", "equals": []}, {"flag": "ready", "equals": true, "item": "ch1_grey_cloth"}, {"receipt": "ch1.unknown", "status": "recorded"}, {"receipt": "ch1.daily_dinner", "status": "missing"}, {"account": "unknown", "equals": "none"}, {"account": "ch1_lounge", "equals": "bad"}, {"requires_item": "ch1_data_disk"}]:
		_condition_check(CONDITION_TREE.evaluate(bad, facts, context), false, false, "unknown/malformed condition refuses eligibility")
	for expression in [{"all": [blocked, {"typo": true}]}, {"any": [ready, {"typo": true}]}, {"any": [ready, {"item": "unknown"}]}]:
		var result := CONDITION_TREE.evaluate(expression, facts, context)
		_condition_check(result, false, false, "boolean branch cannot conceal invalid schema/fact")
		check(result["error"].contains("[1]"), "invalid branch identifies precise condition path")
	_test_condition_meal_subsets(context)
	_test_condition_receipt_trust(context)
	_test_condition_limits(facts)
	var shared := {"flag": "ready", "equals": true}
	var aliases := {"all": [shared, shared]}
	var before := JSON.stringify([aliases, facts, context])
	var first := CONDITION_TREE.evaluate(aliases, facts, context)
	first["value"] = false
	_condition_check(CONDITION_TREE.evaluate(aliases, facts, context), true, true, "result mutation and reused child alias cannot alter evaluation")
	check(JSON.stringify([aliases, facts, context]) == before, "condition/context/facts remain byte-equivalent after evaluation")
	_condition_check(CONDITION_TREE.evaluate(none, facts, {"locked": false, "definitions": context["transaction_definitions"]}), false, false, "context aliases are refused")
	var fake := facts.duplicate(true)
	fake["account"] = "paid200"
	_condition_check(CONDITION_TREE.evaluate(none, fake, context), false, false, "saved account alias cannot impersonate canonical receipts")
	fake = facts.duplicate(true)
	fake["flags"]["ready"] = 1
	_condition_check(CONDITION_TREE.evaluate(ready, fake), true, false, "flag type replacement cannot become boolean true")
	fake["items"]["ch1_data_disk"] = 1
	_condition_check(CONDITION_TREE.evaluate(ready, fake), false, false, "item facts require exact boolean values")


func _test_condition_meal_subsets(context: Dictionary) -> void:
	# Independent authored matrix: six legal exact sets, all 26 others invalid.
	var expected := {0: "none", 1: "open200", 3: "paid200", 5: "owed200", 9: "gifted200", 21: "paid200"}
	var ids := ["ch1.revival_meal.order", "ch1.revival_meal.paid", "ch1.revival_meal.tab", "ch1.revival_meal.gift", "ch1.revival_meal.later_pay"]
	var legal := 0
	var invalid := 0
	for mask in 32:
		var recorded: Array = ["ch1.daily_dinner", "ch1.commission.settled"]
		for i in 5:
			if mask & (1 << i):
				recorded.append(ids[i])
		var facts := _condition_facts(context, recorded)
		for state in ["none", "open200", "paid200", "owed200", "gifted200"]:
			var result := CONDITION_TREE.evaluate({"account": "ch1_lounge", "equals": state}, facts, context)
			_condition_check(result, expected.has(mask), expected.get(mask) == state, "canonical exact meal subset %d vs %s" % [mask, state])
		if expected.has(mask):
			legal += 1
		else:
			invalid += 1
	check(legal == 6 and invalid == 26, "all 32 meal subsets: exactly six legal and 26 invalid")


func _test_condition_receipt_trust(context: Dictionary) -> void:
	var order := "ch1.revival_meal.order"
	var recorded := {"receipt": order, "status": "recorded"}
	var none := {"account": "ch1_lounge", "equals": "none"}
	_condition_check(CONDITION_TREE.evaluate(recorded, _condition_facts(context), context), true, false, "trusted missing receipt is false")
	_condition_check(CONDITION_TREE.evaluate({"not": recorded}, _condition_facts(context), context), true, true, "not missing trusted receipt is true")
	_condition_check(CONDITION_TREE.evaluate(recorded, _condition_facts(context, [order]), context), true, true, "matching recorded receipt is true")
	for id: String in context["transaction_definitions"]:
		var changed := context.duplicate(true)
		changed["transaction_definitions"][id]["credits_delta"] += 1
		_condition_refresh_fingerprint(changed["transaction_definitions"][id])
		var held: Array = [order] if id == order else ([order, id] if id in ["ch1.revival_meal.paid", "ch1.revival_meal.tab", "ch1.revival_meal.gift"] else ([order, "ch1.revival_meal.tab", id] if id == "ch1.revival_meal.later_pay" else [id]))
		var facts := _condition_facts(context, held)
		_condition_check(CONDITION_TREE.evaluate(none, facts, changed), false, false, "all seven recorded definitions detect current resource drift " + id)
		_condition_check(CONDITION_TREE.evaluate({"not": {"receipt": id, "status": "recorded"}}, facts, changed), false, false, "not cannot invert drifted receipt " + id)
		_condition_check(CONDITION_TREE.evaluate(none, _condition_facts(context), changed), true, true, "empty ledger may use complete valid current definitions " + id)
		var malformed := context.duplicate(true)
		malformed["transaction_definitions"][id]["fingerprint"] = "a".repeat(64)
		_condition_check(CONDITION_TREE.evaluate(none, _condition_facts(context), malformed), false, false, "descriptor must prove its own current fingerprint " + id)
	var facts := _condition_facts(context, [order])
	for field in ["definition_fingerprint", "credits_delta"]:
		var broken := facts.duplicate(true)
		broken["ledger"]["receipts"][order][field] = "untrusted"
		_condition_check(CONDITION_TREE.evaluate({"not": recorded}, broken, context), false, false, "not malformed receipt stays invalid " + field)
		_condition_check(CONDITION_TREE.evaluate({"any": [{}, recorded]}, broken, context), false, false, "true any cannot conceal untrusted receipt " + field)
		_condition_check(CONDITION_TREE.evaluate({"all": [{"flag": "blocked", "equals": true}, recorded]}, broken, context), false, false, "false all cannot conceal untrusted receipt " + field)
	var locked := context.duplicate(true)
	locked["ledger_locked"] = true
	_condition_check(CONDITION_TREE.evaluate(none, _condition_facts(context), locked), false, false, "locked empty ledger never maps to none")
	locked["ledger_locked"] = "false"
	_condition_check(CONDITION_TREE.evaluate(none, facts, locked), false, false, "trust state requires exact bool")
	var untrusted := _condition_facts(context)
	untrusted["ledger"] = {"version": 1, "receipts": {}, "status": "untrusted"}
	_condition_check(CONDITION_TREE.evaluate(none, untrusted, context), false, false, "untrusted ledger cannot be normalized to none")
	for key in ["id", "required", "excluded", "credits_delta", "fingerprint"]:
		var missing := context.duplicate(true)
		missing["transaction_definitions"][order].erase(key)
		_condition_check(CONDITION_TREE.evaluate(none, _condition_facts(context), missing), false, false, "complete current descriptor required: " + key)
	var wrong_amount := facts.duplicate(true)
	wrong_amount["ledger"]["receipts"][order]["credits_delta"] += 1
	_condition_check(CONDITION_TREE.evaluate(recorded, wrong_amount, context), false, false, "matching fingerprint alone cannot authenticate wrong receipt delta")
	for change in [{"id": "ch1.daily_dinner"}, {"required": [order]}, {"required": ["ch1.unknown"]}, {"excluded": [order]}, {"credits_delta": true}, {"credits_delta": 0.5}]:
		var malformed := context.duplicate(true)
		malformed["transaction_definitions"][order].merge(change, true)
		_condition_check(CONDITION_TREE.evaluate(none, _condition_facts(context), malformed), false, false, "malformed current descriptor never authenticates empty ledger")
	for bad_snapshot: Variant in [null, [], {"version": true, "receipts": {}}, {"version": 2, "receipts": {}}, {"version": 1, "receipts": []}, {"version": 1, "receipts": {"ch1.unknown": {}}}]:
		var malformed := _condition_facts(context)
		malformed["ledger"] = bad_snapshot
		_condition_check(CONDITION_TREE.evaluate({"not": none}, malformed, context), false, false, "malformed ledger never becomes eligible under not")


func _test_condition_limits(facts: Dictionary) -> void:
	var nested: Dictionary = {}
	for i in CONDITION_TREE.MAX_DEPTH - 1:
		nested = {"not": nested}
	check(CONDITION_TREE.validate(nested)["valid"], "condition exactly at depth limit is valid")
	check(not CONDITION_TREE.validate({"not": nested})["valid"], "depth limit plus one is invalid")
	var cyclic := {}
	cyclic["not"] = cyclic
	var cycle_result := CONDITION_TREE.validate(cyclic)
	check(not cycle_result["valid"] and cycle_result["error"].length() <= 512, "cycle returns bounded invalid diagnostic without deep duplication")
	cyclic.erase("not")
	var children: Array = []
	for i in CONDITION_TREE.MAX_CHILDREN:
		children.append({})
	check(CONDITION_TREE.validate({"all": children})["valid"], "exact child limit is valid")
	children.append({})
	check(not CONDITION_TREE.validate({"all": children})["valid"], "child limit plus one is invalid")
	var groups: Array = []
	for i in 8:
		var leaves: Array = []
		for j in (32 if i < 7 else 23):
			leaves.append({})
		groups.append({"all": leaves})
	check(CONDITION_TREE.validate({"all": groups})["valid"], "exact 256-node budget is valid")
	groups[7]["all"].append({})
	check(not CONDITION_TREE.validate({"all": groups})["valid"], "257-node condition is invalid")
	var id := "a".repeat(CONDITION_TREE.MAX_ID_LENGTH)
	var bounded := facts.duplicate(true)
	bounded["flags"][id] = true
	_condition_check(CONDITION_TREE.evaluate({"flag": id, "equals": true}, bounded), true, true, "exact ID length limit is valid")
	_condition_check(CONDITION_TREE.evaluate({"flag": id + "a", "equals": true}, bounded), false, false, "long ID is invalid")
	for bad_id in ["", "Upper", "a/b", "a b", "1flag"]:
		check(not CONDITION_TREE.validate({"item": bad_id})["valid"], "invalid ID alphabet is rejected")
	check(not CONDITION_TREE.validate({"flag": "ready", "equals": INF})["valid"], "infinite scalar is invalid")
	check(not CONDITION_TREE.validate({"flag": "ready", "equals": NAN})["valid"], "NaN scalar is invalid")
	check(not CONDITION_TREE.validate({"flag": "ready", "equals": "a".repeat(CONDITION_TREE.MAX_TEXT_LENGTH + 1)})["valid"], "long scalar text is invalid")
	var many_facts := {"flags": {}}
	for i in CONDITION_TREE.MAX_FACTS:
		many_facts["flags"]["f%d" % i] = false
	_condition_check(CONDITION_TREE.evaluate({}, many_facts), true, true, "exact fact count limit is valid")
	many_facts["flags"]["one_more"] = false
	_condition_check(CONDITION_TREE.evaluate({}, many_facts), false, false, "fact count limit plus one is invalid")


## 舊故事只留給開發版的舊示範與上面的歷史測試（ST-2）：發行版只載入正式章節，正式章節與正式關卡不引用舊稿的場景或講者。
func _test_release_story_sources() -> void:
	var legacy_ids: Dictionary[String, bool] = {}
	for path in Story.LEGACY_CHAPTER_PATHS:
		var json := load(path) as JSON
		if json != null and json.data is Dictionary:
			for id: String in (json.data as Dictionary).get("scenes", {}):
				legacy_ids[id] = true
	check(legacy_ids.size() > 40, "legacy scripts are still readable for the history tests")
	check(Story.chapter_paths().has(Story.LEGACY_CHAPTER_PATHS[0]), "the development edition still loads the legacy scripts for the old demo levels")
	var dev := CampaignEdition.current()
	CampaignEdition.override_current(dev.describe("through-ch3_clearwater"))
	Story.load_all()
	var paths := Story.chapter_paths()
	check(Story.LEGACY_CHAPTER_PATHS.all(func(path: String) -> bool: return not paths.has(path)), "release editions do not load the legacy scripts")
	check(not Story.chapter_ids().has(&"chapter_01") and not Story.chapter_ids().has(&"chapter_02"), "release editions have no legacy chapters")
	check(legacy_ids.keys().all(func(id: String) -> bool: return not Story.has_scene(StringName(id))), "no legacy scene is playable in a release edition")
	var problems := Story.validate()
	check(problems.is_empty(), "formal chapters stand on their own without the legacy scripts: %s" % "; ".join(problems.slice(0, 3)))
	check(not Story.chapter_info(Story.DEFAULT_CHAPTER).is_empty(), "the default chapter is a formal chapter")
	CampaignEdition.override_current(null)
	Story.load_all()
	check(Story.has_scene(&"radio_start"), "the development edition gets the legacy scripts back")
	# 正式關卡與它們直接引用的資源（人物、道具、機關）不寫舊稿的場景 id。
	var files: Dictionary[String, bool] = {}
	for file in DirAccess.get_files_at("res://data/levels"):
		if file.ends_with(".tres") and (file.begins_with("ch1_") or file.begins_with("ch2_") or file.begins_with("ch3_")):
			files["res://data/levels/" + file] = true
	var linked := RegEx.create_from_string('path="(res://[^"]+\\.tres)"')
	for level: String in files.keys():
		for found in linked.search_all(FileAccess.get_file_as_string(level)):
			files[found.get_string(1)] = true
	var leaks := PackedStringArray()
	for path: String in files:
		var text := FileAccess.get_file_as_string(path)
		for id: String in legacy_ids:
			if text.contains('"%s"' % id):
				leaks.append("%s → %s" % [path, id])
	check(files.size() > 30 and leaks.is_empty(), "formal levels and their resources reference no legacy scene: %s" % ", ".join(leaks.slice(0, 5)))
