#!/usr/bin/env python3
"""第二章「鷺」的區域地圖產生器（ST-19）：輸出 data/levels/ch2_*.tres、ch2_*_map.json、環境主題與人物資料。

沿用第一章產生器的工具（區域格子、出入口、人物與主題的輸出、可通行檢查），只換章節前綴與本章的內容。
落地計畫見 design/13-story-v2/CH02_IMPLEMENTATION.md，劇本見 design/13-story-v2/SCRIPT_CH02.md。
敵人由戰鬥 Session 配置（NE-265、NE-266）：這裡只標出戰鬥區與繞道，不放敵人。
用法：python3 tools/level/build_ch2.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
sys.dont_write_bytecode = True
import build_ch1 as kit  # noqa: E402
from scenery_placement import prepare_props  # noqa: E402

kit.PREFIX = 'ch2'
kit.CHAPTER = 'ch2_heron'
AREA = kit.AREA
H = kit.H
Area = kit.Area

# ---------------------------------------------------------------------------
# 人物與可調查物件：字元 -> 資料檔（台詞由劇本的分派場景依進度挑選，見 tools/story/ch2_source.py）
# ---------------------------------------------------------------------------
NPC_CHARS = {
    'ⓞ': 'ch2_old_k', 'Ⓡ': 'ch2_radio', 'ⓔ': 'ch2_egret', 'Ⓖ': 'ch2_patroller', 'Ⓥ': 'ch2_vig', 'ⓐ': 'ch2_ali_market',
    'Ⓦ': 'ch2_rent_window', 'Ⓑ': 'ch2_banyan', 'Ⓝ': 'ch2_notice_screen', 'ⓗ': 'ch2_hawker', 'Ⓐ': 'ch2_ali_home',
    'ⓛ': 'ch2_collection_book', 'ⓧ': 'ch2_guard', 'ⓙ': 'ch2_sc1_lever', 'ⓓ': 'ch2_drying_desk', 'ⓘ': 'ch2_isolation_diagram',
    'ⓨ': 'ch2_ledger_door', 'ⓜ': 'ch2_ledger_cabinet', 'ⓟ': 'ch2_xiaowei', 'ⓣ': 'ch2_terminal', 'ⓢ': 'ch2_ali_lounge',
    'ⓠ': 'ch2_guest_entry',
    'Ⓔ': 'ch2_egret_booth',
}
# 人物（kind 0）有骨架外觀；物件（kind 1）只有互動提示。rig 用既有外觀；沒有專屬外觀的配角先借用，缺口列在 NE-267。
P, O = 0, 1
NPCS = {
    'ch2_old_k': dict(name='老 K', speaker='old_k', rig='old_k', loop='wipe_hands', facing=1, prompt='{interact} 和老 K 說話',
                      talks=[('ch2_dispatch_old_k', 0)]),
    'ch2_radio': dict(name='工作檯的收音機', speaker='label', kind=O, prompt='{interact} 看看工作檯的收音機', talks=[('ch2_dispatch_radio', 0)]),
    'ch2_egret': dict(name='鷺', speaker='egret', rig='egret', pose='lean', loop='yawn', facing=-1, prompt='{interact} 和鷺說話',
                      talks=[('ch2_dispatch_egret', 0)]),
    'ch2_patroller': dict(name='巡帳員', speaker='patroller', rig='resident', loop='glance', facing=-1, prompt='{interact} 出示查核證',
                          talks=[('ch2_dispatch_patroller', 0)]),
    'ch2_vig': dict(name='利息', speaker='vig', rig='vig', loop='tablet', facing=-1, prompt='{interact} 和利息說話',
                    talks=[('ch2_dispatch_vig', 0)]),
    'ch2_ali_market': dict(name='阿梨', speaker='ali', rig='ali', loop='read_note', facing=1, prompt='{interact} 和阿梨說話',
                           talks=[('ch2_dispatch_ali_market', 0)], spawn_unless_flag='ch2_audit_submitted'),
    'ch2_rent_window': dict(name='租攤視窗', speaker='window_clerk', kind=O, prompt='{interact} 到租攤視窗查合約', talks=[('ch2_dispatch_rent_window', 0)]),
    'ch2_banyan': dict(name='榕伯', speaker='banyan', rig='banyan', loop='stir', facing=1, prompt='{interact} 和榕伯說話',
                       talks=[('ch2_dispatch_banyan', 0)]),
    'ch2_notice_screen': dict(name='公告屏', speaker='label', kind=O, prompt='{interact} 看公告屏', talks=[('ch2_dispatch_notice', 0)]),
    'ch2_hawker': dict(name='小販', speaker='hawker', rig='resident', loop='sort_gear', facing=-1, prompt='{interact} 和小販說話',
                       talks=[('ch2_dispatch_hawker', 0)]),
    'ch2_ali_home': dict(name='阿梨', speaker='ali', rig='ali', loop='stir', facing=-1, prompt='{interact} 敲門找阿梨',
                         talks=[('ch2_dispatch_ali_home', 0)]),
    'ch2_collection_book': dict(name='代收簿', speaker='label', kind=O, prompt='{interact} 翻裝卸間的代收簿', talks=[('ch2_dispatch_collection_book', 0)]),
    'ch2_guard': dict(name='倚著牆的守衛', speaker='label', kind=O, prompt='{interact} 查看倚著牆的守衛', talks=[('ch2_dispatch_guard', 0)]),
    'ch2_sc1_lever': dict(name='橋梯拉桿', speaker='label', kind=O, prompt='{interact} 放下通往代收處的橋梯', talks=[('ch2_dispatch_sc1', 0)]),
    'ch2_drying_desk': dict(name='乾燥作業桌', speaker='label', kind=O, prompt='{interact} 在作業桌上對帳', talks=[('ch2_dispatch_reconcile', 0)]),
    'ch2_isolation_diagram': dict(name='隔離箱示意圖', speaker='label', kind=O, prompt='{interact} 看隔離箱示意圖', talks=[('ch2_dispatch_diagram', 0)]),
    'ch2_ledger_door': dict(name='帳房的門', speaker='label', kind=O, prompt='{interact} 進帳房找阿勇', talks=[('ch2_dispatch_ledger_door', 0)]),
    'ch2_ledger_cabinet': dict(name='帳櫃', speaker='label', kind=O, prompt='{interact} 打開帳櫃', talks=[('ch2_dispatch_cabinet', 0)]),
    'ch2_xiaowei': dict(name='小薇', speaker='xiaowei', rig='xiaowei', loop='glance', facing=1, prompt='{interact} 和小薇說話',
                        talks=[('ch2_dispatch_xiaowei', 0)], spawn_unless_flag='ch2_yong_subdued'),
    'ch2_terminal': dict(name='公用委託終端', speaker='terminal', kind=O, prompt='{interact} 在委託終端上傳證據', talks=[('ch2_dispatch_terminal', 0)]),
    'ch2_ali_lounge': dict(name='阿梨', speaker='ali', rig='ali', loop='wipe_hands', facing=-1, prompt='{interact} 和阿梨說話',
                           talks=[('ch2_dispatch_ali_lounge', 0)], spawn_requires_flag='ch2_audit_submitted'),
    'ch2_guest_entry': dict(name='客人簿', speaker='label', kind=O, prompt='{interact} 看阿梨今晚的工作', talks=[('ch2_dispatch_guest_entry', 0)],
                            spawn_requires_flag='ch2_audit_submitted'),
    'ch2_egret_booth': dict(name='鷺', speaker='egret', rig='egret', loop='yawn', facing=-1, prompt='{interact} 和鷺說話',
                            talks=[('ch2_dispatch_egret_booth', 0)], spawn_requires_flag='ch2_egret_transport_done', spawn_unless_flag='ch2_audit_submitted'),
}

# ---------------------------------------------------------------------------
# 出入口：字元 -> 設定（欄位同第一章）。目標區域留空＝鎖死的門。
# ---------------------------------------------------------------------------
PORTALS = {
    # 當舖（早上）
    'F': dict(id='pawn_front', to=AREA('harbor_street'), target='street_home', mode=0, prompt='{interact} 出門', style='door',
              requires='ch2_brief_done', locked='先上屋頂，鷺在茶座等你拿查核證。'),
    'S': dict(id='pawn_stairs', to=AREA('rooftop'), target='roof_stairs', mode=0, prompt='{interact} 上屋頂', style='ladder', w=20, h=152,
              requires='ch2_morning_settled', locked='先和老 K 把昨晚的報酬對完。'),
    'K': dict(id='pawn_basement', to='', target='', mode=0, prompt='{interact} 地下室', locked='地下室的門鎖著，老 K 說裡面在漏水。', style='hidden', w=32, h=48),
    # 屋頂
    'T': dict(id='roof_stairs', to=AREA('pawnshop'), target='pawn_stairs', mode=0, prompt='{interact} 下樓', style='hidden', w=24, h=44),
    # 港區街道（安全街段）
    'h': dict(id='street_home', to=AREA('pawnshop'), target='pawn_front', mode=0, prompt='{interact} 回當舖', style='door'),
    'm': dict(id='street_market', to=AREA('market_gate'), target='gate_street', mode=0, prompt='{interact} 往市集', style='road', w=28, h=44),
    # 市集入口
    'Ⅰ': dict(id='gate_street', to=AREA('harbor_street'), target='street_market', mode=0, prompt='{interact} 回港區街道', style='road', w=28, h=44),
    'Ⅱ': dict(id='gate_market', to=AREA('market'), target='market_gate', mode=0, prompt='{interact} 進公眾攤道', style='road', w=28, h=44,
              requires='ch2_brief_done', locked='公眾攤道要查核證，鷺在當舖屋頂等你。'),
    'Ⅲ': dict(id='gate_lounge', to=AREA('lounge_front'), target='lounge_gate', mode=0, prompt='{interact} 往復原館', style='road', w=28, h=44),
    'Ⅳ': dict(id='gate_family', to=AREA('ledger_office'), target='office_family', mode=0, prompt='{interact} 走家屬出口回帳房', style='door', w=28, h=56,
              requires='ch2_egret_transport_done', locked='家屬出口從帳房那一側鎖著。'),
    # 公眾攤道與代收處
    'Ⅴ': dict(id='market_gate', to=AREA('market_gate'), target='gate_market', mode=0, prompt='{interact} 回市集入口', style='road', w=28, h=44),
    'Ⅵ': dict(id='market_stairs', to=AREA('ali_home'), target='home_stairs', mode=0, prompt='{interact} 走後樓外梯', style='door'),
    'Ⅶ': dict(id='market_cargo', to=AREA('loading'), target='loading_market', mode=0, prompt='{interact} 往雨棚背面的貨道', style='road', w=28, h=44,
              requires='ch2_market_contact_done', locked='先到代收處問清楚這筆代收款，再去後面查帳。'),
    'Ⅷ': dict(id='market_sc1', to=AREA('loading'), target='loading_sc1', mode=0, prompt='{interact} 走橋梯捷徑到裝卸間', style='door',
              requires='ch2_sc1_open', locked='橋梯收在上面，要從裝卸間那一側放下來。'),
    # 阿梨的小廚房
    'Ⅸ': dict(id='home_stairs', to=AREA('market'), target='market_stairs', mode=0, prompt='{interact} 下後樓外梯', style='door', w=24, h=56),
    # 雨棚背面與裝卸間
    'Ⅹ': dict(id='loading_market', to=AREA('market'), target='market_cargo', mode=0, prompt='{interact} 回公眾攤道', style='road', w=28, h=44),
    'Ⅺ': dict(id='loading_sc1', to=AREA('market'), target='market_sc1', mode=0, prompt='{interact} 走橋梯回代收處', style='door',
              requires='ch2_sc1_open', locked='橋梯還收著，旁邊的拉桿可以放下來。'),
    'Ⅻ': dict(id='loading_ledger', to=AREA('ledger_front'), target='front_loading', mode=0, prompt='{interact} 進北棟貨門', style='door', w=28, h=56,
              requires='ch2_market_reconciled', locked='貨門要核對過的卸貨批號，先在作業桌把三張紙對完。'),
    # 帳房前室
    'ⅰ': dict(id='front_loading', to=AREA('loading'), target='loading_ledger', mode=0, prompt='{interact} 回裝卸間', style='door', w=28, h=56),
    'ⅱ': dict(id='front_office', to=AREA('ledger_office'), target='office_front', mode=0, prompt='{interact} 進二樓帳房', style='door', w=28, h=56,
              requires='ch2_yong_intro_seen', locked='先敲門，看阿勇要怎麼對這筆帳。'),
    # 二樓帳房
    'ⅲ': dict(id='office_front', to=AREA('ledger_front'), target='front_office', mode=0, prompt='{interact} 回前室', style='door', w=28, h=56),
    'ⅳ': dict(id='office_family', to=AREA('market_gate'), target='gate_family', mode=0, prompt='{interact} 走家屬出口到市集電話亭', style='door', w=28, h=56,
              requires='ch2_egret_transport_done', locked='先撐開家屬出口，讓人把鷺抬出去。'),
    # 復原館外
    'ⅴ': dict(id='lounge_gate', to=AREA('market_gate'), target='gate_lounge', mode=0, prompt='{interact} 回市集入口', style='road', w=28, h=44),
}

THEMES = {
    # 區域 -> (地形材質, 立面清單, 室內牆面貼圖, 鏤空機率, 天空, 道具資料夾)
    'pawnshop': ('concrete', ['shopfront', 'brick_block'], 'brick', 0.0, 'sky_storm', ['pawnshop_front', 'pawnshop_kitchen', 'basement_door', 'harbor_street']),
    'rooftop': ('rooftop', ['apartment', 'brick_block'], None, 0.22, 'sky_storm', ['rooftop']),
    'harbor_street': ('asphalt', ['shopfront', 'apartment', 'shutter_block'], None, 0.22, 'sky_storm', ['harbor_street', 'anchor_phone_booth']),
    'market_gate': ('asphalt', ['shopfront', 'shutter_block'], None, 0.22, 'sky_storm', ['neon_market', 'anchor_phone_booth', 'harbor_street']),
    'market': ('asphalt', ['shopfront', 'apartment'], None, 0.22, 'sky_storm', ['neon_market', 'harbor_street', 'accounting_lobby']),
    'ali_home': ('concrete', ['apartment'], 'brick', 0.0, 'sky_storm', ['pawnshop_kitchen', 'dawn_noodle_stall', 'harbor_street']),
    'loading': ('concrete', ['warehouse', 'shutter_block'], None, 0.22, 'sky_storm', ['dock_warehouse', 'neon_market', 'harbor_street', 'pawnshop_kitchen']),
    'ledger_front': ('concrete', ['warehouse'], 'hangar_wall', 0.0, 'sky_storm', ['yong_hideout', 'accounting_lobby', 'anchor_phone_booth']),
    'ledger_office': ('concrete', ['warehouse'], 'hangar_wall', 0.0, 'sky_storm', ['yong_hideout']),
    'lounge_front': ('asphalt', ['facility_wall', 'shutter_block'], None, 0.22, 'sky_storm', ['clinic', 'revival_lounge']),
}

# 劇情接點：進場劇情與機關頻道。
STORY = {
    'pawnshop': dict(intro='ch2_s01_morning'),
    # 阿勇頭目戰（NE-265）制伏時啟動這個頻道，關卡寫入制伏旗標；帳櫃與小薇的劇情讀這個旗標。
    'ledger_office': dict(done={'ch2_yong_down': 'ch2_yong_subdued'}),
}

# 戰鬥區（交給戰鬥 Session 配置，NE-266）：區域 -> [(名稱, x0, x1, 用途)]。這裡只寫進設計資料，不放敵人。
COMBAT_ZONES = {
    'market_gate': [('入口押運手', 30, 48, '短戰，可從上層公眾攤道繞過'), ('入口票據投手', 56, 74, '短戰，可從上層公眾攤道繞過')],
    'loading': [('下層貨道一', 24, 44, '可從雨棚上層繞過'), ('下層貨道二', 60, 80, '可從電線橋繞過')],
    'ledger_office': [('阿勇與兩名小弟', 8, 58, '頭目戰（NE-265）；小薇的隔間不是戰區')],
}


# ---------------------------------------------------------------------------
# 區域
# ---------------------------------------------------------------------------

def build_pawnshop():
    """H1 當舖，隔天早上：老 K 在櫃台結算（S01），工作檯的收音機可以修（S02），樓梯上屋頂找鷺。"""
    a = Area('pawnshop', '當舖（早上）', 112, 20, indoor=True)
    kit.pawnshop_shell(a)
    a.stand(40, 'P')
    a.stand(43, 'K')
    a.stand(50, 'ⓞ')
    a.stand(56, 'V')
    a.stand(61, 'Ⓡ')
    a.stand(74, 'F')
    a.stand(108, 'S')
    a.features = {'landmark': '櫃台與工作檯（x=50～61）：早上的結算與收音機都在這裡'}
    return a


def build_rooftop():
    """H7 屋頂茶座：鷺坐在破傘下（S03、S04、S22）。"""
    a = Area('rooftop', '屋頂茶座', 72, 18)
    kit.rooftop_shell(a)
    a.stand(3, 'T')
    a.stand(5, 'P')
    a.stand(40, 'ⓔ')
    a.features = {'landmark': '破傘下的茶座（x=38）：雨量屏在遠處亮著'}
    return a


def build_harbor_street():
    """H5 安全街段：當舖前門到市集入口，中間是 B1 電話亭。"""
    a = Area('harbor_street', '港區街道（白天）', 64, 20)
    a.stand(3, 'h')
    a.stand(6, 'P')
    a.stand(30, 'C')
    a.stand(61, 'm')
    a.prop('anchor_phone_booth__phone_booth', 30)
    a.prop('harbor_street__umbrella_vending', 9)
    a.prop('harbor_street__fish_cart', 18)
    a.prop('harbor_street__stacked_neon_signs', 24, y=8)
    a.prop('anchor_phone_booth__news_rack', 37)
    a.prop('harbor_street__parked_scooter', 46)
    a.prop('harbor_street__steam_manhole', 52)
    a.prop('harbor_street__restore_queue_sign', 57)
    # 戶外街燈約 4 公尺高（地面上 8 格，同第一章街道，BG-36）。
    a.lamp(14, 12)
    a.lamp(34, 12)
    a.lamp(54, 12)
    a.zone(0, 'alley_calm')
    a.features = {'landmark': 'B1 電話亭（x=30）'}
    return a


def build_market_gate():
    """H12a 市集入口：巡帳員看證（S05），地面兩個戰鬥區可從上層公眾攤道繞過；B3 電話亭；往復原館、家屬出口。"""
    a = Area('market_gate', '市集入口', 120, 20)
    a.combat = True
    a.stand(2, 'Ⅰ')
    a.stand(5, 'P')
    a.stand(18, 'Ⓖ')
    a.prop('neon_market__cut_lock_gate', 22)
    # 上層公眾攤道：x=26～80，第 15 列；兩端有階梯平台上下（跳 3～4 格）
    a.platform(24, 26, 17)
    a.platform(27, 80, 14)
    a.platform(81, 83, 17)
    a.prop('neon_market__tv_stack_stall', 35)
    a.prop('neon_market__produce_stall', 62)
    a.stand(50, 'c', row=13)
    a.trigger(88, 'ch2_b_booth_b3')
    a.stand(92, 'C')
    a.prop('anchor_phone_booth__phone_booth', 92)
    a.prop('anchor_phone_booth__restore_arrow_sign', 95)
    a.stand(96, 'Ⓔ')   # 鷺在 B3 電話亭醒來（S14），搬送完成後才出現
    a.stand(100, 'Ⅲ')
    a.stand(108, 'Ⅳ')
    a.stand(117, 'Ⅱ')
    a.prop('harbor_street__tide_gauge', 112)
    # 戶外街燈約 4 公尺高（BG-36）：地面上的燈在第 12 列，上層攤道（第 14 列）上的燈在第 9 列。
    for x in (12, 86, 104):
        a.lamp(x, 12)
    for x in (30, 48, 66):
        a.lamp(x, 9)
    # 巡帳員旁邊的台階下多一盞低燈，入口第一個戰區的敵人輪廓才不會沒進夜色。
    a.lamp(22, 15)
    a.zone(0, 'market')
    a.features = {'loop': '上層公眾攤道（x=24～83，第 14 列）：可以完全繞過地面兩個戰鬥區',
                  'landmark': '市場的水位尺（x=112）', 'reward': '公眾攤道中段的信用點（x=50）',
                  'secret': '無', 'vertical': '地面與攤道兩層'}
    return a


def build_market():
    """H12b 公眾攤道：代收處（S06）、租攤視窗（證據 A）、榕伯涼茶攤、公告屏、小販；後樓外梯到阿梨家，往後面的貨道。"""
    a = Area('market', '公眾攤道', 140, 20)
    a.stand(2, 'Ⅴ')
    a.stand(5, 'P')
    # 代收處：利息在收款臺後、阿梨在臺前
    a.prop('neon_market__debt_desk', 28)
    a.stand(30, 'Ⓥ')
    a.stand(25, 'ⓐ')
    a.prop('neon_market__permit_board', 38)
    # 租攤視窗
    a.prop('accounting_lobby__ticket_machine', 50)
    a.stand(53, 'Ⓦ')
    a.prop('accounting_lobby__contract_stand', 56)
    # 榕伯的涼茶攤
    a.prop('neon_market__tea_urn', 70)
    a.stand(72, 'Ⓑ')
    a.prop('harbor_street__umbrella_stand', 75)
    # 公告屏與小販
    a.prop('neon_market__speech_screen', 90)
    a.stand(90, 'Ⓝ')
    a.stand(101, 'ⓗ')
    a.prop('neon_market__produce_stall', 104)
    # 後樓外梯（上到三樓小廚房）與橋梯捷徑（從裝卸間放下）
    a.prop('neon_market__ad_pillar', 112)
    a.stand(116, 'Ⅵ')
    a.stand(124, 'Ⅷ')
    a.stand(137, 'Ⅶ')
    for x in (14, 34, 54, 74, 94, 114, 132):
        a.lamp(x, 12)  # 戶外街燈約 4 公尺高（BG-36）
    a.zone(0, 'market')
    a.features = {'landmark': '公告屏（x=90）：沈望的週年演說', 'shortcut': '橋梯捷徑（x=124）：從裝卸間放下後直通'}
    return a


def build_ali_home():
    """H21 阿梨的三樓小廚房：一張桌、一口湯鍋、洗碗池（S07），零戰鬥。"""
    a = Area('ali_home', '阿梨的小廚房', 48, 20, indoor=True)
    a.ceiling(1, 46, 10)
    a.stand(3, 'Ⅸ')
    a.stand(6, 'P')
    a.prop('harbor_street__umbrella_stand', 9)
    a.prop('dawn_noodle_stall__noodle_bowls_table', 20)
    a.prop('dawn_noodle_stall__broth_stove', 30)
    a.stand(32, 'Ⓐ')
    a.prop('pawnshop_kitchen__dish_cabinet', 38)
    a.prop('dawn_noodle_stall__blank_sign_board', 43)
    a.prop('dawn_noodle_stall__hanging_lantern', 25, support='ceiling', ceiling_row=10)
    for x in (12, 26, 40):
        a.lamp(x, 11)
    a.zone(0, 'residential')
    a.features = {'landmark': '門口那把補過的油紙傘（x=9）'}
    return a


def build_loading():
    """H12c 雨棚背面：下層貨道與雨棚上層成環，剪斷的電線橋（S09），裝卸間代收簿（證據 C），乾燥作業桌對帳（S10），北棟貨門。"""
    a = Area('loading', '雨棚背面與裝卸間', 150, 20)
    a.combat = True
    a.stand(2, 'Ⅹ')
    a.stand(5, 'P')
    # 雨棚上層：x=14～96，第 13 列；中段是剪斷電線的橋
    a.platform(10, 12, 17)
    a.platform(13, 96, 13)
    a.platform(97, 99, 17)
    a.prop('harbor_street__pole_wire_knot', 52)
    a.trigger(46, 'ch2_s09_wire')
    # 下層貨道（戰鬥區）
    a.prop('dock_warehouse__wrapped_pallets', 36)
    a.prop('dock_warehouse__float_drum_crate', 68)
    a.stand(84, 'ⓧ')
    # 橋梯拉桿（SC1）與捷徑口
    a.stand(92, 'ⓙ', row=12)
    a.stand(100, 'Ⅺ')
    # 裝卸間
    a.ceiling(104, 148, 10)
    a.block(104, 104, 10, 16)
    a.stand(112, 'ⓛ')
    a.prop('dock_warehouse__open_container', 120)
    a.stand(128, 'ⓓ')
    a.prop('pawnshop_kitchen__dining_table', 128)
    a.stand(134, 'c')
    a.stand(146, 'Ⅻ')
    # 雨棚上層的燈照棚頂，下層貨道另掛棚下燈（棚頂第 13 列擋住上方的光）。
    for x in (30, 70):
        a.lamp(x, 9)
    for x in (20, 40, 60, 80):
        a.lamp(x, 15)
    for x in (110, 124, 140):
        a.lamp(x, 11)
    # 雨棚背面沿用市集的燈色（貨運區的燈有三成是壞的，下層貨道會暗到看不見地面邊緣）；裝卸間用整排亮著的機庫燈。
    a.zone(0, 'market')
    a.zone(104, 'hangar', 6)
    a.features = {'loop': '下層貨道與雨棚上層（x=10～99）成環', 'shortcut': '橋梯捷徑 SC1（x=92 拉桿、x=100 梯口）回代收處',
                  'secret': '乾燥盒的信用點（x=134）', 'landmark': '剪斷電線的橋（x=46～52）', 'vertical': '地面與雨棚兩層'}
    return a


def build_ledger_front():
    """H13 前室：電話亭、隔離箱示意圖、帳房的門（S11 登場）。"""
    a = Area('ledger_front', '北棟二樓前室', 56, 20, indoor=True)
    a.ceiling(1, 54, 10)
    a.stand(3, 'ⅰ')
    a.stand(6, 'P')
    a.stand(16, 'C')
    a.prop('anchor_phone_booth__phone_booth', 16)
    a.prop('yong_hideout__debt_blackboard', 28, y=13, support='wall')
    a.stand(28, 'ⓘ')
    a.prop('yong_hideout__money_sacks', 38)
    a.stand(46, 'ⓨ')
    a.stand(52, 'ⅱ')
    for x in (12, 30, 46):
        a.lamp(x, 11)
    a.zone(0, 'warehouse_interior')
    a.features = {'landmark': '隔離箱示意圖（x=28）：主箱永久解除、側箱只能暫停'}
    return a


def build_ledger_office():
    """H13 二樓帳房：戰區（兩層可繞鐵棍）、小薇在後方高臺的玻璃隔間、帳櫃、家屬出口。頭目戰由 NE-265 製作。"""
    a = Area('ledger_office', '二樓帳房', 72, 20, indoor=True)
    a.combat = True
    a.ceiling(1, 70, 6)
    a.stand(3, 'ⅲ')
    a.stand(6, 'P')
    # 兩層：中段平台可繞過鐵棍（第 15 列）
    a.platform(18, 30, 15)
    a.platform(40, 52, 15)
    # 小薇的玻璃隔間：後方高臺（第 10 列），玻璃與戰區分開
    a.block(58, 69, 11, 11)
    a.stand(63, 'ⓟ', row=10)
    a.prop('yong_hideout__xiaowei_bed', 64, y=10)
    a.prop('yong_hideout__toy_corner', 60, y=10)
    a.prop('yong_hideout__banker_desk', 12)
    a.prop('yong_hideout__ledger_wall', 34, y=13, support='wall')
    a.prop('yong_hideout__teller_cage', 46)
    a.stand(54, 'ⓜ')
    a.prop('yong_hideout__vault_safe', 54)
    a.prop('yong_hideout__pendant_bulbs', 30, support='ceiling', ceiling_row=6)
    a.stand(68, 'ⅳ')
    for x in (14, 34, 50):
        a.lamp(x, 7)
    a.zone(0, 'warehouse_interior')
    a.features = {'arena': '阿勇戰區（x=8～58），兩層平台繞鐵棍', 'landmark': '帳櫃（x=54）', 'vertical': '地面與中段平台兩層',
                  'loop': '家屬出口（x=68）搬送後通到市集電話亭', 'reward': '帳櫃裡的原帳與索引'}
    return a


def build_lounge_front():
    """H10 復原館外：公用委託終端（S15）、休息桌（S16）、客人簿入口（S17；客人簿是阿梨視角的演出，見劇本 S17～S21）。"""
    a = Area('lounge_front', '復原館外', 56, 20)
    a.stand(2, 'ⅴ')
    a.stand(5, 'P')
    a.ceiling(10, 54, 4)
    a.stand(16, 'ⓣ')
    a.prop('clinic__report_cabinet', 16)
    a.prop('revival_lounge__round_table_stools', 30)
    a.stand(33, 'ⓢ')
    a.stand(44, 'ⓠ')
    a.prop('revival_lounge__booth_sofa', 48)
    a.lamp(16, 14)
    a.lamp(34, 14)
    a.zone(0, 'market')
    a.features = {'landmark': '委託終端（x=16）'}
    return a


# 和第一章共用空間的區域沿用第一章審過的擺設位置（scenery_placement.json 的 overrides）。
PLACEMENT_IDS = {'pawnshop': 'ch1_pawnshop', 'rooftop': 'ch1_rooftop'}

AREAS = (build_pawnshop, build_rooftop, build_harbor_street, build_market_gate, build_market, build_ali_home, build_loading,
         build_ledger_front, build_ledger_office, build_lounge_front)


def configure():
    """把第一章的工具切到第二章：人物、出入口、主題與劇情接點都換成本章的，字元不和第一章的資源衝突。"""
    clash = sorted(c for c in NPC_CHARS if c in kit.RES or c in PORTALS or c in kit.TRAINING)
    clash += sorted(c for c in PORTALS if c in kit.RES)
    if clash:
        raise SystemExit(f'第二章的字元和既有資源衝突：{clash}')
    for char, ident in NPC_CHARS.items():
        kit.RES[char] = f'res://data/npcs/{ident}.tres'
    kit.PORTALS = PORTALS
    kit.NPCS = {ident: {**{'rig': '', 'loop': '', 'facing': 1}, **spec} for ident, spec in NPCS.items()}
    kit.THEMES = THEMES
    kit.STORY = STORY


def main():
    configure()
    areas = [build() for build in AREAS]
    problems = []
    for a in areas:
        problems += a.check()
        start = next(((x, y) for y in range(H) for x in range(a.w) if a.grid.at(x, y) == 'P'), None)
        goals = [(a.grid.at(x, y), (x, y)) for y in range(H) for x in range(a.w)
                 if a.grid.at(x, y) in set(kit.RES) | set(PORTALS) | {'C'}]
        problems += kit.reachable(a, start, goals)
    if problems:
        print('\n'.join(problems))
        sys.exit(1)
    kit.write_npc_files()
    for a in areas:
        a.encounters = [{'name': name, 'lock': False, 'x0': x0, 'x1': x1, 'members': [], 'reinforcements': [], 'use': use}
                        for name, x0, x1, use in COMBAT_ZONES.get(a.id, [])]
    kit.write_design(areas)
    for a in areas:
        extra = {"props": prepare_props(a.props, PLACEMENT_IDS.get(a.id, f'ch2_{a.id}'))}
        if a.regions:
            extra["regions"] = a.regions
        a.grid.write(a.id, (kit.LEVEL_DIR, f'ch2_{a.id}_map.json'), extra)
    by_id = {a.id: a for a in areas}
    kit.write_level(by_id['pawnshop'], show_card=True)
    for ident in ('rooftop', 'harbor_street', 'market_gate', 'market', 'ali_home', 'loading', 'ledger_front', 'ledger_office',
                  'lounge_front'):
        # 屋頂的章末接第三章的週日早上（當舖）。
        extra = {'complete_on_flag': '&"ch2_heron_closed"', 'next_level': '"res://data/levels/ch3_pawnshop.tres"'} if ident == 'rooftop' else {}
        kit.write_level(by_id[ident], **extra)


if __name__ == '__main__':
    main()
