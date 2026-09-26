extends Node

const CARD_SCENE := preload("res://scenes/card.tscn")
const MAIN_SCENE := preload("res://main.tscn")

var _errors: Array[String] = []

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	DayCycle.enabled = false
	_run_find_recipe_tests()
	await _run_combine_flow_tests()
	await _run_space_salvage_tests()
	if _errors.is_empty():
		print("COMBINE CHECK: OK")
		get_tree().quit(0)
	else:
		for e in _errors:
			push_error(e)
		print("COMBINE CHECK: FAIL - ", _errors.size(), " error(s)")
		get_tree().quit(1)

func _fail(msg: String) -> void:
	_errors.append(msg)

func _make_card(card_id: String, count := 1) -> Card:
	var card: Card = CARD_SCENE.instantiate()
	add_child(card)
	card.setup_card(CardDB.get_card(card_id), count)
	card.global_position = Vector2(-500, -500)
	return card

func _expect_recipe(card_a: Card, card_b: Card, expected: String, label: String) -> void:
	var recipe := RecipeResolver.find_recipe(card_a, card_b)
	var got: String = recipe.id if recipe != null else "null"
	if got != expected:
		_fail("%s: expected %s, got %s" % [label, expected, got])

func _run_find_recipe_tests() -> void:
	# Resep dasar PDF (Combining Recipe doc): 2-input, urutan bebas.
	_expect_recipe(_make_card("item_water", 1), _make_card("item_ice_chunk", 1),
		"recipe_make_oxygen_tank", "water+ice")
	_expect_recipe(_make_card("item_water", 1), _make_card("item_water", 1),
		"null", "water+water (stack saja, bukan craft)")
	_expect_recipe(_make_card("item_water", 1), _make_card("item_space_rock", 1),
		"recipe_make_dirt", "water+rock")
	_expect_recipe(_make_card("item_space_rock", 1), _make_card("item_water", 1),
		"recipe_make_dirt", "rock+water (dibalik)")
	_expect_recipe(_make_card("item_iron", 1), _make_card("item_component", 1),
		"recipe_make_excavation_tools", "iron+component")
	_expect_recipe(_make_card("item_iron", 1), _make_card("item_iron", 1),
		"recipe_make_component", "iron+iron")
	_expect_recipe(_make_card("item_water", 1), _make_card("item_dirt", 1),
		"recipe_make_fertile_dirt", "water+dirt")
	_expect_recipe(_make_card("item_space_rock", 2), _make_card("item_iron", 1),
		"recipe_build_furnace", "rock2+iron")
	_expect_recipe(_make_card("item_iron", 2), _make_card("item_component", 1),
		"recipe_make_excavation_tools", "iron2+component (subset tetap excavation)")
	_expect_recipe(_make_card("item_iron", 2), _make_card("item_scrap_metal", 1),
		"recipe_charge_energy_cell", "iron2+scrap (cas energy cell)")
	_expect_recipe(_make_card("item_water", 1), _make_card("item_mushroom", 1),
		"recipe_greenroom_grow_from_mushroom", "water+mushroom (gate dicek terpisah)")
	# Qty kurang / tidak cocok → null.
	_expect_recipe(_make_card("item_space_rock", 1), _make_card("item_iron", 1),
		"null", "rock1+iron (qty kurang utk furnace)")
	_expect_recipe(_make_card("item_water", 1), _make_card("item_iron", 1),
		"null", "water+iron (tidak ada resep)")
	# 3-input tanpa board/pool → null (butuh Helper Station + Astronot + pool).
	_expect_recipe(_make_card("item_energy_cell", 1), _make_card("item_space_rock", 1),
		"null", "energy+rock tanpa pool")
	# 1-input ke Structure belum dibangun → null.
	_expect_recipe(_make_card("item_mushroom", 1), _make_card("building_furnace", 1),
		"null", "mushroom+furnace belum dibangun")

# --- Helper khusus kartu di BOARD (bukan kartu test _make_card) ---

func _find_on_board(board: Board, card_id: String) -> Card:
	for child in board.get_children():
		var card := child as Card
		if card != null and not card.is_queued_for_deletion() \
				and card.card_data != null and card.get_card_id() == card_id:
			return card
	return null

func _count_on_board(board: Board, card_id: String) -> int:
	var total := 0
	for child in board.get_children():
		var card := child as Card
		if card != null and not card.is_queued_for_deletion() \
				and card.card_data != null and card.get_card_id() == card_id:
			total += card.stack_count
	return total

