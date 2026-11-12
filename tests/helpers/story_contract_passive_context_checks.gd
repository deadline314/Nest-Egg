extends RefCounted
## Transient origin is scoped to its exact live token; it is not save authority.
static func run(s: TestSuite) -> void:
	var id := &"test_bad_cutscene_passive_context"
	var foreign := &"test_bad_cutscene_passive_foreign"
	var old_auto := Story.auto_skip
	var old_seen := Story._seen.duplicate()
	var old_completed := Story._completed.duplicate()
	var old_serial := Story._request_serial
	var facts := var_to_bytes([GameState.world_flags,Progression.snapshot(),StoryItems.snapshot()])
	Story.auto_skip = false
	Story._scenes[String(id)] = {"mode":"radio","lines":[{"speaker":"rin","text":"TEST context waits until its original request settles."}]}
	var a := {"framing_source":"person","source_id":"actor-a","talk_index":0,"untrusted":"discard"}
	var b := {"framing_source":"person","source_id":"actor-b","talk_index":1}
	var first: int = Story._enqueue_request(id,false,a)
	var second: int = Story._enqueue_request(id,false,b)
	s.check(first != second and Story.presentation_context_for_request(id,first).get("source_id") == "actor-a" and Story.presentation_context_for_request(id,second).get("source_id") == "actor-b","same-id two original requests cannot borrow another NPC source")
	s.check(Story.presentation_context_for_request(foreign,first).is_empty() and Story.presentation_context_for_request(id,second + 1).is_empty(),"context requires both matching scene ID and live request")
	s.check(not Story.presentation_context_for_request(id,first).has("untrusted"),"only original presentation context fields survive")
	a["source_id"] = "mutated-input"
	var copy := Story.presentation_context_for_request(id,first)
	copy["source_id"] = "mutated-output"
	s.check(Story.presentation_context_for_request(id,first).get("source_id") == "actor-a","request owns a defensive context copy in both directions")
	var source := Story._install_source()
	s.check(RunSaveCodec.validate_tree(source).is_empty(),"passive context state stamp remains valid bounded data")
	var stamp := var_to_bytes(source)
	Story._passive_contexts[second]["source_id"] = "changed-runtime"
	s.check(var_to_bytes(Story._install_source()) != stamp,"prepared writer source guard observes transient context mutation")
	Story._on_bubbles_cancelled(id,second)
	s.check(not Story._passive_contexts.has(second) and Story.presentation_context_for_request(id,first).get("source_id") == "actor-a","cancelling newer token keeps the older same-id source isolated")
	Story._complete_request(first,true)
	s.check(not Story._passive_contexts.has(first) and Story.presentation_context_for_request(id,first).is_empty(),"settlement removes its context before a retired token can be reused")
	Story._on_bubbles_cancelled(id,first)
	for reason: StringName in [&"death",&"leave",&"load",&"new_run"]:
		var token: int = Story._enqueue_request(id,false,b)
		Story.reset_active_presentation(reason)
		s.check(not Story._passive_contexts.has(token) and Story._passive_requests.is_empty(),"existing reset lifecycle clears passive context: " + String(reason))
	Story._passive_contexts[999] = b.duplicate()
	s.check(Story.prepare_install([],true).has("error"),"orphan transient context cannot pass whole-run clean preparation")
	Story.reset_active_presentation(&"load")
	s.check(Story._passive_contexts.is_empty() and Story.prepare_install([],true).has("data"),"normal reset restores whole-run clean context")
	Story._scenes.erase(String(id))
	Story._seen = old_seen;Story._completed = old_completed;Story._request_serial = old_serial
	Story.auto_skip = old_auto
	s.check(var_to_bytes([GameState.world_flags,Progression.snapshot(),StoryItems.snapshot()]) == facts,"context lifecycle never grants flags/items/credits")
