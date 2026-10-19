"""第二章「鷺」的作者來源（ST-19）：劇本 design/13-story-v2/SCRIPT_CH02.md 的 S01～S22 落成段落、選擇、結果與任務。

台詞照劇本；劇本描述的動作（遞毛巾、偏傘、洗碗）由演出與擺設表現，不寫成台詞。
新動詞一律用既有的選擇演出：修收音機是三個接點與一次調頻、對帳是依序選欄位、客人簿是問聽記與回答；選錯有一句完整的提示，再選一次，不扣東西。
轉譯與寫檔：python3 tools/story/build_ch2_story.py
"""
from __future__ import annotations

import sys
from dataclasses import replace
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

from ch1_closure import (Option, ProductionSource, Quest, QuestStep, all_of, any_of, beats, flag, grant, item,  # noqa: E402
                         negate, receipt, say, set_flag, transaction, transfer)
from build_ch1_story import actor as stage_actor, stage as stage_scene  # noqa: E402
from chapter_compiler import route_back_to_choices  # noqa: E402

# 舞台演出：屋頂的茶沿用第一章的屋頂舞台（地面線 262、凜縮放 2.2；鷺的骨架只比凜高 3%，同舞台用同一個縮放）。
# 兩人站在茶座兩側、面向對方（0.40W 與 0.60W）；接續的段落沿用同一個舞台與站位，只用很短的淡入。
ROOF_STAGE = "ch1_rooftop"
ROOF_FLOOR = 262
ROOF_SCALE = 2.2


def _roof_cast(fade: float = 1.0) -> list[dict]:
    return [stage_scene(ROOF_STAGE, x=320, y=200, zoom=1.0, fade_in=fade),
            stage_actor("egret", "egret", 372, ROOF_FLOOR, facing=-1, scale=ROOF_SCALE, speaker="egret"),
            stage_actor("rin", "rin", 268, ROOF_FLOOR, facing=1, scale=ROOF_SCALE, speaker="rin")]


def _on_roof(lines: tuple, opening: bool = False) -> list[dict]:
    """屋頂舞台上的一段對話：開場淡入，接續的段落沿用站位、極短淡入。"""
    return _roof_cast(1.0 if opening else 0.25) + beats(*lines)

CHAPTER = {
    "id": "ch2_heron", "title": "第二章　鷺", "subtitle": "沉港市・霓虹市集",
    "end_title": "第二章　鷺　完",
    "teaser": "下一章：晴岸。明天從廣場貨梯去夾層診所，核對月報十七的原表。",
    "release_note": "進度已保存。",
}

SPEAKERS = {
    "rin": {"name": "凜", "color": "#ff3fa4", "portrait": "res://art/portraits/rin.png"},
    "old_k": {"name": "老K", "color": "#ffd23f", "portrait": "res://art/portraits/old_k.png"},
    "egret": {"name": "鷺", "color": "#b8c4d6", "portrait": "res://art/portraits/egret.png"},
    "lamp": {"name": "燈", "color": "#8fe39a", "portrait": "res://art/portraits/lamp.png"},
    "ali": {"name": "阿梨", "color": "#f2b8c6", "portrait": "res://art/portraits/ali.png"},
    "vig": {"name": "利息", "color": "#e0a050", "portrait": "res://art/portraits/vig.png"},
    "yong": {"name": "阿勇", "color": "#d46a4a", "portrait": "res://art/portraits/yong.png"},
    "xiaowei": {"name": "小薇", "color": "#f4e07a", "portrait": "res://art/portraits/xiaowei.png"},
    "banyan": {"name": "榕伯", "color": "#9fc28a", "portrait": "res://art/portraits/banyan.png"},
    "ye": {"name": "葉", "color": "#c8d8f0", "portrait": "res://art/portraits/ye.png", "formal": True},
    "patroller": {"name": "巡帳員", "color": "#c0a080", "portrait": "res://art/portraits/resident.png"},
    "window_clerk": {"name": "視窗員", "color": "#a0b0c0", "portrait": "res://art/portraits/resident.png", "formal": True},
    "hawker": {"name": "小販", "color": "#c8b090", "portrait": "res://art/portraits/resident.png"},
    "medic": {"name": "救護員", "color": "#a8d0c8", "portrait": "res://art/portraits/nurse.png"},
    "broadcast": {"name": "陌生廣播", "color": "#c8c0e8", "portrait": "res://art/portraits/system.png", "formal": True},
    "weather": {"name": "氣象臺", "color": "#9ad7ff", "portrait": "res://art/portraits/system.png", "formal": True},
    "shen": {"name": "沈望", "color": "#e8e0d0", "portrait": "res://art/portraits/system.png", "formal": True},
    "terminal": {"name": "委託終端", "color": "#9ad7ff", "portrait": "res://art/portraits/system.png", "formal": True},
    "label": {"name": "說明", "color": "#ded5b0", "portrait": "res://art/portraits/system.png", "formal": True},
    "voice": {"name": "錄音", "color": "#c8c0e8", "portrait": "res://art/portraits/system.png", "formal": True},
    "zheng": {"name": "鄭先生", "color": "#b0b8c8", "portrait": "res://art/portraits/guest_zheng.png"},
    "chen": {"name": "陳女士", "color": "#c8b8b0", "portrait": "res://art/portraits/guest_chen.png"},
    "hong": {"name": "洪先生", "color": "#b0c8b8", "portrait": "res://art/portraits/guest_hong.png"},
}

# 劇本第 5 節的金額（NE-231 可以調整資源檔的數字；這裡只引用交易）。
TRANSACTIONS = {
    "ch1.commission.settled": ("ch1_commission_settled", 720),        # 第一章的委託，次晨在本章結算
    "ch2.market_advance": ("ch2_market_advance", -40),               # S06 代墊四十
    "ch2.yong_subdued": ("ch2_yong_subdued", 120),                   # S12 制伏阿勇
    "ch2.audit_settled": ("ch2_audit_settled", 250),                 # S15 查核報酬
    "ch2.sq1_need": ("ch2_sq1_need", 20),                            # S06／S16 問出阿梨的需要
    "ch2.sq1_soup": ("ch2_sq1_soup", 40),                            # S07 洗碗試湯
    "ch2.sq1_ledger": ("ch2_sq1_ledger", 40),                        # S16 把錯帳交她決定
    "ch2.guest_zheng": ("ch2_guest_zheng", 20),
    "ch2.guest_chen": ("ch2_guest_chen", 20),
    "ch2.guest_hong": ("ch2_guest_hong", 20),
    "ch2.guest_book": ("ch2_guest_book", 40),                        # S21 收本（客人簿完成）
    "ch2.sq2_sunday": ("ch2_sq2_sunday", 20),                        # S04
    "ch2.sq4_radio": ("ch2_sq4_radio", 20),                          # S02
}

DOCUMENTS = {
    "ch2_check_card": {
        "name": "市場查核證", "icon": "doc_stub", "description": "鷺給的查核證，只放行市集的公眾攤道。",
        "body": "持證人可進入市集公眾攤道查核市場修繕代收批號M17。後方帳房與貨道不在放行範圍。本證不是付款憑證，也不能用來免付任何費用。"},
    "ch2_evidence_contract": {
        "name": "租攤合約副本", "icon": "doc_notice", "description": "租攤視窗給的合約副本：押金本金200，本期利息20。",
        "body": "市場修繕代收批號M17。攤位押金本金200信用點，本期利息20信用點。申請核准前不收續租款。蓋章：暫未核准。"},
    "ch2_evidence_receipt": {
        "name": "代收收據副本", "icon": "doc_stub", "description": "代收處印的收據副本：已付120，本期應付100。",
        "body": "市場修繕代收／批號M17／本金200／本期利息20／已付120／本期應付100。蓋章日期清楚。若當天代墊，另有一行「今日代墊40，待查核抵扣」。"},
    "ch2_evidence_collection": {
        "name": "代收簿副本", "icon": "doc_log", "description": "裝卸間代收簿的副本：同一批號還記著待收120。",
        "body": "批號M17／收款120，其中本金100、利息20／轉送北棟二樓／待收欄120。按合約與收據，正確的待收應該是100。"},
    "ch2_original_ledger": {
        "name": "公開原帳副本", "icon": "doc_log", "description": "帳櫃裡的公開原帳：待收100，代收簿多加的20沒有根據。",
        "body": "批號M17：待收100。代收簿附加20。收費基準另見夾層診所月報17。"},
    "ch2_ali_page": {
        "name": "阿梨私人帳頁副本", "icon": "doc_notice", "description": "帳櫃裡阿梨那一頁的副本。本金兩百她認，錯加的六十她不認。",
        "body": "阿梨的開攤借款本金600，已還本金400，本金剩200。本期利息60已付清。帳上又錯加一次本期利息60，錯記待付260。今日市場代墊的40另列，尚未併入私人帳。"},
    "ch2_clinic_index": {
        "name": "診所報表索引", "icon": "doc_log", "description": "港區代收批號M17對到夾層診所的月報17。這裡只有索引，沒有原表。",
        "body": "診所報表索引：港區代收批號M17→夾層診所月報17。夾層是港區與日照區之間的工作層，診所從廣場貨梯過去。原始月報只能在診所現場申請閱覽。"},
    "ch2_radio_clip": {
        "name": "陌生廣播的片段", "icon": "recording", "description": "收音機錄下的一段尋人廣播：念了三個名字，還提到一頂帽子。",
        "body": "陌生廣播：今晚先念三個還在等回覆的名字。陳海生、周美蘭、林兆安，你們的家人來過。名字念錯了請告訴我。我還留著一頂帽子，如果有人認得帽沿的補線，請到港區電臺留言。"},
}

