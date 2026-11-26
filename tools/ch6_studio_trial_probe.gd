extends "res://tools/ch6_relay_water_probe.gd"
## Development probe. Requires a real ST51 completed slot copied to --save-dir.

const CANOPY_SU := &"ch6_su_canopy"
const BOOTH_SU := &"ch6_su_booth"
const MONITOR := &"ch6_trial_monitor"
const MET := &"ch6_su_studio_met"
const TRIAL := &"ch6_trial_broadcast_confirmed"
const MEET := &"ch6_t_meet_su_studio"
const TAKE := &"ch6_t_studio_trial"
const ORIGINAL := &"ch4_original_ledger_copy"


func _write() -> void:
	if not await _resume_to(YARD):
		return
	var store := _main.get("_run_store") as RunSaveStore
	var before := store.read()
	_check(GameState.has_flag(POWERED) and StoryItems.holds(ORIGINAL), "the genuine paid ST51 save carries relay power and its ledger copy")
	_check(_actor_present(CANOPY_SU) and not GameState.has_flag(MET), "Su is at the canopy on the established route")
	_check_su_rig(CANOPY_SU)
	if not await _portal(&"relay_recording", RECORDING):
		return
	_check(not _actor_present(BOOTH_SU), "the booth is safely accessible before meeting Su")
	await _service(MONITOR)
	_check(_played.has("ch6_t_trial_wait_for_su") and not GameState.has_flag(TRIAL), "the monitor gives an explicit placement hint without authorizing trial")
	if not await _portal(&"recording_relay", YARD):
		return

	await _service(CANOPY_SU, [], MEET)
	_check(_actor_present(CANOPY_SU) and not GameState.has_flag(MET),
			"cancelled introduction leaves Su on the same side of the door")
	if _native_studio_proof():
		_shots[String(MEET)] = "ST-52-canopy"
	await _service(CANOPY_SU)
	_shots.clear()
	_check(_flag_is_saved(store, MET) and not _actor_present(CANOPY_SU),
			"full introduction records one durable move from the canopy")
	_check_audit()
	if not await _portal(&"relay_recording", RECORDING):
		return
	_check(_actor_present(BOOTH_SU), "the established Su is by the mic after meeting her once")
	_check_su_rig(BOOTH_SU)
	await _service(MONITOR)
	_check(_played.has("ch6_t_trial_read_scope") and not GameState.has_flag(TRIAL),
			"the captions teach the permissions and the private feed, preserving the unconfirmed state")
	await _probe_legacy_blank_slate()
	await _service(BOOTH_SU, ["leave"])
	await _service(BOOTH_SU, ["check_line"], TAKE)
	_check(not GameState.has_flag(TRIAL), "leaving and skipping do not approve the local feed")
	if _native_studio_proof():
		_shots[String(TAKE)] = "ST-52-studio"
	await _service(BOOTH_SU, ["check_line"])
	_shots.clear()
	_check(_flag_is_saved(store, TRIAL), "the one completed authorized sample is durable")
	_check(not GameState.has_flag(&"ch6_broadcast_started") and StoryItems.holds(ORIGINAL),
			"trial leaves public broadcasting pending and the original copy in Rin's hands")
	var after := store.read()
	_check(before["story"]["items"] == after["story"]["items"] and before["progression"] == after["progression"]
			and before["story"]["deaths"] == after["story"]["deaths"] and before["runtime"]["loadout"] == after["runtime"]["loadout"],
			"the studio stage preserves custody, paid receipt, credits, deaths and equipment")
	await _service(MONITOR)
	_check(_played.has("ch6_t_trial_monitor_ready") and _played.count(String(TAKE)) == 2,
			"the monitor reopens approved text without repeating the completed trial")
	_check_audit()


## Temporary accepted missing-document state in the isolated fixture only.
func _probe_legacy_blank_slate() -> void:
	var real := StoryItems.snapshot()
	var legacy := real.duplicate(true)
	for key in ["owned", "held", "unseen"]:
		legacy[key].erase(ORIGINAL)
	_check(StoryItems.restore(legacy) and not StoryItems.holds(ORIGINAL),
			"the isolated legacy condition lacks the original copy")
	_check(Story.resolve_dispatch(&"ch6_dispatch_su_booth") == &"ch6_t_choose_blank_trial"
			and Story.scene_available(TAKE), "missing copy enables only the local blank slate")
	await _service(BOOTH_SU, ["leave"])
	_check(_played.has("ch6_t_choose_blank_trial") and not GameState.has_flag(TRIAL)
			and not StoryItems.holds(ORIGINAL), "cancelled blank rehearsal preserves custody and pending state")
	_check(StoryItems.restore(real), "restored the genuine predecessor's custody for the normal route")


func _continue() -> void:
	if not await _resume_to(RECORDING):
		return
	_check(GameState.has_flag(MET) and GameState.has_flag(TRIAL) and not GameState.has_flag(&"ch6_broadcast_started"),
			"cold Continue returns to the same completed private studio state")
	_check(_actor_present(BOOTH_SU) and not _played.has(String(TAKE)),
			"neither introduction nor sample replays on Continue")
	await _service(MONITOR)
	_check(_played.has("ch6_t_trial_monitor_ready") and StoryItems.holds(ORIGINAL),
			"approved text is available after reload with the original copy")


func _actor_present(id: StringName) -> bool:
	var actor := _object(id)
	return is_instance_valid(actor) and actor.is_present()


func _native_studio_proof() -> bool:
	return DisplayServer.get_name() != "headless" and OS.get_cmdline_user_args().has("--studio-proof")


func _check_su_rig(id: StringName) -> void:
	var npc := _object(id)
	var actor: CutsceneActor = npc._actor if is_instance_valid(npc) else null
	var rig: CharacterRig = actor.rig if is_instance_valid(actor) else null
	_check(rig != null and rig.bone_order().size() == 16 and rig._parts.size() == 15
			and rig.has_bone(&"foot_back") and rig.has_bone(&"foot_front"),
			"the real level actor uses Su's complete live rig at %s" % id)
	_check(ResourceLoader.exists("res://art/portraits/su.png", "Texture2D"), "Su's authored portrait is usable")
	if rig == null:
		return
	var feet := npc.global_position
	var query := PhysicsRayQueryParameters2D.create(feet + Vector2(0, -5), feet + Vector2(0, 7), Layers.WORLD)
	var hit := _level.get_world_2d().direct_space_state.intersect_ray(query)
	_check(not hit.is_empty() and absf(hit["position"].y - feet.y) <= 2.0,
			"Su's real placement has floor support at %s" % id)
