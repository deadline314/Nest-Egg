"""ST-16 序章「雨裡的燈」：依 design/13-story-v2/PROLOGUE_SCRIPT.md 的 P01～P06 寫成遊戲劇本。

與製作稿的差異（配合實際機制，意思不變）：
- 製作稿的試貨是「借訓練槍、刀」；遊戲沒有借用裝備的存檔投影，改成用凜自己的槍與徒手近戰試老 K 剛收的靶與訓練器，
  台詞把「試這把槍」改成「試這批器材」。不發槍、不改裝備、不給錢。
- P06 的收膠帶、扣門扣與關燈三個小互動併入和老 K 收尾的對話；鷺的聯絡在收尾對話裡用電話說。
- 練習倒地由訓練站處理：訓練器打中只會停機並補回生命，不會死亡、不計死亡次數、不扣錢、不碰初次建檔。
本檔只產生資料，由 ch1_runtime_backend.py 合進 data/story/ch1_kasa.json。
"""
from __future__ import annotations

import build_ch1_story as legacy

SPEAKERS = {"note": {"name": "紙本", "color": "#ded5b0", "portrait": "res://art/portraits/system.png", "formal": True}}
LEVEL = "res://data/levels/ch1_prologue.tres"


def say(speaker, text):
    return {"do": "say", "speaker": speaker, "text": text}


def lines(*pairs):
    return [{"speaker": s, "text": t} for s, t in pairs]


def flag(name, value=True):
    return {"flag": name, "equals": value}


def done(*flags):
    return [{"kind": "flag", "id": f, "value": True} for f in flags]


def _p01():
    st = "ch1_pawnshop_front"
    y = legacy.FLOOR[st]
    steps = [
        {"do": "scene", "id": "rainy_harbor", "pos": [320, 330], "fade": 1.0},
        legacy.narrate(["沉港市的下層港區，雨沒有停過，水位每晚都在漲。"], 2.4),
        legacy.title("序章　雨裡的燈", "巢蛋當舖", 1.8),
        # 21:9 遮幅（ST-22）：腳底在對話框頂（y≈232）之上、頭頂在上黑邊（y≈43）之下，人在畫面上約 3 倍。
        # 演員用這個舞台量過的縮放、鏡頭拉遠到 0.88（ST-10）：人在畫面上一樣大，但櫃台回到約 0.65 個身高；
        # 直接把人縮到 2.9 的話櫃台會高到胸口以上。
        legacy.stage(st, 320, y - 58, 0.88, 1.0),
        legacy.actor("rin", "rin", 385, y, -1, scale=legacy.actor_scale(st, "rin"), pose="idle"),
        legacy.actor("k", "old_k", 175, y, 1, scale=legacy.actor_scale(st, "old_k"), speaker="old_k", loop="wipe_hands"),
        legacy.sfx("pickup", -16),
        say("voice", "沉港市復原服務提醒您，出門前請確認自己的登記與接應地點。"),
        say("old_k", "把門帶上喔，雨都跑進來了。"),
        say("rin", "外面那個門扣又鬆了，我等一下看。"),
        legacy.wait(0.35),
        say("old_k", "先把鞋擦乾。巢蛋當舖收貨，不收你一路踩進來的水。"),
        say("rin", "你今天收了什麼要我試？"),
        say("old_k", "靶跟訓練器都在後面，工作桌上有貨單。今天剛收的，別急著拿出去用。"),
        legacy.fade(1.0, 0.8),
    ]
    return {"mode": "animated", "pose_policy": "supported", "budget": 26.0, "steps": legacy.spaced(steps)}


