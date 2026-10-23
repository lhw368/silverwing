extends "res://scripts/consumable_inventory.gd"
func _game_ready(game:Node)->bool:
 # Existing thrown explosives keep simulating after the pilot mounts.
 return game.level_id in [2,3] and game.mode=="play" and not game.paused and is_instance_valid(game.player) and game.player.hp>0
func _player_ready(game:Node)->bool:
 return not game.exosuit.active and super._player_ready(game)
