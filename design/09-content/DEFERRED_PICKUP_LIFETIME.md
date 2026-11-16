# 延後生成的掉落物生命週期（NE-301）

2026-11-17，在 BG-32 的原版／候選退出對照中，發現既有未入樹 CreditPickup 的釋放問題。實際呼叫 Enemy._drop_credits，隨即在同一格釋放預定父節點，再等待 deferred queue：孤兒數由 0 增至 1，原檢查自然 exit 1。這與五套件 verbose 的 CreditPickup 類別一致；不同運行的掉落結果可使退出數量不同，不能把原始兩輪數字改寫成相同。

## 範圍與政策

- 核對 Enemy._drop_credits、Enemy._try_drop 與 Level._on_breakable_broken；沿既有 Pickup 基底或既有生成 helper 共用生命週期處理，不建立新的全域生成服務。
- 延後加入場景前，掉落物已有明確清理責任。預定父節點被移除、排入刪除或在加入前退出時，未入樹的掉落物必須被釋放。
- 生成成功後由正常父子關係管理；正常位置、數量、金額、血量、隨機機率、拾取判定及持久化效果不變。
- 物理查詢期間不能直接加入帶碰撞的 Area2D。保留 deferred 安全時點，不用同步 add_child 消除表面洩漏。
- 不只把 deferred 呼叫改綁在另一個可能同格被刪除的物件；也核對整個樹退出前尚未加入的情況。

## 必要證據

原版最小重現保留；三個實際生成入口分別驗證正常加入及同格父節點退出。正常路徑確認真實拾取效果；退出路徑用原物件 ID／弱引用確認釋放、無孤兒及無新增引擎診斷。實際 Level 破箱不得以直接 new 物件冒充。保留 source epoch、原始退出差異、完整日誌與故意移除清理的負控制。

這是獨立的既有物件生命週期缺陷，不是 BG-32 預載政策新增的 Area2D。背景貼圖、預載預算、陰影、場景佈置與劇情條件不屬本次修改。

## 實作與驗證（2026-11-17）

沿 Pickup 基底加入一個靜態 deferred 交付入口，排程本身不綁在可能先被釋放的父節點。交付參數只保留 parent／child 的 WeakRef；child 已釋放、已排刪除或已有其他 owner 時不再接管。原 parent 無效、離樹或已排刪除時，只釋放尚未入樹且沒有其他 owner 的 child；有效時仍在 deferred 時點正常 add_child，不改位置與內容。Enemy 兩個入口及 Level 破箱的信用點／物品入口共用同一處。

先用三種真正生產入口各做 owner 存活／同格釋放、正常等待／frame 0 立即整樹 quit 的獨立程序。修正 VFX/FSM 的最小 fixture 後，原版 quit 自然退出碼雖為 0，仍有 RID／ObjectDB／resources 診斷，嚴格原 log 判斷會拒絕；候選 12 例自然退出 0 且完整 EOF 乾淨。確認這個真正退出邊界可由靜態交付清理後，未再加入全域表、autoload、pool 或 tree-exit callback。

永久回歸跟既有 FxMeleePickupsSuite 併跑：檢查已 free／已換 owner 的 child、重複排入只 ready 一次、parent free／queued／離樹、真 physics body_entered 回呼後才加入，以及真正 Enemy／破箱入口產生的信用點、補給、武器、消耗品位置、數量與實際拾取一次。原測試只問圖示種類而未 free 的六個 Node 一併正確收尾，保留相同斷言；不以舊 fixture 殘留掩蓋新回歸。

故意只移除延後交付中 parent 失效分支的 child.free，87 項套件會有 14 項失敗並自然退出 1；恢復候選則 87 項通過，正常 EOF 沒有新增診斷。原版／候選與這個負控制來源、舊 VFX/FSM 失敗、型別推論編譯失敗及修正後結果全部保留。
