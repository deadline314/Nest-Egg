class_name LightingSceneScenario
extends ScenarioBase
## 開發工具（BG-14）：光影預設放在代表性的場景背景上，量測玩家與敵人的輪廓對比。
## 對應表在 data/lighting_preview/scenes.json（預設 → 場景背景）；每組各截一張圖，並印出玩家與敵人對比與是否達門檻
## （門檻與算法見 ContrastProbe，與暗場可讀性量測一致）。背景圖還沒畫好的標「待背景」，不算失敗。
## 用法：screenshot.tscn -- --out=<資料夾> --scenario=lighting_scenes [--lighting=<預設 id>] [--scene=<場景 id>]
## 玩家站在背景前、敵人在玩家前方 ENEMY_DISTANCE 像素；背景只乘光影預設的背景色調（背景圖本身已畫好光影），其餘與遊戲內相同。

const MAP_PATH := "res://data/lighting_preview/scenes.json"
const BACKGROUND_DIR := "res://art/environment/scenes"
const LIGHTING_DIR := "res://data/lighting"
const ENEMY_DISTANCE := 96.0
## 場景背景預覽時保留的世界節點（其餘的後牆、裝飾、道具都隱藏）。
const KEEP_WORLD_NODES: Array[StringName] = [&"Terrain", &"Entities", &"Projectiles", &"Fx"]
const EMPTY_OFFSET := 240.0
const SAMPLES := 6
const SAMPLE_INTERVAL := 0.2

var _only_lighting := ""
var _only_scene := ""
var _failed := false


func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lighting="):
			_only_lighting = arg.trim_prefix("--lighting=")
		elif arg.begins_with("--scene="):
			_only_scene = arg.trim_prefix("--scene=")
	var problems := validate()
	for problem in problems:
		push_error("[LightingScene] %s" % problem)
	print("%-16s %-20s %-8s %-8s %-8s" % ["光影預設", "場景背景", "玩家對比", "敵人對比", "空處"])
	for entry in entries():
		if _only_lighting != "" and entry[0] != _only_lighting:
			continue
		if _only_scene != "" and entry[1] != _only_scene:
			continue
		await _measure(entry[0], entry[1])
	print("== %s" % ("有對比不足的組合" if _failed or not problems.is_empty() else "全部達標"))


## 對應表攤平成 [光影預設 id, 場景 id] 的清單。讀不到或格式錯誤時回傳空清單（問題由 validate 回報）。
static func entries() -> Array[PackedStringArray]:
	var result: Array[PackedStringArray] = []
	var presets := _presets()
	for lighting_id: String in presets:
		for scene_id: Variant in presets[lighting_id]:
			result.append(PackedStringArray([lighting_id, str(scene_id)]))
	return result


## 回傳對應表的問題清單（空代表沒問題）：檔案讀不到、光影預設不存在。場景背景缺圖不算問題（待 BG-11 畫好）。
static func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	var presets := _presets()
	if presets.is_empty():
		problems.append("%s 讀不到或沒有 presets" % MAP_PATH)
	for lighting_id: String in presets:
		if not ResourceLoader.exists("%s/%s.tres" % [LIGHTING_DIR, lighting_id]):
			problems.append("%s：光影預設「%s」不存在（%s/%s.tres）" % [MAP_PATH, lighting_id, LIGHTING_DIR, lighting_id])
		if not presets[lighting_id] is Array or (presets[lighting_id] as Array).is_empty():
			problems.append("%s：「%s」要列出至少一個場景 id" % [MAP_PATH, lighting_id])
	return problems


static func has_background(scene_id: String) -> bool:
	return ResourceLoader.exists("%s/%s.webp" % [BACKGROUND_DIR, scene_id])


static func _presets() -> Dictionary:
	var file := FileAccess.open(MAP_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or not (parsed as Dictionary).get("presets") is Dictionary:
		return {}
	return (parsed as Dictionary)["presets"]


func _measure(lighting_id: String, scene_id: String) -> void:
	if not has_background(scene_id):
		print("%-16s %-20s 待背景（%s/%s.webp 還沒有）" % [lighting_id, scene_id, BACKGROUND_DIR, scene_id])
		return
	await open_arena("%s/%s.tres" % [LIGHTING_DIR, lighting_id], 8.0)
	var backdrop := _install_background(scene_id)
	await clear_enemies()
	var foe := spawn_enemy("res://data/enemies/grunt.tres", (player.global_position.x + ENEMY_DISTANCE) / 16.0)
	foe.data = foe.data.duplicate()
	foe.data.detect_range = 0.0
	foe.data.attack_range = 0.0
	foe.data.move_speed = 0.0
	foe.facing = -1
	foe.health.setup(999, 0.0)
	await wait(1.0)
	var player_contrast := 0.0
	var enemy_contrast := 0.0
	var empty_contrast := 0.0  # 沒有角色的地方量出來的對比：背景自己的起伏，角色對比要明顯高於它才有意義
	for sample in SAMPLES:
		var probe := ContrastProbe.capture(get_viewport())
		player_contrast += probe.character_contrast(player.global_position) / float(SAMPLES)
		if is_instance_valid(foe):
			enemy_contrast += probe.character_contrast(foe.global_position) / float(SAMPLES)
		empty_contrast += probe.character_contrast(player.global_position + Vector2(EMPTY_OFFSET, 0.0)) / float(SAMPLES)
		await wait(SAMPLE_INTERVAL)
	var ok := player_contrast >= ContrastProbe.MIN_PLAYER_CONTRAST and enemy_contrast >= ContrastProbe.MIN_ENEMY_CONTRAST
	_failed = _failed or not ok
	print("%-16s %-20s %-8.2f %-8.2f %-8.2f %s" % [lighting_id, scene_id, player_contrast, enemy_contrast, empty_contrast, "OK" if ok else "對比不足（門檻 %.2f / %.2f）" % [ContrastProbe.MIN_PLAYER_CONTRAST, ContrastProbe.MIN_ENEMY_CONTRAST]])
	capture("lighting_%s_%s" % [lighting_id, scene_id])
	backdrop.queue_free()
	await finish()


## 隱藏關卡自己的背景、後牆、裝飾與前景（只留地形、角色與特效），改放場景背景圖
## （另一個畫布層，不乘環境光，只乘光影預設的背景色調），量到的才是角色與背景圖的對比。
func _install_background(scene_id: String) -> CanvasLayer:
	level._background.visible = false
	level._foreground.visible = false
	for node in level._world.get_children():
		if not KEEP_WORLD_NODES.has(node.name):
			node.visible = false
	var layer := CanvasLayer.new()
	layer.layer = -10
	add_child(layer)
	var size := get_viewport().get_visible_rect().size
	var tint: Color = level._lighting.current.background_tint
	var sprite := Sprite2D.new()
	sprite.texture = load("%s/%s.webp" % [BACKGROUND_DIR, scene_id]) as Texture2D
	sprite.centered = false
	sprite.scale = size / Vector2(sprite.texture.get_size())
	sprite.modulate = tint
	layer.add_child(sprite)
	var glow_path := "%s/%s_glow.webp" % [BACKGROUND_DIR, scene_id]
	if ResourceLoader.exists(glow_path):
		var glow := Sprite2D.new()
		glow.texture = load(glow_path) as Texture2D
		glow.centered = false
		glow.scale = sprite.scale
		glow.material = LightKit.additive_emissive_material()
		layer.add_child(glow)
	return layer
