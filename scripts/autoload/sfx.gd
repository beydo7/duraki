extends Node
## Autoload „Sfx“: kurze Soundeffekte über den Bus „SFX“ abspielen.
##   Sfx.play(&"card_hover")                     einfach abspielen
##   Sfx.play(&"card_hover", 1.1, -2.0)          Tonhöhe, Lautstärke zusätzlich (dB)
##   var p := Sfx.play(&"intro"); p.stop()       gespielten Sound wieder stoppen
## Die Dateien liegen in assets/sfx/ (erzeugt mit tools/generate_sfx.py).
## Grundlautstärke jedes Sounds steht in VOLUME – hier zentral nachregeln.

const SOUNDS := {
	&"intro": preload("res://assets/sfx/intro.wav"),
	&"card_hover": preload("res://assets/sfx/card_hover.wav"),
	&"card_select": preload("res://assets/sfx/card_select.wav"),
	&"lighter": preload("res://assets/sfx/lighter.wav"),
	&"inhale": preload("res://assets/sfx/inhale.wav"),
	&"exhale": preload("res://assets/sfx/exhale.wav"),
	&"gulp": preload("res://assets/sfx/gulp.wav"),
	&"candle_flicker": preload("res://assets/sfx/candle_flicker.wav"),
	&"clink": preload("res://assets/sfx/clink.wav"),
	&"bottle_knock": preload("res://assets/sfx/bottle_knock.wav"),
	&"pour": preload("res://assets/sfx/pour.wav"),
	&"index_hover": preload("res://assets/sfx/index_hover.wav"),
	&"ui_click": preload("res://assets/sfx/ui_click.wav"),
}
## Grundlautstärke in dB (0 = volle Lautstärke der Datei)
const VOLUME := {
	&"intro": -2.0,
	&"card_hover": -21.0,
	&"card_select": -13.0,
	&"lighter": -17.0,
	&"inhale": -22.0,
	&"exhale": -20.0,
	&"gulp": -15.0,
	&"candle_flicker": -24.0,
	&"clink": -20.0,
	&"bottle_knock": -17.0,
	&"pour": -15.0,
	&"index_hover": -24.0,
	&"ui_click": -17.0,
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
	p.volume_db = float(VOLUME.get(sound, 0.0)) + volume_db
	p.play()
	return p


## Sanft ausblenden (z. B. Intro übersprungen).
func fade_out(p: AudioStreamPlayer, time := 0.25) -> void:
	if p == null or not p.playing:
		return
	var tw := p.create_tween()
	tw.tween_property(p, "volume_db", -60.0, time)
	tw.tween_callback(p.stop)
