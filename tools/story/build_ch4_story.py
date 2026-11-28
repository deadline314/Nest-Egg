#!/usr/bin/env python3
"""Compile the Hollow Shell opening, including location-linked investigation steps."""
from pathlib import Path
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/level"))

from build_ch4 import CHAPTER, POINTS  # noqa: E402
import ch4_roof_story  # noqa: E402
from ch4_office_evidence import add_office_evidence  # noqa: E402
from ch4_pawnshop_return import add_pawnshop_return  # noqa: E402
from ch4_factory_recording import add_factory_recording  # noqa: E402
from ch1_closure import Binding, Option, ProductionSource, Quest, QuestStep, all_of, flag, grant, negate, say, set_flag  # noqa: E402
from build_ch1_story import sfx, wait  # noqa: E402
from ch4_ward_letter import WARD_SCARF, add_ward_letter  # noqa: E402
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
TIP = "ch4_shift_tip_known"
MATCHED = "ch4_factory_batch_matched"
RAIL = "ch4_loader_rail_released"
FLOOR = "ch4_fixed_ground_marked"
SWEEP = "ch4_demo_cover_cleared"
BRIEFED = "ch4_cleaning_briefing_read"
WORK_CROSSED = "ch4_factory_work_crossed"
ATROPOS_MID = "ch4_atropos_midpoint_ready"
ATROPOS_RETREAT = "ch4_atropos_retreat_ready"
EGRET_GONE = "ch4_egret_departed"
TERMINAL_DENIED = "ch4_terminal_revival_denied"
OFFICE = "ch4_office_access"
SHORTCUT = "ch4_safety_shortcut_open"


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


def _living(source, dispatch):
    """ST-63：當舖、病房外櫃檯與復原館之間可以看、可以讀、可以不理的東西。不寫旗標、不給物品。"""
    dispatch["counter_note"] = ["ch4_t_counter_note"]
    source.add("ch4_t_counter_note", "01", (
        ("label", "櫃台上壓著一張便條，是老 K 的字：「今天下雨，帶傘了嗎？」"),
        ("label", "同一張紙的下面，又寫了一次同樣的話，字比較歪。"),
    ), mode="animated")
    dispatch["shift_nurse"] = ["ch4_t_nurse_first", "ch4_t_nurse_signed"]
    source.add("ch4_t_nurse_first", "02", (
        ("shift_nurse", "上週日貨梯泡水，我差點趕不上交班；今天總算準時。"),
        ("shift_nurse", "病房裡床頭燈是暖色的那幾床，才可以探訪。"),
        ("rin", "床上的人不想見人呢？"),
        ("shift_nurse", "那就在門邊等，床上的人會讓你知道能不能靠近。"),
    ), when=negate(flag(SIGNED)), mode="animated")
    source.add("ch4_t_nurse_signed", "02", (
        ("shift_nurse", "簿子簽好就進去吧。床上的人沒回答，就再等一下。"),
    ), when=flag(SIGNED), mode="animated")
    # 接線廊限時挑戰完成時燈的一句（ST-64）。
    source.add("ch4_c_timed_done", "08", (("lamp", "比清掃線快了幾秒。下次別再拿自己去賭時間。"),), mode="radio")
    dispatch["lost_box"] = ["ch4_t_lost_box"]
    source.add("ch4_t_lost_box", "07", (
        ("label", "失物招領箱裡有一隻左手手套、一副耳機，還有一張寫著「明天見」的電影票根。"),
        ("label", "箱子側面貼著一行字：復原完的人常常忘了自己帶了什麼來，請慢慢找。"),
    ), mode="animated")


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
    ), when=flag(COLLECTED), options=(
        Option("ask_letter", "問棠能不能讀上層的信。", "ch4_t_ask_linden_letter", "先徵得棠同意。", when=flag(CONSENT)),
        Option("leave", "先把床頭櫃合上。", None, "回病房時可以再看。"),
    ), cancel_choice_on_back=True)

    dispatch["staff_switch"] = ["ch4_t_open_staff", "ch4_t_staff_open"]
    source.add("ch4_t_open_staff", "06", (
        ("label", "內廊門已解鎖，訪客可以從這條路回外櫃檯。"),
    ), when=negate(flag(INNER)), mode="animated", completion=(set_flag(INNER),))
    source.add("ch4_t_staff_open", "06", (
        ("label", "內廊門已經打開，可以從外櫃檯走回來。"),
    ), when=flag(INNER), mode="animated")


