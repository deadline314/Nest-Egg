# NE-95 2026-10-09 同機配對重測

## 目的與可比性

前輪 EPYC 9V74 的中檔榴彈單次修後 +13.3% 保留，不能挑較快中間樣本替代。此輪主機已變為 **AMD EPYC 7763**，可見 5 CPU、cgroup 配額 4 核，故在新主機重新建立 A／B 基線，**不直接互比前後兩輪 ms**。沒有實體 GPU。Godot 4.7 stable、Vulkan 1.4.305、Forward+ llvmpipe LLVM 19.1.7。

共同基線 `19df828b`：角色、共享動畫、美術、地圖、光影、圖集、工具與其他 Session 的成果均保持一致。B 是目前 main 的特效。A 在本人獨立 detached worktree 只將 Fx、Explosion、ShockRing 三個正式檔案取回 ea59d91b 版本，差異全文保存於 [before-production.patch](before-production.patch)，三個檔案雙邊 SHA-256 在 [measurements.json](measurements.json)。這是目前主程式下隔離舊特效行為，**不是整個舊 ea59d91b 主程式的效能**。

## 條件與順序

320×180、第一章歷史市集 level_01／115 欄、10 grunt、medium、launcher、seed95、time_scale=1、每次 14 秒，vsync／FPS 上限關閉。工具與暖機、首發尖峰處理完全相同：settle25、標題卡 3.8 秒、敵人 0.8 秒、vsync 關閉後 10 frames，使用未縮放牆鐘。保留 outliers；沒有聲稱所有 shader 已熱身。

順序：A1 B1 B2 A2 A3 B3 B4 A4。八次共用 GPU 鎖串行；所有匯入在量測前完成，實際截圖與局部測試在八次結束後才執行。無 ComfyUI、其他截圖、匯入或大量測試。每次 `--no-capture`，輸出目錄驗證沒有 PNG。量測日誌完整保留，不只列最快結果。

| 輪次 | 版本 | mean ms | median ms | p95 ms | p99 ms | max ms | frames |
|---|---|---:|---:|---:|---:|---:|---:|
| 1 | A 修前 | 52.63 | 51.21 | 60.71 | 69.94 | 177.84 | 266 |
| 1 | B 修後 | 50.95 | 50.23 | 60.71 | 65.21 | 76.93 | 275 |
| 2 | A 修前 | 51.78 | 50.91 | 61.10 | 69.27 | 70.35 | 271 |
| 2 | B 修後 | 48.85 | 48.93 | 56.16 | 62.00 | 109.91 | 287 |
| 3 | A 修前 | 52.81 | 50.81 | 63.49 | 113.49 | 131.36 | 266 |
| 3 | B 修後 | 48.99 | 48.66 | 59.53 | 65.23 | 67.14 | 286 |
| 4 | A 修前 | 50.67 | 49.66 | 61.12 | 69.60 | 80.47 | 277 |
| 4 | B 修後 | 50.72 | 50.38 | 58.85 | 66.49 | 67.67 | 277 |

| 配對 | 修後／修前 mean |
|---|---:|
| 1 | 96.808% |
| 2 | 94.341% |
| 3 | 92.767% |
| 4 | 100.099% |

四次 mean 的平均：A **51.9725 ms**、B **49.8775 ms**；B／A **95.969%**。三組較快，一組約 +0.1%。本輪相同條件下未重現 +13.3%，沒有宣稱統計顯著、所有配置、前輪硬體或實體 GPU 無退化。低檔步槍及其他配置仍不由此表代替驗收；BG-17 五敵／環境替換前 105% 是另一基準，也不能混用。

八次命令均退出 0、無 SCRIPT ERROR，**其中四次仍有 resources-at-exit ERROR**。這些是量測後的退出清理訊息，不刪除、不當作「工具全過」；數據收集完成不等於完整驗收通過。本票原生完整遊戲／全光影／實體 GPU 與清理問題仍保留限制。

## 原生画面與局部驗證

性能八次結束後才拍同一原生場地的真實 Breakable 油桶：`hit_by_projectile` →既有延遲→雙陣營爆炸。A／B 各在 0.15／0.22／0.40／0.75 遊戲秒取圖，medium／market、慢播 0.25 僅供看圖；**不拿慢播當性能**。兩邊沿 main 的 ViewportCapture 輸出 sRGB，不改光影、HDR、角色、配方、图集或克制係數。動態粒子相位可不同，不作逐像素等同宣稱。

圖片可見舊圓盤／白弧疊層與目前的火球／單一完整環；高亮核心仍需要使用者檢查下一發、敵人與危險物是否受遮。獨立環形對照也以目前工具保存，CLI 可指定新輸出，不覆寫舊票圖片；保存錯誤會回傳失敗。兩個油桶與獨立環形工具退出 0，沒有 SCRIPT ERROR／ERROR。

固定基準 `19df828b` 的 changed 腳本沒有挑出遊戲套件（改的是獨立審查工具、圖與文件），不是跳過程式變更的零 diff；原生工具已實際執行。另按票與相依整合，指定 EnemyVfxSuite／FxUpgradesSuite：**341 checks，0 new／0 known failures**，包含雙陣營傷害與單次回饋；完整測試交 CI。CI API Forbidden，本輪沒有遠端 CI 通過聲明。

![目前版原生油桶修前／修後](../../images/NE-95-followup/NE-95-barrel-before-after.png)
![左 Placeholder、右共用 ImageTexture](../../images/NE-95-followup/ring-surface.png)

## 重現與保留

從上述共同基線建立本人 isolated A／B；只向 A 套用 before-production.patch，其餘正式程式／內容相同。兩邊分別經 GPU 鎖完成匯入後才跑 [paired-runs.sh](paired-runs.sh)；修改其中 checkout、GODOT 及輸出絕對路徑以符合實際環境，保持全部測量條件。Windows 使用同一 gpu_lock，但略去 xvfb-run。source SHA、全部八份 log、退出碼與無截圖條件可核對。

油桶：`screenshot.tscn -- --scenario=player_fx --barrel-only --quality=medium --lighting=market --slow=0.25 --out=<獨立絕對資料夾>`。環：`shock_ring_review.tscn -- --out=<絕對 PNG 路徑>`；外層使用同一 Forward+、640×360、GPU 鎖。

人工完整兩章／各敵人／燃料槽、25 profile 審查、硬體性能仍未驗收。本輪沒有新生成 Atlas、調整全局 LightKit 或角色曝亮／霓虹。Session 1 的角色驗收與 Session 3 地圖／流程成果保留。
