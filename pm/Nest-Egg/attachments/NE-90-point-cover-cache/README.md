# NE-90 點提示遮罩快取修復

局部遮擋遮罩原來只記錄點位和門檻。12×12 fixture 改一個來源像素、畫布大小不變時，實際 `make_parts.main()` 仍重用舊遮擋遮罩。現在近腿、遠腿及局部遮擋共用來源與設定的識別契約；未變的輸入仍命中，局部點位改動不觸發另一組獨立點提示。

改動範圍：`tools/comfyui/make_parts.py` 與新 CPU 回歸 `test_point_mask_cache.py`。既有 `build_character`、近腿／遠腿與 cover 呼叫維持原接口；只把實際 refine 明確傳給分割器。舊鍵下一次執行相應分割才失效，原 PNG 與定稿不自動重跑。

重跑（Windows 設 `PYTHONUTF8=1`）：

```text
python tools/comfyui/test_point_mask_cache.py
python tools/comfyui/test_mask_delivery.py
tools/run_tests_changed.sh 81d30718b551c06eeae2b6a1c399eee54ffdd611
```

- `regression-before.log`：修前 10 tests、3 failures，退出 1；來源、模型名稱與 refine 的失效測試重現問題。
- `regression-after.log`、`proof-regression.log`：root／獨立 sparse checkout 各 10 tests 通過，退出 0。
- `mask-delivery.log`、`proof-mask-delivery.log`：既有製作工具回歸退出 0，不載模型或 GPU。
- `affected-tests.log`：獨立 checkout 僅套用本票兩份 Python 差異，固定上述基準；正確選出 0 個 Godot 套件，不能算遊戲測試通過。
- `document-native.log`：真 Godot 4.7.2／Forward+／RTX 4070 SUPER 文件預覽，1440×1000，使用共享鎖且 Comfy 已停止。圖片是結果說明，不是遊戲或動畫驗收。

不計通過的執行保留在 rejected：root 首次因 Windows cp950 預設編碼失敗，設定 UTF-8 後重跑；隔離 checkout 初次缺少配方已註冊的來源重建腳本，補齊對應 tracked `art_src` 後重跑；首次文件預覽缺少字型匯入，以共享鎖完成獨立預覽專案匯入後重擷取，正式 log 無 ERROR。沒有修改回歸斷言來略過錯誤。

測試只 mock SAM 輸出，實際快取讀寫與來源灰底重建走正式 `main()`。模型名稱測試只驗證鍵，不聲稱 monkeypatch 改變真 SAM 的模型；同名權重替換仍須人工撤銷相應鍵。這不是遮罩解剖、原生 alpha、所有權或動作接縫通過；NE-90 保持進行中。
