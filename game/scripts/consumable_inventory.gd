extends RefCounted
## Optional level-two supplies. Only tick() advances their simulation.

const CAPS = {"bomb": 4, "armor": 2, "repair": 3}
const LABELS = {"bomb": "爆破弹", "armor": "护甲模块", "repair": "维修包"}
const TINTS = {"bomb": Color("ffb56a"), "armor": Color("75cfff"), "repair": Color("8df0ba")}
const USE_COOLDOWN: float = 0.35
const BOMB_FUSE: float = 0.65
const BOMB_DAMAGE: int = 55
const BOMB_RADIUS: float = 135.0
const BOMB_GRAVITY: float = 1200.0
const BOMB_BODY_RADIUS: float = 9.0

var counts: Dictionary = {"bomb": 0, "armor": 0, "repair": 0}
var armor: int = 0
var collected: Dictionary = {}
var cooldown: float = 0.0
var bombs: Array[Dictionary] = []
var blasts: Array[Dictionary] = []
var _next_serial: int = -2
var _icons: Dictionary = {}

func reset() -> void:
	release_bombs()
	counts = {"bomb": 0, "armor": 0, "repair": 0}
	armor = 0
	collected.clear()
	cooldown = 0.0

func _game_ready(game: Node) -> bool:
	return game.level_id == 2 and game.mode == "play" and not game.paused and is_instance_valid(game.player) and game.player.hp > 0

func _player_ready(game: Node) -> bool:
	return _game_ready(game) and game.player.state in ["idle", "run"] and game.player.is_on_floor()

func use_item(kind: String, game: Node) -> bool:
	if not CAPS.has(kind) or not _player_ready(game) or cooldown > 0.0 or counts[kind] <= 0:
		return false
	if kind == "armor" and armor > 0:
		game.show_status("护甲仍在生效", 1.4)
		return false
	if kind == "repair" and game.player.hp >= 100:
		game.show_status("耐久已满", 1.4)
		return false
	match kind:
		"bomb":
			_spawn_bomb(game)
			game.sfx("shoot")
		"armor":
			armor = 30
			game.float_text(game.player.position + Vector2(0, -140), "护甲 +30", TINTS.armor)
			game.add_sparks(game.player.position + Vector2(0, -55), TINTS.armor, 12)
			game.sfx("checkpoint")
		"repair":
			var restored: int = mini(35, 100 - game.player.hp)
			game.player.hp += restored
			game.float_text(game.player.position + Vector2(0, -140), "+%d" % restored, TINTS.repair)
			game.add_sparks(game.player.position + Vector2(0, -55), TINTS.repair, 12)
			game.sfx("checkpoint")
	counts[kind] -= 1
	cooldown = USE_COOLDOWN
	return true

func try_pickup(entry: Dictionary, game: Node) -> bool:
	if not _player_ready(game) or not _valid_pickup(entry):
		return false
	var kind: String = entry.kind
	if collected.has(entry.id) or counts[kind] >= CAPS[kind]:
		return false
	var offset: Vector2 = game.player.position - entry.pos
	if absf(offset.x) > 62.0 or absf(offset.y) > 72.0:
		return false
	var gained: int = mini(entry.count, CAPS[kind] - counts[kind])
	counts[kind] += gained
	collected[entry.id] = true
	game.float_text(entry.pos + Vector2(0, -95), "%s +%d" % [LABELS[kind], gained], TINTS[kind])
	game.sfx("ui")
	return true

func _valid_pickup(entry: Dictionary) -> bool:
	return typeof(entry.get("id")) == TYPE_STRING and not entry.id.is_empty() and typeof(entry.get("kind")) == TYPE_STRING and CAPS.has(entry.kind) and typeof(entry.get("count")) == TYPE_INT and entry.count > 0 and typeof(entry.get("pos")) == TYPE_VECTOR2 and entry.pos.is_finite()

func _spawn_bomb(game: Node) -> void:
	var body := CharacterBody2D.new()
	body.name = "SupplyBomb_%d" % absi(_next_serial)
	body.collision_layer = 0
	body.collision_mask = 1
	body.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = BOMB_BODY_RADIUS
	shape.shape = circle
	body.add_child(shape)
	game.add_child(body)
	body.position = game.player.position + Vector2(game.player.facing * 30.0, -58.0)
	body.velocity = Vector2(game.player.facing * 390.0, -330.0)
	bombs.append({"body": body, "fuse": BOMB_FUSE, "serial": _next_serial, "rotation": 0.0})
	_next_serial -= 1

func tick(dt: float, game: Node) -> void:
	if not _game_ready(game) or dt <= 0.0 or not is_finite(dt):
		return
	cooldown = maxf(0.0, cooldown - dt)
	for index in range(blasts.size() - 1, -1, -1):
		blasts[index].life -= dt
		if blasts[index].life <= 0.0:
			blasts.remove_at(index)
	for index in range(bombs.size() - 1, -1, -1):
		var bomb: Dictionary = bombs[index]
		var body: CharacterBody2D = bomb.body
		if not is_instance_valid(body):
			bombs.remove_at(index)
			continue
		# Sweep a real circle against world geometry, including thin walls.
		# Small integration steps also preserve the ballistic arc on slow frames.
		var remaining: float = minf(dt, bomb.fuse)
		while remaining > 0.000001:
			var step: float = minf(remaining, 1.0 / 120.0)
			body.velocity.y += BOMB_GRAVITY * step
			var collision: KinematicCollision2D = body.move_and_collide(body.velocity * step)
			if collision:
				body.velocity = body.velocity.bounce(collision.get_normal()) * 0.58
				if collision.get_normal().y < -0.7 and absf(body.velocity.y) < 22.0:
					body.velocity.y = 0.0
			remaining -= step
		bomb.rotation += dt * 8.0
		bomb.fuse -= dt
		if bomb.fuse <= 0.000001:
			var point: Vector2 = body.position
			var serial: int = bomb.serial
			_release_body(body)
			bombs.remove_at(index)
			blasts.append({"pos": point, "life": 0.28})
			game.damage_from_bomb(point, BOMB_RADIUS, BOMB_DAMAGE, serial)
			game.sfx("explode")
			game.add_sparks(point, TINTS.bomb, 26)

