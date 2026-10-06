# 素材來源目錄

2026-10-04 調查結果。所有來源都是 CC0；完整清單（作者、頁面、下載連結）在 `assets_src/audio/manifest.json`，下載用 `tools/audio/fetch_audio.py`，加工用 `tools/audio/build_audio.py`（見 `.claude/skills/audio-pipeline`）。實際進遊戲的素材登記在 `assets_src/audio/LICENSES.json`。

**調查是靠頁面標籤與訊號分析，沒有人逐檔聽過**；挑檔案時先用 `tools/audio/inspect_audio.py` 看特徵，換入後在音效實驗室試聽。

## 音效：類別 → 候選素材包

| 類別 | 候選素材包（前三） |
|---|---|
| 手槍槍聲（gunshot_pistol） | oga_the-free-firearm-sound-library、oga_gunshots、oga_gunshot-sound-effect |
| 步槍槍聲（gunshot_rifle） | oga_the-free-firearm-sound-library、oga_gunshot-sounds |
| 衝鋒槍槍聲（gunshot_smg） | oga_the-free-firearm-sound-library、oga_action-gameshmup-sfx-pack |
| 霰彈槍聲（gunshot_shotgun） | oga_the-free-firearm-sound-library、oga_gunshot-sounds |
| 狙擊槍聲（gunshot_sniper） | oga_the-free-firearm-sound-library、oga_gunshot-sounds |
| 敵方通用槍聲（gunshot_enemy_generic） | oga_the-free-firearm-sound-library、oga_hollywood-style-pistol-silencer-sound-effect、oga_gunshots |
| 消音槍聲（gunshot_silenced） | oga_hollywood-style-pistol-silencer-sound-effect、oga_the-free-firearm-sound-library |
| 發射器／火箭（gunshot_launcher） | oga_cannon-fire、oga_action-gameshmup-sfx-pack、oga_50-cc0-sci-fi-sfx |
| 能量武器（gunshot_energy） | kenney_sci-fi-sounds、oga_action-gameshmup-sfx-pack |
| 軌道砲（gunshot_railgun） | oga_action-gameshmup-sfx-pack、oga_electricity-game-sound-pack、kenney_sci-fi-sounds |
| 光束持續音（beam_loop） | oga_action-gameshmup-sfx-pack、oga_electricity-game-sound-pack |
| 重砲（gunshot_heavy_cannon） | oga_cannon-fire、oga_cannon-hit、oga_action-gameshmup-sfx-pack |
| 彈匣取出／裝入（gun_magazine） | oga_gun-reload-sound-effects、oga_gun-reload-sounds、oga_handgun-reload-sound-effect |
| 拉栓／滑套（gun_bolt_slide） | oga_shotgun-reload-sound-effects、oga_gun-reload-sounds、oga_gun-reload-sound-effects |
| 換彈完成（gun_reload_finish） | oga_gun-reload-lock-or-click-sound、oga_shotgun-reload-sound-effects、oga_equipment-click |
| 空槍（gun_dryfire） | oga_equipment-clicks-ii、oga_10-clicks-and-switches、oga_7-mechanical-clicks-and-buzzes |
| 彈殼落地（gun_shell_casing） | oga_68-workshop-sounds、oga_100-cc0-sfx-2 |
| 命中：肉（impact_flesh） | oga_impact、oga_ripping-into-meat、oga_8-wet-squish-slurp-impacts |
| 命中：護甲（impact_armor） | kenney_impact-sounds、oga_75-cc0-breaking-falling-hit-sfx |
| 命中：金屬（impact_metal） | kenney_impact-sounds、oga_100-cc0-metal-and-wood-sfx |
| 命中：混凝土（impact_concrete） | kenney_impact-sounds、oga_75-cc0-breaking-falling-hit-sfx、oga_impact |
| 命中：玻璃（impact_glass） | kenney_impact-sounds、oga_75-cc0-breaking-falling-hit-sfx |
| 命中：木（impact_wood） | kenney_impact-sounds、oga_100-cc0-metal-and-wood-sfx、oga_impact |
| 命中：能量（impact_energy） | oga_electricity-game-sound-pack、oga_electricity-sound-effects-0、kenney_sci-fi-sounds |
| 跳彈／彈道（ricochet_whiz） | oga_action-gameshmup-sfx-pack、oga_4-metal-dingsrings、oga_100-cc0-sfx-2 |
| 倒地（body_fall） | oga_12-wet-towel-hittingfallingpunching-floor-sounds、oga_40-wet-towel-clubpoundhitattack-sounds、kenney_impact-sounds |
| 弱點叮聲（crit_ding） | kenney_impact-sounds、oga_4-metal-dingsrings、oga_68-workshop-sounds |
| 小爆炸（explosion_small） | oga_explosions-4、oga_25-cc0-bang-firework-sfx、oga_dull-explosion |
| 大爆炸（explosion_large） | oga_action-gameshmup-sfx-pack、oga_explosions-4、kenney_sci-fi-sounds |
| 火焰（fire_flame_loop） | oga_fire-crackling、oga_synthesized-fire-sound-effect、oga_flare-ignition |
| 電弧（electric_zap_arc） | oga_electricity-sound-effects-0、oga_electric-buzz、oga_electricity-game-sound-pack |
| EMP／斷電／復電（emp_power_down_up） | oga_electricity-game-sound-pack、oga_machine-shutting-down、kenney_digital-audio |
| 警報（alarm） | oga_alarm-sound-effect、oga_alarm-1、oga_alarm-2 |
| 警笛（siren） | oga_sirens-and-alarm-noise、oga_storm-siren、oga_short-alarm |
| 終端機嗶聲（beeps_terminal） | oga_50-cc0-sci-fi-sfx、oga_platformer-sounds-terminal-interaction-door-shots-bang-and-footsteps |
| 伺服馬達（servo_motor） | oga_defect-motor-loop、oga_68-workshop-sounds、oga_chain-winch-sounds |
| 無人機懸停（drone_hover） | oga_hovermobile-sfx、oga_sci-fi-vehicle-sound、kenney_sci-fi-sounds |
| 近戰輕揮（melee_swing_light） | oga_swishes-sound-pack、oga_swish-bamboo-stick-weapon-swhoshes |
| 近戰重揮（melee_swing_heavy） | oga_swish-bamboo-stick-weapon-swhoshes、oga_air-whoosh、oga_20-sword-sound-effects-attacks-and-clashes |
| 刀刃命中（melee_blade_hit） | oga_20-sword-sound-effects-attacks-and-clashes、oga_80-cc0-rpg-sfx、kenney_rpg-audio |
| 鈍擊命中（melee_blunt_hit） | oga_punch、oga_thwack-sounds、kenney_impact-sounds |
| 格擋鏗（melee_parry_clang） | oga_20-sword-sound-effects-attacks-and-clashes、oga_33-metal-clang-sounds-cast-iron-pans、oga_metal-clang-sounds |
| 護盾破碎（shield_break） | oga_electricity-game-sound-pack、oga_75-cc0-breaking-falling-hit-sfx |
| 腳步：金屬（footstep_metal） | oga_metal-footsteps-on-concrete |
| 腳步：混凝土（footstep_concrete） | kenney_impact-sounds、oga_fantozzis-footsteps-grasssand-stone |
| 腳步：潮濕（footstep_wet） | oga_100-cc0-sfx-2、oga_40-cc0-water-splash-slime-sfx、oga_water-splash-and-sand-footsteps |
| 腳步：木頭（step_wood） | fs_cc0-steps-wood（Freesound CC0，擷取單步） |
| 腳步：泥土草地（step_dirt） | fs_cc0-steps-ground（Freesound CC0，擷取單步） |
| 跳躍落地（jump_land） | oga_jump-landing、oga_jump-and-run-and-stand、oga_playersounds-1-by-emopreben |
| 衝刺／滑行（dash_slide） | oga_air-whoosh、oga_swishes-sound-pack、oga_68-workshop-sounds |
| 衣物聲（cloth_movement） | kenney_rpg-audio、oga_scorchers-foley-sounds |
| 受傷痛呼（hurt_grunt） | oga_pain-sounds-by-emopreben、oga_15-vocal-male-strainhurtpainjump-sounds |
| 死亡（death） | oga_male-dead-voice、oga_5-hit-sounds-dying、oga_hurt-death-sound-effect-for-character |
| 機械損壞／死亡（robot_damage_death） | oga_electricity-game-sound-pack、oga_machine-shutting-down、kenney_sci-fi-sounds |
| 生物吼叫（creature_growl） | oga_16-monster-growls、oga_monster-snarls |
| 生物啃咬（creature_chomp） | oga_crunchy-bite、oga_80-cc0-creature-sfx、oga_hungry-ghoul |
| 門（door） | kenney_sci-fi-sounds、oga_door-open-door-close |
| 閘門／捲門（gate_shutter） | oga_iron-door、oga_chain-winch-sounds、oga_100-cc0-metal-and-wood-sfx |
| 開關／拉桿（switch_lever_button） | oga_10-clicks-and-switches、oga_100-cc0-sfx-2、oga_button-sfx-pack-iii-assortment-ot-hi-tech |
| 木箱破壞（crate_wood_break） | oga_75-cc0-breaking-falling-hit-sfx、oga_100-cc0-metal-and-wood-sfx |
| 玻璃破碎（glass_break） | oga_glass-break、oga_75-cc0-breaking-falling-hit-sfx、oga_100-cc0-sfx |
| 拾取／金幣（pickup_coin_item） | kenney_rpg-audio、oga_80-cc0-rpg-sfx、oga_100-cc0-sfx-2 |
| 電話鈴聲（telephone_ring） | oga_crank-movie-telephone-ringtone、oga_modern-ringtone-chirptone、oga_doorbell |
| 終端機（terminal_beeps） | oga_50-cc0-sci-fi-sfx、oga_button-sfx-pack-iii-assortment-ot-hi-tech |
| 環境：雨（amb_rain） | oga_amb-rain-loop-1、oga_rain-loopable、oga_rain-gutter-loop |
| 環境：雷（amb_thunder） | oga_rain-long-thunder、oga_100-cc0-sfx-2、oga_muffled-distant-explosion |
| 環境：風（amb_wind） | oga_wind1、oga_mild-wind-background-noise |
| 環境：夜城（amb_city_night） | oga_scifi-city-ambient-loop、oga_100-cc0-sfx-2、oga_high-traffic-road-sounds |
| 環境：機房（amb_machine_room） | oga_sci-fi-ambience-sfx、oga_100-cc0-sfx-2、oga_steam-boiler-sound-loop |
| 環境：電流嗡鳴（amb_electrical_buzz） | oga_electric-buzz、oga_static、oga_7-mechanical-clicks-and-buzzes |
| 環境：滴水（amb_drip） | oga_dripping-water-loop、oga_100-cc0-sfx-2、oga_30-cc0-sfx-loops |
| 環境：人群（amb_crowd） | oga_crowd-shoutingspeaking-ambience、oga_scifi-city-ambient-loop |
| 環境：通風（amb_ventilation） | oga_30-cc0-sfx-loops、oga_dark-ambiences、oga_low-rumbling |
| 介面：點擊（ui_click） | kenney_interface-sounds、kenney_ui-audio |
| 介面：確認（ui_confirm） | kenney_interface-sounds |
| 介面：取消（ui_cancel） | kenney_interface-sounds |
| 介面：錯誤（ui_error） | kenney_interface-sounds |
| 介面：選單移動（ui_menu_move） | kenney_ui-audio、kenney_interface-sounds |
| 介面：開關視窗（ui_open_close） | kenney_interface-sounds |

