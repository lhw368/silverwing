extends RefCounted
## Optional battle supplies. Persistent outcomes are separate from live floor
## items: a checkpoint retry must defeat the same enemy again before an
## unclaimed outcome can appear. Claims roll back together with checkpoint
## resources, while the roll ledger never rolls back or rerolls that enemy.
## The caller saves immediately after on_defeat()/tick() returns true.

const BASE_CHANCE: float = 0.18
const PITY_MISSES: int = 6
const REPAIR_HP: int = 12
const CAPACITOR_SECONDS: float = 2.5
const LOW_HP: int = 35
const GRENADE_CAP: int = 4
const PICKUP_X: float = 52.0
const PICKUP_Y: float = 18.0
const MAX_ENTRIES: int = 4096
const RNG_MODULUS: int = 2147483647
const RNG_MULTIPLIER: int = 48271
const LABELS = {"repair": "维修组件 +12", "capacitor": "技能电容 −2.5秒", "bomb": "爆破弹 +1"}
const TINTS = {"repair": Color("8df0ba"), "capacitor": Color("8ddcff"), "bomb": Color("ffb56a")}

var legacy_entries: int = 0
var seed_value: int = 1
var rng_state: int = 1
var miss_streak: int = 0
var entries: Array[Dictionary] = []
var floor_items: Array[Dictionary] = []
var _by_key: Dictionary = {}
var _defeated_this_world: Dictionary = {}
var _icons: Dictionary = {}
var _dirty: bool = false

func reset_run(run_seed: int = 0) -> void:
	# Keep serialized RNG integers below 2^31; JSON round-trips them exactly.
	# A supplied seed makes the whole sequence reproducible. Fresh runs obtain
	# a seed once, independently of cosmetic/global randf calls afterwards.
	var chosen: int = run_seed if run_seed != 0 else int(Time.get_ticks_usec()) ^ randi()
	seed_value = posmod(chosen - 1, RNG_MODULUS - 1) + 1
	rng_state = seed_value
	miss_streak = 0
	entries.clear()
	legacy_entries = 0
	_by_key.clear()
	clear_world()
	_dirty = true

func clear_world() -> void:
	floor_items.clear()
	_defeated_this_world.clear()

func is_dirty() -> bool:
	return _dirty

func mark_saved() -> void:
	_dirty = false

func consume_dirty() -> bool:
	var result: bool = _dirty
	_dirty = false
	return result

func _active(game) -> bool:
	return game.level_id in [1, 2, 3] and game.mode == "play" and not game.paused and is_instance_valid(game.player) and game.player.hp > 0

func on_defeat(game, enemy, stable_key: String) -> bool:
	# enemy_hit_feedback runs immediately after hp changes, before dead is set.
	if not _active(game) or enemy == null or enemy.hp > 0 or stable_key.is_empty() or stable_key.length() > 240 or _defeated_this_world.has(stable_key):
		return false
	var changed: bool = false
	var entry: Dictionary
	if _by_key.has(stable_key):
		entry = entries[int(_by_key[stable_key])]
		if int(entry.level) != int(game.level_id):
			return false
	else:
		if entries.size() >= MAX_ENTRIES:
			return false
		var low_health: bool = game.player.hp <= LOW_HP
		var kind: String = _roll_outcome(int(game.level_id), low_health)
		entry = {"key": stable_key, "level": int(game.level_id), "low_hp": low_health, "kind": kind, "claimed": false}
		_by_key[stable_key] = entries.size()
		entries.append(entry)
		_dirty = true
		changed = true
	_defeated_this_world[stable_key] = true
	if not entry.claimed and not entry.kind.is_empty():
		var landing: Variant = _landing_point(game, enemy.pos)
		if landing != null:
			floor_items.append({"key": stable_key, "kind": entry.kind, "level": int(game.level_id), "pos": landing})
	return changed

func _advance_rng(state: int) -> int:
	return (state * RNG_MULTIPLIER) % RNG_MODULUS

func _roll_outcome(level: int, low_health: bool) -> String:
	rng_state = _advance_rng(rng_state)
	var chance: float = float(rng_state) / float(RNG_MODULUS)
	rng_state = _advance_rng(rng_state)
	var choice: float = float(rng_state) / float(RNG_MODULUS)
	if chance >= BASE_CHANCE and miss_streak < PITY_MISSES:
		miss_streak += 1
		return ""
	miss_streak = 0
	return _kind_for_roll(level, low_health, choice)

func _kind_for_roll(level: int, low_health: bool, choice: float) -> String:
	# Grenades are already understood by the stage 2/3 controls. Stage 1 has
	# no consumable HUD or usable inventory, so its two weights renormalize.
	var repair_weight: float = 75.0 if low_health else 50.0
	var capacitor_weight: float = 20.0 if low_health else 35.0
	var grenade_weight: float = (5.0 if low_health else 15.0) if level in [2, 3] else 0.0
	var selected: float = choice * (repair_weight + capacitor_weight + grenade_weight)
	if selected < repair_weight:
		return "repair"
	if selected < repair_weight + capacitor_weight:
		return "capacitor"
	return "bomb"

