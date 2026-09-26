class_name Board
extends Control

const CARD_SCENE := preload("res://scenes/card.tscn")

# Background art opsional: satu gambar full-board (kiri = interior kapal
# 45% lebar, kanan = angkasa 55%). Kalau belum ada, pakai warna datar lama.
#   assets/ui/board_bg.png
const BOARD_BG_PATH := "res://assets/ui/board_bg.png"

var ship_rect := Rect2()
var open_rect := Rect2()

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	Sfx.play_music("game")
	add_to_group(&"board")
	_build_zones()
	if DisplayServer.get_name() == "headless" and not force_intro:
		_spawn_test_cards()   # test/debug: layout penuh sekaligus, tanpa intro
	else:
		_spawn_world_nodes()  # main: node dunia + starter kit via intro buka-pack
		_run_intro()
	_show_data_debug()
	_spawn_hud()

func _process(delta: float) -> void:
	_tick_gather(delta)
	_tick_production(delta)
	_tick_eva_oxygen(delta)
	_tick_monster(delta)
	_tick_emergency(delta)
	_tick_contracts(delta)
	_tick_quests(delta)
	_tick_deadlines(delta)
	_tick_danger_alarm(delta)
	_tick_vignette()
	_tick_shake(delta)

func _build_zones() -> void:
	var viewport_size := get_viewport_rect().size
	var divider_x: float = viewport_size.x * 0.40
	ship_rect = Rect2(0, 0, divider_x, viewport_size.y)
	open_rect = Rect2(divider_x, 0, viewport_size.x - divider_x, viewport_size.y)

	if ResourceLoader.exists(BOARD_BG_PATH):
		var bg_art := TextureRect.new()
		bg_art.texture = load(BOARD_BG_PATH)
		bg_art.position = Vector2.ZERO
		bg_art.size = viewport_size
		bg_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg_art.stretch_mode = TextureRect.STRETCH_SCALE
		bg_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg_art)
		move_child(bg_art, 0)
	else:
		var ship_bg := ColorRect.new()
		ship_bg.color = Color(0.13, 0.16, 0.2)
		ship_bg.position = ship_rect.position
		ship_bg.size = ship_rect.size
		ship_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(ship_bg)

		var open_bg := ColorRect.new()
		open_bg.color = Color(0.07, 0.08, 0.13)
		open_bg.position = open_rect.position
		open_bg.size = open_rect.size
		open_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(open_bg)

	var divider := ColorRect.new()
	divider.color = Color(0.4, 0.5, 0.7, 0.6)
	divider.position = Vector2(divider_x - 2, 0)
	divider.size = Vector2(4, viewport_size.y)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divider.visible = false  # garis divider disembunyikan (user)
	add_child(divider)

	_add_vignette(viewport_size)
	_make_preview_label()

# Overlay vignette + grain (UIFactory.vignette).
# Di atas kartu & toast (z 400), di bawah HUD (500) & intro (600).
# Material disimpan agar strength bisa naik dinamis saat kritis (lihat _tick_vignette).
var _vignette_mat: ShaderMaterial = null

func _add_vignette(viewport_size: Vector2) -> void:
	var overlay := UIFactory.vignette(self, viewport_size, 400)
	if overlay != null and overlay.material is ShaderMaterial:
		_vignette_mat = overlay.material as ShaderMaterial

# Label preview hasil combine saat drag hover (hijau = jadi, merah = syarat).
var _preview_label: Label

func _make_preview_label() -> void:
	_preview_label = Label.new()
	_preview_label.visible = false
	_preview_label.z_index = 400
	_preview_label.add_theme_font_size_override("font_size", 16)
	_preview_label.add_theme_color_override("font_color", Color(0.55, 1, 0.6))
	_preview_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_preview_label.add_theme_constant_override("outline_size", 6)
	_preview_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_preview_label)

func update_combine_preview(dragged: Card, at_position: Vector2 = Vector2.INF) -> void:
	if _preview_label == null:
		return
	var mouse := at_position if at_position != Vector2.INF else get_global_mouse_position()
	var target := _card_at(mouse, dragged)
	var recipe: CraftRecipe = null
	if target != null:
		recipe = RecipeResolver.find_recipe(dragged, target, self)
	if recipe == null:
		_preview_label.visible = false
		return
	var blocked := RecipeResolver.check_blocked(recipe, self)
	if blocked != "":
		_preview_label.text = blocked
		_preview_label.add_theme_color_override("font_color", Color(1, 0.6, 0.55))
	else:
		var out: CardData = CardDB.get_card(recipe.output_id)
		var out_name: String = out.display_name if out != null else recipe.output_id
		if recipe.output_qty > 1:
			out_name += " x%d" % recipe.output_qty
		_preview_label.text = "+ " + out_name
		_preview_label.add_theme_color_override("font_color", Color(0.55, 1, 0.6))
	_preview_label.position = mouse + Vector2(16, -30)
	_preview_label.visible = true

func hide_combine_preview() -> void:
	if _preview_label != null:
		_preview_label.visible = false

func get_zone(pos: Vector2) -> Enums.BoardZone:
	if ship_rect.has_point(pos):
		return Enums.BoardZone.SHIP_INTERIOR
	return Enums.BoardZone.OPEN_SPACE

# ---------- Validasi drop (A1.2, A2) ----------