## 音效：缺口（沒有專用的 CC0 素材）

- telephone: dial tones, handset pick-up and hang-up (only ringtones/doorbell found)
- bullet ricochet / whiz-by: no dedicated CC0 pack found (candidates are metal pings to be pitch-swept)
- cloth movement: only Kenney RPG cloth/leather foley; no heavy jacket/armor rustle
- silenced rifle shot: only one pistol silencer sample; suppression can be faked with low-pass on Firearm Library mid-distance shots
- railgun / heavy energy cannon: no dedicated realistic recording; combine charge-up (electricity pack) + low blast (Kenney explosionCrunch) + laser beam
- grenade/rocket launcher: only cannon fire, rocket launch whoosh and big sound-designed shots; no realistic launcher recording
- robot/machine voice-free damage and death: assembled from electricity/mechanical packs, nothing purpose-recorded
- vending machine specific sounds; crowd murmur without speech (only a shouting/speaking crowd and a cyber-city bed)
- flamethrower: only fire crackle/ignite/gas hiss textures, no real flamethrower loop

缺口的處理：用相近素材加工（降頻、濾波、疊層），或保留原本的合成音；實際處理方式記在換入該類音效的票上。

## 音樂：各用途的候選曲目數

| 用途 | 候選曲目數 | 代表曲目 |
|---|---|---|
| 主選單 | 4 | zanindevelopers_cyberpunk-menu-music、bubble5297_main-menu-dark、ruskerdax_pondering-the-cosmos |
| 平靜探索 | 14 | ruskerdax_pondering-the-cosmos、tarush-singhal_cyberpunk-beauty、tsorthan-grove_lights-at-night |
| 緊張／工業 | 39 | cinameng_dark-city、cinameng_mirrorshade__mirrorshade_1、cinameng_mirrorshade__mirrorshade_2_0 |
| 戰鬥 | 21 | ruskerdax_savage-ambush、mintodog_hard-dungeon、joth_the-9th-circle |
| 頭目 | 10 | mintodog_hard-boss-battle-1、mintodog_hard-boss-battle-2、mintodog_heavy-boss-battle-1 |
| 安全區 | 16 | holizna_chills、iamoneabe_dimly-lit、qubodup_chill-lofi-inspired-loop-edit |
| 劇情／情緒 | 25 | iamoneabe_cyber-march、kistol_sadness、ruskerdax_moil |
| 通關 | 5 | bobjt_victory-road、cynicmusic_victory-theme-for-rpg、umplix_victory |
| 死亡 | 16 | ruskerdax_soul-release、kistol_game-over、kistol_game-over-ii |
| 地下／水道 | 9 | yd_factory-ambiance、tozan_sewer-tunnel-ii、bobjt_sewers-beat |
| 實驗室 | 10 | ruskerdax_bleak-terminal、tsorthan-grove_corrupt-data-stream、srg774_dark-sci-fi-audio-pack__pulse_0 |
| 陽光／希望 | 6 | vitalezzz_plains-of-luminescence、kiluaboy_sunset-walk-ambient-quiet-sweet-loop、wolfgang_a-new-start-short-solo-piano |
| 屋頂 | 1 | crivain_icy-heights |

