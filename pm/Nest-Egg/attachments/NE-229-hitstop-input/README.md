# NE-229：受擊停格期間的載具互動

修正只讓實際被Fx局部停住的玩家／載具接收同一個互動鍵邊緣；保留停格截止時間、空車、距離、owner、離開保護、長按與暫停規則。[設計與研究](../../../../design/20-campaign-experience/VEHICLE_HITSTOP_INPUT.md)、[完整收據](validation.json)、[原檔](raw.zip)、[逐檔SHA](manifest.json)。

| 同一情境 | 修前 | 修後 |
|---|---|---|
| 原遊戲流程＋明示60ms局部停格，三輪 | 48項／9失敗 | 48項／0失敗 |
| 輸入套件（只新增9項） | 118項／2失敗 | 118項／0失敗 |
| Forward+原舊關卡＋正式環境，一輪 | 20項／1失敗 | 20項／0失敗 |

最終原生v2前後兩輪都是0引擎ERROR、0退出洩漏診斷，六張PNG逐張檢視。第一個斷言的快照顯示修後實際driver與mounted身份成立，玩家仍process_mode=DISABLED；沒有提早解凍。畫面讀回可能晚於斷言若干物理影格，GAMEPLAY_DIAG與CAPTURE_STATE分別保留，完成原斷言後才暫停世界等讀回。兩輪使用原level_01，不換成另一張正式章節來避退出錯誤；這不代表其他舊工具的退出250已修好。

原選擇器、固定基準5bcc9f68：checks: 96006, new failures: 0, known failures (tests/known_failures.txt): 0  (wall time 598 s)；實際609.05秒。原Smoke與InputFeel既有斷言／輸入／等待逐位元重建相同；runner、selector、filters與known_failures保持。所有shard原log收於zip。

原CI39781993137有96,000項／3新失敗（搭乘、離開、落坑），634秒。原artifact與job全log保留；artifact SHA 827256e782e1f0de023feca1748186edffeff00c0b0af17ee725833baa1ffa9b。原版未介入流程20輪320／0，原CI沒有失敗當刻owner／停格快照，因此本次60ms控制證明一個真缺口，不逕稱原CI唯一根因。原Smoke只新增失敗時診斷，未放寬等待或判準。推送後仍需核對新完整CI。

較早輸入fixture v1為118／4，其中2項是離開失敗造成後續獨立案例的連鎖；修正fixture僅在已記失敗後建立下一案例前提，最終負控制118／2與正式118／0全部保留。原生v1與最終v2皆留原檔。

Vulkan／llvmpipe為軟體Forward+，Dummy音訊；輸入合成、60ms介入明示，不代稱實體手把、硬體GPU、人工整章或整票完成。研究原圖屬各作品，HUNTDOWN載具圖只作構圖參照，不當作該作輸入時間證據；五團隊十圖及官方URL／SHA收於zip。人物關節與完整渲染輪廓不屬本次驗收。

原檔共235項、10,184,682 bytes；zip SHA `0d9254f447a124e0368cd82aa9b257d08db48f5b674adf3f39421571de598a12`，已逐項解出核對SHA。
