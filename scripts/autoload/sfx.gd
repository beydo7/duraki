extends Node
## Autoload „Sfx“: kurze Soundeffekte über den Bus „SFX“ abspielen.
##   Sfx.play(&"card_hover")                     einfach abspielen
##   Sfx.play(&"card_hover", 1.1, -4.0)          Tonhöhe, Lautstärke (dB)
##   var p := Sfx.play(&"intro"); p.stop()       gespielten Sound wieder stoppen
## Die Dateien liegen in assets/sfx/ (erzeugt mit tools/generate_sfx.py).

const SOUNDS := {
	&"intro": preload("res://assets/sfx/intro.wav"),
	&"card_hover": preload("res://assets/sfx/card_hover.wav"),
	&"card_select": preload("res://assets/sfx/card_select.wav"),
	&"lighter": preload("res://assets/sfx/lighter.wav"),
	&"inhale": preload("res://assets/sfx/inhale.wav"),
	&"exhale": preload("res://assets/sfx/exhale.wav"),
	&"gulp": preload("res://assets/sfx/gulp.wav"),
	&"candle_dim": preload("res://assets/sfx/candle_dim.wav"),
	&"clink": preload("res://assets/sfx/clink.wav"),
}
const POOL_SIZE := 10

var _pool: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_pool.append(p)


func play(sound: StringName, pitch := 1.0, volume_db := 0.0) -> AudioStreamPlayer:
	if not SOUNDS.has(sound) or DisplayServer.get_name() == "headless":
		return null
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stop()
	p.stream = SOUNDS[sound]
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.play()
	return p


## Sanft ausblenden (z. B. Intro übersprungen).
func fade_out(p: AudioStreamPlayer, time := 0.25) -> void:
	if p == null or not p.playing:
		return
	var tw := p.create_tween()
	tw.tween_property(p, "volume_db", -40.0, time)
	tw.tween_callback(p.stop)
