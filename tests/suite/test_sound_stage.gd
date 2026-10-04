class_name SoundStageSuite
extends StageSuiteBase
## 實驗室的畫面舞台與情境（NE-166）：情境資料完整、動作存在、每個情境真的會響出對應位置的聲音、取消與備選素材暫時替換不留痕跡。



func run() -> void:
	_catalog.load_all()
	_test_scene_data()
	_test_input_lock()
	_test_sound_helpers()
	await _open_stage()
	await _check_slot_scenes(PackedStringArray(), true)
	await _test_cancel_and_replace()
	await _test_preview_replacement()
	await _close_stage()
	await _test_lab_with_stage()


## 輸入鎖：鎖住時遊戲動作沒有實體按鍵，放開後完全還原（包含順序與內容）。
func _test_input_lock() -> void:
	var before := {}
	for action in [&"shoot", &"move_right", &"reload", &"aim_right"]:
		before[action] = InputMap.action_get_events(action).duplicate()
	var lock := StageInputLock.new()
	lock.lock()
	lock.lock()
	check(lock.is_locked() and InputMap.action_get_events(&"shoot").is_empty() and InputMap.action_get_events(&"move_right").is_empty(), "locking removes the real keys from the game actions")
	check(InputMap.has_action(&"ui_accept") and not InputMap.action_get_events(&"ui_accept").is_empty(), "the lab's own interface keys are untouched")
	lock.unlock()
	var same := true
	for action: StringName in before.keys():
		var now := InputMap.action_get_events(action)
		same = same and now.size() == (before[action] as Array).size()
		for i in now.size():
			same = same and now[i].is_match((before[action] as Array)[i])
	check(not lock.is_locked() and same, "unlocking restores every action's keys exactly")


## 音效長度與錄音訊號。
func _test_sound_helpers() -> void:
	check(Sfx.sound_length(&"shot_pistol") > 0.2, "a sound's length is its longest variant")
	check(Sfx.sound_length(&"kill_enemy") >= Sfx.sound_length(&"kill"), "a sound event's length covers its layers")
	check(is_zero_approx(Sfx.sound_length(&"test_audio_no_such_sound")), "an unknown sound has no length")
	var heard: Array[StringName] = []
	var listener := func(id: StringName) -> void: heard.append(id)
	Sfx.sound_played.connect(listener)
	Sfx.play(&"hit", -80.0)
	Sfx.sound_played.disconnect(listener)
	check(heard == [&"hit"], "every sound that is played is announced")
	Sfx.stop_all()


func _test_scene_data() -> void:
	var scenes := StageScenes.shared()
	check(scenes.is_loaded(), "the scene catalog loads")
	var slot_ids: Array = _catalog.slots.map(func(slot: Dictionary) -> String: return str(slot["id"]))
	var errors := scenes.validate(slot_ids, StageActions.has_action)
	check(errors.is_empty(), "scene catalog has no errors: %s" % ", ".join(errors))
	check(StageActions.names().size() >= 6, "the stage knows its actions (%s)" % ", ".join(StageActions.names()))
	var broken := StageScenes.new("res://tests/fixtures/audio/no_such_scenes.json")
	check(not broken.is_loaded() and broken.ids().is_empty() and broken.scenes_for_slot("P-WPN-001").is_empty(), "a missing scene catalog reads as empty without failing")
	var bad := StageScenes.new("res://tests/fixtures/audio/scenes_bad.json")
	var bad_errors := bad.validate(["P-TEST-001", "P-TEST-002"], func(a: String) -> bool: return a == "fire")
	check(bad_errors.size() >= 4, "a broken catalog reports each problem (%d): %s" % [bad_errors.size(), " | ".join(bad_errors)])


func _test_cancel_and_replace() -> void:
	_stage.run_scene("wpn_fire_smg")
	await frames(10)
	var second_done: bool = await _stage.run_scene("wpn_equip_rifle")
	check(second_done, "a newer scene runs to the end")
	check(not _stage.running and not Input.is_action_pressed(&"shoot"), "a replaced scene leaves nothing held down")
	_stage.stop()
	check(not _stage.running and Sfx.preview_ids().is_empty(), "stopping leaves nothing running or replaced")
	_stage.set_free_play(true)
	check(_stage.is_free_play() and not InputMap.action_get_events(&"shoot").is_empty(), "free play gives the keyboard and mouse back")
	_stage.set_free_play(false)
	check(not _stage.is_free_play() and InputMap.action_get_events(&"shoot").is_empty(), "and locks them again")
	_stage.speed = 0.01
	check(is_equal_approx(_stage.speed, SoundStage.MIN_SPEED), "the speed cannot go below the minimum")
	_stage.speed = TEST_SPEED_UP / 3.0
	Engine.time_scale = TEST_SPEED_UP


