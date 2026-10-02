class_name ProjectileSpec
extends Resource
## 子彈規格：玩家武器、敵人與頭目共用。
## source_id 會被敗北圖鑑用來判斷死因，請與 data/codex/defeat_cards.json 的 id 對應。

@export var source_id: StringName = &""

@export_group("Motion")
@export var speed: float = 400.0
@export var gravity: float = 0.0
@export var lifetime: float = 1.0

@export_group("Damage")
@export var damage: int = 1
@export var stagger: int = 1
@export var knockback: float = 40.0
## 可貫穿的目標數量（0 = 命中即消失）。
@export var pierce: int = 0
@export var passes_walls: bool = false
@export var explosion_radius: float = 0.0
@export var explosion_damage: int = 0
@export var explode_on_expire: bool = false

@export_group("Visual")
@export var radius: float = 3.0
@export var length: float = 8.0
@export var color: Color = Color.WHITE
