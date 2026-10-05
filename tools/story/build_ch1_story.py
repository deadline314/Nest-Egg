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
STAGES = {
    # 舞台 id: (場景立繪, 底色上, 底色下, 地面 y, 雨, 光暈 [x, y, 半徑, 顏色])
    'ch1_pawnshop_front': ('pawnshop_front', '#120d09', '#241810', 336, True, [330, 70, 230, '#ffb066']),
    'ch1_pawnshop_kitchen': ('pawnshop_kitchen', '#0d1410', '#1b241a', 306, False, [300, 40, 200, '#e8e090']),
    'ch1_rooftop': ('rooftop', '#06101f', '#0c1c33', 292, True, [560, 40, 200, '#ffd77a']),
    'ch1_revival_room': ('revival_room', '#d8e4ee', '#f4f8fb', 344, False, [320, 60, 260, '#ffffff']),
    'ch1_revival_lounge': ('revival_lounge', '#160812', '#2a1022', 344, False, [320, 120, 240, '#ff3fa4']),
    'ch1_dawn_noodle_stall': ('dawn_noodle_stall', '#1a2230', '#3a4658', 318, True, [300, 140, 220, '#cfe0ff']),
}
FLOOR = {k: v[3] for k, v in STAGES.items()}


def write_stage(stage_id, scene, top, bottom, rain, glow):
    layers = [
        {"kind": "gradient", "top": top, "bottom": bottom, "parallax": 0.0},
        {"kind": "sprite", "path": f"res://art/environment/scenes/{scene}.webp", "pos": [-64, -36.0], "scale": 0.5,
         "filter": "linear", "life": True},
        {"kind": "glow", "pos": [glow[0], glow[1]], "radius": glow[2], "color": glow[3], "intensity": 0.7, "additive": True,
         "alpha": 0.35, "pulse": 0.06, "pulse_depth": 0.2},
    ]
    if rain:
        layers.append({"kind": "rain", "depth": "front", "opacity": 0.35})
    layers.append({"kind": "motes", "count": 24, "color": "#cfe0ff", "opacity": 0.3, "area": [0, 30, 640, 280], "drift": [2, -3], "size": 1.1, "seed": 7})
    layers.append({"kind": "grain", "amount": 50, "opacity": 0.05, "depth": "front"})
    data = {"camera": {"pos": [320, 180], "zoom": 1.0}, "layers": layers}
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
    step = {"do": "camera", "pos": [x, y], "zoom": zoom, "time": t}
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


def pose(ident, name):
    return {"do": "pose", "id": ident, "pose": name}


def move(ident, x, y, t=1.5, wait_for=True, pose_name=None):
    step = {"do": "move", "id": ident, "to": [x, y], "time": t}
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


