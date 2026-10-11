"""ST-9：把第一章作者來源（ch1_closure.py）轉成遊戲讀取的 data/story/ch1_kasa.json。

規則（執行期契約見 core/story_outcomes.gd 與 autoload/story.gd）：
- 段落的 when 原樣成為場景的前置條件；結果（旗標、取得、交出、交易）成為 results，只在整段播完時一起生效。
- 有選項的段落成為「疊加動畫」場景：台詞後接一個選擇步驟，選項帶 when、意圖旗標與接續 target；
  略過演出時套用 default，而 default 一律是不做不可逆決定的「先返回」類選項。
- 三句以上的對話保留 dialogue；一兩句的回訪若每句 ≤30 字且非接續段落，改成地圖氣泡；其餘用疊加動畫。
- 每個人物或物件入口是一個分派場景：依劇本的階段順序挑第一個成立的段落；可選話題收進最後的「話題」選擇。
- 任務只發布有真實地圖位置、玩家走得到的目標；需要第二章入口或只在初次建檔舞台出現的語義不發布成地圖任務。

本檔不讀寫存檔、不送旗標，只產生資料；執行 `python3 tools/story/ch1_runtime_backend.py` 會覆寫 ch1_kasa.json 與舞台。
"""
from __future__ import annotations

import copy
import json
import os
import sys
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/story"))

import build_ch1_story as legacy  # noqa: E402
import story_i18n  # noqa: E402
from ch1_closure import build_source, validate_source  # noqa: E402
import prologue_source  # noqa: E402

OUT = ROOT / "data/story/ch1_kasa.json"
BUBBLE_MAX_CHARS = 30
BUBBLE_MAX_LINES = 4
DIALOGUE_MIN_LINES = 3
# 舊稿裡被正式稿取代的場景；舊開場（試槍與世界說明）由 ST-16 的序章取代，不再出現在遊戲裡。
SUPERSEDED_LEGACY = {"ch1_t_ali_2", "ch1_t_ali_3", "ch1_c01_open"}
# 任務的公開時機：第一章的第一個目標在序章結束（或略過）後才出現，序章期間只看得到序章的目標。
EXTRA_VISIBLE = {"ch1_meet_egret": ["ch1_prologue_exit"]}

