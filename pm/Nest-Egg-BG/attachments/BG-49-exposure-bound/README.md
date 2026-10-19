# 港口敵人曝光：以實際頭部範圍建立保守上限

原先高品質全角色矩形沒有全白像素，可推出其中敵人也沒有；低品質矩形內有1個全白像素。矩形含背景，不能直接用整個矩形當敵人分母。這次保留原全角色矩形作分子上限，另渲染真正可見頭部作分母下限。

## 方法與適用條件

在原第一章碼頭入口的靜止清掃兵取樣中，先擷取當格線性HDR。保留主畫面的所有燈、雨霧、陰影與輪廓光，沒有改角色或材質。只在獨立透明SubViewport複製當格已變形的head drawable，不複製腳本、AI或其他遊戲行為；原敵人在這兩格暫停，姿態與複本變換須完全相同。複本沿用貼圖、材質與alpha，使用主viewport的final×canvas變換及相同實際像素尺寸。祖先有透明度或head使用GPU骨架蒙皮時明確拒絕，不作錯誤推算。

只數透明畫面中alpha≥0.999且位於原矩形內的頭部像素。六張正式場景裁切均實際檢視，頭部沒有被不透明前景遮住；這些像素因此是可見敵人的一個子集合。這個條件只對本固定、無遮擋取樣成立，不能直接套到躲在門後或被前景蓋住的其他場景。

若W是原矩形所有全白像素、H是這些可見不透明頭部像素：

`敵人全白比例 ≤ W / H`

理由是敵人的全白像素不多於W，敵人總像素不少於H。**這是保守上限，仍不稱為精確純敵人比例。** 原`enemy_only_ratio`保持null；H=0必須無法判定並退出失敗，不能寫成0%。

## 最終同機結果

Godot4.7.2、Forward+／HDR 2D、Vulkan llvmpipe，正式來源230863d8。三組最終運行皆無ERROR／SCRIPT ERROR。

| 品質 | 矩形全白W（三次） | 不透明頭部下限H | 比例保守上限 |
|---|---|---|---|
| high | 0／0／0 | 623／630／629 | 0%／0%／0% |
| low | 1／1／0 | 630／633／633 | 0.158731%／0.157978%／0% |
| blank負控制 | 1／1／1 | 0／0／0 | 全部無法判定，退出1 |

原型保留原16次對比計算與門檻，只增加曝光觀察者的完成等待，避免Level先釋放、少量到第三張。最終高／低碼頭對比仍通過；這些運行與歷史自然相位不同，不另宣稱完整18點的歷史不退化。BG-49四條原驗收保持未勾；軟體GPU、安排好的敵人與六張圖不替代實機戰鬥。

每張保存原HDR binary（格式14、RGB half float、1280×720）、當格HDR正確轉sRGB的完整圖／裁切、完整透明頭部圖／裁切、實際變換與矩形。獨立NumPy/Pillow只讀原始資料重算W、H與上限，六張一致；沒有重畫或修改圖片像素。

## 保留的錯誤

- v1：將head標成CanvasItem，無法靜態推導Node2D的global_transform，編譯失敗並由原生執行器終止。原log、退出值與依原差異重建的v1腳本保留。
- v2：設定SubViewport的canvas變換時尚未加入場景樹，三組各有三條引擎ERROR；數字及圖片完整保留，不當成乾淨原生通過。
- v3：先加入viewport再設定變換，三組0ERROR／0腳本錯誤；另保存祖先alpha保護、真正當格HDR的裁切與完整三張等待。最終blank負控制仍正確失敗。

這次沒有改正式遊戲、原對比公式、場景光影、角色來源、選擇器、filter或known failures。原選擇器固定base230863d8選出0組；三組真正原生與獨立重算另列，不稱遊戲測試全過。

## 參考與重現

開始前讀User-guide、visual-verification及[五個不同團隊的相近遊戲圖片](../../../../design/08-lighting/READABILITY_REFERENCES.md)。圖片只用於主次與輪廓判讀；曝光算法另核對 [Godot Viewport變換／透明背景](https://docs.godotengine.org/en/stable/classes/class_viewport.html)、[SubViewport](https://docs.godotengine.org/en/stable/classes/class_subviewport.html)與[Image原始格式／資料](https://docs.godotengine.org/en/stable/classes/class_image.html)，不由商店截圖推導其技術。

在自己的230863d8暫存checkout匯入正式資源，將[replay兩個probe檔](replay)放進work/；原生執行：

```sh
<Godot4.7.2> --path <checkout> --rendering-driver vulkan --rendering-method forward_plus res://work/harbor_head_bound.tscn -- --level=ch1_street --spots=碼頭入口 --quality=high --out=<absolute-directory>
```

low再一次；加`--blank-mask`預期退出1。只針對本固定的無遮擋港口取樣。`raw.zip`解開後，於證據根目錄執行其`verify-harbor-head-bound.py`可獨立重算已保存結果（需numpy、pillow）；若自行重跑，按原隊列的資料夾及log／exit命名保存，再執行相同檢查。

[118份完整raw（含所有失敗）](raw.zip)、[逐檔SHA](manifest.json)、[正式來源／原始碼保持與獨立結果](source.json)。

可重跑腳本只移除一個檔尾空白行；原生實際運行的完整腳本原樣保存在raw.zip的bg49-head-bound-native-v3.gd，兩份SHA與純格式差異明記於source.json。
