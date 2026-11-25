"""Production story and quest records for the factory roof."""

from ch1_closure import Option, Quest, QuestStep, all_of, flag, grant, item, negate, say, set_flag, transfer
from ch4_roof_layout import LEDGER_SAVED, MESSAGE_RECORDED, MIC_REQUESTED, ROOF_HEARD

MICROPHONE = "ch4_lamp_microphone"
DESTINATION = "ch4_lamp_bedside"


def install(source, dispatch):
    heard = flag(ROOF_HEARD)
    requested = flag(MIC_REQUESTED)
    recorded = flag(MESSAGE_RECORDED)
    ledger_saved = flag(LEDGER_SAVED)
    dispatch["roof_lantern"] = [
        "ch4_t_roof_transmission", "ch4_t_lamp_offer", "ch4_t_lamp_delivered_revisit", "ch4_t_lamp_route_reminder",
    ]
    source.add("ch4_t_roof_transmission", "16", (
        ("lamp", "電話亭說歡迎回來的那句，是我十二歲的時候錄的。他們說新版明天就換。"),
        ("rin", "我這一路都還聽得到你那一條。"),
        ("lamp", "我每次去問，他們都說明天。今天終端連我的錄音都沒播。"),
    ), when=all_of(ledger_saved, negate(heard)), mode="animated", cancel_on_skip=True,
        completion=(set_flag(ROOF_HEARD),))
    source.add("ch4_t_lamp_offer", "16", (
        ("rin", "你需要我做什麼？"),
        ("lamp", "如果妳願意再去一趟病房，可以替我把話筒放到我媽床邊嗎？我想錄一句現在的聲音。"),
    ), when=all_of(heard, negate(requested)), mode="animated",
        cancel_choice_on_back=True, options=(
            Option("take", "帶話筒去病房。", "ch4_t_lamp_accept", "側窗床位在病房走廊的東邊。"),
            Option("later", "等回去探房再帶。", "ch4_t_lamp_later", "話筒可以留在屋頂收訊箱。"),
        ))
    source.add("ch4_t_lamp_accept", "16", (
        ("rin", "話筒我帶著。我會放到側窗那張床旁邊。"),
    ), when=all_of(heard, negate(requested)), mode="animated", cancel_on_skip=True,
        completion=(grant(MICROPHONE), set_flag(MIC_REQUESTED)))
    source.add("ch4_t_lamp_later", "16", (
        ("rin", "我先把原帳帶回去。下一次經過再問你。"),
    ), when=all_of(heard, negate(requested)))
    source.add("ch4_t_lamp_route_reminder", "16", (
        ("lamp", "我媽的床在走廊最東邊的側窗。到了再叫我。"),
    ), when=all_of(requested, negate(recorded)))
    source.add("ch4_t_lamp_delivered_revisit", "16", (
        ("lamp", "先把那句話留在她床邊。等她想聽的時候再播。"),
    ), when=recorded)

    dispatch["lamp_bedside"] = ["ch4_t_lamp_bedside_record", "ch4_t_lamp_bedside_revisit"]
    source.add("ch4_t_lamp_bedside_record", "16", steps=(
        dict(do="world_action", id="ch4_lamp_recorder_press"),
        say("rin", "話筒放穩了。你想說什麼都可以。"),
        say("lamp", "媽，我今天有吃飯。我明天再跟妳說我去哪裡。"),
    ), when=all_of(requested, item(MICROPHONE), negate(recorded)), mode="animated", silence_music=True,
        cancel_on_skip=True, completion=(transfer(MICROPHONE, DESTINATION), set_flag(MESSAGE_RECORDED)))
    source.add("ch4_t_lamp_bedside_revisit", "16", (
        ("lamp", "這段錄音就留在這裡，等她想聽的時候再播。"),
    ), when=recorded)

    source.quests.append(Quest(
        "ch4_roof_transmission", "main", "上屋頂聽燈現在的聲音",
        "原帳辦公室的維修樓梯通到舊廠屋頂，天線收得到燈的通訊。",
        "聽到電話亭那段舊錄音的來歷。", ROOF_HEARD,
        (QuestStep("從辦公室沿樓梯上屋頂，找天線旁的收訊箱。", ROOF_HEARD, "roof_lantern"),),
        visible_flags=(LEDGER_SAVED,),
    ))
    source.quests.append(Quest(
        "ch4_lamp_bedside", "side", "替燈把話筒帶到母親床邊",
        "燈想留下一段現在的聲音。公用病房最東邊有一張他的母親使用的床位。",
        "在側窗那張床邊留下燈的錄音。", MESSAGE_RECORDED,
        (QuestStep("把話筒放到病房的側窗床邊，讓燈錄下留言。", MESSAGE_RECORDED, "lamp_bedside"),),
        visible_flags=(MIC_REQUESTED,),
    ))
