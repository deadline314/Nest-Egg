# Source and ownership provenance

The input is the original 1440×736 RGBA Rin kneel source, SHA-256 `74044963a9ff8d2bc47b5bceed04d8763b856b252069c4817c7f0685b1bd33ed`. Its workflow sidecar is retained beside it with prompt and generation parameters. The seven supplied native masks are the reviewed v3 owner inputs; the builder regenerates the ownership proposal and verifies that every pixel at alpha ≥40 belongs to exactly one owner.

Owner totals are pelvis 20,212; front thigh 38,915; front calf 25,035; front boot 36,817; back thigh 33,039; back calf 21,839; back boot 36,133 (211,990 retained pixels total). The masks are data for a source-registration experiment. They do not prove concealed anatomy, hidden damage layers, or final art acceptance. The canonical bone guides are rig targets and are not independent anatomy measurements.

The original source, workflow metadata, source masks, proposal, guide, measurements, character scale, and 20-bone rig definition are all included under `source/`. Rebuild the checked output with `python pm/Nest-Egg/attachments/NE-222-native-pose/rebuild_proof.py` from the project root.