# 任務步驟的真實格位（人物或物件站的那一格；區域 id 對應 data/levels/ch2_<區域>.tres）。
QUEST_LOCATIONS = {
    "old_k": ("pawnshop", 50, 19), "radio": ("pawnshop", 61, 19), "egret": ("rooftop", 40, 17), "patroller": ("market_gate", 18, 19),
    "vig": ("market", 30, 19), "ali_market": ("market", 25, 19), "rent_window": ("market", 53, 19), "ali_home": ("ali_home", 32, 19),
    "collection_book": ("loading", 112, 19), "reconcile": ("loading", 128, 19), "ledger_door": ("ledger_front", 46, 19),
    "cabinet": ("ledger_office", 54, 19), "egret_booth": ("market_gate", 96, 19), "terminal": ("lounge_front", 16, 19),
    "ali_lounge": ("lounge_front", 33, 19), "guest_entry": ("lounge_front", 44, 19),
}


def _documents_and_transactions(source: ProductionSource):
    source.documents = dict(DOCUMENTS)
    for canonical, (filename, _amount) in TRANSACTIONS.items():
        source.transactions[canonical] = {"resource": f"res://data/story_transactions/{filename}.tres", "caller": "chapter2"}
    source.transactions["ch2.market_advance"]["on_failure"] = {"insufficient_credits": "ch2_t_s06_short"}


def _opt(ident, text, target, explanation, **kw):
    return Option(ident, text, target, explanation, **kw)


# ---------------------------------------------------------------------------
# H1 當舖：S01 次晨結算、S02 收音機
# ---------------------------------------------------------------------------

def _morning(source: ProductionSource):
    settled = receipt("ch1.commission.settled")
    stayed = flag("knows_ali_address")
    source.add("ch2_s01_morning", "S01", (("old_k", "起來啦？頭髮先擦乾，再來櫃台把昨晚的帳對一下喔。"),), mode="bubbles")
    source.add("ch2_t_s01_settle", "S01", (
        ("old_k", "頭髮先擦乾，昨晚那個鍋我換過了喔。"),
        ("rin", "鍋不用算進我的帳，我只叫你加水。"),
        ("egret", "交接櫃驗收過了，八百信用點，沒有少。"),
        ("old_k", "照原來的一成，我收八十，你拿七百二十。")),
        when=negate(settled), options=(
            _opt("settle", "核對三欄後確認結算。", "ch2_t_s01_settled", "報酬八百、抽成八十、淨額七百二十，只結算一次。"),
            _opt("later", "等一下再對帳。", None, "先不結算，之後再找老 K。")))
    source.add("ch2_t_s01_settled", "S01", (
        ("rin", "一成照舊，這筆保費我記著。"),
        ("old_k", "你先把今天的帳算好，別連早餐也省了。"),
        ("rin", "你那本帳不能借我看？"),
        ("old_k", "每個人的東西都記在裡面，不能整本借走啦。"),
        ("egret", "資料盤有一筆市場修繕代收，找不到付款附件。委託要我們核對，不是再偷一片盤。"),
        ("rin", "我拿回執去找收據，盤已經不在我這裡。"),
        ("old_k", "上面指定查這筆，別替他們多接別人的帳。"),
        ("rin", "我核完才回來，飯留著。")),
        when=negate(settled), completion=(transaction("ch1.commission.settled"), set_flag("ch2_morning_settled")),
        next_scene="ch2_t_s01_reaction")
    # 選擇反應：依第一章宵夜的實際結果挑一版。
    source.add("ch2_t_s01_reaction", "S01", (("old_k", "昨晚吃過麵，今天也要吃喔。"), ("rin", "兩頓我分得清楚。")),
               when=all_of(stayed), mode="animated")
    source.segments["ch2_t_s01_settled"] = source.segments["ch2_t_s01_settled"]
    source.add("ch2_t_s01_reaction_left", "S01", (("old_k", "把欠條和回執分開放，別把人家的晚飯當委託。"), ("rin", "我只是不想混在一起。")),
               when=negate(stayed), mode="animated")
    source.add("ch2_t_s01_revisit", "S01", (("old_k", "錢已經對過了，茶在樓上，別讓她等喔。"),), when=settled)

    # S02 收音機：三個接點、一次調頻、聽完廣播、選擇儲存或關掉。
    repaired = flag("ch2_radio_repaired")
    source.add("ch2_t_s02_intro", "S02", (
        ("rin", "這臺還有電，喇叭為什麼沒聲音？"),
        ("old_k", "上次摔到接線鬆了，零件盒有同一款接頭。你要修就拿，別拿槍託敲喔。")),
        when=negate(repaired), next_scene="ch2_t_s02_power", mode="animated")
    wiring = (("power", "電源線", "標著電源的孔", "ch2_t_s02_antenna"), ("antenna", "天線", "標著天線的孔", "ch2_t_s02_speaker"),
              ("speaker", "喇叭線", "標著音源的孔", "ch2_t_s02_tune"))
    holes = (("power", "接到標著電源的孔。"), ("antenna", "接到標著天線的孔。"), ("speaker", "接到標著音源的孔。"))
    for wire, name, right, next_id in wiring:
        options = []
        for hole, text in holes:
            target = next_id if hole == wire else f"ch2_t_s02_{wire}_wrong"
            options.append(_opt(hole, text, target, f"把{name}{text[:-1]}。"))
        options.append(_opt("leave", "先把收音機放著。", None, "不修也能出門，之後可以再來。"))
        source.add(f"ch2_t_s02_{wire}", "S02", (("label", f"三條線都鬆了。現在要接{name}，它該接到{right}。"),),
                   when=negate(repaired), options=tuple(options))
        source.add(f"ch2_t_s02_{wire}_wrong", "S02", (("label", f"喇叭只發出一陣雜訊。{name}要接到{right}，再試一次。"),),
                   mode="animated", next_scene=f"ch2_t_s02_{wire}")
    source.add("ch2_t_s02_tune", "S02", (("lamp", "先讓指標進兩條刻線中間，再轉到聲音最清楚的地方。"),), when=negate(repaired), options=(
        _opt("middle", "把指標轉進兩條刻線中間。", "ch2_t_s02_broadcast", "停在聲音最清楚的地方。"),
        _opt("edge", "把指標轉到刻線外面。", "ch2_t_s02_tune_wrong", "刻線外只有雜訊。")))
    source.add("ch2_t_s02_tune_wrong", "S02", (("label", "刻線外只有低頻的雜訊。把指標轉回兩條刻線中間，再試一次。"),),
               mode="animated", next_scene="ch2_t_s02_tune")
    source.add("ch2_t_s02_broadcast", "S02", (
        ("weather", "港區午後降雨持續，市場低窪通道請改走上層雨棚。"),
        ("broadcast", "今晚先念三個還在等回覆的名字。陳海生、周美蘭、林兆安，你們的家人來過。"),
        ("broadcast", "如果名字念錯了，請告訴我，我會重新念。"),
        ("broadcast", "名字不該只剩一個編號。"),
        ("broadcast", "我還留著一頂帽子。如果有人認得帽沿的補線，請到港區電臺留言。"),
        ("rin", "她連帽子也放進尋人名單。"),
        ("old_k", "名字不記得，東西還在，也是個開頭啦。")),
        when=negate(repaired), options=(
            _opt("save", "儲存這段廣播。", "ch2_t_s02_saved", "收音機修好、廣播聽完，片段記進筆記。"),
            _opt("off", "先關掉收音機。", "ch2_t_s02_off", "收音機修好、廣播聽完，之後可以回來重聽。"),
            _opt("leave", "先離開工作檯。", None, "這次不算修好，之後可以再來。")))
    done = (set_flag("ch2_radio_repaired"), set_flag("sq4_broadcast_heard"), transaction("ch2.sq4_radio"))
    source.add("ch2_t_s02_saved", "S02", (("rin", "陌生廣播、帽沿補線、港區電臺，我先記下來。"),), mode="animated",
               when=negate(repaired), completion=done + (set_flag("sq4_clip_saved"), grant("ch2_radio_clip")))
    source.add("ch2_t_s02_off", "S02", (("rin", "先關掉，名字我記得了，之後再回來聽一次。"),), mode="animated",
               when=negate(repaired), completion=done)
    source.add("ch2_t_s02_relisten", "S02", (
        ("broadcast", "今晚先念三個還在等回覆的名字。陳海生、周美蘭、林兆安，你們的家人來過。"),
        ("broadcast", "我還留著一頂帽子。如果有人認得帽沿的補線，請到港區電臺留言。")),
        when=all_of(repaired, negate(flag("sq4_clip_saved"))), options=(
            _opt("save", "這次把廣播存下來。", "ch2_t_s02_save_late", "片段記進筆記，不另外給獎勵。"),
            _opt("off", "聽完就好。", None, "收音機留在工作檯，之後還能再聽。")))
    source.add("ch2_t_s02_save_late", "S02", (("rin", "陌生廣播、帽沿補線、港區電臺，這次我記下來了。"),), mode="animated",
               when=negate(flag("sq4_clip_saved")), completion=(set_flag("sq4_clip_saved"), grant("ch2_radio_clip")))
    source.add("ch2_t_s02_revisit", "S02", (("label", "收音機修好了，片段已經存在筆記裡。"),),
               when=all_of(repaired, flag("sq4_clip_saved")))


# ---------------------------------------------------------------------------
# H7 屋頂：S03 簡報、S04 週日（可選）、S22 章末
# ---------------------------------------------------------------------------

