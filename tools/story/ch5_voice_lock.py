"""The back-alley voice lock and its in-world replayable clue."""

from build_ch1_story import sfx, wait
from ch1_closure import Binding, Option, Quest, QuestStep, all_of, flag, negate, say, set_flag
from ch5_fee_story import COMPARED as FEE_COMPARED
from ch5_pear_testimony import DATES as DATES_CONFIRMED

OPEN = "ch5_basement_voice_unlocked"
SOURCE = "voice_lock"
REPLY = "下面本來就是水。"


def install(source, dispatch, chapter):
    source.bindings[SOURCE] = Binding("object", chapter, "res://data/npcs/ch5_voice_lock.tres")
    powered = all_of(flag(FEE_COMPARED), flag(DATES_CONFIRMED))
    ready = all_of(flag(FEE_COMPARED), flag(DATES_CONFIRMED), negate(flag(OPEN)))
    menu = "ch5_t_voice_lock_menu"

    dispatch[SOURCE] = [
        "ch5_t_voice_lock_open", "ch5_t_voice_lock_no_dates", menu,
    ]
    source.add(
        "ch5_t_voice_lock_open", "5.04",
        (("rin", "門還開著，樓梯就在裡面。"),), when=flag(OPEN),
        options=(
            Option("contact", "重聽燈的通訊。", "ch5_t_voice_lock_contact", "聽燈轉述誰也在找帳本。"),
            Option("leave", "先離開。", None, "門鎖留在原位。"),
        ), cancel_choice_on_back=True,
    )
    source.add(
        "ch5_t_voice_lock_no_dates", "5.04",
        (("rin", "先核對阿梨手上的交班日期。"),), when=negate(powered),
    )
    source.add(
        menu, "5.04",
        (("rin", "這扇門留著一段門廊錄音。"),), when=ready,
        options=(
            Option("answer", "回答門鎖。", "ch5_t_voice_lock_reply", "選一句話對話筒說。"),
            Option("replay", "重聽門廊錄音。", "ch5_t_voice_lock_recording", "重播老 K 的提問與凜的回答。"),
            Option("hint", "請燈給提示。", "ch5_t_voice_lock_hint_first", "從第一個提示開始。"),
            Option("leave", "先離開。", None, "門鎖留在原位。"),
        ),
        cancel_choice_on_back=True,
    )
    source.add(
        "ch5_t_voice_lock_reply", "5.04",
        (("old_k", "帶傘了嗎？"),),
        when=ready,
        options=(
            Option("water", REPLY, "ch5_t_voice_lock_release", "對話筒回答。"),
            Option("umbrella", "我會帶把傘出門。", "ch5_t_voice_lock_try_again", "對話筒回答。"),
            Option("wait", "我等外面的雨停了再走。", "ch5_t_voice_lock_try_again", "對話筒回答。"),
            Option("leave", "先放下話筒。", None, "想好後可再回答。"),
        ),
        cancel_choice_on_back=True,
    )
    source.add(
        "ch5_t_voice_lock_recording", "5.04",
        steps=(sfx("beep", -23), say("old_k", "帶傘了嗎？"), wait(0.25), say("rin", REPLY)),
        when=ready, mode="animated",
    )
    source.add(
        "ch5_t_voice_lock_hint_first", "5.04",
        (("lamp", "燈下黑，最近的反而看不見。妳往常出門是怎麼回他的？"),),
        when=ready, options=(
            Option("more", "再給我一個提示。", "ch5_t_voice_lock_hint_second", "聽一個更直接的提示。"),
            Option("leave", "我先想一下。", None, "可以回門鎖重聽。"),
        ), cancel_choice_on_back=True,
    )
    source.add(
        "ch5_t_voice_lock_hint_second", "5.04",
        (("lamp", "想想他問妳的那句話，跟門外的雨有關。"),),
        when=ready, options=(
            Option("replay", "重聽門廊錄音。", "ch5_t_voice_lock_recording", "重播老 K 的提問與凜的回答。"),
            Option("leave", "我先想一下。", None, "可以回門鎖重聽。"),
        ), cancel_choice_on_back=True,
    )
    source.add(
        "ch5_t_voice_lock_try_again", "5.04",
        steps=(sfx("beep", -28), say("rin", "先聽一次門廊錄音，再用同一句回答。")),
        when=ready, mode="animated",
    )
    source.add(
        "ch5_t_voice_lock_release", "5.04",
        steps=(say("rin", REPLY), sfx("switch", -20), say("rin", "門開了。下去看看。")),
        when=ready, mode="animated", completion=(set_flag(OPEN),),
    )
    source.add(
        "ch5_t_voice_lock_contact", "5.04",
        (("lamp", "還有人在問帳本。聽說是做廣播的，我還沒問到她叫什麼。"),),
        when=flag(OPEN), mode="animated",
    )
    source.quests.append(Quest(
        "ch5_voice_lock", "main", "打開後巷的聲音鎖",
        "阿梨的交班紀錄指向當舖後巷，門鎖裡存著一段門廊錄音。",
        "後巷通往地下室樓梯。", OPEN,
        (QuestStep("在後巷用原本的話回答門鎖。", OPEN, SOURCE),),
        visible_flags=(DATES_CONFIRMED,),
    ))