func validate_drop(card: Card) -> bool:
	var zone := get_zone(card.global_position + card.size * 0.5)
	match card.card_data.category:
		Enums.CardCategory.BUILDING:
			return zone == Enums.BoardZone.SHIP_INTERIOR
		Enums.CardCategory.NODE:
			return zone == Enums.BoardZone.OPEN_SPACE
		Enums.CardCategory.PACKAGE:
			return zone == Enums.BoardZone.SHIP_INTERIOR
		Enums.CardCategory.UNIT:
			# Unit boleh kerja di mana saja (kapal maupun angkasa). Di Zona
			# Angkasa tidak butuh tether/tank lagi — cukup memakai O2 dari stok
			# kapal (5 O2/hari per unit, lihat DayCycle).
			return true
		_:
			return true

# ---------- Routing drop (A5/A6/A7/A8/A10/A13) ----------

func _on_card_dropped(card: Card, position: Vector2) -> void:
	card.refresh_zone_frame()
	var target: Card = _card_at(position, card)

	# A7: Building → bayar build_cost (A5)
	if card.is_building():
		if card.is_built:
			return
		if not _try_build(card):
			card.global_position = card._pre_drag_position
		return

	# A6: Tool → Unit (equip / consumable)
	if card.is_tool() and target != null and target.is_unit():
		_try_equip_tool(card, target)
		return

	# A7: Unit → Building (assign kerja)
	if card.is_unit() and target != null and target.is_building():
		_try_assign_building(card, target)
		return

	# A3: Unit → Node
	if card.is_unit() and target != null and target.is_node():
		_try_assign(card, target)
		return

	# A8: Unit → Package (depart jika lengkap)
	if card.is_unit() and target != null and target.is_package():
		Packages.try_depart(self, card, target)
		return

	# A8: Item → Package (assembly)
	if card.card_data.category == Enums.CardCategory.ITEM_RAW \
			or card.card_data.category == Enums.CardCategory.ITEM_PROCESSED:
		if target != null and target.is_package():
			Packages.try_assemble(self, card, target)
			return

	if card.is_unit():
		card.unassign()
		card.unassign_from_building()

	# A13: combine manual
	var recipe := RecipeResolver.find_recipe(card, target, self)
	if recipe == null:
		return
	var blocked: String = RecipeResolver.check_blocked(recipe, self)
	if blocked != "":
		_show_toast(blocked, position, Color(1, 0.6, 0.55))
		return
	var spawned := RecipeResolver.execute(recipe, card, target, self, position)
	var output: CardData = CardDB.get_card(recipe.output_id)
	var output_name: String = output.display_name if output != null else recipe.output_id
	if spawned != null:
		_flash_card(spawned, Color(3.0, 3.0, 3.0, 1.0))
	Sfx.play("combine")
	_show_toast("+ " + output_name, position, Color(0.55, 1, 0.6))

# Flash warna singkat di kartu (juice combine / serangan monster).
func _flash_card(c: Card, color: Color) -> void:
	if c == null or not is_instance_valid(c) or c.is_queued_for_deletion():
		return
	var tw := create_tween()
	tw.tween_property(c, "modulate", color, 0.07)
	tw.tween_property(c, "modulate", Color.WHITE, 0.15)

# ---------- A6: equip tool ----------

func _try_equip_tool(tool_card: Card, unit: Card) -> void:
	var tool_data := tool_card.card_data as ToolCardData
	if tool_data == null:
		return
	if tool_data.is_consumable:
		# consumable: langsung pakai efeknya, kartu tool hilang
		Economy.apply_tool_effect(tool_card.get_card_id(), self)
		tool_card.queue_free()
		return
	if unit.has_equipped_tool(tool_card.get_card_id()):
		_show_toast("Already equipped", tool_card.global_position, Color(1, 0.8, 0.5))
		return
	if not unit.equipped_tool_ids.is_empty():
		_show_toast("Already carrying a tool (right-click unit to remove)", tool_card.global_position, Color(1, 0.8, 0.5))
		return
	unit.equip_tool(tool_card.get_card_id())
	tool_card.queue_free()
	var tool_name: String = tool_data.display_name
	_show_toast("Equip: " + tool_name, unit.global_position, Color(0.55, 1, 0.6))

# ---------- A7: assign unit ke building ----------

func _try_assign_building(unit_card: Card, building_card: Card) -> void:
	if not building_card.is_built:
		_show_toast("Building not built yet!", unit_card.global_position, Color(1, 0.6, 0.55))
		return
	if building_card.is_off:
		_show_toast("Building offline (low power)", unit_card.global_position, Color(1, 0.6, 0.55))
		return
	var building_data := building_card.card_data as BuildingCardData
	if building_data != null and building_data.max_unit_slots > 0:
		var used := 0
		for card_node in get_tree().get_nodes_in_group(&"cards"):
			var other := card_node as Card
			if other != null and other.is_unit() and other.assigned_building == building_card:
				used += 1
		if used >= building_data.max_unit_slots:
			_show_toast("Building unit slots full", unit_card.global_position, Color(1, 0.6, 0.55))
			return
	if unit_card.assigned_node != null:
		unit_card.unassign()
	unit_card.assign_to_building(building_card)
	_show_toast("WORKING: " + building_card.card_data.display_name,
		unit_card.global_position, Color(0.55, 1, 0.6))

# ---------- A3: gather ----------

