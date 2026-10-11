extends RefCounted
## Real autoload owner regressions. No fixture service and no production capability.

const Bundle = preload("res://core/story_install_bundle.gd")
const FIRST := "res://data/levels/ch1_pawnshop.tres"
const DISK := &"ch1_data_disk"
const CLOTH := &"ch1_grey_cloth"
const ORDER := "ch1.revival_meal.order"
const PAID := "ch1.revival_meal.paid"


static func _bytes() -> PackedByteArray:
	return var_to_bytes([GameState._install_source(), Progression.snapshot(), StoryItems.snapshot(), Story._install_source()])


static func _capture() -> Dictionary:
	return RunSnapshot.capture(FIRST, {"position": [100, 160], "health": 4, "world": {}, "loadout": {}})


static func _resources() -> Dictionary:
	var result: Dictionary = {}
	# 固定用第一章的七筆交易當夾具（之後章節新增的交易不影響這組檢查）。
	for resource: StoryTransactionData in ResourceCatalog.load_dir("res://data/story_transactions", StoryTransactionData, "StoryInstallChecks"):
		if String(resource.id).begins_with("ch1."):
			result[String(resource.id)] = resource
	return result


static func _ledger(resources: Dictionary, ids: Array, wallet: int) -> Dictionary:
	var ledger := StoryTransactionLedger.new()
	for id: String in ids:
		var result := ledger.commit(resources[id], wallet, Progression.MAX_CREDITS)
		if not result["applied"]:
			return {"error": result["status"]}
		wallet = result["credits_after"]
	return {"ledger": ledger.snapshot(), "wallet": wallet}


static func _refused(s: TestSuite, raw: Dictionary, label: String) -> void:
	var before := _bytes()
	var inputs := var_to_bytes(raw)
	var result := RunSnapshot.prepare_install(raw)
	s.check(result.has("error"), "typed install refuses " + label)
	s.check(_bytes() == before and var_to_bytes(raw) == inputs, "refused preparation leaves all live owners and input unchanged: " + label)


static func _scene() -> String:
	for id: String in Story._scenes:
		if not Story._completed.has(StringName(id)):
			return id
	return ""


static func _projection() -> Dictionary:
	return {"flags": GameState.world_flags.duplicate(true), "credits": Progression.credits,
		"ledger": Progression.snapshot()["story_transactions"], "items": StoryItems.snapshot(),
		"area_states": GameState.area_states.duplicate(true), "completed": Story.progress_snapshot()}


