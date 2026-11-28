#!/usr/bin/env python3
"""第三章「晴岸」的區域地圖產生器（ST-21）：輸出 data/levels/ch3_*.tres、ch3_*_map.json、環境主題與人物資料。

沿用第一章產生器的工具（區域格子、出入口、人物與主題的輸出、可通行檢查），只換章節前綴與本章的內容；寫法同第二章。
落地計畫見 design/13-story-v2/CH03_IMPLEMENTATION.md，劇本見 design/13-story-v2/SCRIPT_CH03.md。
敵人與守門人戰由戰鬥 Session 配置：這裡只標出戰鬥區與繞道、守門人停機的機關頻道，不放敵人。
用法：python3 tools/level/build_ch3.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
sys.dont_write_bytecode = True
import build_ch1 as kit  # noqa: E402

kit.PREFIX = 'ch3'
kit.CHAPTER = 'ch3_clearwater'
AREA = kit.AREA
H = kit.H
Area = kit.Area
MAINTENANCE_CREDIT = '¢'
# 玩法線的機關（字元在每一章同義）。
DECOY_RADIO = 'ψ'
LIVE_CABLE = 'φ'
STEAM_VALVE = 'σ'
LATCH_DOOR = '⊓'
SECRET_WALL = 'X'
MECHANISMS = {DECOY_RADIO: 'res://data/props/decoy_radio.tres', LIVE_CABLE: 'res://data/props/live_cable.tres',
              STEAM_VALVE: 'res://data/props/steam_valve.tres', LATCH_DOOR: 'res://data/props/latch_door.tres'}

# ---------------------------------------------------------------------------
# 人物與可調查物件：字元 -> 資料檔（台詞由劇本的分派場景依進度挑選，見 tools/story/ch3_source.py）
# ---------------------------------------------------------------------------
NPC_CHARS = {
    'ⓞ': 'ch3_old_k', 'Ⓜ': 'ch3_old_k_kitchen', 'ⓜ': 'ch3_unsigned_record', 'Ⓡ': 'ch3_shop_radio',
    'Ⓗ': 'ch3_control_box', 'Ⓘ': 'ch3_water_gauge', 'ⓢ': 'ch3_outer_ladder',
    'Ⓙ': 'ch3_drain_wheel', 'Ⓚ': 'ch3_branch_panel',
    'ⓝ': 'ch3_notice_terminal',
    'ⓩ': 'ch3_zhi', 'ⓟ': 'ch3_public_report', 'Ⓞ': 'ch3_register_cabinet', 'ⓣ': 'ch3_nursing_board', 'ⓓ': 'ch3_deposit_drawer',
    'ⓔ': 'ch3_reading_desk',
    'ⓖ​': None,  # 佔位（不使用）：避免日後誤用同形字元
    'Ⓖ': 'ch3_scanner_gate', 'ⓙ': 'ch3_gatekeeper',
    'Ⓟ': 'ch3_light_spot', 'Ⓠ': 'ch3_telescope',
    'ⓛ': 'ch3_lin', 'Ⓐ': 'ch3_window_morning', 'Ⓑ': 'ch3_window_quiet', 'Ⓤ': 'ch3_window_late',
    'ⓧ': 'ch3_petition_box', 'Ⓦ': 'ch3_waiting_bench',
    # ST-61：廣場與泵室的街坊與告示，兩處秘密空間的紙條。
    'Ⓝ': 'ch3_plaza_nurse', 'Ⓧ': 'ch3_plaza_notice', 'Ⓨ': 'ch3_pump_locker', 'Ⓩ': 'ch3_clinic_cups', 'Ⓥ': 'ch3_office_vent',
}

# 人物（kind 0）有骨架外觀；物件（kind 1）只有互動提示。
P, O = 0, 1
NPCS = {
    'ch3_old_k': dict(name='老 K', speaker='old_k', rig='old_k', loop='wipe_hands', facing=1, prompt='{interact} 和老 K 說話',
                      talks=[('ch3_dispatch_old_k', 0)], spawn_unless_flag='ch3_trade_overheard'),
    'ch3_old_k_kitchen': dict(name='老 K', speaker='old_k', rig='old_k', loop='stir', facing=-1, prompt='{interact} 和老 K 吃飯',
                              talks=[('ch3_dispatch_supper', 0)], spawn_requires_flag='ch3_trade_overheard'),
    'ch3_unsigned_record': dict(name='未署名的記錄', speaker='label', kind=O, prompt='{interact} 翻貨架上的未署名記錄',
                                talks=[('ch3_dispatch_m3', 0)], spawn_requires_flag='m3_available'),
    'ch3_shop_radio': dict(name='店內的通訊器', speaker='label', kind=O, prompt='{interact} 接店內的通訊', talks=[('ch3_dispatch_call', 0)]),
    'ch3_control_box': dict(name='貨梯控制箱', speaker='label', kind=O, prompt='{interact} 查看貨梯控制箱', talks=[('ch3_dispatch_control_box', 0)]),
    'ch3_water_gauge': dict(name='集水槽水尺', speaker='label', kind=O, prompt='{interact} 看集水槽的水尺', talks=[('ch3_dispatch_gauge', 0)]),
    'ch3_outer_ladder': dict(name='廣場外梯', speaker='label', kind=O, prompt='{interact} 放下通往泵室的外梯', talks=[('ch3_dispatch_ladder', 0)]),
    'ch3_drain_wheel': dict(name='排水輪', speaker='label', kind=O, prompt='{interact} 轉動排水輪', talks=[('ch3_dispatch_wheel', 0)]),
    'ch3_branch_panel': dict(name='泵室配電盤', speaker='label', kind=O, prompt='{interact} 打開泵室配電盤', talks=[('ch3_dispatch_panel', 0)]),
    'ch3_notice_terminal': dict(name='公共通知終端', speaker='label', kind=O, prompt='{interact} 查看公共通知', talks=[('ch3_dispatch_notice', 0)]),
    'ch3_zhi': dict(name='芷姐', speaker='zhi', rig='zhi', loop='read_note', facing=-1, prompt='{interact} 和芷姐說話',
                    talks=[('ch3_dispatch_zhi', 0)]),
    'ch3_public_report': dict(name='公開報表', speaker='label', kind=O, prompt='{interact} 翻閱桌上的公開報表', talks=[('ch3_dispatch_report', 0)]),
    'ch3_register_cabinet': dict(name='門邊閱覽櫃', speaker='label', kind=O, prompt='{interact} 查追蹤名冊', talks=[('ch3_dispatch_register', 0)]),
    'ch3_nursing_board': dict(name='護理輪班表', speaker='label', kind=O, prompt='{interact} 看玻璃板上的輪班表', talks=[('ch3_dispatch_roster', 0)]),
    'ch3_deposit_drawer': dict(name='寄存櫃', speaker='label', kind=O, prompt='{interact} 打開寄存櫃', talks=[('ch3_dispatch_drawer', 0)]),
    'ch3_reading_desk': dict(name='閱覽桌', speaker='label', kind=O, prompt='{interact} 在閱覽桌核對三份資料', talks=[('ch3_dispatch_reconcile', 0)]),
    'ch3_scanner_gate': dict(name='門禁閘', speaker='label', kind=O, prompt='{interact} 掃夾層證', talks=[('ch3_dispatch_gate', 0)]),
    'ch3_gatekeeper': dict(name='守門人', speaker='janus', rig='janus', pose='sit', loop='glance', facing=1, prompt='{interact} 看看守門人',
                           pose_before_flag='ch3_janus_aftercare_done', pose_before='idle',  # 停機後先站在櫃檯旁，凜扶他坐下才坐到凳子上
                           talks=[('ch3_dispatch_gatekeeper', 0)], spawn_requires_flag='ch3_janus_disabled'),
    'ch3_light_spot': dict(name='地上的光斑', speaker='label', kind=O, prompt='{interact} 停在光裡', talks=[('ch3_dispatch_light', 0)]),
    'ch3_telescope': dict(name='觀景框', speaker='label', kind=O, prompt='{interact} 從觀景框看遠處', talks=[('ch3_dispatch_telescope', 0)]),
    'ch3_lin': dict(name='林小姐', speaker='lin', rig='lin', loop='read_note', facing=-1, prompt='{interact} 和林小姐說話',
                    talks=[('ch3_dispatch_lin', 0)]),
    'ch3_window_morning': dict(name='A 晨窗', speaker='label', kind=O, prompt='{interact} 量 A 晨窗', talks=[('ch3_dispatch_room_morning', 0)]),
    'ch3_window_quiet': dict(name='B 靜窗', speaker='label', kind=O, prompt='{interact} 量 B 靜窗', talks=[('ch3_dispatch_room_quiet', 0)]),
    'ch3_window_late': dict(name='C 晚窗', speaker='label', kind=O, prompt='{interact} 量 C 晚窗', talks=[('ch3_dispatch_room_late', 0)]),
    'ch3_petition_box': dict(name='公文取件格', speaker='label', kind=O, prompt='{interact} 取異議收件回執', talks=[('ch3_dispatch_petition', 0)]),
    'ch3_waiting_bench': dict(name='等候臺', speaker='label', kind=O, prompt='{interact} 在等候臺停一下', talks=[('ch3_dispatch_bench', 0)]),
    'ch3_plaza_nurse': dict(name='早班護理員', speaker='shift_nurse', rig='nurse', loop='glance', facing=-1, prompt='{interact} 和早班護理員說話',
                            talks=[('ch3_dispatch_plaza_nurse', 0), ('ch3_dispatch_plaza_nurse_again', 1)]),
    'ch3_plaza_notice': dict(name='廣場公告欄', speaker='label', kind=O, prompt='{interact} 看廣場公告欄', talks=[('ch3_dispatch_plaza_notice', 0)]),
    'ch3_pump_locker': dict(name='值班櫃', speaker='label', kind=O, prompt='{interact} 看值班櫃上的紙', talks=[('ch3_dispatch_pump_locker', 0)]),
    'ch3_clinic_cups': dict(name='舊備品櫃', speaker='label', kind=O, prompt='{interact} 打開舊備品櫃', talks=[('ch3_dispatch_clinic_cups', 0)]),
    'ch3_office_vent': dict(name='空調維修口', speaker='label', kind=O, prompt='{interact} 看維修口的工作單', talks=[('ch3_dispatch_office_vent', 0)]),
}

# ---------------------------------------------------------------------------
# 出入口：字元 -> 設定（欄位同第一章）。目標區域留空＝鎖死的門。
# ---------------------------------------------------------------------------
PORTALS = {
    # 當舖
    'F': dict(id='pawn_front', to=AREA('plaza'), target='plaza_street', mode=0, prompt='{interact} 出門去廣場貨梯', style='door',
              requires='ch3_departure_done', locked='先和老 K 吃完早飯，確認今天要出門。'),
    'K': dict(id='pawn_basement', to='', target='', mode=0, prompt='{interact} 地下室', locked='地下室的門鎖著，老 K 說裡面在漏水。', style='hidden', w=32, h=48),
    # 廣場貨梯
    'h': dict(id='plaza_street', to=AREA('pawnshop'), target='pawn_front', mode=0, prompt='{interact} 回當舖', style='door'),
    'Ⅰ': dict(id='plaza_pump', to=AREA('pump'), target='pump_plaza', mode=0, prompt='{interact} 走下路到泵室', style='road', w=28, h=44),
    'L': dict(id='plaza_lift', to=AREA('mezzanine'), target='mezz_lift', mode=0, prompt='{interact} 搭貨梯上夾層', style='hidden', w=32, h=56,
              requires='ch3_freight_ready', locked='貨梯的安全聯鎖還沒解除。先到泵室把水排掉，再回控制箱叫車廂。'),
    'Ⅴ': dict(id='plaza_ladder', to=AREA('pump'), target='pump_ladder', mode=0, prompt='{interact} 走外梯到泵室上橋', style='hidden', w=24, h=56,
              requires='ch3_outer_ladder_down', locked='外梯還收著，貨梯接通以後才能從這一側放下來。'),
    # 泵室
    'Ⅱ': dict(id='pump_plaza', to=AREA('plaza'), target='plaza_pump', mode=0, prompt='{interact} 回廣場', style='road', w=28, h=44),
    'Ⅵ': dict(id='pump_ladder', to=AREA('plaza'), target='plaza_ladder', mode=0, prompt='{interact} 走外梯回廣場貨梯', style='door',
              requires='ch3_outer_ladder_down', locked='外梯收在廣場那一側，貨梯接通後從控制箱旁放下來。'),
    # 夾層通道
    'Ⅲ': dict(id='mezz_lift', to=AREA('plaza'), target='plaza_lift', mode=0, prompt='{interact} 搭貨梯回廣場', style='door', w=32, h=56),
    'Ⅳ': dict(id='mezz_clinic', to=AREA('clinic'), target='clinic_mezz', mode=0, prompt='{interact} 進夾層診所', style='door'),
    'Ⅶ': dict(id='mezz_care', to=AREA('gate_hall'), target='gate_care', mode=0, prompt='{interact} 走護理通道外段到門禁大廳', style='door',
              requires='ch3_care_passage_open', locked='護理通道的外門從門禁大廳那一側鎖著。'),
    # 夾層診所
    'm': dict(id='clinic_mezz', to=AREA('mezzanine'), target='mezz_clinic', mode=0, prompt='{interact} 回夾層通道', style='door'),
    'ⅰ': dict(id='clinic_gate', to=AREA('gate_hall'), target='gate_clinic', mode=0, prompt='{interact} 往門禁大廳', style='door',
              requires='ch3_report_reconciled', locked='門禁大廳要夾層證。先在閱覽桌把三份公開資料核對完。'),
    # 門禁大廳
    'ⅱ': dict(id='gate_clinic', to=AREA('clinic'), target='clinic_gate', mode=0, prompt='{interact} 回診所櫃檯', style='door'),
    'Ⅷ': dict(id='gate_care', to=AREA('mezzanine'), target='mezz_care', mode=0, prompt='{interact} 走護理通道外段回夾層', style='door',
              requires='ch3_care_passage_open', locked='護理通道的外門還鎖著，門禁工作架停下來才會打開。'),
    'ⅲ': dict(id='gate_lift', to=AREA('glass_edge'), target='edge_lift', mode=0, prompt='{interact} 搭邊緣電梯上去', style='door', w=32, h=56,
              requires='ch3_janus_aftercare_done', locked='門禁工作架還擋著邊緣電梯，先讓守門人停下來。'),
    # 玻璃邊緣
    'Ⅸ': dict(id='edge_lift', to=AREA('gate_hall'), target='gate_lift', mode=0, prompt='{interact} 搭邊緣電梯下去', style='door', w=32, h=56),
    'ⅳ': dict(id='edge_homes', to='', target='', mode=0, prompt='{interact} 住宅內區', style='door',
              locked='住宅內區需要正式參觀證，今天只開展示接待。'),
    'ⅴ': dict(id='edge_show', to=AREA('showroom'), target='show_edge', mode=0, prompt='{interact} 進晴岸展示接待', style='door'),
    'ⅵ': dict(id='edge_hall', to=AREA('office_hall'), target='hall_edge', mode=0, prompt='{interact} 走候梯迴廊', style='door'),
    # 晴岸樣品房
    'Ⅹ': dict(id='show_edge', to=AREA('glass_edge'), target='edge_show', mode=0, prompt='{interact} 回玻璃邊緣', style='door'),
    'ⅶ': dict(id='show_hall', to=AREA('office_hall'), target='hall_show', mode=0, prompt='{interact} 往候梯迴廊取回執', style='door',
              requires='ch3_clearwater_tour_done', locked='先在接待桌確認看房，林小姐會告訴您取件格在哪裡。'),
    # 天穹辦公接待廊
    'Ⅺ': dict(id='hall_show', to=AREA('showroom'), target='show_hall', mode=0, prompt='{interact} 回樣品房', style='door'),
    'Ⅻ': dict(id='hall_edge', to=AREA('glass_edge'), target='edge_hall', mode=0, prompt='{interact} 沿候梯迴廊回玻璃邊緣', style='door'),
    'ⅷ': dict(id='hall_office', to='', target='', mode=0, prompt='{interact} 辦公內門', style='door',
              locked='辦公內門需要職員證，迴廊只到等候臺。'),
}

THEMES = {
    # 區域 -> (地形材質, 立面清單, 室內牆面貼圖, 鏤空機率, 天空, 道具資料夾)
    'pawnshop': ('concrete', ['shopfront', 'brick_block'], 'brick', 0.0, 'sky_haze', ['pawnshop_front', 'pawnshop_kitchen', 'basement_door', 'harbor_street']),
    'plaza': ('plaza_asphalt', ['shopfront', 'shutter_block', 'warehouse'], None, 0.22, 'sky_haze', ['harbor_plaza', 'sluice_hall', 'harbor_street']),
    'pump': ('concrete', ['warehouse'], 'hangar_wall', 0.0, 'sky_storm', ['sluice_hall', 'control_room', 'mezzanine']),
    'mezzanine': ('steel_plate', ['facility_wall'], 'facility_panel', 0.0, 'sky_storm', ['mezzanine', 'anchor_phone_booth', 'clinic']),
    'clinic': ('facility_floor', ['facility_wall'], 'facility_panel', 0.0, 'sky_storm', ['clinic', 'nursing_ward', 'control_room']),
    'gate_hall': ('facility_floor', ['facility_wall'], 'facility_panel', 0.0, 'sky_storm', ['gate_hall', 'clinic', 'anchor_phone_booth']),
    # 玻璃邊緣以上是日照區：晴天的天空、玻璃帷幕的牆面，雨只在玻璃外面（關卡 rain=false）。
    'glass_edge': ('facility_floor', ['glass_tower'], None, 0.0, 'sky_blue_clouds', ['sunlit_district', 'clearwater', 'anchor_phone_booth']),
    'showroom': ('facility_floor', ['glass_tower'], 'glass_curtain', 0.0, 'sky_blue_clouds', ['clearwater', 'sunlit_district']),
    'office_hall': ('facility_floor', ['glass_tower'], 'glass_curtain', 0.0, 'sky_blue_clouds', ['tianqiong_corridor', 'accounting_lobby', 'clearwater']),
}

# 劇情接點：進場劇情與機關頻道。
STORY = {
    'mezzanine': dict(intro='ch3_c03_arrive'),
    'glass_edge': dict(intro='ch3_c13_arrive'),
    # 守門人戰由戰鬥組製作：門禁裝置停機（拔掉維修插銷）時啟動這個頻道，關卡寫入停機旗標；之後守門人坐回櫃檯（C12）。
    'gate_hall': dict(durable=True, done={'ch3_janus_down': 'ch3_janus_disabled'}),
}

# 本章的敵人（NE-272、NE-271）：字元 -> 敵人資料 id。章節名單與跨章規則見 data/combat/chapter_rosters.json（NE-97）。
ENEMY_CHARS = {'Ж': 'pump_inspector', 'Ш': 'insulation_inspector', 'Ю': 'janus'}
ENEMY_DISPLAY = {'Ж': '抽水巡檢器', 'Ш': '絕緣巡檢器', 'Ю': '守門人'}
# 掛在吊軌下（不站地面）的敵人字元：可通行檢查不要求腳下有地。
HANGING = ('Ш',)

# 戰鬥區（交給戰鬥 Session 配置）：區域 -> [(名稱, x0, x1, 用途)]。這裡只寫進設計資料，敵人由 ENCOUNTERS 放。
COMBAT_ZONES = {
    'pump': [('下槽抽水巡檢器', 18, 36, '短戰，可沿乾燥上橋繞過'), ('下槽絕緣巡檢器', 42, 60, '短戰，可沿乾燥上橋繞過')],
    'mezzanine': [('維修帶雙巡檢器', 40, 56, '可從照護步道繞過，門診不混戰')],
    'gate_hall': [('守門人／JANUS', 18, 62, '頭目戰：只打外部盾架、掃描臂與通訊器，人物是保護區')],
}

# 戰鬥區裡的敵人（NE-272）：區域 -> {戰鬥區名稱: [(欄, 字元) 或 (欄, 字元, 列)]}。每場同屏最多三個、近戰與遠距最多各一；
# 每種第一次出現時左側五格內沒有別種敵人。數量是第三章的正式配置，整批調整改這裡再重跑產生器。
ENCOUNTERS = {
    'pump': {
        '下槽抽水巡檢器': [(28, 'Ж')],                    # 第一次見到地面亮線：只有一台
        '下槽絕緣巡檢器': [(44, 'Ж'), (52, 'Ш', 15)],    # 吊軌掛在上橋底下（第 15 列），近戰＋遠距
    },
    'mezzanine': {
        '維修帶雙巡檢器': [(46, 'Ш', 16), (52, 'Ж')],    # 吊軌在照護步道底下；走步道就能繞過
    },
    # 守門人（NE-271）站在櫃檯與柱後短上臺之間；登場劇情（C10）看過、玩家走近才醒，增援由他的通訊器叫來。
    'gate_hall': {
        '守門人／JANUS': [(36, 'Ю')],
    },
}


# ---------------------------------------------------------------------------
# 區域
# ---------------------------------------------------------------------------

def build_pawnshop():
    """H1 當舖與 H2 廚房：早上在櫃台吃早飯出門（C00），傍晚回廚房吃留飯（C22），店內通訊接鷺（C23）。"""
    a = Area('pawnshop', '當舖（週日）', 112, 20, indoor=True)
    kit.pawnshop_shell(a)
    a.stand(36, 'ⓜ')
    a.stand(40, 'P')
    a.stand(43, 'K')
    a.stand(50, 'ⓞ')
    a.stand(66, 'Ⓡ')
    a.stand(74, 'F')
    a.stand(93, 'Ⓜ')
    a.features = {'landmark': '櫃台與廚房的飯桌（x=50、x=93）：出門前與回家後的兩頓飯'}
    return a


def _build_plaza_v1():
    """H14 廣場貨梯：控制箱與水尺（C01），貨梯接通後叫車廂（C02），外梯捷徑通泵室上橋，高架維修盒是探索獎勵。"""
    a = Area('plaza', '廣場貨梯', 96, 20)
    a.stand(3, 'h')
    a.stand(6, 'P')
    a.prop('harbor_plaza__loudspeaker_pole', 14)
    a.prop('harbor_plaza__plaza_benches', 20)
    a.stand(21, 'Ⓝ')   # 等貨梯的早班護理員（ST-61）
    a.prop('harbor_plaza__notice_board_plaza', 26)
    a.stand(26, 'Ⓧ')   # 廣場公告欄（ST-61）
    a.stand(32, 'Ⓘ')
    a.prop('sluice_hall__water_level_gauge_tower', 34)
    # 貨梯、控制箱與外梯（BG-43）：貨梯車廂就是出入口的樣子，控制箱與車廂的燈跟著通電、可搭乘的進度換色；
    # 外梯放下之前是收在導軌頂端的樣子。
    a.prop('harbor_plaza__lift_control_box', 40, dx=4, react='lift_control_box')
    a.stand(40, 'Ⓗ')
    a.prop('harbor_plaza__freight_lift', 47, dx=3, react='freight_lift')
    a.stand(48, 'L')
    a.stand(56, 'ⓢ')
    a.prop('harbor_plaza__outer_ladder_up', 60, y=16, dx=3, dy=3, support='wall', react='plaza_outer_ladder')
    a.stand(60, 'Ⅴ')
    # 高架維修盒：從右邊的貨架一路跳上去（看得到，要繞一下才拿得到）。
    a.platform(68, 71, 17)
    a.platform(73, 77, 14)
    a.hint(74, '維修盒：水位降到低線後再領。', row=13)
    a.stand(75, MAINTENANCE_CREDIT, row=13)
    a.prop('harbor_plaza__queue_barriers', 82)
    a.stand(93, 'Ⅰ')
    for x in (12, 28, 66, 86):
        a.lamp(x, 12)  # 戶外街燈約 4 公尺高（BG-36）
    a.zone(0, 'plaza')
    a.features = {'landmark': '貨梯纜輪與導軌（x=48）', 'reward': '高架維修盒（x=75，第 13 列）',
                  'shortcut': '外梯 SC5（x=60）接通後直達泵室上橋'}
    return a


def _build_pump_v1():
    """泵室：乾燥上橋轉排水輪（C02），下槽的乾地配電盤關支路、接主路；下槽兩場短戰都能從上橋繞過，背面工具櫃有一個秘密盒。"""
    a = Area('pump', '集水槽與泵室', 80, 20, indoor=True)
    a.ceiling(1, 78, 6)
    a.combat = True
    a.stand(3, 'Ⅱ')
    a.stand(6, 'P')
    # 乾燥上橋（第 13 列）：從入口跳上，橫跨整座集水槽，到右端接外梯
    a.platform(8, 10, 17)
    a.platform(11, 77, 13)
    a.stand(30, 'Ⓙ', row=12)
    a.prop('sluice_hall__drain_wheel', 29, y=12, dx=11, react='drain_wheel')   # 排水輪在上橋上、互動點旁（BG-44）
    a.prop('sluice_hall__release_console', 24)
    a.prop('sluice_hall__hydraulic_piston', 46)
    a.stand(64, 'Ⓚ')
    a.prop('sluice_hall__branch_panel_closed', 63, y=17, dx=13, support='wall', react='pump_branch_panel')   # 配電盤掛牆，關支路後換成打開的樣子（BG-44）
    a.prop('control_room__cable_bundle_floor', 60)
    a.hint(73, '維修備料：水位降到低線後再領。')
    a.stand(74, MAINTENANCE_CREDIT)
    a.prop('sluice_hall__maintenance_locker', 74, y=19, dx=-9)
    a.prop('mezzanine__drip_basin', 70)
    a.stand(72, 'Ⓨ')   # 值班櫃上的值班表（ST-61）
    a.stand(76, 'Ⅵ', row=12)
    for x in (14, 34, 54, 70):
        a.lamp(x, 8)
    a.zone(0, 'pump_room')
    a.features = {'loop': '乾燥上橋（第 13 列）與下槽成環', 'secret': '下槽背面的工具櫃（x=74）',
                  'landmark': '排水輪（x=30，上橋上）', 'vertical': '上橋與下槽兩層', 'shortcut': '外梯 SC5（x=76）回廣場'}
    return a


def _build_mezzanine_v1():
    """M1 夾層通道：貨梯口、B5 電話亭（可登記復原點）、公共通知終端（C03 可選），往右是診所的公開入口；維修帶一場可繞的短戰。"""
    a = Area('mezzanine', '夾層通道', 80, 20, indoor=True)
    a.ceiling(1, 78, 8)
    a.combat = True
    a.stand(3, 'Ⅲ')
    a.stand(7, 'P')
    a.prop('mezzanine__pipe_manifold', 14, support='ceiling', ceiling_row=8)
    a.stand(22, 'C')
    a.prop('anchor_phone_booth__phone_booth', 22)
    a.stand(32, 'ⓝ')
    a.prop('mezzanine__notice_terminal', 32)   # 公共通知終端（BG-44）
    a.hint(36, '公開報表的查核往右走。安養病房的來訪要洽護理櫃檯，廠房暫停通行。')
    # 照護步道：維修帶上方的平臺，可以繞過巡檢器
    a.platform(38, 40, 17)
    a.platform(41, 58, 14)
    a.platform(59, 61, 17)
    a.prop('mezzanine__hanging_cables', 48, support='ceiling', ceiling_row=8)
    a.prop('mezzanine__exhaust_fan', 52, support='ceiling', ceiling_row=8)
    a.stand(66, 'Ⅶ')
    a.prop('clinic__public_rate_poster', 70, y=15, support='wall')
    a.stand(76, 'Ⅳ')
    for x in (12, 28, 46, 64, 74):
        a.lamp(x, 9)
    a.material_zones = [(0, 'mezzanine_steel_plate'), (20, 'steel_plate')]
    a.zone(0, 'transfer')
    a.features = {'loop': '照護步道（第 14 列）與維修帶成環', 'landmark': 'B5 電話亭（x=22）與朝內的診所招牌',
                  'secret': '公共通知終端的父女狀態（x=32，可選）', 'vertical': '維修帶與照護步道兩層',
                  'shortcut': '護理通道外段 SC6（x=66）回門禁大廳'}
    return a


def build_clinic():
    """M5a 公開櫃檯與閱覽桌、M5b 核閱工作廊：芷姐（C04）、三份公開資料（C05～C07）、閱覽桌核對（C08）、寄存櫃（C09）。"""
    a = Area('clinic', '夾層診所', 104, 20, indoor=True)
    a.ceiling(1, 102, 10)
    a.stand(3, 'm')
    a.stand(6, 'P')
    a.stand(12, 'Ⓞ')
    a.prop('clinic__report_cabinet', 12)
    a.prop('clinic__waiting_chairs', 18)
    a.stand(24, 'ⓩ')
    a.prop('clinic__reception_window', 26)
    a.prop('clinic__queue_number_display', 22, y=12, support='wall')
    a.stand(34, 'ⓟ')
    a.prop('clinic__reading_desk', 36, dx=2)   # 閱覽桌：桌上攤著公開報表（BG-45），兩個互動點都在桌邊
    a.stand(38, 'ⓔ')
    a.prop('clinic__fern_pot', 42)
    # 核閱工作廊：內側回門（x=48）之後
    a.block(47, 47, 10, 16)
    a.prop('nursing_ward__nurse_cart', 54)
    a.stand(60, 'ⓣ')
    a.prop('control_room__whiteboard_notes', 59, y=14, support='wall')
    a.prop('nursing_ward__rain_window_wide', 70, y=13, support='wall')
    a.stand(76, 'ⓓ')
    a.prop('nursing_ward__bedside_locker', 76)
    a.prop('clinic__water_dispenser', 84)
    a.stand(92, 'ⅰ')
    # 往門禁大廳的門右邊：一面有裂縫的隔牆，後面是舊的備品間（NE-419）。不擋主線，打破才看得到。
    a.block(96, 96, 10, 16)
    a.put(96, 19, SECRET_WALL)
    a.prop('nursing_ward__bedside_locker', 99)
    a.stand(101, 'q')
    a.stand(99, 'Ⓩ')   # 備品間的舊備品櫃（ST-61）
    for x in (10, 22, 36, 56, 72, 88, 100):
        a.lamp(x, 11)
    a.zone(0, 'clinic_ward')
    a.features = {'loop': '公開櫃檯與核閱工作廊之間的內側回門（x=47）', 'landmark': '芷姐的公開櫃檯（x=24）',
                  'secret': '往門禁大廳的門右邊，裂縫隔牆後的備品間（x=97～102）；寄存櫃第三個抽屜的錄音（x=76，可選）'}
    return a


def build_gate_hall():
    """M5c 門禁大廳：B6 安全前室、門禁閘（C10）、守門人戰區、扶守門人坐回櫃檯（C12）、SC6 護理通道與邊緣電梯。"""
    a = Area('gate_hall', '門禁大廳', 72, 20, indoor=True)
    a.ceiling(1, 70, 8)
    a.combat = True
    a.stand(3, 'ⅱ')
    a.stand(6, 'P')
    a.stand(10, 'C')
    a.prop('anchor_phone_booth__phone_booth', 10)
    # 門禁大廳自己的東西（BG-39）：排隊的紅龍柱引到門禁閘，閘後是檢查桌與換證機；守門人的櫃台後面是崗亭。
    # 崗亭放在右側平台後面，不擋守門人站的位置。
    a.prop('gate_hall__queue_stanchions', 12)
    a.prop('gate_hall__scanner_gate', 17)
    a.stand(18, 'Ⓖ')
    a.prop('gate_hall__pass_kiosk', 21)
    a.prop('gate_hall__inspection_table', 23)
    a.prop('gate_hall__notice_board', 23, y=16, dy=8, support='wall')
    a.prop('clinic__gatekeeper_desk', 30)
    a.prop('gate_hall__desk_stool', 32, dx=3)   # 守門人停機後坐的凳子（ST-21 C12）：坐姿的骨盆落在凳面上，不坐在空中
    a.stand(32, 'ⓙ')
    a.prop('gate_hall__guard_booth', 57)
    a.prop('gate_hall__waiting_bench', 61)
    # 柱後的短上臺：繞盾架的側路
    a.platform(40, 42, 17)
    a.platform(43, 50, 15)
    a.prop('gate_hall__camera_mast', 56, y=11, support='wall')
    a.stand(58, 'Ⅷ')
    a.stand(68, 'ⅲ')
    for x in (12, 26, 40, 54, 64):
        a.lamp(x, 9)
    a.zone(0, 'facility')
    a.features = {'loop': '柱後的短上臺（x=43～50）繞到盾架背面', 'landmark': '守門人的櫃檯（x=30）',
                  'secret': 'B6 安全前室的電話亭（x=10）', 'vertical': '大廳與短上臺', 'shortcut': '護理通道外段 SC6（x=58）回夾層'}
    return a


def build_glass_edge():
    """S1 玻璃邊緣：第一次看見陽光（C13）、地上的光斑、觀景框的白傘遠景（C14）、住宅內區的門（關著）、展示接待與候梯迴廊。"""
    a = Area('glass_edge', '玻璃邊緣', 72, 20)
    a.stand(3, 'Ⅸ')
    a.stand(6, 'P')
    a.stand(12, 'C')
    a.prop('anchor_phone_booth__phone_booth', 12)
    a.stand(20, 'Ⓟ')
    a.prop('sun_patch', 18, dx=12)                          # 地上的光斑：一道真的會照亮人的日光（BG-45）
    a.stand(30, 'Ⓠ')
    a.prop('sunlit_district__viewing_frame', 29, dx=12)     # 觀景框（BG-45）
    a.prop('sunlit_district__flower_planters', 36)
    a.stand(44, 'ⅳ')
    a.prop('sunlit_district__white_bench', 50)
    a.prop('sunlit_district__street_clock', 54)
    a.stand(60, 'ⅴ')
    a.stand(68, 'ⅵ')
    for x in (16, 40, 64):
        a.lamp(x, 7)
    a.zone(0, 'sunlit_edge')
    # 主光（BG-67）：立面上方偏左的午後太陽，光柱往右下斜照到地上的光斑一帶。其他區段照這份當樣板。
    a.map_extra = {'key_light': {
        'x': 17, 'y': 12, 'color': [1.0, 0.68, 0.4], 'energy': 0.8, 'light_radius': 700,
        'halo_radius': 320, 'halo_alpha': 0.75, 'front_wash': 0.08,
        'shafts': {'count': 6, 'angle': 34, 'length': 360, 'width': 30, 'spread': 300},
        'occlusion': [0.12, 0.88], 'period': 48},
        # 近前景（BG-68）：走道外緣的花台、矮籬與玫瑰叢（只露出小腿高），上緣垂下的枝葉與燈籠串。
        # 地面剖面（BG-72）：走道下方往下變暗，看得到橋面樑、基樁與管線。
        'ground_section': {'start': 14, 'fade': 0.7, 'piles': [56, 104], 'pipes': 0.5},
        # 中景（BG-69、BG-71）：靠牆的回收桶、行道樹花台、咖啡棚、販賣機、貨箱、管線、油桶（深色為主），由 Midground 依規則排位置。
        'midground': {'pieces': ['sunlit_district__sorting_bins', 'sunlit_district__street_tree_planter', 'sunlit_district__cafe_awning_set', 'vending_machine', 'crates_stack', 'pipe_vertical', 'barrels'], 'spacing': [50, 120], 'from': 2, 'to': 70},
        'near_foreground': [{'anchor': 'bottom', 'base': ['planter_edge'], 'pieces': ['rose_bush', 'planters'], 'rise': 14, 'spacing': [30, 120], 'scale': [0.6, 1.15], 'from': 0, 'to': 72}, {'anchor': 'top', 'pieces': ['foliage'], 'above': 175, 'spacing': [40, 120], 'from': 4, 'to': 22}, {'anchor': 'top', 'pieces': ['lanterns'], 'above': 175, 'spacing': [110, 260], 'from': 24, 'to': 72}]}
    a.features = {'landmark': '地上的光斑（x=20）與觀景框（x=30）', 'secret': '觀景框的塔頂花園遠景（可選）'}
    return a


def build_showroom():
    """S2 晴岸樣品房：林小姐的接待桌（C15、C17），三扇展示窗 A 晨、B 靜、C 晚（C16），往候梯迴廊取回執。"""
    a = Area('showroom', '晴岸樣品房', 80, 20, indoor=True)
    a.ceiling(1, 78, 8)
    a.stand(3, 'Ⅹ')
    a.stand(6, 'P')
    a.prop('clearwater__brochure_rack', 10)
    a.stand(16, 'ⓛ')
    a.prop('clearwater__reception_desk', 18)
    a.prop('clearwater__tall_floor_plant', 24)
    a.stand(32, 'Ⓐ')
    a.prop('clearwater__window_chair', 35)
    a.prop('clearwater__sun_chart_notes', 32, y=13, support='wall')
    a.stand(46, 'Ⓑ')
    a.prop('clearwater__white_curtains', 45, y=12, support='wall')
    a.prop('clearwater__rain_sound_machine', 50)
    a.stand(60, 'Ⓤ')
    a.prop('clearwater__sill_with_coin', 60, react='showroom_late_shade')
    a.prop('clearwater__plain_wall_clock', 57, y=12, support='wall')
    a.stand(76, 'ⅶ')
    for x in (12, 34, 47, 61, 72):
        a.lamp(x, 9)
    a.zone(0, 'showroom_day')
    a.zone(42, 'showroom_quiet', blend=6)
    a.zone(55, 'showroom_day', blend=6)
    a.features = {'loop': '三間樣品房圍著接待桌（x=16～62）', 'landmark': '接待桌（x=18）', 'secret': '三扇窗的完整比較（可選）'}
    return a


def build_office_hall():
    """S3 天穹辦公接待廊：公文取件格（C18）、等候臺（C19、C20），辦公內門關著，候梯迴廊接回玻璃邊緣。"""
    a = Area('office_hall', '天穹辦公接待廊', 64, 20, indoor=True)
    a.ceiling(1, 62, 8)
    FLOOR_ROW = 19  # 地面擺設寫明站在地板上：維修廊在頭上，「站在地上」會被算成站在維修廊上
    a.stand(3, 'Ⅺ')
    a.stand(6, 'P')
    a.stand(14, 'ⓧ')
    a.prop('tianqiong_corridor__petition_box', 13, y=FLOOR_ROW)   # 公文取件格（BG-45）
    a.stand(28, 'Ⓦ')
    # 擺設改用天穹接待廊這一包（BG-40）：過場舞台用的就是這個地方的背景，可走的關卡要是同一個樣子。
    # 等候臺是走廊長凳；辦公內門旁是霧面玻璃隔間；牆上是巨幅畫像與燈條。
    a.prop('tianqiong_corridor__portrait_frame', 21, y=12, support='wall')
    a.prop('tianqiong_corridor__sleek_bench', 26, y=FLOOR_ROW)
    a.stand(36, 'ⅷ')
    a.prop('tianqiong_corridor__frosted_partition', 38, y=FLOOR_ROW)
    a.prop('tianqiong_corridor__wall_light_strip', 44, y=10, support='wall')
    a.prop('tianqiong_corridor__cloud_sculpture', 46, y=FLOOR_ROW)
    a.prop('tianqiong_corridor__modern_planter', 51, y=FLOOR_ROW)
    a.prop('tianqiong_corridor__water_cooler', 56, y=FLOOR_ROW)
    a.stand(60, 'Ⅻ')
    # 空調維修廊（NE-419）：迴廊右段踩矮台上到天花板下的維修廊，往左走過等候臺上方，盡頭有一包信用點
    # （從地面看得到，要繞上去才拿得到），再從左端落回取件格旁。玻璃邊緣是光影樣板，平台改放在這裡。
    a.platform(48, 52, 17)
    a.platform(16, 46, 14)
    # 門閂門（玩法線 NE-430 的示範）：第 32 欄一道 6 格高的門，門頂穿過維修廊（那一格空出來）；
    # 左端多一排踏板接上維修廊，從上面繞到門閂那一側拉開，回程就是近路。
    a.platform(11, 13, 17)
    a.grid.put(32, 14, '.')
    a.put(32, 19, LATCH_DOOR)
    a.stand(18, 'q', row=13)
    a.stand(24, 'Ⓥ', row=13)   # 維修廊的空調維修口（ST-61）
    for x in (10, 24, 40, 54):
        a.lamp(x, 9)
    a.zone(0, 'reception_white')
    a.features = {'landmark': '辦公內門與等候臺（x=28～36）', 'vertical': '迴廊地面與天花板下的空調維修廊兩層',
                  'secret': '維修廊左端的信用點（x=18，從右段的矮台繞上去）', 'loop': '維修廊從右段上去、左端落回取件格旁'}
    return a


# NE-300：廣場、泵室與夾層改成看得出上下關係的立體交通（data/levels/ch3_layout_v2.json）。
# 原內容整批下移 16 格，保留內容 ID 與舊檔格位映射；新的維修豎井和貨梯同一個條件（ch3_freight_ready）。
LAYOUT_DY = 16


def build_plaza():
    a = kit._v2_area(_build_plaza_v1())
    a.features.update(vertical='廣場地面、纜輪維修道與高處三層', reward='纜輪上方第 15 列信用點：空中再躍',
                      loop='纜輪維修道從左側踏台上去、越過貨梯後落到高架維修盒')
    return a


def build_pump():
    a = kit._v2_area(_build_pump_v1())
    a.trigger(7, "ch3_b_c02_upper_route")
    a.put(37, 35, DECOY_RADIO)   # 誘餌收音機（NE-406）：引開下槽的巡檢，再從上橋繞過
    a.features.update(vertical='下槽、乾燥上橋與天花板上的管線廊三層', reward='管線廊上方第 7 列信用點：空中再躍',
                      shortcut='管線廊左端的維修豎井 ↔ 夾層（貨梯接通後）')
    return a


def build_mezzanine():
    a = kit._v2_area(_build_mezzanine_v1())
    a.put(61, 35, DECOY_RADIO)   # 誘餌收音機與通電纜線（NE-406）：把巡檢引到纜線上
    a.put(63, 35, LIVE_CABLE)
    a.features.update(vertical='維修帶、照護步道與天花板上的豎井廊三層', reward='豎井廊上方第 7 列信用點：空中再躍',
                      loop='貨梯口旁的豎井往上、豎井廊右端下到泵室管線廊，再經外梯或下路回廣場')
    return a


def route_checks(a):
    """各區的明確路線快照（只是格子近似，不代替真玩家輸入）。"""
    start = next(((x, y) for y in range(a.h) for x in range(a.w) if a.grid.at(x, y) == 'P'), None)
    normal = kit.RouteState('normal')
    late = kit.RouteState('air_jump_bound', jump_tiles=10)
    scenarios = {
        'plaza': [(normal, [('control_box', (40, 35)), ('lift', (48, 35)), ('pump', (93, 35)), ('deck', (60, 23)), ('box', (75, 29))],
                   [('reward', (31, 15))]), (late, [('reward', (31, 15))], [])],
        'pump': [(normal, [('wheel', (30, 28)), ('panel', (64, 35)), ('ladder', (76, 28)), ('shaft', (4, 15))], [('reward', (41, 7))]),
                 (late, [('reward', (41, 7))], [])],
        'mezzanine': [(normal, [('booth', (22, 35)), ('clinic', (76, 35)), ('care', (66, 35)), ('shaft', (74, 15))], [('reward', (57, 7))]),
                      (late, [('reward', (57, 7))], [])],
    }
    problems = []
    for state, goals, forbidden in scenarios.get(a.id, []):
        problems += kit.reachable(a, start, goals, state=state)
        for target in forbidden:
            if not kit.reachable(a, start, [target], state=state):
                problems.append(f'{a.id}/{state.name}: {target[0]} 不該用普通跳躍就到得了')
    return problems


PLACEMENT_IDS = {'pawnshop': 'ch1_pawnshop'}

AREAS = (build_pawnshop, build_plaza, build_pump, build_mezzanine, build_clinic, build_gate_hall, build_glass_edge,
         build_showroom, build_office_hall)


def configure():
    """把第一章的工具切到第三章：人物、出入口、主題與劇情接點都換成本章的，字元不和第一章的資源衝突。"""
    clash = sorted(c for c in NPC_CHARS if c in kit.RES or c in PORTALS or c in kit.TRAINING)
    clash += sorted(c for c in PORTALS if c in kit.RES)
    clash += sorted(c for c in ENEMY_CHARS if c in kit.RES or c in NPC_CHARS or c in PORTALS)
    if MAINTENANCE_CREDIT in kit.RES:
        clash.append(MAINTENANCE_CREDIT)
    if clash:
        raise SystemExit(f'第三章的字元和既有資源衝突：{clash}')
    for char, ident in NPC_CHARS.items():
        kit.RES[char] = f'res://data/npcs/{ident}.tres'
    for char, ident in ENEMY_CHARS.items():
        kit.RES[char] = f'res://data/enemies/{ident}.tres'
        kit.ENEMY_NAMES[char] = ENEMY_DISPLAY[char]
    # Keep the original credits_small ID so the old coordinates still restore collected piles.
    kit.RES[MAINTENANCE_CREDIT] = 'res://data/props/credits_maintenance.tres'
    kit.RES.update(MECHANISMS)
    kit.PORTALS = PORTALS
    kit.NPCS = {ident: {**{'rig': '', 'loop': '', 'facing': 1}, **spec} for ident, spec in NPCS.items()}
    kit.THEMES = THEMES
    kit.STORY = STORY
    kit.placement_id = lambda ident: PLACEMENT_IDS.get(ident, f'ch3_{ident}')


def main():
    configure()
    areas = [build() for build in AREAS]
    for a in areas:
        zones = {name: (x0, x1, use) for name, x0, x1, use in COMBAT_ZONES.get(a.id, [])}
        dy = LAYOUT_DY if hasattr(a, 'legacy_layout') else 0
        for name, members in ENCOUNTERS.get(a.id, {}).items():
            x0, x1, _use = zones[name]
            # 指定列的敵人（吊軌）跟著版面一起下移。
            a.encounter(name, x0, x1, [(m[0], m[1], m[2] + dy) if len(m) > 2 else m for m in members])
    problems = []
    for a in areas:
        problems += a.check(flying=('d',) + HANGING)
        start = next(((x, y) for y in range(a.h) for x in range(a.w) if a.grid.at(x, y) == 'P'), None)
        goals = [(a.grid.at(x, y), (x, y)) for y in range(a.h) for x in range(a.w)
                 if a.grid.at(x, y) in (set(kit.RES) - set(HANGING)) | set(PORTALS) | {'C'}]  # 吊軌上的敵人不用走得到
        problems += route_checks(a) if hasattr(a, 'legacy_layout') else kit.reachable(a, start, goals)
    if problems:
        print('\n'.join(problems))
        sys.exit(1)
    kit.write_npc_files()
    for a in areas:
        placed = {e['name']: e for e in a.encounters}
        a.encounters = [{'name': name, 'lock': False, 'x0': x0, 'x1': x1, 'use': use,
                         'members': list(placed.get(name, {}).get('members', [])),
                         'reinforcements': list(placed.get(name, {}).get('reinforcements', []))}
                        for name, x0, x1, use in COMBAT_ZONES.get(a.id, [])]
    kit.write_design(areas)
    for a in areas:
        extra = kit._map_extra(a)
        a.grid.write(a.id, (kit.LEVEL_DIR, f'ch3_{a.id}_map.json'), extra)
    by_id = {a.id: a for a in areas}
    # 累積版以 CampaignEdition 停在此處。開發版接上下一週日的病房路線。
    kit.write_level(by_id['pawnshop'], show_card=True, complete_on_flag='&"ch3_shore_closed"',
                    next_level='"res://data/levels/ch4_pawnshop.tres"')
    sunlit = {'glass_edge', 'showroom', 'office_hall'}
    for a in areas[1:]:
        lighting_events = [('pump_drained', 12, a.w - 2, 'pump_drained', 'ch3_pump_low')] if a.id == 'pump' else ()
        kit.write_level(a, lighting_events=lighting_events, **({'rain': 'false'} if a.id in sunlit else {}))


if __name__ == '__main__':
    main()
