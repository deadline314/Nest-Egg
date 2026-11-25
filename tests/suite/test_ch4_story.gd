class_name Chapter4StorySuite
extends TestSuite

const Checks := preload("res://tests/helpers/chapter_story_checks.gd")
const STORY := "res://data/story/ch4_hollow.json"
const CHAPTER := &"ch4_hollow"
const CABINET := &"ch4_dispatch_cabinet"
const WAITING_ROOM := &"ch4_dispatch_egret"


func run() -> void:
	var areas := Checks.load_areas(self, "ch4", CHAPTER, ["pawnshop", "ward_reception", "nursing_ward", "revival_lounge", "factory_approach", "factory_loading"])
	Checks.check_portals(self, "chapter 4", areas)
	for area: LevelData in areas.values():
		var actual: Array[Dictionary] = LevelBuilder.parse(area).spawns
		for resource: Resource in area.legend.values():
			if resource is PortalData:
				check(actual.any(func(spawn: Dictionary) -> bool: return spawn["resource"] == resource),
					"%s/%s is parsed as a live portal" % [area.id, resource.id])
	Checks.check_entries(self, "chapter 4", areas, 12)
	Checks.check_quest_markers(self, "chapter 4", "ch4", STORY, areas, 10)

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
	var approach := areas["factory_approach"] as LevelData
	var loading := areas["factory_loading"] as LevelData
	var lower_door := Checks.portal_by_id(approach, &"approach_loading")
	var upper_door := Checks.portal_by_id(loading, &"loading_rail")
	check(lower_door != null and lower_door.requires_flag == &"ch4_factory_batch_matched", "the loading door needs a matching batch")
	check(upper_door != null and upper_door.requires_flag == &"ch4_loader_rail_released", "releasing the internal catch opens a separate return route")
	_check_sweep(loading)
	GameState.start_new_run(GameState.difficulties[1])


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
