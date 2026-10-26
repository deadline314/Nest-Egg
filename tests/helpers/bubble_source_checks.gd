extends RefCounted

class PresenceAnchor extends Node2D:
	var present := true
	func is_present() -> bool:
		return present


static func run(s: TestSuite) -> void:
	await _queued_and_active(s)
	await _exact_story_requests(s)


static func _queued_and_active(s: TestSuite) -> void:
	var original_obstacles := PromptLayout._obstacles.size()
	var stage := Node2D.new()
	s.runner.add_child(stage)
	var speaker := PresenceAnchor.new()
	var other := Node2D.new()
	stage.add_child(speaker)
	stage.add_child(other)
	var host := MapBubbles.new()
	host.anchor_resolver = func(id: String) -> Node2D: return other if id == "other" else speaker
	stage.add_child(host)
	host.set_process(false)
	speaker.position = host._visible_world_rect().get_center() + Vector2(0, 40)
	other.position = speaker.position + Vector2(70, 0)
	var cancelled: Array = []
	var finished: Array[StringName] = []
	host.scene_cancelled.connect(func(id: StringName, request: int) -> void: cancelled.append([String(id), request]))
	host.scene_finished.connect(func(id: StringName) -> void: finished.append(id))
	host.show_lines(&"presence_a", [{"speaker":"a","text":"原說話者的第一句。"},{"speaker":"a","text":"原說話者的第二句。"}], 11)
	host._process(0.0)
	host._process(0.2)
	host.show_lines(&"presence_b", [{"speaker":"other","text":"另一位還在。"}], 12)
	host._layout_boxes()
	s.check(host._active.size() == 1 and (host._active[0]["rect"] as Rect2).has_area(), "original present speaker has a real reading rectangle")
	var age: float = host._active[0]["age"]
	var lease := GameplayLock.acquire(stage)
	host._process(10.0)
	s.check(not host.visible and host._active[0]["age"] == age and host._queue.size() == 2 and cancelled.is_empty() and finished.is_empty(), "modal preserves a present source, unread queue and reading age")
	GameplayLock.release(lease)
	host._process(0.0)
	host._layout_boxes()
	speaker.present = false
	host._layout_boxes() # Same engine frame as the cached visible layout.
	s.check(not (host._active[0]["rect"] as Rect2).has_area(), "declared departure invalidates same-frame reading bounds without waiting for polling")
	lease = GameplayLock.acquire(stage)
	host._process(10.0)
	s.check(cancelled == [["presence_a",11]] and not finished.has(&"presence_a"), "departure cancels exactly the original batch while paused without false completion")
	s.check(host._active.is_empty() and host._queue.size() == 1 and host._queue[0]["id"] == &"presence_b", "departure removes active and unread source lines while preserving another speaker")
	GameplayLock.release(lease)
	host._process(0.0)
	s.check(host._active.size() == 1 and host._active[0]["id"] == &"presence_b" and host._active[0]["age"] == 0.0, "unrelated queued speech resumes with its full original reading time")
	host._process(MapBubbles.HOLD_MAX + MapBubbles.FADE_OUT + 1.0)
	s.check(finished == [&"presence_b"] and not host.is_busy(), "normal unrelated anchor finishes through the original fade contract")
	var detached := Node2D.new()
	stage.add_child(detached)
	host.anchor_resolver = func(_id: String) -> Node2D: return detached if is_instance_valid(detached) else null
	host.show_lines(&"last_position", [{"speaker":"plain","text":"保留原最後位置閱讀。"}], 13)
	host._process(0.0)
	var position: Vector2 = host._active[0]["pos"]
	detached.queue_free()
	await s.frames(1)
	host._process(0.0)
	s.check(host._active.size() == 1 and host._active[0]["pos"] == position and cancelled.size() == 1, "freed plain anchors retain existing last-position reading instead of changing legacy behavior")
	host._process(MapBubbles.HOLD_MAX + MapBubbles.FADE_OUT + 1.0)
	s.check(finished.has(&"last_position"), "freed plain anchor still finishes at the unchanged reading deadline")
	speaker.present = true
	host.anchor_resolver = func(_id: String) -> Node2D: return speaker
	host.show_lines(&"reenqueue_old", [{"speaker":"a","text":"原請求。"}], 14)
	host._process(0.0)
	var reenqueue := func(id: StringName, _request: int) -> void:
		if id == &"reenqueue_old":
			speaker.present = true
			host.show_lines(&"reenqueue_new", [{"speaker":"a","text":"回呼新排入的請求。"}], 15)
	host.scene_cancelled.connect(reenqueue)
	speaker.present = false
	host._process(0.0)
	s.check(host._active.size() == 1 and host._active[0]["id"] == &"reenqueue_new" and host._active[0]["request"] == 15, "cancellation installs old removals before preserving reentrant newly enqueued speech")
	host.scene_cancelled.disconnect(reenqueue)

	stage.queue_free()
	await s.frames(2)
	s.check(PromptLayout._obstacles.size() == original_obstacles, "source cancellation and normal retirement release every registered reading obstacle")


