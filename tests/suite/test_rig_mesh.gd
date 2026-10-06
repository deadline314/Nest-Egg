class_name RigMeshSuite
extends TestSuite
## 肢體關節網格（NE-204）：膝與肘彎起來時輪廓是連續的曲線。測合成的骨頭（靜止＝不變形、遠端不動、彎到極限不折疊、
## 骨頭沒動不重算），再測所有人形角色：有成對的上下段就要做成網格、全部動作逐格不折疊、脫甲與燒融照常運作、可以關掉退回剛體。

const TEXTURE_SIZE := Vector2(40, 100)
const PIVOT := Vector2(20, 0)
const SCALE := 0.1
## 合成肢體：上段骨頭原點在 (0,0)，下段（膝）在 (0, 10)；貼圖 40×100 px、縮放 0.1＝世界 4×10，往下畫，比關節多出 1 像素的重疊。


func run() -> void:
	_test_synthetic()
	await _test_real_rigs()
	await _test_part_behaviour()


# ---------------------------------------------------------------------------
# 合成骨頭
# ---------------------------------------------------------------------------

func _chain() -> Dictionary:
	var root := Node2D.new()
	var upper := Bone2D.new()
	upper.rest = Transform2D(0.0, Vector2.ZERO)
	var lower := Bone2D.new()
	lower.position = Vector2(0, 10)
	lower.rest = Transform2D(0.0, Vector2(0, 10))
	root.add_child(upper)
	upper.add_child(lower)
	runner.add_child(root)
	return {"root": root, "upper": upper, "lower": lower}


func _mesh(chain: Dictionary, upper_part: bool) -> RigPartMesh:
	var mesh := RigPartMesh.new()
	mesh.scale = Vector2.ONE * SCALE
	var tex := PlaceholderTexture2D.new()
	tex.size = TEXTURE_SIZE
	var bone: Bone2D = chain["upper"] if upper_part else chain["lower"]
	var partner: Bone2D = chain["lower"] if upper_part else chain["upper"]
	# 上段零件從骨頭原點往下畫到關節下 1 像素；下段零件從關節上 1 像素往下畫。
	mesh.position = Vector2.ZERO if upper_part else Vector2(0, -1)
	var pivot := PIVOT if upper_part else PIVOT
	var size := TEXTURE_SIZE
	bone.add_child(mesh)
	check(mesh.setup(tex, size, pivot, bone, partner, upper_part, bone.rest.origin, partner.rest.origin, 3.0), "the synthetic %s part builds a mesh" % ("upper" if upper_part else "lower"))
	return mesh


func _test_synthetic() -> void:
	var chain := _chain()
	var upper := _mesh(chain, true)
	var lower := _mesh(chain, false)
	upper.refresh()
	check(upper.deformed_vertices() == upper.rest_vertices(), "at the rest pose the mesh is not deformed")
	check(upper.vertex_count() >= 9 and upper.triangle_count() >= 8, "the mesh has a grid (%d vertices, %d triangles)" % [upper.vertex_count(), upper.triangle_count()])
	var counted := upper.deform_count
	(chain["lower"] as Bone2D).rotation = 1.2
	upper.refresh()
	lower.refresh()
	check(upper.deform_count == counted + 1, "a bone that moved is re-deformed once")
	upper.refresh()
	check(upper.deform_count == counted + 1, "a bone that did not move is not re-deformed")
	var rest := upper.rest_vertices()
	var bent := upper.deformed_vertices()
	var far_moved := 0
	var near_moved := 0
	for i in rest.size():
		var y_world: float = rest[i].y * SCALE
		if bent[i].distance_to(rest[i]) > 0.01:
			if y_world < 6.5:
				far_moved += 1
			else:
				near_moved += 1
	check(far_moved == 0 and near_moved > 0, "only the vertices near the joint move (%d far, %d near)" % [far_moved, near_moved])
	for angle in [0.4, 0.9, 1.57, 2.1, 2.5, -0.5]:
		(chain["lower"] as Bone2D).rotation = angle
		upper.refresh()
		lower.refresh()
		if absf(angle) <= 0.9:
			check(upper.fold_count() == 0 and lower.fold_count() == 0, "no folded triangles up to about 50 degrees at %.2f rad (%d upper, %d lower)" % [angle, upper.fold_count(), lower.fold_count()])
		check(upper.fold_fraction() <= 0.4 and lower.fold_fraction() <= 0.4, "at most a few inner-side wrinkles at %.2f rad (%.2f upper, %.2f lower)" % [angle, upper.fold_fraction(), lower.fold_fraction()])
		check(is_finite(upper.width_ratio()) and upper.width_ratio() > 0.2, "the joint keeps most of its width at %.2f rad (ratio %.2f)" % [angle, upper.width_ratio()])
		# 彎曲後關節正中央的頂點由兩根骨頭平均決定，兩塊零件在那裡重合（接縫看不到）。
		var joint_upper := _nearest_world(upper, Vector2(0, 10))
		var joint_lower := _nearest_world(lower, Vector2(0, 10))
		check(joint_upper.distance_to(joint_lower) < 1.2, "the two parts meet at the joint at %.2f rad (%.2f apart)" % [angle, joint_upper.distance_to(joint_lower)])
	(chain["root"] as Node2D).queue_free()


