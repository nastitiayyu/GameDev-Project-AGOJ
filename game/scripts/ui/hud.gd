class_name HUD
extends Control

# Warna sorotan baris resep: ON = bisa dibuat sekarang, OFF = belum bisa.
const RECIPE_BG_ON := Color(0.11, 0.26, 0.16)
const RECIPE_BORDER_ON := Color(0.4, 0.92, 0.53)
const RECIPE_FG_ON := Color(0.8, 1, 0.85)
const RECIPE_BG_OFF := Color(0.12, 0.13, 0.18)
const RECIPE_BORDER_OFF := Color(0.26, 0.29, 0.36)
const RECIPE_FG_OFF := Color(0.6, 0.64, 0.72)
const RECIPE_STATUS_BAD := Color(1, 0.62, 0.55)

var _board: Board
var _event_card_ref: Card
var _choice_buttons: Array[Button] = []
var _recipe_panel: Panel
var _recipe_list: VBoxContainer
var _recipe_order_sig := ""
var _recipe_search := ""
var _recipe_sort := 0
var _recipe_search_box: LineEdit
var _recipe_sort_box: OptionButton

const RECIPE_SORT_CRAFTABLE := 0
const RECIPE_SORT_AZ := 1
const RECIPE_SORT_TYPE := 2
var _recipe_rows: Array[Dictionary] = []
var _recipe_summary: Label
var _recipe_refresh_timer := 0.0
const HULL_BAR_WIDTH := 220.0

@onready var _stats_label: Label = %StatsLabel
@onready var _day_track: ColorRect = %DayTrack
@onready var _day_fill: ColorRect = %DayFill
@onready var _day_label: Label = %DayLabel
@onready var _pause_button: Button = %PauseButton
@onready var _recipe_button: Button = %RecipeButton
@onready var _event_popup: Panel = %EventPopup
@onready var _hull_track: ColorRect = %HullTrack
@onready var _hull_fill: ColorRect = %HullFill
@onready var _hull_label: Label = %HullLabel


func setup(board: Board) -> void:
	_board = board
	name = "HUD"
	z_index = 500
	process_mode = Node.PROCESS_MODE_ALWAYS  # tombol tetap hidup saat pause
	_wire_buttons()
	_build_recipe_book()
	_refresh_stats()
	GameState.stats_changed.connect(_refresh_stats)
	GameState.credits_changed.connect(func(_c: int) -> void: _refresh_stats())
	GameState.reputation_changed.connect(func(_r: int) -> void: _refresh_stats())
	GameState.day_changed.connect(func(_d: int) -> void: _refresh_stats())
	GameState.game_over.connect(_on_game_over)
	GameState.victory.connect(_on_victory)

func _process(_delta: float) -> void:
	if _day_fill != null and _day_track != null:
		_day_fill.size.x = _day_track.size.x * DayCycle.day_progress()
	_refresh_recipe_timer(_delta)
	_refresh_market_timer(_delta)

var _recipe_sort_btn: Button
var _summary_as_row := false

var _market_visible_timer := 0.0

# Tombol Market muncul/hilang mengikuti ada tidaknya Space Telephone.
func _refresh_market_timer(delta: float) -> void:
	_market_visible_timer -= delta
	if _market_visible_timer > 0.0:
		return
	_market_visible_timer = 0.5
	if _market_button == null or _board == null:
		return
	var unlocked: bool = _board.has_market()
	_market_button.visible = unlocked
	if not unlocked and _market_panel != null:
		_market_panel.visible = false
	elif unlocked and _market_panel != null and _market_panel.visible:
		_refresh_market()

# Stat bar art (5 segmen: O2|Food|Hull|Cr|Power). Nilai saja yang
# ditulis (label sudah baked di gambar); Rep/Skor/Sektor jadi teks kecil
# di bawahnya. Tanpa file → label teks lama.
func _build_stat_bar() -> void:
	var bg := _art(STAT_BG_PATH)
	if bg == null or _stats_label == null:
		return
	_stat_art_mode = true
	_stats_label.visible = false
	var h := 48.0
	var w: float = h * float(bg.get_width()) / float(maxi(1, bg.get_height()))
	var bar_x := 16.0
	var bar := TextureRect.new()
	bar.texture = bg
	bar.position = Vector2(bar_x, 8)
	bar.size = Vector2(w, h)
	bar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bar.stretch_mode = TextureRect.STRETCH_SCALE
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	var segw := w / 5.0
	# Posisi divider diukur dari file bar_stats.png (940px):
	# 6, 159, 344, 533, 701, 932. Nilai rata kanan sebelum divider.
	var divs := [50.0, 200.0, 500.0, 750.0, 1000.0, 1350.0]
	for i in 5:
		var lab := Label.new()
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lab.add_theme_font_size_override("font_size", 20)
		lab.add_theme_color_override("font_color", Color(0.95, 0.97, 1))
		lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		lab.add_theme_constant_override("outline_size", 6)
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lab.position = Vector2(bar_x + divs[i] / 940.0 * w + 4.0, 13)
		lab.size = Vector2((divs[i + 1] - divs[i]) / 940.0 * w - 14.0, h)
		add_child(lab)
		_stat_seg_labels.append(lab)
	# Rep/Skor/Quest di kanan bawah (rata kanan, font 20 sama kayak segmen bar).
	_stat_meta_label = Label.new()
	_stat_meta_label.anchor_left = 1.0
	_stat_meta_label.anchor_top = 1.0
	_stat_meta_label.anchor_right = 1.0
	_stat_meta_label.anchor_bottom = 1.0
	_stat_meta_label.offset_left = -616.0
	_stat_meta_label.offset_top = -44.0
	_stat_meta_label.offset_right = -16.0
	_stat_meta_label.offset_bottom = -12.0
	_stat_meta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stat_meta_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stat_meta_label.add_theme_font_size_override("font_size", 20)
	_stat_meta_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1))
	_stat_meta_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_stat_meta_label.add_theme_constant_override("outline_size", 6)
	_stat_meta_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stat_meta_label)

