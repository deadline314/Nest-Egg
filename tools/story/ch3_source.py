"""第三章「晴岸」的作者來源（ST-21）：劇本 design/13-story-v2/SCRIPT_CH03.md 的 C00～C23 落成段落、選擇、結果與任務。

台詞照劇本；劇本描述的動作（推碗、轉輪、扶椅）由演出與擺設表現，不寫成台詞。
新動詞一律用既有的選擇演出：排水是選轉輪方向、隔離是選要關的開關、對帳是依序確認三個事實、看房是量窗與記提案；
選錯有一句完整的提示，再選一次，不扣東西。旗標名稱避開和前章只差一兩個字的寫法（見 CH03_IMPLEMENTATION.md）。
轉譯與寫檔：python3 tools/story/build_ch3_story.py
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

from ch1_closure import (Option, ProductionSource, Quest, QuestStep, all_of, any_of, flag, grant, item,  # noqa: E402
                         negate, set_flag, transaction)
from build_ch1_story import (actor as stage_actor, cam as stage_cam, face as stage_face, move as stage_move,  # noqa: E402
                             pose as stage_pose, say as stage_say, sfx as stage_sfx, stage as stage_scene, wait as stage_wait)
from chapter_compiler import route_back_to_choices  # noqa: E402
from ch1_closure import beats  # noqa: E402

CHAPTER = {
    "id": "ch3_clearwater", "title": "第三章　晴岸", "subtitle": "夾層診所・玻璃邊緣",
    "end_title": "第三章　晴岸　完",
    "teaser": "下一章：空殼。一週後的週日，到夾層病房外櫃檯找鷺。",
    "release_note": "進度已保存。",
}

SPEAKERS = {
    "rin": {"name": "凜", "color": "#ff3fa4", "portrait": "res://art/portraits/rin.png"},
    "old_k": {"name": "老K", "color": "#ffd23f", "portrait": "res://art/portraits/old_k.png"},
    "lamp": {"name": "燈", "color": "#8fe39a", "portrait": "res://art/portraits/lamp.png"},
    "egret": {"name": "鷺", "color": "#b8c4d6", "portrait": "res://art/portraits/egret.png"},
    "zhi": {"name": "芷姐", "color": "#a8d8d0", "portrait": "res://art/portraits/zhi.png"},
    "janus": {"name": "守門人", "color": "#c8b8a0", "portrait": "res://art/portraits/janus.png"},
    "lin": {"name": "林小姐", "color": "#f0d0a8", "portrait": "res://art/portraits/lin.png"},
    "ye": {"name": "葉", "color": "#c8d8f0", "portrait": "res://art/portraits/ye.png"},
    "ahan": {"name": "阿翰的錄音", "color": "#c8c0e8", "portrait": "res://art/portraits/system.png", "formal": True},
    "panel": {"name": "控制箱", "color": "#9ad7ff", "portrait": "res://art/portraits/system.png", "formal": True},
    "label": {"name": "說明", "color": "#ded5b0", "portrait": "res://art/portraits/system.png", "formal": True},
}

# 劇本第 5 節的金額（NE-231 可以調整資源檔的數字；這裡只引用交易）。
TRANSACTIONS = {
    "ch3.report_reconciled": ("ch3_report_reconciled", 180),   # C08 三處核對與異議回執
    "ch3.gate_disabled": ("ch3_gate_disabled", 100),           # C12 門禁裝置停機回執
    "ch3.sq3_room": ("ch3_sq3_room", 20),                      # C16 房間提案（SQ3-C1）
    "ch3.sq7_tape": ("ch3_sq7_tape", 20),                      # C09 借出阿翰的錄音（SQ7-G1）
    "ch3.sq7_name": ("ch3_sq7_name", 20),                      # C19 看清葉手背的字（SQ7-G2）
}

DOCUMENTS = {
    "ch3_review_slip": {
        "name": "核閱號Q17", "icon": "doc_stub", "description": "芷姐給的只讀核閱號。可以看三份公開資料，不是通行證。",
        "body": "夾層診所公開查核：核閱號Q17。可閱覽月報17的公開報表、護理輪班表與追蹤名冊。資料都用編號，不含姓名。本號不開病房內門。"},
    "ch3_report_p17": {
        "name": "公開報表P17副本", "icon": "doc_notice", "description": "公開報表寫著同批一百人、耗損比例3%，頁尾排除了八個編號。",
        "body": "月報17的觀察對象是同批錨人100名，編號從R17-001到R17-100。公開結論寫達持續護理標準的有3名，公開耗損比例是3%。頁尾另外註記八個編號列為轉存、不計入護理人數，轉存去向寫著帳房。八個編號：R17-012、018、024、037、053、067、082、096。"},
    "ch3_roster_n17": {
        "name": "護理輪班表N17副本", "icon": "doc_log", "description": "白班與晚班各十一個編號，兩班合計二十二次，人數是十一名。",
        "body": "月報17同批錨人在三十日的白班與晚班追蹤。兩班記的是同樣的十一個編號，也就是公開頁的三名加上轉存的八名。交班檢視共有22次，人數是11名。"},
    "ch3_register_t17": {
        "name": "追蹤名冊T17副本", "icon": "doc_log", "description": "轉介的八個編號仍在同批、月底仍需持續護理。",
        "body": "母群：1日建檔的同批錨人100名，換院不移出本月母群。本站持續護理3名；轉介仍追蹤8名，月底仍達持續護理標準。轉介完成只代表換了院區，不是治癒。"},
    "ch3_petition_receipt": {
        "name": "異議回執", "icon": "doc_stub", "description": "三處核閱一致，公開3%與追蹤11%不一致，已要求原發布端回覆。",
        "body": "公開查核Q17的異議回執。三處核閱的結果一致：公開報表寫3%，同批追蹤是11%。診所已要求原發布端回覆。本回執不等於報表已經更正。"},
    "ch3_mezz_pass": {
        "name": "夾層證：公開查核", "icon": "maintenance_pass", "description": "芷姐親手發的證，只開診所側通道與邊緣電梯。",
        "body": "夾層證（公開查核）。放行範圍：診所側通道、護理通道外段、邊緣電梯與晴岸展示接待層。不開病房內門、廠房、塔與住宅內區。"},
    "ch3_gate_receipt": {
        "name": "門禁停機回執", "icon": "doc_stub", "description": "診所委託停下門禁工作架的回執。守門人平安，坐回櫃檯休息。",
        "body": "門禁工作架停機處理完成。外部盾架、掃描臂與通訊器已斷電，維修插銷已拔除。人員平安，已由護理人員安置。處理報酬已結算。"},
    "ch3_tour_card": {
        "name": "晴岸看房卡", "icon": "doc_flyer", "description": "林小姐給的看房卡。三間都是四十八萬，差在朝向、光照與安靜。",
        "body": "晴岸的三間樣品房總價都是480,000。A晨窗朝東，上午八到十點最亮。B靜窗朝北，少有直射的陽光，路聲也低。C晚窗朝西，下午兩到四點最亮。提案欄只記提案，不是預留名額。"},
    "ch3_ahan_tape": {
        "name": "阿翰的錄音", "icon": "recording", "description": "寄存櫃借出的家屬尋人錄音。要找到收件人，不能賣也不能當。",
        "body": "這卷錄音的錄音者是阿翰，片頭他先說出自己的名字，請收件人聽他把名字說完。借出單由芷姐保管，找到收件人後要拿回寄存櫃歸還。"},
    "ch3_intake_receipt": {
        "name": "接待收件回執", "icon": "doc_stub", "description": "風控接待收下月報17查核件的回執。只確認收件，不是答覆。",
        "body": "風控接待收件：月報17查核件。收件人：風控接待。本回執只確認收件，回覆走原發布端。"},
    "ch3_trade_note": {
        "name": "凜的談話記錄", "icon": "doc_log", "description": "凜在候梯迴廊記下的談話：老 K 交過她的備份，換了條件，沒問她。",
        "body": "老 K 對葉說：備份是他交的，條件是停掉危險的派案；他沒讓我看。葉說資料在天穹保管，交付人是他。價碼、原因與協議全文都沒聽到。"},
}

# 任務步驟的真實格位（人物或物件站的那一格；區域 id 對應 data/levels/ch3_<區域>.tres）。
QUEST_LOCATIONS = {
    "old_k": ("pawnshop", 50, 19), "old_k_kitchen": ("pawnshop", 93, 19), "shop_radio": ("pawnshop", 66, 19),
    "control_box": ("plaza", 40, 19), "drain_wheel": ("pump", 30, 12), "branch_panel": ("pump", 64, 19),
    "zhi": ("clinic", 24, 19), "report": ("clinic", 34, 19), "register": ("clinic", 12, 19), "roster": ("clinic", 60, 19),
    "reading_desk": ("clinic", 38, 19), "drawer": ("clinic", 76, 19), "scanner_gate": ("gate_hall", 18, 19),
    "gatekeeper": ("gate_hall", 32, 19), "lin": ("showroom", 16, 19), "petition_box": ("office_hall", 14, 19),
    "bench": ("office_hall", 28, 19),
}

# 人物／物件入口 → 依序檢查的段落（第一個成立的播出）。
DISPATCH = {
    "old_k": ["ch3_t_c00_breakfast", "ch3_t_c00_choice", "ch3_t_c00_revisit"],
    "supper": ["ch3_t_c22_door", "ch3_t_c22_note", "ch3_t_c22_revisit"],
    "c22_room": ["ch3_t_c22_room_set", "ch3_t_c22_room_unset"],
    "m3": ["ch3_t_m3_record", "ch3_t_m3_revisit"],
    "call": ["ch3_t_c23_quiet_day", "ch3_t_c23_call", "ch3_t_c23_invite", "ch3_t_c23_revisit"],
    "control_box": ["ch3_t_c01_box", "ch3_t_c02_call_early", "ch3_t_c02_call", "ch3_t_c02_box_revisit"],
    "gauge": ["ch3_t_c01_gauge", "ch3_t_c01_gauge_low"],
    "ladder": ["ch3_t_c02_ladder_locked", "ch3_t_c02_ladder", "ch3_t_c02_ladder_revisit"],
    "wheel": ["ch3_t_c02_wheel", "ch3_t_c02_wheel_revisit"],
    "panel": ["ch3_t_c02_panel_wet", "ch3_t_c02_panel", "ch3_t_c02_power", "ch3_t_c02_panel_revisit"],
    "notice": ["ch3_t_c03_notice_cut", "ch3_t_c03_notice_keep"],
    "zhi": ["ch3_t_c04_counter", "ch3_t_c04_no_index", "ch3_t_c08_zhi_revisit", "ch3_t_c04_revisit"],
    "report": ["ch3_t_c05_locked", "ch3_t_c05_report", "ch3_t_c05_revisit"],
    "roster": ["ch3_t_c05_locked", "ch3_t_c06_board", "ch3_t_c06_revisit"],
    "register": ["ch3_t_c05_locked", "ch3_t_c07_register", "ch3_t_c07_revisit"],
    "reconcile": ["ch3_t_c05_locked", "ch3_t_c08_missing_report", "ch3_t_c08_missing_roster", "ch3_t_c08_missing_register",
                  "ch3_t_c08_population", "ch3_t_c08_revisit"],
    "drawer": ["ch3_t_c05_locked", "ch3_t_c09_drawer", "ch3_t_c09_lend_again", "ch3_t_c09_revisit"],
    "gate": ["ch3_t_c10_scan", "ch3_t_c10_hint", "ch3_t_c10_revisit"],
    "gatekeeper": ["ch3_t_c12_aftercare", "ch3_t_c12_revisit"],
    "light": ["ch3_t_c13_pause", "ch3_t_c13_revisit"],
    "telescope": ["ch3_t_c14_view"],
    "lin": ["ch3_t_c15_welcome", "ch3_t_c15_hub", "ch3_t_c17_revisit"],
    "room_morning": ["ch3_t_c16_locked", "ch3_t_c16_morning", "ch3_t_c16_morning_revisit"],
    "room_quiet": ["ch3_t_c16_locked", "ch3_t_c16_quiet", "ch3_t_c16_quiet_revisit"],
    "room_late": ["ch3_t_c16_locked", "ch3_t_c16_late", "ch3_t_c16_late_revisit"],
    "proposal": ["ch3_t_c16_propose", "ch3_t_c16_repropose"],
    "petition": ["ch3_t_c18_box", "ch3_t_c18_revisit"],
    "bench": ["ch3_t_c19_early", "ch3_t_c19_watch", "ch3_t_c20_react", "ch3_t_c20_middle", "ch3_t_c19_choice", "ch3_t_c20_revisit"],
    "c19_read": ["ch3_t_c19_read_tape", "ch3_t_c19_read_new"],
}


# 舞台演出：早飯沿用第一章的當舖店面舞台、晚飯沿用廚房舞台，演員站位與縮放照第一章審過的同一場景（ch1_p01_door、ch1_c14_home）。
# 接續的段落沿用同一個舞台與站位，只用很短的淡入，選擇也留在同一個畫面上。
# 縮放與鏡頭跟著第一章同舞台的數字（ST-10，2026-10-12）：演員照立繪裡的櫃台、桌椅量出的縮放，鏡頭拉遠讓人在畫面上一樣大。
STAGES = {
    "front": ("ch1_pawnshop_front", 320, 290, 0.88, (("k", "old_k", 175, 348, 1, 3.6), ("rin", "rin", 385, 348, -1, 3.4))),
    "kitchen": ("ch1_pawnshop_kitchen", 320, 240, 0.8, (("k", "old_k", 230, 304, 1, 4.0), ("rin", "rin", 400, 304, -1, 3.9))),
}


def _staged(where: str, lines: tuple, opening: bool = False) -> list[dict]:
    stage_id, x, y, zoom, cast = STAGES[where]
    steps = [stage_scene(stage_id, x=x, y=y, zoom=zoom, fade_in=1.0 if opening else 0.25)]
    for ident, kind, ax, ay, facing, scale in cast:
        steps.append(stage_actor(ident, kind, ax, ay, facing=facing, scale=scale, speaker=kind, weapon=""))
    return steps + beats(*lines)


def _documents_and_transactions(source: ProductionSource):
    source.documents = dict(DOCUMENTS)
    for canonical, (filename, _amount) in TRANSACTIONS.items():
        source.transactions[canonical] = {"resource": f"res://data/story_transactions/{filename}.tres", "caller": "chapter3"}


def _opt(ident, text, target, explanation, **kw):
    return Option(ident, text, target, explanation, **kw)


# ---------------------------------------------------------------------------
# H1／H2 當舖：C00 早飯與出門
# ---------------------------------------------------------------------------

def _morning(source: ProductionSource):
    departed = flag("ch3_departure_done")
    heard = flag("ch3_breakfast_heard")
    source.add("ch3_t_c00_breakfast", "C00", steps=_staged("front", (
        ("old_k", "先吃完喔，昨晚那杯茶不能算一頓。"),
        ("rin", "我今天去夾層診所，月報十七還沒查。"),
        ("old_k", "帳在這裡也能算，別去上面。那邊的規矩跟市場不一樣。"),
        ("rin", "副本裡沒有原表，我不能一直拿猜的對帳。"),
        ("rin", "查完我想看晴岸，至少知道那筆錢要買什麼。"),
        ("old_k", "別替我把房間訂下來喔，我還沒說要住。"),
        ("rin", "我只去看窗戶，不會簽約，也不會先付錢。")), opening=True),
        when=all_of(negate(departed), negate(heard)), mode="animated", completion=(set_flag("ch3_breakfast_heard"),),
        next_scene="ch3_t_c00_choice")
    source.add("ch3_t_c00_choice", "C00", steps=_staged("front", (("old_k", "索引帶上了嗎？要出門就說一聲。"),), opening=False),
               when=negate(departed), options=(
                   _opt("ask", "問老 K 去過上面沒有。", "ch3_t_c00_ask", "可選的追問，主線一樣。"),
                   _opt("go", "確認出門去廣場貨梯。", "ch3_t_c00_go", "燈會先說貨梯的狀況。"),
                   _opt("later", "先在店裡看看。", None, "之後再找老 K 確認出門。")))
    source.add("ch3_t_c00_ask", "C00", steps=_staged("front", (
        ("rin", "你去過上面？"),
        ("old_k", "做生意的人都得跑幾個地方。妳把該看的紙看完，就回來吃飯。")), opening=False),
        when=negate(departed), mode="animated", next_scene="ch3_t_c00_choice")
    source.add("ch3_t_c00_go", "C00", steps=_staged("front", (
        ("lamp", "廣場貨梯能上夾層，入口那支水尺還亮紅燈。你到現場我再對聯鎖圖。"),
        ("rin", "我先去廣場貨梯，查完診所的報表。"),
        ("rin", "然後再去看晴岸。")), opening=False),
        when=negate(departed), mode="animated", completion=(set_flag("ch3_departure_done"),))
    source.add("ch3_t_c00_revisit", "C00", (("old_k", "索引夾好了就走，回來先吃，紙別放到鍋上喔。"),), when=departed)


# ---------------------------------------------------------------------------
# H14 廣場貨梯與泵室：C01 聯鎖、C02 排水、隔離、呼梯與外梯
# ---------------------------------------------------------------------------

def _freight(source: ProductionSource):
    chart = flag("ch3_interlock_seen")
    low = flag("ch3_pump_low")
    isolated = flag("ch3_wet_branch_isolated")
    powered = flag("ch3_lift_powered")
    ready = flag("ch3_freight_ready")
    ladder = flag("ch3_outer_ladder_down")
    source.add("ch3_t_c01_box", "C01", (
        ("panel", "集水槽水位過高，貨梯安全聯鎖未解除。沿右側上橋去排水泵室。"),
        ("rin", "梯子沒壞，是下面還泡著水。"),
        ("lamp", "先看水尺，紅線下面才可送電。")),
        when=negate(chart), mode="animated", completion=(set_flag("ch3_interlock_seen"),))
    source.add("ch3_t_c02_call_early", "C02", (("panel", "水位尚未到安全線，請先排水，再關閉浸水支路。"),),
               when=all_of(chart, negate(all_of(low, isolated, powered))))
    source.add("ch3_t_c02_call", "C02", (
        ("rin", "水退了，支路也關了，我把車廂叫下來。"),
        ("lamp", "車廂沿著導軌下來了。外梯的鎖扣也鬆開了，在控制箱右邊。")),
        when=all_of(low, isolated, powered, negate(ready)), mode="animated", completion=(set_flag("ch3_freight_ready"),))
    source.add("ch3_t_c02_box_revisit", "C02", (("panel", "貨梯已接通，可以搭乘到夾層。"),), when=ready)
    source.add("ch3_t_c01_gauge", "C01", (("rin", "紅線在車廂底下。"), ("rin", "排水輪在對面，從上橋過去。"),), when=negate(low))
    source.add("ch3_t_c01_gauge_low", "C01", (("label", "水位已經退到低線，浮標停在綠色刻度上。"),), when=low)
    source.add("ch3_t_c02_ladder_locked", "C02", (("label", "外梯的鎖扣還連著貨梯聯鎖，車廂停穩後才放得下來。"),), when=negate(ready))
    source.add("ch3_t_c02_ladder", "C02", (
        ("rin", "我把靠廣場這一頭的平臺梯放下來。"),
        ("lamp", "外梯放好了，回程不用再繞泵室。")),
        when=all_of(ready, negate(ladder)), mode="animated", completion=(set_flag("ch3_outer_ladder_down"),))
    source.add("ch3_t_c02_ladder_revisit", "C02", (("label", "外梯兩端都接在平臺上，可以直接走到泵室上橋。"),), when=ladder)

    source.add("ch3_t_c02_wheel", "C02", (("lamp", "先把水導進旁邊的蓄水槽，水尺到低線才放開車廂。"),),
               when=negate(low), options=(
                   _opt("drain", "把輪轉向蓄水槽那一側。", "ch3_t_c02_drained", "水會改道流進蓄水槽。"),
                   _opt("back", "把輪轉向主槽那一側。", "ch3_t_c02_wheel_wrong", "主槽已經滿了。"),
                   _opt("leave", "先離開排水輪。", None, "之後可以再來。")))
    source.add("ch3_t_c02_wheel_wrong", "C02", (("label", "閥門頂住了，水位停在原處。輪要轉向蓄水槽那一側，再試一次。"),),
               mode="animated", next_scene="ch3_t_c02_wheel")
    source.add("ch3_t_c02_drained", "C02", (
        ("label", "水流改道進了蓄水槽，主槽的浮標落到低線，下槽的照明亮了。"),
        ("lamp", "水位到低線了。去下槽的乾地，把泡水的支路關掉。")),
        mode="animated", completion=(set_flag("ch3_pump_low"),))
    source.add("ch3_t_c02_wheel_revisit", "C02", (("label", "排水輪鎖在蓄水槽那一側，主槽維持低水位。"),), when=low)

    source.add("ch3_t_c02_panel_wet", "C02", (("label", "配電盤前面還泡著水，先在上橋把水排掉再來。"),), when=negate(low))
    source.add("ch3_t_c02_panel", "C02", (("label", "關閉浸水支路，再接通貨梯主路。"),),
               when=all_of(low, negate(isolated)), options=(
                   _opt("branch", "關掉標著浸水支路的開關。", "ch3_t_c02_isolated", "只關泡過水的那一條。"),
                   _opt("main", "關掉標著主路的開關。", "ch3_t_c02_panel_wrong", "主路接的是貨梯。"),
                   _opt("leave", "先不動配電盤。", None, "之後可以再來。")))
    source.add("ch3_t_c02_panel_wrong", "C02", (
        ("lamp", "支路是泡水那條，主路在上橋。你關的是主路，先把它推回去，再關支路。"),),
        mode="animated", next_scene="ch3_t_c02_panel")
    source.add("ch3_t_c02_isolated", "C02", (("lamp", "你關的是支路，不是整座泵。現在可以接通主路了。"),),
               mode="animated", completion=(set_flag("ch3_wet_branch_isolated"),), next_scene="ch3_t_c02_power")
    source.add("ch3_t_c02_power", "C02", (("label", "支路已隔離。接通貨梯主路後，回控制箱就能叫車廂。"),),
               when=all_of(isolated, negate(powered)), options=(
                   _opt("power", "接通貨梯主路。", "ch3_t_c02_powered", "主路有電，車廂才叫得下來。"),
                   _opt("leave", "等一下再接。", None, "之後可以再來。")))
    source.add("ch3_t_c02_powered", "C02", (("lamp", "主路有電了。回廣場的控制箱叫車廂。"),),
               mode="animated", completion=(set_flag("ch3_lift_powered"),))
    source.add("ch3_t_c02_panel_revisit", "C02", (("label", "浸水支路關著，貨梯主路通電中。"),), when=powered)


# ---------------------------------------------------------------------------
# M1 夾層通道：C03
# ---------------------------------------------------------------------------

def _mezzanine(source: ProductionSource):
    source.add("ch3_c03_arrive", "C03", (
        ("rin", "診所招牌朝走廊裡，不朝港區。"),
        ("lamp", "對，從貨梯口往右走，先找診所的公開櫃檯。")),
        mode="bubbles", completion=(set_flag("ch3_mezzanine_reached"),))
    cut = flag("yong_link_choice", "cut")
    source.add("ch3_t_c03_notice_cut", "C03", (
        ("label", "市場收款批號轉介回執：父女連結已撤銷，兩人完成安全離場，未讀取。"),
        ("rin", "這筆不是診所月報，不能混成同一個人。")), when=cut, mode="animated")
    source.add("ch3_t_c03_notice_keep", "C03", (
        ("label", "市場收款批號轉介回執：連結維修暫停，兩人完成安全離場，既有讀取一次，未恢復。"),
        ("rin", "這筆不是診所月報，不能混成同一個人。")), when=negate(cut), mode="animated")


# ---------------------------------------------------------------------------
# M5a／M5b 夾層診所：C04 公開櫃檯、C05～C07 三份資料、C08 核對、C09 寄存櫃
# ---------------------------------------------------------------------------

def _clinic(source: ProductionSource):
    access = flag("ch3_clinic_access")
    report = flag("ch3_public_report_taken")
    roster = flag("ch3_nursing_roster_taken")
    register = flag("ch3_followup_register_taken")
    reconciled = flag("ch3_report_reconciled")
    source.add("ch3_t_c04_counter", "C04", (
        ("rin", "代收說費用照月報十七，我來看原始公開表。"),
        ("zhi", "我是這班的護士芷姐。十七是月份批號，不是你的診斷號。"),
        ("zhi", "市場錯收已結案，查核權還在。你能看的是去掉姓名的統計，不是每個人的病歷。"),
        ("rin", "我先對同一批人，有名字也不替他們作答。"),
        ("zhi", "公開報表在桌上，輪班表在工作廊，追蹤名冊在門邊的閱覽櫃。三份都用編號，日期要一起看。"),
        ("label", "核閱異議處理報酬一百八十信用點，由診所公開查核帳支付，三份證據確認後結算。")),
        when=all_of(negate(access), item("ch2_clinic_index")), mode="animated",
        completion=(set_flag("ch3_clinic_access"), grant("ch3_review_slip")), next_scene="ch3_t_c04_after")
    source.add("ch3_t_c04_after", "C04", (("zhi", "有問題拿編號來問，我能解釋轉介欄。有人正在休息，裡面的門今天不開。"),),
               options=(
                   _opt("disease", "問檔案標頭的「錨人耗損症」。", "ch3_t_c04_disease", "可選的追問。"),
                   _opt("go", "先去看三份資料。", None, "三份可以照任意順序看。")))
    source.add("ch3_t_c04_disease", "C04", (
        ("rin", "這是復原的人生病，還是付帳的人？"),
        ("zhi", "這一冊追蹤的是錨人的記憶與生活能力，不是受錨者的新身體。"),
        ("rin", "我先查這份總表，不把它貼到自己名字上。")), mode="animated")
    source.add("ch3_t_c04_no_index", "C04", (("zhi", "月報要用索引來查。索引在前章的帳櫃裡，拿到再來找我。"),),
               when=all_of(negate(access), negate(item("ch2_clinic_index"))))
    source.add("ch3_t_c04_revisit", "C04", (("zhi", "先看月份與編號，有一份缺了就從原櫃再印。我不收查核入場費。"),), when=access)
    source.add("ch3_t_c08_zhi_revisit", "C08", (("zhi", "你那份異議有回執了，原發布端還沒答。三張紙都留著，不能只拿十一那一格。"),),
               when=reconciled)

    source.add("ch3_t_c05_locked", "C05", (("label", "閱覽的資料要先到芷姐的櫃檯取核閱號。"),), when=negate(access))
    source.add("ch3_t_c05_report", "C05", (
        ("label", "月報十七，觀察期一日到三十日，同批錨人一百名，編號R17-001到R17-100。"),
        ("label", "公開結論：達持續護理標準三名，公開耗損比例百分之三。"),
        ("lamp", "先看頁尾，大字那一格之外還有註記。"),
        ("label", "頁尾註記：另有八個編號列為轉存，不計入護理人數。"),
        ("label", "轉存去向寫著帳房，追蹤狀態另見護理表，沒有治療完成的證明。"),
        ("rin", "大字寫三，下面排掉八個編號。"),
        ("rin", "它們排去哪裡了？"),
        ("lamp", "先找同批追蹤欄，我不能只看標題說它們已經好了。")),
        when=all_of(access, negate(report)), options=(
            _opt("save", "儲存公開頁的副本。", "ch3_t_c05_saved", "副本可以在筆記裡重看。"),
            _opt("leave", "先放回桌上。", None, "之後可以再來。")))
    source.add("ch3_t_c05_saved", "C05", (("rin", "公開頁存好了，三那一格先不算數。"),),
               mode="animated", completion=(set_flag("ch3_public_report_taken"), grant("ch3_report_p17")))
    source.add("ch3_t_c05_revisit", "C05", (("label", "公開報表P17：同批一百名，公開三名，八個編號列轉存。副本已存。"),), when=report)

    source.add("ch3_t_c06_board", "C06", (
        ("label", "護理表N17：月報十七同批，三十日白班與晚班的追蹤，統計單位是不同編號的人。"),
        ("label", "白班有十一個編號：R17-001、004、009，加上轉存的那八個。"),
        ("rin", "公開頁的三個人，再加上轉存的八個。"),
        ("label", "晚班也是同樣十一個編號。交班檢視共二十二次，十一名在三十日仍需持續護理。"),
        ("lamp", "用編號去重，再看轉出去的八個是不是仍在這個月裡。")),
        when=all_of(access, negate(roster)), options=(
            _opt("eleven", "照不同編號計：十一名。", "ch3_t_c06_saved", "兩班重複的編號只算一次。"),
            _opt("twentytwo", "照兩班加總：二十二名。", "ch3_t_c06_wrong", "把每一次交班都算成一個人。"),
            _opt("leave", "先離開輪班表。", None, "之後可以再來。")))
    source.add("ch3_t_c06_wrong", "C06", (("label", "同一編號出現在兩班，請計不同編號。目前是十一名，再選一次。"),),
               mode="animated", next_scene="ch3_t_c06_board")
    source.add("ch3_t_c06_saved", "C06", (("rin", "兩班各十一筆，二十二次不是二十二個人。"),),
               mode="animated", completion=(set_flag("ch3_nursing_roster_taken"), grant("ch3_roster_n17")))
    source.add("ch3_t_c06_revisit", "C06", (("label", "輪班表N17：十一個不同編號，兩班合計二十二次。副本已存。"),), when=roster)

    source.add("ch3_t_c07_register", "C07", (
        ("label", "名冊T17：母群是一日建檔的同批一百名，換院不移出本月母群。"),
        ("label", "本站持續護理三名。轉介仍追蹤八名，月底仍達持續護理標準。"),
        ("rin", "報表說不計，名冊卻寫還在追蹤。"),
        ("label", "轉介完成只代表院區轉介，不是治癒，也不是中止記憶耗損。"),
        ("zhi", "換病房的是人，月份沒有跟著換。我能證明這八個還在同批，但對外那頁不是我核發的。")),
        when=all_of(access, negate(register)), options=(
            _opt("save", "儲存名冊的副本。", "ch3_t_c07_saved", "副本可以在筆記裡重看。"),
            _opt("ask", "問轉存帳房是什麼。", "ch3_t_c07_ask", "可選的追問。"),
            _opt("leave", "先離開閱覽櫃。", None, "之後可以再來。")))
    source.add("ch3_t_c07_ask", "C07", (("zhi", "統計交給中央帳房留存，這個櫃檯沒有中央原帳。"),),
               mode="animated", next_scene="ch3_t_c07_register")
    source.add("ch3_t_c07_saved", "C07", (("rin", "八個人還在同一批，名冊我存下來了。"),),
               mode="animated", completion=(set_flag("ch3_followup_register_taken"), grant("ch3_register_t17")))
    source.add("ch3_t_c07_revisit", "C07", (("label", "名冊T17：母群一百名，轉介仍追蹤八名。副本已存。"),), when=register)

    # C08：三份都在手上才能核對；缺哪一份就說去哪裡補。
    pending = negate(reconciled)
    source.add("ch3_t_c08_missing_report", "C08", (("label", "先取公開頁，確認它到底省掉哪一欄。公開報表在閱覽桌上。"),),
               when=all_of(access, pending, negate(report)))
    source.add("ch3_t_c08_missing_roster", "C08", (("label", "先到工作廊核對不同編號，不能把護理次數當人數。"),),
               when=all_of(access, pending, negate(roster)))
    source.add("ch3_t_c08_missing_register", "C08", (("label", "回門邊閱覽櫃核對轉介完成的意思，再來比對。"),),
               when=all_of(access, pending, negate(register)))
    have_all = all_of(access, report, roster, register, pending)
    source.add("ch3_t_c08_population", "C08", (("label", "第一處：同一批還在母群裡的有幾名？"),),
               when=have_all, options=(
                   _opt("hundred", "照名冊：換院不移出，母群仍是一百名。", "ch3_t_c08_nursing", "對照報表頁尾的排除註記。"),
                   _opt("ninetytwo", "把轉存的八名從母群扣掉：九十二名。", "ch3_t_c08_population_wrong", "照公開頁的算法。"),
                   _opt("leave", "先收起資料。", None, "之後可以再來核對。")))
    source.add("ch3_t_c08_population_wrong", "C08", (("label", "名冊仍以原一百名觀察，轉介不把母群改成九十二名。再選一次。"),),
               mode="animated", next_scene="ch3_t_c08_population")
    source.add("ch3_t_c08_nursing", "C08", (("label", "第二處：這一批仍需持續護理的有幾名？"),), options=(
        _opt("eleven", "照輪班表的不同編號：十一名。", "ch3_t_c08_excluded", "公開頁只列三名。"),
        _opt("twentytwo", "照交班次數：二十二名。", "ch3_t_c08_nursing_wrong", "把次數當人數。"),
        _opt("three", "照公開頁：三名。", "ch3_t_c08_nursing_wrong", "只看大字那一格。")))
    source.add("ch3_t_c08_nursing_wrong", "C08", (("label", "輪班表用不同編號計人，兩班重複的只算一次。再選一次。"),),
               mode="animated", next_scene="ch3_t_c08_nursing")
    source.add("ch3_t_c08_excluded", "C08", (("label", "第三處：公開頁少算的八名去了哪裡？"),), options=(
        _opt("tracked", "名冊寫轉介仍追蹤八名：三加八是十一，十一除以一百。", "ch3_t_c08_result", "提交三處核對。"),
        _opt("cured", "轉存的八名已經不需要護理。", "ch3_t_c08_excluded_wrong", "照報表的寫法。")))
    source.add("ch3_t_c08_excluded_wrong", "C08", (("label", "名冊寫轉介完成只是換院區，月底仍達護理標準。再選一次。"),),
               mode="animated", next_scene="ch3_t_c08_excluded")
    source.add("ch3_t_c08_result", "C08", (
        ("rin", "同一批一百個人，有十一個仍需要護理。"),
        ("rin", "公開那頁只算三個，另外八個被寫成轉存。"),
        ("zhi", "你對的是這一批的比例。別拿它當每次死一次就少十一，也別拿我的護理表替你個人的帳簽名。"),
        ("rin", "我沒有個人原帳，先把這八個補回去。"),
        ("lamp", "月報這裡又排掉人。你現在有異議證據，還沒有中央原帳。"),
        ("rin", "我要先問誰負責那張公開表。"),
        ("label", "異議回執：三處核閱一致，公開百分之三與追蹤百分之十一不一致，已要求原發布端回覆。"),
        ("zhi", "這張只開側通道和邊緣電梯，去那邊的接待廊能投遞異議。"),
        ("rin", "不是職員證，我不拿它進病房。"),
        ("zhi", "對，護理內門還是鎖的。晴岸的展示接待也在邊緣層，參觀不等於入住。")),
        mode="animated", completion=(set_flag("ch3_report_reconciled"), transaction("ch3.report_reconciled"),
                                     grant("ch3_petition_receipt"), grant("ch3_mezz_pass")))
    source.add("ch3_t_c08_revisit", "C08", (("label", "三處核對已提交，異議回執在筆記裡。下一步是門禁大廳。"),), when=reconciled)

    # C09 寄存櫃：完全可選，三份資料不放在這裡。
    heard = flag("sq7_ahan_clip_heard")
    held = flag("sq7_ahan_recording_held")
    source.add("ch3_t_c09_drawer", "C09", (
        ("label", "第三個抽屜的帶盒標著：錄音者阿翰，寄存。家屬尋人錄音，可聽片頭，帶出要登記。"),
        ("rin", "這卷有名字，卻沒有收件人。"),
        ("zhi", "阿翰留下給家屬找回線索，片頭同意公開。你想聽就放這臺，不要當月報附件。")),
        when=all_of(access, negate(heard)), options=(
            _opt("play", "播放片頭。", "ch3_t_c09_play", "聽完可以決定借不借。"),
            _opt("leave", "把抽屜關上。", None, "之後可以再來。")))
    source.add("ch3_t_c09_play", "C09", (
        ("ahan", "我是阿翰，你哥哥。哪天妳想不起我，就先聽我把名字說完。"),
        ("ahan", "妳以前會替我留一盞燈。我把這句錄下來，不要妳裝作記得，只想讓妳有一條路找我。"),
        ("rin", "他連對方可能忘掉都預先錄好了。"),
        ("zhi", "你聽見的是他給人的話，別替收件人答應。要帶走我開借出單，找到本人再還。")),
        mode="animated", completion=(set_flag("sq7_ahan_clip_heard"),), next_scene="ch3_t_c09_lend")
    source.add("ch3_t_c09_lend", "C09", (("zhi", "要借出，還是留在櫃裡？"),), options=(
        _opt("lend", "登記借出這卷錄音。", "ch3_t_c09_borrowed", "找到收件人再歸還，不能賣也不能當。"),
        _opt("keep", "先留在第三個抽屜。", "ch3_t_c09_kept", "下次想借再找芷姐。")))
    source.add("ch3_t_c09_borrowed", "C09", (
        ("rin", "我先記借出，不把它當我的。"),
        ("zhi", "拿去找收件人可以，不能賣掉，也別把它交到公開報表裡。")),
        mode="animated", completion=(set_flag("sq7_ahan_recording_held"), grant("ch3_ahan_tape"), transaction("ch3.sq7_tape")))
    source.add("ch3_t_c09_kept", "C09", (
        ("rin", "名字我看見了，先留在這裡。"),
        ("zhi", "下次來還在第三個抽屜，想借再找我。")), mode="animated")
    source.add("ch3_t_c09_lend_again", "C09", (("zhi", "阿翰那卷還在第三個抽屜，要借出嗎？"),),
               when=all_of(heard, negate(held)), options=(
                   _opt("lend", "登記借出這卷錄音。", "ch3_t_c09_borrowed", "找到收件人再歸還。"),
                   _opt("keep", "還是先留著。", None, "抽屜關上。")))
    source.add("ch3_t_c09_revisit", "C09", (("label", "第三個抽屜是空的，借出單寫著凜的名字。"),), when=held)


# ---------------------------------------------------------------------------
# M5c 門禁大廳：C10 登場、C11 戰鬥提示（戰鬥組呼叫）、C12 扶守門人坐回櫃檯
# ---------------------------------------------------------------------------

def _gate_hall(source: ProductionSource):
    intro = flag("ch3_janus_intro_seen")
    disabled = flag("ch3_janus_disabled")
    aftercare = flag("ch3_janus_aftercare_done")
    source.add("ch3_t_c10_scan", "C10", (
        ("janus", "請問您有預約嗎？證件放在臺上，我替您核對。"),
        ("rin", "公開查核完成了，護士給了這張。"),
        ("zhi", "這張有效，讓她過邊緣電梯。"),
        ("janus", "對不起，我這裡還沒核對完，請您先不要走。"),
        ("label", "工作架的螢幕反覆顯示：昨日日程，查無Q17。機械夾閘合上了。"),
        ("zhi", "他記不得新日程，工作架卻一直把拒絕通行當命令。別打人，把外面的門禁架停下。"),
        ("zhi", "診所委託停機處理，一百信用點在停機回執成立時結算。"),
        ("lamp", "盾架擋正面，掃描臂蓄力時可以打斷。背上的通訊器在架子外側，停它就沒有增援。"),
        ("rin", "我停機器，證件放這裡，你不用再問同一遍。"),
        ("janus", "不好意思，請站回等待線。")),
        when=negate(intro), mode="animated", completion=(set_flag("ch3_janus_intro_seen"),))
    source.add("ch3_t_c10_hint", "C10", (
        ("lamp", "只打橙色的外部部件。盾擊撲空三次會裂盾，繞到背後停掉通訊器就沒有增援。"),),
        when=all_of(intro, negate(disabled)))
    source.add("ch3_t_c10_revisit", "C10", (("label", "門禁閘已經斷電，綠燈常亮，閘門開著。"),), when=disabled)
    # 戰鬥中的短句與首次敗北提示（戰鬥組在對應時機播放）。
    source.add("ch3_c11_bark_sorry", "C11", (("janus", "不好意思，我重新核對。"),), mode="radio")
    source.add("ch3_c11_bark_repeat", "C11", (("rin", "他會重複，先看蓄力。"),), mode="radio")
    source.add("ch3_c11_defeat_hint", "C11", (
        ("lamp", "看他蓄力，再打斷橙色的掃描臂。盾擊撲空三次會裂盾，繞背停通訊器就能阻止增援。"),), mode="radio")

    source.add("ch3_t_c12_aftercare", "C12", (
        ("janus", "謝謝光臨，歡迎您再來。"),
        ("rin", "你先坐，門已經開了。"),
        ("zhi", "現在休息，我把牌子放到桌上。"),
        ("janus", "請問您有預約嗎？"),
        ("zhi", "這一筆我核過了，你不用再站起來。"),
        ("zhi", "側路開了，邊緣電梯也是你的證能去的範圍。帶回市場的紙別弄丟。")),
        when=all_of(disabled, negate(aftercare)), mode="animated",
        completion=(set_flag("ch3_janus_aftercare_done"), set_flag("ch3_care_passage_open"), set_flag("m3_available"),
                    transaction("ch3.gate_disabled"), grant("ch3_gate_receipt")))
    source.add("ch3_t_c12_revisit", "C12", (("janus", "請先在等待線後面，我替您核對。"), ("zhi", "他今天不用再站起來了。")),
               when=aftercare, mode="animated")


# ---------------------------------------------------------------------------
# H1 貨架：M3 未署名的記錄（停機後可讀，可選）
# ---------------------------------------------------------------------------

def _memory(source: ProductionSource):
    source.add("ch3_t_m3_record", "M3", (
        ("label", "她談價的時候，指尖總在桌邊敲三下。我提醒過她，她說這樣才能把數字記穩。"),
        ("rin", "這人一直記我的小動作，卻不寫自己是誰。")),
        when=all_of(flag("m3_available"), negate(flag("m3_seen"))), mode="animated", completion=(set_flag("m3_seen"),))
    source.add("ch3_t_m3_revisit", "M3", (("label", "未署名的記錄夾回貨架，紙角有一道摺痕。"),), when=flag("m3_seen"))


# ---------------------------------------------------------------------------
# S1 玻璃邊緣：C13 第一次陽光、C14 白傘遠景
# ---------------------------------------------------------------------------

def _glass_edge(source: ProductionSource):
    source.add("ch3_c13_arrive", "C13", (
        ("rin", "這裡的光，照到地上是暖的。"),
        ("lamp", "你在玻璃內側，外面住宅還沒開。")),
        mode="bubbles", completion=(set_flag("ch3_sunlight_reached"),))
    paused = flag("ch3_sunlight_pause_seen")
    source.add("ch3_t_c13_pause", "C13", (
        ("rin", "原來沒有雨的時候，影子會落得這麼清楚。"),
        ("lamp", "先看夠，診所的紙又不會跑掉。")),
        when=negate(paused), mode="animated", completion=(set_flag("ch3_sunlight_pause_seen"),))
    source.add("ch3_t_c13_revisit", "C13", (("rin", "今天還有光，我先看這一頁。"),), when=paused)
    source.add("ch3_t_c14_view", "C14", (
        ("label", "塔頂花園的遠景：白髮的年長女人撐著白傘，照看盆栽。旁邊的椅子被植栽擋住。"),
        ("rin", "晴天還撐白傘，是怕光還是怕花被曬？"),
        ("lamp", "從這裡看不清，我不替她答。接待桌在展示門裡面。")), mode="animated")


# ---------------------------------------------------------------------------
# S2 晴岸樣品房：C15 接待、C16 三扇窗與提案（SQ3-C1）、C17 細問
# ---------------------------------------------------------------------------

ROOMS = (
    ("morning", "A 晨窗", (
        ("rin", "早上先照到椅背，老 K 起來時就能看見。"),
        ("rin", "窗臺也放得下一個碗。"),
        ("lin", "這間偏晨光，上午八到十點最亮，下午有遮陰。您先試坐，不用只看我那張圖。")),
     "A 晨窗量過了：早上最亮，下午有遮陰。"),
    ("quiet", "B 靜窗", (
        ("rin", "窗不對主路，吃飯時大概不用一直聽車。"),
        ("lin", "這間少直曬，靠反光也很亮。安靜有人喜歡，也有人睡不著。"),
        ("rin", "他在店裡連滴水都聽得出。"),
        ("rin", "我先記下，不能當他一定喜歡。")),
     "B 靜窗量過了：這間少有直射的陽光，路上的聲音也比較低。"),
    ("late", "C 晚窗", (
        ("rin", "下午才亮，他忙完貨架也能坐一下。"),
        ("rin", "我把椅子靠裡，別讓光直接照眼睛。"),
        ("lin", "這間下午兩到四點最亮，夏天更要用遮陽板。他還沒坐過這張椅子吧？"),
        ("rin", "還沒有，我先留一個提案。")),
     "C 晚窗量過了：這間下午最亮，夏天要用遮陽板。"),
)


def _showroom(source: ProductionSource):
    started = flag("ch3_clearwater_tour_started")
    done = flag("ch3_clearwater_tour_done")
    measured = {room: flag(f"room_{room}_measured") for room, _name, _lines, _note in ROOMS}
    any_measured = any_of(*measured.values())
    source.add("ch3_t_c15_welcome", "C15", (
        ("lin", "不好意思，雨具可以先放在門旁，地上才不會滑。您沒帶傘，我替您拿張擦水布。"),
        ("rin", "不用替我找傘，我來看晴岸的房。"),
        ("lin", "我是晴岸的林小姐，負責這層樣品房。這裡是展示，不是入住，您可以先坐一下。"),
        ("rin", "這張是診所的異議回執，不是購房申請。"),
        ("rin", "先幫我投到相鄰的天穹接待廊。")),
        when=negate(started), options=(
            _opt("post", "把異議回執放進公文格投遞。", "ch3_t_c15_posted", "林小姐蓋收件章，看房不用先交訂金。"),
            _opt("later", "先不投遞。", None, "之後可以再來。")))
    source.add("ch3_t_c15_posted", "C15", (
        ("lin", "公開查核件下午轉風控接待，不用跟房間綁在一起。看房也不需要先交訂金。"),
        ("rin", "三間都寫四十八萬，差的是窗？"),
        ("lin", "三間總價都是四十八萬，差朝向、光照時間和安靜程度。入住要本人看過，我今天不請您簽。"),
        ("lin", "您可以量窗臺、試坐，記下想帶誰再來。也可以今天先不選。"),
        ("rin", "我替老 K 先算算，他老嫌店裡光太少。")),
        mode="animated", completion=(set_flag("ch3_clearwater_tour_started"), grant("ch3_tour_card")))
    source.add("ch3_t_c15_hub", "C15", (("lin", "三間都看完了嗎？想記提案、問別的，或先離開都可以。"),),
               when=all_of(started, negate(done)), options=(
                   _opt("propose", "把看過的一間記作房間提案。", "ch3_dispatch_proposal", "只記提案，不簽約、不扣款。", when=any_measured),
                   _opt("ask", "問林小姐每天在這裡的事。", "ch3_t_c17_ask", "可選的細問。", when=negate(flag("ch3_lin_asked"))),
                   _opt("finish", "看完了，去取異議收件回執。", "ch3_t_c17_leave", "看房卡和公文分開收。", when=any_measured),
                   _opt("leave", "先去看窗。", None, "三扇窗可以照任意順序量。")))
    source.add("ch3_t_c16_locked", "C16", (("label", "林小姐先請您到接待桌登記看房。"),), when=negate(started))
    for room, name, lines, note in ROOMS:
        source.add(f"ch3_t_c16_{room}", "C16", lines, when=all_of(started, negate(measured[room])), mode="animated",
                   completion=(set_flag(f"room_{room}_measured"),))
        source.add(f"ch3_t_c16_{room}_revisit", "C16", (("label", note),), when=measured[room])
    choices = tuple(
        _opt(room, f"把{name}記作提案。", "ch3_t_c16_proposed", "林小姐在看房卡寫提案，這不是預留名額。",
             when=measured[room], intent=(set_flag("room_choice", room),)) for room, name, _lines, _note in ROOMS)
    source.add("ch3_t_c16_propose", "C16", (("label", "只記房間提案，不簽約、不扣款。老 K 仍可親自改選。"),),
               when=negate(flag("sq3_room_proposal_done")),
               options=choices + (_opt("none", "三間我先記差別，今天不填房間。", "ch3_t_c16_none", "房間提案留空。"),))
    source.add("ch3_t_c16_proposed", "C16", (
        ("rin", "我先記這間，回去不把它說成他已經答應。"),
        ("lin", "我在您的看房卡寫提案，這不是預留名額。")),
        mode="animated", completion=(set_flag("sq3_room_proposal_done"), transaction("ch3.sq3_room")))
    source.add("ch3_t_c16_repropose", "C16", (("label", "改提案只換看房卡上的房名，沒有新的獎勵。"),),
               when=flag("sq3_room_proposal_done"),
               options=tuple(_opt(o.id, o.text, "ch3_t_c16_reproposed", "只換卡上的房名。", when=o.when, intent=o.intent) for o in choices)
               + (_opt("keep", "不改了。", None, "提案維持原樣。"),))
    source.add("ch3_t_c16_reproposed", "C16", (("lin", "好的，我只換看房卡上的房名，其他內容都不變。"),), mode="animated")
    source.add("ch3_t_c16_none", "C16", (
        ("rin", "三間我先記差別，今天不替他填房間。"),
        ("lin", "可以，下次帶本人坐過再決定。")), mode="animated")

    source.add("ch3_t_c17_ask", "C17", (
        ("rin", "有人太安靜睡不著，妳每天都聽這些？"),
        ("lin", "我每天開展示窗，椅子有沒有挪過，我都知道。有些人怕的是忽然什麼聲音都沒了。"),
        ("rin", "我只把漏水算成壞掉，沒把聲音也算進去。"),
        ("lin", "您可以把這一句帶回去問，但不用現在替他回答。")),
        mode="animated", completion=(set_flag("ch3_lin_asked"),))
    source.add("ch3_t_c17_leave", "C17", (
        ("lin", "不好意思，您的公文回執在候梯廊的取件格。從那邊回電梯，比再走展示房近。"),
        ("rin", "房間是提案，診所是異議，我不夾成同一筆。")),
        mode="animated", completion=(set_flag("ch3_clearwater_tour_done"),))
    source.add("ch3_t_c17_revisit", "C17", (("lin", "回執在候梯廊的取件格。三扇窗都還在，想再量隨時可以。"),), when=done,
               options=(
                   _opt("propose", "調整房間提案。", "ch3_dispatch_proposal", "只記提案，不簽約。", when=any_measured),
                   _opt("leave", "先這樣。", None, "結束對話。")))


# ---------------------------------------------------------------------------
# S3 天穹辦公接待廊：C18 取回執、C19 手背的字（SQ7-G2）、C20 交易、C21 回去的路
# ---------------------------------------------------------------------------
# 正式過場（偷聽戲）的分鏡規則，參考與取捨見 design/13-story-v2/CH03_OFFICE_STAGING.md：
# 1. 先用全景交代誰在哪：凜在門外走廊、老 K 與葉在玻璃會議室裡，門縫透出光。
# 2. 室內的談話用「隔著玻璃」的鏡頭：窗框與玻璃反光畫在演員前面，台詞用低語（灰字、慢速），字幕一律保留。
# 3. 每兩三句切回凜的反應鏡頭；情緒放在聽的人身上，不放在說的人身上。
# 4. 談話中段讓玩家選：忍住聽完、伸手推門（燈叫住她）或先退開；退開後回等候臺從中段接著聽，不重播前半。
# 5. 最後停在凜身上收尾。

OFFICE_STAGE = "ch3_office_hall"
# 舞台座標量自 art/environment/scenes/tianqiong_corridor.webp（1536×864 縮 0.5 鋪滿，-64..704 × -36..396）：
# 走廊地面從 y≈296 開始，凜站在 300；玻璃會議室的底框在 285～294，室內的人站在 285（底框剛好碰到鞋底）。
# 側門在 x 521～651，門縫在左緣；玻璃牆的直框在 187、307.5、419.5，玻璃在 514 結束。
OFFICE_FLOOR = 300
OFFICE_INSIDE = 285
# 身高（骨架站立高 × 縮放）：凜 58.3 × 2.95 ≈ 172，接近門高 227 的四分之三（約 1.6 公尺）；
# 室內兩人在玻璃後一兩公尺，縮放 2.4（約 135～140）。
OFFICE_CAST = {"rin": (595, OFFICE_FLOOR, 2.95), "old_k": (245, OFFICE_INSIDE, 2.4), "ye": (360, OFFICE_INSIDE, 2.4)}
# 鏡頭：(x, y, 縮放, 這個鏡頭裡最低的腳底線)。x 的範圍讓畫面不超出立繪；室內鏡頭讓凜留在畫面外（她不在這個鏡頭裡）。
OFFICE_SHOTS = {
    "wide": (330, 243.5, 0.88, OFFICE_FLOOR),
    "rin": (399, 254, 1.05, OFFICE_FLOOR),
    "inside": (285, 250, 1.2, OFFICE_INSIDE),
    "ye": (300, 250, 1.2, OFFICE_INSIDE),
}
# 舞台立繪壓暗一階：走廊與窗外都是白色，角色的白髮與淺色衣服才不會糊成一片（同 NE-251 的處理）。
OFFICE_TONE = (0.769, 0.8, 0.839)


def _toned(rgb) -> str:
    return "#%02x%02x%02x" % tuple(round(c * t) for c, t in zip(rgb, OFFICE_TONE))


def office_stage() -> dict:
    """辦公接待廊的舞台資料（data/cutscene/stages/ch3_office_hall.json 由 build_ch3_story.py 寫出）。
    窗框、底框與反光畫在演員前面（depth front），室內的人看起來在玻璃後面；凜站在玻璃結束之後，不會被蓋到。"""
    glass_top, trim_top, trim_bottom, glass_end = 42, OFFICE_INSIDE, 294, 516
    mullion = _toned((195, 208, 218))
    front = lambda layer: dict(layer, depth="front")  # noqa: E731
    layers = [
        {"kind": "gradient", "top": "#141c26", "bottom": "#222c38", "parallax": 0.0},
        # 立繪下緣在 396；全景鏡頭的下緣多露出幾個像素，用同色的地板補上。
        {"kind": "rect", "rect": [-200, 392, 1040, 160], "color": _toned((238, 238, 238))},
        {"kind": "sprite", "path": "res://art/environment/scenes/tianqiong_corridor.webp", "pos": [-64, -36.0], "scale": 0.5,
         "filter": "linear", "source_width": 1536, "modulate": _toned((255, 255, 255))},
        # 會議室裡的午後陽光；走廊這一側壓暗，偷聽的人站在暗處。
        {"kind": "glow", "pos": [250, 150], "radius": 260, "color": "#ffe6bf", "intensity": 0.7, "additive": True, "alpha": 0.2,
         "pulse": 0.05, "pulse_depth": 0.15},
        {"kind": "glow", "pos": [640, 230], "radius": 240, "color": "#0c121b", "intensity": 1.0, "alpha": 0.45},
        # 側門開了一道縫：左緣一條暗縫，縫裡透出會議室的冷光，在走廊地上拉出一道光。
        {"kind": "poly", "points": [[521, 66], [527, 66], [527, 293], [521, 293]], "color": "#2e3640"},
        {"kind": "poly", "points": [[524.5, 70], [526, 70], [526, 292], [524.5, 292]], "color": "#e8f2ff", "alpha": 0.85},
        {"kind": "poly", "points": [[521, 294], [527, 294], [566, 340], [500, 340]], "color": "#e8f2ff", "alpha": 0.18},
        {"kind": "glow", "pos": [525, 200], "radius": 46, "color": "#dcecff", "intensity": 0.6, "additive": True, "alpha": 0.3},
        {"kind": "motes", "count": 18, "color": "#fff4dc", "opacity": 0.25, "area": [0, 80, 510, 200], "drift": [1, -2], "size": 1.0, "seed": 31},
        # 以下在演員前面：玻璃牆的直框、玻璃結束的立柱、底框與反光。
        front({"kind": "rect", "rect": [186, glass_top, 2, trim_top - glass_top], "color": mullion}),
        front({"kind": "rect", "rect": [306.5, glass_top, 2, trim_top - glass_top], "color": mullion}),
        front({"kind": "rect", "rect": [418.5, glass_top, 2, trim_top - glass_top], "color": mullion}),
        front({"kind": "rect", "rect": [512, glass_top, 4, trim_bottom - glass_top], "color": _toned((230, 233, 234))}),
        front({"kind": "rect", "rect": [-64, trim_top, glass_end + 64, trim_bottom - trim_top], "color": _toned((173, 183, 193))}),
        front({"kind": "rect", "rect": [-64, trim_top + 1, glass_end + 64, 1.5], "color": _toned((243, 246, 248))}),
        front({"kind": "poly", "points": [[-64, glass_top], [glass_end, glass_top], [glass_end, trim_top], [-64, trim_top]],
               "color": "#e6f0fa", "alpha": 0.07}),
        front({"kind": "poly", "points": [[70, glass_top], [118, glass_top], [40, trim_top], [-8, trim_top]], "color": "#ffffff", "alpha": 0.08}),
        front({"kind": "poly", "points": [[330, glass_top], [350, glass_top], [282, trim_top], [262, trim_top]], "color": "#ffffff", "alpha": 0.06}),
    ]
    # floors：玻璃牆後的會議室地面（舞台檢查據此判斷室內的人站在地上，不是浮空）。
    return {"camera": {"pos": list(OFFICE_SHOTS["wide"][:2]), "zoom": OFFICE_SHOTS["wide"][2]}, "floor": OFFICE_FLOOR,
            "floors": [OFFICE_INSIDE], "layers": layers}


def _cut(shot: str, fade: float = 0.0) -> dict:
    """換到某個鏡頭（舞台重建，fade 0 是硬切）。之後要重新放演員。"""
    x, y, zoom, feet = OFFICE_SHOTS[shot]
    return stage_scene(OFFICE_STAGE, x=x, y=y, zoom=zoom, fade_in=fade, feet=feet)


def _pan(shot: str, t: float = 1.4, wait_for: bool = True) -> dict:
    """在同一個舞台上把鏡頭推到某個鏡頭（不重建演員）。"""
    x, y, zoom, feet = OFFICE_SHOTS[shot]
    return stage_cam(x, y, zoom, t=t, wait_for=wait_for, feet=feet)


def _cast(*who: str, rin_x: float | None = None, rin_pose: str | None = None, ye_loop: str | None = None) -> list[dict]:
    facing = {"rin": -1, "old_k": 1, "ye": -1}
    steps = []
    for ident in who:
        x, y, scale = OFFICE_CAST[ident]
        if ident == "rin" and rin_x is not None:
            x = rin_x
        steps.append(stage_actor(ident, ident, x, y, facing=facing[ident], scale=scale, speaker=ident, weapon="",
                                 pose=rin_pose if ident == "rin" else None, loop=ye_loop if ident == "ye" else None))
    return steps


def _shot(shot: str, *who: str, fade: float = 0.0, **cast) -> list[dict]:
    return [_cut(shot, fade)] + _cast(*who, **cast)


def _hear(speaker: str, text: str) -> dict:
    """門縫聽到的話：低語（灰字、慢速），字幕照常顯示。"""
    return stage_say(speaker, text, style="whisper")


def _office(source: ProductionSource):
    receipt = flag("ch3_petition_receipt_taken")
    seen = flag("ye_handwriting_seen")
    traded = flag("ch3_trade_overheard")
    name_seen = flag("sq7_ye_name_seen")
    half = flag("ch3_trade_half_heard")
    listened = flag("ch3_trade_listened")
    say_ = beats
    # C18：全景交代位置。凜在門外拿回執，老 K 從會議室另一頭走進來；鏡頭再推到凜身上。
    source.add("ch3_t_c18_box", "C18", steps=[
        *_shot("wide", "rin", "ye", fade=1.0),
        stage_sfx("pickup", -10),
        *say_(("label", "取件格的回執寫著：風控接待收件，月報17查核件。")),
        stage_actor("old_k", "old_k", -60, OFFICE_INSIDE, facing=1, scale=OFFICE_CAST["old_k"][2], speaker="old_k", weapon=""),
        stage_move("old_k", OFFICE_CAST["old_k"][0], OFFICE_INSIDE, t=3.2, wait_for=False),
        *say_(("label", "側門開了一道縫，老 K 收起來客卡，走到葉的桌前。")),
        _pan("rin", t=1.6),
        *say_(("rin", "他叫我別上來，自己卻在這裡。")),
        stage_pose("rin", "listen"),
        _hear("lamp", "我只知道你那張公文送到了，裡面的約不是我排的。")],
        when=negate(receipt), mode="animated",
        completion=(set_flag("ch3_petition_receipt_taken"), set_flag("ch3_k_at_office_seen"), grant("ch3_intake_receipt")),
        next_scene="ch3_t_c19_watch")
    source.add("ch3_t_c18_revisit", "C18", (("label", "取件格空了，回執已經收在筆記裡。"),), when=receipt)

    source.add("ch3_t_c19_early", "C19", (("label", "候梯迴廊的等候臺。公文取件格在左邊。"),), when=negate(receipt))
    # C19：隔著玻璃看葉的手。鏡頭往葉推一點，看完切回凜。
    source.add("ch3_t_c19_watch", "C19", steps=[
        *_shot("inside", "old_k", "ye", "rin", fade=0.25, rin_pose="listen", ye_loop="read_note"),
        _pan("ye", t=2.2, wait_for=False),
        *say_(("label", "葉把透明傘掛在桌旁，停筆，把手背翻向自己，補了一行字才翻開檔案。")),
        stage_pose("ye", "idle", loop=""),
        stage_wait(0.5),
        *_shot("rin", "old_k", "ye", "rin", rin_pose="listen"),
        *say_(("rin", "她先在手上補字，才繼續談。")),
        _hear("lamp", "你看到她的習慣，還不知道她為什麼這樣做。")],
        when=all_of(receipt, negate(seen)), mode="animated", completion=(set_flag("ye_handwriting_seen"),),
        next_scene="ch3_t_c19_choice")
    source.add("ch3_t_c19_choice", "C19", steps=[
        *_shot("rin", "old_k", "ye", "rin", fade=0.25, rin_pose="listen"),
        *say_(("label", "門縫裡的談話聽得見。等候臺靠著實牆，可以停在這裡。"))],
               when=all_of(seen, negate(traded)), options=(
                   _opt("read", "看清葉手背上那一行。", "ch3_dispatch_c19_read", "可選，看清就記下這個名字。", when=negate(name_seen)),
                   _opt("listen", "留下，聽完這段談話。", "ch3_t_c20_trade", "安全的過場，聽完要自己確認記錄。"),
                   _opt("leave", "先退回樣品房。", None, "之後可以再來。")))

    def read_name(last_line):
        return [*_shot("ye", "old_k", "ye", "rin", fade=0.25, rin_pose="listen", ye_loop="read_note"),
                *say_(("label", "葉的手背上寫著一行字：「他叫阿翰。你愛他。」")),
                *_shot("rin", "old_k", "ye", "rin", rin_pose="listen"),
                *say_(("rin", "她把一個名字寫在身上，像怕它不見。"), ("rin", last_line))]
    source.add("ch3_t_c19_read_tape", "C19", steps=read_name("抽屜那捲也寫阿翰，我還沒有問過她。"),
               when=all_of(flag("sq7_ahan_clip_heard"), negate(name_seen)), mode="animated",
               completion=(set_flag("sq7_ye_name_seen"), transaction("ch3.sq7_name")), next_scene="ch3_t_c19_choice")
    source.add("ch3_t_c19_read_new", "C19", steps=read_name("我先記這個名字，不替他們猜關係。"),
               when=all_of(negate(flag("sq7_ahan_clip_heard")), negate(name_seen)), mode="animated",
               completion=(set_flag("sq7_ye_name_seen"), transaction("ch3.sq7_name")), next_scene="ch3_t_c19_choice")

    # C20 前半：條件與交付。室內兩句、凜的反應、室內兩句，最後一句推近再切回凜。
    source.add("ch3_t_c20_trade", "C20", steps=[
        *_shot("inside", "old_k", "ye", "rin", fade=0.25, rin_pose="listen"),
        _hear("old_k", "妳收了她那份備份，我不是來賣第二次。你們排外勤前，先看清她會碰到什麼。"),
        _hear("ye", "資料在天穹保管，交付人是你。這一點沒有改。"),
        *_shot("rin", "old_k", "ye", "rin", rin_pose="listen"),
        stage_wait(0.9),
        *_shot("inside", "old_k", "ye", "rin", rin_pose="listen"),
        _hear("old_k", "妳上次答應的條件，不是讓她一直去換命。我今天要你把危險的派案停掉。"),
        _hear("ye", "樣本要活著，研究才有意義。我可以撤掉清理區的排案，不能答應所有街上都安全。"),
        stage_cam(260, 250, 1.2, t=1.8, wait_for=False, feet=OFFICE_INSIDE),
        stage_wait(0.6),
        _hear("old_k", "她不知道那份資料是我交的，妳別把這個拿到她面前。"),
        *_shot("rin", "old_k", "ye", "rin"),
        stage_wait(1.1)],
        when=all_of(seen, negate(half)), mode="animated", completion=(set_flag("ch3_trade_half_heard"),),
        next_scene="ch3_t_c20_middle")
    # 中段的選擇：情緒先給玩家表達（推門會被燈叫住，不懲罰）；退開後回等候臺從這裡接著聽。
    source.add("ch3_t_c20_middle", "C20", steps=[
        *_shot("rin", "old_k", "ye", "rin", fade=0.25),
        *say_(("rin", "原來那份資料是他親手交出去的。"))],
        when=all_of(half, negate(listened)), options=(
            _opt("stay", "忍住，聽他們說完。", "ch3_t_c20_rest", "安全的過場，他們不會發現你。"),
            _opt("door", "伸手推門。", "ch3_t_c20_hold", "想進去當面問；燈會先叫住你。"),
            _opt("leave", "先退開，晚點再回來聽。", None, "之後回等候臺，從這裡接著聽。")))
    source.add("ch3_t_c20_hold", "C20", steps=[
        *_shot("rin", "old_k", "ye", "rin", fade=0.25),
        stage_move("rin", 560, OFFICE_FLOOR, t=0.6),
        _hear("lamp", "現在推門，他們會換一套說法。你要聽的是他們以為沒人在時說的話。"),
        stage_pose("rin", "listen"),
        *say_(("rin", "我知道，我先聽完再說。"))],
        when=all_of(half, negate(listened)), mode="animated", next_scene="ch3_t_c20_rest")
    # C20 後半：協議與月報異議。葉提到異議時推近，老 K 說要回去時凜退開一步，最後停在凜身上。
    source.add("ch3_t_c20_rest", "C20", steps=[
        *_shot("inside", "old_k", "ye", "rin", fade=0.25, rin_pose="listen"),
        _hear("ye", "你把資料交來，換的條件也已經執行。這件事不是她同意過的，我不替你把它說成同意。"),
        _hear("old_k", "我知道她沒答應，我沒讓她看。"),
        *_shot("rin", "old_k", "ye", "rin", rin_pose="listen"),
        stage_wait(0.8),
        {"do": "branch", "requires_flag": "sq7_ye_name_seen",
         "steps": [stage_say("rin", "她手背上記著要記得的人，說到我卻只說樣本。")], "else_steps": []},
        *_shot("inside", "old_k", "ye", "rin", rin_pose="listen"),
        _hear("ye", "那就先履行眼前的條件。你守原協議，我保留既有安排，別讓她碰這份協議。"),
        _hear("old_k", "不要再把她送到會死的地方。"),
        _pan("ye", t=1.6, wait_for=False),
        stage_wait(0.4),
        _hear("ye", "我剛收到一份月報異議。有人把排除欄對出來了，你家那位也會對紙。"),
        *_shot("rin", "old_k", "ye", "rin", rin_pose="listen"),
        stage_wait(0.7),
        _hear("old_k", "這張你回你的，我回去跟她說。"),
        stage_move("old_k", 420, OFFICE_INSIDE, t=1.6, wait_for=False),
        stage_move("rin", 640, OFFICE_FLOOR, t=0.8),
        _hear("ye", "回覆只能走收件人，不替你撤。"),
        stage_face("old_k", -1),
        stage_move("old_k", -60, OFFICE_INSIDE, t=3.0, wait_for=False),
        stage_wait(1.4)],
        when=all_of(half, negate(listened)), mode="animated", completion=(set_flag("ch3_trade_listened"),), next_scene="ch3_t_c20_react")
    source.add("ch3_t_c20_react", "C20", steps=[
        *_shot("rin", "ye", "rin", fade=0.25, rin_x=640),
        *say_(("rin", "他拿我的備份談條件，回家卻只說吃飯。"),
              ("lamp", "我聽到的是交付與條件，價碼和原因還沒說清。我沒有這份協議。"),
              ("rin", "我現在不問他，先把今天聽到的記下來。"))],
        when=all_of(listened, negate(traded)), options=(
            _opt("record", "把聽到的談話記進筆記。", "ch3_t_c20_recorded", "只記今天聽到的，不闖進辦公室。"),
            _opt("later", "先站一下再記。", None, "之後回等候臺確認記錄。")))
    source.add("ch3_t_c20_recorded", "C20", steps=[
        *_shot("rin", "ye", "rin", fade=0.25, rin_x=640),
        *say_(("rin", "我收起筆記從候梯廊回去，不進辦公室。")),
        stage_face("rin", 1),
        stage_move("rin", 760, OFFICE_FLOOR, t=1.8)],
        mode="animated", completion=(set_flag("ch3_trade_overheard"), grant("ch3_trade_note")),
        next_scene="ch3_t_c21_route")
    source.add("ch3_t_c20_revisit", "C20", steps=[
        *_shot("rin", "ye", "rin", fade=0.25),
        *say_(("label", "辦公內門關著，裡面已經沒有說話聲。"))], when=traded, options=(
        _opt("read", "看清葉留在手背上的那一行。", "ch3_dispatch_c19_read", "可選，剛才沒看清的話。", when=negate(name_seen)),
        _opt("leave", "從候梯迴廊回去。", None, "回當舖吃飯。")))
    source.add("ch3_t_c21_route", "C21", (
        ("lamp", "貨梯與護理外廊都通了，沿邊緣電梯下去，從廣場回家。交通終端還沒啟用，我先把步行路標接好。"),
        ("rin", "那張護理表能不能傳回去？"),
        ("lamp", "你儲存的副本放在筆記，公開原表仍由診所保管。先回當舖吃飯。")),
        mode="animated", completion=(set_flag("ch3_l2_route_announced"),))


# ---------------------------------------------------------------------------
# H1／H2 傍晚：C22 留飯與兩次問傘、C23 鷺的通訊
# ---------------------------------------------------------------------------

def _evening(source: ProductionSource):
    traded = flag("ch3_trade_overheard")
    supper = flag("ch3_home_supper_done")
    source.add("ch3_t_c22_door", "C22", steps=_staged("kitchen", (
        ("old_k", "回來了喔，帶傘了嗎？"),
        ("rin", "沒有，貨梯那邊淋了一點。"),
        ("rin", "今天的，字怎麼抖得這麼厲害？"),
        ("old_k", "紙受潮了，筆寫不太出來。先把飯端出來，別連鍋也算進帳。"),
        ("old_k", "診所那張紙看到了？"),
        ("rin", "公開那頁跟護理表對不上，我有異議回執。"),
        ("old_k", "晴岸也看了？"),
        ("rin", "看了樣品房，沒有簽約。")), opening=True),
        when=all_of(traded, negate(supper), negate(flag("ch3_umbrella_asked_twice"))), mode="animated",
        next_scene="ch3_dispatch_c22_room")
    source.add("ch3_t_c22_room_set", "C22", steps=_staged("kitchen", (
        ("rin", "窗我先留提案，還沒當你答應。"),
        ("old_k", "有空再說，飯先吃喔。")), opening=False),
        when=negate(flag("room_choice", "unset")), mode="animated", next_scene="ch3_t_c22_second")
    source.add("ch3_t_c22_room_unset", "C22", steps=_staged("kitchen", (
        ("rin", "幾扇窗不一樣，我先沒填房間。"),
        ("old_k", "有空再說，飯先吃喔。")), opening=False),
        when=flag("room_choice", "unset"), mode="animated", next_scene="ch3_t_c22_second")
    twice = flag("ch3_umbrella_asked_twice")
    source.add("ch3_t_c22_second", "C22", steps=_staged("kitchen", (
        ("old_k", "帶傘了嗎？"),
        ("rin", "剛才我說沒有。"),
        ("rin", "下次要不要帶，等出門再問。"),
        ("old_k", "好，那就等出門的時候再問。飯還熱著，今天先吃吧。")), opening=False),
        when=negate(supper), mode="animated", completion=(set_flag("ch3_umbrella_asked_twice"),), next_scene="ch3_t_c22_note")
    source.add("ch3_t_c22_note", "C22", steps=_staged("kitchen", (("label", "交易的記錄還夾在筆記內頁。"),), opening=False),
               when=all_of(twice, negate(supper)), options=(
                   _opt("note", "把交易記錄先收進筆記內頁。", "ch3_t_c22_done", "不在飯桌上說辦公廊的事。"),
                   _opt("wait", "先吃飯，等一下再收。", None, "之後再找老 K。")))
    source.add("ch3_t_c22_done", "C22", (("rin", "先吃飯，紙收好了。"),),
               mode="animated", completion=(set_flag("ch3_home_supper_done"),))
    source.add("ch3_t_c22_revisit", "C22", (("old_k", "碗洗過放左邊喔，索引別壓在水壺下面。"),), when=supper)

    call = flag("ch3_egret_call_heard")
    agreed = flag("ch3_next_sunday_agreed")
    source.add("ch3_t_c23_quiet_day", "C23", (("label", "鷺說過今天不接案，傍晚才會聯絡。先回家吃飯。"),), when=negate(supper))
    source.add("ch3_t_c23_call", "C23", (
        ("egret", "今天我不接案，還是想問你一句，月報查到了嗎？"),
        ("rin", "同批一百人，實際要護理的有十一個，公開只算三個。"),
        ("rin", "轉出去那八個被排掉了。"),
        ("egret", "這張夠證明少算人，不夠知道每次的讀取記在哪裡。中央帳本不在公開櫃，我想拿真正的那一本。"),
        ("rin", "我不想再拿一張轉存欄猜下一張。")),
        when=all_of(supper, negate(call)), options=(
            _opt("tell", "告訴鷺老 K 交過備份。", "ch3_t_c23_tell", "說出今天在辦公廊聽到的。"),
            _opt("report", "先只說報表。", "ch3_t_c23_report", "辦公廊的事先留在筆記裡。"),
            _opt("later", "等一下再回鷺。", None, "之後可以再接通訊。")))
    source.add("ch3_t_c23_tell", "C23", (
        ("rin", "我聽到老 K 承認，以前把我的備份交給了葉。"),
        ("rin", "他們有條件，價錢我沒聽到。"),
        ("egret", "他承認了交易，原因還沒說清。先拿原帳再問。")),
        mode="animated", completion=(set_flag("ch3_told_egret_trade"), set_flag("ch3_egret_call_heard")), next_scene="ch3_t_c23_invite")
    source.add("ch3_t_c23_report", "C23", (("egret", "你今晚說得很仔細，剩的沒說也先留在你本子裡。"),),
               mode="animated", completion=(set_flag("ch3_egret_call_heard"),), next_scene="ch3_t_c23_invite")
    source.add("ch3_t_c23_invite", "C23", (
        ("egret", "下個週日到夾層病房外櫃檯找我。我先走我熟的轉介路，你帶三張副本與異議回執。"),
        ("rin", "你不是週日不接案？"),
        ("egret", "我那天本來就去見一個人。見完再一起查，不把那次見面也算成工作。")),
        when=all_of(call, negate(agreed)), options=(
            _opt("agree", "下週日先去病房外櫃檯核對轉介。", "ch3_t_c23_agreed", "確認後本章結束。"),
            _opt("later", "先收好，回頭確認。", None, "之後可以再接通訊確認。")))
    source.add("ch3_t_c23_agreed", "C23", (
        ("rin", "我會帶副本，沒有名字那一頁也留著。"),
        ("egret", "來之前吃飯，別把查帳當晚餐。"),
        ("lamp", "我把日期記成下一個週日，病房位置先只標外櫃檯。裡面的來訪權到時再核。")),
        mode="animated", completion=(set_flag("ch3_next_sunday_agreed"), set_flag("ch3_shore_closed")))
    source.add("ch3_t_c23_revisit", "C23", (("label", "通訊器的日期記在下一個週日：夾層病房外櫃檯。"),), when=agreed)


# ---------------------------------------------------------------------------
# 任務（劇本第 5 節）
# ---------------------------------------------------------------------------

def _quests(source: ProductionSource):
    q = source.quests
    q.append(Quest("ch3_clinic", "main", "到夾層診所查月報十七", "前章的原帳只有索引，月報十七的原表在夾層診所。", "公開核閱號Q17。", "ch3_clinic_access", (
        QuestStep("和老 K 吃完早飯，確認出門。", "ch3_departure_done", "old_k"),
        QuestStep("查看廣場的貨梯控制箱。", "ch3_interlock_seen", "control_box"),
        QuestStep("在泵室上橋轉排水輪，把水排到低線。", "ch3_pump_low", "drain_wheel"),
        QuestStep("在泵室配電盤關掉浸水支路，接通主路。", "ch3_lift_powered", "branch_panel"),
        QuestStep("回控制箱叫下貨梯車廂。", "ch3_freight_ready", "control_box"),
        QuestStep("在診所櫃檯出示月報十七的索引。", "ch3_clinic_access", "zhi"))))
    q.append(Quest("ch3_reconcile", "main", "核對三份公開資料", "公開報表排除了轉存者，要確認同一批人和護理狀態。", "核閱異議處理報酬一百八十信用點。",
                   "ch3_report_reconciled", (
                       QuestStep("在閱覽桌儲存公開報表。", "ch3_public_report_taken", "report"),
                       QuestStep("在工作廊核對護理輪班表。", "ch3_nursing_roster_taken", "roster"),
                       QuestStep("在門邊閱覽櫃查追蹤名冊。", "ch3_followup_register_taken", "register"),
                       QuestStep("在閱覽桌確認三處核對，提出異議。", "ch3_report_reconciled", "reading_desk")),
                   visible_flags=("ch3_clinic_access",)))
    q.append(Quest("ch3_gate", "main", "解除診所門禁裝置", "證件有效，舊的門禁工作架仍然拒絕放行。", "停機處理報酬一百信用點。", "ch3_janus_aftercare_done", (
        QuestStep("在門禁大廳掃夾層證。", "ch3_janus_intro_seen", "scanner_gate"),
        QuestStep("停下門禁工作架，扶守門人坐回櫃檯。", "ch3_janus_aftercare_done", "gatekeeper")),
        visible_flags=("ch3_report_reconciled",)))
    q.append(Quest("ch3_petition", "main", "到晴岸展示層投遞異議", "風控接待在玻璃邊緣的展示層旁邊。", "異議送達風控接待。", "ch3_petition_receipt_taken", (
        QuestStep("在晴岸接待桌投遞異議回執。", "ch3_clearwater_tour_started", "lin"),
        QuestStep("看過至少一扇展示窗，向林小姐確認看完。", "ch3_clearwater_tour_done", "lin"),
        QuestStep("在候梯迴廊的取件格拿回執。", "ch3_petition_receipt_taken", "petition_box")),
        visible_flags=("ch3_janus_aftercare_done",)))
    q.append(Quest("ch3_k_office", "main", "查清老 K 在辦公廊做什麼", "取回執的路上看見老 K 走進葉的辦公室。", "知道他今天上來的原因。", "ch3_trade_overheard", (
        QuestStep("在等候臺看葉手背上的習慣。", "ye_handwriting_seen", "bench"),
        QuestStep("聽完門縫裡的談話，記進筆記。", "ch3_trade_overheard", "bench")),
        visible_flags=("ch3_k_at_office_seen",)))
    q.append(Quest("ch3_home", "main", "回家收好副本，確認下一個週日", "公開月報不夠找到完整的帳。", "下一章的去向。", "ch3_shore_closed", (
        QuestStep("回當舖的廚房吃留飯。", "ch3_home_supper_done", "old_k_kitchen"),
        QuestStep("在店內接鷺的通訊，確認下一個週日。", "ch3_shore_closed", "shop_radio")),
        visible_flags=("ch3_trade_overheard",)))
    q.append(Quest("sq3_room_proposal", "side", "比較樣品房的窗", "三間都是四十八萬，差在朝向、光照時間和安靜程度。", "二十信用點。",
                   "sq3_room_proposal_done", (
                       QuestStep("量過一扇窗後，向林小姐記下房間提案。", "sq3_room_proposal_done", "lin"),),
                   visible_flags=("ch3_clearwater_tour_started",)))
    q.append(Quest("sq7_ahan_tape", "side", "第三個抽屜的錄音", "寄存櫃裡有一卷家屬尋人錄音，片頭同意公開。", "二十信用點。",
                   "sq7_ahan_recording_held", (
                       QuestStep("在寄存櫃聽片頭，登記借出。", "sq7_ahan_recording_held", "drawer"),),
                   visible_flags=("ch3_clinic_access",)))
    q.append(Quest("sq7_ye_name", "side", "看清葉寫的名字", "葉在談話前先在手背補了一行字。", "二十信用點。", "sq7_ye_name_seen", (
        QuestStep("在等候臺看清手背上那一行。", "sq7_ye_name_seen", "bench"),),
        visible_flags=("ye_handwriting_seen",)))


def build_source() -> ProductionSource:
    source = ProductionSource()
    source.speakers = dict(SPEAKERS)
    # 前章的結果只讀不重置；本章的初值只對新輪。room_choice 是可逆的提案值，unset 代表沒有提案。
    source.flag_defaults = {"room_choice": "unset", "ch3_janus_disabled": False}
    _documents_and_transactions(source)
    _morning(source)
    _freight(source)
    _mezzanine(source)
    _clinic(source)
    _gate_hall(source)
    _memory(source)
    _glass_edge(source)
    _showroom(source)
    _office(source)
    _evening(source)
    _quests(source)
    route_back_to_choices(source, DISPATCH, "ch3")
    return source
