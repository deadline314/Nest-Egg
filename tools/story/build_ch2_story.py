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
from ch1_runtime_backend import DEATH_SEQUENCES  # noqa: E402
from chapter_compiler import ChapterSpec, CompileError, write_chapter, write_documents, write_transactions  # noqa: E402

OUT = ROOT / "data/story/ch2_heron.json"
ITEM_DIR = ROOT / "data/story_items"
TRANSACTION_DIR = ROOT / "data/story_transactions"


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
        write_documents(chapter.source, "ch2_heron", ITEM_DIR, 200)
        write_transactions(ch2_source.TRANSACTIONS, TRANSACTION_DIR, "ch2.")
        write_chapter(chapter, OUT)
    except CompileError as error:
        print(str(error), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
