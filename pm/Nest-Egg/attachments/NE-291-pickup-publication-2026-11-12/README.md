# 取得紀錄的介面更新邊界

原斷言要確認通訊取消後，四條取得紀錄會正常回來；產品在`_process`發布可見性，原測試卻只等待兩次`physics_frame`。兩個物理步可能全發生在同一次介面更新前，因而讀到尚未發布的舊狀態。

Observer繼承原`CombatHudSuite`，只記錄check與事件；runner繼承原smoke，僅呼叫原`_test_banner_kinds`並使用原清場。未改原輸入、資料、斷言或等待的V2對照，在UI六修復前／後得到相同結果：60物理／60process上限各12／0；240／30與120／30各12／1。唯一失敗均為「通訊結束後拾取紀錄回來」。原取消事件與失敗斷言之間，物理計數增加2，process signal序號未增加；通訊已同步隱藏、紀錄仍四行、Feed允許處理且仍在處理，但尚未收到介面更新。

候選只將該restore後的一處物理等待改為SceneTree零秒timer的post-process發布邊界。原check、到期判定、hover及其他等待保持。候選來源`da63de606a9615e337a01ca32eebace606309dc7936fa4177a8a0135f1d8bf2b`，可逆重建原來源`5beca0f6f99d4735805f7d8d34f56a6eabd2591fd415a75c8a14d74b7bc260ad`。

正確metadata的V4三個時鐘配置各12／0，共36／0。負控制在真正取消事件時禁止Feed處理，不手動呼叫`_process`或設visible；同樣經過零timer後，原restore與真到期斷言仍失敗12／2。四輪0引擎ERROR／SCRIPT ERROR、來源前後相同；D原測試最後還原，UI六檔保持原SHA。

V1有observer自己的離樹回呼錯誤，拒收。V3的scope錯稱原等待未改，這是metadata錯誤，不能重新解釋成正確；V3實際跑了一處wait改動。原件完整保留，V4增加變體與實際測試SHA核對守門，再重跑三正與負控制。正式結果只採V2乾淨基準／UI六檔對照與V4正確metadata候選。

`proof.zip`是271,800bytes／82members的可獨立驗證小包：原9來源、完整原斷言、來源object去重、候選前後、逐case命令／原日誌／觀察／source before-after。完整401members原始包2,172,758bytes保留在`D:/NestEggDeliveries/NE291-20261112/`，包含所有V1–V4及錯誤原件；Git不需要帶入該完整包。

```powershell
python -B -X utf8 work/ne291-radio-observer-final/verify.py --repo C:/Users/stanl/Github/Nest-Egg --raw-root D:/NestEggDeliveries/NE291-20261112
```

省略`--raw-root`即可只驗小包；加入該參數會逐項驗完整外部原件。`--repo`逐檔比對已發布FAA來源，不依賴目前working檔內容。讀取器另檢查單一wait的可逆重建、六檔才是對照差異、每次真正來源未變、process／physics因果、負控制和原斷言結果。

這些是純headless功能／測試時鐘控制，沒有GPU、效能、硬體手把或視覺驗收主張。Root正式原selector的單套結果另由Root封存附入，不將局部12項當成完整CombatHudSuite。


## Root 正式交付複核

Root 重新執行 proof reader，另外加入所有採用 case 的 ObjectDB／RID／resource 清場漏檢查，全部通過。完整 v1–v4 raw 只有2,172,758 bytes，所以另外連同原 raw-index 原封納入此附件；預設可用 `python verify.py --repo <repo> --raw-root .` 在本資料夾核全部401members，不依賴D磁碟。外部原件仍保留，沒有重壓、刪失敗或重寫v3錯誤metadata。

原 affected selector 在已發布83319fef上，只加一份永久測試等待修正：CombatHudSuite94項、0新／0已知、真正exit0、41.274秒，來源及匯入UID前後不變。`original-selector-raw.zip`／index／verify_official.py 保存完整原log、原入口、未改filter與候選byte，Root已再次實跑reader。這不冒稱NE228六檔的31組已重跑通過；先前31組真紅保留於該票附件。

`figure-data.json`與票內PNG是實際trace資料圖，沒有冒稱Forward+遊戲畫面。沒有產品UI或動畫改動。
