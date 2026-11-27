"""Scene 6.05 only writes a consent-aware result at an actual arrival source."""

from ch1_closure import Option, Quest, QuestStep, all_of, flag, negate, set_flag
from ch6_control_station_story import DECIDED
from ch6_rain_route import ARRIVED, DOOR, KNOWN, ON_TIME, PORCH, RELAYED, START

NORMAL = "ch6_t_ali_run_arm"
GUIDED = "ch6_t_ali_guide_arm"
EARLY = "ch6_t_ali_at_eaves"
PORCH_CHOICE = "ch6_t_ali_porch_choice"
PROTECT = "ch6_t_ali_protective_arrival"


def add_rain_route(source, dispatch):
    relay = all_of(flag(DECIDED), flag(RELAYED))
    pending = all_of(relay, negate(flag(ARRIVED)))
    knows = flag(KNOWN)
    early = flag(ON_TIME)
    dry = all_of(pending, knows)
    settled = all_of(relay, flag(ARRIVED))

    dispatch[START] = ["ch6_t_ali_lane_revisit", "ch6_t_ali_routes_known", "ch6_t_ali_routes_public"]
    source.add("ch6_t_ali_routes_public", "6.05", (
        ("rin", "我還不知道是哪一戶。沿亮著燈的外街找屋號。"),
    ), when=all_of(pending, negate(knows)), mode="animated")
    source.add("ch6_t_ali_routes_known", "6.05", (
        ("rin", "代收處旁的外梯通到三樓。要從粉筆箭頭旁上去，還是先走外街？"),
    ), when=dry, options=(
        Option("run", "從乾台跑到便門", NORMAL, "站上起跑踏板才計時。"),
        Option("guide", "沿箭頭慢慢走", GUIDED, "走同一條乾台，有較多時間。"),
        Option("leave", "先走亮著燈的外街", None, "外街仍能到門廊。"),
    ), cancel_choice_on_back=True)
    source.add(NORMAL, "6.05", (
        ("label", "從粉筆箭頭旁踏上乾台，站穩再往三樓便門走。"),
    ), when=dry, mode="animated", cancel_on_skip=True)
    source.add(GUIDED, "6.05", (
        ("label", "先找粉筆箭頭，再沿有扶手的踏板上樓。較長的計時從站穩後開始。"),
    ), when=dry, mode="animated", cancel_on_skip=True)
    source.add("ch6_t_ali_lane_revisit", "6.05", (
        ("label", "門廊的回覆已收到。可以從市集路口繞回去。"),
    ), when=settled, mode="animated")

    dispatch[DOOR] = [EARLY]
    source.add(EARLY, "6.05", (
        ("rin", "我在樓梯下。妳想讓我陪妳走到哪裡？"),
        ("ali", "先陪我到亮的路口。我自己拿傘。"),
    ), when=dry, mode="animated",
        completion=(set_flag(ON_TIME), set_flag(ARRIVED)), cancel_on_skip=True)

    source.speakers["porch_neighbor"] = {"name":"鄰居", "name_en":"Neighbor", "name_ja":"近所の人",
                                        "color":"#d5c991", "portrait":"res://art/portraits/system.png", "formal":True}
    dispatch[PORCH] = ["ch6_t_ali_porch_early", "ch6_t_ali_porch_protective", PORCH_CHOICE]
    source.add(PORCH_CHOICE, "6.05", (
        ("label", "鄰居在門燈下等著，手上有阿梨留下的傘。要聽她轉話嗎？"),
    ), when=pending, options=(
        Option("hear", "聽鄰居轉話", PROTECT, "確認外街這一路的回覆。"),
        Option("leave", "先離開門廊", None, "可以回屋簷路標重試。"),
    ), cancel_choice_on_back=True)
    source.add(PROTECT, "6.05", (
        ("porch_neighbor", "她走的時候留了這把傘。她想先安靜一下。"),
        ("rin", "等她想見人，我再來。傘留在她找得到的地方。"),
    ), when=pending, mode="animated",
        completion=(set_flag(ON_TIME, False), set_flag(ARRIVED)), cancel_on_skip=True)
    source.add("ch6_t_ali_porch_early", "6.05", (
        ("label", "阿梨自己拿著傘，往亮著燈的路口走。後門已經打開。"),
    ), when=all_of(settled, early), mode="animated")
    source.add("ch6_t_ali_porch_protective", "6.05", (
        ("label", "傘留在門燈下。阿梨會自己決定何時見人，後門可以走。"),
    ), when=all_of(settled, negate(early)), mode="animated")

    source.quests.append(Quest(
        "ch6_ali_rain_route", "main", "沿雨巷找阿梨",
        "燈把電話接給凜。從前庭去市集外街，沿路找熟悉的屋號。",
        "收到門廊的回覆，可以沿市集路口返回。", ARRIVED,
        (QuestStep("到市集外街照路標前進。", ARRIVED, START),),
        visible_flags=(RELAYED,), requires_flags=(DECIDED,),
        blocked_reason="尚未在控制室確認轉接。", suggestion="回到控制台，確認是否轉接來電。",
        completion_requires_steps=True,
    ))
