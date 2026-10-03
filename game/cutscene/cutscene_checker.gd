class_name CutsceneChecker
extends RefCounted
## 過場動畫資料檢查：步驟種類、必填欄位、引用的場景／角色／講者／音效／轉場是否存在、台詞數量。
## Story.validate() 在遊戲啟動與測試時呼叫；也可用 tools/cutscene_check.gd 單獨檢查。

const MAX_SAYS := 16
const MAX_SAY_RUN := 3
const MAX_SAY_LENGTH := 56
const MAX_TIME := 60.0
const FX_KINDS: PackedStringArray = ["shake", "flash", "lightning", "noise", "tint", "rain", "vignette"]
const STYLES: PackedStringArray = ["normal", "whisper", "shout", "noise"]

## 每種步驟的必填欄位。
const STEP_FIELDS: Dictionary = {
	"scene": ["id"],
	"letterbox": ["on"],
	"camera": [],
	"actor": ["id", "pos"],
	"pose": ["id", "pose"],
	"move": ["id", "to"],
	"face": ["id", "dir"],
	"remove": ["id"],
	"say": ["speaker", "text"],
	"narrate": ["lines"],
	"title": ["text"],
	"fx": ["kind"],
	"sfx": ["id"],
	"wait": ["time"],
	"fade": ["to"],
	"transition": ["kind"],
	"end": [],
}
## 這些步驟需要先有舞台。
const NEEDS_STAGE: PackedStringArray = ["camera", "actor", "pose", "move", "face", "remove"]


## 檢查一份動畫場景。speakers 是講者表（Story 的合併結果）。
static func validate(scene_id: String, scene: Dictionary, speakers: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	var steps: Variant = scene.get("steps", [])
	if typeof(steps) != TYPE_ARRAY or (steps as Array).is_empty():
		problems.append("動畫場景 %s 沒有任何步驟" % scene_id)
		return problems
	var defined: Dictionary[String, bool] = {}
	# 疊加演出（overlay）直接蓋在遊戲畫面上，不需要舞台。
	var has_stage := false
	var says := 0
	var run := 0
	var index := 0
	for raw: Variant in steps:
		index += 1
		var where := "動畫場景 %s 第 %d 步" % [scene_id, index]
		if typeof(raw) != TYPE_DICTIONARY:
			problems.append("%s 不是物件" % where)
			continue
		var step: Dictionary = raw
		var kind := str(step.get("do", ""))
		if not STEP_FIELDS.has(kind):
			problems.append("%s 的動作「%s」不存在" % [where, kind])
			continue
		for key in STEP_FIELDS[kind]:
			if not step.has(key):
				problems.append("%s（%s）缺少欄位「%s」" % [where, kind, key])
		if NEEDS_STAGE.has(kind) and not has_stage:
			problems.append("%s（%s）之前沒有指定場景" % [where, kind])
		for time_key in ["time", "delay"]:
			if step.has(time_key):
				var t := float(step[time_key])
				if t < 0.0 or t > MAX_TIME:
					problems.append("%s 的 %s 超出範圍（0 到 %d 秒）" % [where, time_key, int(MAX_TIME)])
		if kind == "say":
			says += 1
			run += 1
			problems.append_array(_check_say(where, step, speakers))
		else:
			run = 0
		if run > MAX_SAY_RUN:
			problems.append("%s 連續超過 %d 句台詞沒有演出，請在中間加入動作或鏡頭" % [where, MAX_SAY_RUN])
		problems.append_array(_check_step(where, kind, step, defined))
		if kind == "scene":
			has_stage = true
			problems.append_array(_check_stage(where, StringName(str(step.get("id", "")))))
	if says > MAX_SAYS:
		problems.append("動畫場景 %s 有 %d 句台詞，上限 %d 句" % [scene_id, says, MAX_SAYS])
	return problems


static func _check_say(where: String, step: Dictionary, speakers: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	if not speakers.has(str(step.get("speaker", ""))):
		problems.append("%s 的講者「%s」未定義" % [where, step.get("speaker", "")])
	var text := str(step.get("text", ""))
	if text.is_empty():
		problems.append("%s 的台詞沒有文字" % where)
	elif text.length() > MAX_SAY_LENGTH:
		problems.append("%s 的台詞 %d 字，超過 %d 字" % [where, text.length(), MAX_SAY_LENGTH])
	if step.has("style") and not STYLES.has(str(step["style"])):
		problems.append("%s 的說話風格「%s」不存在" % [where, step["style"]])
	return problems


static func _check_stage(where: String, id: StringName) -> PackedStringArray:
	if not StageLibrary.exists(id):
		return PackedStringArray(["%s 的場景「%s」不存在（%s）" % [where, id, StageLibrary.path_of(id)]])
	return StageLibrary.validate(id)


static func _check_step(where: String, kind: String, step: Dictionary, defined: Dictionary[String, bool]) -> PackedStringArray:
	var problems := PackedStringArray()
	match kind:
		"actor":
			var id := str(step.get("id", ""))
			defined[id] = true
			var skin := str(step.get("kind", ""))
			var portrait := str(step.get("portrait", ""))
			if skin == "" and portrait == "":
				problems.append("%s 的角色「%s」沒有指定骨架外觀（kind）或頭像（portrait）" % [where, id])
			elif skin != "" and RigLibrary.character(skin).is_empty() and RigLibrary.optional_texture(portrait) == null:
				problems.append("%s 的角色外觀「%s」不存在，也沒有可用的頭像" % [where, skin])
			if step.has("pose") and not CutsceneActor.POSES.has(str(step["pose"])):
				problems.append("%s 的動作「%s」不存在" % [where, step["pose"]])
		"pose", "move", "face", "remove":
			var id := str(step.get("id", ""))
			if not defined.has(id):
				problems.append("%s 引用了尚未出現的角色「%s」" % [where, id])
			if kind == "pose" and not CutsceneActor.POSES.has(str(step.get("pose", ""))):
				problems.append("%s 的動作「%s」不存在" % [where, step.get("pose", "")])
			if kind == "move" and step.has("pose") and not CutsceneActor.POSES.has(str(step["pose"])):
				problems.append("%s 的動作「%s」不存在" % [where, step["pose"]])
			if kind == "remove":
				defined.erase(id)
		"fx":
			if not FX_KINDS.has(str(step.get("kind", ""))):
				problems.append("%s 的特效「%s」不存在" % [where, step.get("kind", "")])
		"sfx":
			if not Sfx.has_sound(StringName(str(step.get("id", "")))):
				problems.append("%s 的音效「%s」未定義" % [where, step.get("id", "")])
		"transition":
			if Transition.kind_from_name(str(step.get("kind", ""))) < 0:
				problems.append("%s 的轉場「%s」不存在" % [where, step.get("kind", "")])
		"narrate":
			var lines: Variant = step.get("lines", [])
			if typeof(lines) != TYPE_ARRAY or (lines as Array).is_empty() or (lines as Array).size() > 3:
				problems.append("%s 的旁白要有 1 到 3 行" % where)
	return problems