func _landing_point(game, at: Vector2) -> Variant:
	if not at.is_finite():
		return null
	var ray := PhysicsRayQueryParameters2D.create(at + Vector2(0, -4), Vector2(at.x, float(game.FLOOR) + 512.0), 1)
	ray.hit_from_inside = true
	var hit: Dictionary = game.get_world_2d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y > -0.7:
		return null
	return hit.position

func _can_reach(game, item: Dictionary) -> bool:
	var offset: Vector2 = game.player.position - item.pos
	if int(item.level) != int(game.level_id) or absf(offset.x) > PICKUP_X or absf(offset.y) > PICKUP_Y:
		return false
	var space: PhysicsDirectSpaceState2D = game.get_world_2d().direct_space_state
	# Both feet and supply must still rest on geometry on this floor. Merely
	# being nearby in x must never collect through stacked platforms or walls.
	var support := PhysicsRayQueryParameters2D.create(item.pos + Vector2(0, -3), item.pos + Vector2(0, 5), 1)
	var footing: Dictionary = space.intersect_ray(support)
	if footing.is_empty() or footing.normal.y > -0.7 or absf(footing.position.y - item.pos.y) > 2.0:
		return false
	var ray := PhysicsRayQueryParameters2D.create(game.player.position + Vector2(0, -12), item.pos + Vector2(0, -12), 1)
	ray.hit_from_inside = true
	return space.intersect_ray(ray).is_empty()

func tick(dt: float, game) -> bool:
	if not is_finite(dt) or dt <= 0.0 or not _active(game):
		return false
	# Supplies cannot heal the pilot inside armor or extend any suit resource.
	if game.exosuit.active or not game.player.is_on_floor():
		return false
	var changed: bool = false
	for index in range(floor_items.size() - 1, -1, -1):
		var item: Dictionary = floor_items[index]
		var entry: Dictionary = entries[int(_by_key[item.key])]
		if entry.claimed:
			floor_items.remove_at(index)
			continue
		if not _can_reach(game, item) or not _reward_available(game, item.kind):
			continue
		entry.claimed = true
		_dirty = true
		changed = true
		_apply_reward(game, item)
		floor_items.remove_at(index)
	return changed

func _reward_available(game, kind: String) -> bool:
	match kind:
		"repair": return game.player.hp < 100
		"capacitor": return game.player.skill_cd > 0.0
		"bomb": return game.level_id in [2, 3] and int(game.inventory.counts.bomb) < GRENADE_CAP
	return false

func _apply_reward(game, item: Dictionary) -> void:
	var label: String = LABELS[item.kind]
	match item.kind:
		"repair":
			var restored: int = mini(REPAIR_HP, 100 - game.player.hp)
			game.player.hp += restored
			label = "维修组件 +%d" % restored
		"capacitor":
			var restored: float = minf(CAPACITOR_SECONDS, game.player.skill_cd)
			game.player.skill_cd = maxf(0.0, game.player.skill_cd - restored)
			label = "技能冷却 −%.1f秒" % restored
		"bomb": game.inventory.counts.bomb += 1
	game.float_text(item.pos + Vector2(-30, -85), label, TINTS[item.kind])
	game.sfx("ui")

func snapshot() -> Dictionary:
	return {"version": 2, "legacy_entries": legacy_entries, "seed": seed_value, "rng_state": rng_state, "miss_streak": miss_streak, "entries": entries.duplicate(true)}

func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= minimum and value <= maximum

func valid_snapshot(data: Variant) -> bool:
	if not data is Dictionary or not _integer(data.get("version"), 1, 2) or data.size() != (5 if int(data.version)==1 else 6) or not _integer(data.get("seed"), 1, RNG_MODULUS - 1) or not _integer(data.get("rng_state"), 1, RNG_MODULUS - 1) or not _integer(data.get("miss_streak"), 0, PITY_MISSES):
		return false
	if not data.get("entries") is Array or data.entries.size() > MAX_ENTRIES:
		return false
	var raw_legacy: Variant = data.entries.size() if int(data.version)==1 else data.get("legacy_entries")
	if not _integer(raw_legacy,0,data.entries.size()):return false
	var legacy: int = int(raw_legacy)
	var entry_index: int = 0
	var seen: Dictionary = {}
	var state: int = int(data.seed)
	var misses: int = 0
	for entry in data.entries:
		if not entry is Dictionary or entry.size() != 5 or not entry.get("key") is String or entry.key.is_empty() or entry.key.length() > 240 or seen.has(entry.key) or not _integer(entry.get("level"), 1, 3) or not entry.get("low_hp") is bool or not entry.get("claimed") is bool or not entry.get("kind") is String:
			return false
		seen[entry.key] = true
		state = _advance_rng(state)
		var chance: float = float(state) / float(RNG_MODULUS)
		state = _advance_rng(state)
		var expected: String = ""
		var chance_limit: float = .35 if entry_index < legacy else BASE_CHANCE
		var pity_limit: int = 3 if entry_index < legacy else PITY_MISSES
		entry_index += 1
		if chance < chance_limit or misses >= pity_limit:
			misses = 0
			expected = _kind_for_roll(int(entry.level), entry.low_hp, float(state) / float(RNG_MODULUS))
		else:
			misses += 1
		if entry.kind != expected or (expected.is_empty() and entry.claimed):
			return false
	return state == int(data.rng_state) and misses == int(data.miss_streak)

