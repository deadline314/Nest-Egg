# NE-95 實玩審查交接

沿用既有圖集、粒子場、Fx 及死亡演出，不重新生成或改系統。Forward+ 截圖與腳本事件驗证屬於可重現的審查材料，不等於使用者實玩一輪，也不等於在 25 個 profile 上都完成人工泛光審查。

| 項目 | 實玩時觀察 | 可重現來源 |
|---|---|---|
| 槍口 | 短閃可辨識槍線，沒有遮掉目標 | player_fx 的手槍／步槍／榴彈 |
| 命中 | 火花位置貼合接觸點，顏色與敵人類型可區分 | light_audit 真子彈受擊 |
| 格擋／反彈 | 一般格擋與成功反彈可分辨，盾面閃光不遮敵方下一發 | player_fx block/parry 連續畫面 |
| 死亡 | 0.05／0.2／0.5／0.9 秒有連續消散，殘留不遮平台 | enemy_vfx grunt／warden／shock_hound |
| 爆炸 | 核心短，火球／煙迅速退場，後續目標可辨識 | light_audit launcher 彈道／負載；barrel-only 真實油桶爆炸 |
| 雨 | 保持景深，彈道與危險物仍可辨認 | 第一章實景 screenshots |
| 蒸汽 | 預警抖動與噴發時機自然，蒸汽不遮敵人整個攻擊窗口 | player_fx vent_warning／burst |

玩家應在第一章市集與設施入口、第二章升降井及回收燈幕，分低／中／高檔實玩上述事件；有實體 GPU 才能確認實機泛光觀感與性能。角色曝亮由 NE-222／Session 1 處理，不能為遮掩角色問題改回共用光影或全面減弱 VFX。

性能紀錄與截圖分兩次跑；計時關閉 capture，固定 seed／解析度／敵人数／武器／warmup，無生成／其他截圖／大量測試。純腳本事件或 time_scale 慢播的圖片只作視覺審查，不作效能數據。


## 本次實作與原生重現

- 衝擊波的 PlaceholderTexture2D 在本機原生 Forward+ 只提供部分 UV，環形 shader 變成偏移的四分之一圓弧。`tools/shock_ring_review.tscn` 在同畫面、同 shader／progress／geometry 對照：左舊 Placeholder，右真正的 ShockRing。只將 carrier 改成一次建立、全環池共用的 2×2 ImageTexture（RGBA8 像素 payload 16 bytes，不等於專用 GPU 配置量）；池容量、shader、配方、Atlas 不變，play 不建立新節點或貼圖。
- `player_fx`／`enemy_vfx` 支援 `--lighting`、`--quality`、`--slow`；慢播只作視覺檢查，結束還原設定。`player_fx --environment-only` 的蒸汽預警與噴發都核對真正狀態；舊腳本預警點已經噴發，修正取樣，沒有改遊戲蒸汽時機。
- `player_fx --barrel-only` 用真正 Breakable.hit_by_projectile 擊破油桶，經現有延遲爆炸及雙陣營傷害路徑，拍 0.15／0.22／0.4／0.75 遊戲秒；不把飛行榴彈圖當成爆炸峰值。
- `light_audit --no-capture` 另跑性能，使用固定 seed95／未縮放 Time.get_ticks_usec 牆鐘（包括 stalls），記錄 level／tile／quality；不將截圖寫入或慢播樣本當性能證據。原生截圖與計時工作用共享鎖序列化。

重現：Godot 4.7、Forward+、相同品質／profile，Linux 使用 xvfb-run。真實兩章完整環境見 BG-17 與 NE-66；此處 player_fx／死亡／油桶是遊戲 Level 測試場地，light_audit 則是真實第一章市集，兩者明確區分。

```sh
python tools/comfyui/gpu_lock.py -- "$GODOT" --audio-driver Dummy --resolution 640x360 --rendering-method forward_plus res://tools/shock_ring_review.tscn
python tools/comfyui/gpu_lock.py -- "$GODOT" --audio-driver Dummy --resolution 640x360 --rendering-method forward_plus res://tools/screenshot.tscn -- --scenario=player_fx --lighting=market --quality=high --slow=0.5 --out=<絕對輸出目錄>
python tools/comfyui/gpu_lock.py -- "$GODOT" --audio-driver Dummy --resolution 640x360 --rendering-method forward_plus res://tools/screenshot.tscn -- --scenario=player_fx --lighting=market --quality=high --slow=0.5 --barrel-only --out=<另一絕對目錄>
python tools/comfyui/gpu_lock.py -- "$GODOT" --audio-driver Dummy --resolution 640x360 --rendering-method forward_plus res://tools/screenshot.tscn -- --scenario=enemy_vfx --lighting=blackout --quality=high --slow=0.5 --enemies=grunt,warden,shock_hound --times=0.05,0.2,0.5,0.9 --out=<另一絕對目錄>
```

本次修正有原生圖支持的衝擊波退化、雙陣營爆炸曝光與取樣；沿用 PARTICLE_SCALE=.5、FLARE_SCALE=.7、SHOCK_SCALE=.55，不改全局光影／角色曝亮參數。局部白熱中心不是整屏無條件通過；需要使用者在兩章不同敵人／燃料槽與所有 profile 實玩，确认是否遮擋下一發和危險物。測試的 25 profile 亮度預算不等於人工泛光驗收。

雙陣營油桶保留兩份傷害節點，但節點不再疊畫舊的平面圓盤；原 Fx 配方連同 flash／環境閃光／shake／Sfx 去重為一次。回歸測試驗證玩家與敵人仍都受傷，並只收到一次環境閃光。油桶修後圖使用此最終版本，不把移除舊圓盤說成生成了新的火球素材。