func _release_body(body: CharacterBody2D) -> void:
	if is_instance_valid(body):
		body.collision_mask = 0
		body.collision_layer = 0
		body.queue_free()

func release_bombs() -> void:
	for bomb in bombs:
		_release_body(bomb.body)
	bombs.clear()
	blasts.clear()

func snapshot() -> Dictionary:
	var ids: Array = collected.keys()
	ids.sort()
	return {"counts": counts.duplicate(true), "armor": armor, "collected": ids}

func restore(data: Dictionary) -> bool:
	# Validate everything before replacing live state or freeing projectiles.
	if data.size() != 3 or typeof(data.get("counts")) != TYPE_DICTIONARY or not _valid_integer(data.get("armor"), 30) or typeof(data.get("collected")) != TYPE_ARRAY:
		return false
	if data.counts.size() != CAPS.size():
		return false
	var restored_counts: Dictionary = {}
	for kind in CAPS:
		if not _valid_integer(data.counts.get(kind), CAPS[kind]):
			return false
		restored_counts[kind] = int(data.counts[kind])
	var restored_ids: Dictionary = {}
	for id in data.collected:
		if typeof(id) != TYPE_STRING or id.is_empty() or restored_ids.has(id):
			return false
		restored_ids[id] = true
	release_bombs()
	counts = restored_counts
	armor = int(data.armor)
	collected = restored_ids
	cooldown = 0.0
	return true

func _valid_integer(value: Variant, maximum: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value)) and value >= 0 and value <= maximum and float(value) == floorf(float(value))

func item_icon(kind: String) -> Texture2D:
	if not _icons.has(kind):
		var path: String = "res://assets/items/%s.png" % kind
		_icons[kind] = load(path) if ResourceLoader.exists(path) else null
	return _icons[kind]

func draw_pickup(entry: Dictionary, game: Node) -> void:
	if game.level_id not in [2, 3] or not _valid_pickup(entry) or collected.has(entry.id):
		return
	var point: Vector2 = entry.pos + Vector2(0, -28)
	var tint: Color = TINTS[entry.kind]
	game.draw_arc(point, 26.0, 0.0, TAU, 24, Color(tint, 0.28), 2.0, true)
	var icon: Texture2D = item_icon(entry.kind)
	if icon:
		game.draw_texture_rect(icon, Rect2(point - Vector2(23, 23), Vector2(46, 46)), false)
	else:
		game.draw_circle(point, 13.0, tint)

func draw_world(game: Node) -> void:
	if game.level_id not in [2, 3]:
		return
	for bomb in bombs:
		if not is_instance_valid(bomb.body):
			continue
		var point: Vector2 = bomb.body.position
		var icon: Texture2D = item_icon("bomb")
		if icon:
			game.draw_texture_rect(icon, Rect2(point - Vector2(16, 16), Vector2(32, 32)), false)
		else:
			game.draw_circle(point, BOMB_BODY_RADIUS, TINTS.bomb)
		game.draw_arc(point, 14.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(bomb.fuse / BOMB_FUSE, 0.0, 1.0), 20, Color("fff0b5"), 2.0, true)
	if not game.effects_enabled:
		return
	for blast in blasts:
		var alpha: float = clampf(blast.life / 0.28, 0.0, 1.0)
		var radius: float = BOMB_RADIUS * (1.0 - alpha * 0.75)
		game.draw_arc(blast.pos, radius, 0.0, TAU, 48, Color(1.0, 0.71, 0.35, alpha), 5.0 * alpha + 1.0, true)

func draw_hud(game: Node) -> void:
	if game.level_id not in [2, 3]:
		return
	game.draw_rect(Rect2(24, 602, 700, 55), Color(0.015, 0.04, 0.075, 0.93))
	var index: int = 0
	for kind in ["bomb", "armor", "repair"]:
		var x: float = 35.0 + index * 229.0
		var tint: Color = TINTS[kind]
		game.draw_rect(Rect2(x, 615, 24, 25), Color(tint, 0.12))
		game.text_at(str(index + 1), Vector2(x + 6, 634), 17, tint)
		var icon: Texture2D = item_icon(kind)
		if icon:
			game.draw_texture_rect(icon, Rect2(x + 29, 608, 42, 42), false)
		game.text_at("%s %d/%d" % [LABELS[kind], counts[kind], CAPS[kind]], Vector2(x + 77, 626), 17, Color("e8f6ff"))
		var detail: String = "投掷 · 范围爆破" if kind == "bomb" else ("吸收剩余 %d" % armor if kind == "armor" else "回复 35 耐久")
		game.text_at(detail, Vector2(x + 77, 646), 13, tint)
		index += 1
