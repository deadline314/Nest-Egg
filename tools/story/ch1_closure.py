"""ST-9 authored production source; never a runtime fixture.

The approved script is split at whole-scene commit boundaries.  This module
describes presentation, explicit decisions, preconditions and real producers.
Only a backend implementing these contracts may turn it into loaded Story JSON.
The current engine cannot silently ignore authoring fields and publish success.
"""
from __future__ import annotations

from dataclasses import dataclass, field
import hashlib
import json
from pathlib import Path
from typing import Any, Protocol

SCRIPT = "design/13-story-v2/CH01_CLOSURE_SCRIPT.md"
ENTRY_CONTRACT = {"upstream_source": "design/13-story-v2/PROLOGUE_SCRIPT.md", "upstream_section": "P06",
                  "entry_scene": "ch1_b_dinner", "required_order": ["P06 safe exit", "ch1_b_dinner_food completed", "ch1_t_egret_1 completed"],
                  "runtime_prologue_integrated": False}
LEVEL = "res://data/levels/ch1_%s.tres"
ITEM_DIR = "res://data/story_items/"
# Read-only projections of canonical receipts, never saved account values.
# Backend verifies each recorded definition fingerprint against its resource.
# Untrusted, conflicting or definition-changed receipts are an error, not none.
MEAL_RECEIPTS = tuple("ch1.revival_meal." + suffix for suffix in ("order", "paid", "tab", "gift", "later_pay"))
ACCOUNT_RECEIPTS = {
    "none": {"exact_recorded_sets": [[]]},
    "open200": {"exact_recorded_sets": [[MEAL_RECEIPTS[0]]]},
    "paid200": {"exact_recorded_sets": [[MEAL_RECEIPTS[0], MEAL_RECEIPTS[1]], [MEAL_RECEIPTS[0], MEAL_RECEIPTS[2], MEAL_RECEIPTS[4]]]},
    "owed200": {"exact_recorded_sets": [[MEAL_RECEIPTS[0], MEAL_RECEIPTS[2]]]},
    "gifted200": {"exact_recorded_sets": [[MEAL_RECEIPTS[0], MEAL_RECEIPTS[3]]]},
}


def author_account_state(recorded_canonical_ids: set[str]) -> str:
    """Pure author-rule check, not a runtime ledger or a saved account.

    Runtime must first reject untrusted/fingerprint-drifted receipts via the
    canonical service.  This only proves the six permitted meal subsets are
    disjoint; dinner/commission/other receipts are outside the meal subset.
    """
    subset = recorded_canonical_ids.intersection(MEAL_RECEIPTS)
    matches = [state for state, rule in ACCOUNT_RECEIPTS.items()
               if any(subset == set(allowed) for allowed in rule["exact_recorded_sets"])]
    if len(matches) != 1:
        raise ValueError("Invalid meal receipt combination; preserve evidence and refuse account predicate")
    return matches[0]


def flag(name: str, value: Any = True) -> dict:
    return {"flag": name, "equals": value}


def item(name: str) -> dict:
    return {"item": name}


def account(state: str) -> dict:
    return {"account": "ch1_lounge", "equals": state}


def receipt(name: str) -> dict:
    return {"receipt": name, "status": "recorded"}


def all_of(*conditions: dict) -> dict:
    return {"all": list(conditions)}


def any_of(*conditions: dict) -> dict:
    return {"any": list(conditions)}


def negate(condition: dict) -> dict:
    return {"not": condition}


def set_flag(name: str, value: Any = True) -> dict:
    return {"kind": "flag", "id": name, "value": value}


def grant(name: str, source_binding: str | None = None) -> dict:
    operation = {"kind": "item_acquire", "id": name}
    if source_binding:
        operation["source_binding"] = source_binding
    return operation


def transfer(name: str, destination: str) -> dict:
    return {"kind": "item_transfer", "id": name, "destination": destination}


def transaction(name: str) -> dict:
    # The registered transaction owns amount, guards, state and receipt.  No
    # choice flag is evidence that payment succeeded, and no raw cash step exists.
    return {"kind": "transaction", "id": name}


def say(speaker: str, text: str) -> dict:
    return {"do": "say", "speaker": speaker, "text": text}


def beats(*lines: tuple[str, str]) -> list[dict]:
    result = []
    for index, (speaker, text) in enumerate(lines):
        if index and index % 3 == 0:
            result.append({"do": "wait", "time": 0.35})
        result.append(say(speaker, text))
    return result


@dataclass(frozen=True)
class Option:
    id: str
    text: str
    target: str | None
    explanation: str
    when: dict = field(default_factory=dict)
    # Only reversible route intent or investigation visibility may be selected
    # here.  Items, payment and irreversible results belong to segment completion.
    intent: tuple[dict, ...] = ()


@dataclass(frozen=True)
class Segment:
    id: str
    section: str
    steps: tuple[dict, ...]
    when: dict = field(default_factory=dict)
    completion: tuple[dict, ...] = ()
    options: tuple[Option, ...] = ()
    binding: str = ""
    mode: str = "dialogue"
    next_scene: str | None = None
    staging: str = ""
    # Returning from a confirmation is not a successful completed scene.
    on_cancel: str = "return_without_completion"


@dataclass(frozen=True)
class QuestStep:
    title: str
    complete_flag: str
    binding: str


@dataclass(frozen=True)
class Quest:
    id: str
    kind: str
    title: str
    background: str
    reward: str
    complete_flag: str
    steps: tuple[QuestStep, ...]
    visible_flags: tuple[str, ...] = ()
    requires_flags: tuple[str, ...] = ()
    blocked_reason: str = ""
    suggestion: str = ""
    completion_requires_steps: bool = False


@dataclass(frozen=True)
class Binding:
    kind: str
    owner: str
    source: str
    location_candidate: dict | None = None
    pending: str = ""


@dataclass
class ProductionSource:
    segments: dict[str, Segment] = field(default_factory=dict)
    quests: list[Quest] = field(default_factory=list)
    bindings: dict[str, Binding] = field(default_factory=dict)
    external_producers: dict[str, str] = field(default_factory=dict)
    transactions: dict[str, dict] = field(default_factory=dict)
    documents: dict[str, dict] = field(default_factory=dict)
    derived_flags: dict[str, dict] = field(default_factory=dict)
    speakers: dict[str, dict] = field(default_factory=dict)
    flag_defaults: dict[str, Any] = field(default_factory=lambda: {"ch1_supper_choice": "unset"})

    def add(self, ident, section, lines=(), *, steps=None, **kwargs):
        if ident in self.segments:
            raise ValueError(f"{SCRIPT} {section}: duplicate scene {ident}")
        self.segments[ident] = Segment(
            ident, section, tuple(steps if steps is not None else beats(*lines)), **kwargs)

    def producer_index(self) -> dict[str, list[str]]:
        index = {name: [where] for name, where in self.external_producers.items()}
        for segment in self.segments.values():
            for operation in segment.completion:
                if operation["kind"] == "flag":
                    index.setdefault(operation["id"], []).append(f"{segment.id}:completion")
            for option in segment.options:
                for operation in option.intent:
                    index.setdefault(operation["id"], []).append(f"{segment.id}:explicit:{option.id}")
        for name in self.derived_flags:
            index[name] = ["derived from verified producers"]
        return index

    def result_producer_index(self) -> dict[str, list[str]]:
        index = {"item:ch1_data_disk": [self.external_producers["ledger_disk_obtained"]],
                 "transaction:ch1.commission.settled": [self.external_producers["ch2_previous_job_settled"]]}
        for segment in self.segments.values():
            for operation in segment.completion:
                index.setdefault(f"{operation['kind']}:{operation['id']}", []).append(f"{segment.id}:completion")
        return index


def location(level, x, y):
    return {"level": LEVEL % level, "cell": [x, y]}


def _bindings(source):
    # These are honest authoring candidates, never proof of runtime reachability.
    entries = {
        "dinner": ("map_scene", "ST-9/ST-16/ST-22", "P06 safe exit -> ch1_pawnshop kitchen dinner", location("pawnshop", 82, 19), "real prologue safe exit and split bubble continuation"),
        "brief": ("npc", "ST-9/ST-22", "ch1_rooftop Egret talks", location("rooftop", 54, 17), "bind complete briefing"),
        "street_clear": ("mechanism", "level owner", "street arena_blockade/last required encounter", location("street", 182, 19), "map exact persistent clear producer"),
        "watchdog": ("mechanism", "level owner", "warehouse watchdog_gate", location("warehouse", 58, 16), "channel event to flag"),
        "flood": ("mechanism", "level owner", "warehouse flood_c", location("warehouse", 123, 22), "persistent mechanism state to flag"),
        "disk_pickup": ("pickup", "ST-9/level owner", "vault legend y -> ch1_data_disk.tres", location("vault", 40, 16), "acquire history+world producer"),
        "cabinet": ("object", "NE-178/ST-9", "lounge new exterior handoff cabinet", location("handoff", 18, 19), "exterior/staging/object absent"),
        "ali_lounge": ("npc", "ST-9/ST-22", "lounge Y -> ali talks", location("lounge", 30, 19), "conditions and explicit menu"),
        "ali_stall": ("npc", "ST-9/ST-22", "stall Q -> ali talks", location("stall", 21, 19), "explicit route and account result"),
        "home": ("map_scene", "ST-9/ST-22", "pawnshop_dawn entry ch1_c14_home", location("pawnshop_dawn", 74, 19), "home gate reads supper_done"),
        "first_clinic": ("stage_interaction", "ST-9/ST-22", "ch1_c09_wake first real death stage", None, "no playable clinic level; stage menu backend"),
        "voice": ("object", "ST-9/level owner", "booth_alley C recording interaction", location("booth_alley", 29, 19), "actual recording heard event and safe interaction"),
        "next_morning": ("chapter_handoff", "ST-19", "chapter2 S01 job settlement", None, "chapter2 real location/terminal objective type"),
    }
    for label, cell in zip(("watch", "guitar", "raincoat", "fare"), ((34, 19), (48, 19), (37, 19), (45, 19))):
        entries[f"label_{label}"] = ("object", "ST-9/level owner", f"pawnshop unique {label} object", location("pawnshop", *cell), "true object absent")
    for ident, values in entries.items():
        source.bindings[ident] = Binding(*values)
    source.external_producers.update({
        "ch1_street_route_open": "street_clear:actual persistent encounter clearance; not radio/region entry",
        "watchdog_defeated": "watchdog:actual persistent gate event",
        "ch1_flood_gate_open": "flood:actual persistent flood_c event",
        "ledger_disk_obtained": "disk_pickup:world slot taken and StoryItems.acquire together",
        "ch1_booth_restoration_done": "NE-230 real ordinary booth restoration completion; no death-count inference",
        "ch1_true_death_record_known": "NE-230 canonical service facts present (not a second death counter)",
        "ch1_zero_true_deaths": "NE-230 derived from real death service, excludes training",
        "ch1_recording_heard": "voice:first actual recording completion or clinic recording playback",
        "ch1_booth_registered": "existing actual checkpoint registration; no clinic/recording inference",
        "ch1_first_clinic_active": "first_clinic:actual first-death presentation context, false in memory replay",
        "ch1_supper_can_rechoose": "NE-231 derived: no irreversible account result/no accepted noodle yet",
        "ch2_previous_job_settled": "NE-231 chapter2 S01 canonical ch1.commission.settled recorded receipt; chapter1 never writes or invokes",
    })


