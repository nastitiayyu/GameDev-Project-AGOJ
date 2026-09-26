extends Node

const MAIN_SCENE := preload("res://main.tscn")

var _errors: Array[String] = []
var _board: Board

func _ready() -> void:
	await get_tree().process_frame
	Events.enabled = false
	DayCycle.enabled = false
	_board = MAIN_SCENE.instantiate()
	add_child(_board)
	await get_tree().process_frame
	await get_tree().process_frame
	_run_gameplay_tests()
	if _errors.is_empty():
		print("GAMEPLAY CHECK: OK")
		get_tree().quit(0)
	else:
		for e in _errors:
			push_error(e)
		print("GAMEPLAY CHECK: FAIL - ", _errors.size(), " error(s)")
		get_tree().quit(1)

func _fail(msg: String) -> void:
	_errors.append(msg)

func _find(card_id: String) -> Card:
	for child in _board.get_children():
		var card := child as Card
		if card != null and not card.is_queued_for_deletion() \
				and card.card_data != null and card.get_card_id() == card_id:
			return card
	return null

func _count(card_id: String) -> int:
	var total := 0
	for child in _board.get_children():
		var card := child as Card
		if card != null and not card.is_queued_for_deletion() \
				and card.card_data != null and card.get_card_id() == card_id:
			total += card.stack_count
	return total

func _count_all() -> int:
	var total := 0
	for child in _board.get_children():
		var card := child as Card
		if card != null and not card.is_queued_for_deletion() and card.card_data != null:
			total += 1
	return total

func _drop(card: Card, target: Card) -> void:
	_board._on_card_dropped(card, target.global_position + target.size * 0.5)

