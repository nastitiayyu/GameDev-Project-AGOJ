class_name UIFactory
extends RefCounted

# Pabrik kecil untuk UI kode: satu baris per kontrol, tanpa duplikasi
# StyleBox/tema berulang di board.gd, hud.gd, menu.gd, intro.gd.

static func panel(size: Vector2, color: Color, radius := 8.0) -> Panel:
	var p := Panel.new()
	p.size = size
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	p.add_theme_stylebox_override("panel", sb)
	p.pivot_offset = size * 0.5
	return p

static func label(text: String, font_size := 15, color := Color(0.9, 0.95, 1),
		align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

static func button(text: String, size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.size = size
	return b

const VIGNETTE_SHADER := "res://shaders/vignette_grain.gdshader"

# Overlay vignette + grain full-rect. Kembalikan node-nya (atau null).
static func vignette(parent: Control, size: Vector2, z := 400) -> ColorRect:
	if not ResourceLoader.exists(VIGNETTE_SHADER):
		return null
	var overlay := ColorRect.new()
	overlay.color = Color(1, 1, 1, 1)
	overlay.position = Vector2.ZERO
	overlay.size = size
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.z_index = z
	var mat := ShaderMaterial.new()
	mat.shader = load(VIGNETTE_SHADER)
	overlay.material = mat
	parent.add_child(overlay)
	return overlay
