extends RefCounted
const Prompt := preload("res://ui/radio_save_prompt.gd")

static func run(s: TestSuite) -> void:
	var language := Story.language
	var scale := Settings.get_ui_text_scale()
	Settings.set_ui_text_scale(1.2)
	for lang: String in ["zh", "ja", "en"]:
		Story.language = lang
		var prompt := Prompt.new()
		s.runner.add_child(prompt)
		await s.frames(3)
		s.check(prompt.retry_button.has_focus() and prompt.cancel_button.visible, "radio recovery offers retry and cancel with focus: " + lang)
		s.check(prompt._message.get_line_count() > 1 and prompt._message.get_visible_line_count() == prompt._message.get_line_count(), "radio failure explanation wraps without truncation: " + lang)
		var retries := [0]
		prompt.retry_requested.connect(func() -> void: retries[0] += 1)
		prompt.retry_button.pressed.emit()
		s.check(retries[0] == 1 and prompt.is_inside_tree(), "radio retry request retains the modal until coordinator resolves it: " + lang)
		var cancels := [0]
		prompt.cancel_requested.connect(func() -> void: cancels[0] += 1)
		var back := InputEventAction.new()
		back.action = &"ui_cancel"
		back.pressed = true
		prompt._unhandled_input(back)
		s.check(cancels[0] == 1, "back requests cancel before commit: " + lang)
		prompt.set_recovery(true)
		await s.frames(2)
		s.check(not prompt.cancel_button.visible and prompt.retry_button.focus_next == prompt.retry_button.get_path(), "committed recovery has one safe focus target and no cancel: " + lang)
		prompt._unhandled_input(back)
		s.check(cancels[0] == 1, "back never cancels already committed recovery: " + lang)
		prompt.set_original_recovery()
		await s.frames(2)
		s.check(prompt.cancel_button.visible and not prompt._message.text.is_empty(), "original-backup recovery remains explicitly unsaved and cancellable: " + lang)
		prompt.queue_free()
		await s.frames(2)
		var event := Prompt.new()
		event.presentation = "event"
		event.allow_cancel = false
		s.runner.add_child(event)
		await s.frames(3)
		s.check(event.retry_button.has_focus() and not event.cancel_button.visible and event.retry_button.focus_next == event.retry_button.get_path(), "automatic event recovery keeps focus on its only safe action: " + lang)
		s.check(event._message.get_visible_line_count() == event._message.get_line_count() and event._message.get_minimum_size().y <= event._message.size.y, "event recovery explanation fits enlarged text without truncation: " + lang)
		var event_cancels := [0]
		event.cancel_requested.connect(func() -> void: event_cancels[0] += 1)
		event._unhandled_input(back)
		s.check(event_cancels[0] == 0, "Back cannot strand an automatic event after the stage ended: " + lang)
		event.set_recovery(true)
		await s.frames(2)
		s.check(not event.cancel_button.visible and event.retry_button.focus_next == event.retry_button.get_path(), "committed event recovery preserves its reload-only focus: " + lang)
		event.set_original_recovery()
		await s.frames(2)
		s.check(not event.cancel_button.visible and event._message.get_visible_line_count() == event._message.get_line_count(), "uncommitted event backup recovery remains truthful and actionable: " + lang)
		event.queue_free()
		await s.frames(2)
	Story.language = language
	Settings.set_ui_text_scale(scale)
