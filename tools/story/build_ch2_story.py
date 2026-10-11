#!/usr/bin/env python3
"""第二章「鷺」劇本的產生器（ST-19）：作者來源 ch2_source.py → data/story/ch2_heron.json、劇情文件與交易資源。

用法：python3 tools/story/build_ch2_story.py
劇本檔、文件與交易資源都由這裡產生，不手改輸出檔；台詞的日文與英文在 tools/story/i18n/ch2_heron.json。
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/story"))

import ch2_source  # noqa: E402
from ch1_closure import render_document_resource  # noqa: E402
from ch1_runtime_backend import DEATH_SEQUENCES  # noqa: E402
from chapter_compiler import ChapterSpec, CompileError, write_chapter  # noqa: E402

OUT = ROOT / "data/story/ch2_heron.json"
ITEM_DIR = ROOT / "data/story_items"
TRANSACTION_DIR = ROOT / "data/story_transactions"


def _write_documents(source):
    for order, (ident, document) in enumerate(source.documents.items()):
        text = render_document_resource(ident, document, 200 + order).replace('chapter = &"ch1_kasa"', 'chapter = &"ch2_heron"')
        (ITEM_DIR / f"{ident}.tres").write_text(text, encoding="utf-8")


def _write_transactions():
    for canonical, (filename, amount) in ch2_source.TRANSACTIONS.items():
        if canonical.startswith("ch1."):
            continue  # 第一章的委託結算資源由第一章維護，這裡只引用
        text = "\n".join([
            '[gd_resource type="Resource" script_class="StoryTransactionData" load_steps=2 format=3]', "",
            '[ext_resource type="Script" path="res://data/scripts/story_transaction_data.gd" id="1_script"]', "",
            "[resource]", 'script = ExtResource("1_script")', f'id = &"{canonical}"', "definition_version = 1",
            f"credits_delta = {amount}", ""])
        (TRANSACTION_DIR / f"{filename}.tres").write_text(text, encoding="utf-8")


def spec() -> ChapterSpec:
    source = ch2_source.build_source()
    return ChapterSpec(
        chapter=dict(ch2_source.CHAPTER), source=source, prefix="ch2", dispatch=ch2_source.DISPATCH,
        quest_locations=ch2_source.QUEST_LOCATIONS,
        important_radio={"ch2_b_booth_b3", "ch2_s12_defeat_hint"},
        flag_defaults=source.flag_defaults,
        death_sequences=DEATH_SEQUENCES,  # 一般死亡的畫面序列和第一章相同（錄音、燈、狀態列、記憶卡，之後縮短）
    )


def main():
    try:
        chapter = spec()
        _write_documents(chapter.source)
        _write_transactions()
        write_chapter(chapter, OUT)
    except CompileError as error:
        print(str(error), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