## 音樂：缺口

- Rooftop wind: only one weak candidate (icy wind loop); no cyberpunk rooftop-specific CC0 found - synthesise wind SFX layer or reuse calm ambient.
- Dedicated cyberpunk victory/chapter-clear sting: CC0 stings found are RPG/fanfare-bright; best tonal fit is srg774 victory (6 s, quiet) - consider a dark custom sting.
- Warden (machine overseer) boss: no truly industrial-machine boss track; closest are tricksntraps ai_fight, mintodog hard/heavy boss, pro-sensory dark_forces_loop. Reclaimer boss: sinister-boss-appears (45 s) and heavy boss battles.
- Story cutscene tragic with cyberpunk timbre: mostly piano/strings candidates; few synth-based tragic pieces (cinameng dark-heart, symphony donnie).
- Sci-fi lab / white tower: only quiet ambient (srg774, tozan 16 kHz); no clean sterile-lab piece.
- Quality caveat: moods judged from page tags/descriptions plus signal stats (loudness, spectral centroid, onset rate) - no one listened. Audition shortlisted tracks before committing.
- Rejected: Kenney Music Jingles (CC0 but cheerful 8-bit/pizzicato/sax/hit), chiptune/8-bit/orchestral-fantasy items, CC-BY/OGA-BY etc. Archive.org CC0 search returned mostly podcasts/uncurated items (API errors on several queries); nothing adopted from archive.org.
- Loudness varies enormously (-4 to -43 LUFS) - normalise all to a common target (e.g. -18 LUFS music bed) before use.
- Dropped for disk budget (still CC0, re-downloadable from page_url): diamond-dust main menu, safe-space loop, awestruck, T&T through_the_sewers/ai_fight/system_overload/Simulation Unknown/Experiment G, cynic sinister-boss-appears, technodono forbidden-exploration, vitalezzz downfall/realm-of-torment, section31 city-on-speed, some-weirdo complicated-feelings, isaiah658 echoes-of-the-past.