# 人物／物件入口的階段順序：越前面越優先（劇本的主線節點先於回訪）。
DISPATCH_PHASES = {
    "cabinet": ["ch1_t_handoff_confirm", "ch1_t_handoff_receipt_prompt", "ch1_t_handoff_summary_prompt", "ch1_t_handoff_revisit"],
    "brief": ["ch1_t_egret_1", "ch1_t_egret_sunday", "ch1_t_egret_sunday_prompt", "ch1_t_egret_sunday_revisit"],
    "ali_lounge": ["ch1_t_ali_meet_booth", "ch1_t_ali_meet_clinic", "ch1_t_ali_meet_no_death", "ch1_t_ali_meet_unknown",
                   "ch1_t_ali_name", "ch1_t_ali_2_ordered", "ch1_t_ali_2_sit", "ch1_t_ali_evening_close", "ch1_t_ali_evening_revisit"],
    "ali_stall": ["ch1_t_supper_choice_ordered", "ch1_t_supper_choice_none", "ch1_t_supper_leave_options", "ch1_t_supper_leave_none",
                  "ch1_t_supper_host_prompt", "ch1_t_supper_host_none_prompt", "ch1_t_supper_stay_meal", "ch1_t_supper_stay_address",
                  "ch1_t_supper_leave_revisit_paid200", "ch1_t_supper_leave_revisit_owed200", "ch1_t_supper_leave_revisit_none",
                  "ch1_t_supper_stay_revisit", "ch1_t_ali_4"],
    **{f"label_{n}": [f"ch1_t_label_{n}", f"ch1_t_label_{n}_revisit"] for n in ("watch", "guitar", "raincoat", "fare")},
    "voice": ["ch1_t_lamp_voice_prompt", "ch1_t_lamp_voice_second_prompt", "ch1_t_lamp_voice_revisit"],
}
# 可選話題「中樞」：replace 指定的入口段落被中樞取代；中樞先說 lines_from 的台詞，再列話題與 extra 選項，
# 話題播完回到中樞，選「先這樣」結束。
OPTIONAL_TOPICS = {
    "brief": {"replace": ["ch1_t_egret_sunday_revisit"], "lines_from": "ch1_t_egret_sunday_revisit", "prompt": "還想問鷺什麼？",
              "topics": [("ch1_t_egret_brief_revisit", "再確認回程與交接櫃。")], "extra": []},
    "ali_lounge": {"replace": ["ch1_t_ali_2_ordered", "ch1_t_ali_2_sit"], "lines_from": None, "prompt": "想和阿梨聊什麼？",
                   "topics": [("ch1_t_ali_death_topic", "談今天的復原。"), ("ch1_t_ali_late_topic", "談為什麼這麼晚還在外面。")],
                   "extra": [{"id": "evening", "text": "問她店裡今晚的事。", "explanation": "聊完阿梨會準備下班。",
                              "target": "ch1_dispatch_ali_evening"}],
                   "extra_dispatch": {"ch1_dispatch_ali_evening": ["ch1_t_ali_2_ordered", "ch1_t_ali_2_sit"]}},
}
# 劇本中由真實服務推出、不存檔的事實（StoryOutcomes.runtime_facts 的提供者）。
RUNTIME_FACTS = {
    "ch1_zero_true_deaths": "deaths_zero",
    "ch1_true_death_record_known": "always",
    "ch1_booth_registered": "checkpoint_registered",
    "ch1_first_clinic_active": "context:first_clinic",
}
# 由正式帳務與旗標推出、每段結果後重算的旗標（任務與條件都讀得到）。
EXTRA_DERIVED = {
    "ch1_supper_can_rechoose": {"all": [
        {"any": [{"account": "ch1_lounge", "equals": "none"}, {"account": "ch1_lounge", "equals": "open200"}]},
        {"not": {"flag": "ch1_supper_host_accepted", "equals": True}},
        {"not": {"flag": "ch1_supper_meal_done", "equals": True}},
        {"not": {"flag": "ch1_supper_done", "equals": True}}]},
    "ch2_previous_job_settled": {"receipt": "ch1.commission.settled", "status": "recorded"},
}
# 真實世界事件的旗標由產生它的資料寫入：關卡的機關頻道（tools/level/build_ch1.py 的 STORY channels_done／channels_cleared）
# 與物品的 acquire_flag（ch1_data_disk → ledger_disk_obtained）。這裡只登記預設值。
WORLD_FLAGS = ("ch1_street_route_open", "watchdog_defeated", "ch1_flood_gate_open", "ledger_disk_obtained")
# 章節資訊：章末卡的下一步提示，與結算畫面說明這一版收錄到哪裡（進度已保存，不偽裝成已有第二章）。
CHAPTER_EXTRA = {
    "teaser": "下一步：明早核對交盤回執，再去市集查那張缺的附件。",
    "release_note": "進度已保存。這一版收錄到第一章結束，第二章尚未收錄。",
}
# 一般死亡的畫面序列（第一次死亡走初次建檔，不經過死亡畫面，所以完整版出現在第一次在電話亭醒來）：
# 錄音的「再來一次，沒關係」→ 一個呼吸後燈說「歡迎回來」→ 狀態列 → 記憶卡；之後縮短，再之後可略過。
DEATH_SEQUENCES = [
    {"min_deaths": 1, "skippable": False, "steps": [
        {"kind": "line", "speaker": "voice", "text": "再來一次，沒關係。", "time": 2.2},
        {"kind": "line", "speaker": "lamp", "text": "歡迎回來，你又回到亭子了。", "time": 1.8},
        {"kind": "status", "text": "復原完成，復原費已從身上的信用點扣除。", "time": 1.6},
        {"kind": "card", "time": 2.4}]},
    {"min_deaths": 3, "skippable": False, "steps": [
        {"kind": "line", "speaker": "lamp", "text": "歡迎回來，路線還接著。", "time": 1.2},
        {"kind": "status", "text": "復原完成，復原費已結算。", "time": 1.0},
        {"kind": "card", "time": 1.2}]},
    {"min_deaths": 5, "skippable": True, "steps": [
        {"kind": "line", "speaker": "lamp", "text": "你知道流程的，我們再走一次。", "time": 0.9},
        {"kind": "card", "time": 0.8}]},
]
# 第一次在電話亭備份（或初次建檔登記）時播放的錄音；播完才算聽過。
BOOTH_RECORDING = "ch1_t_booth_recording"
BOOTH_RECORDING_SCENE = {"mode": "radio", "set_flags": ["ch1_recording_heard"], "lines": [
    {"speaker": "voice", "text": "歡迎使用天穹備份服務，備份已經完成。"},
    {"speaker": "voice", "text": "再來一次，沒關係。"}]}
