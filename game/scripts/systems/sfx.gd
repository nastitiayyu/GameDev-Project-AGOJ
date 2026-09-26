extends Node

# SFX + musik (Autoload: Sfx).
# - SFX kartu prosedural tanpa file audio: noise kertas yang dilembutin
#   (lowpass 2 tingkat, tanpa nada sine) ala kartu remi ditaruh/digeser.
#   (spawn, stack, unstack, combine, pickup, drop, click).
# - Musik: "menu" = assets/sounds/main menu.mp3, "game" = assets/sounds/game.mp3.

const RATE := 22050

const MUSIC_MENU := "res://assets/sounds/main menu.mp3"
const MUSIC_GAME := "res://assets/sounds/game.mp3"

# Throttle per suara biar spawn massal (world gen / intro kit) tidak spam.
const THROTTLE := {"spawn": 0.09, "drop": 0.05, "pickup": 0.05, "click": 0.05}

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _cache := {}
var _last_play := {}
var _music: AudioStreamPlayer
var _music_mode := ""

func _ready() -> void:
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_build_card_sfx()
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	add_child(_music)
	# Semua Button otomatis bunyi klik saat ditekan (termasuk yang dibuat
	# dinamis: popup event, recipe book, market, intro, game over).
	get_tree().node_added.connect(_on_node_added)
	call_deferred("_auto_music")

# Hook tombol yang baru masuk scene tree.
func _on_node_added(node: Node) -> void:
	var b := node as Button
	if b != null and not b.pressed.is_connected(_on_button_pressed):
		b.pressed.connect(_on_button_pressed)

func _on_button_pressed() -> void:
	play("click")

# Pilih musik otomatis sesuai scene aktif (menu vs game).
func _auto_music() -> void:
	var path := ""
	var scene := get_tree().current_scene
	if scene != null and scene.scene_file_path != "":
		path = scene.scene_file_path
	if "menu" in path.to_lower():
		play_music("menu")
	else:
		play_music("game")

func play_music(mode: String) -> void:
	if _music_mode == mode and _music.playing:
		return
	var path := MUSIC_MENU if mode == "menu" else MUSIC_GAME
	if not ResourceLoader.exists(path):
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	if "loop" in stream:
		stream.set("loop", true)
	_music.stream = stream
	_music_mode = mode
	_music.play()

func stop_music() -> void:
	_music.stop()
	_music_mode = ""

func play(sname: String) -> void:
	if not _cache.has(sname) or _players.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if THROTTLE.has(sname):
		var last: float = float(_last_play.get(sname, -10.0))
		if now - last < float(THROTTLE[sname]):
			return
		_last_play[sname] = now
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _cache[sname]
	p.pitch_scale = randf_range(0.97, 1.04)
	p.play()

func _build_card_sfx() -> void:
	# stack = 1 tepukan kartu yang firm (kartu ditempel ke stack).
	_cache["stack"] = _wav(_pat(0.075, 0.55, 0.45))
	# drop/place = kartu ditaruh di meja.
	_cache["drop"] = _wav(_pat(0.06, 0.5, 0.5))
	# pickup = kartu disentil/diangkat, pendek dan pelan.
	_cache["pickup"] = _wav(_pat(0.045, 0.32, 0.6))
	# click tombol = jentik kecil pelan.
	_cache["click"] = _wav(_pat(0.03, 0.22, 0.55))
	# spawn = geser halus + tepuk pelan (kartu muncul/pop).
	_cache["spawn"] = _wav(_concat([
		_slide(0.09, 0.2, 0.4),
		_pat(0.06, 0.45, 0.5),
	]))
	# unstack = tepuk + geser (stack dibelah / kartu dilepas).
	_cache["unstack"] = _wav(_concat([
		_pat(0.05, 0.42, 0.55),
		_slide(0.07, 0.22, 0.45),
	]))
	# danger = stinger dua nada turun (momen bahaya: serangan monster,
	# stat kritis). Beda keluarga dari bunyi kartu yang netral.
	_cache["danger"] = _wav(_concat([
		_sweep(220.0, 98.0, 0.32, 0.5),
		_silence(0.03),
		_sweep(165.0, 82.0, 0.3, 0.45),
	]))
	# combine = 3 tepukan cepat beruntun ala pegang kartu.
	_cache["combine"] = _wav(_concat([
		_pat(0.045, 0.45, 0.45),
		_silence(0.025),
		_pat(0.045, 0.48, 0.52),
		_silence(0.025),
		_pat(0.06, 0.52, 0.6),
	]))

# Tepukan kartu: noise kertas lowpass 2 tingkat (lembut, tanpa nada sine)
# + attack 3ms + decay cepat + "duk" rendah dari noise yang di-lowpass berat.
# bright 0..1: 0 = empuk/gedebuk, 1 = renyah.
func _pat(dur: float, vol: float, bright: float) -> PackedByteArray:
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var a := lerpf(0.15, 0.6, clampf(bright, 0.0, 1.0))
	var s1 := 0.0
	var s2 := 0.0
	var deep := 0.0
	var attack := maxi(1, int(RATE * 0.003))
	for i in n:
		var raw := randf() * 2.0 - 1.0
		s1 += a * (raw - s1)
		s2 += a * (s1 - s2)
		deep += 0.06 * (raw - deep)
		var f := float(i) / n
		var env := exp(-4.5 * f)
		if i < attack:
			env *= float(i) / attack
		var body := s2 * 0.85 + (raw - s1) * 0.25
		var thump := deep * exp(-12.0 * f) * 0.5
		_put_sample(data, i, (body * env + thump) * vol)
	return data

# Geseran kartu: noise kertas yang sama tapi envelope swell (muncul-hilang),
# tanpa "duk" rendah. Pelan dan halus.
func _slide(dur: float, vol: float, bright: float) -> PackedByteArray:
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var a := lerpf(0.15, 0.6, clampf(bright, 0.0, 1.0))
	var s1 := 0.0
	var s2 := 0.0
	for i in n:
		var raw := randf() * 2.0 - 1.0
		s1 += a * (raw - s1)
		s2 += a * (s1 - s2)
		var f := float(i) / n
		var env := sin(PI * clampf(f, 0.0, 1.0))
		var body := s2 * 0.85 + (raw - s1) * 0.25
		_put_sample(data, i, body * env * vol)
	return data

# Nada meluncur turun + sedikit grit noise (stinger bahaya).
func _sweep(f0: float, f1: float, dur: float, vol: float) -> PackedByteArray:
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	var attack := maxi(1, int(RATE * 0.005))
	for i in n:
		var f := float(i) / n
		phase += TAU * lerpf(f0, f1, f) / RATE
		var env := exp(-3.0 * f)
		if i < attack:
			env *= float(i) / attack
		var grit := (randf() * 2.0 - 1.0) * 0.12 * env
		_put_sample(data, i, (sin(phase) * env + grit) * vol)
	return data

func _silence(dur: float) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(int(RATE * dur) * 2)
	return data  # 16-bit: 0 = hening

func _concat(parts: Array) -> PackedByteArray:
	var data := PackedByteArray()
	for part in parts:
		data.append_array(part)
	return data

# Tulis 1 sampel mono 16-bit little-endian ke buffer.
func _put_sample(data: PackedByteArray, idx: int, s: float) -> void:
	var v := int(clampf(s, -1.0, 1.0) * 32767.0)
	data[idx * 2] = v & 0xFF
	data[idx * 2 + 1] = (v >> 8) & 0xFF

func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream
