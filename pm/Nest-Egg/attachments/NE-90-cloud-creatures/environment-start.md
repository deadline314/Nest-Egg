# 啟動與能力：未把 pending 當通過

開場 environment_status 觀察為 pending/offline、capabilities=[]、failure=null。這一筆只有 Session 工具回覆／對話中的觀察，並未保留可驗 SHA 的原始 JSON；不能補造原始回覆。先讀可用 GitHub 依賴，平台就緒後才使用 /workspace shell。

實際未觀察到 snapshot_materialization_failed 或 gateway_unavailable；不得編造這兩種錯誤。就緒後狀態原始結構見 environment-status.json：running/connected、network enforced、failure=null。

真 repo /workspace/Nest-Egg，原 checkout branch work，HEAD a85b23f94c1ed96e3226191a6b026c91436efa68；cached origin/main 86308c96d89994ec47a63d36f64e24c2dd662586。最初 default sandbox fetch 的 proxy port8080 connection failure 是網路沙箱限制；後來經平台批准的同一 origin fetch 成功，没有改認證或绕代理。

先在 a85b23f9 detached worktree 做診斷（snapshot-a85b23f9/）；成功 fetch 後，從真 origin/main c0250bff 建立 codex/cloud-creature-art-audit。工作目錄 /workspace/work/cloud-creature-audit。這兩個基線不混算。後續同步另見 fetch/rebase 記錄。

CI .github/workflows/tests.yml 要 GODOT_VERSION=4.7-stable；default /usr/local/bin/godot 為4.6.3.stable.official.7d41c59c4，拒收。實際使用已有 /workspace/.nest-egg-env/godot/Godot_v4.7-stable_linux.x86_64，版本4.7.stable.official.5b4e0cb0f。headless --audio-driver Dummy 已真正執行。ci-status.json statuses=[] 不是 CI pass；沒有把本地 affected assertion 代稱完整 CI。

畫面使用既有軟體庫和本 Session 的 Xvfb :94（1280x720x24），DISPLAY=:94 LIBGL_ALWAYS_SOFTWARE=1 LD_LIBRARY_PATH=/workspace/.nest-egg-env/render/usr/lib/x86_64-linux-gnu。renderer=gl_compatibility、driver=opengl3、Mesa25.0.7 llvmpipe LLVM19.1.7 256bits；VSync unsupported warning 留在原log。native viewport截圖1280x720、project canvas640x360/stretch canvas_items；接點SubViewport原生2048寬、128格，不做resize。wrapper.scale=1/3.4 而非 animate會覆寫的creature.scale。既有 shock_hound-render.log 的 preview不等比縮放只作工具缺陷診斷，不拿它验收。

import exit0 仍有 TCP listen ERROR（沙箱editor socket）；原log保留。首次更新後affected載入缺.ctex，affected-before-reimport.log 不算通過；重新import後 affected-after-reimport.log 才有681 checks/0 failures。bad-data no_such_creature ERROR 在既有tools/test_filters.sh EXPECTED_ERRORS；exit資源/RID診斷由既有EXIT_DIAGNOSTICS排除，原log不刪。不新增known_failures。Forward+HDR、normal/glow完整實照、實機效能／真輸入交NE224，不冒稱已驗。

官方原始犬步態參考本次未取得：公開原始研究倉庫README候選請求404，GitHub REST metadata403，已停止該來源請求，未绕過。interface的對角小跑分組只作專案接線起點，不是已完成官方動捕相位驗收。root 必須取得可信原始犬walk/run接觸序列後校準；沒有新增素材／motion。
