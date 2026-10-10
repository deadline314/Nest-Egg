# 提交給角色 owner 的精確掛點需求（未修改／未套用）

1. RigInput 增加預設 false 的 holds_melee，僅 PlayerVisual 填入真正 player.holds_melee_weapon() 且非電話／死亡／載具狀態；既有槍、NPC、電話與死亡優先序保持。不要用假的槍械 visual_id 來強迫開啟握手。
2. CharacterRig._update_hand_grips 前手依 `(not _weapon_def.is_empty() or input.holds_melee) and not input.dead` 使用既有同一 hand slot 的握持貼圖，維持原支點和骨長。背手仍沿原 two_handed、盾與 action 條件，不因此冒稱重錘雙手握實。
3. PlayerVisual._draw_melee_weapon 在上述握持狀態建立後，以 `hand.to_global(rig.hand_grip_offset(&"hand_front"))` 作真正掌心世界掛點，再 `to_local` 傳給MeleeArt.draw；方向也轉到相同 Canvas local space（現在 to_local 起點＋world 方向混用，實測角差很小但旋轉／縮放時仍需正確契約）。這些是原 owner 的接點；本組沒有修改這三份檔案。
4. 驗兩面向、完整三招、idle/持物/空手、電話、換武器、受擊／死亡、蹲／空中／盾、掌心材質與柄的接合。握手／掌心／武器順序只套一次翻面；不移動圖片腕支點，不拉長手臂，不新增另一個可見手節點。
5. 本組的原生RGBA畫面和距離數據只能核對柄與現有手的位置；公開offset回0及nearest alpha碰線不算掌心握實。敵人腰/胯缺口分交NE-79/90，不改共享骨架來掩蓋。
