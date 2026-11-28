#!/usr/bin/env python3
"""Scan player-facing story text for readability and voice problems (STORY_COVERAGE.md).

StoryLint (tools/story_lint.tscn) is the gate; this is the reading list it leaves:
  fragment  - a sentence of <= 3 chars standing alone, or a line built from three or more
              comma clauses averaging <= 5 chars (telegraph style)
  long      - one line too long to read in one glance (bubble/radio > 30, other > 40 chars)
  voice     - a speaker saying something CHARACTERS.md says they never say, or a
              speaker's signature habit going missing in a chapter
Usage: python tools/story/dialogue_scan.py [--json out.json] [--max 400]
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SENTENCE_END = re.compile(r"[。！？!?…]+|——")
CLAUSE_SPLIT = re.compile(r"[，、；：,;:。！？!?…—「」『』（）()]+")
# Speakers whose lines are labels, readouts or formal notices (StoryLint "formal").
LONG_LIMIT = {"bubbles": 30}  # radio shows two rows in the comm panel; dialogue boxes wrap
LONG_DEFAULT = 40
# Words a speaker never says (CHARACTERS.md 說話方式「不會說」).
NEVER_SAYS = {
    "rin": ["謝謝", "我愛你", "我需要", "幫我", "對不起"],
    "old_k": ["我愛你", "對不起"],
    "lamp": ["對不起"],
    "egret": ["對不起", "謝謝你"],
}
# Signature endings that should keep showing up (ratio per chapter is reported).
HABIT = {"old_k": ("喔", "啦")}


def chars(text: str) -> int:
    return len(re.sub(r"\s|\{[^}]*\}", "", text))


def sentences(text: str) -> list[str]:
    return [s.strip() for s in SENTENCE_END.split(text) if s.strip()]


def clauses(text: str) -> list[str]:
    return [c for c in CLAUSE_SPLIT.split(text) if c]


def fragment_reason(text: str) -> str:
    text = re.sub(r"「[^」]*」", "那句話", text)  # quoted words are not the speaker's own clauses
    short = [s for s in sentences(text) if chars(s) <= 3 ]
    if short and len(sentences(text)) > 1:
        return "單獨成句的短片段：" + "、".join(short)
    parts = clauses(text)
    if len(parts) >= 3 and sum(chars(p) for p in parts) / len(parts) <= 4:
        return "逗號切成短子句（平均 %.1f 字）" % (sum(chars(p) for p in parts) / len(parts))
    return ""


def story_lines():
    """Yield (chapter, location, mode, speaker, text) from every story JSON."""
    for path in sorted(glob.glob(os.path.join(ROOT, "data", "story", "ch*_*.json"))):
        if os.path.basename(path).startswith("chapter_"):
            continue  # legacy demo story, not in the campaign
        chapter = os.path.basename(path)[:3]
        data = json.load(open(path, encoding="utf-8"))
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        for sid, scene in data.get("scenes", {}).items():
            mode = scene.get("mode", "")
            for i, line in enumerate(scene.get("lines") or []):
                if isinstance(line, dict) and line.get("text"):
                    yield chapter, f"{rel} scenes.{sid}.lines[{i}]", mode, line.get("speaker", ""), line["text"]
            for i, step in enumerate(scene.get("steps") or []):
                if step.get("do") == "say" and step.get("text"):
                    yield chapter, f"{rel} scenes.{sid}.steps[{i}]", mode, step.get("speaker", ""), step["text"]
                elif step.get("do") == "choice":
                    for j, opt in enumerate(step.get("options") or []):
                        for key in ("text", "explanation"):
                            if opt.get(key):
                                yield chapter, f"{rel} scenes.{sid}.steps[{i}].options[{j}].{key}", "choice", "", opt[key]
            for vk, variant in (scene.get("variants") or {}).items() if isinstance(scene.get("variants"), dict) else []:
                for i, line in enumerate(variant.get("lines") or [] if isinstance(variant, dict) else variant):
                    if isinstance(line, dict) and line.get("text"):
                        yield chapter, f"{rel} scenes.{sid}.variants.{vk}[{i}]", mode, line.get("speaker", ""), line["text"]


TRES_STRING = re.compile(r'^(hints|locked_text|body|description) = (?:PackedStringArray\()?(.*?)\)?$', re.M)


def resource_lines():
    for pattern in ("data/levels/ch*.tres", "data/story_items/*.tres"):
        for path in sorted(glob.glob(os.path.join(ROOT, pattern))):
            rel = os.path.relpath(path, ROOT).replace("\\", "/")
            text = open(path, encoding="utf-8").read()
            owner = re.search(r'^chapter = &"(ch\d)', text, re.M)
            chapter = owner.group(1) if owner else os.path.basename(path)[:3]
            for m in TRES_STRING.finditer(text):
                for k, s in enumerate(re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(2))):
                    if re.search(r"[一-鿿]", s):
                        yield chapter, f"{rel} {m.group(1)}[{k}]", m.group(1), "", s


def scan(max_rows: int):
    findings = []
    habit = defaultdict(lambda: [0, 0])
    total = 0
    for chapter, loc, mode, speaker, text in list(story_lines()) + list(resource_lines()):
        total += 1
        reason = fragment_reason(text)
        if reason:
            findings.append(("fragment", chapter, loc, speaker, text, reason))
        limit = LONG_LIMIT.get(mode, LONG_DEFAULT)
        if mode in ("body", "description"):
            limit = 10_000
        n = max((chars(s) for s in re.split(r"\n", text)), default=0)
        if n > limit:
            findings.append(("long", chapter, loc, speaker, text, f"{n} 字（上限 {limit}）"))
        for word in NEVER_SAYS.get(speaker, []):
            if word in text and "不" + word not in text and "別" + word not in text:
                findings.append(("voice", chapter, loc, speaker, text, f"{speaker} 不會說「{word}」"))
        if speaker in HABIT:
            habit[(speaker, chapter)][1] += 1
            if text.rstrip("。！？…").endswith(HABIT[speaker]) or any(h + "，" in text or h + "。" in text for h in HABIT[speaker]):
                habit[(speaker, chapter)][0] += 1
    return total, findings[: max_rows if max_rows > 0 else None], findings, habit


def _scenes():
    out = {}
    for path in glob.glob(os.path.join(ROOT, "data", "story", "ch*_*.json")):
        out.update(json.load(open(path, encoding="utf-8")).get("scenes", {}))
    return out


def _own_lines(scene) -> int:
    return len(scene.get("lines") or []) + sum(1 for s in scene.get("steps") or [] if s.get("do") == "say")


def _reachable(scenes, start):
    """Scene ids reachable from start through routes, then, results and choice targets."""
    seen, todo = set(), [start]
    while todo:
        sid = todo.pop()
        if sid in seen or sid not in scenes:
            continue
        seen.add(sid)
        stack = [scenes[sid]]
        while stack:
            node = stack.pop()
            if isinstance(node, dict):
                stack.extend(node.values())
            elif isinstance(node, list):
                stack.extend(node)
            elif isinstance(node, str) and node in scenes and node not in seen:
                todo.append(node)
    return seen


def _scene_lines(scenes, start) -> int:
    return sum(_own_lines(scenes[s]) for s in _reachable(scenes, start))


def _variants(scenes, start) -> int:
    return len(scenes.get(start, {}).get("routes") or []) or 1


def areas():
    """Per level: who stands there, what they say, and what the place itself tells you."""
    scenes = _scenes()
    rows = []
    for path in sorted(glob.glob(os.path.join(ROOT, "data", "levels", "ch*.tres"))):
        text = open(path, encoding="utf-8").read()
        name = re.search(r'^display_name = "(.*)"', text, re.M)
        ext = dict(re.findall(r'\[ext_resource [^\]]*path="([^"]+)" id="([^"]+)"', text))
        refs = set(re.findall(r'res://data/(npcs|story_items)/([\w]+)\.tres', text))
        npcs, docs = [], []
        for kind, rid in sorted(refs):
            if kind == "story_items":
                docs.append(rid)
                continue
            npc = open(os.path.join(ROOT, "data", "npcs", rid + ".tres"), encoding="utf-8").read()
            talks = re.findall(r'^scene = &"(\w+)"', npc, re.M)
            gated = len(re.findall(r'^(min_talks|requires_flag|after_scene|min_deaths|requires_item|unless_flag) = ', npc, re.M))
            reactions = len(re.findall(r'npc_reaction', npc)) and npc.count('gesture = ')
            person = "kind = 1" not in npc and "kind = 2" not in npc
            npcs.append({"id": rid, "person": person, "talks": sum(_variants(scenes, t) for t in talks), "lines": sum(_scene_lines(scenes, t) for t in talks),
                         "conditions": gated, "reactions": reactions})
        triggers = re.search(r'^story_triggers = PackedStringArray\((.*)\)$', text, re.M)
        trig = re.findall(r'"(\w+)"', triggers.group(1)) if triggers else []
        hints = re.search(r'^hints = PackedStringArray\((.*)\)$', text, re.M)
        rows.append({
            "level": os.path.basename(path)[:-5], "name": name.group(1) if name else "",
            "npcs": npcs, "docs": docs,
            "triggers": [(t, scenes.get(t, {}).get("mode", "?"), _scene_lines(scenes, t)) for t in trig],
            "hints": len(re.findall(r'"(?:[^"\\]|\\.)*"', hints.group(1))) if hints else 0,
        })
    return rows


def print_areas() -> None:
    print("| 區域 | 名稱 | 場景人物與可讀物件［物］（段落／台詞／條件／反應） | 物件與文件 | 觸發的短對話（模式／句數） | 提示牌 |")
    print("|---|---|---|---|---|---|")
    for r in areas():
        people = "；".join(f"{'' if n['person'] else '［物］'}{n['id']}（{n['talks']}／{n['lines']}／{n['conditions']}／{n['reactions']}）" for n in r["npcs"]) or "—"
        trig = "；".join(f"{t}（{m}／{n}）" for t, m, n in r["triggers"]) or "—"
        print(f"| {r['level']} | {r['name']} | {people} | {'、'.join(r['docs']) or '—'} | {trig} | {r['hints']} |")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json")
    ap.add_argument("--max", type=int, default=0)
    ap.add_argument("--areas", action="store_true", help="print the per-area coverage table instead")
    args = ap.parse_args()
    if args.areas:
        print_areas()
        return 0
    total, shown, findings, habit = scan(args.max)
    counts = defaultdict(int)
    for f in findings:
        counts[(f[0], f[1])] += 1
    print(f"掃描 {total} 條文字；發現 {len(findings)} 項")
    for key in sorted(counts):
        print(f"  {key[0]:8s} {key[1]}: {counts[key]}")
    for (speaker, chapter), (hit, n) in sorted(habit.items()):
        print(f"  habit {speaker} {chapter}: {hit}/{n} 句帶 {'／'.join(HABIT[speaker])}")
    for kind, chapter, loc, speaker, text, reason in shown:
        print(f"[{kind}] {loc} ({speaker or '-'}) {reason}\n    {text}")
    if args.json:
        with open(args.json, "w", encoding="utf-8") as out:
            json.dump([dict(zip(("kind", "chapter", "location", "speaker", "text", "reason"), f)) for f in findings],
                      out, ensure_ascii=False, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
