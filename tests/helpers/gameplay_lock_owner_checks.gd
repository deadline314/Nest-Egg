extends RefCounted
## Multiple tokens from one real owner must remain independently releasable and collectable.


static func run(suite: TestSuite) -> void:
	var tree := suite.runner.get_tree()
	var mouse_mode := Input.mouse_mode
	GameplayLock.set_base_paused(false)
	var owner := Node.new()
	tree.root.add_child(owner)
	var first := GameplayLock.acquire(owner, Input.MOUSE_MODE_HIDDEN)
	var second := GameplayLock.acquire(owner, Input.MOUSE_MODE_VISIBLE)
	suite.check(first != second and owner.get_signal_connection_list(&"tree_exiting").size() == 2, "one owner receives two distinct lock cleanup connections")
	GameplayLock.release(first)
	suite.check(GameplayLock.held_only_by(second) and tree.paused and owner.get_signal_connection_list(&"tree_exiting").size() == 1, "releasing one same-owner token leaves the other connected and paused")
	GameplayLock.release(second)
	suite.check(not GameplayLock.is_locked() and not tree.paused and owner.get_signal_connection_list(&"tree_exiting").is_empty(), "explicitly releasing both same-owner tokens clears their connections")
	first = GameplayLock.acquire(owner)
	second = GameplayLock.acquire(owner)
	owner.queue_free()
	await tree.process_frame
	await tree.process_frame
	suite.check(not GameplayLock.is_locked() and not tree.paused, "freeing one owner automatically releases all of its tokens")
	# Idempotent cleanup also retires a failing implementation without contaminating later cases.
	GameplayLock.release(first)
	GameplayLock.release(second)
	GameplayLock.set_base_mouse_mode(mouse_mode)
