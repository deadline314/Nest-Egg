class_name EnemyScenarios
extends RefCounted
## 角色外觀與第二批敵人的截圖情境登記（NE-44、NE-46～48、NE-70）。
## 用法：screenshot.tscn -- --out=<資料夾> --scenario=<名稱>；新增情境只要在 SCENARIOS 加一行。

const SCENARIOS := {
	"characters": "res://tools/scenarios/characters_scenario.gd",
	"recon_enemies": "res://tools/scenarios/recon_scenario.gd",
	"heavy_enemies": "res://tools/scenarios/heavy_scenario.gd",
	"assault_enemies": "res://tools/scenarios/assault_scenario.gd",
	"placement": "res://tools/scenarios/placement_scenario.gd",
	"rin_damage": "res://tools/scenarios/rin_damage_scenario.gd",
	"rin_fit": "res://tools/scenarios/rin_fit_scenario.gd",
	"rin_light": "res://tools/scenarios/rin_light_scenario.gd",
	"rin_perf": "res://tools/scenarios/rin_perf_scenario.gd",
	"light_audit": "res://tools/scenarios/light_audit_scenario.gd",
	"scene_packs": "res://tools/scenarios/scene_pack_scenario.gd",
	"enemy_vfx": "res://tools/scenarios/enemy_vfx_scenario.gd",
	"cast_lineup": "res://tools/scenarios/cast_lineup_scenario.gd",
	"hit_reaction": "res://tools/scenarios/hit_reaction_scenario.gd",
	"hit_direction": "res://tools/scenarios/hit_direction_scenario.gd",
	"hurt_parts": "res://tools/scenarios/hurt_parts_scenario.gd",
	"machine_hit": "res://tools/scenarios/machine_hit_scenario.gd",
	"enemy_flow": "res://tools/scenarios/enemy_flow_scenario.gd",
	"phone_booth": "res://tools/scenarios/phone_booth_scenario.gd",
	"hit_materials": "res://tools/scenarios/hit_materials_scenario.gd",
	"weapon_feel": "res://tools/scenarios/weapon_feel_scenario.gd",
	"melee_combo": "res://tools/scenarios/melee_combo_scenario.gd",
	"block_feel": "res://tools/scenarios/block_feel_scenario.gd",
	"feel_lab": "res://tools/scenarios/feel_lab_scenario.gd",
	"dev_menu": "res://tools/scenarios/dev_menu_scenario.gd",
	"sound_lab": "res://tools/scenarios/sound_lab_scenario.gd",
	"sound_lab_hits": "res://tools/scenarios/sound_lab_hits_scenario.gd",
	"sound_lab_world": "res://tools/scenarios/sound_lab_world_scenario.gd",
	"screen_fx": "res://tools/scenarios/screen_fx_scenario.gd",
	"damage_numbers": "res://tools/scenarios/damage_numbers_scenario.gd",
	"model_vehicle": "res://tools/scenarios/model_vehicle_scenario.gd",
}


static func has_scenario(scenario: String) -> bool:
	return SCENARIOS.has(scenario)


## 執行情境（節點加到 host 底下，跑完移除）。
static func run(host: Node, scenario: String, out_dir: String) -> void:
	var script := load(str(SCENARIOS[scenario])) as GDScript
	var runner := script.new() as ScenarioBase if script != null else null
	if runner == null:
		push_error("[EnemyScenarios] 無法載入情境腳本：%s" % SCENARIOS[scenario])
		return
	runner.out_dir = out_dir
	host.add_child(runner)
	await runner.run()
	runner.queue_free()
