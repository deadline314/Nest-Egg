---
name: character-art-pipeline
description: Nest Egg 角色美術從原生透明立繪到遊戲的固定 SOP。生成或局部修復 Qwen Image 2.1 Uncensored 角色、取骨架、分件、補底層、匯入、處理低解析度或模糊、製作頭像與交付角色票時使用。骨架接合、破圖、動畫及操作驗收串接 rig-animation；不能用生成成功代替遊戲品質通過。
---

# 角色美術生成與遊戲交付 SOP

## 先讀與職責

完整讀取根目錄 AGENTS.md、適用票的需求／驗收／相依與全部 Commit 紀錄，再核對最新程式及來源。必讀：

- `design/03-art-pipeline/CHARACTER_PIPELINE.md`：實際配方與步驟。
- `design/03-art-pipeline/ART_PIPELINE.md`：資源及圖層契約。舊暫代圖的 4 倍解析度、固定畫布不是所有定稿的要求；以實際 spec／character.json 核對。
- `design/12-cast-redraw/RIG_QUALITY.md`：專案品質與預算。
- [rig-animation](../rig-animation/SKILL.md) 及其 [全部件驗收](../rig-animation/references/character-acceptance.md)：生成前讀一遍設計限制，拼合／動畫／交付時按該技能實際驗證。
- 修改票前讀 [pm-ticket](../../../.agents/skills/pm-ticket/SKILL.md)。故事身份、台詞、關卡配置與出場由其所屬 Session 處理。

本技能規定生成、來源、解析度與每步輸出；rig-animation 規定骨架、接點、動作、手感與渲染驗收。兩者的檢查紀錄都必須保留。文件存在、模型生成成功、測試過關不等於美術已驗收。

## 0. 鎖定來源、環境與交付範圍

1. 先查現有 `tools/comfyui/recipes/<id>.json`、`specs/<id>_side.json`、`art_src/characters/<work>/manifest.json`、`art/characters/<id>/character.json`、骨架、頭像及驗收圖。沿用有效來源與已完成步驟。
2. 每個角色列出原圖 hash、配方、seed、實際模型檔、立繪／頭像／零件用途、要求動作、裝備、近遠側與最大展示倍率。缺圖和退化分開辨識，不把已交付內容重新生成。
3. 現有定稿不覆寫。需要補底層或修改衣物時另存階段圖和 job／prompt／seed，原始可見像素盡量保留。新定稿按票準備修前修後並取得票所要求的同意；已有使用者授權按上下文執行，不重複詢問。
4. 凜的 s33 已獲使用者同意沿用並修復。不得因修骨架或升解析度重新生成她整個人、改脸或捏造以前覆寫的批准。
5. 查 `COMFYUI_DIR` 與 `tools/comfyui/comfy_guard.py`、`start_comfyui.ps1` 的實際偵測結果，不硬編舊票的 `C:/ComfyUI`。Python／Godot 也用實際可執行檔。
6. 生成由指定 Session 操作。閱讀 `gpu_lock.py`；ComfyUI、Godot 匯入、Forward+ 截圖與量測使用相同的跨 worktree 共享鎖。锁只序列化工作，不保證模型已卸載；不足時由指定 Session 透過既有啟停腳本處理。

## 1. 先制定解析度契約

不要先縮成固定的小圖，再在遊戲或審查圖裡放大。每個用途先填表：

| 位置 | 必須紀錄 |
|---|---|
| 原生定稿 | PNG 尺寸、RGBA、人物 alpha bbox、原圖 hash |
| 分件來源 | 群組／階段圖與原圖同座標；每次 resize 的原因、倍率與插值 |
| 遊戲貼圖 | 原圖像素／世界像素、貼圖像素／世界像素、各 PNG 的尺寸／pivot／normal／glow |
| Godot 匯入 | 實際 texture.get_size、壓縮、size_limit、alpha 處理、mipmap、濾鏡 |
| 實際畫面 | 邏輯畫布、stretch mode、視窗／實際擷取尺寸、角色在畫面上的像素高度、相機與演員倍率 |
| 頭像／背包 | 原始裁切區、輸出尺寸、最大 UI 顯示尺寸；不得把小頭像當全身 HD 立繪來源 |

