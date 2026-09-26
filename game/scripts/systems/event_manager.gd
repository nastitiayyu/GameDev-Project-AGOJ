extends Node

# A9 — Event System. Autoload: Events

const LOOT_ITEM_ID := "item_meteorite_fragment"

var enabled := true  # false = matikan roll acak (untuk test deterministik)

# A9: P = clamp(0.15 + 0.01×day, 0.15, 0.6), pick berbobot spawn_weight.
# day_frac = fraksi hari yang lewat (1.0 = sehari penuh, legacy end_day).
func maybe_spawn_event(day_frac: float = 1.0) -> void:
	if not enabled or GameState.is_game_over:
		return
	var day := GameState.day
	var chance := clampf(0.15 + 0.01 * day, 0.15, 0.6)
	var roll_p: float = 1.0 - pow(1.0 - chance, day_frac)
	if randf() > roll_p:
		return
	var events := CardDB.get_events()
	if events.is_empty():
		return
	var total_weight := 0
	for event: CardData in events:
		var ed := event as EventCardData
		total_weight += ed.spawn_weight if ed != null else 100
	if total_weight <= 0:
		return
	var roll := randf() * total_weight
	var acc := 0
	var picked: CardData = events[0]
	for event: CardData in events:
		var ed := event as EventCardData
		acc += ed.spawn_weight if ed != null else 100
		if roll < acc:
			picked = event
			break
	var board: Board = get_tree().get_first_node_in_group(&"board")
	if board == null:
		return
	spawn_event(board, picked.id)

func spawn_event(board: Board, event_id: String) -> void:
	var event_data := CardDB.get_card(event_id) as EventCardData
	if event_data == null:
		return
	if event_data.effect_type == Enums.EventEffect.PLAYER_CHOICE:
		# Popup langsung berisi tombol pilihan (tidak jadi kartu dulu).
		var hud2: HUD = board.get_node_or_null("HUD")
		if hud2 != null:
			hud2.show_event_popup(event_id)
			board._show_toast("EVENT: " + event_data.display_name,
				board.open_rect.position + Vector2(100, 60), Color(1, 0.85, 0.5))
		else:
			board.spawn_card_at(event_id, board.random_free_spot(Enums.BoardZone.OPEN_SPACE))
	else:
		# Popup info + tombol OK; efek diterapkan saat OK ditekan.
		var hud: HUD = board.get_node_or_null("HUD")
		if hud != null:
			hud.show_event_popup(event_id)
		else:
			apply_event(board, event_id)

# Ringkasan efek untuk popup (dihrtung dengan severity saat ini).
func event_summary(event_id: String) -> String:
	var event_data := CardDB.get_card(event_id) as EventCardData
	if event_data == null:
		return ""
	var severity: float = 1.0 + 0.015 * GameState.day
	match event_data.effect_type:
		Enums.EventEffect.DAMAGE_HULL:
			return "Hull -%d" % int(event_data.effect_value * severity)
		Enums.EventEffect.DAMAGE_O2:
			return "O2 -%d" % int(event_data.effect_value * severity)
		Enums.EventEffect.STEAL_RESOURCE:
			return "Some resources stolen!"
		Enums.EventEffect.POWER_DEBUFF:
			return "Power -50% for %d days" % event_data.duration_days
		Enums.EventEffect.BUFF_LOOT:
			return "Meteorite x%d!" % int(event_data.effect_value)
	return ""

func apply_event(board: Board, event_id: String, choice_index := -1) -> void:
	var event_data := CardDB.get_card(event_id) as EventCardData
	if event_data == null:
		return
	# A16: severity multiplier
	var severity: float = 1.0 + 0.015 * GameState.day
	if choice_index >= 0:
		var choices: Array = event_data.choices
		if choice_index >= choices.size():
			return
		var choice: Dictionary = choices[choice_index]
		_apply_choice(board, choice)
		return
	match event_data.effect_type:
		Enums.EventEffect.DAMAGE_HULL:
			var dmg: float = event_data.effect_value * severity
			GameState.hull = maxf(GameState.hull - dmg, 0.0)
			board._show_toast("EVENT: %s — Hull -%d" % [event_data.display_name, int(dmg)],
				board.ship_rect.position + Vector2(200, 300), Color(1, 0.5, 0.5))
		Enums.EventEffect.DAMAGE_O2:
			var dmg2: float = event_data.effect_value * severity
			GameState.oxygen = maxf(GameState.oxygen - dmg2, 0.0)
			board._show_toast("EVENT: %s — O2 -%d" % [event_data.display_name, int(dmg2)],
				board.ship_rect.position + Vector2(200, 300), Color(0.6, 0.8, 1))
		Enums.EventEffect.STEAL_RESOURCE:
			_steal_resource(board)
		Enums.EventEffect.POWER_DEBUFF:
			GameState.active_effects["power_debuff"] = event_data.duration_days
			board._show_toast("EVENT: %s — Power debuff %d days" % [event_data.display_name, event_data.duration_days],
				board.ship_rect.position + Vector2(200, 300), Color(1, 0.8, 0.5))
		Enums.EventEffect.BUFF_LOOT:
			for i in int(event_data.effect_value):
				board.spawn_card_at(LOOT_ITEM_ID, board.random_free_spot(Enums.BoardZone.OPEN_SPACE))
			board._show_toast("EVENT: %s — Meteorite x%d!" % [event_data.display_name, int(event_data.effect_value)],
				board.open_rect.position + Vector2(100, 60), Color(0.7, 0.95, 1))
		_:
			pass
	GameState.stats_changed.emit()

func _steal_resource(board: Board) -> void:
	var stacks: Array[Card] = []
	for card_node in get_tree().get_nodes_in_group(&"cards"):
		var card := card_node as Card
		if card == null or card.is_queued_for_deletion() or card.card_data == null:
			continue
		if card.card_data.category == Enums.CardCategory.ITEM_RAW \
				or card.card_data.category == Enums.CardCategory.ITEM_PROCESSED \
				or card.card_data.category == Enums.CardCategory.ITEM_FOOD:
			stacks.append(card)
	if stacks.is_empty():
		return
	var victim: Card = stacks[randi() % stacks.size()]
	var stolen: int = maxi(1, int(round(victim.stack_count * 0.2)))
	board._show_toast("EVENT: Pirates! -%d %s" % [stolen, victim.card_data.display_name],
		victim.global_position, Color(1, 0.5, 0.5))
	victim.set_stack_count(victim.stack_count - stolen)
	if victim.stack_count <= 0:
		victim.queue_free()

func _apply_choice(board: Board, choice: Dictionary) -> void:
	match choice.get("effect_code", ""):
		"grant_pack":
			Economy.open_pack(choice.get("effect_value", ""))
		_:
			pass

func on_card_clicked(board: Board, card: Card) -> void:
	if card == null or card.card_data == null:
		return
	if card.card_data.category != Enums.CardCategory.EVENT:
		return
	var event_data := card.card_data as EventCardData
	if event_data == null or event_data.choices.is_empty():
		return
	var hud: HUD = board.get_node_or_null("HUD")
	if hud != null:
		hud.show_event_choices(card, event_data)