def _documents(source):
    source.documents = {
        "ch1_delivery_receipt": {
            "name": "交盤驗收回執", "icon": "doc_stub", "description": "原盤已由委託方驗收。次晨核對800報酬與80抽成，預計淨額720。",
            "body": "委託：碼頭保險箱資料盤取回。實體已驗收，原盤由委託方保管。報酬800信用點，次晨核對。一成抽成由老 K 依既有約定處理；預計凜淨額720，尚未入帳。閱覽授權限市場修繕代收批號M17與付款附件，非原盤持有權。"},
        "ch1_market_summary": {
            "name": "市場M17待查摘要", "icon": "doc_log", "description": "這筆代收缺付款附件。它是待查記錄，不能直接當作待付結論。",
            "body": "市場修繕代收批號為M17，記錄本金為200信用點。本期利息為20信用點，代收簿記載待收120信用點，但付款附件缺失。以上為待查記錄，不等於合法待付結論。須在市集代收處找同批收據、租攤合約與代收簿核對；本頁無法證明已付金額。查核安排與額外報酬次晨另行說明。"},
        "ch1_lounge_bill": {
            "name": "今晚餐酒明細", "icon": "doc_stub", "description": "明確點餐後才成立的200餐酒單；宵夜麵不收費。是否結清請看今晚的結帳紀錄。",
            "body": "復原餐120信用點；酒80信用點；合計200。離店前再結；陪坐與宵夜麵不另收費。此紙列消費明細，不代表已付。是否已付、招待或保留欠條，請核對當晚實際結帳紀錄。"},
        "ch1_lounge_tab": {
            "name": "餐酒200欠條", "icon": "doc_notice", "description": "凜親自確認保留的餐酒欠條，未付200，無利息、無抵押。",
            "body": "餐酒200信用點／未付。現在不扣款、不加息、不抵押資料盤。之後可主動確認付清；不從次晨720報酬、市集代墊40或阿梨私人債務自動抵扣。本條與委託回執分開保管。"},
    }


def render_document_resource(ident: str, document: dict, order: int) -> str:
    """Godot resource text from the same authored document source.

    These key papers are MANUAL and do not increase unattainable exploration
    collectible totals.  Loading their definitions never grants an item.
    """
    quote = lambda value: json.dumps(value, ensure_ascii=False)
    return "\n".join([
        '[gd_resource type="Resource" script_class="StoryItemData" load_steps=2 format=3]', "",
        '[ext_resource type="Script" path="res://data/scripts/story_item_data.gd" id="1_script"]', "",
        '[resource]', 'script = ExtResource("1_script")', f'id = &{quote(ident)}',
        f'display_name = {quote(document["name"])}', f'description = {quote(document["description"])}',
        'color = Color(0.78, 0.86, 0.92, 1.0)', 'category = 0', f'order = {order}',
        'chapter = &"ch1_kasa"', f'body = {quote(document["body"])}', 'trigger = 3', f'icon = {quote(document["icon"])}', "",
    ])


def _transactions(source):
    # References only.  NE-231 resources own money/conditions/fingerprint; this
    # author does not copy delta/from/to or maintain a second ledger/wallet.
    for canonical, filename, caller in (
        ("ch1.daily_dinner", "ch1_daily_dinner", "chapter1"),
        ("ch1.revival_meal.order", "ch1_revival_meal_order", "chapter1"),
        ("ch1.revival_meal.paid", "ch1_revival_meal_paid", "chapter1"),
        ("ch1.revival_meal.tab", "ch1_revival_meal_tab", "chapter1"),
        ("ch1.revival_meal.gift", "ch1_revival_meal_gift", "chapter1"),
        ("ch1.revival_meal.later_pay", "ch1_revival_meal_later_pay", "later_explicit_visit"),
        ("ch1.commission.settled", "ch1_commission_settled", "chapter2_only"),
    ):
        source.transactions[canonical] = {"resource": f"res://data/story_transactions/{filename}.tres", "caller": caller}
    source.transactions["ch1.revival_meal.paid"]["on_failure"] = {"insufficient_credits": "ch1_t_supper_insufficient"}
    source.derived_flags["ch1_lounge_ordered"] = receipt("ch1.revival_meal.order")
    source.derived_flags["ch1_lounge_tab_settled"] = receipt("ch1.revival_meal.later_pay")


def _opening(source):
    source.add("ch1_b_dinner", "dinner", (
        ("old_k", "今天的飯煮好了喔。這頓我煮給你，不用交四十。"),
        ("rin", "那我先記著。"),
        ("old_k", "不是叫你記一筆，叫你趁熱吃。明天的事明天再說。"),
        ("rin", "好，我先趁熱吃。")), binding="dinner", mode="bubbles", next_scene="ch1_b_dinner_food",
        staging="老K把碗放穩並推筷子。凜鬆開外套袋口，沒有錢或抽屜入款。")
    source.add("ch1_b_dinner_food", "dinner", (("old_k", "我把紅蘿蔔切很細了啊。"), ("rin", "還是看得到。")),
        binding="dinner", mode="bubbles", completion=(transaction("ch1.daily_dinner"), set_flag("ch1_dinner_done")), staging="凜挑紅蘿蔔；段尾真0交易收據與吃飯完成同存，不以flag冒充已有收據。")
    source.add("ch1_t_egret_1", "F01", (
        ("egret", "倉庫保險箱裡有一片資料盤，今晚把它取出來。驗收是八百，不是看一眼就算。"),
        ("rin", "一成照舊，先別算進我能花的錢。"),
        ("egret", "看門狗是倉庫的保全機甲，牠的脾氣可不好。天穹委託的盤，你先照編號取。"),
        ("egret", "拿到盤後走倉庫上層出口。那條路到復原館外的交接櫃，不用帶著盤再穿一次路障。"),
        ("rin", "復原館就是電話亭旁邊那間夜間店？"),
        ("egret", "對，交接櫃在店外，不是交給店裡的人。櫃子收盤後吐回執，明早我跟你對錢。"),
        ("rin", "盤放進櫃子裡，回執由我自己收著，我記住了。")),
        binding="brief", when=flag("ch1_dinner_done"), completion=(set_flag("ch1_heard_brief"),),
        staging="紙角由茶杯壓住，鷺畫回程線後收筆。茶與傘不交凜。")
    source.add("ch1_t_egret_brief_revisit", "F01", (("egret", "上層出口接交接櫃，回執別留在櫃裡，明早還要對。"),),
        binding="brief", when=flag("ch1_heard_brief"))
    source.add("ch1_g10_disk_unclaimed", "F02", (("lamp", "保險箱可以開了，盤還在裡面，別只顧著找上層出口。"),),
        binding="disk_pickup", mode="radio", when=all_of(flag("ch1_flood_gate_open"), negate(flag("ledger_disk_obtained"))))
    source.add("ch1_g10_disk", "F02", (("rin", "收帳人的徽章還貼在上面。"),
        ("lamp", "那是記帳用的資料盤，天穹要核哪一筆，得等交接櫃驗收。")),
        binding="disk_pickup", mode="radio", when=all_of(flag("ledger_disk_obtained"), item("ch1_data_disk")),
        next_scene="ch1_g10_disk_return", staging="由真正y拾取生產者完成後播放；本場不發盤。")
    source.add("ch1_g10_disk_return", "F02", (("rin", "我先把盤送到櫃子，錢明早再對。"),
        ("lamp", "上層通道亮了。走到出口前還有守衛，別把盤當通行證。")), binding="disk_pickup", mode="radio",
        when=all_of(flag("ledger_disk_obtained"), item("ch1_data_disk")))
    source.add("ch1_g10_disk_missing", "F02", (("lamp", "資料盤還在保險箱，取出後再走上層通道。"),),
        binding="disk_pickup", mode="radio", when=negate(flag("ledger_disk_obtained")))


