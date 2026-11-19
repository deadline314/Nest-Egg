# 沈望的週年演說

市集公告屏和對話框共用沈望的角色來源。她在第二章以 74 歲的退休水利工程師與天穹創辦人身分公開致詞。這份來源供公告影像與頭像使用。

- 原始圖為 768 × 768 RGBA，使用本機 RX 9070 XT 與 Qwen Image 2.1 生成。提示詞、ComfyUI 流程、種子及來源雜湊保存在同一目錄。
- 頭像取原生 512 × 512 裁切。公告屏沿用原有螢幕框、標記、支架和檯面，以同一張原圖合成畫面。發光層保留原有螢幕掃描效果，面板法線維持平面。

從專案根目錄執行以下兩個指令重建素材。加上 `--check` 可驗證來源及現有輸出。

```sh
python art_src/characters/ch2_guest_portraits/build.py --spec art_src/characters/ch2_shen_broadcast/portrait.json
python art_src/characters/ch2_shen_broadcast/build_board.py
```
