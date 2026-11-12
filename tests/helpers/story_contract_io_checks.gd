extends RefCounted
const Catalog := preload("res://core/story_result_catalog.gd")
static func run(s: TestSuite) -> void:
	var folder := "user://test_bad_cutscene_catalog_io"
	DirAccess.make_dir_recursive_absolute(folder)
	var catalog := Catalog.new()
	s.check(catalog._error.is_empty(),"canonical runtime catalog remains valid")
	var large_path := folder.path_join("oversized.json")
	var file := FileAccess.open(large_path,FileAccess.WRITE)
	file.store_string(" ".repeat(RunSaveCodec.MAX_BYTES + 1) + "{}")
	file.close()
	s.check(catalog._read(large_path).is_empty() and catalog._error.contains("exceeds 4 MiB"),"oversized raw JSON refuses before ResourceLoader parse")
	catalog._error = ""
	var value := JSON.new()
	value.data = {"version":1,"token":"actual binary JSON resource"}
	var binary := folder.path_join("payload.res")
	s.check(ResourceSaver.save(value,binary) == OK,"engine writes actual JSON binary resource")
	var huge := JSON.new()
	huge.data = {"chunks":Array(range(5000)).map(func(_i:int)->String: return "x".repeat(1000))}
	var huge_binary := folder.path_join("huge.res")
	s.check(ResourceSaver.save(huge,huge_binary) == OK,"engine writes oversized remapped JSON payload")
	var mount := "res://tests/fixtures/test_bad_cutscene_catalog_io_pack/"
	var logical := mount + "catalog.json"
	s.check(not FileAccess.file_exists(logical) and not ResourceLoader.exists(logical),"private pack logical path has no existing source")
	var remap := folder.path_join("catalog.json.remap")
	file = FileAccess.open(remap,FileAccess.WRITE)
	file.store_string('[remap]\npath="' + mount + 'payload.res"\n');file.close()
	var huge_remap := folder.path_join("huge.json.remap")
	file = FileAccess.open(huge_remap,FileAccess.WRITE)
	file.store_string('[remap]\npath="' + mount + 'huge.res"\n');file.close()
	var pack := PCKPacker.new()
	var pack_path := folder.path_join("remap.pck")
	s.check(pack.pck_start(pack_path) == OK and pack.add_file(mount + "payload.res",binary) == OK and pack.add_file(logical + ".remap",remap) == OK and pack.add_file(mount + "huge.res",huge_binary) == OK and pack.add_file(mount + "huge.json.remap",huge_remap) == OK and pack.flush() == OK,"engine produces actual remapped PCK")
	s.check(ProjectSettings.load_resource_pack(pack_path,false),"mount private pack without replacing runtime files")
	s.check(not FileAccess.file_exists(logical) and ResourceLoader.exists(logical),"actual PCK remap resolves with absent raw JSON source")
	var loaded := catalog._read(logical)
	s.check(catalog._error.is_empty() and loaded == value.data,"runtime loader preserves actual remapped JSON content")
	s.check(catalog._read(mount + "huge.json").is_empty() and catalog._error.contains("JSON data exceeds 4 MiB"),"remapped resource still obeys decoded JSON byte limit")
