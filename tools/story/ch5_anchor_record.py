"""Scene 5.06's independent sources, owned comparison and optional notebook."""

from ch1_closure import Binding, Option, Quest, QuestStep, all_of, any_of, flag, grant, item, negate, set_flag
from ch5_anchor_layout import POINTS
from ch5_stair_layout import COAT_KNOWN

OFFICE_COPY = "ch4_original_ledger_copy"
OFFICE_READ = "ch4_original_ledger_read"
COUNTERFOIL_CHECKED = "ch5_anchor_counterfoil_verified"
ANCHOR_CONFIRMED = "ch5_anchor_identity_confirmed"
ANCHOR_RECORD = "ch5_anchor_record"
COMPARE = "ch5_t_anchor_record"


def _counterfoil(source, dispatch):
    found = flag(COUNTERFOIL_CHECKED)
    known_coat = flag(COAT_KNOWN)
    dispatch["anchor_counterfoil"] = ["ch5_t_anchor_counterfoil_seen", "ch5_t_anchor_counterfoil_verification"]
    lines = (
        ("label", "這是當舖留下的搬運回單。第十七批次，送到復原終端。"),
        ("rin", "收件章和必安衣領旁的相同。回單寫的是我的名字，簽收欄還遮著。"),
    )
    source.add("ch5_t_anchor_counterfoil_verification", "5.06", lines,
               when=all_of(known_coat, negate(found)), mode="animated",
               completion=(set_flag(COUNTERFOIL_CHECKED),), cancel_on_skip=True)
    source.add("ch5_t_anchor_counterfoil_seen", "5.06", lines,
               when=all_of(known_coat, found), mode="animated")


def _chair(source, dispatch):
    known_coat = flag(COAT_KNOWN)
    confirmed = flag(ANCHOR_CONFIRMED)
    carried = item(OFFICE_COPY)
    read = flag(OFFICE_READ)
    local = flag(COUNTERFOIL_CHECKED)
    verified = any_of(carried, read, local)
    pending = all_of(known_coat, negate(confirmed))
    ready = all_of(known_coat, negate(confirmed), verified)

    # The holder sees her actual document. Preview-only and local counterfoil
    # readers get their own provenance; neither path issues an old chapter item.
    variants = (
        ("copy", carried, "舊廠原帳的第十七批寫的是我的名字，錨人一欄被遮住了。"),
        ("memory", all_of(negate(carried), read), "在舊廠我看過第十七批的原頁。受錨者是我，錨人的名字被遮住了。"),
        ("local", all_of(negate(carried), negate(read), local), "當舖的搬運回單也寫著第十七批和我的名字。我把回單的批號對到椅子上。"),
    )
    entries = ["ch5_t_anchor_revisit"]
    for key, condition, line in variants:
        name = f"ch5_t_anchor_compare_{key}"
        entries.append(name)
        source.add(name, "5.06", (
            ("rin", line),
            ("label", "座椅讀取板記著同一個批次。要核對座椅登記嗎？"),
        ), when=all_of(pending, condition), options=(
            Option("confirm", "核對第十七批的座椅登記", COMPARE, "核對後記進帳冊。"),
            Option("leave", "先離開", None, "座椅紀錄會留在原處。"),
        ), cancel_choice_on_back=True)
    entries.append("ch5_t_anchor_needs_record")
    dispatch["anchor_chair"] = entries
    source.add("ch5_t_anchor_needs_record", "5.06", (
        ("rin", "我手上沒有原帳，還沒核對過那一批。左邊矮桌上有張搬運回單，可以先看批號。"),
    ), when=all_of(pending, negate(verified)), mode="animated")
    source.add(COMPARE, "5.06", (
        ("label", "第十七批次。登記錨人是老 K，受錨者是凜。"),
        ("rin", "搬運的人把我送到終端。每次坐上這張椅子的人，是老 K。"),
        ("rin", "這些紀錄都留在原處。我把椅子的登記另抄一頁。"),
    ), when=ready, mode="animated", completion=(grant(ANCHOR_RECORD), set_flag(ANCHOR_CONFIRMED)),
        cancel_on_skip=True)
    source.add("ch5_t_anchor_revisit", "5.06", (
        ("label", "第十七批次的座椅登記已抄進凜的帳冊。椅子和頭盔都留在原位。"),
    ), when=confirmed, mode="animated")


def _notebook(source, dispatch):
    known_coat = flag(COAT_KNOWN)
    dispatch["life_notebook"] = ["ch5_t_anchor_life_notebook"]
    pages = (
        ("carrots", "翻看買菜那一頁", "讀桌上筆記的第一頁。", ("label", "她不吃紅蘿蔔。下次買菜記得避開。")),
        ("shoes", "翻看第一天那一頁", "讀桌上筆記的第二頁。", ("label", "她第一天來，把鞋脫在門外，擺得像要被檢查。")),
        ("blank", "翻到最後一頁", "讀桌上筆記的末頁。", ("rin", "最後一頁留白，前一頁的字跡到這裡就停了。")),
    )
    options = []
    for ident, title, explanation, line in pages:
        target = f"ch5_t_anchor_life_{ident}"
        options.append(Option(ident, title, target, explanation))
        source.add(target, "5.06", (line,), when=known_coat, mode="animated")
    source.add("ch5_t_anchor_life_notebook", "5.06", (
        ("rin", "桌上有老 K 的生活筆記。想先翻哪一頁？"),
    ), when=known_coat, options=(*options, Option("leave", "先闔上筆記", None, "還可以回來翻讀。")),
        cancel_choice_on_back=True)


def install(source, dispatch, chapter):
    for name in POINTS:
        source.bindings[name] = Binding("object", chapter, f"res://data/npcs/ch5_{name}.tres")
    source.documents[ANCHOR_RECORD] = {
        "name": "錨椅登記",
        "description": "座椅登記老 K 為錨人，凜為受錨者。",
        "body": "座椅讀取板記著第十七批次，老 K 為登記錨人，凜為受錨者。這一頁抄自座椅讀取板。舊廠原帳的遮蔽欄位照樣保留。",
        "icon": "doc_stub",
        "source_actor": "ch5_anchor_chair",
    }
    _counterfoil(source, dispatch)
    _chair(source, dispatch)
    _notebook(source, dispatch)
    source.quests.append(Quest(
        "ch5_anchor_chair_record", "main", "到地下室核對錨椅登記",
        "必安的衣領留著收件章。地下室有搬運回單和同批次的座椅記錄。",
        "把第十七批次的座椅登記抄進帳冊。", ANCHOR_CONFIRMED,
        (QuestStep("到地下室的錨椅旁核對第十七批次。", ANCHOR_CONFIRMED, "anchor_chair"),),
        visible_flags=(COAT_KNOWN,), completion_requires_steps=True,
    ))
