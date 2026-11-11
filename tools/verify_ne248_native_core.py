"""Read-only verification of native NE-248 public-input natural boss runs."""
from __future__ import annotations

import hashlib
import json
import struct
import sys
from pathlib import Path
from zipfile import ZipFile


def main() -> None:
    root = Path(sys.argv[1])
    checks = 0
    runs = []
    sources = []

    def check(passed: bool, message: str) -> None:
        nonlocal checks
        assert passed, message
        checks += 1

    # Git normalizes display-sidecar text. Canonical evidence remains the original ZIP bytes.
    receipt = json.loads((root / "archive-receipt.json").read_text(encoding="utf-8"))
    archive_path = root / "raw.zip"
    check(hashlib.sha256(archive_path.read_bytes()).hexdigest() == receipt["archive_sha256"], "original evidence archive SHA")
    with ZipFile(archive_path) as archive:
        archived = {entry.filename: archive.read(entry.filename) for entry in archive.infolist()}
    manifest_bytes = archived["manifest.json"]
    check(hashlib.sha256(manifest_bytes).hexdigest() == receipt["original_manifest_sha256"], "original archived manifest SHA")
    manifest = json.loads(manifest_bytes)
    check(len(manifest) + 1 == receipt["original_file_count"], "all 53 original evidence files are preserved")
    probe_entry = receipt["probe_archive_entry"]
    check(set(archived) == {row["file"] for row in manifest} | {"manifest.json", probe_entry}, "archive has exactly original evidence plus tested probe")
    for row in manifest:
        payload = archived[row["file"]]
        check(len(payload) == row["bytes"] and hashlib.sha256(payload).hexdigest() == row["sha256"], f"original evidence bytes: {row['file']}")

    for name, side in (("right", 1), ("left", -1)):
        data = json.loads(archived[f"{name}/report.json"])
        log = archived[f"{name}/run.log"].decode("utf-8")
        check("ERROR" not in log and "Leaked" not in log, f"{name}: engine diagnostics")
        check(archived[f"{name}/exit-code.txt"].decode("utf-8").strip() == "0", f"{name}: exit code")
        check(data["renderer"] == "forward_plus" and data["hdr_2d"] and not data["logic_only"], f"{name}: native renderer")
        check(data["gpu"] == "AMD Radeon RX 9070 XT", f"{name}: hardware adapter")
        check(data["parse_mouse"] and data["diagnostic_ticks"] == 0, f"{name}: corrected public mouse route and full original budget")
        check(data["chapter"] == "ch1_kasa" and data["initial_side"] == side, f"{name}: chapter/facing")
        check(data["player_hit_invulnerability"] == 1.0, f"{name}: authored player protection")
        check(len(data["checks"]) >= 16 and all(c["passed"] for c in data["checks"]), f"{name}: original probe assertions")
        completions = [event for event in data["projectile_events"] if event["kind"] == "expired"]
        observed = [event for event in data["projectile_events"] if event["kind"] == "activation_observed"]
        check(len(completions) == len(data["shots"]), f"{name}: one completed real pistol projectile per public firing attempt")
        check(len(observed) <= len(completions), f"{name}: sampled activations do not overcount real projectiles")
        hp = 90
        for hit in data["hits"]:
            check(hit["source"] == "player_pistol", f"{name}: actual pistol source")
            check(hit["before_hp"] == hp and hit["after_hp"] == hp - hit["amount"], f"{name}: complete damage accounting")
            hp = hit["after_hp"]
        threshold = next(h for h in data["hits"] if h["after_hp"] <= 45)
        phase = next(c["event"] for c in data["captures"] if c["name"] == "phase2")
        check(0 <= phase["t"] - threshold["t"] < 0.051, f"{name}: natural phase 2 follows actual half-health hit")
        cases = {stage: [h for h in data["hits"] if h["stage"] == stage] for stage in ("core", "body", "closed")}
        for stage, hits in cases.items():
            check(len(hits) == 1, f"{name}: exactly one {stage} hit")
        core, body, closed = (cases[s][0] for s in ("core", "body", "closed"))
        check(core["state"] == "core_recover" and core["phase"] == 2 and core["core_scale"] == 2 and core["body_scale"] == 1 and core["boss_facing"] == -side, f"{name}: actual isolated core window")
        check((core["part"], core["weak"], core["amount"], core["marker"]) == ("core", True, 2, "weak"), f"{name}: core part/damage/weak/marker")
        check(core["contact_inside_core"], f"{name}: feedback contact is inside the chosen core")
        check(body["state"] == "core_recover" and body["core_scale"] == 2 and body["body_scale"] == 1 and (body["part"], body["weak"], body["amount"], body["marker"]) == ("", False, 1, "hit"), f"{name}: exposed-window body control")
        check(closed["core_scale"] == 1 and closed["body_scale"] == 1 and not closed["weak"] and closed["amount"] == 1 and closed["marker"] == "hit", f"{name}: closed-core control")
        capture = next(c for c in data["captures"] if c["name"] == "core_hit")
        check(capture["event"]["marker"] == core["marker"], f"{name}: captured event retains real marker")
        for filename in ("phase2.png", "core_hit.png", "body_hit.png", "closed_hit.png", "summary.png"):
            check(f"{name}/{filename}" in archived, f"{name}: native {filename}")
            png = archived[f"{name}/{filename}"]
            check(png[:8] == b"\x89PNG\r\n\x1a\n" and struct.unpack(">II", png[16:24]) == (1280, 720), f"{name}: full-resolution {filename}")
        sources.append(data["source_sha256"])
        runs.append({"side": side, "core_facing": core["boss_facing"], "phase2_t": phase["t"], "phase2_hp": threshold["after_hp"], "core_hp": [core["before_hp"], core["after_hp"]], "core_part": core["part"], "core_damage": core["amount"], "core_weak": core["weak"], "core_marker": core["marker"], "body_damage": body["amount"], "closed_damage": closed["amount"], "hp_accounted": 90 - hp, "probe_checks": len(data["checks"])})
    check(sources[0] == sources[1], "both native sides use identical protected sources")
    project = Path(__file__).resolve().parents[1]
    for source, expected in sources[0].items():
        current = (project / source.removeprefix("res://")).read_bytes()
        if source == "res://tools/ne248_natural_core_probe.gd":
            original = archived[probe_entry]
            check(hashlib.sha256(original).hexdigest() == expected, "archived tested probe matches original report SHA exactly")
            check(current == original.replace(b"\r\n", b"\n"), "current probe differs from archived source only by exact CRLF-to-LF conversion")
        else:
            check(hashlib.sha256(current).hexdigest() == expected, f"unchanged product source bytes: {source}")
    print(json.dumps({"checks": checks, "failures": 0, "evidence_source": "raw.zip original bytes", "probe_source_rule": "original archive SHA plus exact CRLF-to-LF comparison only; ten product sources remain byte-exact", "scope": "native GPU arranged arena; public scripted inputs; not human campaign or physical-device testing", "runs": runs}, indent=2))


if __name__ == "__main__":
    main()
