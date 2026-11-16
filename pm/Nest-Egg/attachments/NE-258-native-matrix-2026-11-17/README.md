# NE-258：RX9070XT 原生矩陣與逐格對照

2026-11-17。Godot 4.7.2、Vulkan Forward+、HDR 2D、AMD Radeon RX 9070 XT。這份附件補齊七槍三方向、真正八格敵人與平台可讀性、白髮曝光、減少閃光及三品質持續射擊；過場／owner 與實牆修正、77 組正式遊戲選測仍引用前次 `NE-258-owner-wall-2026-11-17`，不混成同一個來源版本。

## 本輪結果

| 品質 | 七槍三方向／量測圖 | 真頭部曝光樣本 | 最大 W/H | 正式 whole_feature 成對耗時比 |
|---|---:|---:|---:|---:|
| 低 | 91／66 | 18 | 1.596806% | 100.488281% |
| 中 | 91／66 | 18 | 1.789264% | 101.784038% |
| 高 | 91／66 | 18 | 1.596806% | 100.769231% |

三品質全部成功自然退出，來源前後相同，無 SCRIPT ERROR／ERROR／leak 診斷。獨立 reader 重算 273 張原生圖、198 張量測、54 個同格頭部遮罩及 180 對效能視窗。七槍八格腳底距離都是 128 像素；最低敵人對比為 0.849402（門檻 0.45），最低平台頂面對比為 3.801447（門檻 1.0）。步槍身體亮部的線性亮度開啟約 0.159–0.162，suppressed 約 0.00112–0.00118；它不是人眼亮度百分比。

頭部使用實際 head drawable 的不透明 alpha 面積 H，不用矩形代替分母。W 是同格世界中頭部外框的所有每色版 >0.92 像素，因此 W/H 是無前景遮擋 fixture 的保守上界，上限維持 2%。待機、真正受傷、格擋／衝刺／換彈、七槍射擊、正常／減閃光衝鋒槍均保留原圖與 alpha。開火樣本等待第一個活躍槍口光 post_draw，立即同步讀世界 HDR，記錄同格能量／物理格及最多 120 格的等待數；不是拿下一格的光源能量回填。三品質實際抖動約 0.036332→0.009083 弧度；觀測的火光峰值降至約 25–26%，均通過原 75% gate。

`review/` 是由原圖產生、明標 review 的縮圖／局部圖，僅便於目視。六張公開 summary PNG 的原始來源與 SHA 在 `summary-images.json`，全部逐 byte 複製，原始 PNG、HDR 與 alpha 未重新繪製。畫面只停用 WorldPrompt/HUD，保留世界拾取物和標記；效能保留原 WorldPrompt 更新。

## 效能方法與來源版本

- 每品質 VSync=0、60 對相鄰 on/off、每邊 45 個真實渲染格，AB/BA 交替，切換後等待 0.35 秒。持續正式 shoot 輸入，保留原射速、30 發彈匣、1.3 秒自然自動換彈，僅安排無限備彈。原始每格時間、物理格、換彈、實際 Projectile 啟用與接受射擊事件都保留。
- 沿原工具使用倉庫、一名不攻擊的高生命敵人並清掉原敵人；是同場景持續射擊的功能成本對照，不是整章或所有敵人 AI 負載的上界。
- 上限仍是各對中位數比的上中位數 ≤105%；不是改成平均或以發射數改分母。on/off 視窗內實際子彈數：低 46/52、中 49/59、高 42/56；各視窗都與接受射擊事件相等。換彈落在視窗的位置可以使兩邊總數不同。
- `whole_feature` 是同版反事實控制：正式 ON 身邊微光 84，suppressed OFF 自然變成 150；不是歷史 checkout。`fixed_body150` 的視覺亮度對照有執行，其效能量測未執行；三個正式 whole gate 已通過，不需要再跑輔助效能診斷。
- 正式效能在 NE301 合入之前、HEAD=f3baeb3cd9c8fe453f730773eafe2ed9ac0c5e9b 的來源 epoch；當時包含 receipt 逐檔記錄的 BG32 asset_prefetch 候選及 owner/wall 修正。其他代理的長 CPU/GPU 工作先自然結束，測量期間暫停其重工作，沒有重啟 GPU。這不是宣稱整台 Windows 沒有任何背景程序。
- 本輪新的三品質畫面／曝光在 NE301 的 Pickup／Enemy／Level 三源合入之後；Git HEAD 可在文書提交時變動，但每輪 guarded source bytes 前後一致。每輪確切原始命令、APPDATA/LOCALAPPDATA override、時間、退出碼、Git HEAD 與源 SHA 都在 `process-receipt.json`。
- 正式效能後，工具 v8 只修曝光擷取的等待時點；`checks/perf-function-mapping.json` 證明 `_measure_performance` 至檔尾與正式效能版本逐 byte 相同。409 份不同的 guarded source bytes 依 SHA 去重保存在 `source/blobs/`，每個正式 run 的完整 path→SHA 在 `source/maps.json`。這只涵蓋 receipt 列出的腳本／關卡／武器等檔案，不冒稱所有美術資產或整個使用者環境都被鎖定。

