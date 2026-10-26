# run_tests.sh 與 run_tests_parallel.sh 共用的輸出判斷（用 source 載入）。

# 測試刻意觸發的錯誤（驗證缺圖／缺定義時的容錯）不算失敗。
EXPECTED_ERRORS="找不到角色骨架|區域覆蓋的群組|沒有電話亭可登記|復原點位置無效|missing_part|no_such_character|test_catalog|no_such_icon|起點 987654|test_bad_cutscene|no_such_stage|no_such_sfx|test_missing_prop|test_missing_ammo|test_npc_bad|test_area_bad|no_such_pose|no_such_loop|no_such_action|npc_animations.json 沒有|action_poses.json 沒有|test_no_such_enemy|test_audio_|no_such_creature|test_no_such_feel_event|test_no_such_sound_event|test_no_such_material|test_no_such_attack|test_no_such_weapon|test_no_such_enemy|test_no_such_preset|test_no_such_window|\[FeelAB\]|\[DevMenu\]|\[StageScenes\]|\[StageActions\]|\[SoundStage\]|\[LabArena\]|body->get_space\(\)"

# （body->get_space() 那一行是某個既有測試觸發的引擎訊息，在 main 上就有。）

# 完整測試保留歷史 fixture 的退出資源相容規則；訊息本身不能定位成因，也不能一律歸咎音訊。
# 獨立程序仍嚴格拒絕任何退出洩漏；BG-51 另檢查全部遊戲分片的 DummyTexture 診斷。
# 自己編譯的 Godot 沒有 fontconfig 時，載入介面字型會印這行（系統字型找不到、退回內建字型），與遊戲邏輯無關。
ENGINE_BUILD_NOTES="compiled without fontconfig"

EXIT_DIAGNOSTICS="resources still in use at exit|RID allocations of type .* were leaked at exit"

# 輸出裡有沒有非預期的腳本錯誤：有就回傳 0（成功），沒有回傳 1。
has_unexpected_errors() {
	grep -E "SCRIPT ERROR|^ERROR:|Parse Error" "$1" | grep -vE "$EXIT_DIAGNOSTICS" | grep -vE "$ENGINE_BUILD_NOTES" | grep -vqE "$EXPECTED_ERRORS"
}

# 已知失敗清單（tests/known_failures.txt）：回傳 0 代表這個失敗訊息在清單裡。
is_known_failure() {
	grep -vE '^\s*(#|$)' tests/known_failures.txt 2>/dev/null | grep -qxF -- "$1"
}
