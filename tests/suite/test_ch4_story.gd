class_name Chapter4StorySuite
extends TestSuite

const Checks := preload("res://tests/helpers/chapter_story_checks.gd")
const STORY := "res://data/story/ch4_hollow.json"
const CHAPTER := &"ch4_hollow"
const CABINET := &"ch4_dispatch_cabinet"
const WAITING_ROOM := &"ch4_dispatch_egret"
const NEXT_DAY := "res://data/levels/ch5_pawnshop.tres"


func run() -> void:
	var areas := Checks.load_areas(self, "ch4", CHAPTER, ["pawnshop", "ward_reception", "nursing_ward", "revival_lounge", "factory_approach", "factory_loading", "factory_relay", "factory_safety", "factory_work", "factory_cleaning", "factory_office", "factory_roof", "ward_lamp_bay"])
	Checks.check_portals(self, "chapter 4", areas, {"pawnshop/pawnshop_next_day": NEXT_DAY})
	var handoff := Checks.portal_by_id(areas["pawnshop"], &"pawnshop_next_day")
	check(handoff != null and handoff.target_level == NEXT_DAY and handoff.target_portal == &""
			and handoff.mode == PortalData.Mode.INTERACT and handoff.requires_flag == &"ch4_pawnshop_homecoming_seen",
			"Chapter Five starts only when the player chooses the next day after returning the ledger")
	for area: LevelData in areas.values():
		var actual: Array[Dictionary] = LevelBuilder.parse(area).spawns
		for resource: Resource in area.legend.values():
			if resource is PortalData:
				check(actual.any(func(spawn: Dictionary) -> bool: return spawn["resource"] == resource),
					"%s/%s is parsed as a live portal" % [area.id, resource.id])
	Checks.check_entries(self, "chapter 4", areas, 15)
	Checks.check_quest_markers(self, "chapter 4", "ch4", STORY, areas, 12)

	GameState.start_new_run(GameState.difficulties[1])
	check(Story.resolve_dispatch(CABINET) == &"ch4_t_visit_first", "the cabinet asks for consent before it is investigated")
	GameState.set_flag(&"ch4_linden_visit_confirmed", true)
	check(Story.resolve_dispatch(CABINET) == &"ch4_t_missing_desk", "the cabinet points to the hall before the tapping demonstration")
	GameState.set_flag(&"ch4_voice_demo_read", true)
	check(Story.resolve_dispatch(CABINET) == &"ch4_t_missing_desk", "the voice demonstration can be discovered first")
	GameState.set_flag(&"ch4_voice_demo_read", false)
	GameState.set_flag(&"ch4_desk_demo_read", true)
	check(Story.resolve_dispatch(CABINET) == &"ch4_t_missing_voice", "the cabinet points to the upper platform before the voice demonstration")
	GameState.set_flag(&"ch4_voice_demo_read", true)
	check(Story.resolve_dispatch(CABINET) == &"ch4_t_open_cabinet", "both demonstrations unlock the sequence choices")
	check(Story.resolve_dispatch(WAITING_ROOM) == &"ch4_t_ward_intro", "a run without optional path history can meet Egret")
	GameState.set_flag(&"ch4_visit_signed", true)
	check(Story.resolve_dispatch(WAITING_ROOM) == &"ch4_t_reception_return", "checking in replaces the signing prompt")
	check(StoryItems.find(&"ch4_ward_collection_slip") != null, "the cabinet has a registered document")
	_check_ward_letter(areas["nursing_ward"])
	var approach := areas["factory_approach"] as LevelData
	var loading := areas["factory_loading"] as LevelData
	var lower_door := Checks.portal_by_id(approach, &"approach_loading")
	var upper_door := Checks.portal_by_id(loading, &"loading_rail")
	check(lower_door != null and lower_door.requires_flag == &"ch4_factory_batch_matched", "the loading door needs a matching batch")
	check(upper_door != null and upper_door.requires_flag == &"ch4_loader_rail_released", "releasing the internal catch opens a separate return route")
	_check_safe_platform(loading, areas["factory_relay"], areas["factory_safety"])
	_check_sweep(loading)
	_check_work_lane(areas["factory_safety"], areas["factory_work"])
	_check_boss_arena(areas["factory_safety"], areas["factory_work"], areas["factory_cleaning"], areas["factory_office"])
	_check_roof_loop(areas)
	GameState.start_new_run(GameState.difficulties[1])


