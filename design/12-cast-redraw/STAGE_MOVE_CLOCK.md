# 舞台移動的同一發布時鐘

2026-11-12。NE-267 真 S18 暴露的共用框架問題；純框架已在獨立已發布基底完成驗證，再採入工作樹；兩份仍含 NPC WIP 的工作檔只在 Git 暫存純時鐘差異。

CutsceneActor._process 用本次 render delta 除以位置差，但 idle Tween 在前次 Actor 更新之後，以前次 delta 發布該位移。兩次 delta 不同時，估出的速度並非該移動樣本的速度。物理 Tween 搭配較高 render 頻率則還有沒有新位移的 render 格。

固定 60Hz 的相同角色資料／同一 Actor 沒有這個失敗；只換成 120/30Hz 或 120/60Hz 交替，270/270 個穩態格步態權重不足，實際來源 alpha 材質腳底穿入地面最高 6.63 stage px。真 S18 原生另獨立量到 4.57 stage px。不能改 gait 門檻或以無頭踝點良好取代材質接觸。

候選由 move Tween 發布一致的 position/elapsed sample。角色移動期間只消費這個時鐘的樣本，停止移動後恢復既有 render 更新；NPC/人形動畫本身不改。一般移動保留 idle Tween，持有 hand target 的移動保留 physics Tween，不能改成無條件固定 render/FPS。

以進度差乘原定 duration 得到該 Tween 樣本的 elapsed，再除以建立移動時的演出速率快照還原遊戲時間；同一份快照同時傳給 Tween.set_speed_scale 與 transport，不呼叫引擎不存在的 Tween getter。該樣本的位移與這份時間共同用於速度、骨架動畫及 reach.apply；reach_speed 仍只在原位置乘一次。零進度、初始進度及最後回呼不能製造零時間／重複骨架步。

Actor 只保留 token 與少量純量，transport 弱引用 Actor／Player，沒有 Tween 參考，避免 Tween Callable 與 transport 形成強引用循環。物理發布已消費的本次 render 間隔只抵扣一次；沒有預估未來 frame 或以大額 catch-up 時鐘延後恢復。一般 idle Tween 仍在 render 後發布，不能將其時間再扣到下一格。

每次移動只配置一次狀態與弱引用，以遞增 token 表示演員當前移動的所有權。新移動可以取代舊移動，舊回呼不能再更新位置或套用 then 姿勢。完成、取消、略過、停止處理、死亡、離場、替換與釋放都必須停止發布並釋放控制；不對失效 actor 回呼、不重播坐姿，不改 Story 結果語義。站穩準備與 NE-287 實際 reach 完成等待保留。

驗證須涵蓋實際 Tween/Actor callback 順序、變 render delta、physics-held、場景 speed、零樣本與過期 token，以及原 move/reach 的生命週期回歸。用同一材質腳底／接點守門做舊碼紅與候選綠，再拍真 S18；不以效能或實體手把／鍵盤驗收名義描述自動探針。

## 交付驗證（2026-11-12）

純發布基底的原碼 108/26 → 時鐘 165/0；原 Cutscene/Locomotion 1946/0。真 S18 使用相同 guest 素材與同一材質腳底 reader，原穿地最大 4.573464 stage px，修後三段 0 穿地／0 雙腳無支撐，最大 .856992／-.067793／.969048，原 1 stage px 門檻不變。這組是含未發布 guest 的額外整合；純七檔不依賴 guest、NPC adapter 或新 motion。其餘 NE267 低 alpha 接縫在原票獨立處理。

原 affected selector 在已發布 8c + 近戰 v8 26 檔 + 純時鐘 7 檔的同一來源上跑 70 組、94,097 checks，0 新／0 已知失敗，exit 0；原工具與過濾器未改。不是各自窄測試的加總，也不宣稱這一輪只有七檔或 headless log 零 ERROR。

[純／整合控制、全部失敗、固定材質與外部原始包索引](../../pm/Nest-Egg/attachments/NE-290-stage-move-clock/README.md)；[原 selector 聯合回歸](../../pm/Nest-Egg/attachments/NE-277-contact-timing-2026-11-11/affected-v8-clock-joint-index.json)。
