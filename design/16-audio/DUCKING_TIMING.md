# 音量壓低的時鐘與恢復

原本 Sfx 以 Time.get_ticks_msec 決定 hold 結束，接著卻用受遊戲時間倍率影響的 delta 恢復音量。慢動作或停頓會把同一個音量包絡分成不同時鐘；恢復途中新加入的聲音還會直接以完整音量開始。

現在 hold 和 release 都從同一單調時鐘計算。release 在既有設定的恢復期間內做線性dB變化，結束精確回到基準；事件hold與壓低量、優先級及聲音素材不變。新低優先聲音取當下包絡，高優先聲音維持本身音量。這是本作的包絡選擇，不宣稱是其他遊戲採用的唯一標準。

[實測、原始資料、失敗與重跑](../../pm/Nest-Egg/attachments/NE-154-real-time-ducking/README.md)。以實際 AudioStreamPlayer 比較正常、慢動作0.02和暫停；可由原生圖與逐格JSON核對。既有300ms恢復檢查改以相同單調時鐘等待300ms，保留原音量斷言；在本地CI同版4.7量得舊SceneTreeTimer只經過111ms，沒有靠放寬門檻或任意加長期限通過。負控制仍會抓到原Sfx零delta與新聲音接續失敗。沒有錄取或試聽實際音訊輸出，不能用此證據完成音質與全章素材驗收。

參考 [Godot Time](https://docs.godotengine.org/en/4.1/classes/class_time.html)、[Engine](https://docs.godotengine.org/en/4.1/classes/class_engine.html?highlight=time_scale)、[Unity AudioMixer updateMode](https://docs.unity3d.com/ja/current/ScriptReference/Audio.AudioMixer-updateMode.html)、[Unreal Quartz](https://dev.epicgames.com/documentation/unreal-engine/overview-of-quartz-in-unreal-engine)和[Audio Mixer](https://dev.epicgames.com/documentation/en-us/unreal-engine/audio-mixer-overview?application_version=4.27)：只借用區分遊戲與音訊時間的原則，沒有移植音訊排程器或宣稱取樣精確度。API行為另以本專案實際Godot 4.7.2驗證。
