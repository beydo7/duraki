extends SceneTree
## Simuliert viele Duelle und gibt die Punkteverteilung aus (zum Einstellen der Ziele).
##   godot --headless --path . -s res://tests/score_sim.gd

func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for mistake in [0.45, 0.3, 0.15, 0.0]:
		var scores: Array[int] = []
		var wins := 0
		for game in 400:
			var duel := DurakMatch.new()
			var tracker := ScoreTracker.new(999999)
			tracker.attach(duel)
			duel.start(rng, 6, 7 if mistake == 0.0 else 6)
			var ais := [SimpleAI.new(rng, 0.1), SimpleAI.new(rng, mistake)]
			var steps := 0
			while not duel.is_over and steps < 3000:
				var a := duel.current_actor()
				ais[a].take_turn(duel, a)
				steps += 1
			scores.append(tracker.total)
			if duel.loser == DurakMatch.OPPONENT:
				wins += 1
		scores.sort()
		var q := func(p: float) -> int: return scores[int(p * (scores.size() - 1))]
		print("Fehler %.2f: Durak-Siege %d%%  P20 %d  P40 %d  Median %d  P70 %d  P90 %d" % [
			mistake, wins * 100 / 400, q.call(0.2), q.call(0.4), q.call(0.5), q.call(0.7), q.call(0.9)])
	quit()
