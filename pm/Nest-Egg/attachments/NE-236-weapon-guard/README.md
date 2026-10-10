# NE-236：近戰收招轉盾與真彈體交界

本階段修正：揮空自然收完才舉盾，原本仍保留舊招索引，放盾後的新點按誤接第二招。首次舉盾一律結束舊近戰接續；起手／有效／未支付收招仍鎖定，護盾角度、完美窗口、能量、傷害、電量、換武器風險、共享動畫及回饋未改。

## Source 與 ownership

初始完整回歸基準 `82882bb455ad2d57a5904a6cfbdf6b9c8d6645fa`，交付前無衝突 rebase 到 `212768fa4a98e9db5bb1b3f4c067ef6027c7547d`。新主線只有死亡動畫的專用動作混合清除及相應測試，活著時分支不變。B沒有修改該动画核心。

- `game/player/player.gd`：首次舉盾處只移除「phase非NONE才清連段」的限制，一律 `_end_melee(false)`；UI bounds與其餘內容逐字保持。
- `tests/suite/test_melee_weapons.gd`：追加近戰轉盾回歸與可選原生捕捉；所有原測試內容、斷言及順序逐字保留，沒有改期限、故障拒絕或鬆綁。
- `tools/weapon_guard_probe.gd/.tscn/.gd.uid`：專用原生驗證場景，共用原測試執行器 helpers及同一組嚴格斷言，原runner沒有修改。
- 設計、NE-236階段紀錄、raw、source snapshots及原生圖片。

[source diff](source.diff)、[初始保護檔比對](preservation.json)、[最新主線17檔比對](rebase-preservation.json)、[檔案hashes](hashes.json)。不改Main／Level／Story／RunSnapshot、CharacterRig／HumanoidAnimator／RigInput／PlayerVisual、共享Fx、Progression、Runner／Selector／Filter／Known failures。近戰型錄review分支仍交Root處理，不由本階段推main。

## 真自然路徑

訓練fixture建立真Level、Player、Enemy、Health/Hurtbox及既有ProjectilePool；敵方偵測／移動停用且HP999，玩家亦HP999。fixture不是章節或AI實戰／正式存檔閉環。

每種近戰、左右兩向各跑：真揮擊→自然起手／ACTIVE命中／局部hitstop→支付取消點→用持盾輸入自然轉盾→敵方原規格彈體自然飛行、碰撞。

| 情況 | 30組矩陣內的實際結果 |
|---|---|
| 正面窗口後 | 玩家999維持、盾100→76、彈體消失；無反彈／返回傷害 |
| 正面窗口內 | 玩家與盾維持，彈體換隊、真返回受擊者999→997一次 |
| 背面 | 玩家999→998一次，盾100維持、不反彈 |
| 持盾期間點按 | 事件近戰＋輪詢射擊均拒絕，不存buffer、不耗電 |
| 放盾後 | 舊接續不自動播放；揮空後立即新點按從首招開始 |

另五組真揮空持盾：起手／有效／完整收招都不能提早轉盾。原失敗的匕首、熱刃、重錘、長柄現在舉盾時索引-1，放盾新点按為0；單段鞭原本清尾亦保留。沒有直接呼叫護盾判定、彈體接觸或近戰命中，没有手動推進phase／解除freeze。矩陣與原生路徑見[matrix.json](matrix.json)。

## 試驗來源、失敗與成功

| 目錄 | 結果／用途 |
|---|---|
| red | 初次新測試型別推斷錯誤，0檢查、SCRIPT ERROR、退出1；source/raw保留，不算通過 |
| initial | 產品修正前：591檢查、8新失敗、0已知、退出1、122秒；四種多段武器各兩個殘留／誤接失敗 |
| changed | 首次60組／2worker：一程序malloc abort，`free(): chunks in smallbin corrupted`；只有另一程序完成6915檢查，整輪退出1，598秒；不得算60組通過 |
| changed-single | 原selector仍選60組／1worker：54807檢查、0新／已知失敗、退出0、954秒、0 SCRIPT ERROR |
| native-low | 初次低品質：320檢查、0失敗、退出0；功能通過，但30圖片因章節卡／鏡頭平滑問題標rejected |
| native-high | 等真章節卡finished＋鏡頭reset_smoothing：320檢查、0失敗、退出0，30原生圖 |
| native-low-final | 同樣原生修正，且讓放盾新首招自然收尾後才釋放fixture：325檢查、0失敗、退出0，30原生圖 |
| rebase-checks | 最新212768fa4交叉複驗7組：6971檢查、0新／已知失敗、退出0，279秒，0 SCRIPT ERROR |

首次malloc abort沒有cgroup OOM事件；根因未定位。新增fixture已改成確認新首招後讓其自然收完並等物理收尾，再釋放場景；單worker完整回歸通過。這不是宣稱已修復引擎abort。Runner／selector／filters／known failures保持，所有失败raw保留。

`source-at-changed`是首輪60組及被拒絕試拍所載入版本；`source-before-cleanup`是高品質重拍版本；`source-final`是加入五個自然收尾檢查、最新主線複驗與低品質最終版的版本。差異是可選取景等待／鏡頭及fixture收尾，不是改產品時序或移除斷言。各版本source snapshots均為.txt，不會註冊重複Godot class。

初次及rebase後fresh import退出0。suite保留刻意容錯、既有物理／音效與資源退出診斷，不宣稱無ERROR。原生high／low-final的raw與退出碼各自保留，聲音使用Dummy，不宣稱人工試聽。

## 原生畫面與限界

Godot4.7.2 Forward+／llvmpipe LLVM19.1.7，1280×720，camera3.4，粒子0.25、零震動、減閃。事件／輪詢皆合成輸入，沒有實體手把、硬體GPU、HDR顯示器／VRAM、人工手感或完整章節宣稱。

90張PNG原樣複製到`pm/Nest-Egg/images/`：high／low各30，rejected30。檔名映射與內容hash在matrix.json；都是彈體接觸／返回飛行後的實際狀態，不冒稱命中瞬間逐格美術完成。[代表原生圖檢視與持物接口要求](visual-review.md)記錄章節卡／腳部試拍拒絕、既有提示遮頭、長柄持盾時垂直穿地及共享角色接縫。武器持盾／carry、握持與角色接縫仍不算通過；NE-236／237與全武器驗收保持進行中。

manifest不自我包含README／票／hashes.json；所有列入的source、raw、source snapshots與PNG都需與實際提交Git blob一致。
