extends RefCounted
## 必要故事物品的讀檔修復（NE-230）：依旗標補回、矛盾改用備份、規則檔損毀不擋讀檔。

const FIRST := "res://data/levels/ch1_pawnshop.tres"
const DISK := &"ch1_data_disk"


static func run(s: TestSuite) -> void:
	GameState.story_autosave = false
	GameState.start_new_run(GameState.difficulties[1])
	var base := RunSnapshot.capture(FIRST, {"position": [-1, -1], "health": 5, "world": {}, "loadout": {}})
	var missing := base.duplicate(true)
	missing["story"]["flags"]["ledger_disk_obtained"] = true
	var prepared := RunSnapshot.prepare(missing)
	var items: Dictionary = prepared.get("data", {}).get("story", {}).get("items", {})
	s.check(prepared.has("data") and items.get("held", []).has(DISK) and items.get("owned", []).has(DISK), "obtained but undelivered disk missing from save is restored as held")
	s.check(str(prepared.get("data", {}).get("notices", [""])[0]).contains("資料盤"), "player is told which item was restored")
	s.check(prepared.get("data", {}).get("level") == FIRST, "item repair keeps the saved area")
	var reloaded := RunSnapshot.prepare(JSON.parse_string(JSON.stringify(prepared["data"])))
	s.check(reloaded.has("data") and not reloaded["data"].has("notices"), "repaired save prepares again without a second repair")
	var delivered := base.duplicate(true)
	delivered["story"]["flags"]["ledger_disk_obtained"] = true
	delivered["story"]["flags"]["ch1_disk_delivered"] = true
	s.check(RunSnapshot.prepare(delivered).has("data") and not RunSnapshot.prepare(delivered)["data"]["story"]["items"]["held"].has(DISK), "delivered disk is not given back")
	var contradiction := delivered.duplicate(true)
	contradiction["story"]["items"]["owned"].append(String(DISK))
	contradiction["story"]["items"]["held"].append(String(DISK))
	var rejected := RunSnapshot.prepare(contradiction)
	s.check(str(rejected.get("error", "")).contains("ch1_data_disk") and str(rejected.get("error", "")).contains("ch1_disk_delivered"), "delivered yet still held is rejected so the backup is used, naming the field")
	var transferred := missing.duplicate(true)
	transferred["story"]["items"]["owned"].append(String(DISK))
	transferred["story"]["items"]["transferred"].append(String(DISK))
	s.check(RunSnapshot.prepare(transferred).has("error"), "transferred without delivery flag is rejected")
	var path := "user://ne230-required-items.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"items": [{"item": "x"}, {"item": "ch1_data_disk", "obtained_flag": "a"}, 3]}')
	file.close()
	var loaded := RequiredItemRepair.load_rules(path, false)
	s.check(loaded.size() == 1 and loaded[0]["delivered_flag"] == "", "damaged rule entries are skipped individually; missing delivered flag means never delivered")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	s.check(RequiredItemRepair.rules().size() >= 1, "checked-in rules load")
