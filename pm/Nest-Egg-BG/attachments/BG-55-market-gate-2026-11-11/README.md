# 市集入口敵人補光：原生控制與回歸

本包是腳本安排的原生光影實驗與原敵人 AI 觀察，不是真人通關或實體手把測試。Radeon RX 9070 XT、Godot 4.7.2、Vulkan Forward+、HDR 2D，1280×720 視窗、640×360 邏輯畫面、密度 2、相機倍率 1.92、亮度 0.5。使用共用 GPU lock 串行；不將擷取間隔當效能數字。

## 採用的產品修正

市集入口另用 `market_gate.tres`，相對原 `market.tres` 只有 id 與 `enemy_fill_scale: 0.6 → 1.0` 不同。原環境光、霧密度 1、補光下限、燈具、輪廓光、HDR 上限、陰影與敵人玩法資料全部保留。原先敵人補光是主角補光乘 0.6；局部資料讓它使用相同補光比例，沒有修改共用外觀或提高全域環境光。

關卡與產生器同步指向新 profile。環境音、音樂與場景預覽補新 id 的原 market 別名，避免換區段 id 遺失聲音或預覽。CPU 實際呼叫聲音 owner，並移除別名作負控制，確認保留全部層、音量與 cue。

## 正式全區對照

使用 Main 同一 `LightKit.create_environment()`，確認實際 viewport 的 WorldEnvironment 與 bloom 啟用。整個 Level 凍結並將 shader TIME 停住；相機、主角位置與槍燈移動後，仍同步實際材質、LightBudget、WallShadows 及霧的取光快取。牆影使用原 owner 的 rescan、選燈和低解析 silhouette 更新，低品質維持原本關閉牆影的規則；沒有隱藏霧、雨、背牆或陰影。相機、caster 與取樣矩陣另存數值 array，避免字串顯示精度成為取整誤差。

正式工具在 hold 前讓 PhysicsBody2D 保持原 physics space，避免 Node.DISABLED 預設 REMOVE 把地面形狀也移除；Area 仍停用，搬測試角色不觸發故事區域。主角先擺在支撐面上方 2px，再用真 CharacterBody 碰撞求解向下接觸、保留原 safe margin，不偽造 on_floor。每張圖保留真支撐 ray、floor/feet/gap、solver normal 與 body-space 狀態。接觸陰影另更新真 ray 與 nearest-light cache、呼叫原 owner 零時間更新，避免停住的快取保留舊影位移。

每格同一 live instance 依序拍 A0、A1、B、恢復 A、B2。A/A、恢復 A 與 B/B2 的整張浮點原圖 SHA 必須完全相同，角色部件姿勢、雨點、時鐘與 owner 狀態也必須相同。不是跨程序自然時間畫面的改善比值。LightBudget 的 local `light.visible` 選中數與 `is_visible_in_tree()` 分別保存；父節點隱藏的燈仍可能占預算，不將兩種可見性混為一談。

| 正式案例 | 總格／可站格 | 主角最小 | 地面最小 | 原 profile 敵人最小 | 局部 profile 敵人最小 |
| --- | ---: | ---: | ---: | ---: | ---: |
| `accept-high-grounded-v2` | 21／14 | 3.468495 | 3.426117 | 0.208321 | 0.759697 |
| `accept-low-grounded-v2` | 21／14 | 3.060109 | 3.433574 | 0.269702 | 0.787024 |

門檻仍是敵人 0.45／主角 0.6／地面 1。上表最小值各自取全區，不假稱它們都來自同一敵人同一格。每品質獨立重算 21 格、27 張不同浮點原圖、40 次敵人量測，控制失敗 0。正式靜止敵人連同武器附近的外包框皆無任一 RGB 通道全高於 0.92 的白像素；因整個包含框為零，可證可見敵身白像素也為零，沒有以背景面積稀釋比例。

