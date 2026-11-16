extends RefCounted
## Actual source methods, deferred ownership races, physics callbacks and real pickup effects.
class DropEnemy extends Enemy:
	func _setup_states() -> void:
		fsm.add(&"drop_test_idle", func(_delta: float) -> void: pass)
		fsm.start(&"drop_test_idle")
	func _draw_body(_color: Color) -> void: pass

class DropLevel extends Level:
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)

class CountedPickup extends CreditPickup:
	var ready_count := 0
	func _ready() -> void:
		ready_count += 1
		super._ready()

static func run(s: EnemySuiteBase) -> void:
	await _ownership(s)
	await _source_teardown(s)
	await _physics_callback(s)
	await _rewards(s)

static func _enemy() -> DropEnemy:
	var enemy := DropEnemy.new()
	enemy.data = EnemyData.new()
	enemy.data.id = &"ch1_inspector"  # Existing production VFX definition, not a missing fixture id.
	enemy.data.credit_value = 17
	enemy.data.health_drop_chance = 1.0
	return enemy

static func _ownership(s: TestSuite) -> void:
	var tree := s.runner.get_tree()
	var before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for mode: String in ["normal", "child_free", "child_queued", "other_owner", "parent_free", "parent_queued", "parent_detached"]:
		var owner := Node2D.new()
		var other := Node2D.new()
		tree.root.add_child(owner)
		tree.root.add_child(other)
		var child := CountedPickup.new()
		var ref: WeakRef = weakref(child)
		var id := child.get_instance_id()
		Pickup.add_deferred(owner, child)
		Pickup.add_deferred(owner, child)  # Duplicate pending request must still enter only once.
		match mode:
			"child_free": child.free()
			"child_queued": child.queue_free()
			"other_owner":
				other.add_child(child)
				owner.free()
			"parent_free": owner.free()
			"parent_queued": owner.queue_free()
			"parent_detached": tree.root.remove_child(owner)
		await s.frames(3)
		if mode == "normal" or mode == "other_owner":
			var live := ref.get_ref() as CountedPickup
			s.check(live != null and live.get_parent() == (other if mode == "other_owner" else owner) and live.ready_count == 1,
					"pending pickup enters once and respects its current owner: %s id=%d" % [mode, id])
		else:
			s.check(ref.get_ref() == null and not is_instance_id_valid(id), "pending pickup is actually released: %s id=%d" % [mode, id])
		if is_instance_valid(owner): owner.free()
		other.free()
	var owned := CountedPickup.new()
	var keeper := Node2D.new()
	tree.root.add_child(keeper)
	keeper.add_child(owned)
	Pickup.add_deferred(null, owned)
	s.check(is_instance_valid(owned) and owned.get_parent() == keeper, "invalid requested parent never frees another owner's pickup")
	keeper.free()
	var rejected := HealthPickup.new()
	var rejected_id := rejected.get_instance_id()
	Pickup.add_deferred(null, rejected)
	s.check(not is_instance_id_valid(rejected_id), "no owner at request time releases only the unowned pickup")
	await s.frames(2)
	s.check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == before, "ownership races leave no additional orphan nodes")

static func _source_teardown(s: TestSuite) -> void:
	var before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for mode: String in ["credit", "health", "box", "weapon", "consumable"]:
		for queued: bool in [false, true]:
			var owner: Node2D
			if mode in ["box", "weapon", "consumable"]:
				var level := DropLevel.new()
				level._entities = Node2D.new()
				level.add_child(level._entities)
				s.runner.get_tree().root.add_child(level)
				owner = level
				var box := Breakable.new()
				var spec := _box_spec(mode)
				box.configure(spec, Vector2i(1, 1), 16)
				level._entities.add_child(box)
				level._on_breakable_broken(box)
			else:
				owner = Node2D.new()
				s.runner.get_tree().root.add_child(owner)
				var enemy := _enemy()
				if mode == "health": enemy.data.credit_value = 0
				owner.add_child(enemy)
				enemy.set_physics_process(false)
				if mode == "credit": enemy._drop_credits()
				else: enemy._try_drop(false)
			var owner_id := owner.get_instance_id()
			if queued: owner.queue_free()
			else: owner.free()
			await s.frames(3)
			s.check(not is_instance_id_valid(owner_id) and int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == before,
					"actual %s drop retires with its receiver (queued=%s)" % [mode, queued])

static func _physics_callback(s: TestSuite) -> void:
	var owner := Node2D.new()
	s.runner.get_tree().root.add_child(owner)
	var enemy := _enemy()
	owner.add_child(enemy)
	enemy.set_physics_process(false)
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 1
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	area.add_child(shape)
	var body := CharacterBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var body_shape := CollisionShape2D.new()
	body_shape.shape = RectangleShape2D.new()
	body.add_child(body_shape)
	var observed := [false, false]
	area.body_entered.connect(func(_body: Node2D) -> void:
		observed[0] = true
		enemy._drop_credits()
		for node in owner.get_children():
			if node is Pickup: observed[1] = true)
	owner.add_child(area)
	owner.add_child(body)
	await s.physics_frames(4)
	await s.frames(2)
	var drops := _pickups(owner)
	s.check(observed[0] and not observed[1] and drops.size() == 1, "real physics body_entered defers collision pickup attachment until after the callback")
	owner.free()
	await s.frames(2)

