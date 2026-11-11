# 拾取紀錄的實際畫面更新發布

2026-11-12，NE-228 原受影響回歸在固定來源中實跑31組、13,013項，唯一失敗是「通訊結束後拾取紀錄回來」；exit1、0已知失敗、來源六檔前後完全相同。原始結果已保留在 NE-228 的 `official-first-red-raw.zip`／index，不能改寫成通過或直接歸因產品。

## 原因與控制

`tests/suite/test_combat_hud.gd` 的原斷言呼叫 `cancel_radio()` 後只等 `TestSuite.frames(2)`；該 helper 實際等待 `physics_frame`。通訊取消同步隱藏面板，拾取紀錄則在自己的 `_process` 發布顯示狀態。多個物理更新可發生在同一次畫面更新之前。

唯讀 observer 繼承原 suite 的全部12個斷言、輸入與等待，runner 繼承原 smoke 的建立／清場。九份相關來源先逐 byte 對照已發布 faa5e4e，再以原基底與六個 UI 修正各自做自然引擎時間控制，不手動呼叫任何產品 `_process`、不改可見性或倒數。

| 原基底物理／畫面頻率 | 結果 | 取消後觀察 |
| --- | --- | --- |
| 60／60 | 12／0 | 原顯示檢查通過 |
| 240／30 | 12／1，同一句失敗 | process維持3，physics24→26；radio=false、feed=false；仍正常處理、四行全保留 |
| 120／30 | 12／1，同一句失敗 | process維持5，physics24→26；同樣未經過任何拾取紀錄畫面更新 |

這是測試觀察時間錯配，沒有證明通訊取消或拾取紀錄產品失效。觀察器自己的首輪退出 signal 回呼錯誤另外保留；修正觀察器清場後才採用上述 v2 控制，不冒稱首輪乾淨。

## 修正邊界

只修已證實的恢復顯示觀察邊界，等待真正的畫面更新發布。保留全部原顯示、剩餘時間、列數及到期斷言；其他等待若沒有實際失敗，不一併改寫。不增加物理等待秒數、不手動刷新產品、不改場景、內容、選擇器、原 filter 或已知失敗。

單純增加物理影格數，仍不能保證畫面更新已發布。`process_frame` 本身也在節點 `_process` 之前；使用實際 process 後的 SceneTreeTimer 發布點，並以相同三種時鐘控制與停止拾取紀錄處理的負控制驗證。永久測試仍必須抓得到真正不恢復或丟失紀錄，不能因等待更久而假綠。

## 官方依據

[SceneTree signals](https://docs.godotengine.org/en/stable/classes/class_scenetree.html#signals)：physics與process訊號皆先於對應節點回呼，不保證節點已發布新狀態。

[SceneTreeTimer](https://docs.godotengine.org/en/stable/classes/class_scenetreetimer.html)：預設計時器在該畫面所有節點的 process 之後處理；不必改變產品時間或行為。

## 最後交付

永久變更只有取消通訊後的一處等待與註解；完整原檔可逐byte逆向重建。原六個UI修正保持相同，三種時鐘最後36/0，停Feed負控制12/2。原selector只選一組CombatHudSuite，94/0，沒有為通過修改selector、filter或known failures。

[原source objects、全部v1–v4、metadata明確勘誤與正式94項原件](../../pm/Nest-Egg/attachments/NE-291-pickup-publication-2026-11-12/README.md)。本票不代表NE228完整31組或210頁配置已通過。