def _rooftop(source: ProductionSource):
    brief = flag("ch2_brief_done")
    source.add("ch2_t_s03_tea", "S03", steps=_on_roof((
        ("egret", "小鬼，坐到裡面來，那塊板凳今天還沒有泡水。"),
        ("rin", "你每次都說今天，這木頭已經腫了。"),
        ("rin", "傘骨斷了，你那邊在漏。"),
        ("egret", "我這件外套本來就濕，兩邊一起濕才不會歪。"),
        ("rin", "我記著這杯茶，傘不用算。"),
        ("egret", "你還要替雨開一個帳啊？先喝，茶不會等你算完。")), opening=True),
        when=negate(brief), next_scene="ch2_t_s03_brief", mode="animated")
    source.add("ch2_t_s03_brief", "S03", steps=_on_roof((
        ("egret", "市場查核證只讓你進公眾攤道，後面的帳房還是阿勇管。阿勇是這一帶收帳人的頭。"),
        ("egret", "昨晚盤裡那筆代收款有批號，收據卻不在。去代收處找當天的租攤合約和收款存根。"),
        ("rin", "我先看原本，再聽他們怎麼算。"),
        ("egret", "天穹要找誰多收了錢，我只要他們別拿攤商的錢墊掉。你看見不對的地方就寫，不用替誰挑好看的。"),
        ("rin", "查完這筆就能結案？"),
        ("egret", "附件對得上才算，光把收帳的人打趴不會長出收據。")), opening=False),
        when=negate(brief), next_scene="ch2_t_s03_rain", mode="animated")
    source.add("ch2_t_s03_rain", "S03", steps=_on_roof((
        ("egret", "你看雨別只看腳下。屋頂先響、雨棚再響，你就知道市場哪條路積水了。"),
        ("rin", "所以你喝茶也在看路。"),
        ("egret", "至少我這杯不用你付保費。")), opening=False),
        when=negate(brief), completion=(set_flag("ch2_brief_done"), grant("ch2_check_card")), mode="animated")
    # 簡報後的話題：週日（SQ2）、重擊的練法、再聽一次查帳的重點。
    sunday_asked_ch1 = flag("asked_egret_sunday")
    source.add("ch2_t_egret_hub", "S03", (("egret", "茶還熱，要問什麼就趁現在。"),),
               when=all_of(brief, negate(flag("ch2_audit_submitted"))), options=(
                   _opt("sunday", "問鷺週日的安排。", "ch2_dispatch_sunday", "可選的追問，不影響主線。", when=negate(flag("sq2_sunday_heard"))),
                   _opt("heavy", "問重擊怎麼接。", "ch2_t_s03_heavy", "鷺會說一句練法，不影響主線。"),
                   _opt("brief", "再確認一次查帳的重點。", "ch2_t_s03_brief_again", "重聽代收處要找的東西。"),
                   _opt("leave", "先這樣，我去市集。", None, "結束對話，之後可以再來。")))
    source.add("ch2_t_s03_heavy", "S03", (("egret", "把重擊接在收招後，你要的是空檔，不是揮得久。"),), mode="animated", next_scene="ch2_t_egret_hub")
    source.add("ch2_t_s03_brief_again", "S03", (
        ("egret", "代收處有收據，租攤視窗有合約，後面裝卸間有代收簿。三張對得上，才找得到原帳。"),),
        mode="animated", next_scene="ch2_t_egret_hub")
    source.add("ch2_t_s04_asked", "S04", (
        ("rin", "你昨晚說要看一個人，週日也去？"),
        ("egret", "週日不是空的，我留給別人了。"),
        ("rin", "有人找你收帳？"),
        ("egret", "有個人以前連我發脾氣都會替我端水。我去坐一下，讓她嫌我吵。"),
        ("rin", "那我不排週日，免得你又趕時間。"),
        ("egret", "這句我記下了，哪天有活別又只看價錢。"),
        ("rin", "我先把今天做完，週日你自己留著。")),
        when=sunday_asked_ch1, completion=(set_flag("sq2_sunday_heard"), transaction("ch2.sq2_sunday")), mode="animated", next_scene="ch2_t_egret_hub")
    source.add("ch2_t_s04_new", "S04", (
        ("rin", "你行事曆每個週日都是空的，你不接案？"),
        ("egret", "週日不是空的，我留給別人了。"),
        ("rin", "有人找你收帳？"),
        ("egret", "有個人以前連我發脾氣都會替我端水。我去坐一下，讓她嫌我吵。"),
        ("rin", "那我不排週日，免得你又趕時間。"),
        ("egret", "這句我記下了，哪天有活別又只看價錢。"),
        ("rin", "我先把今天做完，週日你自己留著。")),
        when=negate(sunday_asked_ch1), completion=(set_flag("sq2_sunday_heard"), transaction("ch2.sq2_sunday")), mode="animated", next_scene="ch2_t_egret_hub")

    # S22 章末：兩只茶杯、索引、週日、灰衣人、通路接上。
    ready = all_of(flag("ch2_audit_submitted"), flag("ch2_egret_returned"))
    source.add("ch2_t_s22_tea", "S22", steps=_on_roof((
        ("egret", "這杯先喝，別等我死了才幫我收。"),
        ("rin", "今天你把人家帳房撞壞了，茶錢恐怕不夠賠。"),
        ("egret", "帳對出來了，他的椅子倒下去也值。"),
        ("rin", "代收那筆對完了，可是診所月報還在上面。明天我從廣場貨梯過去，看原來的。"),
        ("egret", "去查表可以，不用每張都有簽名就信它。晴岸也在那邊，就是你那本目錄的日照區住宅。想看就看，不先替老頭子買。")), opening=True),
        when=all_of(ready, negate(flag("ch2_heron_closed"))), options=(
            _opt("go", "明天去夾層診所核對原表。", "ch2_t_s22_decided", "確認明天的去向，接著聊完今晚的茶。"),
            _opt("wait", "先把茶喝完再說。", None, "回到屋頂，之後再來確認。")))
    source.add("ch2_t_s22_decided", "S22", steps=_on_roof((
        ("rin", "我先看表，房子還差得遠。"),
        ("egret", "明天別算我，週日我不接案。")), opening=False),
        when=all_of(ready, negate(flag("ch2_heron_closed"))), mode="animated", next_scene="ch2_dispatch_s22_sunday")
    source.add("ch2_t_s22_sunday_known", "S22", steps=_on_roof((
        ("rin", "那個人還在等你嫌吵，我沒排你的活。"),
        ("egret", "妳終於沒替我把空白填滿，今天算妳贏一次。")), opening=False),
        when=flag("sq2_sunday_heard"), mode="animated", next_scene="ch2_t_s22_greycoat")
    source.add("ch2_t_s22_sunday_unknown", "S22", steps=_on_roof((
        ("rin", "你不是每次都說最後一次，怎麼還留週日？"),
        ("egret", "有個人要見，工作不能佔那天。")), opening=False),
        when=negate(flag("sq2_sunday_heard")), mode="animated", next_scene="ch2_t_s22_greycoat")
    source.add("ch2_t_s22_greycoat", "S22", steps=_on_roof((
        ("rin", "對面那個人一直看這邊，他今天是不是先我們進市場？"),
        ("egret", "看見了不代表知道，我們明天再看。"),
        ("lamp", "港區的通路都接上了，市場後門能回當舖街口。上層那條還沒通，明天得從廣場走。"),
        ("rin", "我先回去，老 K 留了飯。"),
        ("egret", "喝完再走，這次我真不追妳。")), opening=False),
        mode="animated", completion=(set_flag("ch2_heron_closed"), set_flag("harbor_walk_ready")))
    source.add("ch2_t_s22_revisit", "S22", (("egret", "明天別算我，週日我不接案。"),), when=flag("ch2_heron_closed"))


# ---------------------------------------------------------------------------
# H12a 市集入口：S05
# ---------------------------------------------------------------------------

def _gate(source: ProductionSource):
    source.add("ch2_t_s05_gate", "S05", (
        ("patroller", "查核的人走雨棚下，貨道沒有放行。"),
        ("rin", "我去代收處，你把入口留著。"),
        ("lamp", "昨天封路，今天只開了攤道。別跟著貨車鑽進柵門。")),
        when=all_of(flag("ch2_brief_done"), negate(flag("ch2_gate_checked"))), completion=(set_flag("ch2_gate_checked"),))
    source.add("ch2_t_s05_no_card", "S05", (("patroller", "沒有查核證就只能在外面等。鷺在當舖屋頂，拿了證再來。"),),
               when=negate(flag("ch2_brief_done")))
    source.add("ch2_t_s05_revisit", "S05", (("patroller", "攤道往裡走，貨道還是不放行。"),), when=flag("ch2_gate_checked"))
    source.add("ch2_b_booth_b3", "S05", (("lamp", "這座電話亭可以登記復原位置，港區交通線還沒接通。"),), mode="radio")


# ---------------------------------------------------------------------------
# H12b 代收處：S06（追帳兩路）、證據與攤道上的人
# ---------------------------------------------------------------------------

