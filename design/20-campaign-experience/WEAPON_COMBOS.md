# 武器節奏、接續與成長實作邊界

2026-10-10，NE-236／NE-237；初始驗證基準 `b4c186ea401dfb29b92e28a0a9c8e7de46f604e3`。

本文件補充 DESIGN，不覆寫章節帳務 ledger。雲端只提供 Godot 4.7.2、Forward+ 軟體 Vulkan與合成輸入證據；人工遊玩、實體手把、硬體 GPU／HDR 分別驗收。

## 來源與採用

本輪核對 [Godot Input 官方文件](https://docs.godotengine.org/en/stable/classes/class_input.html)：按下邊緣與按住是不同狀態；Input.action_press 不等於真實裝置事件。事件與輪詢兩路都測，不能用合成輸入冒稱實機手把。

核對 [PlayStation 開發者談戰鬥](https://blog.playstation.com/2022/10/04/game-developers-explain-what-makes-god-of-war-2018s-combat-tick/)：聲音、動作與受擊停頓共同表現接觸，畫面清楚亦須考慮。以下時序、價格、連段數與成本是本專案的設計／實測值，不是玩家一致最愛或通用業界門檻。

## Ownership 與公開契約

- 本組：game/player/player.gd 的近戰與輸入接點、MeleeSet／MeleeData、data/melee、近戰專用動作 namespace、近戰測試與專用擷取／量測工具。
- art/rigs/action_poses.json 只新增 rin.melee_<武器>_<招式>，不改敵人／NPC／電話動作；沿現有 PlayerVisual 的 pose 與 phase progress 契約接線。
- NE-237 的購買沿 Progression.buy_upgrade／has_upgrade／snapshot／restore；僅擴充武器改裝資料的近戰招式種類與適用武器，不另造貨幣或保存服務。
- 不修改 Story／Main、世界與死亡存檔、章節產生器、CharacterRig／HumanoidAnimator／RigInput／PlayerVisual、共享 Fx、全域 Progression、環境 props／shader 或 release tools。
- 真退出續玩依賴 NE-230；snapshot 回歸只能证明契約，不代稱整輪續玩。近戰購買介面若缺數值對照，交 UI owner 接入既有 description／招式資料。

## 可操作規則

點按近戰鍵或持近戰武器的射擊鍵可以接續；按住只重複第一招，兩鍵一致。每次點按最多保留一筆 buffer，時間到即消失。停止輸入吃完整收招，不強迫打完整連段。命中只在 recovery 的 cancel_after 後准許接續／衝刺；揮空吃滿 recovery。連段尾端不可循環取消回首招。

換武器、受擊、死亡、破盾、電話與載具中斷會清掉 buffer、招式索引與命中集合。換武器保留尚未支付完的動作時間，避免切武器消除揮空風險。攻擊方向於起手鎖定，後续瞄準不把舊傷害框轉到另一側。

近戰武器不靠自動終結技免費跳過電量。充電沿現有 Loadout；每次揮击扣武器電量，可選終段另扣護盾能量。能量不足不消耗部分成本，不啟動招式、不留下連段接續。終段有較長收招且不提早取消。

每 swing 每個 HealthComponent 最多接觸一次；被格擋亦記下接觸，但不當成造成傷害。只有 DAMAGED 產生命中聲、粒子、命中取消與攻擊方停頓；敵人與反應抗性沿既有契約。多目標的同時 freeze 使用 Fx 的 max 規則、不相加；晚進入 sweep 的目標仍須量測累積上限，不改共享 Fx 取得通過。

## 辨識矩陣與分階段交付

| 武器 | 基礎用途 | 風險／選擇 |
|---|---|---|
| 單分子匕首 | 近身快速刺擊、小位移 | 短距離、低單擊衝擊；可選快速追加，停止仍留短招 |
| 熱刃 | 中距離斜斬與反向斬 | 中等收招；可選終段以能量換重擊 |
| 液壓錘 | 低速重擊、少段 | 長起手／收招、有限電量；可選強招保留充電與反制 |
| 離子長柄 | 準星方向刺擊與橫掃 | 近身死角；可選範圍接續不抹除距離取捨 |
| 單分子鞭 | 遠距甩擊 | 更大近身死角、低持續输出；可選回拉，不永久硬直 |

NE-236 包括全部槍械，近戰階段不可勾整票完成。手槍、衝鋒槍、步槍、散彈、雷射、軌道槍、發射器及機甲炮各列姿態／射擊節奏／後座／彈體／命中資料與實際證據。槍械姿態若需要新 rig 接口，由原 owner 實作；本組提出精確要求，不搶寫。

每武器記錄首次傷害延遲、完整時間／取消時間、實际有效距離、持續 DPS、擊退、護盾能量／電量與充電。基礎／升級、揮空／命中、普通／裝甲／頭目及難度分列；資料計算與實際戰鬥量測分開，不用常數表冒充遊玩。

## 遠程動作接點需求（交角色 owner，尚未實作）

目前 PlayerVisual.notify_fired(color) 將每種槍械的 RigInput.recoil 固定為 1.0，武器的 camera_kick 不會改身體／持槍後座。因此單改槍口顏色或鏡頭位移，不能驗收各槍的身體動作。

請原 owner 保持相容地提供 `PlayerVisual.notify_fired(color: Color, strength: float = 1.0)`：既有閃光路由不變，有限、非負的 strength（建議界線 0–2）送既有單幀 RigInput.recoil；非法值安全回落 1。保留既有清脈衝、握持 IK、兩手、空中／蹲／盾／受擊優先序，不新增另一套動畫器。本組可在 WeaponData 與 Player 射擊呼叫端接每武器 strength，原 owner 驗兩面向與接點。此為提出的需求，沒有冒稱接口已存在。

對 railgun／launcher 若需要起手或較長持槍收招，另請原 owner 提供與現有 action/action_t 相容的遠程優先序：電話、受擊、死亡與盾高於射擊，近戰與遠程不互覆。槍械動作由射擊成功與真實 fire_interval 驅動；空彈匣不觸發開火動作，換武器清舊後座，後座不改實際準星／子彈方向。接口交付前，NE-236 的「全部現有槍械」與完整動作驗收保持未勾。