func _try_assign(unit_card: Card, node_card: Card) -> void:
	var node_data := node_card.card_data as NodeCardData
	if node_data == null:
		return
	if node_data.required_tool_id != "" and not unit_card.has_equipped_tool(node_data.required_tool_id):
		var tool: CardData = CardDB.get_card(node_data.required_tool_id)
		var tool_name: String = tool.display_name if tool != null else node_data.required_tool_id
		_show_toast("Needs tool: " + tool_name, unit_card.global_position, Color(1, 0.6, 0.55))
		return
	if unit_card.assigned_building != null:
		unit_card.unassign_from_building()
	unit_card.assign_to_node(node_card)
	_show_toast("Gathering: " + node_card.card_data.display_name,
		unit_card.global_position, Color(0.55, 1, 0.6))

func has_tool(tool_id: String) -> bool:
	for node in get_tree().get_nodes_in_group(&"cards"):
		var card := node as Card
		if card == null or card.is_queued_for_deletion() or card.card_data == null:
			continue
		if card.card_data.category == Enums.CardCategory.TOOL and card.get_card_id() == tool_id:
			return true
	return false

func _tick_gather(delta: float) -> void:
	for node in get_tree().get_nodes_in_group(&"cards"):
		var unit := node as Card
		if unit == null or unit.is_queued_for_deletion():
			continue
		if unit.assigned_node == null:
			continue
		if unit.assigned_node.is_queued_for_deletion():
			unit.unassign()
			continue
		var node_data := unit.assigned_node.card_data as NodeCardData
		if node_data == null:
			unit.unassign()
			continue
		var interval: float = node_data.gather_interval_sec / _unit_efficiency(unit, unit.assigned_node)
		unit._gather_timer += delta
		unit.set_gather_progress(unit._gather_timer / interval)
		if unit._gather_timer >= interval:
			unit._gather_timer = 0.0
			_harvest(unit, unit.assigned_node, node_data)
			unit.set_gather_progress(0.0)

func _unit_efficiency(unit: Card, node: Card) -> float:
	var unit_data := unit.card_data as UnitCardData
	if unit_data == null:
		return 1.0
	var eff: float = float(unit_data.role_efficiency_map.get(node.get_card_id(), 1.0))
	# A6: Mining Drill → gather di Asteroid Field 2× lebih cepat
	var drill := CardDB.get_card("tool_mining_drill") as ToolCardData
	if unit.has_equipped_tool("tool_mining_drill") and node.get_card_id() == "node_asteroid_field" \
			and drill != null:
		eff *= drill.effect_value
	return eff

# ---------- A7: produksi building real-time ----------

const PRODUCTION_SECONDS_PER_DAY := 10.0

func _tick_production(delta: float) -> void:
	for building in get_built_buildings():
		var bd := building.card_data as BuildingCardData
		if bd == null or bd.production.is_empty():
			continue
		if building.is_off:
			continue
		var prod: Dictionary = bd.production
		var in_id: String = prod.get("input_item_id", "")
		var in_qty: int = int(prod.get("input_qty", 1))
		if in_id != "" and count_item(in_id) < in_qty:
			continue
		var workers: Array[Card] = []
		for unit in get_units():
			if unit.assigned_building == building:
				workers.append(unit)
		if workers.is_empty():
			continue
		var interval: float = float(int(prod.get("interval_days", 1))) * PRODUCTION_SECONDS_PER_DAY
		building.production_timer += delta
		var progress: float = building.production_timer / interval
		for worker in workers:
			worker.set_gather_progress(progress)
		if building.production_timer < interval:
			continue
		building.production_timer = 0.0
		if in_id != "":
			consume_item(in_id, in_qty)
		var out_id: String = prod.get("output_item_id", "")
		var out_qty: int = int(prod.get("output_qty", 1))
		if out_id != "":
			spawn_card_at(out_id, building.global_position + Vector2(0.0, building.size.y + 30.0), out_qty)
			var out_data: CardData = CardDB.get_card(out_id)
			_show_toast("+ %s x%d" % [out_data.display_name if out_data != null else out_id, out_qty],
				building.global_position + Vector2(0.0, 30.0), Color(0.55, 1, 0.6))
		for worker in workers:
			worker.set_gather_progress(0.0)

# ---------- O2 bocor real-time saat EVA ----------

# Semua unit bernapas di Zona Angkasa menguras stok kapal 2.0/detik
# (di luar TRAVELING; drone tidak bernapas jadi tidak kena).
const EVA_O2_DRAIN := 2.0

func _tick_eva_oxygen(delta: float) -> void:
	if GameState.is_game_over:
		return
	var drain := 0.0
	for unit in get_units():
		if unit.unit_state == Enums.UnitState.TRAVELING or unit.is_queued_for_deletion():
			continue
		var ud := unit.card_data as UnitCardData
		if ud == null or not ud.needs_oxygen:
			continue
		if get_zone(unit.global_position + unit.size * 0.5) != Enums.BoardZone.OPEN_SPACE:
			continue
		drain += EVA_O2_DRAIN
	if drain <= 0.0:
		return
	GameState.oxygen = clampf(GameState.oxygen - drain * delta,
		0.0, GameState.O2_MAX)
	GameState.stats_changed.emit()

# ---------- Monster hari ke-4 ----------
# Muncul di kanan sekali saat hari ke-4, jalan ke kiri tiap beberapa detik,
# menyerang Hull tiap beberapa detik setelah sampai di kapal.

