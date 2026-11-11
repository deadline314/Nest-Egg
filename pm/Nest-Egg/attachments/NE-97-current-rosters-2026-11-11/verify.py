"""Verify the archived bytes and independently recount the recorded placements."""
import hashlib
import json
from pathlib import Path
import re
import zipfile


def verify():
    folder = Path(__file__).resolve().parent
    receipt = json.loads((folder / "receipt.json").read_text(encoding="utf8"))
    raw = (folder / "raw.zip").read_bytes()
    assert hashlib.sha256(raw).hexdigest() == receipt["archive_sha256"]
    checks = 1
    with zipfile.ZipFile(folder / "raw.zip") as archive:
        names = archive.namelist()
        assert len(names) == len(set(names)) == receipt["members"]
        manifest = json.loads(archive.read("manifest.json"))
        assert set(names) == set(manifest) | {"manifest.json"}
        for name, expected in manifest.items():
            data = archive.read(name)
            assert len(data) == expected["bytes"], name
            assert hashlib.sha256(data).hexdigest() == expected["sha256"], name
            checks += 1
        report = json.loads(archive.read("positive/report.json"))
        assert report["checks"] == 506 and not report["issues"]
        expected_totals = {"ch1_kasa": (11, 36, 5), "ch2_heron": (10, 10, 0), "ch3_clearwater": (9, 6, 0)}
        identity_chapters = {}
        for chapter, (areas, placed, reinforcements) in expected_totals.items():
            group = report["chapters"][chapter]
            assert len(group["areas"]) == areas
            assert sum(len(area["placed"]) for area in group["areas"]) == placed
            assert sum(len(area["static_reinforcements"]) for area in group["areas"]) == reinforcements
            declared = set(group["declared"])
            assert declared == set(group["enemies"])
            for area in group["areas"]:
                for spawn in area["placed"] + area["static_reinforcements"]:
                    assert spawn["id"] in declared
            for identity in declared:
                identity_chapters.setdefault(identity, []).append(chapter)
            checks += 5
        assert all(len(chapters) == 1 for chapters in identity_chapters.values())
        assert report["shared_identities"] == []
        ch2 = report["chapters"]["ch2_heron"]["enemies"]
        assert ch2["ch2_escort"]["appearance"]["rig_skin"] == "collector_brute"
        assert ch2["ch2_bill_thrower"]["appearance"]["rig_skin"] == "collector_gunner"
        assert ch2["yong"]["dynamic_summon"] == "ch2_escort"
        janus = report["chapters"]["ch3_clearwater"]["enemies"]["janus"]
        assert len(janus["move_summons"]) == 1
        summon = janus["move_summons"][0]
        assert summon["id"] == "pump_inspector" and summon["parameters"]["max_backup"] == 2
        for name, digest in report["sources"].items():
            assert hashlib.sha256(archive.read("inputs/" + name.removeprefix("res://"))).hexdigest() == digest, name
            checks += 1
        original = json.loads(archive.read("inputs/data/combat/chapter_rosters.json"))
        negative = json.loads(archive.read("missing-identity/roster.json"))
        original["chapters"]["ch2_heron"]["enemies"].remove("ch2_escort")
        assert negative == original
        for name, count, issue_count, code in [("positive", 506, 0, 0), ("missing-identity", 504, 7, 1), ("malformed", 21, 4, 1)]:
            result = json.loads(archive.read(name + "/report.json"))
            process = json.loads(archive.read(name + "/process.json"))
            log = archive.read(name + "/run.log").decode("utf8")
            assert result["checks"] == count and len(result["issues"]) == issue_count
            assert process["exit_code"] == code
            assert not re.search(r"ERROR:|SCRIPT ERROR|ObjectDB|resources still|RID allocations", log)
            checks += 4
        source = archive.read("tool/chapter_roster_report.gd")
        old_order = source.replace(b'["ch3_clearwater", "ch2_heron", "ch1_kasa"]', b'["ch1_kasa", "ch2_heron", "ch3_clearwater"]')
        assert old_order != source and archive.read("order-diagnostic/source.gd") == old_order
        diagnostic = archive.read("order-diagnostic/run.log").decode("utf8")
        assert "checks=506 issues=0" in diagnostic and "478 ObjectDB" in diagnostic
        assert "286 resources still in use" in diagnostic
        assert "SCRIPT ERROR" not in diagnostic
        total = 0
        for index in range(4):
            log = archive.read(f"tests/shard_{index}.log").decode("utf8")
            result = re.findall(r"^checks: (\d+), failures: (\d+)\r?$", log, re.MULTILINE)
            assert len(result) == 1 and int(result[0][1]) == 0
            assert not re.search(r"ERROR:|SCRIPT ERROR|ObjectDB|resources still|RID allocations", log)
            total += int(result[0][0])
            checks += 3
        assert total == receipt["suite_checks"] == 2545
        assert "沒有受影響的測試要跑" in archive.read("tests/isolated-selector.log").decode("utf8")
        checks += 12
    print(f"NE-97 evidence: {checks} checks, 0 failures")


if __name__ == "__main__":
    verify()
