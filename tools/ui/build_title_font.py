"""Build the bundled title faces (Nest Egg Title TC / JP) from Noto Serif TC / JP with fontTools.

The title face is only used for place names and chapter titles, so it is subset to
the characters those strings use (area names, chapter titles, a few fixed words).
Any character outside the subset falls back to the body font at runtime, and the
UI kit test fails when an authored title is not covered, naming the missing text.

Traditional Chinese text uses the TC face; Japanese text uses the JP face, because the
TC face lacks Japanese character forms (for example 横, 麺, 縁).

Usage (from the project root):
    python tools/ui/build_title_font.py <NotoSerifTC[wght].ttf> <NotoSerifJP[wght].ttf>

Sources: https://github.com/google/fonts/tree/main/ofl/notoseriftc and .../ofl/notoserifjp (SIL OFL 1.1).
"""

import argparse
import json
import re
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT = Path(__file__).resolve().parents[2]
FONT_DIR = ROOT / "art/fonts"
FACES = {"zh": ("NestEggTitleTC-Bold.ttf", "Nest Egg Title TC"), "ja": ("NestEggTitleJP-Bold.ttf", "Nest Egg Title JP")}
WEIGHT = 700
# Fixed words the title face always needs (chapter numbering, separators, digits).
BASE_TEXT = "第章完序終一二三四五六七八九十百零〇・（）()　：:-—0123456789"
TITLE_KEYS = ("title", "subtitle", "end_title")
LEVEL_NAME = re.compile(r'^display_name = "(.*)"$', re.M)
LEVEL_LOCALIZED = re.compile(r'^localized_names = Dictionary\[String, String\]\((\{.*\})\)$', re.M)


def title_strings(language: str) -> list[str]:
    """Every authored string the title face draws in one language: area names and chapter titles."""
    found: list[str] = []
    for path in sorted((ROOT / "data/levels").glob("*.tres")):
        text = path.read_text(encoding="utf-8")
        if language == "zh":
            found += LEVEL_NAME.findall(text)
        else:
            for raw in LEVEL_LOCALIZED.findall(text):
                names = json.loads(raw)
                if language in names:
                    found.append(names[language])
    suffix = "" if language == "zh" else "_" + language
    for path in sorted((ROOT / "data/story").glob("*.json")):
        chapter = json.loads(path.read_text(encoding="utf-8")).get("chapter")
        if not isinstance(chapter, dict):
            continue
        for key in TITLE_KEYS:
            value = chapter.get(key + suffix)
            if isinstance(value, str):
                found.append(value)
    return found


def corpus(language: str) -> set[int]:
    codepoints = set(range(0x20, 0x7F))
    codepoints.update(map(ord, BASE_TEXT))
    for text in title_strings(language):
        codepoints.update(map(ord, text))
    return codepoints


def build(source: Path, destination: Path, family: str, codepoints: set[int]) -> None:
    with TTFont(source, recalcTimestamp=False) as font:
        static = instancer.instantiateVariableFont(font, {"wght": WEIGHT})
        options = subset.Options()
        options.name_IDs = ["*"]
        options.name_legacy = True
        options.name_languages = ["*"]
        options.layout_features = ["*"]
        exporter = subset.Subsetter(options=options)
        exporter.populate(unicodes=codepoints)
        exporter.subset(static)
        postscript = family.replace(" ", "") + "-Bold"
        # Modified fonts carry their own family name.
        names = {1: family, 2: "Bold", 3: postscript, 4: family + " Bold", 6: postscript,
                 16: family, 17: "Bold", 25: family.replace(" ", "")}
        for name in static["name"].names:
            if name.nameID in names:
                name.string = names[name.nameID].encode(name.getEncoding())
        static.save(destination)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("tc_source", type=Path, help="NotoSerifTC[wght].ttf from google/fonts")
    parser.add_argument("jp_source", type=Path, help="NotoSerifJP[wght].ttf from google/fonts")
    parser.add_argument("--out", type=Path, default=FONT_DIR)
    config = parser.parse_args()
    for language, source in (("zh", config.tc_source), ("ja", config.jp_source)):
        file_name, family = FACES[language]
        destination = config.out / file_name
        codepoints = corpus(language)
        build(source, destination, family, codepoints)
        print(f"{file_name}: {len(codepoints)} codepoints, {destination.stat().st_size} bytes")


if __name__ == "__main__":
    main()
