class_name StoryOutcomes
extends RefCounted
const MAIN_FLAG_COMPLETION_POLICY := "main_flags_v1"
## 劇情段落的「段尾結果」與章節層級的事實表（ST-9）。全部由章節 JSON 描述，新增內容不改程式：
##
## 場景欄位
##   results: [{kind: flag, id, value}｜{kind: item_acquire, id}｜{kind: item_transfer, id}｜{kind: transaction, id}]
##       只在整段播完時一起生效：先預檢全部（原件在手上、交易可成立、物品存在），任一不成立就整段不生效。
##   on_failure: {交易拒絕原因: 場景 id}，例如現金不足時改接「不足額」的選擇場景。
## 章節欄位
##   transactions: {交易 id: {resource: res 路徑}}（正式金額與條件只在 StoryTransactionData 資源裡）
##   derived_flags: {旗標: 條件樹}，每段結果生效後重新計算並寫入（任務目錄讀得到）
##   （真實世界事件的旗標放在產生它的資料上：關卡的 channel_done_flags／channel_cleared_flags、物品的 acquire_flag）
##   runtime_facts: {旗標: 提供者}，讀取當下服務狀態、不存檔（deaths_zero、checkpoint_registered、always、context:<鍵>）
##   event_scenes: [{event: checkpoint, scene}]，對應世界事件第一次發生時播放（播過不重播）

const RUNTIME_PROVIDERS := ["deaths_zero", "has_deaths", "checkpoint_registered", "always"]

var transactions: Dictionary = {}
var derived_flags: Dictionary = {}
var runtime_facts: Dictionary = {}
var event_scenes: Array[Dictionary] = []
## 進行中演出鏈提供的情境事實（例如「真正的初次建檔」）；演出結束或取消即清除。
var context_facts: Dictionary = {}
var _transaction_cache: Dictionary = {}


func clear() -> void:
	transactions.clear()
	derived_flags.clear()
	runtime_facts.clear()
	event_scenes.clear()
	context_facts.clear()
	_transaction_cache.clear()


## 合併一份章節的表；格式錯誤記錄具體位置並略過該筆，不影響其他內容。
func merge_chapter(data: Dictionary, path: String) -> void:
	for key in ["transactions", "derived_flags", "runtime_facts"]:
		var raw: Variant = data.get(key, {})
		if not raw is Dictionary:
			push_error("[StoryOutcomes] %s 的 %s 必須是物件，已略過" % [path, key])
			continue
		var target: Dictionary = get(key)
		for name: Variant in raw:
			target[str(name)] = raw[name]
	for key in ["event_scenes"]:
		var list: Variant = data.get(key, [])
		if not list is Array:
			push_error("[StoryOutcomes] %s 的 %s 必須是陣列，已略過" % [path, key])
			continue
		for i in (list as Array).size():
			if list[i] is Dictionary:
				(get(key) as Array).append(list[i])
			else:
				push_error("[StoryOutcomes] %s 的 %s[%d] 不是物件，已略過" % [path, key, i])


## 讀取一個旗標事實：執行期事實 > 情境事實 > 本輪旗標。未知提供者記錄後回 false。
func flag_value(name: StringName) -> Variant:
	var key := String(name)
	if runtime_facts.has(key):
		return _runtime_fact(key, str(runtime_facts[key]))
	return GameState.get_flag(name)


func _runtime_fact(name: String, provider: String) -> bool:
	if provider.begins_with("context:"):
		return bool(context_facts.get(provider.substr(8), false))
	match provider:
		"deaths_zero":
			return GameState.deaths == 0
		"has_deaths":
			return GameState.deaths > 0
		"checkpoint_registered":
			return GameState.has_checkpoint
		"always":
			return true
	push_warning("[StoryOutcomes] runtime_facts.%s 的提供者「%s」未知，視為不成立" % [name, provider])
	return false


func transaction(id: StringName) -> StoryTransactionData:
	var key := String(id)
	if _transaction_cache.has(key):
		return _transaction_cache[key]
	var entry: Variant = transactions.get(key, {})
	var path := str((entry as Dictionary).get("resource", "")) if entry is Dictionary else ""
	var resource: StoryTransactionData = load(path) as StoryTransactionData if not path.is_empty() and ResourceLoader.exists(path) else null
	if resource == null:
		push_error("[StoryOutcomes] transactions.%s 的資源不存在或型別不符：%s" % [key, path])
	_transaction_cache[key] = resource
	return resource


func receipt_recorded(id: StringName) -> bool:
	return str(Progression.story_receipt_status(id).get("status", "")) == "recorded"


## 餐帳狀態：只由正式收據組合推出，不另存一份帳（組合規則與 StoryConditionTree 相同）。
func account_state(_account: StringName) -> String:
	var mask := 0
	for i in StoryConditionTree.MEAL_IDS.size():
		if receipt_recorded(StringName(StoryConditionTree.MEAL_IDS[i])):
			mask |= 1 << i
	return str(StoryConditionTree.ACCOUNT_MASKS.get(mask, "invalid"))


