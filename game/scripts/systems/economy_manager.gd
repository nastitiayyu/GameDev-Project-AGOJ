extends Node

# A10/A12 — Ekonomi. Autoload: Economy

const RARITY_MULTIPLIER: Dictionary = {
	Enums.Rarity.COMMON: 1.0,
	Enums.Rarity.UNCOMMON: 1.5,
	Enums.Rarity.RARE: 2.5,
	Enums.Rarity.EPIC: 4.0,
}

func try_sell(board: Board, card: Card) -> void:
	if card == null or card.card_data == null:
		return
	var value := int(round(float(card.card_data.sell_value) * float(RARITY_MULTIPLIER.get(card.card_data.rarity, 1.0))))
	if value <= 0:
		board._show_toast("Cannot be sold", card.global_position, Color(1, 0.8, 0.5))
		return
	GameState.add_credits(value)
	board._show_toast("Sold +%d cr" % value, card.global_position, Color(0.55, 1, 0.6))
	board.remove_card(card)

# Harga per unit buat Market (jual 1 / jual semua, prorata stack).
func unit_price(card: Card) -> int:
	if card == null or card.card_data == null:
		return 0
	return maxi(0, int(round(float(card.card_data.sell_value) * float(RARITY_MULTIPLIER.get(card.card_data.rarity, 1.0)))))

func sell_units(board: Board, card: Card, qty: int) -> void:
	if card == null or card.is_queued_for_deletion() or card.card_data == null:
		return
	var take: int = mini(qty, card.stack_count)
	if take <= 0:
		return
	var gain: int = unit_price(card) * take
	if gain <= 0:
		board._show_toast("Cannot be sold", card.global_position, Color(1, 0.8, 0.5))
		return
	card.set_stack_count(card.stack_count - take)
	if card.stack_count <= 0:
		card.queue_free()
	GameState.add_credits(gain)
	board._show_toast("Sold +%d cr" % gain, board.ship_rect.position + Vector2(200, 300), Color(0.55, 1, 0.6))

# A12 — harga progresif: base_cost × (1 + 5% × jumlah sudah dibeli)
func pack_cost(pack_id: String) -> int:
	var pack := RecipeDB.get_pack(pack_id)
	if pack == null:
		return 0
	var n: int = int(GameState.pack_purchase_counts.get(pack_id, 0))
	return pack.base_cost + int(round(pack.base_cost * 0.05 * n))

func buy_pack(pack_id: String) -> bool:
	if GameState.is_game_over:
		return false
	var pack := RecipeDB.get_pack(pack_id)
	if pack == null:
		return false
	var board: Board = get_tree().get_first_node_in_group(&"board")
	# Pack hanya bisa dibeli lewat Market (butuh Space Telephone di board).
	if board != null and not board.has_market():
		board._show_toast("Needs Space Telephone (opens Market)",
			board.ship_rect.position + Vector2(200, 300), Color(1, 0.6, 0.55))
		return false
	# 0. Syarat Reputasi (GDD S4.2: pack tier tinggi butuh Rep).
	if GameState.reputation < pack.rep_required:
		if board != null:
			board._show_toast("Needs Rep %d (now %d)" % [pack.rep_required, GameState.reputation],
				board.ship_rect.position + Vector2(200, 300), Color(1, 0.6, 0.55))
		return false
	# 1. Cek basic resource dulu (gated, Stacklands-style). Belum ada board
	# (mis. headless test tanpa scene) → lewati cek resource.
	if board != null:
		var missing: Array[String] = []
		for req in pack.resource_cost:
			var item_id: String = req.get("item_id", "")
			var qty: int = int(req.get("qty", 1))
			var have: int = board.count_item(item_id)
			if have < qty:
				var item: CardData = CardDB.get_card(item_id)
				missing.append("%s x%d" % [item.display_name if item != null else item_id, qty - have])
		if not missing.is_empty():
			board._show_toast("Need: " + ", ".join(missing),
				board.ship_rect.position + Vector2(200, 300), Color(1, 0.6, 0.55))
			return false
	var cost := pack_cost(pack_id)
	if not GameState.spend_credits(cost):
		if board != null:
			board._show_toast("Not enough credits (%d cr)" % cost,
				board.ship_rect.position + Vector2(200, 300), Color(1, 0.6, 0.55))
		return false
	# 2. Konsumsi resource, baru random spawn lewat open_pack.
	if board != null:
		for req in pack.resource_cost:
			board.consume_item(req.get("item_id", ""), int(req.get("qty", 1)))
	GameState.pack_purchase_counts[pack_id] = int(GameState.pack_purchase_counts.get(pack_id, 0)) + 1
	open_pack(pack_id)
	return true

# Label tombol beli: "Nama (10 cr)" atau "Nama (10 cr + 2x Scrap)".
func pack_label(pack_id: String) -> String:
	var pack := RecipeDB.get_pack(pack_id)
	if pack == null:
		return pack_id
	var parts: Array[String] = ["%d cr" % pack_cost(pack_id)]
	for req in pack.resource_cost:
		var item: CardData = CardDB.get_card(req.get("item_id", ""))
		var item_name: String = item.display_name if item != null else String(req.get("item_id", "?"))
		parts.append("%dx %s" % [int(req.get("qty", 1)), item_name])
	if pack.rep_required > 0:
		parts.append("Rep %d" % pack.rep_required)
	return "%s (%s)" % [pack.display_name, " + ".join(parts)]

func open_pack(pack_id: String) -> void:
	var board: Board = get_tree().get_first_node_in_group(&"board")
	if board == null:
		return
	var pack := RecipeDB.get_pack(pack_id)
	if pack == null:
		push_warning("Economy: pack tidak ada: " + pack_id)
		return
	var total_weight := 0
	for entry in pack.drop_table:
		total_weight += int(entry.get("weight", 0))
	for i in pack.card_count:
		if total_weight <= 0:
			break
		var roll := randf() * total_weight
		var acc := 0
		var picked := ""
		for entry in pack.drop_table:
			acc += int(entry.get("weight", 0))
			if roll < acc:
				picked = entry.get("card_id", "")
				break
		if picked == "":
			continue
		var card_data: CardData = CardDB.get_card(picked)
		var zone: Enums.BoardZone = Enums.BoardZone.OPEN_SPACE
		if card_data != null and card_data.category != Enums.CardCategory.NODE:
			zone = Enums.BoardZone.SHIP_INTERIOR
		board.spawn_card_at(picked, board.random_free_spot(zone))
	board._show_toast("Pack opened: " + pack.display_name,
		board.ship_rect.position + Vector2(240, 320), Color(0.7, 0.95, 1))

# A6 — efek tool consumable
# Nilai efek dibaca dari data (ToolCardData.effect_value) supaya bisa di-tune
# lewat .tres tanpa ubah kode.
func apply_tool_effect(tool_id: String, board: Board) -> void:
	match tool_id:
		"tool_repair_kit":
			GameState.hull = clampf(GameState.hull + 20.0, 0.0, GameState.HULL_MAX)
			board._show_toast("Hull +20", board.ship_rect.position + Vector2(240, 320), Color(0.55, 1, 0.6))
			GameState.stats_changed.emit()
		"item_oxygen_tank":
			var data := CardDB.get_card(tool_id) as ToolCardData
			var restore: float = data.effect_value if data != null else 25.0
			GameState.oxygen = clampf(GameState.oxygen + restore, 0.0, GameState.O2_MAX)
			board._show_toast("O2 +%d" % int(restore),
				board.ship_rect.position + Vector2(240, 320), Color(0.6, 0.9, 1))
			GameState.stats_changed.emit()
		_:
			pass
