extends Node

const RECIPES_DIR := "res://data/recipes"
const SECTORS_DIR := "res://data/sectors"
const PACKS_DIR := "res://data/packs"

var _recipes: Dictionary = {}
var _sectors: Dictionary = {}
var _packs: Dictionary = {}

func _ready() -> void:
	_scan_into(RECIPES_DIR, _recipes)
	_scan_into(SECTORS_DIR, _sectors)
	_scan_into(PACKS_DIR, _packs)

func _scan_into(path: String, registry: Dictionary) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("RecipeDB: folder tidak ditemukan: " + path)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".tres"):
			var full_path := path + "/" + entry
			var res: Resource = load(full_path)
			if res != null and res.get("id") != null:
				registry[res.id] = res
			else:
				push_warning("RecipeDB: resource tanpa id atau gagal load: " + full_path)
		entry = dir.get_next()
	dir.list_dir_end()

func get_recipe(id: String) -> CraftRecipe:
	return _recipes.get(id)

func get_sector(id: String) -> SectorData:
	return _sectors.get(id)

func get_pack(id: String) -> PackDefinition:
	return _packs.get(id)

func all_recipes() -> Array:
	return _recipes.values()

func all_sectors() -> Array:
	return _sectors.values()

func all_packs() -> Array:
	return _packs.values()

func recipe_count() -> int:
	return _recipes.size()

func sector_count() -> int:
	return _sectors.size()

func pack_count() -> int:
	return _packs.size()
