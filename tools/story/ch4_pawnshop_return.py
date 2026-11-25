"""Pawnshop return. Investigating the original ledger in the next chapter is separate."""

from build_ch1_story import actor, face, letterbox, move, stage, wait
from ch1_closure import Option, Quest, QuestStep, all_of, flag, item, negate, say, set_flag

LEDGER = "ch4_original_ledger_copy"
ROOF_HEARD = "ch4_roof_radio_heard"
HEARD = "ch4_pawnshop_homecoming_seen"


def add_pawnshop_return(source, dispatch):
    may_return = all_of(flag("ch4_original_ledger_saved"), item(LEDGER), flag(ROOF_HEARD))
    dispatch["old_k"][0:0] = ["ch4_t_homecoming_reminder", "ch4_t_homecoming_choice"]
    source.add(
        "ch4_t_homecoming_choice", "17",
        (("old_k", "妳回來了。原帳帶在身上嗎？"),),
        when=all_of(may_return, negate(flag(HEARD))),
        options=(
            Option("sit", "和老 K 談原帳。", "ch4_t_homecoming",
                   "在當舖把廠房的原帳交代清楚。"),
            Option("later", "待會再談。", None, "可以先在店裡歇一下。"),
        ),
        cancel_choice_on_back=True,
    )
    shot = stage("ch4_pawnshop_return", 312, 293.0, zoom=0.88, feet=348)
    shot["props"] = {"copied_ledger": {"visible": False}}
    source.add(
        "ch4_t_homecoming", "17", steps=(
            shot, letterbox(),
            actor("old_k", "old_k", 364, 348, facing=-1, scale=2.05),
            actor("rin", "rin", 185, 348, facing=1, scale=2.05),
            wait(0.65),
            move("rin", 249, 348, t=1.52),
            move("old_k", 402, 348, t=0.78),
            face("old_k", -1),
            wait(0.65),
            say("old_k", "帶傘了嗎？妳把外套脫下來，我拿乾的給妳。"),
            wait(0.55),
            dict(do="reach", id="rin", hand="back", space="prop",
                 prop="copied_ledger", to=[47, 14], time=0.34),
            dict(do="prop_visible", id="copied_ledger", visible=True),
            dict(do="prop_move", id="copied_ledger", to=[263, 278], time=0.48),
            dict(do="reach", id="rin", hand="back", release=True, time=0.24),
            say("rin", "我把帳帶回來了。"),
            wait(1.9),
        ),
        when=all_of(may_return, negate(flag(HEARD))), mode="animated",
        completion=(set_flag(HEARD),),
    )
    source.add(
        "ch4_t_homecoming_reminder", "17",
        (("rin", "原帳還在。明天再仔細看看店裡的標籤跟帳冊。"),),
        when=all_of(may_return, flag(HEARD)),
    )
    source.quests.append(Quest(
        "ch4_homecoming", "main", "把原帳帶回當舖",
        "工廠原帳留下了一筆遮住簽名的紀錄。",
        "老 K 已知道凜把原帳帶了回來。", HEARD,
        (QuestStep("在當舖把原帳交代給老 K。", HEARD, "old_k"),),
        visible_flags=(ROOF_HEARD,),
    ))
