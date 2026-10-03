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
	"enemy_vfx": "res://tools/scenarios/enemy_vfx_scenario.gd",
	"cast_lineup": "res://tools/scenarios/cast_lineup_scenario.gd",
	"hit_reaction": "res://tools/scenarios/hit_reaction_scenario.gd",
	"hit_direction": "res://tools/scenarios/hit_direction_scenario.gd",
	"hurt_parts": "res://tools/scenarios/hurt_parts_scenario.gd",
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
