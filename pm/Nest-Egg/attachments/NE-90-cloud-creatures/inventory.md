# NE-90 非人形固定基線盤點（未完成驗收）

| 模型 | Runtime | 正式 Enemy 掛載 | 實際狀態 | 部件／鏈 | 結果 |
|---|---|---|---|---|---|
| bomber | PartCreature | data/enemies/bomber.tres | idle, chase, fuse | 7 | 未驗：解剖、逐格接縫、實機 |
| buoy_worm | ChainCreature | data/enemies/buoy_worm.tres, data/enemies/buoy_worm_small.tres | idle, walk, swell, spit, dead | 6 | 未驗：解剖、逐格接縫、實機 |
| cloud_jelly | ChainCreature | data/enemies/cloud_jelly.tres | idle, drift, charge, discharge, dead | 6 | 未驗：解剖、逐格接縫、實機 |
| cloud_serpent | WormCreature | data/enemies/cloud_serpent.tres | idle, lurk, rumble, erupt, dive, dead | 0 | 未驗：解剖、逐格接縫、實機 |
| drone | PartCreature | data/enemies/drone.tres | idle, hover, lock, dive, climb | 3 | 未驗：解剖、逐格接縫、實機 |
| mimic | PartCreature | data/enemies/mimic.tres | idle, dormant, shake, lunge, recover, exposed, shake_open | 2 | 未驗：解剖、逐格接縫、實機 |
| rail_cannon | PartCreature | data/enemies/rail_cannon.tres | idle, slide, track, lock, dead | 2 | 未驗：解剖、逐格接縫、實機 |
| repair_drone | PartCreature | data/enemies/repair_drone.tres | idle, follow, channel | 3 | 未驗：解剖、逐格接縫、實機 |
| salvage_arm | ChainCreature | data/enemies/salvage_arm.tres | idle, alert, walk, sweep_windup, sweep, slam_windup, slam, dead, exposed | 6 | 未驗：解剖、逐格接縫、實機 |
| searchlight_drone | PartCreature | data/enemies/searchlight_drone.tres | idle, patrol, spot, alarm, unpowered, reboot | 3 | 未驗：解剖、逐格接縫、實機 |
| shaft_bat | PartCreature | data/enemies/shaft_bat.tres | idle, hover, lock, dive, climb, glide, turn, dizzy, dead | 3 | 未驗：解剖、逐格接縫、實機 |
| shock_hound | PartCreature | data/enemies/shock_hound.tres | idle, prowl, circle, growl, pounce, recover | 2 | 未驗：解剖、逐格接縫、實機 |
| swarm_bee | PartCreature | data/enemies/swarm_bee.tres | fly, buzz, sting, recover, dead | 1 | 未驗：解剖、逐格接縫、實機 |
| tangle_wire | ChainCreature | data/enemies/tangle_wire.tres | idle, hidden, warn, lash, retract, dead | 5 | 未驗：解剖、逐格接縫、實機 |
| test_creature | ChainCreature |  | idle, alert, crawl, lash | 5 | 未驗：解剖、逐格接縫、實機 |
| turret | PartCreature | data/enemies/turret.tres | idle, track, lock | 3 | 未驗：解剖、逐格接縫、實機 |
| wall_gecko | PartCreature | data/enemies/wall_gecko.tres | idle, crawl, hang, windup, leap, land, dead | 1 | 未驗：解剖、逐格接縫、實機 |

watchdog：FAIL，rig_skin=warden，人形替身，NE218已存在。
shock_hound：FAIL（四腳動畫資料覆蓋），body/tail兩件、gait.legs=[]；外觀肢數另看來源，不以資料推定。
test_creature：測試fixture，無正式Enemy掛載，不當作已交付模型。

完整部件帳本、原始JSON、RGBA原生尺寸、alpha bbox（只計alpha非零）、source SHA、掛點／父鏈／z／gait、全caller與原票Commit見inventory.json。
PNG和資料檢查不是Godot截圖、解剖或逐格通過。未驗項不代勾。