def _handoff(source):
    source.add("ch1_b_handoff", "F03", (("lamp", "藍燈櫃是交盤用的，店門在旁邊。"), ("rin", "我先把盤交了，再找地方擦乾。")),
        binding="cabinet", mode="bubbles", when=item("ch1_data_disk"))
    source.add("ch1_t_handoff_confirm", "F03", (("terminal", "請確認交付資料盤，接收完成後原盤由委託方保管。"),),
        binding="cabinet", when=all_of(flag("ledger_disk_obtained"), item("ch1_data_disk"), negate(flag("ch1_disk_delivered"))),
        options=(Option("deliver", "交付這片資料盤", "ch1_t_handoff_accept", "報酬800次晨核對；原盤交委託方保管。"),
                 Option("return", "先退出", None, "盤仍由你持有，不取得回執。")))
    source.add("ch1_t_handoff_accept", "F03", steps=[dict(do="world_action", id="handoff_insert"),
        say("terminal", "資料盤已接收，徽章與委託編號一致。驗收回執已建立。")], mode="animated",
        binding="cabinet", when=all_of(item("ch1_data_disk"), negate(flag("ch1_disk_delivered"))),
        completion=(transfer("ch1_data_disk", "dock_commission_cabinet"), set_flag("ch1_disk_delivered")),
        staging="明確交付才手放盤入有支撐插口；鎖聲一次。這一完成段尾原子移盤，先前動畫不落盤。")
    source.add("ch1_t_handoff_receipt_prompt", "F03", (("terminal", "原盤已接收，請取驗收回執。"),),
        binding="cabinet", when=all_of(flag("ch1_disk_delivered"), negate(flag("ch1_disk_receipt_taken"))),
        options=(Option("take", "取出驗收回執", "ch1_t_handoff_receipt", "取回執與電子副本，現在不領錢。"),
                 Option("return", "先退出", None, "原盤仍由櫃子保管，可以回來取紙。")))
    source.add("ch1_t_handoff_receipt", "F03", steps=[dict(do="world_action", id="handoff_take_paper"), *beats(
        ("lamp", "回執出來了，鷺姐明早替你對錢。我把電子副本也留著，雨別讓紙黏成一塊。"),
        ("rin", "盤交了，錢我明天再核。"))], binding="cabinet", mode="animated",
        when=all_of(flag("ch1_disk_delivered"), negate(flag("ch1_disk_receipt_taken"))),
        completion=(grant("ch1_delivery_receipt"), set_flag("ch1_disk_receipt_taken")),
        staging="紙捲伸出，凜取乾紙夾筆記。文件全文在背包，取紙段尾同存。")
    source.add("ch1_t_handoff_summary_prompt", "F03", (("lamp", "紙已拿到，還有缺附件那頁可以留。"),),
        binding="cabinet", when=all_of(flag("ch1_disk_receipt_taken"), negate(flag("ch1_market_summary_known"))),
        options=(Option("save", "保留可閱覽摘要", "ch1_t_handoff_summary", "保留批號M17與待查欄位，不代表已付或待付的判決。"),
                 Option("return", "先退出", None, "回執保留，可以回來存摘要。")))
    source.add("ch1_t_handoff_summary", "F03", (
        ("egret", "盤裡有一筆市場修繕代收沒付款附件。明早上屋頂再談，今晚先把取盤這筆做好。"),
        ("rin", "沒附件是沒付，還是收了沒記？"),
        ("egret", "現在只能說缺一張紙，不能替那個人認欠款。"),
        ("lamp", "這份摘要準你查批號，不是要你再去拿同一片盤。"),
        ("rin", "我留批號和缺的那欄，明早先領錢，再去找收據。"),
        ("egret", "旁邊有熱湯，你把紙收好，別把回執泡進去。"),
        ("rin", "我把帳夾裡面，湯放外面。")), binding="cabinet",
        when=all_of(flag("ch1_disk_delivered"), flag("ch1_disk_receipt_taken"), negate(flag("ch1_market_summary_known"))),
        completion=(grant("ch1_market_summary"), set_flag("ch1_market_summary_known"), set_flag("ch1_handoff_done")),
        staging="只顯完整待查摘要，沒有已付120答案或父女姓名。凜按紙角收筆記。")
    source.add("ch1_t_handoff_revisit", "F03", (("terminal", "驗收紀錄已保存，次晨到當舖核對報酬。"),
        ("egret", "今晚交的盤不會再算第二片，剩下的是明天的紙。")), binding="cabinet", when=flag("ch1_handoff_done"))


def _ali_meeting(source):
    source.add("ch1_b_lounge", "F04", (("ali", "想擦乾就進來，桌邊有乾布。"),),
        binding="ali_lounge", mode="bubbles", when=all_of(flag("ch1_handoff_done"), negate(flag("ch1_lounge_evening_done"))))
    variants = {
        "booth": (all_of(flag("ch1_first_death_done"), flag("ch1_booth_restoration_done")), (
            ("ali", "剛從電話亭回來嗎？你可以先把外套上的水擦掉。"),
            ("rin", "我後來在亭子醒過，最早那次是被送到診間。"),
            ("ali", "你想說最早那次，還是先吃一口熱的？"),
            ("rin", "先吃，盤已經交到外面的櫃了。"))),
        "clinic": (all_of(flag("ch1_first_death_done"), flag("ch1_true_death_record_known"), negate(flag("ch1_booth_restoration_done"))), (
            ("ali", "你手上是初次建檔的紙帶，診間送你出來了？"),
            ("rin", "灰衣人把我送過去，我醒來後走回倉庫，沒有在亭子醒過。"),
            ("ali", "那你這一路又走了一遍。先把紙帶收好，湯不用跟著趕。"),
            ("rin", "回執在本子裡，手上這張我也收。"))),
        "no_death": (all_of(flag("ch1_true_death_record_known"), flag("ch1_zero_true_deaths")), (
            ("ali", "外面下了一整夜，你是來等復原的人，還是自己路過？"),
            ("rin", "我是來交盤的，今天還沒用到復原。"),
            ("ali", "這裡也收沒復原過的客人。你想吃餐，還是只坐一下？"),
            ("rin", "我先看價目，坐著算完這筆。"))),
        "unknown": (negate(flag("ch1_true_death_record_known")), (
            ("ali", "外面下了一整夜，你想先歇一下嗎？"),
            ("rin", "我先歇一下，盤已經交了。"))),
    }
    for name, (condition, lines) in variants.items():
        source.add(f"ch1_t_ali_meet_{name}", "F04", lines, binding="ali_lounge",
            when=all_of(flag("ch1_handoff_done"), negate(flag("ch1_met_ali")), negate(flag("ch1_ali_reception_selected")), condition), next_scene="ch1_t_ali_1",
            staging="按實際服務事實挑一組問候；阿梨只知凜回答，不知錨人或戰鬥次數。")
    source.add("ch1_t_ali_1", "F04", (
        ("ali", "復原餐是一碗補身的熱湯，連肉和麵包是一百二十，酒八十。兩樣一起兩百，離店前再結。"),),
        binding="ali_lounge", when=all_of(flag("ch1_handoff_done"), negate(flag("ch1_met_ali")), negate(flag("ch1_ali_reception_selected"))),
        options=(Option("order", "湯和酒我都要，合計200", "ch1_t_ali_order", "現在不扣款，離店前可付清、保留欠條或接受今晚招待。"),
                 Option("sit", "先只坐一下", "ch1_t_ali_sit", "沒有餐酒訂單，不會欠200。"),
                 Option("return", "先返回", None, "不點餐、不扣款，可以再問。")),
        staging="菜單先放乾桌；價格與未結帳狀態公開。阿梨不端未點餐的碗。")
    source.add("ch1_t_ali_order", "F04", (("rin", "湯和酒我都要，兩百先記這一晚。"),
        ("ali", "好，等你離店前再一起結帳。今晚的麵不另外收錢。"), ("rin", "這邊留給碗，紙不要碰到湯。")),
        binding="ali_lounge", when=all_of(flag("ch1_handoff_done"), negate(flag("ch1_met_ali")), negate(flag("ch1_ali_reception_selected")), account("none")),
        completion=(transaction("ch1.revival_meal.order"), grant("ch1_lounge_bill"), set_flag("ch1_ali_reception_selected")), next_scene="ch1_t_ali_name",
        staging="真正訂單段尾事務成功才發明細，現在扣0；碗杯各一次。")
    source.add("ch1_t_ali_sit", "F04", (("rin", "我先只坐一下，不點餐。"),
        ("ali", "那就坐著休息吧，桌邊有乾布，不用先留飯錢。")), binding="ali_lounge",
        when=all_of(flag("ch1_handoff_done"), negate(flag("ch1_met_ali")), negate(flag("ch1_ali_reception_selected")), account("none")), completion=(set_flag("ch1_ali_reception_selected"),), next_scene="ch1_t_ali_name")
    source.add("ch1_t_ali_name", "F04", (("ali", "您怎麼稱呼？"), ("rin", "我叫凜。"),
        ("ali", "我叫阿梨，是梨子的梨。老人說別分梨吃，會把人分開。"),
        ("rin", "我把名字記著，梨我自己吃。")), binding="ali_lounge",
        when=all_of(flag("ch1_handoff_done"), flag("ch1_ali_reception_selected"), negate(flag("ch1_met_ali"))), completion=(set_flag("ch1_met_ali"),))