# 只在初次建檔舞台或第二章入口才成立、沒有地圖位置的任務語義，不發布成地圖任務。
UNPUBLISHED_QUESTS = {"ch1_next_morning", "sq6_ch1_cloth"}
# 任務步驟的真實格位（角色腳底所在格；入口物件或人物站的位置）。
QUEST_LOCATIONS = {
    "dinner": ("pawnshop", 89, 19), "brief": ("rooftop", 53, 17), "street_clear": ("street", 182, 19),
    "watchdog": ("warehouse", 81, 16), "flood": ("warehouse", 117, 16), "disk_pickup": ("vault", 40, 16),
    "cabinet": ("handoff", 17, 19), "ali_lounge": ("lounge", 29, 19), "ali_stall": ("stall", 20, 19),
    "home": ("pawnshop_dawn", 75, 19), "voice": ("booth_alley", 25, 19),
    "label_watch": ("pawnshop", 32, 19), "label_guitar": ("pawnshop", 35, 19),
    "label_raincoat": ("pawnshop", 36, 19), "label_fare": ("pawnshop", 45, 19),
}
LEVEL = "res://data/levels/ch1_%s.tres"


class CompileError(ValueError):
    pass


def _say_lines(steps):
    return [{"speaker": s["speaker"], "text": s["text"]} for s in steps if s.get("do") == "say"]


def _results(segment):
    ops = []
    for op in segment.completion:
        kind = op["kind"]
        if kind == "flag":
            ops.append({"kind": "flag", "id": op["id"], "value": op["value"]})
        elif kind in ("item_acquire", "item_transfer", "transaction"):
            ops.append({"kind": kind, "id": op["id"]})
        else:
            raise CompileError(f"{segment.id}: 不支援的結果種類 {kind}")
    return ops


def _choice_step(segment, source):
    options = []
    default = None
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
            if option.target not in source.segments:
                raise CompileError(f"{segment.id}.{option.id}: 接續段落不存在 {option.target}")
            entry["target"] = option.target
        options.append(entry)
    # 略過演出時套用的預設：先找「先返回」（沒有接續），再找只寫可逆旗標的接續；交易、交付或取物一律不當預設。
    def reversible(target_id):
        target = source.segments.get(target_id)
        return target is None or all(op["kind"] == "flag" for op in target.completion)

    for option in segment.options:
        if option.target is None:
            default = option.id
            break
    if default is None:
        for option in reversed(segment.options):
            if reversible(option.target):
                default = option.id
                break
    if default is None:
        raise CompileError(f"{segment.id}: 找不到安全的預設選項")
    # 選擇時對話框會收起：把這段最後一句（通常是價格、確認內容）留在選擇提示上，邊看邊決定。
    says = [s for s in segment.steps if s.get("do") == "say"]
    prompt = "請選擇接下來的行動。"
    if says:
        prompt = says[-1]["text"]
    return {"do": "choice", "text": prompt, "default": default, "options": options}


