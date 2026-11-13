"""Copy reviewed native PNG bytes to the ticket image folder without resizing."""
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "pm/Nest-Egg/attachments/NE-267-guest-rigs/scene-material-lf-v8"
TARGET = ROOT / "pm/Nest-Egg/images/NE-267-zheng-material"


def main():
    TARGET.mkdir(exist_ok=False)
    (TARGET / ".gdignore").touch()
    records = []
    for name, state in (("held", "slip-held"), ("rest", "slip-rest"), ("standing", "idle")):
        source = SOURCE / ("ch2_t_s18_ticket-" + state + ".png")
        target = TARGET / (name + ".png")
        shutil.copyfile(source, target)
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        assert hashlib.sha256(target.read_bytes()).hexdigest() == digest
        records.append(dict(source=source.relative_to(ROOT).as_posix(), output=target.name, sha256=digest,
                            classification="exact native PNG bytes, selected snapshot, not the complete timeline"))
    (TARGET / "sources.json").write_text(json.dumps(records, indent=2) + "\n", encoding="utf8", newline="\n")
    print("3 exact native PNG copies")


if __name__ == "__main__":
    main()
