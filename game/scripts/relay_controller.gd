class_name StarportRelayController
extends RefCounted
## First-level traversal objectives. This controller owns no actor physics and
## never changes combat stats, inventory, timers, or player position.
## draw_world() must be called from the game's _draw(), with world transform set.

const LevelData = preload("res://scripts/level_data.gd")
const INTERACT_X: float = 54.0
const INTERACT_Y: float = 28.0
const OFF = Color("#e9b46d")
const ON = Color("#69f2d4")
const WHITE = Color("#e3f7ff")
const PALETTES = [Color("#62cfff"), Color("#bdacf9"), Color("#ffa98b")]

var activated_switches: Dictionary = {}
var _auto_station: int = -1
var _auto_waypoint: int = 0
var _auto_route: Array = []

func reset(checkpoint: Variant = 0) -> void:
	activated_switches.clear()
	_reset_navigation()
	var checkpoint_id: int = int(checkpoint)
	for station in LevelData.RELAY_STATIONS:
		var active: Array = []
		if checkpoint_id >= 2 or (checkpoint_id == 1 and int(station.id) in LevelData.CHECKPOINT_RELAY_IDS):
			for terminal in station.switches: active.append(str(terminal.id))
		activated_switches[station.id] = active

func is_switch_active(station_id: int, switch_id: Variant) -> bool:
	return str(switch_id) in activated_switches.get(station_id, [])

func is_station_open(id: int) -> bool:
	for station in LevelData.RELAY_STATIONS:
		if int(station.id) == id:
			for terminal in station.switches:
				if not is_switch_active(id, str(terminal.id)): return false
			return not station.switches.is_empty()
	return false

func right_bound(default_bound: float) -> float:
	# Taking a minimum leaves every preceding combat room's existing bounds intact.
	# A checkpoint reset marks its earlier stations, avoiding a backwards clamp.
	var bound: float = default_bound
	for station in LevelData.RELAY_STATIONS:
		if not is_station_open(int(station.id)):
			bound = minf(bound, float(station.gate_x) - 35.0)
	return bound

func interact(game) -> bool:
	if game.mode != "play" or game.paused: return false
	for station in LevelData.RELAY_STATIONS:
		for terminal in station.switches:
			if not _near_terminal(game, terminal): continue
			if not _station_ready(game, station):
				game.show_status("先清除高处警戒机，再接通电源。" if _guard_for_station(game, int(station.id)) != null else "先清理战区，再接通供电。", 2.2)
				return true
			var id: int = int(station.id)
			var switch_id: String = str(terminal.id)
			if is_switch_active(id, switch_id):
				game.show_status(str(terminal.label) + " · 已接通", 1.6)
				return true
			var active: Array = activated_switches.get(id, [])
			active.append(switch_id)
			activated_switches[id] = active
			game.sfx("checkpoint")
			game.add_sparks(terminal.feet + Vector2(0, -43), ON, 16)
			game.float_text(terminal.feet + Vector2(-35, -100), "已接通", ON)
			var opened: bool = is_station_open(id)
			game.show_status(str(station.name) + (" · 供电恢复，通路开放 →" if opened else " · %d / %d 接通" % [active.size(), station.switches.size()]), 3.0)
			print("RELAY_SWITCH station=%d switch=%s open=%s t=%.2f" % [id, switch_id, str(opened), game.run_time])
			return true
	return false

func near_prompt(game) -> String:
	if game.mode != "play": return ""
	for station in LevelData.RELAY_STATIONS:
		if not _station_ready(game, station): continue
		for terminal in station.switches:
			if _near_terminal(game, terminal) and not is_switch_active(int(station.id), str(terminal.id)):
				return "E  接通 " + str(terminal.label)
	return ""

func hud_hint(game) -> String:
	if game.mode != "play": return ""
	for station in LevelData.RELAY_STATIONS:
		if not _station_route_ready(game, station) or is_station_open(int(station.id)): continue
		if game.player.position.x < float(station.start) - 180.0 or game.player.position.x > float(station.gate_x) + 140.0: continue
		if _guard_for_station(game, int(station.id)) != null:
			return str(station.name) + " · 可绕过守卫，接通两端电源。"
		var prompt: String = near_prompt(game)
		if not prompt.is_empty(): return prompt
		var active: Array = activated_switches.get(station.id, [])
		return "%s · %d / %d  %s" % [station.name, active.size(), station.switches.size(), station.hint]
	return ""

