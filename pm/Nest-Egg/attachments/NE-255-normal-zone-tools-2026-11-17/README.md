# 法線回呼與來源關節設定

基準：e6017a0fc40dc3f6c55ce260b644ad441e972ff9。範圍為共用工具，沒有交付或宣告新角色完成。

配方normal_rebuilds先驗證全部來源路徑，再執行原normal painter與登記回呼；未登記維持原呼叫。CPU測試實際執行成功回呼與exit7失敗回呼，錯型別、缺檔、越界在painter前拒絕。limb_zone沿runtime原有限範圍由spec寫入rig，錯誤設定在任何輸出前拒絕，原產物保持。

## 相同測試與原始紀錄

- 原版normal回歸：5 tests，10個失敗斷言／子案例；修後5 tests通過。
- 原版limb_zone：3 tests，12 failures與4個缺欄位errors；改用固定原輸出fixture後在原版重跑仍為相同紅例，修後3 tests通過。
- 最小預設fixture由原版實際輸出取得；兩JSON逐位元組核對（僅正規化工作樹換行），PNG逐RGBA核對，避免把PNG壓縮器版本差異當像素差異。建立fixture當時原版與原測試對照的PNG bytes也相同；不讀當前HEAD作永久golden。
- 相關caps、registered layers、hand attachments、final overrides 8項、source alpha 11項、refine fill 3項全過，原stdout/stderr合併bytes保存在logs。
- C:/NE/queue-20261117隔離來源跑tools/run_tests_changed.sh e6017a0fc40dc3f6c55ce260b644ad441e972ff9：無受影響遊戲套件，exit0。初次命令誤將CI檔複製至自身；工具未受影響且該錯誤已保留在命令紀錄，改成絕對來源後重跑，final-changed-selector.log為正式結果。

CPU命令：D:/ComfyUI/.venv-rocm/Scripts/python.exe tools/comfyui/test_normal_rebuilds.py，以及test_limb_zone.py。source/保存本次來源，original/為原版兩工具；receipt.json逐檔SHA可獨立核對。

## 原生診斷邊界

knee-stand四張PNG為相同姿勢／光照／時間下normal開關×剛體網格四控制；knee-continuous為連續法線後同條件。兩JSON記錄骨角，comparison.json記錄區域RGB差異，build log證明原painter後才執行回呼。畫面來自本機9070XT Forward+。

當時沒有凍結整套舊spec、parts、motion；不能據此宣稱最終角色來源可重播或全動作已驗收。凍結的callback僅保存當時bytes，移動位置後WORK不同，不可在附件位置直接執行。這些圖片是定位流程缺口的原始診斷，角色終版仍另做完整來源封存和動態驗收。沒有調整renderer、checker或驗收門檻。