## 注意

- 音量差異很大（-4 到 -43 LUFS），一律經 `build_audio.py` 標準化後才進遊戲。
- 迴圈性質是從作者標籤與檔尾音量推測的，沒有逐首確認；接縫要在實驗室試聽。
- Firearm Library 的檔案是 96 kHz／24 bit 立體聲、5–30 秒，含長尾與連發，加工時要指定取用的時間範圍。


## 第二輪補充（NE-164）

為了讓每個位置有十個以上、而且彼此差異夠大的備選，又找了一輪：新增 271 個音效素材包（約 2,300 個檔案）與 178 首音樂。素材總數 5,258 個（見 [CATALOG.md](CATALOG.md)），位置清單的每個位置有 30 個備選。

- **授權複查**：所有來源頁面（共 734 頁）用 `tools/audio/verify_licenses.py` 重新抓取檢查，結果存在 `assets_src/audio/license_check.json`。OpenGameArt 的授權欄只能有 CC0；同時標示多種授權（例如 CC-BY 與 CC0 並列）的 11 個素材包一律剔除。
- **Internet Archive 來源**（`ia_` 開頭，52 個包，USC 的 Red Library 與 SSE Library）：授權依 archive.org 的項目 metadata（`licenseurl` 必須是 CC0 1.0）。這是 Internet Archive 管理者設定的，不像 OpenGameArt 有上傳者頁面，來源可信度略低一點；都是老式錄音（有磁帶底噪）。要更保守的話，這些素材的編號前綴相同、可從 `manifest.json` 整批移除。
- OpenGameArt 的 CC0 是上傳者自己宣告的，網站不逐檔查證。

