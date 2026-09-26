extends Control

# Main Menu (GDD S4.3): Start / Keluar. Continue butuh save/load
# (di luar cakupan final project, sesuai GDD) jadi tidak ada.
#
# Background art opsional: assets/ui/main_menu_bg.png (planet + logo).
# Kalau belum ada, pakai warna gelap. Kalau bg ada, judul teks disembunyikan
# (logo sudah baked-in di gambar).

const BG_PATH := "res://assets/ui/main_menu_bg.png"
# Font judul menu: Sriracha.
# Kalau file belum ke-import editor, fallback ke menu_font.ttf (isi identik).
const FONT_PATH := "res://assets/ui/Sriracha.ttf"
# Fallback kalau Sriracha belum ke-import: menu_font.ttf (file yang sama).
const FONT_FALLBACK := "res://assets/ui/menu_font.ttf"

static var _menu_font: Font = null

static func menu_font() -> Font:
	if _menu_font != null:
		return _menu_font
	for p in [FONT_PATH, FONT_FALLBACK]:
		if ResourceLoader.exists(p):
			var f := load(p) as Font
			if f != null:
				_menu_font = f
				return _menu_font
	if GameState.default_font != null:
		return GameState.default_font
	return null

func _ready() -> void:
	Sfx.play_music("menu")
	var view := get_viewport_rect().size
	if ResourceLoader.exists(BG_PATH):
		var bg_art := TextureRect.new()
		bg_art.texture = load(BG_PATH)
		bg_art.set_anchors_preset(Control.PRESET_FULL_RECT, false)
		bg_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg_art)
	else:
		var bg := ColorRect.new()
		bg.color = Color(0.06, 0.07, 0.12)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT, false)
		add_child(bg)
		var title := UIFactory.label("SPACE SALVAGE", 64)
		title.position = Vector2(view.x * 0.5 - 350.0, view.y * 0.5 - 190.0)
		title.size = Vector2(700, 90)
		add_child(title)
	

	var start_button := _make_menu_button("Start")
	start_button.position = Vector2(view.x * 0.06, view.y * 0.50)
	start_button.pressed.connect(_on_start)
	add_child(start_button)

	var quit_button := _make_menu_button("Exit")
	quit_button.position = Vector2(view.x * 0.06, view.y * 0.50 + 90.0)
	quit_button.pressed.connect(_on_quit)
	add_child(quit_button)
	UIFactory.vignette(self, view, 100)

func _make_menu_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size = Vector2(360, 72)
	b.add_theme_font_size_override("font_size", 48)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color(0.6, 0.8, 1.0))
	b.add_theme_color_override("font_pressed_color", Color(0.4, 0.65, 1.0))
	var mf := menu_font()
	if mf != null:
		b.add_theme_font_override("font", mf)
	return b

func _on_start() -> void:
	get_tree().change_scene_to_file("res://main.tscn")

func _on_quit() -> void:
	get_tree().quit()
