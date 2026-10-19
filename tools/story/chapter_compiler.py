"""章節劇本的共用轉譯器（ST-19 起）：把作者來源（段落、選擇、結果、任務）轉成遊戲讀的 data/story/<章節>.json。

第一章的轉譯器（ch1_runtime_backend.py）有許多第一章專屬的銜接（舊稿沿用、初次建檔、序章），保持原樣；
第二章之後用這一份，段落的轉譯規則直接沿用第一章（_compile_segment、_choice_step），只把章節專屬的設定改成參數：

- dispatch：人物／物件入口 → 依序檢查的段落（第一個成立的播出；已完成的節點不從入口重播）。
- quests：任務步驟的真實地點（區域 id, 欄, 列），沒有地點的任務不發布。
- important_radio：顯示時凍結世界、等玩家確認的通訊（其餘通訊照常邊玩邊看）。
- transactions：交易引用（金額在 data/story_transactions/*.tres）。
- 譯文：tools/story/i18n/<章節>.json（見 story_i18n.py）。

規則同第一章：段落的 when 成為前置條件；結果只在整段播完時一起生效；有選項的段落成為疊加動畫，略過時套用不做不可逆決定的預設。
"""
from __future__ import annotations

import copy
import json
import os
import sys
from dataclasses import dataclass, field
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/story"))

import dataclasses  # noqa: E402

import story_i18n  # noqa: E402
from ch1_closure import render_document_resource  # noqa: E402
from ch1_runtime_backend import CompileError, _bubble_ok, _results, _say_lines, _walk  # noqa: E402

DIALOGUE_MIN_LINES = 3


@dataclass
class ChapterSpec:
    chapter: dict
    source: object                       # ch1_closure.ProductionSource（段落、任務、交易、文件、講者）
    prefix: str                          # 場景與資料檔的章節前綴，例如 ch2
    dispatch: dict[str, list[str]]
    quest_locations: dict[str, tuple[str, int, int]]
    important_radio: set[str] = field(default_factory=set)
    extra_scenes: dict[str, dict] = field(default_factory=dict)
    flag_defaults: dict = field(default_factory=dict)
    derived_flags: dict = field(default_factory=dict)
    death_sequences: list = field(default_factory=list)
    unpublished_quests: set[str] = field(default_factory=set)


def _choice_step(segment, spec: ChapterSpec) -> dict:
    """選擇步驟：選項可以接到段落或分派入口（依進度挑下一段）。略過演出時套用「不接續」的選項；沒有時用最後一個只寫可逆旗標的。"""
    dispatch_ids = {f"{spec.prefix}_dispatch_{binding}" for binding in spec.dispatch}
    options = []
    for option in segment.options:
        entry = {"id": option.id, "text": option.text, "explanation": option.explanation}
        if option.when:
            entry["when"] = copy.deepcopy(option.when)
        intent = {op["id"]: op["value"] for op in option.intent if op["kind"] == "flag"}
        if len(intent) != len(option.intent):
            raise CompileError(f"{segment.id}.{option.id}: 選項只能帶可逆的意圖旗標")
        if intent:
            entry["set_flags"] = intent
        if option.target:
            if option.target not in spec.source.segments and option.target not in dispatch_ids:
                raise CompileError(f"{segment.id}.{option.id}: 接續段落不存在 {option.target}")
            entry["target"] = option.target
        options.append(entry)
    if not 2 <= len(options) <= 4:
        raise CompileError(f"{segment.id}: 選擇要有兩到四個選項")
    # 略過演出時的預設：先找不接續的選項；沒有就找第一個接到「沒有任何結果」段落的選項（只是多聽一段，不做決定）。
    default = next((o.id for o in segment.options if o.target is None), None)
    if default is None:
        default = next((o.id for o in segment.options if o.target in spec.source.segments
                        and not spec.source.segments[o.target].completion), None)
    if default is None:
        raise CompileError(f"{segment.id}: 要有一個不做決定的選項，略過演出時用它")
    says = [s for s in segment.steps if s.get("do") == "say"]
    prompt = says[-1]["text"] if says else "請選擇接下來的行動。"
    return {"do": "choice", "text": prompt, "default": default, "options": options}