def _factory_approach(source, dispatch):
    dispatch["ali"] = ["ch4_t_tip_known", "ch4_t_shift_tip"]
    source.add("ch4_t_shift_tip", "07", (
        ("ali", "天穹換班才清點轉介箱。剛才有人說，停擺的掛鐘旁那扇側門還能進。"),
        ("rin", "這張取件聯少了接收人，怎麼知道是哪一箱？"),
        ("ali", "班表還在牆上。妳拿批次核對，先找給病房的那格。"),
    ), when=all_of(flag(COLLECTED), negate(flag(TIP))), completion=(set_flag(TIP),))
    source.add("ch4_t_tip_known", "07", (
        ("ali", "找到停擺的掛鐘，貨門的班表就在旁邊。"),
    ), when=flag(TIP), mode="animated")

    dispatch["shift_board"] = ["ch4_t_manifest_revisit", "ch4_t_match_manifest"]
    ready = all_of(flag(TIP), flag(COLLECTED), negate(flag(MATCHED)))
    source.add("ch4_t_match_manifest", "07", (
        ("rin", "同一個時段有兩批箱子。我先核對哪一格是病房的。"),
    ), when=ready, options=(
        Option("nineteen", "對倉儲例行送件的十九批。", "ch4_t_wrong_manifest", "班表列為一般倉儲。"),
        Option("seventeen", "對月報十七的轉介批次。", "ch4_t_manifest_matched", "取件聯寫的是這批。"),
        Option("leave", "先收起手上的紙。", None, "可以稍後重來核對。"),
    ), reference_items=(DOCUMENT,), cancel_choice_on_back=True)
    source.add("ch4_t_wrong_manifest", "07", (
        ("rin", "那格是一般倉儲。我需要找病房的轉介箱。"),
    ), mode="animated", next_scene="ch4_t_match_manifest")
    source.add("ch4_t_manifest_matched", "07", (
        ("rin", "同一批次也寫在班表上。這才是接病房貨的門。"),
    ), when=ready, mode="animated", completion=(set_flag(MATCHED),))
    source.add("ch4_t_manifest_revisit", "07", (
        ("rin", "轉介批次已核對。貨門可以通行。"),
    ), when=flag(MATCHED), mode="animated")

    dispatch["rail_release"] = ["ch4_t_release_rail", "ch4_t_rail_open"]
    source.add("ch4_t_release_rail", "08", (
        ("label", "維修棘輪已鬆開，這條高架可回外廊。"),
    ), when=negate(flag(RAIL)), mode="animated", completion=(set_flag(RAIL),))
    source.add("ch4_t_rail_open", "08", (
        ("label", "棘輪保持鬆開，外廊也可以走這條路。"),
    ), when=flag(RAIL), mode="animated")


    dispatch["workbench"] = ["ch4_t_workbench_return", "ch4_t_survey_floor"]
    source.add("ch4_t_survey_floor", "08", (
        ("rin", "警示牌外是固定地面，這裡有一張可以停靠的工作臺。"),
        ("lamp", "先辨認清掃線，下一段才會進機具工作的範圍。"),
        ("rin", "我已標出固定地面，走維修道也能回到外廊。"),
    ), when=negate(flag(FLOOR)), completion=(set_flag(FLOOR),))
    source.add("ch4_t_workbench_return", "08", (
        ("rin", "我已標出固定地面，走維修道也能回到外廊。"),
    ), when=flag(FLOOR), mode="animated")


def _sweep_demo(source, dispatch):
    dispatch["sweep_console"] = ["ch4_t_sweep_return", "ch4_t_demo_sweep", "ch4_t_sweep_unready"]
    source.add("ch4_t_sweep_unready", "08", (
        ("rin", "先在工作臺確認腳下的地板，再開清掃裝置。"),
    ), when=negate(flag(FLOOR)), mode="animated")
    source.add("ch4_t_demo_sweep", "08", steps=(
        sfx("telegraph", -12),
        wait(1.2),
        say("lamp", "只清掉框內的測試箱。沿警示牌外的固定地板走。"),
    ), when=all_of(flag(FLOOR), negate(flag(SWEEP))), mode="animated", completion=(set_flag(SWEEP),))
    source.add("ch4_t_sweep_return", "08", (
        ("rin", "原位只剩標記，腳下的固定地板還在。"),
    ), when=flag(SWEEP), mode="animated")


