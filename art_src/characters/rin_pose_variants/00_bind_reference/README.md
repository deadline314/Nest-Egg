# 凜的實際骨架參考

2026-10-09，NE-222。這些是Godot4.7.2／RTX4070SUPER的原生SubViewport輸出，832×1216透明PNG，沒有擷取後放大。沿用原有s33派生素材；破圖與衣物問題仍是拒收項目，不能當修後動畫或操作驗收。

- `before`：861b09d0的舊工具，PNG仍畫出網格但JSON只收Sprite，記錄9件。
- `reference`：同姿勢同解析度，包含網格，完整服裝16件；保留原先單側模式。
- `sit`、`crouch`：現有NPC姿態，雙側完整服裝22件；子骨位置保持正式rest。坐姿不包含座面，須另外在實際舞台驗座面支撐。
- 每個目錄的`body`是目前護甲下層（凜包含受損衣物），`armor`是完整服裝。兩者都保留全部骨頭變換、mesh頂點／UV／三角形及sprite仿射資料。
- `manifest.json`記錄工具、角色、骨架與每張輸出的SHA-256。

重跑（生成未進行，使用既有共享鎖）：

```powershell
& '<Python>' tools/comfyui/gpu_lock.py -- '<Godot>' --path . res://tools/comfyui/rig_reference.tscn -- --skin=rin --pose=sit --zoom=16 --out=<絕對輸出目錄>
```

換成`--pose=crouch`可重跑蹲姿；省略pose取得一般單側參考。`python tools/comfyui/test_pose_reference.py`及RigMeshSuite驗證坐標與拒絕損壞資料；測試不是立繪或完整動畫通過。近遠側若共用同一來源貼圖，舊cut_parts會拒絕將兩個姿勢寫成一張貼圖，須先分離兩側製作獨立部件。
