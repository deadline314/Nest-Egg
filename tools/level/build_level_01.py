#!/usr/bin/env python3
"""第一章「雨夜」地圖產生器：以程式擺放地形與實體，輸出 data/levels/level_01_map.json。

地圖檔本身是可直接手改的資料；這個腳本是「設計稿」，方便大幅調整版面後重新產生，
並在輸出前檢查跳躍高度與坑洞寬度是否在角色能力範圍內。
用法：python3 tools/level/build_level_01.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from level_kit import Grid, PLAYER_JUMP_TILES, MECH_JUMP_TILES  # noqa: E402,F401

W, H = 350, 24
GROUND = 20            # 街道地面的列（上緣 y = 320）
TILE = 16
PLAYER_JUMP_TILES = 5  # 玩家跳躍約 88px ≈ 5.5 格
MECH_JUMP_TILES = 3    # 機甲跳躍約 54px ≈ 3.4 格

grid = Grid(W, H)
g = grid.g
put, fill, empty = grid.put, grid.fill, grid.empty


# ---------------------------------------------------------------------------
# 外框與地面
fill(0, 0, 0, H - 1, '#')
fill(W - 1, W - 1, 0, H - 1, '#')
fill(1, W - 2, GROUND, H - 1, '#')

# ---------------------------------------------------------------------------
# S1 屋頂巷弄（0..69）：從屋頂出發，跨越巷道，再一路往下到街道；衝鋒槍
fill(1, 27, 15, GROUND - 1, '#')          # 屋頂 A（上緣 y=240）
fill(9, 10, 13, 14, '#')                  # 冷氣機
fill(29, 30, 18, GROUND - 1, '#')         # 巷子裡的木箱（掉下去時的踏腳）
fill(32, 52, 15, GROUND - 1, '#')         # 屋頂 B（上緣 y=240）
fill(37, 38, 13, 14, '#')                 # 掩體
# 隱藏房間：屋頂 B 的牆面內側挖出一間小室，入口是巷子裡看得到的裂縫牆（打破才進得去）。
fill(32, 38, 16, GROUND - 1, '.')
put(32, 19, 'x')                          # 裂縫牆（1×4 格，往上長）
put(36, 19, 'v')                          # 老K的語音留言（收集品）
put(37, 19, 'i')                          # 醫療針
put(24, 14, 'f')                          # 天穹宣傳單（收集品）
fill(53, 57, 17, 17, '=')                 # 往下的雨棚
fill(59, 63, 18, 18, '=')
put(3, 14, 'P')
put(5, 14, '1')
put(6, 14, '&')                           # radio_start
put(13, 14, '2')
put(20, 14, '&')                          # radio_roof
put(22, 14, 'g')
put(34, 14, '3')
put(44, 14, 'g')
put(42, 14, 'U')                          # 衝鋒槍
put(50, 14, 'i')                          # 醫療針
put(48, 14, 'H')
put(56, 19, '4')
put(62, 19, 'C')
put(66, 19, '~')
for x, y, c in [(29, 16, '$'), (24, 9, '@'), (47, 8, '%'), (60, 12, '$'), (66, 13, '%')]:
    put(x, y, c)

# ---------------------------------------------------------------------------
# S2 霓虹市集（70..159）：雨棚上的保全、頭頂的監視蜂、霰彈槍、鎮暴員
for x0 in (74, 88, 104, 126, 142):
    fill(x0, x0 + 6, 16, 16, '=')
put(91, 15, 'g')                          # （原本在 78：把麵攤前後留成沒有敵人的安全區）
put(72, 19, 'A')                          # 麵攤阿婆（場景人物，說完給蠟筆畫與零錢）
put(84, 19, '&')                          # radio_market
put(90, 19, '&')                          # radio_market_mei
put(92, 19, 'g')
put(96, 19, '5')
put(98, 8, 'd')
put(102, 19, '6')
put(112, 19, 'S')
put(116, 7, 'd')
put(118, 19, '7')
put(119, 19, '&')                         # radio_shield
put(124, 19, 'r')
put(130, 15, 'g')
put(135, 19, 'H')
put(137, 19, '&')                         # radio_forecast
put(128, 19, 'e')                         # 護盾電池
put(140, 19, 'C')
put(146, 15, 'g')
put(152, 19, 'g')
for x in (86, 120, 145):
    put(x, 19, '~')
for x, y, c in [(72, 11, '$'), (80, 12, '%'), (84, 4, '@'), (95, 11, '$'), (101, 13, '%'), (108, 11, '$'),
                (118, 4, '@'), (122, 12, '$'), (133, 11, '%'), (139, 12, '$'), (150, 4, '@'), (156, 11, '$')]:
    put(x, y, c)

# ---------------------------------------------------------------------------
# S3 貨運站（160..239）：突擊步槍、機甲、貨櫃上的砲台、自爆蟲群、擲彈兵、榴彈發射器
put(162, 19, 'C')
put(164, 19, 'W')                         # 夜班工人（場景人物，給交班紙條與醫療針）
put(165, 19, '&')                         # radio_mech
put(166, 19, 'R')                          # 突擊步槍（上機甲前）
put(168, 19, 'M')
put(171, 19, '8')
fill(178, 183, 17, 19, '#')               # 貨櫃（3 格高）
put(180, 16, 't')
put(182, 16, 'y')                         # 貨運清單（收集品，貨櫃頂）
fill(186, 188, GROUND, H - 1, '.')        # 排水溝（坑）
put(192, 19, 'g')
fill(200, 205, 18, 19, '#')               # 貨櫃（2 格高）
put(202, 17, 't')
put(210, 19, 'g')
put(214, 19, 'r')
fill(218, 223, 17, 19, '#')               # 貨櫃（3 格高）
put(220, 16, 'm')
put(226, 19, '9')
for x in (229, 231, 233):
    put(x, 19, 'b')
put(236, 19, 'H')
put(238, 19, 'G')                          # 榴彈發射器
put(196, 19, 'i')                         # 醫療針
for x, y, c in [(166, 11, '%'), (174, 6, '@'), (196, 12, '$'), (208, 10, '%'), (228, 11, '$')]:
    put(x, y, c)
for x in (176, 207):
    put(x, 19, '~')

# ---------------------------------------------------------------------------
# S4 天穹設施入口（240..309，室內）：雷射柵欄、尖刺、迫擊兵、貫穿光束、電磁軌道砲
fill(240, W - 2, 0, 3, '#')               # 天花板（室內不下雨）
put(242, 19, 'C')
put(245, 19, '&')                         # radio_facility
fill(252, 252, 13, 19, '|')
fill(257, 262, 16, 16, '=')
fill(264, 270, 16, 16, '=')
fill(258, 268, 19, 19, '^')
put(272, 19, 't')
put(274, 19, '&')                         # radio_arm
fill(276, 276, 13, 19, '|')
put(280, 19, 'g')
put(282, 19, 'e')                         # 護盾電池
fill(284, 286, 17, 17, '=')               # 上高台的踏板
fill(288, 293, 15, 19, '#')               # 高台
put(290, 14, 'm')
put(296, 19, 'L')
put(300, 19, 'g')
put(302, 19, 'H')
put(304, 19, 'C')
put(306, 19, '&')                         # radio_last
put(308, 19, 'V')                          # 電磁軌道砲（頭目戰前）
put(309, 19, 'i')                         # 醫療針
for x in (250, 262, 270, 282, 290, 300, 322, 332, 340):
    put(x, 4, '*')

# ---------------------------------------------------------------------------
# S5 頭目機庫（310..349）
put(310, 19, 'B')
fill(316, 321, 15, 15, '=')
fill(338, 343, 15, 15, '=')
fill(326, 333, 11, 11, '=')
put(342, 19, 'X')

# 信用點：小堆散在路上（c），隱藏房間裡有一大堆（q）
for x, y in [(17, 14), (47, 14), (100, 19), (114, 19), (138, 19), (175, 19), (195, 19), (212, 19), (225, 19), (274, 19), (298, 19)]:
    if empty(x, y):
        put(x, y, 'c')
put(35, 19, 'q')
# 補給點（z）：兩個檢查點旁各一個
put(142, 19, 'z')
put(243, 19, 'z')

# 第二批敵人（NE-46：n 探照無人機、Z 狙擊手）：只放在空位，不動既有的敵人與檢查點
put(185, 12, 'n')                        # 探照無人機（貨運站中段，教玩家認光束與警報）
fill(188, 192, 15, 15, '=')               # 狙擊手的高台（單向平台，下方照常通行）
put(190, 14, 'Z')                         # 狙擊手（貨櫃可以擋雷射）

# 第二批敵人（NE-48：T 電擊犬、[ 偽裝箱）
for x in (175, 176, 177):
    put(x, 19, 'T')                       # 電擊犬一群（貨運站入口，旁邊的貨櫃頂可以躲）
put(199, 19, '[')                         # 偽裝箱（醫療針旁邊，貨櫃腳下）

# 室外路燈
for x in (12, 28, 40, 62, 76, 96, 110, 130, 150, 172, 190, 210, 230):
    if empty(x, 9):
        put(x, 9, '*')


# ---------------------------------------------------------------------------
# 檢查：沿路面（實心地形；單向平台是選擇性路線不列入）的高度變化不能超過跳躍能力、坑不能太寬
problems = grid.check_route()
if problems:
    raise SystemExit("\n".join(problems))

# ---------------------------------------------------------------------------
# 場景美術：材質覆蓋區（貨櫃、天花板）與道具。道具只是裝飾，不改變地形與實體的位置。
# 道具座標：x 是左邊的欄；ground 為真時站在該處地表；否則 y 是底邊所在的列。
regions = [
    # 屋頂以下是建築本體：磚牆與混凝土，不是整片屋頂碎石。
    {"x0": 1, "x1": 27, "y0": 16, "y1": 19, "material": "brick"},
    {"x0": 32, "x1": 52, "y0": 16, "y1": 19, "material": "concrete"},
    {"x0": 178, "x1": 183, "y0": 17, "y1": 19, "material": "container_red"},
    {"x0": 200, "x1": 205, "y0": 18, "y1": 19, "material": "container_blue"},
    {"x0": 218, "x1": 223, "y0": 17, "y1": 19, "material": "container_green"},
    {"x0": 240, "x1": 309, "y0": 0, "y1": 3, "material": "facility_panel"},
    {"x0": 310, "x1": W - 2, "y0": 0, "y1": 3, "material": "steel_plate"},
]


def prop(prop_id, x, ground=True, y=None, flip=False, dx=0, dy=0):
    entry = {"id": prop_id, "x": x}
    if ground:
        entry["ground"] = True
    else:
        entry["y"] = y
    if flip:
        entry["flip"] = True
    if dx:
        entry["dx"] = dx
    if dy:
        entry["dy"] = dy
    return entry


props = [
    # S1 屋頂巷弄：天線、晾衣架、水塔、排氣管、樓梯間；巷子裡的管線與逃生梯；街上的雜物
    prop("antenna", 1), prop("clothesline", 12), prop("satellite_dish", 17), prop("water_tower", 19),
    prop("vent_stack", 24), prop("rooftop_hut", 25), prop("pipe_vertical", 31, False, 19),
    prop("fire_escape", 29, False, 19), prop("vent_stack", 40), prop("ac_unit", 42, dx=4), prop("antenna", 48, flip=True),
    prop("chimney_stack", 45), prop("trash_can", 55), prop("graffiti", 64, False, 18), prop("puddle", 60),
    prop("vending_machine", 67), prop("street_lamp", 52),
    # S2 霓虹市集：燈籠、麵攤、販賣機、路燈、電線桿、積水、候車亭
    prop("lantern_string", 72, False, 10), prop("lantern_string", 120, False, 10), prop("noodle_stall", 70),
    prop("vending_machine", 87), prop("street_lamp", 82), prop("street_lamp", 128), prop("utility_pole", 75, dx=-16),
    prop("utility_pole", 156, dx=-16), prop("puddle", 100), prop("puddle", 118), prop("puddle", 136),
    prop("bus_stop", 134), prop("bench", 121), prop("dumpster", 114), prop("fire_escape", 106, False, 19),
    prop("trash_can", 90), prop("graffiti", 144, False, 18), prop("billboard_ad", 148, False, 12),
    # S3 貨運站：起重機、堆高機、棧板、貨箱、柵欄、休息室
    prop("worker_hut", 163), prop("forklift", 170), prop("pallet_stack", 174), prop("crane_arm", 189),
    prop("crates_stack", 190), prop("fence", 196), prop("fence", 212), prop("crane_arm", 224), prop("barrels", 227),
    prop("puddle", 207), prop("puddle", 200), prop("puddle", 225), prop("hazard_sign", 176, False, 14),
    prop("pipe_horizontal", 206, False, 12),
    # S4 設施入口與停電走廊
    prop("facility_pipes", 246, False, 4), prop("facility_pipes", 290, False, 4), prop("camera_wall", 250, False, 5),
    prop("camera_wall", 280, False, 5), prop("camera_wall", 300, False, 5, flip=True), prop("control_console", 248),
    prop("server_rack", 254), prop("gate_door", 296, dx=32), prop("hazard_sign", 254, False, 10),
    prop("hazard_sign", 278, False, 10), prop("floor_marking", 244), prop("floor_marking", 300),
    prop("emergency_light", 264, False, 4), prop("emergency_light", 274, False, 4), prop("emergency_light", 284, False, 4),
    prop("cables_hang", 266, False, 5), prop("cables_hang", 296, False, 5),
    # S5 頭目機庫
    prop("gantry_crane", 316, False, 8), prop("hangar_light", 318, False, 4), prop("hangar_light", 330, False, 4),
    prop("hangar_light", 342, False, 4), prop("fuel_tank", 313), prop("fuel_tank", 345), prop("floor_marking", 322),
    prop("floor_marking", 336), prop("hazard_sign", 326, False, 14),
    # 植物（NE-64）：屋頂花園與街角的樹，前景的樹半透明、不擋敵人與子彈
    prop("tree_island", 7), prop("tree_pine_front", 27), prop("tree_quiver", 36), prop("tree_pine_1", 50),
    prop("tree_jacaranda", 96), prop("tree_fir_1", 142), prop("tree_fir_front", 157),
    prop("tree_stump", 205), prop("tree_branch", 217), prop("tree_pine_2", 233),
]

grid.write("level_01", (os.path.dirname(__file__), '..', '..', 'data', 'levels', 'level_01_map.json'),
           {"regions": regions, "props": props})