func _test_preview_replacement() -> void:
	var stream := AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path("res://tests/fixtures/audio/tone_a.ogg"))
	var played := {}
	var seen := func(id: StringName) -> void: played[id] = Sfx.preview_ids().has(id)
	Sfx.sound_played.connect(seen)
	await _stage.run_scene("wpn_fire_pistol", {"shot_pistol": stream})
	Sfx.sound_played.disconnect(seen)
	check(played.get(&"shot_pistol", false), "the replaced sound is the one used while the scene runs")
	check(Sfx.preview_ids().is_empty(), "the replacement is gone after the scene")
	check(Sfx.source_of(&"shot_pistol") == &"file", "the real sound is untouched after the scene")


const COPY_PATH := "user://test_audio_stage_weapon_sounds.json"


func _tooltip_gaps(node: Node, into: PackedStringArray) -> void:
	if node is SoundStage:
		return  # 舞台裡面是遊戲本身的畫面，不是實驗室的控制項
	if node is Button or node is LineEdit or node is OptionButton or node is CheckBox or node is Slider or node is ItemList or node is SpinBox:
		if (node as Control).tooltip_text.is_empty() and not (node.get_parent() is SpinBox):
			into.append("%s (%s) under %s/%s" % [node.name, node.get_class(), node.get_parent().name, node.get_parent().get_parent().name if node.get_parent().get_parent() != null else ""])
	for child in node.get_children():
		_tooltip_gaps(child, into)