def _collection_office(source: ProductionSource):
    contact = flag("ch2_market_contact_done")
    source.add("ch2_t_s06_open", "S06", (
        ("vig", "今天四十信用點代收款，加上前帳的利息，我才能替您收租攤申請。"),
        ("ali", "申請上沒有這一項，你先把已收的兩筆列出來。"),
        ("rin", "昨晚收的那筆也算利息？"),
        ("vig", "我是阿勇的副手，大家叫我利息。帳在他那裡，我這裡只負責收。"),
        ("ali", "我來找攤位，不是來續借。你把我的申請壓著，我就得一直回來。"),
        ("ali", "你先問我，好嗎？")),
        when=negate(contact), options=(
            _opt("pay", "先付四十取得收據。", "ch2_t_s06_pay_confirm", "代墊四十信用點，只解除今天的催收，不結清阿梨的債。"),
            _opt("ask", "先問阿梨需要什麼。", "ch2_t_s06_ask", "把手從口袋拿開，先聽她說。")))
    source.add("ch2_t_s06_pay_confirm", "S06", (("label", "代墊四十信用點，只解除今天的催收；不結清阿梨的債。"),),
               when=negate(contact), options=(
                   _opt("confirm", "確認代墊四十。", "ch2_t_s06_paid", "扣四十信用點，取得蓋章收據。"),
                   _opt("back", "先不付錢，回到剛才的選擇。", "ch2_t_s06_open_again", "回到剛才的選擇，什麼都不扣。")))
    source.add("ch2_t_s06_open_again", "S06", (("ali", "你先問我，好嗎？"),), when=negate(contact), options=(
        _opt("pay", "先付四十取得收據。", "ch2_t_s06_pay_confirm", "代墊四十信用點，只解除今天的催收，不結清阿梨的債。"),
        _opt("ask", "先問阿梨需要什麼。", "ch2_t_s06_ask", "把手從口袋拿開，先聽她說。")))
    source.add("ch2_t_s06_short", "S06", (("label", "信用點不夠，先問阿梨並核對收據。"),), mode="animated", next_scene="ch2_t_s06_open_again")
    source.add("ch2_t_s06_paid", "S06", (
        ("rin", "這四十我先墊，你開收據。"),
        ("ali", "我會把這筆記給你，但攤位的事還沒解決。")),
        when=negate(contact), completion=(transaction("ch2.market_advance"), set_flag("ali_advance_40", 40),
                                         grant("ch2_evidence_receipt"), set_flag("ch2_evidence_receipt")),
        mode="animated", next_scene="ch2_t_s06_invite")
    source.add("ch2_t_s06_ask", "S06", (
        ("rin", "你現在需要什麼？"),
        ("ali", "一塊能煮麵的攤位，還有一張租攤許可。我缺的是這兩樣，不是你口袋裡的錢。"),
        ("rin", "把已付的收據給我，我先查他為什麼收兩次。"),
        ("vig", "查帳可以，今天還欠四十。"),
        ("egret", "這筆有爭議，委託查完前不能往上加。你不簽，我把拒絕查核也寫進去。"),
        ("vig", "您拿存根看，原本不能帶走。")),
        when=negate(contact), completion=(set_flag("ch2_ali_need_asked"), transaction("ch2.sq1_need"),
                                         grant("ch2_evidence_receipt"), set_flag("ch2_evidence_receipt")),
        mode="animated", next_scene="ch2_t_s06_invite")
    stayed = flag("knows_ali_address")
    source.add("ch2_t_s06_invite", "S06", (
        ("ali", "復原館夜班下班了，我在市場找位置，後樓三樓的小廚房還有湯。"),), mode="animated", next_scene="ch2_dispatch_s06_supper")
    source.add("ch2_t_s06_invite_left", "S06", (("ali", "昨晚你先走，我沒來得及給你留一碗。"),), when=negate(stayed),
               mode="animated", next_scene="ch2_t_s06_close")
    source.add("ch2_t_s06_invite_stayed", "S06", (("ali", "昨晚那碗不是租攤試吃，這次才算。"),), when=stayed,
               mode="animated", next_scene="ch2_t_s06_close")
    source.add("ch2_t_s06_close", "S06", (
        ("rin", "我先對附件，有空再去吃。"),
        ("ali", "後樓外梯能找到我，想進來就敲門，不用替我跟別人借鑰匙。")),
        mode="animated", completion=(set_flag("ch2_market_contact_done"),))
    # 回訪：付款路可以補問需要；利息只有一句。
    source.add("ch2_t_s06_ali_paid_revisit", "S06", (("ali", "你墊的四十我記著，你想先聽攤位的事嗎？"),),
               when=all_of(contact, negate(flag("ch2_ali_need_asked"))), options=(
                   _opt("ask", "先聽攤位的事。", "ch2_t_s06_ask_late", "完整問一次她需要什麼。"),
                   _opt("later", "我先把委託查完。", "ch2_t_s06_later", "她會留著申請，等你回來再談。")))
    source.add("ch2_t_s06_ask_late", "S06", (
        ("rin", "你現在需要什麼？"),
        ("ali", "一塊能煮麵的攤位，還有一張租攤許可。我缺的是這兩樣，不是你口袋裡的錢。"),
        ("rin", "我先查他為什麼收兩次，攤位的事妳自己簽。")),
        when=negate(flag("ch2_ali_need_asked")), mode="animated", completion=(set_flag("ch2_ali_need_asked"), transaction("ch2.sq1_need")))
    source.add("ch2_t_s06_later", "S06", (("ali", "我留著申請，等你回來再談。"),), mode="animated")
    source.add("ch2_t_s06_ali_revisit", "S06", (("ali", "後樓外梯能找到我，敲門就好。"),),
               when=all_of(contact, flag("ch2_ali_need_asked")))
    source.add("ch2_t_s06_vig_revisit", "S06", (("vig", "附件帶去帳房，別拿我的存根當免付證。"),), when=contact)

    # S08 三份證據與攤道上的人（任意順序；拿到即儲存）。
    source.add("ch2_t_s08_contract", "S08", (
        ("window_clerk", "攤位押金本金二百，本期利息二十。申請沒有核准前，不收續租款。"),
        ("rin", "這行要留副本，代收處給我的金額不一樣。"),
        ("window_clerk", "副本給您，章蓋的是暫未核准。")),
        when=negate(flag("ch2_evidence_contract")), completion=(grant("ch2_evidence_contract"), set_flag("ch2_evidence_contract")))
    source.add("ch2_t_s08_contract_revisit", "S08", (("window_clerk", "合約副本給過了，申請核准前我們不收續租款。"),),
               when=flag("ch2_evidence_contract"))
    source.add("ch2_t_s08_banyan", "S08", (
        ("banyan", "我賣涼茶賣到這把年紀，鷺年輕時把我攤子打翻，賠了三倍，還先付十年的茶錢。"),
        ("rin", "她現在連茶都拿來借人情。"),
        ("banyan", "她以前最難相處，現在最好說話。以前她總說下回再賠，後來不敢拖了。")),
        when=negate(flag("ch2_banyan_heard")), completion=(set_flag("ch2_banyan_heard"),))
    source.add("ch2_t_s08_banyan_revisit", "S08", (("banyan", "喝茶賒帳我也記著，別裝沒聽見。"),), when=flag("ch2_banyan_heard"))
    source.add("ch2_t_s08_screen", "S08", (
        ("shen", "我們先確認一件事：每一份申請，都代表有人還想回家。天穹會繼續讓第二次成為可能。"),
        ("label", "天穹週年演說，創辦人沈望。旁邊的氣象欄寫著：今晚降雨偏多，復原申請量預計增加。")))
    source.add("ch2_t_s08_rumor", "S08", (
        ("hawker", "人家說付帳人遲早來收，你最好別只看今天的價。"),
        ("rin", "你見過他收什麼？"),
        ("hawker", "我也是聽的，沒見過。")),
        when=negate(flag("ch2_rumor_heard")), completion=(set_flag("ch2_rumor_heard"),))
    source.add("ch2_t_s08_rumor_revisit", "S08", (("hawker", "我只是聽說的，你自己看帳比較準。"),), when=flag("ch2_rumor_heard"))
    source.add("ch2_t_s08_collection", "S08", (
        ("label", "批號M17，收款120，其中本金100、利息20，轉送北棟二樓。待收欄寫著120。"),
        ("rin", "本金已還一百，這期利息也付過了，他又塞了二十進去。")),
        when=negate(flag("ch2_evidence_collection")), completion=(grant("ch2_evidence_collection"), set_flag("ch2_evidence_collection")))
    source.add("ch2_t_s08_collection_revisit", "S08", (("label", "代收簿的副本已經在筆記裡，原本留在裝卸間。"),),
               when=flag("ch2_evidence_collection"))


# ---------------------------------------------------------------------------
# H21 阿梨的小廚房：S07
# ---------------------------------------------------------------------------

def _ali_home(source: ProductionSource):
    visited = flag("ch2_ali_home_visit")
    knows = flag("knows_ali_address")
    source.add("ch2_t_s07_door", "S07", (
        ("ali", "你找到了，門口那把補過的傘就是我的。先把鞋底的水擦一下，好嗎？"),),
        when=negate(visited), next_scene="ch2_dispatch_s07_address", mode="animated")
    source.add("ch2_t_s07_address_new", "S07", (
        ("rin", "你說後樓，我差點走進貨梯。"),
        ("ali", "我是市場後樓三樓，走外梯，敲兩下再敲一下，我就知道是你。")),
        when=negate(knows), completion=(set_flag("knows_ali_address"),), mode="animated", next_scene="ch2_t_s07_bowls")
    source.add("ch2_t_s07_address_known", "S07", (
        ("ali", "還記得兩下再一下，你沒把暗號算成一筆帳吧？"),
        ("rin", "我記在人名那頁，沒有標價。")),
        when=knows, mode="animated", next_scene="ch2_t_s07_bowls")
    source.add("ch2_t_s07_bowls", "S07", (("ali", "你想喝湯的話，先替我洗這三隻，好嗎？我剛試的都用完了。"),),
               when=negate(visited), options=(
                   _opt("wash", "洗碗試湯。", "ch2_t_s07_wash", "替她洗三隻碗，再試湯。"),
                   _opt("address", "只記地址，先走。", "ch2_t_s07_leave", "地址記下了，下次再來。")))
    source.add("ch2_t_s07_leave", "S07", (("ali", "下次再來，門口會留一盞燈。"),), mode="animated",
               completion=(set_flag("ch2_ali_home_visit"),))
    source.add("ch2_t_s07_wash", "S07", (("label", "沖過的碗要放到乾燥架上。左邊的架子是乾的。"),), options=(
        _opt("left", "放到左邊的乾燥架。", "ch2_t_s07_soup", "左邊是乾的。"),
        _opt("right", "放到右邊的架子。", "ch2_t_s07_wash_wrong", "右邊還在滴水。"),
        _opt("stop", "先不洗了，下次再來。", None, "地址記下了，試湯留到下次。")))
    source.add("ch2_t_s07_wash_wrong", "S07", (("ali", "那邊還滴水，換到左邊就好。"),), mode="animated", next_scene="ch2_t_s07_wash")
    source.add("ch2_t_s07_soup", "S07", (
        ("rin", "這鍋放的梨比昨晚多。"),
        ("ali", "我在試能煮一整晚的湯，梨嬸以前就是這樣教我的。她在梨攤邊撿到我，所以我叫阿梨。"),
        ("rin", "攤子準備叫什麼？"),
        ("ali", "名字還沒想好，我先想每天要給人吃什麼。"),
        ("rin", "我可以把攤租先付了。"),
        ("ali", "你先替我把錯的帳找出來。要不要租，我會自己簽，不用你替我答應。"),
        ("rin", "那你簽，我記要用的東西。")),
        mode="animated", completion=(set_flag("ch2_ali_home_visit"), set_flag("sq1_soup_practice_done"), transaction("ch2.sq1_soup")))
    source.add("ch2_t_s07_revisit", "S07", (("ali", "碗放左邊就好，今天我先試湯，不收新的攤租。"),), when=visited)


