#!/usr/bin/env python3
"""Compile the first playable Chapter Six route to the broadcast relay yard."""

from pathlib import Path
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/level"))

from build_ch6 import CHAPTER, POINTS, REQUEST, WITNESS  # noqa: E402
from build_ch1_story import sfx  # noqa: E402
from ch6_control_station_story import add_control_station  # noqa: E402
from ch6_relay_water_story import add_relay_water  # noqa: E402
from ch6_rain_route_story import add_rain_route  # noqa: E402
from ch6_studio_trial import PEOPLE  # noqa: E402
from ch6_studio_trial_story import add_studio_trial  # noqa: E402
from ch1_closure import Binding, Option, ProductionSource, Quest, QuestStep, all_of, flag, negate, say, set_flag  # noqa: E402
from chapter_compiler import ChapterSpec, write_chapter  # noqa: E402


CHAPTER_INFO = {
    "id": CHAPTER,
    "title": "第六章　斷錨",
    "subtitle": "港區・廣播站",
    "end_title": "第六章　斷錨　完",
    "teaser": "下一章　日照",
}
GAUGE = "ch6_yard_gauge_read"
OFFER = "ch6_t_offer_approach"
AGREEMENT = "ch6_t_confirm_approach"
GAUGE_READ = "ch6_t_read_yard_gauge"


def build_spec():
    source = ProductionSource(flag_defaults={})
    source.speakers["su"] = {"name": "蘇", "name_en": "Wake", "name_ja": "蘇", "color": "#a9d4cf",
                             "portrait": "res://art/portraits/su.png", "formal": True}
    source.bindings.update({
        name: Binding("npc" if name in PEOPLE else "object", CHAPTER, f"res://data/npcs/ch6_{name}.tres") for name in POINTS
    })
    dispatch = {
        "plaza_intercom": ["ch6_t_approach_revisit", OFFER, "ch6_t_wait_for_request"],
        "relay_signal": ["ch6_t_read_line_status"],
        "yard_gauge": ["ch6_t_yard_gauge_revisit", GAUGE_READ],
    }
    ready = all_of(flag(REQUEST), negate(flag(WITNESS)))
    source.add("ch6_t_wait_for_request", "6.01", (
        ("label", "廣場喇叭在待機。先用電話亭聯絡燈。"),
    ), when=negate(flag(REQUEST)))
    source.add(OFFER, "6.01", (
        ("su", "我是蘇，負責這裡的播報。妳到橋頭等白燈亮，我請人把高架放下來。"),
        ("rin", "原帳在我這裡。到前庭再核對哪些能播。從貨梯過去嗎？"),
    ), when=ready, options=(
        Option("follow", "從貨梯上高架。", AGREEMENT, "打開廣場的維修貨梯。"),
        Option("leave", "先留在廣場。", None, "稍後可以再接入喇叭。"),
    ), cancel_choice_on_back=True)
    source.add(AGREEMENT, "6.01", steps=(
        say("su", "高架放下了。看貨梯門上的白燈。高處能看線路，下面也通往前庭。"),
        sfx("switch", -22.0),
    ), when=ready, mode="animated", completion=(set_flag(WITNESS),), cancel_on_skip=True)
    source.add("ch6_t_approach_revisit", "6.01", (
        ("su", "白燈還亮著。到前庭先看水位尺。"),
    ), when=flag(WITNESS), mode="animated")
    source.add("ch6_t_read_line_status", "6.01", (
        ("label", "前庭還沒送電。帶電的街側線路和備用中繼分開標著。"),
    ), mode="animated")
    source.add(GAUGE_READ, "6.01", (
        ("rin", "水已經淹過第一格，泵房的指示燈還沒亮。"),
    ), when=all_of(flag(WITNESS), negate(flag(GAUGE))), mode="animated",
        completion=(set_flag(GAUGE),), cancel_on_skip=True)
    source.add("ch6_t_yard_gauge_revisit", "6.01", (
        ("label", "刻針還在白線上。回程出口在高架坡道腳下。"),
    ), when=flag(GAUGE), mode="animated")
    source.quests.append(Quest(
        "ch6_approach_relay", "main", "從港區廣場到中繼站",
        "燈已轉告公開帳本的請託。蘇在廣場的喇叭等凜。",
        "已到中繼站前庭，確認水位。",
        GAUGE,
        (QuestStep("用廣場的喇叭向蘇確認維修路線。", WITNESS, "plaza_intercom"),
         QuestStep("從高架進前庭，查看水位尺。", GAUGE, "yard_gauge")),
        visible_flags=(REQUEST,), completion_requires_steps=True,
    ))
    add_relay_water(source, dispatch, GAUGE)
    add_studio_trial(source, dispatch, REQUEST)
    add_control_station(source, dispatch, REQUEST)
    add_rain_route(source, dispatch)
    return ChapterSpec(CHAPTER_INFO, source, "ch6", dispatch, POINTS)


if __name__ == "__main__":
    missing = write_chapter(build_spec(), ROOT / f"data/story/{CHAPTER}.json")
    raise SystemExit(int(bool(missing)))
