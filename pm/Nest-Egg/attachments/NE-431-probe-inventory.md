# NE-431 探針盤點（2026-11-28）

`tools/*probe*.tscn` 與 `tests/probes/*.tscn` 共 143 支；在 CI 或有執行器（`tools/run_*.py`）的 26 支，兩邊都沒有的 117 支。

## 已補進挑選規則與 CI

- `tools/run_ch4_save_chain.py`：第四章存檔鏈（Atropos 競技場寫檔 → 另開程序冷啟動、回到安全臺、拿原帳），涵蓋 `tools/ch4_atropos_probe.tscn` 與 `tools/ch4_ledger_probe.tscn`（以及它們繼承的接線廊、工作帶、安全臺探針）。挑選規則現在也認得 `res://tools/chN_*_probe.tscn`。

## 章節流程與存檔鏈（建議之後逐章補執行器，和第四章一樣一章一支）

- `tools/ch1_flow_probe.tscn`
- `tools/ch1_maintenance_probe.tscn`
- `tools/ch2_flow_probe.tscn`
- `tools/ch2_handoff_probe.tscn`
- `tools/ch2_resume_probe.tscn`
- `tools/ch3_flow_probe.tscn`
- `tools/ch3_handoff_probe.tscn`
- `tools/ch3_resume_probe.tscn`
- `tools/ch4_archive_probe.tscn`
- `tools/ch4_atropos_portrait_probe.tscn`
- `tools/ch4_factory_probe.tscn`
- `tools/ch4_homecoming_probe.tscn`
- `tools/ch4_relay_probe.tscn`
- `tools/ch4_sunday_replay_probe.tscn`
- `tools/ch4_sweep_probe.tscn`
- `tools/ch4_ward_letter_probe.tscn`
- `tools/ch4_ward_probe.tscn`
- `tools/ch4_work_lane_probe.tscn`
- `tools/ch5_flood_memory_probe.tscn`
- `tools/ch5_gray_wage_probe.tscn`
- `tools/ch5_ledger_call_probe.tscn`
- `tools/ch5_shelf_probe.tscn`
- `tools/ch5_voice_lock_probe.tscn`
- `tools/ch6_approach_probe.tscn`
- `tools/ch6_lamp_control_probe.tscn`
- `tools/ch6_rain_route_probe.tscn`
- `tools/ch6_relay_water_probe.tscn`
- `tools/ch6_studio_trial_probe.tscn`

## tests/probes 底下沒有執行器的流程檢查（建議補進既有執行器或新開執行器）

- `tests/probes/clinic_original.tscn`
- `tests/probes/isolation_completion.tscn`
- `tests/probes/janus_completion.tscn`
- `tests/probes/prologue_original.tscn`
- `tests/probes/retry_flow.tscn`
- `tests/probes/rig_crouch_feet_invalid.tscn`
- `tests/probes/story_contract_audit.tscn`

## 原生畫面、量測與單次驗證工具（要視窗或 GPU，不適合放進無頭 CI；維持手動或在票上跑）

- `tools/bg31_main_lifecycle_probe.tscn`
- `tools/bg31_repaired_production_canvas_probe.tscn`
- `tools/bg47_native_probe.tscn`
- `tools/bg48_grounded_readability_probe.tscn`
- `tools/bg48_related_readability_probe.tscn`
- `tools/bg49_held_pool_probe.tscn`
- `tools/bg49_held_readability_probe.tscn`
- `tools/bg49_world_readability_probe.tscn`
- `tools/bg55_enemy_action_probe.tscn`
- `tools/bg55_enemy_readability_probe.tscn`
- `tools/camera_walk_probe.tscn`
- `tools/capture_precision_probe.tscn`
- `tools/cinematic_framing_probe.tscn`
- `tools/cinematic_resume_probe.tscn`
- `tools/codex_replay_probe.tscn`
- `tools/contextual_ui_probe.tscn`
- `tools/controller_recovery_probe.tscn`
- `tools/dash_silhouette_native_probe.tscn`
- `tools/enemy_glow_probe.tscn`
- `tools/enemy_glow_probe_selftest.tscn`
- `tools/environment_motion_probe.tscn`
- `tools/environment_probe.tscn`
- `tools/environment_steam_probe.tscn`
- `tools/fixture_states_probe.tscn`
- `tools/frame_time_probe.tscn`
- `tools/framing_probe.tscn`
- `tools/free_encounter_native_probe.tscn`
- `tools/harbor_lamplighter_demo_probe.tscn`
- `tools/harbor_readability_probe.tscn`
- `tools/interaction_holster_probe.tscn`
- `tools/lamp_flicker_probe.tscn`
- `tools/light_pool_probe.tscn`
- `tools/maul_attachment_probe.tscn`
- `tools/melee_art_probe.tscn`
- `tools/melee_module_probe.tscn`
- `tools/melee_resume_probe.tscn`
- `tools/melee_sound_probe.tscn`
- `tools/ne222_cutscene_fill_probe.tscn`
- `tools/ne222_light_energy_probe.tscn`
- `tools/ne248_natural_core_probe.tscn`
- `tools/ne251_wake_probe.tscn`
- `tools/ne267_guest_scene_probe.tscn`
- `tools/ne268_native_contact_probe.tscn`
- `tools/ne277_contact_probe.tscn`
- `tools/ne277_delivery_probe.tscn`
- `tools/ne277_feedback_probe.tscn`
- `tools/ne277_gait_handoff_probe.tscn`
- `tools/physics_rate_probe.tscn`
- `tools/pickup_settlement_probe.tscn`
- `tools/play_input_frame_probe.tscn`
- `tools/prefetch_lifetime_probe.tscn`
- `tools/prologue_play_probe.tscn`
- `tools/prologue_replay_probe.tscn`
- `tools/prologue_resume_probe.tscn`
- `tools/quest_map_perf_probe.tscn`
- `tools/quest_map_probe.tscn`
- `tools/quest_resume_probe.tscn`
- `tools/quest_route_resume_probe.tscn`
- `tools/radio_durable_probe.tscn`
- `tools/radio_freeze_probe.tscn`
- `tools/radio_tune_probe.tscn`
- `tools/readability_phase_probe.tscn`
- `tools/rig_perf_probe.tscn`
- `tools/route_frame_time_probe.tscn`
- `tools/route_walk_probe.tscn`
- `tools/run_continuity_probe.tscn`
- `tools/run_save_probe.tscn`
- `tools/run_save_ui_probe.tscn`
- `tools/scene_motion_probe.tscn`
- `tools/story_durable_write_probe.tscn`
- `tools/sway_region_probe.tscn`
- `tools/test_bg55_probe_controls.tscn`
- `tools/test_contrast_probe_geometry.tscn`
- `tools/texture_route_probe.tscn`
- `tools/training_art_probe.tscn`
- `tools/vfx_exposure_probe.tscn`
- `tools/wall_shadow_probe.tscn`
- `tools/weapon_balance_probe.tscn`
- `tools/weapon_guard_probe.tscn`
- `tools/weapon_light_probe.tscn`
