extends Node

# A15 — Waktu linear. Tidak ada lagi tombol "End Day": waktu jalan terus,
# 1 hari = DAY_LENGTH detik. Stat (O2/food/power) terkuras per-detik;
# hal diskrit (travel, event, kematian, efek) diskalakan fraksional.
# end_day() dipertahankan sebagai legacy sekali-jalan-penuh (dipakai test).

const CANISTER_O2_RESTORE := 25.0
const DRONE_POWER_DRAW := 5.0
const BASE_POWER_CAP := 50.0
const DAY_LENGTH := 70.0
# Sekring O2: O2 tepat 0 selama ini (detik) → game over. Menggantikan aturan
# lama "5 hari tanpa oksigen" yang bikin O2 0 tidak mati-mati.
# Life support kapal: regen O2 flat per detik selama ada kru di dalam.
# (0.15/dtk vs konsumsi ~0.07/dtk/unit → 1-2 kru di dalam = O2 nambah,
# 3+ kru = tetap tekor; EVA 2.0/dtk tetap jauh dominan.)
const O2_REGEN_PER_SEC := 0.15
const O2_FUSE_SECONDS := 5.0

var enabled := true  # false = matikan tick (untuk test deterministik)
var _accum := 0.0
var _o2_fuse := 0.0

func _process(delta: float) -> void:
	if not enabled or GameState.is_game_over or GameState.won:
		return
	var board: Board = get_tree().get_first_node_in_group(&"board")
	if board == null:
		return
	if board.get_node_or_null("IntroOverlay") != null:
		return  # waktu belum jalan selama intro
	var day_frac := delta / DAY_LENGTH
	_tick_fraction(board, day_frac)
	_accum += delta
	while _accum >= DAY_LENGTH:
		_accum -= DAY_LENGTH
		GameState.advance_day()
		GameState.update_score()
		GameState.stats_changed.emit()

func day_progress() -> float:
	return clampf(_accum / DAY_LENGTH, 0.0, 1.0)

func day_seconds_left() -> int:
	return int(ceil(DAY_LENGTH - _accum))

# Satu langkah waktu linear sebesar day_frac hari.
func _tick_fraction(board: Board, day_frac: float) -> void:
	var day_float := float(GameState.day) + day_progress()
	var consumption_mult: float = 1.0 + 0.02 * day_float

	var need_food := 0
	var need_oxygen := 0
	for unit in board.get_units():
		var ud := unit.card_data as UnitCardData
		if ud == null:
			continue
		if ud.needs_food:
			need_food += 1
		if ud.needs_oxygen:
			need_oxygen += 1

	# O2 + food terkuras kontinu; stok kartu otomatis menambal saat
	# defisitnya muat satu kartu penuh (tanpa waste spiral per-frame).
	GameState.oxygen = clampf(
		GameState.oxygen - 5.0 * need_oxygen * consumption_mult * day_frac,
		0.0, GameState.O2_MAX)
	_regen_oxygen(board, day_frac)
	_auto_top_up_oxygen(board)
	# Snap: di bawah 0.5 dianggap 0 agar HUD (yang membulatkan) jujur dan
	# counter days_without_oxygen / roll kematian tidak ke-reset regen mikro.
	if GameState.oxygen < 0.5:
		GameState.oxygen = 0.0
	GameState.food = clampf(
		GameState.food - 4.0 * need_food * consumption_mult * day_frac,
		0.0, GameState.FOOD_MAX)
	_auto_eat_food(board)

	if GameState.oxygen <= 0.0:
		GameState.days_without_oxygen += day_frac
		if _o2_fuse <= 0.0:
			board._show_toast("O2 EMPTY! Save the ship!", board.ship_rect.position + Vector2(200, 300), Color(1, 0.4, 0.4))
		_o2_fuse += day_frac * DAY_LENGTH
	else:
		GameState.days_without_oxygen = 0.0
		_o2_fuse = 0.0
	if GameState.food <= 0.0:
		GameState.days_without_food += day_frac
	else:
		GameState.days_without_food = 0.0

	_resolve_power(board, day_frac)
	_resolve_deaths(board, day_frac)
	Packages.resolve_travel(day_frac)
	Events.maybe_spawn_event(day_frac)

	for key in GameState.active_effects.keys():
		GameState.active_effects[key] = float(GameState.active_effects[key]) - day_frac
		if float(GameState.active_effects[key]) <= 0.0:
			GameState.active_effects.erase(key)

	_check_game_over()
	GameState.update_score()
	GameState.stats_changed.emit()

