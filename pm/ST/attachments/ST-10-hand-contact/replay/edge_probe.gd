extends Node
func _ready() -> void:
 var before := OS.get_cmdline_user_args().has("--before")
 var actor := CutsceneActor.new()
 var control: RefCounted
 if before:
  var script := GDScript.new()
  script.source_code = FileAccess.get_file_as_string("res://work/st10-reach/reach-v2.gd.txt").replace("class_name CutsceneReach\n", "")
  if script.reload() != OK:
   get_tree().quit(2)
   return
  control = script.new(&"front")
 else: control = CutsceneReach.new(&"front")
 control.configure({"hand": "front", "to": [100, 120], "time": 0.0})
 control.configure({"hand": "front", "to": [140, 160], "time": 0.35})
 control.apply(actor, 0.175)
 var release_point: Vector2 = control.target
 control.configure({"hand": "front", "release": true, "time": 0.35})
 control.apply(actor, 0.175)
 var error: float = control.target.distance_to(release_point)
 var ok := error < 0.001
 print("RELEASE_EDGE %s" % JSON.stringify({"before": before, "checks": 1, "failures": 0 if ok else 1, "drift_stage_pixels": error}))
 actor.free()
 get_tree().quit(0 if ok else 1)
