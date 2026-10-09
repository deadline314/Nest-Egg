# 真基線／真引擎／原生證據索引

| 項目 | 實際值／證據 |
|---|---|
| 真repo | /workspace/Nest-Egg；不改原work checkout |
| 獨立worktree/branch | /workspace/work/cloud-creature-audit；codex/cloud-creature-art-audit |
| 圖像／source／局部套件固定base | c0250bff9dd6a44a8b1c9df557eaab18b0a12996 |
| 成功fetch | fetch-before-save.log；origin/main已由c0250bff到4d71d7a8；fetch不代表worktree已更新 |
| rebase／push | synchronization.md；提交前後真SHA以git/rebase/push原log核對 |
| CI要求 | .github/workflows/tests.yml GODOT_VERSION=4.7-stable |
| 實際合格引擎 | /workspace/.nest-egg-env/godot/Godot_v4.7-stable_linux.x86_64；4.7.stable.official.5b4e0cb0f |
| 拒收引擎 | /usr/local/bin/godot 4.6.3；rejected-engine.log |
| 真headless | --headless --audio-driver Dummy；affected-after-reimport.log / numeric / gait / metadata |
| 真畫面 | Xvfb :94，軟體Mesa25.0.7 llvmpipe LLVM19.1.7；renderer gl_compatibility，driver opengl3 |
| native尺寸 | 一般Godot PNG1280×720（canvas640×360/stretch canvas_items）；SubViewport接點atlas2048×依cell數高度、每cell128×128；failure crop原生128×128未resize |
| actor scale | 接點SubViewport wrapper1/3.4，兩face；正常window截图額外canvas伸展2倍，沒有宣稱actor3.4=window3.4像素比例 |
| source對照 | inventory.json（57 source /62 runtime PNG）、source-check.json（實選31圖 byte一致）、source-gray原生灰底分析圖 |
| 真assertion | 5個explicit suite 681 checks/0 failures；raw ERROR與既有filter政策分列REPORT，不加knownfailures |
| 接點 | frames.json的actual joint/state/frame/face/zoom與png相對路徑；contacts-report.json原生SHA／門檻／耗時，contact-failures.jsonl.gz全旗標 |
| 負控制 | controls.py / negative-control-delta.json，6個新增失敗；原checker一像素洞門檻不改 |
| 真FAIL | confirmed-failures.json + images watchdog/drone/shock_hound/wall_gecko原生灰底截圖 |
| gait | gait.json 48組（含small倍率0.62）；gait-render.log與12張原生worst數值重現；腳掌actual輪廓接地仍未驗，不拿FootGait target當通過 |
| 全圖索引 | evidence-index.json，所有保存PNG native_size/sha256/bytes |
| 未驗 | Forward+HDR／實機perf／real input／全量全彩人工逐格／Worm接點／材質腳掌接地；没有算passed |
| NE218接口 | NE218-interface.md／minimal-mount.patch；未套用、缺真watchdog素材不能交付 |

本次只有evidence/tool私有修正；原票NE90/NE91/NE99/NE100/NE218已含發現的素材／步態缺口，未另開重複票。使用者新增的HEAD:main授權僅將本組證據合入；票正文與審查中由root單寫。NE224保留本地Forward+最後驗收。
