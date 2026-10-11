extends RefCounted
## 累積章節版本：身分、資料損毀退路、存檔隔離、舊版接續、較新版拒絕與章末路由。
## 只用 user:// 的隔離目錄，不碰正式槽；結束時恢復目前版本。

const ROOT := "user://ne230-editions"
const FIRST := "res://data/levels/ch1_pawnshop.tres"
const LEGACY := "res://data/levels/level_02.tres"


static func run(s: TestSuite) -> void:
	_clear(ROOT)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
	var dev := CampaignEdition.load_from(CampaignEdition.CAMPAIGN_PATH, CampaignEdition.EDITION_PATH)
	s.check(dev.issues.is_empty() and dev.development and dev.id == "demo-0.1" and dev.slot_path() == RunSaveStore.DEFAULT_PATH, "checked-in edition is development and keeps the existing slot")
	s.check(dev.includes_chapter(&"ch1_kasa") and dev.includes_chapter(&"chapter_02") and dev.includes_chapter(&""), "development edition reaches formal and legacy chapters")
	var ch1 := dev.describe("through-ch1_kasa")
	var ch2 := dev.describe("through-chapter_2")
	s.check(ch1 != null and not ch1.development and ch1.title() == "序章至第一章" and ch1.slot_path() == "user://runs/through-ch1_kasa/slot-1.json", "release edition has its own title and slot directory")
	s.check(ch1.includes_chapter(&"prologue") and ch1.includes_chapter(&"ch1_kasa") and not ch1.includes_chapter(&"chapter_2") and not ch1.includes_chapter(&"chapter_02") and not ch1.includes_chapter(&""), "release edition excludes later and legacy chapters")
	s.check(ch2.can_continue_from(ch1) and not ch1.can_continue_from(ch2) and ch1.can_continue_from(ch1) and dev.can_continue_from(ch2), "older editions continue forward, never backward")
	for bad: Variant in ["through-chapter_9", "../runs", "", null, 3, "through-" + "x".repeat(80)]:
		s.check(dev.describe(bad) == null, "unknown release id is not an edition: %s" % str(bad).left(20))
	# 發行工具在隔離來源寫入的版本設定（含版本號與來源提交等額外欄位）。
	_write_text(ROOT.path_join("release_edition.json"), '{"schema": 1, "through": "ch1_kasa", "version": "v1", "source_sha": "0123", "_note": "generated"}')
	var built := CampaignEdition.load_from(CampaignEdition.CAMPAIGN_PATH, ROOT.path_join("release_edition.json"), false)
	s.check(built.issues.is_empty() and built.id == "through-ch1_kasa" and built.is_last_chapter(&"ch1_kasa") and built.first_level == FIRST, "release tool's generated edition file loads as that edition")
	_write_text(ROOT.path_join("bad_edition.json"), '{"through": "chapter_9"}')
	var fallback := CampaignEdition.load_from(CampaignEdition.CAMPAIGN_PATH, ROOT.path_join("bad_edition.json"), false)
	s.check(fallback.development and fallback.issues.size() == 1 and fallback.issues[0].contains("bad_edition.json/through"), "unknown through falls back to development and names the field")
	_write_text(ROOT.path_join("bad_campaign.json"), '{"chapters": [')
	var broken := CampaignEdition.load_from(ROOT.path_join("bad_campaign.json"), ROOT.path_join("missing.json"), false)
	s.check(broken.development and broken.issues.size() == 2 and broken.issues[0].contains("bad_campaign.json：第") and broken.issues[1].contains("missing.json"), "corrupt campaign and missing edition report exact files without crashing")
	_write_text(ROOT.path_join("dup_campaign.json"), '{"chapters": [{"id": "a"}, {"id": "a"}, {"id": "b/c"}, {"title": "x"}], "first_level": "user://x.tres"}')
	var duplicate := CampaignEdition.load_from(ROOT.path_join("dup_campaign.json"), CampaignEdition.EDITION_PATH, false)
	s.check(duplicate.order == [&"a"] and duplicate.issues.size() == 4 and duplicate.first_level == FIRST, "duplicate, unsafe and missing chapter ids and foreign first level are skipped with locations")

	GameState.story_autosave = false
	GameState.start_new_run(GameState.difficulties[1])
	CampaignEdition.override_current(ch1)
	var saved := RunSnapshot.capture(FIRST, {"position": [-1, -1], "health": 5, "world": {}, "loadout": {}})
	s.check(saved["release"] == "through-ch1_kasa", "capture records the current edition")
	s.check(RunSnapshot.prepare(saved).has("data"), "same edition save prepares")
	var legacy := saved.duplicate(true)
	legacy["level"] = LEGACY
	var newer := RunSnapshot.prepare(legacy)
	s.check(newer.get("newer_edition", false) and newer.get("unknown_version", false) and str(newer.get("error")).contains("原檔保留"), "save standing in a chapter outside this edition is protected, not loaded")
	var from_dev := saved.duplicate(true)
	from_dev["release"] = "demo-0.1"
	s.check(RunSnapshot.prepare(from_dev).has("data"), "development save inside the edition's chapters still continues")

	# 存檔隔離與接續：每個版本自己的目錄，舊版只讀。
	CampaignEdition.override_current(ch1)
	var ch1_store := RunSaveStore.new(ROOT.path_join("runs/through-ch1_kasa/slot-1.json"))
	ch1_store.validator = RunSnapshot.prepare
	Progression.add_credits(321)
	s.check(ch1_store.write(RunSnapshot.capture(FIRST, {"position": [-1, -1], "health": 5, "world": {}, "loadout": {}})), "first edition writes its own slot")
	var ch1_hash := FileAccess.get_sha256(ch1_store.path)
	CampaignEdition.override_current(ch2)
	var ch2_store := RunSaveStore.new(ROOT.path_join("runs/through-chapter_2/slot-1.json"))
	ch2_store.validator = RunSnapshot.prepare
	s.check(ch2_store.read().is_empty() and not ch2_store.exists(), "newer edition starts without its own slot")
	var lineage := ch2_store.find_other_editions(ch2)
	s.check(lineage.has("data") and lineage["data"]["progression"]["credits"] == 321 and (lineage["edition"] as CampaignEdition).id == "through-ch1_kasa", "newer edition finds the older edition's progress")
	s.check(ch2_store.write(RunSnapshot.capture(FIRST, {"position": [-1, -1], "health": 5, "world": {}, "loadout": {}})), "continued progress writes to the newer edition's own slot")
	s.check(FileAccess.get_sha256(ch1_store.path) == ch1_hash and not FileAccess.file_exists(ch1_store.path + ".bak"), "older edition save is untouched by import and later saves")
	var junk := RunSaveStore.new(ROOT.path_join("runs/not-an-edition/slot-1.json"))
	s.check(junk.write(RunSnapshot.capture(FIRST, {"position": [-1, -1], "health": 5, "world": {}, "loadout": {}})), "unrelated directory fixture written")
	CampaignEdition.override_current(dev.describe("through-prologue"))
	var prologue_store := RunSaveStore.new(ROOT.path_join("runs/through-prologue/slot-1.json"))
	prologue_store.validator = RunSnapshot.prepare
	var older_only := prologue_store.find_other_editions(CampaignEdition.current())
	s.check(not older_only.has("data") and (older_only.get("newer") as CampaignEdition).id == "through-chapter_2", "smaller edition only reports the newest larger edition save")
	s.check(FileAccess.get_sha256(ch1_store.path) == ch1_hash, "reporting a newer save does not modify it")
	_write_text(ROOT.path_join("runs/through-ch1_kasa/slot-1.json.newrun"), "{}")
	CampaignEdition.override_current(dev)
	var dev_store := RunSaveStore.new(ROOT.path_join("runs/demo-0.1/slot-1.json"))
	dev_store.validator = RunSnapshot.prepare
	var skipped := dev_store.find_other_editions(dev)
	s.check(skipped.has("data") and (skipped["edition"] as CampaignEdition).id == "through-chapter_2" and FileAccess.file_exists(ch1_store.path + ".newrun") and FileAccess.get_sha256(ch1_store.path) == ch1_hash, "pending transaction in another edition is never recovered from here")
	s.check(ch1_store.player_issue() == "" and _issue_store("x：一句原因").player_issue() == "一句原因", "player notice drops file path")

	# 章末路由：下一章不在本版本時停在完成卡，不接舊示範。
	var main: Node = load("res://game/main.gd").new()
	var demo := load("res://data/levels/level_01.tres") as LevelData
	CampaignEdition.override_current(ch1)
	s.check(main.call("_next_level", demo) == null, "release edition ends instead of entering a chapter it does not include")
	CampaignEdition.override_current(dev)
	var next: LevelData = main.call("_next_level", demo)
	s.check(next != null and next.resource_path == LEGACY, "development edition still follows the demo chain")
	main.free()
	CampaignEdition.override_current(null)
	_clear(ROOT)


static func _issue_store(issue: String) -> RunSaveStore:
	var store := RunSaveStore.new(ROOT.path_join("unused/slot-1.json"))
	store.issues.append(issue)
	return store


static func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


static func _clear(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_clear(path.path_join(sub))
	for file in dir.get_files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(file)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
