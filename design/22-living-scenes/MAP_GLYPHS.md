# 地圖字元：跨章同義的機關與新敵人

同一個字元在每一個關卡意思都要一樣。這份只列各章共用、或地圖線開的字元；各章自己的人物與出入口字元在各章產生器（`tools/level/build_ch*.py`）裡，開新字元前先用 `git grep -n "<字元>" -- data/levels tools/level` 確認沒人用過，再寫進這張表。

引擎保留：`# = ^ | ~ P C H B * & .` 與數字（見 skill `chapter-design`）。

## 機關與拾取（玩法線做的元件，地圖線擺）

| 字元 | 資料 | 是什麼 | 出現在 |
|---|---|---|---|
| `!` | `data/props/suspended_crate.tres` | 吊掛貨箱（NE-397） | 第一章倉庫、第二章裝卸間 |
| `σ` | `data/props/steam_valve.tres` | 蒸汽閥（NE-398） | 第一章街道、倉庫深處 |
| `φ` | `data/props/live_cable.tres` | 斷電纜與積水（NE-400） | 第二章市集入口、第三章夾層、第四章接線廊 |
| `Ω` | `data/props/conveyor.tres` | 可反轉的輸送帶（NE-401） | 第四章接線廊 |
| `ψ` | `data/props/decoy_radio.tres` | 誘餌收音機（NE-404） | 第三章泵室、夾層 |
| `┅` | `data/props/crumbling_walkway.tres` | 會塌的走道（NE-420） | 第一章屋頂 |
| `⦀` | `data/props/hiding_spot.tres` | 門簾凹室（NE-426） | 第二章裝卸間 |
| `⊓` | `data/props/latch_door.tres` | 門閂門：一側拉開門閂後一直開著，另一側打不開（NE-430） | 第三章天穹辦公接待廊 |
| `X` | `data/props/ch1_secret_wall.tres` | 裂縫牆（打破露出秘密房間） | 第一章街道、倉庫深處；第三章診所；第二章北棟前室 |
| `x` | `data/props/ch1_crate.tres` | 可打破的貨箱（掩護，掉零錢） | 第一章當舖；第二章市集入口 |
| `▧` | `data/props/ch4_arena_cover.tres` | 廠房掩護箱 | 第四章清掃工作廊、舊廠外廊 |
| `c`／`q` | `data/props/credits_small.tres`／`credits_large.tres` | 信用點 | 各章 |

## 地圖線開的敵人字元

| 字元 | 敵人 | 開的票 | 說明 |
|---|---|---|---|
| `Щ` | 重裝機槍手（`heavy_gunner`） | NE-451 | 舊示範關卡用 `v`，但 `v` 在第一章是看門狗的閘門 |
| `Ф` | 狙擊手（`sniper`） | NE-451 | 舊示範關卡用 `Z`，但 `Z` 在第一章是麵攤的出口 |
| `☏` | 收帳人·聯絡員（`collector_caller`） | NE-452 | `☎` 在第五章是電話亭 |

第三章的巡檢器與守門人用 `Ж`、`Ш`、`Ю`（`build_ch3.py`），第四章的切割者、探照無人機、清掃兵用 `b`、`d`、`g`（`build_ch4.py`）。