func progress_snapshot() -> Dictionary:
	var result: Array = []
	var completed: int = 0
	var active_count: int = 0
	var total_count: int = 0
	for station in LevelData.RELAY_STATIONS:
		var active: Array = activated_switches.get(station.id, [])
		var opened: bool = is_station_open(int(station.id))
		if opened: completed += 1
		active_count += active.size()
		total_count += station.switches.size()
		result.append({"id": station.id, "name": station.name, "open": opened, "active": active.duplicate(), "total": station.switches.size()})
	return {"completed": completed, "total": LevelData.RELAY_STATIONS.size(), "active_switches": active_count, "total_switches": total_count, "stations": result}

func draw_world(game) -> void:
	for station in LevelData.RELAY_STATIONS:
		if float(station.gate_x) < game.camera_x - 180.0 or float(station.start) > game.camera_x + 1380.0: continue
		var id: int = int(station.id)
		var accent: Color = PALETTES[posmod(id, PALETTES.size())]
		var opened: bool = is_station_open(id)
		_draw_wires(game, station)
		for platform in station.platforms:
			_draw_platform(game, platform, accent)
		_draw_gate(game, station, accent, opened)
		for terminal in station.switches:
			_draw_terminal(game, station, terminal, accent)

func _near_terminal(game, terminal: Dictionary) -> bool:
	var feet: Vector2 = terminal.feet
	return game.player.is_on_floor() and absf(game.player.position.x - feet.x) <= INTERACT_X and absf(game.player.position.y - feet.y) <= INTERACT_Y

func _station_ready(game, _station: Dictionary) -> bool:
	return game.mode == "play" and not game.paused

func _station_route_ready(game, _station: Dictionary) -> bool:
	return game.mode == "play" and not game.paused

func _guard_for_station(game, station_id: int):
	for enemy in game.enemies:
		if not enemy.dead and enemy.get("relay_station") == station_id: return enemy
	return null

func _draw_wires(game, station: Dictionary) -> void:
	var bus_y: float = LevelData.FLOOR + 22.0
	for i in station.switches.size():
		var terminal: Dictionary = station.switches[i]
		var active: bool = is_switch_active(int(station.id), str(terminal.id))
		var tint: Color = Color(ON, 0.65) if active else Color(OFF, 0.30)
		var anchor: Vector2 = terminal.feet + Vector2(16.0, -22.0)
		var row_y: float = bus_y + i * 7.0
		game.draw_polyline(PackedVector2Array([anchor, Vector2(anchor.x + 12, anchor.y), Vector2(anchor.x + 12, row_y), Vector2(station.gate_x, row_y), Vector2(station.gate_x, LevelData.FLOOR - 30.0)]), tint, 2.0, true)

func _draw_platform(game, platform: Rect2, accent: Color) -> void:
	if game.floor_tex:
		game.draw_texture_rect_region(game.floor_tex, platform, Rect2(110, 148, 420, 88), Color("#aec5d6"))
	else:
		game.draw_rect(platform, Color("#203a51"))
	game.draw_rect(Rect2(platform.position, Vector2(platform.size.x, 3)), accent)
	game.draw_line(platform.position + Vector2(0, 4), platform.position + Vector2(0, 12), accent, 2.0)
	game.draw_line(platform.position + Vector2(platform.size.x, 4), platform.position + Vector2(platform.size.x, 12), accent, 2.0)
	# Thin visual suspension struts are not collision objects.
	for fraction in [0.18, 0.82]:
		var x: float = platform.position.x + platform.size.x * fraction
		game.draw_line(Vector2(x, platform.end.y), Vector2(x, LevelData.FLOOR), Color(accent, 0.12), 2.0)

