# NE228 Codex v5：焦點、完整閱讀與手動捲動

本包只交付圖鑑兩個來源的修正與驗證。全UI210、Threat、超寬KEEP完整頁矩陣、實體手把／自然主線流程仍未完成，不因這兩頁面品質修正代勾母票。

## 最後實際結果

來源固定 `ui/codex_screen.gd` cb3a1565…d4c21、`test_ui_screens.gd` a9fd0603…0c38；完整SHA在candidate/acceptance index。相對published187d330a，只有這兩個delta，另外四個曾共測的UI來源已由前一進度提交完成，不重複計交付。原候選manifest的scope仍保留當時「native/official pending」，最後結果由本包新的acceptance-index補充，沒有回寫舊manifest。

| 最後epoch | 原生條件 | 實際結果 |
|---|---|---|
| native-cb3a-720-clean-v2 | 原生Forward+ / RX9070XT，1280×720，字級1.0 | 8張原PNG、exit0／0診斷／0退出洩漏，原來源與C v14前後同；queue前後8188=0/0、8189真10061 |
| native-cb3a-1080-scale12-clean-v2 | 同硬體與後端，1920×1080，字級1.2 | 8張原PNG、相同完整守門通過 |
| detail-sync-snapshot-trace-60-60-v17 | 真headless時鐘，physics60 / process cap60 | 原16項／0失敗，含永久測試與被動layout觀測 |
| detail-final-layout-signature-120-30-v18 | physics120 / process cap30 | 原29項／0失敗；真wheel 0→23→23、字級1.0→1.2後末卡完整 |

Root的正式原入口受影響檢查另有19groups／9,212／0新0已知／exit0，base187＋僅這兩源，原3,943來源前後同。原件在上層UI附件 `official-codex-final-v1-{index.json,raw.zip}` 與 `verify_official_codex_final_v1.py`，完整SHA只在acceptance-index連結，不複製／重stage那些已封的共享檔。此reader不冒稱又跑一次該正式檢查。

## 修正與真實控制

原published `follow_focus=false`，末卡焦點可以停在可視區之外。單改true後，已解鎖詳情使卡牆重排，第一次focus的scroll先於佈局完成，末卡下緣仍被切掉；實際最長的原攻略ch1_inspector_contact／62字還把整頁往下撐，頁尾與返回鈕跑出720視窗。

現在詳情仍用原214寬面板、原字級與完整原文，內文在有界ScrollContainer內閱讀，PgUp/PgDn或對應垂直導覽可讀到末行；頁尾與Return維持在viewport。focus layout hook只在真wall尺寸或內容minimum變化後校正實際後代焦點，兩Vector實例cache；同步擷取排序當下的幾何簽名，deferred後僅在仍匹配時套用。保留有效／tree／visible／follow／descendant守門，沒有每幀輪詢、搶外部focus或縮字／截短攻略。

控制原件全部保留：

- 原published＋新斷言真紅、follow_focus=false 故障也真紅，原「3個process」斷言沒延長。曾初步懷疑physics publication，讀到原suite自己的override後已排除，不把NE291根因挪到此處。
- a039天真sort hook在真wheel後0→23→0（14／1），不是只測scroll屬性setter。
- RAM no-hook同源保留wheel23，但實際字級變更後末卡y422…479、wall110…284，27／1真紅。此no-hook只對其明示第一／manual頁生效，另一個long guide頁未斷連，不宣稱27項每頁都是no-hook。
- v13／v14早期cache方案都有真resize紅；v15重複signal連接、v16工具parse失敗亦保留，沒有改成產品通過。
- cb3a最終native真`Viewport.push_input` mouse motion/wheel，記錄事件座標與即時／settled scroll；`Settings.set_ui_text_scale(1.0→1.2)`實際重排，末卡幾何獨立重算仍包含。
- 最長原攻略以RAM解鎖的實際author card呈現，真InputEventAction PageDown parse後到末行；Return走真button的pressed callback，確認closed/釋放/解鎖集合還原。這是合成callback與fixture，不冒稱OS按鍵／實體手把或自然任務解鎖。Return/清場是原producer斷言＋乾淨退出，沒有偽稱另存了實體button event log。

