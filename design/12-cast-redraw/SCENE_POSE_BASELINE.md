# NE-222：第一章姿勢與產生器交接基線

此文件交付給後續故事 Session 使用。角色接縫、外套、全動作與完整美術驗收仍由 NE-222 負責；姿勢資料檢查不能替代逐格外觀驗收。ST-16 尚未生成的演出不計入已驗證範圍。

## 可重跑的來源與介面

`tools/story/build_ch1_story.py` 是來源，`data/story/ch1_kasa.json` 是輸出。站位、地面線、比例及鏡頭沿用目前已合入的資料；台詞、任務、旗標及出场不在本次修正范围。

新第一章動畫場景由 animated() 宣告 `pose_policy: supported`。CutsceneChecker.validate() 實際檢查 actor.pose、pose.pose、move.pose、move.then，以及 choice／branch 的展開步驟。sit／lean／squat／crouch／kneel／dead 都須在同一步有非空字串 `pose_reason` 與 `pose_support`。不支援的動畫名稱仍被原本的姿勢檢查拒絕；不能因填了理由就使用尚未實作的 kneel。

actor()、pose()、move() 均接受 pose_reason／pose_support 選填參數。描述實際用途、接觸對象與量測位置；不能填「比較好看」或虛構支撐來繞過。坐姿仍用骨架實測的 sit_y，起身需回到舞台 ground_y；鏡頭沿用 clamp_camera_y，腳底不被字幕蓋住。

例如：

```python
actor('rin', 'rin', 316, sit_y(st, 'rin', 196), 1,
      scale=actor_scale(st, 'rin'), pose='sit', speaker='rin',
      pose_reason='復原後坐在檢查台邊緣醒來。',
      pose_support='診間檢查台座面：舞台 x=316、y=196；腳底由 sit_y 量測。')
```

資料檢查只保證缺漏／空白／錯誤型別會失敗；語意是否成立、臀部／背／腳是否真的接觸對象，仍須量測与看原生遊戲圖。既有舊章過場未宣告此政策；本次不批量改寫其劇本。新第一章三場與後續由此產生器建立的場景均使用政策，回歸測試防止本章三場移除政策。

## 第一章三場姿勢基線

| 場景 | 演員、姿態與理由 | 接觸／檢查範圍 |
|---|---|---|
| ch1_c01_open | 凜站著在櫃台前接差事；老 K 站在櫃台旁擦手、說話。取消無理由的開場蹲姿。 | 凜 x=385、面向左、腳底 y=348、scale=3.4；老 K x=175、面向右、scale=3.7。站姿修前／修後原生 1920×1080。 |
| ch1_c09_wake | 凜復原後坐在檢查台邊緣醒來，談話後起身。燈為聲音，沒有借角色站位。 | 座面 x=316、y=196；坐姿由 sit_y 計算，起身回舞台地面 y=280。保留自動播放的坐、起身畫面；全過渡逐格與接縫仍在 NE-222 驗收。 |
| ch1_c14_home | 凜從門口走向老 K；老 K 站在爐前，转身取水再走回，都是地面行走與站姿。 | 地面 y=304；凜 x=575→330；老 K x=120→500→190。保留自動播放畫面；全動態接縫仍在 NE-222 驗收。 |

## 重跑與交接

1. 更新產生器後重新產生；確認输出 diff 只包含授权的内容。舞台的 source_width 是已交付的來源比例契約，重新產生不得删掉它或改第一章地圖。
2. 執行受影響的故事、姿勢、圖層與章節測試。資料負向案例須證明「缺理由」与「有理由但缺支撐」失敗，也要覆盖 move.then。
3. 原生 Forward+ 拍三場，量地面／座面接觸與字幕遮挡，保留分辨率、姿勢、時刻与来源。截图 FPS 不是正式效能基線。
4. 本次产出合入 main 後，Session 1 釋放 tools/story/build_ch1_story.py 的修改工作；後續故事 Session 從最新 main 接手。新增演出遵守此介面及 scene-staging，按票验证自身新增内容；不冒稱 ST-16 已检查。

相關流程：character-art-pipeline、rig-animation 及 scene-staging。全角色全部件、單像素孔洞及動作切換檢查的門檻不因姿勢資料通過而降低。
