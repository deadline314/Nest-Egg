class_name Layers
extends RefCounted
## 物理碰撞層定義（須與 project.godot 的 [layer_names] 對應）。
## 統一在此管理，避免各處寫死魔術數字。

const WORLD := 1 << 0
const PLATFORM := 1 << 1
const PLAYER := 1 << 2
const ENEMY := 1 << 3
const PLAYER_HURTBOX := 1 << 4
const ENEMY_HURTBOX := 1 << 5
const PICKUP := 1 << 6
const VEHICLE := 1 << 7
## 只擋子彈、不擋角色的屏障（蒸汽閥噴出的蒸汽牆，NE-398）。子彈的碰撞會加上這一層。
const SCREEN := 1 << 8

## 角色站立用的地形（實心牆 + 單向平台）。
const SOLID := WORLD | PLATFORM
