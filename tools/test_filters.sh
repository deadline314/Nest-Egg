# run_tests.sh 與 run_tests_parallel.sh 共用的輸出判斷（用 source 載入）。

# 測試刻意觸發的錯誤（驗證缺圖／缺定義時的容錯）不算失敗。
EXPECTED_ERRORS="missing_part|no_such_character|test_catalog|no_such_icon|起點 987654|test_bad_cutscene|no_such_stage|no_such_sfx|test_missing_prop|test_missing_ammo|test_npc_bad|test_area_bad|no_such_pose|no_such_loop|no_such_action|npc_animations.json 沒有|action_poses.json 沒有|test_no_such_enemy|test_audio_|no_such_creature|test_no_such_feel_event|test_no_such_sound_event|test_no_such_material|test_no_such_attack|test_no_such_weapon|test_no_such_enemy|test_no_such_preset|test_no_such_window|\[FeelAB\]|\[DevMenu\]|\[StageScenes\]|\[StageActions\]|\[SoundStage\]|\[LabArena\]|body->get_space\(\)"

# （body->get_space() 那一行是某個既有測試觸發的引擎訊息，在 main 上就有。）

# 引擎結束時的資源檢查（「resources still in use at exit」「RID allocations … leaked at exit」）是關閉當下音訊執行緒還沒放掉播放實例造成的，
# 與遊戲邏輯無關、也不穩定重現，所以不算失敗；真正的腳本錯誤仍然會被抓到。
EXIT_DIAGNOSTICS="resources still in use at exit|RID allocations of type .* were leaked at exit"

# 輸出裡有沒有非預期的腳本錯誤：有就回傳 0（成功），沒有回傳 1。
has_unexpected_errors() {
	grep -E "SCRIPT ERROR|^ERROR:|Parse Error" "$1" | grep -vE "$EXIT_DIAGNOSTICS" | grep -vqE "$EXPECTED_ERRORS"
}

# 已知失敗清單（tests/known_failures.txt）：回傳 0 代表這個失敗訊息在清單裡。
is_known_failure() {
	grep -vE '^\s*(#|$)' tests/known_failures.txt 2>/dev/null | grep -qxF -- "$1"
}