const MONSTER_ID := "event_space_monster"
const MONSTER_DAY := 4
const MONSTER_MOVE_EVERY := 4.0
const MONSTER_STEP := 140.0
const MONSTER_ATTACK_EVERY := 4.0
const MONSTER_ATTACK_DMG := 8.0

var monster_event_done := false
var _monsters: Array[Dictionary] = []

func spawn_monster() -> Card:
	var pos := Vector2(open_rect.end.x - 70.0, open_rect.position.y + open_rect.size.y * 0.45)
	var card := spawn_card_at(MONSTER_ID, pos)
	if card == null:
		return null
	_monsters.append({"card": card, "timer": 0.0, "attacking": false})
	_show_toast("MONSTER incoming from the right! Prepare your defenses!",
		pos, Color(1, 0.6, 0.4))
	return card

func _tick_monster(delta: float) -> void:
	if GameState.is_game_over or GameState.won:
		return
	if get_node_or_null("IntroOverlay") != null:
		return
	if not monster_event_done and GameState.day >= MONSTER_DAY:
		monster_event_done = true
		spawn_monster()
	for entry in _monsters.duplicate():
		var card: Card = entry.get("card")
		if card == null or not is_instance_valid(card) or card.is_queued_for_deletion():
			_monsters.erase(entry)
			continue
		entry["timer"] = float(entry.get("timer", 0.0)) + delta
		var attacking: bool = bool(entry.get("attacking", false))
		var interval: float = MONSTER_ATTACK_EVERY if attacking else MONSTER_MOVE_EVERY
		if float(entry["timer"]) < interval:
			continue
		entry["timer"] = 0.0
		if attacking:
			GameState.hull = maxf(GameState.hull - MONSTER_ATTACK_DMG, 0.0)
			if GameState.hull <= 0.0:				# Alasan sendiri biar ending dapat flavour monster (end_game
				# mengunci alasan pertama; cek generik DayCycle tak menimpa).
				GameState.end_game("Space monster tore the hull apart")
			add_shake(10.0)
			Sfx.play("danger")
			_flash_card(card, Color(1.0, 0.3, 0.3, 1.0))
			_show_toast("Monster attacks! Hull -%d" % int(MONSTER_ATTACK_DMG),
				card.global_position, Color(1, 0.45, 0.45))
			_hud_show_defense()
			GameState.stats_changed.emit()
		else:
			var edge := ship_rect.end.x + 10.0
			var target_x := maxf(card.global_position.x - MONSTER_STEP, edge)
			if target_x <= edge:
				entry["attacking"] = true
				_show_toast("Monster reached the ship!", card.global_position, Color(1, 0.5, 0.5))
				_hud_show_defense()
			var tween := create_tween()
			tween.tween_property(card, "global_position:x", target_x, 0.5)

func _hud_show_defense() -> void:
	var hud: HUD = get_node_or_null("HUD")
	if hud != null:
		hud.show_defense_bar(true)

# ---------- Deadline kontrak (paket kedaluwarsa) ----------
# Kontrak (non-SOS, non-quest) hangus kalau deadline_days lewat sejak spawn.
# Quest dikecualikan (krusial buat menang); SOS punya timer sendiri.
# Sisa hari tampil di kartu via _deadline_text(), merah saat < 1 hari.

func _tick_deadlines(delta: float) -> void:
	if GameState.is_game_over or GameState.won:
		return
	if get_node_or_null("IntroOverlay") != null:
		return
	var day_frac := delta / DayCycle.DAY_LENGTH
	for card_node in get_tree().get_nodes_in_group(&"cards"):
		var card := card_node as Card
		if card == null or card.is_queued_for_deletion() or not card.is_package():
			continue
		if card.has_meta("emergency") or card.get_card_id().begins_with("pkg_quest_"):
			continue
		var pkg := card.card_data as PackageCardData
		if pkg == null:
			continue
		if not card.has_meta("deadline_left"):
			card.set_meta("deadline_left", float(maxi(1, pkg.deadline_days)))
		var left: float = float(card.get_meta("deadline_left")) - day_frac
		card.set_meta("deadline_left", left)
		if left <= 0.0:
			_show_toast("Contract expired: " + card.card_data.display_name,
				card.global_position, Color(1, 0.5, 0.5))
			card.queue_free()
		else:
			card.refresh()

# ---------- Alarm bahaya (SFX danger + vignette) ----------

var _danger_cooldown := 0.0
const DANGER_EVERY := 8.0

# Stinger bahaya berkala selama ada stat kritis (Hull/O2/Food < 25%).
func _tick_danger_alarm(delta: float) -> void:
	_danger_cooldown = maxf(0.0, _danger_cooldown - delta)
	if GameState.is_game_over or GameState.won or _danger_cooldown > 0.0:
		return
	if get_node_or_null("IntroOverlay") != null:
		return
	var critical := GameState.hull < GameState.HULL_MAX * 0.25 \
		or GameState.oxygen < GameState.O2_MAX * 0.25 \
		or GameState.food < GameState.FOOD_MAX * 0.25
	if critical:
		_danger_cooldown = DANGER_EVERY
		Sfx.play("danger")

# Tunnel-vision: vignette mengetat saat Hull/O2 kritis (0.65 normal → 0.95).
func _tick_vignette() -> void:
	if _vignette_mat == null:
		return
	var danger := 0.0
	if not GameState.is_game_over:
		var hull_frac := clampf(GameState.hull / GameState.HULL_MAX, 0.0, 1.0)
		var o2_frac := clampf(GameState.oxygen / GameState.O2_MAX, 0.0, 1.0)
		if hull_frac < 0.25:
			danger = maxf(danger, 1.0 - hull_frac / 0.25)
		if o2_frac < 0.25:
			danger = maxf(danger, 1.0 - o2_frac / 0.25)
	_vignette_mat.set_shader_parameter("strength", 0.65 + danger * 0.3)

