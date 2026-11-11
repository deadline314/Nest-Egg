# BG-31 原生交付的獨立複核

2026-11-12。四條原需求逐項複核；本輪沒有啟動新引擎、渲染或效能量測。實際讀回原Arc B580／Forward+新局與獨立程序冷讀：原始log逐條126／0、117／0，與各自完整event摘要相同，原driver行、自然exit0、零錯誤與洩漏保留。新局完成開場與老K第一段，冷讀不重播開場並接老K第二段，三輪返回／續玩與四次menu-settled資源樣本一致。

直接由原events重算：四次回選單nodes163、orphan0；每個程序各自的texture/video統計固定、prefetch不超過64份／1inflight。由原CSV獨立重算程序峰值，與原wrapper逐值相同；不是新的9070XT效能或driver VRAM上限結論。runs.json其餘歷史14程序摘要保留，沒有將它們全部冒稱本輪有重跑或完整raw逐條讀回。

原兩份Windows log被Git以LF保存。本輪不改寫原件：另存明示的CRLF重建副本，兩份都精確吻合原wrapper記錄的完整SHA。原wrapper的pid與log內Godot pid保持不同欄位，沒有假稱相等或臆測映射。實際log事件與summary的Godot身份相同，冷讀另記前一程序身份。

三張原圖已重新逐張檢視，原PNG的SHA皆吻合實際record中的image收據，人物／對話頭像／場景／介面完整。圖中的舊角色外觀、普通提示與名牌不視為本輪美術認可；沒有以歷史Arc圖冒稱新9070XT畫面。原4 resources退出失敗保留。

重要通訊保存拒絕／重試／取消的原生流程已另由NE246後續交付；其早期錯誤Main觀察政策不作世界凍結證據，世界凍結以後來正確政策的原生世界帳為準。BG31的圖形資源切換及有界回收驗收與NE246的閱讀／原子保存分開審查。

`python verify.py` 唯讀核對完整ZIP／member bytes／SHA／CRC，從原log／events／CSV重算上述結果，不依賴已演進的工作樹。包內目前已發布程式只是來源演進參照，沒有冒稱原Arc執行的精確全來源或本輪新回歸。
