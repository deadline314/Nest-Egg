"""Office evidence and an optional factory recording for Hollow Shell."""

from ch1_closure import Option, Quest, QuestStep, all_of, flag, grant, item, negate, set_flag

LEDGER_DOCUMENT = "ch4_original_ledger_copy"
OFFICE_OPEN = "ch4_office_access"
WARD_SLIP = "ch4_ward_collection_slip"
LEDGER_READ = "ch4_original_ledger_read"
LEDGER_SAVED = "ch4_original_ledger_saved"


def add_office_evidence(source, dispatch):
    source.documents[LEDGER_DOCUMENT] = {
        "name": "舊廠原帳副本",
        "icon": "doc_stub",
        "description": "原帳記著凜的姓名和耗損，另一個簽名被遮住。",
        "body": (
            "十七批次的原帳把凜列為受錨者，錨人的姓名仍然以匿名登記。\n"
            "本輪已經復原 {run_restorations} 次。\n"
            "原帳當時記下的耗損為 91%。"
        ),
        "source_actor": "ch4_original_ledger",
        "show_run_restorations": True,
    }
    dispatch["original_ledger"] = [
        "ch4_t_ledger_revisit", "ch4_t_ledger_read_again",
        "ch4_t_ledger_check", "ch4_t_ledger_needs_slip",
    ]
    can_read = all_of(flag(OFFICE_OPEN), item(WARD_SLIP))
    source.add("ch4_t_ledger_check", "12", (
        ("rin", "封面寫了十七批次。取件聯上的編號跟這張一樣。"),
        ("lamp", "帳本留在辦公室。先展開取件聯上的那一頁。"),
    ), when=all_of(can_read, negate(flag(LEDGER_READ))), options=(
        Option("compare", "對照取件聯，展開原帳。", "ch4_t_ledger_page", "查看同批原始紀錄。"),
        Option("leave", "我想先去看看旁邊的檔案。", None, "取件聯會留在背包。"),
    ), cancel_choice_on_back=True)
    source.add("ch4_t_ledger_needs_slip", "12", (
        ("rin", "先拿病房的取件聯，才知道原帳裡是哪一批。"),
    ), when=all_of(flag(OFFICE_OPEN), negate(item(WARD_SLIP))))
    source.add("ch4_t_ledger_page", "12", (
        ("rin", "受錨者是我，付這筆的人欄位卻遮住了。"),
        ("lamp", "錨人會替受錨者分擔復原的代價。這張表只寫當時的耗損，寫的人把名字藏了。"),
    ), when=all_of(can_read, negate(flag(LEDGER_READ))), mode="animated", completion=(set_flag(LEDGER_READ),))
    source.add("ch4_t_ledger_read_again", "12", (
        ("rin", "這一頁的數字連著塗黑的欄位。我想把原樣保留下來。"),
    ), when=all_of(can_read, flag(LEDGER_READ), negate(flag(LEDGER_SAVED))), options=(
        Option("save", "把原帳的這一頁存下來。", "ch4_t_ledger_saved", "原帳留在桌上，背包多一份副本。"),
        Option("leave", "先把原帳闔上。", None, "還可以回來保存這一頁。"),
    ), cancel_choice_on_back=True)
    source.add("ch4_t_ledger_saved", "12", (
        ("rin", "這一頁也存一份。我要保留它還在帳本上的樣子。"),
    ), when=all_of(can_read, flag(LEDGER_READ), negate(flag(LEDGER_SAVED))),
       mode="animated", completion=(grant(LEDGER_DOCUMENT, "original_ledger"), set_flag(LEDGER_SAVED)))
    source.add("ch4_t_ledger_revisit", "12", (
        ("rin", "原帳這一頁也在副本裡。塗黑的地方照原樣留著。"),
    ), when=all_of(flag(OFFICE_OPEN), flag(LEDGER_SAVED)))

    source.quests.append(Quest(
        "ch4_read_original_ledger", "main", "到辦公室保存原帳",
        "廠房裡保留了十七批次的原頁，可以拿病房的取件聯核對。",
        "把原帳副本帶在身上。", LEDGER_SAVED,
        (QuestStep("在工作臺核對取件聯，讀取原帳。", LEDGER_READ, "original_ledger"),
         QuestStep("在帳本旁保存這一頁的副本。", LEDGER_SAVED, "original_ledger")),
        visible_flags=(OFFICE_OPEN,), completion_requires_steps=True,
    ))