def _evening(source):
    waiting = all_of(flag("ch1_met_ali"), negate(flag("ch1_lounge_evening_done")))
    for ordered in (True, False):
        suffix = "ordered" if ordered else "sit"
        question = "這湯怎麼是甜的？" if ordered else "妳收鍋時還放梨？"
        response = "餐酒的兩百我記著，坐著的不用另開一張。" if ordered else "我只坐了一會兒，沒有餐酒這筆。"
        source.add(f"ch1_t_ali_2_{suffix}", "F05", (
            ("rin", question), ("ali", "梨放進去煮久一點，冷了也沒那麼澀。這是我以前學的做法。"),
            ("rin", "妳把湯留到這麼晚，也是工作？"), ("ali", "我也有下班的時候。今晚已經到了，不會把你坐多久都記成工錢。"),
            ("rin", response)), binding="ali_lounge", when=all_of(waiting, negate(flag("ch1_ali_evening_talk_done")), account("open200" if ordered else "none")),
            completion=(set_flag("ch1_ali_evening_talk_done"),), next_scene="ch1_t_ali_evening_close", staging="阿梨把胸牌放櫃邊；點餐者喝真正湯，未點者只看收鍋。")
    source.add("ch1_t_ali_evening_close", "F05", (
        ("ali", "外頭剩一碗麵，我下班後才吃。你想留下就一起，不想等也能先走。"),
        ("rin", "我到門口再決定，先把紙收好。")), binding="ali_lounge", when=all_of(waiting, flag("ch1_ali_evening_talk_done")),
        completion=(set_flag("ch1_lounge_evening_done"),),
        staging="阿梨收杯、到唯一攤位；館內不留第二個阿梨。沒有未選就塞麵。")
    source.add("ch1_t_ali_death_topic", "F05", (
        ("rin", "妳不問我今天怎麼死的？"), ("ali", "你想講的話我就聽著。你想先把湯喝完，我也不會替你補一個故事。"),
        ("rin", "先讓我喝完，明早還有帳。")), binding="ali_lounge",
        when=all_of(flag("ch1_met_ali"), flag("ch1_first_death_done"), account("open200")))
    source.add("ch1_t_ali_late_topic", "F05", (("rin", "妳不問我為什麼跑這麼晚？"),
        ("ali", "你想講才講，坐一下不需要先交代差事。")), binding="ali_lounge", when=flag("ch1_met_ali"))
    source.add("ch1_t_ali_evening_revisit", "F05", (("ali", "湯鍋我收了，麵在外頭，走不走你自己決定。"),),
        binding="ali_lounge", when=all_of(flag("ch1_lounge_evening_done"), negate(flag("ch1_supper_done"))))


def _supper_choice(source):
    undecided = all_of(flag("ch1_lounge_evening_done"), negate(flag("ch1_supper_done")), flag("ch1_supper_choice", "unset"))
    source.add("ch1_b_stall", "F06", (("ali", "這碗麵還熱，你要留下嗎？"),), binding="ali_stall", mode="bubbles", when=undecided)
    for ordered in (True, False):
        suffix = "ordered" if ordered else "none"
        account_line = ("今晚餐酒兩百，沒有另收陪坐或宵夜錢。你留下，這份我用今天的招待額度結。" if ordered
                        else "你今晚只坐了一會兒，沒有餐酒帳。想回家就回，麵還是我請的。")
        lines = [("ali", "你想先回家，還是留下吃一碗？麵是我請的，不加在餐酒那張。"),
                 ("rin", "我想先把今晚這張說清楚，明天那張另算。"), ("ali", account_line)]
        if ordered:
            lines.append(("ali", "你先走，可以付清，也可以把欠條留著。"))
        source.add(f"ch1_t_supper_choice_{suffix}", "F06", lines, binding="ali_stall",
            when=all_of(undecided, account("open200" if ordered else "none")), options=(
                Option("leave", "結清餐酒，先回家。" if ordered else "先回家，改天再聊。",
                       "ch1_t_supper_leave_options" if ordered else "ch1_t_supper_leave_none",
                       "確認支付200；不足可保留欠條。" if ordered else "沒有餐酒帳，不會扣款。",
                       intent=(set_flag("ch1_supper_choice", "leave"),)),
                Option("stay", "留下來吃一碗麵。", "ch1_t_supper_host_prompt" if ordered else "ch1_t_supper_host_none_prompt",
                       "接受阿梨今晚的一份餐酒招待；麵不收錢。" if ordered else "麵由阿梨請，沒有餐酒帳。",
                       intent=(set_flag("ch1_supper_choice", "stay"),)),
                Option("return", "先返回，讓我想一下。", None, "暫不作決定，可以再和阿梨說話。")),
            staging="空椅從攤後拉出、有實際支撐，阿梨不碰凜；原傘掛棚鉤。焦點不是預設結果。")


def _leave(source):
    unpaid_leave = all_of(flag("ch1_supper_choice", "leave"), negate(flag("ch1_supper_done")), account("open200"))
    back = Option("rechoose", "回去想一下", "ch1_t_supper_return", "還沒付款、簽欠條或接受招待，可以重選。", when=flag("ch1_supper_can_rechoose"))
    source.add("ch1_t_supper_leave_options", "F07", (
        ("rin", "餐點一百二十加上酒八十，今晚一共兩百。麵我就不吃了，我想先回家。"),
        ("ali", "你不用替那碗麵留錢，我留給自己。")), binding="ali_stall", when=unpaid_leave,
        options=(Option("pay", "確認支付200信用點", "ch1_t_supper_pay", "結清今晚餐酒並回家；不足額不扣款。"),
                 Option("defer", "保留200欠條，先回家", "ch1_t_supper_tab_confirm", "現在不扣款、不加息；之後主動付清。"), back),
        staging="只轉已點餐酒菜單；離開路不坐麵椅、不吃麵。")
    source.add("ch1_t_supper_pay", "F07", (("rin", "餐酒兩百，我先結這張，明天的回執另算。"),),
        binding="ali_stall", when=unpaid_leave,
        completion=(transaction("ch1.revival_meal.paid"), set_flag("ch1_supper_done")), next_scene="ch1_t_supper_paid_goodbye",
        staging="確認與段尾交易成功才扣200及supper_done；失敗轉不足額，不演已收到錢。")
    source.add("ch1_t_supper_paid_goodbye", "F07", (
        ("ali", "錢我收到了。回去別把濕紙放在爐邊烘，上面的字會掉。"), ("rin", "明天我要拿紙對錢，今晚先讓它乾。"),
        ("ali", "我下次還在這裡，你想喝湯再來。"), ("rin", "我記住這間店，不把下次也先答應了。")),
        binding="ali_stall", when=all_of(flag("ch1_supper_done"), account("paid200")))
    source.add("ch1_t_supper_insufficient", "F07", (
        ("rin", "我現在不夠兩百，不拿明天的錢當今天已經付了。"),
        ("ali", "那就先把帳留著，我不加利息。你也可以坐下來，今晚算我請客。")), binding="ali_stall", when=unpaid_leave,
        options=(Option("defer", "保留200欠條，先回家。", "ch1_t_supper_tab_confirm", "現在不扣款、不加息。"),
                 Option("stay", "回去選留下吃麵。", "ch1_t_supper_return", "回去重新決定，尚未接受招待。"),
                 Option("return", "先返回。", None, "維持未結帳，可再選。")))
    source.add("ch1_t_supper_tab_confirm", "F07", (("ali", "餐酒兩百，現在不扣款、不加息，之後你可以主動付清。"),),
        binding="ali_stall", when=unpaid_leave,
        options=(Option("confirm", "確認保留200欠條", "ch1_t_supper_tab", "欠條與委託回執分開，不從720報酬自動扣。"),
                 Option("return", "先返回", None, "不建立欠條、不扣款。")))
    source.add("ch1_t_supper_tab", "F07", (
        ("rin", "這張我自己記，不放進委託回執。"),
        ("ali", "你自己寫清楚就好，沒有復原服務替你簽這張。")), binding="ali_stall", when=unpaid_leave,
        completion=(transaction("ch1.revival_meal.tab"), grant("ch1_lounge_tab"), set_flag("ch1_supper_done")),
        next_scene="ch1_t_supper_tab_goodbye", staging="凜寫餐酒200未付，阿梨取副本；真欠條段尾同存，不扣現金。")
    source.add("ch1_t_supper_tab_goodbye", "F07", (("ali", "欠條我留著，今晚不會再加，你先回家。"),
        ("rin", "我記住這間店，不把下次也先答應了。")), binding="ali_stall", when=all_of(account("owed200"), flag("ch1_supper_done")))
    source.add("ch1_t_supper_leave_none", "F07", (
        ("rin", "我今晚只是坐一會兒，沒有點餐。我先回家，下次再來吃。"),
        ("ali", "那就沒有餐酒這張。門口地滑，走外側那塊乾板。"),
        ("ali", "我下次還在這裡，你想喝湯再來。"), ("rin", "我記住這間店，不把下次也先答應了。")),
        binding="ali_stall", when=all_of(flag("ch1_supper_choice", "leave"), account("none"), negate(flag("ch1_supper_done"))),
        completion=(set_flag("ch1_supper_done"),), staging="阿梨收空椅，沒有支付確認、欠條、麵或地址。")
    source.add("ch1_t_supper_return", "F06", (("rin", "我還沒答應留下，先回去想一下。"),
        ("ali", "那就先想，不用替我把話說完。")), binding="ali_stall", when=flag("ch1_supper_can_rechoose"),
        completion=(set_flag("ch1_supper_choice", "unset"),), staging="明確返回後恢復操作；不可逆結果發生後本場不可用。")
    for state, line in (("paid200", "今晚的兩百已經結了，麵是我的，你回家吧。"),
                        ("owed200", "欠條我留著，今晚不會再加，你先回家。"),
                        ("none", "你沒有點餐，不用為那張空椅留錢。")):
        source.add(f"ch1_t_supper_leave_revisit_{state}", "F07", (("ali", line),), binding="ali_stall",
            when=all_of(flag("ch1_supper_done"), flag("ch1_supper_choice", "leave"), account(state)))


