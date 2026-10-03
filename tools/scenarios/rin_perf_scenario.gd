extends ScenarioBase
## NE-71 情境：同屏很多骨架角色時的效能。放 N 個凜、再放 N 個小兵外觀（舊 Q 版骨架），各量測 3 秒的
## 每影格處理時間（毫秒）、繪製呼叫數與貼圖記憶體，印在輸出裡。
## 用法：screenshot.tscn -- --out=<資料夾> --scenario=rin_perf [--count=12]

var _count := 12


func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--count="):
			_count = int(arg.trim_prefix("--count="))
	await open_arena("res://data/lighting/transfer.tres", 6.0)
	for skin: String in ["trooper", "rin", "trooper", "rin"]:
		var holder := Node2D.new()
		level._entities.add_child(holder)
		var puppets: Array[CharacterRig] = []
		var inputs: Array[RigInput] = []
		for i in _count:
			var rig := CharacterRig.new()
			holder.add_child(rig)
			rig.position = Vector2((10.0 + i * 2.2) * 16.0, FLOOR_Y)
			rig.setup(skin)
			rig.set_weapon("rifle")
			var input := RigInput.new()
			input.velocity = Vector2(150, 0) if i % 2 == 0 else Vector2.ZERO
			puppets.append(rig)
			inputs.append(input)
		await wait(1.0)
		var frames := 0
		var process_ms := 0.0
		var draw_calls := 0
		var elapsed := 0.0
		while elapsed < 3.0:
			var dt := get_process_delta_time()
			for i in puppets.size():
				puppets[i].animate(dt, inputs[i])
			await get_tree().process_frame
			elapsed += get_process_delta_time()
			process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			draw_calls += int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			frames += 1
		print("PERF %s x%d: process %.2f ms/frame, draw calls %d/frame, frames %d, video memory %.1f MB" % [
			skin, _count, process_ms / frames, draw_calls / frames, frames, Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0])
		holder.queue_free()
		await settle(10)
	await finish()
