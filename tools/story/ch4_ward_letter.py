"""Optional ward visit and Linden’s consent to read the witness names."""
from ch1_closure import Option, all_of, flag, grant, negate, set_flag

WITNESS_NOTE = "ch4_linden_witness_note"
WITNESS_NOTED = "ch4_linden_witnesses_noted"
WARD_SCARF = "ch4_b_ward_scarf"


def add_ward_letter(source, dispatch, consent: str, collected: str):
    source.speakers["ward_letter"] = {"name": "凜讀信", "name_ja": "手紙を読む凜", "name_en": "Rin reading aloud",
                        "color": "#e2d5b8", "portrait": "res://art/portraits/rin.png"}
    source.documents[WITNESS_NOTE] = {
        "name": "棠同意抄下的名單", "icon": "doc_stub", "source_actor": "ch4_cabinet",
        "description": "凜依棠同意，抄下信裡能去詢問的四處。",
        "body": "市集可以問榕伯，復原館可以找阿梨。當舖可以問老 K，病房可以找當天替棠辦入院的護理員。原信留在棠手邊。",
    }

    available = all_of(flag(consent), flag(collected))
    unrecorded = all_of(flag(consent), flag(collected), negate(flag(WITNESS_NOTED)))
    source.add("ch4_t_ask_linden_letter", "15", (
        ("rin", "信封上寫著妳的名字。妳想自己看，還是要我念給妳聽？"),
        ("linden", "我今天不想聽太多。妳先念她寫了要找哪些人。"),
    ), when=available, options=(
        Option("read_aloud", "只念信裡的四個人。", "ch4_t_read_linden_letter", "照棠同意的範圍讀信。"),
        Option("leave", "先讓棠收著信。", None, "下次可以再問她。"),
    ), cancel_choice_on_back=True)
    source.add("ch4_t_read_linden_letter", "15", (
        ("ward_letter", "如果妳想聽我的事，可以找市集的榕伯、復原館的阿梨。"),
        ("ward_letter", "也可以去當舖找老 K，或問那天替妳辦入院的護理員。"),
        ("ward_letter", "我沒有要他們說一樣的事。"),
    ), when=available, options=(
        Option("note", "把四個地方抄進自己的筆記。", "ch4_t_note_linden_witnesses", "信留在棠的床頭櫃。", when=negate(flag(WITNESS_NOTED))),
        Option("leave", "把信放回棠伸手拿得到的地方。", None, "下次回病房還能再問。"),
    ), cancel_choice_on_back=True)
    source.add("ch4_t_note_linden_witnesses", "15", (
        ("rin", "地方都記好了。信放在妳伸手拿得到的地方。"),
    ), when=unrecorded, mode="animated", cancel_on_skip=True,
               completion=(grant(WITNESS_NOTE), set_flag(WITNESS_NOTED)))

    dispatch["ward_scarf"] = [WARD_SCARF]
    source.add(WARD_SCARF, "15", (
        ("rin", "圍巾的標籤只印了床位。"),
        ("rin", "先讓它留在掛勾上好了。"),
    ), mode="radio")
