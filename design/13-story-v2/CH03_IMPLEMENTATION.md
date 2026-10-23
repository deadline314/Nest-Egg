# 第三章「晴岸」落地紀錄（ST-21）

劇本：[SCRIPT_CH03.md](SCRIPT_CH03.md)。寫法沿用第二章（[CH02_IMPLEMENTATION.md](CH02_IMPLEMENTATION.md)）：作者來源 → 共用轉譯器 → 遊戲讀的劇本檔，區域地圖由產生器輸出。

## 1. 檔案

| 用途 | 檔案 |
|---|---|
| 區域地圖產生器 | `tools/level/build_ch3.py` → `data/levels/ch3_*.tres`、`ch3_*_map.json`、`data/npcs/ch3_*.tres`、`data/environment/themes/ch3_*.tres` |
| 劇本作者來源 | `tools/story/ch3_source.py`（段落、選擇、任務、文件、交易） |
| 劇本產生器 | `tools/story/build_ch3_story.py` → `data/story/ch3_clearwater.json`、`data/story_items/ch3_*.tres`、`data/story_transactions/ch3_*.tres` |
| 共用轉譯器 | `tools/story/chapter_compiler.py`（第二章起共用：段落轉譯、分派、任務、答錯再選一次、文件與交易輸出） |
| 譯文 | `tools/story/i18n/ch3_clearwater.json`（中文原文 → 日文、英文） |
| 測試 | `tests/suite/test_ch3_story.gd`；各章共用的地圖與劇本檢查在 `tests/helpers/chapter_story_checks.gd` |
| 探針 | `tools/ch3_flow_probe.tscn`（`--route=full|minimal`、`--yong=cut|keep`）、`tools/ch3_resume_probe.tscn`（`--mode=write|continue`）、`tools/ch3_readability_check.tscn` |

## 2. 區域

劇本的 H／M／S 地名對到九張地圖（格子 16 像素，地面第 20 列）：

| 地圖 | 劇本 | 內容 |
|---|---|---|
| `ch3_pawnshop` | H1／H2 | 早上櫃台的早飯（C00）、傍晚廚房的留飯（C22）、店內通訊（C23）、貨架的未署名記錄（M3）。章末旗標 `ch3_shore_closed` 寫入就結束本章（第四章尚未收錄，沒有下一關） |
| `ch3_plaza` | H14 | 貨梯控制箱與水尺（C01、C02）、外梯 SC5、高架維修盒 |
| `ch3_pump` | 泵室 | 乾燥上橋的排水輪、下槽的配電盤、背面工具櫃；下槽兩個戰鬥區可沿上橋繞過 |
| `ch3_mezzanine` | M1 | B5 電話亭、公共通知終端（父女兩路的回執）、往診所；維修帶戰鬥區可從照護步道繞過；SC6 回門禁大廳 |
| `ch3_clinic` | M5a／M5b | 芷姐、閱覽桌（公開報表、核對）、門邊閱覽櫃（名冊）、工作廊的輪班表、寄存櫃 |
| `ch3_gate_hall` | M5c | B6、門禁閘（C10）、守門人戰區、扶椅後的守門人（C12）、SC6、邊緣電梯 |
| `ch3_glass_edge` | S1 | 第一次陽光（進場兩句話）、光斑、觀景框（C14）、住宅內區的門（關著） |
| `ch3_showroom` | S2 | 林小姐的接待桌、A 晨窗、B 靜窗、C 晚窗 |
| `ch3_office_hall` | S3 | 公文取件格（C18）、等候臺（C19、C20）、辦公內門（關著） |

第二章屋頂的章末（`ch2_heron_closed`）接到 `ch3_pawnshop`。

## 3. 劇本的機制怎麼用現有系統做

- 排水、隔離、對帳都是選擇演出：轉錯方向、關錯開關、算錯人數只會有一句完整的提示，再選一次，不扣東西（`route_back_to_choices`）。
- 三份資料任意順序；閱覽桌依序檢查缺哪一份，三份都在才開始三處核對。
- 早飯與晚飯是正式過場：沿用第一章審過的店面與廚房舞台、演員站位與縮放；接續段落與選擇留在同一個畫面上。
- 辦公接待廊（C18～C20）是正式過場：本章自己的舞台 `ch3_office_hall`，隔著玻璃的室內鏡頭與凜的反應鏡頭交替，談話中段可以忍住、推門或先退開（退開後從中段接著聽）。分鏡與參考見 [CH03_OFFICE_STAGING.md](CH03_OFFICE_STAGING.md)。
- 房間提案是選項的可逆意圖旗標 `room_choice`（morning／quiet／late），只有第一次提案發 SQ3-C1 的二十；改提案只換卡上的房名。
- C21 的交通版尚未實作，用步行版（只寫 `ch3_l2_route_announced`，不寫 `cross_region_l2_ready`）。

## 4. 和戰鬥組的接點

| 接點 | 說明 |
|---|---|
| 守門人戰（NE-271） | 停機（拔維修插銷）時啟動機關頻道 `ch3_janus_down`，門禁大廳的 `channel_done_flags` 寫入 `ch3_janus_disabled`；之後守門人出現在櫃檯旁，扶他坐好（C12）才結算停機報酬一百並開 SC6 與邊緣電梯。戰中短句 `ch3_c11_bark_sorry`、`ch3_c11_bark_repeat`，首次敗北提示 `ch3_c11_defeat_hint`（重要通訊，凍結世界） |
| 兩種巡檢器（NE-272） | 戰鬥區寫在 `ch3_design.json`：泵室下槽兩場、夾層維修帶一場、守門人的增援 |

## 5. 和劇本的差異

- 停機報酬一百在扶椅那一段結算（劇本寫在停機當下）：結算一律由故事段落的結果寫入，戰鬥只交出停機旗標；邊緣電梯要扶椅完成才開，所以不會漏發。
- 交易摘要、看房卡等文件的日文與英文放在 `data/story_items/i18n.json`（2026-10-23 起，三章 49 份道具與文件都有），背包、撿取提示與取得訊息依劇本語言顯示，缺譯退回英文再退回中文。
- 旗標名稱避開和前章只差一兩個字的寫法：章末 `ch3_shore_closed`（不寫 `ch3_complete`）、外梯 `ch3_outer_ladder_down`、護理通道 `ch3_care_passage_open`（不寫 SC5／SC6）。

## 6. 數字

主線報酬 180＋100＝280；支線 20×3＝60；兩個探索盒是地圖上的信用點。完整路線 340、只走主線 280（流程探針核對）。480,000 是房價目標，不扣也不發。
