# 手把輸入與介面接線

NE-229，2026-10-10。設計依據沿用本目錄 RESEARCH.md 的 Steam Input 與 XAG 112／113；本輪沿用現有 InputBindings、AimInput、InputMap 和 Settings，沒有另建一套遊戲輸入。第一批基準為 `727dd8e1`，實際測試基準與日誌另記於票內。

## 操作與裝置

確認使用面板下方按鈕、返回使用右方按鈕，分頁使用肩鍵。遊戲內的 A／B／X／Y 可重綁；選單的確認與返回保留一致語法。已辨識的 Xbox／PlayStation／Nintendo 顯示相應名稱，未知手把的四個面板按鈕另標位置，避免只憑品牌字母指引。任務與地圖沒有預設直達手把鍵，使用 Start 暫停選單進入，不能顯示不存在的快捷鍵。

近期有意義的按下、滑鼠位移或搖桿推動決定提示與瞄準來源。按鍵放開、鍵盤重複、小於兩像素的滑鼠位移和死區內搖桿漂移不切換來源；已保持的搖桿值在滑鼠操作後不搶回瞄準。切回手把需要新的按鈕或明顯搖桿位移。

左搖桿操作選單時，初推立即移動一項；相同方向的多次軸事件不連跳，按住 0.35 秒後每 0.1 秒移動一項。回中心、切換裝置、失去窗口焦點、退出選單或斷線停止重複。只在 UI 上下文的軸事件與按住計時器執行，不每影格掃描所有介面。

射擊與格擋按住持續；近戰武器按住射擊連續揮擊，近戰／跳躍／衝刺按下觸發並沿用既有輸入緩衝。重綁不能移除必要動作的唯一手把按鈕，也不能以未綁定快捷鍵占用必要動作；設定畫面需要顯示拒絕原因。軸與扳機保持既有固定映射。

## 偏好與回饋

右搖桿圓形死區預設 0.3，可調 0.1–0.6；反轉只作用於手把垂直瞄準。回中心保持最近瞄準方向。震動強度為 0–1，0 即關閉，回饋僅送目前實際已連線手把。射擊、一般格擋、完美格擋、近戰命中與受擊有不同震動；設定不參與傷害、判定、動畫時序或輸入緩衝。

所有設定透過既有 Settings 保存；壞值有具體位置警告並退回預設，手把設定與鍵盤改鍵互不重設。恢復改鍵資料時，必要按鈕缺漏或重複會讓手把映射退回預設，保留鍵鼠設定。

## 拔插與恢復

InputMap 的手把事件接受所有 device index，避免重插後索引改變導致無法操作。正在操作的手把斷線時釋放所有按住狀態、停止震動及選單重複；實際遊戲取得共用 GameplayLock 暫停並顯示提示，重接本身不恢復。玩家以手把確認／暫停或鍵盤 Enter／暫停鍵明確繼續，該次確認被吞掉，不同時跳躍／射擊。既有選單／過場保持自己的暫停與焦點；玩家節點換場移除時收回斷線鎖，避免回主選單後殘留暫停。

## UI owner 的最小接點

`InputBindings.bindings_changed()` 在改鍵或裝置變更發出，現有頁面在這個訊號刷新文字。`format()` 支援遊戲動作、`{ui_accept}`／`{ui_cancel}`／`{ui_up}`／`{ui_down}`／`{ui_left}`／`{ui_right}` 與 `{inventory_prev_tab}`／`{inventory_next_tab}`。固定寫 Enter、Esc、Q/E 或 A/B 的頁面須改用模板。

設定控制項直接使用以下 API；不另外持有一份數值：

| 控制項 | 讀取 | 變更 | 說明 |
|---|---|---|---|
| 右搖桿死區 0.1–0.6 | `get_aim_deadzone() -> float` | `set_aim_deadzone(value: float)` | 忽略右搖桿中心的微小偏移。 |
| 反轉垂直瞄準 | `get_invert_aim_y() -> bool` | `set_invert_aim_y(value: bool)` | 反轉右搖桿上下瞄準方向。 |
| 手把震動 0–1 | `get_vibration_strength() -> float` | `set_vibration_strength(value: float)` | 調整射擊、受擊與格擋的手把震動；0 為關閉。 |

