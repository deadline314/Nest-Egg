# NE-67 CC0 草叢新增與重現

來源：Kenney 官方 [Starter-Kit-FPS](https://github.com/KenneyNL/Starter-Kit-FPS/tree/185fd2326d74a5cf858cffc616f87cf9696f9cc0)，固定版本的 README 明確將 2D／3D／音效美術列為 CC0；軟體 MIT 與本模型授權分開。完整檔案 SHA-256 與 README 證據雜湊留在 manifest／LICENSES。

依 `.agents/skills/free-asset-pipeline/SKILL.md` 的「可重現的新 CC0 素材示例」從零下載 grass-small.glb 及 Textures/colormap.png，既有 build_props 以正交鏡頭渲染顏色／鏡頭空間法線，再依單素材資料調暗、降彩度、偏冷，不改 grade_master。模型沒有自發光，不偽造發光層。

實際輸出 182×144 RGBA 顏色與法線，世界尺寸 22.7×18，搖動幅度 0.6。BG-17 政策匯入半解析度並保留至少 4 pixels/world-pixel；完整 PNG 留作重加工來源。尺寸／實際 payload 以 in-game.log 的 Godot imported image 欄位為準，不由 PNG 大小推定 GPU 記憶體。

## 本 Session 的實際驗證

1. 官方來源下載成功，授權證據及两个檔案雜湊核對。
2. 重新下載（移出本票自己的 raw 快取）、重渲染／加工；兩張 PNG 與 .tres 的 SHA-256 均一致，見 repeat-check.log。
3. 新素材由 PropLibrary 載入、PropData.validate 通過，真實第一章市集建立三個 PropNode，法線／搖動走現有系統。截图新增前／低／中／高檔；沒有把預覽位置寫入正式 map。
4. 素材檢查、來源拒絕測試、受影響遊戲測試結果見本票。

## Session 3 正式擺位介面

`PropLibrary.find(&"kenney_sedge")`；`PropNode.setup(data, top_left, flip)`；以 `PropData.size` 底邊貼地。可在區段的 props 描述使用 id=kenney_sedge，保持既有碰撞、角色與家具。此 Session 已交付遊戲內預覽與庫資料，正式放哪裡由 Session 3 決定，未修改地圖或重建第一章。

## 仍待使用者審查

- NE-66 全局風格與暗場／效能條件尚未全部通過；這件草叢沒有證明整體替換已通過。
- 開新對話，只貼：「幫我換一個新的路燈素材」。確認主動讀取 free-asset-pipeline Skill、優先選有明確授權的 CC0、走下載→加工→匯入→遊戲截圖→受影響測試並留下來源。ComfyUI 若確需使用交指定生成 Session，不能另外開生成端。
- 新對話條件：最新 main、Godot 4.7、可用渲染器、共享 GPU 鎖；遵守主機分工與本次票狀態要求。驗收時留下該對話與 commit、素材授權／圖像／測試，確認保留既有位置。
- 本 Session 沒有開新對話環境；草叢流程與同 Session 重跑不能當作路燈／新對話驗證。該項保留給使用者，未打勾。
