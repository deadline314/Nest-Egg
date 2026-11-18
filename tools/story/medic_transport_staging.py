"""S13：救護護送、維修鑰匙保管及兩名成年搬運者的真接觸表演。"""
from __future__ import annotations
from build_ch1_story import actor

ART='res://art/environment/scene_props/ch2_medic_transport/'
PREFIX='ch2_medic_transport__'
FLOOR=296.0
SCALE=1.9
BED='transport_stretcher'
UMBRELLA='egret_broken_umbrella'
BAG='egret_equipment_bag'
KEY='medic_maintenance_key'
LOCK='medic_pause_lock'
PANEL='family_exit_panel'
BED_SCALE=150.0/545.0
BED_Y=FLOOR-226.5*BED_SCALE
BED_IN=[510.0,BED_Y]
BED_REST=[350.0,BED_Y]
BED_LEFT_GRIP=[18.5,8.5]
BED_RIGHT_GRIP=[518.5,28.5]
MATTRESS_Y=BED_Y+59.5*BED_SCALE
GROUND_PATIENT=[280.0,302.63]
BED_PATIENT=[440.0,MATTRESS_Y+6.63]
CARRY_PATIENT=[440.0,247.25]
DOOR_SCALE=145.0/456.0
DOOR_POS=[540.0,FLOOR-456*DOOR_SCALE]
PANEL_POS=[DOOR_POS[0]+32*DOOR_SCALE,DOOR_POS[1]+44*DOOR_SCALE]
PANEL_GRIP=[104.5,190.5]
PANEL_OPEN=[PANEL_POS[0]-70,PANEL_POS[1]]
BOX_SCALE=58.0/480.0
BOX_POS=[508.0,203.0]
LOCK_POINT=[531.0,229.0]
LOCK_SCALE=.14
KEY_SCALE=.13
UMBRELLA_SCALE=110.0/364.0
UMBRELLA_GRIP=[177.5,226.5]

def point(pos,p,scale):return [pos[i]+p[i]*scale for i in range(2)]
def sprite(name,prop_id,pos,scale,*,visible=True,front=False,**extra):
    width={'stretcher':545,'restraint':14,'equipment_bag':76,'broken_umbrella':364,'pause_box':243,'pause_lock':56,'maintenance_key':36,'exit_frame':271,'exit_panel':206,'exit_sill':300}[name]
    support={'pause_box':'帳房右側實牆支架','pause_lock':'牆上隔離箱暫停閂','maintenance_key':'醫護掌心/制服腰袋','restraint':'搬送床框的固定束帶','equipment_bag':'搬送床側框','exit_panel':'固定門框內滑門導軌'}
    if name in support:extra['support']=support[name]
    return dict(kind='sprite',id=prop_id,path=ART+PREFIX+name+'.png',pos=pos,scale=scale,source_width=width,filter='linear',glow=False,visible=visible,depth='front' if front else 'back',lighting='physical',**extra)

def layers():
    return (
        sprite('pause_box','medic_side_box',BOX_POS,BOX_SCALE),
        sprite('pause_lock',LOCK,[LOCK_POINT[0]-28.5*LOCK_SCALE,LOCK_POINT[1]-8.5*LOCK_SCALE],LOCK_SCALE,visible=False,front=True),
        sprite('maintenance_key',KEY,[531,250],KEY_SCALE,visible=False,front=True),
        sprite('exit_frame','family_exit_frame',DOOR_POS,DOOR_SCALE,front=True),
        sprite('exit_panel',PANEL,PANEL_POS,DOOR_SCALE),
        sprite('exit_sill','family_exit_sill',[DOOR_POS[0],FLOOR],86.0/300.0,front=True),
        sprite('stretcher',BED,BED_IN,BED_SCALE,visible=False),
        sprite('restraint','transport_strap_chest',[0,0],.225,visible=False,front=True,parent_prop=BED,anchor=[170.0,0.0],pivot=[0,10*BED_SCALE/.225]),
        sprite('restraint','transport_strap_hips',[0,0],.225,visible=False,front=True,parent_prop=BED,anchor=[285.0,0.0],pivot=[0,10*BED_SCALE/.225]),
        sprite('equipment_bag',BAG,[0,0],.2,visible=False,front=True,parent_prop=BED,anchor=[390.0,120.0]),
        sprite('broken_umbrella',UMBRELLA,[550,FLOOR-247.5*UMBRELLA_SCALE],UMBRELLA_SCALE,visible=False,front=True),
    )

