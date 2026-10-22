# NE-228：離開閱讀後頁首恢復的動畫時序

2026-10-22。先讀使用者指南與同票五款介面圖片研究，沿用原畫幅、0.1秒來源檢查、0.28秒Sine淡入淡出與減動態規則。CI 39748800959再次出現原頁首恢復失敗，原完整95,961項有1新失敗；本機原59組63,098／0不能取代它。

這次先前加入的失敗診斷有原始狀態：等待後active／locked／paused為false，selected為null、scope為0、goal為0，但amount仍為0.0034066、Tween elapsed 0.262853／0.28、仍在執行，頁首因此保持隱藏。前後28個物理影格、僅7個process影格。不能再猜是演出或鎖沒有釋放；也不能只因重新跑成功就稱已修復。

先用原helper、原0.48秒等待與原斷言，在獨立探針加入明示的主執行緒間歇負載重現；保留來源及每次結果。假設是物理來源判定與idle Tween的時序不同，需用同一負載的修前／修後驗證才能採用。保留完整原測試與錯誤過濾，不拉長等待、不降低HUD遮幅門檻、不關閉原預告功能。

[Godot官方Tween](https://docs.godotengine.org/en/stable/classes/class_tween.html)說明Tween在指定process或physics階段的節點之後更新；[SceneTreeTimer](https://docs.godotengine.org/en/stable/classes/class_scenetreetimer.html)也在節點之後處理。這些文件提供更新階段的契約，並不單憑文件認定遠端每一格的時間成因。

## 驗證結果

同負載原helper260／3重現；只將Tween改到來源判定的物理階段後260／0，保持動畫長度與原判定。固定基準原兩組1494／0、52秒。正式Main公開輸入三組60／0、0引擎ERROR，12張圖逐張看過。獨立舊level_02的原生退出250在原程式也重現，仍未定位，不稱已修復。[原始證據與重跑](../../pm/Nest-Egg/attachments/NE-228-framing-clock/README.md)。