# ---------------------------------------------------------------------------
# H12c 雨棚背面：S09 路痕、SC1 捷徑、S10 對帳
# ---------------------------------------------------------------------------

def _loading(source: ProductionSource):
    source.add("ch2_s09_wire", "S09", (("rin", "這條電線被人剪斷了。"), ("lamp", "電已經斷了，可以從橋上過去。")), mode="bubbles")
    source.add("ch2_t_s09_guard", "S09", (
        ("rin", "守衛還有呼吸，誰先來過？"),
        ("lamp", "我只看見門沒鎖，查不到人。"),
        ("lamp", "先看門內，別替影子取名字。")),
        when=negate(flag("ch2_guard_seen")), completion=(set_flag("ch2_guard_seen"),))
    source.add("ch2_t_s09_guard_revisit", "S09", (("label", "守衛倚著牆睡著，胸口一起一伏，沒有受傷。"),), when=flag("ch2_guard_seen"))
    source.add("ch2_t_s09_lever", "S09", (("rin", "從這邊放下橋梯，回代收處就不用繞了。"),),
               when=negate(flag("ch2_sc1_open")), completion=(set_flag("ch2_sc1_open"),))
    source.add("ch2_t_s09_lever_revisit", "S09", (("label", "橋梯已經放下，通到代收處。"),), when=flag("ch2_sc1_open"))

    have_all = all_of(flag("ch2_evidence_contract"), flag("ch2_evidence_receipt"), flag("ch2_evidence_collection"))
    done = flag("ch2_market_reconciled")
    source.add("ch2_t_s10_missing_receipt", "S10", (("label", "先找代收處要已付收據，不能只用對方的帳證明對方。"),),
               when=all_of(negate(done), negate(flag("ch2_evidence_receipt"))))
    source.add("ch2_t_s10_missing_collection", "S10", (("label", "還缺代收簿，去雨棚後面的裝卸間核對待收欄。"),),
               when=all_of(negate(done), flag("ch2_evidence_receipt"), negate(flag("ch2_evidence_collection"))))
    source.add("ch2_t_s10_missing_contract", "S10", (("label", "還缺租攤合約，去租攤視窗確認這期利息。"),),
               when=all_of(negate(done), flag("ch2_evidence_receipt"), flag("ch2_evidence_collection"), negate(flag("ch2_evidence_contract"))))
    source.add("ch2_t_s10_principal", "S10", (
        ("egret", "拿本金的欄對本金，別拿還款總額整筆減掉。裡面有已付利息。"),
        ("label", "三張紙攤在桌上。先找出本金還剩多少。")),
        when=all_of(have_all, negate(done)), options=(
            _opt("principal", "選收據的本金欄：本金還剩一百。", "ch2_t_s10_interest", "收據寫本金兩百、已付的一百二裡有一百是本金。"),
            _opt("total", "把已付的一百二整筆當本金減掉。", "ch2_t_s10_principal_wrong", "已付的一百二裡還有利息。")))
    source.add("ch2_t_s10_principal_wrong", "S10", (("label", "收據的一百二包含一百本金與二十利息，請分別比較。"),),
               mode="animated", next_scene="ch2_t_s10_principal")
    source.add("ch2_t_s10_interest", "S10", (
        ("rin", "本金還剩一百，二十的利息已經付過。"),
        ("label", "再找出哪一欄把已付的利息又算了一次。")),
        options=(
            _opt("collection", "選代收簿的待收欄：一百二十。", "ch2_t_s10_batch", "合約與收據都說利息付過了。"),
            _opt("contract", "選合約的利息欄：二十。", "ch2_t_s10_interest_wrong", "合約上的二十是本期該付的利息，不是重複的那筆。")))
    source.add("ch2_t_s10_interest_wrong", "S10", (("label", "合約的二十是本期利息，收據寫著已經付過。請找把它又算一次的那一欄。"),),
               mode="animated", next_scene="ch2_t_s10_interest")
    source.add("ch2_t_s10_batch", "S10", (
        ("rin", "代收簿還寫一百二十，他把已付的二十再收一次。"),
        ("label", "最後確認這筆帳送到哪裡。")),
        options=(
            _opt("north", "選代收簿的批號：轉送北棟二樓。", "ch2_t_s10_done", "三張都有同一批號。"),
            _opt("window", "選租攤視窗的地址。", "ch2_t_s10_batch_wrong", "租攤視窗只開合約，帳不是送到那裡。")))
    source.add("ch2_t_s10_batch_wrong", "S10", (("label", "租攤視窗只開合約。代收簿的批號旁寫著帳送去的地方。"),),
               mode="animated", next_scene="ch2_t_s10_batch")
    source.add("ch2_t_s10_done", "S10", (
        ("lamp", "三張都有同一批號，北棟二樓就是送帳的地方。"),
        ("egret", "把這三張留著，我們去找原本。你只查出了這一期，別替所有欠帳的人說已經清了。"),
        ("rin", "我拿證據去，不拿你的猜測去。")),
        mode="animated", completion=(set_flag("ch2_market_reconciled"),))
    source.add("ch2_t_s10_revisit", "S10", (("label", "重複的二十已經對出來了，北棟二樓的貨門會放行。"),), when=done)


# ---------------------------------------------------------------------------
# H13 帳房：S11 登場、S12 頭目戰的選擇（由頭目戰呼叫）、S13 結果與鷺倒下
# ---------------------------------------------------------------------------

