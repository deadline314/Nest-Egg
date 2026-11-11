# BG-52：9070 XT 本機生成環境

本輪交付 GPU 環境與一張工作流樣本，不代表角色定稿。全部原始資料與來源位元組在 [raw.zip](raw.zip)，雜湊與來源清單在 [receipt.json](receipt.json)。[獨立保存驗證](verification.json)為 101 項、0 失敗；不啟動服務或載入模型。

## 實際結果與界線

| 項目 | 觀察 |
|---|---|
| 硬體 | AMD Radeon RX 9070 XT，16 GB VRAM，驅動 32.0.32015.7029 |
| 獨立環境 | `D:/ComfyUI/.venv-rocm`，Python 3.13.15，PyTorch 2.13.0+rocm10.0.0，裝置 gfx1201 |
| GPU 運算 | 真正裝置上的 0～15 平方和為 1240；backend=rocm、device=cuda，後者為 ROCm 的 PyTorch 命名空間 |
| HIP 回報 | 7.15.26333，保留實值，沒有改成 wheel 標籤版本 |
| 獨立服務 | 8189 啟動、重用、重新啟動、停止均 exit 0；停止後端點不可達；最終三次服務 log 無 ERROR／Traceback／節點匯入失敗 |
| 生成 | 832×1216 原生 RGBA，Qwen 2.1、25 步、seed 26711，179.37 秒；這是觀察耗時，非獨占基準 |
| 生成服務 | 既有共享 8188、`.venv-aot-amd`，同版本 PyTorch 與 9070 XT；不是獨立 `.venv-rocm` 完成模型生成的宣稱 |
| CPU 回歸 | 實際後端、無 GPU 拒絕、埠與安全重試、遠端拒絕本機重啟、HIP OOM、預覽不變更、精確停止埠等 8 項；既有快取 7 項、GPU 鎖 2 項，全過 |
| 遊戲影響選擇 | 此票生成工具選出 0 組；直接跑上述 17 項，不以空選擇代替驗證 |

兩個服務的分工如實保留：獨立環境實際驗 GPU kernel 與完整服務生命週期；生成工作透過已存在、同硬體與加速版本的服務排隊。客戶端不啟動、停止、重啟或卸載共享服務的模型。生成時未啟本票的原生 Godot；8189 停止釋放後才接續原生 Godot 重驗。共享鎖只涵蓋本 repo／其 worktree，不宣稱可攔截其他專案，也不宣稱獨占效能。

## 原圖與 alpha

原 PNG SHA-256：`816c34cd9aa12203e7218e3d6fb610493deffc3d27d227b3c9b1c3375b2ed1ac`。四角 alpha=0，有不透明主體；完全透明 768,268 像素、alpha 1～3 共 55,834、4～39 共 2,586、40～249 共 4,705、250～255 共 180,319。完整 256 階分布在原 generation.json。

原生 alpha 未切圖、去背或精修。黑／灰／白底診斷圖均實看過，包含低 alpha 雜點；原始完整 alpha bbox 因雜點遍及畫布，不能把它說成乾淨切邊。提示的中年女性身份呈現不足，因此只收作環境樣本，未採用到任何角色或批准來源。

![原生透明工作流樣本，未作角色定稿](../../images/BG-52-radeon-runtime-sample.png)

## 保留的錯誤

最初套件缺 GGUF 依賴及服務共用資料庫的錯誤保留。安裝對應依賴後，第一版 user 路徑隔離仍會讓 ComfyUI 嘗試搬移原資料庫：雖端點 ready、四命令 exit 0，server log 有 ERROR，所以 lifecycle-v1 不算乾淨通過。

查實際 ComfyUI 原始碼後，改成非預設埠的明確 `--database-url`，避免舊資料庫搬移；lifecycle-v2 首次建立獨立庫成功、重新啟動不重建／搬移共享庫，三次 log 乾淨。兩批原始結果均保存，不重寫舊 log 或把 ready 當作沒有錯誤。舊 CUDA 環境另有套件查詢紀錄，未卸載或覆蓋。

## 重跑

先設定正確環境及埠，確認沒有其他工作持有該服務。GPU 指令透過共享鎖：

```powershell
$env:COMFYUI_DIR='D:/ComfyUI'
$env:COMFYUI_PYTHON='D:/ComfyUI/.venv-rocm/Scripts/python.exe'
$env:COMFY_HOST='http://127.0.0.1:8189'
python tools/comfyui/gpu_lock.py -- D:/ComfyUI/.venv-rocm/Scripts/python.exe tools/comfyui/runtime_probe.py --exercise
powershell -File tools/comfyui/start_comfyui.ps1 -PlanOnly -Port 8189
python tools/comfyui/verify_rocm_evidence.py pm/Nest-Egg-BG/attachments/BG-52-rocm-runtime
```

ZIP 含實際工作圖、提示、生成腳本、最終生命週期腳本、完整套件清單、硬體／共享服務程序觀察、安裝與測試輸出、初次失敗和最終 log、原始 PNG 及三底色診斷圖。腳本以 repo 根目錄的 work 路徑執行；生成腳本的 `--reuse-service` 只准使用既有服務，服務消失就失敗，不會接管。原始來源快照與目前交付來源分開標示。