func _check_ward_letter(ward: LevelData) -> void:
	var listen := &"ch4_t_read_linden_letter"
	var copy := &"ch4_t_note_linden_witnesses"
	var recorded := &"ch4_linden_witnesses_noted"
	var consent := &"ch4_linden_visit_confirmed"
	var collected := &"ch4_collection_slip_saved"
	check(not Story.scene_available(listen) and not Story.scene_available(copy), "visit consent alone cannot expose the upper drawer")
	GameState.set_flag(collected, true)
	GameState.set_flag(consent, false)
	check(not Story.scene_available(listen) and not Story.scene_available(copy), "an earlier public slip does not replace Linden’s permission")
	GameState.set_flag(consent, true)
	check(Story.scene_available(listen) and Story.scene_available(copy), "an authorized ward revisit can start with no factory progress")
	GameState.set_flag(recorded, true)
	check(Story.scene_available(listen) and not Story.scene_available(copy), "a copy remains readable without offering duplicate acquisition")
	GameState.set_flag(collected, false)
	GameState.set_flag(recorded, false)
	var spawns: Array[Dictionary] = LevelBuilder.parse(ward).spawns
	check(spawns.any(func(entry: Dictionary) -> bool:
		var npc := entry.get("resource") as NpcData
		return npc != null and npc.id == &"ch4_ward_scarf" and entry.get("cell") == Vector2i(35, 17)),
		"the scarf has a distinct world interaction on the upper walkway")

func _check_sweep(loading: LevelData) -> void:
	var console := &"ch4_dispatch_sweep_console"
	var result := &"ch4_demo_cover_cleared"
	check(Story.resolve_dispatch(console) == &"ch4_t_sweep_unready", "the sweep console asks the player to survey the floor first")
	GameState.set_flag(&"ch4_fixed_ground_marked", true)
	check(Story.resolve_dispatch(console) == &"ch4_t_demo_sweep", "the fixed-ground survey unlocks the demonstration")
	GameState.set_flag(result, true)
	check(Story.resolve_dispatch(console) == &"ch4_t_sweep_return", "a completed demonstration gives a read-only explanation")
	var matches: Array[Resource] = []
	for resource: Resource in loading.legend.values():
		if resource is BreakableData and resource.sweep_result == result:
			matches.append(resource)
	check(matches.size() == 1, "only one cover in the loading bay uses the demonstration flag")
	if matches.size() == 1:
		var cover := matches[0] as BreakableData
		check(cover.sweep_preview == &"ch4_t_demo_sweep" and cover.validate().is_empty(), "the demonstration owns one valid cover without drops or explosion")


func _check_safe_platform(loading: LevelData, relay: LevelData, safety: LevelData) -> void:
	var entrance := Checks.portal_by_id(loading, &"loading_relay")
	var shortcut := Checks.portal_by_id(loading, &"loading_service")
	check(entrance != null and entrance.requires_flag == &"ch4_demo_cover_cleared", "the active factory route asks for the safe rehearsal first")
	check(shortcut != null and shortcut.requires_flag == &"ch4_safety_shortcut_open", "the staff shortcut opens only from the safe platform")
	var hall := LevelBuilder.parse(relay)
	var refuge := LevelBuilder.parse(safety)
	check(hall.checkpoints.is_empty() and refuge.checkpoints.size() == 1, "the route puts its phone in the safe room")
	var threats: Array[StringName] = []
	for spawn: Dictionary in hall.spawns:
		var enemy := spawn.get("resource") as EnemyData
		if enemy != null:
			threats.append(enemy.id)
	# NE-451：上層走道的兩台探照無人機換一台成狙擊手；下層仍是清掃兵，東端出口是切割者。
	check(threats.count(&"sweeper") == 1 and threats.count(&"slasher") == 1 and threats.count(&"searchlight_drone") == 1 and threats.count(&"sniper") == 1,
			"the shared floor and upper catwalk contain two distinct patrol groups")


