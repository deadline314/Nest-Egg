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
## 攻擊類別（預兆提示音與視覺語言依此共用）：ranged 遠程子彈、melee 近戰、explosive 爆炸、beam 光束／火焰／雷射、charge 衝撞撲咬、support 輔助（不造成傷害）。
@export var attack_category: StringName = &"ranged"
## 預兆短於 0.4 秒（24 格）時必須寫明理由；空字串＝沒有例外，資料檢查會要求預兆至少 0.4 秒。
@export var telegraph_exempt: String = ""
## 命中材質（火花、碎屑與聲音依此變化）：flesh、armor、metal、glass、wood、concrete、energy；空字串用通用回饋。
@export var hit_material: StringName = &""
## 零件式外觀（art/creatures/<id>.json，PartCreature）：機械類與動物類的非人形敵人用；空字串＝用骨架或程式繪製。
@export var creature_skin: String = ""
## 觸手生物外觀的整體縮放（同一組美術的小隻版本，例如浮標蟲分裂出來的小蟲）。
@export var creature_scale: float = 1.0
## 狀態名稱 → 零件動畫的狀態名稱；沒列的狀態用同名的動畫，找不到就用 idle。
@export var creature_states: Dictionary = {}
## 招式動作：狀態名稱 → 專屬動作名稱（art/rigs/action_poses.json 的 actions），在該狀態期間播放；沒列的狀態用一般動畫。
@export var rig_actions: Dictionary = {}
## 放鬆的狀態（還沒發現玩家）：這些狀態下武器自然垂下，其他狀態與被警報引來時才舉槍。
@export var relaxed_states: PackedStringArray = ["patrol", "idle", "stalk"]

@export_group("Body")
@export var body_size: Vector2 = Vector2(12, 20)
@export var color: Color = Color(0.9, 0.4, 0.35)
@export var uses_gravity: bool = true
@export var knockback_scale: float = 0.5

@export_group("Stats")
@export var max_health: int = 3
## 持久世界裡，受過的傷會保留（離開區域、玩家死亡後都在，死亡時回復一部分，比例見 LevelData.death_boss_recovery）。迷你頭目用。
@export var persists_damage: bool = false
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

@export_group("Strike")
## 貼身與鎖鏈類攻擊（StrikeEnemy）的參數：判定範圍、高度帶、出招區間、鎖鏈與鉤子等；欄位說明與預設見 StrikeSpec。其他敵人留空。
@export var strike: Dictionary = {}

@export_group("Reaction")
## 韌性（耐打程度）：連續中彈累積的衝擊力達到此值就畏縮；單次衝擊達 1.5 倍就硬直（打斷動作）。頭目設很高就幾乎不畏縮。
@export var poise: float = 4.0
## 畏縮（動作暫停）與硬直（打斷動作）的秒數。
@export var flinch_time: float = 0.18
@export var stagger_time: float = 0.45
## 出招中的狀態：這些狀態下輕擊與累積都打不斷，只有單次衝擊達韌性 2.5 倍的重擊才會硬直（蓄力階段不在其中，所以蓄力可以被打斷）。
@export var armor_states: PackedStringArray = ["leap", "charge", "dash", "burst", "fire", "pounce", "lunge", "burn", "dive"]

@export_group("Body reaction")
## 沒有骨架的敵人（機械類）被打到時身體的反應：wobble 震動（砲台、迫擊砲）、stall 失速傾斜下沉（飛行機）、
## stumble 踉蹌壓扁（地面爬行的）。幅度 hit_amount 是像素（stall 是弧度的倍率）。人形敵人用骨架的受擊動作，不看這兩個欄位。
@export_enum("wobble", "stall", "stumble") var hit_style: String = "wobble"
@export var hit_amount: float = 1.5
## 損傷狀態：生命比例降到這些值以下（約剩 2/3、1/3）時外觀變舊、冒煙與火花（由高到低）。空陣列＝沒有損傷狀態。
@export var damage_states: PackedFloat32Array = [0.67, 0.34]

@export_group("Hurt parts")
## 部位受擊框（頭、核心等弱點），依序、前面的優先。每筆 {"id": 部位名, "size": Vector2, "mult": 傷害倍率, "bone": 骨頭名（選填）, "offset": Vector2（選填）}。
## 有骨架且寫了 bone：判定跟著那根骨頭走（蹲下、倒下時一起降低），offset 是相對骨頭的位置（往面向的方向為正 x）；
## 沒有 bone：offset 是相對腳底的固定位置。mult 大於 1 的部位算弱點，打中有回饋、畫面上有標記。
@export var hurt_parts: Array[Dictionary] = []

@export_group("Finisher")
## 生命低於此比例進入「破防」可被終結；0 代表不可終結。
@export_range(0.0, 1.0) var finish_health_ratio: float = 0.34
@export var stagger_duration: float = 1.2
@export_range(0.0, 1.0) var health_drop_chance: float = 0.1
## 被玩家擊敗時掉落的信用點（0 = 不掉）。
@export var credit_value: int = 0

@export_group("Light")
## 自帶的光（NE-259）：光池半徑（像素），0＝這種敵人不帶燈。只給有道理帶燈的（探照、眼睛、面罩燈條）；
## 一般敵人不帶燈，暗的區域裡要靠槍燈或場景燈照出來。
@export_range(0.0, 200.0, 1.0) var light_radius: float = 0.0
## 平常的光色。發現主角時同色變亮，準備攻擊時轉成全遊戲共用的紅色預兆。
@export var light_color: Color = Color(0.6, 0.9, 1.0)
@export_range(0.0, 2.0, 0.05) var light_energy: float = 0.7
## 光跟著哪個零件走（骨架角色填骨頭名，例如 head；零件式生物填零件名）。空的＝用 light_offset 相對於腳底的位置。
@export var light_part: StringName = &""
## 光相對於那個零件的位置（朝右時；面向左邊時 x 會反過來）。
@export var light_offset: Vector2 = Vector2.ZERO
## 發光標記的大小（像素）：一小條亮的畫在光的位置上（眼睛、面罩燈條），讓光看得出是從哪裡來的。(0, 0)＝不畫。
@export var light_mark: Vector2 = Vector2.ZERO
## 哪些狀態算「還沒發現主角」（光維持平常的亮度）。空的＝用 relaxed_states。頭目類的狀態名稱不一樣時填這裡（例如睡著的 dormant）。
@export var light_calm_states: PackedStringArray = []


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
	if light_radius < 0.0 or light_energy < 0.0 or light_mark.x < 0.0 or light_mark.y < 0.0:
		problems.append("%s: 自帶的光的半徑、亮度與發光標記不能是負的" % id)
	if not strike.is_empty():
		problems.append_array(StrikeSpec.validate(self))
	return problems