def hand_point(kind):
    # 綁定開手掌的既有不透明中心，不生成或疊加新手。
    points={'ch2_greycoat':[75.5,48.5],'ch2_medic':[43.5,47.5],'rin':[96.5,37.5]}
    return points[kind]

def reach(who,kind,*,to=None,hand='front',prop=None,target_actor=None,part=None,time=.45,wait=True,release=False,angle=0.0,**extra):
    result=dict(do='reach',id=who,hand=hand,time=time,wait=wait,**extra)
    if release:result['release']=True;return result
    result.update(contact=hand_point(kind),angle=angle)
    if to is not None:result['to']=to
    if prop is not None:result.update(space='prop',prop=prop)
    if target_actor is not None:result.update(space='part',target_actor=target_actor,part=part)
    return result

def move(who,to,time=1.0,*,pose='walk',then='idle',wait=True,reason=None,support=None):
    step=dict(do='move',id=who,to=to,time=time,pose=pose,then=then,wait=wait)
    if pose in ['crouch','dead'] or then in ['crouch','dead']:
        step.update(pose_reason=reason or '搬運中保持受傷成人的既有臥姿。',pose_support=support or '由兩名成年搬運者的掌心、擔架墊與綁帶承重；不把蹲姿當臥姿。')
    return step

def medic_opening(*,keep):
    steps=[actor('medic','ch2_medic',522,FLOOR,facing=-1,scale=SCALE,speaker='medic',weapon='')]
    if keep:
        lock_grip=[28.5,8.5]
        key_grip=[8.5,12.5] # 原鑰匙環的實心金屬邊，不取透明環心或齒尖。
        steps += [
            dict(do='prop_move',id=LOCK,to=[522-lock_grip[0]*LOCK_SCALE,226-lock_grip[1]*LOCK_SCALE],time=0),
            dict(do='prop_visible',id=LOCK,visible=True),
            reach('medic','ch2_medic',prop=LOCK,to=lock_grip),
            dict(do='prop_hold',id=LOCK,actor='medic',hand='front',point=lock_grip,follow_rotation=False),
            reach('medic','ch2_medic',to=LOCK_POINT),dict(do='prop_release',id=LOCK),
            dict(do='sfx',id='mat_metal',volume=-14,jitter=0),dict(do='wait',time=.25),
            dict(do='prop_move',id=KEY,to=[LOCK_POINT[0]-key_grip[0]*KEY_SCALE,LOCK_POINT[1]-key_grip[1]*KEY_SCALE],time=0),
            dict(do='prop_visible',id=KEY,visible=True),reach('medic','ch2_medic',prop=KEY,to=key_grip),
            dict(do='prop_hold',id=KEY,actor='medic',hand='front',point=key_grip,follow_rotation=True),
            reach('medic','ch2_medic',to=LOCK_POINT,angle=1.5707963267948966,time=.3),dict(do='wait',time=.2),
            reach('medic','ch2_medic',to=LOCK_POINT,angle=0,time=.3),
            reach('medic','ch2_medic',target_actor='medic',part='pelvis',to=[150.5,40.5]),
            dict(do='prop_visible',id=KEY,visible=False),dict(do='prop_release',id=KEY),
            reach('medic','ch2_medic',release=True),
        ]
    return tuple(steps)