func _check_work_lane(safety: LevelData, work: LevelData) -> void:
	var entrance := Checks.portal_by_id(safety, &"safety_work")
	check(entrance != null and entrance.requires_flag == &"ch4_cleaning_briefing_read", "the work lane requires the safe-platform briefing")
	var layout := LevelBuilder.parse(work)
	var sectors: Array[Dictionary] = []
	for entry: Dictionary in layout.spawns:
		var data := entry.get("resource") as MechanismData
		if data != null and data.kind == MechanismData.Kind.SWEEP_LANE:
			check(data.validate().is_empty(), "each work sweep uses a valid, bounded warning and live period")
			sectors.append(entry)
	check(sectors.size() == 2, "the work lane has two independently placed sweep sectors")
	if sectors.size() == 2:
		var a: Vector2i = sectors[0]["cell"]
		var b: Vector2i = sectors[1]["cell"]
		check(absi(a.y - b.y) >= 5, "the second sweep is far enough above the first to leave alternate footing")
	var malformed := MechanismData.new()
	malformed.kind = MechanismData.Kind.SWEEP_LANE
	malformed.sweep_warning_seconds = INF
	check(not malformed.validate().is_empty(), "nonfinite warning durations are rejected before spawning")


func _check_boss_arena(safety: LevelData, work: LevelData, gallery: LevelData, office: LevelData) -> void:
	var entrance := Checks.portal_by_id(work, &"work_arena")
	var exit := Checks.portal_by_id(gallery, &"arena_office")
	check(entrance != null and entrance.requires_flag == &"ch4_factory_work_crossed", "the gallery requires the work-lane survey")
	check(exit != null and exit.requires_flag == &"ch4_office_access" and exit.target_level == office.resource_path,
		"the office portal requires the durable withdrawal result")
	check(gallery.safe_resume_level == safety.resource_path, "combat retries and cold resumes target the safe platform")
	var layout := LevelBuilder.parse(gallery)
	var erased_covers := 0
	var controlled_lanes := 0
	var boss_roster := 0
	var player_start := layout.player_start
	for entry: Dictionary in layout.spawns:
		var resource: Resource = entry["resource"]
		if resource is MechanismData and resource.kind == MechanismData.Kind.SWEEP_LANE:
			check(resource.channel == &"ch4_arena_sweeps" and resource.validate().is_empty(),
				"the gallery has controller-owned sweep sectors")
			controlled_lanes += 1
		elif resource is BreakableData and resource.sweep_result == &"ch4_arena_cover_erased":
			var cell: Vector2i = entry["cell"]
			check(layout.cell(cell.x, cell.y + 1) == LevelBuilder.SOLID, "the marked cover is independent of the permanent floor")
			erased_covers += 1
		elif resource is EnemyData and resource.id == &"atropos":
			check(not resource.is_boss and entry["position"].x > player_start.x, "the captain is a local encounter facing the entrance")
			check(DefeatCodex.has_card(resource.contact_source_id) and resource.projectile != null and DefeatCodex.has_card(resource.projectile.source_id)
				and DefeatCodex.has_card(&"atropos_barrage"), "all captain attacks have their own practical defeat guidance")
			boss_roster += 1
	check(erased_covers == 1 and controlled_lanes == 2 and boss_roster == 1, "the gallery has two elevations, one marked cover and one captain")
	var handoff := &"ch4_dispatch_egret_at_rail"
	var release := &"ch4_dispatch_office_release"
	check(Story.resolve_dispatch(handoff) != &"ch4_t_egret_handoff", "the midpoint conversation cannot start at entry")
	GameState.set_flag(&"ch4_atropos_midpoint_ready", true)
	check(Story.resolve_dispatch(handoff) == &"ch4_t_egret_handoff", "the living player's midpoint makes the handoff available")
	GameState.set_flag(&"ch4_egret_departed", true)
	check(Story.resolve_dispatch(handoff) != &"ch4_t_egret_handoff", "the committed departure cannot reappear")
	check(Story.resolve_dispatch(release) != &"ch4_t_work_retreat", "the terminal stays inactive during phase two")
	GameState.set_flag(&"ch4_atropos_retreat_ready", true)
	check(Story.resolve_dispatch(release) == &"ch4_t_work_retreat", "the release needs withdrawal and the prior departure")

