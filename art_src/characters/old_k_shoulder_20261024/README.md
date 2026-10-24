# Old K：抬手後的外套底層

原 torso 的灰色橢圓是烘在軀幹上的手臂殘影。上臂旋轉後它仍留在肩下；改根部權重的私有試驗仍重現，所以不採用該幾何改動。

本來源只恢復獨立手臂下面的棕色外套。`raw/torso-generated.png` 是影像工具的原始輸出，並非整張採用；`reference/` 保留原 832×1216 分件及 241×334 遊戲貼圖。提示詞見 `prompt.txt`；工具沒有暴露 seed／graph，不能聲稱可重新生成相同畫稿。

`shoulder-mask.png` 是原遊戲貼圖座標中的局部範圍，`provenance.json` 記錄輪廓、輸入 SHA、來源與定位。生成圖的 alpha 在目標區為250；只讀其 RGB，完整保留原來源 alpha。使用畫布比例及官方 part_transform 反向投影，不以生成圖輪廓重新定位。

## 重建

環境：Python、Pillow、NumPy、opencv-python-headless。實際核對為 OpenCV 4.11.0、NumPy 2.3.5。

```
python art_src/characters/old_k_shoulder_20261024/rebuild.py
```

從任何工作目錄可執行。配方 `tools/comfyui/recipes/old_k.json` 已登記此步驟；在 textures 之前產生 `art_src/characters/old_k/overrides/refined/torso.png`。原 07_refined 不改；輸入或既有 override 不符時拒絕覆蓋。

正式 diffuse 由原 `part_transform`／`render_part` 匯出。Normal 必須走 Godot `NormalMapMaker.make`，CPU 版本不相同，不可混用；本次只更新 torso 及 torso_n，其餘零件不重寫。完整建置的 normals 步驟仍使用原工具。

原 diffuse 與 Godot normal 基線逐像素一致；新 source 連跑兩次相同，官方切件逐像素等於正式 diffuse。外側 RGB、整張 alpha、尺寸、pivot、骨架、掛點、眼睛、臉與其餘部件保留。這個局部來源不代表全角色動作、接縫或人體驗收已完成。

[原生修前後、原始失敗與測試](../../../pm/Nest-Egg/attachments/NE-222-old-k-shoulder/README.md)。