func _refresh_stats() -> void:
	if _stat_art_mode and _stat_seg_labels.size() == 5:
		var vals: Array[String] = ["%.0f" % GameState.oxygen, "%.0f" % GameState.food,
			"%.0f" % GameState.hull, "%d" % GameState.credits,
			"%.0f/%d" % [GameState.power, int(GameState.power_cap)]]
		for i in 5:
			_stat_seg_labels[i].text = vals[i]
		_update_stat_seg_color(0, GameState.oxygen, GameState.O2_MAX)
		_update_stat_seg_color(1, GameState.food, GameState.FOOD_MAX)
		_stat_meta_label.text = "Rep %d   Score %d   Quest %d/%d" % [GameState.reputation,
			GameState.score, GameState.quest_done.size(), Packages.QUEST_ORDER.size()]
		if _day_label != null:
			_day_label.text = "Day %d" % GameState.day
		_update_hull_bar()
		return
	_stats_label.text = "O2 %.0f   Food %.0f   Hull %.0f   Power %.0f/%d   Cr %d   Rep %d   Score %d   Quest %d/%d" % [
		GameState.oxygen, GameState.food, GameState.hull,
		GameState.power, int(GameState.power_cap), GameState.credits,
		GameState.reputation, GameState.score,
		GameState.quest_done.size(), Packages.QUEST_ORDER.size()]
	if _day_label != null:
		_day_label.text = "Day %d" % GameState.day
	_update_hull_bar()

# Defense bar kapal: muncul saat monster menyerang (board memanggil).
func show_defense_bar(visible_now: bool) -> void:
	for node in [_hull_track, _hull_fill, _hull_label]:
		if node != null:
			node.visible = visible_now
	_update_hull_bar()

# Warna peringatan segmen O2/Food (threshold sama kayak Hull bar).
# Kritis (<25%) ikut berkedip pelan biar tidak baru sadar pas game over.
func _update_stat_seg_color(i: int, val: float, maxv: float) -> void:
	if i < 0 or i >= _stat_seg_labels.size():
		return
	var frac := clampf(val / maxf(1.0, maxv), 0.0, 1.0)
	var lab := _stat_seg_labels[i]
	if frac > 0.5:
		lab.add_theme_color_override("font_color", Color(0.95, 0.97, 1))
	elif frac > 0.25:
		lab.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	elif int(Time.get_ticks_msec() / 600) % 2 == 0:
		lab.add_theme_color_override("font_color", Color(1, 0.35, 0.35))
	else:
		lab.add_theme_color_override("font_color", Color(0.95, 0.97, 1))

func _update_hull_bar() -> void:
	if _hull_fill == null:
		return
	var frac := clampf(GameState.hull / GameState.HULL_MAX, 0.0, 1.0)
	_hull_fill.size.x = HULL_BAR_WIDTH * frac
	if frac > 0.5:
		_hull_fill.color = Color(0.4, 0.9, 0.4)
	elif frac > 0.25:
		_hull_fill.color = Color(0.95, 0.8, 0.3)
	else:
		_hull_fill.color = Color(1.0, 0.35, 0.35)
	if _hull_label != null:
		_hull_label.text = "HULL %d" % int(GameState.hull)

func _shop_pack_ids() -> Array[String]:
	var pack_ids: Array[String] = []
	for pack in RecipeDB.all_packs():
		if pack.shop_visible:
			pack_ids.append(pack.id)
	pack_ids.sort()
	return pack_ids

func _wire_buttons() -> void:
	_pause_button.pressed.connect(_toggle_pause.bind(_pause_button))
	_build_settings()
	_build_log()

	_recipe_button.pressed.connect(_toggle_recipe_book)
	_build_market()
	_apply_button_art()
	_juice_button(_pause_button)
	_juice_button(_recipe_button)
	_juice_button(_settings_button)

# ---------- Log kejadian (kanan bawah, 6 baris terakhir) ----------

const LOG_MAX_ROWS := 6

var _log_list: VBoxContainer

func _build_log() -> void:
	_log_list = VBoxContainer.new()
	_log_list.name = "EventLog"
	_log_list.anchor_left = 1.0
	_log_list.anchor_top = 1.0
	_log_list.anchor_right = 1.0
	_log_list.anchor_bottom = 1.0
	_log_list.offset_left = -376.0
	_log_list.offset_top = -196.0
	_log_list.offset_right = -16.0
	_log_list.offset_bottom = -52.0
	_log_list.alignment = BoxContainer.ALIGNMENT_END
	_log_list.add_theme_constant_override("separation", 2)
	_log_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_log_list)

