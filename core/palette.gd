class_name Palette
extends RefCounted
## 全域配色。暫代美術全部以程式繪製，調整風格只需改這裡。

const CYAN := Color("35e0ff")
const CYAN_DIM := Color("1b7f95")
const SUIT := Color("1c2633")
const ARMOR := Color("d6eef4")
const WHITE := Color("f2f7fa")
const DANGER := Color("ff5a4f")
const WARNING := Color("ffc94a")
## 賽博龐克三原色霓虹：洋紅、青、黃（青色沿用 CYAN）。
const MAGENTA := Color("ff2e88")
const NEON_YELLOW := Color("ffd23f")
const NEON_GREEN := Color("3dffa0")
const NEON_PURPLE := Color("a46bff")
const NEON_COLORS: Array[Color] = [Color("ff2e88"), Color("35e0ff"), Color("ffd23f"), Color("a46bff"), Color("3dffa0")]
## 夜空：高處深藍紫、地平線被城市燈光染成洋紅。
const SKY_TOP := Color("070a18")
const SKY_HORIZON := Color("3a1238")
const CITY_FAR := Color("120e24")
const CITY_MID := Color("181430")
const CITY_NEAR := Color("1d1a36")
const RAIN := Color(0.62, 0.72, 0.95, 0.35)
const WARM_LIGHT := Color("ffb066")
const TERRAIN_FILL := Color("232c37")
const TERRAIN_EDGE := Color("3e4c5d")
const TERRAIN_TOP := Color("7390a6")
const PLATFORM := Color("566a7e")
const BG_FAR := Color("0a0c1a")
const BG_MID := Color("101820")
const BG_NEAR := Color("16202a")
const UI_PANEL := Color(0.04, 0.07, 0.1, 0.9)
const UI_TEXT := Color("e8f4f8")
const UI_MUTED := Color("8aa0ad")