兩輪16原圖已逐原尺寸親看14個唯一內容（各returned-last與last逐byte相同）：長攻略最後一行可見、邊框／Return與圖例不溢出；變字級後末卡仍完整。manual-wheel畫面允許先前焦點卡被使用者主動滾出，這是保留手動捲動的正確控制，不拿該畫面宣稱卡仍完整。詳情是有提示的捲動閱讀，不要求每張長文同時完整塞在一頁。

## 來源、尺寸與舊epoch界線

專用D基底8c788e7c，只有自己凍結的UI候選；不冒稱整份D等於後續C或正式187。每個epoch實際使用的before/after、source物件與C守門原件都在ZIP。最後原生C守門是當時**v14／364路徑**，後來Root採用UI兩源產生v15／365路徑（新增原未列的Codex、更新原UiScreens），沒有拿live C倒填歷史收據。

使用active viewport的真正PNG，不是桌面Window截圖，沒有補黑邊或變更KEEP；16張實際image/Pillow尺寸是1280×720或1920×1080。`texture_reported_get_width_height`在同次資料可回較大數字，作為原觀測保留，沒有冒稱它等於實際readback，也不猜測原因。之前21:9外窗active內容1920＋左右320 final offset的爭議仍在完整矩陣待驗，這兩個16:9短驗不替代它。

47個epoch原檔全部留存並逐一標legacy／accepted，不把舊a039、v13、focus-only的exit0解釋為完整v5通過。尤其native-cb3a-720-v1雖功能過，queue後驗1running，**拒作乾淨最終**；1080-scale12-v1忙碌preflight拒絕，根本沒有引擎exit或PNG，不能補造。最後兩個clean-v2才是乾淨新原生。

既有metadata勘誤亦保留：最長卡曾誤稱hook_pull，實際是ch1_inspector_contact／62；舊v2總manifest曾在validguard更新後被覆寫，後來由原source物件重建為舊SHA並明記reconstructed index，不能叫未動過的原manifest。各run原source/exit沒有因此改寫，v3/v4/v5另存。cp950終端亂碼、早期SceneTree缺autoload、parse錯誤等均屬legacy工具原失敗，沒有算進最終通過。

## 離線驗證與原bytes

raw.zip以content-addressed objects儲存完整原bytes，members.json將原路徑映射到SHA，不正規化CRLF。含47epoch的原source／log／exit／觀測／PNG，另封完整producer與各候選原來源。排除的是隔離user profile本身及Python cache；user目錄路徑與隔離守門保留。所有一般raw皆低於100MB所以完整留Repo，沒有只留下精選綠圖。

唯一private例外是外部Comfy busy queue中與本工作無關的graph／prompt。其原JSON原bytes保存在D外部private-queues.zip，index存整包／逐檔SHA與計數；Git只留derived count/status/SHA，不操作、取消、隱藏外部工作。最後clean兩輪的前後queue原JSON沒有外部graph，完整包含，可獨立驗0/0與真10061。

```powershell
python verify.py --root <本資料夾>
python reader_controls.py --root <本資料夾>
```

reader逐byte驗ZIP、全部成員、16張原圖與actual size、兩份產品SHA、C原364字典、原生後端／硬體、每輪前後queue；用原數值重算末卡／頁尾／Return／詳情bounds、原完整hint、讀到最後行、wheel不回彈與resize。reader只讀，不在凍結epoch內重寫收據。另三個記憶體反例保留passed旗標卻改wheel回彈／藏末卡／截攻略，必須各自拒絕；它們是reader控制，與原引擎紅分開列。