def stage(stage_id, x=320, y=180, zoom=1.0, fade_in=1.2):
    return {"do": "scene", "id": stage_id, "pos": [x, y], "zoom": zoom, "fade": fade_in}


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
    y = FLOOR['ch1_pawnshop_front']
    animated('ch1_c01_shop', [
        stage('ch1_pawnshop_front', 330, 200, 1.15, 1.4),
        actor('rin', 'rin', 400, y, -1, pose='crouch'),
        actor('k', 'old_k', 250, y, 1, speaker='old_k', loop='wipe_hands'),
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

    # C1-02 晚飯：四十、紅蘿蔔、幾次了
    y = FLOOR['ch1_pawnshop_kitchen']
    animated('ch1_c02_dinner', [
        stage('ch1_pawnshop_kitchen', 320, 190, 1.1, 1.2),
        actor('rin', 'rin', 250, y, 1, pose='sit'),
        actor('k', 'old_k', 420, y, -1, speaker='old_k', loop='stir'),
        wait(1.0),
        say('old_k', "今天的。"),
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
    y = FLOOR['ch1_rooftop']
    animated('ch1_c03a_roof', [
        stage('ch1_rooftop', 440, 200, 1.1, 1.4),
        actor('egret', 'night_worker', 470, y, -1, speaker='egret', pose='sit'),
        actor('rin', 'rin', 120, y, 1),
        move('rin', 330, y, 3.0, True, 'walk'),
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
        stage('ch1_rooftop', 440, 200, 1.1, 0.0),
        actor('egret', 'night_worker', 470, y, -1, speaker='egret', pose='sit'),
        actor('rin', 'rin', 330, y, 1),
        say('egret', "你一個人去。不要一個人死，浪費。", ja="一人で死ぬなよ、もったいない。", en="Don't die alone. Waste of a good death."),
        wait(0.8),
        say('egret', "開玩笑啦。死了還不是照樣喝酒。", ja="死んだって、どうせ酒は飲めるさ。", en="You can still drink after."),
        cam(380, 230, 1.5, 1.4),
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
        cam(470, 190, 1.2, 1.6),
        say('egret', "看到那座塔沒有？上面有太陽。真的太陽。", ja="あの塔、見える？上には太陽がある。本物の。", en="See that tower? There's sun up there. Real sun."),
        say('rin', "聽說。"),
        wait(0.5),
        say('egret', "你要帶他去喔。"),
        fade(1.0, 0.9),
    ], flags=['ch1_heard_brief'])

    # C1-04 出門：帶傘了嗎
    y = FLOOR['ch1_pawnshop_front']
    animated('ch1_c04_out', [
        stage('ch1_pawnshop_front', 330, 200, 1.15, 1.2),
        actor('rin', 'rin', 330, y, 1),
        actor('k', 'old_k', 220, y, 1, speaker='old_k', loop='wipe_hands'),
        move('rin', 520, y, 2.4, True, 'walk'),
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

    # C1-09 復原室醒來（第一次死亡後，重生時播出）
    y = FLOOR['ch1_revival_room']
    animated('ch1_c09_wake', [
        stage('ch1_revival_room', 320, 190, 1.1, 1.0),
        actor('rin', 'rin', 330, y, 1, pose='sit', speaker='rin'),
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

    # C1-12 復原館：阿梨初見（基底層，不露骨）
    y = FLOOR['ch1_revival_lounge']
    animated('ch1_c12_lounge', [
        stage('ch1_revival_lounge', 320, 200, 1.1, 1.4),
        actor('ali', 'nurse', 250, y, 1, speaker='ali', loop='wipe_hands'),
        actor('rin', 'rin', 520, y, -1),
        move('rin', 400, y, 2.0, True, 'walk'),
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
    y = FLOOR['ch1_dawn_noodle_stall']
    animated('ch1_c13_noodle', [
        stage('ch1_dawn_noodle_stall', 320, 200, 1.1, 1.6),
        actor('ali', 'nurse', 360, y, -1, speaker='ali', loop='stir'),
        actor('rin', 'rin', 250, y, 1, pose='sit'),
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

    # C1-14 回家：水燒乾了、空眼神
    y = FLOOR['ch1_pawnshop_kitchen']
    animated('ch1_c14_home', [
        stage('ch1_pawnshop_kitchen', 330, 190, 1.1, 1.4),
        actor('rin', 'rin', 120, y, 1),
        actor('k', 'old_k', 400, y, -1, speaker='old_k'),
        move('rin', 300, y, 2.0, True, 'walk'),
        say('rin', "老 K。"),
        say('old_k', "啊。"),
        say('old_k', "水燒乾了喔。"),
        wait(0.5),
        say('rin', "是。"),
        say('old_k', "老了。"),
        say('old_k', "我去裝個水。"),
        move('k', 560, y, 2.6, True, 'walk'),
        sfx('switch', -10),
        wait(1.4),
        move('k', 400, y, 2.4, True, 'walk'),
        cam(400, 230, 1.7, 1.6),
        wait(3.0),
        say('old_k', "…你什麼時候回來的？"),
        say('rin', "剛剛。"),
        say('old_k', "喔。水燒好了。"),
        wait(1.4),
        fade(1.0, 1.4),
    ], flags=['ch1_home_done'])


def main():
    os.makedirs(STAGE_DIR, exist_ok=True)
    for stage_id, (scene, top, bottom, _floor, rain, glow) in STAGES.items():
        write_stage(stage_id, scene, top, bottom, rain, glow)
    build()
    data = {"chapter": CHAPTER, "speakers": SPEAKERS, "respawn_scenes": RESPAWN, "scenes": SCENES}
    with open(OUT, 'w') as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write('\n')
    print('wrote', OUT, f'({len(SCENES)} scenes)')


if __name__ == '__main__':
    main()