func _find_two_on_board(board: Board, card_id: String) -> Array[Card]:
	var found: Array[Card] = []
	for child in board.get_children():
		var card := child as Card
		if card != null and not card.is_queued_for_deletion() \
				and card.card_data != null and card.get_card_id() == card_id:
			found.append(card)
			if found.size() >= 2:
				break
	return found

func _run_combine_flow_tests() -> void:
	var board: Board = MAIN_SCENE.instantiate()
	add_child(board)
	await get_tree().process_frame
	await get_tree().process_frame

	# A. water di-drop ke ice chunk → Oxygen Tank baru spawn.
	# (board awal: water total 7, ice total 1.)
	var ice := _find_on_board(board, "item_ice_chunk")
	var water0 := _find_on_board(board, "item_water")
	var tank_before: int = _count_on_board(board, "item_oxygen_tank")
	board._on_card_dropped(water0, ice.global_position + ice.size * 0.5)
	await get_tree().process_frame
	if _count_on_board(board, "item_oxygen_tank") != tank_before + 1:
		_fail("flow A: oxygen tank tidak bertambah (sebelum %d, sesudah %d)" \
			% [tank_before, _count_on_board(board, "item_oxygen_tank")])
	if _count_on_board(board, "item_water") != 6:
		_fail("flow A: water seharusnya 6 (7-1), sekarang %d" % _count_on_board(board, "item_water"))
	if _count_on_board(board, "item_ice_chunk") != 0:
		_fail("flow A: ice seharusnya habis, sekarang %d" % _count_on_board(board, "item_ice_chunk"))

	# B. iron di-drop ke component → Excavation Tools, iron-1 + component habis.
	# (board awal: iron total 4, component 0 → spawn 1 buat test.)
	var tools_before: int = _count_on_board(board, "tool_excavation_tools")
	board.spawn_card_at("item_component", Vector2(900, 700))
	await get_tree().process_frame
	var iron := _find_on_board(board, "item_iron")
	var component := _find_on_board(board, "item_component")
	board._on_card_dropped(iron, component.global_position + component.size * 0.5)
	await get_tree().process_frame
	if _count_on_board(board, "tool_excavation_tools") != tools_before + 1:
		_fail("flow B: excavation tools seharusnya bertambah 1 (sekarang %d)"
			% _count_on_board(board, "tool_excavation_tools"))
	if _count_on_board(board, "item_iron") != 3:
		_fail("flow B: iron seharusnya 3 (4-1), sekarang %d" % _count_on_board(board, "item_iron"))
	if _count_on_board(board, "item_component") != 0:
		_fail("flow B: component seharusnya habis, sekarang %d" % _count_on_board(board, "item_component"))

	# C. water di-drop ke space rock → Dirt (rantai: Dirt+Water=Fertile Dirt).
	# (board: rock total 5, water sisa 6 setelah flow A.)
	var dirt_before: int = _count_on_board(board, "item_dirt")
	var water := _find_on_board(board, "item_water")
	var rock := _find_on_board(board, "item_space_rock")
	board._on_card_dropped(water, rock.global_position + rock.size * 0.5)
	await get_tree().process_frame
	if _count_on_board(board, "item_dirt") != dirt_before + 1:
		_fail("flow C: dirt tidak bertambah (sebelum %d, sesudah %d)" \
			% [dirt_before, _count_on_board(board, "item_dirt")])
	if _count_on_board(board, "item_water") != 5:
		_fail("flow C: water seharusnya 5 (6-1), sekarang %d" % _count_on_board(board, "item_water"))
	if _count_on_board(board, "item_space_rock") != 4:
		_fail("flow C: space rock seharusnya 4 (5-1), sekarang %d" % _count_on_board(board, "item_space_rock"))
# --- Tes fitur baru: combine ke Structure, syarat Building/Worker, & 3-input pool ---
# (recipe dari GDD/Combining Recipe: Furnace, Green Room, Helper Station)