def _stay(source):
    stay = all_of(flag("ch1_supper_choice", "stay"), negate(flag("ch1_supper_done")))
    for ordered in (True, False):
        suffix = "" if ordered else "_none"
        host_lines = (("rin", "我留下。麵是妳請，今晚那份也算妳請？"),
                      ("ali", "是我自己決定的一份，今晚還沒用。你不用把明天的報酬押給我。")) if ordered else (
                      ("rin", "我留下，麵就這一碗？"), ("ali", "還有湯，你想添再跟我說。"))
        source.add(f"ch1_t_supper_host{suffix}_prompt", "F08", host_lines, binding="ali_stall",
            when=all_of(stay, account("open200" if ordered else "none"), negate(flag("ch1_supper_host_accepted"))),
            options=(Option("accept", "接受今晚的招待" if ordered else "接受這碗麵", f"ch1_t_supper_stay_host{suffix}",
                            "餐酒由阿梨招待，不返現金；麵免費。" if ordered else "只接受麵，不生成餐酒帳。"),
                     Option("return", "回去想一下", "ch1_t_supper_return", "尚未接受招待，可回去重新決定。", when=flag("ch1_supper_can_rechoose"))))
        completion = ((transaction("ch1.revival_meal.gift"),) if ordered else ()) + (set_flag("ch1_supper_host_accepted"),)
        source.add(f"ch1_t_supper_stay_host{suffix}", "F08", (
            ("rin", "那我欠妳一碗麵，下次換我請。"), ("ali", "那就欠著，你願意下次再坐，我就留一張椅子。")),
            binding="ali_stall", when=all_of(stay, account("open200" if ordered else "none"), negate(flag("ch1_supper_host_accepted"))),
            completion=completion, next_scene="ch1_t_supper_stay_meal",
            staging="明確接受後阿梨在紙單寫當班招待；無訂單不造單。段尾事務gifted不增減現金。人情不是欠條。")
    source.add("ch1_t_supper_stay_meal", "F08", (
        ("rin", "麵裡也放梨，你不怕人只記得甜？"),
        ("ali", "有人記得甜就再來，有人嫌甜就告訴我。我想開自己的攤，得先有人願意說不好吃。"),
        ("rin", "這碗我吃完了，還沒找到不好吃的地方。")), binding="ali_stall",
        when=all_of(stay, flag("ch1_supper_host_accepted"), negate(flag("ch1_supper_meal_done"))),
        completion=(set_flag("ch1_supper_meal_done"),), next_scene="ch1_t_supper_stay_address",
        staging="凜自行選坐有支撐椅並吃真麵，固定演出≤8秒。無租攤成功或永久增益。")
    source.add("ch1_t_supper_stay_address", "F08", (
        ("ali", "我最近被收帳人盯上，去問租攤的事，也被叫回去對帳。"),
        ("rin", "他們要妳還多少？我明天也去市集查一張缺的收據。"),
        ("ali", "本金我認，已經付過的又被寫進去。那張我得自己看，不能聽誰說就再付。"),
        ("rin", "妳想我幫妳付，還是先看妳那張？"),
        ("ali", "今晚先不用替我做。你明天有委託，先把你的紙對完；我的事，我想清楚會自己說。"),
        ("rin", "妳收了攤，平常去哪裡？"),
        ("ali", "我住市集後樓三樓，從代收處旁的外梯上去。敲兩下再一下，我就知道是你。"),
        ("rin", "我把三樓和外梯記下，沒有答應今晚就去。"),
        ("ali", "我只是告訴你，不替你排明天。"),
        ("rin", "回執放委託那頁，妳的名字放後面，不寫價錢。"),
        ("ali", "這一頁留一點空，下次想說的事還裝得下。")), binding="ali_stall", mode="animated",
        when=all_of(stay, flag("ch1_supper_meal_done")),
        completion=(set_flag("knows_ali_address"), set_flag("sq1_first_supper_done"), set_flag("ch1_supper_done")),
        staging="地圖疊加短夜話，傘移到實掛鉤、凜放筆再記地址。資訊略後地址全文可讀；只在本段尾保存。")
    source.add("ch1_t_ali_4", "F08", (("ali", "麵吃完就先回家，明天的帳留給明天。"),),
        binding="ali_stall", when=all_of(flag("ch1_supper_done"), flag("ch1_supper_choice", "stay")))
    source.add("ch1_t_supper_stay_revisit", "F08", (("ali", "我住市集後樓三樓，外梯上去，兩下再一下；路你記著，今晚先回家。"),),
        binding="ali_stall", when=all_of(flag("ch1_supper_done"), flag("knows_ali_address"), flag("ch1_supper_choice", "stay")))


def _clinic_and_home(source):
    # Existing rig IDs, idle/walk and known stage geometry only.  New prop states
    # remain staging requirements for the owning stage/world implementation.
    # 初次建檔：舞台、坐姿與光影沿用已量測的診間演出（build_ch1_story 的 ch1_c09_wake），這裡只寫台詞。
    # 「歡迎回來」與「你的聲音跟電話亭很像」是燈與錄音聲線的伏筆（O03 支線會回頭問），保留原有日英文。
    clinic_steps = [
        say("rin", "幹，嘴裡全是金屬味。"),
        {"do": "wait", "time": 0.8},
        {**say("lamp", "歡迎回來。你死了十一分鐘。"), "ja": "おかえり。十一分、死んでたよ。", "en": "Welcome back. You were dead for eleven minutes.", "transcreate": True},
        say("rin", "誰把我送到這裡？我沒在這間診間登記。"),
        say("lamp", "灰衣人用貨車把你送來，裝備也放在臺邊。你是第一次復原，要先建檔。"),
        # 推近到凜的臉：她坐在檢查台上，鏡頭中心夠高才不會把頭與馬尾推進 21:9 黑邊（ST-22）。
        {"do": "camera", "pos": [316, 198], "zoom": 1.55, "time": 1.0},
        say("lamp", "備份能存你走過的地方，初次建檔是另一件事。這次完成後，下次才在登記的亭子醒來。"),
        {**say("rin", "你的聲音跟電話亭很像。"), "ja": "電話ボックスの声、お前に似てるな。", "en": "You sound like the phone booth.", "transcreate": True},
        say("lamp", "港區少年的聲音，長得都差不多吧。"),
        {"do": "camera", "pos": [316, 205], "zoom": 1.4, "time": 1.0},
        say("lamp", "初次建檔免信用點費，之後復原照登記費扣，記憶也會磨損。"),
        {"do": "fx", "kind": "noise", "time": 0.4},
        say("rin", "我以為保單連這個也算好了。"),
        say("lamp", "我只知道你這次登記能過，保單那頁得你自己留著。"),
        say("rin", "我先把裝備帶走，回去接著走。"),
    ]
    source.add("ch1_c09_wake", "O04", steps=clinic_steps, binding="first_clinic", mode="animated",
        when=all_of(flag("ch1_first_clinic_active"), negate(flag("ch1_first_death_done"))),
        completion=(set_flag("ch1_first_death_done"),),
        staging="真首次死亡建檔；裝備依持有袋保留，沒有不存在盤或回執。可選托盤菜單不鎖建檔。")
    # Correct backup question uses real registration; no new death counter.
    source.add("ch1_t_clinic_backup_registered", "O04", (("rin", "我在街角備份過，還不能直接回亭子？"),
        ("lamp", "初次建檔是另一件事，這次完成後才回登記的亭子。")), binding="first_clinic",
        when=all_of(flag("ch1_first_clinic_active"), flag("ch1_booth_registered")))
    source.add("ch1_t_clinic_backup_missing", "O04", (("rin", "我還沒登記亭子，下次要走回這裡？"),
        ("lamp", "完成建檔後登記電話亭，下次在登記的亭子醒來。")), binding="first_clinic",
        when=all_of(flag("ch1_first_clinic_active"), negate(flag("ch1_booth_registered"))))
    try:
        from . import kitchen_staging as kitchen
    except ImportError:
        import kitchen_staging as kitchen
    home_steps = [
        {"do": "scene", "id": "ch1_pawnshop_kitchen", "pos": [320, 240], "zoom": 0.8, "fade": 1.0,
         "props": {"kettle": {"pos": kitchen.STOVE, "state": "default"},
                   "stove_dial": {"angle": 0}, "stove_flame": {"visible": True}, "stove_heat": {"visible": True}}},
        {"do": "actor", "id": "rin", "kind": "rin", "pos": [575, 304], "facing": -1, "scale": 3.9, "pose": "idle", "layer": 1},
        {"do": "actor", "id": "k", "kind": "old_k", "speaker": "old_k", "pos": [145, 304], "facing": -1, "scale": 4.0, "pose": "idle", "layer": 0},
        {"do": "move", "id": "rin", "to": [330, 304], "time": 2.0, "wait": True, "then": "idle"},
        say("rin", "老 K，壺裡已經沒水了，我先把爐火關掉。"),
    ]
    home_steps.extend(kitchen.close_stove())
    home_steps.extend(beats(
        ("old_k", "你已經回來了啊，我本來想留一壺。"),
        ("rin", "我回來了，資料盤已經交出去，錢明早再核對。"), ("old_k", "八百那張有回執就收好，別拿來墊鍋喔。"),
        ("old_k", "這壺燒乾了，不能算水好了。我去裝，今晚不用等它再滾。")))
    home_steps.extend(kitchen.fill_kettle())
    home_steps.extend(beats(("old_k", "你什麼時候回來的？"), ("rin", "剛才，我站在這裡叫你關火。"),
        ("old_k", "我有聽見喔。明天先好好吃飯，再來對帳。"), ("rin", "飯留著，錢我明早再算。")))
    # 章末卡只由關卡結尾播一次（章節資訊的 end_title 與 teaser），這裡不再疊一張同樣的完成卡。
    home_steps.extend([{"do": "fade", "to": 1.0, "time": 1.0}])
    source.add("ch1_c14_home", "F09", steps=home_steps, binding="home", mode="animated",
        when=all_of(flag("ch1_supper_done"), flag("ch1_handoff_done"), negate(flag("ch1_home_done"))),
        completion=(set_flag("ch1_home_done"), set_flag("ch1_complete")),
        staging="凜真關爐、壺移耐熱墊；老K到現有水缸裝水。段尾爐關且壺有水未沸，乾杯不倒熱水。由正式舞台道具重建；物件不自行發故事結果。")
    source.add("ch1_t_home_revisit", "F09", (("old_k", "回執放乾的那格，飯在鍋裡，明早再算喔。"),),
        binding="home", when=flag("ch1_home_done"))