7 盞實際燈具的 authored 狀態均為 stable，沒有把 caption 的 `lamps=full` 宣稱為真正發生的閃爍亮相。正式 `*-grounded-v2-independent.json` 也從同份 float bytes 重算每品質 14 可站格的主角完整身高框與地面兩框，與原生逐值相符（容差 0.000002）。

原 profile 最暗的同格精選是押運手腳底 (968,320)、c3:r1：高品質 0.208321→0.984478，低品質 0.269702→1.027129，見 [selected-original-failures-grounded.json](selected-original-failures-grounded.json)。修後全區最差則為高品質押運手 (712,320)／c2:r2 的 0.759697，低品質投帳手 (1128,320)／c3:r2 的 0.787024，見 [selected-images-grounded.json](selected-images-grounded.json)。每份都連到完整原生圖、未縮放原像素近拍及原始來源。`BG-55-grounded-*-grid-review.jpg` 是縮圖導覽，不是原像素證據。已檢視原生近拍、完整圖與全區導覽；衣物紋理仍在，雨霧與牆面層次保留。

三名押運手 `ch2_escort`／`collector_brute` 的原腳底是 (584,320)、(712,320)、(968,320)；一名投帳手是 (1128,320)。沒有把索引順序猜成敵人種類；每個實際節點記 id、skin、腳底、朝向、補光、上限、量測框及原始像素。

## 原 AI 動作與攻擊

`actions-high-v3`、`actions-low-v3` 使用實際關卡和原敵人 AI。只安排主角在目標左方 72 世界像素、耐久 999，保留原受傷無敵時間；其他敵人停住、雷光停用。沒有改敵人 FSM、HP、攻擊參數或強迫狀態。每種敵人觀察 8 秒實際經過時間，不冒稱 8 秒完整逐物理格錄製。原生輸出各 2 actors／0 failures／0 engine ERROR。

高／低品質押運手採樣 387／385 次，包含巡邏、靠近、蓄力、突進、恢復，專用 rig action 的 phase 確實前進；敵 HP 保持 6，主角最低 997。投帳手採樣 384／399 次，包含巡邏、瞄準、蓄力、恢復，每品質實際產生 5 個敵方投射物；敵 HP 保持 5，主角最低 996。投帳手原 code 的預兆與紙張是 FSM overlay，沒有專用 `RigInput.action`，不將空 action 軌宣稱為專用骨架投擲動畫。

44 張 action 原圖已獨立解碼並逐像素核對 PNG。caption 的 state 是 frame_post_draw 當下的真狀態，另留 trigger_state。live Player 在視覺姿勢更新之前更新槍燈，render-time origin 差最高 0.14742 世界像素，沒有補寫姿勢或光源來美化此觀察；這與凍結工具要求同步後零誤差的契約不同。

動作圖包含原蓄力紅光、白色驚嘆號、棍頭及紙彈等 HDR 亮效。外包框最大白像素 233、HDR peak 8.5，這是包含效果和背景的計數，不能冒稱敵身過曝比例；真正白像素圖已檢視，亮點來自原預兆與棍頭，衣物細節仍在。靜止身體曝光零上界與動態亮效分開記錄。

## 已知答案與獨立負控制

`cpu-support-isolated-v3` 為 88 checks／0 failures、0 engine ERROR。凍結後移相機 1900 像素，故意省略同步時 LightBudget 仍選舊畫面、silhouette 仍用舊矩陣；同步後改選正確光源與相機，低品質仍無牆影 viewport。另有真 body-space 移除負控、已知 y180 地板接觸與真陰影 cache 負控，以及 rig 補光／材質、槍燈 top_level 原點、平台下可見地板、單因素 profile 與聲音別名。

