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
DEATH_SCENES = []


def animated(scene_id, steps, then=None, flags=None, budget=None):
    """budget：預估秒數上限（過場檢查器會估計並比對，見 CutsceneChecker.estimate_seconds）。"""
    scene = {"mode": "animated"}
    if budget:
        scene["budget"] = budget
    if then:
        scene["then"] = then
    if flags:
        scene["set_flags"] = flags
    scene["steps"] = spaced(steps)
    SCENES[scene_id] = scene


def lines_scene(scene_id, mode, lines, then=None, flags=None, bark=False):
    """mode：radio（通訊面板）、bubbles（地圖氣泡，bark＝戰鬥短句 ≤10 字）、dialogue（人物對話，玩家主動）、cinematic。"""
    scene = {"mode": mode}
    if bark:
        scene["bark"] = True
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
    # ---------------------------------------------------------------------
    # 過場 1／3：開場（≤20 秒）：雨、水位、老 K、差事、一成照抽。其他劇情都在地圖上（氣泡、廣播、人物對話）。
    # 設計與逐窗口表見 design/13-story-v2/CH01_NARRATIVE_V2.md。
    # ---------------------------------------------------------------------
    st = 'ch1_pawnshop_front'
    y = FLOOR[st]
    animated('ch1_c01_open', [
        {"do": "scene", "id": "rainy_harbor", "pos": [320, 330], "fade": 1.0},
        narrate(["港區水位三點二公尺，持續上升"], 1.6),
        fx('lightning', 0.5),
        title("傘", "かさ　Kasa", 1.8),
        stage(st, 320, 250, 1.0, 1.0),
        actor('rin', 'rin', 385, y, -1, scale=actor_scale(st, 'rin'), pose='squat'),
        actor('k', 'old_k', 175, y, 1, scale=actor_scale(st, 'old_k'), speaker='old_k', loop='wipe_hands'),
        sfx('pickup', -16),
        wait(0.4),
        say('old_k', "水位又上來了。鷺等一下來，有差事。"),
        pose('rin', 'idle'),
        say('rin', "上面指定的？一成照抽。"),
        say('old_k', "照抽。保費嘛，你自己簽的。去後面試試手感。"),
        fade(1.0, 0.8),
    ], budget=20.0)

    # 晚飯（廚房，進門就開始）：老 K 站在桌邊。氣泡不鎖操作；說完才寫旗標，樓梯才會開（出入口 S）。
    lines_scene('ch1_b_dinner', 'bubbles', [
        ('old_k', "今天的。"),
        ('rin', "四十。"),
        ('old_k', "我切很細了啊。"),
        ('rin', "還是看得到。"),
    ], flags=['ch1_dinner_done'])
    lines_scene('ch1_t_oldk_1', 'dialogue', [
        ('old_k', "幾次了？"),
        ('rin', "九。"),
        ('old_k', "九啊。"),
        ('rin', "別人兩三倍。我還好。"),
        ('old_k', "喔。吃飯。"),
    ])
    lines_scene('ch1_t_oldk_2', 'dialogue', [
        ('old_k', "記得回來吃飯。"),
        ('rin', "嗯。"),
        ('old_k', "路上小心。水大。"),
    ])

    # 老 K 對死亡的反應（累計死亡 1 次、4 次以上時換句子）
    lines_scene('ch1_t_oldk_d1', 'dialogue', [
        ('old_k', "…又死了？"),
        ('rin', "一次。"),
        ('old_k', "水燒好了。吃完再去。"),
    ])
    lines_scene('ch1_t_oldk_d4', 'dialogue', [
        ('old_k', "這個月第幾次了？"),
        ('rin', "別數。"),
        ('old_k', "我數。我替你數。"),
    ])

    # 屋頂：鷺在等。到達時氣泡，差事是玩家主動的人物對話（說完旗標 ch1_heard_brief，前門才開）。
    lines_scene('ch1_b_roof', 'bubbles', [
        ('egret', "小鬼。遲到三分鐘。"),
        ('rin', "老 K 在吃飯。"),
        ('egret', "那老頭永遠在吃飯。"),
    ])
    lines_scene('ch1_t_egret_1', 'dialogue', [
        ('egret', "地點，碼頭倉庫。目標，保險箱裡一片資料盤。"),
        ('egret', "有隻看門狗守著。兩條腿，一條尾巴，脾氣不好。"),
        ('rin', "誰要的。"),
        ('egret', "上面。我不問，你也別問。"),
        ('rin', "你呢。"),
        ('egret', "我今晚有事。…看一個人。"),
        ('egret', "你一個人去。不要一個人死，浪費。開玩笑啦。"),
        ('egret', "看到那座塔沒有？上面有太陽。真的太陽。"),
    ], flags=['ch1_heard_brief'])
    lines_scene('ch1_t_egret_2', 'dialogue', [
        ('egret', "欸，晴岸？你要買房？"),
        ('rin', "還早。"),
        ('egret', "給誰？"),
        ('rin', "一個人。"),
        ('egret', "喔——老頭子的喔？"),
        ('rin', "別說。"),
        ('egret', "好好好。嘴巴縫起來。你要帶他去喔。"),
    ])

    # 街道：出門的獨白、燈的廣播與戰鬥提示（廣播不鎖操作）
    lines_scene('ch1_b_street_in', 'bubbles', [
        ('rin', "老 K 每次都問：帶傘了嗎。"),
        ('rin', "下面本來就是水。"),
    ])
    lines_scene('ch1_g06_lamp', 'radio', [
        ('lamp', "喂喂，一、二、三。聽得到嗎？市集被收帳人封了，走碼頭那邊。"),
        ('rin', "聽得到。"),
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
    # 鎖場開始時凜的戰鬥短句（≤10 字、≤2 句）
    lines_scene('ch1_k_plaza', 'bubbles', [('rin', "路封了。")], bark=True)
    lines_scene('ch1_k_blockade', 'bubbles', [('rin', "收帳人。")], bark=True)
    lines_scene('ch1_k_vault', 'bubbles', [('rin', "有人守著。")], bark=True)
    lines_scene('ch1_k_walkway', 'bubbles', [('rin', "上面有人。")], bark=True)

    # 倉庫：看門狗、水位謎、保險箱（都是廣播或氣泡）
    lines_scene('ch1_g07_dog', 'radio', [
        ('lamp', "牠在大廳最裡面，睡著。"),
        ('rin', "多大。"),
    ])
    lines_scene('ch1_c11_watchdog', 'radio', [
        ('lamp', "看門狗只有一頭。別的紀錄裡，牠有三個頭。"),
        ('rin', "…什麼紀錄。"),
    ])
    lines_scene('ch1_g10_pit', 'radio', [
        ('rin', "站上去，水淹過頭，我就死了。"),
        ('lamp', "對。我要你死一次。差別很大。"),
    ])
    lines_scene('ch1_g10_pit2', 'radio', [
        ('rin', "閘門會一直開著？"),
        ('lamp', "世界不會因為你死了就重來。死是工具。"),
    ])
    lines_scene('ch1_g10_cross', 'radio', [
        ('rin', "這很方便。"),
        ('lamp', "…對。很方便。"),
    ])
    lines_scene('ch1_g10_disk', 'radio', [
        ('lamp', "那是收帳人的帳。上面為什麼要這個？"),
        ('rin', "不知道。錢到了就行。"),
    ])

    # 過場 2／3：診間醒來（第一次死亡後、重生前播出，≤45 秒）：講清楚怎麼被運來、為什麼在這裡、之後怎麼辦。凜坐在檢查台的邊緣，腿垂下來
    st = 'ch1_revival_room'
    animated('ch1_c09_wake', [
        stage(st, 316, 205, 1.4, 1.0),
        actor('rin', 'rin', 316, sit_y(st, 'rin', 196), 1, scale=actor_scale(st, 'rin'), pose='sit', speaker='rin'),
        fx('flash', 0.6),
        wait(1.2),
        say('rin', "…幹。"),
        wait(0.8),
        say('lamp', "歡迎回來。你死了十一分鐘。", ja="おかえり。十一分、死んでたよ。", en="Welcome back. You were dead for eleven minutes."),
        say('rin', "誰把我弄到這的？"),
        say('lamp', "穿灰外套的人，開貨車。不說話，也不收錢，放下就走。"),
        wait(0.8),
        say('rin', "這間診所我沒登記過。"),
        say('lamp', "所以他們才送你來。第一次死，要先建檔。"),
        say('lamp', "建好以後就不用被拖來了。撥過的電話亭，就是你醒來的地方。"),
        say('rin', "你的聲音跟電話亭很像。", ja="電話ボックスの声、お前に似てるな。", en="You sound like the phone booth."),
        say('lamp', "港區少年的聲音，長得都差不多吧。"),
        wait(0.9),
        say('rin', "要錢吧。"),
        say('lamp', "復原費，從信用點裡扣一點。還有，每次醒來，記憶的邊角會磨掉一點點。"),
        say('rin', "磨多少？"),
        say('lamp', "沒人量得準。"),
        wait(0.8),
        pose('rin', 'idle'),
        say('rin', "走了。"),
        wait(0.5),
        fade(1.0, 1.2),
    ], flags=['ch1_first_death_done'], budget=45.0)
    # 死亡之後的短演出：在電話亭醒來時的一句通訊（前幾次完整，之後縮短）
    lines_scene('ch1_d_back_a', 'radio', [('lamp', "歡迎回來。復原費已扣。")])
    lines_scene('ch1_d_back_b', 'radio', [('lamp', "再來一次，沒關係。")])
    lines_scene('ch1_d_back_c', 'radio', [('lamp', "…歡迎回來。")])
    DEATH_SCENES.append({"scene": "ch1_c09_wake", "unless_flag": "ch1_first_death_done", "free": True, "register_checkpoint": True})
    RESPAWN.append({"scene": "ch1_d_back_a", "min_deaths": 1, "max_deaths": 3, "repeat": True})
    RESPAWN.append({"scene": "ch1_d_back_b", "min_deaths": 4, "max_deaths": 9, "repeat": True})
    RESPAWN.append({"scene": "ch1_d_back_c", "min_deaths": 10, "repeat": True})

    # 復原館與麵攤（可走動的場景，不是過場）：進門一句氣泡，人物對話由玩家主動；說完才開出口（旗標有人讀）。
    lines_scene('ch1_b_lounge', 'bubbles', [('ali', "坐吧，湯還熱。")])
    lines_scene('ch1_t_ali_1', 'dialogue', [
        ('ali', "今天第幾次？"),
        ('rin', "一。"),
        ('ali', "一？那你運氣好。吃什麼？復原餐，還是酒？"),
        ('rin', "都要。"),
        ('ali', "您貴姓？"),
        ('rin', "凜。"),
        ('ali', "阿梨。梨子的梨。別分梨吃，會分開。"),
        ('rin', "好。"),
    ], flags=['ch1_met_ali'])
    lines_scene('ch1_t_ali_2', 'dialogue', [
        ('rin', "這湯怎麼是甜的？"),
        ('ali', "放了一顆梨。"),
        ('ali', "我下班了。這個不是工作。"),
        ('rin', "多少。"),
        ('ali', "放著吧。"),
    ])
    lines_scene('ch1_b_stall', 'bubbles', [('ali', "吃。")])
    lines_scene('ch1_t_ali_4', 'dialogue', [('ali', "吃完再走。"), ('rin', "好。"), ('ali', "天快亮了。")])
    lines_scene('ch1_t_ali_3', 'dialogue', [
        ('rin', "多少。"),
        ('ali', "不收錢。"),
        ('rin', "那我欠你。"),
        ('ali', "那就欠著。"),
        ('ali', "我最近被收帳人盯上了。"),
        ('rin', "欠多少。"),
        ('ali', "錢不是問題。他們一直在加。"),
        ('ali', "市集後面，三樓。敲三下，再敲兩下，是我。"),
    ], flags=['knows_ali_address'])

    # 過場 3／3：回家（章末，≤60 秒）：水燒乾了、空眼神（老 K 在爐子前，凜從門口走進來）
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
    ], budget=60.0)


def main():
    os.makedirs(STAGE_DIR, exist_ok=True)
    for stage_id, (scene, top, bottom, rain, glow, extra) in STAGES.items():
        write_stage(stage_id, scene, top, bottom, rain, glow, extra)
    build()
    data = {"chapter": CHAPTER, "speakers": SPEAKERS, "respawn_scenes": RESPAWN, "death_scenes": DEATH_SCENES, "scenes": SCENES}
    with open(OUT, 'w') as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write('\n')
    print('wrote', OUT, f'({len(SCENES)} scenes)')


if __name__ == '__main__':
    main()
