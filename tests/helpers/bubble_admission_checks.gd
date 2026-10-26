extends RefCounted
## Eligibility changes withdraw unread original requests without consuming them.

static func run(s: TestSuite) -> void:
	await _host_contract(s)
	await _story_facts(s)


static func _host_contract(s: TestSuite) -> void:
	var obstacles := PromptLayout._obstacles.size()
	var anchor := Node2D.new()
	s.runner.add_child(anchor)
	var host := MapBubbles.new()
	host.anchor_resolver = func(_id: String) -> Node2D: return anchor
	anchor.add_child(host)
	host.set_process(false)
	anchor.position = host._visible_world_rect().get_center() + Vector2(0, 40)
	var cancelled: Array = []
	var finished: Array[StringName] = []
	host.scene_cancelled.connect(func(id: StringName, request: int) -> void: cancelled.append([id, request]))
	host.scene_finished.connect(func(id: StringName) -> void: finished.append(id))
	host.show_lines(&"invalid", [{"speaker":"rin","text":"原招呼。"},{"speaker":"rin","text":"尚未讀的下一句。"}], 21)
	host._process(0.0)
	host._process(0.2)
	host._layout_boxes()
	var owner: Node = host._active[0]["bounds_owner"]
	var age: float = host._active[0]["age"]
	s.check(PromptLayout._obstacles.has(owner) and (host._active[0]["rect"] as Rect2).has_area(), "eligible original line owns real reading geometry")
	host.cancel_unavailable(Callable())
	host.cancel_unavailable(func(_id: StringName, _request: int) -> Variant: return null)
	s.check(host._active[0]["age"] == age and host._queue.size() == 1, "invalid or non-boolean admission does not cancel or consume reading time")
	host.show_lines(&"valid", [{"speaker":"rin","text":"仍然有效的另一句。"}], 22)
	var lease := GameplayLock.acquire(anchor)
	var queries := {}
	host.cancel_unavailable(func(id: StringName, request: int) -> bool:
		queries[request] = int(queries.get(request, 0)) + 1
		return id != &"invalid")
	s.check(queries == {21:1,22:1}, "admission queries each original request once, including multi-line batches")
	s.check(cancelled == [[&"invalid",21]] and finished.is_empty(), "paused invalidation cancels exactly the original request without completion")
	s.check(not PromptLayout._obstacles.has(owner) and host._active.is_empty() and host._queue.size() == 1, "same-frame cancellation releases reading geometry and preserves unrelated speech")
	GameplayLock.release(lease)
	host._process(0.0)
	s.check(host._active[0]["id"] == &"valid" and host._active[0]["age"] == 0.0, "unrelated speech retains its full original reading interval")
	host._process(MapBubbles.HOLD_MAX + MapBubbles.FADE_OUT + 1.0)
	s.check(finished == [&"valid"] and not host.is_busy(), "valid speech still finishes through the original hold and fade contract")
	var requeue := func(id: StringName, request: int) -> void:
		if id == &"same" and request == 23:
			host.show_lines(id, [{"speaker":"rin","text":"回呼新排入的同名請求。"}], 24)
	host.scene_cancelled.connect(requeue)
	host.show_lines(&"same", [{"speaker":"rin","text":"原請求。"}], 23)
	host._process(0.0)
	host.cancel_unavailable(func(_id: StringName, request: int) -> bool: return request != 23)
	s.check(host._queue.size() == 1 and host._queue[0]["request"] == 24 and host.is_processing(), "cancellation callback preserves newly enqueued same-id work and processing")
	host.scene_cancelled.disconnect(requeue)
	host._process(0.0)
	host._process(MapBubbles.HOLD_MAX + MapBubbles.FADE_OUT + 1.0)
	host.show_lines(&"finishing", [{"speaker":"rin","text":"即將讀完。"}], 31)
	host._process(0.0)
	host._active[0]["age"] = host._active[0]["hold"]
	host.show_lines(&"withdrawn", [{"speaker":"rin","text":"結果改變後不再成立。"}], 32)
	host._process(0.0)
	var on_finished := func(id: StringName) -> void:
		if id == &"finishing":
			host.cancel_unavailable(func(other: StringName, _request: int) -> bool: return other != &"withdrawn")
	host.scene_finished.connect(on_finished)
	host._process(MapBubbles.FADE_OUT)
	s.check(not host.is_busy() and cancelled.has([&"withdrawn",32]) and not finished.has(&"withdrawn"), "completion callback cannot resurrect another active line it has just invalidated")
	host.scene_finished.disconnect(on_finished)
	anchor.queue_free()
	await s.frames(2)
	s.check(PromptLayout._obstacles.size() == obstacles, "admission cancellation and reentrant retirement release all reading obstacles")


static func _wait(id: StringName, result: Array) -> void:
	result[0] = await Story.play_and_wait(id, false)


