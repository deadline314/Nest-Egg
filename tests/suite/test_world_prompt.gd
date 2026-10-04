class_name WorldPromptSuite
extends TestSuite
## 世界提示自動錯開（NE-120）：同時顯示的提示不重疊、不蓋住人物，被推開的提示滑過去，沒人靠近時不運算。


func run() -> void:
	_test_solver()
	await _test_nodes()
	await _test_npc_obstacle()


func _rect(x: float, y := 0.0, w := 60.0, h := 15.0) -> Rect2:
	return Rect2(x, y, w, h)


func _overlap_free(rects: Array[Rect2], nudges: PackedVector2Array) -> bool:
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if Rect2(rects[i].position + nudges[i], rects[i].size).intersects(Rect2(rects[j].position + nudges[j], rects[j].size)):
				return false
	return true


func _test_solver() -> void:
	var one: Array[Rect2] = [_rect(0.0)]
	check(PromptLayout.solve(one, []).duplicate()[0] == Vector2.ZERO, "單獨一個提示不動")
	var apart: Array[Rect2] = [_rect(0.0), _rect(100.0)]
	var nudges := PromptLayout.solve(apart, []).duplicate()
	check(nudges[0] == Vector2.ZERO and nudges[1] == Vector2.ZERO, "不重疊的提示都不動")
	var stacked: Array[Rect2] = [_rect(0.0), _rect(10.0), _rect(20.0), _rect(30.0)]
	nudges = PromptLayout.solve(stacked, []).duplicate()
	check(_overlap_free(stacked, nudges), "四個重疊的提示排開後互不重疊")
	check(nudges[0] == Vector2.ZERO, "最左邊的提示留在原位")
	check(nudges[1].y < 0.0 and nudges[2].y < nudges[1].y, "重疊的提示先上下錯開（往上一格一格疊）")
	# 人物（障礙）在原位上方時改往旁邊讓開，不蓋住人物。
	var body := Rect2(20.0, -40.0, 24.0, 56.0)
	var blocked: Array[Rect2] = [_rect(10.0, -10.0)]
	var obstacles: Array[Rect2] = [body]
	nudges = PromptLayout.solve(blocked, obstacles).duplicate()
	check(not Rect2(blocked[0].position + nudges[0], blocked[0].size).intersects(body), "提示不蓋住人物")
	# 已經排好的結果，再算一次一樣（不會因重算而抖動）。
	var again := PromptLayout.solve(stacked, []).duplicate()
	var first := PromptLayout.solve(stacked, []).duplicate()
	check(again == first, "同樣的輸入每次排出同樣的結果")


func _spawn_prompt(parent: Node2D, x: float, text: String) -> WorldPrompt:
	var prompt := WorldPrompt.new()
	prompt.text = text
	prompt.offset = Vector2(0, -30)
	prompt.reach_check = func() -> bool: return true
	var holder := Node2D.new()
	holder.position = Vector2(x, 0)
	parent.add_child(holder)
	holder.add_child(prompt)
	return prompt


func _test_nodes() -> void:
	var stage := Node2D.new()
	runner.add_child(stage)
	var prompts: Array[WorldPrompt] = [
		_spawn_prompt(stage, 0.0, "{interact} 撥號備份"), _spawn_prompt(stage, 14.0, "{interact} 補給"),
		_spawn_prompt(stage, 28.0, "{interact} 拾取武器"),
	]
	await frames(30)
	var rects: Array[Rect2] = []
	for prompt in prompts:
		rects.append(Rect2(prompt.base_rect().position + prompt._nudge, prompt.base_rect().size))
	var free := true
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			free = free and not rects[i].intersects(rects[j])
	check(free, "同一處三個提示實際顯示時自動排開、不重疊")
	var leader_shown := false
	for prompt in prompts:
		leader_shown = leader_shown or prompt._nudge.length() > 1.0
	check(leader_shown, "被推開的提示有移動（並畫出指回自己物件的細線）")
	# 條件不成立就不顯示，也不參與排版。
	for prompt in prompts:
		prompt.reach_check = func() -> bool: return false
	await frames(40)
	var hidden := true
	for prompt in prompts:
		hidden = hidden and prompt._alpha <= 0.0 and not prompt.is_showing()
	check(hidden, "離開互動範圍後提示淡出，不再參與排版")
	PromptLayout.update()
	check(PromptLayout._active.is_empty(), "沒有提示在顯示時不做排版運算")
	stage.queue_free()
	await frames(2)
	check(PromptLayout._prompts.is_empty(), "提示離開場景時取消登記")


## 人物登記為障礙：旁邊物件的提示不蓋住人物，自己的提示用「按互動鍵有效」的範圍顯示。
func _test_npc_obstacle() -> void:
	var stage := Node2D.new()
	runner.add_child(stage)
	var holder := Node2D.new()
	stage.add_child(holder)
	var npc_rect := Rect2(-12.0, -56.0, 24.0, 56.0)
	PromptLayout.add_obstacle(holder, func() -> Rect2: return Rect2(holder.global_position + npc_rect.position, npc_rect.size))
	var prompt := _spawn_prompt(stage, 6.0, "{interact} 撥號備份")
	prompt.offset = Vector2(0, -20)
	prompt.position = prompt.offset
	await frames(30)
	var shown := Rect2(prompt.base_rect().position + prompt._nudge, prompt.base_rect().size)
	check(not shown.intersects(npc_rect), "提示不蓋住旁邊的人物")
	stage.queue_free()
	await frames(2)
	check(PromptLayout._obstacles.is_empty(), "人物離開場景時取消障礙登記")
