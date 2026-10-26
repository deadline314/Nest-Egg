# Godot 4.7.2：音訊資料生命週期修補

NE-280 的暫時引擎修補，對應 [Godot 124217](https://github.com/godotengine/godot/issues/124217)。保留音訊與空間混音，不改遊戲的聲音設定、測試選擇器或失敗清單。這是客製引擎，不能稱為官方發行版。

官方原始碼以兩次主執行緒更新延後回收匯流排資料；負載下，音訊執行緒仍可能正在複製舊資料。修補在回收前取得既有 driver 鎖，等待當次混音完成。退休資料已從原子指標移除，之後的混音無法再取得它；SafeList 的延後刪除因此也在這個同步邊界之後。Dummy、ALSA、PulseAudio 的混音都持有同一把 driver 鎖。沒有新增音訊執行緒配置，也沒有輪詢等待或無界限資料保留。主執行緒可能等待當次混音完成，須連同原負載和效能驗證。

## Linux x86_64 開發環境

需要 Python 3.12+、C/C++ 編譯器、pkg-config、venv 與 wayland-scanner。Ubuntu 24.04 的套件是 `build-essential python3-venv pkg-config libwayland-bin`。第一次會下載固定 Godot 原始碼、AccessKit SDK 與 SCons，並完整編譯；預留約 8 GiB，低核心機器可能需要一小時。

```sh
python3 tools/godot_audio/test_build.py
python3 tools/godot_audio/build.py --jobs 3
GODOT="$PWD/work/godot-audio-safe/dist/godot" tools/run_tests_changed.sh
```

建置器保留 X11、Wayland、AccessKit、Vulkan、OpenGL 3 與完整 editor。使用 production 最佳化，關閉 LTO 以控制建置時間與記憶體；不保證與官方編譯器產出的效能完全相同。自訂 `--work-dir` 可隔離建置。`--archive` 只接受 manifest 固定雜湊的來源包；`--scons-python` 可指定已安裝固定版本 SCons 的 Python。

後續使用先驗證來源版本、patch、配方、二進位大小及 SHA-256 收據，成功才重用。`--verify-only` 僅驗證、不下載或重建。修改了既有來源或下載快取時會拒絕覆寫，應保留現場並另選新的專用建置目錄。不要讓多個程序共用同一個建置目錄。失敗會回報具體階段，不會自動換鏡像或退回有缺陷的官方引擎。

`dist/receipt.json` 記錄來源、patch、編譯命令、編譯器、功能與二進位雜湊；`LICENSE.txt` 與 `COPYRIGHT.txt` 一起保留。CI 只快取這份完成的 dist，恢復後再次核對，並在遊戲測試前保存快取。

## 獨立音訊負載

```sh
python3 tools/godot_audio/run_audio_load.py \
  --engine "$PWD/work/godot-audio-safe/dist/godot" \
  --project "$PWD/tools/godot_audio/probes" \
  --output "$PWD/work/audio-load-new-run" --cases 8 --seconds 12
```

輸出目錄必須尚不存在。每個程序使用獨立設定目錄；先從實際取樣核對中央左右平衡、降低 12 dB 的振幅比例及左右移動的聲道差，再核對 32 個移動音源、音量變化、固定上限的記憶體配置與非零混音。退出前等待實際混音進度，檢查崩潰、逾時、腳本錯誤與資源洩漏。Dummy driver 仍執行混音，但這不等於實體聲卡／耳機聽感驗收。單次未重現也不能排除間歇競態；原八程序遊戲回歸仍是必要條件。

## 其他平台與上游更新

自動建置與快取收據目前只支援 Linux x86_64。Windows／macOS 可用 Python 3.12+ 執行 `build.py --prepare-only --work-dir <專用目錄>`，取得經驗證及精確套用修補的來源，再依 [Godot 平台建置指南](https://docs.godotengine.org/en/stable/contributing/development/compiling/index.html) 使用該平台的 editor／export-template 工具鏈。`--prepare-only` 不代表已建置，也不產生通過收據；各平台與 export template 須使用同一來源修補並各自完成原生、裝置與遊戲回歸，不能拿 Linux 結果代稱。

上游正式版本包含對應修正後，先對照來源與原崩潰負載，再更新引擎版本及 CI，最後移除這份暫時修補。不要只依版本號猜測缺陷已修好。
