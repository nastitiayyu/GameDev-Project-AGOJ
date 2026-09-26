class_name GameOverScreen
extends Control

# Layar akhir dedicated (dim + alasan + flavour naratif + breakdown skor
# + Main Lagi). Di-spawn HUD saat sinyal GameState.game_over / victory.

var _reason := ""

func setup(reason: String, victory := false) -> void:
	_reason = reason
	%ReasonLabel.text = reason
	if victory:
		%Title.text = "VICTORY!"
		%Title.add_theme_color_override("font_color", Color(0.45, 1, 0.55))
		%FlavourLabel.text = "The Warp Core hums warmly. The cargo ship Om Jarwo jumps home, carrying %d hard-earned Credits and %d packages delivered right on time. Contract complete — the crew returns as legends." % [
			GameState.total_credits_earned, GameState.total_packages_delivered]
	else:
		%FlavourLabel.text = _lose_flavour(reason)
	%BreakLabel.text = "Days survived: %d\nCredits earned: %d\nPackages delivered: %d" % [
		GameState.day, GameState.total_credits_earned, GameState.total_packages_delivered]
	%ScoreLabel.text = "Final Score: %d" % GameState.score

# Satu kalimat penutup sesuai cara kalah — naratif, bukan teknis.
# (ReasonLabel sudah menjelaskan sisi teknisnya.)
func _lose_flavour(reason: String) -> String:
	var r := reason.to_lower()
	if "monster" in r:
		return "It came silently out of the dark, and left without looking back. The cargo ship Om Jarwo is now just a silent monument adrift."
	if "hull" in r:
		return "The alarms went out one by one. Among the spiralling debris, the Warp Core died too. The dream of home shattered into pieces."
	if "units died" in r or "unit" in r:
		return "No hands left to steer the ship. This vessel is now just an iron coffin drifting aimlessly."
	if "o2" in r or "oxygen" in r:
		return "The last breath felt sweet and cold. The crew fell asleep one by one amid panels still blinking."
	if "starv" in r:
		return "An empty stomach cannot be reasoned with. The hold had long gone silent before the last light died."
	return "Space does not forgive the careless."

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	%RestartButton.pressed.connect(_on_restart)
	%ExitButton.pressed.connect(_on_exit)

func _on_restart() -> void:
	get_tree().paused = false
	GameState.reset()
	Packages.traveling.clear()
	DayCycle._accum = 0.0
	get_tree().reload_current_scene()

func _on_exit() -> void:
	get_tree().paused = false
	get_tree().quit()