`cut_layers.py` 的比例為：

```text
k = tex_px_per_wp / illustration_px_per_wp
texture_scale = 1 / tex_px_per_wp
```

- `k < 1` 是實際降採樣，必須明確說明用途與品質代價。高解析角色的預設是保留來源有效細節；降低解析度須有量測和畫面證據。
- 增加 `tex_px_per_wp` 時同步由工具重算 PNG 尺寸、pivot、texture_scale、normal／glow；世界高度、關節長度、武器掛點與判定不因貼圖密度改變。只改 PNG 或只改 texture_scale 都會失配。
- `k > 1` 不會創造原圖沒有的細節，不能把插值放大當作重新生成的 HD 原圖。先處理最大實際展示尺度是否需要更高解析來源。
- 2026-10-08 修復前的 main：凜來源 832×1216，spec 為 23.78 原圖像素／世界像素、20 貼圖像素／世界像素，即 k≈0.841；這是要審查的降採樣，不是推薦值。
- 本專案設計座標 640×360，預設視窗 1280×720，`canvas_items` 與原生顯示渲染須分別量測。不能僅看設計尺寸就斷言整個遊戲先畫成 640×360 再拉大。
- 畫面中只占少量像素的臉，不能保留原圖全部細線。要檢查實際相機、過場与背包的展示用途，不能單純放大已擷取的小圖冒充修復。

## 2. 生成原生透明立繪

1. 使用既有 Qwen Image 2.1 Uncensored 的原生 RGBA 工作流（`comfy_api.py` 與配方）；確認實際模型／VAE／節點支援 RGBA。不得把提示詞寫「透明」但實際是白底或棋盤格當透明交付。
2. 提示詞規定成人／角色身份與既定外觀、完整頭腳、面向、比例、衣物穿著結構、裝備與便於分件的姿勢。保持風格、臉、髮型、材質一致，避免不合理發光、融化紋理及多餘肢體。
3. 外套需要穿在肩膀與袖子上時，明确写穿着的领口、肩缝、袖窿、袖口与后摆。不得一边要求穿好的外套、一边保留 hanging off shoulders 的相反提示。
4. 四足角色按四足解剖、關節與動作製作，不能沿用人形監管者作為看門狗外觀。
5. job graph、模型、prompt、negative（若工作流實際支援）、seed、尺寸及原始輸出全部保留。比較候選後選定，不把挑過的 seed 或局部修圖偽寫成原始未修正輸出。
6. 檢查 alpha 真正有透明背景、邊緣沒有白／灰光暈、髮絲不被切掉；與解剖、衣物、左右手腳、手指和配件帳本一起審查。立繪不合理先修原圖，不能靠動畫遮住。

輸出：`01_design/design_s<seed>.png`、核對後的 `base_rgba.png`、來源紀錄。整張定稿批准依票執行。

## 3. 骨架定位與座標契約

1. 原圖不搬移；SAM 3D Body 需要灰底時另存參考圖，不破壞原生 alpha。
2. 使用既有 `pose_keypoints.py`／`fit_joints.py`。模型預測只當參考，逐點核對肩、肘、腕、頸、腰、髖、膝、踝與鞋底，確認點落在正確的近側／遠側部位。
3. 遮擋、厚甲、衣襬或四足不能由人形模型猜測後直接驗收；按立繪關節手動校準並保留依據。
4. 原圖座標、貼圖座標、骨頭局部世界座標及角色世界縮放分清。原點／父子鏈／骨長／pivot／翻面與掛點按 rig-animation 驗證。
5. 重跑 pose 前比較现有已核对 joints。自动预测不得盖掉人工校准或把原定稿换成不同比例。

輸出：`keypoints.json`、骨架 overlay、spec.joints／bones。原圖與 overlay 都要可核對。

## 4. 分群、補底層與切件