## mesh 的頂點（轉成骨架空間）離 target 最近的那一個。
func _nearest_world(mesh: RigPartMesh, target: Vector2) -> Vector2:
	var best := Vector2.ZERO
	var best_distance := INF
	var bone := mesh.get_parent() as Node2D
	for vertex in mesh.deformed_vertices():
		# 骨架空間 = 骨頭空間經過骨頭本身的變換
		var point: Vector2 = (bone.transform * (mesh.transform * vertex))
		if point.distance_to(target) < best_distance:
			best_distance = point.distance_to(target)
			best = point
	return best


# ---------------------------------------------------------------------------
# 真實角色
# ---------------------------------------------------------------------------

func _humanoid_skins() -> Array[String]:
	var ids: Array[String] = []
	for dir in DirAccess.get_directories_at("res://art/characters"):
		var def := RigLibrary.character(dir)
		if not def.is_empty() and str(def.get("rig", "")).get_file() != "":
			ids.append(dir)
	ids.sort()
	return ids


func _test_real_rigs() -> void:
	var with_meshes := 0
	for skin in _humanoid_skins():
		var holder := Node2D.new()
		runner.get_tree().root.add_child(holder)
		var rig := CharacterRig.new()
		holder.add_child(rig)
		if not rig.setup(skin):
			holder.queue_free()
			continue
		var has_pairs := rig.has_bone(&"leg_front_upper") and rig.has_bone(&"leg_front_lower")
		var meshes := rig.limb_meshes().size()
		if has_pairs:
			check(meshes >= 4, "%s: the arms and legs are bendable meshes (%d)" % [skin, meshes])
			with_meshes += 1
		var vertices := 0
		for mesh in rig.limb_meshes():
			vertices += mesh.vertex_count()
		check(vertices <= 500, "%s: the limb meshes stay small (%d vertices)" % [skin, vertices])
		# 全部關節同時彎到活動範圍的極限
		for pair in [[&"leg_front_lower", 2.3], [&"leg_back_lower", 2.3], [&"arm_front_lower", -2.3], [&"arm_back_lower", -2.3], [&"leg_front_upper", -1.6], [&"arm_front_upper", -1.4]]:
			if rig.has_bone(pair[0]):
				rig.bone(pair[0]).rotation = pair[1]
		rig.refresh_limbs()
		var worst := 0.0
		for mesh in rig.limb_meshes():
			worst = maxf(worst, mesh.fold_fraction())
			for vertex in mesh.deformed_vertices():
				if not (is_finite(vertex.x) and is_finite(vertex.y)):
					check(false, "%s: %s has a non-finite vertex" % [skin, mesh.name])
					break
		check(worst <= 0.4, "%s: only a few wrinkles with every joint at its limit (%.2f of a part's triangles)" % [skin, worst])
		holder.queue_free()
		await frames(1)
	check(with_meshes >= 10, "most humanoid characters use limb meshes (%d)" % with_meshes)


func _test_part_behaviour() -> void:
	var holder := Node2D.new()
	runner.get_tree().root.add_child(holder)
	var rig := CharacterRig.new()
	holder.add_child(rig)
	check(rig.setup("rin"), "rin builds")
	var armor := rig.armor_count()
	check(armor >= 4, "the armor steps still exist with mesh limbs (%d)" % armor)
	var before := _visible_armor(rig)
	rig.set_armor_ratio(0.0, true)
	check(_visible_armor(rig) == 0 and before > 0, "stripping the armor hides the mesh parts too (%d -> %d)" % [before, _visible_armor(rig)])
	rig.set_armor_ratio(1.0, false)
	check(_visible_armor(rig) == before, "restoring the armor shows them again")
	check(rig.set_dissolve(0.5), "a rig with mesh limbs can be dissolved")
	check(not rig.visual_bounds().has_area() or rig.visual_bounds().size.y > 20.0, "the visual bounds cover the body")
	holder.queue_free()
	# 關掉時退回剛體零件
	CharacterRig.force_rigid_limbs = true
	var rigid_holder := Node2D.new()
	runner.get_tree().root.add_child(rigid_holder)
	var rigid := CharacterRig.new()
	rigid_holder.add_child(rigid)
	check(rigid.setup("rin") and rigid.limb_meshes().is_empty(), "with limb bending off every part is a rigid sprite")
	CharacterRig.force_rigid_limbs = false
	rigid_holder.queue_free()
	await frames(1)


func _visible_armor(rig: CharacterRig) -> int:
	var count := 0
	for node in rig.find_children("armor_*", "CanvasItem", true, false):
		count += 1 if (node as CanvasItem).visible else 0
	return count
