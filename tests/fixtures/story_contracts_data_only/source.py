"""Synthetic author content only; never part of the shipped story."""
from ch1_closure import Binding, Option, grant, set_flag, flag

def add_content(spec):
    source = spec.source
    source.bindings["patroller"] = Binding("npc","original NPC author content","res://data/npcs/ch2_patroller.tres")
    source.flag_defaults.update({"test_contract_ack_mode":False,"test_contract_copy_mode":False,"ch2_patrol_note_seen":False,"ch2_patrol_requested":False,"ch2_patrol_copy_received":False})
    source.add("ch2_t_patrol_note_ack","TEST",(("patroller","測試用查核註記。"),("rin","我已讀完。"),("patroller","記下這次閱讀。")),binding="patroller",when=flag("test_contract_ack_mode"),completion=(set_flag("ch2_patrol_note_seen"),))
    source.add("ch2_t_patrol_copy","TEST",(("patroller","這是測試用手動副本。"),("rin","我收下這份副本。"),("patroller","只交付這一次。")),binding="patroller",when=flag("ch2_patrol_requested"),completion=(grant("ch2_patrol_copy"),set_flag("ch2_patrol_copy_received")))
    source.add("ch2_t_patrol_copy_prompt","TEST",(("patroller","是否領取測試用副本？"),),binding="patroller",options=(Option("accept","領取副本","ch2_t_patrol_copy","確認後領取。",intent=(set_flag("ch2_patrol_requested"),)),Option("later","稍後再說",None,"不取得任何物品。")))
    return spec