def _factory_safety(source, dispatch):
    dispatch["safety_instruction"] = ["ch4_t_safety_instruction", "ch4_t_safety_replay"]
    source.add("ch4_t_safety_instruction", "09", (
        ("factory_pa", "這一班的原帳要留在辦公室。所有人退到黃線外，清理程序已經開始。"),
        ("egret", "我從高處替妳看清掃線。"),
        ("rin", "先等她離開黃線，我再過去。"),
    ), when=negate(flag(BRIEFED)), mode="animated", completion=(set_flag(BRIEFED),))
    source.add("ch4_t_safety_replay", "09", (
        ("lamp", "黃線內是工作帶。這裡有檢查點，員工門可以返回裝卸帶。"),
    ), when=flag(BRIEFED), mode="animated")
    dispatch["safety_catch"] = ["ch4_t_safety_catch", "ch4_t_safety_open"]
    source.add("ch4_t_safety_catch", "09", (
        ("rin", "門栓放了。回裝卸帶可以直接走這條高架。"),
    ), when=negate(flag(SHORTCUT)), mode="animated", completion=(set_flag(SHORTCUT),))
    source.add("ch4_t_safety_open", "09", (
        ("rin", "員工門通往裝卸帶的上層。"),
    ), when=flag(SHORTCUT), mode="animated")


def _work_lane(source, dispatch):
    dispatch["work_observation"] = ["ch4_t_work_observation", "ch4_t_work_crossed"]
    source.add("ch4_t_work_observation", "09", (
        ("lamp", "白線會先掃底層，再掃另一端的高架。看到白框，先走另一層。"),
        ("rin", "這裡讀得到原帳的路徑。工作廊在前面。"),
    ), when=negate(flag(WORK_CROSSED)), mode="animated", completion=(set_flag(WORK_CROSSED),))
    source.add("ch4_t_work_crossed", "09", (
        ("rin", "離開白框的範圍，固定路面還能通行。"),
    ), when=flag(WORK_CROSSED), mode="animated")


def _cleanup_battle(source, dispatch):
    dispatch["egret_at_rail"] = ["ch4_t_egret_handoff"]
    source.add("ch4_t_egret_handoff", "10", (
        ("rin", "妳把手給我。我先拿終端接上。"),
        ("factory_terminal", "無法執行復原。"),
        ("egret", "原帳在樓上。妳自己看。"),
    ), when=all_of(flag(ATROPOS_MID), negate(flag(EGRET_GONE))), mode="animated",
        completion=(set_flag(TERMINAL_DENIED), set_flag(EGRET_GONE)), silence_music=True)
    dispatch["office_release"] = ["ch4_t_work_retreat"]
    source.add("ch4_t_work_retreat", "11", (
        ("lamp", "她退到工作廊裡了。辦公室的門現在解鎖。"),
        ("rin", "我先帶原帳出去。"),
    ), when=all_of(flag(ATROPOS_RETREAT), flag(EGRET_GONE), negate(flag(OFFICE))), mode="animated",
        completion=(set_flag(OFFICE),))


