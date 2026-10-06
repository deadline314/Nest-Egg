#!/usr/bin/env python3
"""第一章「傘」的劇本資料產生器（ST-2、ST-9）：輸出 data/story/ch1_kasa.json 與場景舞台 data/cutscene/stages/ch1_*.json。

台詞來自 design/13-story-v2/SCRIPT_CH01.md（《邊緣行者》式短句）。這個腳本把分鏡表轉成現有的過場動畫資料：
- 動畫過場（animated）：C1-xx，用 BG-11 場景立繪當舞台；超過連續 3 句台詞時自動插入短停頓（過場檢查器的限制）。
- 過場（cinematic）與通訊（radio）：玩法段的對話；通訊每段最多 2 句、過場每段最多 6 句。
- 對話選項、旗標分支與可互動物件的短台詞屬於 ST-3，這裡先用「預設的那一條路」寫成線性場景；場景結束時用 set_flags 設旗標。
- 日文與英文只放★關鍵句（雙關與標誌性台詞）：欄位 ja、en 與 transcreate: true，缺漏時遊戲只顯示中文。
用法：python3 tools/story/build_ch1_story.py
"""
import json
import os

ROOT = os.path.join(os.path.dirname(__file__), '..', '..')
OUT = os.path.join(ROOT, 'data', 'story', 'ch1_kasa.json')
STAGE_DIR = os.path.join(ROOT, 'data', 'cutscene', 'stages')

CHAPTER = {
    "id": "ch1_kasa",
    "title": "第一章　傘",
    "subtitle": "沉港市・下層港區",
    "end_title": "第一章　傘　完",
    "teaser": "下一章　鷺",
}

# 新的講者（凜、老 K 沿用舊檔裡的定義）。頭像先借用現有的圖，之後換成正式立繪。
SPEAKERS = {
    "egret": {"name": "鷺", "color": "#ffb066", "portrait": "res://art/portraits/resident.png"},
    "lamp": {"name": "燈", "color": "#8fe39a", "portrait": "res://art/portraits/wataru.png"},
    "ali": {"name": "阿梨", "color": "#ff8fc0", "portrait": "res://art/portraits/nurse.png"},
    "voice": {"name": "錄音", "color": "#9ad7ff", "portrait": "res://art/portraits/system.png", "formal": True},
}

