class_name Card
extends Panel

signal clicked(card: Card)
signal dropped(card: Card, position: Vector2)

const DRAG_THRESHOLD := 6.0
const DRAG_SCALE := 1.1
const DRAG_Z_INDEX := 100

var card_data: CardData
var stack_count := 1

# A3 — runtime state gather (bukan data, tidak menyentuh resource bersama)
var assigned_node: Card = null        # Unit → Node yang sedang dikerjai
var node_durability_left: int = -1    # Node: sisa durability (is_limited)
var _gather_timer := 0.0

# A4 — state machine unit
var unit_state: int = Enums.UnitState.IDLE
var assigned_building: Card = null    # Unit → Building tempat WORKING
var equipped_tool_ids: Array[String] = []

# A7 — building runtime
var is_built := false                 # sudah dibayar build_cost & terpasang
var is_off := false                   # auto-shutdown kekurangan power
var production_timer := 0.0           # progress produksi real-time (dipakai unit WORKING)

# A8 — package runtime
var assembled_items: Dictionary = {}  # item_id -> qty sudah dikunci
var is_departing := false             # sedang TRAVELING (kartu dikeluarkan dari board)

var _dragging := false
var _was_dragging := false
var _drag_offset := Vector2.ZERO
var _press_position := Vector2.ZERO
var _pre_drag_position := Vector2.ZERO

@onready var _title_label: Label = %TitleLabel
@onready var _color_rect: ColorRect = %ColorRect
@onready var _count_label: Label = %CountLabel
@onready var _category_label: Label = %CategoryLabel
@onready var _status_label: Label = %StatusLabel
@onready var _progress_track: ColorRect = %ProgressTrack
@onready var _progress_fill: ColorRect = %ProgressFill
@onready var _frame_rect: TextureRect = %FrameTexture
@onready var _art_rect: TextureRect = %ArtTexture

# Art per kartu: assets/cards/art_<card_id>.png (opsional).
# Kalau belum ada, kotak warna placeholder tetap tampil.
static var _art_cache: Dictionary = {}

# Frame kartu per zona (biru = kapal, coklat = angkasa). File PNG opsional:
# kalau belum ada, kartu tampil placeholder lama. Taruh di:
#   assets/cards/card_frame_ship.png  (biru, Zona Kapal)
#   assets/cards/card_frame_space.png (coklat, Zona Angkasa)
const FRAME_SHIP_PATH := "res://assets/cards/card_frame_ship.png"
const FRAME_SPACE_PATH := "res://assets/cards/card_frame_space.png"
static var _frame_ship: Texture2D
static var _frame_space: Texture2D
static var _fallback_style: StyleBoxFlat

func _ready() -> void:
	add_to_group(&"cards")
	_apply_bold_fonts()
	refresh_zone_frame()
	_update_visuals()

# Bold: FontVariation embolden di atas fallback font (game_font).
static var _bold_font: Font = null

static func _bold() -> Font:
	var base := ThemeDB.fallback_font
	var fv := _bold_font as FontVariation
	if fv == null or fv.base_font != base:
		fv = FontVariation.new()
		fv.base_font = base
		fv.variation_embolden = 0.8
		_bold_font = fv
	return _bold_font

func _apply_bold_fonts() -> void:
	var f := _bold()
	for lab in [_title_label, _count_label, _category_label, _status_label]:
		if lab != null:
			(lab as Label).add_theme_font_override("font", f)

func setup_card(data: CardData, count := 1, built := false) -> void:
	card_data = data
	stack_count = count
	is_built = built
	if is_building() and not built:
		# Bangunan belum dibangun: tampil sebagai kartu (tidak bisa dipakai sampai build_cost dibayar)
		is_off = false
	var node_data := data as NodeCardData
	if node_data != null and node_data.is_limited:
		node_durability_left = node_data.durability
	if is_inside_tree():
		_update_visuals()

func is_unit() -> bool:
	return card_data != null and card_data.category == Enums.CardCategory.UNIT

func is_node() -> bool:
	return card_data != null and card_data.category == Enums.CardCategory.NODE

func is_building() -> bool:
	return card_data != null and card_data.category == Enums.CardCategory.BUILDING

