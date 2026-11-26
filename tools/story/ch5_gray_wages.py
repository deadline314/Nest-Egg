"""The optional paid service route and the opening of its return latch."""

from ch1_closure import Binding, Option, Quest, QuestStep, all_of, flag, grant, negate, set_flag, transaction, say

DECLINED_BUYOUT = "ch5_ye_offer_declined"
PAID = "ch5_gray_first_wage_paid"
UNLATCHED = "ch5_gray_return_unlatched"
RECEIPT = "ch5_gray_wage_receipt"
TRANSACTION = "ch5.gray_path.first_wage"
AMOUNT = 800
COUNTER = "gray_wage_notice"
LATCH = "gray_return_latch"
PAY = "ch5_t_pay_first_gray_wage"
INSUFFICIENT = "ch5_t_gray_wage_insufficient"


def install(source, dispatch, chapter):
    for name in (COUNTER, LATCH):
        source.bindings[name] = Binding("object", chapter, f"res://data/npcs/ch5_{name}.tres")
    source.transactions[TRANSACTION] = {
        "resource": "res://data/story_transactions/ch5_gray_first_wage.tres",
        "caller": "chapter5",
        "on_failure": {"insufficient_credits": INSUFFICIENT},
    }
    source.documents[RECEIPT] = {
        "name": "灰道第一期工錢收據",
        "description": "必安留下的交班單，第一期已由凜付清。",
        "body": f"凜為本期交班支付 {AMOUNT} 信用點。這張收據適用於當舖地下室到電話亭的服務通道。以後各段另有交班紀錄。",
        "icon": "doc_stub",
        "source_actor": "ch5_gray_wage_notice",
    }
    eligible = flag(DECLINED_BUYOUT)
    unpaid = all_of(eligible, negate(flag(PAID)))
    notice = "ch5_t_gray_wage_menu"
    dispatch[COUNTER] = ["ch5_t_gray_wage_paid", notice, "ch5_t_gray_wage_wait"]
    source.add("ch5_t_gray_wage_wait", "5.10",
               (("rin", "先回店裡把那份要約談清楚。"),), when=negate(eligible))
    source.add(notice, "5.10", (
        ("label", f"本期工錢是 {AMOUNT} 信用點。付清後，可從小桌往外走到電話亭巷。"),
        ("rin", "所以連離開時走哪條路，也是從他的帳上付出去的。"),
    ), when=unpaid, options=(
        Option("pay", f"支付 {AMOUNT} 信用點。", PAY, "付清這一期，開啟灰道的第一段。"),
        Option("street", "先走地面的街道。", None, "從港區街道前往電話亭巷。"),
    ), cancel_choice_on_back=True)
    source.add(PAY, "5.10", (
        ("rin", "這一期從我的錢付。給我留張收據。"),
    ), when=unpaid, mode="animated", cancel_on_skip=True,
        completion=(transaction(TRANSACTION), grant(RECEIPT), set_flag(PAID)))
    source.add(INSUFFICIENT, "5.10", (
        ("rin", "我現在付不起這一期。先從地面去電話亭。"),
    ), when=unpaid, mode="animated")
    source.add("ch5_t_gray_wage_paid", "5.10", (
        ("label", "這一期已結清。裡面的回口要從小桌那一側拉開。"),
    ), when=flag(PAID), reference_items=(RECEIPT,), mode="animated")

    dispatch[LATCH] = ["ch5_t_gray_latch_open", "ch5_t_gray_latch_release"]
    source.add("ch5_t_gray_latch_release", "5.10", steps=(
        dict(do="world_action", id="ch5_gray_latch_press"),
        say("rin", "把這頭的滑扣扳下去，就能從電話亭回到小桌。"),
    ), when=all_of(flag(PAID), negate(flag(UNLATCHED))), mode="animated", cancel_on_skip=True,
        completion=(set_flag(UNLATCHED),))
    source.add("ch5_t_gray_latch_open", "5.10", (
        ("rin", "回口留著。要回當舖就走這條路。"),
    ), when=flag(UNLATCHED), mode="animated")

    source.quests.append(Quest(
        "ch5_gray_first_wage", "side", "接下第一期灰道工錢",
        "地下室的交班單可以自願接下。也可以走地面前往電話亭。",
        "打開當舖地下室和電話亭之間的灰道。", UNLATCHED,
        (QuestStep("查看地下室的交班單，選擇是否付款。", PAID, COUNTER),
         QuestStep("在灰道的小桌旁，從裡面打開回口。", UNLATCHED, LATCH)),
        visible_flags=(DECLINED_BUYOUT,), completion_requires_steps=True,
    ))
