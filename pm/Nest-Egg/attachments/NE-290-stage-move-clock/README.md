# NE-290 同一發布時鐘證據

純框架候選由已發布 `2c5cc9fc9f9869c045aa8a762260cfd50112ace8` 的完整 runtime archive 建立。`proposal-v1/manifest.json` 列出七個可獨立交付的 runtime／UID／回歸檔；純 Player 沒有 NE-267 尚未發布的站穩準備、NPC adapter、motion 或 guest 美術依賴。`C-union-safe-player.gd.txt` 只供工作樹整合，保留那些既有 WIP，不能整檔當作純票提交。

- `published-clock-red-v1`：相同核心 callback fixtures，原發布碼 108 checks／26 failures，exit 1；失敗原碼、二進位 log 與來源保留。
- `published-clock-green-v1`：165／0，包含核心 108、所有權與暫停等 13、已發布 NE-287 reach 44；exit 0，無引擎／腳本診斷與清場洩漏。
- `published-focused-v1`：原 CutsceneSuite、LocomotionSuite 1946／0，79.451 秒，exit 0。既有故意錯誤 fixture 訊息使用原 `tools/test_filters.sh` 分類，零意外診斷、零洩漏；不是宣稱 log 完全沒有 ERROR 字樣。
- `cleanup-audit-v1.json` 另掃原始 log 的 `ObjectDB leaked`／`were leaked`、RID 與 resource 洩漏措辭。

`published-native-v1` 是實際 Forward+／RX 9070 XT 的 12.355 秒原生擷取，exit 0、零診斷／洩漏。D 純候選全來源、C348 context 與 wrapper 來源在程序前後完全相同。其他 CPU 工作存在，不能作效能結論。六頁使用實際 dispatcher／Tween／Actor 與已發布 Rin、廚房壺，重放固定及交替 delta、一般與物理持物移動，兩朝向、每頁四個相鄰樣本。24 個樣本 gait weight 都是 1；持物接點最差 0.000003815 stage px。這是受控 callback 測試，沒有人工操作或實體輸入裝置驗收。

原尺寸七張 PNG 已全部目視；人物、手、腳與壺均完整。持壺頁標題偏長而相鄰文字互疊，沒有遮住人物或量測區域；不以標題問題冒稱版面完全通過。Root 另親自檢視七張，範圍只含這七張。既有 Rin 體態／服裝屬原資產，沒有在本票修正。

`published-s18-static.png` 單獨呈現未改的已發布 S18：它仍使用舊共用護理師身體與客人肖像，沒有新 guest actor，該靜態圖本身不測移動，也不作 NE-267 美術驗收。真正 guest S18 另有下段整合重拍；新 walk 的 50 個真接縫失敗保留於 NE-267，不能被 clock 原生六頁代替。

`guest-scene-clock-v1` 是 D 整合候選的真 S18 三段：同一 observer、原 guest 美術／motion／NPC adapter 完全不變，Actor 與 transport 使用純候選相同 bytes，Player 保留站穩準備的 union-safe 版本。這組含尚未發布的 guest，不能冒稱純框架基底；純基底的永久回歸與原生六頁在上方獨立成立。自然播放、合成推進對話，沒有 Story 結果／credits 變更；33.749 秒 exit 0、零診斷／洩漏，D 與 C348 來源前後完全相同。

同一 `analyse_scene_feet.py` 用原來源 alpha≥128 像素中心的凸包與保存的 Sprite2D affine，獨立重算兩個版本，與 observer 最差差異 0.0000162 stage px。原 1 stage px 門檻沒有修改：舊 ticket 98 個足底穿地樣本／40 格雙腳皆無支撐、done 55／21，最大 4.573464；新 ticket 469、name 303、done 643 個 frame 取樣中，三段都為 0 穿地／0 無支撐，最大分別 0.856992、-0.067793、0.969048 stage px。這是實際 render 取樣，沒有宣稱完整固定 60Hz 的逐格資料。

