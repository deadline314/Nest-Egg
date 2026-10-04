extends Node2D
## 開發工具：觸手生物的動作預覽（需要可渲染的環境）。
## 用法：godot --path . res://tools/creature_preview.tscn -- --creature=test_creature --out=/絕對路徑/檔名.png [--zoom=倍率]
## 並排顯示同一隻生物在 idle、alert、crawl 與鞭擊（進度 0、30%、55%、80%）的樣子；每一格都從 idle 開始跑到穩定。
## --hit：改成看受擊：沒被打、第 3 條觸手被打到後 0.05／0.15／0.3／0.6 秒（受擊波往兩端傳），以及打斷那條觸手之後。
## --strip：改成同一個狀態（--state=名稱）在連續 8 個時間點的樣子，檢查行進波與收縮波怎麼往前傳。

const HIT_FRAMES: Array[String] = ["idle", "hit:0.05", "hit:0.15", "hit:0.3", "hit:0.6", "sever:0.3"]
## 狀態名稱以 walk 開頭時預覽的行走速度（像素／秒）。
const WALK_SPEED := 40.0
const STATES: Array[String] = ["idle", "alert", "crawl", "lash:0.0", "lash:0.3", "lash:0.55", "lash:0.8"]
## 有腿的生物（有 gait 段）改看走路：待機與走路的連續畫面。

var _parts_id := ""
var _creature_id := "test_creature"
var _out := ""
var _zoom := 0.9
var _strip := false
## --bright：檢視用的亮場景（淺灰背景、柔和白光）。
var _bright := false
var _hit := false
var _state := "crawl"
## --states=a,b,c：自選要並排看的狀態（每個預設從 idle 跑到穩定；walk 開頭的會邊走邊看）。
var _states: Array[String] = []
## --worm=<id>：看蠕行生物（WormCreature）在各狀態往右移動時的樣子。
var _worm_id := ""
## --free=4,5：預覽時先把這幾條腿放開步態（看出招的樣子，遊戲裡由敵人腳本放開）。
var _free: Array[int] = []
var _creatures: Array[ChainCreature] = []
var _wanted: Array[String] = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--creature="):
			_creature_id = arg.trim_prefix("--creature=")
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--zoom="):
			_zoom = float(arg.trim_prefix("--zoom="))
		elif arg == "--bright":
			_bright = true
		elif arg == "--strip":
			_strip = true
		elif arg == "--hit":
			_hit = true
		elif arg.begins_with("--parts="):
			_parts_id = arg.trim_prefix("--parts=")
		elif arg.begins_with("--state="):
			_state = arg.trim_prefix("--state=")
		elif arg.begins_with("--states="):
			_states.assign(arg.trim_prefix("--states=").split(",", false))
		elif arg.begins_with("--free="):
			for part in arg.trim_prefix("--free=").split(",", false):
				_free.append(int(part))
		elif arg.begins_with("--worm="):
			_worm_id = arg.trim_prefix("--worm=")
	add_child(LightKit.create_environment())
	var bg := ColorRect.new()
	bg.color = Color("5b6577") if _bright else Color("121826")
	bg.size = Vector2(1280, 720)
	bg.z_index = -10
	add_child(bg)
	if not _parts_id.is_empty():
		_build_parts_sheet()
		if not _out.is_empty():
			_capture_parts.call_deferred()
		return
	if not _worm_id.is_empty():
		_build_worm_sheet()
		if not _out.is_empty():
			_capture_worms.call_deferred()
		return
	var items: Array[String] = []
	if not _states.is_empty():
		items = _states
	elif _strip:
		for i in 8:
			items.append("%s:%d" % [_state, i])
	elif _hit:
		items = HIT_FRAMES
	else:
		items = STATES
	var count := items.size()
	var width := get_viewport_rect().size.x
	for i in count:
		var creature := ChainCreature.new()
		creature.position = Vector2(60.0 + float(i) * ((width - 120.0) / float(maxi(1, count - 1))), 110.0)
		creature.scale = Vector2.ONE * _zoom
		add_child(creature)
		if not creature.setup(_creature_id):
			push_error("[creature_preview] 無法建立：%s" % _creature_id)
			creature.queue_free()
			continue
		_creatures.append(creature)
		_wanted.append(items[i])
	if not _out.is_empty():
		_capture.call_deferred()


var _worms: Array[WormCreature] = []
var _worm_states: Array[String] = []


func _build_worm_sheet() -> void:
	var data := RigLibrary.load_json(WormCreature.PATH % _worm_id)
	var names: Array = _states if not _states.is_empty() else (data.get("states", {}) as Dictionary).keys()
	# 蠕行生物的身體用世界座標，不受父節點縮放影響，所以放大用鏡頭。
	var zoom := _zoom if _zoom != 0.9 else 2.5
	var view := get_viewport_rect().size / zoom  # 鏡頭看得到的世界範圍
	var camera := Camera2D.new()
	camera.zoom = Vector2.ONE * zoom
	camera.position = view * 0.5
	add_child(camera)
	for row in names.size():
		var worm := WormCreature.new()
		worm.position = Vector2(view.x * 0.25, view.y * (float(row) + 0.5) / float(names.size()))
		add_child(worm)
		if not worm.setup(_worm_id):
			push_error("[creature_preview] 無法建立蠕行生物：%s" % _worm_id)
			return
		_worms.append(worm)
		_worm_states.append(str(names[row]))