func add_log(text: String, color: Color = Color(0.9, 0.95, 1)) -> void:
	if _log_list == null:
		return
	var row := Label.new()
	row.text = text
	row.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_theme_font_size_override("font_size", 13)
	row.add_theme_color_override("font_color", color)
	row.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	row.add_theme_constant_override("outline_size", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_list.add_child(row)
	while _log_list.get_child_count() > LOG_MAX_ROWS:
		var oldest := _log_list.get_child(0)
		_log_list.remove_child(oldest)
		oldest.queue_free()

# Animasi pencet: tombol mengecil 0.06 dtk lalu memantul kembali.
func _juice_button(b: Button) -> void:
	if b == null:
		return
	b.pressed.connect(_on_button_juice.bind(b))

func _on_button_juice(b: Button) -> void:
	if not is_instance_valid(b):
		return
	b.pivot_offset = b.size * 0.5
	var tw := create_tween()
	tw.tween_property(b, "scale", Vector2(0.88, 0.88), 0.06)
	tw.tween_property(b, "scale", Vector2.ONE, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# Art tombol (opsional, fallback tombol teks):
#   assets/ui/btn_pause.png, btn_play.png, btn_recipe.png,
#   btn_setting.png, bar_day.png
const BTN_PAUSE_PATH := "res://assets/ui/btn_pause.png"
const BTN_PLAY_PATH := "res://assets/ui/btn_play.png"
const BTN_RECIPE_PATH := "res://assets/ui/btn_recipe.png"
const BTN_SETTING_PATH := "res://assets/ui/btn_setting.png"
const DAY_BG_PATH := "res://assets/ui/bar_day.png"
const STAT_BG_PATH := "res://assets/ui/bar_stats.png"

var _stat_seg_labels: Array[Label] = []
var _stat_meta_label: Label = null
var _stat_art_mode := false

static var _btn_art: Dictionary = {}

static func _art(path: String) -> Texture2D:
	if not _btn_art.has(path):
		_btn_art[path] = load(path) if ResourceLoader.exists(path) else null
	return _btn_art[path]

func _skin_button(b: Button, tex: Texture2D) -> void:
	if b == null or tex == null:
		return
	b.text = ""
	b.flat = true
	b.expand_icon = true
	b.icon = tex
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _apply_button_art() -> void:
	_skin_button(_pause_button, _art(BTN_PAUSE_PATH))
	_refresh_pause_button()
	_skin_button(_recipe_button, _art(BTN_RECIPE_PATH))
	_skin_button(_settings_button, _art(BTN_SETTING_PATH))
	var day_bg := _art(DAY_BG_PATH)
	if day_bg != null and _day_track != null:
		var bg := TextureRect.new()
		bg.texture = day_bg
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_SCALE
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_day_track.add_child(bg)
		_day_track.color = Color(0, 0, 0, 0)
	_build_stat_bar()

# ---------- Market (unlock: Space Telephone di board) ----------

var _market_button: Button
var _market_panel: Panel
var _market_list: VBoxContainer

func _build_market() -> void:
	_market_button = Button.new()
	_market_button.name = "MarketButton"
	_market_button.text = "Market"
	_market_button.anchor_left = 0.0
	_market_button.anchor_top = 1.0
	_market_button.anchor_right = 0.0
	_market_button.anchor_bottom = 1.0
	_market_button.offset_left = 80.0
	_market_button.offset_top = -60.0
	_market_button.offset_right = 220.0
	_market_button.offset_bottom = -12.0
	_market_button.visible = false
	_market_button.pressed.connect(_toggle_market)
	add_child(_market_button)

	_market_panel = UIFactory.panel(Vector2(minf(480.0, _board.get_viewport_rect().size.x * 0.4), 420.0),
		Color(0.09, 0.1, 0.15))
	_market_panel.name = "MarketPanel"
	_market_panel.position = Vector2(8, 90)
	_market_panel.visible = false
	add_child(_market_panel)

	var title := UIFactory.label("MARKET", 20, Color(0.9, 0.95, 1), HORIZONTAL_ALIGNMENT_LEFT)
	title.position = Vector2(16, 10)
	title.size = Vector2(300, 30)
	_market_panel.add_child(title)

	var close_button := UIFactory.button("Close", Vector2(100, 34))
	close_button.position = Vector2(_market_panel.size.x - 116.0, 8)
	close_button.pressed.connect(_toggle_market)
	_market_panel.add_child(close_button)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(8, 52)
	scroll.size = Vector2(_market_panel.size.x - 16.0, _market_panel.size.y - 60.0)
	_market_panel.add_child(scroll)

	_market_list = VBoxContainer.new()
	_market_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_market_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_market_list)

func _toggle_market() -> void:
	if _market_panel == null:
		return
	_market_panel.visible = not _market_panel.visible
	if _market_panel.visible:
		_refresh_market()

func _market_header(text: String) -> void:
	var h := UIFactory.label(text, 16, Color(0.7, 0.95, 1), HORIZONTAL_ALIGNMENT_LEFT)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_market_list.add_child(h)

func _refresh_market() -> void:
	if _market_list == null or _board == null:
		return
	for child in _market_list.get_children():
		child.queue_free()
	_market_header("BUY PACKS")
	for pack_id in _shop_pack_ids():
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)
		_market_list.add_child(row)
		var pack_name := UIFactory.label(Economy.pack_label(pack_id),
			15, Color(0.9, 0.95, 1), HORIZONTAL_ALIGNMENT_LEFT)
		pack_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pack_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(pack_name)
		var buy := UIFactory.button("Buy", Vector2(110, 34))
		buy.pressed.connect(_buy_pack.bind(pack_id))
		row.add_child(buy)
	_market_header("Cr %d: SELL RESOURCES" % GameState.credits)
	var any_sell := false
	for card_node in get_tree().get_nodes_in_group(&"cards"):
		var card := card_node as Card
		if card == null or card.is_queued_for_deletion() or card.card_data == null:
			continue
		if not (card.card_data.category == Enums.CardCategory.ITEM_RAW \
				or card.card_data.category == Enums.CardCategory.ITEM_PROCESSED \
				or card.card_data.category == Enums.CardCategory.ITEM_FOOD):
			continue
		var price := Economy.unit_price(card)
		if price <= 0:
			continue
		any_sell = true
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)
		_market_list.add_child(row)
		var item_name := UIFactory.label("%s x%d" % [card.card_data.display_name, card.stack_count],
			15, Color(0.9, 0.95, 1), HORIZONTAL_ALIGNMENT_LEFT)
		item_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(item_name)
		var b1 := UIFactory.button("Sell 1 (+%d)" % price, Vector2(130, 34))
		b1.pressed.connect(_on_market_sell.bind(card, 1))
		row.add_child(b1)
		var ball := UIFactory.button("All (+%d)" % (price * card.stack_count), Vector2(150, 34))
		ball.pressed.connect(_on_market_sell.bind(card, card.stack_count))
		row.add_child(ball)
	if not any_sell:
		var empty := UIFactory.label("No resources yet.", 14, Color(0.6, 0.64, 0.72), HORIZONTAL_ALIGNMENT_LEFT)
		_market_list.add_child(empty)
	_market_header("SEND PACKAGES")
	var any_pkg := false
	for card_node in get_tree().get_nodes_in_group(&"cards"):
		var card := card_node as Card
		if card == null or card.is_queued_for_deletion() or not card.is_package():
			continue
		if card.has_meta("emergency"):
			continue
		any_pkg = true
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)
		_market_list.add_child(row)
		var prog := "READY" if card.is_package_complete() else card._package_progress_text()
		var pkg_name := UIFactory.label("%s (%s)" % [card.card_data.display_name, prog],
			15, Color(0.9, 0.95, 1), HORIZONTAL_ALIGNMENT_LEFT)
		pkg_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(pkg_name)
		var go := UIFactory.button("Depart", Vector2(130, 34))
		go.pressed.connect(_on_market_depart.bind(card))
		row.add_child(go)
	if not any_pkg:
		var empty2 := UIFactory.label("No packages yet.", 14, Color(0.6, 0.64, 0.72), HORIZONTAL_ALIGNMENT_LEFT)
		_market_list.add_child(empty2)

func _on_market_sell(card: Card, qty: int) -> void:
	Economy.sell_units(_board, card, qty)
	_refresh_market()

