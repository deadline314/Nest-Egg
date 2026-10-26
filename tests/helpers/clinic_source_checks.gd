extends RefCounted
const Clinic := preload("res://game/story_result_clinic.gd")
const Sources := preload("res://game/story_result_sources.gd")

static func run(s: TestSuite) -> void:
	var scenes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Clinic.SOURCE))["scenes"]
	var locations := {}
	for id: String in scenes:
		locations[id] = Clinic.SOURCE
	var before := var_to_bytes([GameState.world_flags,Progression.snapshot(),StoryItems.snapshot(),Story.progress_snapshot()])
	for id: String in Clinic.BOUNDARIES:
		s.check(not Sources.boundary(id,scenes,locations).is_empty(),"actual first-clinic boundary validates: " + id)
	for mutation: Array in [
		[Clinic.TAKE,"results",[{"kind":"item_acquire","id":"ch1_data_disk"}]],
		[Clinic.LOOK,"then",Clinic.TAKE],
		[Clinic.ROOT,"when",{}],
		[Clinic.MISSING,"then",Clinic.TAKE],
		[Clinic.LEAVE,"completion_policy","atomic_v1"],
	]:
		var changed := scenes.duplicate(true)
		changed[mutation[0]][mutation[1]] = mutation[2]
		s.check(Clinic.boundary(Clinic.ROOT,changed,locations).is_empty(),"altered distant family cannot grant first-death completion: " + mutation[0])
	var changed := scenes.duplicate(true)
	changed[Clinic.TRAY]["steps"].back()["options"][0]["target"] = Clinic.TAKE
	s.check(not Clinic.valid(changed,locations),"original tray cannot bypass examining the cloth")
	var foreign := locations.duplicate()
	foreign[Clinic.TAKE] = "res://data/story/ch2_heron.json"
	s.check(not Clinic.valid(scenes,foreign),"same named foreign cloth producer cannot own the clinic family")
	var proof := {"chapter":"ch1_kasa","root":Clinic.ROOT,"entry":{"scene":Clinic.ROOT,"free":true,"register_checkpoint":true,"unless_flag":"ch1_first_death_done"}}
	s.check(Clinic.resume(proof,"",{},[],false) == {"valid":true,"scene":Clinic.ROOT},"unregistered genuine death resumes its original root without inventing a result")
	var registered := {"ch1_first_death_done":true}
	for pending: String in [Clinic.TRAY,Clinic.LOOK,Clinic.DECIDE,Clinic.TAKE,Clinic.LEAVE,Clinic.REGISTERED,Clinic.MISSING]:
		s.check(Clinic.resume(proof,pending,registered,[Clinic.ROOT],false) == {"valid":true,"scene":pending},"registered death preserves exact unread segment: " + pending)
	s.check(Clinic.resume(proof,Clinic.TRAY,registered,[],false) == {"valid":false},"flag without its completed root cannot invent an owned first-clinic continuation")
	s.check(Clinic.resume(proof,Clinic.TAKE,{},[],false) == {"valid":false},"unregistered death cannot jump to the cloth reward")
	s.check(Clinic.resume(proof,"ch1_t_ali_sit",registered,[Clinic.ROOT],false) == {"valid":false},"a foreign pending scene cannot impersonate a clinic continuation")
	for pending: String in ["",Clinic.ROOT,Clinic.TAKE,Clinic.LEAVE]:
		var history: Array = [Clinic.ROOT,pending]
		s.check(Clinic.resume(proof,pending,registered,history,false) == {"valid":true,"scene":""},"settled genuine death finishes retry without a second result: " + pending)
	var forged := proof.duplicate(true)
	forged["entry"]["free"] = false
	s.check(not Clinic.owns_episode(forged),"paid or unrelated death presentation cannot borrow the free first-clinic producer")
	var facts := Story.outcomes.context_facts.duplicate(true)
	Story.outcomes.context_facts["first_clinic"] = true
	var condition := {"all":[{"flag":"ch1_first_clinic_active","equals":true},{"not":{"flag":"ch1_first_death_done","equals":true}}]}
	var expected := {"all":[{},{"not":{"flag":"ch1_first_death_done","equals":true}}]}
	s.check(Story.outcomes.bind_context_condition(condition) == expected,"bind only transient context while preserving persistent candidate conditions")
	Story.outcomes.context_facts.clear()
	s.check(Story.outcomes.bind_context_condition({"flag":"ch1_first_clinic_active","equals":true}) == {"not":{}},"absent context remains false rather than becoming a saved world flag")
	var malformed := {"flag":"ch1_first_clinic_active","equals":true,"extra":true}
	s.check(Story.outcomes.bind_context_condition(malformed) == malformed,"malformed conditions remain available to the strict original planner error")
	Story.outcomes.context_facts = facts
	s.check(before == var_to_bytes([GameState.world_flags,Progression.snapshot(),StoryItems.snapshot(),Story.progress_snapshot()]),"clinic preflight and context binding never publish persistent services")
