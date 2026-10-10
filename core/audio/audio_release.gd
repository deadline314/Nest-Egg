class_name AudioRelease
## 結束程序前停掉配樂、環境音與音效，等混音端放掉播放中的串流，程序才不會帶著未回收的音訊資源結束。
## 停止要求在下一次混音才生效，所以要等到看見幾次混音；最多等 TIMEOUT_MS，逾時照常繼續。
## 遊戲的結束流程與會自己結束程序的開發工具共用。

const TIMEOUT_MS := 400
const MIXES := 2


static func settle(tree: SceneTree) -> void:
	Music.stop(0.0)
	Ambience.stop_all(0.0)
	Sfx.stop_all()
	var deadline := Time.get_ticks_msec() + TIMEOUT_MS
	var since_mix := AudioServer.get_time_since_last_mix()
	var mixes := 0
	while mixes < MIXES and Time.get_ticks_msec() < deadline:
		await tree.process_frame
		var now := AudioServer.get_time_since_last_mix()
		if now < since_mix:
			mixes += 1
		since_mix = now
	# 混音端移除後，主執行緒再跑一格才真正釋放。
	await tree.process_frame
