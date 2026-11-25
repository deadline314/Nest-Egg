"""Playable 5.02, comparing the old receipt with the historical fee ledger."""

from ch1_closure import Option, Quest, QuestStep, all_of, flag, negate, set_flag
from ch5_fee_layout import FIRST_CATCH

RECEIPT_READ = "ch5_fee_receipt_read"
LEDGER_READ = "ch5_fee_ledger_read"
COMPARED = "ch5_fee_ledger_compared"
RECEIPT = (
    ("label", "這張當舖收據寫著，委託報酬是 800，扣除手續費 80，實領 720。"),
)
LEDGER = (
    ("label", "總帳寫著每單撥入 10%，歷年累計 52,000 信用點，留給凜。"),
    ("rin", "這一頁的章和舊收據上的章一樣。"),
)


def _register_read(source, dispatch, binding, read, lines):
    scene = f"ch5_t_read_{binding}"
    revisit = f"ch5_t_revisit_{binding}"
    unlocked = flag(FIRST_CATCH)
    dispatch[binding] = [scene, revisit]
    source.add(scene, "5.02", lines, when=all_of(unlocked, negate(flag(read))),
               mode="animated", cancel_on_skip=True, completion=(set_flag(read),))
    source.add(revisit, "5.02", lines, when=all_of(unlocked, flag(read)), mode="animated")


def install(source, dispatch):
    _register_read(source, dispatch, "fee_receipt", RECEIPT_READ, RECEIPT)
    _register_read(source, dispatch, "fee_ledger", LEDGER_READ, LEDGER)
    ready = all_of(flag(FIRST_CATCH), flag(RECEIPT_READ), flag(LEDGER_READ), negate(flag(COMPARED)))
    dispatch["inventory_board"][:0] = ["ch5_t_fee_compared", "ch5_t_choose_fee", "ch5_t_need_fee_pages"]
    source.add("ch5_t_need_fee_pages", "5.02", (
        ("rin", "先翻櫃台左邊的舊收據和右邊的總帳，再回來比對。"),
    ), when=all_of(flag(FIRST_CATCH), negate(all_of(flag(RECEIPT_READ), flag(LEDGER_READ)))),
        mode="animated")
    source.add("ch5_t_choose_fee", "5.02", (
        ("label", "舊收據和總帳蓋著同一個當舖章。"),
        ("rin", "每筆委託的錢是怎麼存進總帳的？"),
    ), when=ready, cancel_choice_on_back=True, options=(
        Option("gross", "每單的報酬都存了進去。", "ch5_t_fee_check_receipt", "核對收據的報酬和實領。"),
        Option("fee_share", "每單的一成都存進同一本帳。", "ch5_t_confirm_fee", "比較收據的手續費與總帳的比例。"),
        Option("live_balance", "總帳寫的是我現在的餘額。", "ch5_t_fee_check_ledger", "核對總帳的累計欄。"),
        Option("leave", "先離開。", None, "單據會留在櫃台。"),
    ))
    source.add("ch5_t_fee_check_receipt", "5.02", (
        ("label", "左頁的 720 是實領。請再看報酬和手續費。"),
    ), when=ready, mode="animated")
    source.add("ch5_t_fee_check_ledger", "5.02", (
        ("label", "右頁的 52,000 是歷年累計。請再看每單撥入的比例。"),
    ), when=ready, mode="animated")
    source.add("ch5_t_confirm_fee", "5.02", (
        ("rin", "我一直以為那一成是保費。老 K 把它留在店裡，還寫了我的名字。"),
        ("rin", "我還不知道誰付了復原帳。阿梨看過灰衣人付錢，我去問她。"),
    ), when=ready, mode="animated", cancel_on_skip=True, completion=(set_flag(COMPARED),))
    source.add("ch5_t_fee_compared", "5.02", (
        ("label", "第二道滑扣已開。總帳寫著按單存給凜的手續費。"),
    ), when=flag(COMPARED), mode="animated")

    source.quests.append(Quest(
        "ch5_fee_ledger", "main", "核對櫃台的舊收據和存款總帳。",
        "第一道滑扣鬆開後，凜發現收據和總帳蓋著同一個當舖章。",
        "記下手續費存給凜的來歷。", COMPARED,
        (QuestStep("查看櫃台左邊的舊委託收據。", RECEIPT_READ, "fee_receipt"),
         QuestStep("查看櫃台右邊的手續費存款總帳。", LEDGER_READ, "fee_ledger"),
         QuestStep("回盤點板核對兩份單據。", COMPARED, "inventory_board")),
        visible_flags=(FIRST_CATCH,), completion_requires_steps=True,
    ))