def _ledger(source: ProductionSource):
    intro = flag("ch2_yong_intro_seen")
    source.add("ch2_t_s11_diagram", "S11", (
        ("label", "安全撤銷會永久解除這段復原連結，同時斷開動力；不會傷害座位上的人。"),
        ("label", "維修暫停閂在側箱內。側箱現在被主機的帶電護板封住，手伸不進去。")))
    source.add("ch2_t_s11_intro", "S11", (
        ("yong", "你們拿幾張副本，就要我把人借出去的錢當沒借？"),
        ("rin", "我沒有刪本金，這二十已經付了。"),
        ("egret", "把原帳拿出來，先核批號。你不認那個章，也不能叫人再付一次。"),
        ("yong", "上面一天一張收費表，我只能照今天的收。你要說我錯，把今天那張也拿來。"),
        ("rin", "那就讓我們看。"),
        ("yong", "這裡沒有給你們的鑰匙，拿帳先過我。")),
        when=negate(intro), next_scene="ch2_t_s11_xiaowei", mode="animated")
    source.add("ch2_t_s11_xiaowei", "S11", (
        ("xiaowei", "爸爸，傘要放在哪裡？"),
        ("yong", "小薇，傘放在腳邊就好，不要離開椅子。"),
        ("rin", "你把你女兒帶到帳房幹什麼？"),
        ("yong", "小薇是我的錨人，連著終端我才能回來。她要我回來。"),
        ("xiaowei", "我不想爸爸再不見了。")),
        when=negate(intro), next_scene="ch2_t_s11_boxes", mode="animated")
    source.add("ch2_t_s11_boxes", "S11", (
        ("lamp", "他的裝甲和復原共用電源，主箱撤銷能一起切掉。斷電後才能卸下棍子和儲能匣。"),
        ("egret", "主機在她那層下面，別朝她那邊開槍。"),
        ("lamp", "主箱會永久解除這段連結，側箱只能暫停，但現在被護板擋住。")),
        when=negate(intro), mode="animated", completion=(set_flag("ch2_yong_intro_seen"),))
    source.add("ch2_t_s11_revisit", "S11", (("lamp", "主箱永久解除父女連結，小薇不是攻擊目標。準備好就進帳房。"),), when=intro)
    source.add("ch2_t_xiaowei_line", "S11", (("xiaowei", "爸爸說不要離開椅子，我就坐在這裡。"),))

    # S12：頭目戰在血量門檻安全暫停後播出（NE-265 呼叫），選擇只寫意圖，真正的撤銷由隔離箱的操作寫入。
    source.add("ch2_t_s12_choice", "S12", (
        ("label", "永久解除會切掉動力與讀取。阿勇將失去靠小薇復原的資格，小薇不再承擔這段連結的損耗。"),
        ("lamp", "斷電後打壞棍柄的鎖扣，再卸下儲能匣，就能制伏他。你還是要避開他的反擊。"),
        ("label", "保留資格就繼續迎戰。儲能匣仍帶電，攻擊它可能使阿勇過載死亡；復原會讓小薇失去記憶。"),
        ("label", "側箱的暫停閂現在被護板擋住，無法使用。繼續打有風險，不能保證兩人都不付出代價。")),
        when=negate(flag("ch2_yong_subdued")), options=(
            _opt("cut", "永久解除父女連結，再制伏。", None, "接著要親手操作主隔離箱。", intent=(set_flag("yong_link_choice", "cut"),)),
            _opt("keep", "保留連結資格，繼續迎戰。", None, "繼續打，風險如上。", intent=(set_flag("yong_link_choice", "keep"),)),
            _opt("back", "先返回說明。", "ch2_t_s12_choice", "再看一次四段說明。")))
    source.add("ch2_s12_bark_mark", "S12", (("lamp", "踩亮墊能清掉標記。"),), mode="radio")
    source.add("ch2_s12_bark_egret", "S12", (("egret", "他還會再補一棍。"),), mode="radio")
    source.add("ch2_t_s12_keep_revival", "S12", (
        ("xiaowei", "爸爸，你說回來就吃飯。"),
        ("yong", "我回來了，妳看著我。"),
        ("xiaowei", "這把傘是誰的？")),
        when=negate(flag("yong_revival_done")), mode="animated",
        completion=(set_flag("yong_revival_done"), set_flag("xiaowei_read_count", 1), set_flag("xiaowei_yellow_umbrella_recognized", False)))
    source.add("ch2_t_s12_keep_pause", "S12", (("lamp", "他的匣蓋閉不上，現在斷了電，可以卸下來。"),),
               when=negate(flag("yong_link_isolated")), mode="animated", completion=(set_flag("yong_link_isolated"),))
    source.add("ch2_s12_defeat_hint", "S12", (("lamp", "隔離箱能阻止小薇的讀取，亮墊能清除利息標記。看見鐵棍蓄力再閃避。"),), mode="radio")

    subdued = flag("ch2_yong_subdued")
    taken = flag("ch2_original_ledger_taken")
    source.add("ch2_t_s13_locked", "S13", (("label", "帳櫃鎖著，鑰匙掛在阿勇身上。"),), when=negate(subdued))
    source.add("ch2_t_s13_cut", "S13", (
        ("yong", "你永久拆了我和她的連結，還要我認你算的帳？"),
        ("rin", "你活著就能對，別拿她再付。"),
        ("xiaowei", "爸爸，我們回家嗎？"),
        ("yong", "傘拿著，門外等我的人會送妳。")),
        when=all_of(subdued, flag("yong_link_choice", "cut"), negate(taken)), mode="animated", next_scene="ch2_t_s13_cabinet",
        completion=(transaction("ch2.yong_subdued"),))
    source.add("ch2_t_s13_keep", "S13", (
        ("yong", "她連自己的傘都不記得，你們滿意了？"),
        ("rin", "是你把她接進來的，原帳也不能靠她付。"),
        ("medic", "連結暫停了，恢復得先讓你們知道代價，再由你們決定。今天不會再讀她。"),
        ("xiaowei", "爸爸，這把傘先讓你拿。我想自己走出去。"),
        ("yong", "好，我走在妳後面。")),
        when=all_of(subdued, negate(flag("yong_link_choice", "cut")), negate(taken)), mode="animated", next_scene="ch2_t_s13_cabinet",
        completion=(transaction("ch2.yong_subdued"),))
    source.add("ch2_t_s13_cabinet", "S13", (
        ("label", "原帳寫著：待收100；代收簿附加20；收費基準另見夾層診所月報17。"),
        ("rin", "原本寫一百，代收那二十沒有根據。"),
        ("lamp", "月報十七在夾層診所，這裡只有索引，沒有原始報表。"),
        ("yong", "上面每天改，我拿得到的也是抄本。你想問原來怎麼算，就上去問。")),
        when=all_of(subdued, negate(taken)), mode="animated",
        completion=(set_flag("ch2_original_ledger_taken"), grant("ch2_original_ledger"), grant("ch2_ali_page"), grant("ch2_clinic_index")),
        next_scene="ch2_t_s13_fall")
    source.add("ch2_t_s13_fall", "S13", (
        ("rin", "鷺姐，你先別起來，讓我看看傷在哪裡。"),
        ("egret", "這下茶又要重泡了。"),
        ("lamp", "她的復原點在市集亭子，先把門口清出來，有人來接。"),
        ("rin", "她的傘也帶上，兩根骨都斷了。")),
        when=all_of(taken, negate(flag("ch2_egret_transport_done"))), mode="animated",
        completion=(set_flag("ch2_egret_transport_done"),))
    source.add("ch2_t_s13_revisit", "S13", (("label", "帳櫃空了，原帳的副本在筆記裡。到市集電話亭等鷺。"),), when=taken)


# ---------------------------------------------------------------------------
# B3 與 H10：S14 第 214 次、S15 結案、S16 私人帳、S17～S21 客人簿
# ---------------------------------------------------------------------------

def _return_and_audit(source: ProductionSource):
    returned = flag("ch2_egret_returned")
    source.add("ch2_t_s14_return", "S14", (
        ("voice", "歡迎回來。"),
        ("lamp", "鷺姐，這次是第二百一十四次了。"),
        ("egret", "你們連我遲到幾次都不算，這個倒記得清楚。"),
        ("banyan", "喝茶賒帳我也記著，別裝沒聽見。"),
        ("rin", "兩根傘骨還沒長回來，復原只管你自己？"),
        ("egret", "傘要是也收費，我早就用手接雨了。")),
        when=negate(returned), next_scene="ch2_t_s14_quiet", mode="animated")
    source.add("ch2_t_s14_quiet", "S14", (
        ("rin", "你不會怕醒不過來？"),
        ("egret", "我先把今天過完，不然明天的茶誰喝？"),
        ("lamp", "門口清了，帳目可以上傳了。查完再回屋頂，別漏掉委託結算。")),
        when=negate(returned), mode="animated",
        completion=(set_flag("ch2_egret_returned"), set_flag("egret_restoration_count", 214)))
    source.add("ch2_t_s14_revisit", "S14", (("egret", "我人回來了，傘沒修，這次紀錄別多算。"),), when=returned)

    ready = all_of(returned, flag("ch2_original_ledger_taken"), flag("ch2_market_reconciled"))
    submitted = flag("ch2_audit_submitted")
    source.add("ch2_t_s15_not_ready", "S15", (("terminal", "上傳需要三份證據與原帳。原帳在北棟二樓的帳櫃。"),),
               when=all_of(negate(submitted), negate(flag("ch2_original_ledger_taken"))))
    source.add("ch2_t_s15_wait_egret", "S15", (("lamp", "先到市集電話亭等鷺，她醒了我們再一起上傳。"),),
               when=all_of(negate(submitted), flag("ch2_original_ledger_taken"), negate(returned)))
    source.add("ch2_t_s15_upload", "S15", (
        ("ye", "我是天穹的葉，負責這次帳務抽查。你提出的同批號副本已核對，這一期附加的二十不成立。"),
        ("rin", "另一張診所月報決定他收多少，我要看原來的。"),
        ("ye", "索引可以給你。夾層診所儲存原始月報，現場申請閱覽，這裡不能替它答。"),
        ("egret", "我們對的是市場代收，阿梨自己的舊債由她簽。這筆先結，別混成一本。"),
        ("rin", "私人那頁我留副本，不幫她銷掉。"),
        ("terminal", "市場查核報酬二百五十信用點，第一次結算。夾層是港區與日照區之間的工作層，診所從廣場貨梯過去。")),
        when=all_of(ready, negate(submitted)), mode="animated",
        completion=(set_flag("ch2_audit_submitted"), transaction("ch2.audit_settled")))
    source.add("ch2_t_s15_revisit", "S15", (("terminal", "查核已結案。索引保存在你的筆記裡。"),), when=submitted)

    delivered = flag("sq1_ledger_delivered")
    source.add("ch2_t_s16_page", "S16", (
        ("rin", "妳這一頁也把付過的利息加了一次，六十，不是市場那筆二十。"),
        ("ali", "本金兩百我認，這六十我不認。"),
        ("ali", "你沒替我刪掉，這樣我能自己去說。你想陪我申請更正，還是先把紙留給我？")),
        when=all_of(submitted, item("ch2_ali_page"), negate(delivered)), options=(
            _opt("correct", "陪她申請更正，簽名她自己寫。", "ch2_t_s16_correct", "附加的六十暫停催收，本金兩百保留。"),
            _opt("hold", "把證據交給她，何時交由她決定。", "ch2_t_s16_hold", "她先把紙留著，自己挑日子。"),
            _opt("later", "先不談這頁。", None, "紙還在你手上，之後可以再交給她。")))
    advance = flag("ali_advance_40", 40)
    source.add("ch2_t_s16_correct", "S16", (
        ("rin", "我陪妳，簽名妳自己寫。"),
        ("terminal", "附加60已暫停，待核對；本金200保留。")),
        mode="animated", next_scene="ch2_dispatch_s16_close",
        completion=(set_flag("sq1_ledger_delivered"), set_flag("ali_ledger_action", "correct"), transfer("ch2_ali_page", "ali"),
                    transaction("ch2.sq1_ledger")))
    source.add("ch2_t_s16_hold", "S16", (
        ("rin", "我把證據給妳，何時交由妳決定。"),
        ("ali", "我今天先留著，租攤那邊還等我補資料。")),
        mode="animated", next_scene="ch2_dispatch_s16_close",
        completion=(set_flag("sq1_ledger_delivered"), set_flag("ali_ledger_action", "hold"), transfer("ch2_ali_page", "ali"),
                    transaction("ch2.sq1_ledger")))
    source.add("ch2_t_s16_advance", "S16", (
        ("ali", "妳墊的四十不能拿來抵我沒同意的舊帳，我先把收據夾在旁邊。"),
        ("rin", "妳決定怎麼用，我不再替你塞進去。")),
        when=advance, mode="animated")
    source.add("ch2_t_s16_need", "S16", (("ali", "你現在想問攤位的事嗎？"),),
               when=negate(flag("ch2_ali_need_asked")), options=(
                   _opt("ask", "問攤位的事。", "ch2_t_s06_ask_late", "完整問一次她需要什麼。"),
                   _opt("no", "今天先不問。", None, "不影響主線。")))
    source.add("ch2_t_s16_revisit_correct", "S16", (("ali", "我收到暫停催收的回執，攤位許可還要我補，這不是你欠的。"),),
               when=flag("ali_ledger_action", "correct"))
    source.add("ch2_t_s16_revisit_hold", "S16", (("ali", "那頁還在我這裡，我會挑自己能去的那天。"),), when=flag("ali_ledger_action", "hold"))
    source.add("ch2_t_s16_idle", "S16", (("ali", "我在等夜班的客人，你先去忙，湯我會留。"),))


