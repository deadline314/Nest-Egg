"""Compile the owned testimony and the optional evidence review in scene 5.03."""

from ch1_closure import Binding, Option, Quest, QuestStep, all_of, flag, grant, negate, set_flag
from ch5_revival_route import LEDGER_COMPARED

DATES = "ch5_pear_dates_confirmed"
DOCUMENT = "ch5_pear_shift_dates"
RECORD = "ch5_t_pear_record_dates"


def add_pear_testimony(source, dispatch, chapter):
    source.bindings["pear"] = Binding("npc", chapter, "res://data/npcs/ch5_pear.tres")
    source.documents[DOCUMENT] = {
        "name": "阿梨抄下的交班日期",
        "description": "杯墊背面的店章每月蓋在同一天。",
        "body": "阿梨抄下杯墊背面的店章。連續幾個月，店章都蓋在同一天。灰外套每次帶現金，把收條壓在杯子底下。阿梨手上只留著交班日期，原帳的付帳人欄仍空著。",
        "icon": "doc_stub",
        "source_actor": "ch5_pear",
    }
    ready = all_of(flag(LEDGER_COMPARED), negate(flag(DATES)))
    dispatch["pear"] = ["ch5_t_pear_review_offer", "ch5_t_pear_question", "ch5_t_pear_wait"]
    source.add("ch5_t_pear_wait", "5.03", (
        ("ali", "帶當舖那兩份單據的對照來，我再替妳找日期。"),
    ), when=negate(flag(LEDGER_COMPARED)), mode="animated")
    source.add("ch5_t_pear_question", "5.03", (
        ("rin", "我出事的地方總有人穿灰外套。那個人也來過這裡嗎？"),
        ("ali", "我還留著那幾個月的交班日期。妳要現在看嗎？"),
    ), when=ready, options=(
        Option("check_dates", "看阿梨留下的交班日期", RECORD, "確認後抄進帳冊。"),
        Option("leave", "先離開", None, "可以隨時回來問。"),
    ), cancel_choice_on_back=True)
    source.add(RECORD, "5.03", (
        ("ali", "杯墊背面有店章。連續幾個月，他都在同一天帶現金來。"),
        ("ali", "他一坐下就把收條壓在杯子底下。搬運的人送到終端，值班的人就會蓋章。"),
        ("rin", "所以同一天重複出現，原帳卻還是沒寫誰付的錢。"),
        ("ali", "我這裡只有交班日期。要查原單，可以從當舖的後巷找起。"),
    ), when=ready, mode="animated", completion=(grant(DOCUMENT), set_flag(DATES)),
       cancel_on_skip=True)
    _review(source)
    source.quests.append(Quest(
        "ch5_pear_testimony", "main", "到復原館找阿梨核對日期",
        "當舖的帳已核對。要追查原帳的搬運費，去復原館問阿梨。",
        "把阿梨留下的交班日期抄進帳冊。", DATES,
        (QuestStep("到復原館吧台問阿梨灰衣人領款的日期。", DATES, "pear"),),
        visible_flags=(LEDGER_COMPARED,), completion_requires_steps=True,
    ))


def _review(source):
    confirmed = all_of(flag(LEDGER_COMPARED), flag(DATES))
    source.add("ch5_t_pear_review_offer", "5.03", (
        ("ali", "妳已經抄過交班日期了。想再看一下幾份單據嗎？"),
    ), when=confirmed, options=(
        Option("review", "翻看手上的線索", "ch5_t_pear_review", "比對單據，保留疑問。"),
        Option("leave", "先離開", None, "交班日期留在帳冊裡。"),
    ), reference_items=(DOCUMENT,), cancel_choice_on_back=True)
    evidence = (
        ("receipt", "看店內收條", "看看收條上寫了什麼。",
         "收條列出了搬運費。店裡的客人可能看過交接，但收條沒有收款人的名字。"),
        ("dates", "看阿梨的交班日期", "看看店章的日期。",
         "灰衣人在交班那天都來過。出現在店裡，跟掏錢的是不是同一個人，還得查。"),
        ("ledger", "看舊帳裡的搬運費", "看看原帳留下的記號。",
         "老 K 或葉或許看過這類單據，但原帳的付帳人欄是空白。"),
    )
    options = []
    for short_id, text, explanation, line in evidence:
        scene = f"ch5_t_pear_review_{short_id}"
        options.append(Option(short_id, text, scene, explanation))
        source.add(scene, "5.03", (("rin", line),), when=confirmed, mode="animated")
    source.add("ch5_t_pear_review", "5.03", (
        ("rin", "三份紀錄可以對在一起看。哪張能幫我查清楚？"),
    ), when=confirmed, options=(*options, Option("leave", "收起帳冊", None, "可以稍後再比對。")),
        reference_items=(DOCUMENT,), cancel_choice_on_back=True)
