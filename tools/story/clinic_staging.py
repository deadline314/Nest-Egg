"""Finite first-clinic contact props. Source pixels are immutable atlas coordinates.

The real seated rig was measured before choosing these points. Presentation
never grants items; Story's existing death-owned result boundary does that.
"""
from math import pi

ATLAS = "res://art/environment/scene_props/revival_room_contacts/clinic_atlas.png"
SOURCE_WIDTH = 1254
BED_Y = 194.0
TRAY_X = 340.0
TRAY_WIDTH = 80.0
TRAY_SCALE = TRAY_WIDTH / 1097.0
TRAY_SOURCE_FOOT_Y = 663.0
TRAY_SOURCE_SURFACE_Y = 393.0
SURFACE_Y = BED_Y + (TRAY_SOURCE_SURFACE_Y - TRAY_SOURCE_FOOT_Y) * TRAY_SCALE
CUP_GRIP = [162, 858]
CUP_BASE_Y = 1090.0
CUP_SCALE = 6.4 / (CUP_BASE_Y - CUP_GRIP[1])
CUP_PICKUP = [330.0, SURFACE_Y - 6.4]
CUP_ASIDE = [343.0, CUP_PICKUP[1]]
CLOTH_GRIP = [704, 967]
CLOTH_SCALE = 15.0 / 510.0
CLOTH_SUPPORT = [710, 1055]
CLOTH_PICKUP = [326.0, SURFACE_Y + (CLOTH_GRIP[1] - CLOTH_SUPPORT[1]) * CLOTH_SCALE]
POCKET = [315.0, 168.0]


def layers():
    shared = dict(kind="sprite", path=ATLAS, source_width=SOURCE_WIDTH,
                  filter="linear", glow=False, modulate="#b4c6d4")
    return [
        dict(shared, id="clinic_tray", region=[67,232,1121,445], pivot=[560.5,431],
             pos=[TRAY_X,BED_Y], scale=TRAY_SCALE, support="exam_table"),
        dict(shared, id="clinic_cloth", region=[655,790,534,356],
             pivot=[CLOTH_SUPPORT[0]-655,CLOTH_SUPPORT[1]-790],
             pos=[CLOTH_PICKUP[0]-(CLOTH_GRIP[0]-CLOTH_SUPPORT[0])*CLOTH_SCALE,SURFACE_Y],
             scale=CLOTH_SCALE, support="clinic_tray"),
        dict(shared, id="clinic_cup", region=[131,776,396,328], pivot=[198,CUP_BASE_Y-776],
             pos=[CUP_PICKUP[0]-(CUP_GRIP[0]-329)*CUP_SCALE,SURFACE_Y],
             scale=CUP_SCALE, support="clinic_tray"),
    ]


def furniture():
    # Explicit measured H-based bounds; all props rest on existing supports.
    cup_x = CUP_PICKUP[0]-(CUP_GRIP[0]-329)*CUP_SCALE
    cloth_left = CLOTH_PICKUP[0]+(667-CLOTH_GRIP[0])*CLOTH_SCALE
    return [
        dict(id="clinic_tray",kind="bed_tray",rect=[TRAY_X-TRAY_WIDTH/2,BED_Y-419*TRAY_SCALE,TRAY_WIDTH,421*TRAY_SCALE],support=True),
        dict(id="clinic_cup",kind="cup",rect=[cup_x-186*CUP_SCALE,SURFACE_Y-303*CUP_SCALE,372*CUP_SCALE,304*CUP_SCALE],support=True),
        dict(id="clinic_cloth",kind="cloth_corner",rect=[cloth_left,SURFACE_Y+(802-CLOTH_SUPPORT[1])*CLOTH_SCALE,510*CLOTH_SCALE,332*CLOTH_SCALE],support=True),
    ]


def actions():
    def reach(hand, **fields):
        return dict(do="reach",id="rin",hand=hand,**fields)
    return [
        reach("back",space="prop",prop="clinic_cup",to=CUP_GRIP,angle=pi/6,time=.3,grip=True),
        dict(do="prop_hold",id="clinic_cup",actor="rin",hand="back",point=CUP_GRIP,follow_rotation=False),
        reach("back",to=[CUP_PICKUP[0],CUP_PICKUP[1]-3],angle=pi/6,time=.18),
        reach("back",to=[CUP_ASIDE[0],CUP_ASIDE[1]-3],angle=pi/6,time=.32),
        reach("back",to=CUP_ASIDE,angle=pi/6,time=.22),
        dict(do="prop_release",id="clinic_cup"),
        reach("back",release=True,time=.25),
        reach("front",space="prop",prop="clinic_cloth",to=CLOTH_GRIP,angle=pi/2,time=.3,grip=True),
        dict(do="prop_hold",id="clinic_cloth",actor="rin",hand="front",point=CLOTH_GRIP,follow_rotation=True),
        reach("front",to=[CLOTH_PICKUP[0],CLOTH_PICKUP[1]-4],angle=pi/2,time=.2),
        reach("front",to=POCKET,angle=0,time=.35),
        dict(do="wait",time=.15),
        dict(do="prop_visible",id="clinic_cloth",visible=False),
        dict(do="prop_release",id="clinic_cloth"),
        reach("front",release=True,time=.3),
        dict(do="wait",time=.15),
    ]
