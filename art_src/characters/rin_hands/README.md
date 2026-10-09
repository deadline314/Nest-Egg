# Rin 的兩側手臂與握持附件

Rin 的右手仍是機械義肢，左手改為獨立的人體手與手臂。只消費保留來源中的指定部位；s33 頭臉、身體、髮型、腿與已驗證的穿著外套不重畫。K／L 是先前快取的局部來源，不套用私有試作的骨架、動作或權重；本次只生成缺少的右手機械握持圖，seed 22275。

`manifest.json` 保存所有原圖、提示詞、工作流、遮罩的 SHA256、原圖到 canonical 832×1216 的變換，以及來源腕部與掌心握點。新機械手的透明輸出含低 alpha 雜點和陰影，故使用保留的 SAM 點選遮罩分割；不將原始 Qwen RGBA 直接稱為乾淨交付。L 的工作流紀錄是先前依提示詞重建的 graph，原紀錄保留此限制。

手腕是骨架旋轉中心，掌心是武器握點，兩者不能混為同一點。新握持附件沿用原手腕與 +X 掌指軸，腕部校準由原圖腕接頭 row 560 的實際左右邊界（363–386）取中心，將原支點 x=369 校正到 x=374；前臂長只在 setup 固定為 6.54 世界像素，動作時不改骨長，武器材質握點不變。四指屈曲加一個拇指，不能把延伸的手指、槍或另一隻手切入附件。右前臂保留既有圖中真實機械腕接頭的 source rows 542–573，使接頭跨越分割邊界；手部也保留 rows 528–560 的真實前臂連接。沒有畫圓形填洞片。

原精修的「洋紅雜點」過濾曾把金屬上的粉紅反光挖成透明洞：上臂41個像素、手腕9個像素。這些像素從保留的原始06_parts恢復，逐點座標及來源hash已登記；不是用新握持圖或衣服顏色補洞。配方不再對機械手臂套用這個顏色刪除規則。八張full-canvas輸出均在寫入前核對hash。

重現（配方在 textures 前自動恢復登記來源；先驗證全部來源與輸出，再覆寫 source overrides）：

```powershell
& D:/ComfyUI/.venv/Scripts/python.exe art_src/characters/rin_hands/rebuild.py
& D:/ComfyUI/.venv/Scripts/python.exe tools/comfyui/build_character.py --recipe tools/comfyui/recipes/rin.json --from textures --to import
& D:/ComfyUI/.venv/Scripts/python.exe tools/comfyui/test_hand_attachments.py
```

實際 COMFYUI_DIR、Python 與 Godot 路徑依本機配置；上述為本次已查證環境。只重跑 textures/normals/import，不重跑立繪、姿勢提取、全部 SAM 或補全。source override 必須保持 full-canvas RGBA，握持附件不另生成第三個手節點。

空手、單／雙手持物、護盾、電話、近戰、死亡及切換，都需兩面向、完整時間軸與腕／袖口隔離檢查。握點距離回歸、來源檢查、逐格 alpha、全彩解剖與實際關卡／過場各自留證；任何小孔洞仍拒收，文件或單張預覽不能代替通過。
