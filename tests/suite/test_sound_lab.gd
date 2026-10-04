class_name SoundLabSuite
extends TestSuite
## 音效實驗室（NE-162）：只能從命令列開、遊戲流程進不去；位置分頁的挑選與位置清單文件雙向連動（寫回、外部修改偵測、
## 手動放入勾選、跨類別搜尋）；即時試玩、背景音樂、混音分頁都能用；每個控制項都有 tooltip；缺預聽檔不崩潰。

const LAB_SCENE := "res://tools/sound_lab/sound_lab.tscn"
const COPY_PATH := "user://test_audio_lab_placements.md"
## 測試用的版面比例檔（檔名含 test_audio_，故意寫壞時的錯誤記錄不算失敗）。
const LAYOUT_PATH := "user://test_audio_lab_layout.cfg"

var _fake_previews: PackedStringArray = []  ## 測試自己建立的空預聽檔（收尾時刪掉；本機真有的預聽檔不動）
var _created_audition_dir := false


func run() -> void:
	_test_not_reachable_from_the_game()
	_test_layout_store()
	await _test_lab()
	_cleanup()


func _script_paths(dir: String, into: PackedStringArray) -> void:
	for sub in DirAccess.get_directories_at(dir):
		if not sub.begins_with("."):
			_script_paths(dir.path_join(sub), into)
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd") or file.ends_with(".tscn") or file.ends_with(".tres"):
			into.append(dir.path_join(file))


func _test_not_reachable_from_the_game() -> void:
	var paths := PackedStringArray()
	for dir in ["res://game", "res://ui", "res://autoload", "res://core", "res://scenes", "res://data"]:
		_script_paths(dir, paths)
	var leaked := PackedStringArray()
	for path in paths:
		var text := FileAccess.get_file_as_string(path)
		if text.contains("tools/sound_lab") or text.contains("SoundLab"):
			leaked.append(path)
	check(leaked.is_empty(), "the sound lab is not referenced by game files: %s" % ", ".join(leaked))
	check(not String(ProjectSettings.get_setting("application/run/main_scene", "")).contains("sound_lab"), "the sound lab is not the main scene")


func _cleanup() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(COPY_PATH))
	_remove_fake_previews()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LAYOUT_PATH))


func _remove_fake_previews() -> void:
	for path in _fake_previews:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_fake_previews.clear()
	if _created_audition_dir:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AudioCatalog.AUDITION_DIR))
		_created_audition_dir = false


## 讓這些素材「有預聽檔」（只補沒有的）：清單只列有預聽檔的素材，測試不能依賴本機有沒有預聽檔（CI 一個都沒有）。
func _ensure_previews(catalog: AudioCatalog, ids: Array) -> void:
	var dir := ProjectSettings.globalize_path(AudioCatalog.AUDITION_DIR)
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
		_created_audition_dir = true
	for id: String in ids:
		if catalog.has_preview(id):
			continue
		var file := FileAccess.open(catalog.preview_path(id), FileAccess.WRITE)
		if file != null:
			file.close()
			_fake_previews.append(catalog.preview_path(id))


## 把預聽檔暫時移開（本機真有的也一樣），回傳移開後的路徑；沒有預聽檔時回傳空字串。
func _stash_preview(catalog: AudioCatalog, id: String) -> String:
	var path := catalog.preview_path(id)
	if not FileAccess.file_exists(path):
		return ""
	var stash := path + ".test_stash"
	DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(stash))
	return stash


func _unstash_preview(catalog: AudioCatalog, id: String, stash: String) -> void:
	if not stash.is_empty():
		DirAccess.rename_absolute(ProjectSettings.globalize_path(stash), ProjectSettings.globalize_path(catalog.preview_path(id)))


func _list_texts(list: ItemList) -> PackedStringArray:
	var texts := PackedStringArray()
	for i in list.item_count:
		texts.append(list.get_item_text(i))
	return texts


## 清單裡所有素材項目的編號（不含說明用的停用項目）。
func _list_ids(list: ItemList) -> PackedStringArray:
	var ids := PackedStringArray()
	for i in list.item_count:
		if list.get_item_metadata(i) != null:
			ids.append(str(list.get_item_metadata(i)))
	return ids


