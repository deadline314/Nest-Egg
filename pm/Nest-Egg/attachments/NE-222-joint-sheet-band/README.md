# NE-222 接點放大圖範圍修正

放大圖只標原檢查範圍，固定輸入的代表圖跨程序一致。這是工具顯示修正；角色、原判定與1,688筆失敗均不變。

[固定四筆對照](../../images/NE-222-joint-sheet-band.png)：每列左舊右新，順序為正面肩凹口、背面袖口中心、背面肩凹口、背面肩封閉孔洞。來源均為同一批Godot4.7.2 Forward+軟體渲染原始128px格子，裁切後11倍最近鄰放大。不是完整遊戲原生視窗或素材修復圖。

`raw.zip` 的逐檔大小與SHA256在 `manifest.json`；`validation.json`記錄範圍與限制。解壓至獨立資料夾後：

```sh
python3 source/test_joint_audit_both.py
python3 review/reproduce.py
```

需要numpy、Pillow、scipy。第一條是五項回歸；第二條重新產生固定對照。比較舊工具時，將source複製到臨時資料夾，以 `joint_audit_both_before.py` 替換該臨時資料夾的 `joint_audit_both.py` 再執行測試；原版五項失敗，修正版五項通過。不要覆蓋工作中的工具。

配對四步擷取完整原圖／metadata／report保留在captures：兩邊各512筆，pair39、worn5筆失敗。這四步是連續60Hz步驟，不是整個週期四等分。before120保留完整30,720筆報告與metadata；其1,920張PNG仍在本機ignored原始資料，不重複收入此工具證據包。所有失敗仍在，沒有放寬判定或用交集取代原始失敗。

investigation保留前置診斷及失敗：初版隔離探針的typed-array SCRIPT ERROR不算產品失敗或通過。V2修正私人探針後可擷取；平移版stagger的alpha120與原119不逐像素相等，未宣稱全數相等。完整身體背景圖為未受光診斷且隱藏武器／特效，不是自然遊玩。初次editor import未持有共用GPU鎖，其後原生擷取使用共用鎖；未與本Session無頭遊戲測試重疊。

原68個凍結素材／骨架／檢查器來源雜湊核對一致。此次只逐張看before、after分類表及固定對照；不代表全部原始幀、實體GPU、完整動作或NE-222已驗收。實作決策見[設計](../../../../design/12-cast-redraw/JOINT_REVIEW_BAND.md)。