def _optional(source):
    source.add("ch1_t_egret_sunday_prompt", "O01", (("egret", "我今晚有自己的事，回執明早對。"),),
        binding="brief", when=all_of(flag("ch1_heard_brief"), negate(flag("asked_egret_sunday"))),
        options=(Option("ask", "問今晚與週日的事", "ch1_t_egret_sunday", "只問她願意說的，不影響取盤差事。", intent=(set_flag("ch1_sunday_accepted"),)),
                 Option("return", "先去做差事", None, "週日不接案不會鎖住主線。")))
    source.add("ch1_t_egret_sunday", "O01", (
        ("rin", "妳今晚不跟去，是又接了別張差事？"),
        ("egret", "今晚去看一個人，差事明天才算。週日我也不排活。"),
        ("rin", "每個週日都不排，這張表是誰替妳留的？"),
        ("egret", "我自己留的。有人肯讓我坐一會兒，不能每次坐到一半就接電話。"),
        ("rin", "那我明天找妳，不把週日也排進去。"),
        ("egret", "這句你記著，下次有價高的別又說很快就做完。"),
        ("egret", "茶喝掉，不然等你算完，又說熱的不是這杯。")), binding="brief",
        when=all_of(flag("ch1_heard_brief"), flag("ch1_sunday_accepted"), negate(flag("asked_egret_sunday"))),
        completion=(set_flag("asked_egret_sunday"),), staging="鷺收杯看錶，用杯擋紙角，不畫私人目的地、不提棠。")
    source.add("ch1_t_egret_sunday_revisit", "O01", (("egret", "週日我留給那個人，今天先把你的差事做完。"),),
        binding="brief", when=flag("asked_egret_sunday"))
    labels = {
        "watch": ("送貨員押來的懷錶。他說遲到二十分鐘會被罵，三年沒有贖回。", (
            ("rin", "錶都不走了，你還留二十分鐘？"), ("old_k", "他說明天來，我就留到明天喔。櫃子裡多一格，又不會趕人走。"))),
        "guitar": ("押來時已經沒有弦。主人說，彈的人不在了。", (
            ("rin", "沒有弦，也算一件樂器？"), ("old_k", "以前彈的人很大聲啦。我聽過，就不用再寫價錢告訴自己。"))),
        "raincoat": ("碼頭舊雨衣。主人說，這件曾替另一個人擋過水。", (
            ("rin", "這個袖口破了，水還是會進去。"), ("old_k", "那就先替它折好，別讓人穿上才發現。我沒說穿著就不會死喔。"))),
        "fare": ("船錢，留給回不來的人渡河用的。", (
            ("rin", "這罐也算在可賣的貨裡？"), ("old_k", "這個不賣。有人回不來，還是要留一筆給他走完路。"))),
    }
    for name, (label, dialogue) in labels.items():
        seen = f"ch1_label_{name}_seen"
        source.add(f"ch1_t_label_{name}", "O02", (("label", label),) + dialogue,
            binding=f"label_{name}", when=negate(flag(seen)), completion=(set_flag(seen),),
            staging="玩家主動讀此真物獨立標籤；腳在地、物不離架。標籤全文留日誌，不發物或硬幣。")
        source.add(f"ch1_t_label_{name}_revisit", "O02", (("label", label), ("old_k", "這件我留著，主人來了才好找。")),
            binding=f"label_{name}", when=flag(seen))
    label_flags = tuple(flag(f"ch1_label_{name}_seen") for name in labels)
    source.derived_flags["ch1_labels_started"] = any_of(*label_flags)
    source.derived_flags["sq8_first_labels_done"] = all_of(*label_flags)
    source.add("ch1_t_lamp_voice_prompt", "O03", (("lamp", "耳機我還接著，你想問什麼？"),),
        binding="voice", when=all_of(flag("ch1_recording_heard"), negate(flag("ch1_lamp_voice_asked"))),
        options=(Option("ask", "問燈為什麼像錄音", "ch1_t_lamp_voice_first", "記錄相似，不替錄音者填姓名。", intent=(set_flag("ch1_voice_accepted"),)),
                 Option("return", "先把路走完", None, "不影響當前主線，下次可再問。")))
    source.add("ch1_t_lamp_voice_first", "O03", (
        ("rin", "剛才錄音裡那個聲音跟你很像，你也替他們錄過？"),
        ("lamp", "我只在耳機裡陪你走，亭子播的是舊錄音。港區的喇叭本來都一樣難聽。"),
        ("rin", "你把我的耳機也罵進去了。"), ("lamp", "那顆喇叭真該換，我沒有改口。")), binding="voice",
        when=all_of(flag("ch1_recording_heard"), flag("ch1_voice_accepted"), negate(flag("ch1_lamp_voice_asked"))),
        completion=(set_flag("ch1_lamp_voice_asked"),), next_scene="ch1_t_lamp_voice_second_prompt")
    source.add("ch1_t_lamp_voice_second_prompt", "O03", (("lamp", "路線還接著，你要繼續問錄音？"),), binding="voice",
        when=all_of(flag("ch1_lamp_voice_asked"), negate(flag("sq5_lamp_voice_noticed"))),
        options=(Option("ask", "再問錄音是不是他", "ch1_t_lamp_voice_second", "他願不願意說，由他自己決定。"),
                 Option("later", "先不問", "ch1_t_lamp_voice_later", "保留第一次問過的線索，不算第二次答完。")))
    source.add("ch1_t_lamp_voice_second", "O03", (
        ("rin", "我不是問喇叭。我想知道，說歡迎回來的人是不是你。"),
        ("lamp", "以前的聲音不一定跟現在一樣，我現在不想說這段。你可以先把路走完。"),
        ("rin", "那我記相似，不替你寫答案。"), ("lamp", "這樣記就好，回執也別忘了。")), binding="voice",
        when=all_of(flag("ch1_lamp_voice_asked"), negate(flag("sq5_lamp_voice_noticed"))),
        completion=(set_flag("sq5_lamp_voice_noticed"),), staging="鍵聲停一拍；安全亭／診間真互動，不需要再死一次。")
    source.add("ch1_t_lamp_voice_later", "O03", (("rin", "路線先接著，我回頭再問聲音。"),
        ("lamp", "耳機我不掛，你走到下一盞燈再看。")), binding="voice", when=flag("ch1_lamp_voice_asked"))
    source.add("ch1_t_lamp_voice_revisit", "O03", (("lamp", "那段舊聲音我還沒想講，你記相似就好。"),),
        binding="voice", when=flag("sq5_lamp_voice_noticed"))
    real_clinic = all_of(flag("ch1_first_clinic_active"), flag("ch1_first_death_done"), negate(item("ch1_grey_cloth")))
    source.add("ch1_t_clinic_tray_prompt", "O04", (("lamp", "裝備在臺邊，茶杯放在托盤上。你想先看看，還是離開？"),),
        binding="first_clinic", when=real_clinic,
        options=(Option("look", "看杯邊的布角", "ch1_t_clinic_cloth_look", "查看真托盤，不在復原回放中取物。"),
                 Option("leave", "先離開診間", "ch1_t_clinic_cloth_leave", "不取布也能繼續主線。")))
    source.add("ch1_t_clinic_cloth_look", "O04", (("rin", "這杯還熱，杯邊怎麼壓了一塊布？"),
        ("lamp", "送你來的人留下的，診間的人只說他放完就走。")), binding="first_clinic", when=real_clinic,
        completion=(set_flag("ch1_grey_cloth_examined"),), next_scene="ch1_t_clinic_cloth_decide",
        staging="真托盤固定、杯旁壓灰布，不穿杯底；查看段只看、不給物。")
    source.add("ch1_t_clinic_cloth_decide", "O04", (("rin", "布角沒有名字，我要收起，還是留在這裡？"),),
        binding="first_clinic", when=all_of(real_clinic, flag("ch1_grey_cloth_examined")),
        options=(Option("take", "收起布角", "ch1_t_clinic_cloth_take", "實際挪杯收布；茶不拿走。"),
                 Option("leave", "留在托盤", "ch1_t_clinic_cloth_leave", "不取得物品，也不完成取布節點。")))
    source.add("ch1_t_clinic_cloth_take", "O04", (("rin", "布上沒有名字，我先把它收著，茶就留在這裡。"),
        ("lamp", "先讓它乾，不要跟濕紙夾一起。")), binding="first_clinic",
        when=all_of(real_clinic, flag("ch1_grey_cloth_examined")),
        completion=(grant("ch1_grey_cloth", "first_clinic"), set_flag("has_grey_cloth")),
        staging="凜挪杯到托盤另側、真取灰布；托盤world空側和held同一整輪事務保存，非回憶收藏發獎。")
    source.add("ch1_t_clinic_cloth_leave", "O04", (("rin", "我先不拿，杯子留這裡。"),
        ("lamp", "你要走就先穿好裝備，門口會有人指電話亭。")), binding="first_clinic", when=flag("ch1_first_clinic_active"))


