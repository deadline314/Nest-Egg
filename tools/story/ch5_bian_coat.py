"""5.05 exposes the name only at the physical coat, after confirming the reading."""

from ch1_closure import Binding, Quest, QuestStep, all_of, flag, item, negate, set_flag
from ch5_alley_layout import LOCK
from ch5_stair_layout import COAT, COAT_KNOWN

READ = "ch5_t_read_bian_coat"
READ_WITH_CLOTH = "ch5_t_read_bian_coat_with_cloth"


def install(source, dispatch, chapter):
    source.bindings[COAT] = Binding("object", chapter, f"res://data/npcs/ch5_{COAT}.tres")
    dispatch[COAT] = ["ch5_t_revisit_bian_coat", READ_WITH_CLOTH, READ]
    lines = (
        ("rin", "外套裡縫著必安。旁邊的收件章，和阿梨留下的那枚一樣。"),
        ("rin", "他把外套留在梯口，手上的委託到這裡就結束了。"),
    )
    ready = all_of(flag(LOCK), negate(flag(COAT_KNOWN)))
    cloth = item("ch1_grey_cloth")
    source.add(READ, "5.05", lines, when=all_of(ready, negate(cloth)), mode="animated",
               cancel_on_skip=True, completion=(set_flag(COAT_KNOWN),))
    source.add(READ_WITH_CLOTH, "5.05", (*lines,
        ("rin", "我帶來的灰布也有同一道補縫。我先把布角收好。"),
    ), when=all_of(ready, cloth), mode="animated", cancel_on_skip=True, completion=(set_flag(COAT_KNOWN),))
    source.add("ch5_t_revisit_bian_coat", "5.05", (
        ("rin", "必安把灰外套留在這裡。我可以下樓了。"),
    ), when=flag(COAT_KNOWN), mode="animated")
    source.quests.append(Quest(
        "ch5_basement_avoidance", "main", "繞過灰衣人，查看梯口的外套",
        "下層可直接閃避，上層維修架可以跨過繩圈與圍堵。",
        "從衣領辨認灰衣人，打開地下室的入口。", COAT_KNOWN,
        (QuestStep("躲過搬運，等灰衣人走開再查看外套。", COAT_KNOWN, COAT),),
        visible_flags=(LOCK,),
    ))
