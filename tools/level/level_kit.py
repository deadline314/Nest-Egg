"""關卡地圖產生器共用工具：格子網格、摆放、輸出分段 JSON、可通行檢查。

各章的產生器（build_level_XX.py）只需要描述「擺什麼」，輸出格式與檢查在這裡統一。
地圖檔本身是可直接手改的資料；產生器是方便大幅調整版面後重新產生的「設計稿」。
"""
import json
import os

TILE = 16
PLAYER_JUMP_TILES = 5  # 玩家跳躍約 88px ≈ 5.5 格
MECH_JUMP_TILES = 3    # 機甲跳躍約 54px ≈ 3.4 格
MAX_PIT_TILES = 3
SEGMENT_WIDTH = 50
HEADROOM = 3           # 站得下玩家需要的淨空格數


class Grid:
    def __init__(self, width, height):
        self.w, self.h = width, height
        self.g = [['.'] * width for _ in range(height)]

    def put(self, x, y, c):
        self.g[y][x] = c

    def fill(self, x0, x1, y0, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.g[y][x] = c

    def empty(self, x, y):
        return self.g[y][x] == '.'

    def at(self, x, y):
        return self.g[y][x]

    def rows(self):
        return [''.join(r) for r in self.g]

    def ascii(self, x0=0, x1=None):
        x1 = self.w if x1 is None else x1
        return '\n'.join(''.join(r[x0:x1]) for r in self.g)

    def surface(self, x, ignore_chars=('#',)):
        """第 x 欄的可站立地面（列）：最上面一個實心格，上方至少有 HEADROOM 格非實心；沒有回傳 None。"""
        for y in range(self.h):
            if self.g[y][x] != '#':
                continue
            if y >= HEADROOM and all(self.g[y - k][x] != '#' for k in range(1, HEADROOM + 1)):
                return y
        return None

    def check_route(self, allow_step_columns=()):
        """沿主要地面檢查：高度變化不能超過玩家跳躍能力、坑不能太寬。回傳問題清單。
        allow_step_columns：升降梯所在的欄範圍 [(x0, x1)]，這些範圍內的高度差由升降梯負責，不檢查。"""
        problems = []
        prev = self.surface(1)
        gap = 0
        for x in range(2, self.w - 1):
            s = self.surface(x)
            if s is None or s >= self.h - 1:
                gap += 1
                continue
            if gap > MAX_PIT_TILES:
                problems.append(f"col {x}: 坑寬 {gap} 格，機甲跳不過")
            gap = 0
            skip = any(a <= x <= b for a, b in allow_step_columns)
            if not skip and prev is not None and prev - s > PLAYER_JUMP_TILES:
                problems.append(f"col {x}: 往上 {prev - s} 格，玩家跳不上去")
            prev = s
        return problems

    def write(self, name, path_parts, extra=None):
        """extra：額外寫進 JSON 的欄位（props 道具清單、regions 材質覆蓋區）。"""
        rows = self.rows()
        segments = [[r[i:i + SEGMENT_WIDTH] for r in rows] for i in range(0, self.w, SEGMENT_WIDTH)]
        path = os.path.join(*path_parts)
        with open(path, 'w', encoding='utf-8') as f:
            f.write('{\n  "segments": [\n')
            for si, seg in enumerate(segments):
                f.write('    [\n' + ',\n'.join('      "' + r + '"' for r in seg) + '\n    ]' + (',' if si < len(segments) - 1 else '') + '\n')
            f.write('  ]')
            for key, value in (extra or {}).items():
                f.write(',\n  "' + key + '": [\n' + ',\n'.join('    ' + json.dumps(v, ensure_ascii=False) for v in value) + '\n  ]')
            f.write('\n}\n')
        json.load(open(path))
        print(f"{name}: {self.w}x{self.h} written")