func _draw_gate(game, station: Dictionary, accent: Color, opened: bool) -> void:
	var x: float = station.gate_x
	var top: float = LevelData.FLOOR - 282.0
	var tint: Color = ON if opened else OFF
	game.draw_rect(Rect2(x - 19, top - 15, 38, 15), Color("#173248"))
	game.draw_rect(Rect2(x - 24, LevelData.FLOOR - 20, 48, 20), Color("#173248"))
	game.draw_line(Vector2(x - 16, top - 7), Vector2(x + 16, top - 7), tint, 4.0)
	game.draw_line(Vector2(x - 20, LevelData.FLOOR - 18), Vector2(x + 20, LevelData.FLOOR - 18), tint, 3.0)
	if not opened:
		game.draw_rect(Rect2(x - 12, top, 24, 264), Color(tint, 0.10))
		for i in 5:
			var alpha: float = 0.42 + 0.16 * sin(game.clock_time * 4.0 + i * 0.8)
			game.draw_line(Vector2(x - 8 + i * 4, top), Vector2(x - 8 + i * 4, LevelData.FLOOR - 20), Color(tint, alpha), 1.5)
		for y in range(6):
			var beam_y: float = top + 22.0 + y * 40.0
			game.draw_line(Vector2(x - 10, beam_y), Vector2(x + 10, beam_y + 14), Color(tint, 0.40), 2.0)
	else:
		for i in 3:
			var at: Vector2 = Vector2(x - 18.0 + i * 18.0, LevelData.FLOOR - 60)
			game.draw_polyline(PackedVector2Array([at + Vector2(-5, -8), at + Vector2(3, 0), at + Vector2(-5, 8)]), ON, 2.0, true)
	# Place the service label on the floor fascia, leaving every elevated terminal
	# and landing silhouette clear, including the highest core platform.
	var sign_x: float = x - 330.0
	var sign_y: float = LevelData.FLOOR + 44.0
	game.panel(Rect2(sign_x - 12, sign_y, 350, 43), Color(0.025, 0.065, 0.10, 0.90), Color(accent, 0.65))
	game.text_at(str(station.name), Vector2(sign_x, sign_y + 19), 17, accent)
	game.text_at("ONLINE  /  通路开放 →" if opened else "OFFLINE  /  接通平台上的电源", Vector2(sign_x, sign_y + 36), 13, tint)
	for i in station.switches.size():
		var terminal: Dictionary = station.switches[i]
		var active: bool = is_switch_active(int(station.id), str(terminal.id))
		game.draw_circle(Vector2(x - 8.0 + i * 16.0, top - 34), 4.0, ON if active else OFF)

func _draw_terminal(game, station: Dictionary, terminal: Dictionary, accent: Color) -> void:
	var feet: Vector2 = terminal.feet
	var active: bool = is_switch_active(int(station.id), str(terminal.id))
	var ready: bool = _station_ready(game, station)
	var tint: Color = ON if active else OFF
	var body: Rect2 = Rect2(feet + Vector2(-24, -66), Vector2(48, 66))
	# Reuse a crop of the generated metal environment art rather than adding an
	# unrelated placeholder illustration. The switch and energy effects are native.
	if game.floor_tex:
		game.draw_texture_rect_region(game.floor_tex, body, Rect2(570, 130, 178, 138), Color("#abbfcf"))
	else:
		game.draw_rect(body, Color("#233b51"))
	game.draw_rect(body, Color(accent, 0.80), false, 1.5)
	game.draw_rect(Rect2(feet + Vector2(-18, -58), Vector2(36, 25)), Color("#071b2a"))
	game.draw_rect(Rect2(feet + Vector2(-17, -57), Vector2(34, 23)), Color(tint, 0.16))
	game.draw_rect(Rect2(feet + Vector2(-29, -4), Vector2(58, 4)), accent)
	var center: Vector2 = feet + Vector2(0, -45)
	if active:
		game.draw_polyline(PackedVector2Array([center + Vector2(-9, 0), center + Vector2(-2, 7), center + Vector2(11, -7)]), ON, 3.0, true)
	else:
		game.draw_arc(center, 8, -PI * 0.25, PI * 1.25, 20, tint, 2.0, true)
		game.draw_line(center + Vector2(0, -11), center + Vector2(0, -1), tint, 2.0)
	for i in 3:
		game.draw_rect(Rect2(feet + Vector2(-15 + i * 11, -21), Vector2(8, 5)), tint if active else Color(accent, 0.26))
	game.text_at(str(terminal.label), feet + Vector2(-44, 24), 15, tint)
	if not active and ready and game.mode == "play":
		if _near_terminal(game, terminal):
			game.panel(Rect2(feet + Vector2(-85, -117), Vector2(170, 34)), Color(0.02, 0.075, 0.12, 0.95), tint)
			game.text_at("E  接通电源", feet + Vector2(-64, -94), 19, WHITE)
		else:
			var lift: float = sin(game.clock_time * 3.0) * 3.0
			game.draw_polyline(PackedVector2Array([feet + Vector2(-7, -85 + lift), feet + Vector2(0, -78 + lift), feet + Vector2(7, -85 + lift)]), tint, 2.0, true)