整合重拍 19 張原尺寸 PNG 已全部目視：進場、坐下、持紙、放桌、起身／離座、站定的手腳完整，未見時鐘引入的閃跳或穿地。原生 RGBH 在三個 `raw-NN.zip`，每個小於 45 MiB；完整三包共 64,043,701 bytes 已逐 SHA 原封複製到持久位置 `D:/NestEggDeliveries/NE290-20261112/guest-scene-clock-v1/`，原件也留在附件本機目錄。Git 精準忽略這三包與鬆散 raw，保留 PNG／原始 JSON、log、source 小包與 `external-raw-index-v1.json`，沒有重新壓縮或改寫原證據。

該資料夾 `read_raw.py --raw-root D:/NestEggDeliveries/NE290-20261112/guest-scene-clock-v1` 可用 `raw-manifest-v1.json` 逐 member／archive SHA 與獨立轉色驗證 19 張，已實際執行通過。原純發布七張的 4.49 MiB raw 包保留在 Git。接縫的 6.216 倍新 scope 仍有另一組真失敗，未因這 19 張抽樣而勾成全角色完成。

原始七張 RGBH 位元組完整封在 `published-native-v1/raw.zip`（4,703,414 bytes），`raw-manifest-v1.json` 有逐 member 與 archive SHA。`read_raw.py` 使用 float 線性光轉 sRGB 後才量化，獨立核對所有 PNG，僅允許既有 1 code value 四捨五入差；可在沒有鬆散 `.raw` 的 checkout 直接執行。原始 `.raw` 本機仍保留，Git 只忽略鬆散重複位元組。

早期 union 證據仍保留：`dispatcher-mixed-green-v2` 的暫停 fixture 自身假設錯誤，289／1；診斷證明 callback 仍正確 pending，改以實際 play／有界完成觀察後 `dispatcher-mixed-green-v3` 為 289／0。它含 NE-267 WIP，只是額外整合證據，不能冒稱純發布基底的測試。

固定來源的原 selector 聯合正式回歸已完成：70 組、94,097 checks、0 新／0 已知失敗、真正 exit 0、847.040 秒，33 個候選來源與匯入產生的 UID 前後一致。聯合來源為已發布 8c 加近戰 v8 的 26 檔與純時鐘 7 檔；沒有 NPC adapter／美術／motion／站穩準備，也沒有後續 UI 修正。原過濾器保留，200 條既有／預期診斷原樣封存，0 SCRIPT ERROR，不能稱 headless 全 log 零 ERROR。

[完整命令、原始四程序 log、候選原碼與獨立 reader](../NE-277-contact-timing-2026-11-11/affected-v8-clock-joint-index.json)；同目錄 `verify_affected_v8_clock_joint.py` 已由 Root 執行重算通過。

完整來源封包共十一個 `source-01.zip`、50,151,979 bytes，亦原封複製到上述持久交付根目錄，原件本機保留；精準忽略各自的 source ZIP。`external-source-index-v1.json` 保留相對路徑、長度、原 ZIP SHA 與原／複本位置，原始 log／JSON 及每個來源 before/after 字典沒有縮減或改寫。Git 保留 `proposal-v1/sourcebytes.zip` 的純七檔原始碼及各 patch、小型 runtime-sourcebytes、全部 receipts／負控制與原 PNG。`verify_external.py --raw-root D:/NestEggDeliveries/NE290-20261112` 已逐 byte 長度、SHA256 與每個 ZIP member CRC 驗證完整十四包；任何來源重現仍須指向原封的外部包，不冒稱 ZIP 已包含在 Git checkout。

Root 已另親自檢視純基底 7 張與真 S18 19 張原尺寸圖，並從原材質重新計算足底報告，與封存 JSON 完全相同。`independent-primary-review.json` 列出逐圖 SHA 與範圍。原足部 PNG 另外保留在 `guest-scene-clock-v1/material_sources/`；`analyse_scene_feet.py` 預設讀這份固定來源、先驗 SHA、比對封存報告，不再依賴可變的 D 工作樹，也不覆寫原報告。可用 `--out` 另存新報告。NE-267 原有接縫問題維持原票驗收，沒有被本票的時鐘接地通過取代。