1. 按 spec.groups 的優先序取得 SAM 3.1 遮罩，分件前檢查群組覆蓋／互斥／未認領像素。提示或遮罩錯誤先修，不讓最近像素分配把手、衣袖或遠腿偷偷分進軀幹。
2. 可見圖先重新分割；只有被其他部件遮住、原圖沒有的底層才局部補全。階段圖預設只提供隱藏區，定稿其餘像素保留。已授權局部衣物修復時可明確使用 replace_visible，只取經檢視的目標衣物遮罩；不得把整張編輯結果當新定稿蓋掉臉與身體。
3. 身體、袖子、手、外套、護甲、腰、骨盆、兩腿、鞋與附件逐件核對。雙腿只取單條正確的近腿再用既定近遠側機制；不能把兩隻鞋或另一隻手切進同一件。
4. 指定的補全結果只能包含目標部件，不能新長肢體、改姿勢或重畫臉。補全圖與原圖對位、alpha、遮罩、取用範圍都要留下。
5. 遮罩快取鍵包含來源圖内容 hash、階段與提示／點位。既有快取未包含來源 hash 時，先核對來源並只使受影響的遮罩失效，不能因同名檔存在就宣稱快取有效。多輸出按 saver node 對應，不假設返回順序、不得同名覆寫前一張 mask。
6. 依骨軸切線、支點、近遠側与圖層切件。接合處留下真实底层的重叠；10px／25% 等只是起點，不是所有身材、動作都能通過的數值。
7. 頭、手、鞋、武器、外套领口与袖口须挂在实际固定的骨头；把整件外套挂胸口会让袖子跟不上手臂。活動衣襬交由相應彈簧鏈，肩领不能当自由飘带。
8. `refine` 只清確定的游離碎屑、錯色、透明白邊與已指定区域，不抹掉真实衣物、輪廓、腳趾或接點資料。`damage` 保留正確損傷底層，不能用缺件模擬脫甲。

輸出：`sam/`、`04_stages/`、`05_groups/`、`06_parts/ownership.png`、`07_refined/` 與補全依據。錯切、多手或腿重影不進下一關。

## 局部重跑與可重現修復

- `make_parts.py --only <群組>` 在發布零件時保留既有無關 PNG；被選定群組影響的 `within`／`not_within`／`minus_group` 與衍生 `near_leg` 仍須重算。`refine_parts.py --only <非損傷部件>` 只發布選定部件。兩個 `--only` 的單位不同；空名稱、未知名稱或包含空項的清單須在寫圖或啟動模型前拒絕。
- 先保存各步驟輸入／輸出 hash。局部重跑後，既有無關部件須逐位元組一致；必要相依部件要確實更新。完整重跑維持原有流程，不把後續損傷、貼圖、normal 或匯入自動當成已驗證。
- 校準與人工修補的來源層可放在 `<work>/overrides/refined/<part>.png`；必須是 spec 中已知部件、與 `base_rgba.png` 完全相同畫布的 RGBA。它優先於 07_refined／06_parts。保留修前、所用底層、取用座標／遮罩、修補理由與原圖／修補 hash；不得把修補寫成重新生成或批准的新定稿。
- `<work>/overrides/*.png` 是最終遊戲尺寸的覆蓋圖，由 build_character 套用。部件名稱、RGBA 格式與新切出 PNG 尺寸都須吻合；不符時，在替換既有遊戲 PNG、骨架與外觀資料前停止，錯誤指向實際來源路徑。不得警告後略過、繼續交付混合版本。
- 用獨立暫存目錄從相同來源重跑 refine → damage → cut，與候選交付逐件比對 PNG、character.json 和骨架資料；資料相等和影像檔案相等分開記錄。normal／Godot 匯入／Forward+ 外觀另驗，不把 CPU 可重現結果當成動畫或人體驗收。
- 離線回歸：`python tools/comfyui/test_mask_delivery.py`；此檢查不載入模型、不使用 GPU。它驗證局部發布、相依重算、來源覆蓋與拒絕無效輸入時保留交付。全角色及全動作驗收仍交給 rig-animation。

## 5. 遊戲貼圖、法線與匯入