func _write_layout_file(text: String) -> void:
	var file := FileAccess.open(LAYOUT_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


## 版面比例存檔：寫入後可還原；沒有檔、損毀、超出範圍都退回預設，不崩潰。
func _test_layout_store() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LAYOUT_PATH))
	var layout := SoundLabLayout.new(LAYOUT_PATH)
	check(is_equal_approx(layout.ratio("rows", 0.5), 0.5), "a missing layout file falls back to the default ratio")
	layout.set_ratio("rows", 0.3)
	layout.set_ratio("cols", 5.0)
	layout.set_ratio("nan", NAN)
	check(layout.is_dirty() and is_equal_approx(layout.ratio("cols", 0.4), 0.9), "an oversized ratio is clamped to the allowed range")
	check(is_equal_approx(layout.ratio("nan", 0.4), 0.4), "a NaN ratio is ignored")
	layout.flush()
	check(not layout.is_dirty(), "flushing clears the dirty flag")
	check(is_equal_approx(SoundLabLayout.new(LAYOUT_PATH).ratio("rows", 0.5), 0.3), "a saved ratio is restored")
	_write_layout_file("this is [not a config file")
	check(is_equal_approx(SoundLabLayout.new(LAYOUT_PATH).ratio("rows", 0.5), 0.5), "a corrupt layout file falls back to the default ratio")
	_write_layout_file("[split_ratios]
rows=\"wide\"
cols=7.5
ok=0.25
")
	var partly := SoundLabLayout.new(LAYOUT_PATH)
	check(is_equal_approx(partly.ratio("rows", 0.5), 0.5) and is_equal_approx(partly.ratio("cols", 0.4), 0.4), "non-numeric and out-of-range ratios fall back to the default")
	check(is_equal_approx(partly.ratio("ok", 0.5), 0.25), "a valid ratio next to broken ones is still read")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LAYOUT_PATH))


func _tooltip_gaps(node: Node, into: PackedStringArray) -> void:
	if node is Button or node is LineEdit or node is OptionButton or node is CheckBox or node is Slider or node is ItemList:
		if (node as Control).tooltip_text.is_empty():
			into.append("%s (%s)" % [node.name, node.get_class()])
	for child in node.get_children():
		_tooltip_gaps(child, into)


func _test_lab() -> void:
	DirAccess.copy_absolute(ProjectSettings.globalize_path(PlacementDoc.PATH), ProjectSettings.globalize_path(COPY_PATH))
	var lab := (load(LAB_SCENE) as PackedScene).instantiate() as SoundLab
	lab.doc_path = COPY_PATH
	lab.stage_enabled = false
	lab.layout_path = LAYOUT_PATH
	runner.get_tree().root.add_child(lab)
	await frames(3)
	_ensure_previews(lab.catalog, lab.catalog.slot("P-WPN-001")["candidates"] + lab.catalog.search("rain", "", 100000))
	check(lab.catalog.is_loaded() and lab.doc.slot_ids().size() == lab.catalog.slots.size(), "the lab loads the catalog and the placement list")
	var gaps := PackedStringArray()
	_tooltip_gaps(lab, gaps)
	check(gaps.is_empty(), "every control has a tooltip: %s" % ", ".join(gaps.slice(0, 5)))

	# ---- 位置分頁：左欄上下各約一半，分隔可拖、比例會記住
	var tab := lab.slots_tab
	var top_height: float = (tab._rows.get_child(0) as Control).size.y
	var bottom_height: float = (tab._rows.get_child(1) as Control).size.y
	check(tab._rows.is_ancestor_of(tab._candidate_list) and tab._rows.is_ancestor_of(tab._slot_list), "the slot list and the candidates share the left column")
	check(top_height > 0.0 and absf(top_height - bottom_height) <= 0.15 * (top_height + bottom_height), "the slot list and the candidates each take about half the height (%.0f / %.0f)" % [top_height, bottom_height])
	var offset := int(tab._rows.size.y * 0.2)
	tab._rows.split_offset = offset
	tab._rows.dragged.emit(offset)
	await frames(2)
	check(tab._rows.get_child(0).size.y > top_height, "dragging the divider down gives the slot list more height")
	check(lab.layout.is_dirty() and lab.layout.ratio("slots_left_rows", 0.5) > 0.6, "the dragged ratio is remembered")
	lab.layout.flush()
	check(SoundLabLayout.new(LAYOUT_PATH).ratio("slots_left_rows", 0.5) > 0.6, "the dragged ratio survives a restart")
	# 視窗變大時兩邊一起變大（清單多顯示列數），不是等比放大畫面。
	var tall: float = (tab._rows.get_child(1) as Control).size.y
	tab._rows.size.y += 200.0
	await frames(2)
	check(tab._rows.get_child(1).size.y > tall, "a taller window gives the candidate list more room")

	# ---- 位置分頁：挑選寫回文件
	check(tab._slot_list.item_count == lab.catalog.slots.size(), "the slot list shows every slot (%d)" % tab._slot_list.item_count)
	tab._domain.select(1)
	tab._domain.item_selected.emit(1)
	check(tab._slot_list.item_count > 0 and tab._slot_list.item_count < lab.catalog.slots.size(), "the domain filter narrows the list")
	tab._domain.select(0)
	tab._domain.item_selected.emit(0)
	tab._search.text = "手槍射擊"
	tab._search.text_changed.emit(tab._search.text)
	check(tab._slot_list.item_count >= 1, "searching by name finds the slot")
	tab.select_slot("P-WPN-001")
	check(tab.selected_slot() == "P-WPN-001" and tab._title.text.contains("手槍射擊"), "selecting a slot shows its title")
	check(tab._candidate_list.item_count >= 10, "a slot offers at least ten candidates (%d)" % tab._candidate_list.item_count)
	check(tab._current_list.item_count >= 1, "the current assets are listed")

	# ---- 並排顯示：遊戲現在用 vs 預計換成（NE-181）
	var current_text := "
