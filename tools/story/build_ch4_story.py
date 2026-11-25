#!/usr/bin/env python3
"""Compile the Hollow Shell opening, including location-linked investigation steps."""
from pathlib import Path
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/level"))

from build_ch4 import CHAPTER, POINTS  # noqa: E402
from ch1_closure import Binding, Option, ProductionSource, Quest, QuestStep, all_of, flag, grant, negate, say, set_flag  # noqa: E402
from build_ch1_story import sfx, wait  # noqa: E402
from chapter_compiler import ChapterSpec, route_back_to_choices, write_chapter, write_documents  # noqa: E402

CHAPTER_INFO = {
    "id": CHAPTER,
    "title": "第四章　空殼",
    "subtitle": "夾層安養病房",
    "end_title": "第四章　空殼　完",
    "teaser": "回當舖查清倉庫原帳留下的問題。",
}
DOCUMENT = "ch4_ward_collection_slip"
WRAPPED = "ch4_documents_wrapped"
SIGNED = "ch4_visit_signed"
CONSENT = "ch4_linden_visit_confirmed"
DESK = "ch4_desk_demo_read"
VOICE = "ch4_voice_demo_read"
COLLECTED = "ch4_collection_slip_saved"
INNER = "ch4_inner_exit_open"


def _opening(source, dispatch):
    dispatch["old_k"] = ["ch4_t_wrap", "ch4_t_wrapped"]
    source.add("ch4_t_wrap", "01", (
        ("old_k", "袋口要折兩次，水才不會從縫裡跑進去喔。"),
        ("rin", "我只帶副本。原本還留在診所，他們不能說少了一頁。"),
        ("old_k", "我把袋子放門邊。回來記得把濕的東西掛起來。"),
    ), when=negate(flag(WRAPPED)), completion=(set_flag(WRAPPED),))
    source.add("ch4_t_wrapped", "01", (
        ("old_k", "回執包好了，出門沿病房的牌子走。"),
    ), when=flag(WRAPPED), mode="animated")

    dispatch["egret"] = ["ch4_t_ward_intro", "ch4_t_reception_return"]
    dispatch["ward_history"] = ["ch4_t_traded_before", "ch4_t_sunday_before", "ch4_t_reception_sign"]
    dispatch["ward_sunday"] = ["ch4_t_sunday_before", "ch4_t_reception_sign"]
    source.add("ch4_t_ward_intro", "02", (
        ("egret", "裡面是安養病房，住著需要長期照顧的人。棠住在這裡，她是我的伴侶。"),
        ("rin", "回執只寫批次。我給櫃檯看這張，妳的訪客簿不用翻給我。"),
        ("egret", "等她問妳是誰，再照妳自己的名字答就好。"),
    ), when=negate(flag(SIGNED)), mode="animated", next_scene="ch4_dispatch_ward_history")
    source.add("ch4_t_traded_before", "02", (
        ("egret", "上週妳提到的備份，我在這裡沒問人。病房的帳和訪客資料分開放。"),
    ), when=flag("ch3_told_egret_trade"), mode="animated", next_scene="ch4_dispatch_ward_sunday")
    source.add("ch4_t_sunday_before", "02", (
        ("egret", "我在屋頂說過週日要留給一個人，那個人就是她。"),
    ), when=flag("sq2_sunday_heard"), mode="animated", next_scene="ch4_t_reception_sign")
    source.add("ch4_t_reception_sign", "02", (
        ("egret", "今天的訪客簿放在櫃檯，簽了就能進去。"),
    ), options=(
        Option("sign", "簽訪客簿，準備進病房。", "ch4_t_signed", "簽好後開啟病房內門。"),
        Option("leave", "我想先在外面等一下。", None, "之後可以再來簽名。"),
    ), cancel_choice_on_back=True)
    source.add("ch4_t_signed", "02", (
        ("rin", "我把回執放在櫃檯，簿子也簽好了。"),
    ), when=negate(flag(SIGNED)), mode="animated", completion=(set_flag(SIGNED),))
    source.add("ch4_t_reception_return", "02", (
        ("egret", "妳可以直接走訪客入口，棠坐在雨窗旁邊。"),
    ), when=flag(SIGNED), mode="animated")


