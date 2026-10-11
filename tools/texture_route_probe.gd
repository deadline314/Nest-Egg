extends Node
## 走一輪區域與過場，量「已載入的環境貼圖」會不會越積越多、換區域時最長的一格有多長（BG-32）。
##
## 用法（原生）：
##   godot --path . res://tools/texture_route_probe.tscn -- [--levels=ch1_street,ch1_booth_alley,...] [--rounds=2] [--dwell=40]
## --dwell：在每個區域多待幾個影格才量、才離開（真的玩會待上幾分鐘；待得夠久，預載才來得及把隔壁區域的圖準備好）。
## 依序進入每個區域（真的建立關卡、釋放上一個），在每個區域把它會播的過場的舞台都建出來再拆掉（等於看過那些過場），
## 然後記錄：快取裡的環境貼圖（張數與匯入後的大小）、只被預載拿著的環境貼圖、渲染器的貼圖記憶體、
## 進入這個區域後 90 個影格裡最長的一格。路線的最後一站回到第一站，兩者相比就是「走一圈之後多留了多少」。
## 同一支腳本可以原封不動拿去量還沒有釋放機制的舊版本（複製過去跑），修前修後用同一台機器。
## 輸出 ROUTE 開頭的行；結尾的 ROUTE_SUMMARY 是最後一站相對第一站的比例。

## 預設路線：照第一章出入口實際連接的順序走完所有區域再回到街道（玩家只能經出入口移動，預載也是針對隔壁的區域）。
const DEFAULT_LEVELS: PackedStringArray = ["ch1_street", "ch1_booth_alley", "ch1_street", "ch1_warehouse", "ch1_vault", "ch1_lounge",
	"ch1_stall", "ch1_pawnshop_dawn", "ch1_rooftop", "ch1_pawnshop", "ch1_street"]
const ENTER_FRAMES := 90
const STAGE_FRAMES := 12
const SETTLE_FRAMES := 40
const ENV := "res://art/environment/"
## 一站的畫面上純白像素最多佔多少（正常的夜景不到 1%）。
const MAX_WHITE_SHARE := 0.05

var _levels := DEFAULT_LEVELS
var _rounds := 1
var _dwell := SETTLE_FRAMES
var _level: Level


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--levels="):
			_levels = argument.trim_prefix("--levels=").split(",", false)
		elif argument.begins_with("--rounds="):
			_rounds = maxi(1, int(argument.trim_prefix("--rounds=")))
		elif argument.begins_with("--dwell="):
			_dwell = maxi(SETTLE_FRAMES, int(argument.trim_prefix("--dwell=")))
	_run.call_deferred()


func _run() -> void:
	Story.auto_skip = true
	for id: String in Story.scene_ids():
		Story._seen[StringName(id)] = true
	add_child(LightKit.create_environment())
	GameState.start_new_run(GameState.difficulties[1])
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var first := {}
	var last := {}
	var worst_enter := 0.0
	var worst_white := 0.0
	for round_index in _rounds:
		for index in _levels.size():
			var record := await _visit(_levels[index])
			if first.is_empty():
				first = record
			last = record
			if not (round_index == 0 and index == 0):
				worst_enter = maxf(worst_enter, float(record["enter_max_ms"]))
			worst_white = maxf(worst_white, float(record["white_share"]))
			print("ROUTE round=%d stop=%d level=%s cached=%d cached_bytes=%d prefetch_only=%d prefetch_bytes=%d stage_cached=%d renderer_texture_bytes=%d enter_max_ms=%.1f enter_median_ms=%.2f stages_built=%d white_share=%.4f" % [
				round_index + 1, index + 1, _levels[index], record["count"], record["bytes"], record["prefetch_count"], record["prefetch_bytes"],
				record["stage_count"], record["renderer"], record["enter_max_ms"], record["enter_median_ms"], record["stages"], record["white_share"]])
	var library: Script = RigLibrary
	var reloads := int(library.get("reloads_after_release")) if "reloads_after_release" in library else -1
	var total_first := int(first["bytes"]) + int(first["prefetch_bytes"])
	var total_last := int(last["bytes"]) + int(last["prefetch_bytes"])
	print("ROUTE_SUMMARY first_bytes=%d last_bytes=%d ratio=%.3f first_with_prefetch=%d last_with_prefetch=%d ratio_with_prefetch=%.3f renderer_first=%d renderer_last=%d worst_enter_ms=%.1f reloads_after_release=%d worst_white_share=%.4f" % [
		first["bytes"], last["bytes"], float(last["bytes"]) / maxf(1.0, float(first["bytes"])), total_first, total_last,
		float(total_last) / maxf(1.0, float(total_first)), first["renderer"], last["renderer"], worst_enter, reloads, worst_white])
	if worst_white > MAX_WHITE_SHARE:
		push_error("[TextureRouteProbe] 有一站畫面上純白的比例到 %.1f%%：有貼圖被錯放掉了？" % (worst_white * 100.0))
	if is_instance_valid(_level):
		_level.queue_free()
	for i in 6:
		await get_tree().process_frame
	if ResourceLoader.exists("res://core/audio/audio_release.gd"):
		await load("res://core/audio/audio_release.gd").settle(get_tree())
	get_tree().quit()


