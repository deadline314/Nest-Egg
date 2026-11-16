extends Node
var checks := 0
var failures: Array[String] = []
func _ready() -> void:
	_run.call_deferred()
func _check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)
func _run() -> void:
	await preload("res://tests/helpers/prefetch_scope_checks.gd").run(Chapter1MapSuite.new(self))
	for failure: String in failures: print("FAIL ", failure)
	print("BG32_SERVICE_REGRESSION checks=", checks, " failures=", failures.size())
	await AudioRelease.settle(get_tree())
	get_tree().quit(0 if failures.is_empty() else 1)