# Legacy: resolve 1 hari penuh sekaligus (dipakai test).
func end_day() -> void:
	if GameState.is_game_over:
		return
	var board: Board = get_tree().get_first_node_in_group(&"board")
	if board == null:
		return
	GameState.advance_day()
	var day := GameState.day
	var consumption_mult: float = 1.0 + 0.02 * day

	var need_food := 0
	var need_oxygen := 0
	for unit in board.get_units():
		var ud := unit.card_data as UnitCardData
		if ud == null:
			continue
		if ud.needs_food:
			need_food += 1
		if ud.needs_oxygen:
			need_oxygen += 1
	var food_need: float = 4.0 * need_food * consumption_mult
	var eaten: float = _consume_food(board, food_need)
	var food_shortage: float = maxf(food_need - eaten, 0.0)

	var o2_restore: float = _consume_canisters(board)

	var o2_consumption: float = 5.0 * need_oxygen * consumption_mult
	var o2_shortage: float = maxf(o2_consumption - o2_restore, 0.0)
	GameState.oxygen = clampf(GameState.oxygen - o2_shortage, 0.0, GameState.O2_MAX)
	_regen_oxygen(board, 1.0)
	if GameState.oxygen < 0.5:
		GameState.oxygen = 0.0
	GameState.food = clampf(GameState.food - food_shortage, 0.0, GameState.FOOD_MAX)
	if GameState.oxygen <= 0.0:
		GameState.days_without_oxygen += 1.0
		_o2_fuse = GameState.days_without_oxygen * DAY_LENGTH
	else:
		GameState.days_without_oxygen = 0.0
		_o2_fuse = 0.0
	if GameState.food <= 0.0:
		GameState.days_without_food += 1.0
	else:
		GameState.days_without_food = 0.0
	_resolve_power(board, 1.0)
	_resolve_deaths(board, 1.0)
	Packages.resolve_travel()
	Events.maybe_spawn_event()
	for key in GameState.active_effects.keys():
		GameState.active_effects[key] = float(GameState.active_effects[key]) - 1.0
		if float(GameState.active_effects[key]) <= 0.0:
			GameState.active_effects.erase(key)
	_check_game_over()
	GameState.update_score()
	GameState.stats_changed.emit()

# ---------- Stok otomatis (jalur linear) ----------

# Life support: O2 nambah selama ada kru bernapas di dalam kapal.
func _regen_oxygen(board: Board, day_frac: float) -> void:
	var crew_inside := false
	for unit in board.get_units():
		var ud := unit.card_data as UnitCardData
		if ud == null or not ud.needs_oxygen:
			continue
		if unit.unit_state == Enums.UnitState.TRAVELING or unit.is_queued_for_deletion():
			continue
		if board.get_zone(unit.global_position + unit.size * 0.5) == Enums.BoardZone.SHIP_INTERIOR:
			crew_inside = true
			break
	if crew_inside:
		GameState.oxygen = clampf(
			GameState.oxygen + O2_REGEN_PER_SEC * day_frac * DAY_LENGTH,
			0.0, GameState.O2_MAX)

# Makan satu kartu canister hanya kalau defisitnya muat penuh (+25).
func _auto_top_up_oxygen(board: Board) -> void:
	if GameState.oxygen >= GameState.O2_MAX:
		return
	for card in board.get_cards_of_id("item_oxygen_canister"):
		if GameState.oxygen > GameState.O2_MAX - CANISTER_O2_RESTORE:
			break
		GameState.oxygen = clampf(GameState.oxygen + CANISTER_O2_RESTORE, 0.0, GameState.O2_MAX)
		card.queue_free()

# Makan satu kartu food hanya kalau defisitnya muat penuh (tanpa waste).
func _auto_eat_food(board: Board) -> void:
	if GameState.food >= GameState.FOOD_MAX:
		return
	for card_node in get_tree().get_nodes_in_group(&"cards"):
		if GameState.food >= GameState.FOOD_MAX:
			break
		var card := card_node as Card
		if card == null or card.is_queued_for_deletion() or card.card_data == null:
			continue
		if card.card_data.category != Enums.CardCategory.ITEM_FOOD:
			continue
		var fd := card.card_data as ItemCardData
		var restore: float = fd.food_restore if fd != null else 0.0
		if restore <= 0.0 or GameState.food > GameState.FOOD_MAX - restore:
			continue
		GameState.food = clampf(GameState.food + restore, 0.0, GameState.FOOD_MAX)
		card.queue_free()
		break  # satu kartu per tick cukup

# ---------- 2. Konsumsi food (jalur legacy end_day) ----------

func _consume_food(_board: Board, need: float) -> float:
	var eaten := 0.0
	for card_node in get_tree().get_nodes_in_group(&"cards"):
		if eaten >= need:
			break
		var card := card_node as Card
		if card == null or card.is_queued_for_deletion() or card.card_data == null:
			continue
		if card.card_data.category != Enums.CardCategory.ITEM_FOOD:
			continue
		var fd := card.card_data as ItemCardData
		var restore: float = fd.food_restore if fd != null else 0.0
		if restore <= 0.0:
			continue
		eaten += restore
		card.queue_free()
	return eaten

# ---------- 3. O2 canister (jalur legacy end_day) ----------

