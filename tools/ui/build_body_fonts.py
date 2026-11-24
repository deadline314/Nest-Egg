"""Build the bundled body fonts from IBM Plex Sans source TTFs with fontTools."""

import argparse
from pathlib import Path
import subprocess

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[2]
FONT_DIR = ROOT / "art/fonts"
BODIES = {"TC": "Nest Egg Sans TC", "JP": "Nest Egg Sans JP"}


def corpus() -> set[int]:
    # Cover authored text plus legacy coverage and keyboard punctuation.
    with TTFont(FONT_DIR / "NotoSansTC-Regular-subset.ttf") as legacy:
        codepoints = set(legacy.getBestCmap())
    codepoints.update(range(0x20, 0x100))
    paths = subprocess.check_output(
        ["git", "ls-files", "-z", "autoload", "core", "data", "game", "scenes", "ui"],
        cwd=ROOT,
    ).decode("utf-8").split("\0")
    for path in map(Path, paths):
        if path.suffix in {".gd", ".json", ".tres", ".tscn"}:
            codepoints.update(map(ord, (ROOT / path).read_text(encoding="utf-8")))
    return codepoints


def build(source: Path, destination: Path, family: str, codepoints: set[int]) -> None:
    options = subset.Options()
    options.name_IDs = ["*"]
    options.name_legacy = True
    options.name_languages = ["*"]
    with TTFont(source, recalcTimestamp=False) as font:
        exporter = subset.Subsetter(options=options)
        exporter.populate(unicodes=codepoints)
        exporter.subset(font)
        postscript = family.replace(" ", "") + "-Regular"
        # Modified fonts use a new family name, as required by the reserved name.
        names = {
            1: family, 2: "Regular", 3: postscript, 4: family + " Regular",
            6: postscript, 16: family, 17: "Regular", 18: family + " Regular",
            20: postscript, 21: family, 22: "Regular", 25: family.replace(" ", ""),
        }
        for name in font["name"].names:
            if name.nameID in names:
                name.string = names[name.nameID].encode(name.getEncoding())
        font.save(destination)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_dir", type=Path, help="Directory holding the two original IBM TTFs")
    parser.add_argument("--out", type=Path, default=FONT_DIR)
    config = parser.parse_args()
    config.out.mkdir(parents=True, exist_ok=True)
    codepoints = corpus()
    for suffix, family in BODIES.items():
        build(config.source_dir / f"IBMPlexSans{suffix}-Regular.ttf",
              config.out / f"NestEggSans{suffix}-Regular.ttf", family, codepoints)


if __name__ == "__main__":
    main()
