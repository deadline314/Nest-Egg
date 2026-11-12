extends Node
## Observe actual targets/callbacks at segment boundaries. Never alter combat.
var problems: Array[String] = []
var current: Dictionary = {}
var host: Player
var targets: Array[WeakRef] = []
var clock: Node

func _ready() -> void:
	Sfx.sound_played.connect(_sound)
	EventBus.hit_confirmed.connect(_confirmed)

func _exit_tree() -> void:
	if Sfx.sound_played.is_connected(_sound):Sfx.sound_played.disconnect(_sound)
	if EventBus.hit_confirmed.is_connected(_confirmed):EventBus.hit_confirmed.disconnect(_confirmed)

func spaces(node: Node, result: Array) -> void:
	if node is CollisionObject2D:
		var space := PhysicsServer2D.body_get_space(node.get_rid()) if node is PhysicsBody2D else PhysicsServer2D.area_get_space(node.get_rid())
		result.append({"path":String(node.get_path()),"can_process":node.can_process(),"space":space.get_id()})
	for child in node.get_children():spaces(child,result)

func begin(segment: Dictionary, player: Player, sample_clock: Node) -> void:
	current=segment
	host=player
	clock=sample_clock
	targets.clear()
	var data := {"targets_start":[],"targets_end":[],"damage":[],"hit_confirmed":[],"audio_calls":[],"closed":false,"physics_start":Engine.get_physics_frames()}
	for foe: Enemy in get_tree().get_nodes_in_group(&"enemies"):
		var collision: Array=[]
		spaces(foe,collision)
		data["targets_start"].append({"id":foe.get_instance_id(),"health":foe.health.current,"can_process":foe.can_process(),"spaces":collision,"material":String(foe.hurtbox.material_id())})
		targets.append(weakref(foe))
		if not foe.health.damaged.is_connected(_damage):foe.health.damaged.connect(_damage)
	var hum := player.find_child("MeleeHum",true,false)
	data["hum_start"]=String(hum.call(&"sounding")) if hum!=null else ""
	current["content"]=data

func _attack_index() -> int:
	return host._melee_index if is_instance_valid(host) else -1

func _pose() -> Dictionary:
	var result := {"physics_frame":Engine.get_physics_frames(),"position":[host.global_position.x,host.global_position.y],"phase":host._melee_phase,"phase_time":host.melee.time,"attack_index":_attack_index(),"landed":host.melee.landed,"targets":[]}
	if not host.melee.attack.is_empty():
		var chest: Vector2=host.melee._chest()
		var direction: Vector2=host.melee.direction(host.melee.attack)
		result["chest"]=[chest.x,chest.y]
		result["direction"]=[direction.x,direction.y]
		result["range"]=host.melee.attack["range"]
		result["query_target_count"]=host.melee.targets(host.melee.attack).size()
		for ref in targets:
			var foe := ref.get_ref() as Enemy
			if foe==null:continue
			var closest: Vector2=foe.hurtbox.closest_point(chest)
			result["targets"].append({"id":foe.get_instance_id(),"health":foe.health.current,"position":[foe.global_position.x,foe.global_position.y],"closest":[closest.x,closest.y],"closest_distance":closest.distance_to(chest),"can_process":foe.can_process(),"body_space":PhysicsServer2D.body_get_space(foe.get_rid()).get_id(),"hurtbox_space":PhysicsServer2D.area_get_space(foe.hurtbox.get_rid()).get_id()})
	return result

func _damage(info: DamageInfo) -> void:
	if current.is_empty():return
	current["content"]["damage"].append({"source_id":String(info.source_id),"amount":info.amount,"weak":info.weak_hit,"attack_index":_attack_index(),"physics_frame":Engine.get_physics_frames(),"pose":_pose()})

func _sound(id: StringName) -> void:
	if current.is_empty():return
	var event := {"id":String(id),"attack_index":_attack_index(),"physics_frame":Engine.get_physics_frames()}
	if String(id).begins_with("melee_"):event["pose"]=_pose()
	current["content"]["audio_calls"].append(event)

func _confirmed(point: Vector2, killed: bool) -> void:
	if current.is_empty():return
	current["content"]["hit_confirmed"].append({"point":[point.x,point.y],"killed":killed,"physics_frame":Engine.get_physics_frames()})

func require(ok: bool, message: String) -> void:
	if ok:return
	var context := "%s/%s: %s" % [current["weapon"],current["part"],message]
	problems.append(context)
	push_error("[MeleeSoundContent] " + context)

func close() -> void:
	if current.is_empty():return
	var data: Dictionary=current["content"]
	for ref in targets:
		var foe := ref.get_ref() as Enemy
		if foe!=null:data["targets_end"].append({"id":foe.get_instance_id(),"health":foe.health.current})
	var hum := host.find_child("MeleeHum",true,false) if is_instance_valid(host) else null
	data["hum_end"]=String(hum.call(&"sounding")) if hum!=null else ""
	data["physics_end"]=Engine.get_physics_frames()
	data["closed"]=true
	data["sample_end_frames"]=clock.mark()
	var part: String=current["part"]
	if part in ["pistol_hit","combo_hit"]:
		require(data["targets_start"].size()==1,"exactly one real target required")
		for target: Dictionary in data["targets_start"]:
			require(target["can_process"] and not target["spaces"].is_empty(),"target must actually process")
			for space: Dictionary in target["spaces"]:require(space["space"]!=0,"target collider missing actual physics space: " + space["path"])
		require(not data["damage"].is_empty() and not data["hit_confirmed"].is_empty(),"actual Health.damaged and hit_confirmed required")
		var expected_source := "player_pistol" if part=="pistol_hit" else "melee"
		for event: Dictionary in data["damage"]:require(event["source_id"]==expected_source,"wrong actual damage source")
		require("mat_armor" in current["sounds"],"actual armor material sound required")
		if part=="pistol_hit":require(data["damage"].size()==3,"all three reference shots must really damage")
		else:
			for event: Dictionary in data["audio_calls"]:
				if event["id"].begins_with("melee_%s_hit" % current["weapon"]):
					var matches := false
					for damage: Dictionary in data["damage"]:
						matches=matches or (damage["attack_index"]==event["attack_index"] and damage["physics_frame"]<=event["physics_frame"])
					require(matches,"hit layer without actual prior damage in same attack")
				elif event["id"].begins_with("melee_%s_swing" % current["weapon"]):require(not event["pose"]["landed"],"swing emitted despite already landed strike")
	if part in ["pistol","combo_miss"]:
		require(data["targets_start"].is_empty() and data["damage"].is_empty() and data["hit_confirmed"].is_empty(),"miss segment must have no target or actual hit")
	if part=="idle":require(data["hum_end"]=="melee_%s_idle" % current["weapon"],"real idle player must sound correct weapon")
	if part=="holster":require(data["hum_end"].is_empty(),"real idle player must stop after holster")
	current={}
	targets.clear()