def _compile_segment(segment, spec: ChapterSpec, inside_presentation: bool) -> dict:
    """段落 → 場景（規則同第一章）：有選項的成為疊加動畫；三句以上的對話保留對話；地圖上的一兩句短話改成氣泡。"""
    scene = {}
    results = _results(segment)
    lines = _say_lines(segment.steps)
    # 有舞台（scene 步驟）的段落是正式過場：不疊在地圖上，演員的姿勢要寫理由與支撐（同第一章的 pose_policy）。
    staged = any(s.get("do") == "scene" for s in segment.steps)
    if segment.options:
        scene.update(mode="animated", steps=[copy.deepcopy(s) for s in segment.steps] + [_choice_step(segment, spec)])
        if not staged:
            scene["overlay"] = True
    elif segment.mode == "animated":
        scene.update(mode="animated", steps=[copy.deepcopy(s) for s in segment.steps])
        if not staged:
            scene["overlay"] = True
    elif segment.mode in ("radio", "bubbles"):
        scene.update(mode=segment.mode, lines=lines)
    elif len(lines) >= DIALOGUE_MIN_LINES:
        scene.update(mode="dialogue", lines=lines)
    elif not inside_presentation and not any(op["kind"] != "flag" for op in results) and _bubble_ok(lines):
        scene.update(mode="bubbles", lines=lines)
    else:
        scene.update(mode="animated", overlay=True, steps=[copy.deepcopy(s) for s in segment.steps])
    if staged and scene.get("mode") == "animated":
        scene["pose_policy"] = "supported"
    if segment.when:
        scene["when"] = copy.deepcopy(segment.when)
    if results:
        scene["results"] = results
    for op in segment.completion:
        failure = spec.source.transactions.get(op["id"], {}).get("on_failure") if op["kind"] == "transaction" else None
        if failure:
            scene["on_failure"] = dict(failure)
    if segment.next_scene:
        scene["then"] = segment.next_scene
    return scene


def _presentation_targets(spec: ChapterSpec) -> set[str]:
    """必須在鎖操作的演出裡播放的段落：入口段落、被選項或接續帶進來的段落。地圖觸發的短句才用氣泡或通訊。"""
    source = spec.source
    entries = {name for phases in spec.dispatch.values() for name in phases}
    targets = set()
    for segment in source.segments.values():
        if segment.id in entries and segment.mode not in ("radio", "bubbles"):
            targets.add(segment.id)
        for option in segment.options:
            if option.target:
                targets.add(option.target)
        if segment.next_scene and segment.mode not in ("radio", "bubbles"):
            targets.update((segment.id, segment.next_scene))
    return targets


def _dispatchers(spec: ChapterSpec, scenes: dict) -> dict:
    out = {}
    for binding, phases in spec.dispatch.items():
        routes = []
        for name in phases:
            if name not in scenes:
                raise CompileError(f"分派 {binding}：段落不存在 {name}")
            when = copy.deepcopy(scenes[name].get("when", {}))
            done = [{"not": {"flag": op["id"], "equals": True}} for op in scenes[name].get("results", [])
                    if op["kind"] == "flag" and op["value"] is True]
            clauses = ([when] if when else []) + done
            routes.append({"when": clauses[0] if len(clauses) == 1 else ({"all": clauses} if clauses else {}), "target": name})
        out[f"{spec.prefix}_dispatch_{binding}"] = {"mode": "dispatch", "routes": routes}
    return out


def _quests(spec: ChapterSpec) -> list:
    quests = []
    for q in spec.source.quests:
        if q.id in spec.unpublished_quests:
            continue
        steps = []
        for step in q.steps:
            if step.binding not in spec.quest_locations:
                raise CompileError(f"任務 {q.id}：步驟「{step.title}」沒有真實地點 {step.binding}")
            level, x, y = spec.quest_locations[step.binding]
            steps.append({"title": step.title, "complete_flag": step.complete_flag,
                          "location": {"level": f"res://data/levels/{spec.prefix}_{level}.tres", "cell": [x, y]}})
        quest = {"id": q.id, "kind": q.kind, "title": q.title, "background": q.background, "reward": q.reward,
                 "complete_flag": q.complete_flag, "steps": steps}
        if q.visible_flags:
            quest["visible_flags"] = list(q.visible_flags)
        if q.completion_requires_steps:
            quest["completion_requires_steps"] = True
        if q.requires_flags:
            quest["requires_flags"] = list(q.requires_flags)
            quest["blocked_reason"] = q.blocked_reason
            quest["suggestion"] = q.suggestion
        quests.append(quest)
    return quests


def _defaults(spec: ChapterSpec, scenes: dict) -> dict:
    out = dict(spec.flag_defaults)
    for scene in scenes.values():
        for op in scene.get("results", []):
            if op["kind"] == "flag":
                value = op["value"]
                out.setdefault(op["id"], "unset" if isinstance(value, str) else (0 if isinstance(value, int) and not isinstance(value, bool) else False))
        for entry in _walk(scene.get("steps", [])):
            flags = entry.get("set_flags")
            for name, value in flags.items() if isinstance(flags, dict) else ():
                out.setdefault(name, "unset" if isinstance(value, str) else False)
    for name in spec.derived_flags:
        out.setdefault(name, False)
    return out


