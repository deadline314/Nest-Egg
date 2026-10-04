class_name ClipToolRunner
extends RefCounted
## 呼叫 tools/audio/clip_tool.py（NE-179）的小包裝，給實驗室的擷取介面用。
## 結果一律是 {"ok": bool, "error": String, "data": Dictionary}：找不到 Python、工具回報錯誤、輸出不是 JSON 都轉成 ok=false 加一句說明，不會崩潰。
## 測試時換成假的（覆寫 _run），不需要 Python 與 ffmpeg。

const SCRIPT := "res://tools/audio/clip_tool.py"
const PYTHON_NAMES: Array[String] = ["python", "python3", "py"]


func prepare(asset_id: String) -> Dictionary:
	return _call(PackedStringArray(["prepare", asset_id, "--json"]))


func export_clip(asset_id: String, start: float, end: float, note := "") -> Dictionary:
	var args := PackedStringArray(["export", asset_id, "--start", "%.4f" % start, "--end", "%.4f" % end, "--json"])
	if not note.is_empty():
		args.append_array(PackedStringArray(["--note", note]))
	return _call(args)


func _call(args: PackedStringArray) -> Dictionary:
	var run := _run(args)
	if int(run.get("exit_code", -1)) == -1 and str(run.get("output", "")).is_empty():
		return _fail("找不到 Python：擷取功能要用 Python 與 ffmpeg（Windows：scoop install python ffmpeg），裝好後重開實驗室")
	var json := JSON.new()  # parse() 失敗只回傳錯誤碼，不會在輸出裡噴錯誤
	var parsed: Variant = json.data if json.parse(_last_line(str(run.get("output", "")))) == OK else null
	if typeof(parsed) != TYPE_DICTIONARY:
		return _fail("擷取工具沒有回傳可讀的結果（結束碼 %d）：%s" % [int(run.get("exit_code", -1)), str(run.get("output", "")).strip_edges().left(200)])
	var data: Dictionary = parsed
	if data.has("error"):
		return _fail(str(data["error"]))
	if int(run.get("exit_code", 0)) != 0:
		return _fail("擷取工具失敗（結束碼 %d）" % int(run["exit_code"]))
	return {"ok": true, "error": "", "data": data}


## 實際執行：回傳 {"exit_code": int, "output": String}；測試覆寫這個函式。
func _run(args: PackedStringArray) -> Dictionary:
	var full := PackedStringArray([ProjectSettings.globalize_path(SCRIPT)])
	full.append_array(args)
	for python in PYTHON_NAMES:
		var output: Array = []
		var code := OS.execute(python, full, output, false)
		if code != -1:
			return {"exit_code": code, "output": "\n".join(output)}
	return {"exit_code": -1, "output": ""}


func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message, "data": {}}


static func _last_line(text: String) -> String:
	var lines := text.strip_edges().split("\n", false)
	return lines[lines.size() - 1].strip_edges() if not lines.is_empty() else ""
