extends Node
func _ready():
 process_mode = Node.PROCESS_MODE_ALWAYS
 call_deferred("run")
func run():
 var locale="en"
 var chapter_id=&"ch2_heron"
 var text_scale=1.2
 var resolution=Vector2i(1280,720)
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--language="):locale=arg.trim_prefix("--language=")
  elif arg.begins_with("--chapter="):chapter_id=StringName(arg.trim_prefix("--chapter="))
  elif arg.begins_with("--scale="):text_scale=float(arg.trim_prefix("--scale="))
  elif arg.begins_with("--width="):resolution.x=int(arg.trim_prefix("--width="))
  elif arg.begins_with("--height="):resolution.y=int(arg.trim_prefix("--height="))
 Settings.use_storage("user://ne228-terminal-layout.cfg")
 Settings.set_ui_text_scale(text_scale)
 Settings.set_reduce_ui_motion(true)
 get_window().size=resolution
 DisplayMode.ensure_scaling(get_window())
 Story.set_language(locale)
 GameState.start_new_run(GameState.difficulties[0])
 CampaignEdition.override_current(CampaignEdition.current().describe("through-"+String(chapter_id)))
 var screen=VictoryScreen.new()
 screen.chapter=chapter_id
 add_child(screen)
 await get_tree().create_timer(0.1,true,false,true).timeout
 var bounds=screen.get_global_rect()
 var teaser=screen._rows.back() as Label
 var report={"language":locale,"chapter":String(chapter_id),"scale":text_scale,"resolution":[resolution.x,resolution.y],"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"visible_lines":teaser.get_visible_line_count(),"screen":str(bounds),"teaser":str(teaser.get_global_rect()),"text":teaser.text,"lines":teaser.get_line_count(),"buttons":[],"valid":true}
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
