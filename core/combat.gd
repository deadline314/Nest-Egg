class_name Combat
extends RefCounted
## 戰鬥共用定義。

enum Team { PLAYER, ENEMY }


## 回傳「會被此陣營攻擊打到」的受擊框碰撞層。
static func hurtbox_mask_against(team: Team) -> int:
	return Layers.ENEMY_HURTBOX if team == Team.PLAYER else Layers.PLAYER_HURTBOX
