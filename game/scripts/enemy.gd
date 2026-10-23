class_name StarportEnemy
extends RefCounted

const BOSS_WAVE_SPEED: float = 350.0
const BOSS_WAVE_RADIUS: float = 23.0
const BOSS_WAVE_JUMP_LEAD: float = 0.35
const BOSS_RECOVERY: float = 1.6
const BOSS_APPROACH_DELAY: float = 0.5

var kind: String = "melee"
var relay_station: int = -1
var ground_y: float = 574.0
var hitstop: float = 0.0
var visual_clock: float = 0.0
var state_elapsed: float = 0.0
var visual_state: String = ""
var actual_motion_x: float = 0.0
var physics_body: CharacterBody2D = null
var pos: Vector2 = Vector2.ZERO
var home: float = 0.0
var hp: int = 36
var max_hp: int = 36
var shield: int = 2
var facing: int = -1
var state: String = "approach"
var timer: float = 0.0
var cycle: int = 0
var move_name: String = ""
var dead: bool = false
var flash: float = 0.0
var last_serial: int = -1
var hit_serials: Dictionary = {}
var attack_applied: bool = false
var phase_two: bool = false
var locked_x: float = 0.0
var death_timer: float = 0.0
var knock_time: float = 0.0
var knock_speed: float = 0.0

func _init(type: String = "melee", point: Vector2 = Vector2.ZERO) -> void:
	kind = type
	pos = point
	ground_y = point.y
	home = point.x
	max_hp = {"melee":36,"shield":80,"drone":24,"boss":650}.get(kind,36)
	hp = max_hp
	shield = 2 if kind == "shield" else 0
	if kind == "drone":
		pos.y -= 28.0
	timer = 0.5

func hit(damage: int, heavy: bool, from_x: float, serial: int, game: Node, ranged: bool = false, contact_point: Variant = null) -> bool:
	if dead or hit_serials.has(serial):
		return false
	last_serial = serial
	hit_serials[serial] = true
	var frontal: bool = (from_x - pos.x) * facing > 0.0
	var broke_shield: bool = false
	var blocked: bool = kind=="shield" and shield>0 and frontal
	if kind == "shield" and shield > 0 and frontal:
		if heavy:
			shield -= 1
			game.float_text(pos + Vector2(0,-160), "破甲 %d/2" % (2-shield), Color("ffe4a4"))
			if shield == 0:
				broke_shield = true
				state = "stun"
				timer = 1.7
		else:
			damage = maxi(1, int(damage * 0.2))
	hp = maxi(0, hp - damage)
	flash = 0.12
	game.enemy_hit_feedback(self,damage,heavy,from_x,serial,ranged,blocked,broke_shield,contact_point)
	if kind != "boss" and (kind != "shield" or shield <= 0 or not frontal):
		knock_time = 0.12
		knock_speed = (100.0 if not heavy else 200.0) * (1.0 if pos.x >= from_x else -1.0)
		if kind != "shield" or shield <= 0:
			state = "stun"
			timer = 1.7 if broke_shield else (0.28 if not heavy else 0.55)
	if hp <= 0:
		dead = true
		state = "dead"
		game.kills += 1
		game.sfx("explode")
		game.add_sparks(pos + Vector2(0,-55), Color("ffb972"), 24)
	return true

func attach_physics(game: Node) -> void:
	if is_instance_valid(physics_body): return
	physics_body = CharacterBody2D.new()
	physics_body.name = "EnemyBody_"+kind
	physics_body.collision_layer = 4
	physics_body.collision_mask = 1
	var shape = CollisionShape2D.new()
	var capsule = CapsuleShape2D.new()
	capsule.radius = 48.0 if kind=="boss" else 20.0
	capsule.height = 196.0 if kind=="boss" else (56.0 if kind=="drone" else 100.0)
	shape.shape = capsule
	shape.position.y = -capsule.height*0.5
	physics_body.add_child(shape)
	game.add_child(physics_body)
	physics_body.position = pos