## 原失敗與正式測試

所有舊資料只作診斷，沒有改成通過：舊 visual-low-v1 的 raw `source_unchanged=false` 保持；獨立核對它唯一變動為 LightKit 一行 shortcut 註解，前後 bytes 與 mapping 在 `parent-comment/`。舊 visual 三品質含 WorldPrompt 遮擋，已由新的量測 fixture 取代；舊 tool 只有原 SHA 而沒有完整工具 source snapshot，不能把它當可冷重播的最終證明。

舊曝光／換彈／短暫槍口光的失敗與 source snapshots 全保留。`exposure-high-all7-v1` 真正退出 1、兩個活躍火光 gate 失敗；spread 與正常 SMG 的指定畫格能量為 0，不能冒充含槍口火光的曝光。v8 真正等待活躍畫格後再取樣。最終同版 `exposure-high-blank-v2` 的真空白遮罩 H=0、ratio=null，唯一曝光 gate 失敗、自然退出 1；沒有把空樣本填成 0%。

原本省略 `--quality` 的合法原生命令確實仍可執行並套用當前 high；未知 quality 則有最終版本的 headless 退出 2、具體拒絕訊息、來源不變收據（`argument-negative/`）。工具 v8 自檢 8/0；獨立 reader 另以 15 種保持 PASS 欄位、但破壞原始時間／來源／發射／光源／分母的負控制確認拒絕，包括數學一致但真正超出 105% 的 raw timing。

最終兩個工具在隔離 f3 + exact v8 的原 `run_tests_changed.sh f3...` 自然退出 0，實際 selector=0，收據保存在 `official-tools/`；這沒有再跑、也不重複宣稱先前 77 組／96249 項遊戲檢查。

## 離線重算與重現

Python 及 numpy/Pillow 版本見 `reader-environment.json`。在此資料夾執行：

```text
python -B verify_archives.py --temp-base D:/NestEggVerification
```

可將 temp-base 換成任何有至少約 3.5 GB 空間的既有目錄；完全不需 Godot 或 GPU。每個獨立 tar.xz 都小於 50,000,000 bytes；同名 `.json` 列出 archive SHA/size 與每一 member SHA/size。reader 逐串流驗 bytes，拒絕重複名稱、symlink、absolute／越界／Windows drive path、profile；僅將所需檔案安全解到臨時目錄，呼叫原 BG49 的 HDR／contrast reader 重算，結束後清掉自己的臨時目錄。沒有封裝 APPDATA/LOCALAPPDATA profile 或整份玩家存檔。

Godot 原生重現仍需專案本身及對應美術／匯入資源。`reproduce/run_matrix.py` 原本位於 `work/ne258-light-owner-20261117/`，依那個位置解析專案根目錄及 `freeze-wall-v4.json`；不能直接從附件目錄執行就聲稱冷 clone 可重播。完整當次 guarded source bytes 可依 `source/maps.json` 從 blobs 還原到原相對位置（包括未追蹤的 work probe/runner），而原生 CLI 與真實設定 override 已在各 receipt；附件不另造 replay framework。離線 bytes／數值重算是獨立可攜的。

Root 獨立目視／重算與 staged-byte review 由 root 另加 `ROOT_REVIEW.md`；不改寫本封包的原始 archive 或 run 收據。
