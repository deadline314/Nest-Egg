extends RefCounted

static func run(s: TestSuite) -> void:
	const TEX := "res://art/environment/props/trash_can.png"
	var native := RigLibrary.texture_size(TEX)
	RigLibrary.optional_texture(TEX)  # 快取預熱；不把首次載入當作持物洩漏。
	var initial_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	for kind: String in ["rin", "old_k"]:
		for facing: int in [-1, 1]:
			for hand: StringName in [&"front", &"back"]:
				var stage := StageLibrary.Stage.new()
				s.runner.add_child(stage)
				stage.position = Vector2(40, 70)
				stage.rotation = 0.11
				stage.scale = Vector2.ONE * 1.3
				var def := {"kind": "sprite", "id": "held_fixture", "path": TEX, "pos": [0, 0], "source_width": native.x, "scale": 0.2}
				var sprite := StageLayers.create(def, "hold fixture") as StageLayers._Sprite
				stage.add_layer(sprite)
				sprite.rotation = 0.12
				var actor := CutsceneActor.new()
				stage.actors.add_child(actor)
				actor.setup(&"hold_test", kind, "", 3.9 if kind == "rin" else 4.0, "")
				actor.position = Vector2(160, 304)
				actor.layer_slot = 1
				actor.z_index = WorldLayers.stage_actor_z(1)
				actor.face(facing)
				actor.set_process(false)
				for frame in 120:
					actor._process(1.0 / 60.0)
				var source := native * Vector2(0.5, 0.2)
				sprite.position = Vector2(160, 154) - sprite.transform.basis_xform(sprite.source_point(source))
				var raw_contact := Vector2(64, 39) if kind == "old_k" else (Vector2(73, 40) if hand == &"front" else Vector2(92, 38))
				var command := {"hand": String(hand), "space": "prop", "prop": "held_fixture", "to": [source.x, source.y], "contact": [raw_contact.x, raw_contact.y], "angle": PI * 0.5, "time": 0.1}
				var binding := StagePropBinding.new(sprite, source)
				var label := "%s/%d/%s" % [kind, facing, hand]
				s.check(actor.set_hand_target(command, binding), label + " starts calibrated prop contact")
				actor._process(0.1)
				var contact_position := sprite.position
				sprite.position += Vector2(8, 0)
				s.check(not stage.hold_prop("held_fixture", actor, hand, source).is_empty() and sprite.position == contact_position + Vector2(8, 0), label + " distant prop cannot teleport into the hand")
				sprite.position = contact_position
				var instance := sprite.get_instance_id()
				var parent := sprite.get_parent()
				var original_z := sprite.z_index
				var original_relative := sprite.z_as_relative
				var original_material := sprite.material
				var original_tint := sprite.self_modulate
				var original_texture := sprite.texture
				var original_width := sprite.texture.get_width() * (stage.global_transform.affine_inverse() * sprite.global_transform).x.length()
				s.check(stage.hold_prop("held_fixture", actor, hand, source).is_empty(), label + " actual touching prop can be held")
				s.check(sprite.material == actor.rig._light_material and sprite.texture == original_texture, label + " held physical prop shares the actor response without replacing its diffuse/normal")
				s.check(stage.prop_held("held_fixture") and sprite.get_instance_id() == instance and sprite.get_parent() == parent, label + " holds the identical stage node without reparenting or cloning")
				s.check(not stage.hold_prop("held_fixture", actor, hand, source).is_empty(), label + " rejects duplicate ownership of one prop")
				for frame in 8:
					actor.position.x = 160.0 + frame * 8.0
					actor.face(facing if frame % 2 == 0 else -facing)
					stage.position += Vector2(2, -1)
					stage.rotation += 0.03
					stage.scale = Vector2.ONE * (1.3 + frame * 0.02)
					if frame == 3:
						var image := Image.create(maxi(1, sprite.texture.get_width() / 2), maxi(1, sprite.texture.get_height() / 2), false, Image.FORMAT_RGBA8)
						image.fill(Color.WHITE)
						sprite.texture = ImageTexture.create_from_image(image)
					actor._process(1.0 / 60.0)
					stage._process(1.0 / 60.0)
					var palm := actor.hand_contact_global(hand)
					var physical_prop := sprite.to_global(sprite.source_point(source))
					var transform := stage.global_transform.affine_inverse() * sprite.global_transform
					s.check(palm.distance_to(physical_prop) < 0.02, label + " physical grip follows translation turn and camera at frame %d" % frame)
					s.check(transform.determinant() > 0.0 and absf(wrapf(transform.x.angle() - 0.12, -PI, PI)) < 0.001, label + " actor mirror cannot invert or turn the held prop")
					s.check(absf(sprite.texture.get_width() * transform.x.length() - original_width) < 0.01, label + " texture resolution change preserves authored prop width")
				s.check(stage.release_prop("held_fixture") and not stage.prop_held("held_fixture") and not stage.is_processing(), label + " release removes the binding and disables idle hold work")
				s.check(sprite.z_index == original_z and sprite.z_as_relative == original_relative, label + " release restores its original layer rules")
				s.check(sprite.material == original_material and sprite.self_modulate == original_tint, label + " release restores the original stage appearance")
				var released_position := sprite.position
				actor.position.x += 30
				actor._process(1.0 / 60.0)
				stage._process(1.0 / 60.0)
				s.check(sprite.position.distance_to(released_position) < 0.01, label + " released object stays on stage when actor walks away")
				actor.set_hand_target(command, StagePropBinding.new(sprite, source))
				actor._process(0.1)
				s.check(stage.hold_prop("held_fixture", actor, hand, source).is_empty(), label + " same object can be picked up again after a real new contact")
				actor.free()
				stage._process(1.0 / 60.0)
				s.check(not stage.prop_held("held_fixture") and not stage.is_processing() and sprite.z_as_relative == original_relative, label + " disappearing actor safely releases weak hold ownership")
				s.check(sprite.material == original_material and sprite.self_modulate == original_tint, label + " disappearing actor cannot leave a stale held material behind")
				stage.free()
	_shared_contacts(s, TEX, native)
	s.check(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) == initial_nodes, "repeated hold move mirror resize release and owner destruction retain no scene nodes")