func _on_market_depart(package_card: Card) -> void:
	if not is_instance_valid(package_card) or package_card.is_queued_for_deletion():
		return
	if not package_card.is_package_complete():
		_board._show_toast("Package incomplete", package_card.global_position, Color(1, 0.8, 0.5))
		return
	var pilot: Card = null
	for unit in _board.get_units():
		if unit.unit_state == Enums.UnitState.IDLE \
				and unit.assigned_node == null and unit.assigned_building == null:
			pilot = unit
			break
	if pilot == null:
		_board._show_toast("No free units", package_card.global_position, Color(1, 0.6, 0.55))
		return
	Packages.try_depart(_board, pilot, package_card)
	_refresh_market()

func _buy_pack(pack_id: String) -> void:
	if Economy.buy_pack(pack_id):
		_refresh_market()

func _toggle_pause(button: Button) -> void:
	if GameState.is_game_over:
		return
	get_tree().paused = not get_tree().paused
	_refresh_pause_button()

func _refresh_pause_button() -> void:
	if _pause_button == null:
		return
	var paused := get_tree().paused
	var art_pause := _art(BTN_PAUSE_PATH)
	if art_pause != null:
		_pause_button.icon = _art(BTN_PLAY_PATH) if paused else art_pause
	else:
		_pause_button.text = "Resume" if paused else "Pause"

# ---------- Setting: suara, main menu, exit, save & load ----------

var _settings_button: Button
var _settings_panel: Panel
var _volume_slider: HSlider
var _volume_label: Label
var _settings_status: Label

func _build_settings() -> void:
	_settings_button = Button.new()
	_settings_button.name = "SettingsButton"
	_settings_button.text = "Settings"
	_settings_button.anchor_left = 0.0
	_settings_button.anchor_top = 1.0
	_settings_button.anchor_right = 0.0
	_settings_button.anchor_bottom = 1.0
	_settings_button.offset_left = 8.0
	_settings_button.offset_top = -76.0
	_settings_button.offset_right = 72.0
	_settings_button.offset_bottom = -12.0
	_settings_button.pressed.connect(_toggle_settings)
	add_child(_settings_button)

	_settings_panel = UIFactory.panel(Vector2(440, 286), Color(0.09, 0.1, 0.15))
	_settings_panel.name = "SettingsPanel"
	_settings_panel.anchor_left = 0.5
	_settings_panel.anchor_top = 0.5
	_settings_panel.anchor_right = 0.5
	_settings_panel.anchor_bottom = 0.5
	_settings_panel.offset_left = -220.0
	_settings_panel.offset_top = -143.0
	_settings_panel.offset_right = 220.0
	_settings_panel.offset_bottom = 143.0
	_settings_panel.visible = false
	add_child(_settings_panel)
	if _skin_panel(_settings_panel, "res://assets/ui/panel_settings.png"):
		_build_settings_art()
	else:
		_build_settings_classic()

