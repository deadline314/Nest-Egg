# BG-17 同機重現與限制

環境：Linux 6.18.44 / AMD EPYC 9V74、5 vCPU；Godot 4.7 stable 5b4e0cb0f；Vulkan 1.4.305 Forward+ / llvmpipe LLVM 19.1.7。沒有實體 GPU；不可與 Windows / Arc B580 或舊票不同機器數據互比。Godot 路徑以 GODOT 指定，Linux 使用 xvfb-run 與 Mesa Vulkan。

## 固定條件

- 替換前 ca369c71、修前 6f4805be、本次修改，三份獨立 checkout；同一份 tools/environment_probe.gd/.tscn 複製到基線。
- 320×180、low、第一章 tile 30/115/200、每處 5 靜止 grunt、固定種子 17、120 warmup + 180 frames，Dummy audio，關閉 vsync/FPS 上限。
- 共享鎖包住整個 Godot 工作，不與生成、其他截圖、大量測試並行。量測完成後才截圖；normal cache 即使 low 關閉取樣仍計入已載入記憶體。
- `ENVIRONMENT imported_payload_bytes` 是實際 CompressedTexture2D.get_image().get_data_size()，逐張尺寸、格式、mips、bytes 列在原始 log；相同路徑去重，含 diffuse/glow/normal。這是匯入貼圖 payload，不能宣稱為實體 GPU 的 dedicated VRAM 配置。`renderer_texture_bytes` 是整程序渲染器統計，包含非環境圖與 framebuffer，另列。
- BC7 全圖壓縮試驗節省記憶體但本機 mean frame 約 62ms，因此拒絕；已還原 lossless。診斷 shader override 只在工具 runtime 暫時套用，明確標 NOT acceptance，未修改角色檔案，也不足以把整個效能差距歸因於角色。

## 最終結果

環境實際匯入 payload（321 張）：322,205,351 → 160,348,152 bytes（307.3 → 152.9 MiB，49.8%）。整程序 renderer texture statistics：修前約 393.6 MiB → 本次 225.9 MiB（包含 framebuffer 與角色，不能當環境專屬 VRAM）。未使用的環境 mips 已停用，主視窗 sampler 在 log 實測為 1（linear）；原圖不變，立面與細長圖保留必要尺寸。

| 第一章位置 | 替換前 ca369c71 ms | 修前 6f4805be ms | 本次 ms | 本次／替換前 |
|---|---:|---:|---:|---:|
| tile 30 | 20.831 | 26.767 | 30.097 | 144.5% |
| tile 115 | 18.581 | 28.317 | 26.353 | 141.8% |
| tile 200 | 18.466 | 27.713 | 24.533 | 132.9% |

低檔相對替換前 105% 尚未達標；替換前到現在還包含角色、戰鬥及其他程式變動，不能全部歸因於環境。本次保留已合入全局光影及角色設定，沒有以停用角色 shader 的診斷結果冒充驗收。

受影響測試：39 組、43,239 checks、零 new／known failures。初次檢查抓到立面解析度／細長圖取整／舞台生命層 fixture 的實際退化，修復後重跑；劇情首句顯示的初次失敗在重跑通過，known_failures.txt 未變更。StageCoverageWorldSuite 實際需約 153 秒，基線獨跑 93 checks／0 failures，不把慢測試誤稱卡死。

## 命令

```sh
python tools/assets/texture_import.py
python tools/comfyui/gpu_lock.py -- "$GODOT" --headless --editor --quit
python tools/comfyui/gpu_lock.py -- xvfb-run -a "$GODOT" --audio-driver Dummy --path . --resolution 320x180 --rendering-driver vulkan --rendering-method forward_plus res://tools/environment_probe.tscn -- --frames=180
python tools/comfyui/gpu_lock.py -- xvfb-run -a "$GODOT" --audio-driver Dummy --path . --resolution 640x360 --rendering-driver vulkan --rendering-method forward_plus res://tools/readability_check.tscn -- --quality=low
SHARDS=8 tools/run_tests_changed.sh <本票第一個提交的父提交>
python tools/assets/check_assets.py
python -m unittest discover -s tools/assets -p test_texture_import.py
python -m unittest discover -s tools/comfyui -p test_gpu_lock.py
```

實體 GPU 驗收：同機同法再量三個 checkout；先確認 Session 1 沒有生成工作、常駐模型已依既有流程釋放。共享鎖只序列化運算，不保證顯示記憶體足夠。本 Session 不操作 ComfyUI。

## 跨組接手界面

- 環境政策 `assets_src/pipeline/texture_import.json` 與 `tools/assets/texture_import.py`，素材加工後自動套用；source art、map 座標、家具 pos/scale/layer、角色 rig、既有 LightKit/global grade 不變。
- `BackdropLayer.source_width` 及舞台 sprite `source_width` 是渲染尺寸補償。StageLayers.sprite_scale 保留原作者的世界尺寸；StageLibrary 同樣補償，避免誤判覆蓋面積。生成舞台資料後再套用匯入政策；check_assets 偵測漏套用。
- NE-222／角色 shader 的全局性能仍由 Session 1 負責；診斷不等於根因證明。Session 3 保有擺位與關卡流程所有權。本 Session 沒有自動向其他聊天傳訊。
- 真正未通過的暗場／低檔耗時與實體 GPU 檢查不得勾選。保留其他 Session 已合入的光影值。

舞台／場景整圖的縮圖在實際開場對照中使櫃台與地板變軟，因此保留全解析度；最終 152.9 MiB 仍低於修前一半。Stage 引用縮圖道具時仍用尺寸 metadata 補償。
