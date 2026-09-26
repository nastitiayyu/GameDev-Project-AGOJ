class_name IntroOverlay
extends ColorRect

# Intro: teks cerita fade-in berurutan, lalu tombol Mulai.
# Board memanggil setup() lalu menunggu signal finished(kit).

signal finished(kit: Array)

# Starter kit tunggal (gaya Survivor: sumber daya dasar dulu).
const DEFAULT_KIT: Array = [
	["unit_astronaut", 1], ["item_water", 2], ["item_food", 2],
	["item_mushroom", 2], ["item_ice_chunk", 2], ["item_scrap_metal", 1],
]

const STORY_LINES := [
	["The cargo ship Om Jarwo was on its way home when...", 18],
	["Day 0: Accident", 34],
	["You wake among debris. Your ship is badly damaged.", 18],
	["The Warp Core is down. Without it, no way home.", 16],
	["Oxygen is limited. Gather anything usable.", 16],
	["Build. Survive. Return.", 16],
]

# Jeda sebelum baris pertama ("sadar dari pingsan") + jeda antar baris.
const BASE_DELAY := 0.5
const LINE_GAP := 0.55

var _view := Vector2.ZERO
var _started := false

func setup(board: Board) -> void:
	_view = board.get_viewport_rect().size
	color = Color(0, 0, 0, 0.78)
	# Ukuran eksplisit (jangan andalkan anchor: parent bisa berukuran 0
	# saat setup sehingga fill gelap tidak tampil + klik lolos).
	mouse_filter = Control.MOUSE_FILTER_STOP
	position = Vector2.ZERO
	size = _view
	var y := _view.y * 0.5 - 150.0
	for line in STORY_LINES:
		var label := UIFactory.label(String(line[0]), int(line[1]))
		label.position = Vector2(0, y)
		label.size = Vector2(_view.x, 44)
		label.modulate.a = 0.0
		add_child(label)
		var fade_in := create_tween()
		fade_in.tween_property(label, "modulate:a", 1.0, 0.6).set_delay(BASE_DELAY + LINE_GAP * STORY_LINES.find(line))
		y += 52.0
	var start := UIFactory.button("Start", Vector2(180, 48))
	start.position = Vector2(_view.x * 0.5 - 90.0, y + 20.0)
	start.modulate.a = 0.0
	start.pressed.connect(_on_start)
	add_child(start)
	var fade_btn := create_tween()
	fade_btn.tween_property(start, "modulate:a", 1.0, 0.6).set_delay(BASE_DELAY + LINE_GAP * STORY_LINES.size())

func _on_start() -> void:
	if _started:
		return
	_started = true
	for node in find_children("*", "Button", true, false):
		(node as Button).disabled = true
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 0.0, 0.4)
	fade.tween_callback(queue_free)
	finished.emit(DEFAULT_KIT)
