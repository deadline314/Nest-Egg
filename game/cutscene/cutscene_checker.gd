class_name CutsceneChecker
extends RefCounted
## 過場動畫資料檢查：步驟種類、必填欄位、引用的場景／角色／講者／音效／轉場是否存在、台詞數量。
## Story.validate() 在遊戲啟動與測試時呼叫；也可用 tools/cutscene_check.gd 單獨檢查。

const MAX_SAYS := 16
const MAX_SAY_RUN := 3
const MAX_SAY_LENGTH := 56
const MAX_TIME := 60.0
## 預估播放秒數的讀速：一句台詞 = SAY_BASE + SAY_PER_CHAR × 字數（玩家一般的閱讀與點擊速度）。場景可以用 budget 宣告預算（秒），超過就是問題。
const SAY_BASE := 1.0
const SAY_PER_CHAR := 0.08
const FX_KINDS: PackedStringArray = ["shake", "flash", "lightning", "noise", "tint", "rain", "vignette"]
const STYLES: PackedStringArray = ["normal", "whisper", "shout", "noise"]
const SUPPORTED_POSES: PackedStringArray = ["sit", "lean", "squat", "crouch", "kneel", "dead"]

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
	"choice": ["options", "default"],
	"branch": ["steps"],
}
## 畫面（舞台座標）的大小與中心；鏡頭預設在中心、縮放 1。
const STAGE_SIZE := Vector2(640, 360)
## 對話框蓋住畫面下緣約 25%（框頂約在 266／360 處）：演員的腳底在畫面上的位置不能低於這條線，腳會被框蓋住。
const FEET_MAX_SCREEN_Y := 266.0
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
	if scene.has("pose_policy") and scene["pose_policy"] != "supported":
		problems.append("動畫場景 %s 的 pose_policy 不存在" % scene_id)
	for raw: Variant in _expanded_steps(steps):
		index += 1
		var where := "動畫場景 %s 第 %d 步" % [scene_id, index]
		if typeof(raw) != TYPE_DICTIONARY:
			problems.append("%s 不是物件" % where)
			continue
		var step: Dictionary = raw
		var kind := str(step.get("do", ""))
		if scene.get("pose_policy", "") == "supported" and kind in ["actor", "pose", "move"]:
			for pose_key in ["pose", "then"]:
				if SUPPORTED_POSES.has(str(step.get(pose_key, ""))):
					for context_key in ["pose_reason", "pose_support"]:
						var context: Variant = step.get(context_key, "")
						if not context is String or (context as String).strip_edges().is_empty():
							problems.append("%s 的 %s 姿勢「%s」缺少非空文字 %s" % [where, pose_key, step[pose_key], context_key])
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
		if kind == "choice":
			problems.append_array(StoryRules.validate_choice(where, step))
		problems.append_array(_check_step(where, kind, step, defined))
		if kind == "scene":
			has_stage = true
			problems.append_array(_check_stage(where, StringName(str(step.get("id", "")))))
	if says > MAX_SAYS:
		problems.append("動畫場景 %s 有 %d 句台詞，上限 %d 句" % [scene_id, says, MAX_SAYS])
	if scene.has("budget"):
		var budget := float(scene["budget"])
		var estimate := estimate_seconds(scene)
		if budget <= 0.0:
			problems.append("動畫場景 %s 的 budget 必須是正數" % scene_id)
		elif estimate > budget:
			problems.append("動畫場景 %s 預估 %.0f 秒，超過預算 %.0f 秒（台詞每句約 %.1f 秒 + %.2f 秒 × 字數）" % [scene_id, estimate, budget, SAY_BASE, SAY_PER_CHAR])
	return problems


## 預估一份動畫場景的播放秒數（不含玩家額外停留）：台詞依字數、等待／淡出／特效／標題依各自的時間，會等待的移動與鏡頭依其時間。
static func estimate_seconds(scene: Dictionary) -> float:
	var total := 0.0
	var steps: Variant = scene.get("steps", [])
	if typeof(steps) != TYPE_ARRAY:
		return total
	for raw: Variant in steps:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var step: Dictionary = raw
		match str(step.get("do", "")):
			"say":
				total += SAY_BASE + SAY_PER_CHAR * float(str(step.get("text", "")).length())
			"narrate":
				var chars := 0
				for line: Variant in step.get("lines", []):
					chars += str(line).length()
				total += float(step.get("time", 2.2)) + 0.05 * float(chars)
			"title":
				total += float(step.get("time", 2.5)) + 0.8
			"wait", "fade", "fx":
				total += float(step.get("time", 0.5))
			"scene":
				total += float(step.get("fade", 0.0))
			"move", "camera":
				if bool(step.get("wait", false)):
					total += float(step.get("time", 1.0))
	return total


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


## 演出的構圖檢查（新寫的過場要通過；舊的過場資料不強制）：演員的腳底在畫面上的位置不被對話框蓋住。
## 依序追蹤鏡頭（scene、camera 步驟的 pos／zoom）與每個演員最後的位置（actor、move），
## 腳底的畫面 y = 畫面中心 + (舞台 y − 鏡頭 y) × 縮放。每個演員只回報一次。
static func staging_problems(scene_id: String, scene: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	var steps: Variant = scene.get("steps", [])
	if typeof(steps) != TYPE_ARRAY:
		return problems
	var cam := STAGE_SIZE * 0.5
	var zoom := 1.0
	var feet: Dictionary[String, Vector2] = {}
	var reported: Dictionary[String, bool] = {}
	var index := 0
	for step: Variant in steps:
		index += 1
		if typeof(step) != TYPE_DICTIONARY:
			continue
		var kind := str((step as Dictionary).get("do", ""))
		match kind:
			"scene", "camera":
				if (step as Dictionary).has("pos"):
					cam = StageLayers.vec2_of(step["pos"])
				if (step as Dictionary).has("zoom"):
					zoom = float(step["zoom"])
			"actor":
				feet[str(step.get("id", ""))] = StageLayers.vec2_of(step.get("pos"))
			"move":
				if feet.has(str(step.get("id", ""))):
					feet[str(step["id"])] = StageLayers.vec2_of(step.get("to"))
			"remove":
				feet.erase(str(step.get("id", "")))
			_:
				continue
		for id: String in feet:
			var screen_y := STAGE_SIZE.y * 0.5 + (feet[id].y - cam.y) * zoom
			if screen_y > FEET_MAX_SCREEN_Y and not reported.has(id):
				reported[id] = true
				problems.append("%s 第 %d 步：演員「%s」的腳底在畫面 y=%.0f，會被對話框蓋住（上限 %.0f）；把鏡頭中心往下移或降低縮放" % [scene_id, index, id, screen_y, FEET_MAX_SCREEN_Y])
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
			if step.has("layer") and (int(step["layer"]) < 0 or int(step["layer"]) >= WorldLayers.MAX_STAGE_ACTORS):
				problems.append("%s 的圖層組 layer 要在 0 到 %d 之間" % [where, WorldLayers.MAX_STAGE_ACTORS - 1])
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


static func _expanded_steps(raw: Array) -> Array:
	var result: Array = []
	for step: Variant in raw:
		result.append(step)
		if not step is Dictionary:
			continue
		if step.get("do") == "choice":
			var options: Variant = step.get("options", [])
			if options is Array:
				for option: Variant in options:
					if option is Dictionary and option.get("steps") is Array:
						result.append_array(_expanded_steps(option.steps))
		elif step.get("do") == "branch":
			for key in ["steps", "else_steps"]:
				if step.get(key) is Array:
					result.append_array(_expanded_steps(step[key]))
	return result
