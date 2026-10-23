---
name: visual-verification
description: 需要用真實畫面驗證 Nest Egg 的光影、泛光、過曝、角色接縫、姿勢、UI 版面時使用。內容：在沒有 GPU 的雲端環境用軟體 Vulkan（lavapipe）跑 Forward+ 截圖與量測、截圖與量測工具的用法與陷阱、「看過才算驗收」的規則。只要票的驗收牽涉畫面（過曝、發光、破圖、姿勢、介面排版），先讀這份。
---

# 用真實畫面驗證

背景：使用者看的是 Forward+（HDR 2D、泛光）的真實畫面。Compatibility 渲染器沒有泛光，所以在 Compatibility 下「量不到過曝」不代表沒有過曝。NE-213 曾因此在沒有重現問題的情況下結案，被使用者推翻（2026-10-07）。**畫面相關的問題，沒有在 Forward+ 下重現與驗證就不能結案。**

## 取得 Forward+ 畫面（雲端環境，沒有 GPU）

```bash
# 一次性：軟體 Vulkan（lavapipe）。容器重啟後要重裝。
apt-get install -y mesa-vulkan-drivers libvulkan1 vulkan-tools
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json
# 截圖（Forward+，含泛光）；Godot 要是有 X11 與 Vulkan 的版本（/home/user/godot_build/godot_x11，自編；沒有的話見 CI 的下載方式或重編）
xvfb-run -a -s "-screen 0 1280x720x24" godot_x11 --path . --rendering-driver vulkan --rendering-method forward_plus \
  res://tools/screenshot.tscn -- --out=<絕對路徑資料夾> --scenario=<名稱>
```

- 啟動訊息會印 `Vulkan … Forward+ … llvmpipe`，沒印就是沒有跑在 Forward+。
- 軟體渲染很慢（一張約 1～3 分鐘的場景要預留時間，長的掃描放背景跑，不要用 `pkill -f` 清理，會殺到自己的 shell）。
- 只有 Compatibility 可用時（`--rendering-driver opengl3 --rendering-method gl_compatibility`）只能看形狀、接縫、姿勢，**不能判斷過曝與泛光**。

## 工具

