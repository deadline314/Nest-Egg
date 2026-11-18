# ST-8 current source and native review

Base: 56f1c19b0ac0d9ea57cf061dbc0aa3c000a808cd. Changes affect the offline icon producer, its ownership data, registered published icon masters, Python tests and CI. No runtime game code or published runtime PNG is changed.

## Results

- Original producer: 7 tests, 6 fail. Fixed producer: 7 tests, all pass. Covers adopted outputs, vector fallback, broken ownership JSON, duplicate ownership, missing masters, registered-master recovery and path escape.
- Rebuild into empty private output directories: 14 catalog entries, all 50 current PNGs pixel-identical. The adopted dagger uses registered PNG masters; the other outputs use existing vector source. Runtime PNG hashes are unchanged.
- Official changed-test selector against the base: exit0, no affected Godot suites for these offline files. Python tests run explicitly and are added to CI.
- Additional gameplay regression: UiKit, FloodPit, Areas; 196 checks, 0 new/known failures. Other current chapter/item coverage is included in NE-240's published 56-group, 59,214-check run on identical game code and data. This is evidence reuse, not a newly repeated full run.
- Godot 4.7.2 Forward+ Vulkan, RX 9070 XT: 3 item overview and 15 inventory PNGs, 1280×720; both native processes exit0, 0 SCRIPT ERROR and 0 ERROR. All 18 images were actually reviewed at 1:1 on nine pages.

## Source boundary

The older vector producer overwrote a dagger icon intentionally adopted by a4adfb7b6df92b225acf64c608d74d1c484fc2eb. Its two accepted published PNGs are now versioned as explicit import masters with blob/SHA provenance. They are not the original generated RAW. That RAW is absent from this checkout; no claim of regenerating the original model output is made. Current icon outputs can be rebuilt from the registered masters.

## Native fixture boundary

Inventory items were arranged by the existing screenshot scenario. Screens verify UI and image layout, not manual pickup, human gameplay or a physical controller. The private adapter inherits the existing scenario and only releases the Level children and waits for existing audio cleanup before quitting. Original screenshot tool and game lifecycle are unchanged. Previous ST-8 exit diagnostics remain in historical ticket records; they are not described as clean.

## Packet

evidence.zip includes raw commands/logs/results, all 18 native PNGs, nine 1:1 review pages, reconstruction outputs, real red/green logs, source hashes and the exact private adapters/runners. manifest.json hashes every archive member and the archive. Private save/profile folders are excluded. Runner paths are recorded as actually executed, not advertised as a portable standalone project.
