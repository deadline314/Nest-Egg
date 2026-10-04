class_name ModelVehicleScenario
extends ScenarioBase
## 截圖情境（NE-153）：載具（堡壘機甲）站姿與瞄準，亮場景下拍預覽。
## 用法：screenshot.tscn -- --out=<資料夾> --scenario=model_vehicle

func run() -> void:
	await open_arena("res://data/lighting/neutral.tres", 12.0)
	var vehicle := Vehicle.new()
	vehicle.configure(load("res://data/vehicles/bulwark.tres") as VehicleData)
	vehicle.position = Vector2(14.0 * 16.0, FLOOR_Y)
	level._entities.add_child(vehicle)
	await wait(0.8)
	capture("vehicle")
	await finish()
