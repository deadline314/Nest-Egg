#!/usr/bin/env python3
"""第三章「晴岸」劇本的產生器（ST-21）：作者來源 ch3_source.py → data/story/ch3_clearwater.json、劇情文件與交易資源。

用法：python3 tools/story/build_ch3_story.py
劇本檔、文件、交易資源與本章的過場舞台都由這裡產生，不手改輸出檔；台詞的日文與英文在 tools/story/i18n/ch3_clearwater.json。
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/story"))

import ch3_source  # noqa: E402
from ch1_runtime_backend import DEATH_SEQUENCES  # noqa: E402
from chapter_compiler import ChapterSpec, CompileError, write_chapter, write_documents, write_transactions  # noqa: E402

OUT = ROOT / "data/story/ch3_clearwater.json"
STAGE_DIR = ROOT / "data/cutscene/stages"
ITEM_DIR = ROOT / "data/story_items"
TRANSACTION_DIR = ROOT / "data/story_transactions"


def spec() -> ChapterSpec:
    source = ch3_source.build_source()
    return ChapterSpec(
        chapter=dict(ch3_source.CHAPTER), source=source, prefix="ch3", dispatch=ch3_source.DISPATCH,
        quest_locations=ch3_source.QUEST_LOCATIONS,
        important_radio={"ch3_c11_defeat_hint"},
        flag_defaults=source.flag_defaults,
        death_sequences=DEATH_SEQUENCES,  # 一般死亡的畫面序列和前兩章相同
    )


def write_stages():
    """本章自己的過場舞台（辦公接待廊）。格式同第一章的 write_stage：縮排 1、結尾換行。"""
    path = STAGE_DIR / f"{ch3_source.OFFICE_STAGE}.json"
    path.write_text(json.dumps(ch3_source.office_stage(), ensure_ascii=False, indent=1) + "\n", encoding="utf-8")


def main():
    try:
        write_stages()
        chapter = spec()
        write_documents(chapter.source, "ch3_clearwater", ITEM_DIR, 300)
        write_transactions(ch3_source.TRANSACTIONS, TRANSACTION_DIR, "ch3.")
        write_chapter(chapter, OUT)
    except CompileError as error:
        print(str(error), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