func release_physics() -> void:
	if is_instance_valid(physics_body): physics_body.queue_free()
	physics_body = null

func _resolve_physics(displacement: Vector2, dt: float) -> void:
	if not is_instance_valid(physics_body):
		pos += displacement
		return
	physics_body.velocity.x = displacement.x/maxf(dt,0.000001)
	if kind=="drone": physics_body.velocity.y = 0.0
	else: physics_body.velocity.y += 1750.0*dt
	physics_body.move_and_slide()
	pos = physics_body.position

func tick(dt: float, game: Node) -> void:
	if visual_state != state:
		visual_state = state
		state_elapsed = 0.0
	if hitstop > 0.0:
		hitstop = maxf(0.0,hitstop-dt)
		flash = maxf(0.0,flash-dt)
		_resolve_physics(Vector2.ZERO,dt)
		return
	visual_clock += dt
	state_elapsed += dt
	var previous = pos
	_tick_logic(dt,game)
	var displacement = pos-previous
	pos = previous
	_resolve_physics(displacement,dt)
	actual_motion_x = (pos.x-previous.x)/maxf(dt,0.000001)
	if visual_state != state:
		visual_state = state
		state_elapsed = 0.0
	if dead and death_timer>0.45: release_physics()

func _tick_logic(dt: float, game: Node) -> void:
	if knock_time > 0.0:
		pos.x += knock_speed * minf(dt,knock_time)
		pos.x = clampf(pos.x,game.left_bound()+45.0,game.right_bound()-45.0)
		knock_time = maxf(0.0,knock_time-dt)
	flash = maxf(0, flash-dt)
	if dead:
		death_timer += dt
		return
	timer -= dt
	var p: SilverwingPlayer = game.player
	var dist: float = p.position.x - pos.x
	if state == "stun":
		if timer <= 0:
			state = "approach"
			timer = 0.3
		return
	if kind == "boss":
		boss_tick(dt, game)
		return
	if state == "windup":
		if timer <= 0:
			state = "attack"
			timer = 0.20
			if kind == "drone":
				game.projectiles.append({"pos":pos+Vector2(facing*34,-48),"vx":facing*440.0,"life":3.0,"friendly":false,"damage":10,"radius":8.0})
				game.sfx("shoot")
			elif absf(dist) < 114.0 and absf(p.position.y-pos.y) < 70 and dist * facing >= -20:
				p.damage(12 if kind == "shield" else 8, pos.x, "盾兵撞击" if kind == "shield" else "机兵挥击")
			game.add_sparks(pos + Vector2(facing*70,-55), Color("ffab6b"), 5)
		return
	if state == "attack":
		if timer <= 0:
			state = "recover"
			timer = 0.95
		return
	if state == "recover":
		if timer <= 0:
			state = "approach"
		return
	facing = 1 if dist > 0 else -1
	var reach: float = 420.0 if kind == "drone" else 85.0
	if absf(dist) > reach:
		pos.x += facing * (80.0 if kind == "shield" else 105.0) * dt
	elif absf(dist) < 220 and kind == "drone":
		pos.x -= facing * 45.0 * dt
	pos.x = clampf(pos.x, game.left_bound()+45, game.right_bound()-45)
	if absf(dist) <= reach+5 and timer <= 0 and game.active_attackers() < 2 and absf(pos.x-game.camera_x-640) < 640:
		state = "windup"
		timer = 0.65 if kind == "drone" else 0.5
		locked_x = p.position.x
		game.sfx("warning")