def _ward(source, dispatch):
    dispatch["linden"] = ["ch4_t_linden_meet", "ch4_t_linden_revisit"]
    source.add("ch4_t_linden_meet", "03", (
        ("linden", "妳要放東西嗎？先放這張桌子，我右手拿得比較穩。"),
        ("rin", "我是凜。我在查轉介的事，想借妳床頭櫃裡那張公用的取件聯。"),
        ("linden", "它收在下層。護士把開法放在走廊和窗邊，妳可以去看。"),
    ), when=negate(flag(CONSENT)), completion=(set_flag(CONSENT),))
    source.add("ch4_t_linden_revisit", "03", (
        ("linden", "公用的紙放在下層，上層放的是我自己的東西。"),
    ), when=flag(CONSENT), mode="animated")
    source.add("ch4_t_visit_first", "03", (
        ("rin", "先去雨窗旁問棠，確認她願意借出取件聯。"),
    ), when=negate(flag(CONSENT)), mode="animated")

    taps = (sfx("step_wood", -15), wait(0.18), sfx("step_wood", -15), wait(0.18), sfx("step_wood", -15))
    for binding, section, result, instruction, audio in (
        ("desk_demo", "04", DESK, "先敲靠床的桌緣三下，再等提示燈亮。", taps),
        ("voice_demo", "05", VOICE, "等桌緣燈亮，再對著收音鍵哼一小段。", (sfx("beep", -19),)),
    ):
        scene = f"ch4_t_{binding}"
        replay = f"{scene}_replay"
        steps = (*audio, say("ward_demo", instruction))
        dispatch[binding] = ["ch4_t_visit_first", replay, scene]
        source.add(replay, section, steps=steps, when=flag(result), mode="animated")
        source.add(scene, section, steps=steps, when=all_of(flag(CONSENT), negate(flag(result))),
                   mode="animated", completion=(set_flag(result),), cancel_on_skip=True)

    dispatch["cabinet"] = ["ch4_t_visit_first", "ch4_t_read_slip_again", "ch4_t_missing_desk", "ch4_t_missing_voice", "ch4_t_open_cabinet"]
    source.add("ch4_t_missing_desk", "06", (
        ("rin", "先去走廊的顯示屏看桌緣示範。"),
    ), when=negate(flag(DESK)), mode="animated")
    source.add("ch4_t_missing_voice", "06", (
        ("rin", "窗邊上層還有一段收音示範，我先去看。"),
    ), when=negate(flag(VOICE)), mode="animated")
    available = all_of(flag(CONSENT), flag(DESK), flag(VOICE), negate(flag(COLLECTED)))
    source.add("ch4_t_open_cabinet", "06", (
        ("rin", "櫃子等兩個訊號，我先照示範做一次。"),
    ), when=available, options=(
        Option("sequence", "先敲三下，燈亮後再按收音鍵。", "ch4_t_take_slip", "依桌緣與收音示範的順序。"),
        Option("voice_first", "先按收音鍵，再敲桌緣。", "ch4_t_wrong_order", "讓收音鍵先接收訊號。"),
        Option("single_tap", "敲一下，再按收音鍵。", "ch4_t_wrong_order", "只送出一次敲擊訊號。"),
        Option("leave", "先把櫃門留著。", None, "兩段示範都能重看。"),
    ), cancel_choice_on_back=True)
    source.add("ch4_t_wrong_order", "06", (
        ("rin", "提示燈熄了。櫃子會等我重新輸入。"),
    ), mode="animated", next_scene="ch4_t_open_cabinet")
    source.add("ch4_t_take_slip", "06", (
        ("rin", "我先敲桌緣三下，等燈亮再按收音鍵。"),
        ("linden", "就是這樣開的。妳可以把下層那張拿走。"),
        ("rin", "取件聯寫的是舊廠代收，沒有病人的名字。"),
    ), when=available, mode="animated", completion=(grant(DOCUMENT), set_flag(COLLECTED)))
    source.add("ch4_t_read_slip_again", "06", (
        ("rin", "公用的取件聯已收進筆記。上層的東西留給棠。"),
    ), when=flag(COLLECTED), mode="animated")

    dispatch["staff_switch"] = ["ch4_t_open_staff", "ch4_t_staff_open"]
    source.add("ch4_t_open_staff", "06", (
        ("label", "內廊門已解鎖，訪客可以從這條路回外櫃檯。"),
    ), when=negate(flag(INNER)), mode="animated", completion=(set_flag(INNER),))
    source.add("ch4_t_staff_open", "06", (
        ("label", "內廊門已經打開，可以從外櫃檯走回來。"),
    ), when=flag(INNER), mode="animated")


