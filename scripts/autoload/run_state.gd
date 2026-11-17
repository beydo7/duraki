extends Node
## Autoload „Run“: Zustand des aktuellen Roguelike-Runs und Szenenwechsel.

signal changed

const SCENE_MENU := "res://scenes/menu/main_menu.tscn"
const SCENE_MAP := "res://scenes/run/run_map.tscn"
const SCENE_MATCH := "res://scenes/match/match.tscn"
const SCENE_REWARD := "res://scenes/run/reward.tscn"
const SCENE_RUN_END := "res://scenes/run/run_end.tscn"

const OPPONENT_DIR := "res://data/opponents/"
const RELIC_DIR := "res://data/relics/"

const START_LIVES := 3
const BASE_HAND_SIZE := 6
const NORMAL_FIGHTS := 3 # danach folgt der Boss
const GOLD_REWARD_OPTION := 15

var rng := RandomNumberGenerator.new()
var seed_value := 0
var lives := 0
var gold := 0
var floor_index := 0
var encounters: Array[OpponentData] = []
var relics: Array[RelicData] = []
var last_gold_reward := 0
var won_run := false


func start_new_run(p_seed := 0) -> void:
	seed_value = p_seed if p_seed != 0 else randi()
	rng.seed = seed_value
	lives = START_LIVES
	gold = 0
	floor_index = 0
	relics.clear()
	won_run = false
	encounters = _build_encounters()
	changed.emit()
	goto(SCENE_MAP)


func current_opponent() -> OpponentData:
	if floor_index < encounters.size():
		return encounters[floor_index]
	return null


func player_hand_size() -> int:
	var size := BASE_HAND_SIZE
	for r in relics:
		size += r.hand_size_bonus
	return size


## Wird von der Match-Szene aufgerufen, sobald ein Duell vorbei ist.
func on_match_finished(loser: int) -> void:
	match loser:
		DurakMatch.OPPONENT:
			var opponent := current_opponent()
			last_gold_reward = opponent.gold_reward
			for r in relics:
				last_gold_reward += r.bonus_gold_per_win
			gold += last_gold_reward
			floor_index += 1
			if floor_index >= encounters.size():
				_end_run(true)
			else:
				changed.emit()
				goto(SCENE_REWARD)
		DurakMatch.PLAYER:
			lives -= 1
			if lives <= 0:
				_end_run(false)
			else:
				changed.emit()
				goto(SCENE_MAP)
		_:
			goto(SCENE_MAP) # Unentschieden: nochmal gegen denselben Gegner


## Bis zu `count` zufällige Relikte, die der Spieler noch nicht hat.
func get_reward_choices(count := 2) -> Array[RelicData]:
	var pool: Array[RelicData] = []
	for r in _load_all(RELIC_DIR):
		if not relics.any(func(owned: RelicData) -> bool: return owned.id == r.id):
			pool.append(r)
	_shuffle(pool)
	return pool.slice(0, count)


func add_relic(relic: RelicData) -> void:
	relics.append(relic)
	lives += relic.extra_lives
	changed.emit()


func add_gold(amount: int) -> void:
	gold += amount
	changed.emit()


func goto(scene_path: String) -> void:
	get_tree().change_scene_to_file.call_deferred(scene_path)


func _end_run(won: bool) -> void:
	won_run = won
	changed.emit()
	goto(SCENE_RUN_END)


func _build_encounters() -> Array[OpponentData]:
	var normal: Array[OpponentData] = []
	var bosses: Array[OpponentData] = []
	for res in _load_all(OPPONENT_DIR):
		var o := res as OpponentData
		if o.is_boss:
			bosses.append(o)
		else:
			normal.append(o)
	_shuffle(normal)
	var result: Array[OpponentData] = normal.slice(0, NORMAL_FIGHTS)
	# Leichtere Gegner zuerst
	result.sort_custom(func(a: OpponentData, b: OpponentData) -> bool:
		return a.mistake_chance > b.mistake_chance)
	if not bosses.is_empty():
		result.append(bosses[rng.randi_range(0, bosses.size() - 1)])
	return result


## Lädt alle Ressourcen eines Ordners (funktioniert auch in exportierten Builds).
func _load_all(dir: String) -> Array[Resource]:
	var result: Array[Resource] = []
	var files := ResourceLoader.list_directory(dir)
	files.sort()
	for file in files:
		if file.ends_with(".tres") or file.ends_with(".res"):
			result.append(load(dir + file))
	return result


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