func _check_roof_loop(areas: Dictionary) -> void:
	var office := Checks.portal_by_id(areas["factory_office"], &"office_roof")
	var return_stairs := Checks.portal_by_id(areas["factory_safety"], &"safety_roof")
	var bypass := Checks.portal_by_id(areas["factory_roof"], &"roof_safety")
	var bay := Checks.portal_by_id(areas["nursing_ward"], &"ward_lamp_bay")
	var cupboard := &"ch4_lamp_bedside"
	var radio := &"ch4_dispatch_roof_lantern"
	var recorder := &"ch4_dispatch_lamp_bedside"
	var microphone := &"ch4_lamp_microphone"
	check(office != null and return_stairs != null and office.requires_flag == &"ch4_original_ledger_saved"
		and return_stairs.requires_flag == office.requires_flag, "both roof entries depend only on the original ledger")
	check(bypass != null and bypass.requires_flag.is_empty(), "the rooftop return does not depend on the optional favor")
	check(bay != null and bay.requires_flag == &"ch4_lamp_mic_requested", "the separate bedside bay opens after accepting the microphone")
	check(Story.resolve_dispatch(radio) == &"" and Story.resolve_dispatch(recorder) == &"", "the two new stations cannot produce an early result")
	GameState.set_flag(&"ch4_original_ledger_saved", true)
	check(Story.resolve_dispatch(radio) == &"ch4_t_roof_transmission", "the normal route supports the first transmission without optional scenes")
	GameState.set_flag(&"ch4_roof_radio_heard", true)
	check(Story.resolve_dispatch(radio) == &"ch4_t_lamp_offer" and not StoryItems.owns(microphone), "listening opens a separate optional offer")
	GameState.set_flag(&"ch4_lamp_mic_requested", true)
	check(Story.resolve_dispatch(recorder) == &"", "the bedside cannot record without custody of the microphone")
	var item := StoryItems.find(microphone)
	check(item != null and item.validate().is_empty() and not item.is_collectible(), "the microphone is a valid, manually granted item")
	StoryItems.acquire(microphone)
	check(Story.resolve_dispatch(recorder) == &"ch4_t_lamp_bedside_record", "the requested, held microphone enables the bedside recording")
	var results: Array = Story._scenes.get("ch4_t_lamp_bedside_record", {}).get("results", [])
	check(results.any(func(operation: Dictionary) -> bool:
		return (operation.get("kind") == "item_transfer" and operation.get("id") == String(microphone)
			and operation.get("destination") == String(cupboard))), "the terminal result transfers the microphone to its own physical bedside")
	GameState.set_flag(&"ch4_lamp_message_recorded", true)
	check(Story.resolve_dispatch(recorder) == &"ch4_t_lamp_bedside_revisit", "a recording cannot be awarded again")
	var bedside := areas["ward_lamp_bay"] as LevelData
	var layout := LevelBuilder.parse(bedside)
	var definition := WorldPropAction.definition("ch4_lamp_recorder_press")
	var prop := PropLibrary.find_in(&"nursing_ward__bedside_radio", bedside.environment.prop_dirs())
	var placements: Array = bedside.load_props().filter(func(entry: Dictionary) -> bool:
		return entry["id"] == String(prop.id)) if prop != null else []
	check(prop != null and placements.size() == 1, "only the side-window radio supplies the recording anchor")
	if placements.size() == 1 and prop != null:
		var radio_rect: Rect2 = PropPlacement.resolve(placements[0], prop, layout).get("rect", Rect2())
		var station := radio_rect.position + Vector2(definition["station"][0], definition["station"][1])
		check(station.y == PropPlacement.ground_surface(layout, floori(station.x / layout.tile_size)),
			"the recorder's hand action starts at an exact, load-bearing floor height")
