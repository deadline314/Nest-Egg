class_name ApplyToolRunner
extends RefCounted
## 呼叫 tools/audio/apply_placements.py（NE-163、NE-186）的小包裝，給實驗室的「套用到遊戲」用。
## preview：同步執行 --dry-run --json，列出會改哪些位置（很快）。
## start／poll：套用要重建全部音訊（約一到三分鐘），所以在背景啟動，工具結束時把結果寫成 JSON 檔，實驗室輪詢那個檔。
## 結果一律是 {"ok": bool, "error": String, ...}；找不到 Python、工具回報錯誤、輸出不是 JSON 都轉成 ok=false 加一句說明，不會崩潰。
## 測試時換成假的（覆寫 _run、_spawn、_is_running）。

const SCRIPT := "res://tools/audio/apply_placements.py"
const RESULT_PATH := "user://apply_result.json"
const PYTHON_NAMES: Array[String] = ["python", "python3", "py"]


## 會改哪些位置：{"ok", "error", "changes": Array[Dictionary], "problems": PackedStringArray}。
func preview() -> Dictionary:
	var run := _run(PackedStringArray(["--dry-run", "--json"]))
	if int(run.get("exit_code", -1)) == -1 and str(run.get("output", "")).is_empty():
		return _fail("找不到 Python：套用要用 Python 與 ffmpeg（Windows：scoop install python ffmpeg），裝好後重開實驗室")
	var json := JSON.new()  # parse() 失敗只回傳錯誤碼，不會在輸出裡噴錯誤
	var parsed: Variant = json.data if json.parse(_last_line(str(run.get("output", "")))) == OK else null
	if typeof(parsed) != TYPE_DICTIONARY:
		return _fail("套用工具沒有回傳可讀的結果（結束碼 %d）：%s" % [int(run.get("exit_code", -1)), str(run.get("output", "")).strip_edges().left(200)])
	var data: Dictionary = parsed
	if data.has("error"):
		return _fail(str(data["error"]))
	var problems := PackedStringArray()
	for line: Variant in data.get("problems", []):
		problems.append(str(line))
	return {"ok": true, "error": "", "changes": data.get("changes", []), "problems": problems}


## 在背景套用這幾個位置；回傳 {"ok", "error", "handle"}，handle 交給 poll。
func start(slot_ids: PackedStringArray) -> Dictionary:
	if slot_ids.is_empty():
		return _fail("沒有選任何位置")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RESULT_PATH))
	var args := PackedStringArray(["--json", "--result", ProjectSettings.globalize_path(RESULT_PATH), "--slots"])
	args.append_array(slot_ids)
	var pid := _spawn(args)
	if pid < 0:
		return _fail("找不到 Python：套用要用 Python 與 ffmpeg（Windows：scoop install python ffmpeg）")
	return {"ok": true, "error": "", "handle": pid}


## {"running": true} 或 {"running": false, "result": {"ok", "applied", "problems", "error"}}；工具結束了卻沒有結果檔也算失敗。
func poll(handle: int) -> Dictionary:
	if _is_running(handle):
		return {"running": true}
	var text := FileAccess.get_file_as_string(RESULT_PATH) if FileAccess.file_exists(RESULT_PATH) else ""
	var json := JSON.new()
	var parsed: Variant = json.data if not text.is_empty() and json.parse(text) == OK else null
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"running": false, "result": {"ok": false, "applied": [], "problems": [], "error": "套用工具結束了，但沒有留下結果檔；可能中途失敗，到終端機執行 python tools/audio/apply_placements.py 看訊息"}}
	return {"running": false, "result": parsed}


## 同步執行（只給 preview 用）：回傳 {"exit_code": int, "output": String}；測試覆寫。
func _run(args: PackedStringArray) -> Dictionary:
	var full := PackedStringArray([ProjectSettings.globalize_path(SCRIPT)])
	full.append_array(args)
	for python in PYTHON_NAMES:
		var output: Array = []
		var code := OS.execute(python, full, output, false)
		if code != -1:
			return {"exit_code": code, "output": "\n".join(output)}
	return {"exit_code": -1, "output": ""}


## 在背景啟動；回傳程序編號，啟動不了回傳 -1；測試覆寫。
func _spawn(args: PackedStringArray) -> int:
	var full := PackedStringArray([ProjectSettings.globalize_path(SCRIPT)])
	full.append_array(args)
	for python in PYTHON_NAMES:
		var pid := OS.create_process(python, full)
		if pid > 0:
			return pid
	return -1


func _is_running(handle: int) -> bool:
	return OS.is_process_running(handle)


func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message, "changes": [], "problems": PackedStringArray(), "handle": -1}


static func _last_line(text: String) -> String:
	var lines := text.strip_edges().split("\n", false)
	return lines[lines.size() - 1].strip_edges() if not lines.is_empty() else ""
