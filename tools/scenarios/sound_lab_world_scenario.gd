class_name SoundLabWorldScenario
extends ScenarioBase
## 截圖情境（NE-169）：音效實驗室的畫面舞台執行機關、電話亭、暫停選單、環境音與音樂情境。
## 用法：screenshot.tscn -- --out=<資料夾> --scenario=sound_lab_world

func run() -> void:
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var lab := SoundLab.new()
	lab.doc_path = "user://scenario_placements.md"
	DirAccess.copy_absolute(ProjectSettings.globalize_path(PlacementDoc.PATH), ProjectSettings.globalize_path(lab.doc_path))
	add_child(lab)
	await lab.stage().wait_ready()
	await wait(1.0)
	lab.tabs.current_tab = lab.tabs.get_tab_idx_from_control(lab.scenes_tab)
	for entry: Array in [["env_phone_call", 2.2, "lab_phone"], ["env_power", 1.0, "lab_power"], ["ui_pause_menu", 1.2, "lab_menu"], ["amb_rooftop", 3.0, "lab_ambience"], ["music_boss_warden", 3.5, "lab_boss_music"]]:
		lab.scenes_tab.select_scene(entry[0])
		lab.dock.play_scene(entry[0])
		await wait(float(entry[1]))
		capture(entry[2])
		lab.dock.stop()
		await wait(0.5)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(lab.doc_path))
	await finish()
