class_name ApplyPanelSuite
extends TestSuite
## 實驗室的「套用到遊戲」（NE-186）：列出會改的位置、有警告的預設不勾、確認前什麼都不做、取消不套用、
## 背景套用的輪詢（執行中、成功、失敗、沒結果檔）、錯誤顯示；測試不需要 Python 與 ffmpeg：套用工具換成假的。

const LAB_SCENE := "res://tools/sound_lab/sound_lab.tscn"
const COPY_PATH := "user://test_audio_apply_placements.md"
const LAYOUT_PATH := "user://test_audio_apply_layout.cfg"
const OLD_RESULT := "user://apply_result.json"


## 假的套用工具：記錄呼叫，回傳事先設定好的結果；poll 先回傳 running 幾次再給結果。
class FakeRunner:
	extends ApplyToolRunner
	var preview_result := {"ok": true, "error": "", "changes": [], "problems": PackedStringArray()}
	var start_result := {"ok": true, "error": "", "handle": 42}
	var finished_result := {"ok": true, "applied": [], "problems": [], "error": ""}
	var running_polls := 2
	var start_calls: Array = []
	var preview_calls := 0

	func preview() -> Dictionary:
		preview_calls += 1
		return preview_result

	func start(slot_ids: PackedStringArray) -> Dictionary:
		start_calls.append(slot_ids)
		return start_result

	func poll(_handle: int) -> Dictionary:
		if running_polls > 0:
			running_polls -= 1
			return {"running": true}
		return {"running": false, "result": finished_result}


## 假的命令列結果：測試 ApplyToolRunner 怎麼解讀工具的輸出與結果檔。
class ScriptedRunner:
	extends ApplyToolRunner
	var run_result := {"exit_code": 0, "output": ""}
	var spawned := PackedStringArray()
	var spawn_pid := 7
	var running := false

	func _run(_args: PackedStringArray) -> Dictionary:
		return run_result

	func _spawn(args: PackedStringArray) -> int:
		spawned = args
		return spawn_pid

	func _is_running(_handle: int) -> bool:
		return running


func _changes() -> Array:
	return [
		{"slot": "P-HIT-001", "name": "命中金屬", "kind": "sfx", "target": "hit_metal", "current": ["IMP-0001"], "planned": ["IMP-0002"], "warnings": []},
		{"slot": "P-WPN-001", "name": "手槍射擊", "kind": "sfx", "target": "shot_pistol", "current": ["GUN-0031", "GUN-0085"], "planned": ["GUN-0383"], "warnings": ["武器射擊音效至少要有 2 個變體"]},
		{"slot": "P-BGM-001", "name": "主選單", "kind": "music", "target": "menu_dark", "current": [], "planned": ["MUS-0002"], "warnings": []},
	]


func run() -> void:
	_test_runner()
	await _test_panel()
	_cleanup()


func _cleanup() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(COPY_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LAYOUT_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(OLD_RESULT))


func _test_runner() -> void:
	var runner := ScriptedRunner.new()
	runner.run_result = {"exit_code": 0, "output": "noise\n{\"changes\": [{\"slot\": \"P-HIT-001\"}], \"problems\": [\"P-X：問題\"]}\n"}
	var preview := runner.preview()
	check(bool(preview["ok"]) and (preview["changes"] as Array).size() == 1 and (preview["problems"] as PackedStringArray).size() == 1, "a preview line after noise is read")
	runner.run_result = {"exit_code": 1, "output": "{\"error\": \"讀取位置清單失敗\"}"}
	check(not bool(runner.preview()["ok"]) and str(runner.preview()["error"]).contains("讀取位置清單失敗"), "the tool's error is passed on")
	runner.run_result = {"exit_code": -1, "output": ""}
	check(str(runner.preview()["error"]).contains("Python"), "a missing Python explains what to install")
	runner.run_result = {"exit_code": 0, "output": "not json"}
	check(not bool(runner.preview()["ok"]), "unreadable output is a failure, not a crash")
	check(not bool(runner.start(PackedStringArray())["ok"]), "starting with no slots is refused")
	var started := runner.start(PackedStringArray(["P-HIT-001", "P-WPN-001"]))
	check(bool(started["ok"]) and int(started["handle"]) == 7 and runner.spawned.has("--slots") and runner.spawned.has("P-WPN-001") and runner.spawned.has("--result") and runner.spawned.has("--json"), "starting passes the slots and the result file to the tool")
	runner.spawn_pid = -1
	check(not bool(runner.start(PackedStringArray(["P-HIT-001"]))["ok"]), "a tool that cannot start is reported")
	runner.running = true
	check(bool(runner.poll(7)["running"]), "a running tool is reported as running")
	runner.running = false
	var file := FileAccess.open(OLD_RESULT, FileAccess.WRITE)
	file.store_string("{\"ok\": true, \"applied\": [\"P-HIT-001\"], \"problems\": [], \"error\": \"\"}\n")
	file.close()
	var done := runner.poll(7)
	check(not bool(done["running"]) and bool(done["result"]["ok"]) and (done["result"]["applied"] as Array).size() == 1, "a finished tool's result file is read")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(OLD_RESULT))
	check(not bool(runner.poll(7)["result"]["ok"]) and str(runner.poll(7)["result"]["error"]).contains("結果檔"), "a tool that ends without a result file is a failure")


func _tooltip_gaps(node: Node, into: PackedStringArray) -> void:
	if node is Button or node is CheckBox or (node is Label and (node as Label).tooltip_text.is_empty() and node.get_parent() is VBoxContainer and node.get_parent().get_parent() is ScrollContainer):
		if (node as Control).tooltip_text.is_empty():
			into.append("%s（%s）" % [node.name, node.get_class()])
	for child in node.get_children():
		_tooltip_gaps(child, into)


