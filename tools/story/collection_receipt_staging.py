"""Contact cues for the original S06 payment receipt."""

from build_ch1_story import move
from rent_window_staging import ART, PAPER_PATH, PAPER_POINT, PAPER_STATE, STAMP_BASE, STAMP_GRIP


PAPER = "collection_paid_receipt"
STAMP = "collection_receipt_stamp"
MARK = "collection_receipt_mark"
# Widths on the existing stage, normalized from the 96- and 49-pixel sources.
PAPER_SCALE = 19.0 / 96
STAMP_SCALE = 18.0 / 49
HAND_CONTACT = [79.5, 37.5]


def _scaled_point(origin, point, scale):
    return [start + offset * scale for start, offset in zip(origin, point)]


def scene(desk, clerk_x, clerk_floor):
    # The paper and stamp sit on the ledger side of the actual desk plane.
    paper_edge = _scaled_point(desk["pos"], [86, 70], desk["scale"])
    stamp_surface = _scaled_point(desk["pos"], [192, 62], desk["scale"])
    paper_pos = [paper_edge[0], paper_edge[1] - PAPER_STATE["material_bottom_pixel_centre"] * PAPER_SCALE]
    rest_pos = [xy - pixel * STAMP_SCALE for xy, pixel in zip(stamp_surface, STAMP_BASE)]
    paper_contact = _scaled_point(paper_pos, PAPER_POINT, PAPER_SCALE)
    palm = _scaled_point(rest_pos, STAMP_GRIP, STAMP_SCALE)
    press = [xy - (base - grip) * STAMP_SCALE for xy, base, grip in zip(paper_contact, STAMP_BASE, STAMP_GRIP)]
    lift = [press[0], press[1] - 6.0]
    layers = (
        dict(kind="sprite", id=PAPER, path=PAPER_PATH, pos=paper_pos, scale=PAPER_SCALE,
             source_width=96, filter="linear", depth="front", visible=False, glow=False, lighting="physical"),
        dict(kind="sprite", id=MARK, path=ART + "contract_mark.png", pos=[0, 0], scale=PAPER_SCALE,
             source_width=96, filter="linear", depth="front", parent_prop=PAPER, anchor=[0, 0], visible=False),
        dict(kind="sprite", id=STAMP, path=ART + "stamp.png", pos=rest_pos, scale=STAMP_SCALE,
             source_width=49, filter="linear", depth="front", visible=False, glow=False, lighting="physical"),
    )
    reach = dict(do="reach", id="vig", hand="front", contact=HAND_CONTACT, angle=1.7, time=0.26, wait=True)
    steps = (
        dict(do="prop_visible", id=PAPER, visible=True),
        dict(do="prop_visible", id=STAMP, visible=True),
        move("vig", clerk_x - 18, clerk_floor, t=0.34),
        dict(reach, space="prop", prop=STAMP, to=STAMP_GRIP),
        dict(do="prop_hold", id=STAMP, actor="vig", hand="front", point=STAMP_GRIP),
        dict(reach, to=lift),
        dict(reach, to=press, time=0.17),
        dict(do="sfx", id="mat_wood", volume=-12.0, jitter=0.0),
        dict(do="prop_visible", id=MARK, visible=True),
        dict(do="wait", time=0.2),
        dict(reach, to=lift, time=0.16),
        dict(reach, to=palm),
        dict(do="prop_release", id=STAMP),
        dict(do="reach", id="vig", hand="front", release=True, time=0.26, wait=True),
        move("vig", clerk_x, clerk_floor, t=0.34),
        dict(do="face", id="vig", dir=-1),
    )
    return layers, steps
