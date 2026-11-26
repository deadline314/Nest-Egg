"""5.08 separates Old K's explanation from the physical redemption clause."""

from ch1_closure import Binding, Option, Quest, QuestStep, all_of, flag, negate, set_flag
from ch5_agreement_layout import APPENDIX, CONFIRMED, OLD_K

EXPLAINED = "ch5_backup_trade_explained"
CLAUSE_READ = "ch5_redemption_clause_read"
CONSENT_STATUS = "ch5_memory_redemption_status"
AWAITING = "awaiting_personal_consent"
OFFER = "ch5_t_ask_backup_trade"
EXPLAIN = "ch5_t_explain_backup_trade"
SUMMARY = "ch5_t_summarize_backup_trade"
READ = "ch5_t_read_redemption_clause"

FACT = ("old_k", "我把妳賣給了讓妳活著的人。葉拿妳的備份當樣本，答應不查這張椅子。")
DECISION = ("old_k", "我還沒決定要不要贖回。拿回記憶，我就得記得舊椅當時記下的四十次。")
CLAUSE = (
    ("label", "沈望簽過的原條文寫著，契約一旦成立，不得中止。"),
    ("label", "讀去的記憶存放在天穹帳房。贖回須當事人與錨人同意。"),
    ("label", "贖回費用是 480,000 信用點。目前等待本人同意。"),
)


def _old_k(source, dispatch):
    ready = all_of(flag(CONFIRMED), negate(flag(EXPLAINED)))
    dispatch[OLD_K] = ["ch5_t_backup_revisit", "ch5_t_backup_clause_hint", OFFER]
    source.add(OFFER, "5.08", (("rin", "錨椅的登記已經核對了。我想問清楚那筆交易。"),),
               when=ready, cancel_choice_on_back=True, options=(
                   Option("explain", "問他為什麼把資料交出去。", EXPLAIN, "聽老 K 說明備份交易。"),
                   Option("summary", "只問交換的條件。", SUMMARY, "直接核對他和葉交換的條件。"),
                   Option("leave", "先離開。", None, "可以再回樓梯旁找老 K。"),
               ))
    source.add(EXPLAIN, "5.08", (
        ("rin", "筆記最後一頁是空的。你每次問我的那句，怎麼沒寫？"),
        ("old_k", "那句不用寫。"),
        ("rin", "椅子的登記我核對過了。你拿我的資料換了什麼？"),
        FACT,
        ("old_k", "我不是替妳付。是我想付。"),
        ("rin", "我沒有問你。"),
        ("old_k", "妳也沒問過。"),
        ("rin", "你想要我怎麼做？"),
        ("old_k", "去賺妳的錢。妳自己那一份還要用。"),
        DECISION,
    ), when=ready, mode="animated", completion=(set_flag(EXPLAINED),), cancel_on_skip=True)
    source.add(SUMMARY, "5.08", (FACT, DECISION), when=ready, mode="animated",
               completion=(set_flag(EXPLAINED),), cancel_on_skip=True)
    source.add("ch5_t_backup_clause_hint", "5.08", (
        ("old_k", "再往裡走，桌上那份附頁寫了贖回的條件。"),
    ), when=all_of(flag(EXPLAINED), negate(flag(CLAUSE_READ))), mode="animated")
    source.add("ch5_t_backup_revisit", "5.08", (
        ("rin", "附頁寫可以拿回來。你想我把它拿回來嗎？"), DECISION,
    ), when=flag(CLAUSE_READ), mode="animated")


def _appendix(source, dispatch):
    ready = all_of(flag(CONFIRMED), flag(EXPLAINED), negate(flag(CLAUSE_READ)))
    dispatch[APPENDIX] = ["ch5_t_redemption_revisit", READ, "ch5_t_redemption_ask_first", "ch5_t_redemption_chair_first"]
    source.add(READ, "5.08", CLAUSE, when=ready, mode="animated", cancel_on_skip=True,
               completion=(set_flag(CLAUSE_READ), set_flag(CONSENT_STATUS, AWAITING)))
    source.add("ch5_t_redemption_revisit", "5.08", CLAUSE, when=flag(CLAUSE_READ), mode="animated")
    source.add("ch5_t_redemption_ask_first", "5.08", (
        ("rin", "先到樓梯旁問老 K，再來讀這張附頁。"),
    ), when=all_of(flag(CONFIRMED), negate(flag(EXPLAINED))), mode="animated")
    source.add("ch5_t_redemption_chair_first", "5.08", (
        ("rin", "先核對錨椅的登記，再查這份附頁。"),
    ), when=negate(flag(CONFIRMED)), mode="animated")


def install(source, dispatch, chapter):
    source.bindings[OLD_K] = Binding("npc", chapter, f"res://data/npcs/ch5_{OLD_K}.tres")
    source.bindings[APPENDIX] = Binding("object", chapter, f"res://data/npcs/ch5_{APPENDIX}.tres")
    _old_k(source, dispatch)
    _appendix(source, dispatch)
    source.quests.append(Quest(
        "ch5_anchor_agreement", "main", "問清交易，讀完贖回附頁",
        "錨椅的登記已核對。老 K 回到樓梯旁，桌上有一份贖回附頁。",
        "記下備份交換與贖回條件，等待本人同意。", CLAUSE_READ,
        (QuestStep("到地下室樓梯旁向老 K 問備份交易。", EXPLAINED, OLD_K),
         QuestStep("在檯燈下的桌上讀記憶贖回附頁。", CLAUSE_READ, APPENDIX)),
        visible_flags=(CONFIRMED,), completion_requires_steps=True,
    ))
