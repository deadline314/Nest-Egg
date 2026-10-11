extends RefCounted
## NE-233～235：章節逐區稽核（ChapterAudit）。既有 PacingSuite 負責註冊及執行。
## 守住的規則：每個區域從章節入口走得到、上鎖的出入口都有會解開它的來源、每章至少一個迴圈（不是單線走廊）、
## 復原點與出入口之間不會隔太遠、場景合理性沒有錯誤。整章太短與占位素材只列在報告與票上，不在這裡擋。


static func run(suite: TestSuite) -> void:
	_test_graph_rules(suite)
	_test_real_chapters(suite)


## 連結圖的計算本身：用正式第一章的區域，換掉入口看走不到的區域會被找出來。
static func _test_graph_rules(s: TestSuite) -> void:
	var index := QuestMapIndex.for_chapter(&"ch1_kasa")
	var paths: Array = index.areas.keys()
	var alias := CampaignLedger._layout_aliases(paths)
	var normal := ChapterAudit._graph(index, paths, alias, "res://data/levels/ch1_prologue.tres")
	s.check(normal["unreachable"].is_empty() and int(normal["areas"]) > 0, "every chapter-one area is reachable from the prologue: %s" % [normal["unreachable"]])
	var nowhere := ChapterAudit._graph(index, paths, alias, "res://data/levels/no_such_area.tres")
	s.check(nowhere["unreachable"].size() == int(nowhere["areas"]), "an entry outside the chapter reaches nothing, and every area is reported")
	var writers := ChapterAudit.flag_writers()
	s.check(writers.has("ch2_sc1_open") and writers.has("ledger_disk_obtained") and not writers.has(""), "flag writers come from story results, story items and level data")


static func _test_real_chapters(s: TestSuite) -> void:
	var chapters := 0
	for chapter: Dictionary in CampaignLedger.build()["chapters"]:
		chapters += 1
		var result := ChapterAudit.audit(StringName(chapter["id"]))
		var id: String = result["id"]
		var errors: Array = result["findings"].filter(func(f: Dictionary) -> bool: return f["level"] == "error")
		s.check(errors.is_empty(), "%s: no unreachable areas, unopenable locks or scene errors: %s" % [id, errors])
		s.check(int(result["graph"]["loops"]) >= 1, "%s: the area map has at least one loop, not a single corridor (%d)" % [id, result["graph"]["loops"]])
		var far: Array = result["findings"].filter(func(f: Dictionary) -> bool: return f["kind"] == "checkpoint")
		s.check(far.is_empty(), "%s: respawn points, starts and exits are never more than %d tiles apart: %s" % [id, ChapterAudit.MAX_CHECKPOINT_GAP_TILES, far])
		for exit: Dictionary in result["locked_exits"]:
			s.check(exit["written"], "%s: the lock %s on the way to %s can be opened" % [id, exit["flag"], exit["to"]])
	s.check(chapters >= 3, "the audit covers every campaign chapter with areas (%d)" % chapters)
