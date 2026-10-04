class_name SoundLabHitsScenario
extends ScenarioBase
## 截圖情境（NE-167）：音效實驗室的畫面舞台執行命中、角色與移動情境（打頭部弱點、完美格擋、敵人出手、走路）。
## 用法：screenshot.tscn -- --out=<資料夾> --scenario=sound_lab_hits

func run() -> void:
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var lab := SoundLab.new()
	lab.doc_path = "user://scenario_placements.md"
	DirAccess.copy_absolute(ProjectSettings.globalize_path(PlacementDoc.PATH), ProjectSettings.globalize_path(lab.doc_path))
	add_child(lab)
	await lab.stage().wait_ready()
	await wait(1.0)
	lab.tabs.current_tab = lab.tabs.get_tab_idx_from_control(lab.scenes_tab)
	for entry: Array in [["hit_weak_point", 1.3, "lab_hit_weak"], ["guard_parry", 0.25, "lab_parry"], ["chr_behave_shock_hound", 4.0, "lab_enemy_behave"], ["mov_walk_metal", 1.0, "lab_walk"]]:
		lab.scenes_tab.select_scene(entry[0])
		lab.dock.play_scene(entry[0])
		await wait(float(entry[1]))
		capture(entry[2])
		lab.dock.stop()
		await wait(0.3)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(lab.doc_path))
	await finish()
