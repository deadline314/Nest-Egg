# NE-154：音量壓低的真實時間恢復

基準 `223f936a`；兩個遊戲／測試檔的獨立音效工作樹，其他角色與故事候選未混入本票。Godot 4.7.2 official／Linux；原生視窗為 llvmpipe Forward+／Vulkan，音訊輸出 Dummy。本頁是實際引擎參數觀察，不是人耳試聽、實體裝置或全章遊玩。

## 結果

- 原整批回歸 `combined-affected-final`：87,985 checks／2 new failures，另有一組 signal 11 未完成。兩項是新背景的 mipmaps 設定和原有音量恢復；原始四組輸出保留。此輪不是綠色，音效修復不宣稱解決引擎崩潰。
- 同一失敗組合另跑21組：4,865 checks／0 failures；未再次崩潰，尚未證實根因。
- 專項 red：782 checks／2個新增預期失敗，過期事件在遊戲 delta=0 時不能恢復，也不能還原播放中聲音的音量。原有恢復斷言與門檻保留。
- 專項 green：784 checks／0 failures；另驗恢復途中新低優先聲音沿用當前壓低量，高優先聲音保持原音量。
- 與CI同版Godot 4.7在此環境的本地補查：原先等候300ms的SceneTreeTimer實際只經過111ms，hold期限未改，舊斷言過早執行。改成仍等待相同300ms單調時鐘，沒有改−4／−2dB門檻。校正後以原Sfx作負控制仍有3項失敗；最終Sfx在4.7與4.7.2各784 checks／0 failures。這個測試時鐘修正與產品的零delta修復分開驗證。
- 原 `run_tests_changed.sh 223f936a`：75組／90780 checks／0 new、0 known，1184秒，0 SCRIPT ERROR。同一遊戲程式隨後只校正FeelSuite的300ms測試等候，並在兩引擎單獨重驗該組；不把早期75組說成含後來測試文字的同一份來源。原 selector、filter、known_failures 未改。這輪有 2 條 GodotArea2D RID 釋放ERROR，完整保留；不能稱作全輸出零錯誤。
- 原生 envelope v3：正常、time_scale=0.02、SceneTree paused 三組，各觀察1秒，全部由−8 dB回到0 dB，低優先聲音回到其−2 dB基準；失敗0、退出0，log無 ERROR。每格原始秒數與音量在 JSON，不是預先畫好的理論曲線。

## 重跑

`GODOT=<實際執行檔> SHARDS=4 tools/run_tests_changed.sh 223f936a`。解壓 [raw.zip](raw.zip)，將最終 `duck_release_probe.gd` 放在任意暫存目錄；以 `<Godot> --path <本票遊戲目錄> --script <probe.gd> -- --out=<絕對目錄>` 拍原生圖，加 `--headless` 只取數值。探針經 root 取真正的 Sfx autoload，沒有另建假混音器；JSON含遊戲音效程式 SHA。

原生 v1 的數值有效，但軸標以空白排版、位置錯誤，圖作廢；v2補拍誤判目前排程階段，遇到已在使用的Xvfb而未啟動Godot，錯誤未刪。v3先等當時真正執行的原生工作完整退出，再使用涵蓋Xvfb生命週期的共用互斥鎖。這是工作排程修正，沒有改遊戲渲染等待、快取或判定門檻。更早的探針編譯失敗亦保留，最終探針使用真正 autoload 節點。

## 設計依據與範圍

[來源與採用理由](references.json)／[設計](../../../../design/16-audio/DUCKING_TIMING.md)。hold與release使用同一單調時鐘；恢復曲線明確為設定期間內的線性dB變化，和舊版依frame delta反覆逼近的尾段不同。事件深度、hold、優先級、素材與授權皆未更動。五款同類遊戲的圖片是視覺參考，不能推定其音效實作。全章正式素材、實體裝置與人耳聽感仍依原驗收。

[實際原生圖](../../images/NE-154-real-time-ducking.png)。[逐檔 SHA-256](manifest.json)；raw共59檔。
