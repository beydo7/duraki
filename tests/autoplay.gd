extends Node
## Spielt automatisch komplette Runs durch (Smoke-Test für alle Szenen).
## Ausführen:
##   godot --headless --path . res://tests/autoplay.tscn

const RUNS := 5

var _bot := SimpleAI.new(RandomNumberGenerator.new(), 0.0)
var _runs_done := 0
var _cooldown := 0


func _ready() -> void:
	Engine.time_scale = 20.0
	# Damit der Szenenwechsel diesen Node nicht mit entlädt:
	_detach.call_deferred()


func _detach() -> void:
	var placeholder := Node.new()
	get_tree().root.add_child(placeholder)
	get_tree().current_scene = placeholder
	Run.start_new_run(1000)


func _process(_delta: float) -> void:
	_cooldown -= 1
	if _cooldown > 0:
		return
	_cooldown = 3
	var scene := get_tree().current_scene
	if scene == null:
		return
	match scene.name:
		"RunMap":
			scene.get_node("%FightButton").pressed.emit()
		"Match":
			var duel: DurakMatch = scene.duel
			if duel.is_over:
				scene.get_node("%ContinueButton").pressed.emit()
			elif duel.current_actor() == DurakMatch.PLAYER:
				_bot.take_turn(duel, DurakMatch.PLAYER)
		"Shop":
			# das erste bezahlbare Angebot kaufen, dann weiter
			for offer in Run.shop_offers:
				if Run.buy(offer):
					break
			scene.get_node("%ContinueButton").pressed.emit()
		"RunEnd":
			_runs_done += 1
			print("Run %d: %s, Etage %d/%d, Gold %d, Relikte %d" % [
				_runs_done, "gewonnen" if Run.won_run else "verloren",
				Run.floor_index, Run.encounters.size(), Run.gold, Run.relics.size()])
			if _runs_done >= RUNS:
				get_tree().quit()
			else:
				Run.start_new_run(1000 + _runs_done)
				_cooldown = 10