仍然找不到的聲音（用相近素材加工，或保留合成音）：
- Telephone: no dial-tone/DTMF/busy-signal recordings found in any CC0 source (OGA, Kenney, IA). Obtained instead: rotary-dial telephone with ring, handset lift/hang-up, pay-phone-in-booth, crank phone, coin return, rings (Red Library Communications, SSE Communications, OGA Owlish phone ring). DTMF/dial tone must be synthesised (sine pairs, trivial with numpy) - recommend generating in the pipeline.
- Real modern gun-handling (magazine out/in, charging handle, selector) is still scarce: available are rifle/pistol cocking, bolt, slide breech, clip load, shotgun load, revolver spin, empty-click, shell eject, plus OGA reload/dry-fire packs; all vintage-style mechanics (no AR magazine drop). Layer metal clicks (SSE Mechanical, Kenney impact metal) for modern feel.
- Railgun / energy cannon / heavy sci-fi cannon: only sound-designed material (50 Free SciFi 192 kHz, theremin lasers, SSE sci-fi ray gun/phaser/energy). No dedicated recording; compose by layering charge-up + low blast.
- Suppressed rifle/SMG: only pistol-silencer takes (SSE Suppressed, OGA voice-made Silencers, existing hollywood silencer). Low-pass a rifle shot to fake the rest.
- Modern SMG / assault-rifle single shots are 1930s-50s era (Tommy gun, Bren, M16 burst, BAR). No modern close-mic 9mm SMG pack found.
- Bullet whiz-by: exist only inside compilations (SSE Bullets "Bullets flying overhead", "Rifle bullets flying over and hitting objects"); no isolated whiz one-shots, slice from the takes.
- Robotic voices without words: OGA "Robot Voice Pack" contained spoken phrases and was rejected/deleted; "Female/Male Alien Robot Vocal SFX" (49 MB WAV) skipped, content not verified wordless. Non-verbal robot noises come from OGA Robotic Transformations, sci-fi packs and SSE sci-fi/servo.
- Metal grating / wet pavement footsteps: only metal stairs, tunnel, water, gravel, tile, stone, hard surface (Red Footsteps, OGA snow-and-gravel, Owlish). No explicit grating or wet-pavement recording; water-walking + metal-stairs are the nearest. Rooftop gravel is well covered.
- Seamless ambience loops: most new beds are linear recordings (not authored loops); loop points must be found/crossfaded in the pipeline. Authored loops: OGA airvent-loop, fridge-loop-1, crickets-ambient-noise-loopable, rain-on-window-loop, wind-whoosh-loop, seamless-energy-emission-loop, loopable-dungeon-ambience, SSE "loopable" sci-fi computer/space-ship beds. Machine-room hum and generator ambience exist (SSE Machines, SSE Motors generator, OGA industrial-fan/lab-ambience); a true city-night bed is weak (traffic + urban room tone only, vintage).
- Crowd murmur without words: only walla beds from SSE Ambience (hotel lobby, cafe, courtroom murmur) - vintage, contain indistinct speech; no clean wordless murmur.
- Five planned IA files returned persistent HTTP 500 on every format and were not obtained (SSE Weapons: arrows fly & hit, five arrows whoosh, crossbow load/shot; Red Footsteps 1: hard tile floor; Red Guns Machine: machine gun with reverb).

