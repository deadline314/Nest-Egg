class_name MaterialDummy
extends Node2D
## 打擊感實驗室的靶（NE-133）：帶材質標籤的木樁，打不死（每次受傷後補滿），受擊會閃白並累計次數與傷害；
## moving 為 true 時左右來回走，當移動靶。使用正式的受擊框與生命元件，所以子彈、近戰、爆炸都照真實規則命中。

const SIZE := Vector2(18.0, 40.0)
const MATERIAL_COLORS := {
	&"flesh": Color("b0454f"), &"armor": Color("a48a4a"), &"metal": Color("8d97ab"), &"glass": Color("6fb8cc"),
	&"wood": Color("8b6b43"), &"concrete": Color("7c8494"), &"energy": Color("3fc4d8"), &"generic": Color("9aa0aa"),
}

var hit_material: StringName = &"generic"
var moving := false
## 預兆靶：每隔幾秒閃紅光預告（0.6 秒、有預兆音），接著朝玩家打出一發敵人子彈，測預兆提示與格擋、閃避。
var telegraphing_target := false
var telegraph_left := 0.0
var health: HealthComponent
var hurtbox: Hurtbox
var hits := 0
var total_damage := 0

var _origin_x := 0.0
var _time := 0.0
var _flash := 0.0


func setup(material: StringName, p_moving := false, p_telegraph := false) -> void:
	hit_material = material
	moving = p_moving
	telegraphing_target = p_telegraph


func _ready() -> void:
	_origin_x = position.x
	health = HealthComponent.new()
	add_child(health)
	health.setup(9999, 0.0)
	health.damaged.connect(_on_damaged)
	hurtbox = Hurtbox.new()
	add_child(hurtbox)
	hurtbox.setup(Combat.Team.ENEMY, health, SIZE, Vector2(0.0, -SIZE.y * 0.5))
	hurtbox.hit_material = hit_material
	add_to_group(&"feel_lab_targets")


func _physics_process(delta: float) -> void:
	_time += delta
	_flash = maxf(0.0, _flash - delta)
	if telegraphing_target:
		_tick_telegraph(delta)
	if moving:
		position.x = _origin_x + sin(_time * 1.4) * 70.0
	queue_redraw()


const TELEGRAPH_INTERVAL := 3.0
const TELEGRAPH_TIME := 0.6
var _attack_cooldown := TELEGRAPH_INTERVAL


func _tick_telegraph(delta: float) -> void:
	if telegraph_left > 0.0:
		telegraph_left -= delta
		if telegraph_left <= 0.0:
			_fire_at_player()
		return
	_attack_cooldown -= delta
	if _attack_cooldown <= 0.0:
		_attack_cooldown = TELEGRAPH_INTERVAL
		telegraph_left = TELEGRAPH_TIME
		Sfx.play(&"telegraph", -4.0)


func _fire_at_player() -> void:
	var players := get_tree().get_nodes_in_group(&"player")
	if players.is_empty():
		return
	var target := players[0] as Node2D
	var origin := global_position + Vector2(0.0, -SIZE.y * 0.6)
	var spec := load("res://data/projectiles/grunt_shot.tres") as ProjectileSpec
	ProjectilePool.spawn(spec, origin, (target.global_position + Vector2(0.0, -24.0) - origin).normalized(), Combat.Team.ENEMY)
	Sfx.play(&"shot_enemy", -8.0)


func _on_damaged(info: DamageInfo) -> void:
	hits += 1
	total_damage += info.amount
	_flash = 0.12
	health.current = health.max_health  # 打不死
	health.is_dead = false


func _draw() -> void:
	var color: Color = MATERIAL_COLORS.get(hit_material, Color.WHITE)
	if telegraph_left > 0.0:
		color = color.lerp(Color(1.0, 0.2, 0.25), 0.8)
		draw_string(UiKit.font(), Vector2(-3.0, -SIZE.y - 14.0), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.3, 0.3))
	if _flash > 0.0:
		color = color.lerp(Color.WHITE, 0.7)
	draw_rect(Rect2(Vector2(-SIZE.x * 0.5, -SIZE.y), SIZE), color.darkened(0.45))
	draw_rect(Rect2(Vector2(-SIZE.x * 0.5, -SIZE.y), SIZE), color, false, 1.5)
	draw_rect(Rect2(Vector2(-SIZE.x * 0.5 + 3.0, -SIZE.y + 3.0), Vector2(SIZE.x - 6.0, 6.0)), color.lightened(0.2))
	var font := UiKit.font()
	draw_string(font, Vector2(-14.0, -SIZE.y - 10.0), String(hit_material), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.85))
	draw_string(font, Vector2(-14.0, -SIZE.y - 2.0), "%d / %d" % [hits, total_damage], HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.6, 0.9, 1.0, 0.8))