# ---------------------------------------------------------------------------
# 舞台：BG-11 的場景立繪（1536×864）縮成 0.5 倍鋪滿，腳底線依各張圖的地面位置而定
# ---------------------------------------------------------------------------
# 舞台是 BG-11 的場景立繪（1536×864）縮成 0.5 倍鋪滿（-64,-36 起，涵蓋 -64..704 × -36..396）。
# 立繪裡家具是真實比例，所以角色的縮放要照畫面比例（每個場景不同，量自畫面上的桌椅、櫃台、欄杆高度）；
# 坐姿以量到的座位高度算：y = 座面 + (坐姿髖高 - 骨盆半高) × 縮放（髖高是各骨架坐著時髖部離腳底的高度）。
# 舞台座標除了立繪還有：腳底的地面線、各演員的縮放、預設的鏡頭（對話框在畫面下緣約 22%，所以腳底要落在畫面約 70% 以上）。
STAGES = {
    # 舞台 id: (場景立繪, 底色上, 底色下, 雨, 光暈, 額外圖層)
    'ch1_pawnshop_front': ('pawnshop_front', '#120d09', '#241810', True, [330, 70, 230, '#ffb066'], []),
    'ch1_pawnshop_kitchen': ('pawnshop_kitchen', '#0d1410', '#1b241a', False, [300, 40, 200, '#e8e090'], []),
    'ch1_rooftop': ('rooftop', '#06101f', '#0c1c33', True, [560, 40, 200, '#ffd77a'], []),
    'ch1_revival_room': ('revival_room', '#d8e4ee', '#f4f8fb', False, [320, 60, 260, '#ffffff'], []),
    'ch1_revival_lounge': ('revival_lounge', '#160812', '#2a1022', False, [320, 120, 240, '#ff3fa4'], []),
    'ch1_dawn_noodle_stall': ('dawn_noodle_stall', '#1a2230', '#3a4658', True, [330, 140, 220, '#cfe0ff'], 'stall'),
}
# 地面線（腳底 y）與座位（座面 y；沒有就是 None）。
FLOOR = {
    'ch1_pawnshop_front': 348, 'ch1_pawnshop_kitchen': 304, 'ch1_rooftop': 262,
    'ch1_revival_room': 280, 'ch1_revival_lounge': 262, 'ch1_dawn_noodle_stall': 300,
}
# 演員縮放：{舞台: {骨架: 縮放}}。同一個舞台上的人高度大致一致。
SCALE = {
    'ch1_pawnshop_front': {'rin': 3.4, 'old_k': 3.7},
    'ch1_pawnshop_kitchen': {'rin': 3.8, 'old_k': 4.2},
    'ch1_rooftop': {'rin': 2.2, 'night_worker': 2.3},
    'ch1_revival_room': {'rin': 2.5},
    'ch1_revival_lounge': {'rin': 2.4, 'nurse': 2.8},
    'ch1_dawn_noodle_stall': {'rin': 1.7, 'nurse': 1.9},
}
# 各骨架坐姿時髖部離腳底的高度（縮放 1 時）與骨盆半高。數字用 `godot --headless --path . res://tools/rig_pose_report.tscn` 量（NPC 動畫器的坐姿用 IK 把腳平放在地上，髖高由資料的比例決定）；換了坐姿資料要重量。
HIP_SIT = {'rin': 17.41, 'old_k': 16.87, 'nurse': 16.35, 'night_worker': 16.0, 'resident': 15.98}
PELVIS = 3.5


def actor_scale(stage_id, kind):
    return SCALE[stage_id][kind]


def sit_y(stage_id, kind, seat_y):
    """坐在座面 seat_y 上時，腳底（演員原點）的 y。"""
    return round(seat_y + (HIP_SIT[kind] - PELVIS) * actor_scale(stage_id, kind), 1)


def stall_layers(scale):
    """宵夜麵攤的立繪只有街道：麵攤、桌子與燈籠用場景專屬物件的貼圖補上。
    每個物件的邏輯大小（w×h，世界像素，與關卡裡的道具資料一致）乘上演員的縮放就是舞台上的大小；
    貼圖的解析度各不相同（麵攤 6 倍、其他 10 倍），所以縮放要用「邏輯寬 ÷ 貼圖寬」算，不能寫死倍率。"""
    from PIL import Image
    d = 'res://art/environment/scene_props/dawn_noodle_stall/dawn_noodle_stall__%s.png'
    disk = os.path.join(ROOT, 'art', 'environment', 'scene_props', 'dawn_noodle_stall', 'dawn_noodle_stall__%s.png')
    floor = FLOOR['ch1_dawn_noodle_stall']

    def sprite(name, x, w, h, lift=0.0):
        tex_w = Image.open(disk % name).size[0]
        return {"kind": "sprite", "path": d % name, "pos": [round(x, 1), round(floor - (h + lift) * scale, 1)],
                "scale": round(scale * w / tex_w, 4), "filter": "linear", "glow": True}
    # 燈籠（連繩）掛在攤車頂的前緣，下緣高過頭頂（lift 是世界像素，也要乘上縮放）。
    return [sprite('ali_noodle_cart', 395, 58.1, 66.0), sprite('noodle_bowls_table', 335, 30.4, 25.5),
            sprite('hanging_lantern', 405, 16.9, 33.0, 30.0)]


