"""Scene 5.09 quotes the offer and records only Rin's deliberate decisions."""

from ch1_closure import Binding, Option, Quest, QuestStep, all_of, any_of, flag, item, negate, say, set_flag
from build_ch1_story import wait
from ch5_offer_layout import CLAUSE_READ, PAPERS, YE

DECLINED = "ch5_ye_offer_declined"
ASKED = "ch5_ye_ahan_asked"
NAME_WITNESSED = "sq7_ye_name_seen"
HELD_TAPE = "ch3_ahan_tape"
REFUSE = "ch5_t_ye_decline"
ASK = "ch5_t_ye_ahan"

OFFER_LINES = (
    ("ye", "我給妳 480,000 信用點。妳照常工作，這件事留在我們之間。"),
    ("rin", "這也是一間晴岸房子的價錢。妳想買的是我不再問。"),
    ("ye", "妳是我們最好的樣本。文件在桌上，簽了字今天就能領錢。"),
)
REFUSAL = Option("refuse", "拒絕簽下保密要約", REFUSE, "拒簽後仍由凜保管手上的紀錄。")
QUESTION = Option("ask_ahan", "問她手背上的名字", ASK, "問葉這個名字對她的意義。")
LEAVE = Option("leave", "先離開", None, "可以回櫃台再談。")


def _negotiation(source, dispatch):
    entered = flag(CLAUSE_READ)
    closed = flag(DECLINED)
    known_name = any_of(flag(NAME_WITNESSED), item(HELD_TAPE))
    can_ask = all_of(entered, known_name, negate(flag(ASKED)))
    pending = all_of(entered, negate(closed))

    dispatch[YE] = ["ch5_t_ye_offer_with_ahan", "ch5_t_ye_offer",
                    "ch5_t_ye_revisit_with_ahan", "ch5_t_ye_revisit"]
    source.add("ch5_t_ye_offer_with_ahan", "5.09", OFFER_LINES,
               when=all_of(pending, can_ask), options=(REFUSAL, QUESTION, LEAVE),
               cancel_choice_on_back=True)
    source.add("ch5_t_ye_offer", "5.09", OFFER_LINES,
               when=pending, options=(REFUSAL, LEAVE), cancel_choice_on_back=True)
    source.add(REFUSE, "5.09", (
        ("rin", "把表收回去。我會自己決定帳本拿去做什麼。"),
        ("ye", "我記住妳的答覆了。桌上的文件妳可以再看。"),
    ), when=pending, mode="animated", cancel_on_skip=True, completion=(set_flag(DECLINED),))
    source.add("ch5_t_ye_revisit_with_ahan", "5.09", (
        ("ye", "我已經聽過妳的答覆。妳還想問別的嗎？"),
    ), when=all_of(closed, can_ask), options=(QUESTION, LEAVE), cancel_choice_on_back=True)
    source.add("ch5_t_ye_revisit", "5.09", (
        ("ye", "保密要約已經收回。桌上的文件還可以查看。"),
    ), when=all_of(entered, closed), mode="animated")
    source.add(ASK, "5.09", steps=(
        say("rin", "妳手背上的名字是阿翰嗎？"),
        wait(0.45),
        say("ye", "那個名字，我每天早上都要再寫一次。"),
    ), when=can_ask, mode="animated", cancel_on_skip=True, completion=(set_flag(ASKED),))


def _read_papers(source, dispatch):
    entrance = flag(CLAUSE_READ)
    quote = ("label", "保密要約列了 480,000 信用點，桌上的文件仍未簽署。")
    selection = flag("sq3_room_proposal_done")
    proposals = (
        ("morning", "原來我只提了晨窗。要不要選這間，最後由老 K 決定。"),
        ("quiet", "原來我只提了靜窗。要不要選這間，最後由老 K 決定。"),
        ("late", "原來我只提了晚窗。要不要選這間，最後由老 K 決定。"),
    )
    entries = []
    for room, line in proposals:
        scene = f"ch5_t_ye_quote_{room}"
        entries.append(scene)
        source.add(scene, "5.09", (quote, ("rin", line)),
                   when=all_of(entrance, selection, flag("room_choice", room)), mode="animated")
    entries.append("ch5_t_ye_quote")
    dispatch[PAPERS] = entries
    source.add("ch5_t_ye_quote", "5.09", (quote,), when=entrance, mode="animated")


def install(source, dispatch, chapter):
    source.bindings[YE] = Binding("npc", chapter, f"res://data/npcs/ch5_{YE}.tres")
    source.bindings[PAPERS] = Binding("object", chapter, f"res://data/npcs/ch5_{PAPERS}.tres")
    _negotiation(source, dispatch)
    _read_papers(source, dispatch)
    source.quests.append(Quest(
        "ch5_ye_pawnshop_offer", "main", "回當舖聽葉的條件",
        "凜已看過贖回條文。葉正在當舖，桌上有一份同樣金額的保密要約。",
        "確認拒簽，保留凜處置帳本的決定。", DECLINED,
        (QuestStep("回當舖櫃台與葉談完，明確拒絕保密要約。", DECLINED, YE),),
        visible_flags=(CLAUSE_READ,), completion_requires_steps=True,
    ))
