extends Node2D
## 量主角蹲著時單膝跪的高度（NE-222）：後膝、兩腳腳踝相對地面的位置，速度 0 與有速度各量一次。
##   godot --headless --path . res://pm/Nest-Egg/attachments/NE-222-kneel-probe/probe.tscn


func _ready() -> void:
	for vx: float in [0.0, 70.0, 140.0]:
		var rig := CharacterRig.new()
		add_child(rig)
		rig.setup("rin", "")
		rig.set_weapon("rifle")
		var input := RigInput.new()
		input.facing = 1
		input.aim_dir = Vector2.RIGHT
		input.on_floor = true
		input.crouching = true
		input.two_handed = true
		input.velocity = Vector2(vx, 0.0)
		for i in 181:
			rig.animate(1.0 / 60.0, input)
			if i % 60 == 0:
				var origin := rig.global_position.y
				print("vx=%s frame=%d front_ankle=%.2f back_ankle=%.2f back_knee=%.2f hip=%.2f" % [vx, i,
					rig.bone(&"foot_front").global_position.y - origin, rig.bone(&"foot_back").global_position.y - origin,
					rig.bone(&"leg_back_lower").global_position.y - origin, rig.bone(&"hip").global_position.y - origin])
		rig.queue_free()
	var standing := CharacterRig.new()
	add_child(standing)
	standing.setup("rin", "")
	var idle := RigInput.new()
	for i in 60:
		standing.animate(1.0 / 60.0, idle)
	print("standing: lowest drawn edge=%.2f" % (standing.visual_bounds().end.y - standing.global_position.y))
	standing.queue_free()
	# 倒地：朝右與朝左、正面與背面中彈，倒定之後全身最低與最高的骨頭位置（地面是 0，往下為正）。
	for facing: int in [1, -1]:
		for from_front: bool in [true, false]:
			var rig := CharacterRig.new()
			add_child(rig)
			rig.setup("rin", "")
			rig.set_weapon("rifle")
			var input := RigInput.new()
			input.facing = facing
			input.aim_dir = Vector2(facing, 0.0)
			input.on_floor = true
			input.dead = true
			input.death_dir = float(-facing if from_front else facing)
			for i in 241:
				rig.animate(1.0 / 60.0, input)
				if i % 30 == 0:
					var low := -INF
					var high := INF
					for bone_name in rig.bone_order():
						var y := rig.bone(bone_name).global_position.y - rig.global_position.y
						low = maxf(low, y)
						high = minf(high, y)
					print("dead facing=%d from_front=%s t=%.1f lowest_bone=%.2f highest_bone=%.2f hip=%.2f chest=%.2f" % [facing, from_front, i / 60.0, low, high,
						rig.bone(&"hip").global_position.y - rig.global_position.y, rig.bone(&"chest").global_position.y - rig.global_position.y])
			print("dead facing=%d from_front=%s settled: lowest drawn edge=%.2f" % [facing, from_front, rig.visual_bounds().end.y - rig.global_position.y])
			rig.queue_free()
	get_tree().quit()