音樂仍然薄弱的用途：
- Victory / chapter-clear stings: only ~10 new, almost all very short (2-17 s) bright or RPG-flavoured fanfares (church-organ fanfare, cynic fanfare, SterlingRay finish-line piano stinger are the most restrained). CC0 on OGA has essentially no dark cyberpunk victory sting; a custom one is still the realistic route.
- Defeat / game-over: 8 new (all short; several are chiptune-tinged or piano/horror stings: NBJD game-over is distorted chiptune). Together with the 16 from round 1 this is adequate.
- Industrial / factory / machine rhythm: no dedicated new CC0 industrial-rhythm tracks beyond Abandoned Steel Mill (Spring Spring), section31 Tunnel Drilling/Going Deep and the cinameng dub-techno loops; still thin. Ruskerdax 'Scaling Up' (factory, 24 MB flac) was skipped for size.
- Hunter-flavoured boss: new boss pool is mostly sci-fi electronic / metal / MintoDog trance; nothing organic-predator specific besides vitalezzz Hunter-class Lifeform (horror action) and Umplix Hunted by the Evil (26 s).
- Rooftop wind and rain: only ~6 tracks contain actual rain/wind/thunder texture (kindland rain-and-thunders, Tsorthan dirty_rain_loop, Rizy sleep music, A_Thor Mysterious Winds, wipics Winter Wind, iamoneabe Thunderous Fall, Birds-and-Wind, west-winds storm version); the rest are cold/stormy-mood ambient. Layering a synthesized wind/rain SFX bed is still advisable.
- Sci-fi lab / sterile white tower: new picks are space/ambient and cinameng soundscapes; no truly clean 'sterile lab' piece found, mood is approximated.
- Menu: 18 new candidates but few are both slow AND dark AND long; best fits: Tsorthan dirty_rain/The World Fell Silent pack, Stumpystrust Longing for a Lost Feeling, GboxMikeFozzy Title Screen Loop, EmoPreben Horror, vitalezzz Celestial Harmony. Many cinameng items are 8-60 s loop fragments.
- Quality caveat: moods and uses were judged from page tags/descriptions plus signal stats (LUFS, spectral centroid, onset rate, tail level); nothing was auditioned by ear, so shortlist before wiring in.
- Loudness varies from -7 to -48 LUFS (cinameng Rakish -48, Tozan garden tunes -30..-37); normalise on import.
- Rejected by the hard CC0 rule: ~140 OGA pages carrying CC0 together with CC-BY / OGA-BY / GPL / CC-BY-SA (dual-licensed, treated as ambiguous) were skipped. Chiptune/8-bit/midi/cartoon/fantasy-orchestral/cheerful pages were filtered by tags; very large WAV/FLAC (>9 MB, e.g. Umplix wavs, The Oracle metal albums, Holizna collections, Yoiyami) skipped for the download budget but remain CC0 and re-downloadable.
- archive.org and kenney.nl were not re-searched this round (round 1 found nothing usable there).
