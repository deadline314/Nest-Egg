class_name Chapter4StorySuite
extends TestSuite

const Checks := preload("res://tests/helpers/chapter_story_checks.gd")
const STORY := "res://data/story/ch4_hollow.json"
const CHAPTER := &"ch4_hollow"
const CABINET := &"ch4_dispatch_cabinet"
const WAITING_ROOM := &"ch4_dispatch_egret"


func run() -> void:
	var areas := Checks.load_areas(self, "ch4", CHAPTER, ["pawnshop", "ward_reception", "nursing_ward"])
	Checks.check_portals(self, "chapter 4", areas)
	for area: LevelData in areas.values():
		var actual: Array[Dictionary] = LevelBuilder.parse(area).spawns
		for resource: Resource in area.legend.values():
			if resource is PortalData:
				check(actual.any(func(spawn: Dictionary) -> bool: return spawn["resource"] == resource),
					"%s/%s is parsed as a live portal" % [area.id, resource.id])
	Checks.check_entries(self, "chapter 4", areas, 7)
	Checks.check_quest_markers(self, "chapter 4", "ch4", STORY, areas, 6)

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
	GameState.start_new_run(GameState.difficulties[1])