func is_package() -> bool:
	return card_data != null and card_data.category == Enums.CardCategory.PACKAGE

func is_tool() -> bool:
	return card_data != null and card_data.category == Enums.CardCategory.TOOL

func get_card_id() -> String:
	return card_data.id

func _update_visuals() -> void:
	if card_data == null:
		return
	_title_label.text = card_data.display_name
	_refresh_art()
	_category_label.text = _category_short()
	_count_label.text = "x%d" % stack_count if stack_count > 1 else ""
	_count_label.visible = stack_count > 1
	_update_status_visual()

func _update_status_visual() -> void:
	if card_data == null:
		return
	if is_unit():
		match unit_state:
			Enums.UnitState.DEAD:
				_status_label.text = "DEAD"
				return
			Enums.UnitState.TRAVELING:
				_status_label.text = "TRAVELING"
				return
	if assigned_node != null or assigned_building != null:
		_status_label.text = "WORKING"
		return
	if is_package():
		_status_label.text = _package_progress_text()
		if _is_deadline_urgent():
			_status_label.add_theme_color_override("font_color", Color(0.9, 0.15, 0.1))
		else:
			_status_label.remove_theme_color_override("font_color")
		return
	if is_node() and node_durability_left >= 0:
		_status_label.text = "DUR %d" % node_durability_left
		return
	if is_unit() and not equipped_tool_ids.is_empty():
		var names: Array[String] = []
		for tool_id in equipped_tool_ids:
			var tool: CardData = CardDB.get_card(tool_id)
			names.append(tool.display_name if tool != null else tool_id)
		_status_label.text = "EQ: " + ", ".join(names)
		return
	_status_label.text = ""

func refresh() -> void:
	_update_visuals()

# Tampilkan art PNG kalau ada, kalau tidak pakai kotak warna kategori.
# Mode art: gambar full-bleed seukuran kartu, nama pindah ke bawah,
# label kategori disembunyikan (status/progress tetap di tempatnya).
func _refresh_art() -> void:
	if _art_rect == null or _color_rect == null:
		return
	var tex := card_art()
	if tex == null:
		_art_rect.visible = false
		_color_rect.visible = true
		_color_rect.color = card_data.get_placeholder_color()
		_title_label.offset_top = 51.0
		_title_label.offset_bottom = 78.0
		_category_label.visible = true
		_status_label.offset_top = 96.0
		_status_label.offset_bottom = 113.0
		return
	_art_rect.texture = tex
	_art_rect.offset_left = -6.0
	_art_rect.offset_top = -6.0
	_art_rect.offset_right = 96.0
	_art_rect.offset_bottom = 99.0
	_art_rect.visible = true
	_color_rect.visible = false
	_title_label.offset_top = 100.0
	_title_label.offset_bottom = 126.0
	_category_label.visible = false
	_status_label.offset_top = 80.0
	_status_label.offset_bottom = 93.0

# Art kartu (atau null kalau belum ada file-nya). Dipakai inspect overlay.
# Urutan: art spesifik per kartu → art bersama per jenis → null (placeholder).
# File jenis (8, di assets/cards/): art_unit, art_node, art_building,
# art_tool, art_material (mentah+olahan+loot), art_food, art_package, art_event.
func card_art() -> Texture2D:
	if card_data == null:
		return null
	if not _art_cache.has(card_data.id):
		_art_cache[card_data.id] = _find_art()
	return _art_cache[card_data.id]

func _find_art() -> Texture2D:
	var specific := "res://assets/cards/art_%s.png" % card_data.id
	if ResourceLoader.exists(specific):
		return load(specific)
	var shared := "res://assets/cards/art_%s.png" % _art_group_name()
	if shared != specific and ResourceLoader.exists(shared):
		return load(shared)
	return null

func _art_group_name() -> String:
	match card_data.category:
		Enums.CardCategory.UNIT:
			return "unit"
		Enums.CardCategory.NODE:
			return "node"
		Enums.CardCategory.BUILDING:
			return "building"
		Enums.CardCategory.TOOL:
			return "tool"
		Enums.CardCategory.ITEM_RAW, Enums.CardCategory.ITEM_PROCESSED, Enums.CardCategory.CURRENCY_LOOT:
			return "material"
		Enums.CardCategory.ITEM_FOOD:
			return "food"
		Enums.CardCategory.PACKAGE:
			return "package"
		Enums.CardCategory.EVENT:
			return "event"
	return ""

