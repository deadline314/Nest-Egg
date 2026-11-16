extends Node
func _ready():
 process_mode = Node.PROCESS_MODE_ALWAYS
 call_deferred("run")
func run():
 Settings.use_storage("user://ne228-terminal-layout.cfg")
 Settings.set_ui_text_scale(1.2)
 Settings.set_reduce_ui_motion(true)
 get_window().size=Vector2i(1280,720)
 DisplayMode.ensure_scaling(get_window())
 Story.set_language("en")
 GameState.start_new_run(GameState.difficulties[0])
 CampaignEdition.override_current(CampaignEdition.current().describe("through-ch2_heron"))
 var screen=VictoryScreen.new()
 screen.chapter=&"ch2_heron"
 add_child(screen)
 await get_tree().create_timer(0.1,true,false,true).timeout
 var bounds=screen.get_global_rect()
 var teaser=screen._rows.back() as Label
 var report={"screen":str(bounds),"teaser":str(teaser.get_global_rect()),"text":teaser.text,"lines":teaser.get_line_count(),"buttons":[],"valid":true}
 for button in screen._buttons:
  report.buttons.append(str(button.get_global_rect()))
  report.valid=report.valid and bounds.encloses(button.get_global_rect())
 report.valid=report.valid and bounds.encloses(teaser.get_global_rect())
 print("TERMINAL_LAYOUT ",JSON.stringify(report))
 var out=""
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--out="):out=arg.trim_prefix("--out=")
 if DisplayServer.get_name()!="headless" and not out.is_empty():
  await RenderingServer.frame_post_draw
  preload("res://tools/viewport_capture.gd").image(get_viewport()).save_png(out)
 screen.queue_free()
 for i in 6:await get_tree().process_frame
 Sfx.stop_all()
 Music.stop(0.0)
 Ambience.stop_all(0.0)
 await get_tree().create_timer(0.3,true,false,true).timeout
 get_tree().quit(0 if report.valid else 1)