def write_stage(stage_id, scene, top, bottom, rain, glow, extra):
    layers = [
        {"kind": "gradient", "top": top, "bottom": bottom, "parallax": 0.0},
        {"kind": "sprite", "path": f"res://art/environment/scenes/{scene}.webp", "pos": [-64, -36.0], "scale": 0.5,
         "filter": "linear"},  # 不能開 life：窗光閃爍會把整張背景切成忽明忽暗的方塊
        {"kind": "glow", "pos": [glow[0], glow[1]], "radius": glow[2], "color": glow[3], "intensity": 0.7, "additive": True,
         "alpha": 0.35, "pulse": 0.06, "pulse_depth": 0.2},
    ]
    if extra == 'stall':
        scale = SCALE[stage_id]['rin']
        layers.extend(stall_layers(scale))
        # 麵攤旁的小板凳：座面在骨盆下方（坐姿的髖高決定它的高度）。
        seat = FLOOR[stage_id] - (HIP_SIT['rin'] - PELVIS) * scale
        layers.append({"kind": "poly", "points": [[290, seat], [320, seat], [320, seat + 3], [290, seat + 3]], "color": "#6a4a30", "parallax": 1.0})
        layers.append({"kind": "poly", "points": [[294, seat + 3], [297, seat + 3], [297, FLOOR[stage_id]], [294, FLOOR[stage_id]]], "color": "#4a3320", "parallax": 1.0})
        layers.append({"kind": "poly", "points": [[313, seat + 3], [316, seat + 3], [316, FLOOR[stage_id]], [313, FLOOR[stage_id]]], "color": "#4a3320", "parallax": 1.0})
    if rain:
        layers.append({"kind": "rain", "depth": "front", "opacity": 0.35})
    layers.append({"kind": "motes", "count": 24, "color": "#cfe0ff", "opacity": 0.3, "area": [0, 30, 640, 280], "drift": [2, -3], "size": 1.1, "seed": 7})
    layers.append({"kind": "grain", "amount": 50, "opacity": 0.05, "depth": "front"})
    data = {"camera": {"pos": [320, 180], "zoom": 1.0}, "floor": FLOOR[stage_id], "layers": layers}
    with open(os.path.join(STAGE_DIR, f'{stage_id}.json'), 'w') as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write('\n')


# ---------------------------------------------------------------------------
# 步驟
# ---------------------------------------------------------------------------

def say(speaker, text, ja=None, en=None, style=None):
    step = {"do": "say", "speaker": speaker, "text": text}
    if style:
        step["style"] = style
    if ja or en:
        step["ja"] = ja or ""
        step["en"] = en or ""
        step["transcreate"] = True
    return step


def wait(t=0.5):
    return {"do": "wait", "time": t}


def cam(x, y, zoom=1.0, t=1.2, wait_for=False):
    step = {"do": "camera", "pos": [x, clamp_camera_y(y, zoom)], "zoom": zoom, "time": t}
    if wait_for:
        step["wait"] = True
    return step


def actor(ident, kind, x, y, facing=1, scale=2.0, speaker=None, pose=None, loop=None, weapon=""):
    step = {"do": "actor", "id": ident, "kind": kind, "pos": [x, y], "facing": facing, "scale": scale, "weapon": weapon}
    if speaker:
        step["speaker"] = speaker
    if pose:
        step["pose"] = pose
    if loop:
        step["loop"] = loop
    return step


def pose(ident, name, loop=None):
    step = {"do": "pose", "id": ident, "pose": name}
    if loop is not None:
        step["loop"] = loop
    return step


def move(ident, x, y, t=1.5, wait_for=True, pose_name=None, then=None):
    """then：走到之後的姿勢（預設站著）；坐下的移動要寫 then='sit'，不然到了又站起來。"""
    step = {"do": "move", "id": ident, "to": [x, y], "time": t}
    if then:
        step["then"] = then
    if wait_for:
        step["wait"] = True
    if pose_name:
        step["pose"] = pose_name
    return step


def face(ident, direction):
    return {"do": "face", "id": ident, "dir": direction}


def fx(kind, t=0.5, **kw):
    step = {"do": "fx", "kind": kind, "time": t}
    step.update(kw)
    return step