# Pilih frame biru/coklat sesuai zona posisi kartu saat ini.
func refresh_zone_frame() -> void:
	if _frame_rect == null:
		return
	var in_space := false
	var board := get_tree().get_first_node_in_group(&"board") as Board
	if board != null and is_inside_tree():
		in_space = board.get_zone(global_position + size * 0.5) == Enums.BoardZone.OPEN_SPACE
	var tex := _frame_texture(in_space)
	if tex == null:
		_frame_rect.visible = false
		add_theme_stylebox_override("panel", _fallback_panel_style())
		return
	remove_theme_stylebox_override("panel")
	_frame_rect.texture = tex
	_frame_rect.visible = true

static func _frame_texture(in_space: bool) -> Texture2D:
	if in_space:
		if _frame_space == null and ResourceLoader.exists(FRAME_SPACE_PATH):
			_frame_space = load(FRAME_SPACE_PATH)
		return _frame_space
	if _frame_ship == null and ResourceLoader.exists(FRAME_SHIP_PATH):
		_frame_ship = load(FRAME_SHIP_PATH)
	return _frame_ship

# Panel kartu transparan (frame PNG yang tampil). Kalau PNG belum ada,
# pakai gaya placeholder lama agar kartu tetap terbaca.
static func _fallback_panel_style() -> StyleBoxFlat:
	if _fallback_style == null:
		_fallback_style = StyleBoxFlat.new()
		_fallback_style.bg_color = Color(0.96, 0.96, 0.98)
		_fallback_style.set_border_width_all(2)
		_fallback_style.border_color = Color(0.35, 0.38, 0.45)
		_fallback_style.set_corner_radius_all(8)
		_fallback_style.shadow_color = Color(0, 0, 0, 0.25)
		_fallback_style.shadow_size = 4
	return _fallback_style

# ---------- A3: assign unit ke node ----------

func assign_to_node(node: Card) -> void:
	assigned_node = node
	_gather_timer = 0.0
	set_gather_progress(0.0)
	set_unit_state(Enums.UnitState.WORKING)
	z_index = 2
	global_position = node.global_position + Vector2(6.0, 23.0)
	_update_status_visual()

func unassign() -> void:
	assigned_node = null
	_gather_timer = 0.0
	set_gather_progress(-1.0)
	if assigned_building == null:
		set_unit_state(Enums.UnitState.IDLE)
	else:
		_update_status_visual()
	z_index = 0

func set_gather_progress(p: float) -> void:
	if _progress_track == null or _progress_fill == null:
		return
	var show_bar: bool = (assigned_node != null or assigned_building != null) and p >= 0.0
	_progress_track.visible = show_bar
	_progress_fill.visible = show_bar
	if show_bar:
		_progress_fill.size.x = _progress_track.size.x * clampf(p, 0.0, 1.0)

# ---------- A7: assign unit ke building ----------

func assign_to_building(building: Card) -> void:
	assigned_building = building
	set_unit_state(Enums.UnitState.WORKING)
	z_index = 2
	global_position = building.global_position + Vector2(6.0, 23.0)
	_update_status_visual()

func unassign_from_building() -> void:
	assigned_building = null
	set_gather_progress(-1.0)
	if assigned_node == null:
		set_unit_state(Enums.UnitState.IDLE)
	else:
		_update_status_visual()
	z_index = 0

# ---------- A4: unit state machine ----------

func set_unit_state(state: int) -> void:
	unit_state = state
	_update_status_visual()

# ---------- A5: tool equip (1 tool per unit) ----------

func equip_tool(tool_id: String) -> void:
	if equipped_tool_ids.has(tool_id):
		return
	equipped_tool_ids.append(tool_id)
	_update_status_visual()

func unequip_tool(tool_id: String) -> void:
	equipped_tool_ids.erase(tool_id)
	_update_status_visual()

