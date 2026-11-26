"""The optional durable chapter-ending call through the actual street booth."""

from build_ch1_story import sfx
from ch1_closure import Binding, Option, Quest, QuestStep, all_of, flag, negate, say, set_flag

OFFER_SETTLED = "ch5_ye_offer_declined"
CALL_REQUESTED = "ch5_ledger_broadcast_requested"
BOOTH = "paymaster_phone"
COMPLETE = "ch5_t_make_ledger_call"
INTRO = "ch5_t_offer_ledger_call"


def install(source, dispatch, chapter):
    source.bindings[BOOTH] = Binding("object", chapter, "res://data/npcs/ch5_paymaster_phone.tres")
    ready = all_of(flag(OFFER_SETTLED), negate(flag(CALL_REQUESTED)))
    dispatch[BOOTH] = ["ch5_t_ledger_call_revisit", INTRO, "ch5_t_ledger_call_wait"]
    source.add("ch5_t_ledger_call_wait", "5.11", (
        ("rin", "先把當舖的事談清楚，再打給燈。"),
    ), when=negate(flag(OFFER_SETTLED)))
    source.add(INTRO, "5.11", (
        ("rin", "街上的電話還通。現在要把帳的事告訴燈嗎？"),
    ), when=ready, options=(
        Option("call", "把帳的事告訴燈。", COMPLETE, "約好怎麼讓其他人看到帳本。"),
        Option("leave", "先離開電話亭。", None, "可以隨時回來打給燈。"),
    ), cancel_choice_on_back=True)
    source.add(COMPLETE, "5.11", steps=(
        dict(do="world_action", id="ch5_phone_hook_press"),
        sfx("phone_pickup", -18),
        sfx("phone_dial", -24),
        say("rin", "我們查到誰在付錢，也查到復原的代價。這些人有權知道自己簽了什麼。"),
        say("lamp", "我會記下來。妳要我先做什麼？"),
        say("rin", "公開帳本。"),
        sfx("phone_hangup", -22),
    ), when=ready, mode="animated", cancel_on_skip=True, completion=(set_flag(CALL_REQUESTED),))
    source.add("ch5_t_ledger_call_revisit", "5.11", (
        ("lamp", "妳交代的事已經記下。資料先收好，我去找能播出去的地方。"),
    ), when=flag(CALL_REQUESTED), mode="animated")

    source.quests.append(Quest(
        "ch5_ledger_call", "main", "請燈準備公開帳本",
        "凜拒絕了買斷的要約。電話亭巷的話筒還能接通燈。",
        "燈開始準備讓其他人看到帳本。", CALL_REQUESTED,
        (QuestStep("到電話亭巷，撥電話把帳的事告訴燈。", CALL_REQUESTED, BOOTH),),
        visible_flags=(OFFER_SETTLED,),
    ))
