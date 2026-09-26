extends Node

# Verifikasi fitur "sorot resep yang bisa dibuat sekarang dari kartu di board":
# - RecipeResolver.can_make_now() / unmet_reason() logika
# - HUD._refresh_recipe_highlights() mewarnai baris resep sesuai kondisi board

const MAIN_SCENE := preload("res://main.tscn")

var _errors: Array[String] = []
var _board: Board
var _hud: HUD

func _ready() -> void:
	await get_tree().process_frame
	Events.enabled = false
	_board = MAIN_SCENE.instantiate()
	add_child(_board)
	await get_tree().process_frame
	await get_tree().process_frame
	_hud = _board.get_node("HUD") as HUD
	_clear_board()
	_run_tests()
	if _errors.is_empty():
		print("RECIPE HIGHLIGHT CHECK: OK")
		get_tree().quit(0)
	else:
		for e in _errors:
			push_error(e)
		print("RECIPE HIGHLIGHT CHECK: FAIL - ", _errors.size(), " error(s)")
		get_tree().quit(1)

func _fail(msg: String) -> void:
	_errors.append(msg)

func _clear_board() -> void:
	for child in _board.get_children():
		var card := child as Card
		if card != null:
			card.free()

func _spawn(card_id: String, count := 1, built := false) -> void:
	_board.spawn_card_at(card_id, Vector2(700, 700), count, built)

func _can(recipe_id: String) -> bool:
	return RecipeResolver.can_make_now(RecipeDB.get_recipe(recipe_id), _board)

func _reason(recipe_id: String) -> String:
	return RecipeResolver.unmet_reason(RecipeDB.get_recipe(recipe_id), _board)

func _row(recipe_id: String) -> Dictionary:
	for row in _hud._recipe_rows:
		if String(row["recipe"].id) == recipe_id:
			return row
	return {}

func _run_tests() -> void:
	# A. Board kosong → tidak ada resep yang bisa dibuat.
	if _can("recipe_make_oxygen_tank"):
		_fail("A: oxygen tank tidak boleh bisa dibuat di board kosong")
	if _can("recipe_make_dirt"):
		_fail("A: dirt tidak boleh bisa dibuat di board kosong")
	if not _reason("recipe_make_dirt").begins_with("Kurang:"):
		_fail("A: alasan dirt seharusnya 'Kurang: ...', dapat: " + _reason("recipe_make_dirt"))

	# B. Water + Ice tersedia → Oxygen Tank bisa; Dirt belum (tanpa rock).
	_spawn("item_water", 1)
	_spawn("item_ice_chunk", 1)
	if not _can("recipe_make_oxygen_tank"):
		_fail("B: water+ice seharusnya bisa buat oxygen tank (alasan: %s)" % _reason("recipe_make_oxygen_tank"))
	if _can("recipe_make_dirt"):
		_fail("B: dirt belum bisa dibuat tanpa space rock")

	# C. HUD: baris resep yang bisa menyala hijau, yang belum tetap redup.
	_hud._refresh_recipe_highlights()
	var on_row := _row("recipe_make_oxygen_tank")
	var off_row := _row("recipe_make_dirt")
	if on_row.is_empty() or off_row.is_empty():
		_fail("C: baris resep tidak ditemukan di HUD")
	else:
		var on_style := on_row["style"] as StyleBoxFlat
		var off_style := off_row["style"] as StyleBoxFlat
		if on_style.bg_color != HUD.RECIPE_BG_ON:
			_fail("C: baris oxygen tank seharusnya berwarna ON")
		if off_style.bg_color != HUD.RECIPE_BG_OFF:
			_fail("C: baris dirt seharusnya berwarna OFF")
		var on_status := on_row["status"] as Label
		if not on_status.text.contains("BISA"):
			_fail("C: status baris oxygen tank seharusnya menyatakan 'BISA', dapat: " + on_status.text)

	# D. Tambah Space Rock → Dirt (water+rock) jadi bisa.
	_spawn("item_space_rock", 1)
	if not _can("recipe_make_dirt"):
		_fail("D: dirt seharusnya bisa setelah space rock ada (alasan: %s)" % _reason("recipe_make_dirt"))

	# E. Resep ke Structure (Furnace): butuh Furnace TERBANGUN yang ada di board.
	_spawn("item_iron_ore", 1)
	if _can("recipe_furnace_smelt_ore"):
		_fail("E: smelt ore tidak boleh bisa tanpa furnace")
	_spawn("building_furnace", 1, false)   # belum dibangun → jangan dihitung
	if _can("recipe_furnace_smelt_ore"):
		_fail("E: furnace yang BELUM dibangun tidak boleh membuka resep")
	_clear_cards_of_id("building_furnace")
	_spawn("building_furnace", 1, true)
	if not _can("recipe_furnace_smelt_ore"):
		_fail("E: smelt ore seharusnya bisa setelah furnace terbangun (alasan: %s)" % _reason("recipe_furnace_smelt_ore"))

	# F. Resep 3-input + syarat (Little Helper): butuh Helper Station + Astronot.
	_spawn("item_energy_cell", 1)
	_spawn("item_iron", 1)
	if _can("recipe_craft_little_helper"):
		_fail("F: little helper tidak boleh bisa tanpa helper station/astronot (alasan: %s)" % _reason("recipe_craft_little_helper"))
	_spawn("unit_astronaut", 1)
	if _can("recipe_craft_little_helper"):
		_fail("F: little helper tidak boleh bisa dengan astronaut saja tanpa helper station")
	_spawn("building_helper_station", 1, true)
	if not _can("recipe_craft_little_helper"):
		_fail("F: little helper seharusnya bisa dengan helper station + astronaut (alasan: %s)" % _reason("recipe_craft_little_helper"))

	# G. Resep butuh building (promote di Workshop).
	_spawn("item_circuit_board", 2)
	if _can("recipe_promote_engineer"):
		_fail("G: promote engineer tidak boleh bisa tanpa workshop")
	if not _reason("recipe_promote_engineer").begins_with("Butuh building:"):
		_fail("G: alasan promote engineer seharusnya 'Butuh building: ...', dapat: " + _reason("recipe_promote_engineer"))
	_spawn("building_workshop", 1, true)
	if not _can("recipe_promote_engineer"):
		_fail("G: promote engineer seharusnya bisa dengan workshop terbangun (alasan: %s)" % _reason("recipe_promote_engineer"))

	# H. Resep produksi (duration > 0): Oxygen Canister butuh Oxygen Generator.
	if _can("recipe_oxygen_canister"):
		_fail("H: oxygen canister tidak boleh bisa tanpa oxygen generator")
	_spawn("building_oxygen_generator", 1, true)
	if not _can("recipe_oxygen_canister"):
		_fail("H: oxygen canister seharusnya bisa dengan generator terbangun (alasan: %s)" % _reason("recipe_oxygen_canister"))

	# I. HUD punya satu baris per resep.
	if _hud._recipe_rows.size() != RecipeDB.recipe_count():
		_fail("I: jumlah baris resep HUD (%d) != jumlah resep (%d)"
			% [_hud._recipe_rows.size(), RecipeDB.recipe_count()])

func _clear_cards_of_id(card_id: String) -> void:
	for child in _board.get_children():
		var card := child as Card
		if card != null and card.card_data != null and card.get_card_id() == card_id:
			card.free()
