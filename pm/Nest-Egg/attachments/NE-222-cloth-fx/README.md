# NE-222：衣物受損與克制布屑

本段交付衣物受損時的短暫特效，不代表跪姿、解剖、全部接點或操作手感已通過。正式來源、PNG、骨架、HP與攻擊時序未改。

## 原有行為與本次變更

凜已有五組衣物受損外觀，HP透過真正Player回呼更新。以六點HP示例，第一次受傷剩五點仍在同一外觀階段，剩四點才移除外套；其後依序是胸口、腰臀與大腿，小腿的最後階段在零HP。`armor_debris: false`保留完整身體；舊版本仍對每件受損衣物噴出裝甲火花。

本次改用既有非加法粒子場的暗色布屑：每件最多三片，0.32–0.48秒淡出，沒有額外發光環、整段身體或整件衣物剪影。初始化、未跨階段、回血和非有限位置不噴屑。原生pose替代網格從同一slot的身體部件取掛點，避免全部集中在Skeleton原點。真正裝甲敵人維持原來的碎片及裝甲火花。

方向參考[Riot Games：Visual Effects](https://www.riotgames.com/en/artedu/visual-effects)：節制效果，清楚傳達狀態，並保持角色與整體風格一致。這些粒子數、速度與時間是本專案的實測起點，不是通用業界標準。

## 實際驗證

- Godot `4.7.2.stable.official.ed1daf0bf`；Vulkan 1.4.351、Forward+、RTX 4070 SUPER、HDR 2D。兩次GPU工作走現有共享鎖，生成未同時執行。
- 固定水平瞄準的真正Player HP事件，兩面向與camera zoom 1.0／3.4，各拍12張：初始、五次傷害各兩張、回血。修前／後各48張1280×720原生PNG，未重採樣；全部保留在[修前](../../images/NE-222-cloth-fx/before/)與[修後](../../images/NE-222-cloth-fx/after/)。沒有模擬輸入或聲稱完整戰鬥播放。
- 這是neutral光照診斷；關閉此fixture的post與fog，固定相機和玩家物理處理，正常外觀動畫、受傷、粒子與光照回呼仍執行。不能當成所有場景的後製、霓虹、接縫或效能驗收。取樣0.23秒及再過0.5秒，並非全動作逐格掃描。
- 四個面向／倍率組合皆在剩四／三／二／一點HP時分別錄到18／3／3／6片布屑；18片來自同一外套階段六件衣物，每件最多三片。初始、第一擊、恢復及消散取樣均零布屑，全部48張零RigDebris。兩側均看見衣物受損貼圖及短暫小布屑，沒有新的整段身體剪影。
- 真正Player headless回歸216 checks：前後受擊、兩面向、未跨門檻、恢復、致死、布屑到期、數量、定位、pose掛點負控制、非有限座標；敵人裝甲回歸包含在內。相關三個FX套件443 checks，皆零失敗。
- 固定基準`8b61faef5561211275d8341f7ef3c10a64442638`執行`tools/run_tests_changed.sh`，實際選76組，八個headless程序平行；53,980 checks、零新失敗、零已知失敗、259秒，沒有SCRIPT ERROR。完整套件未執行。
- Rebase至`0f1aa0a1`後，遠端改到章節建置與場景檢查；重跑SceneSanity、Props、Chapter1Map與HitReaction共1,983 checks，零新／已知失敗、61秒、沒有SCRIPT ERROR。合併後log另外保存。
- 同一三組FX套件的乾淨基準與修後皆出現6 Area2D RIDs、6 CanvasItem RIDs、16 ObjectDB及8 resources離開時的診斷，已保存兩份log比較，未改known failures或把它們稱作無錯誤。原生修前另有4 ObjectDB／1 resource離開診斷，原生修後沒有ERROR；資料與遊戲驗收不因exit 0掩蓋log內容。

## 重跑

從最新已整合專案根目錄，使用實際Godot與Python路徑；Comfy模型常駐時先由本Session透過既有停止流程釋放資源：

```powershell
$env:GODOT = 'C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe'
& 'D:/ComfyUI/.venv/Scripts/python.exe' tools/comfyui/gpu_lock.py -- $env:GODOT --path . --audio-driver Dummy res://pm/Nest-Egg/attachments/NE-222-cloth-fx/capture.tscn -- --out=D:/review/NE-222-cloth-fx
```

此命令重拍當前行為。修前需獨立checkout固定基準，複製同一fixture到相同相對位置後執行；不在最新main倒退正式程式。原生命令的當時路徑為`res://.godot/ne222-clothing-capture/capture.tscn`；公開fixture只改script資源路徑，拍攝程式相同。

受影響測試以本票實作前固定SHA執行：

```bash
GODOT='C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe' SHARDS=8 tools/run_tests_changed.sh 8b61faef5561211275d8341f7ef3c10a64442638
```

[修前紀錄](before-capture.json)、[修後紀錄](after-capture.json)、[局部回歸與基準比較](verification.md)、[SHA索引](manifest.json)。完整raw logs在本目錄；未把文件圖、來源圖或合成圖當成遊戲截圖。
