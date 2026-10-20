extends RefCounted
## Real canonical receipts; reject whole batches before any live mutation.
static func run(s: TestSuite) -> void:
	var prior_money := Progression.snapshot()
	var prior_items := StoryItems.snapshot()
	var prior_flags := GameState.world_flags.duplicate(true)
	Progression.reset_run()
	Progression.add_credits(1000)
	var order := {"kind": "transaction", "id": "ch1.revival_meal.order"}
	var paid := {"kind": "transaction", "id": "ch1.revival_meal.paid"}
	var gift := {"kind": "transaction", "id": "ch1.revival_meal.gift"}
	var before := var_to_bytes([Progression.snapshot(), StoryItems.snapshot(), GameState.world_flags])
	var chained := Story.outcomes.preflight(&"batch_regression", {"results": [order, paid]}, [])
	s.check(chained["ok"], "one batch may open and pay a canonical bill in author order")
	s.check(before == var_to_bytes([Progression.snapshot(), StoryItems.snapshot(), GameState.world_flags]), "successful batch preview never installs its proposed bill or payment")
	var duplicate := Story.outcomes.preflight(&"batch_regression", {"results": [order, order]}, [])
	s.check(not duplicate["ok"] and duplicate["reason"] == "already_recorded", "duplicate canonical operation refuses before the first live receipt")
	var excluded := Story.outcomes.preflight(&"batch_regression", {"results": [order, paid, gift]}, [])
	s.check(not excluded["ok"] and excluded["reason"] == "excluded", "mutually exclusive payment and gift refuse the whole proposed receipt set")
	s.check(before == var_to_bytes([Progression.snapshot(), StoryItems.snapshot(), GameState.world_flags]), "duplicate and exclusive refusals preserve every live owner")
	# Isolated bounded outgoing definitions, individually affordable. These are
	# fixture IDs, never presented as registered campaign transactions.
	var old_cache := Story.outcomes._transaction_cache.duplicate()
	var first := StoryTransactionData.new()
	first.id = &"batch.first"
	first.credits_delta = -700
	var second := StoryTransactionData.new()
	second.id = &"batch.second"
	second.credits_delta = -700
	Story.outcomes._transaction_cache["batch.first"] = first
	Story.outcomes._transaction_cache["batch.second"] = second
	var shortfall := Story.outcomes.preflight(&"batch_regression", {"results": [{"kind": "transaction", "id": "batch.first"}, {"kind": "transaction", "id": "batch.second"}], "on_failure": {"insufficient_credits": "shortfall"}}, [])
	s.check(not shortfall["ok"] and shortfall["reason"] == "insufficient_credits" and shortfall["failure_scene"] == "shortfall", "cumulative balance refuses two individually affordable costs and retains authored fallback")
	s.check(before == var_to_bytes([Progression.snapshot(), StoryItems.snapshot(), GameState.world_flags]), "cumulative shortfall cannot debit the first payment")
	Story.outcomes._transaction_cache = old_cache
	Progression.restore(prior_money)
	StoryItems.restore(prior_items)
	GameState.world_flags = prior_flags
