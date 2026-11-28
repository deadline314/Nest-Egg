"""Build the bundled title faces (Nest Egg Title TC / JP) from Noto Serif TC / JP with fontTools.

The title faces cover the same authored text as the body fonts (every .gd/.json/.tres/.tscn
string under the game folders), so any screen title, place or chapter name can use them.
Characters the source lacks (mostly arrows and key symbols) fall back to the body font,
and the presentation test fails when an authored place or chapter name is not covered.

Traditional Chinese text uses the TC face; Japanese text uses the JP face, because the
TC face lacks Japanese character forms (for example 横, 麺, 縁).

Usage (from the project root):
    python tools/ui/build_title_font.py <NotoSerifTC[wght].ttf> <NotoSerifJP[wght].ttf>

Sources: https://github.com/google/fonts/tree/main/ofl/notoseriftc and .../ofl/notoserifjp (SIL OFL 1.1).
"""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

import build_body_fonts as body_fonts

ROOT = Path(__file__).resolve().parents[2]
FONT_DIR = ROOT / "art/fonts"
FACES = {"zh": ("NestEggTitleTC-Bold.ttf", "Nest Egg Title TC"), "ja": ("NestEggTitleJP-Bold.ttf", "Nest Egg Title JP")}
WEIGHT = 700
# Fixed words the title face always needs (chapter numbering, separators, digits).
BASE_TEXT = "第章完序終一二三四五六七八九十百零〇・（）()　：:-—0123456789"


def corpus() -> set[int]:
    """The same authored-text coverage as the body fonts, so any title can use the title face."""
    codepoints = body_fonts.corpus()
    codepoints.update(map(ord, BASE_TEXT))
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
    codepoints = corpus()
    for language, source in (("zh", config.tc_source), ("ja", config.jp_source)):
        file_name, family = FACES[language]
        destination = config.out / file_name
        build(source, destination, family, codepoints)
        print(f"{file_name}: {len(codepoints)} codepoints, {destination.stat().st_size} bytes")


if __name__ == "__main__":
    main()
