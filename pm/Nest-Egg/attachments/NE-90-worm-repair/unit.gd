extends Node
var checks := 0
var failures := 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	ChainCreatureSuite.new(self)._test_worm_belly_and_neck()
	print("checks: %d, failures: %d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: ", message)
