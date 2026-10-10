extends Node2D
const DIR := "res://.godot/ne222-walk-torso-22316-native/"
const CAPTURE = preload("res://tools/viewport_capture.gd")
var rows: Array[Dictionary] = []
var captures: Array[Dictionary] = []
var out := ""
var speed := 70.0
var elapsed := 0.0
var next_sample := 0
var pending := -1
var complete := true
const SAMPLE_TIMES := [1.0,1.25,1.5,1.75,2.0]

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out=arg.trim_prefix("--out=")
		if arg.begins_with("--speed="): speed=float(arg.trim_prefix("--speed="))
	assert(out.is_absolute_path() and out.ends_with(".json"))
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	get_tree().root.content_scale_size=Vector2i(1600,1000)
	get_tree().root.size=Vector2i(1600,1000)
	get_viewport().use_hdr_2d=true
	RenderingServer.set_default_clear_color(Color("5b6577"))
	add_child(LightKit.create_environment())
	var diffuse := ImageTexture.create_from_image(Image.load_from_file(DIR+"torso.png"))
	var normal := ImageTexture.create_from_image(Image.load_from_file(DIR+"torso_n.png"))
	var glow := ImageTexture.create_from_image(Image.load_from_file(DIR+"torso_glow.png"))
	for zoom: float in [3.4,1.0]:
		for facing: int in [1,-1]:
			for candidate: bool in [false,true]:
				var holder:=Node2D.new()
				holder.position=Vector2(210+(rows.size()%4)*390,470 if zoom>1 else 850)
				holder.scale=Vector2.ONE*zoom
				add_child(holder)
				var rig:=CharacterRig.new()
				holder.add_child(rig)
				assert(rig.setup("rin"))
				if candidate:
					var torso:=rig.find_child("armor_torso",true,false) as RigPartMesh
					if torso==null:
						push_error("Expected production torso waist mesh")
						get_tree().quit(1)
						return
					var lit:=CanvasTexture.new()
					lit.diffuse_texture=diffuse
					lit.normal_texture=normal
					torso.scale=Vector2.ONE*(0.04205/4)
					assert(torso.setup(lit,Vector2(864,1408),Vector2(252,1256),torso._self_bone,torso._partner,
						torso._partner_is_child,torso._self_rest,torso._partner_rest,rig.rest(&"chest").length()*rig._limb_zone,torso._partner_direction))
					assert(torso._glow!=null)
					torso._glow.texture=glow
					torso._glow.uv=torso.uv
					torso._glow.polygon=torso.polygon
					torso._glow.polygons=torso.polygons
				var input:=RigInput.new()
				input.facing=facing
				input.aim_dir=Vector2(facing,0)
				input.two_handed=false
				input.relaxed=true
				input.run_speed=150
				input.velocity=Vector2(facing*speed,0)
				rows.append({"rig":rig,"input":input,"candidate":candidate,"facing":facing,"zoom":zoom})
				var label:=Label.new()
				label.position=holder.position+Vector2(-150,35)
				label.text=("candidate" if candidate else "baseline")+" f%d x%.1f v%.2f"%[facing,zoom,speed]
				add_child(label)
	var title:=Label.new()
	title.position=Vector2(40,30)
	title.text="NE-222 / neutral torso 22316 / PRIVATE intact armor comparison"
	title.add_theme_font_size_override("font_size",26)
	add_child(title)
	var scope:=Label.new()
	scope.position=Vector2(40,75)
	scope.text="Existing skeleton/animator/coat retained. Not gameplay, damage, seam or anatomy acceptance."
	add_child(scope)
	RenderingServer.frame_post_draw.connect(_after_draw)
	assert(rows.size()==8)
	complete=false

func _process(delta:float) -> void:
	if complete: return
	elapsed+=minf(delta,1.0/30)
	for row in rows: row["rig"].animate(minf(delta,1.0/30),row["input"])
	for pair in range(0,rows.size(),2):
		var a:CharacterRig=rows[pair]["rig"]
		var b:CharacterRig=rows[pair+1]["rig"]
		for bone_name in a.bone_order():
			assert(a.rest(bone_name).is_equal_approx(b.rest(bone_name)))
			assert(a.bone(bone_name).transform.is_equal_approx(b.bone(bone_name).transform))
	if next_sample<SAMPLE_TIMES.size() and elapsed>=SAMPLE_TIMES[next_sample]:
		pending=next_sample
		next_sample+=1
	if next_sample>=SAMPLE_TIMES.size() and pending<0:
		complete=true
		var file:=FileAccess.open(out,FileAccess.WRITE)
		file.store_string(JSON.stringify({"status":"PRIVATE_NOT_ACCEPTED","speed":speed,"seconds":elapsed,"captures":captures,"rows":rows.size()},"\t"))
		get_tree().quit()

func _after_draw() -> void:
	if pending<0: return
	for row in rows:
		var bounds:Rect2=row["rig"].visual_bounds()
		assert(bounds.position.x>=0 and bounds.position.y>=0 and bounds.end.x<=1600 and bounds.end.y<=1000,"Clipped character")
	var path:=out.get_base_dir().path_join("sample_%d.png"%pending)
	assert(CAPTURE.image(get_viewport()).save_png(path)==OK)
	captures.append({"index":pending,"seconds":elapsed,"file":path.get_file()})
	pending=-1
