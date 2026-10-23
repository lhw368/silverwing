class_name SilverwingPlayer
extends CharacterBody2D

const SPEED = 290.0
const GRAVITY = 1750.0
const JUMP_SPEED = -650.0
const DODGE_DURATION: float = 0.30
const DODGE_INVULN_DURATION: float = 0.10
const DODGE_INVULN_START: float = (DODGE_DURATION - DODGE_INVULN_DURATION) * 0.5
const DODGE_INVULN_END: float = DODGE_INVULN_START + DODGE_INVULN_DURATION
# Prevent floating-point accumulation from adding a frame at a boundary.
const DODGE_TIME_EPSILON: float = 0.000000001
var hp: int = 100
var hitstop: float = 0.0
var facing: int = 1
var state: String = "idle"
var elapsed: float = 0.0
var invuln: float = 0.0
var dodge_cd: float = 0.0
var skill_cd: float = 0.0
var combo: int = 0
var combo_buffer: bool = false
var hit_done: bool = false
var coyote: float = 0.0
var jump_buffer: float = 0.0
var attack_serial: int = 0
var game: Node
var last_cause: String = ""

func setup(owner_game: Node) -> void:
	game = owner_game
	var shape = CollisionShape2D.new()
	var capsule = CapsuleShape2D.new()
	capsule.radius = 22.0
	capsule.height = 96.0
	shape.shape = capsule
	shape.position.y = -48.0
	add_child(shape)
	collision_layer = 2
	collision_mask = 1

func reset_at(point: Vector2) -> void:
	position = point
	velocity = Vector2.ZERO
	hp = 100
	hitstop = 0.0
	state = "idle"
	elapsed = 0.0
	invuln = 1.0
	dodge_cd = 0.0
	skill_cd = 0.0
	combo = 0
	combo_buffer = false
	hit_done = false
	jump_buffer = 0.0
	facing = 1

func begin_action(action: String) -> bool:
	if hp <= 0 or game.mode != "play":
		return false
	if action == "jump":
		jump_buffer = 0.12
		return true
	if action == "light" and state == "light":
		if elapsed >= 0.08 and combo < 3:
			combo_buffer = true
		return false
	var free: bool = state in ["idle", "run", "air"]
	var cancel: bool = state == "light" and elapsed >= 0.25
	if action == "dodge":
		if dodge_cd > 0.0 or not (free or cancel):
			return false
		hitstop = 0.0
		state = "dodge"
		elapsed = 0.0
		dodge_cd = 0.8
		game.sfx("dodge")
		return true
	if not free or not is_on_floor():
		return false
	if action == "skill" and skill_cd > 0.0:
		return false
	if action in ["light", "heavy", "skill"]:
		state = action
		elapsed = 0.0
		hit_done = false
		combo = 1
		combo_buffer = false
		attack_serial += 1
		if action == "skill":
			skill_cd = 8.0
		return true
	return false

func tick(delta: float, axis: float) -> void:
	invuln = maxf(0.0, invuln - delta)
	dodge_cd = maxf(0.0, dodge_cd - delta)
	skill_cd = maxf(0.0, skill_cd - delta)
	jump_buffer = maxf(0.0, jump_buffer - delta)
	if hitstop > 0.0:
		hitstop = maxf(0.0,hitstop-delta)
		velocity.x = 0.0
		velocity.y += GRAVITY*delta
		move_and_slide()
		position.x = clampf(position.x,game.left_bound(),game.right_bound())
		return
	elapsed += delta
	if is_on_floor():
		coyote = 0.10
	else:
		coyote = maxf(0.0, coyote - delta)
	velocity.y += GRAVITY * delta
	if hp <= 0:
		state = "dead"
		velocity.x = move_toward(velocity.x, 0.0, 1600.0 * delta)
	elif state == "hurt":
		velocity.x = move_toward(velocity.x, 0.0, 850.0 * delta)
		if elapsed >= 0.25:
			state = "idle"
	elif state == "dodge":
		velocity.x = facing * 800.0
		if elapsed + DODGE_TIME_EPSILON >= DODGE_DURATION:
			state = "idle"
	elif state in ["light", "heavy", "skill"]:
		velocity.x = move_toward(velocity.x, 0.0, 2200.0 * delta)
		var startup: float = 0.10 if state == "light" else (0.30 if state == "heavy" else 0.24)
		var active_end: float = startup + (0.12 if state == "light" else 0.14)
		if elapsed >= startup and (elapsed < active_end or not hit_done):
			var first_active_tick: bool = not hit_done
			hit_done = true
			game.player_strike(state, combo, attack_serial, first_active_tick)
			if state != "skill":
				velocity.x = facing * (75.0 if state == "light" else 50.0)
		var duration: float = (0.36 if combo < 3 else 0.44) if state == "light" else (0.80 if state == "heavy" else 0.70)
		if elapsed >= duration:
			if state == "light" and combo_buffer and combo < 3:
				combo += 1
				elapsed = 0.0
				combo_buffer = false
				hit_done = false
				attack_serial += 1
			else:
				state = "idle"
	else:
		if absf(axis) > 0.1:
			facing = 1 if axis > 0.0 else -1
		velocity.x = move_toward(velocity.x, axis * SPEED, 2400.0 * delta)
		state = "run" if absf(velocity.x) > 10.0 else "idle"
		if jump_buffer > 0.0 and coyote > 0.0:
			velocity.y = JUMP_SPEED
			elapsed = 0.0
			jump_buffer = 0.0
			coyote = 0.0
			game.sfx("jump")
		if not is_on_floor():
			state = "air"
	move_and_slide()
	position.x = clampf(position.x, game.left_bound(), game.right_bound())

func is_dodge_invulnerable() -> bool:
	# The middle 100 ms of the action, [0.100, 0.200), share its clock:
	# pause and local hitstop freeze the window together with the dodge.
	# Keep this separate from spawn, hurt-recovery and skill invulnerability.
	var action_time: float = elapsed + DODGE_TIME_EPSILON
	return state == "dodge" and action_time >= DODGE_INVULN_START and action_time < DODGE_INVULN_END

func is_invulnerable() -> bool:
	return invuln > 0.0 or is_dodge_invulnerable()

func can_take_damage() -> bool:
	# Armor and exosuit callers must check this before consuming durability.
	return hp > 0 and game.mode == "play" and not game.paused and not is_invulnerable()

func damage(amount: int, source_x: float, cause: String) -> bool:
	if not can_take_damage():
		return false
	hp = maxi(0, hp - amount)
	hitstop = 0.0
	invuln = 0.7
	state = "hurt" if hp > 0 else "dead"
	elapsed = 0.0
	velocity.x = 240.0 * (1.0 if position.x >= source_x else -1.0)
	combo_buffer = false
	last_cause = cause
	game.hits_taken += 1
	if game.autoplay: print("AUTO_HIT ",cause," player=",position," action=",state)
	game.kick_shake(4.0)
	game.sfx("hurt")
	game.float_text(position + Vector2(0, -135), "-%d" % amount, Color("ff987c"))
	if hp <= 0:
		game.on_player_death()
	return true
