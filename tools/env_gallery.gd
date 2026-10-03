class_name EnvGallery
extends RefCounted
## 環境元件畫廊：測試與截圖共用。材質畫廊（每種地形材質一個區段）與道具畫廊（平地上排開所有道具）。

const MATERIALS_MAP := "res://tests/fixtures/env_gallery.json"
const PROPS_MAP := "res://tests/fixtures/env_props.json"
const ZONE_TILES := 13
const BACKDROP_IDS: Array[String] = ["far_skyline", "mid_buildings", "near_foreground"]
const BACKDROP_SCROLL: Dictionary = {"far_skyline": 0.12, "mid_buildings": 0.26, "near_foreground": 0.5}
const BACKDROP_BOTTOM: Dictionary = {"far_skyline": 300.0, "mid_buildings": 320.0, "near_foreground": 360.0}


## 每種材質一個區段（13 欄），立面清單包含全部立面，背景用三層貼圖。
static func theme() -> EnvironmentTheme:
	var result := EnvironmentTheme.new()
	var facades: Array[FacadeData] = []
	for res in ResourceCatalog.load_dir("res://data/environment/facades", FacadeData, "EnvGallery"):
		facades.append(res as FacadeData)
	var index := 0
	for res in ResourceCatalog.load_dir("res://data/environment/materials", TerrainMaterialData, "EnvGallery"):
		var zone := EnvZone.new()
		zone.from_tile = index * ZONE_TILES
		zone.material = res as TerrainMaterialData
		zone.facades = facades
		zone.label = String(zone.material.id)
		result.zones.append(zone)
		index += 1
	for id in BACKDROP_IDS:
		var layer := BackdropLayer.new()
		layer.texture = "res://art/environment/backdrop/%s.png" % id
		layer.scroll_scale = BACKDROP_SCROLL[id]
		layer.bottom_y = BACKDROP_BOTTOM[id]
		result.backdrop.append(layer)
	return result


static func level_data(kind: String) -> LevelData:
	var data := LevelData.new()
	data.id = StringName("env_" + kind)
	data.layout_path = MATERIALS_MAP if kind == "materials" else PROPS_MAP
	data.environment = theme()
	data.rain = false
	return data
