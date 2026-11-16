# NE-255 明確選擇NPC姿勢與工作循環

2026-11-17，Godot 4.7.2、Windows、原生Vulkan Forward+、AMD Radeon RX 9070 XT；所有原生程序經既有共享GPU鎖序列執行。

## 支援範圍

沿用`tools/rig_joint_audit.tscn -- --npc-performance --npc-pose=...`，原五種明選值`stand`、`sit`、`sit_talk`、`sit_listen`、`wave`保持，新增`lean`、`crouch`及`loop:<已登記名稱>`。循環名稱由現有`NpcAnimator.loop_names()`提供，不另維護一份名單；例如`--npc-pose=loop:hammer`。省略`--npc-pose`仍只跑原五項，combat及transition預設與參數不變。

以真正`npc_pose`輸入指定靠／蹲，NPC蹲不啟用玩家戰鬥蹲的輸入。原180格預備與1/60秒步進保持，工作循環在預備完成後才給`npc_loop`。每個擷取格、每個隔離接點都核對真正動畫器的`_use_npc`、`_pose_now`、`_loop_name`，錯狀態立即拒絕；每格通過後才可產圖，最後metadata另保存實際姿勢／循環。

圖檔basename使用既有`String.validate_filename()`，Windows輸出為`loop_hammer_1.0_000.png`；metadata的原動作名稱仍是`loop:hammer`。

## 小樣本與負控制

本批只用既有`old_k`、`elbow_front`單接點、兩面向、1×、每項2格；不代表任何新角色通過，不代表完整工作週期、全接點、兩倍率、全彩外觀、正常光照或實際遊玩驗收。

| 案例 | 原工具 | 新工具 |
|---|---|---|
| 明選lean | exit1，CLI拒絕 | exit0，實際姿勢lean，兩面向 |
| 明選crouch | exit1，CLI拒絕 | exit0，實際姿勢crouch，兩面向 |
| 明選loop:hammer | exit1，CLI拒絕 | exit0，實際姿勢stand、循環hammer，兩面向 |
| 未登記loop | — | exit1，CLI拒絕，沒有frames.json |
| 只去掉循環輸入，保留同一檢查 | — | exit1；frame0要求stand/hammer，實際stand/，同檢查拒絕 |

原缺輸入負控制只有刪除`input.npc_loop = expected_npc_loop`一行，沒有換檢查、門檻或角色。原拒絕、修後正例、無效循環及缺輸入負控制的完整log／exit／命令列全部保留；預期的ERROR沒有改寫為無錯誤。

## 舊模式相同與原像素檢查

同一角色、接點、步數與倍率的原新A/A比較：default五動作10張、combat八動作16張、transition兩動作4張，共30張PNG的原始bytes完全一致。原metadata所有既有欄位也完全一致；NPC正例新增的兩項實際狀態欄位另列，不改舊欄位。

未修改的`check_joint_frames.py`自檢仍拒絕一像素洞與斷片；新三動作共12個單接點樣本0失敗，default另20樣本0失敗。這32個局部取樣不能外推角色整體合格。combat／transition本批證明同輸入原圖與metadata相同，不冒稱已重新通過整套角色驗收。

## 重跑與來源

`runs-before.json`、`runs-after.json`及`runs-regression.json`記錄全部14個原生命令與退出碼；`pixel-checks.json`記錄未修改像素檢查器結果。`audit-before.gd`、`audit-after.gd`及`audit-missing-loop.gd`保留原版、候選及唯一缺輸入變體。原版及變體場景仍用原工作路徑；重播時把這些檔案放回`work/ne255-npc-audit-20261117/`，從repo根目錄跑`run_cases.py before|after`、`run_regression.py`。

`receipt.json`保存全部原始檔案和依賴雜湊。`verify.py`獨立核對14個退出、實際姿勢、兩面向、時間軸、合法檔名、原五動作、30張PNG及既有metadata相同，以及缺輸入變體只有一行差異。像素檢查器、RigInput、NPC動畫器及角色資料沒有修改。
