# 舞台移動的同一發布時鐘

2026-11-12。NE-267 真 S18 暴露的共用框架問題；候選先在獨立 D 專案驗證，未採 C。

CutsceneActor._process 用本次 render delta 除以位置差，但 idle Tween 在前次 Actor 更新之後，以前次 delta 發布該位移。兩次 delta 不同時，估出的速度並非該移動樣本的速度。物理 Tween 搭配較高 render 頻率則還有沒有新位移的 render 格。

固定 60Hz 的相同角色資料／同一 Actor 沒有這個失敗；只換成 120/30Hz 或 120/60Hz 交替，270/270 個穩態格步態權重不足，實際來源 alpha 材質腳底穿入地面最高 6.63 stage px。真 S18 原生另獨立量到 4.57 stage px。不能改 gait 門檻或以無頭踝點良好取代材質接觸。

候選由 move Tween 發布一致的 position/elapsed sample。角色移動期間只消費這個時鐘的樣本，停止移動後恢復既有 render 更新；NPC/人形動畫本身不改。一般移動保留 idle Tween，持有 hand target 的移動保留 physics Tween，不能改成無條件固定 render/FPS。

以進度差乘原定 duration 得到該 Tween 樣本的 elapsed，再除以 Tween 自己的 speed_scale 還原遊戲時間。該樣本的位移與這份時間共同用於速度、骨架動畫及 reach.apply；reach_speed 仍只在原位置乘一次。零進度、初始進度及最後回呼不能製造零時間／重複骨架步。

每次移動只配置一次狀態與弱引用，以遞增 token 表示演員當前移動的所有權。新移動可以取代舊移動，舊回呼不能再更新位置或套用 then 姿勢。完成、取消、略過、停止處理、死亡、離場、替換與釋放都必須停止發布並釋放控制；不對失效 actor 回呼、不重播坐姿，不改 Story 結果語義。站穩準備與 NE-287 實際 reach 完成等待保留。

驗證須涵蓋實際 Tween/Actor callback 順序、變 render delta、physics-held、場景 speed、零樣本與過期 token，以及原 move/reach 的生命週期回歸。用同一材質腳底／接點守門做舊碼紅與候選綠，再拍真 S18；不以效能或實體手把／鍵盤驗收名義描述自動探針。