func _visit(level_id: String) -> Dictionary:
	if is_instance_valid(_level):
		_level.queue_free()
		_level = null
	var data := load("res://data/levels/%s.tres" % level_id) as LevelData
	# 這裡是直接換區域、不是走出入口：不帶上一站的出入口，從這個區域的起點進去。
	GameState.pending_portal = &""
	_level = Level.new()
	_level.configure(data)
	add_child(_level)
	# 進入這個區域後的每一格：最長的一格就是換區域的停頓。
	var times: Array[float] = []
	var previous := Time.get_ticks_usec()
	for i in ENTER_FRAMES:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - previous) / 1000.0)
		previous = now
	_level.hud.visible = false
	for enemy: Node in get_tree().get_nodes_in_group(&"enemies"):
		enemy.queue_free()
	var stages := await _watch_scenes(data)
	for i in _dwell:
		await get_tree().process_frame
	var record := _loaded()
	# 畫面上純白的比例：貼圖被錯放掉的話，用它畫的東西會變成白色方塊（背牆曾經整面變白）。
	await RenderingServer.frame_post_draw
	var image: Image = preload("res://tools/viewport_capture.gd").image(get_viewport())
	image.resize(160, 90, Image.INTERPOLATE_BILINEAR)
	var white := 0
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.r > 0.92 and pixel.g > 0.92 and pixel.b > 0.92:
				white += 1
	record["white_share"] = float(white) / float(image.get_width() * image.get_height())
	var sorted := times.duplicate()
	sorted.sort()
	record["enter_max_ms"] = sorted[sorted.size() - 1]
	record["enter_median_ms"] = sorted[sorted.size() / 2]
	record["stages"] = stages
	return record


## 這個區域會播的過場：把每一個舞台真的建出來放一下再拆掉（貼圖會被載入、用過、放開）。回傳建了幾個。
func _watch_scenes(data: LevelData) -> int:
	var scene_ids: Array = [data.intro_scene]
	scene_ids.append_array(data.story_triggers)
	scene_ids.append_array(data.channel_scenes.values())
	var stage_ids: Dictionary = {}
	for scene: Variant in scene_ids:
		var id := str(scene)
		var seen: Dictionary = {}
		while id != "" and not seen.has(id) and Story.has_scene(StringName(id)):
			seen[id] = true
			var definition: Dictionary = Story._scenes[id]
			for step: Variant in definition.get("steps", []):
				if typeof(step) == TYPE_DICTIONARY and str(step.get("do", "")) == "scene":
					stage_ids[str(step.get("id", ""))] = true
			id = str(definition.get("then", ""))
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	var built := 0
	for stage_id: String in stage_ids:
		if stage_id.is_empty() or not ResourceLoader.exists(StageLibrary.path_of(StringName(stage_id))):
			continue
		var stage := StageLibrary.build(StringName(stage_id))
		if stage == null:
			continue
		layer.add_child(stage)
		built += 1
		for i in STAGE_FRAMES:
			await get_tree().process_frame
		stage.queue_free()
		for i in 2:
			await get_tree().process_frame
	layer.queue_free()
	# 有釋放機制的版本：過場結束時遊戲自己會要求釋放；這裡照樣要求一次（舊版本沒有就略過）。
	if ResourceLoader.exists("res://core/texture_release.gd"):
		load("res://core/texture_release.gd").request()
	return built


## 現在快取裡的環境貼圖（RigLibrary 的快取加上受光貼圖的法線）、只被預載拿著的環境貼圖、渲染器的貼圖記憶體。
func _loaded() -> Dictionary:
	var textures: Dictionary = RigLibrary._texture_cache.duplicate()
	for path: String in LitTextures._normals:
		var normal: Texture2D = LitTextures._normals[path]
		textures[normal.resource_path] = normal
	var bytes := 0
	var count := 0
	var stage_count := 0
	for path: String in textures:
		if not path.begins_with(ENV):
			continue
		var texture: Texture2D = textures[path]
		bytes += _payload(texture)
		count += 1
		if path.contains("/stages/") or path.contains("/scenes/"):
			stage_count += 1
	var prefetch_bytes := 0
	var prefetch_count := 0
	for path: String in AssetPrefetch._cache:
		if not path.begins_with(ENV) or textures.has(path):
			continue
		prefetch_bytes += _payload(AssetPrefetch._cache[path] as Texture2D)
		prefetch_count += 1
	textures.clear()
	return {"count": count, "bytes": bytes, "stage_count": stage_count, "prefetch_count": prefetch_count, "prefetch_bytes": prefetch_bytes,
		"renderer": int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED))}


## 匯入後的大小估算（寬 × 高 × 4，含 mipmap 再乘 4/3）：不讀回像素，量測本身不佔記憶體也不花時間。
func _payload(texture: Texture2D) -> int:
	if texture == null:
		return 0
	return int(float(texture.get_width()) * float(texture.get_height()) * 4.0)