def escort_steps(route):
    # 選擇/旗標仍由原段落完成契約負責，這裡只讓成人帶家屬走實際出口。
    steps=[move('medic',[565,FLOOR],.7),reach('medic','ch2_medic',prop=PANEL,to=PANEL_GRIP),
           dict(do='prop_move',id=PANEL,to=PANEL_OPEN,time=.65,wait=False),move('medic',[505,FLOOR],.65),reach('medic','ch2_medic',release=True),
           move('medic',[670,FLOOR],2.6,wait=False),move('xiaowei',[640,FLOOR],2.6,wait=False)]
    if route=='keep':steps.append(move('yong',[600,FLOOR],2.6,wait=False))
    steps += [dict(do='wait',time=2.7),dict(do='remove',id='medic'),dict(do='remove',id='xiaowei')]
    if route=='keep':steps.append(dict(do='remove',id='yong'))
    return tuple(steps)

def fall_opening():
    return (dict(do='pose',id='egret',pose='dead',pose_reason='鷺在成人戰區受傷後倒在地上，與玩家HP/死亡UI無關。',pose_support='完整臥姿的衣料/身體底面落於帳房地板y296。'),dict(do='wait',time=.7))

def loading_steps():
    return (
        dict(do='prop_visible',id=BED,visible=True),
        actor('porter_front','ch2_greycoat/transport',500,FLOOR,facing=-1,scale=SCALE,speaker='',weapon=''),
        actor('porter_rear','ch2_medic/transport',652,FLOOR,facing=-1,scale=SCALE*.96,speaker='',weapon=''),
        reach('porter_front','ch2_greycoat',prop=BED,to=BED_LEFT_GRIP),
        dict(do='prop_hold',id=BED,actor='porter_front',hand='front',point=BED_LEFT_GRIP,follow_rotation=False),
        reach('porter_rear','ch2_medic',prop=BED,to=BED_RIGHT_GRIP),
        move('porter_front',[340,FLOOR],2.5,wait=False),move('porter_rear',[492,FLOOR],2.5),
        dict(do='prop_release',id=BED),reach('porter_front','ch2_greycoat',release=True,wait=False),reach('porter_rear','ch2_medic',release=True),
        move('porter_front',[255.5,FLOOR],1.2,wait=False),move('porter_rear',[329,FLOOR],1.9),
        dict(do='pose',id='porter_front',pose='crouch',pose_reason='成年搬運者以既有單膝跪接口托住肩背，準備放上擔架。',pose_support='後膝及前腳踩實帳房地板y296。'),
        dict(do='pose',id='porter_rear',pose='crouch',pose_reason='單膝跪下托住受傷成人雙腿，不把病患留在地上。',pose_support='後膝及前腳踩實帳房地板y296。'),
        dict(do='wait',time=1.0),
        reach('porter_front','ch2_greycoat',target_actor='egret',part='torso',to=[90.5,218.5]),
        reach('porter_rear','ch2_medic',target_actor='egret',part='leg_front_lower',to=[4.5,95.5],angle=-1.5707963267948966),
        move('egret',[GROUND_PATIENT[0],CARRY_PATIENT[1]],1.0,pose='dead',then='dead'),
        dict(do='pose',id='porter_front',pose='idle'),move('porter_rear',[308,FLOOR],.25),dict(do='wait',time=.4),
        move('porter_front',[415.5,FLOOR],3,wait=False),move('porter_rear',[468,FLOOR],3,wait=False),
        move('egret',CARRY_PATIENT,3,pose='dead',then='dead'),
        dict(do='pose',id='porter_front',pose='squat',pose_reason='兩人彎膝把鷺平放到擔架墊，保持背與腿的掌心承重。',pose_support='雙腳仍貼地板y296，待床墊接觸後才收手。'),
        dict(do='pose',id='porter_rear',pose='squat',pose_reason='配合另一端降低搬運高度。',pose_support='雙腳貼地板y296。'),dict(do='wait',time=.5),
        move('egret',BED_PATIENT,.7,pose='dead',then='dead'),
        reach('porter_front','ch2_greycoat',release=True,wait=False),reach('porter_rear','ch2_medic',release=True),
        dict(do='pose',id='porter_front',pose='idle'),dict(do='pose',id='porter_rear',pose='idle'),dict(do='wait',time=.6),
        move('porter_front',[405,FLOOR],.5),
        reach('porter_front','ch2_greycoat',prop='transport_strap_chest',to=[7.5,15.5]),
        dict(do='prop_visible',id='transport_strap_chest',visible=True),dict(do='sfx',id='mat_metal',volume=-18,jitter=0),
        reach('porter_front','ch2_greycoat',release=True),move('porter_front',[430,FLOOR],.5),
        reach('porter_front','ch2_greycoat',prop='transport_strap_hips',to=[7.5,15.5]),dict(do='prop_visible',id='transport_strap_hips',visible=True),reach('porter_front','ch2_greycoat',release=True),
        move('porter_front',[440,FLOOR],.8),dict(do='pose',id='porter_front',pose='crouch',pose_reason='低身檢查擔架側掛裝備袋。',pose_support='後膝與前腳支撐於地板y296。'),dict(do='wait',time=1.0),
        dict(do='prop_visible',id=BAG,visible=True),reach('porter_front','ch2_greycoat',prop=BAG,to=[38.5,10.5]),reach('porter_front','ch2_greycoat',release=True),dict(do='pose',id='porter_front',pose='idle'),
        move('rin',[565,FLOOR],3.0),reach('rin','rin',prop=PANEL,to=PANEL_GRIP),dict(do='prop_move',id=PANEL,to=PANEL_OPEN,time=.65,wait=False),move('rin',[505,FLOOR],.65),
        dict(do='pose',id='porter_front',pose='listen'),
    )