func restore(data: Variant) -> bool:
	# Reject the entire input before touching live state. Replaying the small
	# ledger verifies each outcome plus RNG/pity, including malformed saves.
	if not valid_snapshot(data):
		return false
	legacy_entries = data.entries.size() if int(data.version)==1 else int(data.legacy_entries)
	seed_value = int(data.seed)
	rng_state = int(data.rng_state)
	miss_streak = int(data.miss_streak)
	entries.clear()
	_by_key.clear()
	for value in data.entries:
		var entry: Dictionary = value.duplicate(true)
		entry.level = int(entry.level)
		_by_key[entry.key] = entries.size()
		entries.append(entry)
	clear_world()
	_dirty = false
	return true

func capture_checkpoint() -> Dictionary:
	var claimed: Array[String] = []
	for entry in entries:
		if entry.claimed:
			claimed.append(entry.key)
	claimed.sort()
	var pending: Array[Dictionary] = []
	for item in floor_items:
		if not entries[int(_by_key[item.key])].claimed:
			pending.append({"key": item.key, "level": item.level, "pos": [item.pos.x, item.pos.y]})
	return {"version": 1, "claimed": claimed, "pending": pending}

func valid_checkpoint(data: Variant) -> bool:
	if not data is Dictionary or data.size() != 3 or not _integer(data.get("version"), 1, 1) or not data.get("claimed") is Array or not data.get("pending") is Array:
		return false
	if data.claimed.size() + data.pending.size() > entries.size():
		return false
	var seen: Dictionary = {}
	for key in data.claimed:
		if not key is String or not _by_key.has(key) or seen.has(key) or entries[int(_by_key[key])].kind.is_empty():
			return false
		seen[key] = true
	for item in data.pending:
		if not item is Dictionary or item.size() != 3 or not item.get("key") is String or not _by_key.has(item.key) or seen.has(item.key) or not _integer(item.get("level"), 1, 3) or not item.get("pos") is Array or item.pos.size() != 2:
			return false
		var entry: Dictionary = entries[int(_by_key[item.key])]
		if entry.kind.is_empty() or int(entry.level) != int(item.level):
			return false
		for value in item.pos:
			if not typeof(value) in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or absf(float(value)) > 1000000.0:
				return false
		seen[item.key] = true
	return true

func restore_checkpoint(data: Variant, game = null) -> bool:
	# This is called ONLY together with restoring checkpoint player resources
	# and inventory. An earned grenade cannot persist while its claim resets.
	if not valid_checkpoint(data):
		return false
	var pending: Array[Dictionary] = []
	for item in data.pending:
		var at := Vector2(float(item.pos[0]), float(item.pos[1]))
		if game != null:
			if int(item.level) != int(game.level_id):
				return false
			var surface: Variant = _landing_point(game, at)
			if surface == null or at.distance_to(surface) > 2.0:
				return false
		pending.append({"key": item.key, "kind": entries[int(_by_key[item.key])].kind, "level": int(item.level), "pos": at})
	var claimed: Dictionary = {}
	for key in data.claimed:
		claimed[key] = true
	for entry in entries:
		entry.claimed = claimed.has(entry.key)
	clear_world()
	floor_items = pending
	for item in floor_items:
		_defeated_this_world[item.key] = true
	_dirty = true
	return true

func _item_icon(game, kind: String) -> Texture2D:
	if game.item_textures.has(kind):
		return game.item_textures[kind]
	if not _icons.has(kind):
		var path: String = "res://assets/items/%s.png" % kind
		_icons[kind] = load(path) if ResourceLoader.exists(path) else null
	return _icons[kind]

func draw(game) -> void:
	if game.mode == "menu":
		return
	for item in floor_items:
		if int(item.level) != int(game.level_id) or item.pos.x < game.camera_x - 80 or item.pos.x > game.camera_x + 1360:
			continue
		var point: Vector2 = item.pos + Vector2(0, -25)
		var tint: Color = TINTS[item.kind]
		game.draw_arc(point, 24.0, 0.0, TAU, 24, Color(tint, 0.35), 1.5, true)
		var icon: Texture2D = _item_icon(game, item.kind)
		if icon:
			game.draw_texture_rect(icon, Rect2(point - Vector2(20, 20), Vector2(40, 40)), false)
		game.text_at(LABELS[item.kind], item.pos + Vector2(-57, -54), 14, tint)
