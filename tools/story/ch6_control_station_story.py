"""Scene 6.04 keeps diagnostics local and resolves the incoming call once."""

from build_ch1_story import sfx
from ch1_closure import Option, Quest, QuestStep, all_of, flag, negate, say, set_flag
from ch6_control_station import OBJECT, STAGE
from ch6_studio_trial import TRIAL

DECIDED = "ch6_control_call_decided"
RELAYED = "ali_call_relayed"
DIAGNOSTICS = "ch6_t_control_diag"
CHOICE = "ch6_t_control_decision"
FORWARD = "ch6_t_relay_ali_call"
KEEP = "ch6_t_keep_relay_feed"


def _visibility(**values):
    return [dict(do="prop_visible", id=key, visible=visible) for key, visible in values.items()]


def _local_choice(text, ident, title, explanation, **next_step):
    return dict(do="choice", text=text, default="leave", cancel_choice_on_back=True, options=[
        dict(id=ident, text=title, explanation=explanation, **next_step),
        dict(id="leave", text="離開控制畫面", explanation="目前的接線保持不變。"),
    ])


def _diagnostic_steps():
    communications = _local_choice("監聽訊號已清楚。要接收通訊嗎？", "listen", "切到通訊",
                                   "只監聽來電。", target=CHOICE)
    levelled = [*_visibility(noisy_display=False, clear_display=True, call_alarm=True),
                sfx("phone_ring", -26), communications]
    interference = _local_choice("中繼器收到回訊。要校正接收濾波嗎？", "filter", "校正干擾",
                                 "讓線況與通訊回到可讀狀態。", steps=levelled)
    relay_selected = [*_visibility(relay_dim=False, relay_active=True), sfx("switch", -22), interference]
    return (
        dict(do="scene", id=STAGE),
        say("lamp", "我從控制室看線。凜，妳守錄音室的門。"),
        _local_choice("要查看中繼訊號嗎？", "relay", "查看中繼訊號",
                      "核對前庭到錄音室的兩路回訊。", steps=relay_selected),
    )


def add_control_station(source, dispatch, request):
    requested = flag(request)
    trial = flag(TRIAL)
    decided = flag(DECIDED)
    routed = flag(RELAYED)
    ready = all_of(requested, trial, negate(decided))

    dispatch[OBJECT] = ["ch6_t_control_revisit_forward", "ch6_t_control_revisit_keep", DIAGNOSTICS, "ch6_t_control_wait"]
    source.add("ch6_t_control_wait", "6.04", (
        ("label", "先和蘇確認室內試音，控制室才接得到監聽訊號。"),
    ), when=negate(trial), mode="animated")
    source.add(DIAGNOSTICS, "6.04", steps=_diagnostic_steps(), when=ready, mode="animated")
    source.add(CHOICE, "6.04", steps=(
        dict(do="scene", id=STAGE, props={
            "relay_dim": {"visible": False}, "relay_active": {"visible": True},
            "noisy_display": {"visible": False}, "clear_display": {"visible": True},
            "call_alarm": {"visible": True},
        }, fade=.15),
        say("ali", "有人等在我家外面。我想請凜過來，你能找到她嗎？"),
        say("lamp", "只有一條臨時線。把電話接給凜，就得暫停蘇那邊的監聽。"),
    ), when=ready, options=(
        Option("forward", "把電話轉給凜", FORWARD, "暫停監聽，讓凜直接收到來電。"),
        Option("keep", "守住監聽線", KEEP, "讓蘇接著試音。這通電話不會轉接。"),
        Option("leave", "暫不做決定", None, "保持來電與監聽的目前狀態。"),
        Option("review", "回去查線路", None, "回錄音室，再開終端查看回訊。"),
    ), cancel_choice_on_back=True)

    source.add(FORWARD, "6.04", (
        ("lamp", "阿梨在家門口等妳。她想請妳過去。我先把這一端的線留著。"),
        ("label", "電話已轉接。室內監聽暫停。"),
    ), when=ready, mode="animated", completion=(set_flag(RELAYED), set_flag(DECIDED)), cancel_on_skip=True)
    source.add(KEEP, "6.04", (
        ("su", "我把這段室內試音收完了。屋頂剛有人走過，妳去看看樓梯。"),
        ("label", "監聽已保留。這通電話沒有轉接。"),
    ), when=ready, mode="animated", completion=(set_flag(RELAYED, False), set_flag(DECIDED)), cancel_on_skip=True)
    source.add("ch6_t_control_revisit_forward", "6.04", (
        ("label", "電話已轉到凜這一端。監聽紀錄標為暫停。"),
    ), when=all_of(decided, routed), mode="animated")
    source.add("ch6_t_control_revisit_keep", "6.04", (
        ("label", "監聽線已保留，來電沒有轉接。"),
    ), when=all_of(decided, negate(routed)), mode="animated")

    source.quests.append(Quest(
        "ch6_control_call", "main", "查看控制室的來電",
        "從錄音室接上燈的監聽畫面，再決定要怎麼處理來電。",
        "已保存來電的去向。", DECIDED,
        (QuestStep("接上控制室，檢查中繼與通訊。", DECIDED, OBJECT),),
        visible_flags=(TRIAL,), completion_requires_steps=True,
    ))