static func _story_facts(s: TestSuite) -> void:
	var old_host := Story._bubble_host
	var old_auto := Story.auto_skip
	var flags := GameState.world_flags.duplicate(true)
	var defaults := GameState.flag_defaults.duplicate(true)
	var items := StoryItems.snapshot()
	var progression := Progression.snapshot()
	var enabled := &"test_ne228_admitted"
	var read := &"test_ne228_read"
	GameState.flag_defaults[String(enabled)] = true
	GameState.flag_defaults[String(read)] = false
	GameState.world_flags.erase(String(enabled))
	GameState.world_flags.erase(String(read))
	Story.auto_skip = false
	var anchor := Node2D.new()
	s.runner.add_child(anchor)
	var host := MapBubbles.new()
	host.anchor_resolver = func(_id: String) -> Node2D: return anchor
	anchor.add_child(host)
	host.set_process(false)
	Story.set_bubble_host(host)
	var id := &"test_ne228_admission_waiter"
	var parallel := &"test_ne228_admission_parallel"
	var item_id := &"test_ne228_admission_item"
	var receipt_id := &"test_ne228_admission_receipt"
	for scene_id: StringName in [id, parallel, item_id, receipt_id]:
		Story._scenes[String(scene_id)] = {"mode":"bubbles","lines":[{"speaker":"rin","text":"條件仍成立時才能繼續閱讀。"}],"when":{"flag":String(enabled),"equals":true},"set_flags":[String(read)]}
	var first: Array = [null]
	_wait(id, first)
	host._process(0.0)
	var lease := GameplayLock.acquire(anchor)
	GameState.set_flag(enabled, false)
	s.check(first[0] == false and not host.is_busy() and not Story._passive_requests.has(id), "actual flag event cancels the original pending Story request synchronously while paused")
	s.check(not GameState.has_flag(read) and not Story.progress_snapshot().has(id) and not Story._seen.has(id), "state withdrawal publishes no read flag, history or seen marker")
	GameplayLock.release(lease)
	GameState.set_flag(enabled, true)
	var second: Array = [null]
	_wait(id, second)
	host._process(0.0)
	host._process(MapBubbles.HOLD_MAX + MapBubbles.FADE_OUT + 1.0)
	s.check(second[0] == true and GameState.has_flag(read) and Story.progress_snapshot().has(id), "a genuinely reread request still publishes its original completion")
	GameState.set_flag(read, false)
	var third: Array = [null]
	var fourth: Array = [null]
	_wait(parallel, third)
	host._process(0.0)
	_wait(parallel, fourth)
	GameState.set_flag(enabled, false)
	s.check(third[0] == false and fourth[0] == false and not Story._passive_requests.has(parallel) and not GameState.has_flag(read), "one fact change retires both same-id original tokens without publishing unread results")
	GameState.set_flag(enabled, true)
	StoryItems._owned.erase(&"ch1_lounge_bill")
	StoryItems._held.erase(&"ch1_lounge_bill")
	StoryItems._unseen.erase(&"ch1_lounge_bill")
	StoryItems._transferred.erase(&"ch1_lounge_bill")
	Story._scenes[String(item_id)]["when"] = {"not":{"item":"ch1_lounge_bill"}}
	var item_waiter: Array = [null]
	_wait(item_id, item_waiter)
	host._process(0.0)
	var acquired := StoryItems.acquire(&"ch1_lounge_bill", false)
	s.check(acquired and item_waiter[0] == false and not host.is_busy(), "actual item acquisition cancels a no-longer-eligible original world line")
	Story._scenes[String(item_id)]["when"] = {"item":"ch1_lounge_bill"}
	var transfer_waiter: Array = [null]
	_wait(item_id, transfer_waiter)
	host._process(0.0)
	var transferred := StoryItems.transfer(&"ch1_lounge_bill")
	s.check(transferred and transfer_waiter[0] == false and not host.is_busy(), "actual original-item transfer cancels held-item-dependent speech without a flag event")
	Progression._story_transactions = StoryTransactionLedger.new()
	Story._scenes[String(receipt_id)]["when"] = {"account":"ch1_lounge","equals":"none"}
	var receipt_waiter: Array = [null]
	_wait(receipt_id, receipt_waiter)
	host._process(0.0)
	var committed := Progression.apply_story_transaction(Story.outcomes.transaction(&"ch1.revival_meal.order"))
	s.check(committed["applied"] and receipt_waiter[0] == false and not host.is_busy(), "actual transaction commit invalidates account-dependent speech without requiring a flag change")
	Story.set_bubble_host(old_host if is_instance_valid(old_host) else null)
	for scene_id: StringName in [id, parallel, item_id, receipt_id]:
		Story._scenes.erase(String(scene_id))
		Story._seen.erase(scene_id)
		Story._completed.erase(scene_id)
	anchor.queue_free()
	await s.frames(2)
	Story.auto_skip = old_auto
	StoryItems.restore(items)
	Progression.restore(progression, false)
	GameState.world_flags = flags
	GameState.flag_defaults = defaults