獨立 Python verifier 從原 float bytes 重建取樣框和像素外圈，重算亮部／暗部對比及 PNG 的浮點線性→sRGB，不呼叫 Godot 被測量測函式。正式檢查使用 `--require-owners --require-contact`。先驗原始 baseline 通過，再於記憶體破壞對比、幾何、控制結論、caster 相機、support gap、physics space、接觸陰影與 raw byte，八項全被拒絕；原始檔未改。現行收據為 [verifier-negative-controls-grounded-v2.json](verifier-negative-controls-grounded-v2.json)，舊版本亦保留。

## 保留的無效／診斷輪次

- `diag-high-v1` 有 3 條 probe 的 typed-array SCRIPT ERROR，雖 engine exit0 仍拒絕；`cpu-parse-red` 是型別推論錯誤後的 bounded timeout124；`cpu-profile-v1` 為錯誤音樂負控的 68／1。原始錯誤、來源與 log 留在各自 raw.zip。
- `diag-high-v2/v3`、`diag-low-v3` 是早期單因素定位，尚未建立 Main WorldEnvironment。只用來找方向，不作最終 bloom 驗收。
- `accept-high-v1`／`accept-low-v1` 雖有 Main WorldEnvironment，但持有場景時尚未同步相機相關 Budget／WallShadows，只作診斷；不能因 A/A 相同就假稱持有的是正確 owner 畫面。
- `accept-high-v2/v3`、`accept-low-v4` 與未帶 grounded 的 related-v1 雖補了 camera owner，仍沿用 floor-minus-two 的浮空主角，且 DISABLED 預設會移除 physics bodies；不作真正接地／接觸陰影的最終驗收。原影像、早期最小值與 derived receipts 保留，不能據其第一章 edge 紅直接判產品缺陷。
- `accept-high-grounded-v1` 已保留 body-space 並真碰撞接地，但尚未強制重算 ContactShadow 的 nearest-light cache；同樣只作工具診斷。最終全 8 輪均用 grounded-v2／88-check 版本。
- `cpu-support-v1` 在預設 REMOVE 的 disabled 父節點下嘗試碰撞，得到真 body-space null 與 SCRIPT ERROR；只終止這個已失敗的自有程序，原 log、來源與退出碼保留。後續先保留真 body-space，再作實際求解，88 項全通。
- `accept-low-v3` 在第 16 格附近正常 exit0 卻沒有完成索引，原因未確定，明記 incomplete，沒有算過關。後續 runner 同時要求完成 artifact；原始收據不重寫。
- action-v1 為原 AI 觀察，但圖片可能在 trigger 與實際 render 間轉狀態；正式圖片用 v3 的 post-draw 標記。
- 早期 `accept-low-v1` 執行時僅離線 verifier 檔案有更新，沒有 runtime／產品變更。ZIP 同存該 checker 前後位元組與聲明；不宣稱所有檔案 SHA 相同。

所有 raw.zip 均含逐檔 byte 長度與 SHA manifest、原始 logs/JSON/浮點 bytes/PNG、實際被測工具與 runtime source 副本。每個 ZIP 每一個成員已讀回驗 hash；案例來源前後逐 byte 固定（上述明示的離線 checker 例外僅限該檔）。[archives.json](archives.json) 保留每包 SHA、完結 artifact、退出碼及錯誤，不把 exit0 等同驗收通過。ZIP 以 scoped `.gitattributes -text` 保存原位元組；工作中的展開資料夾不入 Git，避免類別重複。

## 相關區域的無退步控制與原有不足

相關區域沒有引用新市集入口 profile。各格比較原 profile 與現況 authored profile，A/A、A/B、恢復 A、B2 的整張 float bytes 全部相同；逐像素無變更，不用容差把下降當 noise。所有 owner 檢查與獨立重算通過。這是本票沒有改壞其他區域的證據，並不表示原有每一項門檻已滿足。

