@abstract
class_name StageSuiteBase
extends TestSuite
## 畫面舞台測試的共用部分：開關舞台、逐個位置執行情境並驗證實際響出對應的聲音。

## 測試時把時間加速，情境跑得快；動作用的是秒，所以加速不影響邏輯。
const TEST_SPEED_UP := 3.0
## 對輸入時機敏感的動作（連段、衝上去終結）用比較慢的速度，其餘盡量加速。
## 材質靶只有 18 像素寬；三倍速的步槍每影格飛 32 像素，會跳過受擊框。命中驗證用正常遊戲速度。
const SLOW_ACTIONS := {"melee": 1.5, "finisher": 2.0, "shoot_target": 1.0}

var _stage: SoundStage
var _catalog := AudioCatalog.new()


func _open_stage() -> void:
	_stage = SoundStage.new()
	_stage.size = Vector2(640, 360)
	runner.add_child(_stage)
	await _stage.wait_ready()
	Engine.time_scale = TEST_SPEED_UP


func _close_stage() -> void:
	Engine.time_scale = 1.0
	_stage.stop()
	_stage.queue_free()
	await frames(3)
	check(not InputMap.action_get_events(&"shoot").is_empty(), "closing the stage gives the real keys back to the game")


## 每個有對應情境的位置：執行它的第一個情境，實際響出來的音效要包含位置的聲音。每個情境只跑一次。
## domains 不是空的就只檢查那些域（P-XXX-NNN 的 XXX）；one_per_action 為 true 時，每種動作只挑第一個用到它的情境（代表性抽查）。
func _check_slot_scenes(domains: PackedStringArray, one_per_action: bool) -> void:
	var scenes := StageScenes.shared()
	var results := {}
	var exercised := {}
	for entry: Dictionary in _catalog.slots:
		var slot_id := str(entry["id"])
		var slot := entry
		if not domains.is_empty() and not domains.has(str(slot["domain"])):
			continue
		var wanted := scenes.scenes_for_slot(slot_id)
		if wanted.is_empty():
			check(not scenes.slot_reason(slot_id).is_empty(), "%s without a scene explains why" % slot_id)
			continue
		var scene_id := wanted[0]
		var action := str(scenes.scene(scene_id)["action"])
		if not results.has(scene_id):
			if one_per_action and exercised.has(action):
				continue
			exercised[action] = true
			Engine.time_scale = float(SLOW_ACTIONS.get(action, TEST_SPEED_UP))
			var completed := await _stage.run_scene(scene_id)
			Engine.time_scale = TEST_SPEED_UP
			results[scene_id] = {"completed": completed, "sounds": _stage.recorded_unique()}
			check(completed, "scene %s runs to the end" % scene_id)
		if not results.has(scene_id):
			continue
		var sounds: PackedStringArray = results[scene_id]["sounds"]
		var candidates := _variants_of(str(slot["target"]))
		if bool(scenes.scene(scene_id).get("alternates", false)):
			# 輪流播的一組（三首戰鬥曲）：每次只會響其中一首，這個情境服務的位置裡有一個響到就算。
			for sibling in scenes.slots_for_scene(scene_id):
				candidates.append(str(_catalog.slot(sibling)["target"]))
		var heard := false
		for variant in candidates:
			heard = heard or sounds.has(variant)
		check(heard, "scene %s makes %s (%s) sound; heard: %s" % [scene_id, slot_id, slot["target"], ", ".join(sounds)])


## 一個音效在聲音事件的同一層裡輪流播的變體（命中聲 A／B／C 輪流響，一個情境不保證每個變體都響到）；沒有變體就只有它自己。
func _variants_of(id: String) -> PackedStringArray:
	var out := PackedStringArray([id])
	for event_id: Variant in Sfx.event_ids():
		var def: Dictionary = Sfx._events[event_id]
		for layer: Dictionary in def.get("layers", []):
			var variants: Array = layer.get("sounds", [])
			if variants.has(id):
				for variant: Variant in variants:
					out.append(str(variant))
	return out
