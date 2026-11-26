"""Durable service steps for scene 6.02, from high gauge to safe backup power."""

from build_ch1_story import sfx
from ch1_closure import Option, Quest, QuestStep, all_of, flag, negate, say, set_flag
from ch6_relay_water import DIVERTED, DRAINED, POWERED


def add_relay_water(source, dispatch, gauge):
    gauge_read = flag(gauge)
    divided = flag(DIVERTED)
    lowered = flag(DRAINED)
    powered = flag(POWERED)
    missing_gauge = "ch6_t_relay_need_gauge"
    source.add(missing_gauge, "6.02", (
        ("label", "先到前庭水位尺確認目前的刻度。"),
    ), when=negate(gauge_read), mode="animated")

    dispatch["yard_gauge"].insert(0, "ch6_t_yard_gauge_safe")
    source.add("ch6_t_yard_gauge_safe", "6.02", (
        ("rin", "刻針已降到白線下，可以接上備援電源。"),
    ), when=all_of(gauge_read, lowered), mode="animated")

    dispatch["relay_diverter"] = [missing_gauge, "ch6_t_diverter_revisit", "ch6_t_relay_divert"]
    source.add("ch6_t_diverter_revisit", "6.02", (
        ("label", "雨槽已分流到外槽。退水控制盒在泵房第一階。"),
    ), when=divided, mode="animated")
    source.add("ch6_t_relay_divert", "6.02", steps=(
        say("su", "先把屋簷的雨水引到外槽，泵房才能退水。"),
        dict(do="world_action", id="ch6_turn_diverter"),
        sfx("switch", -14),
        say("label", "分流刻針已轉到底。可以操作泵房的退水盒。"),
    ), when=all_of(gauge_read, negate(divided)), mode="animated",
       completion=(set_flag(DIVERTED),), cancel_on_skip=True)

    dispatch["relay_drain"] = [missing_gauge, "ch6_t_drain_need_diversion",
                               "ch6_t_drain_revisit", "ch6_t_relay_drain"]
    source.add("ch6_t_drain_need_diversion", "6.02", (
        ("label", "雨水還往泵房流。先轉水位尺旁的分流手輪。"),
    ), when=negate(divided), mode="animated")
    source.add("ch6_t_drain_revisit", "6.02", (
        ("label", "刻針已降到白線下。備援箱在上層乾台。"),
    ), when=lowered, mode="animated")
    source.add("ch6_t_relay_drain", "6.02", steps=(
        dict(do="world_action", id="ch6_press_drain"),
        sfx("switch", -15),
        say("rin", "水位往下退了。到白線以下，備援箱才會放行。"),
    ), when=all_of(gauge_read, divided, negate(lowered)), mode="animated",
       completion=(set_flag(DRAINED),), cancel_on_skip=True)

    ready = all_of(gauge_read, divided, lowered, negate(powered))
    dispatch["relay_backup"] = [missing_gauge, "ch6_t_drain_need_diversion", "ch6_t_backup_need_drain",
                                "ch6_t_backup_revisit", "ch6_t_choose_backup"]
    source.add("ch6_t_backup_need_drain", "6.02", (
        ("label", "水位還在白線上。先操作階梯旁的退水控制盒。"),
    ), when=negate(lowered), mode="animated")
    source.add("ch6_t_backup_revisit", "6.02", (
        ("label", "備援自檢完成。錄音室入口在乾台右側的地面。"),
    ), when=powered, mode="animated")
    source.add("ch6_t_choose_backup", "6.02", (
        ("label", "水位已低於白線。是否接通錄音室的備援電源？"),
    ), when=ready, options=(
        Option("connect", "接通備援電源", "ch6_t_relay_connect", "通過自檢後開錄音室。"),
        Option("leave", "先離開電源箱", None, "可以回來接電。"),
    ), cancel_choice_on_back=True)
    source.add("ch6_t_relay_connect", "6.02", steps=(
        dict(do="world_action", id="ch6_press_backup"),
        sfx("switch", -12),
        say("label", "中繼器自檢通過。錄音室可開門，麥克風仍在待機。"),
    ), when=ready, mode="animated", completion=(set_flag(POWERED),), cancel_on_skip=True)

    source.quests.append(Quest(
        "ch6_relay_water", "main", "恢復廣播站的中繼電力",
        "先把屋簷雨槽分流，等刻針落到白線下，再接上備援電源。",
        "可以從前庭進錄音室。", POWERED,
        (QuestStep("在水位尺旁轉動分流手輪。", DIVERTED, "relay_diverter"),
         QuestStep("到泵房第一階退水。", DRAINED, "relay_drain"),
         QuestStep("到上層乾台接通備援。", POWERED, "relay_backup")),
        visible_flags=(gauge,), completion_requires_steps=True,
    ))