def build_spec():
    source = ProductionSource(flag_defaults={})
    source.speakers = {
        "linden": {"name": "棠", "name_ja": "棠", "name_en": "Linden",
                   "color": "#c0d3c8", "portrait": "res://art/portraits/linden.png"},
        "ward_demo": {"name": "護理示範", "name_ja": "看護手順", "name_en": "Ward demonstration",
                      "color": "#c3d7e5", "portrait": "res://art/portraits/system.png"},
    }
    source.documents[DOCUMENT] = {
        "name": "病房公用取件聯", "icon": "doc_stub",
        "description": "月報十七批次的物件由舊廠代收，單據沒有病人個資。",
        "body": "月報十七批次的轉介物件由舊廠代收。接收人核對取件聯與外門當班紀錄後放行。聯上只記批次與去向。",
    }
    dispatch = {}
    _opening(source, dispatch)
    _ward(source, dispatch)
    route_back_to_choices(source, dispatch, "ch4")
    source.bindings.update({
        binding: Binding("npc" if binding in ("old_k", "egret") else "object", CHAPTER,
                         f"res://data/npcs/ch4_{binding}.tres")
        for binding in POINTS
    })
    source.quests.append(Quest(
        "ch4_ward_visit", "main", "帶回執去安養病房探訪棠",
        "鷺在夾層病房外等凜，兩人約好先核對回執。",
        "訪客可以進入安養病房。", CONSENT,
        (QuestStep("請老 K 把回執裝進防水袋。", WRAPPED, "old_k"),
         QuestStep("去外櫃檯找鷺簽訪客簿。", SIGNED, "egret"),
         QuestStep("到雨窗旁問棠能不能借取件聯。", CONSENT, "linden")),
    ))
    source.quests.append(Quest(
        "ch4_ward_investigation", "main", "解開床頭櫃並取得公用取件聯",
        "棠同意借出公用聯，護士留下了兩段開櫃示範。",
        "取件聯會指向月報十七批次的轉介去向。", COLLECTED,
        (QuestStep("看走廊的桌緣示範。", DESK, "desk_demo"),
         QuestStep("到窗邊上層看收音示範。", VOICE, "voice_demo"),
         QuestStep("回床頭櫃輸入兩個訊號。", COLLECTED, "cabinet")),
        visible_flags=(CONSENT,), completion_requires_steps=True,
    ))
    return ChapterSpec(CHAPTER_INFO, source, "ch4", dispatch, POINTS)


def main():
    spec = build_spec()
    write_documents(spec.source, CHAPTER, ROOT / "data/story_items", 400)
    missing = write_chapter(spec, ROOT / f"data/story/{CHAPTER}.json")
    return int(bool(missing))


if __name__ == "__main__":
    raise SystemExit(main())
