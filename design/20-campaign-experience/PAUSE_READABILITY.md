# NE-228：暫停與圖鑑隔開背景文字

2026-10-22。先讀使用者指南、UI風格及現有共用背景。NE-223的正式場景拍攝發現：暫停選單只壓暗，HUD目標文字與箭頭仍能穿進「目前進度」及操作表背後。文字放大時尤其會形成兩層可辨的字。使用者先前已要求任務／資訊頁保留場景輪廓，但不要透出HUD文字。

沿用現有SceneBackdrop共用背景：模糊、低飽和與壓暗，再疊原暫停選單的前景。沒有新增離線圖片或CPU畫面擷取；不改世界光照、動作、存檔、暫停與重要通訊鎖。以同一正式場景、相同狀態及相同解析度做前後比較，驗原選單聚焦、取消、設定／圖鑑／任務子頁返回、重要通訊凍結及減動態。單純換背景不加鏡像實作的單元測試，既有回歸與實際原生輸入／畫面是主要驗證。

## 本輪實際重看五款來源圖

[原圖、頁面來源及SHA](../../pm/Nest-Egg/attachments/NE-229-recovery-references/sources.json)沿用已有資產，這次逐張重看。沒有將圖中觀察稱為玩家民調或對方的內部實作。

| 圖片 | 本次採用的觀察 |
|---|---|
| [Hollow Knight暫停](../../pm/Nest-Egg/attachments/NE-229-recovery-references/hollow-knight-game-menu.jpg) | 場景仍可辨識，主要操作字清楚且不與場景資訊競爭。 |
| [Blasphemous選項](../../pm/Nest-Egg/attachments/NE-229-recovery-references/blasphemous-options.jpg) | 選項區的背景單純；保留前景選中及確認／返回資訊。 |
| [Celeste暫停](../../pm/Nest-Egg/attachments/NE-229-recovery-references/celeste-paused.jpg) | 場景壓暗，操作列是唯一應讀的文字層；不改本作原按鈕動作。 |
| [Hades主選單](../../pm/Nest-Egg/attachments/NE-229-recovery-references/hades-main-menu.jpg) | 這是主選單而非暫停；僅參考主體圖像與操作文字的分層。 |
| [Cyberpunk 2077暫停](../../pm/Nest-Egg/attachments/NE-229-recovery-references/cyberpunk-2077-pause.jpg) | 背景明顯失焦，前景內容仍銳利；沿用本作既有背景元件，不抄對方構圖。 |

[Godot官方Screen-reading shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html)：2D首次screen texture會複製背景，後續讀相同backbuffer。任務子頁疊在暫停上時必須檢查實際合成，不假設新增模糊一定正確；不新增第二套shader或隨意插BackBufferCopy改變既有層級。

修前正式探針20／0代表原操作可走完，不代表可讀性通過。逐頁看圖時，圖鑑也有相同HUD文字透入，原本0.97透明度在HDR線性混色後仍可辨；因此同票把圖鑑也接回共用背景。設定是既有不透明底，實際看圖沒有此問題，保持原樣。暫停與圖鑑保留原背景的點擊阻擋，另以實際空白區滑鼠點擊驗不開槍／不解凍。

## 最終證據

固定54b05d17，原選擇器18組6911檢查0新／已知失敗，215秒。四組正式場景／尺寸原生矩陣84／0，主選單入口5／0，五程序均0引擎ERROR；全部來源、較早版本、畫面控制、日誌與38張最終圖見[驗證附件](../../pm/Nest-Egg/attachments/NE-228-modal-background/README.md)。軟體Vulkan與合成輸入不代稱硬體GPU效能或人工實體裝置驗收；原18組包含重要通訊鎖的檢查，沒有新增真戰鬥通訊拍攝。
