# 三名重裝敵人的完整接點基線

這是一份**失敗證據交付**。基線 `fcd9ea756a07fcb72c4486ecb4065ccad6c441f7` 的正式素材未被私有候選替換。NE-79／80／81／90 的整體美術驗收不能據此打勾。

Godot 4.7.2、RTX 4070 SUPER、Forward+／Vulkan 1.4.351，ComfyUI 已停止，原生擷取持有主 checkout 共用 GPU 鎖。每名角色隔離十四個相鄰部件接點，遮去其他肢體、武器、盾與發光，涵蓋八動作、兩面向、1×／3.4×、每組 120 格。1,920 張原生 3584×384 RGBA 圖產生 161,280 接點樣本，**19,803 失敗**。

| 角色 | 失敗樣本 | 已定位的部位 |
|---|---:|---|
| 鎮暴員 | 8,711 | 兩腕、兩肘、兩膝、頸 |
| 重裝機槍手 | 9,694 | 兩腕、兩肘、兩膝、兩肩、頸 |
| 監管者 | 1,398 | 前腕、兩肘、前膝、頸 |

鎮暴員與重裝機槍手的兩腕合計 15,360 失敗，橫跨全部取樣狀態。鎮暴員手套來源還混入旁邊大腿；兩人的前臂分件漏掉原圖已有的袖口。肩、頸、肘、膝中也有一像素孔洞或孤立邊緣像素，均按原門檻拒收。中心 alpha 正常不能代替整段無孔洞；原有腰髖三接點通過不能推定十四接點通過。

## 證據與限制

- `asset-audit.json` 保存原圖、P／U 補全、SAM 遮罩、分件、正式 PNG、規格及骨架來源 SHA。透明度盤點不證明解剖與部件歸屬正確。
- `frames.json` 保存全部取樣時間、矩形、角色、面向、接點與尺度；`report.json.gz` 保留 19,803 個完整失敗記錄；`manifest.json` 保存全部 1,920 張原生 PNG 雜湊及部位統計。
- 六張代表性原生 PNG 原樣保存在 `../../images/NE-90-all-joint-audit/`；其餘約 638 MiB 的逐格原圖保留在 Session worktree 的 `.godot/ne79-81-delivery-revalidation/native-joints/`。需要全部 PNG 時依下面命令重現，不能把只發布六張說成全部逐格圖片均已發布。
- `cpu-suites.log` 是固定基線已註冊十一套件的 **4,226 checks／0 failures**；其中四項 ERROR 是已知的負向 fixture，另有 221 ObjectDB leak warnings，沒有 SCRIPT ERROR。未註冊的 EnemyArtDeliverySuite 不算執行。`source-checks.log` 的三角色規格與部件／法線檢查通過。
- 自動量測不涵蓋開口輪廓缺口、完整全彩人體、光照、護甲脫落、真正關卡戰鬥與手感；這些需另驗。私有候選結果與上述基線分開，不掩蓋失敗。
- 最新 main 的 CI 未開始執行：GitHub check annotation 記錄帳務付款／spending limit 限制；不是測試通過，也不是新增測試失敗。

## 重現

在獨立 checkout 取上述固定基線；使用同一引擎、同一 GPU、ComfyUI 停止及共用鎖。`out` 必須是新目錄，不能覆蓋原始證據：

```powershell
D:/ComfyUI/.venv/Scripts/python.exe tools/comfyui/gpu_lock.py -- C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe --path . res://tools/rig_joint_audit.tscn -- --out=<絕對新目錄> --chars=enforcer,heavy_gunner,warden --frames=120
D:/ComfyUI/.venv/Scripts/python.exe tools/check_joint_frames.py <絕對新目錄>
```

後一命令應退出 1 並列出失敗，不能當成測試成功。核對本交付封包：

```powershell
D:/ComfyUI/.venv/Scripts/python.exe pm/Nest-Egg/attachments/NE-90-all-joint-audit/verify.py
```

封包核對通過只代表六張圖共 504 個接點與完整失敗帳本一致；最後仍明示 **art audit FAIL 19803/161280**。核對器同時保留正常、單像素孔洞與分離部件的負控制，不放寬任何面積門檻。
