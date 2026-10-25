# ST-10：吃麵餐具候選

2026-10-26（Asia/Taipei）。透明筷子與分離麵條的工具原始RGBA候選；來源圖片未覆寫，完整提示詞／參考雜湊見prompt.json，實際1536×1024、935,864bytes、SHA及透明區塊見manifest.json。要求約1200×800，工具未提供seed／model／job，皆記null，不編造。

已接共用素材管線與正式劇情；驗證結果見ST-10 meal-actions附件，不以候選採用本身當驗收。低alpha邊緣以真正渲染器檢查，不把透明RGB或殘點當實體接觸。角色既有手圖、碗與故事結果保持；加工走story_staging_art清單，沒有用圖片編輯程式手改成品。


桌子完整／餐後兩份新生成原件各1369×1149，去掉左碗固定筷子，右碗仍有食物與餐具。來源與提示詞見table-{full,eaten}-{manifest,prompt}.json；外區不是逐像素不變，下方桌椅alpha32 IoU約0.98167，右碗／蒸氣約0.98696，原始量測見交付附件。來源皆保留；完整表面、餐後表面與圖集走同一grade／normal／import流程，向右／下補成偶數畫布，不手工繪製產品圖片。

舊完整／餐後／glow參考已以prior-*-reference.png凍結，生成時參考SHA可回查。正式舞台的筷子為獨立同一物件，地圖餐後變體沿用原餐後來源內的一雙休息筷子；兩種表現各只有一雙。舊story_prop_states入口委派同一正式管線，歷史recipe留在prior_adoption，不保留第二個會覆寫成品的製作者。
