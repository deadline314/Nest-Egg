# NE262 原生／CPU補驗交付（2026-11-12，供Root獨立審查）

這包只新增證據，沒有修改產品或票。原提交 `0f1df75f7b2d3036c4756f21a7d5c4d55a936994` 移除了平常的弱點四角框；原550項測試沒有找到可回讀raw，仍只視為歷史票文，不用本包數字回填。

入口：[index.json](index.json)、[verify_pack.py](verify_pack.py)、[source.zip](source.zip)、[raw.zip](raw.zip)、[ticket-draft.md](ticket-draft.md)、[design-draft.md](design-draft.md)。所有大原件留存；`raw.zip` 約48.7MB，建議Root交付時完整原byte另存外部，只把source/index/reader/三張原圖與草稿放Git。若外部保存 raw.zip，讀取器用 `--raw-root <其資料夾>`，不需要改原manifest或來源。

## 三張真原圖

- [legacy-before.png](images/legacy-before.png)：真grunt與watchdog的頭及其他弱點有四角框。
- [after-a1.png](images/after-a1.png)：同一真actor／同一pose／同一鏡頭，常駐四角框消失。
- [debug.png](images/debug.png)：真頭部黃框、砲塔普通部位青框；disabled back_power不畫debug框。

三張都是1280×720原生readback，無剪裁、標題、調色或拼圖，已逐張全尺寸實看。複本逐byte等於raw內PNG，SHA在index。原始老票的組圖仍在原Git提交；本包不是重製它。

## 版本與真實對照

被執行的runtime是獨立D影子的published `8c788e7c79a6c842e94aaf62892b5301492bc9a6`。`source.zip/published-D8c`保存實際相關函數／資料；每次執行的selected runtime/art SHA前後相同。C364v14也逐檔before/after守門，但它是**並行工作樹context，並非D程序載入的runtime**。`source.zip/earlier-review/current-source`是更早只讀審查時的C來源（含當時未交NE277 Hurtbox），不冒稱為D原生來源。

**B只在RAM繼承真actor的正式behavior，還原原提交父版本的 `_draw_weak_points` 函式，SHA `ddfe5b4d5a8dde4d43450c798fd3b5742c4f6f1678cde7289bf27f8e9519eb9a`，不是完整歷史checkout。** A和debug走D正式函數。其餘新增override只觀察 `super._weak_point_feedback` 的真粒子數，不代替產品回饋。真傷害／弱點回饋另外走公開存在的Projectile `_strike`受控API。

原生是Radeon RX9070XT、Godot4.7.2、Vulkan Forward+、HDR2D、實際window及readback1280×720。原場景world保持paused，level明確PAUSABLE，獨立world process/physics witness、骨點／drawable transforms、動畫時間、相機、body/area space與其他pose欄位都固定。正常序列為A1→B→A2→debug→A3；三張A的整PNG與整float bytes完全相同，不是只比較局部平均或把相近畫面當A/A。

## 實際結果，分開計數

| 案例 | 引擎結果 | 獨立讀取器結果 |
|---|---|---|
| CPU真head/body受擊 | 14/0，13.001s，exit0／無diagnostic | 真head傷2／part=head／weak=true；body傷1非weak；head weak callback真生成3粒子；weak Sfx leaf與準星timer實際發布 |
| CPU把body冒稱head | 14項中4項故意紅，12.402s，exit1／無diagnostic | 倍率／part弱旗／weak callback粒子／準星四項拒絕 |
| zoom2正常原生 | 13/0，13.468s，engineexit0／無diagnostic | legacy24段與debug12段投影逐線通過；全尺寸A/A、同pose與spaces通過；新reader程序exit0 |
| after仍畫四角框 | 13/0，13.575s，engineexit0／無diagnostic | B-A無應有的真變化像素，reader新程序exit1；不是拿engine0作通過 |
| debug故意關掉 | 13/0，13.494s，engineexit0／無diagnostic | debug-A無應有黃／青變化像素，reader新程序exit1 |
| 正常raw離線故意錯投影24px | 不啟引擎、不改圖 | 仍在viewport內，預測位置真變化cluster0<4，readerexit1 |

正常原生、兩故障與首失敗構圖四個執行，C364v14 source全相同，primary C GPU lock串行。每組8188 before/after均0running/0pending；8189記錄真ConnectionRefused/10061，寫作service absent，**不拿拒連自行宣稱模型idle**。這些是功能驗證，不是效能樣本。

### 保留的失敗

- CPU第一輪把 `Fx.sparks(...6...)`誤期待為6個實粒子，實際published `PARTICLE_SCALE=.5`生成3；原14/1／engineexit1與原producer完整保留於 `cpu-/1794424719260700600`。修正工具期待為正式倍率，不改產品。
- 原native zoom3使watchdog右半與legacy仍畫的disabled back_power框出viewport；engine13/0，但reader因真投影出框拒絕。原圖／float／source／plan保留於 `native/1794458714060871000`，其獨立reader仍拒絕。
- 新epoch只把fixture camera zoom3改2並記新SHA，原角色位置／部位／資料、判定公式與邊界不改；舊capture不歸到新source。

### 聲音、火花與來源界線

CPU實際head命中觀察到 `hurt_humanoid`、`hit_a`、`mat_armor`、`hit_weak` 的真 `Sfx.sound_played`，weak callback粒子14→17；body沒有weak callback／weak marker。`PARTICLE_SCALE=.5`與設定倍率1對請求6的期待是3。這是實際API／spawn／聲音leaf事件，沒有錄PCM、人工試聽、自然瞄準飛行或實體手把宣稱。

原NE262提交沒有改任何傷害／音效產品。函數body對照、命中材質JSON相同；另保存原提交與D8c的selected `hit_enemy`事件、`hit_weak/hit_a/hit_b/hit_c/hit_tail/mat_armor` bank entry逐值相同證據，`hit_weak_01.ogg` SHA也相同。整份sound bank／事件檔與Fx腳本因後續其他票已不同，不能擴張成整份歷史版本／全混音相同。

## 唯讀重算

依賴Python、NumPy、Pillow。直接讀ZIP，不解壓、不找live runtime、不寫回raw、不啟Godot。

```powershell
python -X utf8 verify_pack.py
python -X utf8 verify_pack.py --raw-root D:/your-external-NE262-folder
python -X utf8 -m unittest test_pack test_geometry -v
```

本包實跑portable reader成功：raw539檔、source90檔，全部CRC／SHA重算，CPU正負／原粒子錯誤／正常36段／兩故障／舊zoom3／24px錯投影／C364四組／queue／三圖byte全部核過。10個Python控制通過；geometry test只改import alias以引用同byte的`reader.py`，原test／reader來源仍完整封在source/raw。每個成功引擎的真stdout無SCRIPT ERROR／ERROR／ObjectDB/resource diagnostic；沒有將原票550、Root的其他正式回歸或新Python個數混加成一個漂亮總數。

Root可另精確引用其已封的official42聯合回歸（NE228六源＋NE231四源；58,211／0新／0已知、508.782s、185原filter允許ERROR／0SCRIPT），它不是本D8c probe同源的純NE262新測試，也不能替代原550。票稿保留這個範圍界線，最終採用與狀態由Root獨立確認。