static func operations(scene: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw: Variant = scene.get("results", [])
	if raw is Array:
		for op: Variant in raw:
			if op is Dictionary:
				result.append(op)
	return result


## Validate the unfiltered payload before any payment or item mutation. The same
## contract is used by content validation; operations() is only a typed view.
func result_contract_problem(scene_id: StringName, scene: Dictionary) -> String:
	var where := "場景 %s" % String(scene_id).left(256)
	if scene.has("completion_policy") and scene["completion_policy"] not in [MAIN_FLAG_COMPLETION_POLICY, "main_terminal_results_v1"]:
		return where + " 的 completion_policy 不受支援"
	var results: Variant = scene.get("results", [])
	var flags: Variant = scene.get("set_flags", [])
	var tree := RunSaveCodec.validate_tree({"results": results, "set_flags": flags}, 32768)
	if not tree.is_empty():
		return "%s 的結果：%s" % [where, tree[0]]
	if not results is Array:
		return "%s 的 results 必須是陣列" % where
	if not flags is Array:
		return "%s 的 set_flags 必須是陣列" % where
	for i in flags.size():
		var id: Variant = flags[i]
		if typeof(id) not in [TYPE_STRING, TYPE_STRING_NAME] or String(id).is_empty():
			return "%s 的 set_flags[%d] 必須是非空旗標名稱" % [where, i]
		if GameState.flag_defaults.has(String(id)) and not GameState.flag_defaults[String(id)] is bool:
			return "%s 的 set_flags[%d]：%s 不是布林旗標" % [where, i, id]
	for i in results.size():
		var op: Variant = results[i]
		var at := "%s 的 results[%d]" % [where, i]
		if not op is Dictionary:
			return at + " 必須是物件"
		for key: String in ["kind", "id"]:
			var raw: Variant = op.get(key)
			if typeof(raw) not in [TYPE_STRING, TYPE_STRING_NAME] or String(raw).is_empty():
				return at + " 的 " + key + " 必須是非空文字"
		if str(op["kind"]) not in ["flag", "item_acquire", "item_transfer", "transaction"]:
			return at + " 的結果種類未知：" + str(op["kind"])
		if scene.get("completion_policy", "") == MAIN_FLAG_COMPLETION_POLICY and str(op["kind"]) != "flag":
			return at + " 超出 main_flags_v1 的旗標範圍"
		if str(op["kind"]) == "flag":
			var value: Variant = op.get("value", true)
			if not GameState._flag_value_valid(value):
				return at + " 的旗標值必須是有限純量"
			var id := String(op["id"])
			if GameState.flag_defaults.has(id):
				var fallback: Variant = GameState.flag_defaults[id]
				# Match the existing save owner: JSON 2.0 may represent integer 2.
				if typeof(value) != typeof(fallback) and not (value is float and fallback is int and value == floor(value)):
					return at + " 的旗標值與宣告型別不符：" + id
	return ""


## 預檢整段結果；回傳 {ok, reason, failure_scene, where}。不改任何狀態。
func preflight(scene_id: StringName, scene: Dictionary, transfers: Array[StringName]) -> Dictionary:
	var problem := result_contract_problem(scene_id, scene)
	if not problem.is_empty():
		return {"ok": false, "reason": "invalid_results", "failure_scene": "", "where": problem}
	for item in transfers:
		if not StoryItems.holds(item):
			return {"ok": false, "reason": "item_not_held", "failure_scene": "", "where": "%s 交出 %s" % [scene_id, item]}
	var local_ledger := StoryTransactionLedger.new()
	local_ledger.restore(Progression._story_transactions.snapshot(), true)
	var wallet := Progression.credits
	for op in operations(scene):
		var id := StringName(str(op.get("id", "")))
		match str(op.get("kind", "")):
			"item_transfer":
				if not StoryItems.holds(id):
					return {"ok": false, "reason": "item_not_held", "failure_scene": "", "where": "%s 交出 %s" % [scene_id, id]}
			"item_acquire":
				if StoryItems.find(id) == null:
					return {"ok": false, "reason": "unknown_item", "failure_scene": "", "where": "%s 取得 %s" % [scene_id, id]}
			"transaction":
				var resource := transaction(id)
				var status := local_ledger.commit(resource, wallet, Progression.MAX_CREDITS)
				if status["applied"]:
					wallet = status["credits_after"]
				else:
					var reason := str(status.get("status", "invalid_definition"))
					var failures: Variant = scene.get("on_failure", {})
					var fallback := str((failures as Dictionary).get(reason, "")) if failures is Dictionary else ""
					return {"ok": false, "reason": reason, "failure_scene": fallback, "where": "%s 交易 %s" % [scene_id, id]}
			"flag":
				pass
			_:
				return {"ok": false, "reason": "unknown_operation", "failure_scene": "", "where": "%s 結果種類 %s" % [scene_id, op.get("kind", "")]}
	return {"ok": true, "reason": "", "failure_scene": "", "where": ""}


## 套用已預檢的結果：交易 → 旗標 → 交出 → 取得 → 重新計算衍生旗標。交易在提交時仍被拒絕就停在原處並回 false。
func commit(scene_id: StringName, scene: Dictionary, transfers: Array[StringName]) -> bool:
	var ops := operations(scene)
	for op in ops:
		if str(op.get("kind", "")) == "transaction":
			var committed := Progression.apply_story_transaction(transaction(StringName(str(op["id"]))))
			if not bool(committed.get("applied", false)):
				push_error("[StoryOutcomes] %s 的交易 %s 在提交時被拒絕（%s），段尾結果未生效" % [scene_id, op["id"], committed.get("status", "")])
				return false
	var flags: Variant = scene.get("set_flags", [])
	if flags is Array:
		for flag: Variant in flags:
			GameState.set_flag(StringName(str(flag)))
	for op in ops:
		if str(op.get("kind", "")) == "flag":
			GameState.set_flag(StringName(str(op["id"])), op.get("value", true))
	for item in transfers:
		StoryItems.transfer(item)
	for op in ops:
		match str(op.get("kind", "")):
			"item_transfer":
				StoryItems.transfer(StringName(str(op["id"])))
			"item_acquire":
				StoryItems.acquire(StringName(str(op["id"])))
	refresh_derived()
	return true


## 衍生旗標依條件重算並寫入本輪旗標（例如四張標籤都讀過）。只在值改變時寫入。
func refresh_derived() -> void:
	for name: String in derived_flags:
		var value := StoryRules.holds(derived_flags[name])
		if GameState.get_flag(StringName(name)) != value:
			# 衍生值可由其他旗標重算：不另外請求保存，觸發它的結果或讀檔流程自己會保存。
			GameState.set_flag(StringName(name), value, false)


func scenes_for_event(event: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for entry in event_scenes:
		if str(entry.get("event", "")) == String(event) and not str(entry.get("scene", "")).is_empty():
			result.append(StringName(str(entry["scene"])))
	return result


## 載入檢查：交易資源存在、條件樹格式正確、事件場景與事實提供者寫法正確。回傳問題清單（含位置）。
func validate(has_scene: Callable) -> PackedStringArray:
	var problems := PackedStringArray()
	for id: String in transactions:
		var entry: Variant = transactions[id]
		var path := str((entry as Dictionary).get("resource", "")) if entry is Dictionary else ""
		if path.is_empty() or not ResourceLoader.exists(path):
			problems.append("transactions.%s 的資源不存在：%s" % [id, path])
	for name: String in derived_flags:
		var checked := StoryConditionTree.validate(derived_flags[name])
		if not checked["valid"]:
			problems.append("derived_flags.%s 條件無效：%s" % [name, checked["error"]])
	for name: String in runtime_facts:
		var provider := str(runtime_facts[name])
		if not provider.begins_with("context:") and not RUNTIME_PROVIDERS.has(provider):
			problems.append("runtime_facts.%s 的提供者未知：%s" % [name, provider])
	for i in event_scenes.size():
		var scene := str(event_scenes[i].get("scene", ""))
		if not bool(has_scene.call(StringName(scene))):
			problems.append("event_scenes[%d] 的場景不存在：%s" % [i, scene])
	return problems


## 場景層級的結果與交易失敗分支格式。
func validate_scene(scene_id: String, scene: Dictionary, has_scene: Callable) -> PackedStringArray:
	var problems := PackedStringArray()
	var problem := result_contract_problem(StringName(scene_id), scene)
	if not problem.is_empty():
		problems.append(problem)
		return problems
	for op in operations(scene):
		var kind := str(op.get("kind", ""))
		var id := str(op.get("id", ""))
		if id.is_empty():
			problems.append("場景 %s 的結果缺少 id" % scene_id)
		elif kind in ["item_acquire", "item_transfer"] and StoryItems.find(StringName(id)) == null:
			problems.append("場景 %s 的結果引用不存在的物品：%s" % [scene_id, id])
		elif kind == "transaction" and not transactions.has(id):
			problems.append("場景 %s 的交易未登記在 transactions：%s" % [scene_id, id])
		elif kind not in ["flag", "item_acquire", "item_transfer", "transaction"]:
			problems.append("場景 %s 的結果種類未知：%s" % [scene_id, kind])
	var failures: Variant = scene.get("on_failure", {})
	if failures is Dictionary:
		for reason: Variant in failures:
			if not bool(has_scene.call(StringName(str(failures[reason])))):
				problems.append("場景 %s 的 on_failure.%s 指向不存在的場景" % [scene_id, reason])
	if scene.has("when"):
		var checked := StoryConditionTree.validate(scene["when"])
		if not checked["valid"]:
			problems.append("場景 %s 的 when 條件無效：%s" % [scene_id, checked["error"]])
	return problems