func _run_space_salvage_tests() -> void:
	var board: Board = MAIN_SCENE.instantiate()
	add_child(board)
	await get_tree().process_frame
	await get_tree().process_frame

	# D. Iron Ore di-drop ke Furnace (belum dibangun) → harus DIBLOKIR
	var furnace := board.spawn_card_at("building_furnace", Vector2(50, 50))
	var ore := _find_on_board(board, "item_iron_ore")
	board._on_card_dropped(ore, furnace.global_position + furnace.size * 0.5)
	await get_tree().process_frame
	if _count_on_board(board, "item_iron") != 4:
		_fail("flow D: Iron tidak boleh nambah, Furnace belum dibangun (%d)"
			% _count_on_board(board, "item_iron"))

	# E. Furnace dibangun (bayar build_cost), lalu Iron Ore di-drop lagi → Iron nambah
	board._try_build(furnace)
	await get_tree().process_frame
	var ore2 := _find_on_board(board, "item_iron_ore")
	if ore2 != null:
		var iron_before: int = _count_on_board(board, "item_iron")
		board._on_card_dropped(ore2, furnace.global_position + furnace.size * 0.5)
		await get_tree().process_frame
		if _count_on_board(board, "item_iron") != iron_before + 1:
			_fail("flow E: Furnace built seharusnya menghasilkan Iron (%d -> %d)"
				% [iron_before, _count_on_board(board, "item_iron")])
	else:
		_fail("flow E: item_iron_ore tidak ditemukan di board (cek data spawn test)")

	# F. Water+Mushroom tanpa Green Room+Worker → DIBLOKIR
	var water := _find_on_board(board, "item_water")
	var mushroom := _find_on_board(board, "item_mushroom")
	var mushroom_before: int = mushroom.stack_count
	board._on_card_dropped(water, mushroom.global_position + mushroom.size * 0.5)
	await get_tree().process_frame
	if _find_on_board(board, "item_mushroom") == null \
			or _find_on_board(board, "item_mushroom").stack_count != mushroom_before:
		_fail("flow F: Mushroom tidak boleh nambah tanpa Green Room + worker")

	# G. Green Room dibangun + ada Astronot di board → Water+Mushroom = 2x Mushroom
	var green_room := board.spawn_card_at("building_green_room", Vector2(50, 260))
	board._try_build(green_room)
	# (Astronot sudah ada di test board bawaan _spawn_test_cards)
	await get_tree().process_frame
	var water2 := _find_on_board(board, "item_water")
	var mushroom2 := _find_on_board(board, "item_mushroom")
	if water2 != null and mushroom2 != null:
		board._on_card_dropped(water2, mushroom2.global_position + mushroom2.size * 0.5)
		await get_tree().process_frame
		# Resep konsumsi 1 Mushroom sbg bahan lalu hasilkan 2x Mushroom baru → net +1
		if _count_on_board(board, "item_mushroom") != mushroom_before + 1:
			_fail("flow G: Green Room + Astronot: net Mushroom seharusnya +1 (1 abis, +2 baru) (skrg %d, sebelum %d)"
				% [_count_on_board(board, "item_mushroom"), mushroom_before])
	else:
		_fail("flow G: kartu water/mushroom habis sebelum waktunya")

	# H. Little Helper (3-input: Energy Cell + Space Rock + Iron), butuh Helper Station
	var helper_station := board.spawn_card_at("building_helper_station", Vector2(50, 470))
	var energy := _find_on_board(board, "item_energy_cell")
	var rock := _find_on_board(board, "item_space_rock")
	var iron := _find_on_board(board, "item_iron")
	# taruh berdekatan biar masuk radius pool
	energy.global_position = Vector2(700, 700)
	rock.global_position = Vector2(730, 700)
	iron.global_position = Vector2(760, 700)
	# belum dibangun → harus diblokir
	board._on_card_dropped(energy, rock.global_position + rock.size * 0.5)
	await get_tree().process_frame
	if _count_on_board(board, "unit_little_helper") != 0:
		_fail("flow H: Little Helper tidak boleh lahir, Helper Station belum dibangun")
	board._try_build(helper_station)
	await get_tree().process_frame
	var energy2 := _find_on_board(board, "item_energy_cell")
	var rock2 := _find_on_board(board, "item_space_rock")
	if energy2 != null and rock2 != null:
		board._on_card_dropped(energy2, rock2.global_position + rock2.size * 0.5)
		await get_tree().process_frame
		if _count_on_board(board, "unit_little_helper") != 1:
			_fail("flow H: Little Helper seharusnya lahir setelah Helper Station + Astronot ada (skrg %d)"
				% _count_on_board(board, "unit_little_helper"))
	else:
		_fail("flow H: energy_cell/space_rock tidak ditemukan sebelum combine kedua")
