"""S11 的三份證據副本，沿用已驗證的紙張貼圖與凜的握點。"""
from __future__ import annotations

from guest_ticket_staging import PATH, PAPER_POINT, SOURCE_WIDTH, STATES
from market_pass_staging import RIN_HAND


DESK_TOP = 215.0
RIN_X = 210.0
PAPER_SCALE = 0.20
PAPERS = (("s11_contract_copy", 220.0), ("s11_interest_receipt", 234.0), ("s11_collection_copy", 248.0))


def layers() -> tuple[dict, ...]:
    return tuple(
        dict(kind="sprite", id=paper, path=PATH, source_width=SOURCE_WIDTH,
             pos=[RIN_X - 9.0 + x - PAPERS[0][1], 223.0], scale=PAPER_SCALE, filter="linear",
             visible=False, depth="back",
             states={state["id"]: dict(path="res://" + state["path"]) for state in STATES})
        for paper, x in PAPERS
    )


def place_papers(floor: float) -> tuple[dict, ...]:
    steps = []
    for index, (paper, x) in enumerate(PAPERS):
        if index:
            steps.append(dict(do="move", id="rin", to=[RIN_X + x - PAPERS[0][1], floor],
                              time=0.32, pose="walk", then="idle", wait=True))
        contact_x = x + PAPER_POINT[0] * PAPER_SCALE
        steps.extend((
            dict(do="reach", id="rin", hand="front", space="prop", prop=paper, to=PAPER_POINT,
                 contact=RIN_HAND, time=0.21, wait=True),
            dict(do="prop_visible", id=paper, visible=True),
            dict(do="prop_hold", id=paper, actor="rin", hand="front", point=PAPER_POINT, follow_rotation=False),
            dict(do="reach", id="rin", hand="front", to=[contact_x, DESK_TOP - 18.0],
                 contact=RIN_HAND, time=0.29, wait=True),
        ))
        for state in STATES:
            bottom_offset = (state["material_bottom_pixel_centre"] - PAPER_POINT[1]) * PAPER_SCALE
            steps.extend((
                dict(do="prop", id=paper, state=state["id"]),
                dict(do="reach", id="rin", hand="front", to=[contact_x, DESK_TOP - bottom_offset],
                     contact=RIN_HAND, time=0.06, wait=True),
            ))
        steps.extend((dict(do="prop_release", id=paper),
                      dict(do="reach", id="rin", hand="front", release=True, time=0.22, wait=True)))
    steps.extend((dict(do="move", id="rin", to=[RIN_X, floor], time=0.54, pose="walk", then="idle", wait=True),
                  dict(do="face", id="rin", dir=1)))
    return tuple(steps)
