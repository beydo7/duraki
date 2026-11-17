extends Control
## Belohnung nach einem Sieg: ein Relikt wählen oder Gold nehmen.


func _ready() -> void:
	%GoldLabel.text = "+%d Gold (jetzt %d)" % [Run.last_gold_reward, Run.gold]

	for relic in Run.get_reward_choices():
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(220, 120)
		btn.text = "%s\n\n%s" % [relic.display_name, relic.description]
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.pressed.connect(func() -> void:
			Run.add_relic(relic)
			Run.goto(Run.SCENE_MAP))
		%Choices.add_child(btn)

	var gold_btn := Button.new()
	gold_btn.custom_minimum_size = Vector2(220, 120)
	gold_btn.text = "Säckchen Gold\n\n+%d Gold" % Run.GOLD_REWARD_OPTION
	gold_btn.pressed.connect(func() -> void:
		Run.add_gold(Run.GOLD_REWARD_OPTION)
		Run.goto(Run.SCENE_MAP))
	%Choices.add_child(gold_btn)