def _presentation_targets(source):
    """必須在鎖操作的演出裡播放的段落：人物／物件入口的段落（玩家主動對話）、被選項或演出接續帶進來的段落，
    以及自己會接續到下一段的段落。地圖觸發的短句才用氣泡或通訊。"""
    targets = set()
    talk_bindings = {b for b in DISPATCH_PHASES} | {"first_clinic", "home"}
    for segment in source.segments.values():
        if segment.binding in talk_bindings and segment.mode not in ("radio", "bubbles"):
            targets.add(segment.id)
        for option in segment.options:
            if option.target:
                targets.add(option.target)
        if segment.next_scene and segment.mode not in ("radio", "bubbles"):
            targets.update((segment.id, segment.next_scene))
    return targets


def _bubble_ok(lines):
    return len(lines) <= BUBBLE_MAX_LINES and all(len(line["text"]) <= BUBBLE_MAX_CHARS for line in lines)


def _compile_segment(segment, source, inside_presentation, base_scene):
    scene = {}
    results = _results(segment)
    lines = _say_lines(segment.steps)
    if segment.options:
        steps = [copy.deepcopy(s) for s in segment.steps] + [_choice_step(segment, source)]
        scene.update(mode="animated", overlay=True, steps=steps)
    elif segment.mode == "animated":
        steps = [copy.deepcopy(s) for s in segment.steps]
        if base_scene and not any(s.get("do") == "scene" for s in steps) and any(s.get("do") == "scene" for s in base_scene.get("steps", [])):
            # 作者只寫台詞時沿用已量測的舞台：開頭的佈景／演員／光影與結尾的收勢都來自原演出。
            base_steps = base_scene["steps"]
            first_say = next(i for i, s in enumerate(base_steps) if s.get("do") == "say")
            last_say = max(i for i, s in enumerate(base_steps) if s.get("do") == "say")
            steps = copy.deepcopy(base_steps[:first_say]) + steps + copy.deepcopy(base_steps[last_say + 1:])
        scene.update(mode="animated", steps=steps)
        if not any(s.get("do") == "scene" for s in steps):
            scene["overlay"] = True
        for key in ("budget", "pose_policy"):
            if base_scene and key in base_scene:
                scene[key] = base_scene[key]
    elif segment.mode in ("radio", "bubbles"):
        scene.update(mode=segment.mode, lines=lines)
    elif len(lines) >= DIALOGUE_MIN_LINES:
        scene.update(mode="dialogue", lines=lines)
    elif not inside_presentation and not any(op["kind"] != "flag" for op in results) and _bubble_ok(lines):
        scene.update(mode="bubbles", lines=lines)
    else:
        scene.update(mode="animated", overlay=True, steps=[copy.deepcopy(s) for s in segment.steps])
    if segment.when:
        scene["when"] = copy.deepcopy(segment.when)
    if results:
        scene["results"] = results
    for op in segment.completion:
        failure = source.transactions.get(op["id"], {}).get("on_failure") if op["kind"] == "transaction" else None
        if failure:
            scene["on_failure"] = dict(failure)
    if segment.next_scene:
        scene["then"] = segment.next_scene
    return scene


def _dispatchers(source, scenes):
    out = {}
    for binding, phases in DISPATCH_PHASES.items():
        routes = []
        for name in phases:
            if name not in scenes:
                raise CompileError(f"分派 {binding}：段落不存在 {name}")
            when = copy.deepcopy(scenes[name].get("when", {}))
            # 已經完成的節點不從入口重播：段尾把某個旗標設成完成，路線就要求它尚未成立。
            done = [{"not": {"flag": op["id"], "equals": True}} for op in scenes[name].get("results", [])
                    if op["kind"] == "flag" and op["value"] is True]
            clauses = ([when] if when else []) + done
            routes.append({"when": clauses[0] if len(clauses) == 1 else ({"all": clauses} if clauses else {}), "target": name})
        out[f"ch1_dispatch_{binding}"] = {"mode": "dispatch", "routes": routes}
    return out


