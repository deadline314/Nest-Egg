# Radeon 9070 XT 本機生成環境

2026-11-11，使用者已換成 AMD Radeon RX 9070 XT。現有 `D:/ComfyUI/.venv` 為 Python 3.12.11／PyTorch 2.11.0+cu128，保留作舊環境，不把 CUDA 套件直接當作 AMD 支援。

## 選擇與依據

- 採 Windows 原生 ROCm，建立獨立 Python 3.13 環境，保留既有 ComfyUI 原始碼、模型、節點及原定稿。
- 先固定 ComfyUI 官方 Windows ROCm 10.0 建議的 PyTorch 與 gfx1201 裝置套件，再逐項核對現有節點相容性；不因新 wheel 可下載就宣稱可生成。
- 實際檢查 HIP 版本、顯卡身分、裝置上的張量計算、ComfyUI 系統資訊與一個原生 RGBA 生成工作。記錄版本、工作圖、seed、輸出與錯誤；來源／解析度／分件／骨架驗收仍依角色技能。
- 啟動腳本可指定 Python 路徑並依實際後端選參數，不再依資料夾或 venv 名稱猜顯卡。無可用加速器時回報實際原因，不靜默改用 CPU。
- 生成與 Godot 原生驗證共用 GPU 鎖；一次一張，依當下記憶體占用調整，不更新驅動或重開整台機器來掩蓋相容問題。

## 官方來源

- [ComfyUI：AMD Windows ROCm 10.0](https://github.com/Comfy-Org/ComfyUI#amd-gpus-windows-rocm-100)
- [AMD：PyTorch 安裝與裝置專用套件](https://rocm.docs.amd.com/projects/ai-ecosystem/en/latest/frameworks/pytorch/install.html)
- [AMD：ROCm 10.0 相容矩陣](https://rocm.docs.amd.com/en/docs-10.0.0/compatibility/compatibility-matrix.html)

網站會更新；交付以保存的實際套件版本、硬體測試與生成紀錄為準。

## 實測與操作（2026-11-11）

獨立環境為 `D:/ComfyUI/.venv-rocm`，Python 3.13.15、PyTorch 2.13.0+rocm10.0.0、gfx1201 裝置套件。實際 `torch.version.hip` 為 7.15.26333，這是套件回報的執行期版本，不改寫成 wheel 的 ROCm 10.0 標籤。9070 XT 上的 0～15 平方和實際得到 1240，沒有 CPU 回退。套件固定清單在 `tools/comfyui/requirements-rocm-windows.txt`；ComfyUI 保留原版本 79be670，原 CUDA 環境、模型與定稿未替換。

啟動前明確設定 `COMFYUI_DIR`、`COMFYUI_PYTHON` 及客戶端 `COMFY_HOST`，以 `-PlanOnly -Port 8189` 預覽。實際啟動、重用、重新啟動與停止均維持該埠及直譯器。非預設埠使用獨立的 user/input/output/temp、log 及明確 SQLite URL；只有 user 路徑仍會觸發 ComfyUI 的舊資料庫搬移，首次錯誤已保存，明確資料庫 URL 後重新驗證沒有該錯誤。停止只精確比對指定埠，不能把 8189 認成 81890。

一次原生 832×1216、25 步的既有 Qwen RGBA 工作流已成功，seed 26711；工作圖、提示、輸出及完整 alpha 分布均保存。生成透過既有共享 8188 服務的正常佇列完成；該服務使用 `.venv-aot-amd`，同為 Python 3.13.15／PyTorch 2.13.0+rocm10.0.0／9070 XT。這不冒稱獨立 `.venv-rocm` 服務完成模型生成：後者另驗 GPU 張量與 8189 服務生命週期。客戶端在共享服務上禁止啟停／重試重啟，也不卸載其他工作模型。

原生透明圖不作角色定稿。提示指定中年女性，但樣本的年齡與性別呈現不足，仍須角色票的身份、畫風、動作與接點驗收。原始 alpha 有低透明度雜點；不切掉、重繪或把它冒稱精修完成。黑、灰、白底只供檢視原始 alpha，原 PNG 未改。

本 repo 與 worktree 以共享鎖串行生成／原生 Godot，其他專案的工作另行觀察；本次沒有獨占 GPU 的效能宣稱。詳細版本、失敗與重跑方法見 `pm/Nest-Egg-BG/attachments/BG-52-rocm-runtime/README.md`。
