# NE-228：通訊可見性與背景說明同步

通訊面板顯示／隱藏與來源離樹時，同步更新背景Hover守門，保留原實際可見性查詢與每格後備輪詢。延遲但尚未顯示不擋背景；關閉其中一個來源不能解除其他可見來源。[設計與參照](../../../../design/20-campaign-experience/RADIO_HOVER_VISIBILITY.md)、[完整收據](validation.json)、[原檔](raw.zip)、[逐項SHA](manifest.json)。

最終原CombatHud只新增9項，修前76／6、修後76／0；初版新增8項75／5→75／0也完整保留。既有原斷言、輸入、等待逐位元且順序相同；沒有延長原兩物理影格、清空原佇列或放寬判斷。原runner、selector、filters與known_failures不變。

原生最終v2修前13／5、修後13／0；兩程序0引擎ERROR、0退出洩漏診斷，八張原圖逐張檢視，包括各自真正引擎Tooltip視窗PNG。原生v1修後12／0的圖片只顯示逐字中途，另留原檔；v2只等原typewriter自然完成並新增完整文字見證，不改產品時長。新同步snapshot在任何等待／渲染前：原版radio_visible=true、guard=false，Tooltip仍是原instance；新版guard=true、Tooltip id0。關閉原版guard仍true，新版即false。

畫面讀回是在後續render：原版輪詢在下一次畫面更新也已收起Tooltip，因此前後radio圖都可正常分層。圖與同次呼叫快照不是同一時點，不聲稱拍到Tooltip壓字影格。同步狀態與真實視窗生命週期由原生負控制證明，不能拿後畫面正常說原同步已正確。

原選擇器、固定基準7a29f753：checks: 90853, new failures: 0, known failures (tests/known_failures.txt): 0  (wall time 1398 s)；程序含準備1398.94秒。全部分片原log在zip，沒有把刻意容錯ERROR當成原生無ERROR。

本票原選擇器實際是76組；首輪六程序90,856項有1項未改動的彈帶切換點超標（29.6畫面像素，原嚴格小於24），555秒。未修改7a與本次來源獨立同一彈帶套件各33／0；未重現不稱已修復彈帶根因。容器cpu.max=400000/100000，實際四核心配額；最後同來源改兩程序保留引擎背景工作空間，沒有改選擇器、原判準、輸入、等待或已知失敗清單。前後cpu.stat與實際分組保留。先前口頭把組數說成88已更正，全部正式收據按原76組。driver標記FULL指選出範圍全跑，不是全專案88組。

先前BG-50第一輪50組55,025／1是獨立爆炸效能超標；第二輪55,025／2是原通訊守門斷言。同一原十組加唯讀觀察8774／0，兩項在該次未重現，但明確看到同呼叫可見root／guard不同步。原兩項缺失敗當刻快照，故不逕稱唯一原根因。全部失敗、探針與先前7a完整CI96007／0／0、550秒的job log保留。BG-50暖檔修正與另一批HUD空間調整仍在各自分支，沒有混入此提交。

實際重看Hollow Knight暫停圖與Hades主選單圖，借用活動資訊層次；不從圖片推論Tooltip事件或偏好民調。原圖、既有來源URL／SHA都收於zip，來源對照仍可回到NE-229原附件。

軟體Forward+／HDR／Vulkan llvmpipe，Dummy音訊；真當舖Level與真引擎Tooltip，通訊台詞為明示顯示fixture，已隔離設定、指定可見滑鼠並重設演出。觀察節點ALWAYS、Level保留PAUSABLE。這不是正式故事producer、人工自然通關、實體手把／硬體GPU或完整角色關節驗收，整票原未勾條件保持。

原檔638項、6,489,409 bytes，zip SHA `54ead42cf3ab36c8195517a4016d13248265e6b9b75130352429b0d04b32ff40`，逐項解出核對完成。
