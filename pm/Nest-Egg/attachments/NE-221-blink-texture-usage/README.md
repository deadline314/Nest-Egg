# 眨眼貼圖引用檢查修正

`check_parts.py` 原來只計入普通部件與握持貼圖，誤報正式 `eye_states` 的半閉、閉眼圖無人使用。現在辨識三個眼睛狀態的實際引用；所有貼圖仍走原來的完整初篩，沒有修改孔洞、碎片或透明度門檻。

CPU 重跑：

```powershell
python tools/comfyui/test_check_parts.py
python tools/comfyui/check_parts.py rin old_k nurse night_worker repairman_chen resident ah_po wataru mei --normals
```

回歸修前3項有2項失敗，修後3項皆通過；另驗證未引用貼圖仍報警、眼圖缺檔仍報警、無效眼睛配置不掩蓋未引用貼圖。正式九角色初篩保留凜後髮的兩個孔洞警告（最大762來源像素），因此整批 exit1；這不是接縫或全身美術通過。

紀錄：`regression-before.log`、`regression-after.log`、`parts-before.log`（凜、三種重裝敵人、老K、阿婆）、`parts-after.log`（全部九個眨眼角色）。檢查器只改Python引用辨識，角色PNG／骨架／動作與原生眨眼時序不變。文件預覽是檢查結果說明，不是本次重新播放遊戲的證據。
