from pathlib import Path
import json
import subprocess

root = Path('C:/Users/stanl/Github/Nest-Egg')
packet = root / 'pm/Nest-Egg-BG/attachments/BG-32-native-residency-2026-11-17'
summary = json.loads((root / 'work/bg32-audit-20261117/variant-summary.json').read_text(encoding='utf-8'))
lines = []
for label, r in summary.items():
    lines.append(f"| {label} | {r['ratio'] * 100:.6f}% | {len(r['failures'])} | {r['enter_max_mean_except_startup_ms']:.3f} | {r['enter_max_except_startup_ms']:.3f} | {r['stage_sync_max_ms']:.3f} | {r['stage_enter_max_ms']:.3f} | {r['stage_exit_max_ms']:.3f} |")
rows = '\n'.join(lines)
changed = subprocess.check_output(['git', 'diff', '--name-only', '986b3a6b8', '3713db51062b14ed33ab61488559109fc41e2bfd'], cwd=root, text=True).splitlines()
runtime_changes = [x for x in changed if x.startswith(('core/', 'game/', 'scenes/', 'ui/', 'tools/'))]
(packet / 'baseline-code-changes.json').write_text(json.dumps({'native_base': '986b3a6b8', 'official_base': '3713db51062b14ed33ab61488559109fc41e2bfd', 'changed_code_paths': runtime_changes}, indent=2) + '\n', encoding='utf-8')
text = f'''# BG-32：9070 XT 重驗與最小修正

Godot 4.7.2 ed1daf0bf、Forward+ Vulkan、HDR 2D、AMD Radeon RX 9070 XT，1280×720；原生路線關閉 vsync、max_fps=0，不開 fixed-fps。全部 GPU 工作經跨 worktree 共用鎖串行，未與角色生成並跑。這次沒有更換圖、天空、主題、角色或渲染器。

## 可攜核驗

執行 `python verify.py`。只讀附件，不啟動 Godot/GPU；重算每個清單 payload、前後比例、15 次直接舞台 coverage、實際 owner finish/cancel、兩輪 E gates、Main 252/0 與每輪選單水位、實存存檔 checksum、來源與全部原始圖 SHA。`original-outputs.json` 記原輸出每檔 bytes/SHA；`raw-image-aliases.json` 對應原始 PNG 到兩個獨立 ZIP（各 <45 MiB，無重新壓圖）。包括 current 初輪、漏建負控、A/B/C/D/E 每輪和 Main D/E1/E2/E3 的失敗圖；不是只保留成功圖。`raw/` 保留原始 JSON、存檔、工具、正式測試 log；`work/` 保留當時變體、執行腳本與原始 console。`.gitattributes` 固定附件 bytes，不讓 CRLF 自動轉換改變證據 SHA。

## 產品差異與來源

原版 A 的街道鄰居第一次 requested/collected/cached 恰為 256，queue/inflight 都已 0；不是還沒載完。返回時變 331，第一次缺鄰居 88 項、返回缺 13 項。固定 256 的單次上限截掉尾段；後續同 scope 呼叫會跳過已 cache 的項目，所以回來才補入尾段，形成 114.640992% 的比較。E 對齊原已存在的 512 隊列上限，第一次和返回都是 331；受 128 MiB 總預算影響仍可合法缺 13 項，未要求全鄰居永駐。

E 同時讓閒置關卡不 pin 自己的 intro/trigger/channel/respawn 舞台；播放中仍由真 CutscenePlayer 持有，不砍當前 owner。鄰居預載只去掉當前 theme 沒用的天空／遠景及其同名 normal/glow，其他鄰居素材不變。`art/environment/backdrop/` 是此專案既有背景圖位置約定，並非新增硬編關卡／天空名稱；當前 theme.sky/backdrop 用既有變體收集，避免為此重走 prop/enemy。實際前景 ForegroundLayer 的 top/bottom 和 glow 雖同目錄，為每個 Level 都在用，工具沿正式常數保留，不能誤報未用天空。真 street/dawn/lounge/stall 的資料與 cache 回歸涵蓋此界線。

總 cache/queue 上限 512、總 128 MiB、主緒每影格 1 張、2ms 軟預算、載入後端策略原樣保留。軟預算不是單次同步 load 的硬實時上限，原 log 的超預算數值完整保留。

原版 A4 可重算的殘留：lounge 的 sky_dawn 2,605,056 bytes（prefetch）；stall 的 sky_storm 3,260,416 bytes（rig_cache+prefetch）；pawnshop_dawn 的 kitchen diffuse+normal 各 6,300,096 bytes（prefetch）。E 每站 stage/unused backdrop 都 0。原版第一→末站 payload 88,220,632→101,137,008；E 98,655,808→101,137,008 bytes。提高第一次分母是修復真截斷，不改 110% gate；同時以固定負控證明原版會拒絕。

`work/final-source-shas.json`、`frozen-candidate/` 是正式候選四檔。原生 E core SHA 是 115774bc…；最後 core 4ed88b06… 僅把註解改回中文及修正舊張數，`work/comment-mapping.json` 和兩份完整原 bytes 可重算非註解行完全一致；不可宣稱兩者原 byte 相同。正式 CPU 測試用最後 4ed 候選。

原生隔離基準是已發布 NE240 的 986b3a6b8，正式 affected advance 到 3713db51062b14ed33ab61488559109fc41e2bfd。兩者之間的程式差異見 `baseline-code-changes.json`：五個 inventory 音效頁與獨立 dialogue_box_capture 工具；Main／Level／CutscenePlayer／Story／環境渲染及本測試路線未改。沒有把不同 baseline 稱為同 bytes。advance 前逐檔備份且只還原自己四檔，自己的探針移到證據外部保存，再恢復完全相同四份候選；未 hard reset 或清理他人檔。

## 路線與計時界線

11 站固定為 street→booth_alley→street→warehouse→vault→lounge→stall→pawnshop_dawn→rooftop→pawnshop→street，每站 dwell 300。從同步 Level load/configure/add_child 前開始量到隨後 90 影格；stage 同步建立、12 個進場影格、拆除後 6 影格另記。readback 和截圖在計時窗外。排空預載有 30 秒界限，逐張匯入 payload 依 Image 實際尺寸／格式／mips／data_size，合併 cache、normal、prefetch、retiring 後依路徑去重，owner/source/scope 全保留。這不是實體卡專屬 VRAM；renderer_texture_bytes 是渲染器程序配置量，與 payload 分開。

coverage 沿 Level intro/triggers/channel、實際 layout NPC talks、章節死亡／復原入口，再依真 StoryRules 條目遍歷 dispatch、選項及 branch，列出 15 次實建舞台及完整來源鏈。這部分是直接舞台資源壓力測試，**不是自然玩過死亡或整章劇情**。另外同進程真 CutscenePlayer 播 authored ch1_c09_wake，逐句正常 finish，另一輪在舞台存在時 cancel；真角色、UI、FX owner 都經過進出，after stage=0。Main 路線在下一節另驗，不能由此取代。

門檻維持 110% 和 5%；無閒置 stage、無未用 backdrop、來源/coverage/engine error 都真 gate，失敗自然 exit 1。`control-skip-stage` 刻意漏建真沿途舞台，exit 1；CPU 自檢 12/0，注入 engine Logger error 仍 exit 1。真服務 18 checks 在原版 4 fail（尾段、舞台、兩天空），恢復 E 後 18/0；局部完整 Chapter1Map 1962/0。

## 所有變體與原值

A=256 原版；B=512；C=再取消閒置 stage pin；D=再去未用鄰居 backdrop、但收集目前區域時重走全資產；E=只收集當前 theme 背景，避免多餘掃描。A1/B1/C1/A2/C2 的工具尚無未用天空 gate，不得以 C=0fail 聲稱整票完成。D1/D2 工具把正式前景錯當未用天空，11 次錯報保留；D3/D4 依正式 Foreground 常數改正後才真正完整通過。工具版本 SHA 與當時完整來源都保留。

表中時間單位 ms。mean/worst 是每站 90 影格最長值的平均／最大（排除第一站啟動）；stage 是全路線 max。不能把不同 tool epoch 的數字當嚴格單因子改善。A3 檔案冷讀明顯較長，仍完整列出；不拿它作效能改善結論。最終同工具交替 A3/E1/A4/E2 的 warm A4 與 E1/E2 未呈現持續更長換區停頓，沒有新增容差或宣稱消除原有約 200ms 峰值。

| run | 回街道比例 | gate failures | enter mean | enter worst | stage sync | stage enter | stage exit |
|---|---:|---:|---:|---:|---:|---:|---:|
{rows}

真 CutscenePlayer finish/cancel 的最長影格：A4 21.695/21.369ms；E1 20.743/19.863ms；E2 19.101/21.591ms。這是重複樣本，沒有把不足 1ms 的自然變動改寫成改善或新門檻。A4/E1/E2 的純白最高都 <5%；精確逐站值在 report 中。

## 真 Main 新局、對話、選單與冷續玩

原 BG31 工具未更動（SHA 5efc7a70e5c35ae7de2d608efa31b21a365b2915d448dbbcf06a01a44cac5ac8），獨立複製工具只服務本票。Main E4 exact probe SHA 20b6c27e…，generator、原版、每次候選與 .tscn 一起保留。record PID39652，cold PID39256：131+121=252 checks、0 failure，兩份原 log 自然 EOF 無 SCRIPT/ERROR/Parse/Compile/leak。讀完真序章 6 句，真 Main 控制 world/level/store，合成 UI/input 移動接近老K、實際 interact 開啟/完成對話；pause clock、舊節點/weakref回收、保存/續玩位置生命值/進度/物品與故事一致均檢查。

為測人物對話，完整序章結束後受控呼叫 Main 正式 area owner 到 pawnshop，再真移動與互動；**這不是自然完成序章任務或人手操作**。沒有 teleport、更改物理/速度、舞台或關卡佈置。三輪 menu/continue 後再最後 return，共每進程 4 次 settled menu；都等待 queue/inflight=0，沒有以區域工具水位替代。

| 進程 | 每次 menu 環境 payload（bytes） | 每次 renderer texture（bytes） | 次數 |
|---|---:|---:|---:|
| record | 46,474,208 | 144,687,120 | 4 |
| cold | 46,474,208 | 143,560,720 | 4 |

各進程內完全平穩；不同進程 renderer 值不冒稱相同。Main 影格最大值逐事件保留，但畫面擷取等流程開銷可落入相鄰事件，不拿此值聲稱細微效能增益；嚴格對照用上面的 route 計時窗。

Main D 初輪 20/1：舊硬編3句但真序章6句，改用 authored entries 計數。E1/E2/E3 各29/1：工具持有的水平輸入被 flow/focus 清掉卻以為是碰撞，兩次跳躍嘗試同樣失敗，全部原圖與 log 保留；獨立真 Level CPU 診斷證明 x1136 無碰撞牆，改為有界重送實際輸入後 E4 走通，成功輪沒有用跳躍。這是 fixture 修正，沒有修遊戲碰撞或把失敗刪掉。

## 正式 affected 與重跑

正式工具只看到本票凍結 core/map/helper/probe 四檔，基準 full3713、SHARDS=2；受影響套件為 Chapter1Map、Chapter2Story、Chapter2、DeathReaction、Encounter、Environment、InputFeel、ReadabilityTargets、RunSave、UiScreens，共10組。結果以 `raw/official-3713/console.log`、exit.txt 與兩份完整 shard log 為準；執行前後 source guard 必須一致。工具本身的原生與自檢另列，不能聲稱這10組執行了原生探針。

重跑原生 route（新空輸出資料夾）可用：

```powershell
python tools/comfyui/gpu_lock.py -- C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe --path . --rendering-method forward_plus --rendering-driver vulkan res://tools/texture_route_probe.tscn -- --out=C:/NE/new-bg32-route --dwell=300
```

`--self-test` 可 headless；`--control=skip-stage` 原生必須自然失敗；`--self-test --control=engine-error` 必須自然失敗。真服務 standalone fixtures 原樣在 `raw/isolation-work-sources/bg32-scope-regression.*`，加入自己的臨時 work 路徑可重跑；舊路徑在 .tscn 中明示。Main exact 證據重現需在自己隔離 worktree 使用保留的 E1157 原 bytes（guard會誠實拒絕 final4ed 註解版），恢復對應 `work/bg32-main-E4/probe.*`，record/cold 應用獨立原生進程和空 profile；`--out=<絕對新資料夾> --slot=<絕對存檔> --phase=record|cold`。冷輪讀同一 slot 與 record-summary，不能換 fixture 假續玩。最後恢復候選 bytes，勿動共用工作區或正在生成的角色。
'''
(packet / 'README.md').write_text(text, encoding='utf-8')
print(packet / 'README.md')