def compile_chapter(spec: ChapterSpec) -> dict:
    source = spec.source
    targets = _presentation_targets(spec)
    scenes = {}
    for ident, segment in source.segments.items():
        scenes[ident] = _compile_segment(segment, spec, ident in targets)
    for ident, scene in spec.extra_scenes.items():
        if ident in scenes:
            raise CompileError(f"場景 {ident} 重複")
        scenes[ident] = copy.deepcopy(scene)
    scenes.update(_dispatchers(spec, scenes))
    for ident in spec.important_radio:
        if scenes.get(ident, {}).get("mode") != "radio":
            raise CompileError(f"重要通訊 {ident} 不是通訊場景")
        scenes[ident]["freeze"] = True
    _check_lines(scenes)
    chapter = dict(spec.chapter)
    chapter["languages"] = ["zh", *story_i18n.LANGUAGES]
    document = {
        "chapter": chapter, "speakers": copy.deepcopy(source.speakers), "flag_defaults": _defaults(spec, scenes),
        "transactions": {k: {"resource": v["resource"]} for k, v in source.transactions.items()},
        "derived_flags": copy.deepcopy(spec.derived_flags), "quests": _quests(spec), "scenes": scenes,
    }
    if spec.death_sequences:
        document["death_sequences"] = copy.deepcopy(spec.death_sequences)
    return document


def _check_lines(scenes: dict):
    """台詞與選項不能是空的；講者要有名字。"""
    for ident, scene in scenes.items():
        for line in scene.get("lines", []):
            if not str(line.get("text", "")).strip() or not line.get("speaker"):
                raise CompileError(f"{ident}：有空白台詞或缺講者")
        for step in _walk(scene.get("steps", [])):
            if step.get("do") == "say" and (not str(step.get("text", "")).strip() or not step.get("speaker")):
                raise CompileError(f"{ident}：有空白台詞或缺講者")


def write_chapter(spec: ChapterSpec, out_path: Path) -> list[str]:
    """轉譯、補上譯文並寫檔；回傳缺譯位置（不擋輸出，遊戲端退回英文再退回中文）。"""
    document = compile_chapter(spec)
    missing = story_i18n.apply(document, story_i18n.load_table(story_i18n.table_path(spec.chapter["id"])))
    os.makedirs(out_path.parent, exist_ok=True)
    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(document, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print("wrote", out_path, f"({len(document['scenes'])} scenes, {len(document['quests'])} quests)")
    if missing:
        print(f"缺譯 {len(missing)} 處（補在 tools/story/i18n/{spec.chapter['id']}.json）：" + "；".join(missing[:5]), file=sys.stderr)
    return missing


# ---------------------------------------------------------------------------
# 各章共用的作者工具：答錯再選一次、劇情文件與交易資源的輸出
# ---------------------------------------------------------------------------

def route_back_to_choices(source, dispatch: dict, prefix: str):
    """「選錯了再選一次」：提示段落接回剛才的選擇。接續不重播看過的段落，所以改經一個只有一條路線的分派回去。"""
    talk_prefix = f"{prefix}_t_"
    for ident, segment in list(source.segments.items()):
        target = segment.next_scene
        if target and target in source.segments and source.segments[target].options and not target.startswith(f"{prefix}_dispatch_"):
            binding = f"back_{target.removeprefix(talk_prefix)}"
            dispatch.setdefault(binding, [target])
            source.segments[ident] = dataclasses.replace(segment, next_scene=f"{prefix}_dispatch_{binding}")


def write_documents(source, chapter_id: str, item_dir: Path, order_base: int):
    """劇情文件 → data/story_items/<id>.tres（排序值從 order_base 起，章節欄位寫本章）。"""
    for order, (ident, document) in enumerate(source.documents.items()):
        text = render_document_resource(ident, document, order_base + order).replace('chapter = &"ch1_kasa"', f'chapter = &"{chapter_id}"')
        (item_dir / f"{ident}.tres").write_text(text, encoding="utf-8")


def write_transactions(transactions: dict, transaction_dir: Path, owned_prefix: str):
    """本章的交易資源 → data/story_transactions/<檔名>.tres。只寫本章前綴的交易；前章的交易由前章維護，這裡只引用。"""
    for canonical, (filename, amount) in transactions.items():
        if not canonical.startswith(owned_prefix):
            continue
        text = "\n".join([
            '[gd_resource type="Resource" script_class="StoryTransactionData" load_steps=2 format=3]', "",
            '[ext_resource type="Script" path="res://data/scripts/story_transaction_data.gd" id="1_script"]', "",
            "[resource]", 'script = ExtResource("1_script")', f'id = &"{canonical}"', "definition_version = 1",
            f"credits_delta = {amount}", ""])
        (transaction_dir / f"{filename}.tres").write_text(text, encoding="utf-8")

