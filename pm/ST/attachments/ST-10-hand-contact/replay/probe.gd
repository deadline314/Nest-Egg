extends "res://tools/scenarios/scenario_base.gd"
var checks := 0
var failures := 0
var baseline := false
func _ready() -> void:
 process_mode = Node.PROCESS_MODE_ALWAYS
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--out="): out_dir = arg.trim_prefix("--out=")
  if arg == "--baseline": baseline = true
 DirAccess.make_dir_recursive_absolute(out_dir)
 _run.call_deferred()
func _check(ok: bool, message: String) -> void:
 checks += 1
 if not ok: failures += 1
 print("CONTACT_CHECK %s %s" % [ok, message])
func _until(p: CutscenePlayer, count: int) -> bool:
 var end := Time.get_ticks_msec() + 15000
 while is_instance_valid(p) and p.steps_run < count and Time.get_ticks_msec() < end:
  await get_tree().process_frame
 return is_instance_valid(p) and p.steps_run >= count
func _run() -> void:
 var facts := var_to_bytes([GameState.world_flags, StoryItems.snapshot(), Progression.snapshot(), Story.progress_snapshot()])
 for facing in [-1, 1]:
  var p := CutscenePlayer.new()
  add_child(p)
  var formal: Dictionary = Story._scenes["ch1_c14_home"]
  var steps: Array = formal["steps"].slice(0, 3).duplicate(true)
  steps[0]["fade"] = 0.3
  steps[1]["pos"] = [330, 304]
  steps[1]["facing"] = facing
  steps[2]["facing"] = facing
  steps.append({"do": "wait", "time": 0.8})
  for id in ["rin", "k"]:
   steps.append({"do": "reach", "id": id, "hand": "front", "to": [0, 0], "time": 0.35})
  steps.append({"do": "wait", "time": 60.0})
  p.play(&"st10_contact_preview", {"steps": steps})
  _check(await _until(p, 3), "formal stage and both actors instantiated")
  var targets: Array[Vector2] = []
  var lengths: Array[Vector2] = []
  var index := 4
  for id in [&"rin", &"k"]:
   var actor: CutsceneActor = p._actors[id]
   var rig := actor.rig
   var shoulder := rig.bone(&"arm_front_upper")
   var elbow := rig.bone(&"arm_front_lower")
   var wrist := rig.bone(&"hand_front")
   var skeleton := rig.get_node("Skeleton") as Node2D
   var local := skeleton.to_local(shoulder.global_position) + Vector2(0.65, 0.35) * (rig.rest(&"arm_front_lower").length() + rig.rest(&"hand_front").length())
   var target := p._stage.actors.to_local(skeleton.to_global(local))
   targets.append(target)
   lengths.append(Vector2(shoulder.global_position.distance_to(elbow.global_position), elbow.global_position.distance_to(wrist.global_position)))
   p._steps[index]["to"] = [target.x, target.y]
   if baseline: p._steps[index] = {"do": "wait", "time": 0.35}
   var marker := Line2D.new()
   marker.width = 0.7
   marker.default_color = Color(0.4, 1.0, 0.9)
   marker.points = PackedVector2Array([target + Vector2(-5, 0), target + Vector2(5, 0), target, target + Vector2(0, -5), target + Vector2(0, 5)])
   p._stage.front.add_child(marker)
   index += 1
  _check(await _until(p, 6), "production step dispatcher finishes both approach steps")
  await settle(4)
  index = 0
  for id in [&"rin", &"k"]:
   var rig: CharacterRig = p._actors[id].rig
   var a := rig.bone(&"arm_front_upper")
   var b := rig.bone(&"arm_front_lower")
   var c := rig.bone(&"hand_front")
   var error := p._stage.actors.to_local(c.global_position).distance_to(targets[index])
   print("CONTACT_RESULT %s" % JSON.stringify({"actor": id, "facing": facing, "stage_error": error, "target": [targets[index].x, targets[index].y]}))
   _check(error < 0.02, "%s/%d actual rendered wrist reaches its stage target" % [id, facing])
   _check(absf(a.global_position.distance_to(b.global_position) - lengths[index].x) < 0.02 and absf(b.global_position.distance_to(c.global_position) - lengths[index].y) < 0.02, "both arm segments preserve their length")
   index += 1
  await RenderingServer.frame_post_draw
  _capture_checked("contact-%d" % facing)
  if not baseline:
   for id in ["rin", "k"]:
    await p._do_reach({"id": id, "hand": "front", "release": true, "time": 0.35})
  await settle(4)
  await RenderingServer.frame_post_draw
  _capture_checked("released-%d" % facing)
  p.cancel()
  await settle(4)
 _check(facts == var_to_bytes([GameState.world_flags, StoryItems.snapshot(), Progression.snapshot(), Story.progress_snapshot()]), "contact preview and cancellation cannot mutate story custody or progress")
 print("CONTACT_TOTAL checks=%d failures=%d baseline=%s" % [checks, failures, baseline])
 get_tree().quit(1 if failures else 0)

func _capture_checked(label: String) -> void:
 var picture := preload("res://tools/viewport_capture.gd").image(get_viewport())
 var visible := 0
 var samples := 0
 for y in range(0, picture.get_height(), 24):
  for x in range(0, picture.get_width(), 24):
   var pixel := picture.get_pixel(x, y)
   samples += 1
   if maxf(pixel.r, maxf(pixel.g, pixel.b)) > 0.05: visible += 1
 _check(float(visible) / samples > 0.2, "captured stage is visible after fade and is not a black screen")
 picture.save_png(out_dir.path_join(label + ".png"))