# ---------- Screen shake (dipicu serangan monster) ----------

var _shake_strength := 0.0

func add_shake(strength: float) -> void:
	_shake_strength = maxf(_shake_strength, strength)

func _tick_shake(delta: float) -> void:
	if _shake_strength <= 0.0:
		if position != Vector2.ZERO:
			position = Vector2.ZERO
		return
	position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_strength
	_shake_strength = maxf(_shake_strength - delta * 30.0, 0.0)

# ---------- Paket darurat (butuh Space Telephone di board) ----------

const EMERGENCY_TIME := 120.0
const EMERGENCY_COOLDOWN := 90.0

var _emergency_cooldown := 45.0

func has_market() -> bool:
	return has_card_id("item_space_telephone")

func _tick_emergency(delta: float) -> void:
	if GameState.is_game_over or GameState.won:
		return
	if get_node_or_null("IntroOverlay") != null:
		return
	var active: Card = null
	for card_node in get_tree().get_nodes_in_group(&"cards"):
		var card := card_node as Card
		if card != null and not card.is_queued_for_deletion() and card.is_package() \
				and card.has_meta("emergency"):
			active = card
			break
	if active == null:
		if has_market():
			_emergency_cooldown -= delta
			if _emergency_cooldown <= 0.0:
				_emergency_cooldown = EMERGENCY_COOLDOWN
				_spawn_emergency()
		return
	var left: float = float(active.get_meta("time_left", 0.0)) - delta
	active.set_meta("time_left", left)
	active.refresh()
	if active.is_package_complete():
		var pkg := active.card_data as PackageCardData
		GameState.add_credits(pkg.reward_credits)
		GameState.add_reputation(pkg.reward_rep)
		GameState.total_packages_delivered += 1
		GameState.update_score()
		GameState.stats_changed.emit()
		_show_toast("SOS sent! +%d cr +%d rep" % [pkg.reward_credits, pkg.reward_rep],
			active.global_position, Color(0.55, 1, 0.6))
		active.queue_free()
	elif left <= 0.0:
		_show_toast("SOS failed... package expired", active.global_position, Color(1, 0.5, 0.5))
		active.queue_free()

func _spawn_emergency() -> void:
	var card := spawn_card_at("pkg_emergency_sos", random_free_spot(Enums.BoardZone.SHIP_INTERIOR))
	if card == null:
		return
	card.set_meta("emergency", true)
	card.set_meta("time_left", EMERGENCY_TIME)
	card.refresh()
	_show_toast("EMERGENCY package! Supply materials, %ds!" % int(EMERGENCY_TIME),
		card.global_position, Color(1, 0.85, 0.5))

# ---------- Kontrak paket (misi final: layani semua sektor) ----------

const CONTRACT_IDS := ["pkg_scrap_run", "pkg_ore_haul", "pkg_gas_refill",
	"pkg_deep_relay", "pkg_alien_artifacts"]
const CONTRACT_EVERY := 75.0
const CONTRACT_FIRST := 20.0
const CONTRACT_MAX := 2

var _contract_timer := CONTRACT_FIRST

func _tick_contracts(delta: float) -> void:
	if GameState.is_game_over or GameState.won:
		return
	if get_node_or_null("IntroOverlay") != null:
		return
	if not has_market():
		return
	var active := 0
	for card_node in get_tree().get_nodes_in_group(&"cards"):
		var card := card_node as Card
		if card != null and not card.is_queued_for_deletion() and card.is_package() \
				and not card.has_meta("emergency"):
			active += 1
	if active >= CONTRACT_MAX:
		return
	_contract_timer -= delta
	if _contract_timer > 0.0:
		return
	_contract_timer = CONTRACT_EVERY
	_spawn_contract()

func _spawn_contract() -> void:
	var pool: Array[String] = []
	for pid in CONTRACT_IDS:
		if CardDB.get_card(pid) is PackageCardData:
			pool.append(pid)
	if pool.is_empty():
		return
	var pid: String = pool[_rng.randi() % pool.size()]
	var card := spawn_card_at(pid, random_free_spot(Enums.BoardZone.SHIP_INTERIOR))
	if card == null:
		return
	var data := CardDB.get_card(pid) as PackageCardData
	_show_toast("New contract: " + data.display_name, card.global_position, Color(0.7, 0.95, 1))

# ---------- Quest linear (syarat menang; butuh telephone) ----------

var _quest_timer := 5.0

func _tick_quests(delta: float) -> void:
	if GameState.is_game_over or GameState.won:
		return
	if get_node_or_null("IntroOverlay") != null:
		return
	_quest_timer -= delta
	if _quest_timer > 0.0:
		return
	_quest_timer = 5.0
	if not has_market():
		return
	for pid in Packages.QUEST_ORDER:
		if GameState.quest_done.has(pid):
			continue
		for card_node in get_tree().get_nodes_in_group(&"cards"):
			var card := card_node as Card
			if card != null and not card.is_queued_for_deletion() \
					and card.get_card_id() == pid:
				return  # quest ini sedang aktif, tunggu selesai
		spawn_quest(pid)
		return