static func run(s: TestSuite) -> void:
	var defaults := GameState.flag_defaults.duplicate(true)
	GameState.story_autosave = false
	GameState.register_flag_defaults({"install_test_bool": false, "install_test_count": 0}, "tests/story_install")
	GameState.start_new_run(GameState.difficulties[1])
	Progression.restore({"version": 1, "credits": 1000, "upgrades": {"pistol": ["quick_reload"]},
		"abilities": ["emp_pulse", "overclock"], "equipped": "overclock", "pawned": {"med_injector": 2}})
	GameState.checkpoint_loadout = {"weapons": ["res://data/weapons/pistol.tres"], "mag": [7], "reserve": [-1], "active": 0, "consumables": {"med_injector": 1}}
	GameState.level_start_loadout = GameState.checkpoint_loadout.duplicate(true)
	GameState._carried_loadout = GameState.checkpoint_loadout.duplicate(true)
	GameState.area_state(&"install_test_area")
	var resources := _resources()
	s.check(resources.size() == 7 and StoryItems.find(DISK) != null and StoryItems.find(CLOTH) != null, "typed owner checks use all seven canonical transactions and real item catalog")
	if resources.size() != 7:
		GameState.flag_defaults = defaults
		return
	var scene := _scene()
	s.check(not scene.is_empty(), "typed completion uses a real loaded scene")
	if scene.is_empty():
		GameState.flag_defaults = defaults
		return
	var valid := _capture()
	var baseline := _bytes()
	var events := {"count": 0}
	var on_credits := func(_credits: int, _delta: int) -> void: events["count"] += 1
	var on_simple := func() -> void: events["count"] += 1
	var on_id := func(_id: StringName) -> void: events["count"] += 1
	var on_item := func(_item: StoryItemData) -> void: events["count"] += 1
	var on_lives := func(_lives: int) -> void: events["count"] += 1
	var on_request := func(_request: int, _completed: bool) -> void: events["count"] += 1
	var on_cancel := func(_scene: StringName, _context: Dictionary, _reason: StringName, _request: int) -> void: events["count"] += 1
	Progression.credits_changed.connect(on_credits)
	Progression.upgrades_changed.connect(on_simple)
	Progression.abilities_changed.connect(on_simple)
	Progression.pawned_changed.connect(on_simple)
	Progression.story_transaction_committed.connect(on_id)
	StoryItems.acquired.connect(on_item)
	StoryItems.transferred.connect(on_item)
	Story.scene_finished.connect(on_id)
	Story.request_settled.connect(on_request)
	Story.presentation_cancelled.connect(on_cancel)
	EventBus.lives_changed.connect(on_lives)
	GameState.run_save_requested.connect(on_simple)
	var saved_exists := FileAccess.file_exists(GameState.STORY_SAVE_PATH)
	var saved_text := FileAccess.get_file_as_string(GameState.STORY_SAVE_PATH) if saved_exists else ""
	# These fail before the first owner assignment, including late-owner errors.
	var bad := valid.duplicate(true)
	bad["version"] = 999
	_refused(s, bad, "future whole-run version")
	bad = valid.duplicate(true)
	bad["progression"]["version"] = 999
	_refused(s, bad, "future progression version")
	bad = valid.duplicate(true)
	bad["state"]["checkpoint_progress"]["version"] = 999
	_refused(s, bad, "future embedded checkpoint progression version")
	bad = valid.duplicate(true)
	bad["story"]["version"] = 999
	_refused(s, bad, "future story version")
	bad = valid.duplicate(true)
	bad["story"]["items"]["custody_version"] = 999
	_refused(s, bad, "future custody version")
	bad = valid.duplicate(true)
	bad["progression"]["story_transactions"] = {"version": 999, "receipts": {}}
	_refused(s, bad, "future ledger version")
	bad = valid.duplicate(true)
	bad["story"]["flags"]["install_test_bool"] = "wrong"
	_refused(s, bad, "wrong declared flag type")
	bad = valid.duplicate(true)
	bad["state"]["future_owner_state"] = true
	_refused(s, bad, "unknown future state owner field")
	bad = valid.duplicate(true)
	bad["story"]["future_companion_state"] = true
	_refused(s, bad, "unknown future story owner field")
	bad = valid.duplicate(true)
	bad["progression"]["upgrades"]["pistol"].append("future_upgrade")
	_refused(s, bad, "unknown upgrade")
	bad = valid.duplicate(true)
	bad["progression"]["abilities"].append("future_ability")
	_refused(s, bad, "unknown ability")
	bad = valid.duplicate(true)
	bad["progression"]["equipped"] = "future_ability"
	_refused(s, bad, "unlocked/equipped mismatch")
	bad = valid.duplicate(true)
	bad["progression"]["pawned"] = {"future_consumable": 1}
	_refused(s, bad, "unknown pawned consumable")
	bad = valid.duplicate(true)
	bad["story"]["items"]["owned"].append("future_item")
	_refused(s, bad, "unknown story item")
	bad = valid.duplicate(true)
	bad["story"]["seen"].append("future_scene")
	_refused(s, bad, "unknown completed scene")
	var paid := _ledger(resources, [ORDER, PAID], Progression.credits)
	s.check(not paid.has("error"), "actual canonical order then paid ledger prepares without touching live wallet")
	if paid.has("error"):
		paid = {"ledger": {"version": 1, "receipts": {}}, "wallet": Progression.credits}
	bad = valid.duplicate(true)
	bad["progression"]["story_transactions"] = paid["ledger"].duplicate(true)
	bad["progression"]["story_transactions"]["receipts"][PAID]["credits_delta"] += 1
	_refused(s, bad, "canonical receipt delta mismatch")
	bad = valid.duplicate(true)
	bad["progression"]["story_transactions"] = paid["ledger"].duplicate(true)
	bad["progression"]["story_transactions"]["receipts"][PAID]["definition_fingerprint"] = "0".repeat(64)
	_refused(s, bad, "canonical receipt fingerprint mismatch")
	bad = valid.duplicate(true)
	bad["progression"]["story_transactions"] = paid["ledger"].duplicate(true)
	var gift: Dictionary = resources["ch1.revival_meal.gift"].descriptor()
	bad["progression"]["story_transactions"]["receipts"][gift["id"]] = {"definition_fingerprint": gift["fingerprint"], "credits_delta": gift["credits_delta"]}
	_refused(s, bad, "mutually exclusive paid and gift receipts")
	s.check(_bytes() == baseline and events["count"] == 0, "all failed owner preparations emit no notification/save/reset and preserve exact live state")
	# Every supported resource is proved through a legal canonical receipt path.
	for ids: Array in [["ch1.daily_dinner"], ["ch1.commission.settled"], [ORDER], [ORDER, PAID], [ORDER, "ch1.revival_meal.tab"], [ORDER, "ch1.revival_meal.gift"], [ORDER, "ch1.revival_meal.tab", "ch1.revival_meal.later_pay"]]:
		var preview := _ledger(resources, ids, Progression.credits)
		var raw := Progression.snapshot()
		raw["credits"] = preview.get("wallet", Progression.credits)
		raw["story_transactions"] = preview.get("ledger", {})
		s.check(not preview.has("error") and Progression.prepare_install(raw).has("data"), "typed wallet accepts actual canonical receipt path: " + str(ids))
	s.check(_bytes() == baseline, "successful canonical preparations remain pure against actual owners")
	var target := valid.duplicate(true)
	target["progression"]["credits"] = paid["wallet"]
	target["progression"]["story_transactions"] = paid["ledger"]
	target["story"]["flags"]["install_test_bool"] = true
	target["story"]["flags"]["install_test_count"] = 3
	target["story"]["seen"].append(scene)
	for id: StringName in [DISK, CLOTH]:
		target["story"]["items"]["owned"].append(id)
		target["story"]["items"]["unseen"].append(id)
	target["story"]["items"]["held"].append(CLOTH)
	target["story"]["items"]["transferred"].append(DISK)
	target["state"]["deaths"] = 4
	target["state"]["kills"] = 9
	target["state"]["area_states"]["install_test_area"]["consumed"]["ch1_data_disk@1,2"] = true
	var first := RunSnapshot.prepare_install(target)
	var second := RunSnapshot.prepare_install(target)
	s.check(first.has("data") and second.has("data") and _bytes() == baseline, "two whole-run bundles allocate complete owner state without changing live data")
	if first.has("data") and second.has("data"):
		var bundle: StoryInstallBundle = first["data"]
		var competing: StoryInstallBundle = second["data"]
		target["progression"]["credits"] = 1
		target["story"]["flags"]["install_test_bool"] = false
		target["story"]["items"]["owned"].clear()
		target["state"]["checkpoint_loadout"]["weapons"].clear()
		s.check(bundle.preflight().get("ready", false), "changing caller input cannot alter or stale detached prepared owner state")
		s.check(bundle.install_silent().get("installed", false), "whole-run prepared data owners install synchronously")
		s.check(events["count"] == 0, "silent assignment publishes no credits/items/scene/request/lives/save notification")
		s.check(Progression.credits == paid["wallet"] and Progression.story_receipt_status(StringName(PAID))["status"] == "recorded" and GameState.get_flag(&"install_test_bool") == true and Story._completed.has(StringName(scene)), "wallet receipt flags and completion are coherently installed")
		s.check(StoryItems.owns(DISK) and not StoryItems.holds(DISK) and StoryItems.was_transferred(DISK) and StoryItems.holds(CLOTH), "silent custody installs history/current/transferred independently")
		s.check(GameState.deaths == 4 and GameState.kills == 9 and GameState.area_states["install_test_area"]["consumed"]["ch1_data_disk@1,2"], "complete run statistics and area markers install before external observation")
		s.check(Progression.snapshot()["upgrades"] == valid["progression"]["upgrades"] and Progression.equipped_ability().id == &"overclock" and Progression.pawned_count(&"med_injector") == 2, "prepared install preserves canonical upgrades abilities equipped ability and pawn tickets")
		s.check(GameState.checkpoint_loadout["weapons"] == ["res://data/weapons/pistol.tres"] and GameState.level_start_loadout["weapons"] == ["res://data/weapons/pistol.tres"] and GameState._carried_loadout.is_empty(), "whole-run checkpoint/entry loadout survives input mutation while transient carried loadout resets")
		var installed := _bytes()
		s.check(bundle.install_silent().has("error") and competing.install_silent().has("error") and _bytes() == installed, "consumed bundle and competing stale bundle cannot reinstall or partially write")
		var observed := {"coherent": false}
		var observer := func(_credits: int, _delta: int) -> void:
			observed["coherent"] = Progression.story_receipt_status(StringName(PAID))["status"] == "recorded" and GameState.get_flag(&"install_test_bool") == true and StoryItems.was_transferred(DISK) and Story._completed.has(StringName(scene)) and GameState.deaths == 4
		Progression.credits_changed.connect(observer)
		s.check(Progression.spend(20) and observed["coherent"], "first subsequent real service notification observes all coherent installed owners")
		Progression.credits_changed.disconnect(observer)
		s.check(bundle.install_silent().has("error") and Progression.credits == paid["wallet"] - 20, "later ordinary spending is never replaced by a previously installed proposal")
	_test_batches(s, scene, events)
	s.check(FileAccess.file_exists(GameState.STORY_SAVE_PATH) == saved_exists and (not saved_exists or FileAccess.get_file_as_string(GameState.STORY_SAVE_PATH) == saved_text), "preparation/silent install never writes the real legacy story file")
	Progression.credits_changed.disconnect(on_credits)
	Progression.upgrades_changed.disconnect(on_simple)
	Progression.abilities_changed.disconnect(on_simple)
	Progression.pawned_changed.disconnect(on_simple)
	Progression.story_transaction_committed.disconnect(on_id)
	StoryItems.acquired.disconnect(on_item)
	StoryItems.transferred.disconnect(on_item)
	Story.scene_finished.disconnect(on_id)
	Story.request_settled.disconnect(on_request)
	Story.presentation_cancelled.disconnect(on_cancel)
	EventBus.lives_changed.disconnect(on_lives)
	GameState.run_save_requested.disconnect(on_simple)
	Story.reset_active_presentation(&"new_run")
	GameState.flag_defaults = defaults


