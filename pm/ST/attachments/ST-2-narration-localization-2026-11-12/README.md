# ST-2：補齊序章旁白與副標翻譯

原掃描略過`narrate.lines`裸字串與`title.sub`，使序章兩處在日／英文模式留下中文，也沒有缺譯提示。來源、產生器、資料、執行期及回歸一起修正：旁白譯文逐位置檢查容器、長度及字串型別，缺日文退英文再退中文，記錄精確位置。旗標／ID陣列與原非字串項目保留。

中文及劇情不變，新增4個翻譯欄位；既有內容只把老K擦鞋句的日文店名統一為「巣卵質店」，與新副標及命名表的「巣卵」一致。其餘既有JSON值、3筆作者覆寫及舊表項保留。文字覆蓋532處／475種原文→534處／477種，原缺4個日英欄位→0；重建冪等。

| 範圍 | 結果 |
|---|---|
| 原StoryLint與真正修前反例 | 原175／0；新增同一回歸194／9→194／0 |
| Python單元 | 4 tests通過；原紅與中間失敗保留 |
| schema候選原受影響入口 | 26組8,834項，0新／0已知失敗，exit0，732秒 |
| schema→店名三檔增量 | 原selector選9組4,274項，0新／0已知失敗，exit0，248秒 |
| 接最新音訊主線612696e4的整合 | StoryLint／Cutscene／Music／UiScreens四組2,732項／0，原runner exit0、84.067秒；4,928份列入來源前後相同 |

兩輪各自保存來源manifest、命令、完整log與前後凍結。9組只代表三檔增量，不代稱最終七檔對原基準的完整選取。四組整合在原隔離分支乾淨rebase最新main後重放相同七檔，以原執行檔／default headless完成。原過濾器與斷言保留；零SCRIPT／退出洩漏不代表raw沒有刻意ERROR。

`original-proof.zip`保留97份indexed原件與索引本身，共243,056B。`latest-main-integration.zip`保存主協調的新整合腳本、命令、完整分片及來源字典。主協調另從新解包重跑來源逐值／覆寫／增量檢查。核對兩份ZIP與目前七檔：

```powershell
python -X utf8 pm/ST/attachments/ST-2-narration-localization-2026-11-12/verify.py
python -X utf8 tools/story/test_story_i18n.py
```

要重算來源語義，在保有4a2f9ecf歷史的獨立checkout解開原包、套用內附`final.patch`，讓該checkout只有七檔候選；設`ST2_CANDIDATE_ROOT`指向它，再跑`check_integrity.py`與`check_increment.py`。原helper也核對工作區範圍，不應對有其他工作的主工作區直接執行。重建與環境命令見ZIP原README。

本次資料／執行期回歸不代稱新Forward+截圖、母語審稿或真人完整章節；序章兩處的原生畫面接續驗證，完整套件由新推送CI負責。ST-2維持進行中及原前置關係。