def sfx(ident, volume=-8):
    return {"do": "sfx", "id": ident, "volume": volume}


def fade(to=1.0, t=0.9):
    return {"do": "fade", "to": to, "time": t}


# 對話框蓋住畫面下緣約 25%（框頂約在 266／360 處）：演員的腳底在畫面上的位置要在這條線之上，否則腳被框蓋住。
# 鏡頭的畫面中心 y 因此不能太靠上：腳底畫面 y = 180 + (地面線 − 鏡頭 y) × 縮放 ≤ FEET_MAX_Y。
FEET_MAX_Y = 262.0
_camera_floor = [None]


def clamp_camera_y(y, zoom):
    """鏡頭中心 y 的下限：讓目前舞台的腳底線落在對話框之上（沒有登記地面線的舞台不限制）。"""
    floor = _camera_floor[0]
    if floor is None:
        return y
    return max(y, round(floor - (FEET_MAX_Y - 180.0) / zoom, 1))


def stage(stage_id, x=320, y=180, zoom=1.0, fade_in=1.2):
    _camera_floor[0] = FLOOR.get(stage_id)
    return {"do": "scene", "id": stage_id, "pos": [x, clamp_camera_y(y, zoom)], "zoom": zoom, "fade": fade_in}


def narrate(lines, t=2.4):
    return {"do": "narrate", "lines": lines, "time": t}


def title(text, sub, t=2.6, color="#35e0ff"):
    return {"do": "title", "text": text, "sub": sub, "time": t, "color": color}


def letterbox(on=True, t=0.6):
    return {"do": "letterbox", "on": on, "time": t}


def spaced(steps):
    """連續台詞超過 3 句時，自動插入短停頓（過場檢查器的限制）。"""
    out = []
    run = 0
    for step in steps:
        if step["do"] == "say":
            if run >= 3:
                out.append(wait(0.35))
                run = 0
            run += 1
        else:
            run = 0
        out.append(step)
    return out


SCENES = {}
RESPAWN = []


def animated(scene_id, steps, then=None, flags=None):
    scene = {"mode": "animated"}
    if then:
        scene["then"] = then
    if flags:
        scene["set_flags"] = flags
    scene["steps"] = spaced(steps)
    SCENES[scene_id] = scene


def lines_scene(scene_id, mode, lines, then=None, flags=None):
    scene = {"mode": mode}
    if then:
        scene["then"] = then
    if flags:
        scene["set_flags"] = flags
    scene["lines"] = [{"speaker": s, "text": t} for s, t in lines]
    SCENES[scene_id] = scene


# ---------------------------------------------------------------------------
# 序幕與當舖（H1）
# ---------------------------------------------------------------------------

