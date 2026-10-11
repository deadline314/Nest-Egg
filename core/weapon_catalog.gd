class_name WeaponCatalog
extends RefCounted
## One source of weapon resources, runtime melee profiles and applicable upgrades.
## No copied balance values or hand-maintained weapon ID list.

const WEAPON_DIR := "res://data/weapons"
const UPGRADE_DIR := "res://data/upgrades"

var weapons: Array[WeaponData] = []
var upgrades: Array[WeaponUpgradeData] = []
var profiles: Dictionary[StringName, MeleeSet] = {}
var default_melee: MeleeSet
var issues := PackedStringArray()


static func load_all(weapon_dir := WEAPON_DIR, upgrade_dir := UPGRADE_DIR) -> WeaponCatalog:
	var errors := PackedStringArray()
	var result := from_resources(_read_tree(weapon_dir, errors), _read_tree(upgrade_dir, errors))
	result.issues.append_array(errors)
	if result.weapons.is_empty():
		result.issues.append(weapon_dir + " has no valid weapon definitions")
	for error in result.issues:
		push_error("[WeaponCatalog] " + error)
	return result


static func from_resources(weapon_resources: Array[Resource], upgrade_resources: Array[Resource]) -> WeaponCatalog:
	var result := WeaponCatalog.new()
	result.default_melee = MeleeData.default_set()
	result.issues.append_array(MeleeData.validate())
	var seen: Dictionary = {}
	for resource in weapon_resources:
		var weapon := resource as WeaponData
		if weapon == null:
			result.issues.append(_source(resource) + " must be WeaponData")
			continue
		var problems := weapon.validate()
		if seen.has(weapon.id):
			problems.append("duplicate id %s (first %s)" % [weapon.id, seen[weapon.id]])
		else:
			seen[weapon.id] = _source(weapon)
		if weapon.is_melee() and problems.is_empty():
			var profile := MeleeData.set_of(weapon)
			problems.append_array(profile.validate())
			if problems.is_empty():
				result.profiles[weapon.id] = profile
		if not problems.is_empty():
			for problem in problems:
				result.issues.append(_source(weapon) + ": " + problem)
			continue
		result.weapons.append(weapon)
	seen.clear()
	for resource in upgrade_resources:
		var upgrade := resource as WeaponUpgradeData
		if upgrade == null:
			result.issues.append(_source(resource) + " must be WeaponUpgradeData")
			continue
		var problems := upgrade.validate()
		if seen.has(upgrade.id):
			problems.append("duplicate id %s (first %s)" % [upgrade.id, seen[upgrade.id]])
		else:
			seen[upgrade.id] = _source(upgrade)
		if upgrade.effect == WeaponUpgradeData.Effect.MELEE_TECHNIQUE:
			var weapon := result.find_weapon(upgrade.melee_weapon_id)
			var profile: MeleeSet = result.profiles.get(upgrade.melee_weapon_id)
			if weapon == null or profile == null or not upgrade.applies_to(weapon) or profile.extension_upgrade() != upgrade.id:
				problems.append("melee_weapon_id/extension upgrade mismatch: %s" % upgrade.melee_weapon_id)
		if not problems.is_empty():
			for problem in problems:
				result.issues.append(_source(upgrade) + ": " + problem)
			continue
		result.upgrades.append(upgrade)
	for id in result.profiles.keys():
		var profile := result.profiles[id]
		if profile.extension_upgrade() != &"" and result.find_upgrade(profile.extension_upgrade()) == null:
			result.issues.append("%s/extension/upgrade unknown or invalid: %s" % [profile.path, profile.extension_upgrade()])
			result.weapons.erase(result.find_weapon(id))
			result.profiles.erase(id)
	result.weapons.sort_custom(func(a: WeaponData, b: WeaponData) -> bool: return str(a.id) < str(b.id))
	result.upgrades.sort_custom(func(a: WeaponUpgradeData, b: WeaponUpgradeData) -> bool: return a.order < b.order if a.order != b.order else str(a.id) < str(b.id))
	return result


func find_weapon(id: StringName) -> WeaponData:
	for weapon in weapons:
		if weapon.id == id:
			return weapon
	return null


func find_upgrade(id: StringName) -> WeaponUpgradeData:
	for upgrade in upgrades:
		if upgrade.id == id:
			return upgrade
	return null


static func _source(resource: Resource) -> String:
	return resource.resource_path if resource != null and not resource.resource_path.is_empty() else "<in-memory resource>"


static func _read_tree(dir: String, errors: PackedStringArray) -> Array[Resource]:
	var result: Array[Resource] = []
	if not DirAccess.dir_exists_absolute(dir):
		errors.append(dir + " missing catalog directory")
		return result
	var files := DirAccess.get_files_at(dir)
	files.sort()
	var seen: Dictionary = {}
	for file in files:
		var path := dir.path_join(file.trim_suffix(".remap"))
		if not path.ends_with(".tres") or seen.has(path):
			continue
		seen[path] = true
		var resource := load(path) as Resource
		if resource == null:
			errors.append(path + " cannot load catalog resource")
		else:
			result.append(resource)
	var dirs := DirAccess.get_directories_at(dir)
	dirs.sort()
	for child in dirs:
		result.append_array(_read_tree(dir.path_join(child), errors))
	return result