def _quests(source):
    def step(title, complete_flag, binding):
        return QuestStep(title, complete_flag, binding)

    source.quests = [
        Quest("ch1_meet_egret", "main", "吃完飯，上屋頂找鷺", "鷺帶來碼頭的差事。老 K 已留晚飯，吃完再上屋頂聽簡報。", "聽完簡報即可出門，報酬在驗收後核對。", "ch1_heard_brief",
            (step("回廚房吃老 K 這次免收的晚飯", "ch1_dinner_done", "dinner"), step("上屋頂聽鷺的完整簡報", "ch1_heard_brief", "brief"))),
        Quest("ch1_take_disk", "main", "到碼頭倉庫取回資料盤", "鷺要保險箱裡的一片盤，市集今晚封路，燈帶你走碼頭。", "取得後到復原館外交接櫃驗收。", "ledger_disk_obtained",
            (step("清開街道前往碼頭的路障", "ch1_street_route_open", "street_clear"), step("擊倒看門狗，打開倉庫隔牆", "watchdog_defeated", "watchdog"),
             step("實際開水閘，確認浮橋路保持", "ch1_flood_gate_open", "flood"), step("打開保險箱，取出資料盤", "ledger_disk_obtained", "disk_pickup")),
            ("ch1_heard_brief",), ("ch1_heard_brief",), "還沒聽完差事。", "上屋頂找鷺，聽完回程安排。", completion_requires_steps=True),
        Quest("ch1_handoff_disk", "main", "把資料盤交到館外交接櫃", "鷺安排上層出口接復原館。櫃子收盤後留回執，明早憑它核對錢。", "保留回執與待查摘要；800報酬次晨另算。", "ch1_handoff_done",
            (step("走上層回程，到館外櫃確認交盤", "ch1_disk_delivered", "cabinet"), step("從交接櫃取出驗收回執", "ch1_disk_receipt_taken", "cabinet"),
             step("保留市場M17待查摘要", "ch1_handoff_done", "cabinet")), ("ledger_disk_obtained",), ("ledger_disk_obtained",), "還沒有取到實體資料盤。", "回保險箱取盤；已交盤可在櫃子補印回執。"),
        Quest("ch1_close_evening", "main", "和阿梨說好今晚的去留", "盤已驗收。阿梨下班邀你吃麵，你可以留下或把帳說清楚先走。", "兩種決定都能回家；地址只在實際告知後記下。", "ch1_supper_done",
            (step("進復原館，和吧臺的阿梨說話", "ch1_met_ali", "ali_lounge"), step("聽阿梨說下班後的邀請", "ch1_lounge_evening_done", "ali_lounge"),
             step("到麵攤決定去留，說清楚今晚帳", "ch1_supper_done", "ali_stall")), ("ch1_handoff_done",), ("ch1_handoff_done",), "今晚的去留還沒說好。", "到麵攤說話；沒有錢也能保留欠條。"),
        Quest("ch1_go_home", "main", "回當舖，把回執收好", "今晚的事已經說好，明早要對報酬。先回家，老 K 還等著燒水。", "完成第一章，下一步是次晨核對回執。", "ch1_complete",
            (step("從麵攤回當舖，和老 K 說話", "ch1_home_done", "home"), step("把回執收好，結束今晚", "ch1_complete", "home")),
            ("ch1_supper_done",), ("ch1_supper_done",), "今晚的事還沒說清楚。", "和阿梨說好去留；不需要先取得地址。"),
        Quest("ch1_next_morning", "main", "明早核對回執與市集附件", "原盤已交，摘要顯示代收缺付款附件。鷺約好明早核對800報酬與80抽成。", "淨額720只在次晨確認後入帳。", "ch2_previous_job_settled",
            (step("次晨在當舖核對交盤回執與報酬", "ch2_previous_job_settled", "next_morning"),), ("ch1_complete",), ("ch1_complete",), "這個版本尚未包含第二章。", "第一章進度已保存；待正式第二章入口繼續。"),
        Quest("sq8_ch1_labels", "side", "讀老 K 留下的四張標籤", "貨架上有沒賣出的舊物，老 K 還記得它們在等誰。", "收錄四件標籤，物品仍留在當舖。", "sq8_first_labels_done",
            tuple(step(f"讀{label}的標籤", f"ch1_label_{name}_seen", f"label_{name}") for name, label in (("watch", "懷錶"), ("guitar", "吉他"), ("raincoat", "雨衣"), ("fare", "船錢罐"))), ("ch1_labels_started",)),
        Quest("sq2_ch1_sunday", "side", "問鷺為什麼留著週日", "她今晚不跟去，週日也不排差事。你可以問，也可以讓她留著自己的事。", "記下週日不接案，不提前知道她見誰。", "asked_egret_sunday",
            (step("在屋頂問鷺今晚與週日的事", "asked_egret_sunday", "brief"),), ("ch1_sunday_accepted",), ("ch1_heard_brief",), "還沒有聽差事。", "先聽簡報，之後可選擇追問。"),
        Quest("sq5_ch1_voice", "side", "問燈為什麼像電話亭錄音", "亭子裡的舊聲音與耳機裡的燈相似。相似不等於知道錄音者。", "記錄聲音線索，答案尚未確認。", "sq5_lamp_voice_noticed",
            (step("聽真實電話亭錄音後問燈", "ch1_lamp_voice_asked", "voice"), step("再問錄音是否是他，或先保留", "sq5_lamp_voice_noticed", "voice")),
            ("ch1_voice_accepted",), ("ch1_recording_heard",), "還沒有實際聽過亭子錄音。", "在安全電話亭聽錄音，不需要再死一次。"),
        Quest("sq6_ch1_cloth", "side", "看看診間茶杯邊的灰布", "送凜來的人留下熱茶，布角沒有名字。你可以收起，也可以留下。", "實際收起後保留灰布，不自動知道送來的人。", "has_grey_cloth",
            (step("初次建檔時查看托盤，選擇收布", "has_grey_cloth", "first_clinic"),), ("ch1_grey_cloth_examined",)),
        Quest("sq1_ch1_supper", "side", "留下吃麵，聽阿梨說自己的事", "阿梨下班邀你吃麵。接受之前不用替她還債，也不用替她作明天的決定。", "實際告知後，把住處與暗號記進本子。", "sq1_first_supper_done",
            (step("明確接受阿梨的邀請並吃麵", "ch1_supper_meal_done", "ali_stall"), step("聽她說完夜話，把實地址記下", "sq1_first_supper_done", "ali_stall")), ("ch1_lounge_evening_done",)),
    ]


def build_source() -> ProductionSource:
    source = ProductionSource()
    source.speakers = {
        "terminal": {"name": "交接櫃", "color": "#9ad7ff", "portrait": "res://art/portraits/system.png", "formal": True},
        "label": {"name": "標籤", "color": "#ded5b0", "portrait": "res://art/portraits/system.png", "formal": True},
    }
    _bindings(source)
    _documents(source)
    _transactions(source)
    _opening(source)
    _handoff(source)
    _ali_meeting(source)
    _evening(source)
    _supper_choice(source)
    _leave(source)
    _stay(source)
    _clinic_and_home(source)
    _optional(source)
    _quests(source)
    return source


NATIVE_STEPS = frozenset({"scene", "letterbox", "camera", "actor", "pose", "move", "face", "remove", "say", "narrate", "title", "fx", "sfx", "wait", "fade", "transition", "end", "reach", "prop", "prop_move", "prop_hold", "prop_release", "prop_visible", "world_action"})
CAPABILITIES = frozenset({
    "scene_preconditions_v1", "explicit_decisions_v1", "whole_scene_atomic_results_v1",
    "canonical_account_predicates_v1", "manual_item_transfer_v1",
    "resolved_interaction_bindings_v1", "quest_nonmap_targets_v1",
    "truthful_restoration_facts_v1", "safe_scene_continuation_v1", "atomic_world_item_results_v1",
})


def _condition_flags(expression):
    if not isinstance(expression, dict) or not expression:
        return []
    if "flag" in expression:
        return [expression["flag"]]
    if "not" in expression:
        return _condition_flags(expression["not"])
    return [name for key in ("all", "any") for child in expression.get(key, []) for name in _condition_flags(child)]


def _condition_receipts(expression):
    if not isinstance(expression, dict) or not expression:
        return []
    if "receipt" in expression:
        return [expression["receipt"]]
    if "not" in expression:
        return _condition_receipts(expression["not"])
    return [name for key in ("all", "any") for child in expression.get(key, []) for name in _condition_receipts(child)]


def _condition_errors(expression, where):
    if not isinstance(expression, dict):
        return [f"{where}: condition must be a dictionary"]
    if not expression:
        return []
    if set(expression) == {"flag", "equals"} and isinstance(expression["flag"], str) and expression["flag"]:
        return []
    if set(expression) == {"account", "equals"} and expression["account"] == "ch1_lounge" and expression["equals"] in {"none", "open200", "paid200", "owed200", "gifted200"}:
        return []
    if set(expression) == {"item"} and expression["item"] in {"ch1_data_disk", "ch1_grey_cloth", "ch1_delivery_receipt", "ch1_market_summary"}:
        return []
    if set(expression) == {"receipt", "status"} and isinstance(expression["receipt"], str) and expression["receipt"].startswith("ch1.") and expression["status"] == "recorded":
        return []
    if set(expression) == {"not"}:
        return _condition_errors(expression["not"], where + ".not")
    for key in ("all", "any"):
        if set(expression) == {key} and isinstance(expression[key], list) and expression[key]:
            return [problem for i, child in enumerate(expression[key]) for problem in _condition_errors(child, f"{where}.{key}[{i}]")]
    return [f"{where}: unknown/invalid condition {expression!r}; never treat as eligible"]


