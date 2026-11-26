#!/usr/bin/env python3
"""Compile Chapter Five scene 5.01 from the shelf interactions and inventory board."""

from pathlib import Path
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/level"))

from build_ch5 import CHAPTER, POINTS  # noqa: E402
from ch5_pear_testimony import add_pear_testimony  # noqa: E402
from ch5_revival_route import PEAR  # noqa: E402
from build_ch1_story import sfx  # noqa: E402
from ch1_closure import Binding, Option, ProductionSource, Quest, QuestStep, all_of, any_of, flag, negate, say, set_flag  # noqa: E402
from chapter_compiler import ChapterSpec, write_chapter, write_documents
import ch5_fee_story  # noqa: E402  # noqa: E402

CHAPTER_INFO = {
    "id": CHAPTER,
    "title": "第五章　付帳人",
    "subtitle": "空白標籤",
    "end_title": "第五章　付帳人　完",
    "teaser": "下一章　斷錨",
}
INDEX = "ch5_pawnshop_index_read"
MATCHED = "ch5_pawnshop_labels_matched"
LABELS = {
    "watch": ("懷錶的標籤只剩「取回日」的格線。",
              "送貨員押來的懷錶。他說遲到二十分鐘會被罵，三年沒有贖回。"),
    "guitar": ("吉他仍寫著「押來時已經沒有弦」。",
               "押來時已經沒有弦。主人說，彈的人不在了。"),
    "raincoat": ("雨衣上的別針孔還在，原來那行字磨掉了。",
                 "碼頭舊雨衣。主人說，這件曾替另一個人擋過水。"),
    "fare": ("船錢罐底還寫著「留給回不來的人」。",
             "船錢，留給回不來的人渡河用的。"),
}
INDEX_TEXT = (
    ("label", "抽屜格號：01 懷錶、02 吉他、03 雨衣、04 船錢罐。"),
    ("label", "把空白的那兩格勾起來，等客人回來認字。東西先留在架上。"),
)


def _shelf(source, dispatch):
    evidence = []
    for name, (current, previous) in LABELS.items():
        read = f"ch5_pawnshop_{name}_read"
        prior = f"ch1_label_{name}_seen"
        scene = f"ch5_t_{name}"
        dispatch[name] = [f"{scene}_compare", f"{scene}_revisit", scene]
        source.add(f"{scene}_compare", "5.01", (
            ("label", current), ("rin", "我把以前讀過的那張抄在筆記裡。"), ("label", previous),
        ), when=flag(prior), mode="animated")
        source.add(f"{scene}_revisit", "5.01", (("label", current),), when=flag(read), mode="animated")
        source.add(scene, "5.01", (("label", current),),
                   when=all_of(negate(flag(prior)), negate(flag(read))), mode="animated",
                   completion=(set_flag(read),), cancel_on_skip=True)
        evidence.append(any_of(flag(prior), flag(read)))
    return all_of(flag(INDEX), *evidence)


def _inventory(source, dispatch, evidence):
    dispatch["shelf_index"] = ["ch5_t_read_index", "ch5_t_revisit_index"]
    source.add("ch5_t_read_index", "5.01", INDEX_TEXT, when=negate(flag(INDEX)),
               mode="animated", completion=(set_flag(INDEX),), cancel_on_skip=True)
    source.add("ch5_t_revisit_index", "5.01", INDEX_TEXT, when=flag(INDEX), mode="animated")

    dispatch["inventory_board"] = ["ch5_t_labels_matched", "ch5_t_need_index",
                                  "ch5_t_need_labels", "ch5_t_choose_labels"]
    source.add("ch5_t_need_index", "5.01", (("rin", "先看櫃台抽屜裡的格號。"),),
               when=negate(flag(INDEX)), mode="animated")
    source.add("ch5_t_need_labels", "5.01", (("rin", "先翻完架上的標籤，再回來核對。"),),
               when=negate(evidence), mode="animated")
    ready = all_of(evidence, negate(flag(MATCHED)))
    source.add("ch5_t_choose_labels", "5.01", (
        ("rin", "他平常連破袖口都要寫清楚。這兩張明明寫過，現在只剩紙。"),
        ("label", "哪兩張標籤變成了空白？"),
    ), when=ready, options=(
        Option("watch_guitar", "懷錶和吉他", "ch5_t_wrong_labels", "核對第 01、02 格。"),
        Option("watch_raincoat", "懷錶和雨衣", "ch5_t_lift_catch", "核對第 01、03 格。"),
        Option("raincoat_fare", "雨衣和船錢罐", "ch5_t_wrong_labels", "核對第 03、04 格。"),
        Option("leave", "先離開", None, "可以再看格號或標籤。"),
    ), cancel_choice_on_back=True)
    source.add("ch5_t_wrong_labels", "5.01", (("rin", "再把索引上的格號和架上的字對一次。"),),
               mode="animated")
    source.add("ch5_t_lift_catch", "5.01", steps=(
        say("rin", "第一格和第三格。空白的只有這兩張。"),
        say("label", "第一道滑扣鬆開了。"),
        sfx("switch", -14),
    ), when=ready, mode="animated", completion=(set_flag(MATCHED),), cancel_on_skip=True)
    source.add("ch5_t_labels_matched", "5.01", (("label", "01 懷錶和 03 雨衣已勾記，第一道滑扣已開。"),),
               when=flag(MATCHED), mode="animated")


def build_spec():
    source = ProductionSource(flag_defaults={})
    dispatch = {}
    evidence = _shelf(source, dispatch)
    _inventory(source, dispatch, evidence)
    ch5_fee_story.install(source, dispatch)
    source.bindings.update({
        name: Binding("object", CHAPTER, f"res://data/npcs/ch5_{name}.tres") for name in POINTS
    })
    source.quests.append(Quest(
        "ch5_blank_labels", "main", "對照貨架，找出兩張空白標籤",
        "老 K 到樓下查滲水。四件舊物都在原位，櫃台抽屜還有格號。",
        "盤點板的第一道滑扣打開。", MATCHED,
        (QuestStep("查看櫃台抽屜的格號。", INDEX, "shelf_index"),
         QuestStep("比對貨架的標籤，再到盤點板勾出兩張空白標籤。", MATCHED, "inventory_board")),
        completion_requires_steps=True,
    ))
    add_pear_testimony(source, dispatch, CHAPTER)
    return ChapterSpec(CHAPTER_INFO, source, "ch5", dispatch, {**POINTS, "pear": PEAR})


if __name__ == "__main__":
    spec = build_spec()
    write_documents(spec.source, CHAPTER, ROOT / "data/story_items", 500)
    missing = write_chapter(spec, ROOT / f"data/story/{CHAPTER}.json")
    raise SystemExit(int(bool(missing)))