func _capture_worms() -> void:
	var dt := 1.0 / 60.0
	for i in _worms.size():
		var worm := _worms[i]
		worm.reset_trail(Vector2.RIGHT)
		for step in 150:
			worm.global_position.x += 0.0 if _worm_states[i] == "idle" else 0.5
			worm.animate(dt, StringName(_worm_states[i]))
	for i in 4:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(_out)
	print("saved ", _out)
	get_tree().quit()


## --parts=<id>：看零件式生物（PartCreature）：每個狀態一列，由左到右是 0、0.04、0.08…秒的樣子（有步態的以滿速移動）。
var _part_rows: Array[Dictionary] = []


func _build_parts_sheet() -> void:
	var probe := PartCreature.new()
	if not probe.setup(_parts_id):
		push_error("[creature_preview] 無法建立零件式生物：%s" % _parts_id)
		probe.free()
		return
	var data := RigLibrary.load_json(PartCreature.PATH % _parts_id)
	probe.free()
	var states: Array = (data.get("states", {}) as Dictionary).keys()
	var gait_speed := float((data.get("gait", {}) as Dictionary).get("full_speed", 80.0))
	for row in states.size():
		for col in 8:
			var creature := PartCreature.new()
			creature.setup(_parts_id)
			creature.scale = Vector2.ONE * (_zoom if _zoom != 0.9 else 1.5)
			creature.position = Vector2(40.0 + float(col) * 70.0, 40.0 + float(row) * 55.0)
			add_child(creature)
			_part_rows.append({"creature": creature, "state": StringName(states[row]), "steps": 30 + col * 3, "speed": gait_speed if str(states[row]).begins_with("run") or str(states[row]).begins_with("walk") or str(states[row]).begins_with("crawl") else 0.0})


func _capture_parts() -> void:
	for spot: Array in [[Vector2(130, 10), Palette.CYAN], [Vector2(420, 10), Color("ff2e88")], [Vector2(280, 180), Palette.WARM_LIGHT]]:
		var light := LightKit.create_point_light(Color("f0f4ff") if _bright else spot[1], 900.0 if _bright else 420.0, 0.9 if _bright else 1.4)
		light.position = spot[0]
		add_child(light)
	var dt := 1.0 / 60.0
	for entry in _part_rows:
		var creature: PartCreature = entry["creature"]
		for i in int(entry["steps"]):
			creature.animate(dt, entry["state"], Vector2(float(entry["speed"]), 0.0), 1, 0.0)
	for i in 4:
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	image.save_png(_out)
	print("saved ", _out)
	get_tree().quit()


## 讓每一隻跑到想看的狀態與時間點：先在 idle 跑 1 秒，再切到目標狀態跑（lash 跑到指定進度；strip 每格多跑 0.12 秒）。
func _run_to(creature: ChainCreature, want: String, index: int) -> void:
	var dt := 1.0 / 60.0
	for free_index in _free:
		creature.set_free(free_index, true)
	for i in 60:
		creature.animate(dt, &"idle")
	var parts := want.split(":")
	var state_name := parts[0]
	if state_name == "hit" or state_name == "sever":
		var target := creature.bone_of(2, creature.bone_count() / 2)
		if state_name == "hit":
			creature.hit_wave(target.global_position, 1.0)
		else:
			creature.hit_wave(target.global_position, 1.0)
			creature.sever(2, Vector2.RIGHT)
		for i in int(float(parts[1]) / dt):
			creature.animate(dt, &"idle")
		return
	if _strip:
		var strip_speed := WALK_SPEED if state_name.begins_with("walk") else 0.0
		for i in int(1.5 / dt + float(index) * 0.12 / dt):
			creature.position.x += strip_speed * dt
			creature.animate(dt, StringName(state_name), Vector2(strip_speed, 0.0))
		return
	if parts.size() > 1:
		# 名稱:進度（0～1）：播到該狀態持續時間的這個比例（鞭擊、掃地等）。
		var duration := creature.state_duration(StringName(state_name))
		for i in int(float(parts[1]) * duration / dt):
			creature.animate(dt, StringName(state_name))
		creature.animate(dt, StringName(state_name))
		return
	var speed := WALK_SPEED if state_name.begins_with("walk") else 0.0
	for i in 150:
		creature.position.x += speed * dt  # 走路：身體往前移，腳釘在地上
		creature.animate(dt, StringName(state_name), Vector2(speed, 0.0))


func _capture() -> void:
	for i in _creatures.size():
		_run_to(_creatures[i], _wanted[i], i)
	for i in 4:
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	image.save_png(_out)
	print("saved ", _out)
	get_tree().quit()