def _guest_book(source: ProductionSource):
    """S17～S21：阿梨的視角，以舞台演出播出；三位客人可以任意順序，每位各自儲存。"""
    source.add("ch2_t_s17_offer", "S17", (
        ("ali", "我有三位客人，晚一點才收店。你先回去，湯我會留。"),
        ("rin", "別替我把夜班也記成欠，我下次再來。")),
        when=all_of(flag("ch2_audit_submitted"), negate(flag("guest_book_completed"))), options=(
            _opt("watch", "看她今天的工作（進入阿梨的視角）。", "ch2_dispatch_s17_enter", "接下來是阿梨的夜班；可以隨時回到凜這邊。"),
            _opt("leave", "先回屋頂。", None, "客人簿之後還能再看。")))
    source.add("ch2_t_s17_book", "S17", (("ali", "我可以聽您說，也可以照您留下的細節陪您說話。今晚有三位預約，我一位一位來。"),),
               when=negate(flag("ch2_guest_book_entered")), mode="animated", completion=(set_flag("ch2_guest_book_entered"),),
               next_scene="ch2_t_s17_open")
    source.add("ch2_t_s17_open", "S17", (("label", "阿梨翻開客人簿，看下一位預約的客人。"),),
               when=negate(flag("guest_book_completed")), options=(
                   _opt("zheng", "第一位客人：鄭先生。", "ch2_t_s18_ticket", "他想有人問他今天吃了什麼。", when=negate(flag("guest_ticket_answered"))),
                   _opt("chen", "第二位客人：陳女士。", "ch2_t_s19_band", "她想有人坐在那張椅子上。", when=negate(flag("guest_band_answered"))),
                   _opt("hong", "第三位客人：洪先生。", "ch2_t_s20_letter", "他想先把話講完。", when=negate(flag("guest_letter_answered"))),
                   _opt("back", "先回到凜那邊。", None, "剩下的客人之後還能再陪。")))
    # S18 鄭先生
    source.add("ch2_t_s18_ticket", "S18", (("zheng", "我想有人問我今天吃了什麼，她以前會問。我女兒二十六歲那年沒有回來。"),), options=(
        _opt("ask", "問他：「您想讓我怎麼稱呼您？」", "ch2_t_s18_name", "先問稱呼。"),
        _opt("dad", "直接叫他爸爸。", "ch2_t_s18_dad", "不先問就照角色說。")))
    source.add("ch2_t_s18_dad", "S18", (("zheng", "我剛才想先叫鄭先生，我還沒準備好。"),), mode="animated", next_scene="ch2_t_s18_ticket")
    source.add("ch2_t_s18_name", "S18", (
        ("ali", "您想讓我怎麼稱呼您？"),
        ("zheng", "叫鄭先生就好，今晚不用叫爸爸，那樣我會一直等她。"),
        ("zheng", "我今天吃了魚，沒吃完。她總把魚刺挑到左邊的小盤，怕我嫌麻煩。")), options=(
            _opt("fish", "照他說的稱呼、沒吃完的魚與左邊的小盤回應他。", "ch2_t_s18_done", "用他剛說過的三件事。"),
            _opt("meat", "問鄭先生今天的肉好不好吃。", "ch2_t_s18_wrong", "和他說的不一樣。")))
    source.add("ch2_t_s18_wrong", "S18", (("zheng", "我今天吃的是魚，我可以再說一次。"),), mode="animated", next_scene="ch2_t_s18_name")
    source.add("ch2_t_s18_done", "S18", (
        ("ali", "鄭先生，您今天的魚沒有吃完，要不要把刺先放在左邊的小盤？"),
        ("zheng", "我想說沒吃完，她大概會笑我。妳不用學她笑，聽我說完就好。")),
        mode="animated", next_scene="ch2_dispatch_s17_next",
        completion=(set_flag("guest_ticket_answered"), transaction("ch2.guest_zheng")))
    # S19 陳女士
    source.add("ch2_t_s19_band", "S19", (
        ("chen", "我妻子今天在另一個港口，回不來。我想有人坐這張椅子，不用裝作她真的在這裡。"),
        ("ali", "我坐這邊，您要我先聊什麼？")), options=(
            _opt("today", "問她：「您今晚想談今天，還是只想安靜一點？」", "ch2_t_s19_quiet", "讓她決定要不要說。"),
            _opt("death", "問她怎麼死的。", "ch2_t_s19_wrong_death", "直接問復原的事。")))
    source.add("ch2_t_s19_wrong_death", "S19", (("chen", "這件事我今晚不想說，請換個話題。"),), mode="animated", next_scene="ch2_t_s19_band")
    source.add("ch2_t_s19_quiet", "S19", (
        ("chen", "別問我怎麼死的。我記得每一秒，只想吃一口熱的。"),
        ("chen", "她替我收外套時，都會把帽子翻出來，不讓水流進領子。今晚能替我翻嗎？"),
        ("ali", "您有不能吃的東西嗎？"),
        ("chen", "不要蔥，梨湯就好。")), options=(
            _opt("soup", "替她翻好雨帽，端一碗沒有蔥的梨湯。", "ch2_t_s19_done", "照她說的四件事：不問死法、熱湯、雨帽、不要蔥。"),
            _opt("scallion", "端一碗加了蔥的湯。", "ch2_t_s19_wrong_soup", "忘了她不吃蔥。")))
    source.add("ch2_t_s19_wrong_soup", "S19", (("chen", "我不能吃蔥，您能換一碗嗎？"),), mode="animated", next_scene="ch2_t_s19_quiet")
    source.add("ch2_t_s19_done", "S19", (
        ("ali", "這碗梨湯沒有蔥。您的雨帽已經翻出來，外套掛著晾就好。"),
        ("chen", "我還能聞到湯，今天先不談別的。")),
        mode="animated", next_scene="ch2_dispatch_s17_next",
        completion=(set_flag("guest_band_answered"), transaction("ch2.guest_chen")))
    # S20 洪先生
    source.add("ch2_t_s20_letter", "S20", (
        ("hong", "我以前每次都替他回話，後來他不跟我出海了。你能先當作還願意聽的人嗎？"),
        ("ali", "我可以聽，但我不能替他答應您。")), options=(
            _opt("listen", "問他：「您希望我回答，還是先讓您說完？」", "ch2_t_s20_story", "讓他先說。"),
            _opt("forgive", "說：「我替他原諒您。」", "ch2_t_s20_wrong", "替不在場的人回答。")))
    source.add("ch2_t_s20_wrong", "S20", (("ali", "我不能替他原諒您，我可以再聽您說一遍。"), ("hong", "對，他沒有說過沒關係。")),
               mode="animated", next_scene="ch2_t_s20_letter")
    source.add("ch2_t_s20_story", "S20", (
        ("hong", "先讓我說完。不要說沒關係，他沒有這麼說過。"),
        ("hong", "我那天替他簽了下一趟的名，覺得船位難得，留給他就是幫他。沒問他為什麼不想去。"),
        ("hong", "我現在想把名字圈掉，信還是得寄。")), options=(
            _opt("heard", "回答：「我聽見了，您可以把沒問過他的事寫進信裡。」", "ch2_t_s20_done", "不替朋友回答，把筆交給他。"),
            _opt("fine", "告訴他沒關係，朋友一定會懂。", "ch2_t_s20_wrong_fine", "他剛說過不要這句。")))
    source.add("ch2_t_s20_wrong_fine", "S20", (("hong", "他沒有說過沒關係，請不要替他說。"),), mode="animated", next_scene="ch2_t_s20_story")
    source.add("ch2_t_s20_done", "S20", (
        ("ali", "我聽見了，您可以把沒問過他的事寫進信裡。"),
        ("hong", "我自己寄，不能叫妳替我。"),
        ("ali", "信封給您，寄到哪裡也請您自己決定。")),
        mode="animated", next_scene="ch2_dispatch_s17_next",
        completion=(set_flag("guest_letter_answered"), transaction("ch2.guest_hong")))
    # S21 收本
    all_guests = all_of(flag("guest_ticket_answered"), flag("guest_band_answered"), flag("guest_letter_answered"))
    source.add("ch2_t_s21_close", "S21", (
        ("ali", "鄭先生不想聽爸爸，陳女士不要蔥，洪先生不想別人替他說沒關係。今天三頁都寫清楚了。"),
        ("label", "阿梨把一顆梨放進鍋裡。"),
        ("ali", "梨嬸教我，湯裡放一顆梨，煮到最後也不容易澀。她在梨攤邊把我抱回去，我能留下的做法就這幾樣。"),
        ("ali", "我沒有錨人，真倒下就沒有下一次。有人能把今天說完，我就先讓他說完。")),
        when=all_of(all_guests, negate(flag("guest_book_completed"))), mode="animated",
        completion=(set_flag("guest_book_completed"), transaction("ch2.guest_book")))
    source.add("ch2_t_s17_revisit", "S17", (("ali", "客人簿收好了，今晚的三頁都寫清楚了。"),), when=flag("guest_book_completed"))


