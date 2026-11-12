extends RefCounted
## Live accessibility toggles must preserve scene-authored visibility.

static func run(suite: TestSuite, factory: Variant = StageLayers) -> void:
	var previous := Settings.get_reduce_flashes()
	Settings.set_reduce_flashes(false)
	var visible_layer: Node2D = factory.create({"kind": "grain", "amount": 140, "opacity": 0.2, "reason": "test memory"}, "BG27 live memory")
	suite.runner.add_child(visible_layer)
	suite.check(visible_layer.visible and visible_layer.is_processing(), "special grain starts active without reduced flashes")
	Settings.set_reduce_flashes(true)
	suite.check(not visible_layer.is_processing(), "existing special grain stops updating immediately when reduced flashes is enabled")
	suite.check(visible_layer.visible, "accessibility does not overwrite the authored visible state")
	var reduced_layer: Node2D = factory.create({"kind": "grain", "amount": 140, "opacity": 0.2, "reason": "test memory"}, "BG27 reduced memory")
	suite.runner.add_child(reduced_layer)
	suite.check(not reduced_layer.is_processing(), "special grain created while reduced flashes is enabled does not update")
	var hidden_layer: Node2D = factory.create({"kind": "grain", "amount": 140, "opacity": 0.2, "reason": "test memory", "visible": false}, "BG27 hidden memory")
	suite.runner.add_child(hidden_layer)
	Settings.set_reduce_flashes(false)
	suite.check(reduced_layer.visible and reduced_layer.is_processing(), "existing special grain returns when reduced flashes is disabled")
	suite.check(visible_layer.visible and visible_layer.is_processing(), "live special grain resumes its normal state")
	suite.check(not hidden_layer.visible and hidden_layer.process_mode == Node.PROCESS_MODE_DISABLED, "accessibility changes preserve an authored hidden disabled layer")
	var ids := [visible_layer.get_instance_id(), reduced_layer.get_instance_id(), hidden_layer.get_instance_id()]
	visible_layer.queue_free()
	reduced_layer.queue_free()
	hidden_layer.queue_free()
	await suite.frames(2)
	var retained := false
	for connection in Settings.display_changed.get_connections():
		if connection.callable.get_object_id() in ids: retained = true
	suite.check(not retained, "freed grain layers leave no display-setting observers")
	Settings.set_reduce_flashes(previous)