func _consume_canisters(board: Board) -> float:
	var restored := 0.0
	for card in board.get_cards_of_id("item_oxygen_canister"):
		if GameState.oxygen >= GameState.O2_MAX:
			break
		restored += CANISTER_O2_RESTORE
		card.queue_free()
	return restored

# ---------- 4. Power (A11/A14) ----------

func _resolve_power(board: Board, day_frac: float = 1.0) -> void:
	var generated := 0.0
	var cap := BASE_POWER_CAP
	for building in board.get_built_buildings():
		var bd := building.card_data as BuildingCardData
		if bd == null:
			continue
		cap += bd.power_generated
		generated += bd.power_generated
	if float(GameState.active_effects.get("power_debuff", 0)) > 0.0:
		generated *= 0.5
	var consumption := 0.0
	for building in board.get_built_buildings():
		var bd := building.card_data as BuildingCardData
		if bd != null and not building.is_off:
			consumption += bd.power_draw
	for unit in board.get_units():
		var ud := unit.card_data as UnitCardData
		if ud != null and ud.role == Enums.UnitRole.ROBOT_DRONE \
				and (unit.assigned_node != null or unit.assigned_building != null):
			consumption += DRONE_POWER_DRAW
	GameState.power_cap = cap
	var rate: float = (generated - consumption) / DAY_LENGTH
	# Proyeksi tick ini: kalau pool jebol, matikan beban terbesar dulu.
	var again := true
	while again and GameState.power + rate * day_frac * DAY_LENGTH < 0.0:
		again = false
		var victim: Card = null
		var victim_draw := 0.0
		for building in board.get_built_buildings():
			if building.is_off:
				continue
			var bd := building.card_data as BuildingCardData
			if bd == null or bd.passive_effect == "prevent_death" \
					or building.get_card_id() == "building_oxygen_generator":
				continue
			if victim == null or bd.power_draw > victim_draw:
				victim = building
				victim_draw = bd.power_draw
		if victim != null:
			victim.is_off = true
			victim.refresh()
			rate = (generated - _current_consumption(board)) / DAY_LENGTH
			again = true
	GameState.power = clampf(GameState.power + rate * day_frac * DAY_LENGTH, 0.0, GameState.power_cap)
	# Nyalakan lagi yang mati kalau pool muat menanggung draw-nya.
	for building in board.get_built_buildings():
		if not building.is_off:
			continue
		var bd := building.card_data as BuildingCardData
		var draw: float = bd.power_draw if bd != null else 0.0
		if GameState.power - draw >= 0.0:
			building.is_off = false
			building.refresh()

func _current_consumption(board: Board) -> float:
	var consumption := 0.0
	for building in board.get_built_buildings():
		var bd := building.card_data as BuildingCardData
		if bd != null and not building.is_off:
			consumption += bd.power_draw
	for unit in board.get_units():
		var ud := unit.card_data as UnitCardData
		if ud != null and ud.role == Enums.UnitRole.ROBOT_DRONE \
				and (unit.assigned_node != null or unit.assigned_building != null):
			consumption += DRONE_POWER_DRAW
	return consumption

# ---------- 5. Kematian (A14) ----------

func _resolve_deaths(board: Board, day_frac: float = 1.0) -> void:
	# 25%/hari saat O2 nol → peluang fraksional per tick.
	var death_p: float = 1.0 - pow(0.75, day_frac)
	for unit in board.get_units().duplicate():
		var roll := randf()
		var should_die := roll < death_p and GameState.oxygen <= 0.0
		if should_die:
			_kill_unit(board, unit, "critical O2")
	# Food nol 3 hari → 1 unit mati
	if GameState.days_without_food >= 3.0:
		var alive := board.get_units()
		if not alive.is_empty():
			var victim: Card = alive[randi() % alive.size()]
			_kill_unit(board, victim, "Starvation")

func _kill_unit(board: Board, unit: Card, reason: String) -> void:
	if unit == null or not is_instance_valid(unit) or unit.is_queued_for_deletion():
		return
	board._show_toast("%s died (%s)" % [unit.card_data.display_name, reason],
		unit.global_position, Color(1, 0.45, 0.45))
	unit.set_unit_state(Enums.UnitState.DEAD)
	unit.set_gather_progress(-1.0)
	unit.queue_free()

# ---------- 10. Game over ----------

func _check_game_over() -> void:
	var board: Board = get_tree().get_first_node_in_group(&"board")
	if GameState.hull <= 0.0:
		GameState.end_game("Ship hull destroyed")
	elif board != null and board.get_units().is_empty():
		GameState.end_game("All units died")
	elif GameState.days_without_oxygen >= 5.0 or _o2_fuse >= O2_FUSE_SECONDS:
		GameState.end_game("O2 depleted for too long")
	elif GameState.days_without_food >= 5.0:
		GameState.end_game("Crew starved to death")
