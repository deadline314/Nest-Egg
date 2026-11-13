# NE-295 角色受光：原生對照與離線重讀

候選基底為 `92521d0cf3c18bd3dad4b13a316844e70bfaecd0`，22 個交付路徑（13 runtime、7 permanent-test source、2 新 UID）。18 個既有檔案的原始 bytes 已逐一對上該 commit；原版與候選均在 `candidate-owned-source-v2.zip`。不含 primary C 的近戰／NPC 未提交內容。

所有最終原生 epoch 使用真正 Godot 4.7.2／RX 9070 XT／Forward+，C463/v29、獨立五個 user 目錄、canonical 非阻塞主鎖、8188/8189 四次實查均通過。各 epoch 自己的來源前後完全相同；不聲稱跨 epoch 的整份私有工具字典相同。所有既有紅例與舊來源保留，沒有拿新 metadata 回填舊 frame。

## 重讀

Python 需 NumPy、Pillow。從任何位置執行，不需要 Godot、原工作樹或使用者資料：

```powershell
python verify.py --extract-to D:/NestEggVerification/ne295-independent-read --out D:/NestEggVerification/ne295-independent-result.json
```

指定全新的解壓目錄。讀者逐 ZIP／CRC／每檔 SHA 驗證，核 final22/base18、每個 final epoch 的來源／C463／四份 queue／實際 scene 與遞迴 private base 原 bytes，再重跑下列五個 CPU 讀者與負控制。原始 float 與每張同幀 PNG 全在 63 個 ZIP；合計 163,395,886 bytes、1,481 個 ZIP 檔案項目，最大單檔 23,163,701 bytes。`index.json` 列完整來源、大小與 SHA。

## 最終原生證據

| scope | epoch | 原件與結果 |
|---|---|---|
| 真實手件／前臂／鏡像／坐姿 | `ne295-renderer-coverage-v1/basis-native-v3` | 5×11 RGBAH 全幅；五組 NORMAL 與 Lambert 全部落在原 float 格式包絡內；Sprite identity、flat、restore exact。前臂 final product 與獨立 RAM oracle 全像素 exact，舊 basis 負控仍有 12 個 interior pixels 被拒 |
| 近戰、持物、碎片、燒融、品質往返 | `ne295-final-renderers-v1/appearance-v2` | 37 RGBAH 全幅；三頁 AABA／HIGH restore exact，真 shadow／direction／normal 有反應。同一 pool instance armor→chain 重用、flash tint 回復與武器切換通過 |
| 雲蛇 normal Z／UV 契約 | `ne295-final-renderers-v1/worm-v1` | reset／curved 真 Worm mesh 各 8 幅；blue 變更不影響 final，flat 與 published default exact，restore exact。第一候選錯誤 Z 負控分別改變 953／1,536 pixels |
| 自然死亡與單次淡出 | `ne295-final-renderers-v1/death-v2` | 真 FSM→Hurtbox 致死→原 Tween，3 個自然 stage，每 stage scene／head copy／body copy／獨立 source-alpha1 reference 共 12 幅。來源 HP/FSM/phase 未手設；額外 reference 只改副本 alpha，不改 live enemy |
| 最終屋頂同格因果回歸 | `ne295-final-renderers-v1/cause-v1` | 16 個真正 Main RGBH 全幅＋32 個 RGBAH 真部件副本 ROI。main／part AABA 與 restore exact；真 Egret context 差 9,738 pixels；實際 source/copy mesh instance flag 一致，故沒有漏複製 opt-in 而測到舊 shader |

前四列是明示安排的 component／SubViewport 原生觀察，不是自然整章通關、玩家／實體手把操作或效能數字。最後屋頂亦為固定 pose／camera 因果 fixture；單件副本沒有 fog／foreground，不能拿其 bounding rectangle 當主畫面曝白分母。世界 Egret 與手／前臂的真 Main 原圖另保留。

`selected/` 的 22 張皆原 PNG bytes，含三個完整死亡 scene、body 與 alpha1 reference、持物／debris／worm 三頁、燒融與屋頂前後。全部無 resize、無拼接、無補光。

## 數學與來源界線

