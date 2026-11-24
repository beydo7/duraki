extends Node
## Autoload „Music“: Hintergrundmusik über den Bus „Music“ (Lautstärke in den Optionen).
## Läuft über Szenenwechsel hinweg weiter und wiederholt sich nahtlos.
##   Music.play_main()     Hauptthema starten (weich eingeblendet), läuft schon → nichts tun
##   Music.stop(1.5)       ausblenden
## Datei: assets/music/main_theme.ogg (erzeugt mit tools/generate_music.py).

const MAIN_THEME := "res://assets/music/main_theme.ogg"
const FADE_IN := 2.5

var _player: AudioStreamPlayer
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.bus = &"Music"
	add_child(_player)


func play_main() -> void:
	if _player.playing or DisplayServer.get_name() == "headless":
		return
	if not ResourceLoader.exists(MAIN_THEME):
		return
	var stream := load(MAIN_THEME) as AudioStream
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_player.stream = stream
	_player.volume_db = -40.0
	_player.play()
	_fade_to(0.0, FADE_IN)


func stop(time := 1.5) -> void:
	if not _player.playing:
		return
	_fade_to(-40.0, time)
	_tween.tween_callback(_player.stop)


func _fade_to(db: float, time: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_player, "volume_db", db, time).set_trans(Tween.TRANS_SINE)