".join(_list_texts(tab._current_list))
	check(current_text.contains("GUN-0031") and current_text.contains("A_42P.wav"), "the current list shows the id, the file name and the pack in full")
	lab.catalog.assets["GUN-9991"] = {"pack": "clips_sfx", "file": "GUN-9991.wav", "dur": 0.5, "parent": "GUN-0031", "start": 1.0, "end": 1.5}
	check(lab.asset_line("GUN-9991").contains("擷取自 GUN-0031") and lab.asset_detail("GUN-9991").contains("1.00–1.50") and lab.asset_detail("GUN-9991").contains("A_42P.wav"), "a clip is described by its source asset and range")
	check(lab.asset_detail("GUN-0000").contains("找不到") and lab.asset_detail("GUN-0031").contains("A_42P.wav"), "unknown ids are said to be missing and normal assets show their file")
	lab.doc.set_planned("P-WPN-001", PackedStringArray(["GUN-0020", "GUN-9991", "GUN-8888"]))
	tab.refresh()
	tab.select_slot("P-WPN-001")
	var planned_texts := _list_texts(tab._planned_list)
	check(planned_texts.size() == 3 and planned_texts[1].contains("擷取自") and planned_texts[2].contains("找不到"), "the planned list shows every planned asset, clips with their source and unknown ids marked")
	check(planned_texts[0].contains("沒有預聽檔") == not lab.catalog.has_preview("GUN-0020") and planned_texts[1].contains("沒有預聽檔"), "assets without a preview stay listed and are marked")
	var slot_line := ""
	for i in tab._slot_list.item_count:
		if tab._slot_list.get_item_text(i).contains("P-WPN-001"):
			slot_line = tab._slot_list.get_item_text(i)
	check(slot_line.contains("GUN-0020") and slot_line.contains("共 3"), "the slot list shows the planned asset (%s)" % slot_line)
	lab.doc.set_planned("P-WPN-001", PackedStringArray())
	tab.refresh()
	tab.select_slot("P-WPN-001")
	check(tab._planned_list.item_count == 1 and tab._planned_list.is_item_disabled(0) and tab._planned_list.get_item_text(0).contains("還沒挑"), "an empty plan says so")
	tab.compare_gap = 0.05
	check(not await tab.compare_current_and_planned() and lab.status_label.text.contains("還沒有預計使用"), "comparing without a plan only explains")
	lab.doc.set_planned("P-WPN-001", PackedStringArray(["GUN-0031"]))
	tab.refresh()
	tab.select_slot("P-WPN-001")
	check(await tab.compare_current_and_planned() == lab.catalog.has_preview("GUN-0031"), "comparing plays the game's sound, then the planned asset")
	lab.audition.stop()
	Sfx.stop_all()
	lab.catalog.assets.erase("GUN-9991")
	lab.doc.set_planned("P-WPN-001", PackedStringArray())
	tab.refresh()
	tab.select_slot("P-WPN-001")
	tab._candidate_list.select(2)
	tab._candidate_list.select(3, false)
	var picked := tab.selected_assets()
	check(picked.size() == 2, "multi-select picks two candidates")
	tab._pick(false)
	check(lab.doc.planned("P-WPN-001") == picked, "picking writes the plan to the document")
	var reread := PlacementDoc.new()
	reread.load_doc(COPY_PATH)
	check(reread.planned("P-WPN-001") == picked, "the file on disk has the plan")
	check(tab._slot_list.get_item_text(tab._slot_list.get_selected_items()[0]).contains("★"), "the slot list marks slots that have a plan")
	tab._candidate_list.deselect_all()
	tab._candidate_list.select(5)
	tab._pick(true)
	check(lab.doc.planned("P-WPN-001").size() == 3, "adding appends to the plan")
	tab._manual_check.button_pressed = true
	check(lab.doc.is_manual("P-WPN-001"), "ticking 'placed by hand' writes the checkbox")
	tab._manual_check.button_pressed = false
	check(not lab.doc.is_manual("P-WPN-001"), "unticking clears it")
	tab._on_planned_submitted("GUN-0001、IMP-0002 GUN-9999")
	check(lab.doc.planned("P-WPN-001") == PackedStringArray(["GUN-0001", "IMP-0002"]), "typing ids writes the known ones and skips unknown ids, in any category")
	tab._write_planned(PackedStringArray())
	check(lab.doc.planned("P-WPN-001").is_empty(), "clearing empties the plan")

	# ---- 跨類別搜尋
	tab._search_edit.text = "rain"
	tab._search_edit.text_changed.emit("rain")
	check(tab._search_list.item_count > 0, "the global search finds assets by pack or file name")
	var categories := {}
	for i in tab._search_list.item_count:
		categories[str(tab._search_list.get_item_metadata(i)).split("-")[0]] = true
	check(categories.size() >= 2, "an unfiltered search crosses categories (%s)" % [categories.keys()])
	tab._result_tabs.current_tab = 1
	tab._search_list.select(0)
	tab._pick(false)
	check(lab.doc.planned("P-WPN-001").size() == 1 and not str(lab.doc.planned("P-WPN-001")[0]).begins_with("GUN-"), "a search result from another category can be picked for a gun slot")
	tab._write_planned(PackedStringArray())
	tab._result_tabs.current_tab = 0

	# ---- 沒有預聽檔的素材不列出（備選、搜尋、目前用的），預計使用不受影響；補回就出現
	var victim := str((lab.catalog.slot("P-WPN-001")["candidates"] as Array)[0])
	tab._on_planned_submitted(victim)
	var stash := _stash_preview(lab.catalog, victim)
	check(not lab.catalog.has_preview(victim), "the test can take a preview away")
	tab.select_slot("P-WPN-001")
	check(not _list_ids(tab._candidate_list).has(victim), "a candidate without a preview is not listed")
	check(tab._candidate_list.item_count >= 1 and tab._candidate_list.get_item_text(0).contains("build_candidates") and tab._candidate_list.is_item_disabled(0), "the list says how many are hidden and how to build the previews")
	tab._search_edit.text = victim
	tab._search_edit.text_changed.emit(victim)
	check(not _list_ids(tab._search_list).has(victim) and tab._search_list.get_item_text(0).contains("1 個"), "searching for its id does not list it, and the hidden count is shown")
	for list: ItemList in [tab._current_list, tab._candidate_list, tab._search_list]:
		for aid in _list_ids(list):
			check(lab.catalog.has_preview(aid), "every listed asset has a preview (%s)" % aid)
	check(lab.doc.planned("P-WPN-001") == PackedStringArray([victim]) and tab._planned_edit.text == victim, "the planned use is kept even when its preview is missing")
	var on_disk := PlacementDoc.new()
	on_disk.load_doc(COPY_PATH)
	check(on_disk.planned("P-WPN-001") == PackedStringArray([victim]), "the placement document still lists it")
	_unstash_preview(lab.catalog, victim, stash)
	tab.select_slot("P-WPN-001")
	tab._fill_search()
	check(_list_ids(tab._candidate_list).has(victim) and _list_ids(tab._search_list).has(victim), "once the preview is back the asset is listed again")
	tab._write_planned(PackedStringArray())
	tab._search_edit.text = "rain"
	tab._search_edit.text_changed.emit("rain")

	# ---- 來源顯示與音量微調（只預覽，不動真正的資料檔）
	tab.select_slot("P-WPN-001")
	check(tab._source.text.contains("音效檔") and tab._source.text.contains("CC0"), "the slot shows its source, license pack and length: %s" % tab._source.text)
	tab.select_slot("P-ENV-013")
	check(tab._source.text.contains("合成音"), "a synthesized sound is labelled as such")
	tab.select_slot("P-WPN-001")
	var original_volume := Sfx.bank().volume_db(&"shot_pistol")
	tab._volume_slider.value = original_volume + 3.0
	check(is_equal_approx(Sfx.bank().volume_db(&"shot_pistol"), original_volume + 3.0), "dragging the volume slider takes effect immediately")
	var volume_preview := tab.save_volume(true)
	check((volume_preview["diff"] as PackedStringArray).size() == 1, "the volume preview lists one difference")
	Sfx.bank().all_defs()["shot_pistol"]["volume_db"] = original_volume
	tab.select_slot("P-BGM-004")
	check(tab._source.text.contains("音樂檔") and not tab._volume_slider.editable, "music slots point to the music tab for volume")

	# ---- 與文件即時連動：外部修改
	check(not lab.sync_now(), "no reload when nothing changed")
	var text := FileAccess.get_file_as_string(COPY_PATH)
	var lines := text.split("\n")
	for i in lines.size():
		if lines[i].begins_with("| P-HIT-001 |"):
			var cells := PlacementDoc._split(lines[i])
			cells[PlacementDoc.COL_PLANNED] = "IMP-0007"
			cells[PlacementDoc.COL_MANUAL] = "[x]"
			lines[i] = "| " + " | ".join(cells) + " |"
	OS.delay_msec(1100)
	var file := FileAccess.open(COPY_PATH, FileAccess.WRITE)
	file.store_string("\n".join(lines))
	file.close()
	check(lab.sync_now(), "an outside edit is picked up")
	check(lab.doc.planned("P-HIT-001") == PackedStringArray(["IMP-0007"]) and lab.doc.is_manual("P-HIT-001"), "the lab sees the outside edit")
	check(lab.status_label.text.contains("重新載入"), "the status line says the document was reloaded")
	tab.select_slot("P-HIT-001")
	check(tab._manual_check.button_pressed and tab._planned_edit.text.contains("IMP-0007"), "the detail panel shows the reloaded values")

	# ---- 試聽（空的假預聽檔放不出聲音，先移除；之後只剩本機真有的預聽檔）
	_remove_fake_previews()
	var has_preview := lab.catalog.has_preview("GUN-0031")
	check(lab.audition_asset("GUN-0031") == has_preview, "auditioning plays the preview when it exists")
	check(not lab.audition_asset("GUN-9999") and lab.status_label.text.contains("build_candidates"), "a missing preview explains how to make it, without failing")
	lab.audition.stop()

	# ---- 即時試玩
	var live := lab.live_tab
	check(live.play_character("grunt", &"death") != &"" and live.play_character("player", &"hurt") == &"hurt", "the character buttons resolve and play sounds")
	check(live.play_character("test_audio_no_such_enemy", &"death") == &"kill_enemy", "an unknown character plays the default")
	check(live.play_weapon_kind("pistol", &"reload_start") == &"reload_start_pistol" and live.play_weapon_kind("laser", &"reload_start") == &"reload_start_energy", "switching weapons changes the reload sound")
	check(await live.play_weapon_fire("rifle", 1) == &"shot_rifle", "the weapon button plays its fire sound")
	check(is_equal_approx(live.fire_rate(), 1.0), "the fire rate multiplier starts at 1")
	live._fire_rate.select(live._fire_rate.item_count - 1)
	check(is_equal_approx(live.fire_rate(), 2.0) and await live.play_weapon_fire("spread", 2) == &"shot_spread", "a faster fire rate still plays the weapon's sound, with a shorter gap")
	live._fire_rate.select(0)
	check(live.play_material("metal") == &"mat_metal" and live.play_material("weak") == &"hit_weak", "materials resolve to their events")
	live.play_named(&"explosion")
	live.play_land("metal")
	check(live._result.text.contains("metal"), "the result line reports what was played")
	check(Footsteps.name_for(&"metal", &"step") != Footsteps.name_for(&"wet", &"step"), "different ground gives different steps")

	# ---- 背景音樂與環境音
	var music := lab.music_tab
	music.select_cue("calm_rooftop")
	check(music.play_selected() == (Music.cue_def(&"calm_rooftop").size() > 0), "a cue can be played from the lab")
	check(music.seek_to_seam(), "jumping near the end of the loop works while a cue plays")
	music._zone.select(music._zone_ids().find("hangar"))
	music._state.select(Music.STATES.find("boss"))
	check(music.simulate() == &"boss_warden", "the simulator reports the boss cue for the hangar")
	music.select_cue("calm_rooftop")
	var cue_volume := float(Music.cue_def(&"calm_rooftop").get("volume_db", 0.0))
	music._cue_volume.value = cue_volume + 2.0
	check(is_equal_approx(float(Music.cue_def(&"calm_rooftop")["volume_db"]), cue_volume + 2.0), "the cue volume slider takes effect immediately")
	check((music.save_cue(true)["diff"] as PackedStringArray).size() == 1, "the cue preview lists one difference")
	Music._cues["calm_rooftop"]["volume_db"] = cue_volume

	# 備選曲目：選中 cue 後列出它那首曲子的備選；沒有預聽檔的不列出（不論本機有沒有預聽檔都要成立）。
	music.select_cue("calm_rooftop")
	var music_slot := music.slot_for_cue("calm_rooftop")
	check(str(music_slot.get("id", "")) == "P-BGM-004", "a cue finds the slot of its track")
	check(music.candidate_ids("calm_rooftop").size() >= 10, "a music cue has at least ten candidate tracks")
	check(music._candidate_list.item_count <= music.candidate_ids("calm_rooftop").size(), "the candidate list never shows more than the slot has")
	if music._candidate_list.item_count < music.candidate_ids("calm_rooftop").size():
		check(music._candidate_note.text.contains("build_candidates"), "hidden candidates are explained with how to build the previews")
	check(not music.audition_candidate() and not music.pick_candidate(), "auditioning or picking with nothing selected is refused without failing")
	var first_candidate := music.candidate_ids("calm_rooftop")[0]
	music._candidate_list.add_item("test_audio_candidate")
	music._candidate_list.set_item_metadata(music._candidate_list.item_count - 1, first_candidate)
	music._candidate_list.select(music._candidate_list.item_count - 1)
	check(music.pick_candidate() and lab.doc.planned("P-BGM-004") == PackedStringArray([first_candidate]), "picking a candidate writes the planned track to the placement document")
	lab.audition.stop()
	music._cue_list.deselect_all()
	music._fill_candidates()
	check(music._candidate_list.item_count == 0 and music._candidate_note.text.contains("沒有位置登記"), "a cue without a slot shows an explanation instead of candidates")

	music.play_ambience()
	music.show_now_playing()
	check(music._info.text.contains("calm_rooftop"), "the now-playing line names the cue")
	Music.stop(0.0)
	Ambience.stop_all(0.0)

	# ---- 混音與診斷
	check(lab.mixer_tab.update_diagnostics().contains("同時發聲"), "the diagnostics line reports voices")
	lab.mixer_tab._process(0.1)
	# 收尾：停掉還在播的聲音，程式結束時才不會留下播放實例。
	Sfx.stop_all()
	lab.audition.stop()
	lab.queue_free()
	await frames(2)