func _test_panel() -> void:
	DirAccess.copy_absolute(ProjectSettings.globalize_path(PlacementDoc.PATH), ProjectSettings.globalize_path(COPY_PATH))
	var lab := (load(LAB_SCENE) as PackedScene).instantiate() as SoundLab
	lab.doc_path = COPY_PATH
	lab.stage_enabled = false
	lab.layout_path = LAYOUT_PATH
	var fake := FakeRunner.new()
	lab.apply_runner = fake
	runner.get_tree().root.add_child(lab)
	await frames(3)

	# ---- 開啟失敗：只顯示說明
	fake.preview_result = {"ok": false, "error": "找不到 Python", "changes": [], "problems": PackedStringArray()}
	check(not await lab.open_apply_panel() and lab.apply_panel._status.text.contains("找不到 Python") and lab.apply_panel._apply_button.disabled, "a failing preview shows the reason and nothing can be applied")
	check(lab.status_label.text.contains("找不到 Python"), "the lab status line repeats the error")
	lab.apply_panel.close()
	await frames(2)
	check(lab.apply_panel == null, "closing removes the panel")

	# ---- 沒有要套用的位置
	fake.preview_result = {"ok": true, "error": "", "changes": [], "problems": PackedStringArray()}
	check(await lab.open_apply_panel() and lab.apply_panel._apply_button.disabled and lab.apply_panel.checked_slots().is_empty(), "nothing to apply is shown and the button stays off")
	lab.apply_panel.close()
	await frames(2)

	# ---- 列出會改的位置：有警告的預設不勾
	fake.preview_result = {"ok": true, "error": "", "changes": _changes(), "problems": PackedStringArray(["P-X-001：預計使用「亂寫」看不出素材編號"])}
	check(await lab.open_apply_panel(), "the panel opens with the planned changes")
	var panel := lab.apply_panel
	await frames(2)
	check(panel._checks.size() == 3 and panel.checked_slots() == PackedStringArray(["P-HIT-001", "P-BGM-001"]), "slots with warnings start unchecked")
	check(panel._checks[1].text.contains("GUN-0031、GUN-0085 → GUN-0383") and panel._checks[2].text.contains("（合成音）"), "each row shows the slot, the current and the planned assets")
	check(panel._problems.text.contains("亂寫") and panel._apply_button.text == "套用選中的 2 個位置", "problems are listed and the button counts the checked slots")
	panel.set_all(true)
	check(panel.checked_slots().size() == 3 and panel._apply_button.text.contains("3"), "select all checks everything")
	panel.set_all(false)
	check(panel.checked_slots().is_empty() and panel._apply_button.disabled and not panel.request_apply() and panel._status.text.contains("先勾選"), "nothing checked cannot be applied")

	# ---- 確認前什麼都不做；取消不套用
	panel._checks[0].button_pressed = true
	panel._checks[1].button_pressed = true
	check(panel.request_apply() and panel.is_confirming() and fake.start_calls.is_empty(), "asking to apply only shows the confirmation")
	check(panel._confirm_label.text.contains("2 個位置") and panel._confirm_label.text.contains("pipeline.json"), "the confirmation says how many slots and what is rewritten")
	panel.cancel_apply()
	check(not panel.is_confirming() and fake.start_calls.is_empty() and panel._status.text.contains("取消"), "cancelling changes nothing")

	# ---- 確認後在背景套用；輪詢到結束
	check(panel.request_apply() and panel.confirm_apply() and panel.is_applying(), "confirming starts the apply in the background")
	check(fake.start_calls.size() == 1 and fake.start_calls[0] == PackedStringArray(["P-HIT-001", "P-WPN-001"]), "the checked slots are what is applied")
	check(not panel.close() and lab.apply_panel == panel, "the panel cannot be closed while applying")
	panel.poll_now()
	check(panel.is_applying() and panel._status.text.contains("套用中"), "a running tool keeps the panel waiting")
	panel.poll_now()
	fake.finished_result = {"ok": true, "applied": ["P-HIT-001", "P-WPN-001"], "problems": [], "error": ""}
	panel.poll_now()
	check(not panel.is_applying() and panel._status.text.contains("已套用 2 個位置") and panel._status.text.contains("匯入"), "a finished apply reports the count and the next steps")
	check(lab.status_label.text.contains("已套用 2 個位置") and panel._apply_button.disabled, "the lab status is updated and the button stays off after applying")
	check(panel.close(), "the panel can be closed after applying")
	await frames(2)

	# ---- 失敗：啟動不了、執行失敗
	await lab.open_apply_panel()
	panel = lab.apply_panel
	await frames(2)
	fake.start_result = {"ok": false, "error": "找不到 Python：套用要用 Python", "handle": -1}
	check(panel.request_apply() and not panel.confirm_apply() and not panel.is_applying() and panel._status.text.contains("找不到 Python"), "a tool that cannot start shows the reason and the panel stays usable")
	fake.start_result = {"ok": true, "error": "", "handle": 43}
	fake.running_polls = 0
	fake.finished_result = {"ok": false, "applied": [], "problems": [], "error": "重建音訊失敗，請看終端機的訊息"}
	check(panel.request_apply() and panel.confirm_apply(), "the apply starts again")
	panel.poll_now()
	check(not panel.is_applying() and panel._status.text.contains("套用失敗") and panel._status.text.contains("重建音訊失敗"), "a failed apply shows the tool's reason")

	# ---- tooltip
	var gaps := PackedStringArray()
	_tooltip_gaps(panel, gaps)
	check(gaps.is_empty(), "every control of the panel has a tooltip: %s" % ", ".join(gaps.slice(0, 5)))
	panel.close()
	lab.audition.stop()
	lab.queue_free()
	await frames(2)