# Klik kanan unit: lepas tool yang dipakai (kartu kembali ke board).
func _unequip_last() -> void:
	if equipped_tool_ids.is_empty():
		return
	var board := get_tree().get_first_node_in_group(&"board") as Board
	if board == null:
		return
	var tool_id: String = equipped_tool_ids.back()
	unequip_tool(tool_id)
	board.spawn_card_at(tool_id, global_position + size * 0.5 + Vector2(70, 0))
	board._show_toast("Removed", global_position, Color(0.7, 0.95, 1))

func has_equipped_tool(tool_id: String) -> bool:
	return equipped_tool_ids.has(tool_id)

# ---------- A8: package assembly ----------

func get_package_requirement_count() -> int:
	var pkg_data := card_data as PackageCardData
	if pkg_data == null:
		return 0
	return pkg_data.required_items.size()

func is_package_complete() -> bool:
	var required: Array = card_data.required_items if card_data != null else []
	for req in required:
		var item_id: String = req.get("item_id", "")
		var qty: int = int(req.get("qty", 1))
		if int(assembled_items.get(item_id, 0)) < qty:
			return false
	return required.size() > 0

func _package_progress_text() -> String:
	var required: Array = card_data.required_items if card_data != null else []
	var done := 0
	var total := 0
	for req in required:
		var item_id: String = req.get("item_id", "")
		var qty: int = int(req.get("qty", 1))
		total += qty
		done += mini(qty, int(assembled_items.get(item_id, 0)))
	if total == 0:
		return ""
	var base := "READY" if is_package_complete() else "%d/%d" % [done, total]
	if has_meta("emergency"):
		return "SOS %ds %s" % [maxi(0, int(get_meta("time_left", 0.0))), base]
	if get_card_id().begins_with("pkg_quest_"):
		return base  # quest tidak kedaluwarsa
	return "%s %s" % [base, _deadline_text()]

# Sisa deadline kontrak ("8d" / "2.4d"). Diisi board._tick_deadlines per tick;
# fallback ke data mentah sebelum tick pertama jalan.
func _deadline_text() -> String:
	var pkg := card_data as PackageCardData
	var full := float(pkg.deadline_days) if pkg != null else 0.0
	var left := float(get_meta("deadline_left", full))
	if left >= 3.0:
		return "%dd" % int(ceil(left))
	return "%.1fd" % maxf(0.0, left)

# Deadline < 1 hari: status merah (di-refresh tiap tick via refresh()).
func _is_deadline_urgent() -> bool:
	if not is_package() or has_meta("emergency"):
		return false
	if get_card_id().begins_with("pkg_quest_"):
		return false
	var pkg := card_data as PackageCardData
	var full := float(pkg.deadline_days) if pkg != null else 0.0
	return float(get_meta("deadline_left", full)) < 1.0

func set_stack_count(n: int) -> void:
	stack_count = n
	_update_visuals()

func _category_short() -> String:
	match card_data.category:
		Enums.CardCategory.NODE:
			return "NODE"
		Enums.CardCategory.ITEM_RAW:
			return "RAW"
		Enums.CardCategory.ITEM_PROCESSED:
			return "PROC"
		Enums.CardCategory.ITEM_FOOD:
			return "FOOD"
		Enums.CardCategory.TOOL:
			return "TOOL"
		Enums.CardCategory.BUILDING:
			return "BUILD"
		Enums.CardCategory.UNIT:
			return "UNIT"
		Enums.CardCategory.PACKAGE:
			return "PKG"
		Enums.CardCategory.EVENT:
			return "EVENT"
		Enums.CardCategory.CURRENCY_LOOT:
			return "LOOT"
	return ""

func is_draggable() -> bool:
	if card_data == null:
		return false
	if card_data.category == Enums.CardCategory.NODE or card_data.category == Enums.CardCategory.EVENT:
		return false
	if is_building() and is_built:
		return false
	if is_unit() and (unit_state == Enums.UnitState.TRAVELING or unit_state == Enums.UnitState.DEAD):
		return false
	return true

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT \
			and event.pressed:
		if is_unit():
			_unequip_last()
			return
		_split_stack()
		return
	if not is_draggable():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_drag()
		else:
			_end_drag()

