extends Node
## 移動動作報告：用法
##   godot --headless --path . res://tools/rig_locomotion_report.tscn -- [--skin=rin] [--speeds=30,60,90,120,150] [--run=150]
## 對指定角色以幾種速度各跑 6 秒，印出骨盆上下抖動的指標（見 LocomotionAudit）。調整 art/motion/<角色>.json 時用它看數字。


func _ready() -> void:
	var skin := "rin"
	var speeds: Array[float] = [30.0, 60.0, 90.0, 120.0, 150.0]
	var run_speed := 150.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--skin="):
			skin = arg.trim_prefix("--skin=")
		elif arg.begins_with("--run="):
			run_speed = float(arg.trim_prefix("--run="))
		elif arg.begins_with("--speeds="):
			speeds.clear()
			for part in arg.trim_prefix("--speeds=").split(","):
				speeds.append(float(part))
	var holder := Node2D.new()
	add_child(holder)
	var rig := CharacterRig.new()
	holder.add_child(rig)
	if not rig.setup(skin):
		push_error("[locomotion] 角色建立失敗：%s" % skin)
		get_tree().quit(1)
		return
	print("%s  L=%.1f px" % [skin, absf(rig.rest(&"hip").y)])
	print("speed  pp(px)  pp/L   f_main  hf     vel     acc    acc/th  step   rev/s  slide(L)  head_pp")
	for speed in speeds:
		var r := LocomotionAudit.measure(rig, speed, run_speed)
		print("%5.0f  %6.2f  %5.3f  %6.2f  %5.3f  %6.1f  %6.0f  %5.2f  %5.2f  %5.2f  %6.3f    %5.2f" % [
			speed, r["pp"], r["pp_l"], r["f_main"], r["hf"], r["peak_vel"], r["peak_acc"], r["acc_ratio"], r["frame_step"],
			r["reversals_per_second"], r["slide_l"], r["head_pp"]])
	get_tree().quit(0)