def build():
    # C1-00 序幕：雨，水位三點二
    animated('ch1_c00_prologue', [
        {"do": "scene", "id": "rainy_harbor", "pos": [320, 330], "fade": 1.8},
        letterbox(True, 0.8),
        wait(0.6),
        narrate(["天穹氣象台提醒您", "今晚降雨持續", "港區水位三點二公尺，持續上升"], 2.6),
        cam(320, 150, 1.0, 4.5),
        wait(3.0),
        fx('lightning', 0.6),
        cam(320, -10, 1.0, 3.5),
        wait(2.2),
        fx('lightning', 0.8),
        title("傘", "かさ　Kasa", 2.8),
        fade(1.0, 1.0),
    ], then='ch1_c01_shop')

    # C1-01 當舖開場：水位、差事、一成照抽、保費
    st = 'ch1_pawnshop_front'
    y = FLOOR[st]
    animated('ch1_c01_shop', [
        stage(st, 320, 250, 1.0, 1.4),
        actor('rin', 'rin', 385, y, -1, scale=actor_scale(st, 'rin'), pose='squat'),
        actor('k', 'old_k', 175, y, 1, scale=actor_scale(st, 'old_k'), speaker='old_k', loop='wipe_hands'),
        sfx('pickup', -16),
        wait(0.8),
        say('old_k', "水位又上來了啦。"),
        say('rin', "三點二。"),
        say('old_k', "你怎麼知道？"),
        pose('rin', 'idle'),
        wait(0.6),
        say('rin', "牆上寫的。"),
        say('old_k', "啊。對。牆上有寫。"),
        wait(0.5),
        say('old_k', "鷺等一下來，說有差事。"),
        say('rin', "上面指定的？"),
        wait(0.9),
        say('old_k', "上面指定的。我看過了，倉庫而已。"),
        say('rin', "一成照抽。"),
        say('old_k', "照抽。保費嘛。你自己簽的。"),
        say('rin', "嗯。"),
        wait(0.4),
        say('old_k', "去後面試試手感。那把子彈用不完。"),
        fade(1.0, 0.8),
    ])

    # C1-02 晚飯：四十、紅蘿蔔、幾次了（凜坐左邊的椅子，老 K 從爐子走過來坐右邊的）
    st = 'ch1_pawnshop_kitchen'
    seat = 240
    animated('ch1_c02_dinner', [
        stage(st, 320, 240, 1.0, 1.2),
        actor('rin', 'rin', 196, sit_y(st, 'rin', seat), 1, scale=actor_scale(st, 'rin'), pose='sit'),
        actor('k', 'old_k', 110, FLOOR[st], 1, scale=actor_scale(st, 'old_k'), speaker='old_k', loop='stir'),
        wait(1.0),
        say('old_k', "今天的。"),
        move('k', 371, FLOOR[st], 3.0, True, 'walk'),
        face('k', -1),
        move('k', 371, sit_y(st, 'old_k', seat), 0.05, True, 'sit', then='sit'),
        pose('k', 'sit', loop=''),
        sfx('pickup', -8),
        say('rin', "四十。"),
        say('old_k', "收到。"),
        wait(0.8),
        say('old_k', "我切很細了啊。"),
        say('rin', "還是看得到。"),
        say('old_k', "看得到才叫紅蘿蔔啊。"),
        wait(1.4),
        say('old_k', "幾次了？"),
        say('rin', "九。"),
        say('old_k', "九啊。"),
        wait(0.8),
        say('rin', "別人兩三倍。我還好。"),
        say('old_k', "喔。"),
        fade(1.0, 0.9),
    ], flags=['ch1_dinner_done'])

    # C1-03 屋頂：鷺的差事（選項「問她今晚的事」的預設路線，選項屬於 ST-3）
    st = 'ch1_rooftop'
    y = FLOOR[st]
    egret = lambda: actor('egret', 'night_worker', 548, y, -1, scale=actor_scale(st, 'night_worker'), speaker='egret', pose='lean')  # noqa: E731
    animated('ch1_c03a_roof', [
        stage(st, 430, 205, 1.5, 1.4),
        egret(),
        actor('rin', 'rin', 150, y, 1, scale=actor_scale(st, 'rin')),
        move('rin', 430, y, 3.2, True, 'walk'),
        say('egret', "小鬼。遲到三分鐘。", style='shout'),
        sfx('pickup', -10),
        say('rin', "老 K 在吃飯。"),
        say('egret', "那老頭永遠在吃飯。聽好，差事很簡單。"),
        wait(0.9),
        say('egret', "地點，碼頭倉庫。目標，保險箱裡一片資料盤。", ja="場所は埠頭の倉庫。狙いは金庫の中のディスク一枚。", en="Dock warehouse. Target: one disk in a safe."),
        say('egret', "有隻看門狗守著。兩條腿，一條尾巴，脾氣不好。"),
        say('rin', "誰要的。"),
        wait(0.5),
        say('egret', "上面。我不問，你也別問。"),
        say('rin', "你呢。"),
        say('egret', "我今晚有事。"),
        wait(1.0),
        say('rin', "什麼事。"),
        say('egret', "…看一個人。"),
        say('rin', "誰。"),
        say('egret', "下次講。喝茶。"),
    ], then='ch1_c03b_roof')
    animated('ch1_c03b_roof', [
        stage(st, 430, 205, 1.5, 0.0),
        egret(),
        actor('rin', 'rin', 430, y, 1, scale=actor_scale(st, 'rin')),
        say('egret', "你一個人去。不要一個人死，浪費。", ja="一人で死ぬなよ、もったいない。", en="Don't die alone. Waste of a good death."),
        wait(0.8),
        say('egret', "開玩笑啦。死了還不是照樣喝酒。", ja="死んだって、どうせ酒は飲めるさ。", en="You can still drink after."),
        cam(430, 190, 2.2, 1.4),
        narrate(["晴岸　480,000", "已存 27,400"], 2.6),
        say('egret', "欸，晴岸？你要買房？"),
        say('rin', "還早。"),
        wait(0.5),
        say('egret', "給誰？"),
        say('rin', "一個人。"),
        say('egret', "喔——老頭子的喔？"),
        wait(0.6),
        say('rin', "別說。"),
        say('egret', "好好好。嘴巴縫起來。"),
        cam(480, 190, 1.5, 1.6),
        say('egret', "看到那座塔沒有？上面有太陽。真的太陽。", ja="あの塔、見える？上には太陽がある。本物の。", en="See that tower? There's sun up there. Real sun."),
        say('rin', "聽說。"),
        wait(0.5),
        say('egret', "你要帶他去喔。"),
        fade(1.0, 0.9),
    ], flags=['ch1_heard_brief'])

    # C1-04 出門：帶傘了嗎
    st = 'ch1_pawnshop_front'
    y = FLOOR[st]
    animated('ch1_c04_out', [
        stage(st, 360, 250, 1.0, 1.2),
        actor('rin', 'rin', 300, y, 1, scale=actor_scale(st, 'rin')),
        actor('k', 'old_k', 175, y, 1, scale=actor_scale(st, 'old_k'), speaker='old_k', loop='wipe_hands'),
        move('rin', 540, y, 2.6, True, 'walk'),
        say('old_k', "帶傘了嗎？", ja="傘、持った？", en="Got your kasa?"),
        say('rin', "下面本來就是水。", ja="下はもともと水だよ。", en="It's water down there anyway."),
        say('old_k', "喔。"),
        wait(0.8),
        fx('lightning', 0.4),
        fade(1.0, 0.9),
    ], flags=['ch1_out_done'])

    # G1-06 街道：燈登場與戰鬥提示（通訊／過場）
    lines_scene('ch1_g06_lamp', 'cinematic', [
        ('lamp', "喂喂，一、二、三。聽得到嗎？"),
        ('rin', "聽得到。"),
        ('lamp', "你耳機又有雜音。我說過那顆喇叭該換了。"),
        ('rin', "你想換你付。"),
        ('lamp', "哈。我今天先幫你看路。市集被收帳人封了，走碼頭那邊。"),
    ])
    lines_scene('ch1_g06_tip_slide', 'radio', [
        ('lamp', "按閃躲，往旁邊滑。剛按下去那一瞬間，子彈打不到你。"),
    ])
    lines_scene('ch1_g06_tip_blade', 'radio', [
        ('lamp', "貼身的時候用刀，省子彈。"),
        ('lamp', "雖然你的子彈用不完。習慣一下，早晚會換槍。"),
    ])
    lines_scene('ch1_g06_tip_collector', 'radio', [
        ('lamp', "前面穿黃衣服的是收帳人。比保全慢，比保全痛。"),
    ])
    lines_scene('ch1_g06_clear', 'radio', [
        ('lamp', "好。倉庫在碼頭盡頭，我在你耳邊。"),
    ])

    # G1-07 倉庫：看門狗
    lines_scene('ch1_g07_dog', 'radio', [
        ('lamp', "牠在大廳最裡面，睡著。"),
        ('rin', "多大。"),
    ])
    # C1-11 看門狗戰完（隔牆升起時播出）
    lines_scene('ch1_c11_watchdog', 'cinematic', [
        ('lamp', "只有一頭。"),
        ('rin', "什麼只有一頭。"),
        ('lamp', "看門狗。別的紀錄裡，它有三個頭。"),
    ])
    # G1-10 水位謎：以死解謎
    lines_scene('ch1_g10_pit', 'cinematic', [
        ('rin', "站上去，水淹過頭，我就死了。"),
        ('lamp', "對。"),
        ('rin', "你要我淹死。"),
        ('lamp', "我要你死一次。差別很大。"),
    ], then='ch1_g10_pit2')
    lines_scene('ch1_g10_pit2', 'cinematic', [
        ('rin', "閘門會一直開著？"),
        ('lamp', "世界不會因為你死了就重來。你死了，水還是水。"),
        ('rin', "所以死是工具。"),
        ('lamp', "你學得真快。"),
    ])
    lines_scene('ch1_g10_cross', 'radio', [
        ('rin', "這很方便。"),
        ('lamp', "…對。很方便。"),
    ])
    lines_scene('ch1_g10_disk', 'cinematic', [
        ('lamp', "那是收帳人的帳。上面為什麼要這個？"),
        ('rin', "不知道。"),
        ('lamp', "你不好奇？"),
        ('rin', "錢到了就行。"),
    ])

    # C1-09 復原室醒來（第一次死亡後，重生時播出）：凜坐在檢查台的邊緣，腿垂下來
    st = 'ch1_revival_room'
    animated('ch1_c09_wake', [
        stage(st, 316, 205, 1.4, 1.0),
        actor('rin', 'rin', 316, sit_y(st, 'rin', 196), 1, scale=actor_scale(st, 'rin'), pose='sit', speaker='rin'),
        fx('flash', 0.6),
        wait(1.2),
        say('rin', "…幹。"),
        wait(1.0),
        say('lamp', "歡迎回來。", ja="おかえり。", en="Welcome back."),
        say('rin', "你的聲音跟終端很像。", ja="ターミナルの声、お前に似てるな。", en="You sound like the terminal."),
        wait(0.9),
        say('lamp', "港區少年的聲音，長得都差不多吧。"),
        say('rin', "騙人。"),
        wait(1.1),
        say('lamp', "你要不要先喝茶？"),
        pose('rin', 'idle'),
        wait(0.8),
        say('rin', "誰放的。"),
        say('lamp', "診所的人吧。每次都有。"),
        wait(0.6),
        fade(1.0, 1.2),
    ])
    RESPAWN.append({"scene": "ch1_c09_wake", "min_deaths": 1})

    # C1-12 復原館：阿梨初見（基底層，不露骨）：凜坐吧台的高腳椅，阿梨站在吧台右端
    st = 'ch1_revival_lounge'
    y = FLOOR[st]
    stool = 205
    animated('ch1_c12_lounge', [
        stage(st, 330, 205, 1.4, 1.4),
        actor('ali', 'nurse', 430, y, -1, scale=actor_scale(st, 'nurse'), speaker='ali', loop='wipe_hands'),
        actor('rin', 'rin', 520, y, -1, scale=actor_scale(st, 'rin')),
        move('rin', 300, y, 2.4, True, 'walk'),
        face('rin', 1),
        move('rin', 300, sit_y(st, 'rin', stool), 0.05, True, 'sit', then='sit'),
        say('ali', "今天第幾次？"),
        say('rin', "一。"),
        say('ali', "一？才一次？"),
        say('ali', "那你運氣好。吃什麼？復原餐，還是酒？"),
        say('rin', "都要。"),
        wait(0.8),
        say('ali', "您貴姓？"),
        say('rin', "凜。"),
        say('ali', "阿梨。梨子的梨。別分梨吃，會分開。", ja="梨って書いて、なし。縁起悪いって言われるけどね、『無し』に通じるから。", en="Pear. Like the fruit. Like 'a pair'—somebody's other half, for the night."),
        say('rin', "好。"),
        wait(1.0),
        say('rin', "這湯怎麼是甜的？"),
        say('ali', "放了一顆梨。"),
        wait(1.2),
        say('ali', "我下班了。"),
        say('ali', "這個不是工作。"),
        say('rin', "多少。"),
        wait(0.9),
        say('ali', "放著吧。"),
        fade(1.0, 1.2),
    ])

    # C1-13 天亮：宵夜（選項的預設路線：留下來吃，旗標 knows_ali_address 預設為真）
    st = 'ch1_dawn_noodle_stall'
    y = FLOOR[st]
    animated('ch1_c13_noodle', [
        stage(st, 410, 238, 1.8, 1.6),
        actor('ali', 'nurse', 525, y, -1, scale=actor_scale(st, 'nurse'), speaker='ali', loop='stir'),
        actor('rin', 'rin', 305, y, 1, scale=actor_scale(st, 'rin'), pose='sit'),
        wait(1.4),
        say('ali', "吃。"),
        say('rin', "多少。"),
        say('ali', "不收錢。"),
        wait(0.6),
        say('rin', "那我欠你。", ja="じゃあ、借りだね。", en="Then I owe you."),
        say('ali', "那就欠著。", ja="ツケにしとく。", en="Put it on the tab."),
        wait(1.6),
        say('ali', "我最近被收帳人盯上了。"),
        say('rin', "欠多少。"),
        say('ali', "錢不是問題。他們一直在加。"),
        wait(0.6),
        say('rin', "你住哪。"),
        say('ali', "市集後面，三樓。敲三下，再敲兩下，是我。"),
        say('rin', "我不去。"),
        wait(0.5),
        say('ali', "沒要你去。我只是告訴你。"),
        fade(1.0, 1.2),
    ], flags=['knows_ali_address', 'ch1_noodle_done'])

    # C1-14 回家：水燒乾了、空眼神（老 K 在爐子前，凜從門口走進來）
    st = 'ch1_pawnshop_kitchen'
    y = FLOOR[st]
    animated('ch1_c14_home', [
        stage(st, 320, 240, 1.0, 1.4),
        actor('rin', 'rin', 575, y, -1, scale=actor_scale(st, 'rin')),
        actor('k', 'old_k', 120, y, -1, scale=actor_scale(st, 'old_k'), speaker='old_k'),
        move('rin', 330, y, 2.6, True, 'walk'),
        say('rin', "老 K。"),
        face('k', 1),
        say('old_k', "啊。"),
        say('old_k', "水燒乾了喔。"),
        wait(0.5),
        say('rin', "是。"),
        say('old_k', "老了。"),
        say('old_k', "我去裝個水。"),
        move('k', 500, y, 2.8, True, 'walk'),
        sfx('switch', -10),
        wait(1.4),
        face('k', -1),
        move('k', 190, y, 2.8, True, 'walk'),
        cam(190, 190, 1.9, 1.6),
        wait(3.0),
        say('old_k', "…你什麼時候回來的？"),
        say('rin', "剛剛。"),
        say('old_k', "喔。水燒好了。"),
        wait(1.4),
        fade(1.0, 1.4),
    ], flags=['ch1_home_done'])


def main():
    os.makedirs(STAGE_DIR, exist_ok=True)
    for stage_id, (scene, top, bottom, rain, glow, extra) in STAGES.items():
        write_stage(stage_id, scene, top, bottom, rain, glow, extra)
    build()
    data = {"chapter": CHAPTER, "speakers": SPEAKERS, "respawn_scenes": RESPAWN, "scenes": SCENES}
    with open(OUT, 'w') as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write('\n')
    print('wrote', OUT, f'({len(SCENES)} scenes)')


if __name__ == '__main__':
    main()
