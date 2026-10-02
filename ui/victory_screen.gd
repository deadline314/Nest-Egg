class_name VictoryScreen
extends Control
## 過關畫面：顯示時間、死亡次數、擊破數、終結數、圖鑑收集進度。

signal replay_requested
signal menu_requested


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if not get_parent() is Control:
		UiKit.fit_to_viewport(self)
	theme = UiKit.theme()
	var box := UiKit.centered_panel(self, 360.0, 0.85)
	box.add_child(UiKit.label("任務完成", 20, Palette.CYAN, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UiKit.label("難度：%s" % GameState.difficulty.display_name, 11, Palette.UI_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var stats: Array[String] = [
		"通關時間　%s" % UiKit.format_time(GameState.run_time),
		"失敗次數　%d" % GameState.deaths,
		"擊破數　　%d" % GameState.kills,
		"終結技　　%d" % GameState.finishers,
		"敗北圖鑑　%d / %d" % [DefeatCodex.unlocked_count(), DefeatCodex.total_count()],
	]
	for line in stats:
		box.add_child(UiKit.label(line, 12))
	var replay := UiKit.button("再玩一次", replay_requested.emit, "相同難度重新開始")
	box.add_child(replay)
	box.add_child(UiKit.button("回主選單", menu_requested.emit, "更換難度或查看圖鑑"))
	replay.grab_focus.call_deferred()
