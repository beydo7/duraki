class_name CardSfx
extends Node
## Kartengeräusche: Mischen, Austeilen, Legen, Aufnehmen, Bito.
## Austeil-Sounds werden hintereinander „abgespielt wie beim echten Geben“
## und warten, bis ein vorheriges Aufnehmen/Bito-Geräusch durch ist.

const SOUNDS := {
	&"shuffle": preload("res://assets/audio/card_shuffle.wav"),
	&"deal": preload("res://assets/audio/card_deal.wav"),
	&"place": preload("res://assets/audio/card_place.wav"),
	&"take": preload("res://assets/audio/card_take.wav"),
	&"bito": preload("res://assets/audio/card_bito.wav"),
}
const VOLUME_DB := {
	&"shuffle": -2.0, &"deal": -4.0, &"place": 0.0, &"take": -2.0, &"bito": -4.0,
}
const DEAL_INTERVAL := 0.075
const MAX_DEAL_SOUNDS := 6

var _players := {}
var _queue_until := 0.0 # Zeitpunkt (Sekunden), ab dem wieder ausgeteilt werden darf


func _ready() -> void:
	for key in SOUNDS:
		var p := AudioStreamPlayer.new()
		p.stream = SOUNDS[key]
		p.volume_db = VOLUME_DB.get(key, 0.0)
		p.max_polyphony = 8
		add_child(p)
		_players[key] = p


func play(key: StringName, delay := 0.0, pitch_variation := 0.06) -> void:
	if delay > 0.0:
		# Timer als Kind-Node: wird mit der Szene aufgeräumt, nichts bleibt hängen.
		var timer := Timer.new()
		timer.one_shot = true
		timer.wait_time = delay
		timer.timeout.connect(func() -> void:
			_play_now(key, pitch_variation)
			timer.queue_free())
		add_child(timer)
		timer.start()
		return
	_play_now(key, pitch_variation)


func _play_now(key: StringName, pitch_variation: float) -> void:
	var p: AudioStreamPlayer = _players.get(key)
	if p == null:
		return
	p.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	p.play()


## Mischen. Folgende Austeil-Sounds warten, bis es fertig ist.
func play_shuffle() -> void:
	play(&"shuffle", 0.0, 0.02)
	_block_for(SOUNDS[&"shuffle"].get_length() * 0.8)


## Für jede gezogene Karte ein kurzes „Geben“, nacheinander.
func play_deal(count: int) -> void:
	count = mini(count, MAX_DEAL_SOUNDS)
	if count <= 0:
		return
	var start := maxf(_now(), _queue_until)
	for i in count:
		play(&"deal", start - _now() + i * DEAL_INTERVAL)
	_queue_until = start + count * DEAL_INTERVAL


func play_place() -> void:
	play(&"place")


func play_take() -> void:
	play(&"take", 0.0, 0.04)
	_block_for(SOUNDS[&"take"].get_length() * 0.7)


func play_bito() -> void:
	play(&"bito", 0.0, 0.04)
	_block_for(SOUNDS[&"bito"].get_length() * 0.6)


func _block_for(seconds: float) -> void:
	_queue_until = maxf(_queue_until, _now() + seconds)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