## 真角色／真網格的同格負控：主手更新道具之後，第二手才讀新變換。
static func _shared_contacts(s: TestSuite, texture: String, native: Vector2) -> void:
	var stage := StageLibrary.Stage.new()
	s.runner.add_child(stage)
	var player := CutscenePlayer.new()
	s.runner.add_child(player)
	player._running = true
	var sprite := StageLayers.create({"kind":"sprite","id":"shared","path":texture,"pos":[0,0],"source_width":native.x,"scale":.2}, "shared contact fixture") as StageLayers._Sprite
	stage.add_layer(sprite)
	var first := native * Vector2(.3,.2)
	var second := native * Vector2(.7,.2)
	var offset := (second.x-first.x)*.2
	var actors: Array[CutsceneActor] = []
	for index in 2:
		var actor := CutsceneActor.new()
		stage.actors.add_child(actor)
		actor.setup(StringName("shared_%d" % index), "rin", "", 3.9, "")
		actor.position=Vector2(160+offset*index,304)
		actor.set_process(true)
		for frame in 120:actor._process(1.0/60.0)
		actors.append(actor)
		player._actors[actor.actor_id]=actor
	sprite.position=Vector2(160,154)-sprite.transform.basis_xform(sprite.source_point(first))
	for index in 2:
		var point:=first if index==0 else second
		s.check(actors[index].set_hand_target({"hand":"front","to":[point.x,point.y],"contact":[73,40],"angle":PI*.5,"time":.1}, StagePropBinding.new(sprite,point)), "同物第二手建立具體來源接觸")
		actors[index]._process(.1)
	s.check(stage.hold_prop("shared",actors[0],&"front",first).is_empty(), "主手只在真接觸後持有同一物件")
	var worst_lag:=0.0
	var worst_contact:=0.0
	var deformed_changed:=false
	for frame in 40:
		var delta:=1.0/120.0 if frame%2==0 else 1.0/30.0
		for index in 2:
			actors[index].position.x=160+offset*index+frame*1.25
			actors[index]._process(delta)
		stage._process(delta)
		var actor:=actors[1]
		var reach:CutsceneReach=actor._reaches[0]
		var target:=sprite.to_global(sprite.source_point(second))
		worst_lag=maxf(worst_lag,actor.hand_contact_global(&"front").distance_to(target))
		var t:=actor._t
		var animation_time:float=actor.rig.animator._time
		var elapsed:=reach._elapsed
		var weight:=reach.weight
		var before:Dictionary={}
		for mesh:RigPartMesh in actor.rig._meshes:
			if mesh.get_parent().name==&"arm_front_upper" or mesh.get_parent().name==&"arm_front_lower":
				before[mesh.get_instance_id()]=mesh.deformed_vertices().duplicate()
		player._process(delta)
		worst_contact=maxf(worst_contact,actor.hand_contact_global(&"front").distance_to(target))
		for mesh:RigPartMesh in actor.rig._meshes:
			if mesh.get_parent().name==&"arm_front_upper" or mesh.get_parent().name==&"arm_front_lower":
				deformed_changed=deformed_changed or mesh.deformed_vertices()!=before[mesh.get_instance_id()]
		s.check(actor._t==t and actor.rig.animator._time==animation_time and reach._elapsed==elapsed and reach.weight==weight,"最後重解不推進角色、動畫或 reach 平滑時鐘")
	s.check(worst_lag>StagePropHold.CONTACT_TOLERANCE,"省略最後階段的原生骨架負控可抓到一格落後")
	s.check(worst_contact<.02,"最後階段使同一影格第二掌心貼住實際 held prop")
	s.check(deformed_changed,"接觸重解沿真 RigPartMesh 變形快取發布")
	s.check(not stage.held_contact_problem(actors[0],&"front",sprite).is_empty(),"持有手不得回綁自己的 held prop")
	s.check(stage.held_contact_problem(actors[1],&"front",sprite).is_empty(),"空閒第二手可跟隨同一 held prop")
	var other:=StageLayers.create({"kind":"sprite","id":"other","path":texture,"pos":[0,0],"source_width":native.x,"scale":.2},"other hold fixture") as StageLayers._Sprite
	stage.add_layer(other)
	other.position=actors[1].hand_contact_global(&"front")-other.transform.basis_xform(other.source_point(first))
	s.check(stage.hold_prop("other",actors[1],&"front",first).is_empty(),"互持負控先保留兩個真實擁有者")
	s.check(not stage.held_contact_problem(actors[0],&"front",other).is_empty() and not stage.held_contact_problem(actors[1],&"front",sprite).is_empty(),"兩個持有手不可建立互持回授")
	stage.release_prop("other")
	s.check(actors[1].set_hand_target({"hand":"front","to":[second.x,second.y],"contact":[73,40],"angle":PI*.5,"time":.1},StagePropBinding.new(sprite,second)),"死亡負控重新建立活動的第二手依賴")
	actors[1]._process(.1)
	var saved:=actors[1].hand_contact_global(&"front")
	actors[1].set_pose(&"dead")
	sprite.position.x+=12
	player._process(1.0/60.0)
	s.check(actors[1].hand_contact_global(&"front")==saved,"新增死亡不能被最後接觸階段重啟")
	player._actors.clear()
	player._running=false
	player.free()
	stage.free()