def validate_source(source: ProductionSource) -> list[str]:
    """Meaningful CPU source checks; not StoryLint, engine or save/load tests."""
    problems = []
    producers = source.producer_index()
    sections = {segment.section for segment in source.segments.values()}
    required = {f"F{i:02}" for i in range(1, 10)} | {f"O{i:02}" for i in range(1, 5)}
    if not required.issubset(sections):
        problems.append(f"missing approved script sections: {sorted(required - sections)}")
    if len(source.quests) != 11 or sum(q.kind == "main" for q in source.quests) != 6:
        problems.append("approved quest semantics must contain six main plus five side quests")
    known_items = {"ch1_data_disk", "ch1_grey_cloth"} | set(source.documents)
    for segment in source.segments.values():
        where = segment.id
        if segment.binding not in source.bindings:
            problems.append(f"{where}: unresolved author binding id {segment.binding}")
        problems.extend(_condition_errors(segment.when, where))
        for name in _condition_receipts(segment.when):
            if name not in source.transactions:
                problems.append(f"{where}: receipt {name} has no canonical resource")
        references = _condition_flags(segment.when)
        spoken = [entry for entry in segment.steps if entry.get("do") == "say"]
        limit = {"radio": 2, "bubbles": 4, "dialogue": 8, "animated": 16}.get(segment.mode)
        if limit is None or len(spoken) > limit:
            problems.append(f"{where}: {len(spoken)} lines exceeds {segment.mode} limit {limit}")
        for index, entry in enumerate(segment.steps):
            if entry.get("do") not in NATIVE_STEPS:
                problems.append(f"{where}.steps[{index}]: unknown presentation handler {entry.get('do')}")
            if entry.get("do") == "say":
                maximum = 30 if segment.mode == "bubbles" else 56
                if not entry.get("text") or len(entry["text"]) > maximum:
                    problems.append(f"{where}.steps[{index}]: text exceeds {maximum} characters")
                if entry.get("speaker") not in {"rin", "old_k", "egret", "lamp", "ali", "terminal", "label"}:
                    problems.append(f"{where}.steps[{index}]: unknown speaker")
        targets = [segment.next_scene] if segment.next_scene else []
        if segment.options and not 2 <= len(segment.options) <= 4:
            problems.append(f"{where}: decisions require two to four explicit choices")
        if len({option.id for option in segment.options}) != len(segment.options):
            problems.append(f"{where}: duplicate option id")
        for option in segment.options:
            if not option.text or len(option.text) > 56 or not option.explanation:
                problems.append(f"{where}/{option.id}: missing or oversized choice text")
            if option.target:
                targets.append(option.target)
            references.extend(_condition_flags(option.when))
            problems.extend(_condition_errors(option.when, f"{where}/{option.id}"))
            for name in _condition_receipts(option.when):
                if name not in source.transactions:
                    problems.append(f"{where}/{option.id}: unknown receipt {name}")
            for operation in option.intent:
                if operation.get("kind") != "flag" or operation.get("id") not in {"ch1_supper_choice", "ch1_sunday_accepted", "ch1_voice_accepted"}:
                    problems.append(f"{where}/{option.id}: irreversible result incorrectly stored as choice intent")
        for target in targets:
            if target not in source.segments:
                problems.append(f"{where}: next/option target {target} missing")
        for operation in segment.completion:
            kind, ident = operation.get("kind"), operation.get("id")
            if kind == "flag":
                if ident == "ch2_previous_job_settled":
                    problems.append(f"{where}: chapter1 cannot settle chapter2 job")
            elif kind == "transaction":
                if ident not in source.transactions:
                    problems.append(f"{where}: transaction {ident} not registered in source")
                elif source.transactions[ident]["caller"] != "chapter1":
                    problems.append(f"{where}: chapter1 invokes later/chapter2 transaction {ident}")
            elif kind in {"item_acquire", "item_transfer"}:
                if ident not in known_items:
                    problems.append(f"{where}: unknown item {ident}")
                if kind == "item_acquire" and ident == "ch1_data_disk":
                    problems.append(f"{where}: real disk must originate at world pickup, never scene reward")
                if operation.get("source_binding") not in (None, *source.bindings):
                    problems.append(f"{where}: unknown physical item source binding")
                if kind == "item_acquire" and ident == "ch1_grey_cloth" and operation.get("source_binding") != "first_clinic":
                    problems.append(f"{where}: gray cloth requires real clinic tray consumption")
            else:
                problems.append(f"{where}: unknown completion operation {kind}")
        for name in references:
            if name not in producers:
                problems.append(f"{where}: flag {name} has no declared producer")
    for name, condition in source.derived_flags.items():
        problems.extend(_condition_errors(condition, f"derived:{name}"))
        for dependency in _condition_flags(condition):
            if dependency not in producers or dependency == name:
                problems.append(f"derived:{name}: unresolved/self-dependent producer {dependency}")
        for dependency in _condition_receipts(condition):
            if dependency not in source.transactions:
                problems.append(f"derived:{name}: unknown canonical receipt {dependency}")
    quest_ids = set()
    for quest in source.quests:
        if quest.id in quest_ids:
            problems.append(f"{quest.id}: duplicate quest")
        quest_ids.add(quest.id)
        if len(quest.title) > 16 or not quest.title or quest.kind not in {"main", "side"}:
            problems.append(f"{quest.id}: title/kind budget invalid")
        if not quest.background or not quest.reward or not quest.steps:
            problems.append(f"{quest.id}: missing complete player-facing quest description")
        if quest.requires_flags and (not quest.blocked_reason or not quest.suggestion):
            problems.append(f"{quest.id}: no blocked explanation/suggestion")
        names = [quest.complete_flag, *quest.visible_flags, *quest.requires_flags]
        for step in quest.steps:
            names.append(step.complete_flag)
            if not step.title or len(step.title) > 28 or step.binding not in source.bindings:
                problems.append(f"{quest.id}: invalid step title/binding {step.title}")
        for name in names:
            if name not in producers:
                problems.append(f"{quest.id}: missing flag producer {name}")
    for name, document in source.documents.items():
        if not all(document.get(key) for key in ("name", "description", "body", "icon")) or len(document["body"]) > 220:
            problems.append(f"{name}: incomplete/oversized StoryItemData text")
    for name, definition in source.transactions.items():
        if not definition.get("resource", "").startswith("res://data/story_transactions/") or not name.startswith("ch1."):
            problems.append(f"{name}: missing canonical NE-231 resource reference")
        if any(key in definition for key in ("cash_delta", "credits_delta", "from", "to", "wallet", "receipt")):
            problems.append(f"{name}: duplicate monetary/receipt truth in authoring registry")
        for status, scene in definition.get("on_failure", {}).items():
            if status != "insufficient_credits" or scene not in source.segments:
                problems.append(f"{name}: unsupported failure status/scene {status}/{scene}")
    return problems


class ProductionNotReady(RuntimeError):
    pass


class ProductionBackend(Protocol):
    """Implement once the real runtime owners hand over their tested interfaces.

    No CLI switch accepts pretend capabilities or fixture locations.  A verified
    backend must compile predicates/results/decisions and report actual producer
    and interaction bindings for continuity/navigation review.
    """
    def capabilities(self) -> set[str]: ...
    def binding_errors(self, source: ProductionSource) -> list[str]: ...
    def compile_story(self, source: ProductionSource, base_document: dict) -> dict: ...


def compile_production(source: ProductionSource, backend: ProductionBackend | None = None, base_document: dict | None = None) -> dict:
    errors = validate_source(source)
    if errors:
        raise ValueError("\n".join(errors))
    missing = CAPABILITIES - (backend.capabilities() if backend is not None else set())
    if missing:
        raise ProductionNotReady("Formal export refused: runtime backend missing " + ", ".join(sorted(missing)))
    errors = backend.binding_errors(source)
    if errors:
        raise ProductionNotReady("Formal export refused: " + "\n".join(errors))
    if base_document is None:
        raise ProductionNotReady("Formal export refused: retained chapter presentation source missing")
    # Returning a dictionary is not publishing it.  The integration owner must
    # validate generated engine JSON before the CLI writes the loaded path.
    return backend.compile_story(source, base_document)


def source_report(source: ProductionSource) -> dict:
    errors = validate_source(source)
    script_path = Path(__file__).resolve().parents[2] / SCRIPT
    return {
        "author_source": SCRIPT,
        "author_source_sha256": hashlib.sha256(script_path.read_bytes()).hexdigest(),
        "entry_contract": ENTRY_CONTRACT,
        "sections": sorted({s.section for s in source.segments.values()}),
        "segments": len(source.segments), "explicit_decision_segments": sum(bool(s.options) for s in source.segments.values()),
        "quest_semantics": len(source.quests), "published_quests": 0,
        "producer_index": source.producer_index(), "source_errors": errors,
        "result_producers": source.result_producer_index(), "account_receipt_projections": ACCOUNT_RECEIPTS,
        "runtime_backend_required": sorted(CAPABILITIES),
        "pending_bindings": {name: binding.pending for name, binding in source.bindings.items() if binding.pending},
        "unlocated_semantics": [q.id for q in source.quests if any(source.bindings[s.binding].location_candidate is None for s in q.steps)],
        "runtime_verified": False,
    }