func spawn_quest(pid: String) -> void:
	var card := spawn_card_at(pid, random_free_spot(Enums.BoardZone.SHIP_INTERIOR))
	if card == null:
		return
	var data := CardDB.get_card(pid) as PackageCardData
	_show_toast("New quest: " + data.display_name, card.global_position, Color(0.7, 0.95, 1))

func _harvest(unit: Card, node: Card, node_data: NodeCardData) -> void:
	var item_id: String = node_data.output_item_id
	if node_data.secondary_output_item_id != "" \
			and _rng.randf() < node_data.secondary_chance:
		item_id = node_data.secondary_output_item_id
	_spawn_nearby(item_id, node, node_data.output_qty)
	if node_data.is_limited:
		node.node_durability_left -= 1
		node.refresh()
		if node.node_durability_left <= 0:
			_deplete_node(node)

func _deplete_node(node: Card) -> void:
	for card_node in get_tree().get_nodes_in_group(&"cards"):
		var card := card_node as Card
		if card != null and card.assigned_node == node:
			card.unassign()
	node.queue_free()

func _spawn_nearby(item_id: String, node: Card, count: int) -> void:
	var candidate_positions: Array[Vector2] = [
		node.global_position + Vector2(-98.0, 15.0),
		node.global_position + Vector2(node.size.x + 8.0, 15.0),
		node.global_position + Vector2(15.0, -143.0),
		node.global_position + Vector2(15.0, node.size.y + 8.0),
		node.global_position + Vector2(-98.0, node.size.y + 8.0),
		node.global_position + Vector2(node.size.x + 8.0, node.size.y + 8.0),
		node.global_position + Vector2(-98.0, -143.0),
		node.global_position + Vector2(node.size.x + 8.0, -143.0),
	]
	for pos in candidate_positions:
		if _is_slot_free(pos):
			spawn_card_at(item_id, pos + Vector2(45.0, 64.0), count)
			return
	spawn_card_at(item_id, node.global_position + Vector2(node.size.x * 0.5, -45.0), count)

func _is_slot_free(position: Vector2) -> bool:
	for card_node in get_tree().get_nodes_in_group(&"cards"):
		var card := card_node as Card
		if card == null or card.is_queued_for_deletion() or card.card_data == null:
			continue
		if card.get_global_rect().grow(10.0).has_point(position):
			return false
	return true

func _card_at(position: Vector2, exclude: Card) -> Card:
	var best: Card = null
	for node in get_tree().get_nodes_in_group(&"cards"):
		var candidate: Card = node as Card
		if candidate == null or candidate == exclude or candidate.is_queued_for_deletion():
			continue
		if candidate.card_data == null:
			continue
		if not candidate.get_global_rect().grow(6.0).has_point(position):
			continue
		if best == null or candidate.z_index >= best.z_index:
			best = candidate
	return best

func has_building(building_id: String) -> bool:
	return has_card_id(building_id, true)

# require_built = true: kalau kartunya Building, harus sudah is_built dulu
# (Unit/item lain tidak punya konsep "built" jadi tidak kena filter ini).
func has_card_id(card_id: String, require_built := false) -> bool:
	for node in get_tree().get_nodes_in_group(&"cards"):
		var card := node as Card
		if card == null or card.is_queued_for_deletion() or card.card_data == null:
			continue
		if card.get_card_id() != card_id:
			continue
		if require_built and card.is_building() and not card.is_built:
			continue
		return true
	return false

# Kartu longgar (bukan yg di-exclude) dalam radius tertentu dari sebuah titik.
# Dipakai RecipeResolver untuk combine 3+ input (pool di sekitar titik drop).
func get_cards_near(position: Vector2, radius: float) -> Array[Card]:
	var result: Array[Card] = []
	for node in get_tree().get_nodes_in_group(&"cards"):
		var card := node as Card
		if card == null or card.is_queued_for_deletion() or card.card_data == null:
			continue
		if card.global_position.distance_to(position) <= radius:
			result.append(card)
	return result

func has_unit_role(role: int) -> bool:
	for node in get_tree().get_nodes_in_group(&"cards"):
		var card := node as Card
		if card == null or card.is_queued_for_deletion() or card.card_data == null:
			continue
		if card.card_data.category != Enums.CardCategory.UNIT:
			continue
		var unit_data := card.card_data as UnitCardData
		if unit_data != null and unit_data.role == role:
			return true
	return false

func _show_toast(text: String, position: Vector2, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = position
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "position:y", position.y - 44.0, 1.1)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 1.1)
	tween.tween_callback(label.queue_free)
	var hud: HUD = get_node_or_null("HUD")
	if hud != null:
		hud.add_log(text, color)

# ---------- A7: build cost ----------

func _try_build(building_card: Card) -> bool:
	var building_data := building_card.card_data as BuildingCardData
	if building_data == null:
		return false
	var missing: Array[String] = []
	var cost: Array = building_data.build_cost
	for req in cost:
		var item_id: String = req.get("item_id", "")
		var qty: int = int(req.get("qty", 1))
		var have: int = count_item(item_id)
		if have < qty:
			var item: CardData = CardDB.get_card(item_id)
			missing.append("%s x%d" % [item.display_name if item != null else item_id, qty - have])
	if not missing.is_empty():
		_show_toast("Need: " + ", ".join(missing), building_card.global_position, Color(1, 0.6, 0.55))
		return false
	for req in cost:
		consume_item(req.get("item_id", ""), int(req.get("qty", 1)))
	building_card.is_built = true
	building_card.is_off = false
	building_card.refresh()
	_show_toast("Built: " + building_card.card_data.display_name,
		building_card.global_position, Color(0.55, 1, 0.6))
	return true