def build_spec():
    source = ProductionSource(flag_defaults={})
    source.speakers = {
        "factory_terminal": {"name": "復原終端", "name_ja": "復元端末", "name_en": "Restoration terminal",
                             "color": "#cad8dd", "portrait": "res://art/portraits/system.png"},
        "factory_pa": {"name": "廠內廣播", "name_ja": "工場内放送", "name_en": "Factory PA",
                       "color": "#e4bd91", "portrait": "res://art/portraits/atropos.png"},
        "linden": {"name": "棠", "name_ja": "棠", "name_en": "Linden",
                   "color": "#c0d3c8", "portrait": "res://art/portraits/linden.png"},
        "ward_demo": {"name": "護理示範", "name_ja": "看護手順", "name_en": "Ward demonstration",
                      "color": "#c3d7e5", "portrait": "res://art/portraits/system.png"},
        "shift_nurse": {"name": "早班護理員", "name_ja": "早番の看護師", "name_en": "Morning-Shift Nurse",
                        "color": "#a8d0c8", "portrait": "res://art/portraits/nurse.png"},
    }
    source.documents[DOCUMENT] = {
        "name": "病房公用取件聯", "icon": "doc_stub",
        "description": "月報十七批次的物件由舊廠代收，單據沒有病人個資。",
        "body": "月報十七批次的轉介物件由舊廠代收。接收人核對取件聯與外門當班紀錄後放行。聯上只記批次與去向。",
    }
    dispatch = {}
    _opening(source, dispatch)
    _living(source, dispatch)
    _ward(source, dispatch)
    _factory_approach(source, dispatch)
    _sweep_demo(source, dispatch)
    _factory_safety(source, dispatch)
    _work_lane(source, dispatch)
    _cleanup_battle(source, dispatch)
    add_office_evidence(source, dispatch)
    add_factory_recording(source, dispatch)
    add_ward_letter(source, dispatch, CONSENT, COLLECTED)
    ch4_roof_story.install(source, dispatch)
    add_pawnshop_return(source, dispatch)
    route_back_to_choices(source, dispatch, "ch4")
    source.bindings.update({
        binding: Binding("npc" if binding in ("old_k", "egret", "ali", "egret_at_rail", "shift_nurse") else "object", CHAPTER,
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
    source.quests.append(Quest(
        "ch4_factory_entry", "main", "帶取件聯找舊廠的貨門",
        "取件聯寫著舊廠代收，阿梨知道換班時用哪個入口。",
        "找到廠房內可以安全停留的工作臺。", FLOOR,
        (QuestStep("到復原館找阿梨問換班紀錄。", TIP, "ali"),
         QuestStep("在舊廠外門核對公用取件聯。", MATCHED, "shift_board"),
         QuestStep("到裝卸帶確認工作邊界。", FLOOR, "workbench")),
        visible_flags=(COLLECTED,), completion_requires_steps=True,
    ))
    source.quests.append(Quest(
        "ch4_sweep_demonstration", "main", "在固定地面試一次清掃線",
        "舊廠的清掃裝置會讓標記的掩體消失。",
        "知道警示框和固定地面的位置。", SWEEP,
        (QuestStep("在裝卸帶試一次清掃線。", SWEEP, "sweep_console"),),
        visible_flags=(FLOOR,),
    ))

    source.quests.append(Quest(
        "ch4_safety_approach", "main", "穿過接線廊抵達安全臺",
        "工作帶前有一道黃線，可以在外側停下做準備。",
        "確認黃色邊界，聽清楚隊長的廣播。", BRIEFED,
        (QuestStep("穿過接線廊，在安全臺聽廣播。", BRIEFED, "safety_instruction"),),
        visible_flags=(SWEEP,),
    ))

    source.quests.append(Quest(
        "ch4_factory_work", "main", "通過清理工作帶",
        "白線會掃過測試箱和高架。可沿固定工作臺等待，也可以換層。",
        "在工作帶另一端查到通往原帳的路徑。", WORK_CROSSED,
        (QuestStep("避開白框，去工作帶另一端核對讀數。", WORK_CROSSED, "work_observation"),),
        visible_flags=(BRIEFED,),
    ))

    source.quests.append(Quest(
        "ch4_cleanup_battle", "main", "打開原帳辦公室",
        "清理隊長守在前方工作廊。鷺看著固定欄杆和清掃線。",
        "清理隊長撤離，辦公室開門。", OFFICE,
        (QuestStep("通過清掃工作廊，打開辦公室。", OFFICE, "office_release"),),
        visible_flags=(WORK_CROSSED,),
    ))
    return ChapterSpec(CHAPTER_INFO, source, "ch4", dispatch, POINTS,
        dismissible_radio={WARD_SCARF},
        flag_defaults={"ch4_work_cover_erased": False, "ch4_arena_cover_erased": False, ATROPOS_MID: False, ATROPOS_RETREAT: False})


def main():
    spec = build_spec()
    write_documents(spec.source, CHAPTER, ROOT / "data/story_items", 400)
    missing = write_chapter(spec, ROOT / f"data/story/{CHAPTER}.json")
    return int(bool(missing))


if __name__ == "__main__":
    raise SystemExit(main())