## 實驗室加上舞台：情境清單、位置分頁的畫面情境與備選素材試聽、換彈時間軸編輯器。
func _test_lab_with_stage() -> void:
	DirAccess.copy_absolute(ProjectSettings.globalize_path(PlacementDoc.PATH), ProjectSettings.globalize_path("user://test_audio_stage_placements.md"))
	DirAccess.copy_absolute(ProjectSettings.globalize_path(WeaponSounds.PATH), ProjectSettings.globalize_path(COPY_PATH))
	var lab := (load("res://tools/sound_lab/sound_lab.tscn") as PackedScene).instantiate() as SoundLab
	lab.doc_path = "user://test_audio_stage_placements.md"
	runner.get_tree().root.add_child(lab)
	await lab.stage().wait_ready()
	Engine.time_scale = TEST_SPEED_UP
	var gaps := PackedStringArray()
	_tooltip_gaps(lab, gaps)
	check(gaps.is_empty(), "every control of the lab with the stage has a tooltip: %s" % ", ".join(gaps.slice(0, 6)))
	# 情境清單
	var tab := lab.scenes_tab
	check(tab._list.item_count == StageScenes.shared().ids().size(), "the scene list shows every scene (%d)" % tab._list.item_count)
	tab.select_scene("wpn_reload_pistol")
	check(tab._slots.item_count == 3 and tab._title.text == "手槍換彈", "selecting a scene shows the slots it serves")
	tab._search.text = "終結"
	tab._search.text_changed.emit(tab._search.text)
	check(tab._list.item_count == 1, "the search narrows the scene list")
	tab._search.text = ""
	tab._search.text_changed.emit("")
	await tab.play_selected()
	check(lab.dock.stage.recorded_unique().has("reload_done_pistol"), "playing a scene from the list runs it on the stage")
	check(lab.dock._heard_label.text.contains("reload_start_pistol"), "the dock lists what actually sounded")
	# 位置分頁：畫面情境與備選素材試聽
	var slots := lab.slots_tab
	slots.select_slot("P-WPN-013")
	check(slots._scene_option.item_count == 1 and not slots._scene_option.disabled, "a slot with a scene offers it")
	check(await slots.play_in_stage(""), "a slot's scene plays on the stage")
	StageScenes.set_shared(StageScenes.new("res://tests/fixtures/audio/scenes_none.json"))
	slots.select_slot("P-HIT-001")
	check(slots._scene_option.item_count == 0 and slots._scene_note.text.contains("測試用的原因"), "a slot without a scene says why: %s" % slots._scene_note.text)
	check(not await slots.play_in_stage(""), "playing a slot without a scene is refused, not a crash")
	StageScenes.set_shared(null)
	slots.select_slot("P-WPN-001")
	check(not await slots.play_in_stage_with_candidate(), "trying a candidate with nothing selected is refused")
	slots._candidate_list.select(0)
	var with_preview := lab.catalog.has_preview(str(slots._candidate_list.get_item_metadata(0)))
	var tried: bool = await slots.play_in_stage_with_candidate()
	check(tried == with_preview, "trying a candidate needs its audition file; without one the lab says how to make it (%s)" % lab.status_label.text)
	check(Sfx.preview_ids().is_empty() and lab.doc.planned("P-WPN-001").is_empty(), "trying a candidate on stage changes nothing permanent")
	# 換彈時間軸編輯器
	var editor := lab.dock.reload_editor
	editor.data_path = COPY_PATH
	editor.set_weapon("pistol")
	check(editor.cues.size() == 3 and not editor.dirty, "the editor starts from the weapon's current timeline")
	editor._apply_preset([{"at": 0.0, "kind": "reload_start", "volume_db": -3.0}])
	check(ReloadCues.for_weapon(&"pistol").size() == 1 and editor.dirty, "a preset takes effect in the game immediately")
	await editor.play_in_stage()
	var heard := lab.dock.stage.recorded_unique()
	check(heard.has("reload_start_pistol") and not heard.has("reload_mid_pistol") and not heard.has("reload_done_pistol"), "a real reload on stage uses the edited one-part timeline: %s" % ", ".join(heard))
	editor.add_cue(0.5)
	check(editor.cues.size() == 2 and ReloadCues.for_weapon(&"pistol").size() == 2, "adding a part takes effect")
	editor._edit(1, "kind", "")
	editor._edit(1, "sound", "test_audio_no_such_sound")
	check(ReloadCues.for_weapon(&"pistol").size() == 2 and editor._warning.text.contains("不存在"), "a sound that does not exist is reported and not applied: %s" % editor._warning.text)
	editor._edit(1, "sound", "reload_mid_heavy")
	check(ReloadCues.sound_of(&"pistol", ReloadCues.for_weapon(&"pistol")[1]) == &"reload_mid_heavy", "a specific sound can replace a weapon's own")
	editor._on_cue_dragged(1, 0.8)
	check(is_equal_approx(ReloadCues.for_weapon(&"pistol")[1].at, 0.8), "dragging a marker moves the cue")
	var preview := editor.save(true)
	check((preview["errors"] as PackedStringArray).is_empty() and (preview["diff"] as PackedStringArray).size() == 1, "the preview lists one difference")
	check(FileAccess.get_file_as_string(COPY_PATH) == FileAccess.get_file_as_string(WeaponSounds.PATH), "the preview writes nothing")
	var saved := editor.save(false)
	check((saved["errors"] as PackedStringArray).is_empty() and (JSON.parse_string(FileAccess.get_file_as_string(COPY_PATH))["profiles"]["pistol"]["reload_cues"] as Array).size() == 2, "saving writes the timeline under the weapon's profile")
	check(not editor.dirty, "saving clears the unsaved mark")
	editor._apply_preset([])
	check(ReloadCues.for_weapon(&"pistol").is_empty(), "the silent preset empties the timeline")
	editor.revert()
	check(ReloadCues.for_weapon(&"pistol").size() == 3 and editor.cues.size() == 3 and not editor.dirty, "reverting restores the data file's timeline")
	for _i in 15:
		editor.add_cue(0.5)
	check(editor.cues.size() == ReloadCues.MAX_CUES, "the editor stops at the maximum number of parts")
	editor.revert()
	# 收合舞台不影響其他分頁
	lab.dock.set_shown(false)
	check(not lab.dock.visible, "the stage column can be hidden")
	lab.dock.set_shown(true)
	lab.dock.stop()
	Engine.time_scale = 1.0
	Sfx.stop_all()
	lab.queue_free()
	await frames(3)
	WeaponSounds.reload_data(true)
	for path in [COPY_PATH, COPY_PATH + ".bak", "user://test_audio_stage_placements.md"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