func boss_wave_hint(game: Node) -> Dictionary:
	# A normal jump lasts about 0.74 s. Prompt against the wave's leading
	# collision edge, not its launch: travel time varies with player distance.
	# This pure query also works during recovery and stays frozen when paused.
	var hint := {"stage":"", "text":"", "impact_in":INF}
	if kind != "boss" or dead or not is_instance_valid(game.player):
		return hint
	var impact_in: float = INF
	var travelling: bool = false
	var player_speed: float = game.player.velocity.x
	for projectile in game.projectiles:
		if not projectile.get("boss_wave",false) or projectile.get("boss_id",-1) != get_instance_id() or float(projectile.life) <= 0.0:
			continue
		var speed: float = absf(float(projectile.vx))
		if speed <= 0.0:
			continue
		var direction: float = signf(float(projectile.vx))
		var ahead: float = (game.player.position.x-float(projectile.pos.x))*direction
		var hit_width: float = 27.0+float(projectile.radius)
		if ahead < -hit_width:
			continue # The trailing edge has already passed this player.
		var closing_speed: float = speed-player_speed*direction
		if closing_speed <= 0.0 and ahead > hit_width:
			continue
		travelling = true
		impact_in = minf(impact_in,maxf(0.0,(ahead-hit_width)/maxf(closing_speed,0.001)))
	if not travelling and state == "windup" and move_name == "wave":
		var until_release: float = maxf(0.0,timer)
		var release_delta: float = game.player.position.x+player_speed*until_release-pos.x
		var closing_speed: float = BOSS_WAVE_SPEED-player_speed*signf(release_delta)
		if closing_speed > 0.0:
			impact_in = until_release+maxf(0.0,(absf(release_delta)-27.0-BOSS_WAVE_RADIUS)/closing_speed)
	if is_inf(impact_in):
		return hint
	hint.impact_in = impact_in
	if impact_in <= BOSS_WAVE_JUMP_LEAD:
		hint.stage = "jump"
		hint.text = "现在起跳"
	else:
		hint.stage = "travel" if travelling else "charge"
		hint.text = "震波接近 · 等待波近" if travelling else "震波蓄力 · 等待波近"
	return hint

func boss_tick(dt: float, game: Node) -> void:
	var p: SilverwingPlayer = game.player
	var dist: float = p.position.x-pos.x
	phase_two = hp <= max_hp/2
	if state == "windup":
		if timer <= 0:
			state = "attack"
			attack_applied = false
			timer = 0.6 if move_name == "charge" else 0.24
			if move_name == "wave":
				for direction in [-1,1]:
					game.projectiles.append({"pos":Vector2(pos.x,game.FLOOR-18),"vx":direction*BOSS_WAVE_SPEED,"life":3.5,"friendly":false,"damage":20,"radius":BOSS_WAVE_RADIUS,"boss_wave":true,"boss_id":get_instance_id()})
				game.kick_shake(6.0)
				game.sfx("slam")
		return
	if state == "attack":
		if move_name == "charge":
			pos.x += facing * 700.0 * dt
			pos.x = clampf(pos.x,game.left_bound()+90,game.right_bound()-90)
			if absf(dist)<110 and absf(p.position.y-pos.y)<80:
				p.damage(22,pos.x,"首领冲撞")
		elif move_name == "sweep" and not attack_applied:
			attack_applied = true
			if absf(dist)<220 and dist*facing>=-20 and absf(p.position.y-pos.y)<120:
				p.damage(18,pos.x,"首领横扫")
			game.sfx("slam")
		if timer <= 0:
			state = "recover"
			timer = BOSS_RECOVERY
		return
	if state == "recover":
		if timer <= 0:
			state = "approach"
			timer = BOSS_APPROACH_DELAY
		return
	facing = 1 if dist > 0 else -1
	if absf(dist)>185:
		pos.x += facing*95.0*dt
	if timer <= 0:
		var sequence: Array = ["sweep","charge","wave"] if not phase_two else ["wave","sweep","charge","sweep"]
		move_name = sequence[cycle%sequence.size()]
		cycle += 1
		state = "windup"
		timer = 0.85 if move_name != "wave" else 0.95
		locked_x = p.position.x
		game.sfx("warning")
