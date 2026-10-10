# NE-90 參考編輯 RGBA 通道修復

正式修改只有 `tools/comfyui/comfy_api.py`、其既有 CPU 回歸與製作文件／三組技能，沒有採用新角色立繪、分件或骨架。

修前 `LoadImage` 的 IMAGE 只有 RGB，MASK 是反向 alpha；目前 API 每個參考槽以既有 `JoinImageWithAlpha` 合回 RGBA，再傳給 `TextEncodeQwenImage21`。已核對本機節點來源：vision 分支按 alpha 合成白底，VAE 收到四通道。編輯工作流 job key 增加版本，舊 RGB-only 編輯不命中新 key；文生圖原 key 不變。既有定稿沒有自動重跑或覆寫。

## 真正執行的檢查

- 固定基準 `eb7ac9d5603692aaa8b36aab48996e385ef529bd`：新增兩項回歸在舊 API 下產生三個 failures（兩個參考槽與舊 edit cache）；修改後 7 tests 通過。RGB 與 RGBA 參考、多槽、編輯 latent、文生圖快取、cache options 與無效參數都實跑。
- 乾淨的 detached sparse verification checkout 只套用兩份 Python 差異，實跑 `tools/run_tests_changed.sh eb7ac9d5603692aaa8b36aab48996e385ef529bd`，正確選出 0 個 Godot 套件；另外執行相同 7 個 Python tests。這不表示遊戲測試已跑。root 明列兩份檔的完整專案選擇結果同樣是 0。
- `verify_roundtrip.py` 經本機 ComfyUI 真節點 Load / Join / Save，不載入生成模型、CLIP 或 VAE。原輸入及三個 saver 的真 PNG、graph 與安裝節點 SHA 見 `roundtrip-report.json`，按 saver ID S0/S1/S2 核對，不按多輸出順序猜對應。
- 原 RGB-only 分支存成 RGB，等效 alpha 全 255。Join 分支是真 RGBA，alpha 0 與 255 都保留，RGB byte-equal；原 RGB 圖 Join 後 alpha 全 255。16×16 測試的八種 alpha `[0,1,39,40,128,254,255,64]` 實際回存為 `[0,0,38,39,128,254,255,63]`：128 個 alpha byte 相差 1，沒有聲稱全 RGBA byte-exact。這是浮點合回再存 uint8 的截斷，不是接縫容差或原圖修改授權。
- 第一次檢查腳本誤以 SaveImage prefix 配下載檔，StopIteration（`roundtrip.log`），沒有算通過；API 實際多 saver 下載名保留 node ID，修正查找後 `roundtrip-v2.log` 退出 0。Comfy server 只跑這組圖像 I/O，模型未載入；目前沒有 WebSocket module，既有輪詢成功完成。
- `NE-90-reference-rgba-contract.png` 是 Godot 4.7.2 / Forward+ / RTX 4070 SUPER 實際擷取 1280×720 的診斷文件預覽；16×16 原始圖以 nearest x15 展示。不是角色原圖、生成比較或遊戲驗收。原生 capture exit 0、無 SCRIPT ERROR；ComfyUI 已停止，共用 GPU 鎖。

## 重跑

從專案根目錄執行 `python tools/comfyui/test_cache_options.py`。實際節點 replay 腳本原本位於 `.godot/ne90-reference-rgba/`；要重跑先複製 `verify_roundtrip.py` 至新私有 `.godot/ne90-reference-rgba/` 目錄，以實際 Python 執行，設 `COMFYUI_DIR` 指向實際安裝，循既有 shared lock／guard。腳本會启动 ComfyUI 並上傳合成測試圖，但不載模型；不要在已發布 packet 内直接執行／覆寫證據。`node_source_sha256` 釘選這次實際安裝；其他版本先核對節點契約。原生 capture 的 private path 與 source PNG 同樣先複製回獨立驗證 checkout，不修改正式素材。

編輯尺寸由第一張參考 latent 決定，w/h 並不決定編輯畫布。官方 encoder 以 resolution² 面積保比例取 32 倍數，resolution=0 為原參考取 32 倍數。這是節點原始碼／官方文件核對，沒有以此宣稱新人體姿勢生成通過。

參考：[Comfy Qwen 2.1 workflow](https://docs.comfy.org/tutorials/image/qwen/qwen-image-2-1)、[TextEncodeQwenImage21](https://docs.comfy.org/built-in-nodes/TextEncodeQwenImage21)。輸入通道修正不保證生成 alpha、全角色所有權、人體、接點或全動作；這些整體 gates 仍未勾選，NE-90 維持進行中。完整遊戲測試交 CI，沒有更改 known_failures。
