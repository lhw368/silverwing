extends "res://scripts/player.gd"
## Keep the first level's damage and all movement/combat behavior intact.

func damage(amount: int, source_x: float, cause: String) -> bool:
	if game.level_id != 2:
		return super.damage(amount, source_x, cause)
	# Match the base acceptance gate before touching supplies. Paused level-two
	# damage is rejected even if a caller accidentally submits an old hit.
	if not can_take_damage():
		return false
	var absorbed: int = mini(maxi(0, amount), game.inventory.armor)
	game.inventory.armor -= absorbed
	# A zero-damage accepted hit still gives the normal reaction and immunity.
	var accepted: bool = super.damage(maxi(0, amount - absorbed), source_x, cause)
	if absorbed > 0:
		game.float_text(position + Vector2(0, -166), "护甲吸收 %d" % absorbed, Color("75cfff"))
		game.add_sparks(position + Vector2(0, -60), Color("75cfff"), 10)
	return accepted
