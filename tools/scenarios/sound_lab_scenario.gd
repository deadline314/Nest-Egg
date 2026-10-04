class_name SoundLabScenario
extends ScenarioBase
## 截圖情境（NE-166）：開音效實驗室，右側畫面舞台執行情境，拍位置分頁、情境清單與換彈時間軸。
## 用法：screenshot.tscn -- --out=<資料夾> --scenario=sound_lab

func run() -> void:
	# 實驗室用視窗的實際解析度（獨立開啟時它自己會這樣設），文字才讀得清楚。
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var lab := SoundLab.new()
	lab.doc_path = "user://scenario_placements.md"
	DirAccess.copy_absolute(ProjectSettings.globalize_path(PlacementDoc.PATH), ProjectSettings.globalize_path(lab.doc_path))
	add_child(lab)
	await lab.stage().wait_ready()
	await wait(1.0)
	# 情境清單 + 手槍換彈執行中。
	lab.tabs.current_tab = lab.tabs.get_tab_idx_from_control(lab.scenes_tab)
	lab.scenes_tab.select_scene("wpn_reload_pistol")
	lab.dock.play_scene("wpn_reload_pistol")
	await wait(0.55)
	capture("lab_stage_reload")
	await wait(1.2)
	capture("lab_stage_reload_done")
	# 改成一段（整段一個聲音）。
	lab.dock.reload_editor._apply_preset([{"at": 0.0, "sound": "reload_start_heavy", "volume_db": -3.0}])
	await wait(0.3)
	capture("lab_stage_one_part")
	# 位置分頁：選手槍射擊，用備選素材在畫面試。
	lab.tabs.current_tab = lab.tabs.get_tab_idx_from_control(lab.slots_tab)
	lab.slots_tab.select_slot("P-WPN-001")
	lab.slots_tab._candidate_list.select(1)
	lab.slots_tab.play_in_stage_with_candidate()
	await wait(0.5)
	capture("lab_stage_slots")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(lab.doc_path))
	await finish()
