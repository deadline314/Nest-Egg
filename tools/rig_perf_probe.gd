extends Node
## 骨架效能量測：用法 godot --headless --path . res://tools/rig_perf_probe.tscn [-- --count=10 --frames=600 --skin=rin]
## 同時建 count 隻人形，跑 frames 格跑步與蹲下輪替的動畫，印出每格 CharacterRig.animate 的平均耗時（微秒）：
## 剛體零件（舊）與關節網格（NE-204）各一次，以及網格增加的頂點數。只量腳本端的成本（無頭模式沒有繪圖）。


func _ready() -> void:
	var count := 10
	var frames := 600
	var skin := "rin"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--count="):
			count = int(arg.trim_prefix("--count="))
		elif arg.begins_with("--frames="):
			frames = int(arg.trim_prefix("--frames="))
		elif arg.begins_with("--skin="):
			skin = arg.trim_prefix("--skin=")
	var rigid := _measure(skin, count, frames, true)
	var mesh := _measure(skin, count, frames, false)
	print("%s ×%d：剛體 %.1f µs/格，關節網格 %.1f µs/格（多 %.1f µs，每隻多 %.1f µs），網格頂點 %d" % [skin, count, rigid[0], mesh[0], mesh[0] - rigid[0], (mesh[0] - rigid[0]) / count, mesh[1]])
	get_tree().quit()


## 回傳 [每格平均微秒, 每隻的網格頂點數]。
func _measure(skin: String, count: int, frames: int, rigid: bool) -> Array:
	CharacterRig.force_rigid_limbs = rigid
	var rigs: Array[CharacterRig] = []
	var inputs: Array[RigInput] = []
	for i in count:
		var rig := CharacterRig.new()
		add_child(rig)
		rig.setup(skin)
		rig.set_weapon("rifle")
		rigs.append(rig)
		inputs.append(RigInput.new())
	CharacterRig.force_rigid_limbs = false
	var vertices := 0
	for mesh in rigs[0].limb_meshes():
		vertices += mesh.vertex_count()
	var started := Time.get_ticks_usec()
	for frame in frames:
		for i in count:
			var input := inputs[i]
			input.facing = 1
			input.on_floor = true
			input.crouching = (frame / 120 + i) % 3 == 2
			input.velocity = Vector2(150.0 if (frame / 120 + i) % 3 != 1 else 0.0, 0.0)
			input.run_speed = 150.0
			input.aim_dir = Vector2.RIGHT
			rigs[i].animate(1.0 / 60.0, input)
	var elapsed := float(Time.get_ticks_usec() - started) / float(frames)
	for rig in rigs:
		rig.queue_free()
	return [elapsed, vertices]
