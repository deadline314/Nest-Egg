#!/usr/bin/env python3
"""第一章「傘」的區域地圖產生器（ST-6）：輸出 data/levels/ch1_*.tres、ch1_*_map.json、環境主題、機關與音樂對應。

設計見 design/13-story-v2/CH01_LEVEL.md。地圖檔是可直接手改的資料，這個腳本是「設計稿」：
大幅調整版面後重新執行，並在輸出前檢查玩家站得住、出入口與道具落在地面上、主要路徑跳得過去。
用法：python3 tools/level/build_ch1.py
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from level_kit import Grid, PLAYER_JUMP_TILES, HEADROOM  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), '..', '..')
LEVEL_DIR = os.path.join(ROOT, 'data', 'levels')
THEME_DIR = os.path.join(ROOT, 'data', 'environment', 'themes')
PROP_DIR = os.path.join(ROOT, 'data', 'props')
H = 24
TILE = 16

# ---------------------------------------------------------------------------
# 資源登記：legend 字元 -> 資源路徑。字元在全章通用，同一字元在不同區域代表同一種東西。
# ---------------------------------------------------------------------------
RES = {
    # 敵人
    'g': 'res://data/enemies/sweeper.tres',
    'k': 'res://data/enemies/collector_gunner.tres',
    'b': 'res://data/enemies/collector_brute.tres',
    'd': 'res://data/enemies/drone.tres',
    'w': 'res://data/enemies/watchdog.tres',
    'n': 'res://data/npcs/ch1_old_k.tres',      # 場景人物（ST-12）：老 K、鷺、阿梨（復原館、麵攤各一份）
    'E': 'res://data/npcs/ch1_egret.tres',
    'Y': 'res://data/npcs/ch1_ali_lounge.tres',
    'Q': 'res://data/npcs/ch1_ali_stall.tres',
    'z': 'res://data/enemies/ch1_inspector.tres',  # 迷你頭目：收帳人·督察（傷會留著）；B 是引擎保留的頭目戰場字元
    # 道具
    'i': 'res://data/consumables/med_injector.tres',
    'e': 'res://data/consumables/shield_cell.tres',
    'c': 'res://data/props/credits_small.tres',
    'q': 'res://data/props/credits_large.tres',
    'u': 'res://data/weapons/melee/melee_dagger.tres',
    'f': 'res://data/story_items/doc_echo_flyer.tres',
    'o': 'res://data/story_items/doc_collection_notice.tres',
    'l': 'res://data/story_items/doc_dike_log.tres',
    'p': 'res://data/story_items/doc_rain_news.tres',
    't': 'res://data/story_items/doc_pawn_stub.tres',
    'y': 'res://data/story_items/ch1_data_disk.tres',
    # 可破壞物與機關
    'x': 'res://data/props/ch1_crate.tres',
    'X': 'res://data/props/ch1_secret_wall.tres',
    'A': 'res://data/props/ch1_switch_a.tres',
    'a': 'res://data/props/ch1_gate_a.tres',
    'R': 'res://data/props/ch1_switch_b.tres',
    'r': 'res://data/props/ch1_gate_b.tres',
    's': 'res://data/props/ch1_gate_c.tres',
    'v': 'res://data/props/ch1_gate_watchdog.tres',
    'W': 'res://data/props/ch1_flood_pit.tres',
}

# 出入口：字元 -> (id, 目標區域, 目標出入口, 模式, 提示, 鎖住提示, 外觀, 寬, 高)
# 模式 0＝互動、1＝走進就切換。目標區域留空＝鎖死的門。
AREA = lambda name: f'res://data/levels/ch1_{name}.tres'  # noqa: E731
PORTALS = {
    # 當舖
    'F': dict(id='pawn_front', to=AREA('street'), target='street_home', mode=0, prompt='{interact} 出門', style='door',
              requires='ch1_heard_brief', locked='先去屋頂：鷺在等你。'),
    'S': dict(id='pawn_stairs', to=AREA('rooftop'), target='roof_stairs', mode=0, prompt='{interact} 上屋頂', style='ladder', w=20, h=152,
              requires='ch1_dinner_done', locked='先吃晚飯。老 K 在等。'),
    'K': dict(id='pawn_basement', to='', target='', mode=0, prompt='{interact} 地下室', locked='漏水，別開。', style='door'),
    # 屋頂
    'T': dict(id='roof_stairs', to=AREA('pawnshop'), target='pawn_stairs', mode=0, prompt='{interact} 下樓', style='ladder', w=20, h=48),
    # 街道
    'h': dict(id='street_home', to=AREA('pawnshop'), target='pawn_front', mode=0, prompt='{interact} 回當舖', style='door'),
    'j': dict(id='street_booth', to=AREA('booth_alley'), target='booth_street', mode=0, prompt='{interact} 電話亭巷', style='road', w=28, h=44),
    'm': dict(id='street_market', to='', target='', mode=0, prompt='{interact} 市集', locked='收帳人封路。', style='road', w=28, h=44),
    'N': dict(id='street_warehouse', to=AREA('warehouse'), target='wh_street', mode=0, prompt='{interact} 碼頭倉庫', style='door', w=28, h=48),
    # 電話亭巷
    'J': dict(id='booth_street', to=AREA('street'), target='street_booth', mode=1, prompt='', style='road', w=20, h=44),
    # 倉庫
    'O': dict(id='wh_street', to=AREA('street'), target='street_warehouse', mode=0, prompt='{interact} 回街道', style='door', w=28, h=48),
    'L': dict(id='wh_upper', to=AREA('lounge'), target='', mode=0, prompt='{interact} 上層通道（過去就回不來了）', style='door'),
    # 復原館
    'G': dict(id='lounge_exit', to=AREA('stall'), target='', mode=1, prompt='', style='road', w=20, h=44,
              requires='ch1_met_ali', locked='先和阿梨說話。'),
    # 宵夜麵攤
    'Z': dict(id='stall_home', to=AREA('pawnshop_dawn'), target='pawn_front', mode=0, prompt='{interact} 回家', style='door',
              requires='knows_ali_address', locked='先吃點東西，和阿梨說話。'),
}

# 鎖場遭遇用的動態字元（每個遭遇一個範圍字元、一個閘門字元）：希臘字母，不會和其他字元衝突。
DYN_POOL = list('αβγδεζηθικλμνξοπρστυφχψω')
DYN_RES = {}          # 字元 -> 資源路徑（輸出 legend 時用）
ENEMY_NAMES = {'g': '清掃兵', 'k': '收帳人槍手', 'b': '打手', 'd': '無人機', 'w': '看門狗', 'z': '督察'}
MAX_MEMBERS = 4        # 單場成員上限
MAX_ALIVE = 6          # 成員加一波增援的同屏上限
ENCOUNTER_DIR = os.path.join(ROOT, 'data', 'props')

CHAPTER = 'ch1_kasa'
BACKDROP = [("far_skyline", 0.12, 300.0), ("mid_buildings", 0.26, 320.0), ("near_foreground", 0.5, 360.0)]


class Area:
    """一個區域：格子網格加上道具清單、提示牌、光影與出入口。"""

    def __init__(self, ident, name, width, ground, **options):
        self.id = ident
        self.name = name
        self.w = width
        self.ground = ground
        self.grid = Grid(width, H)
        self.props = []
        self.hints = []
        self.chars = set()
        self.zones = []          # (起點欄, 過渡欄, 光影 id)
        self.regions = []        # 材質覆蓋區（貨櫃…）
        self.triggers = []       # (欄, 場景 id)：地圖上的 & 劇情觸發點
        self.encounters = []     # 遭遇紀錄（設計報告與檢查用，見 encounter）
        self.combat = False      # 戰鬥區：要有迴圈／獎勵／秘密／地標／垂直空間（features）
        self.features = {}       # 例如 {'loop': '高路', 'secret': '裂縫牆', ...}
        self.options = options
        g = self.grid
        g.fill(0, 0, 0, H - 1, '#')
        g.fill(width - 1, width - 1, 0, H - 1, '#')
        g.fill(1, width - 2, ground, H - 1, '#')

    # --- 格子 -------------------------------------------------------------
    def block(self, x0, x1, y0, y1, c='#'):
        self.grid.fill(x0, x1, y0, y1, c)

    def clear(self, x0, x1, y0, y1):
        self.grid.fill(x0, x1, y0, y1, '.')

    def platform(self, x0, x1, y):
        self.grid.fill(x0, x1, y, y, '=')

    def ceiling(self, x0, x1, rows):
        """室內屋頂：最上方 rows 列實心（有屋頂的欄＝室內，沒有雨、背牆畫成室內牆面）。"""
        self.grid.fill(x0, x1, 0, rows - 1, '#')

    def put(self, x, y, c):
        assert self.grid.at(x, y) in ('.', 'P'), f'{self.id}: ({x},{y}) 已有 {self.grid.at(x, y)!r}，放不下 {c!r}'
        self.grid.put(x, y, c)
        self.chars.add(c)

    def stand(self, x, c, row=None):
        """放在地面上（腳底在地面列的上方一格）。row 指定站立的列。"""
        self.put(x, (self.ground - 1) if row is None else row, c)

    def trigger(self, x, scene):
        """& 劇情觸發點：玩家由左往右越過時播放 scene（每輪一次）。"""
        self.triggers.append((x, scene))
        self.put(x, self.ground - 1, '&')

    def encounter(self, name, x0, x1, members, reinforcements=(), lock=False, slug='', gate_h=10, floor_row=None,
                  start_text='', clear_text='', start_scene='', max_lock=90.0):
        """一場遭遇（ST-11）。members：[(欄, 字元)] 或 [(欄, 字元, 列)]（站在平台上或飛行時指定列），放在 x0～x1 之間。
        lock＝True：在 x0、x1 放競技場閘門（高 gate_h 格），玩家走進範圍就鎖場，成員與增援（reinforcements：字元清單）全倒才打開。
        floor_row：閘門與範圍字元站的列（預設地面上一列）。成員必須剛好是範圍內的所有敵人（check 會數）。"""
        placed = []
        for m in members:
            x, c = m[0], m[1]
            row = m[2] if len(m) > 2 else None
            assert x0 <= x <= x1, f'{self.id}/{name}: 成員 {c!r} 在 {x} 超出範圍 {x0}～{x1}'
            if row is None:
                self.stand(x, c)
            else:
                self.put(x, row, c)
            placed.append(c)
        record = {'name': name, 'x0': x0, 'x1': x1, 'lock': lock, 'members': placed, 'reinforcements': list(reinforcements)}
        if lock:
            assert (x1 - x0) % 2 == 0, f'{self.id}/{name}: 鎖場範圍的寬度要是奇數格（x0、x1 相差偶數）'
            for other in self.encounters:
                if other['lock'] and not (x1 < other['x0'] or x0 > other['x1']):
                    raise AssertionError(f'{self.id}/{name}: 鎖場範圍和 {other["name"]} 重疊')
            zone_char, gate_char = DYN_POOL.pop(0), DYN_POOL.pop(0)
            row = (self.ground - 1) if floor_row is None else floor_row
            self.put((x0 + x1) // 2, row, zone_char)
            self.put(x0, row, gate_char)
            self.put(x1, row, gate_char)
            assert slug.isascii() and slug, f'{self.id}/{name}: 鎖場需要英文代號 slug（資料檔名用）'
            key = f'{self.id}_{slug}'
            DYN_RES[zone_char] = f'res://data/props/ch1_enc_{key}.tres'
            DYN_RES[gate_char] = f'res://data/props/ch1_arena_{key}.tres'
            record.update(zone_char=zone_char, gate_char=gate_char, key=key, gate_h=gate_h, start_text=start_text, clear_text=clear_text,
                          start_scene=start_scene, max_lock=max_lock)
        self.encounters.append(record)

    def region(self, x0, x1, y0, y1, material):
        self.regions.append({"x0": x0, "x1": x1, "y0": y0, "y1": y1, "material": material})

    def lamp(self, x, y):
        self.grid.put(x, y, '*')

    def hint(self, x, text, row=None):
        self.hints.append(text)
        self.put(x, (self.ground - 1) if row is None else row, str(len(self.hints)))

    def prop(self, ident, x, **kw):
        entry = {"id": ident, "x": x}
        entry.update(kw)
        if 'y' not in kw and 'ground' not in kw:
            entry['ground'] = True
        self.props.append(entry)

    def zone(self, start, profile, blend=12):
        self.zones.append((start, blend, profile))

    # --- 檢查 -------------------------------------------------------------
    def solid_below(self, x, y):
        """格子 (x, y) 底下是不是站得住（實心或單向平台）。"""
        return self.grid.at(x, y + 1) in ('#', '=')

    def check(self, flying=('d',)):
        problems = []
        g = self.grid
        legend_chars = set(RES) | set(PORTALS) | set(DYN_RES)
        for y in range(H):
            for x in range(self.w):
                c = g.at(x, y)
                if c in ('P', 'C') or c in legend_chars or c.isdigit():
                    if c in flying:
                        continue
                    if not self.solid_below(x, y):
                        problems.append(f'{self.id}: {c!r} 在 ({x},{y}) 腳下沒有地面')
                    elif y >= HEADROOM and any(g.at(x, y - k) == '#' for k in range(1, HEADROOM)) and c not in ('X',):
                        problems.append(f'{self.id}: {c!r} 在 ({x},{y}) 頭上沒有淨空')
        problems += self.check_encounters()
        return problems

    def check_encounters(self):
        """遭遇規則（design/13-story-v2/CH01_PACING_V2.md §5）：成員上限、同屏上限、鎖場範圍內的敵人剛好是成員。"""
        problems = []
        g = self.grid
        enemy_chars = set(ENEMY_NAMES)
        for e in self.encounters:
            if len(e['members']) > MAX_MEMBERS:
                problems.append(f'{self.id}/{e["name"]}: 成員 {len(e["members"])} 個，超過上限 {MAX_MEMBERS}')
            if len(e['members']) + len(e['reinforcements']) > MAX_ALIVE:
                problems.append(f'{self.id}/{e["name"]}: 成員加增援 {len(e["members"]) + len(e["reinforcements"])} 個，超過同屏上限 {MAX_ALIVE}')
            inside = sorted(g.at(x, y) for y in range(H) for x in range(e['x0'], e['x1'] + 1) if g.at(x, y) in enemy_chars)
            if e['lock'] and inside != sorted(e['members']):
                problems.append(f'{self.id}/{e["name"]}: 鎖場範圍內的敵人 {inside} 和宣告的成員 {sorted(e["members"])} 不一致')
            if not e['lock']:
                for other in self.encounters:
                    if other['lock'] and other['x0'] <= e['x0'] <= other['x1']:
                        problems.append(f'{self.id}/{e["name"]}: 開放遭遇落在鎖場 {other["name"]} 的範圍裡')
        return problems


def reachable(area, start, targets, open_chars=('a', 'r', 's', 'v')):
    """簡化的平台可達性：從起點出發，能走、能跳（上 5 格、橫 7 格內）、能落下。回傳到不了的目標清單。
    閘門視為打開；水坑視為漲滿（坑口有貨櫃浮橋）。"""
    g = area.grid

    def cell(x, y):
        if x < 0 or x >= area.w or y < 0 or y >= H:
            return '#'
        return g.at(x, y)

    def solid(x, y):
        return cell(x, y) == '#'

    pits = [(x, y) for x in range(area.w) for y in range(H) if cell(x, y) == 'W']
    raft = set()
    if pits:
        px = pits[0][0]
        for x in range(px - 5, px + 6):
            raft.add((x, 17))

    def support(x, y):
        return solid(x, y + 1) or cell(x, y + 1) == '=' or (x, y + 1) in raft

    def free(x, y):
        return all(not solid(x, y - k) for k in range(HEADROOM))

    def land(x, y):
        # 從 (x, y) 往下落到第一個有支撐的位置；落出地圖回傳 None
        while y < H - 1 and not support(x, y):
            y += 1
        return (x, y) if y < H - 1 and free(x, y) else None

    seen = {start}
    stack = [start]
    while stack:
        x, y = stack.pop()
        for dx in range(-7, 8):
            nx = x + dx
            if nx < 1 or nx >= area.w - 1:
                continue
            for dy in range(-PLAYER_JUMP_TILES, 1):
                ty = y + dy
                if ty < 0 or solid(nx, ty) or not free(nx, ty):
                    continue
                if abs(dx) > 1 and dy == 0 and any(solid(x + (1 if dx > 0 else -1) * k, y) for k in range(1, abs(dx))):
                    continue
                if dy < 0 and any(solid(x, y - k) for k in range(1, -dy + 1)):
                    continue
                if support(nx, ty):
                    node = (nx, ty)
                elif dy == 0 and abs(dx) <= 1:
                    node = land(nx, ty)
                else:
                    node = land(nx, ty)
                if node and node not in seen:
                    seen.add(node)
                    stack.append(node)
    missing = []
    for c, (tx, ty) in targets:
        near = any((tx + ax, ty + ay) in seen for ax in (-1, 0, 1) for ay in (-1, 0, 1))
        if not near:
            missing.append(f'{area.id}: {c!r} 在 ({tx},{ty}) 到不了')
    return missing


def write_tres_value(v):
    return json.dumps(v, ensure_ascii=False)


class TresWriter:
    """最小的 .tres 文字輸出：收集 ext_resource 與 sub_resource，最後組成檔案。"""

    def __init__(self, script_class, script_path):
        self.script_class = script_class
        self.exts = {}        # 路徑 -> (id, type)
        self.subs = []
        self.script_id = self.ext(script_path, 'Script')

    def ext(self, path, kind='Resource'):
        if path not in self.exts:
            base = os.path.basename(path).split('.')[0]
            self.exts[path] = (f'{len(self.exts) + 1}_{base}', kind)
        return self.exts[path][0]

    def sub(self, body_lines):
        sid = f'Resource_{len(self.subs)}'
        self.subs.append((sid, body_lines))
        return sid

    def render(self, resource_lines):
        total = len(self.exts) + len(self.subs) + 1
        out = [f'[gd_resource type="Resource" script_class="{self.script_class}" load_steps={total} format=3]', '']
        for path, (ident, kind) in self.exts.items():
            out.append(f'[ext_resource type="{kind}" path="{path}" id="{ident}"]')
        out.append('')
        for sid, body in self.subs:
            out.append(f'[sub_resource type="Resource" id="{sid}"]')
            out.extend(body)
            out.append('')
        out.append('[resource]')
        out.extend(resource_lines)
        return '\n'.join(out) + '\n'


# ---------------------------------------------------------------------------
# 機關與可破壞物的資料（只在檔案不存在時建立，之後可直接在編輯器調整）
# ---------------------------------------------------------------------------

def write_data_files():
    os.makedirs(PROP_DIR, exist_ok=True)
    files = {
        'ch1_crate.tres': ('BreakableData', 'res://data/scripts/breakable_data.gd', [
            'id = &"ch1_crate"', 'display_name = "貨箱"', 'look = 0', 'hint = "貨箱：打破它，裡面有零錢"', 'max_health = 3',
            'size_tiles = Vector2i(2, 2)', 'color = Color(0.45, 0.4, 0.34, 1.0)', 'credit_drop = 10']),
        'ch1_secret_wall.tres': ('BreakableData', 'res://data/scripts/breakable_data.gd', [
            'id = &"ch1_secret_wall"', 'display_name = "裂縫牆"', 'look = 3', 'hint = "牆上有裂縫：打破它，後面可能有東西"', 'max_health = 5',
            'size_tiles = Vector2i(1, 3)', 'color = Color(0.3, 0.34, 0.4, 1.0)']),
        'ch1_switch_a.tres': ('MechanismData', 'res://data/scripts/mechanism_data.gd', [
            'id = &"ch1_switch_a"', 'kind = 2', 'display_name = "水閘開關 A"', 'hint = "{interact} 切換開關：閘 A"',
            'color = Color(0.35, 0.88, 1, 1)', 'channel = &"flood_a"']),
        'ch1_gate_a.tres': ('MechanismData', 'res://data/scripts/mechanism_data.gd', [
            'id = &"ch1_gate_a"', 'kind = 1', 'display_name = "閘 A"', 'hint = "閘 A：旁邊的開關控制它"',
            'color = Color(0.35, 0.88, 1, 1)', 'channel = &"flood_a"', 'size_tiles = Vector2i(1, 13)']),
        'ch1_switch_b.tres': ('MechanismData', 'res://data/scripts/mechanism_data.gd', [
            'id = &"ch1_switch_b"', 'kind = 2', 'display_name = "水閘開關 B"', 'hint = "{interact} 切換開關：閘 B"',
            'color = Color(1, 0.76, 0.29, 1)', 'channel = &"flood_b"']),
        'ch1_gate_b.tres': ('MechanismData', 'res://data/scripts/mechanism_data.gd', [
            'id = &"ch1_gate_b"', 'kind = 1', 'display_name = "閘 B"', 'hint = "閘 B：開關在高處的平台上"',
            'color = Color(1, 0.76, 0.29, 1)', 'channel = &"flood_b"', 'size_tiles = Vector2i(1, 13)']),
        'ch1_gate_c.tres': ('MechanismData', 'res://data/scripts/mechanism_data.gd', [
            'id = &"ch1_gate_c"', 'kind = 1', 'display_name = "閘 C"', 'hint = "閘 C：開關是坑底的踏板"',
            'color = Color(1, 0.35, 0.3, 1)', 'channel = &"flood_c"', 'size_tiles = Vector2i(1, 13)']),
        'ch1_gate_watchdog.tres': ('MechanismData', 'res://data/scripts/mechanism_data.gd', [
            'id = &"ch1_gate_watchdog"', 'kind = 1', 'display_name = "隔牆"', 'hint = "隔牆：打倒看門狗才會升起"',
            'color = Color(1, 0.55, 0.2, 1)', 'channel = &"watchdog_gate"', 'size_tiles = Vector2i(1, 13)']),
        'ch1_flood_pit.tres': ('MechanismData', 'res://data/scripts/mechanism_data.gd', [
            'id = &"ch1_flood_pit"', 'kind = 4', 'display_name = "水坑"', 'color = Color(0.35, 0.88, 1, 1)',
            'channel = &"flood_c"', 'size_tiles = Vector2i(11, 6)', 'rise_time = 1.8']),
    }
    for name, (cls, script, lines) in files.items():
        path = os.path.join(PROP_DIR, name)
        if os.path.exists(path):
            continue
        w = TresWriter(cls, script)
        body = [f'script = ExtResource("{w.script_id}")'] + lines
        with open(path, 'w') as f:
            f.write(w.render(body))
        print('wrote', path)


# ---------------------------------------------------------------------------
# 區域設計
# ---------------------------------------------------------------------------

def build_pawnshop():
    """當舖由左到右：後空地（教學）→ 店面 → 廚房（晚飯、樓梯）。玩家從店面開始，教學之後一路往右走到屋頂。"""
    a = Area('pawnshop', '當舖', 112, 20, indoor=True)
    a.ceiling(31, 110, 10)
    a.block(31, 31, 10, 16)       # 後空地與店面之間（高 3 格的門洞）
    a.block(79, 79, 10, 16)       # 店面與廚房之間
    # 店面
    a.stand(40, 'P')
    a.hint(38, '移動 {move_left}/{move_right}，跳躍 {jump}（按久跳更高）')
    a.hint(46, '按 {inventory} 開背包：武器改裝、道具與文件都在這裡')
    a.prop('pawnshop_front__tag_shelf', 33)
    a.prop('basement_door__locked_iron_door', 42)
    a.stand(43, 'K')
    a.prop('pawnshop_front__wall_instruments', 49, y=14)
    a.prop('pawnshop_front__counter_register', 52)
    a.prop('pawnshop_front__locked_ledger_box', 53, dy=-36)
    a.prop('pawnshop_front__arms_workbench', 61)
    a.prop('pawnshop_front__pawn_sign', 64, y=11)
    a.prop('pawnshop_front__leak_bucket', 69)
    a.prop('pawnshop_front__crate_pile', 72)
    a.prop('harbor_street__umbrella_stand', 76)
    a.stand(57, 't')
    a.stand(67, 'c')
    a.stand(74, 'F')
    for x in (36, 46, 56, 66, 74):
        a.lamp(x, 11)
    # 後空地（教學）x=1～30
    a.hint(28, '滑鼠瞄準，{shoot} 射擊；{reload} 換彈。打左邊的木箱練習')
    a.stand(5, 'x')
    a.stand(9, 'x')
    a.hint(20, '{dash} 衝刺：短暫無敵，可以穿過危險')
    a.platform(12, 17, 16)
    a.put(14, 15, 'u')
    a.hint(11, '{move_down}＋{jump} 從單向平台落下；{melee} 近戰')
    a.stand(24, 'c')
    # 廚房 x=80～110：晚飯在入口，樓梯在最右
    a.trigger(82, 'ch1_b_dinner')
    a.stand(86, 'n')
    a.hint(88, '老 K 在桌邊：按 {interact} 和他說話')
    a.prop('pawnshop_kitchen__dish_cabinet', 81)
    a.prop('pawnshop_kitchen__water_urn', 83)
    a.prop('pawnshop_kitchen__dining_table', 90)
    a.prop('pawnshop_kitchen__lunch_left_for_today', 91, dy=-25)
    a.prop('pawnshop_kitchen__hanging_pans', 94, y=13)
    a.prop('pawnshop_kitchen__paper_shade_lamp', 88, y=11)
    a.prop('pawnshop_kitchen__kettle_stove', 98)
    a.prop('pawnshop_kitchen__old_fridge', 102)
    a.prop('pawnshop_kitchen__tear_off_calendar', 100, y=14)
    a.hint(104, '樓梯通往屋頂：鷺在上面等你')
    a.stand(108, 'S')
    for x in (88, 98, 106):
        a.lamp(x, 11)
    a.zone(0, 'rooftop')
    a.zone(30, 'pawnshop_warm', 6)
    return a


def build_rooftop():
    a = Area('rooftop', '屋頂', 72, 18)
    a.clear(29, 31, 18, 21)        # 縫：寬 3 格、深 4 格，掉下去爬得上來
    a.block(14, 16, 16, 17)         # 冷氣機
    a.block(56, 58, 16, 17)
    a.stand(3, 'T')
    a.stand(5, 'P')
    a.hint(24, '屋頂中間有一條縫：助跑跳過去，跳躍 {jump}')
    a.stand(20, 'c')
    a.stand(62, 'c')
    a.trigger(34, 'ch1_b_roof')
    a.stand(54, 'E')
    a.hint(50, '鷺在等你：走過去按 {interact} 聽差事')
    a.prop('rooftop__stairwell_hut', 1)
    a.prop('rooftop__rusty_water_tank', 44)
    a.prop('rooftop__antenna_forest', 64)
    a.prop('rooftop__dish_pair', 9)
    a.prop('rooftop__rain_collecting_barrel', 34)
    a.prop('rooftop__torn_umbrella_tea', 38)
    a.prop('rooftop__folding_chairs_boxes', 49)
    a.prop('rooftop__rope_coil_hook', 22, y=10)
    a.lamp(12, 12)
    a.lamp(40, 12)
    a.lamp(66, 12)
    a.zone(0, 'rooftop')
    return a


def build_street():
    """港區街道（ST-11 重設計）：市集口（安全）→ 掩護教學 → 格擋 → 鎖場「街心」→ 近戰與高路 → 空襲 → 鎖場「路障」（迷你頭目）→ 裂縫牆秘密房 → 倉庫門。
    逐場遭遇與設計理由見 design/13-story-v2/CH01_PACING_V2.md §3.1。"""
    a = Area('street', '港區街道', 208, 20)
    a.combat = True
    a.features = {
        'loop': '高路：從 x=122 的階梯平台上屋頂帶（列 10），沿路到 x=146 跳下回到街上',
        'reward': '屋頂帶上的大額信用點（x=139）：從街上就看得到，要繞階梯才拿得到',
        'secret': '路障後的裂縫牆（x=187）：打破牆進去有大額信用點',
        'landmark': '重生看板（x=102，整條街都看得到）',
        'vertical': '地面、平台、屋頂帶三層',
    }
    a.stand(4, 'P')
    a.stand(6, 'h')
    # 市集口（安全區）
    a.trigger(9, 'ch1_b_street_in')
    a.hint(10, '街上有人發傳單、有人聊天，不是每個人都想打你')
    a.stand(22, 'f')
    a.stand(34, 'j')
    a.hint(38, '街角的巷子裡有電話亭：先去備份，死了才有地方醒來')
    # 掩護教學（x=49～70）
    a.trigger(50, 'ch1_g06_lamp')
    a.hint(52, '清掃兵在前面：靠著箱子，瞄準、射擊、再縮回去')
    a.block(58, 59, 18, 19)
    a.encounter('接觸', 62, 70, [(66, 'g')])
    # 高台（x=72～86）：抬頭瞄準
    a.block(72, 73, 17, 19)
    a.platform(76, 81, 16)
    a.encounter('高台', 76, 86, [(78, 'g', 15), (84, 'g')])
    # 格擋（x=84～90）
    a.trigger(82, 'ch1_g06_tip_slide')
    a.hint(86, '按住 {block} 舉盾；子彈到的瞬間舉盾＝完美反彈')
    a.block(88, 88, 18, 19)
    a.encounter('格擋', 89, 90, [(90, 'k')])
    # 鎖場「街心」（x=92～118）：兩層平台與一架無人機，增援一名槍手
    a.platform(98, 103, 16)
    a.platform(106, 111, 13)
    a.block(113, 114, 18, 19)
    a.encounter('街心', 92, 118, [(98, 'g'), (111, 'g'), (104, 'd', 9)], reinforcements=['k'], lock=True, slug='plaza', gate_h=9,
                start_text='路被封住了：打倒他們', clear_text='街道通了', start_scene='ch1_k_plaza')
    a.stand(121, 'i')
    # 近戰與高路（x=122～147）
    a.trigger(120, 'ch1_g06_tip_blade')
    a.hint(123, '敵人頭上出現青色菱形：按 {melee} 終結，回補彈藥')
    a.block(127, 128, 18, 19)
    a.encounter('近戰', 124, 140, [(133, 'b'), (138, 'g')])
    a.platform(122, 125, 16)
    a.platform(127, 130, 13)
    a.platform(132, 146, 10)
    a.stand(139, 'q', row=9)
    a.encounter('高路', 141, 146, [(143, 'g', 9)])
    # 空襲（x=142～150）
    a.encounter('空襲', 147, 150, [(148, 'd', 13)])
    # 鎖場「路障」（x=152～182）＝迷你頭目：督察、兩名槍手；增援兩名清掃兵
    a.trigger(149, 'ch1_g06_tip_collector')
    a.block(160, 161, 17, 19)
    a.platform(164, 169, 15)
    a.block(171, 172, 18, 19)
    a.platform(175, 179, 15)
    a.encounter('路障', 152, 182, [(168, 'z'), (166, 'k', 14), (177, 'k', 14)], reinforcements=['g', 'g'], lock=True, slug='blockade', gate_h=9,
                start_text='收帳人封路：撐住', clear_text='路障清掉了', start_scene='ch1_k_blockade')
    a.stand(185, 'o')
    a.stand(184, 'c')
    a.stand(186, 'm')
    # 碼頭路（x=183～207）：裂縫牆的秘密房與倉庫的門
    a.block(187, 199, 16, 19)
    a.clear(187, 193, 17, 19)
    a.put(187, 19, 'X')
    a.stand(191, 'q', row=19)
    a.stand(203, 'c')
    a.stand(204, 'N')
    a.trigger(183, 'ch1_g06_clear')
    a.hint(201, '碼頭倉庫：看門狗睡在大廳深處，走進去再決定要不要叫醒牠')
    a.encounter('出口伏擊', 183, 187, [(184, 'd', 14), (186, 'd', 11)])
    a.stand(188, 'e')
    # 道具：背景立面
    a.prop('harbor_street__fish_cart', 14)
    a.prop('harbor_street__parked_scooter', 42)
    a.prop('harbor_street__pole_wire_knot', 54)
    a.prop('harbor_street__restore_queue_sign', 28)
    a.prop('harbor_street__stacked_neon_signs', 74, y=12)
    a.prop('harbor_street__rebirth_billboard', 102, y=8)
    a.prop('harbor_street__steam_manhole', 118)
    a.prop('harbor_street__tide_gauge', 144)
    a.prop('harbor_street__umbrella_vending', 170)
    a.prop('harbor_street__stacked_neon_signs', 178, y=12)
    for x in (10, 30, 56, 78, 104, 126, 150, 176, 200):
        a.lamp(x, 8)
    a.zone(0, 'market')
    a.zone(181, 'freight', 14)
    return a


def build_booth_alley():
    a = Area('booth_alley', '電話亭巷', 56, 20)
    a.stand(4, 'J')
    a.stand(6, 'P')
    a.stand(26, 'C')
    a.hint(22, '電話亭：按 {interact} 備份。死了會從最近的電話亭醒來')
    a.stand(18, 'c')
    a.stand(44, 'c')
    a.stand(36, 'p')
    a.prop('anchor_phone_booth__shutter_graffiti', 8)
    a.prop('anchor_phone_booth__trash_bags', 13)
    a.prop('anchor_phone_booth__news_rack', 34)
    a.prop('anchor_phone_booth__leaning_bicycle', 40)
    a.prop('anchor_phone_booth__restore_arrow_sign', 48)
    a.prop('anchor_phone_booth__backup_kiosk', 51)
    a.prop('anchor_phone_booth__poster_wall', 28, y=14)
    a.prop('anchor_phone_booth__flicker_lamp_post', 31)
    a.prop('anchor_phone_booth__gutter_downpipe', 20)
    a.lamp(26, 8)
    a.zone(0, 'neutral')
    return a


def build_warehouse():
    """碼頭倉庫（ST-11 重設計）：前廳（看門狗＝迷你頭目 A）→ 閘門廳（機關與水坑）→ 保險箱（鎖場，迷你頭目 B）→ 上層走道（鎖場）。
    逐場遭遇與設計理由見 design/13-story-v2/CH01_PACING_V2.md §3.2。"""
    a = Area('warehouse', '碼頭倉庫', 244, 17, indoor=True)
    a.combat = True
    a.features = {
        'loop': '保險箱旁的階梯平台（x=168～181）：上去走上層走道，也可以從平台跳回下層走道',
        'reward': '貨櫃堆頂的醫療針（x=24）：前廳一進來就看得到，要爬貨櫃，上面有槍手守著',
        'secret': '下層走道盡頭的裂縫牆（x=234）：打破牆進去有大額信用點',
        'landmark': '吊車鏈條與探照燈（前廳，x=11～34）',
        'vertical': '地面、貨櫃頂、上層走道三層',
    }
    a.ceiling(1, 242, 4)
    # 前廳（看門狗廳）x=1～72
    a.stand(3, 'O')
    a.stand(4, 'P')
    a.hint(7, '看門狗睡在大廳深處：牠的傷會留著，死了不白死')
    a.trigger(10, 'ch1_g07_dog')
    a.stand(9, 'i')
    a.block(14, 19, 14, 16)       # 貨櫃（掩護與平台）
    a.region(14, 19, 14, 16, 'container_red')
    a.block(22, 25, 12, 16)
    a.region(22, 25, 12, 16, 'container_blue')
    a.block(46, 49, 14, 16)
    a.region(46, 49, 14, 16, 'container_green')
    a.encounter('貨櫃頂', 20, 26, [(23, 'k', 11)])
    a.stand(24, 'i', row=11)
    a.encounter('前廳左', 28, 34, [(30, 'g')])
    a.encounter('前廳右', 36, 42, [(38, 'g')])
    a.encounter('吊車下', 44, 50, [(47, 'k', 13)])
    a.encounter('看門狗', 52, 60, [(56, 'w')])      # 迷你頭目 A：不鎖場，傷會留著
    a.stand(28, 'c')
    a.stand(66, 'c')
    a.stand(68, 'c')
    a.hint(70, '隔牆：打倒看門狗才會升起')
    a.stand(73, 'v')
    a.prop('dock_warehouse__watchdog_dock', 60)
    a.prop('dock_warehouse__hoist_chain', 34, y=9)
    a.prop('dock_warehouse__searchlight_post', 11)
    a.prop('dock_warehouse__wrapped_pallets', 41)
    a.prop('dock_warehouse__rotating_beacon', 52)
    # 閘門廳 x=74～160
    a.stand(77, 'C')
    a.hint(80, '電話亭 B2：先備份，再往裡走')
    a.stand(83, 'A')
    a.stand(84, 'l')
    a.stand(90, 'a')
    a.hint(92, '開關：按 {interact} 切換，閘門跟著開關')
    a.encounter('開關守衛', 93, 96, [(95, 'b')])
    a.block(97, 99, 14, 16)
    a.region(97, 99, 14, 16, 'container_rust')
    a.block(101, 103, 12, 16)
    a.region(101, 103, 12, 16, 'container_red')
    a.platform(105, 110, 11)
    a.put(107, 10, 'R')
    a.encounter('高處無人機', 98, 110, [(100, 'd', 7), (108, 'd', 6)])
    a.stand(112, 'r')
    a.stand(113, 'c')
    a.encounter('坑前', 114, 116, [(114, 'b'), (116, 'k')])
    a.hint(115, '牆上的水位刻度很高：這個坑會漲水')
    a.trigger(117, 'ch1_g10_pit')
    a.trigger(119, 'ch1_g10_pit2')
    # 水坑：寬 11（x=118～128）、深 6（列 17～22），坑底在第 23 列
    a.clear(118, 128, 17, 22)
    a.stand(123, 'W', row=22)
    a.encounter('坑上', 119, 128, [(123, 'd', 7)])
    a.stand(133, 's')
    a.trigger(135, 'ch1_g10_cross')
    a.prop('dock_warehouse__floor_switch_plate', 121, y=22, dx=-3)
    a.prop('dock_warehouse__water_pump', 86)
    a.prop('dock_warehouse__float_drum_crate', 106, y=10)
    a.encounter('坑對岸', 134, 140, [(137, 'g'), (140, 'g')])
    # 保險箱 x=142～166：鎖場，迷你頭目 B（督察），資料盤在裡面
    a.block(150, 151, 14, 16)
    a.platform(158, 163, 13)
    a.encounter('保險箱守衛', 142, 166, [(157, 'z'), (148, 'k')], reinforcements=['b'], lock=True, slug='vault', gate_h=13,
                start_text='保險箱有人守著：撐住', clear_text='保險箱安全了', start_scene='ch1_k_vault')
    a.stand(160, 'y')
    a.hint(156, '保險箱裡有一片資料盤：拿了就能從上層通道離開')
    a.stand(146, 'c')
    a.stand(167, 'i')
    a.trigger(168, 'ch1_g10_disk')
    a.prop('dock_warehouse__open_container', 143)
    # 上層走道：階梯平台通往右側的高處走道
    a.platform(168, 171, 14)
    a.platform(173, 176, 12)
    a.platform(178, 181, 10)
    a.encounter('階梯', 169, 181, [(172, 'd', 9)])
    a.block(183, 238, 9, 10)
    a.block(239, 242, 9, 10)
    a.put(240, 8, 'L')
    a.stand(190, 'c', row=8)
    a.encounter('上層走道', 185, 235, [(192, 'g', 8), (204, 'g', 8), (216, 'k', 8), (210, 'd', 6)], reinforcements=['k'], lock=True, slug='walkway',
                gate_h=5, floor_row=8, start_text='走道上有人：清乾淨再走', clear_text='走道通了', start_scene='ch1_k_walkway')
    # 下層走道（走道下面）：秘密房
    a.stand(210, 'c', row=16)
    a.stand(200, 'i', row=16)
    a.block(234, 241, 11, 16)
    a.clear(234, 240, 14, 16)
    a.put(234, 16, 'X')
    a.stand(238, 'q', row=16)
    for x in (12, 40, 66, 90, 118, 146, 172, 200, 226):
        a.lamp(x, 5)
    a.zone(0, 'freight')
    return a


def build_lounge():
    a = Area('lounge', '復原館', 56, 20, indoor=True)
    a.ceiling(1, 54, 10)
    a.stand(4, 'P')
    a.stand(52, 'G')
    a.trigger(12, 'ch1_b_lounge')
    a.stand(30, 'Y')
    a.hint(26, '阿梨在吧台：走過去按 {interact} 說話，說完才出得去')
    a.prop('revival_lounge__booth_sofa', 6)
    a.prop('revival_lounge__round_table_stools', 14)
    a.prop('revival_lounge__jukebox', 21)
    a.prop('revival_lounge__bar_counter', 27)
    a.prop('revival_lounge__bottle_wall_shelf', 28, y=14)
    a.prop('revival_lounge__menu_board', 38, y=14)
    a.prop('revival_lounge__corner_plant_string_lights', 40)
    a.prop('revival_lounge__hat_coat_rack', 46)
    a.prop('revival_lounge__neon_glass_sign', 10, y=13)
    for x in (10, 24, 38, 50):
        a.lamp(x, 11)
    a.zone(0, 'market')
    return a


def build_stall():
    a = Area('stall', '宵夜麵攤', 48, 20)
    a.stand(4, 'P')
    a.stand(44, 'Z')
    a.trigger(12, 'ch1_b_stall')
    a.stand(21, 'Q')
    a.hint(17, '阿梨的麵攤：按 {interact} 說話，說完才能回家')
    a.prop('dawn_noodle_stall__ali_noodle_cart', 18)
    a.prop('dawn_noodle_stall__noodle_bowls_table', 26)
    a.prop('dawn_noodle_stall__stool_stack', 32)
    a.prop('dawn_noodle_stall__hanging_lantern', 22, y=12)
    a.prop('dawn_noodle_stall__dawn_string_lights', 14, y=10)
    a.prop('dawn_noodle_stall__cat_box_bed', 36)
    a.prop('dawn_noodle_stall__shop_shutter_dawn', 6)
    a.lamp(20, 9)
    a.zone(0, 'mezzanine_gray')
    return a


# ---------------------------------------------------------------------------
# 場景人物（ST-12）：地圖上說話的人。台詞在劇本（build_ch1_story.py）：玩家靠近按互動鍵才說的是 dialogue 場景，到達時冒的是氣泡。
# ---------------------------------------------------------------------------
NPC_DIR = os.path.join(ROOT, 'data', 'npcs')
NPCS = {
    'ch1_old_k': dict(name='老 K', speaker='old_k', rig='old_k', loop='wipe_hands', facing=-1, prompt='{interact} 和老 K 說話',
                      talks=[('ch1_t_oldk_1', 0), ('ch1_t_oldk_2', 1)]),
    'ch1_egret': dict(name='鷺', speaker='egret', rig='night_worker', pose='lean', loop='yawn', facing=-1, prompt='{interact} 聽鷺說差事',
                      talks=[('ch1_t_egret_1', 0), ('ch1_t_egret_2', 1)]),
    'ch1_ali_lounge': dict(name='阿梨', speaker='ali', rig='nurse', loop='wipe_hands', facing=-1, prompt='{interact} 和阿梨說話',
                           talks=[('ch1_t_ali_1', 0), ('ch1_t_ali_2', 1)]),
    'ch1_ali_stall': dict(name='阿梨', speaker='ali', rig='nurse', loop='stir', facing=-1, prompt='{interact} 和阿梨說話',
                          talks=[('ch1_t_ali_3', 0), ('ch1_t_ali_4', 1)]),
}


def write_npc_files():
    os.makedirs(NPC_DIR, exist_ok=True)
    for ident, n in NPCS.items():
        w = TresWriter('NpcData', 'res://data/scripts/npc_data.gd')
        talk_script = w.ext('res://data/scripts/npc_talk.gd', 'Script')
        subs = []
        for scene, min_talks in n['talks']:
            body = [f'script = ExtResource("{talk_script}")', f'scene = &"{scene}"']
            if min_talks:
                body.append(f'min_talks = {min_talks}')
            subs.append(w.sub(body))
        lines = [f'script = ExtResource("{w.script_id}")', f'id = &"{ident}"', f'display_name = {json.dumps(n["name"], ensure_ascii=False)}',
                 f'speaker = "{n["speaker"]}"', f'rig_id = "{n["rig"]}"']
        if n.get('pose'):
            lines.append(f'pose = &"{n["pose"]}"')
        lines += [f'loop = &"{n["loop"]}"', f'facing = {n["facing"]}', f'prompt = {json.dumps(n["prompt"], ensure_ascii=False)}',
                  f'talks = Array[ExtResource("{talk_script}")]([' + ', '.join(f'SubResource("{x}")' for x in subs) + '])']
        with open(os.path.join(NPC_DIR, f'{ident}.tres'), 'w') as f:
            f.write(w.render(lines))


# ---------------------------------------------------------------------------
# 鎖場遭遇的資料檔與設計報告
# ---------------------------------------------------------------------------

def write_encounter_files(areas):
    """每個鎖場兩個資料檔：範圍（ENCOUNTER）與競技場閘門（GATE，arena_gate）。每次重新產生，不手改。"""
    os.makedirs(ENCOUNTER_DIR, exist_ok=True)
    for a in areas:
        for e in a.encounters:
            if not e['lock']:
                continue
            channel = f'arena_{e["key"]}'
            w = TresWriter('MechanismData', 'res://data/scripts/mechanism_data.gd')
            width = e['x1'] - e['x0'] + 1
            lines = [f'script = ExtResource("{w.script_id}")', f'id = &"ch1_enc_{e["key"]}"', 'kind = 5',
                     f'display_name = {json.dumps("鎖場：" + e["name"], ensure_ascii=False)}', f'channel = &"{channel}"',
                     f'size_tiles = Vector2i({width}, {e["gate_h"]})', f'max_lock_seconds = {float(e["max_lock"])}']
            if e['reinforcements']:
                enemy_script = w.ext('res://data/scripts/enemy_data.gd', 'Script')
                refs = ', '.join(f'ExtResource("{w.ext(RES[c])}")' for c in e['reinforcements'])
                lines.append(f'reinforcements = Array[ExtResource("{enemy_script}")]([{refs}])')
            if e['start_text']:
                lines.append(f'start_text = {json.dumps(e["start_text"], ensure_ascii=False)}')
            if e['clear_text']:
                lines.append(f'clear_text = {json.dumps(e["clear_text"], ensure_ascii=False)}')
            if e['start_scene']:
                lines.append(f'start_scene = &"{e["start_scene"]}"')
            with open(os.path.join(ENCOUNTER_DIR, f'ch1_enc_{e["key"]}.tres'), 'w') as f:
                f.write(w.render(lines))
            g = TresWriter('MechanismData', 'res://data/scripts/mechanism_data.gd')
            glines = [f'script = ExtResource("{g.script_id}")', f'id = &"ch1_arena_{e["key"]}"', 'kind = 1',
                      f'display_name = "競技場閘門"', 'hint = ""', 'color = Color(1, 0.35, 0.3, 1)', f'channel = &"{channel}"',
                      f'size_tiles = Vector2i(1, {e["gate_h"]})', 'arena_gate = true']
            with open(os.path.join(ENCOUNTER_DIR, f'ch1_arena_{e["key"]}.tres'), 'w') as f:
                f.write(g.render(glines))


def write_design(areas):
    """設計資料：每區的戰鬥區標記、特色（迴圈、獎勵、秘密、地標、垂直空間）與遭遇清單，測試與報告讀它。"""
    data = {'areas': {}}
    for a in areas:
        data['areas'][a.id] = {
            'combat': a.combat, 'features': a.features,
            'encounters': [{'name': e['name'], 'lock': e['lock'], 'x0': e['x0'], 'x1': e['x1'], 'members': [ENEMY_NAMES[c] for c in e['members']],
                            'reinforcements': [ENEMY_NAMES[c] for c in e['reinforcements']]} for e in a.encounters],
        }
    with open(os.path.join(LEVEL_DIR, 'ch1_design.json'), 'w') as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write('\n')


def render_overview(areas, out_dir):
    """一頁式地圖圖解（設計文件用）：每格 6 像素，實心、平台、敵人、鎖場閘門、獎勵、出入口與電話亭用不同顏色，鎖場範圍畫框。"""
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        print('沒有 Pillow，略過地圖圖解')
        return
    cell = 6
    font = ImageFont.truetype(os.path.join(ROOT, 'art', 'fonts', 'Cubic_11.ttf'), 11)
    colors = {'#': (70, 76, 90), '=': (120, 170, 200), 'P': (80, 220, 120), 'C': (60, 200, 255), 'X': (200, 150, 60)}
    enemy_color = (235, 70, 70)
    boss_color = (255, 40, 200)
    for a in areas:
        if not a.combat:
            continue
        w, h = a.w * cell, H * cell + 28
        img = Image.new('RGB', (w, h), (18, 20, 28))
        d = ImageDraw.Draw(img)
        for y in range(H):
            for x in range(a.w):
                c = a.grid.at(x, y)
                box = (x * cell, y * cell + 14, x * cell + cell - 1, y * cell + 14 + cell - 1)
                if c in colors:
                    d.rectangle(box, fill=colors[c])
                elif c in ('w', 'z'):
                    d.rectangle(box, fill=boss_color)
                elif c in ENEMY_NAMES:
                    d.rectangle(box, fill=enemy_color)
                elif c in DYN_RES and DYN_RES[c].find('_arena_') >= 0:
                    d.rectangle(box, fill=(255, 160, 40))
                elif c in ('q', 'c', 'i', 'e', 'y', 'o', 'f', 'l', 'p', 't'):
                    d.rectangle(box, fill=(250, 220, 60))
                elif c in PORTALS:
                    d.rectangle(box, fill=(180, 120, 255))
        for e in a.encounters:
            if e['lock']:
                d.rectangle((e['x0'] * cell, 14, e['x1'] * cell + cell - 1, 14 + H * cell), outline=(255, 160, 40))
                d.text((e['x0'] * cell + 3, 1), e['name'], fill=(255, 190, 90), font=font)
        d.text((2, H * cell + 16), f'{a.id}  紅＝敵人 洋紅＝迷你頭目 橘＝競技場閘門／鎖場框 黃＝獎勵 紫＝出入口 藍＝電話亭 青＝平台', fill=(190, 200, 220), font=font)
        os.makedirs(out_dir, exist_ok=True)
        img.save(os.path.join(out_dir, f'ST-11-map-{a.id}.png'))
        print('wrote', os.path.join(out_dir, f'ST-11-map-{a.id}.png'))


def report(areas):
    total = locks = 0
    for a in areas:
        for e in a.encounters:
            total += 1
            locks += 1 if e['lock'] else 0
    print(f'遭遇 {total} 場，其中鎖場 {locks} 場')
    for a in areas:
        if a.encounters:
            print(f'  {a.id}: ' + '、'.join(f'{e["name"]}{"（鎖）" if e["lock"] else ""}' for e in a.encounters))


# ---------------------------------------------------------------------------
# 輸出
# ---------------------------------------------------------------------------

THEMES = {
    # 區域 -> (地形材質, 立面清單, 室內牆面貼圖, 鏤空機率, 天空, 道具資料夾)
    'pawnshop': ('concrete', ['shopfront', 'brick_block'], 'brick', 0.0, 'sky_storm', ['pawnshop_front', 'pawnshop_kitchen', 'basement_door', 'harbor_street']),
    'rooftop': ('rooftop', ['apartment', 'brick_block'], None, 0.22, 'sky_storm', ['rooftop']),
    'street': ('asphalt', ['shopfront', 'apartment', 'shutter_block'], None, 0.22, 'sky_storm', ['harbor_street']),
    'booth_alley': ('asphalt', ['shutter_block', 'apartment'], None, 0.22, 'sky_storm', ['anchor_phone_booth']),
    'warehouse': ('concrete', ['warehouse'], 'hangar_wall', 0.0, 'sky_storm', ['dock_warehouse']),
    'lounge': ('facility_floor', ['facility_wall'], 'facility_panel', 0.0, 'sky_storm', ['revival_lounge']),
    'stall': ('asphalt', ['shopfront', 'shutter_block'], None, 0.22, 'sky_dawn', ['dawn_noodle_stall']),
}
SCENE_PROPS = 'res://data/environment/scene_props/%s'

def write_theme(area, theme_key):
    material, facades, interior, holes, sky, prop_scenes = THEMES[theme_key]
    w = TresWriter('EnvironmentTheme', 'res://data/scripts/environment_theme.gd')
    zone_script = w.ext('res://data/scripts/env_zone.gd', 'Script')
    layer_script = w.ext('res://data/scripts/backdrop_layer.gd', 'Script')
    mat = w.ext(f'res://data/environment/materials/{material}.tres')
    facade_refs = ', '.join(f'ExtResource("{w.ext(f"res://data/environment/facades/{f}.tres")}")' for f in facades)
    facade_script = w.ext('res://data/scripts/facade_data.gd', 'Script')
    body = [f'script = ExtResource("{zone_script}")', 'from_tile = 0', f'material = ExtResource("{mat}")',
            f'facades = Array[ExtResource("{facade_script}")]([{facade_refs}])']
    if interior:
        scale = 8 if interior in ('facility_panel', 'hangar_wall', 'steel_plate') else 4
        body += [f'interior = "res://art/environment/materials/{interior}_body.png"', f'interior_scale = {scale}']
    body += [f'hole_chance = {holes}', f'label = "{area.name}"']
    zone = w.sub(body)
    layers = []
    for tex, scroll, bottom in BACKDROP:
        ext = 'png' if tex == 'near_foreground' else 'webp'
        extra = ['tint = Color(1.3, 1.3, 1.4, 1)', 'texture_scale = 4'] if ext == 'webp' else []
        layers.append(w.sub([f'script = ExtResource("{layer_script}")', f'texture = "res://art/environment/backdrop/{tex}.{ext}"'] + extra +
                            [f'scroll_scale = {scroll}', f'bottom_y = {bottom}']))
    sky_sub = w.sub([f'script = ExtResource("{layer_script}")', f'texture = "res://art/environment/backdrop/{sky}.webp"', 'scroll_scale = 0.03',
                     'bottom_y = 300.0', 'texture_scale = 2', 'tint = Color(1.4, 1.35, 1.5, 1)'])
    dirs = ', '.join(json.dumps(SCENE_PROPS % s) for s in prop_scenes)
    res = [f'script = ExtResource("{w.script_id}")',
           f'zones = Array[ExtResource("{zone_script}")]([SubResource("{zone}")])',
           'backdrop = Array[ExtResource("%s")]([%s])' % (layer_script, ', '.join(f'SubResource("{x}")' for x in layers)),
           f'sky = SubResource("{sky_sub}")',
           f'extra_prop_dirs = PackedStringArray({dirs})']
    path = os.path.join(THEME_DIR, f'ch1_{area.id}.tres')
    with open(path, 'w') as f:
        f.write(w.render(res))
    return f'res://data/environment/themes/ch1_{area.id}.tres'


# 每個區域的劇情接點：進場過場、機關頻道播放的場景（劇本在 tools/story/build_ch1_story.py 產生）
STORY = {
    'pawnshop': dict(intro='ch1_c01_open'),
    'warehouse': dict(channels={'watchdog_gate': 'ch1_c11_watchdog'}),
    'pawnshop_dawn': dict(intro='ch1_c14_home'),
}


def write_level(area, theme_key=None, level_id=None, map_name=None, persist=True, **opts):
    """輸出一個區域的地圖、環境主題與 LevelData。level_id／map_name 不同於區域 id 時共用地圖（天亮的當舖）。"""
    level_id = level_id or area.id
    map_name = map_name or area.id
    theme_path = write_theme(area, theme_key or area.id) if opts.pop('theme', True) else opts.pop('theme_path')
    w = TresWriter('LevelData', 'res://data/scripts/level_data.gd')
    legend = []
    used = sorted(area.chars | {c for c in PORTALS if c in area.chars} | set(opts.pop('extra_chars', '')))
    for c in used:
        if c in RES:
            legend.append(f'"{c}": ExtResource("{w.ext(RES[c])}")')
        elif c in DYN_RES:
            legend.append(f'"{c}": ExtResource("{w.ext(DYN_RES[c])}")')
        elif c in PORTALS:
            p = PORTALS[c]
            portal_script = w.ext('res://data/scripts/portal_data.gd', 'Script')
            body = [f'script = ExtResource("{portal_script}")', f'id = &"{p["id"]}"']
            if p['to']:
                body.append(f'target_level = "{p["to"]}"')
                if p.get('target'):
                    body.append(f'target_portal = &"{p["target"]}"')
            if p.get('requires'):
                body.append(f'requires_flag = &"{p["requires"]}"')
            if p.get('locked'):
                body.append(f'locked_text = "{p["locked"]}"')
            if p['mode']:
                body.append(f'mode = {p["mode"]}')
            if p.get('prompt'):
                body.append(f'prompt = "{p["prompt"]}"')
            if p.get('w'):
                body.append(f'width = {p["w"]}')
            if p.get('h'):
                body.append(f'height = {p["h"]}')
            body.append(f'style = "{p.get("style", "door")}"')
            sid = w.sub(body)
            legend.append(f'"{c}": SubResource("{sid}")')
    zone_script = w.ext('res://data/scripts/lighting_zone.gd', 'Script')
    zone_ids = []
    for start, blend, profile in area.zones:
        prof = w.ext(f'res://data/lighting/{profile}.tres')
        zone_ids.append(w.sub([f'script = ExtResource("{zone_script}")', f'start_tile = {start}', f'blend_tiles = {blend}', f'profile = ExtResource("{prof}")']))
    theme = w.ext(theme_path)
    res = [f'script = ExtResource("{w.script_id}")', f'id = &"ch1_{level_id}"', f'display_name = "{opts.pop("display_name", area.name)}"',
           'tile_size = 16', f'height = {H}',
           'legend = Dictionary[String, Resource]({\n' + ',\n'.join(legend) + '\n})' if legend else 'legend = Dictionary[String, Resource]({})',
           'hints = PackedStringArray(' + ', '.join(json.dumps(h, ensure_ascii=False) for h in area.hints) + ')',
           f'chapter = &"{CHAPTER}"',
           f'persistent_world = {"true" if persist else "false"}',
           f'show_chapter_card = {"true" if opts.pop("show_card", False) else "false"}',
           f'environment = ExtResource("{theme}")',
           f'layout_path = "res://data/levels/ch1_{map_name}_map.json"',
           'lighting_zones = Array[ExtResource("%s")]([%s])' % (zone_script, ', '.join(f'SubResource("{z}")' for z in zone_ids))]
    story = STORY.get(level_id, {})
    if story.get('intro'):
        res.append(f'intro_scene = &"{story["intro"]}"')
    if story.get('channels'):
        res.append('channel_scenes = Dictionary[StringName, StringName]({' + ', '.join(f'&"{k}": &"{v}"' for k, v in story['channels'].items()) + '})')
    triggers = [scene for _, scene in sorted(area.triggers)]
    # 天亮的當舖與當舖共用地圖：& 標記還在，晚飯場景已經看過，不會重播。
    res.append('story_triggers = PackedStringArray(' + ', '.join(json.dumps(t) for t in triggers) + ')')
    for key, value in opts.items():
        res.append(f'{key} = {value}')
    path = os.path.join(LEVEL_DIR, f'ch1_{level_id}.tres')
    with open(path, 'w') as f:
        f.write(w.render(res))
    print('wrote', path)


def main():
    write_data_files()
    os.makedirs(LEVEL_DIR, exist_ok=True)
    os.makedirs(THEME_DIR, exist_ok=True)
    areas = [build_pawnshop(), build_rooftop(), build_street(), build_booth_alley(), build_warehouse(), build_lounge(), build_stall()]
    problems = []
    for a in areas:
        problems += a.check()
        start = next(((x, y) for y in range(H) for x in range(a.w) if a.grid.at(x, y) == 'P'), None)
        goals = [(a.grid.at(x, y), (x, y)) for y in range(H) for x in range(a.w)
                 if a.grid.at(x, y) in set(RES) | set(PORTALS) | {'C'} and a.grid.at(x, y) not in ('d', 'a', 'r', 's', 'v', 'W', 'X')]
        problems += reachable(a, start, goals)
    if problems:
        print('\n'.join(problems))
        sys.exit(1)
    write_npc_files()
    write_encounter_files(areas)
    write_design(areas)
    report(areas)
    if '--render' in sys.argv:
        render_overview(areas, os.path.join(ROOT, 'pm', 'ST', 'images'))
    for a in areas:
        extra = {"props": a.props}
        if a.regions:
            extra["regions"] = a.regions
        a.grid.write(a.id, (LEVEL_DIR, f'ch1_{a.id}_map.json'), extra)
    by_id = {a.id: a for a in areas}
    write_level(by_id['pawnshop'], show_card=True, display_name='當舖')
    write_level(by_id['rooftop'])
    write_level(by_id['street'])
    write_level(by_id['booth_alley'])
    write_level(by_id['warehouse'])
    write_level(by_id['lounge'])
    write_level(by_id['stall'])
    # 天亮的當舖：同一張地圖，換光影與進場後結束本章。
    dawn = build_pawnshop()
    dawn.id = 'pawnshop'
    dawn.zones = [(0, 12, 'mezzanine_gray')]
    write_level(dawn, level_id='pawnshop_dawn', map_name='pawnshop', theme=False, theme_path='res://data/environment/themes/ch1_pawnshop.tres',
                display_name='當舖（天亮）', complete_after_intro='true')


if __name__ == '__main__':
    main()