| 工具 | 用途 |
|---|---|
| `tools/screenshot.tscn --scenario=exposure` | 每份光影設定下主角的曝光（全白比例、光暈比、峰值） |
| `--scenario=exposure_lamp@關卡檔[@燈編號]` | 主角的頭靠近場景燈（跳起、爬梯子貼天花板）時的全白像素比例；`--legacy-exposure` 看修正前 |
| `--scenario=exposure_play@關卡檔` | 用真的按鍵跑一段（跑、跳、射擊、衝刺、格擋、近戰），存下最白的幾格 |
| `--scenario=exposure_states@關卡檔[@欄]` | 待機、受擊閃白、開槍、格擋各拍一張 |
| `--scenario=exposure_sweep@關卡檔@間隔` | 整張地圖每隔幾欄量一次 |
| `tools/rig_preview.tscn` | 角色姿勢、動作、接縫（`--chars --closeup --zoom --joints --level --rigid --gait --action`） |
| `tools/rig_perf_probe.tscn` | 骨架動畫每格成本 |
| `tools/sway_region_probe.tscn` | 區域擺動（頭髮、衣襬、胸口）：`--angles` 只動一個區域、其他固定在 0，量畫面上改變的像素與範圍；`--curves` 用真實輸入序列輸出每個擺動的峰值與停下時間（30／60 更新率）；`--strip=stop\|jump\|land\|dash` 連續影格，並排「這個區域固定在 0」的對照組與差異圖 |
| `tools/light_pool_probe.tscn` | 光池：每一盞亮著的場景燈，燈下的牆面比光池外亮幾倍（只量背後有牆的地方）。調環境光或改燈之後重跑 |
| `tools/frame_time_probe.tscn [--level=…] [--seconds=20] [--off=prefetch,lights,…] [--vsync] [--idle]`（原生；加 `--fullscreen` 用螢幕解析度） | 玩起來卡不卡：機器人在正式關卡實際跑、跳、開槍，記錄每一格的間隔（中位數、第 95／99 百分位、超過 16.7／33.3 毫秒的格數、最長幾格發生在哪）、進關卡花的時間、預載載了幾張與單張最久；`--off` 關掉某一類再量可以找出是誰的成本。量的時候機器上不要有別的工作（別的工作階段跑測試或截圖會讓數字差到一倍以上），兩個版本要交替各量幾輪 |
| `tools/wall_shadow_probe.tscn` | 牆上的影子：主角站在場景燈左、正下方、右各一張，槍燈照一排敵人一張，每張都有影子開與關；`perf` 量 12 個敵人時開與關的每影格耗時（成對交替 60 組），`reenter` 看反覆進出關卡資源有沒有累積 |
| `tools/lamp_flicker_probe.tscn` | 閃爍的燈：每盞燈一秒內亮度明顯變化幾次（上限 3）、兩種會閃的狀態各連拍 3 秒；`--reduce-flashes` 看「減少閃光」 |
| `tools/lamp_gallery.tscn` | 場景燈具一覽：每一款亮與熄滅、原本的裝法與掛在桿子上的樣子 |
| `tools/weapon_light_probe.tscn` | 槍燈：在真實關卡套上暗的光影，每把槍朝三個方向各拍一張；量開、關槍燈時 8 格外敵人的亮度，以及開火時每影格的耗時（開、關交替量）。這支工具也能原封不動拿去量還沒有槍燈的舊版本 |
| `tools/vfx_exposure_probe.tscn` ＋ `tools/vfx_exposure_sheet.py` | 每一份光影設定下的槍口、敵人死亡、油桶爆炸連拍與全白比例（`--level` 換成真實關卡、`--stress` 量連續爆炸的每影格間隔）；改爆炸或新增光影設定後重跑 |
| `tools/screenshot.tscn --scenario=screens --text-scale=1.2` | 主選單、難度、設定、圖鑑、暫停、背包各分頁、死亡、結算一次拍完；`--text-scale` 寫入獨立設定檔，`--size=寬x高` 改視窗大小 |
| `tools/ui_textscale_sweep.tscn [--text-scale=1.2]` | 設定四個分頁與補給商店，並列出超出畫面或被裁切的文字；捲動區裡還沒捲到的列只計數不算問題，但有更多內容卻沒有捲動提示會列出 |
| `tools/quest_map_probe.tscn --text-scale=1.2` | 任務與地圖各分頁的放大文字版面；`--fixtures` 畫面會標示驗證樣本 |
| `tools/hud_hover_modal_capture.tscn [--legacy]` | 滑鼠停在 HUD 上再開暫停頁／通訊／交談；`--legacy` 拿掉守門重現修前畫面 |
| `tools/pickup_feed_capture.tscn` | 拾取紀錄與舊的中央取得橫幅對照 |
| `tools/ne251_wake_probe.tscn -- --mode=route\|isolated\|resume\|sweep` | 過場舞台上主角頭部的純白比例，以及白髮和正後方背景分不分得開（`route` 走真正的倉庫溺斃 → 診間醒來；`sweep` 量所有有主角登場的舞台）；門檻純白 2%、糊掉 5% |

量測陷阱（都踩過）：
- 專案用 stretch，螢幕座標要用 `get_viewport().get_final_transform() * get_viewport().get_canvas_transform()`，只用 `canvas_transform` 會量到錯的地方。
- `Node.find_child("head")` 會先找到 Bone2D 而不是同名的 Sprite2D；要量零件請用 `find_children("head", "Sprite2D", true, false)`。
- 材質、modulate 的實驗要先確認真的套到目標節點（印出 `material`），否則會得到「沒有差別」的錯誤結論。
- 截圖是 HDR 浮點影像，像素值可以大於 1；「全白」用每個色版 > 0.92 判斷。
- 在地圖裡擺放主角：`layout.floor_below(欄, 4)`；有些位置在牆裡或鏡頭沒跟上，截圖看過再信數字。
- 比「開」與「關」兩張畫面時，鏡頭要先停下來（瞄準方向改變後鏡頭會慢慢偏過去，等 2 秒以上），雨、蒸汽、閃爍要先定住或藏起來，否則兩張的差別大部分是雜訊。用「開比關暗兩成以上的畫面比例」減去「關比開暗兩成以上的比例」，不要用整張的平均亮度差。
- 量每影格耗時：機器同時有別的工作時，整段各量一次再相除會差到一成以上。改成「開、關緊接著各量 45 格」算一組，量 60 組取比值的中位數。
- 著色器看起來沒作用時，先把中間值直接輸出成顏色（一個色版一個值）再用開與關兩張的比值量，不要只用眼睛看縮圖：曾經在「資料有沒有傳進著色器」上繞了很久，其實是傳了、但算出來的效果被霧與光錐蓋掉。
- 軟體渲染約每秒數格：等待提示、橫幅這類有時效的畫面要用「幾格」而不是「幾十格」，否則截到的是已經淡出的畫面；需要等時間時用實際毫秒計時。
- 新增 `class_name` 後要先跑一次 `--headless --editor --quit` 更新類別快取，否則其他腳本找不到新類別。
- 過場的問題要走實際路線量一次：關卡在過場播放時還留在底下（補光倍率、泛光設定都是那一關的），單獨播放場景量到的不一定是玩家看到的（NE-251）。