static func _box_spec(kind: String) -> BreakableData:
	var spec := BreakableData.new()
	if kind == "box":
		spec.credit_drop = 23
		spec.health_drop_chance = 1.0
	else:
		spec.drop_chance = 1.0
		spec.drops = [load("res://data/weapons/rifle.tres") if kind == "weapon" else ConsumableBag.find(&"med_injector")]
	return spec

static func _pickups(owner: Node) -> Array[Pickup]:
	var result: Array[Pickup] = []
	for child in owner.get_children():
		if child is Pickup: result.append(child)
	return result

static func _collect_once(s: TestSuite, pickup: Pickup, player: Player) -> void:
	var id := pickup.get_instance_id()
	pickup._on_body_entered(player)
	pickup._on_body_entered(player)
	await s.frames(2)
	s.check(not is_instance_id_valid(id), "real pickup is consumed once and actually freed id=%d" % id)

static func _rewards(s: EnemySuiteBase) -> void:
	await s.open_level(10.0)
	var level := s.level
	var player := level.player
	player.set_physics_process(false)
	player.health.setup(10, 0.0)
	player.health.current = 5
	var owner := Node2D.new()
	level._entities.add_child(owner)
	var enemy := _enemy()
	enemy.position = Vector2(700, 300)
	owner.add_child(enemy)
	enemy.set_physics_process(false)
	enemy._drop_credits()
	await s.frames(2)
	var drops := _pickups(owner)
	s.check(drops.size() == 1 and drops[0] is CreditPickup, "real enemy credits produce exactly one reward")
	if drops.size() == 1 and drops[0] is CreditPickup:
		var credit := drops[0] as CreditPickup
		s.check(credit.value == 17 and credit.position.y == 296 and absf(credit.position.x - 700) <= 6.0, "enemy credit amount and original random position range remain")
		var before := Progression.credits
		await _collect_once(s, credit, player)
		s.check(Progression.credits == before + 17, "two pickup notifications award enemy credits only once")
	enemy.data.credit_value = 0
	enemy._try_drop(false)
	await s.frames(2)
	drops = _pickups(owner)
	s.check(drops.size() == 1 and drops[0] is HealthPickup and drops[0].position == Vector2(700, 296), "real enemy supply preserves one pickup and its position")
	if drops.size() == 1 and drops[0] is HealthPickup:
		await _collect_once(s, drops[0], player)
		s.check(player.health.current == 7, "two notifications apply the enemy health reward only once")
	owner.free()
	for index in 3:
		var kind: String = ["box", "weapon", "consumable"][index]
		if kind == "weapon": player.loadout.reset(load("res://data/weapons/pistol.tres"))
		if kind == "consumable": player.consumables.restore({})
		var spec := _box_spec(kind)
		var box := level._create_prop({"resource": spec, "cell": Vector2i(45 + index * 3, 20)}) as Breakable
		box.position = Vector2(720 + index * 48, 320)
		level._entities.add_child(box)
		var previous := _pickups(level._entities)
		var expected_position := box.world_center()
		box._on_died(null)
		box._on_died(null)
		await s.frames(3)
		drops = _pickups(level._entities)
		for old: Pickup in previous: drops.erase(old)
		s.check(drops.size() == (2 if kind == "box" else 1), "real broken signal produces the original reward count exactly once: " + kind)
		for drop: Pickup in drops:
			s.check(drop.position == expected_position, "box reward retains its original world-center position: " + kind)
			if drop is CreditPickup:
				var before := Progression.credits
				await _collect_once(s, drop, player)
				s.check(Progression.credits == before + 23, "box credit award is unchanged and not duplicated")
			elif drop is HealthPickup:
				player.health.current = 5
				await _collect_once(s, drop, player)
				s.check(player.health.current == 7, "box repair award is unchanged and not duplicated")
			elif drop is WeaponPickup:
				var switches := [0]
				var on_switch := func() -> void: switches[0] += 1
				player.loadout.weapon_switched.connect(on_switch)
				await _collect_once(s, drop, player)
				s.check(player.loadout.weapon_in(player.loadout.active_slot).id == &"rifle" and switches[0] == 1, "box weapon configuration and one actual equip remain")
				player.loadout.weapon_switched.disconnect(on_switch)
			elif drop is ConsumablePickup:
				var before := player.consumables.count(&"med_injector")
				await _collect_once(s, drop, player)
				s.check(player.consumables.count(&"med_injector") == before + 1, "box consumable configuration and single inventory award remain")
	await s.end_level(level)
