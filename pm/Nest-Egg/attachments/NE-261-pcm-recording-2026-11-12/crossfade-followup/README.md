# NE-261：換曲修正後的同操作補驗

NE-293已發布於 `6fb171a314894540880e972b2cc1a8fb1f4bce2d`。本票只更新待機聲驗收與證據；聲音素材、武器音量及動作資料均未改。本票仍為進行中，保留NE-260的原前置關係。七條證據及既有試聽／材質界線見 `criteria-audit.md`，該檔保留驗證者交付時的原稿；其中「發布後」條件已由本次提交核對。

原34段操作錄音通過：4bus各2,489,856幀、0丟幀，10按住段、32次真傷害及312次原查詢；液壓錘待機−43.717873dB、實際背景−27.995607dB，相差15.722266dB。原聲音未降、背景設定未升；改善的是已確認的換曲凹谷。

重算沿用NE-293同一份已獨立重讀的公開包，不另複製大型原件：

```powershell
python -X utf8 pm/Nest-Egg/attachments/NE-293-crossfade-2026-11-12/packet/verify_delivery.py --raw-root D:/NestEggDeliveries/NE293-20261112
```

原失敗仍須exit1，新錄音須exit0。外存ZIP的每member SHA／CRC／size均會核對；遠端checkout沒有附上兩份大型PCM，其他機器需帶外存原件並更換`--raw-root`。原24段、另一輪hold失敗及原使用者試聽紀錄仍在本票原packet，沒有重建或改寫。