func _process(_delta: float) -> void:
	if not _dragging:
		return
	global_position = get_global_mouse_position() - _drag_offset
	if not _was_dragging and global_position.distance_to(_press_position) > DRAG_THRESHOLD:
		_was_dragging = true
	if _was_dragging:
		var preview_board := get_tree().get_first_node_in_group(&"board") as Board
		if preview_board != null:
			preview_board.update_combine_preview(self)

func _begin_drag() -> void:
	_dragging = true
	_was_dragging = false
	_press_position = get_global_mouse_position()
	_pre_drag_position = global_position
	_drag_offset = _press_position - global_position
	z_index = DRAG_Z_INDEX
	Sfx.play("pickup")
	pivot_offset = size * 0.5
	scale = Vector2(DRAG_SCALE, DRAG_SCALE)

func _end_drag() -> void:
	if not _dragging:
		return
	_dragging = false
	z_index = 0
	pivot_offset = Vector2.ZERO
	scale = Vector2.ONE
	var preview_board := get_tree().get_first_node_in_group(&"board") as Board
	if preview_board != null:
		preview_board.hide_combine_preview()
	if _was_dragging:
		var board: Node = get_tree().get_first_node_in_group(&"board")
		if board == null or not board.validate_drop(self):
			_revert_drop()
			return
		if _try_merge_stack():
			return
		Sfx.play("drop")
		dropped.emit(self, get_global_mouse_position())
	else:
		clicked.emit(self)

func _revert_drop() -> void:
	global_position = _pre_drag_position
	var tween := create_tween()
	tween.tween_property(self, "self_modulate", Color(1, 0.35, 0.35, 1), 0.12)
	tween.tween_property(self, "self_modulate", Color.WHITE, 0.3)

# Klik kanan: belah stack jadi dua (setengah dibulatkan ke bawah pindah ke
# kartu baru di sebelahnya, sisa minimal 1). Bukan item / isi 1: abaikan.
func _split_stack() -> void:
	if not _is_stackable_item() or stack_count <= 1:
		return
	var board := get_tree().get_first_node_in_group(&"board") as Board
	if board == null:
		return
	var moved: int = maxi(1, stack_count / 2)
	if moved >= stack_count:
		return
	set_stack_count(stack_count - moved)
	var top_left := global_position + Vector2(size.x + 16.0, 16.0)
	board.spawn_card_at(card_data.id, top_left + size * 0.5, moved)
	Sfx.play("unstack")

func _is_stackable_item() -> bool:
	return card_data != null \
		and card_data.stack_max > 0 \
		and (card_data.category == Enums.CardCategory.ITEM_RAW \
			or card_data.category == Enums.CardCategory.ITEM_PROCESSED \
			or card_data.category == Enums.CardCategory.ITEM_FOOD)

func _try_merge_stack() -> bool:
	if not _is_stackable_item():
		return false
	var mouse_position := get_global_mouse_position()
	for node in get_tree().get_nodes_in_group(&"cards"):
		var other: Card = node as Card
		if other == self or other.is_queued_for_deletion():
			continue
		if other.card_data == null or other.card_data.id != card_data.id:
			continue
		if other.stack_count >= other.card_data.stack_max:
			continue
		if not other.get_global_rect().grow(4.0).has_point(mouse_position):
			continue
		# Resep combine lebih prioritas daripada stacking (mis. Water+Water =
		# Oxygen Tank, Iron+Iron = Component): kalau pasangan ini cocok resep,
		# biarkan drop lanjut ke Combine Engine, jangan di-merge.
		var board := get_tree().get_first_node_in_group(&"board") as Board
		if board != null and RecipeResolver.find_recipe(self, other, board) != null:
			return false
		var space: int = other.card_data.stack_max - other.stack_count
		var moved: int = mini(space, stack_count)
		other.stack_count += moved
		other._update_visuals()
		stack_count -= moved
		if stack_count <= 0:
			queue_free()
		else:
			_update_visuals()
			global_position = other.global_position + Vector2(12, 12)
		Sfx.play("stack")
		return true
	return false