def build():
    """回傳 (scenes, quests, dispatch)；場景 id 都以 ch1_p 開頭。"""
    s = {}
    s["ch1_p01_door"] = _p01()
    # P02：工作桌旁的對話（走到工作桌才算完成移動練習）、自願閱讀的目錄、跳上搬貨台取工具。
    s["ch1_p02_talk"] = {"mode": "dialogue", "map_interaction": True, "lines": lines(
        ("old_k", "目錄又翻到那一頁啦？紙都要被你磨破了。"),
        ("rin", "晴岸那間四十八萬，窗戶下午照得到太陽。"),
        ("old_k", "晴岸是上層的日照區，光是電梯就要換兩趟。你搬箱子別一直看它。"),
        ("rin", "我沒要搬上去。我想把你搬上去。"),
        ("old_k", "我在這裡住得好好的，飯也煮得熟。"),
        ("rin", "你睡的那間，晴天也看不出來。"),
        ("old_k", "那就先把今天過完。你跳上搬貨台拿工具，我替你留飯。"))}
    s["ch1_p02_catalog"] = {"mode": "dialogue", "lines": lines(
        ("note", "晴岸住宅目錄：日照區邊緣住宅，標價四十八萬信用點。看房須預約，目錄不代表已經購屋。"),
        ("note", "凜的手記：以前存下的兩萬七千四百先記在這裡。還沒拿到的差事錢不算，房子的數字也不會自己變小。"),
        ("rin", "我把這頁折起來，等錢夠了再翻開。"))}
    # 拿到工具後老 K 跟到後面的白線外看試貨（見 build_ch1.py 的站位），P03～P04 的話改成邊練邊說的氣泡。
    s["ch1_p02_tool"] = {"mode": "bubbles", "lines": lines(("rin", "工具拿到了，先去後面試靶。"))}
    # P03：射擊線。
    s["ch1_p03_range"] = {"mode": "bubbles", "lines": lines(
        ("old_k", "靶跟訓練器都是今天剛收的，你用自己的槍幫我試準不準。"),
        ("rin", "彈匣看過了。你站我後面的白線外，別靠近背板。"),
        ("old_k", "我就看它有沒有亂跳。先試低處那個靶，再看上面那個。"),
        ("rin", "這個靶的鉸鏈比外殼新，可能換過裡面的零件。"))}
    s["ch1_p03_hit"] = {"mode": "bubbles", "lines": lines(
        ("old_k", "落點沒歪，靶也收得住。你再走兩步試，別替它藏毛病。"),
        ("rin", "我收回剛才那句，它的框有點鬆。"),
        ("old_k", "上面那個靶想試就跳上平台，不試也行，訓練器在更後面。"))}
    s["ch1_p03_high"] = {"mode": "bubbles", "lines": lines(("rin", "上面的靶也沒歪，跳著打一樣準。"))}
    # P04：橡膠靶、訓練器、衝刺線。
    s["ch1_p04_intro"] = {"mode": "bubbles", "lines": lines(
        ("old_k", "近戰也試一下。窄巷裡，槍不一定轉得過去。"),
        ("rin", "這個橡膠靶的裂口會刮手，先貼起來再賣。"),
        ("old_k", "貼的在桌邊。訓練器只會往前打，出手前會亮燈，你站穩再靠近它。"),
        ("rin", "我看見燈了。你把它調慢一點，別讓機器把我的手臂折掉。"))}
    s["ch1_p04_melee"] = {"mode": "bubbles", "lines": lines(("rin", "打到軟靶也沒有滑手，握得住。"))}
    s["ch1_p04_fall"] = {"mode": "dialogue", "map_interaction": True, "lines": lines(
        ("old_k", "先站穩，機器停了。別跟一根桿子賭氣喔。"),
        ("rin", "腳沒站穩，墊子邊緣捲起來了。你把它攤平，我再試。"),
        ("old_k", "拉好了。要再試就靠近它，燈亮的時候面向它舉盾。"))}
    s["ch1_p04_guard"] = {"mode": "bubbles", "lines": lines(("rin", "擋住了。這台出手前會亮燈，看得出來。"))}
    # 試完衝刺，老 K 回櫃台。
    s["ch1_p04_dash"] = {"mode": "dialogue", "map_interaction": True, "lines": lines(
        ("rin", "槍還能用，靶的框要鎖緊，這台的桿子太長了。"),
        ("old_k", "我記在貨單上了。回櫃台來，那張復原服務單我順便跟你說。"),
        ("rin", "好，我把器材排回原位就過去。"))}
    # P05：服務單與老 K 的說明；依剛才是否真的被訓練器打停而分兩種收尾。
    service = [
        ("rin", "這上面寫的記憶代價，為什麼不寫在價錢旁邊？"),
        ("old_k", "價錢能補，忘掉的事不一定補得回來喔。"),
        ("rin", "我每次都算進你的那一成了，不是嗎？"),
        ("old_k", "你這邊有保單，先別拿別人的契約套在自己身上。"),
        ("rin", "你每次都這樣講。我至少要知道，出事了該回哪裡。"),
        ("old_k", "到電話亭要真的確認備份，光走過不算。現場要補什麼資料，就問服務的人。"),
    ]
    s["ch1_p05_service_fall"] = {"mode": "dialogue", "completion_policy": "main_terminal_results_v1", "results": done("ch1_prologue_service_heard"), "lines": lines(*service,
        ("rin", "那剛才機器停下來，跟這個沒關係。"),
        ("old_k", "當然沒關係。你是在地墊上站不穩，又不是去拿命試貨。"))}
    s["ch1_p05_service_clean"] = {"mode": "dialogue", "completion_policy": "main_terminal_results_v1", "results": done("ch1_prologue_service_heard"), "lines": lines(*service,
        ("rin", "剛才試貨只是練習，不是復原。"),
        ("old_k", "本來就是喔。你拿器材試手感，不是拿命試貨。"))}
    s["ch1_p05_sheet"] = {"mode": "dialogue", "lines": lines(
        ("note", "沉港市公共復原服務說明：復原需要有效登記、備份與接應地點，不保證每次都能執行。"),
        ("note", "首次建檔與一般復原不同，請依服務人員指示辦理。"),
        ("note", "復原會產生費用，也可能消耗契約承擔者的記憶。"),
        ("note", "電話亭的確認紀錄用來查找最近的備份與接應位置；地圖上的標記不代表已經辦妥登記。"))}
    # P06：收尾與鷺的聯絡，交到第一章的第一個目標。
    s["ch1_p06_call"] = {"mode": "dialogue", "completion_policy": "main_terminal_results_v1", "results": done("ch1_prologue_done", "ch1_prologue_exit"), "lines": lines(
        ("egret", "我是鷺，人在你家屋頂，待會兒有份差事給你看。"),
        ("rin", "你又不走正門，老 K 還以為雨把屋頂敲壞了。"),
        ("egret", "我怕他又留我修門扣。你吃完飯再上來，這次不催你。"),
        ("old_k", "聽到了喔，先吃飯。試貨的事我來收尾。"),
        ("rin", "門扣我扣緊了，燈也關了。靶的毛病寫在貨單旁邊。"),
        ("old_k", "我都看到了。你先去洗手，飯還熱著，從旁邊那扇門回店裡吃。"))}
    s["ch1_p_k_wait"] = {"mode": "animated", "overlay": True, "steps": [
        say("old_k", "器材都在後面，一樣一樣試，試完再回來跟我說。")]}
    s["ch1_p_k_backyard"] = {"mode": "animated", "overlay": True, "steps": [
        say("old_k", "我在這裡看著，你一樣一樣試，試完回櫃台找我。")]}
    s["ch1_p_k_after"] = {"mode": "animated", "overlay": True, "steps": [
        say("old_k", "飯在廚房保溫，從旁邊那扇門回店裡，吃完再上屋頂。")]}
    s["ch1_dispatch_prologue_old_k"] = {"mode": "dispatch", "routes": [
        {"when": {"all": [flag("ch1_prologue_exit"), {"not": flag("ch1_dinner_done")}]}, "target": "ch1_p_k_after"},
        {"when": {"all": [flag("ch1_prologue_service_heard"), {"not": flag("ch1_prologue_done")}]}, "target": "ch1_p06_call"},
        {"when": {"all": [flag("ch1_prologue_dash_done"), flag("ch1_prologue_fall_shown"), {"not": flag("ch1_prologue_service_heard")}]}, "target": "ch1_p05_service_fall"},
        {"when": {"all": [flag("ch1_prologue_dash_done"), {"not": flag("ch1_prologue_service_heard")}]}, "target": "ch1_p05_service_clean"},
        {"when": {}, "target": "ch1_p_k_wait"},
    ]}

    # 格座標指向完成這一步的那個物件或人物（tests/suite/test_ch1_map.gd 會核對）。
    def step(title, done_flag, x, y=19):
        return {"title": title, "complete_flag": done_flag, "location": {"level": LEVEL, "cell": [x, y]}}
    quest = {"id": "ch1_prologue", "kind": "main", "title": "試完器材，回店吃飯",
             "background": "老 K 今天收了一批靶和訓練器，要你幫忙試。試完晚飯在廚房保溫，鷺說有份差事。",
             "reward": "熟悉移動、射擊、近戰、格擋與衝刺；不給錢，也不改你的裝備。",
             "complete_flag": "ch1_prologue_exit",
             "steps": [step("看看工作桌上今天要試的器材", "ch1_prologue_bench_done", 24),
                       step("取下搬貨台上的試貨工具", "ch1_prologue_jump_done", 30, 17),
                       step("試訓練槍的落點", "ch1_prologue_shot_done", 60),
                       step("試橡膠靶的近戰手感", "ch1_prologue_melee_done", 79),
                       step("試訓練器的正面防禦", "ch1_prologue_guard_done", 90),
                       step("試地上的衝刺訓練線", "ch1_prologue_dash_done", 103),
                       step("回櫃台，聽老 K 說明復原服務", "ch1_prologue_service_heard", 38),
                       step("跟老 K 收尾，從旁邊的門回店裡", "ch1_prologue_exit", 40)]}
    defaults = {name: False for name in (
        "ch1_prologue_bench_done", "ch1_prologue_jump_done", "ch1_prologue_range_reached", "ch1_prologue_shot_done", "ch1_prologue_high_shot_done",
        "ch1_prologue_trainer_reached", "ch1_prologue_melee_done", "ch1_prologue_guard_done", "ch1_prologue_dash_done", "ch1_prologue_fall_shown",
        "ch1_prologue_service_heard", "ch1_prologue_done", "ch1_prologue_skipped", "ch1_prologue_exit")}
    # 舊存檔已經在第一章（吃過晚飯）就視為走過序章，不倒塞序章。
    derived = {"ch1_prologue_exit": {"any": [flag("ch1_prologue_done"), flag("ch1_prologue_skipped"), flag("ch1_dinner_done")]}}
    return s, [quest], defaults, derived