def _as_presentation(scene, segment):
    """可選話題要能接回中樞，必須是鎖操作的演出；一兩句的話題改用疊加動畫。"""
    if scene.get("mode") in ("animated", "dialogue"):
        return
    steps = [{"do": "say", "speaker": l["speaker"], "text": l["text"]} for l in scene.get("lines", [])]
    keep = {k: scene[k] for k in ("when", "results") if k in scene}
    scene.clear()
    scene.update(mode="animated", overlay=True, steps=steps, **keep)


def _attach_topics(source, scenes):
    for binding, spec in OPTIONAL_TOPICS.items():
        hub_id = f"ch1_hub_{binding}"
        options = []
        for scene_id, title in spec["topics"]:
            _as_presentation(scenes[scene_id], source.segments[scene_id])
            scenes[scene_id]["then"] = hub_id
            option = {"id": scene_id.replace("ch1_t_", ""), "text": title, "explanation": "可選話題，不影響主線。", "target": scene_id}
            if source.segments[scene_id].when:
                option["when"] = copy.deepcopy(source.segments[scene_id].when)
            options.append(option)
        options.extend(copy.deepcopy(spec["extra"]))
        options.append({"id": "leave", "text": "先聊到這裡，我還有事要做。", "explanation": "結束對話，之後可以再來。"})
        if len(options) > 4:
            raise CompileError(f"{hub_id}：選項超過 4 個")
        lines = _say_lines(source.segments[spec["lines_from"]].steps) if spec["lines_from"] else []
        replaced = [scenes[name].get("when", {}) for name in spec["replace"]]
        hub = {"mode": "animated", "overlay": True, "steps": [
            {"do": "say", "speaker": l["speaker"], "text": l["text"]} for l in lines] + [
            {"do": "choice", "text": spec["prompt"], "default": "leave", "options": options}]}
        when = replaced[0] if len(replaced) == 1 else {"any": replaced}
        if when:
            hub["when"] = copy.deepcopy(when)
        scenes[hub_id] = hub
        for dispatch_id, targets in spec.get("extra_dispatch", {}).items():
            scenes[dispatch_id] = {"mode": "dispatch", "routes": [
                {"when": copy.deepcopy(scenes[t].get("when", {})), "target": t} for t in targets]}
        phases = DISPATCH_PHASES[binding]
        first = phases.index(spec["replace"][0])
        DISPATCH_PHASES[binding] = phases[:first] + [hub_id] + [p for p in phases[first:] if p not in spec["replace"]]


CLINIC_CONTINUATIONS = ("ch1_t_clinic_tray_prompt", "ch1_t_clinic_cloth_look", "ch1_t_clinic_cloth_decide", "ch1_t_clinic_cloth_take",
                        "ch1_t_clinic_cloth_leave", "ch1_t_clinic_backup_registered", "ch1_t_clinic_backup_missing")
CLINIC_EXITS = ("ch1_t_clinic_cloth_leave",)


