"""Scene 6.03 permission checks and a local-only microphone rehearsal."""

from build_ch1_story import sfx
from ch1_closure import Option, Quest, QuestStep, all_of, flag, item, negate, say, set_flag
from ch6_relay_water import POWERED
from ch6_studio_trial import BOOTH_SU, MET, MONITOR, TRIAL, YARD_SU

ORIGINAL = "ch4_original_ledger_copy"
MEETING = "ch6_t_meet_su_studio"
CHECK = "ch6_t_choose_studio_trial"
CHECK_BLANK = "ch6_t_choose_blank_trial"
TAKE = "ch6_t_studio_trial"


def add_studio_trial(source, dispatch, request):
    powered = all_of(flag(request), flag(POWERED))
    met = flag(MET)
    rehearsed = flag(TRIAL)
    original = item(ORIGINAL)
    ready = all_of(powered, met, negate(rehearsed))
    heard_earlier = flag("sq4_broadcast_heard")
    dispatch[YARD_SU] = [MEETING]
    source.add(MEETING, "6.03", steps=(
        say("su", "雨進不來了。妳先看門上的燈，我進去試麥克風。"),
        say("rin", "試音只走室內的線。要公開的欄位再逐一核對。"),
    ), when=all_of(powered, negate(met)), mode="animated", completion=(set_flag(MET),),
        cancel_on_skip=True)

    dispatch[MONITOR] = ["ch6_t_trial_monitor_ready", "ch6_t_trial_read_scope", "ch6_t_trial_wait_for_su"]
    source.add("ch6_t_trial_wait_for_su", "6.03", (
        ("label", "試音稿收在桌上。先到掛著白燈的門外找蘇。"),
    ), when=negate(met), mode="animated")
    source.add("ch6_t_trial_read_scope", "6.03", steps=(
        say("label", "試音稿只列同意公開的姓名、復原費和代付款。標記未確認的部分留在原帳。"),
        say("label", "播出線封閉。這裡可以重看字幕。"),
        dict(do="branch", when=heard_earlier, steps=[
            say("rin", "收音機裡那段也先念名字。那頂帽子，妳還留著嗎？"),
            say("su", "帽子還留著。先把這次要讀的欄位核對好。"),
        ]),
        dict(do="branch", when=all_of(negate(heard_earlier), flag("ch4_voice_demo_read")), steps=[
            say("rin", "我在病房看過那段示範。名單到本人點頭才能動。"),
        ]),
    ), when=all_of(powered, met, negate(rehearsed)), mode="animated")
    source.add("ch6_t_trial_monitor_ready", "6.03", (
        ("label", "室內試音已確認。姓名、復原費與代付欄各自核對公開許可。"),
        ("label", "這是室內試音留檔。控制室另管對外播報。"),
    ), when=rehearsed, mode="animated")

    dispatch[BOOTH_SU] = ["ch6_t_trial_monitor_ready", CHECK, CHECK_BLANK]
    source.add(CHECK, "6.03", steps=(
        say("su", "有些人只同意列復原費，沒有同意公開名字。那行我會留空。要先試室內的線嗎？"),
    ), when=all_of(ready, original), options=(
        Option("check_line", "確認室內試音", TAKE, "試音與字幕留在室內。"),
        Option("leave", "先暫停試音", None, "可以回來試音。"),
    ), cancel_choice_on_back=True)
    source.add(CHECK_BLANK, "6.03", (
        ("su", "原帳不在手上。先用空白試音稿，單獨測麥克風和字幕，好嗎？"),
    ), when=all_of(ready, negate(original)), options=(
        Option("check_line", "用空白稿試音", TAKE, "不讀姓名或帳目。"),
        Option("leave", "先暫停試音", None, "可以回來試音。"),
    ), cancel_choice_on_back=True)
    source.add(TAKE, "6.03", steps=(
        sfx("switch", -19),
        say("su", "先測室內麥克風的清晰度。還沒確認許可的欄位一律留白。"),
        say("rin", "我守這扇門。妳念完一頁，我再把下一頁放到桌邊。"),
        say("label", "室內試音通過。對外播報仍待命。"),
    ), when=ready, mode="animated", completion=(set_flag(TRIAL),), cancel_on_skip=True)

    source.quests.append(Quest(
        "ch6_studio_trial", "main", "核對廣播站試音",
        "在門邊找蘇。到錄音室確認室內麥克風與字幕。",
        "試音已確認，可以聯絡控制室。", TRIAL,
        (QuestStep("到錄音室門外找蘇。", MET, YARD_SU),
         QuestStep("在錄音室確認室內試音。", TRIAL, BOOTH_SU)),
        visible_flags=(POWERED,), completion_requires_steps=True,
    ))