## 驗收規則

1. 驗收畫面問題時：**先重現，再修，再用同一個場景重跑同一個量測**，修前修後並排放進票的截圖。
2. 不確定使用者看到的是什麼時，多試幾種觸發（光源距離、動作、特效、補光倍率高的暗場景），不要只量預設位置。
3. 看圖要看放大後的細節（過場倍率約 3.4 倍），不是縮圖。
4. 數字通過但畫面看起來不對，以畫面為準，回頭修量測。

## 光池巡覽與觀察位置（BG-49，2026-10-20）

- 鏡頭移動不會移動LightingController的目標；巡覽每盞燈時，以不碰撞的觀察點跟到燈的位置，真玩家保持原位，避免意外觸發故事／傳送門。每筆保存目標與燈座標、區域、實際霧量、環境光及輪廓光；錯位要退出失敗。
- 原光池公式、24格等待、燈、陰影、輪廓光與自然雨霧保持。故意恢復只移鏡頭作負控制，確認能抓到錯位；不能以換低門檻或改選擇器代替驗證。
- 雨霧相位不同的獨立運行不可直接互比。單因素診斷可固定同一場景的模擬並保留全部繪製，交替原值／新值兩次；保存雨霧時鐘、可見性、鏡頭與輪廓光，證明保持。明寫運行中介入，不假稱歷史checkout或全關／實機驗收。

## 有背景的曝光矩形與保守上限（BG-49，2026-10-20）

- 矩形內全白為0可推出其中角色為0；非0不能除以含背景面積。固定、確定無遮擋的取樣可用真正可見不透明頭部像素H作角色面積下限、全角色矩形白像素W作白像素上限，故比例≤W/H。明寫保守上限，精確enemy_only_ratio仍null。H=0必須拒絕，不能報0%。
- 複製真正已變形drawable到獨立透明SubViewport，只讀alpha，不複製行為。先把viewport加入樹再設定canvas變換；使用主final×canvas與實際像素尺寸。固定原姿態，檢查變換完全相同、範圍不超出原矩形；祖先透明或GPU蒙皮未明確處理就拒絕。頭部被不透明前景遮住時，此固定取樣的下限不能直接通用。
- 保存原格HDR binary與實際格式／尺寸、同格sRGB圖、完整alpha及裁切。用獨立唯讀腳本重算，另跑空白遮罩負控制。保留原型編譯／引擎錯誤，最終無ERROR不等於歷史資料皆無ERROR，也不代稱實機戰鬥。

## 自然交戰與部位命中的探針（NE-248，2026-10-20）

- 要驗自然第二階段，使用正式Player的公開移動／射擊／換彈與滑鼠輸入，記錄真實damage／marker與生命帳；不能用直接指定生命、phase、FSM或核心開關的示範取代。安排場地與玩家耐久需明示，不冒稱真人完整章節。
- 使用任務對應的正式章節，明寫LevelData.chapter。空白資料的預設舊稿chapter_01曾在原生退出出錯；正式ch1_kasa的通過不代表舊稿也修好。若任務就是舊稿，不得換章節讓它變綠。保留全部退出碼、ERROR、源碼及逐欄對照。
- 同時有多發在途時，不能以探針當前目標解讀上一發。用真實projectile身分追蹤，或公開輸入一次只發一發並等它自然結束；不得移除子彈來整理證據。命中後持續同一公開瞄準到擷取完成，否則準星已移到下一目標。
- 弱點倍率與整體增傷分開記錄：監管者跳砸後的全身2倍可和核心2倍重疊。隔離部位比較時等待正式全身倍率回1，不改敵人值；另驗實際倍率與info.part／weak_hit／marker。不能因扣了2就推定核心命中。
- 空中跨半血時phase變數與下一次FSM轉換時間可能不同；使用真正phase事件，不把較晚的狀態取樣當成同一時刻。獨立驗證器錯誤亦保留，不放寬原條件來通過。
- 引擎exit0仍有ERROR／資源洩漏不算乾淨；除錯器wrapper的exit0也不能代稱inferior沒崩潰。沒有符號時保留地址，不編造堆疊函式名或只憑網路相似訊息定根因。
- 共用拍攝工具可能會改玩法條件：ScenarioBase開場會把玩家受傷保護設為0。自然交戰探針要依正式tuning還原並斷言；提高玩家生命也須明示。等待AI的重播時間上限與產品的傷害／窗口門檻分開記錄，預算不足的案例保留為未完成，不當成通過。