def _first_clinic(scenes):
    """初次建檔：建檔演出本身由死亡場景表觸發；播完接托盤與「下次在哪裡醒來」的選擇。"""
    wake = scenes["ch1_c09_wake"]
    wake["context_facts"] = ["first_clinic"]
    when = wake.get("when", {})
    clauses = when.get("all", [when]) if when else []
    clauses = [c for c in clauses if c != {"flag": "ch1_first_clinic_active", "equals": True}]
    wake["when"] = clauses[0] if len(clauses) == 1 else {"all": clauses}
    wake["then"] = "ch1_t_clinic_tray_prompt"
    tray = scenes["ch1_t_clinic_tray_prompt"]
    choice = next(s for s in tray["steps"] if s.get("do") == "choice")
    choice["options"].insert(1, {"id": "backup", "text": "問下次會在哪裡醒來。", "explanation": "復原點的規則，不影響建檔。",
                                 "target": "ch1_dispatch_clinic_backup"})
    for topic in ("ch1_t_clinic_backup_registered", "ch1_t_clinic_backup_missing"):
        scene = scenes[topic]
        if scene.get("mode") != "animated":
            steps = [{"do": "say", "speaker": l["speaker"], "text": l["text"]} for l in scene.get("lines", [])]
            when = scene.get("when")
            scene.clear()
            scene.update(mode="animated", overlay=True, steps=steps)
            if when:
                scene["when"] = when
        scene["then"] = "ch1_t_clinic_tray_prompt"
    # 托盤與灰布都還在診間：沿用建檔的舞台與凜（極短淡入，接續同一場），只有離開的那一段收黑幕。
    staging = []
    for step in wake["steps"]:
        if step.get("do") == "say":
            break
        if step.get("do") in ("scene", "actor"):
            entry = copy.deepcopy(step)
            if entry.get("do") == "scene":
                entry["fade"] = 0.25
            staging.append(entry)
    if wake["steps"] and wake["steps"][-1].get("do") == "fade":
        wake["steps"].pop()
    for ident in CLINIC_CONTINUATIONS:
        scene = scenes[ident]
        scene.pop("overlay", None)
        scene["steps"] = copy.deepcopy(staging) + scene["steps"]
        scene["pose_policy"] = wake.get("pose_policy", "supported")
        if ident in CLINIC_EXITS or ident == "ch1_t_clinic_cloth_take":
            scene["steps"].append({"do": "fade", "to": 1.0, "time": 0.8})
    scenes["ch1_dispatch_clinic_backup"] = {"mode": "dispatch", "routes": [
        {"when": copy.deepcopy(scenes[t].get("when", {})), "target": t}
        for t in ("ch1_t_clinic_backup_registered", "ch1_t_clinic_backup_missing")]}


def _quests(source):
    quests = []
    for q in source.quests:
        if q.id in UNPUBLISHED_QUESTS:
            continue
        steps = []
        for step in q.steps:
            if step.binding not in QUEST_LOCATIONS:
                raise CompileError(f"任務 {q.id}：步驟「{step.title}」沒有真實地點 {step.binding}")
            level, x, y = QUEST_LOCATIONS[step.binding]
            steps.append({"title": step.title, "complete_flag": step.complete_flag, "location": {"level": LEVEL % level, "cell": [x, y]}})
        quest = {"id": q.id, "kind": q.kind, "title": q.title, "background": q.background, "reward": q.reward,
                 "complete_flag": q.complete_flag, "steps": steps}
        visible = list(q.visible_flags) + EXTRA_VISIBLE.get(q.id, [])
        if visible:
            quest["visible_flags"] = visible
        if q.requires_flags:
            quest["requires_flags"] = list(q.requires_flags)
            quest["blocked_reason"] = q.blocked_reason
            quest["suggestion"] = q.suggestion
        quests.append(quest)
    return quests


def _defaults(source, scenes):
    out = dict(source.flag_defaults)
    for scene in scenes.values():
        for op in scene.get("results", []):
            if op["kind"] == "flag":
                out.setdefault(op["id"], "unset" if isinstance(op["value"], str) else False)
        for entry in _walk(scene.get("steps", [])):
            for name, value in entry.get("set_flags", {}).items() if isinstance(entry.get("set_flags"), dict) else ():
                out.setdefault(name, "unset" if isinstance(value, str) else False)
    for name in WORLD_FLAGS:
        out.setdefault(name, False)
    out.setdefault("ch1_recording_heard", False)
    out.setdefault("ch1_booth_restoration_done", False)
    for name in (*source.derived_flags, *EXTRA_DERIVED):
        out.setdefault(name, False)
    for name in RUNTIME_FACTS:
        out.pop(name, None)
    return out


def _walk(steps):
    for step in steps if isinstance(steps, list) else []:
        if isinstance(step, dict):
            yield step
            for key in ("options", "steps", "else_steps"):
                yield from _walk(step.get(key))


# 重要通訊（NE-246）：教學、頭目、謎題提示與劇情通訊顯示時凍結世界、等玩家確認。
# 只有這些一句話的隨口回應維持不暫停（死後回來的反應、清場後的一句）。
AMBIENT_RADIO = {"ch1_g06_clear", "ch1_d_back_a", "ch1_d_back_b", "ch1_d_back_c"}