1. 使用既有 `cut_layers.py`，輸出匹配尺寸與 pivot 的 parts、glow、character.json、rig。完成全套後再替換，失敗保留舊資源。
2. 檢查原位重組：零件 alpha／顏色／轮廓对位；关节附近透明范围不能因裁切、转正或滤镜丢失。骨长、世界大小与武器挂点维持契约。
3. 以 `paint_normals.tscn` 產生或用已核對的手繪 normal，之後才 import。normal／glow 與 diffuse 尺寸、pivot、UV 一致。
4. 匯入檢查 `process/size_limit`、實際載入尺寸與壓縮模式。`CompressedTexture2D` 類型名不代表有損壓縮，须读实际 compress/mode。不能误把环境贴图的缩小预设套到高解析角色。
5. 角色線稿的取樣濾鏡、mipmap、透明邊、法線與 bloom 分開檢查。Nearest 不是畫得更清晰的萬用開關；小頭像放大、旋轉、縮小和高解析线稿分别比較。保留適用像素素材自己的設定。
6. 原圖、群組／零件、載入 texture、正常光照、發光關閉、實際 Forward+ 各看一次：定位细节是在哪一步丢失，不用加锐化或加光遮掩。
7. 更新 manifest 時保留已有生成／seed／批准来源与歷史，不用最後一次短建置覆盖整份紀錄。只重跑受影响步骤；命中快取的分件不需要启动模型。

## 6. 接合、動態與實機品質關卡

执行 [rig-animation 全部件驗收](../rig-animation/references/character-acceptance.md)，在票上留下结果：

- 全部部件與全部接點帳本、原位重組、單骨旋轉、父子鏈／pivot／權重／圖層／武器／眼睛／衣襬／護甲檢查。
- 所有適用動作、左右面向、最大弯曲、起停／跳落／蹲起／反向／連擊切換、傷害／護甲脫落／死亡及 NPC／非人形專屬狀態。
- 逐格包含完整 clip／循环周期与切换，不把 2 秒自动当所有动画的完整范围。1×／3.4× 是本票既有检查倍率；其他最大展示倍率也要覆盖。
- 透明底相邻件隔离检查、完整角色外观与明暗背景检查，不能用武器、其他肢体、护甲、阴影或 glow 遮住断口。
- 所有裂缝、缺角、单像素孔洞与浮片都失败；不得放宽面积阈值、移除缩腰／折叠指标或提高顶点预算来通过。
- AnimAudit、受影响测试、固定条件的性能比较与实际 Forward+ 游戏／过场／背包／头像画面。实际输入响应与伤害判定按技能测试，不能把审查图说成人工游玩。
- 全角色／NPC／四足的适用范围明确。工具缺少某部位／动作时补有效覆盖或标未验证，不能用人形八动作代表四足合格。

当前命令示例（先确认本次覆盖角色／动作符合工具）：

```powershell
$env:COMFYUI_DIR = '<实际目录>'
$env:GODOT = '<实际 Godot console 可执行文件>'
& '<Python>' tools/comfyui/check_spec.py --recipe tools/comfyui/recipes/<id>.json --joints
& '<Python>' tools/comfyui/build_character.py --recipe tools/comfyui/recipes/<id>.json --from <受影响步骤> --to import
& '<Python>' tools/comfyui/check_parts.py <id> --normals
& '<Python>' tools/comfyui/gpu_lock.py -- $env:GODOT --path . res://tools/rig_joint_audit.tscn -- --chars=<id> --joints=<适用接点> --frames=<完整范围> --out=<绝对目录>
& '<Python>' tools/check_joint_frames.py <同目录>
```

`rig_joint_audit` 的现有八状态与十四类接点不是全部 NPC／衣物／四足的覆盖表，须按 rig-animation 帐本补足。`build_character.godot` 自己取得共享锁；不要再把整个 build 包在同一把非重入锁内。

## 7. 高解析審查圖與真實遊戲圖