# ---------- Helper untuk sistem lain (DayCycle/Economy/Packages) ----------

func count_item(item_id: String) -> int:
	var total := 0
	for card_node in get_tree().get_nodes_in_group(&"cards"):
		var card := card_node as Card
		if card == null or card.is_queued_for_deletion() or card.card_data == null:
			continue
		if card.get_card_id() == item_id:
			total += card.stack_count
	return total

func consume_item(item_id: String, qty: int) -> int:
	var remaining := qty
	for card_node in get_tree().get_nodes_in_group(&"cards"):
		var card := card_node as Card
		if remaining <= 0:
			break
		if card == null or card.is_queued_for_deletion() or card.card_data == null:
			continue
		if card.get_card_id() != item_id:
			continue
		var take: int = mini(remaining, card.stack_count)
		card.set_stack_count(card.stack_count - take)
		remaining -= take
		if card.stack_count <= 0:
			card.queue_free()
	return qty - remaining

func get_units() -> Array[Card]:
	var result: Array[Card] = []
	for card_node in get_tree().get_nodes_in_group(&"cards"):
		var card := card_node as Card
		if card != null and not card.is_queued_for_deletion() and card.is_unit():
			result.append(card)
	return result

func get_built_buildings() -> Array[Card]:
	var result: Array[Card] = []
	for card_node in get_tree().get_nodes_in_group(&"cards"):
		var card := card_node as Card
		if card != null and not card.is_queued_for_deletion() \
				and card.is_building() and card.is_built:
			result.append(card)
	return result

func get_cards_of_id(card_id: String) -> Array[Card]:
	var result: Array[Card] = []
	for card_node in get_tree().get_nodes_in_group(&"cards"):
		var card := card_node as Card
		if card != null and not card.is_queued_for_deletion() \
				and card.card_data != null and card.get_card_id() == card_id:
			result.append(card)
	return result

func find_first(card_id: String) -> Card:
	var cards := get_cards_of_id(card_id)
	return cards[0] if not cards.is_empty() else null

func random_free_spot(zone: Enums.BoardZone) -> Vector2:
	for i in 40:
		var rect := ship_rect if zone == Enums.BoardZone.SHIP_INTERIOR else open_rect
		var pos := Vector2(
			rect.position.x + _rng.randf_range(20.0, rect.size.x - 180.0),
			rect.position.y + _rng.randf_range(40.0, rect.size.y - 240.0))
		if _is_slot_free(pos):
			return pos + Vector2(60.0, 85.0)
	return ship_rect.position + Vector2(200, 400)

func remove_card(card: Card) -> void:
	card.queue_free()

# ---------- Spawn ----------

func spawn_card_at(card_id: String, position: Vector2, count := 1, built := false) -> Card:
	var card := _instantiate_card(card_id, count, built)
	if card == null:
		return null
	add_child(card)
	card.global_position = position - card.size * 0.5
	card.refresh_zone_frame()
	Sfx.play("spawn")
	return card

func _instantiate_card(card_id: String, count := 1, built := false) -> Card:
	var card_data: CardData = CardDB.get_card(card_id)
	if card_data == null:
		push_warning("Board: spawn gagal, id tidak ada di CardDB: " + card_id)
		return null
	var card: Card = CARD_SCENE.instantiate()
	card.setup_card(card_data, count, built)
	card.dropped.connect(_on_card_dropped)
	card.clicked.connect(_on_card_clicked)
	return card

func _spawn_card(card_id: String, position: Vector2, count := 1, built := false) -> Card:
	var card := _instantiate_card(card_id, count, built)
	if card == null:
		return null
	add_child(card)
	card.global_position = position
	card.refresh_zone_frame()
	Sfx.play("spawn")
	return card

func _on_card_clicked(card: Card) -> void:
	Events.on_card_clicked(self, card)
	# Kartu event berpilihan buka popup pilihan — jangan tutupi dengan inspect.
	var ed := card.card_data as EventCardData if card != null else null
	if card != null and card.card_art() != null \
			and (ed == null or ed.choices.is_empty()):
		_show_inspect(card)

# Inspect: art tampil besar hampir selayar + nama. Klik untuk tutup.
func _show_inspect(card: Card) -> void:
	var tex := card.card_art()
	if tex == null or get_node_or_null("InspectOverlay") != null:
		return
	var view := get_viewport_rect().size
	var overlay := ColorRect.new()
	overlay.name = "InspectOverlay"
	overlay.color = Color(0, 0, 0, 0.85)
	overlay.position = Vector2.ZERO
	overlay.size = view
	overlay.z_index = 700
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var art := TextureRect.new()
	art.texture = tex
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.size = Vector2(view.x * 0.6, view.y * 0.72)
	art.position = (view - art.size) * 0.5 + Vector2(0, -30)
	overlay.add_child(art)
	var name_label := Label.new()
	name_label.text = card.card_data.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 28)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.97, 1))
	name_label.position = Vector2(0, art.position.y + art.size.y + 12.0)
	name_label.size = Vector2(view.x, 40)
	overlay.add_child(name_label)
	var hint := Label.new()
	hint.text = "click anywhere to close"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.6, 0.64, 0.72))
	hint.position = Vector2(0, name_label.position.y + 44.0)
	hint.size = Vector2(view.x, 24)
	overlay.add_child(hint)
	overlay.gui_input.connect(_on_inspect_input.bind(overlay))