def _mark_important_radio(scenes):
    for ident, scene in scenes.items():
        if scene.get("mode", "radio") == "radio" and ident not in AMBIENT_RADIO and scene.get("lines"):
            scene["freeze"] = True


def compile_document():
    source = build_source()
    errors = validate_source(source)
    if errors:
        raise CompileError("\n".join(errors))
    legacy.build()
    base_scenes = {k: v for k, v in legacy.SCENES.items() if k not in SUPERSEDED_LEGACY}
    scenes = {k: v for k, v in base_scenes.items() if k not in source.segments}
    targets = _presentation_targets(source)
    for ident, segment in source.segments.items():
        scenes[ident] = _compile_segment(segment, source, ident in targets, base_scenes.get(ident))
    scenes[BOOTH_RECORDING] = copy.deepcopy(BOOTH_RECORDING_SCENE)
    prologue_scenes, prologue_quests, prologue_defaults, prologue_derived = prologue_source.build()
    scenes.update(prologue_scenes)
    _first_clinic(scenes)
    _attach_topics(source, scenes)
    scenes.update(_dispatchers(source, scenes))
    _mark_important_radio(scenes)
    speakers = copy.deepcopy(legacy.SPEAKERS)
    speakers.update(copy.deepcopy(source.speakers))
    speakers.update(copy.deepcopy(prologue_source.SPEAKERS))
    # 凜與老 K 的名牌原本只寫在舊稿（chapter_01.json）；正式第一章自己帶，三語名牌才有地方放（ST-2）。
    speakers.setdefault("rin", {"name": "凜", "color": "#ff3fa4", "portrait": "res://art/portraits/rin.png"})
    speakers.setdefault("old_k", {"name": "老K", "color": "#ffd23f", "portrait": "res://art/portraits/old_k.png"})
    derived = copy.deepcopy(source.derived_flags)
    derived.update(copy.deepcopy(EXTRA_DERIVED))
    derived.update(prologue_derived)
    defaults = _defaults(source, scenes)
    defaults.update({k: v for k, v in prologue_defaults.items() if k not in defaults})
    return {
        "chapter": {**legacy.CHAPTER, **CHAPTER_EXTRA}, "speakers": speakers, "death_sequences": copy.deepcopy(DEATH_SEQUENCES),
        "respawn_scenes": legacy.RESPAWN, "death_scenes": legacy.DEATH_SCENES,
        "flag_defaults": defaults,
        "transactions": {k: {"resource": v["resource"]} for k, v in source.transactions.items() if v["caller"] == "chapter1"},
        "derived_flags": derived, "runtime_facts": dict(RUNTIME_FACTS),
        "event_scenes": [{"event": "checkpoint", "scene": BOOTH_RECORDING}],
        "restoration_flag": "ch1_booth_restoration_done",
        "quests": prologue_quests + _quests(source), "scenes": scenes,
    }


def main():
    try:
        data = compile_document()
    except CompileError as error:
        print(str(error), file=sys.stderr)
        return 2
    # ST-2：每一句補上日文與英文（對照表在 tools/story/i18n/ch1_kasa.json）；缺譯列出具體位置，遊戲端退回英文再退回中文。
    data["chapter"]["languages"] = ["zh", *story_i18n.LANGUAGES]
    missing = story_i18n.apply(data, story_i18n.load_table(story_i18n.table_path("ch1_kasa")))
    if missing:
        print(f"缺譯 {len(missing)} 處（補在 tools/story/i18n/ch1_kasa.json）：" + "；".join(missing[:5]), file=sys.stderr)
    os.makedirs(legacy.STAGE_DIR, exist_ok=True)
    for stage_id, (scene, top, bottom, rain, glow, extra) in legacy.STAGES.items():
        legacy.write_stage(stage_id, scene, top, bottom, rain, glow, extra)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print("wrote", OUT, f"({len(data['scenes'])} scenes, {len(data['quests'])} quests)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