func _reset_navigation() -> void:
	_auto_station = -1
	_auto_waypoint = 0
	_auto_route.clear()

func autoplay_axis(game, _delta: float) -> Variant:
	# QA only: production calls this solely inside its --autoplay driver. The
	# route uses exactly the same axis/jump/interact actions as keyboard input.
	if game.mode != "play" or game.active_zone >= 0:
		return null
	var selected: Dictionary = {}
	for station in LevelData.RELAY_STATIONS:
		if is_station_open(int(station.id)): continue
		if _station_route_ready(game, station) and game.player.position.x >= float(station.start) - 240.0:
			selected = station
		break
	if selected.is_empty():
		_reset_navigation()
		return null
	if _auto_station != int(selected.id):
		_auto_station = int(selected.id)
		_auto_waypoint = 0
		_auto_route = selected.qa_waypoints.duplicate()
	if _station_ready(game, selected):
		for terminal in selected.switches:
			if not is_switch_active(int(selected.id), str(terminal.id)) and _near_terminal(game, terminal):
				game.interact()
	if is_station_open(int(selected.id)):
		_reset_navigation()
		return null
	if _auto_route.is_empty(): return 0.0
	var actor = game.player
	var guard = _guard_for_station(game, int(selected.id))
	if guard != null:
		var guard_dx: float = guard.pos.x - actor.position.x
		if actor.is_on_floor() and absf(guard.pos.y - actor.position.y) < 110.0 and absf(guard_dx) <= 160.0:
			if actor.state in ["idle", "run"]:
				if absf(guard_dx) > 1.0: actor.facing = int(signf(guard_dx))
				actor.begin_action("heavy")
			elif actor.state == "light":
				actor.begin_action("light")
			return 0.0
	var target: Vector2 = _auto_route[_auto_waypoint]
	if actor.is_on_floor() and absf(actor.position.y - target.y) < 5.0 and absf(actor.position.x - target.x) < 24.0:
		_auto_waypoint += 1
		if _auto_waypoint >= _auto_route.size(): _auto_waypoint = 0
		target = _auto_route[_auto_waypoint]
	# Recover a genuine fall by reusing the earliest reachable route step.
	if actor.is_on_floor() and (actor.position.y - target.y > 125.0 or (_auto_waypoint > 0 and actor.position.y >= LevelData.FLOOR - 5.0)):
		for i in _auto_route.size():
			var candidate: Vector2 = _auto_route[i]
			if absf(actor.position.y - candidate.y) < 5.0:
				_auto_waypoint = i
				target = candidate
				break
		if actor.position.y >= LevelData.FLOOR - 5.0:
			_auto_waypoint = 0
			target = _auto_route[0]
	var dx: float = target.x - actor.position.x
	var axis: float = signf(dx) if absf(dx) > 7.0 else 0.0
	if not actor.is_on_floor():
		# Brake over the landing instead of moving past a narrow platform.
		if absf(dx) < absf(actor.velocity.x) * 0.05 + 4.0: axis = 0.0
		return axis
	if actor.position.y - target.y > 6.0:
		var support: Rect2 = _support_at(actor.position)
		if support.size.x > 0.0 and support.size.x < 1000.0:
			var edge: float = support.end.x - 9.0 if dx > 0 else support.position.x + 9.0
			if absf(actor.position.x - edge) > 14.0:
				return signf(edge - actor.position.x)
			actor.begin_action("jump")
		else:
			# Ground entry: jump before the cargo crate while still clear of its
			# solid side. This is the same approach as the existing autoplay.
			var landing: Rect2 = _support_at(target)
			var lip: float = landing.position.x if dx >= 0 else landing.end.x
			if absf(actor.position.x - lip) < 83.0: actor.begin_action("jump")
	elif target.y - actor.position.y > 6.0:
		# A descending waypoint is reached by walking off the current ledge.
		return axis
	return axis

func _support_at(feet: Vector2) -> Rect2:
	for platform in LevelData.OBSTACLES + LevelData.RELAY_PLATFORMS:
		if absf(feet.y - platform.position.y) <= 5.0 and feet.x >= platform.position.x - 4.0 and feet.x <= platform.end.x + 4.0:
			return platform
	return Rect2(-200.0, LevelData.FLOOR, LevelData.WORLD_END + 400.0, 180.0)