static func _test_batches(s: TestSuite, completed: String, events: Dictionary) -> void:
	GameState._carried_loadout = GameState.checkpoint_loadout.duplicate(true)
	var projection := _projection()
	var prepared := Bundle.prepare_story(projection)
	s.check(prepared.has("data"), "story-only bundle uses current canonical owner state")
	if prepared.has("data"):
		var stale: StoryInstallBundle = prepared["data"]
		Progression.spend(1)
		var before := _bytes()
		s.check(stale.preflight().has("error") and stale.install_silent().has("error") and _bytes() == before, "ordinary spend between prepare/install stales the whole bundle before any write")
	var raw := _projection()
	raw["future_world_handler"] = true
	var before := _bytes()
	s.check(Bundle.prepare_story(raw).has("error") and _bytes() == before, "unknown future story capability is explicitly refused without a handler")
	raw = _projection()
	raw["ledger"]["receipts"].erase(PAID)
	s.check(Bundle.prepare_story(raw).has("error") and _bytes() == before, "batch cannot erase an existing canonical receipt")
	raw = _projection()
	raw["completed"].erase(StringName(completed))
	s.check(Bundle.prepare_story(raw).has("error") and _bytes() == before, "batch cannot erase an earlier completed segment")
	# Use a real Story request to prove preparation/installation never settles it.
	var pending := &""
	for id: String in Story._scenes:
		if Story.scene_mode(StringName(id)) == Story.MODE_RADIO and not Story._completed.has(StringName(id)) and not Story.resolved_lines(StringName(id)).is_empty():
			pending = StringName(id)
			break
	s.check(pending != &"" and Story.play(pending, false), "batch reservation test starts an actual loaded radio request")
	if pending != &"" and Story._passive_requests.has(pending):
		var requests: Array = Story._passive_requests[pending].duplicate()
		var request_state := var_to_bytes(Story._install_source())
		before = _bytes()
		s.check(RunSnapshot.prepare_install(_capture()).has("error") and _bytes() == before, "whole-run preparation refuses active presentation without cancellation or waiter callbacks")
		prepared = Bundle.prepare_story(_projection())
		s.check(prepared.has("data"), "story batch can prepare while preserving actual pending reservation")
		if prepared.has("data"):
			var batch: StoryInstallBundle = prepared["data"]
			var count: int = events["count"]
			s.check(batch.install_silent().get("installed", false) and Story.was_seen(pending) and not Story._completed.has(pending) and Story._passive_requests[pending] == requests, "silent batch retains pending _seen/request while leaving it uncompleted")
			s.check(events["count"] == count, "pending-request batch emits no completion/cancellation/item/save callback")
			s.check(var_to_bytes(Story._install_source()) == request_state and not GameState._carried_loadout.is_empty(), "batch keeps complete presentation state and carried loadout untouched")
		Story.reset_active_presentation(&"new_run")
	# Preparation remains stale if a flag, item, area or generation changes later.
	for kind: String in ["flag", "custody", "area", "generation"]:
		prepared = Bundle.prepare_story(_projection())
		s.check(prepared.has("data"), "fresh bundle prepares before " + kind + " stale test")
		if not prepared.has("data"):
			continue
		var stale: StoryInstallBundle = prepared["data"]
		match kind:
			"flag": GameState.set_flag(&"install_test_count", 8)
			"custody": StoryItems.mark_seen(CLOTH)
			"area": GameState.area_state(&"install_test_area")["consumed"]["another@3,4"] = true
			"generation": Story.reset_active_presentation(&"new_run")
		before = _bytes()
		s.check(stale.install_silent().has("error") and _bytes() == before, "stale " + kind + " bundle rejects before any owner assignment")