def transport_tail():
    return (
        reach('rin','rin',release=True),move('rin',[700,FLOOR],2.8,wait=False),
        dict(do='wait',time=5.5), # 既有listen頭部反應；原生另量點頭，不把指令本身當通過。
        dict(do='prop_visible',id=UMBRELLA,visible=True),
        move('porter_rear',[575,FLOOR],1.5),dict(do='pose',id='porter_rear',pose='crouch',pose_reason='取回靠在安全出口門框的破傘。',pose_support='後膝與前腳固定於地板y296。'),dict(do='wait',time=1.0),
        reach('porter_rear','ch2_medic',hand='back',prop=UMBRELLA,to=UMBRELLA_GRIP),
        dict(do='prop_hold',id=UMBRELLA,actor='porter_rear',hand='back',point=UMBRELLA_GRIP,follow_rotation=False),
        reach('porter_rear','ch2_medic',hand='back',target_actor='porter_rear',part='head',to=[77.5,122.5]),dict(do='pose',id='porter_rear',pose='idle'),dict(do='wait',time=.8),
        reach('porter_rear','ch2_medic',hand='back',target_actor='porter_rear',part='head',to=[77.5,122.5],offset=[0,20]),
        move('porter_front',[340,FLOOR],1.8,wait=False),move('porter_rear',[492,FLOOR],1.8),
        dict(do='pose',id='porter_front',pose='idle'),
        reach('porter_front','ch2_greycoat',prop=BED,to=BED_LEFT_GRIP),dict(do='prop_hold',id=BED,actor='porter_front',hand='front',point=BED_LEFT_GRIP,follow_rotation=False),
        reach('porter_rear','ch2_medic',prop=BED,to=BED_RIGHT_GRIP),
        move('porter_front',[665,FLOOR],5.0,wait=False),move('porter_rear',[817,FLOOR],5.0,wait=False),
        move('egret',[BED_PATIENT[0]+325,BED_PATIENT[1]],5.0,pose='dead',then='dead'),
        dict(do='wait',time=.3),dict(do='prop_release',id=BED),dict(do='prop_release',id=UMBRELLA),
        dict(do='remove',id='egret'),dict(do='remove',id='porter_front'),dict(do='remove',id='porter_rear'),
        dict(do='prop_visible',id=BED,visible=False),dict(do='prop_visible',id='transport_strap_chest',visible=False),dict(do='prop_visible',id='transport_strap_hips',visible=False),dict(do='prop_visible',id=BAG,visible=False),dict(do='prop_visible',id=UMBRELLA,visible=False),
        reach('rin','rin',release=True),dict(do='wait',time=.3),
    )