func _on_inspect_input(event: InputEvent, overlay: ColorRect) -> void:
	if event is InputEventMouseButton and event.pressed:
		overlay.queue_free()

func _spawn_test_cards() -> void:
	_spawn_card("node_asteroid_field", open_rect.position + Vector2(80, 160))
	_spawn_card("node_debris_field", open_rect.position + Vector2(300, 340))
	_spawn_card("node_ice_field", open_rect.position + Vector2(80, 460))
	_spawn_card("node_gas_cloud", open_rect.position + Vector2(300, 120))
	_spawn_card("tool_cutting_laser", open_rect.position + Vector2(520, 160))

	# Kolom 1: unit & building
	_spawn_card("unit_astronaut", Vector2(60, 120))
	_spawn_card("unit_astronaut", Vector2(60, 290))
	_spawn_card("unit_engineer", Vector2(60, 460))
	_spawn_card("building_workshop", Vector2(60, 630), 1, true)
	_spawn_card("building_solar_panel", Vector2(60, 800), 1, true)

	# Kolom 2: material combine
	_spawn_card("item_ice_chunk", Vector2(230, 120))
	_spawn_card("item_scrap_metal", Vector2(230, 460), 3)
	_spawn_card("item_crystal_ore", Vector2(230, 630))
	_spawn_card("item_circuit_board", Vector2(230, 800), 2)

	# Kolom 3: material combine lanjutan
	_spawn_card("item_alien_flora", Vector2(400, 120))
	_spawn_card("item_fuel_cell", Vector2(400, 290), 2)
	_spawn_card("item_scrap_metal", Vector2(400, 460), 2)
	_spawn_card("item_fuel_cell", Vector2(400, 800))

	# Kolom 4: material combine + demo stacking
	_spawn_card("item_scrap_metal", Vector2(570, 120), 3)
	_spawn_card("item_metal_ingot", Vector2(570, 290))
	_spawn_card("item_water", Vector2(570, 460), 2)
	_spawn_card("item_water", Vector2(570, 630))

	# Kolom 5: sistem baru (Phase 5-12)
	_spawn_card("building_hydroponics_bay", Vector2(740, 120), 1, false)
	_spawn_card("pkg_scrap_run", Vector2(940, 800))
	_spawn_card("tool_repair_kit", Vector2(740, 630))
	_spawn_card("item_metal_ingot", Vector2(740, 800), 3)

	# Zona angkasa: pendukung sistem
	_spawn_card("item_oxygen_canister", open_rect.position + Vector2(440, 800), 2)

	# Baris tambahan (di bawah semua kolom lain, biar tidak nabrak node/kartu
	# lain): material mentah sesuai GDD/Combining Recipe Space Salvage, biar
	# semua resep combine baru (Furnace, Green Room, Helper Station, dst) bisa
	# langsung dites di board tanpa mesti buka Card Pack dulu.
	_spawn_card("item_water", Vector2(60, 1150), 4)
	_spawn_card("item_space_rock", Vector2(230, 1150), 5)
	_spawn_card("item_iron", Vector2(400, 1150), 4)
	_spawn_card("item_iron_ore", Vector2(570, 1150), 3)
	_spawn_card("item_energy_cell", Vector2(740, 1150), 2)
	_spawn_card("item_mushroom", Vector2(230, 1320), 2)

# ---------- Game start: node dunia + intro pilih-pack (non-headless) ----------

# true = jalankan intro walau headless (dipakai tests/intro_check).
var force_intro := false

func _spawn_world_nodes() -> void:
	_spawn_card("node_asteroid_field", open_rect.position + Vector2(180, 140))
	_spawn_card("node_debris_field", open_rect.position + Vector2(650, 420))
	_spawn_card("node_ice_field", open_rect.position + Vector2(150, 620))
	_spawn_card("node_gas_cloud", open_rect.position + Vector2(700, 100))

func _run_intro() -> void:
	var intro := IntroOverlay.new()
	intro.name = "IntroOverlay"
	intro.z_index = 600
	add_child(intro)
	intro.setup(self)
	intro.finished.connect(_on_intro_finished)

func _on_intro_finished(kit: Array) -> void:
	var i := 0
	for entry in kit:
		var pos := Vector2(150.0 + (i % 3) * 130.0, 150.0 + (i / 3) * 170.0)
		var card := _spawn_card(String(entry[0]), pos, int(entry[1]))
		if card != null:
			card.pivot_offset = card.size * 0.5
			card.scale = Vector2(0.2, 0.2)
			var pop := create_tween()
			pop.tween_property(card, "scale", Vector2.ONE, 0.3) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.08 * i)
		i += 1

func _show_data_debug() -> void:
	var label := Label.new()
	label.name = "DataDebugLabel"
	label.position = Vector2(8, 1045)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
	label.text = "CardDB: %d cards | %d recipes | %d sectors | %d packs" % [
		CardDB.get_count(),
		RecipeDB.recipe_count(),
		RecipeDB.sector_count(),
		RecipeDB.pack_count(),
	]
	add_child(label)

func _spawn_hud() -> void:
	var hud: HUD = (load("res://scenes/hud.tscn") as PackedScene).instantiate()
	add_child(hud)
	hud.setup(self)