func _build_settings_art() -> void:
	_ghost_button(_settings_panel, Vector2(380, 15), Vector2(40, 40), _toggle_settings)
	_volume_slider = HSlider.new()
	_volume_slider.min_value = 0.0
	_volume_slider.max_value = 100.0
	_volume_slider.step = 1.0
	_volume_slider.position = Vector2(65, 118)
	_volume_slider.size = Vector2(235, 24)
	_volume_slider.value_changed.connect(_on_volume_changed)
	_settings_panel.add_child(_volume_slider)
	_volume_label = null
	# Slot baked Save/Load dibiarkan kosong (fitur dihapus).
	_ghost_button(_settings_panel, Vector2(65, 143), Vector2(309, 42), _on_settings_menu)
	_ghost_button(_settings_panel, Vector2(65, 211), Vector2(309, 42), _on_settings_exit)
	_settings_status = UIFactory.label("", 13, Color(0.6, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER)
	_settings_status.position = Vector2(0, 261)
	_settings_status.size = Vector2(440, 24)
	_settings_panel.add_child(_settings_status)

func _build_settings_classic() -> void:
	_skin_panel(_settings_panel, "res://assets/ui/panel_settings.png")

	var title := UIFactory.label("Settings", 28, Color(0.9, 0.95, 1), HORIZONTAL_ALIGNMENT_CENTER)
	title.position = Vector2(0, 20)
	title.size = Vector2(440, 40)
	_settings_panel.add_child(title)

	var close_button := Button.new()
	close_button.text = "X"
	close_button.flat = true
	close_button.add_theme_font_size_override("font_size", 26)
	close_button.position = Vector2(440.0 - 60.0, 12)
	close_button.size = Vector2(48, 48)
	close_button.pressed.connect(_toggle_settings)
	_settings_panel.add_child(close_button)

	var vol_title := UIFactory.label("Sound", 16, Color(0.7, 0.95, 1), HORIZONTAL_ALIGNMENT_LEFT)
	vol_title.position = Vector2(55, 78)
	vol_title.size = Vector2(200, 24)
	_settings_panel.add_child(vol_title)

	_volume_slider = HSlider.new()
	_volume_slider.min_value = 0.0
	_volume_slider.max_value = 100.0
	_volume_slider.step = 1.0
	_volume_slider.position = Vector2(55, 104)
	_volume_slider.size = Vector2(240, 24)
	_volume_slider.value_changed.connect(_on_volume_changed)
	_settings_panel.add_child(_volume_slider)

	_volume_label = UIFactory.label("100%", 16, Color(0.9, 0.95, 1), HORIZONTAL_ALIGNMENT_LEFT)
	_volume_label.position = Vector2(303, 104)
	_volume_label.size = Vector2(100, 24)
	_settings_panel.add_child(_volume_label)

	var y := 150.0
	for entry in [["Main Menu", "_on_settings_menu"], ["Exit", "_on_settings_exit"]]:
		var b := UIFactory.button(String(entry[0]), Vector2(330, 44))
		b.position = Vector2(55, y)
		b.pressed.connect(Callable(self, String(entry[1])))
		_settings_panel.add_child(b)
		y += 56.0

	_settings_status = UIFactory.label("", 14, Color(0.6, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER)
	_settings_status.position = Vector2(0, y)
	_settings_status.size = Vector2(440, 24)
	_settings_panel.add_child(_settings_status)

# Background art panel: TextureRect full-rect + stylebox transparan.
# Art berisi UI baked-in → tombol asli dibuat transparan tanpa teks,
# tepat di atas slot baked di gambar. Mengembalikan true bila art dipakai.
const PANEL_ART_ENABLED := true

func _skin_panel(panel: Panel, art_path: String) -> bool:
	if panel == null or not PANEL_ART_ENABLED or not ResourceLoader.exists(art_path):
		return false
	var bg := TextureRect.new()
	bg.texture = load(art_path)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(bg)
	panel.move_child(bg, 0)
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	return true

func _toggle_settings() -> void:
	if _settings_panel == null:
		return
	_settings_panel.visible = not _settings_panel.visible
	if _settings_panel.visible and _volume_slider != null:
		var v := int(round(GameState.get_volume() * 100.0))
		_volume_slider.set_value_no_signal(v)
		if _volume_label != null:
			_volume_label.text = "%d%%" % v
		_settings_status.text = ""

func _on_volume_changed(v: float) -> void:
	GameState.set_volume(v / 100.0)
	if _volume_label != null:
		_volume_label.text = "%d%%" % int(round(v))

func _on_settings_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/menu.tscn")

func _on_settings_exit() -> void:
	get_tree().quit()

# ---------- Buku resep combo (tombol "Resep" kiri-bawah) ----------
# Tiap resep tampil sebagai satu baris yang di-highlight hijau kalau bisa
# langsung dibuat dari kartu yang ada di board sekarang (lihat
# _refresh_recipe_highlights). Baris yang belum bisa diberi alasannya.

func _refresh_recipe_timer(delta: float) -> void:
	# Refresh sorotan berkala selagi buku resep terbuka, biar langsung ikut
	# berubah saat kartu di board bertambah/berkurang/habis.
	if _recipe_panel == null or not _recipe_panel.visible:
		return
	_recipe_refresh_timer -= delta
	if _recipe_refresh_timer <= 0.0:
		_recipe_refresh_timer = 0.25
		_refresh_recipe_highlights()

func _toggle_recipe_book() -> void:
	if _recipe_panel == null:
		return
	_recipe_panel.visible = not _recipe_panel.visible
	if _recipe_panel.visible:
		_refresh_recipe_highlights()

func _build_recipe_book() -> void:
	var view := _board.get_viewport_rect().size
	_recipe_panel = UIFactory.panel(Vector2(minf(480.0, view.x * 0.4), minf(754.0, view.y - 90.0)),
		Color(0.09, 0.1, 0.15))
	_recipe_panel.name = "RecipeBook"
	_recipe_panel.position = Vector2(8, 90)
	_recipe_panel.visible = false
	add_child(_recipe_panel)
	var use_art := _skin_panel(_recipe_panel, "res://assets/ui/panel_recipe.png")

	if use_art:
		_build_recipe_art()
	else:
		_build_recipe_classic()
	_refresh_recipe_highlights()

func _ghost_button(parent: Control, pos: Vector2, size: Vector2, on_press: Callable) -> Button:
	# Tombol transparan tanpa teks di atas slot baked di art.
	var b := Button.new()
	b.flat = true
	b.text = ""
	b.position = pos
	b.size = size
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b

func _build_recipe_art() -> void:
	var close_x := _ghost_button(_recipe_panel, Vector2(419, 15), Vector2(36, 36), _toggle_recipe_book)
	close_x.mouse_filter = Control.MOUSE_FILTER_STOP

	_recipe_search_box = LineEdit.new()
	_recipe_search_box.placeholder_text = "Search recipes / materials..."
	_recipe_search_box.position = Vector2(29, 66)
	_recipe_search_box.size = Vector2(347, 50)
	_style_transparent_input(_recipe_search_box)
	_recipe_search_box.text_changed.connect(_on_recipe_search_changed)
	_recipe_panel.add_child(_recipe_search_box)

	_recipe_sort_btn = Button.new()
	_recipe_sort_btn.flat = true
	_recipe_sort_btn.add_theme_font_size_override("font_size", 14)
	_recipe_sort_btn.add_theme_color_override("font_color", Color(0.9, 0.95, 1))
	_recipe_sort_btn.position = Vector2(389, 66)
	_recipe_sort_btn.size = Vector2(65, 50)
	_recipe_sort_btn.pressed.connect(_cycle_recipe_sort)
	_recipe_panel.add_child(_recipe_sort_btn)
	_update_sort_btn_text()

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(37, 145)
	scroll.size = Vector2(377, 577)
	_recipe_panel.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	_recipe_list = list

	_recipe_summary = UIFactory.label("", 13, Color(0.6, 1, 0.7), HORIZONTAL_ALIGNMENT_LEFT)
	_recipe_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_child(_recipe_summary)

	_add_recipe_rows(list)
	_summary_as_row = true

func _build_recipe_classic() -> void:
	var title := UIFactory.label("Recipes", 28, Color(0.9, 0.95, 1), HORIZONTAL_ALIGNMENT_CENTER)
	title.position = Vector2(0, 16)
	title.size = Vector2(_recipe_panel.size.x, 40)
	_recipe_panel.add_child(title)

	var close_button := Button.new()
	close_button.text = "X"
	close_button.flat = true
	close_button.add_theme_font_size_override("font_size", 26)
	close_button.position = Vector2(_recipe_panel.size.x - 60.0, 12)
	close_button.size = Vector2(48, 48)
	close_button.pressed.connect(_toggle_recipe_book)
	_recipe_panel.add_child(close_button)

	var legend := UIFactory.label("Green rows = can be crafted now from cards on the board",
		12, Color(0.62, 0.78, 0.68), HORIZONTAL_ALIGNMENT_LEFT)
	legend.position = Vector2(16, 112)
	legend.size = Vector2(_recipe_panel.size.x - 32.0, 18)
	_recipe_panel.add_child(legend)

	_recipe_summary = UIFactory.label("", 12, Color(0.6, 1, 0.7), HORIZONTAL_ALIGNMENT_LEFT)
	_recipe_summary.position = Vector2(16, 130)
	_recipe_summary.size = Vector2(_recipe_panel.size.x - 32.0, 18)
	_recipe_panel.add_child(_recipe_summary)

	_recipe_search_box = LineEdit.new()
	_recipe_search_box.placeholder_text = "Search recipes / materials..."
	_recipe_search_box.position = Vector2(16, 64)
	_recipe_search_box.size = Vector2(_recipe_panel.size.x - 192.0, 40)
	_recipe_search_box.text_changed.connect(_on_recipe_search_changed)
	_recipe_panel.add_child(_recipe_search_box)

	_recipe_sort_box = OptionButton.new()
	_recipe_sort_box.position = Vector2(_recipe_panel.size.x - 160.0, 64)
	_recipe_sort_box.size = Vector2(144, 40)
	_recipe_sort_box.add_item("Craftable", RECIPE_SORT_CRAFTABLE)
	_recipe_sort_box.add_item("A-Z", RECIPE_SORT_AZ)
	_recipe_sort_box.add_item("Type", RECIPE_SORT_TYPE)
	_recipe_sort_box.item_selected.connect(_on_recipe_sort_changed)
	_recipe_panel.add_child(_recipe_sort_box)

	var frame := Panel.new()
	var frame_sb := StyleBoxFlat.new()
	frame_sb.bg_color = Color(0, 0, 0, 0)
	frame_sb.border_color = Color(0.75, 0.62, 0.35)
	frame_sb.set_border_width_all(2)
	frame_sb.set_corner_radius_all(8)
	frame.add_theme_stylebox_override("panel", frame_sb)
	frame.position = Vector2(16, 156)
	frame.size = Vector2(_recipe_panel.size.x - 32.0, _recipe_panel.size.y - 164.0)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_recipe_panel.add_child(frame)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(24, 164)
	scroll.size = Vector2(_recipe_panel.size.x - 48.0, _recipe_panel.size.y - 180.0)
	_recipe_panel.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	_recipe_list = list

	_add_recipe_rows(list)
	_summary_as_row = false

func _add_recipe_rows(list: VBoxContainer) -> void:
	var recipes: Array = RecipeDB.all_recipes()
	recipes.sort_custom(func(a, b): return a.id < b.id)
	for recipe in recipes:
		list.add_child(_build_recipe_row(recipe))

func _style_transparent_input(le: LineEdit) -> void:
	var empty := StyleBoxEmpty.new()
	le.add_theme_stylebox_override("normal", empty)
	le.add_theme_stylebox_override("focus", empty)
	le.add_theme_stylebox_override("read_only", empty)
	le.add_theme_color_override("font_color", Color(0.95, 0.97, 1))
	le.add_theme_color_override("font_placeholder_color", Color(0.6, 0.64, 0.72))

const RECIPE_SORT_SHORT := ["Ready", "A-Z", "Type"]

func _cycle_recipe_sort() -> void:
	_recipe_sort = (_recipe_sort + 1) % 3
	_update_sort_btn_text()
	_apply_recipe_order()

func _update_sort_btn_text() -> void:
	if _recipe_sort_btn != null:
		_recipe_sort_btn.text = RECIPE_SORT_SHORT[_recipe_sort]

func _build_recipe_row(recipe: CraftRecipe) -> Control:
	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = RECIPE_BG_OFF
	style.border_color = RECIPE_BORDER_OFF
	style.border_width_left = 5
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	row.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	row.add_child(box)

	var desc := UIFactory.label(_recipe_line(recipe), 15, RECIPE_FG_OFF, HORIZONTAL_ALIGNMENT_LEFT)
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(desc)

	var status := UIFactory.label("", 13, RECIPE_FG_OFF, HORIZONTAL_ALIGNMENT_LEFT)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(status)

	_recipe_rows.append({"recipe": recipe, "control": row, "style": style, "desc": desc, "status": status,
		"sort_name": _recipe_sort_name(recipe), "sort_cat": _recipe_sort_cat(recipe),
		"hay": _recipe_haystack(recipe)})
	return row

func _recipe_sort_name(recipe: CraftRecipe) -> String:
	return _card_short(recipe.output_id).to_lower()

func _recipe_sort_cat(recipe: CraftRecipe) -> int:
	var out: CardData = CardDB.get_card(recipe.output_id)
	return int(out.category) if out != null else 99

func _recipe_haystack(recipe: CraftRecipe) -> String:
	var parts: Array[String] = [recipe.output_id, _card_short(recipe.output_id)]
	for req in recipe.inputs:
		var item_id := String(req.get("item_id", ""))
		parts.append(item_id)
		parts.append(_card_short(item_id))
	return " ".join(parts).to_lower()

# Update warna + status tiap baris resep sesuai kondisi board saat ini.
# Yang bisa dibuat selalu dipin di paling atas (urut stabil).
func _refresh_recipe_highlights() -> void:
	if _board == null:
		return
	var makeable := 0
	for row in _recipe_rows:
		var recipe: CraftRecipe = row["recipe"]
		var style: StyleBoxFlat = row["style"]
		var desc: Label = row["desc"]
		var status: Label = row["status"]
		var can := RecipeResolver.can_make_now(recipe, _board)
		row["can"] = can
		style.bg_color = RECIPE_BG_ON if can else RECIPE_BG_OFF
		style.border_color = RECIPE_BORDER_ON if can else RECIPE_BORDER_OFF
		desc.add_theme_color_override("font_color", RECIPE_FG_ON if can else RECIPE_FG_OFF)
		if can:
			makeable += 1
			status.text = "✔  CAN BE CRAFTED NOW"
			status.add_theme_color_override("font_color", RECIPE_BORDER_ON)
		else:
			status.text = "✖  " + RecipeResolver.unmet_reason(recipe, _board)
			status.add_theme_color_override("font_color", RECIPE_STATUS_BAD)
	_apply_recipe_order()
	if _recipe_summary != null:
		_recipe_summary.text = "%d / %d recipes can be crafted now" % [makeable, _recipe_rows.size()]

func _on_recipe_search_changed(text: String) -> void:
	_recipe_search = text
	_apply_recipe_order()

func _on_recipe_sort_changed(index: int) -> void:
	_recipe_sort = index
	_apply_recipe_order()

# Urut + saring baris resep: mode "Bisa dibuat" (hijau di atas, stabil),
# "A-Z", atau "Jenis" (kategori output). Query menyaring nama/bahan.
# Reorder hanya saat signature berubah agar scroll tidak lompat.
func _apply_recipe_order() -> void:
	if _recipe_list == null or _board == null:
		return
	var q := _recipe_search.strip_edges().to_lower()
	var sig := "%d|%s|" % [_recipe_sort, q]
	for row in _recipe_rows:
		sig += "1" if bool(row.get("can", false)) else "0"
	var vis := {}
	for row in _recipe_rows:
		var recipe: CraftRecipe = row["recipe"]
		var show: bool = q == "" or String(row.get("hay", "")).contains(q)
		vis[recipe.id] = show
		sig += "v" if show else "h"
	if sig == _recipe_order_sig:
		return
	_recipe_order_sig = sig
	for row in _recipe_rows:
		var recipe: CraftRecipe = row["recipe"]
		(row["control"] as Control).visible = bool(vis[recipe.id])
	var ordered: Array = []
	for row in _recipe_rows:
		var recipe: CraftRecipe = row["recipe"]
		if bool(vis[recipe.id]):
			ordered.append(row)
	ordered.sort_custom(_recipe_row_less)
	var idx := 0
	for row in ordered:
		_recipe_list.move_child(row["control"], idx)
		idx += 1
	for row in _recipe_rows:
		var recipe: CraftRecipe = row["recipe"]
		if not bool(vis[recipe.id]):
			_recipe_list.move_child(row["control"], idx)
			idx += 1

func _recipe_row_less(a: Dictionary, b: Dictionary) -> bool:
	if _recipe_sort == RECIPE_SORT_AZ:
		return String(a.get("sort_name", "")) < String(b.get("sort_name", ""))
	if _recipe_sort == RECIPE_SORT_TYPE:
		if int(a.get("sort_cat", 99)) != int(b.get("sort_cat", 99)):
			return int(a.get("sort_cat", 99)) < int(b.get("sort_cat", 99))
		return String(a.get("sort_name", "")) < String(b.get("sort_name", ""))
	var a_can := bool(a.get("can", false))
	var b_can := bool(b.get("can", false))
	if a_can != b_can:
		return a_can
	return String(a.get("sort_name", "")) < String(b.get("sort_name", ""))

func _card_short(card_id: String) -> String:
	var data: CardData = CardDB.get_card(card_id)
	return data.display_name if data != null else card_id

func _recipe_line(recipe: CraftRecipe) -> String:
	var ins: Array[String] = []
	for req in recipe.inputs:
		ins.append("%s x%d" % [_card_short(String(req.get("item_id", "?"))), int(req.get("qty", 1))])
	var line := _card_short(recipe.output_id)
	if int(recipe.output_qty) > 1:
		line += " x%d" % int(recipe.output_qty)
	line += "\n    Materials: " + " + ".join(ins)
	var gates: Array[String] = []
	if String(recipe.required_building_id) != "":
		gates.append("Building: " + _card_short(String(recipe.required_building_id)))
	if not recipe.required_any_structure_ids.is_empty():
		var names: Array[String] = []
		for id in recipe.required_any_structure_ids:
			names.append(_card_short(String(id)))
		gates.append("Needs: " + " / ".join(names))
	if not recipe.required_any_worker_ids.is_empty():
		var names: Array[String] = []
		for id in recipe.required_any_worker_ids:
			names.append(_card_short(String(id)))
		gates.append("Workers: " + " / ".join(names))
	if not recipe.structure_target_ids.is_empty():
		var names: Array[String] = []
		for id in recipe.structure_target_ids:
			names.append(_card_short(String(id)))
		gates.append("To: " + " / ".join(names))
	if int(recipe.duration_days) > 0:
		gates.append("%d-day production" % int(recipe.duration_days))
	if not gates.is_empty():
		line += "  |  " + ", ".join(gates)
	return line

# ---------- Event popup (random event + A9 PLAYER_CHOICE) ----------
# Panel statis dari hud.tscn; judul/deskripsi/pilihan diisi dinamis.
# Random event antre bila popup sedang tampil; efek diterapkan saat OK.

var _event_queue: Array[String] = []
var _event_popup_busy := false

func _clear_event_popup() -> void:
	for child in _event_popup.get_children():
		# remove_child dulu (queue_free saja masih tampil 1 frame
		# dan menumpuk dengan isi popup berikutnya).
		_event_popup.remove_child(child)
		child.queue_free()
	_choice_buttons.clear()
	_event_card_ref = null

# Style popup event sekali saja: panel navy + border emas, tombol teks
# disamakan gaya UI game (asset btn_*.png hanya ikon, tidak cocok di sini).
var _popup_styles_built := false
var _popup_btn_normal: StyleBoxFlat
var _popup_btn_hover: StyleBoxFlat
var _popup_btn_pressed: StyleBoxFlat

func _build_popup_styles() -> void:
	if _popup_styles_built:
		return
	_popup_styles_built = true
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = Color(0.11, 0.12, 0.22)
	panel_sb.set_border_width_all(2)
	panel_sb.border_color = Color(0.85, 0.7, 0.35)
	panel_sb.set_corner_radius_all(12)
	panel_sb.content_margin_left = 4.0
	panel_sb.content_margin_right = 4.0
	_event_popup.add_theme_stylebox_override("panel", panel_sb)
	_popup_btn_normal = StyleBoxFlat.new()
	_popup_btn_normal.bg_color = Color(0.2, 0.21, 0.33)
	_popup_btn_normal.set_border_width_all(2)
	_popup_btn_normal.border_color = Color(0.85, 0.7, 0.35)
	_popup_btn_normal.set_corner_radius_all(8)
	_popup_btn_hover = _popup_btn_normal.duplicate() as StyleBoxFlat
	_popup_btn_hover.bg_color = Color(0.3, 0.32, 0.48)
	_popup_btn_pressed = _popup_btn_normal.duplicate() as StyleBoxFlat
	_popup_btn_pressed.bg_color = Color(0.12, 0.13, 0.24)

func _style_popup_button(b: Button) -> void:
	_build_popup_styles()
	b.add_theme_stylebox_override("normal", _popup_btn_normal)
	b.add_theme_stylebox_override("hover", _popup_btn_hover)
	b.add_theme_stylebox_override("pressed", _popup_btn_pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color(0.6, 0.8, 1.0))
	b.add_theme_font_size_override("font_size", 20)

# Tinggi teks ter-wrap (baris * tinggi baris) agar label tidak tumpuk.
func _wrapped_text_height(text: String, font_size: int, width: float) -> float:
	var fnt := ThemeDB.fallback_font
	if fnt == null or text.is_empty():
		return float(font_size + 8)
	var sz := fnt.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size)
	var rows := maxi(1, int(ceil(sz.y / maxf(1.0, fnt.get_height(font_size)))))
	return float(rows * (font_size + 8) + 8)

func show_event_popup(event_id: String) -> void:
	if GameState.is_game_over:
		return
	if _event_popup_busy or _event_popup.visible:
		if not _event_queue.has(event_id):
			_event_queue.append(event_id)
		return
	_display_event_popup(event_id)

func _display_event_popup(event_id: String) -> void:
	var event_data := CardDB.get_card(event_id) as EventCardData
	if event_data == null:
		_show_next_queued_event()
		return
	_event_popup_busy = true
	_clear_event_popup()
	_build_popup_styles()
	# Layout kursor dari atas; tinggi panel menyesuaikan isi (art + teks
	# bervariasi, posisi fix lama bikin teks tumpuk).
	var y := 16.0
	var title := Label.new()
	title.text = event_data.display_name
	title.position = Vector2(16, y)
	title.add_theme_font_size_override("font_size", 22)
	title.size = Vector2(408, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_event_popup.add_child(title)
	y += 38.0
	y = _maybe_add_event_art(event_id, y)
	var desc := Label.new()
	desc.text = event_data.description
	desc.position = Vector2(16, y)
	var desc_h := _wrapped_text_height(event_data.description, 16, 408.0)
	desc.size = Vector2(408, desc_h)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_event_popup.add_child(desc)
	y += desc_h + 10.0
	if not event_data.choices.is_empty():
		# PLAYER_CHOICE: popup langsung berisi tombol pilihan.
		for i in event_data.choices.size():
			var choice: Dictionary = event_data.choices[i]
			var btn := Button.new()
			btn.text = String(choice.get("label", "Choose"))
			btn.position = Vector2(16, y)
			btn.size = Vector2(408, 44)
			btn.pressed.connect(_on_event_choice.bind(event_id, i))
			_style_popup_button(btn)
			_event_popup.add_child(btn)
			_choice_buttons.append(btn)
			y += 54.0
	else:
		var effect := Label.new()
		effect.text = Events.event_summary(event_id)
		effect.position = Vector2(16, y)
		effect.size = Vector2(408, 26)
		effect.add_theme_font_size_override("font_size", 15)
		effect.add_theme_color_override("font_color", Color(1, 0.7, 0.55))
		_event_popup.add_child(effect)
		y += 32.0
		var ok := Button.new()
		ok.text = "OK"
		ok.position = Vector2(16, y)
		ok.size = Vector2(408, 48)
		ok.pressed.connect(_on_event_ok.bind(event_id))
		_style_popup_button(ok)
		_event_popup.add_child(ok)
		_choice_buttons.append(ok)
		y += 56.0
	y += 12.0
	_event_popup.offset_top = -y * 0.5
	_event_popup.offset_bottom = y * 0.5
	_event_popup.visible = true

func _on_event_choice(event_id: String, index: int) -> void:
	_event_popup.visible = false
	_event_popup_busy = false
	_clear_event_popup()
	if GameState.is_game_over:
		_event_queue.clear()
		return
	var board: Board = get_tree().get_first_node_in_group(&"board")
	if board != null:
		Events.apply_event(board, event_id, index)
	_show_next_queued_event()

# Gambar event (opsional): assets/cards/art_<event_id>.png.
# Mengembalikan posisi y berikutnya (tambah tinggi art bila ada).
func _maybe_add_event_art(event_id: String, y: float) -> float:
	var path := "res://assets/cards/art_%s.png" % event_id
	if not ResourceLoader.exists(path):
		return y
	var art := TextureRect.new()
	art.texture = load(path)
	art.position = Vector2(16, y)
	art.size = Vector2(408, 200)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_event_popup.add_child(art)
	return y + 208.0

func _on_event_ok(event_id: String) -> void:
	_event_popup.visible = false
	_event_popup_busy = false
	_clear_event_popup()
	if GameState.is_game_over:
		_event_queue.clear()
		return
	var board: Board = get_tree().get_first_node_in_group(&"board")
	Events.apply_event(board, event_id)
	_show_next_queued_event()

func _show_next_queued_event() -> void:
	if _event_queue.is_empty():
		return
	var next_id: String = _event_queue.pop_front()
	show_event_popup(next_id)

func show_event_choices(card: Card, event_data: EventCardData) -> void:
	if _event_popup_busy:
		return
	if _event_card_ref != null and is_instance_valid(_event_card_ref) \
			and _event_card_ref != card:
		return
	_event_card_ref = card
	_clear_event_popup()
	_event_card_ref = card
	var title := Label.new()
	title.text = event_data.display_name
	title.position = Vector2(16, 12)
	title.add_theme_font_size_override("font_size", 20)
	title.size = Vector2(400, 30)
	_event_popup.add_child(title)
	var y := _maybe_add_event_art(card.get_card_id(), 48.0)
	var desc := Label.new()
	desc.text = event_data.description
	desc.position = Vector2(16, y)
	desc.size = Vector2(400, 60)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_event_popup.add_child(desc)
	y += 70.0
	for i in event_data.choices.size():
		var choice: Dictionary = event_data.choices[i]
		var btn := Button.new()
		btn.text = choice.get("label", "Choose")
		btn.position = Vector2(16, y)
		btn.size = Vector2(408, 40)
		btn.pressed.connect(_resolve_choice.bind(i))
		_style_popup_button(btn)
		_event_popup.add_child(btn)
		_choice_buttons.append(btn)
		y += 50.0
	_event_popup.visible = true

func _resolve_choice(index: int) -> void:
	if _event_card_ref == null:
		return
	var board: Board = get_tree().get_first_node_in_group(&"board")
	Events.apply_event(board, _event_card_ref.get_card_id(), index)
	if is_instance_valid(_event_card_ref):
		_event_card_ref.queue_free()
	_event_card_ref = null
	_event_popup.visible = false

# ---------- Game over (A16) ----------
# Scene dedicated: scenes/game_over.tscn (class GameOverScreen).

func _on_game_over(reason: String) -> void:
	var screen: GameOverScreen = (load("res://scenes/game_over.tscn") as PackedScene).instantiate()
	add_child(screen)
	screen.setup(reason, false)

func _on_victory(reason: String) -> void:
	var screen: GameOverScreen = (load("res://scenes/game_over.tscn") as PackedScene).instantiate()
	add_child(screen)
	screen.setup(reason, true)
