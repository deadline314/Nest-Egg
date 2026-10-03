class_name EnemyData
extends Resource
## 敵人定義：數值與行為腳本分離。
## 新增敵人 = 新的行為腳本（繼承 Enemy）+ 新的 .tres + 在關卡 legend 指定字元。

@export var id: StringName = &"enemy"
@export var display_name: String = "敵人"
## 行為腳本，必須繼承 Enemy。
@export var behavior: Script
@export var is_boss: bool = false

@export_group("Appearance")
## 骨架外觀 id（art/characters/<id>）；空字串代表使用程式繪製外觀（機械類敵人）。
@export var rig_skin: String = ""
## 手持武器外觀 id（art/weapons/weapons.json）。
@export var rig_weapon: String = ""
@export var rig_two_handed: bool = true
## 後手向前舉盾。
@export var rig_shield: bool = false
## 招式動作：狀態名稱 → 專屬動作名稱（art/rigs/action_poses.json 的 actions），在該狀態期間播放；沒列的狀態用一般動畫。
@export var rig_actions: Dictionary = {}

@export_group("Body")
@export var body_size: Vector2 = Vector2(12, 20)
@export var color: Color = Color(0.9, 0.4, 0.35)
@export var uses_gravity: bool = true
@export var knockback_scale: float = 0.5

@export_group("Stats")
@export var max_health: int = 3
@export var move_speed: float = 50.0
@export var contact_damage: int = 1
@export var contact_source_id: StringName = &""

@export_group("Combat")
@export var detect_range: float = 220.0
@export var attack_range: float = 180.0
@export var attack_cooldown: float = 1.5
## 攻擊預兆時間：所有攻擊都必須有預兆，讓玩家「學會就能贏」。
@export var telegraph_time: float = 0.4
@export var projectile: ProjectileSpec
@export var extra_projectiles: Array[ProjectileSpec] = []
@export var summon: EnemyData

@export_group("Ability")
## 依行為解讀：衝刺速度、引信時間、爆炸半徑等。
@export var ability_speed: float = 0.0
@export var ability_time: float = 0.0
@export var ability_radius: float = 0.0
@export var ability_damage: int = 0

@export_group("Finisher")
## 生命低於此比例進入「破防」可被終結；0 代表不可終結。
@export_range(0.0, 1.0) var finish_health_ratio: float = 0.34
@export var stagger_duration: float = 1.2
@export_range(0.0, 1.0) var health_drop_chance: float = 0.1
## 被玩家擊敗時掉落的信用點（0 = 不掉）。
@export var credit_value: int = 0


func find_projectile(source: StringName) -> ProjectileSpec:
	if projectile != null and projectile.source_id == source:
		return projectile
	for spec in extra_projectiles:
		if spec != null and spec.source_id == source:
			return spec
	return null


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if behavior == null:
		problems.append("%s: 缺少 behavior 腳本" % id)
	if max_health <= 0:
		problems.append("%s: max_health 必須大於 0" % id)
	if body_size.x <= 0.0 or body_size.y <= 0.0:
		problems.append("%s: body_size 必須為正值" % id)
	return problems
