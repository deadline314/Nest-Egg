"""Write art/vfx/enemies/<enemy>.json from the table below (one file per enemy; edit the JSON afterwards, this script is only the first draft).

    python tools/gen_enemy_vfx.py
"""
import json
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / "art/vfx/enemies"


def B(c, a, s, l):
    return {"color": c, "amount": a, "speed": s, "life": l}


def L(c, r, e, t):
    return {"color": c, "radius": r, "energy": e, "time": t}


E = {
    "grunt": dict(step=dict(every=22, dust=2, spread=22, shake=0.0), hit=dict(color="#ffb060", amount=6, speed=180, light=0.8),
                  death=dict(bursts=[B("#ffa050", 14, 170, 0.4), B("#c8d4e4", 6, 90, 0.5)], light=L("#ffa050", 64, 1.1, 0.22), shake=2.2, hitstop=0.03, extras=["dust"]),
                  states={"aim": dict(at="muzzle", light=L("#ffa050", 36, 0.9, 0.15))}),
    "elite_grunt": dict(step=dict(every=26, dust=1, spread=16, shake=0.0), hit=dict(color="#ff7040", amount=7, speed=200, light=1.0),
                        death=dict(bursts=[B("#ff7a1a", 18, 200, 0.45), B("#506080", 8, 110, 0.55)], light=L("#ff7a1a", 74, 1.4, 0.26), shake=2.8, hitstop=0.04, extras=["dust", "embers"]),
                        states={"aim": dict(at="muzzle", light=L("#ff7a1a", 44, 1.2, 0.14))}),
    "sniper": dict(step=dict(every=34, dust=1, spread=10, shake=0.0), hit=dict(color="#ff2a3d", amount=5, speed=150, light=0.7),
                   death=dict(bursts=[B("#ff2a3d", 10, 130, 0.5)], light=L("#ff2a3d", 60, 1.0, 0.35), shake=1.6, hitstop=0.02, extras=["smoke"]),
                   states={"lock": dict(at="muzzle", bursts=[B("#ff2a3d", 6, 60, 0.3)], light=L("#ff2a3d", 50, 1.8, 0.3))}),
    "flamer": dict(step=dict(every=20, dust=3, spread=26, shake=0.25, spark=1, spark_color="#ff8a1a"), hit=dict(color="#ff8a1a", amount=8, speed=130, kind="smoke", light=0.9),
                   death=dict(bursts=[B("#ff8a1a", 22, 150, 0.7), B("#ffd070", 10, 220, 0.35)], light=L("#ff8a1a", 96, 1.8, 0.4), shake=3.0, hitstop=0.04, extras=["embers", "smoke"]),
                   states={"ignite": dict(at="muzzle", bursts=[B("#ffd070", 8, 80, 0.3)], light=L("#ff8a1a", 54, 1.4, 0.35)),
                           "burn": dict(at="muzzle", light=L("#ff6a10", 90, 2.0, 0.5), shake=0.8)}),
    "mortar": dict(step=dict(every=28, dust=2, spread=18, shake=0.0), hit=dict(color="#ffa31a", amount=6, speed=160, light=0.8),
                   death=dict(bursts=[B("#ffa31a", 16, 190, 0.45), B("#5a5a48", 10, 100, 0.6)], light=L("#ffa31a", 70, 1.3, 0.28), shake=2.4, hitstop=0.03, extras=["smoke", "dust"]),
                   states={"aim": dict(at="feet", dust=3, spread=20)}),
    "shield_rusher": dict(step=dict(every=18, dust=3, spread=34, shake=0.5, spark=1, spark_color="#ffd000"), hit=dict(color="#ffd000", amount=5, speed=210, kind="arc", light=1.0),
                          death=dict(bursts=[B("#ffd000", 14, 200, 0.4), B("#2a3a60", 8, 120, 0.5)], light=L("#ffd000", 70, 1.3, 0.25), shake=3.0, hitstop=0.05, extras=["dust", "arc"]),
                          states={"windup": dict(at="feet", dust=3, spread=16, shake=0.4),
                                  "charge": dict(at="feet", dust=6, spread=50, shake=1.2, bursts=[B("#ffd000", 6, 120, 0.25)]),
                                  "dazed": dict(bursts=[B("#35e0ff", 8, 100, 0.4)])}),
    "heavy_gunner": dict(step=dict(every=26, dust=3, spread=30, shake=0.9), hit=dict(color="#ff2e88", amount=4, speed=120, light=0.6),
                         death=dict(bursts=[B("#ff2e88", 20, 160, 0.55), B("#3a3e48", 14, 90, 0.7)], light=L("#ff2e88", 90, 1.6, 0.35), shake=4.0, hitstop=0.06, extras=["steam", "dust", "smoke"]),
                         states={"spin_up": dict(at="muzzle", bursts=[B("#ff2e88", 6, 70, 0.4)], light=L("#ff2e88", 44, 1.2, 0.5)),
                                 "vent": dict(at="center", steam=True, shake=1.0, light=L("#ff8a30", 70, 1.6, 0.4))}),
    "warden": dict(step=dict(every=34, dust=4, spread=40, shake=1.4), hit=dict(color="#ff2a3d", amount=4, speed=110, light=0.5),
                   death=dict(bursts=[B("#ff2a3d", 30, 230, 0.7), B("#e8eef8", 20, 160, 0.8), B("#ffffff", 10, 300, 0.3)], light=L("#ff5a5a", 140, 2.4, 0.6), shake=6.0, hitstop=0.12, extras=["steam", "arc", "smoke", "dust"]),
                   states={"leap_windup": dict(at="feet", dust=4, spread=30, shake=0.8),
                           "leap": dict(at="feet", dust=8, spread=70, shake=2.5, bursts=[B("#ff2a3d", 10, 160, 0.3)]),
                           "burst_windup": dict(at="muzzle", light=L("#ff2a3d", 60, 1.6, 0.5)),
                           "fan_windup": dict(at="muzzle", light=L("#ff2a3d", 80, 2.0, 0.6)),
                           "summon_windup": dict(at="center", bursts=[B("#ff2a3d", 12, 100, 0.6)]),
                           "phase_shift": dict(at="center", steam=True, shake=2.0, bursts=[B("#ffffff", 16, 260, 0.4)], light=L("#ffffff", 120, 2.5, 0.4))}),
    "reclaimer": dict(step=dict(every=40, dust=1, spread=14, shake=0.0, spark=1, spark_color="#ff7a1a"), hit=dict(color="#ff7a1a", amount=6, speed=190, kind="arc", light=0.9),
                      death=dict(bursts=[B("#ff7a1a", 26, 240, 0.6), B("#35e0ff", 14, 180, 0.45)], light=L("#ff7a1a", 120, 2.2, 0.5), shake=5.0, hitstop=0.1, extras=["arc", "embers", "coolant"]),
                      states={"dash_windup": dict(at="feet", dust=3, spread=20, bursts=[B("#ff7a1a", 6, 80, 0.3)]),
                              "dash": dict(at="feet", dust=7, spread=60, bursts=[B("#ff7a1a", 10, 200, 0.2)], shake=1.4),
                              "blink_out": dict(bursts=[B("#35e0ff", 14, 200, 0.3)], light=L("#35e0ff", 70, 1.8, 0.2)),
                              "rail_windup": dict(at="center", bursts=[B("#35e0ff", 10, 80, 0.5)], light=L("#35e0ff", 90, 1.8, 0.6))}),
    "slasher": dict(step=dict(every=16, dust=2, spread=26, shake=0.0), hit=dict(color="#ff2a3d", amount=7, speed=220, light=0.9),
                    death=dict(bursts=[B("#ff2a3d", 16, 210, 0.4), B("#ffc0c0", 6, 140, 0.3)], light=L("#ff2a3d", 66, 1.3, 0.22), shake=2.0, hitstop=0.03, extras=["smoke"]),
                    states={"windup": dict(at="feet", dust=2, spread=12, bursts=[B("#ff2a3d", 5, 50, 0.4)]),
                            "leap": dict(at="feet", dust=5, spread=40, bursts=[B("#ff2a3d", 8, 170, 0.2)], shake=0.6)}),
    "stalker": dict(step=dict(every=36, dust=0, spread=0, shake=0.0), hit=dict(color="#ff2eb0", amount=5, speed=170, kind="arc", light=0.8),
                    death=dict(bursts=[B("#ff2eb0", 14, 150, 0.5), B("#35e0ff", 12, 120, 0.6)], light=L("#ff2eb0", 70, 1.4, 0.4), shake=1.4, hitstop=0.02, extras=["arc"]),
                    states={"aim": dict(at="muzzle", bursts=[B("#ff2eb0", 6, 70, 0.3)], light=L("#ff2eb0", 44, 1.6, 0.3)),
                            "retreat": dict(bursts=[B("#35e0ff", 8, 90, 0.25)])}),
    "bomber": dict(step=dict(every=12, dust=1, spread=10, shake=0.0, spark=1, spark_color="#ffd23f"), hit=dict(color="#ffd23f", amount=5, speed=170, light=0.7),
                   death=dict(bursts=[B("#ffd23f", 22, 260, 0.5), B("#ff8a1a", 14, 180, 0.45)], light=L("#ffd23f", 90, 2.0, 0.3), shake=3.0, hitstop=0.05, extras=["smoke", "embers"]),
                   states={"fuse": dict(at="center", bursts=[B("#ffd23f", 8, 110, 0.3)], light=L("#ffd23f", 60, 1.6, 0.4))}),
    "drone": dict(hit=dict(color="#ff4060", amount=5, speed=160, kind="arc", light=0.8),
                  death=dict(bursts=[B("#ff4060", 12, 170, 0.4), B("#8090a8", 8, 130, 0.5)], light=L("#ff4060", 58, 1.2, 0.25), shake=1.4, hitstop=0.02, extras=["smoke", "arc"]),
                  states={"lock": dict(at="center", light=L("#ff4060", 60, 1.8, 0.4)), "dive": dict(at="center", bursts=[B("#ff4060", 6, 120, 0.2)])}),
    "searchlight_drone": dict(hit=dict(color="#ffe070", amount=5, speed=150, kind="arc", light=0.8),
                              death=dict(bursts=[B("#ffe070", 14, 160, 0.45), B("#6a7890", 10, 120, 0.55)], light=L("#ffe070", 100, 1.8, 0.45), shake=1.8, hitstop=0.03, extras=["smoke", "arc", "dust"]),
                              states={"alarm": dict(at="center", light=L("#ff3040", 110, 2.2, 0.5), shake=0.6),
                                      "unpowered": dict(at="center", bursts=[B("#35e0ff", 8, 100, 0.3)]),
                                      "reboot": dict(at="center", bursts=[B("#ffe070", 8, 80, 0.4)], light=L("#ffe070", 80, 1.6, 0.4))}),
    "repair_drone": dict(hit=dict(color="#7aff9a", amount=5, speed=150, kind="steam", light=0.7),
                         death=dict(bursts=[B("#7aff9a", 14, 150, 0.5), B("#e8f4ec", 8, 110, 0.45)], light=L("#7aff9a", 70, 1.4, 0.3), shake=1.2, hitstop=0.02, extras=["steam", "coolant"]),
                         states={"channel": dict(at="center", bursts=[B("#7aff9a", 6, 60, 0.5)], light=L("#7aff9a", 54, 1.4, 0.5))}),
    "shock_hound": dict(step=dict(every=14, dust=2, spread=22, shake=0.0, spark=1, spark_color="#35e0ff"), hit=dict(color="#35e0ff", amount=6, speed=200, kind="arc", light=1.0),
                        death=dict(bursts=[B("#35e0ff", 20, 230, 0.4), B("#ffffff", 8, 260, 0.2)], light=L("#35e0ff", 80, 2.0, 0.3), shake=2.0, hitstop=0.03, extras=["arc", "smoke"]),
                        states={"growl": dict(at="feet", dust=2, spread=14, bursts=[B("#35e0ff", 8, 110, 0.3)], light=L("#35e0ff", 48, 1.4, 0.4)),
                                "pounce": dict(at="feet", dust=5, spread=40, bursts=[B("#35e0ff", 10, 200, 0.2)], shake=0.7)}),
    "turret": dict(hit=dict(color="#ff2a3d", amount=4, speed=140, light=0.6),
                   death=dict(bursts=[B("#ff2a3d", 14, 170, 0.5), B("#7a8294", 14, 120, 0.7)], light=L("#ff5a3a", 80, 1.6, 0.4), shake=2.6, hitstop=0.04, extras=["smoke", "steam", "embers"]),
                   states={"lock": dict(at="muzzle", light=L("#ff2a3d", 60, 2.0, 0.4)), "track": dict(at="muzzle", light=L("#ff2a3d", 36, 0.9, 0.2))}),
    "mimic": dict(step=dict(every=60, dust=0, spread=0, shake=0.0), hit=dict(color="#ff7a40", amount=7, speed=150, kind="smoke", light=0.6),
                  death=dict(bursts=[B("#a07050", 18, 170, 0.5), B("#ffffff", 8, 120, 0.3), B("#ff4040", 8, 150, 0.4)], light=L("#ff6040", 74, 1.4, 0.3), shake=3.2, hitstop=0.05, extras=["dust", "smoke"]),
                  states={"shake": dict(at="feet", dust=2, spread=14, shake=0.5),
                          "lunge": dict(at="center", dust=6, spread=44, bursts=[B("#ffffff", 6, 180, 0.2)], shake=2.0),
                          "exposed": dict(at="center", bursts=[B("#ff4040", 8, 90, 0.4)], light=L("#ff4040", 60, 1.4, 0.4))}),
}

OUT.mkdir(parents=True, exist_ok=True)
for name, spec in E.items():
    data = {"description": f"{name} 的專屬特效（EnemyVfx 讀取；欄位說明見 game/enemies/enemy_vfx.gd）。每個敵人自己一份，死亡演出彼此不同。", **spec}
    (OUT / f"{name}.json").write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf8")
print(len(E), "files")