- 白手並非不受光：真 opaque hand pixels 對燈方向、遮擋、normal 有回應，unshaded 負控對方向無反應。原白色 albedo 沒有為了變暗而重畫。
- 變形前臂確有 item normal basis 與 UV tangent 分岔；Sprite 無此缺口。只讓實際 mesh 在 setup 時 opt in；Sprite／鏡像／flat 保留原路徑，沒有逐 frame 配置新材質。
- Worm 原發布版的 default normal 由 RG 重建 Z。第一候選曾錯誤重解 B、再編碼 Z；此版本與紅證據保留。final 明確保持 engine RG/sqrt 與 NORMAL_MAP Z-direct 契約，blue／flat 原生對照已證。
- 透明 HDR RGBA 的 RGB 是原生 premultiplied 值。原 PNG 直接將這些 float RGB 編成 sRGB、保留 alpha（超過 1 的 additive composite alpha 在 PNG 飽和）；這是展示預覽，數值判斷一律使用原 float。held 整頁與 death scene 含既有 additive glow／FX，alpha 可大於 1，不能當 coverage。
- 原 engine `BLEND_MODE_ADD` 的 alpha 為 `src_alpha² + dst_alpha`，精確 [engine source](https://raw.githubusercontent.com/godotengine/godot/ed1daf0bf001b61586d9930840f2f1394092c079/servers/rendering/renderer_rd/storage_rd/material_storage.cpp) 原 bytes／SHA 也在工具來源包。只對這種完整 additive composite 使用專用 loader；單件 alpha reader 的 0..1 與原一個 half ULP gate 沒有放寬。
- 死蛇折疊 strip 的多層 alpha 會累積，故原 body 最大值與 head 不同。final reader 從實際 quad／UV／投影取得凸頸段，內縮 1 physical pixel、排除其他 quad 擴 1 pixel AABB，再交集同幀、同 texture/material/filter 的獨立 alpha1 source reference opaque pixels。**不按 faded image 的 alpha 挑點。**65／18／18 pixels 各逐像素通過原 single-fade half ULP gate；原全 body max 1／.833984375／.2548828125 照留。
- 真 raw 負控：empty、double fade、舊 body 不 fade、錯位 geometry 全拒收（5/0 含 positive）；clone flag 缺失／不一致負控 3/0，rotated normal oracle 5/0。所有修改只在 CPU RAM 副本，原 raw 不變。

## 歷史紅例與勘誤

ZIP 保留各 parser、engine log、原 source-before/after、C／queue 收據與已完成的所有 float/PNG：初期 Rect2 推型／C++ only parent API、Texture 宣告尺寸誤當 Image 尺寸、未 freeze 的 shader TIME、未真正啟用 sit、shader default getter 尚未 draw 的 null→false，皆有原紅與新 epoch，未重命名成通過。舊 Window／Texture 拒收發生時尚未讀取 Image 的結果不倒填。

`sit` 前提錯誤來自 RigInput 預設 `two_handed=true`，正確 NpcAnimator 會切回 humanoid；後續僅 fixture 使用 `false`，有真 pose sets／slots／visible／active witness。原 `basis-native-v2` 只有四個完整 case 的 partial oracle 不能當五 case 成功。最終 `basis-native-v3` 的歷史 label `actual-old` 代表當時已套用的 **final v2 product**；`known-old` 才是保留的舊 basis 負控，名稱不回寫。

原 `appearance` reader 曾把完整 additive composite 當 coverage，以及誤要求已過期 flash timer 必須恰等於 0；兩個拒收保留。新讀者只修對應表示法／既有 `<=0` 契約，另外嚴驗 attachment tint exact 恢復。原 death9 的全 body maximum 假設紅亦保留；新版增加獨立 source-opacity reference 得到 12 原件，未補寫舊 9 圖的 UV／topology。

116 短 contract 的 private inherited `work/ne295-v1/contracts.gd` 漏列於該短 wrapper 的 source 清單；此事不回填。原 72 epoch 前後與現檔 SHA 均為 `91f422830d9fbba8d4d629a799171891528352bc42bb0ccabebcd7f2c34f4061`，原 bytes 已保存。五個最終 **native** 的實際 scene→producer→private extends 全部由本 portable reader 逐原 SHA 物件驗證。正式永久回歸以 Root 後續原 affected 聯集收據為準。

## 共同舞台 caller 與正式回歸

BG-57 的 final borrow6（本票相同 CharacterRig／RigDebris／兩 shader／include＋UID）已獨立通過正常 parser 與真同 canvas Rin／StagePropHold 的 7-frame AABA、normal HIGH→LOW→HIGH、release／contact。共同原件見 [BG-57 final-held-context-v2 原件索引](../../../Nest-Egg-BG/attachments/BG-57-scene-lighting-2026-11-13/final-held-context-v2/index.json)；其 manifest 明列本票 final6 與 owner manifest `440a3a3644dbe5914b83fe78f1cd6f80bfe704bbfe3d20bd0019e46dddd04620`；不把舊 borrow6 圖當新依賴版本。此包五個 readers 不冒稱重跑 BG-57 的獨立 stage reader。

Root 的最終 canonical 原 affected 聯集與 PM 完成判定另附正式補件。此 README 不提前將母票條件勾選。
