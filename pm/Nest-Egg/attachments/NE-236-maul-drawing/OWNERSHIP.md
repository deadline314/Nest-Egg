# 逐格唯讀掛點與美術接點

基準06c440760。source圖保持原 hash：NE-237-maul-hit-right-2-high 8f2f21b5a28c5e3e3581fed5847cf9f6463fe50509a44c211bdd02fd834d9193；NE-236-natural-late-contact 09dec0d8509ec009e5239c7b82eea0aee4d9a0888e678f326507bf9ac74de8af。

440個真render影格，兩面向3招，3.4x，fixed render timestep60fps，軟體Vulkan。每招真目標HP999→993/991/988，damage signal恰1。這是合成接續的功能與繪製量測，不是真手把或真人遊測。

手腕→前臂的原繪製方向沒有額外翻面：world前臂軸與實際Canvas transform後的shaft軸角差最大0.0000171 rad。兩面向均有限、連續。現有handler把MeleeArt握把起點設在hand_front骨的世界原點（手腕），CharacterRig手掌資料則另有grip_offset=[1.15531,0.22636]。440/440影格grip_variant_closed=false，public hand_grip_offset返回0；不能用這個0宣稱掌心握持已正確。

原grip line只在localX -5..0，已宣告closed掌心到此線中心距1.35385..1.35388世界px；實際open手部不透明像素質心到grip line1.80348..1.80488px。最近一個不透明手像素距線約0.0002px，但那只证明某個邊界碰到，不能證明掌心握實或手指姿勢。質心也不是解剖掌心；原生全彩須獨立檢視。

game/player/player_visual.gd:_draw_melee_weapon 用to_local(hand.global_position)、world forearm direction；沒有讀掌心offset。game/rig/character_rig.gd:_update_hand_grips 僅以_weapon_def非空判斷握手，而近戰visual_id=""，因此握手變體從未启用。原 owner 需提供近戰持物的明確狀態，沿既有手slot啟用握持、掌心與手腕分開；本組不修改PlayerVisual/CharacterRig/RigInput/共享骨架。

獨立繪製可修重錘的連續柄（延伸到槌頭內部）、跨掌心區域的握把、非發光槌頭主体/斜邊/液壓接縫；不改判定、動作時序、舊pose、Player或共享Fx。型錄草稿在另一工作樹，絕不混入武器main交付。

敵人腰/胯全彩缺口為NE-79/90 owner待驗；本組只記錄，不補畫或改共享骨架。槌與整體角色美術仍未完整驗收，NE-236/237保持進行中。

重錘獨立繪製修後440格：已宣告closed掌心到grip中心線0.03067..0.03075世界px，open手部不透明像素質心到grip中心線0.11948..0.12099px。未移動手腕/骨架，也未啟用握手變體（仍0/440closed）；這是握把覆蓋範圍改善，不是新的掌心接線已完成。