API 均位於 InputBindings。頁面需要同步控制項時連接 `controller_options_changed()`；重綁捕捉按鈕先讀 `joy_binding_error(action: StringName, button: int) -> String`，非空時保持捕捉並顯示原因，空時才 `set_joy_button()`，原有互換回傳值仍相容。

設定的第 4 個「手把」分頁呈現死區 10–60%、反轉上下與震動 0–100%，恢復預設只重設這三項。LB／RB 切頁後把焦點移到實際可見控制項。手把欄短按 B 可綁定、長按 0.6 秒取消；鍵盤欄按 B 或 Esc 取消，取消後保留原值與原按鈕焦點。長按使用忽略遊戲時間縮放的單次 Timer，捕捉期間吞掉左搖桿轉出的導航事件。

## 交付邊界與驗收

第一批交付共用服務、實際遊戲瞄準與回饋接點、HUD／暫停說明以及合成輸入回歸。主選單、背包與設定由 UI owner 接線；其他頁面逐一核對提示、焦點與完整操作。正式主線任務、序章／後續章節與整輪續玩依其原 owner 的正式資料驗證，介面樣本不能代替章節。

合成測試可確認 device index、死區／反轉、提示／改鍵、類比導航、必要按鈕保護、斷線／確認恢復及焦點丟失釋放；不能驗收真實手把辨識、硬體震動強弱、實際拔插驅動、完整一章的人工作業或畫面焦點可見度。NE-229 在 UI 整合、必要範圍測試、真實畫面與實體手把全流程完成前保持進行中。

`tools/run_controller_capture.ps1 -Godot <執行檔> -OutputPath <絕對目錄>` 在獨立 APPDATA 啟動捕捉器，使用實際 Main 路由與合成手把事件，依焦點走主選單、難度、第一章當舖、背包分頁、暫停、空的正式任務目錄、區域／世界地圖、設定分頁與返回。畫面以 `NE-229-synthetic-` 命名並印出真正已連線手把清單；使用虛擬裝置 999 的結果不算實體裝置。捕捉器沿用 HDR readback；截圖需在 Forward+ 實際檢視，headless 只執行同一路由檢查。探針停用故事自動保存；獨立捕捉程序另驗證實際 user data 位置位於隔離目錄，錯誤中斷也不寫入真人存檔。影像寫入失敗會讓退出碼非零。

捕捉器支援 `-Width 1600 -Height 900 -TextScale 1.2`，文字設定只寫入該次隔離設定檔。每張影像等待 0.8 秒並在繪製完成後讀回；另外保存改鍵提示、長 B 取消、鍵盤欄 B 取消及短 B 綁定後的畫面。

### 2026-10-10 合成驗證基準

基準 `33519c09e9630ab2189b9988384abd51ac76e280` 加本票與 UI 接線未提交變更，Godot 4.7.2。InputFeelSuite 共 93 checks／0 failures，包含核心 57 checks 與實際場景路由 36 checks。後者只透過 `Input.parse_input_event()` 送 joy device 999 的 pressed／released；不呼叫按鈕 pressed 訊號、不直接 grab_focus。確認三個手把選項由實際控制項調整並恢復原值、可見分頁焦點、兩種 B 取消保留原值／焦點，以及返回時不殘留戰鬥輸入。

Forward+ Vulkan／Intel Arc B580 的隔離捕捉於 1280×720／100% 與 1600×900／120% 各完成 36 checks／0 failures，後者包括 14 張影像。Runtime 偵測到實體 joypad `[0]`，全部送入的事件仍來自 synthetic 999；沒有實體按鍵、拔插或觸感驗收。正式任務目錄為空，未插入故事樣本。執行沒有 SCRIPT ERROR／Parse Error，退出有 265 ObjectDB instances leaked 的警告，保留原 log，未加過濾例外；UI 畫面檢視及最終 ALL 結果在交付前另記。

新工具 UID 由本次 editor import 產生：`controller_flow_probe.gd` 為 `uid://vftyu62ntuai`，`controller_flow_capture.gd` 為 `uid://cl1vn1hg0g7hl`；無關 projectile／scenery／pixel capture 的生成 UID 不納入本票。

### 原始畫面核對