func _run_gameplay_tests() -> void:
	# A. A6: Repair Kit consumable → Hull +20
	GameState.hull = 60.0
	var kit := _find("tool_repair_kit")
	var astronaut := _find("unit_astronaut")
	_drop(kit, astronaut)
	await get_tree().process_frame
	if GameState.hull != 80.0:
		_fail("A: hull harus 80 setelah repair kit, sekarang %.0f" % GameState.hull)
	if _find("tool_repair_kit") != null:
		_fail("A: repair kit harus terkonsumsi")

	# B. A7: bangun Hydroponics Bay (cost 3 ingot + 2 water)
	var hydro := _find("building_hydroponics_bay")
	_board._on_card_dropped(hydro, hydro.global_position + hydro.size * 0.5)
	await get_tree().process_frame
	if hydro.is_built == false:
		_fail("B: hydroponics bay harus terbangun")
	if _count("item_metal_ingot") != 1:
		_fail("B: ingot harus 1 (4-3), sekarang %d" % _count("item_metal_ingot"))
	if _count("item_water") != 1:
		_fail("B: water harus 1 (3-2), sekarang %d" % _count("item_water"))

	# C. Market: jual 1 water → +3 cr (common, harga per-unit)
	var water := _find("item_water")
	var water_before := _count("item_water")
	Economy.sell_units(_board, water, 1)
	await get_tree().process_frame
	if GameState.credits != 53:
		_fail("C: credits harus 53 (50+3), sekarang %d" % GameState.credits)
	if _count("item_water") != water_before - 1:
		_fail("C: water harus berkurang 1, sekarang %d" % _count("item_water"))

	# D. A7 produksi real-time: hydro + worker + bahan → progress penuh → 1 veggie (1 water)
	var a1 := _find("unit_astronaut")
	_drop(a1, hydro)
	await get_tree().process_frame
	if a1.assigned_building != hydro:
		_fail("D: unit harus WORKING di hydroponics")
	hydro.production_timer = 10.0 * 1 + 0.1   # interval_days=1 → 10 detik
	await get_tree().process_frame
	if _count("item_hydro_veggie") != 1:
		_fail("D: hydro veggie harus 1 setelah produksi, sekarang %d" % _count("item_hydro_veggie"))
	if _count("item_water") != 2:
		_fail("D: water seharusnya 2 (3-1 produksi), sekarang %d" % _count("item_water"))
	DayCycle.end_day()
	await get_tree().process_frame
	if GameState.food != 100.0:
		_fail("D: food harus tetap 100 (stock cukup), sekarang %.0f" % GameState.food)
	if GameState.day != 1:
		_fail("D: hari harus 1, sekarang %d" % GameState.day)

	# E. A8: assemble package scrap×5 → berangkat → terkirim (1 hari)
	var pkg := _find("pkg_scrap_run")
	var scrap1 := _find("item_scrap_metal")
	_drop(scrap1, pkg)
	await get_tree().process_frame
	var scrap2 := _find("item_scrap_metal")
	_drop(scrap2, pkg)
	await get_tree().process_frame
	if not pkg.is_package_complete():
		_fail("E: package harus lengkap (5/5)")
	var a2 := _find("unit_astronaut")
	_drop(a2, pkg)
	await get_tree().process_frame
	if a2.unit_state != Enums.UnitState.TRAVELING:
		_fail("E: unit harus TRAVELING")
	if Packages.traveling.size() != 1:
		_fail("E: harus ada 1 paket traveling")
	Packages.resolve_travel()
	await get_tree().process_frame
	if GameState.credits != 78:
		_fail("E: credits harus 78 (53+25), sekarang %d" % GameState.credits)
	if GameState.reputation != 5:
		_fail("E: rep harus 5, sekarang %d" % GameState.reputation)
	if GameState.total_packages_delivered != 1:
		_fail("E: paket terkirim harus 1")
	if a2.unit_state != Enums.UnitState.IDLE:
		_fail("E: unit harus kembali IDLE setelah terkirim")

	# F. A1.2 (revisi): unit boleh kerja di Zona Angkasa TANPA tether —
	#    cukup memakai O2 dari stok kapal. Oxygen Tank consumable
	#    yang menambah 25 O2 saat dipakai pada unit.
	var spacer := _board.spawn_card_at("unit_astronaut", Vector2(1750, 760))
	var tank_owner := _board.spawn_card_at("unit_astronaut", Vector2(1750, 300))
	await get_tree().process_frame
	if _board.get_zone(Vector2(1780, 790)) != Enums.BoardZone.OPEN_SPACE:
		_fail("F: koordinat tes harus di Zona Angkasa")
	if not _board.validate_drop(spacer):
		_fail("F: unit harus boleh masuk Zona Angkasa tanpa tether/tank")
	_board._on_card_dropped(spacer, spacer.global_position + spacer.size * 0.5)
	await get_tree().process_frame
	if spacer.is_queued_for_deletion():
		_fail("F: unit tidak boleh hilang di Zona Angkasa tanpa tether/tank")
	GameState.oxygen = 40.0
	var tank := _board.spawn_card_at("item_oxygen_tank", Vector2(1750, 500))
	await get_tree().process_frame
	if tank == null:
		_fail("F: oxygen tank tidak bisa di-spawn")
	else:
		_drop(tank, tank_owner)
		await get_tree().process_frame
		if GameState.oxygen != 65.0:
			_fail("F: oxygen tank harus +25 O2 (40 -> 65), sekarang %.0f" % GameState.oxygen)
		if _find("item_oxygen_tank") != null:
			_fail("F: oxygen tank harus terkonsumsi setelah dipakai")

	# G. A9: PLAYER_CHOICE — Trade → Alien Pack gratis terbuka
	var cards_before := _count_all()
	Events.apply_event(_board, "event_alien_encounter", 0)
	await get_tree().process_frame
	if _count_all() <= cards_before:
		_fail("G: pilihan Trade harus membuka Alien Pack (kartu bertambah)")
	Events.apply_event(_board, "event_alien_encounter", 1)
	await get_tree().process_frame

	# H. A15/A16: semua unit mati → Game Over
	for unit in _board.get_units():
		unit.queue_free()
	await get_tree().process_frame
	DayCycle.end_day()
	await get_tree().process_frame
	if not GameState.is_game_over:
		_fail("H: semua unit mati harus Game Over")