| 區域／品質 | 拍攝格／可站格 | 主角最小 | 地面最小 | 敵人最小 | 原生退出 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 公眾攤道／高 | 24／16 | 3.442629 | 2.985167 | 無敵人 | 0 |
| 公眾攤道／低 | 24／16 | 2.936626 | 2.986692 | 無敵人 | 0 |
| 復原館外／高 | 9／6 | 2.213226 | 3.413035 | 無敵人 | 0 |
| 復原館外／低 | 9／6 | 2.295753 | 3.446826 | 無敵人 | 0 |
| 第一章共用外觀區／高 | 4／4 | 1.578602 | 0.503747 | 0.212734 | 1 |
| 第一章共用外觀區／低 | 4／4 | 1.411767 | 0.237566 | 0.300872 | 1 |

上表均為 `regression-grounded-*-v2`。第一章拍 c4:r1、c6:r1、c4:r2、c6:r2，共用槍手與打手外觀的實際敵人都留在原位置。真失敗包括打手 `collector_brute` 腳底 (2136,320)、清掃兵 `sweeper` 腳底 (1352,320)，及主角真接觸原平台後 (2008,255.984375) 的地面亮邊（平台 y256、實際 gap 0.015625，solver normal 向上、接觸陰影有效）。清掃兵最低高 0.415826／低 0.413017。舊的浮空 254 座標不作缺陷證據；新接地後上述不足仍真存在。所有 false 與 exit1 保留，A/B 全圖一致、不調其他區域或門檻掩蓋不足。詳見 [results-summary-grounded.json](results-summary-grounded.json) 與各 `regression-grounded-*-independent.json`；舊 summary 明確屬診斷。

## 受影響測試

隔離 `run_tests_changed.sh` 正式選為 ALL：88 套件、98,446 checks、0 new／0 known failures，真正 exit0。15 個候選檔案的前後 SHA 相同，本票六個產品檔案也與該候選逐 byte 相同；此組包含 NE283 修正及 NE277 較早七檔，不包含後來的新 Animator。3 個分片有原 runner filter 允許的 shutdown 診斷，沒有 SCRIPT ERROR，不宣稱所有 log 零 ERROR。原 full.log、四個 shard、candidate 與 exit 收據逐 byte ZIP 保存並讀回核驗，見 [affected-tests.json](affected-tests.json) 與 [affected-tests-raw.zip](affected-tests-raw.zip)。

## 原位元組與重驗入口

[canonical-evidence.json](canonical-evidence.json) 明列 8 個正式 held 案例、2 個 live AI 案例及 88-check CPU 案例。8 個 held 案例的完整被列入 runtime source 字典互相相同、執行前後相同；它們的工具與六個產品檔案也與交付來源相同。每個原生 ZIP 的 `source-before.json` 決定該輪實際封存範圍，不將它冒稱為全 repo 的完整資源快照。

[final-protocol-source-raw.zip](final-protocol-source-raw.zip) 保存最終工具、六產品與操作 runner 的原 bytes，逐成員 hash 見 [final-protocol-source.json](final-protocol-source.json)。UID sidecar 是交付的路徑參照；probe 使用明確的 `res://` 路徑載入，實際測試來源以各 case 的 source 清單為準。舊 `BG-55-final-*`／未帶 grounded 的圖片及 summary 是先前診斷，正式靜止圖僅使用 grounded-v2；live AI 圖另以 `BG-55-live-ai-*` 命名。

解開任一正式原生 ZIP 到 repo 已忽略的 `work/` 子目錄後，可直接重算原 float pixels，例如：

```powershell
python tools/verify_bg55_readability.py work/bg55-check/high --require-owners --require-contact --out=work/bg55-check/high-check.json
python tools/test_bg55_evidence_verifiers.py work/bg55-check/high --out=work/bg55-check/negative-check.json
python tools/verify_bg55_actions.py work/bg55-check/ai-high --out=work/bg55-check/ai-high-check.json
```

各 case 的 `command.json` 保存真正執行的 Godot argv；重跑原生時換成新的 output 路徑，使用 GPU lock、保留當輪來源 SHA 與 raw.zip。不可把重算舊資料冒稱為新原生截圖。
