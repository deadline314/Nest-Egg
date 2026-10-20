extends RefCounted
const Prompt := preload("res://ui/destination_save_prompt.gd")

class QuietMain extends "res://game/main.gd":
	func _ready() -> void:
		pass

static func run(s: TestSuite) -> void:
	var language := Story.language
	var scale := Settings.get_ui_text_scale()
	Settings.set_ui_text_scale(1.2)
	for lang: String in ["zh", "ja", "en"]:
		Story.language = lang
		for purpose: String in ["area", "retry", "respawn", "chapter"]:
			var prompt := Prompt.new()
			prompt.purpose = purpose
			prompt.can_stay = purpose in ["area", "retry"]
			s.runner.add_child(prompt)
			await s.frames(3)
			s.check(prompt.retry_button.has_focus(), "destination retry receives focus: " + lang + purpose)
			s.check(prompt.message.get_visible_line_count() == prompt.message.get_line_count() and prompt.message.get_minimum_size().y <= prompt.message.size.y and prompt.message.size.x <= prompt.size.x, "destination explanation fits without truncation at enlarged text scale: " + lang + purpose)
			if lang in ["ja", "en"]:
				s.check(prompt.message.get_line_count() > 1, "long destination explanation actually wraps: " + lang + purpose)
			s.check(prompt.cancel_button.visible == prompt.can_stay, "finished worlds never offer stay: " + lang + purpose)
			var next := prompt.cancel_button if prompt.can_stay else prompt.retry_button
			s.check(prompt.retry_button.focus_next == next.get_path(), "destination focus remains among safe actions: " + lang + purpose)
			var requests := [0, 0]
			prompt.retry_requested.connect(func() -> void: requests[0] += 1)
			prompt.cancel_requested.connect(func() -> void: requests[1] += 1)
			prompt.retry_button.pressed.emit()
			var back := InputEventAction.new()
			back.action = &"ui_cancel"
			back.pressed = true
			prompt._unhandled_input(back)
			s.check(requests == [1, 1 if prompt.can_stay else 0], "retry emits and back cannot dismiss automatic recovery: " + lang + purpose)
			prompt.queue_free()
			await s.frames(2)
	Story.language = language
	Settings.set_ui_text_scale(scale)
	var main := QuietMain.new()
	s.runner.add_child(main)
	main._show_destination_failure(func() -> void: pass, false, "chapter")
	s.check(main._destination_save_prompt == null and not GameplayLock.is_locked(), "a rejected resource returning to the menu cannot create a route recovery there")
	main._active_run = true
	var other_lock := GameplayLock.acquire(s.runner)
	var retries := [0]
	main._show_destination_failure(func() -> void: retries[0] += 1, false, "respawn")
	await s.frames(2)
	s.check(main._route_pending() and s.runner.get_tree().paused, "Main blocks routing and pauses while recovery awaits input")
	main._destination_save_prompt.retry_button.pressed.emit()
	s.check(retries[0] == 1 and not main._route_pending(), "Main retries the original operation exactly once")
	s.check(GameplayLock.held_only_by(other_lock), "retry releases only its own pause ownership")
	GameplayLock.release(other_lock)
	main._show_destination_failure(func() -> void: retries[0] += 1, true, "area")
	main._destination_save_prompt.cancel_button.pressed.emit()
	s.check(retries[0] == 1 and not GameplayLock.is_locked() and not s.runner.get_tree().paused, "stay resumes the source without invoking the failed route")
	main._show_destination_failure(func() -> void: retries[0] += 1, false, "chapter")
	main.queue_free()
	await s.frames(2)
	s.check(not GameplayLock.is_locked() and not s.runner.get_tree().paused, "removing Main cannot leave a recovery pause behind")
