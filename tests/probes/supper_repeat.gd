extends "res://tests/probes/supper_completion.gd"
## Two genuine decisions and two completed rechoose replies, no IO fault.
func _run() -> void:
	case_name = "normal_return"
	_mode = "return"
	var actor := await _open_source()
	if actor == null:
		await _exit()
		return
	var wallet := Progression.credits
	for round_index in 2:
		faulted = false
		skip_sent = false
		batch_spends.clear()
		actor._talk()
		await _drive()
		await _frames(5)
		_check(faulted and _prompt() == null and not actor._talking and actor.talk_count == round_index + 1, "repeat actual rechoose reply settles its original source once per genuine encounter")
		_check(GameState.get_flag(&"ch1_supper_choice") == "unset" and not GameState.has_flag(&"ch1_supper_done") and not GameState.has_flag(&"ch1_supper_host_accepted"), "repeat rechoose retains the original undecided unpaid outcome")
		_main.call("_save_run")
		_check(_same_counts(_primary(),round_index + 1), "repeat reply preserves three original durable counters")
	_check(observer_spends == 2 and Progression.credits == wallet - 2, "repeat decision preserves both ordinary spends without duplicating a reward")
	_check(Progression.story_receipt_status(&"ch1.revival_meal.order").get("status") == "recorded" and Progression.story_receipt_status(&"ch1.revival_meal.paid").get("status") != "recorded", "repeat rechoose cannot bill the original unpaid order")
	await _exit()
