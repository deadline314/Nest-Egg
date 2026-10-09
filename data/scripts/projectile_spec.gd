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
## Shape is decorative; radius remains the shared physical head radius.
@export_enum("round", "rifle", "compact", "pellet", "energy", "rail", "grenade", "shell", "organic", "wave") var visual_style: String = "round"
## Maximum decorative trail in world pixels, independent of speed and frame rate.
@export_range(0.0, 40.0) var trail_distance: float = 14.0
@export var radius: float = 3.0
@export var length: float = 8.0
@export var color: Color = Color.WHITE
## 彈道拖尾：記錄最近幾個位置畫成漸細漸淡的尾巴（0＝沒有拖尾，上限見 Projectile.MAX_TRAIL_POINTS）；trail_width 是粗細倍率（細長的子彈用小一點）。
@export var trail_points: int = 5
@export var trail_width: float = 1.0
## 火箭類：飛行時每隔一小段冒一縷煙。
@export var smoke_trail: bool = false
