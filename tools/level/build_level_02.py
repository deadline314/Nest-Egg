#!/usr/bin/env python3
"""第二章「天空的代價」地圖產生器：輸出 data/levels/level_02_map.json。

結構（全程室內、密閉，沒有雨）：
  S1 升降井入口  0..69    橘色警示燈。安全示範：貨箱、油桶、玻璃牆、升降梯
  S2 升降井      70..139  升到抬高的平台，閘門與開關、切割者、上層維修走道（文件）
  S3 夾層區      140..214 灰白冷光。迷彩獵手、燈下才看得見、隱藏房間（裂縫牆）
  S3b 中庭       215..262 兩層陽台的挑高空間。攀牆者、蝙蝠機、光橋（只有燈照到才看得見的路）、隱藏房間（裂縫牆）
  S3c 回收燈幕   263..324 追逐橋段：燈幕從身後推進，連續的矮牆與坑洞，前後各一個檢查點
  S4 電力室      325..384 青綠。電力開關、雷射柵欄、砲台、維修機、纏絲、隱藏房間（開關閘門）
  S4b 看守長     385..414 迷你頭目的場地：兩根掩體柱與兩層平台；擊敗後解開 414 欄的閘門
  S5 轉運站      415..439 慘白。補給點、航的語音
  S5b 病房區     440..469 一排病房：床位平台、護理師、吊軌砲
  S5c 頭目戰     470..509 頭目戰（回收員，鋪滿電軌的場地）
  （偏移：原電力室 +110、原轉運站前半 +140、原轉運站後半 +170；改版面時先看這裡）
用法：python3 tools/level/build_level_02.py（會檢查跳躍高度、坑洞寬度與升降梯銜接）
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from level_kit import Grid, PLAYER_JUMP_TILES, TILE  # noqa: E402

W, H = 510, 24
GROUND = 20            # 地面的列（上緣 y = 320）
PLATEAU = 14           # S2 抬高平台的列（上緣 y = 224，比地面高 6 格，要靠升降梯）

grid = Grid(W, H)
put, fill, empty = grid.put, grid.fill, grid.empty

# ---------------------------------------------------------------------------
# 外框、地面與天花板（整關密閉）
fill(0, 0, 0, H - 1, '#')
fill(W - 1, W - 1, 0, H - 1, '#')
fill(1, W - 2, GROUND, H - 1, '#')
fill(1, W - 2, 0, 3, '#')

# ---------------------------------------------------------------------------
# S1 升降井入口（0..69）：沒有敵人的安全示範，再來一場小戰鬥，最後搭升降梯上去
put(3, 19, 'P')
put(5, 19, '1')                            # 升降井提示
put(8, 19, '&')                            # c2_radio_start
put(14, 19, 'a')                           # 貨箱（安全示範）
put(18, 19, 'a')
put(22, 19, '&')                           # c2_radio_barrel
put(26, 19, 'o')                           # 單獨的油桶（安全示範）
# 玻璃牆後的小隔間：打破玻璃拿補給（高 5 格，玩家跳得上去）
fill(30, 37, 15, 15, '#')
fill(37, 37, 15, 19, '#')
put(30, 19, 'w')
put(33, 19, 'c')
put(35, 19, 'i')
put(42, 19, '2')                           # 油桶＋敵人的提示
put(44, 19, 'E')
put(46, 19, 'o')                           # 夾在兩個敵人之間的油桶
put(49, 19, 'E')
put(52, 19, 'U')                           # 衝鋒槍
put(54, 19, 'H')
put(56, 19, 'C')
put(59, 19, 'c')
# 升降梯：抬高 4 格後跳上 6 格高的平台
put(62, 19, 'u')
fill(66, 139, PLATEAU, GROUND - 1, '#')    # S2 的抬高平台（也是 S1 尾端的「牆」）

# ---------------------------------------------------------------------------
# S2 升降井（70..139）：平台上
FEET = PLATEAU - 1
put(72, FEET, 'C')
put(74, FEET, '&')                         # c2_radio_k1
put(78, FEET, 'c')
put(80, FEET, 'A')                         # 維修員老陳（場景人物，給護盾電池）
# 閘門與開關並排（安全示範）：隧道天花板壓低到 4 格，閘門不打開就過不去
fill(88, 92, 4, PLATEAU - 5, '#')
put(84, FEET, 'y')
put(90, FEET, 'h')
put(96, FEET, 'a')
put(102, FEET, 'k')
put(106, FEET, 'o')
put(110, FEET, 'k')
put(113, FEET, 'R')                        # 突擊步槍
put(116, FEET, 'H')
# Removed the overlapping surveillance bee; one bat replaces the former pack below.
put(121, FEET, 'E')
put(126, FEET, '&')                        # c2_memory
put(128, FEET, 'i')
# 上層維修走道：搭升降梯（抬高 6 格）上去，單向平台；盡頭有文件與看守的砲台
put(131, FEET, 'f')
fill(133, 149, 8, 8, '=')
put(136, 7, '&')                           # c2_reclaimer_glass
put(138, 7, 'D')                           # 升降井維護備忘（收集品）
put(141, 7, 'c')
put(143, 7, 'c')
put(147, 5, '>')

# ---------------------------------------------------------------------------
# S3 夾層區（140..214）：回到地面
put(141, 19, 'C')
put(142, 19, '&')                          # c2_radio_cloak
put(144, 19, 'G')                          # 夾層區住戶（場景人物，給醫療針）
put(145, 19, 'z')                          # 補給點
put(148, 19, 'Q')                          # 霰彈槍
put(150, 19, '3')                          # 迷彩獵手提示
put(152, 19, '&')                          # c2_radio_wall
put(155, 19, 's')
put(160, 19, 'E')
fill(163, 169, 16, 16, '=')
put(166, 15, 'W')                          # 航的語音留言（收集品，陽台上）
put(168, 19, '&')                          # c2_radio_corridor
put(172, 19, 's')
put(178, 19, 'E')
put(182, 19, 'H')
put(186, 19, 's')
# 隱藏房間 A：裂縫牆（打破才進得去），裡面有文件、大筆信用點與補給
fill(190, 199, 15, 19, '#')
fill(190, 198, 16, 19, '.')
put(190, 19, 'x')                          # 裂縫牆佔 1×4 格（列 16..19），要先清掉牆格
put(194, 19, 'N')
put(196, 19, 'q')
put(197, 19, 'i')
put(202, 19, 'E')
put(205, 19, 's')
put(209, 19, 'e')
put(211, 19, 'c')
for x, y, c in [(150, 9, '@'), (167, 8, '%'), (176, 10, '$'), (195, 9, '%'), (206, 9, '$')]:
    put(x, y, c)

# ---------------------------------------------------------------------------
# S3b 中庭（215..262）：兩層陽台的挑高空間
put(216, 19, 'C')
put(218, 19, 'z')                          # 補給點
put(222, 19, 'c')
put(224, 4, 'S')                           # 攀牆者（掛在天花板上，第一次遭遇左邊有 12 格安全空間）
put(236, 7, '+')                           # 井道蝙蝠機（中庭上空盤旋）
put(246, 4, 'S')                           # 攀牆者
# 二層陽台（單向平台）：從地面跳上去，一路往右
fill(222, 230, 16, 16, '=')
fill(233, 241, 13, 13, '=')
fill(244, 250, 16, 16, '=')
put(226, 15, 'q')
put(237, 12, 'i')
put(247, 15, 'e')
put(231, 19, '4')                          # 光橋提示看板
# 光橋：從第二層陽台右端往上的樓梯，只有燈照到的部分才看得見；盡頭是平台上的補給
fill(243, 245, 10, 10, '~')
fill(248, 250, 8, 8, '~')
fill(253, 255, 6, 6, '~')
fill(257, 261, 6, 6, '=')
put(258, 5, 'q')
put(260, 5, 'e')
# 隱藏房間 C：裂縫牆（打破才進得去），裡面有補給與信用點
fill(253, 262, 15, 19, '#')
fill(253, 261, 16, 19, '.')
put(253, 19, 'x')                          # 裂縫牆佔 1×4 格（列 16..19）
put(257, 19, 'q')
put(259, 19, 'i')
put(260, 19, 'e')
put(261, 19, 'c')
for x, y, c in [(228, 8, '$'), (240, 7, '%'), (250, 9, '@')]:
    put(x, y, c)

# ---------------------------------------------------------------------------
# S3c 回收燈幕（263..324）：追逐橋段，不能停
put(264, 19, 'C')                          # 橋段前的檢查點
put(267, 19, '&')                          # cut_c9_alarm（警報）
put(269, 19, '&')                          # c2_curtain（無線電）
put(272, 19, 'X')                          # 燈幕起點：走過這裡燈幕從身後出發
for x in (278, 294, 308):                  # 矮牆（2 格高，跳過去）
    fill(x, x + 1, 18, 19, '#')
for x in (284, 300, 316):                  # 坑洞（3 格寬，跳過去）
    fill(x, x + 2, GROUND, H - 1, '.')
fill(288, 291, 16, 16, '=')                # 兩處低平台，可以選擇不跳牆改走平台
fill(320, 322, 16, 16, '=')
put(324, 19, 'C')                          # 橋段後的檢查點

# ---------------------------------------------------------------------------
# S4 電力室（原 215..274，現在 +110 → 325..384）
D4 = 110                                    # 橋段後的檢查點在 324，所以電力室入口不再放
put(217 + D4, 19, '&')                     # c2_radio_power
put(222 + D4, 19, 'p')                     # 電力開關（安全示範：雷射柵欄就在前面）
put(225 + D4, 19, 'J')                     # 電力室值班記錄（收集品）
fill(228 + D4, 228 + D4, 13, 19, '|')
fill(234 + D4, 234 + D4, 13, 19, '|')
put(238 + D4, 19, 'c')
put(266 + D4, 5, '>')
put(246 + D4, 19, '&')                     # c2_radio_medic
put(247 + D4, 19, 'o')
put(249 + D4, 19, 'E')
put(250 + D4, 14, 'M')
put(252 + D4, 19, 'E')
put(272 + D4, 4, 'S')
put(258 + D4, 19, 'l')                     # 隱藏房間 B 的開關
# 隱藏房間 B：開關閘門（藍色）
fill(262 + D4, 270 + D4, 15, 19, '#')
fill(262 + D4, 269 + D4, 16, 19, '.')
put(262 + D4, 19, 'j')                     # 閘門佔 1×4 格（列 16..19）
put(266 + D4, 19, 'K')                     # NEST 實驗日誌（收集品）
put(268 + D4, 19, 'e')
put(271 + D4, 19, '&')                     # c2_radio_k2
put(273 + D4, 19, 'C')
# 纏絲：掛在一根橫樑下，伸出時掃過下面的走道（離電力開關的安全示範與雷射柵欄都超過 9 格）
fill(354, 359, 4, 14, '#')                 # 從天花板垂下的一塊（和天花板相連，不當成地面）
put(357, 15, '<')

# ---------------------------------------------------------------------------
# S4b 看守長（385..414）：迷你頭目的場地
put(386, 19, 'C')
put(387, 19, 'z')
put(389, 19, '&')                          # c2_radio_captain
put(391, 19, 'H')
fill(396, 397, 17, 19, '#')                # 兩根掩體柱（3 格高）
fill(402, 403, 17, 19, '#')
fill(392, 399, 14, 14, '=')                # 兩層平台：跳起來躲震波
fill(404, 411, 14, 14, '=')
put(408, 19, 'b')                          # 看守長
fill(414, 414, 4, 15, '#')                 # 出口的閘門（擊敗看守長才打開）
put(414, 19, 'm')

# ---------------------------------------------------------------------------
# S5 轉運站（原 275..299 → +140 = 415..439；病房區 440..469；原 300..339 → +170 = 470..509）
D5 = 140
put(276 + D5, 19, 'H')
put(279 + D5, 19, 'z')
put(283 + D5, 19, 'V')                     # 航的語音留言（收集品）
put(288 + D5, 19, 'i')
put(290 + D5, 19, 'e')
put(292 + D5, 19, 'F')                     # 雷射
put(296 + D5, 19, '&')                     # c2_radio_last
put(298 + D5, 19, 'L')                     # 牆上的刻痕（可調查物）
# 病房區：四道從天花板垂下的隔間牆把走道分成五間病房，每間一張床位平台
D6 = 170
for wall_x in (446, 452, 458, 464):
    fill(wall_x, wall_x, 4, 13, '#')
for bed_x in (442, 448, 454, 460, 466):
    fill(bed_x, bed_x + 2, 18, 18, '=')
put(443, 19, 'I')                          # 轉運站護理師（場景人物，給十二號床交接單）
put(449, 17, 'c')
put(455, 17, 'c')
put(461, 17, 'i')
put(467, 17, 'e')
put(457, 5, '>')                           # 吊軌砲（天花板軌道，中間兩間病房）
put(300 + D6, 19, 'B')
fill(306 + D6, 311 + D6, 16, 16, '=')
fill(312 + D6, 317 + D6, 13, 13, '=')
fill(318 + D6, 323 + D6, 16, 16, '=')
put(332 + D6, 19, 'Y')                     # 回收員

# 第二批敵人（NE-46：n 探照無人機、Z 狙擊手）：只放在空位，不動既有的敵人與檢查點
put(166, 11, 'n')                          # 探照無人機（夾層區，光池會照出迷彩獵手）
put(196, 14, 'Z')                          # 狙擊手（站在隱藏房間的屋頂上）

# 第二批敵人（NE-47：O 火焰兵、v 重裝機槍手）：只放在空位，不動既有的敵人與檢查點
put(100, FEET, 'O')                        # 火焰兵（升降井平台，離閘門與開關的安全示範超過 9 格）
put(212, 19, 'v')                          # 重裝機槍手（夾層區後段，離電力開關的安全示範超過 9 格）
put(236 + D4, 19, 'O')                     # 火焰兵（電力室，兩道雷射柵欄之後）
put(261 + D4, 19, 'v')                     # 重裝機槍手（電力室尾，隱藏房間閘門旁）

# NE-97：偽裝箱與電擊犬只屬第一章 Demo，空缺使用已交付的塔內生物。
# 一群電擊犬改成一隻蝙蝠機，避免直接換成三隻耐打的新敵人造成難度尖峰。
put(108, 4, 'S')                          # 攀牆者，掛在升降井天花板
put(118, 7, '+')                          # 井道蝙蝠機，取代監視蜂與原電擊犬群
put(426, 7, '+')                          # 轉運站原電擊犬群
put(417, 4, 'S')                          # 轉運站原偽裝箱

# 第二章新生物（NE-99）：升降井上空的蝙蝠機；其餘見中庭、電力室、病房區（機關的安全示範 9 格內不放敵人）
put(72, 7, '+')                            # 井道蝙蝠機（升降井上空；左邊 5 格內沒有別種敵人，離機關示範超過 9 格）

# ---------------------------------------------------------------------------
# 場景燈：依區段疏密（電力室最暗）
for x0, x1, step in [(8, 69, 12), (70, 139, 14), (140, 214, 9), (215, 262, 10), (263, 324, 8), (325, 384, 18), (385, 414, 12), (415, 439, 10), (440, 469, 11), (470, 508, 10)]:
    for x in range(x0, x1, step):
        if empty(x, 4):
            put(x, 4, '*')

# ---------------------------------------------------------------------------
# 檢查
problems = grid.check_route(allow_step_columns=[(64, 67)])
# 升降梯銜接：S1 升降梯（抬高 4 格）的頂面與平台頂面的差距不超過跳躍高度，水平空隙不超過 3 格
lift_top = GROUND - 4
if lift_top - PLATEAU > PLAYER_JUMP_TILES - 1:
    problems.append(f"S1 升降梯頂面（列 {lift_top}）與平台（列 {PLATEAU}）差 {lift_top - PLATEAU} 格，跳不上去")
if 66 - (62 + 2) > 3:
    problems.append("S1 升降梯到平台的水平空隙超過 3 格")
# 上層維修走道：升降梯抬高 6 格，頂面要和走道同高
catwalk_top = PLATEAU - 6
if catwalk_top != 8:
    problems.append(f"維修走道在列 8，升降梯頂面在列 {catwalk_top}，必須同高")
# 每個檢查點都要站得穩：腳下一格必須是實心。
for y in range(H):
    for x in range(W):
        if grid.at(x, y) == 'C' and grid.at(x, y + 1) != '#':
            problems.append(f"檢查點 ({x},{y}) 腳下不是實心")
# 追逐橋段：起點與終點之間不能有玩家跳不過的東西，終點（起點 + 50 格）前後都要有檢查點。
CHASE_START, CHASE_LENGTH = 272, 50
if grid.at(CHASE_START, 19) != 'X':
    problems.append("追逐橋段的起點 X 不在 (272, 19)")
if not any(grid.at(x, 19) == 'C' for x in range(CHASE_START - 12, CHASE_START)):
    problems.append("追逐橋段起點前 12 格內沒有檢查點")
if not any(grid.at(x, 19) == 'C' for x in range(CHASE_START + CHASE_LENGTH - 4, CHASE_START + CHASE_LENGTH + 8)):
    problems.append("追逐橋段終點附近沒有檢查點")
for x in range(CHASE_START, CHASE_START + CHASE_LENGTH):
    wall_height = sum(1 for y in range(4, GROUND) if grid.at(x, y) == '#')
    if wall_height > PLAYER_JUMP_TILES - 2:
        problems.append(f"追逐橋段第 {x} 欄的障礙有 {wall_height} 格高，跑著跳不過")
# ---------------------------------------------------------------------------
# 場景美術（NE-55）：材質覆蓋區與道具。道具只是裝飾，不改變地形與實體；擺放時自動避開有實體（敵人、道具、機關）的格子。
import math
import re

PROP_DIR = os.path.join(os.path.dirname(__file__), '..', '..', 'data', 'environment', 'props')


def prop_size(prop_id):
    text = open(os.path.join(PROP_DIR, prop_id + '.tres'), encoding='utf-8').read()
    m = re.search(r'^size = Vector2\(([\d.]+), ([\d.]+)\)', text, re.M)
    return float(m.group(1)), float(m.group(2))


FREE_CHARS = set('.*$%@cqieHDFJKNQRUVW')   # 道具可以蓋在上面的格子：空氣、場景燈、裝飾招牌、拾取物（敵人、人物、機關、可破壞物不行）
props = []


ENEMY_CHARS = set('ksMETvOZnS+<>bY')   # 敵人佔的範圍比一格寬，道具和敵人左右各留一格


def cells_free(x0, x1, y0, y1):
    if not all(grid.at(x, y) in FREE_CHARS for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)):
        return False
    return not any(grid.at(x, y) in ENEMY_CHARS for x in range(max(1, x0 - 1), min(W - 2, x1 + 1) + 1) for y in range(y0, min(H - 1, y1 + 2) + 1))


def place(prop_id, x, mode='floor', y=None, flip=False, dx=0, search=16):
    """mode：floor 站在地面（底邊在列 y，預設 19）；ceil 掛在天花板下（頂邊在列 4）；mid 底邊在列 y。
    從 x 起向右找第一個不蓋到實體的位置（最多找 search 格）；找不到就報錯，由設計者改位置。"""
    w, h = prop_size(prop_id)
    cols = int(math.ceil(w / TILE_PX))
    rows = int(math.ceil(h / TILE_PX))
    if mode == 'ceil':
        bottom = 3 + rows
    elif mode == 'mid':
        bottom = y
    else:
        bottom = 19 if y is None else y
    top = bottom - rows + 1
    for shift in range(search + 1):
        xs = x + shift
        decal = h <= 8.0  # 貼地的標線、積水不算佔格
        if xs + cols - 1 < W - 1 and (decal or cells_free(xs, xs + cols - 1, top, bottom)) and (mode != 'floor' or all(grid.at(c, bottom + 1) in '#=' for c in range(xs, xs + cols))):
            entry = {"id": prop_id, "x": xs, "y": bottom}
            if flip:
                entry["flip"] = True
            if dx:
                entry["dx"] = dx
            props.append(entry)
            return
    problems.append(f"道具 {prop_id}（第 {x} 欄起 {search} 格內）找不到不蓋到實體的位置")


TILE_PX = 16
regions = [
    {"x0": 1, "x1": 139, "y0": 0, "y1": 3, "material": "steel_plate"},
    {"x0": 66, "x1": 139, "y0": 14, "y1": 19, "material": "old_metal"},
    {"x0": 140, "x1": 262, "y0": 0, "y1": 3, "material": "concrete"},
    {"x0": 263, "x1": 324, "y0": 0, "y1": 3, "material": "hangar"},
    {"x0": 325, "x1": 384, "y0": 0, "y1": 3, "material": "facility_panel"},
    {"x0": 385, "x1": 414, "y0": 0, "y1": 3, "material": "hangar"},
    {"x0": 415, "x1": 469, "y0": 0, "y1": 3, "material": "facility_panel"},
    {"x0": 470, "x1": W - 2, "y0": 0, "y1": 3, "material": "steel_plate"},
]

# S1 升降井入口：升降梯井口、管線、警示牌、應急燈
place("elevator_door", 10); place("hazard_sign", 20); place("crates_stack", 38); place("floor_marking", 48)
place("pipe_vertical", 56); place("floor_marking", 16)
for x in (12, 38, 58):
    place("facility_pipes", x, 'ceil')
for x in (24, 46, 64):
    place("emergency_light", x, 'ceil')
place("camera_wall", 44, 'mid', 6); place("cables_hang", 30, 'ceil')
# S2 升降井：抬高的平台（腳下列 13）；上層維修走道（腳下列 7）
place("pipe_vertical", 74, 'mid', 13); place("hazard_sign", 98, 'mid', 13)
place("barrels", 123, 'mid', 13); place("crates_stack", 104, 'mid', 13); place("floor_marking", 112, 'mid', 13)
place("elevator_door", 128, 'mid', 13)
for x in (78, 104, 122):
    place("emergency_light", x, 'ceil')
place("facility_pipes", 82, 'ceil'); place("facility_pipes", 112, 'ceil'); place("cables_hang", 96, 'ceil')
place("server_rack", 134, 'mid', 7); place("pipe_horizontal", 140, 'mid', 7); place("camera_wall", 138, 'mid', 4)
# S3 夾層區：住戶的街道——販賣機、冷氣、長椅、暖光燈、塗鴉、招牌
place("vending_machine", 147); place("lamp_warm", 152); place("bench", 156); place("graffiti", 164)
place("ac_unit", 174, 'mid', 12); place("trash_can", 170); place("dumpster", 180); place("crayon_drawing", 185, 'mid', 17)
place("billboard_ad", 192, 'mid', 12); place("lamp_warm", 200); place("ac_unit_big", 204, 'mid', 12)
place("vending_machine", 208); place("window_rain", 176, 'mid', 14)
for x in (150, 178, 206):
    place("emergency_light", x, 'ceil')
# S3b 中庭：樹、長椅、暖光燈、陽台上的小東西
place("tree_fir_1", 219); place("tree_jacaranda", 232); place("tree_stump", 238); place("bench", 240);
place("lamp_warm", 226, 'mid', 15); place("bench", 234, 'mid', 12); place("lamp_warm", 245, 'mid', 15); place("vending_machine", 251)
place("window_rain", 224, 'mid', 12); place("ac_unit", 250, 'mid', 12)
for x in (222, 236, 250):
    place("emergency_light", x, 'ceil')
# S3c 回收燈幕：警示、地面標線、應急燈與攝影機
for x in (266, 283, 300, 312):
    place("hazard_sign", x)
for x in (275, 292, 306):
    place("floor_marking", x)
for x in (270, 282, 298, 314):
    place("emergency_light", x, 'ceil')
place("camera_wall", 276, 'mid', 6); place("camera_wall", 304, 'mid', 6, flip=True); place("facility_pipes", 288, 'ceil'); place("cables_hang", 318, 'ceil')
# S4 電力室：機櫃、控制台、管線、電纜、攝影機
place("server_rack", 332); place("control_console", 340); place("server_rack", 342); place("hazard_sign", 346)
place("server_rack", 366); place("control_console", 376); place("floor_marking", 356); place("floor_marking", 372)
place("gate_door", 380, dx=0)
for x in (330, 345, 362, 378):
    place("facility_pipes", x, 'ceil')
for x in (336, 352, 368):
    place("emergency_light", x, 'ceil')
place("camera_wall", 340, 'mid', 6); place("camera_wall", 372, 'mid', 6, flip=True); place("cables_hang", 350, 'ceil'); place("cables_hang", 374, 'ceil')
# S4b 看守長場地：機庫燈、龍門吊、油槽、標線
for x in (392, 400, 408):
    place("hangar_light", x, 'ceil')
place("gantry_crane", 396, 'mid', 9); place("fuel_tank", 388); place("fuel_tank", 411); place("floor_marking", 392); place("floor_marking", 404); place("hazard_sign", 390)
# S5 轉運站：電梯門、販賣機、長椅、全像終端
place("elevator_door", 418); place("terminal_holo", 421); place("vending_machine", 430); place("lamp_warm", 437)
place("emergency_light", 418, 'ceil'); place("emergency_light", 432, 'ceil'); place("facility_pipes", 424, 'ceil')
# S5b 病房區：每張床位平台（腳下列 17）一張病床，牆上蠟筆畫與無線電，天花板軌道旁的燈
for bed_x in (442, 448, 454, 460, 466):
    place("hospital_bed", bed_x, 'mid', 17, search=2)
place("crayon_drawing", 444, 'mid', 14); place("crayon_drawing", 456, 'mid', 14); place("radio_set", 450, 'mid', 14)
place("lamp_warm", 462, 'mid', 14); place("window_rain", 468, 'mid', 14)
for x in (444, 450, 456, 462, 468):
    place("emergency_light", x, 'ceil')
# S5c 頭目戰：機庫（沿用第一章頭目場地的道具）
place("gantry_crane", 486, 'mid', 8); place("fuel_tank", 480); place("fuel_tank", 505)
for x in (478, 490, 502):
    place("hangar_light", x, 'ceil')
place("floor_marking", 484); place("floor_marking", 498); place("hazard_sign", 494)

if problems:
    raise SystemExit("\n".join(problems))

grid.write("level_02", (os.path.dirname(__file__), '..', '..', 'data', 'levels', 'level_02_map.json'),
           {"regions": regions, "props": props})
