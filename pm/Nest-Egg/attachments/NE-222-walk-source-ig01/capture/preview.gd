extends Node
const Capture = preload("res://viewport_capture.gd")

func _ready() -> void:
 var root := ""
 var output := ""
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--root="):
   root = arg.trim_prefix("--root=")
  if arg.begins_with("--out="):
   output = arg.trim_prefix("--out=")
 assert(root.is_absolute_path() and output.is_absolute_path())
 var viewport := SubViewport.new()
 viewport.size = Vector2i(1920,1600)
 viewport.use_hdr_2d = true
 viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
 add_child(viewport)
 var background := ColorRect.new()
 background.color = Color("202735")
 background.size = Vector2(1920,1600)
 viewport.add_child(background)
 label(viewport, Vector2(60,30), "NE-222 | WALK SOURCE REVIEW", 32)
 label(viewport, Vector2(60,80), "Original preserved. Candidate only: not a rigged animation, seam or gameplay pass.", 23)
 var paths := [root.path_join("art_src/characters/rin2/base_rgba.png"),root.path_join("art_src/characters/rin_walk_source_ig01/raw/source.png")]
 var titles := ["APPROVED STANDING SOURCE", "NEW WALK SOURCE - NOT ADOPTED"]
 for i in 2:
  var panel := ColorRect.new()
  panel.color = Color("687080")
  panel.position = Vector2(60+i*960,160)
  panel.size = Vector2(900,1320)
  viewport.add_child(panel)
  label(viewport, Vector2(75+i*960,125), titles[i], 22)
  var image := Image.load_from_file(paths[i])
  assert(image != null and not image.is_empty())
  var sprite := Sprite2D.new()
  sprite.texture = ImageTexture.create_from_image(image)
  sprite.centered = false
  sprite.scale = Vector2.ONE * (1260.0 / image.get_height())
  sprite.position = Vector2(75+i*960,185)
  viewport.add_child(sprite)
 label(viewport, Vector2(60,1510), "Source-alpha defects and uncertain model joints remain recorded. Production Rin parts are unchanged.", 23)
 await RenderingServer.frame_post_draw
 await RenderingServer.frame_post_draw
 var captured := Capture.image(viewport)
 assert(captured.get_size() == Vector2i(1920,1600))
 assert(captured.save_png(output) == OK)
 print("SOURCE_REVIEW_CAPTURE size=1920x1600 renderer=",RenderingServer.get_current_rendering_method()," hdr=",viewport.use_hdr_2d)
 get_tree().quit()

func label(viewport: SubViewport, at: Vector2, text: String, size: int) -> void:
 var node := Label.new()
 node.position = at
 node.text = text
 node.add_theme_font_size_override("font_size",size)
 viewport.add_child(node)