1. 原始立繪、單件、組合與實機畫面各保留，前者不能冒充後者。
2. 修前／修後使用同窗口／实际擷取尺寸、姿勢、时间、倍率、方向、裝備、光照及後製。审查明亮版使用工具已有的 `--bright`，同时保留实际关卡光照；不得只交暗到看不清的图。
3. 高解析擷取用实际较大 render target／原生窗口（例如已核对的 Godot `--resolution`），保存原始 PNG 后核对真实像素尺寸。不能 resize 已拍的小图当作高解析截图。
4. 先确认头、手、脚和枪口没有被画布裁掉。必要时分开拍全身与头／手／接点特写，特写不取代完整站姿或动作。
5. 背包全身立繪、對話頭像与遊戲骨架用途不同；各自从正确的高解析来源裁切／拼合，不从 128×128 头像反推全身细节。
6. 描邊、眼睛、臉、髮絲、材質与衣物缝线在目标显示尺寸仍有合理可读性；全分辨率被泛光或后制糊掉，也算实机品质失败。

7. HDR 2D 的 `ViewportTexture.get_image()` 回傳線性色彩。彩色 PNG 使用 `tools/viewport_capture.gd` 的原生 sRGB 編碼轉換；不改解析度、alpha、遊戲光照或曝光。未啟用 HDR 的 viewport 不轉換，不能重複 gamma 轉換。以 `tools/test_viewport_capture.tscn` 的已知灰色色塊驗證 HDR／非 HDR 都與原始顏色接近、尺寸與透明區不變。接點 alpha 稽核、normal 與 glow 資料圖不作彩色截圖轉換。保留舊線性 PNG 為失敗證據，重新擷取正確編碼的畫面，不能靠任意提亮遮暗。

## 8. 每票交付与重跑规则

- 记录受影响步骤和最后一次有效输入 hash，沿用其他步骤。原图没变，不重跑 design；只是坐标／切线问题，不重画整张人。
- 受影响测试使用固定 base hash，commit／rebase 后仍覆盖实际差异；票要求完整测试时另跑完整测试。新 CI 失败先修，不添加到 known_failures。
- 截圖、来源与检查记录保存在本票项目 images／art_src；下一段 Commit 记录已实现和已验证的结果。只有实际交付才按本次用户要求标審查中；未验证条件保留未勾选，用户确认不代勾。
- 一票一 commit 并立即正常整合远端 main；先 fetch／rebase、保留其他 Session 的修改、验证必要合并结果。身份、推送、本地 main 同步与清理依本次任务指示。
- 同步 `.agents/skills/`、`.claude/skills/`；若任务明确要求 `.agent/`，同步这份兼容副本。修改生成工具、规格或渲染后也核对本 SOP，避免文档与实际流程分歧。

## 参考

- [Godot Multiple resolutions](https://docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html)：区分设计尺寸、原生渲染与 stretch mode；API 以本项目实际 4.7.2 确认。
- [Godot ViewportTexture](https://docs.godotengine.org/en/stable/classes/class_viewporttexture.html)：HDR 2D 讀回使用線性編碼，保存彩色 PNG 前須依 viewport 轉成 sRGB。
- 部件、骨架、动作与手感的原始资料及专案量测，见 rig-animation 的引用与对应票。不得把未经核对的数字标为行业统一标准。

## 蹲姿需要輪廓驗收（NE-222）

骨架校準與分割時，先把骨盆臀部與近遠側大腿的素材歸屬標清楚，不能把整個臀部複製進兩條會旋轉的腿。逐格接點檢查之後，仍需依 [rig-animation 的臀腿驗收](../rig-animation/references/character-acceptance.md) 檢查全彩輪廓、支撐與完整蹲姿切換。若出現球狀臀部、折角或重複體積，回到分割／支點／權重修正，必要時補局部彎曲變體；沒有洞不能作為交付理由。


持槍靜止蹲瞄採合理單膝跪姿，一般蹲與低姿移動分別驗證。前脚、後膝與裝備要按實際材質接地及遮擋檢查；完整起落、換向、換槍、卸槍與瞄準掃描遵循 [rig-animation 持槍跪姿驗收](../rig-animation/references/character-acceptance.md)。
