extends Node

const CARD_SCENE := preload("res://scenes/card.tscn")
const MAIN_SCENE := preload("res://main.tscn")

var _errors: Array[String] = []
var _board: Board
var _pending_calls := 0

func _ready() -> void:
	await get_tree().process_frame
	DayCycle.enabled = false
	_board = MAIN_SCENE.instantiate()
	add_child(_board)
	await get_tree().process_frame
	await get_tree().process_frame
	await _run_gather_tests()
	if _errors.is_empty():
		print("GATHER CHECK: OK")
		get_tree().quit(0)
	else:
		for e in _errors:
			push_error(e)
		print("GATHER CHECK: FAIL - ", _errors.size(), " error(s)")
		get_tree().quit(1)

func _fail(msg: String) -> void:
	_errors.append(msg)

func _find_card(card_id: String) -> Card:
	for node in get_tree().get_nodes_in_group(&"cards"):
		var card := node as Card
		if card != null and not card.is_queued_for_deletion() \
				and card.card_data != null and card.get_card_id() == card_id:
			return card
	return null

func _count_cards(card_id: String) -> int:
	var total := 0
	for node in get_tree().get_nodes_in_group(&"cards"):
		var card := node as Card
		if card != null and not card.is_queued_for_deletion() \
				and card.card_data != null and card.get_card_id() == card_id:
			total += card.stack_count
	return total

func _drop(unit: Card, target: Card) -> void:
	_board._on_card_dropped(unit, target.global_position + target.size * 0.5)

func _run_gather_tests() -> void:
	# 1. Assign unit ke node → status WORKING, posisi menempel node
	var astronaut := _find_card("unit_astronaut")
	var ice_field := _find_card("node_ice_field")
	_drop(astronaut, ice_field)
	await get_tree().process_frame
	if astronaut.assigned_node != ice_field:
		_fail("gather 1: unit tidak ter-assign ke node")

	# 2. Satu harvest: paksa timer hampir penuh → 1 Ice Chunk spawn, durability 15→14
	var ice_data := ice_field.card_data as NodeCardData
	var ice_before: int = _count_cards("item_ice_chunk")
	astronaut._gather_timer = ice_data.gather_interval_sec + 0.1
	await get_tree().process_frame
	await get_tree().process_frame
	if _count_cards("item_ice_chunk") != ice_before + 1:
		_fail("gather 2: ice chunk tidak bertambah (sebelum %d, sesudah %d)"
			% [ice_before, _count_cards("item_ice_chunk")])
	if ice_field.node_durability_left != 14:
		_fail("gather 2: durability harus 14, sekarang %d" % ice_field.node_durability_left)

	# 3. Tool-block: gas cloud butuh cutting laser — tanpa equip harus ditolak
	var gas_cloud := _find_card("node_gas_cloud")
	_drop(astronaut, gas_cloud)
	await get_tree().process_frame
	if astronaut.assigned_node == gas_cloud:
		_fail("gather 3: assign ke gas cloud harus diblokir tanpa cutting laser")

	# 3b. Equip cutting laser ke astronaut (A6)
	var laser := _find_card("tool_cutting_laser")
	_board._on_card_dropped(laser, astronaut.global_position + astronaut.size * 0.5)
	await get_tree().process_frame
	if not astronaut.has_equipped_tool("tool_cutting_laser"):
		_fail("gather 3b: equip cutting laser gagal")

	# 4. Tool sudah di-equip → assign berhasil, 1 harvest → Space Gas +1
	_drop(astronaut, gas_cloud)
	await get_tree().process_frame
	if astronaut.assigned_node != gas_cloud:
		_fail("gather 4: assign ke gas cloud gagal padahal laser ada")
	var gas_data := gas_cloud.card_data as NodeCardData
	var gas_before: int = _count_cards("item_space_gas")
	astronaut._gather_timer = gas_data.gather_interval_sec + 0.1
	await get_tree().process_frame
	await get_tree().process_frame
	if _count_cards("item_space_gas") != gas_before + 1:
		_fail("gather 4: space gas tidak bertambah")

	# 5. Durability habis → node hilang, unit kembali IDLE
	ice_field.node_durability_left = 1
	ice_field.refresh()
	astronaut._gather_timer = 0.0
	_drop(astronaut, ice_field)
	await get_tree().process_frame
	astronaut._gather_timer = ice_data.gather_interval_sec + 0.1
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(ice_field):
		_fail("gather 5: node ice field harus hilang setelah durability habis")
	if astronaut.assigned_node != null:
		_fail("gather 5: unit harus IDLE setelah node hilang")

	# 6. Unit di-drop ke tempat kosong → unassign (IDLE)
	_drop(astronaut, gas_cloud)
	await get_tree().process_frame
	if astronaut.assigned_node != gas_cloud:
		_fail("gather 6: assign ulang gagal")
	_board._on_card_dropped(astronaut, Vector2(100, 900))
	await get_tree().process_frame
	if astronaut.assigned_node != null:
		_fail("gather 6: drop ke tempat kosong harus unassign unit")