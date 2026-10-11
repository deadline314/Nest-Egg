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
| `tools/light_pool_probe.tscn` | 光池：每一盞亮著的場景燈，燈下的牆面比光池外亮幾倍（只量背後有牆的地方）。調環境光或改燈之後重跑 |
| `tools/weapon_light_probe.tscn` | 槍燈：在真實關卡套上暗的光影，每把槍朝三個方向各拍一張；量開、關槍燈時 8 格外敵人的亮度，以及開火時每影格的耗時（開、關交替量）。這支工具也能原封不動拿去量還沒有槍燈的舊版本 |
| `tools/vfx_exposure_probe.tscn` ＋ `tools/vfx_exposure_sheet.py` | 每一份光影設定下的槍口、敵人死亡、油桶爆炸連拍與全白比例（`--level` 換成真實關卡、`--stress` 量連續爆炸的每影格間隔）；改爆炸或新增光影設定後重跑 |
| `tools/ne251_wake_probe.tscn -- --mode=route\|isolated\|resume\|sweep` | 過場舞台上主角頭部的純白比例，以及白髮和正後方背景分不分得開（`route` 走真正的倉庫溺斃 → 診間醒來；`sweep` 量所有有主角登場的舞台）；門檻純白 2%、糊掉 5% |

量測陷阱（都踩過）：
- 專案用 stretch，螢幕座標要用 `get_viewport().get_final_transform() * get_viewport().get_canvas_transform()`，只用 `canvas_transform` 會量到錯的地方。
- `Node.find_child("head")` 會先找到 Bone2D 而不是同名的 Sprite2D；要量零件請用 `find_children("head", "Sprite2D", true, false)`。
- 材質、modulate 的實驗要先確認真的套到目標節點（印出 `material`），否則會得到「沒有差別」的錯誤結論。
- 截圖是 HDR 浮點影像，像素值可以大於 1；「全白」用每個色版 > 0.92 判斷。
- 在地圖裡擺放主角：`layout.floor_below(欄, 4)`；有些位置在牆裡或鏡頭沒跟上，截圖看過再信數字。
- 過場的問題要走實際路線量一次：關卡在過場播放時還留在底下（補光倍率、泛光設定都是那一關的），單獨播放場景量到的不一定是玩家看到的（NE-251）。

## 驗收規則

1. 驗收畫面問題時：**先重現，再修，再用同一個場景重跑同一個量測**，修前修後並排放進票的截圖。
2. 不確定使用者看到的是什麼時，多試幾種觸發（光源距離、動作、特效、補光倍率高的暗場景），不要只量預設位置。
3. 看圖要看放大後的細節（過場倍率約 3.4 倍），不是縮圖。
4. 數字通過但畫面看起來不對，以畫面為準，回頭修量測。