static func _wait(id: StringName, result: Array) -> void:
	result[0] = await Story.play_and_wait(id, false)


static func _exact_story_requests(s: TestSuite) -> void:
	var old_host := Story._bubble_host
	var old_auto := Story.auto_skip
	var old_flags := GameState.world_flags.duplicate(true)
	var old_defaults := GameState.flag_defaults.duplicate(true)
	var flag := &"test_ne228_presence_result"
	GameState.flag_defaults[String(flag)] = false
	GameState.world_flags.erase(String(flag))
	Story.auto_skip = false
	var anchor := PresenceAnchor.new()
	s.runner.add_child(anchor)
	var host := MapBubbles.new()
	host.anchor_resolver = func(_id: String) -> Node2D: return anchor
	s.runner.add_child(host)
	host.set_process(false)
	Story.set_bubble_host(host)
	var id := &"test_ne228_presence_waiter"
	var parallel_id := &"test_ne228_presence_parallel"
	for scene_id: StringName in [id,parallel_id]:
		Story._scenes[String(scene_id)] = {"mode":"bubbles","lines":[{"speaker":"rin","text":"真正來源還在時才繼續。"}],"set_flags":[String(flag)]}
	var first: Array = [null]
	_wait(id,first)
	var request: int = Story._passive_requests[id][0]
	host._process(0.0)
	anchor.present = false
	host._process(0.0)
	s.check(first[0] == false and not Story._passive_requests.has(id), "declared source departure resolves the exact original Story waiter as cancelled")
	s.check(not GameState.has_flag(flag) and not Story.progress_snapshot().has(id) and not Story._seen.has(id), "cancelled speech never publishes flag, read history or a false seen result")
	anchor.present = true
	var second: Array = [null]
	_wait(id,second)
	var newer: int = Story._passive_requests[id][0]
	host._process(0.0)
	Story._on_bubbles_cancelled(id,request)
	s.check(newer != request and second[0] == null and Story._passive_requests[id] == [newer], "stale cancellation cannot retire a newer same-id request")
	host._process(MapBubbles.HOLD_MAX + MapBubbles.FADE_OUT + 1.0)
	s.check(second[0] == true and GameState.has_flag(flag) and Story.progress_snapshot().has(id), "returned source can genuinely read and publish the normal original result")
	GameState.set_flag(flag,false)
	var third: Array = [null]
	var fourth: Array = [null]
	_wait(parallel_id,third)
	host._process(0.0)
	_wait(parallel_id,fourth)
	var requests: Array = Story._passive_requests[parallel_id].duplicate()
	anchor.present = false
	host._process(0.0) # Queue is visited before active; the newer token retires first.
	s.check(requests.size() == 2 and third[0] == false and fourth[0] == false and not Story._passive_requests.has(parallel_id), "same-id batches cancel their own tokens even when the newer queued token retires first")
	s.check(not GameState.has_flag(flag) and not Story.progress_snapshot().has(parallel_id), "out-of-order source cancellation cannot publish unread parallel results")
	Story.set_bubble_host(old_host if is_instance_valid(old_host) else null)
	for scene_id: StringName in [id,parallel_id]:
		Story._scenes.erase(String(scene_id))
		Story._seen.erase(scene_id)
		Story._completed.erase(scene_id)
	host.queue_free()
	anchor.queue_free()
	await s.frames(2)
	Story.auto_skip = old_auto
	GameState.world_flags = old_flags
	GameState.flag_defaults = old_defaults