def _guest_book_frames(source: ProductionSource):
    """BG-46：整段夜班留在客人簿房間；客人談話用有支撐的坐姿，入口及回訪仍在凜所在的館外。"""
    for ident, segment in list(source.segments.items()):
        if segment.section not in {"S17", "S18", "S19", "S20", "S21"} or ident in {"ch2_t_s17_offer", "ch2_t_s17_revisit"}:
            continue
        seated = segment.section in {"S18", "S19", "S20"}
        actor = stage_actor("ali", "ali", 232 if seated else 150, 265.5, facing=1, scale=3.9, speaker="ali",
                            pose="sit" if seated else "idle",
                            pose_reason="坐下陪成年客人談話。" if seated else None,
                            pose_support="左椅座面 x=204.25～272.25、y=209；腳底在地板 y=265.5。" if seated else None)
        if seated:
            actor["seat_sag"] = 0.50
            if segment.options:
                segment = replace(segment, options=segment.options + (_opt("back", "先回到凜那邊。", None, "剩下的客人之後還能再陪。"),))
        cast = [stage_scene("ch2_guest_book_room", x=320, y=206.3, zoom=0.84, fade_in=0.35, feet=265.5), actor]
        source.segments[ident] = replace(segment, mode="animated", steps=tuple(cast) + segment.steps)


DISPATCH = {
    "old_k": ["ch2_t_s01_settle", "ch2_t_s01_revisit"],
    "s01_reaction": ["ch2_t_s01_reaction", "ch2_t_s01_reaction_left"],
    "radio": ["ch2_t_s02_intro", "ch2_t_s02_relisten", "ch2_t_s02_revisit"],
    "egret": ["ch2_t_s03_tea", "ch2_t_s22_tea", "ch2_t_egret_hub", "ch2_t_s22_revisit"],
    "sunday": ["ch2_t_s04_asked", "ch2_t_s04_new"],
    "s22_sunday": ["ch2_t_s22_sunday_known", "ch2_t_s22_sunday_unknown"],
    "patroller": ["ch2_t_s05_no_card", "ch2_t_s05_gate", "ch2_t_s05_revisit"],
    "vig": ["ch2_t_s06_open", "ch2_t_s06_vig_revisit"],
    "ali_market": ["ch2_t_s06_open", "ch2_t_s06_ali_paid_revisit", "ch2_t_s06_ali_revisit"],
    "s06_supper": ["ch2_t_s06_invite_stayed", "ch2_t_s06_invite_left"],
    "rent_window": ["ch2_t_s08_contract", "ch2_t_s08_contract_revisit"],
    "banyan": ["ch2_t_s08_banyan", "ch2_t_s08_banyan_revisit"],
    "notice": ["ch2_t_s08_screen"],
    "hawker": ["ch2_t_s08_rumor", "ch2_t_s08_rumor_revisit"],
    "ali_home": ["ch2_t_s07_door", "ch2_t_s07_revisit"],
    "s07_address": ["ch2_t_s07_address_known", "ch2_t_s07_address_new"],
    "collection_book": ["ch2_t_s08_collection", "ch2_t_s08_collection_revisit"],
    "guard": ["ch2_t_s09_guard", "ch2_t_s09_guard_revisit"],
    "sc1": ["ch2_t_s09_lever", "ch2_t_s09_lever_revisit"],
    "reconcile": ["ch2_t_s10_missing_receipt", "ch2_t_s10_missing_collection", "ch2_t_s10_missing_contract", "ch2_t_s10_principal",
                  "ch2_t_s10_revisit"],
    "diagram": ["ch2_t_s11_diagram"],
    "ledger_door": ["ch2_t_s11_intro", "ch2_t_s11_revisit"],
    "xiaowei": ["ch2_t_xiaowei_line"],
    "cabinet": ["ch2_t_s13_locked", "ch2_t_s13_cut", "ch2_t_s13_keep", "ch2_t_s13_fall", "ch2_t_s13_revisit"],
    "egret_booth": ["ch2_t_s14_return", "ch2_t_s14_revisit"],
    "terminal": ["ch2_t_s15_not_ready", "ch2_t_s15_wait_egret", "ch2_t_s15_upload", "ch2_t_s15_revisit"],
    "ali_lounge": ["ch2_t_s16_page", "ch2_t_s16_revisit_correct", "ch2_t_s16_revisit_hold", "ch2_t_s16_idle"],
    "s16_close": ["ch2_t_s16_advance", "ch2_t_s16_need"],
    "guest_entry": ["ch2_t_s17_offer", "ch2_t_s17_revisit"],
    # 每位客人談完：三位都談完就收本（S21），否則回到客人名單。
    "s17_next": ["ch2_t_s21_close", "ch2_t_s17_open"],
    "s17_enter": ["ch2_t_s17_book", "ch2_t_s17_open"],
}


def _quests(source: ProductionSource):
    q = source.quests
    q.append(Quest("ch2_settle", "main", "核對昨晚的委託報酬", "盤已驗收，報酬尚待核對。", "淨額七百二十信用點。", "ch2_brief_done", (
        QuestStep("在櫃台和老 K 核對報酬。", "ch2_morning_settled", "old_k"),
        QuestStep("上屋頂向鷺拿查核證。", "ch2_brief_done", "egret"))))
    q.append(Quest("ch2_reconcile", "main", "查清市集重複的利息", "代收帳沒有付款附件，需要原始證據。", "找到原帳的位置。", "ch2_market_reconciled", (
        QuestStep("出示查核證，進市集的公眾攤道。", "ch2_gate_checked", "patroller"),
        QuestStep("到代收處問清楚這筆代收款。", "ch2_market_contact_done", "vig"),
        QuestStep("到租攤視窗取合約副本。", "ch2_evidence_contract", "rent_window"),
        QuestStep("到雨棚背面的裝卸間翻代收簿。", "ch2_evidence_collection", "collection_book"),
        QuestStep("在乾燥作業桌比對三張紙。", "ch2_market_reconciled", "reconcile")),
        visible_flags=("ch2_brief_done",)))
    q.append(Quest("ch2_ledger", "main", "到北棟二樓核對原帳", "收據指向阿勇管的帳房。", "制伏阿勇的報酬一百二十信用點。", "ch2_egret_returned", (
        QuestStep("進帳房，看阿勇怎麼對這筆帳。", "ch2_yong_intro_seen", "ledger_door"),
        QuestStep("制伏阿勇，打開帳櫃。", "ch2_original_ledger_taken", "cabinet"),
        QuestStep("到市集電話亭等鷺。", "ch2_egret_returned", "egret_booth")),
        visible_flags=("ch2_market_reconciled",)))
    q.append(Quest("ch2_audit", "main", "交回查帳結果", "公開原帳已證明多收，診所索引仍需另查。", "查核報酬二百五十信用點。", "ch2_heron_closed", (
        QuestStep("在復原館外的委託終端上傳證據。", "ch2_audit_submitted", "terminal"),
        QuestStep("回當舖屋頂和鷺碰面。", "ch2_heron_closed", "egret")),
        visible_flags=("ch2_egret_returned",)))
    q.append(Quest("sq1_ali_need", "side", "問出阿梨的需要", "阿梨在代收處被催帳，付錢之前可以先問她。", "二十信用點。", "ch2_ali_need_asked", (
        QuestStep("問阿梨現在需要什麼。", "ch2_ali_need_asked", "ali_market"),), visible_flags=("ch2_market_contact_done",)))
    q.append(Quest("sq1_ali_soup", "side", "到阿梨家試湯", "阿梨邀你去後樓三樓的小廚房。", "四十信用點與一碗熱湯。", "ch2_ali_home_visit", (
        QuestStep("走後樓外梯，敲阿梨的門。", "ch2_ali_home_visit", "ali_home"),), visible_flags=("ch2_market_contact_done",)))
    q.append(Quest("sq1_ali_ledger", "side", "把錯帳交她決定", "帳櫃裡有阿梨那一頁，錯加的六十要由她自己決定怎麼處理。", "四十信用點。", "sq1_ledger_delivered", (
        QuestStep("把阿梨的帳頁交給她。", "sq1_ledger_delivered", "ali_lounge"),), visible_flags=("ch2_audit_submitted",)))
    q.append(Quest("sq1_guest_book", "side", "看阿梨的客人簿", "阿梨今晚有三位客人，你可以看她怎麼工作。", "每位客人二十信用點，收本再四十。", "guest_book_completed", (
        QuestStep("在復原館外看阿梨的客人簿。", "guest_book_completed", "guest_entry"),), visible_flags=("ch2_audit_submitted",)))
    q.append(Quest("sq2_egret_sunday", "side", "問鷺週日的安排", "鷺的週日從不接案。", "二十信用點。", "sq2_sunday_heard", (
        QuestStep("在屋頂問鷺週日的安排。", "sq2_sunday_heard", "egret"),), visible_flags=("ch2_brief_done",)))
    q.append(Quest("sq4_radio", "side", "修好並聽清廣播", "工作檯上的收音機接線鬆了。", "二十信用點。", "sq4_broadcast_heard", (
        QuestStep("修好工作檯的收音機。", "sq4_broadcast_heard", "radio"),)))


def build_source() -> ProductionSource:
    source = ProductionSource()
    source.speakers = dict(SPEAKERS)
    source.flag_defaults = {"yong_link_choice": "unset", "ali_ledger_action": "unset", "ali_advance_40": 0, "xiaowei_read_count": 0,
                            "xiaowei_yellow_umbrella_recognized": True, "yong_alive": True, "egret_restoration_count": 213,
                            "yong_link_revoked": False, "yong_link_restoration_agreed": False, "ch2_yong_subdued": False}
    _documents_and_transactions(source)
    _morning(source)
    _rooftop(source)
    _gate(source)
    _collection_office(source)
    _ali_home(source)
    _loading(source)
    _ledger(source)
    _return_and_audit(source)
    _guest_book(source)
    _guest_book_frames(source)
    _quests(source)
    route_back_to_choices(source, DISPATCH, "ch2")
    return source