同樣 1600×900／120%、root ALWAYS 與暫停狀態的設定頁隔離流程完成 15 checks／0 failures，prefetch requests 0，沒有退出物件警告。Runtime 的 `rendering/driver/threads/thread_model` 為 1。字串、visible_in_tree、全父鏈 modulate／self_modulate 都正確且 alpha=1，Engine.time_scale=1。

連續圖片檢視時，重複文字區域曾被誤判為 UI 缺字；原始 PNG 的標題區仍有 2686 個青色文字像素，像素轉 ASCII 可辨識完整「設定」，原生 Godot 視窗也顯示完整標題、頁籤、可見按鍵列與腳註。連拍 3 張、每張相隔 3 個 process frames 的 SHA256 一致，與原生窗口比較那次保存的 PNG 亦相同（`0d5b05b64af211287ee7ba34b96dd49c405f594fefa091bd3e7cd3a0b5f1bf4d`）。因此沒有成立的 UI 缺字問題，沒有套用重繪／改字型等正式 UI workaround。

測試 fixture 使用 `Input.action_press()` 時須明確選擇 `AimInput.using_gamepad = true`，因為該 API 不產生「近期裝置」事件；不能讓每影格非零軸自動奪回來源來遷就測試。這次 main 的兩處 fixture 因此有變更，原有 test selector 按規則選 ALL，最終受影響批次不得繞過。

### 實際工具的合成瞄準相容性

首次 retained `33519c09e` 的 ALL 跑完 79 組、53,848 checks，29 個新的實際聲音 MISS（不是已知失敗），另有 SubViewport 初始化時的 `affine_invert` determinant 0 錯誤。SoundStage／StageCoverageWeapons 的 LabArena 以 `Input.action_press()` 指定方向但沒有裝置事件，因此新近期裝置規則正確保留滑鼠來源，腳本工具卻瞄錯方向。

實際工具透過 `AimInput.set_virtual_gamepad(actor: Node2D, enabled: bool)` 指定單一腳本角色的模擬來源，沒有改動全域最近裝置或提示；SoundLab 的 free-play、teardown 和 exit 清除 override。既有 screenshot 的 12 組方向捕捉與試聽工具也成對指定／清除 actor override，滑鼠情境不覆寫。兩個滑鼠讀取分支在 canvas determinant 不可反轉時保留安全的方向／準星 fallback。

根因修復單組 SoundStageSuite 為 134 checks／0 failures；InputFeel／AmmoTray／Melee／SoundLab／StageCoverageWeapons 五組為 410 checks／0 failures，InputFeel 現為 97 項（含原本實際路由 36 項），增加 node-scoped 模擬來源／清除與兩個奇異矩陣 fallback 的檢查。原失敗 log 在 `C:/tmp/ne229-final-all`；正常 log 在 `C:/tmp/ne229-soundstage-fix` 與 `C:/tmp/ne229-aim-tool-fix`。未更動 selector、錯誤過濾或 KnownFailures；同步 main 後依原 selector 跑 final ALL，結果如下。


### 最終完整批次

基準 `c147c8dbaea385b032e367e7dfe8310d7dd718f4` 加本票凍結程式，Godot 4.7.2；`tools/run_tests_changed.sh` 原 selector 選 ALL、SHARDS=2，79 組共 53,837 checks／0 new failures／0 known failures，588 秒、exit 0。包含 InputFeel／AmmoTray／Melee／SoundLab／SoundStage／StageCoverageWeapons 及實際 Main 路由探針 36 checks／0 failures；未出現非預期腳本錯誤、原 29 聲音 MISS 或 `affine_invert`。兩工具另以載入專案 autoload 的暫存場景驗證編譯與 override 的 press／release／exit 清除，6 checks／0 failures，日誌 `C:/tmp/ne229-tool-scene-parse.log`。直接 `--check-only` 不載入 autoload，不能用於這兩個既有工具。

最終 22 個凍結程式檔的 SHA256 與測前 manifest 完全一致（`C:/tmp/ne229-final-source-manifest.json`）。完整正常主記錄與兩 shard 日誌保存於票的 `attachments/NE-229-final-{console,shard-0,shard-1}.log`，原失敗日誌維持在 `C:/tmp/ne229-final-all`；不把失敗新增到已知失敗清單。實體手把、完整續玩／章末的人工作業維持未驗收，NE-229 仍進行中。
