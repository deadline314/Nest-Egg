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
