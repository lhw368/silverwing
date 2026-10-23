extends Node

# Deterministic rule tests using the actual player, enemy, scene, and save code.
# Fixtures deliberately position combatants and clear waves. This is NOT an
# unassisted end-to-end playthrough; visual and full-run QA are separate.
const EnemyScript = preload("res://scripts/enemy.gd")
const LevelData = preload("res://scripts/level_data.gd")
var game: Node
var results: Array = []
var failures: int = 0
var started_msec: int = 0

func check(id: String, passed: bool, detail: String = "") -> void:
	results.append({"id":id,"passed":passed,"detail":detail})
	if not passed:
		failures += 1
	print(("PASS " if passed else "FAIL ") + id + (" | " + detail if not detail.is_empty() else ""))

func settle_player(point: Vector2 = Vector2(300, 572)) -> void:
	game.start_run(false)
	game.relays.reset(2) # Isolated combat fixture; full relay progression has separate checks.
	game.player.reset_at(point)
	for i in 5:
		await get_tree().physics_frame
		game.player.tick(1.0/60.0, 0.0)
	game.player.invuln = 0.0
	game.clear_combat()
	game.freeze = 0.0

func write_save(path: String, value: String) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(value)
		file.close()

func remove_test_saves() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(game.SAVE_PATH + suffix):
			DirAccess.remove_absolute(game.SAVE_PATH + suffix)

func reset_save_fields() -> void:
	game.saved_checkpoint = 0
	game.best_time = 0.0
	game.volume = 0.6
	game.shake_amount = 0.6
	game.save_warning = ""

func run(owner_game: Node) -> void:
	game = owner_game
	started_msec = Time.get_ticks_msec()
	game.set_physics_process(false)
	var isolated = OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-test-data")
	check("isolated_save_directory", isolated, OS.get_user_data_dir())
	if not isolated:
		finish()
		return
	remove_test_saves()
	await test_ground_and_attacks()
	await test_combo()
	await test_attack_interrupts_and_spacing()
	await test_dodge_hurt_death()
	await test_pause()
	test_enemy_hit_and_shield()
	test_boss_telegraphs()
	test_projectile_collisions()
	test_attacker_limit()
	await test_zone_gates()
	await test_checkpoint_retry()
	test_save_recovery()
	await test_death_priority_at_gate()
	remove_test_saves()
	finish()

func test_ground_and_attacks() -> void:
	await settle_player()
	check("ground_fixture_settles", game.player.is_on_floor(), str(game.player.position))
	var enemy = EnemyScript.new("melee", Vector2(410, game.FLOOR))
	game.enemies = [enemy]
	check("ground_light_starts", game.player.begin_action("light"))
	var serial = game.player.attack_serial
	game.player.tick(0.05, 0)
	check("light_startup_no_early_hit", enemy.hp == 36)
	game.player.tick(0.051, 0)
	check("light_active_frame_hits", enemy.hp == 26, "hp=" + str(enemy.hp))
	for i in 3: game.player.tick(0.08, 0)
	check("one_swing_damages_once", enemy.hp == 26 and game.player.attack_serial == serial)
	await settle_player(Vector2(300, 350))
	check("air_fixture_off_floor", not game.player.is_on_floor())
	for action in ["light", "heavy", "skill"]:
		check("air_rejects_"+action, not game.player.begin_action(action))
	check("air_allows_dodge", game.player.begin_action("dodge"))
	await settle_player()
	check("ground_heavy_starts", game.player.begin_action("heavy"))
	game.player.tick(0.9, 0)
	check("ground_skill_starts", game.player.begin_action("skill"))
	game.player.tick(0.25, 0)
	check("skill_creates_projectile", game.projectiles.size() == 1 and game.projectiles[0].friendly)
	game.player.tick(0.5, 0)
	check("skill_cooldown_blocks_repeat", not game.player.begin_action("skill") and game.player.skill_cd > 7.0)

func test_combo() -> void:
	await settle_player()
	game.player.begin_action("light")
	var first_serial = game.player.attack_serial
	game.player.elapsed = 0.07
	game.player.begin_action("light")
	check("combo_rejects_early_buffer", not game.player.combo_buffer and game.player.combo == 1)
	game.player.elapsed = 0.08
	game.player.begin_action("light")
	check("combo_accepts_window_buffer", game.player.combo_buffer)
	game.player.tick(0.33, 0)
	check("combo_advances_second", game.player.combo == 2 and game.player.attack_serial == first_serial+1)
	game.player.elapsed = 0.20
	game.player.begin_action("light")
	game.player.tick(0.21, 0)
	check("combo_advances_third", game.player.combo == 3 and game.player.attack_serial == first_serial+2)
	game.player.elapsed = 0.24
	game.player.begin_action("light")
	check("combo_caps_three", not game.player.combo_buffer and game.player.combo == 3)
	game.player.tick(0.25, 0)
	check("combo_third_recovers", game.player.state == "idle" and game.player.combo == 3)
	game.player.begin_action("light")
	check("combo_new_chain_resets", game.player.combo == 1)
	game.player.elapsed = 0.24
	check("dodge_cannot_cancel_early_light", not game.player.begin_action("dodge"))
	game.player.elapsed = 0.25
	check("dodge_cancels_recovery_light", game.player.begin_action("dodge"))


func test_attack_interrupts_and_spacing() -> void:
	await settle_player()
	var original_hitstop = game.hitstop_enabled
	game.hitstop_enabled = false # Feedback timing covered at real physics cadence by feel-regression.gd.
	var front = EnemyScript.new("boss",Vector2(410,game.FLOOR))
	var behind = EnemyScript.new("boss",Vector2(70,game.FLOOR))
	var far = EnemyScript.new("boss",Vector2(650,game.FLOOR))
	game.enemies = [front,behind,far]
	game.player.begin_action("light")
	game.player.tick(0.11,0)
	check("light_hitbox_facing_and_range", front.hp == 640 and behind.hp == 650 and far.hp == 650)
	game.player.tick(0.14,0)
	game.player.begin_action("light")
	game.player.tick(0.16,0)
	game.player.tick(0.11,0)
	check("actual_combo_second_hit_damage", front.hp == 630)
	game.player.tick(0.14,0)
	game.player.begin_action("light")
	game.player.tick(0.16,0)
	game.player.tick(0.11,0)
	check("actual_combo_finisher_damage", front.hp == 612 and game.player.combo == 3)
	game.hitstop_enabled = original_hitstop
	await settle_player()
	front = EnemyScript.new("boss",Vector2(410,game.FLOOR))
	game.enemies = [front]
	game.player.begin_action("heavy")
	game.player.tick(0.15,0)
	game.player.damage(8,200,"test interrupt")
	game.player.tick(0.30,0)
	check("hurt_interrupts_attack_before_active_frame", front.hp == 650 and game.player.state == "idle")

func test_dodge_hurt_death() -> void:
	await settle_player()
	check("dodge_starts", game.player.begin_action("dodge"))
	check("dodge_start_is_vulnerable", game.player.can_take_damage())
	game.player.tick(0.10, 0)
	check("dodge_iframe_midpoint", not game.player.damage(8, 0, "test") and game.player.hp == 100)
	game.player.tick(0.10, 0)
	check("dodge_iframe_ends_at_020", game.player.damage(8, 0, "test") and game.player.hp == 92)
	game.player.tick(0.26, 0)
	check("dodge_cooldown_blocks_repeat", not game.player.begin_action("dodge") and game.player.dodge_cd > 0)
	check("hurt_immunity_outlasts_stun", not game.player.damage(8, 0, "test") and game.player.state == "idle")
	game.player.tick(0.45, 0)
	check("hurt_immunity_expires", game.player.damage(8, 0, "test") and game.player.hp == 84)
	game.player.tick(0.26, 0)
	check("dodge_cooldown_recovers", game.player.begin_action("dodge"))
	game.player.invuln = 0
	game.player.hp = 8
	game.player.combo_buffer = true
	check("lethal_hit_sets_death", game.player.damage(8, 0, "test lethal") and game.player.state == "dead" and game.mode == "dead")
	for action in ["jump", "light", "heavy", "dodge", "skill"]:
		check("dead_rejects_"+action, not game.player.begin_action(action))
	var enemy = EnemyScript.new("melee", game.player.position+Vector2(50,0))
	game.enemies = [enemy]
	game.player_strike("heavy", 1, game.player.attack_serial+1)
	game.player.tick(0.5, 1.0)
	check("dead_priority_cannot_attack", enemy.hp == 36 and game.player.state == "dead" and not game.player.combo_buffer)

func test_pause() -> void:
	await settle_player()
	game.player.dodge_cd = 0.6
	game.player.skill_cd = 6.0
	game.player.invuln = 0.4
	var enemy = EnemyScript.new("melee", Vector2(400,game.FLOOR))
	enemy.state = "windup"
	enemy.timer = 0.3
	game.enemies = [enemy]
	game.projectiles = [{"pos":Vector2(700,game.FLOOR-40),"vx":-300.0,"life":2.0,"friendly":false,"damage":10,"radius":8.0}]
	var position_before = game.player.position
	var elapsed_before = game.player.elapsed
	var time_before = game.run_time
	var clock_before = game.clock_time
	game.paused = true
	game.test_mode = false
	game._physics_process(1.0)
	game.test_mode = true
	check("pause_freezes_simulation", game.player.position == position_before and game.player.elapsed == elapsed_before and game.run_time == time_before and enemy.timer == 0.3 and game.projectiles[0].life == 2.0)
	check("pause_freezes_cooldowns", is_equal_approx(game.player.dodge_cd,0.6) and is_equal_approx(game.player.skill_cd,6.0) and is_equal_approx(game.player.invuln,0.4))
	check("pause_freezes_animation_clock", game.clock_time == clock_before, "clock delta=" + str(game.clock_time-clock_before))
	var event = InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_J
	event.physical_keycode = KEY_J
	game._unhandled_input(event)
	check("pause_blocks_combat_input", game.player.state == "idle")
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	game._unhandled_input(event)
	check("pause_escape_resumes", not game.paused)

func test_enemy_hit_and_shield() -> void:
	game.start_run(false)
	var enemy = EnemyScript.new("boss", Vector2(500,game.FLOOR))
	enemy.hit(10, false, 400, 101, game)
	var first_hp = enemy.hp
	check("same_serial_rejected", not enemy.hit(10,false,400,101,game) and enemy.hp == first_hp)
	enemy.hit(10,false,400,102,game)
	var second_hp = enemy.hp
	check("same_serial_rejected_after_interleaving", not enemy.hit(10,false,400,101,game) and enemy.hp == second_hp, "hp="+str(enemy.hp)+"; expected="+str(second_hp))
	var shield = EnemyScript.new("shield", Vector2(500,game.FLOOR))
	shield.facing = -1
	shield.hit(10,false,400,201,game)
	check("shield_frontal_light_reduced", shield.hp == 78 and shield.shield == 2)
	shield.hit(28,true,400,202,game)
	check("shield_first_heavy_one_armor", shield.shield == 1 and shield.hp == 50)
	shield.hit(28,true,400,203,game)
	check("shield_second_heavy_breaks", shield.shield == 0 and shield.state == "stun" and shield.timer >= 1.7 and shield.hp == 22)
	var rear = EnemyScript.new("shield", Vector2(500,game.FLOOR))
	rear.facing = -1
	rear.hit(10,false,600,211,game)
	check("shield_back_full_damage", rear.hp == 70 and rear.shield == 2)
	rear.hit(28,true,600,212,game)
	check("shield_back_heavy_bypasses_armor", rear.hp == 42 and rear.shield == 2)
	var melee = EnemyScript.new("melee", Vector2(500,game.FLOOR))
	var kills_before = game.kills
	melee.hit(40,false,400,301,game)
	melee.hit(40,false,400,302,game)
	check("enemy_death_counts_once", melee.dead and melee.state == "dead" and game.kills == kills_before+1)

func test_boss_telegraphs() -> void:
	game.start_run(false)
	game.completed_zones = range(game.zones.size()-1)
	game.active_zone = game.zones.size()-1
	game.relays.reset(2) # Isolated boss telegraph fixture.
	var boss_room_x: float = game.zones[-1].left+350.0
	game.player.position = Vector2(boss_room_x,game.FLOOR)
	game.player.invuln = 0
	var boss = EnemyScript.new("boss", Vector2(boss_room_x+200.0,game.FLOOR))
	game.enemies = [boss]
	var observed: Array = []
	for expected_move in ["sweep","charge","wave"]:
		game.player.hp = 100
		game.player.invuln = 0
		game.player.position = Vector2(boss_room_x,game.FLOOR)
		boss.pos = Vector2(boss_room_x+80.0,game.FLOOR)
		game.projectiles.clear()
		boss.state = "approach"
		boss.timer = 0.0
		boss.tick(0.001,game)
		observed.append(boss.move_name)
		var windup = boss.timer
		check("boss_"+expected_move+"_telegraph", boss.state == "windup" and boss.move_name == expected_move and windup >= 0.85)
		var hp_before = game.player.hp
		var projectile_count = game.projectiles.size()
		boss.tick(windup-0.01,game)
		check("boss_"+expected_move+"_no_early_damage", boss.state == "windup" and game.player.hp == hp_before and game.projectiles.size() == projectile_count)
		boss.tick(0.011,game)
		check("boss_"+expected_move+"_attack_follows_warning", boss.state == "attack")
		if expected_move == "wave":
			check("boss_wave_emits_two_directions", game.projectiles.size() == projectile_count+2 and game.projectiles[-1].vx * game.projectiles[-2].vx < 0)
			game.update_effects(0.2)
			check("boss_wave_hits_grounded_player", game.player.hp == 80)
		else:
			boss.tick(0.01,game)
			check("boss_"+expected_move+"_active_hit", game.player.hp == (82 if expected_move == "sweep" else 78))
		boss.tick(0.61,game)
		check("boss_"+expected_move+"_recovery_window", boss.state == "recover" and boss.timer >= 1.0)
	check("boss_three_distinct_moves", observed == ["sweep","charge","wave"])
	boss.hp = boss.max_hp/2
	boss.state = "approach"
	boss.timer = 0
	boss.tick(0.01,game)
	check("boss_second_phase_at_half_health", boss.phase_two and boss.state == "windup")


func test_projectile_collisions() -> void:
	game.start_run(false)
	game.player.position = Vector2(800,game.FLOOR)
	game.player.invuln = 0
	var drone = EnemyScript.new("drone",Vector2(880,game.FLOOR))
	drone.facing = -1
	drone.state = "windup"
	drone.timer = 0
	game.enemies = [drone]
	drone.tick(0.01,game)
	check("drone_attack_emits_projectile", game.projectiles.size() == 1)
	game.update_effects(0.10)
	check("drone_shot_hits_standing_body", game.player.hp == 90, "hp="+str(game.player.hp))
	game.clear_combat()
	game.player.hp = 100
	game.player.invuln = 0
	game.player.position.y = game.FLOOR-120
	game.projectiles = [{"pos":Vector2(800,game.FLOOR-18),"vx":0.0,"life":1.0,"friendly":false,"damage":20,"radius":23.0}]
	game.update_effects(0.01)
	check("jumped_player_clears_ground_wave", game.player.hp == 100)
	game.clear_combat()
	game.player.position.y = game.FLOOR
	var enemy = EnemyScript.new("boss",Vector2(800,game.FLOOR))
	game.enemies = [enemy]
	game.projectiles = [{"pos":Vector2(800,game.FLOOR-60),"vx":0.0,"life":1.0,"friendly":true,"damage":24,"radius":36.0,"serial":401}]
	game.update_effects(0.01)
	game.update_effects(0.01)
	check("skill_projectile_damages_target_once", enemy.hp == 626)
	enemy.hit(10,false,700,402,game)
	game.update_effects(0.01)
	check("skill_interleaved_melee_does_not_rehit", enemy.hp == 616)

func test_attacker_limit() -> void:
	game.start_run(false)
	game.player.position = Vector2(800,game.FLOOR)
	game.player.invuln = 1000
	game.camera_x = 250
	for i in 6:
		var enemy = EnemyScript.new("melee",Vector2(775+i*8,game.FLOOR))
		enemy.timer = 0
		game.enemies.append(enemy)
	var highest = 0
	for frame in 600:
		for enemy in game.enemies:
			enemy.tick(1.0/60.0,game)
			highest = maxi(highest,game.active_attackers())
	check("enemy_attacker_cap_two", highest == 2, "maximum="+str(highest)+" across 600 simulated enemy ticks")

func test_zone_gates() -> void:
	await settle_player()
	game.relays.reset(0)
	for zone_id in game.zones.size():
		game.player.position = Vector2(game.zones[zone_id].start+1,game.FLOOR)
		game.update_zones()
		check("zone_%d_gate_activates"%zone_id, game.active_zone == zone_id and game.wave_index == 0 and game.alive_count()>0)
		check("zone_%d_bounds_locked"%zone_id, game.left_bound() == game.zones[zone_id].left+25 and game.right_bound() == game.zones[zone_id].right-25)
		game.player.position.x = game.right_bound()+100
		game.player.tick(0.001,0)
		check("zone_%d_player_clamped"%zone_id, game.player.position.x <= game.right_bound())
		var wave_count = game.zones[zone_id].waves.size()
		for wave in wave_count:
			var current_wave = game.wave_index
			game.update_zones()
			check("zone_%d_wave_%d_live_blocks_gate"%[zone_id,wave], game.wave_index == current_wave and game.active_zone == zone_id)
			# Fixture kill: validates gate/wave logic, not combat ability.
			for enemy in game.enemies:
				enemy.dead = true
				enemy.hp = 0
			game.update_zones()
			if wave < wave_count-1:
				check("zone_%d_next_wave_stays_locked"%zone_id, game.active_zone == zone_id and game.wave_index == wave+1 and game.alive_count()>0)
		check("zone_%d_completion_recorded"%zone_id, zone_id in game.completed_zones)
		if zone_id < game.zones.size()-1:
			check("zone_%d_gate_releases"%zone_id, game.active_zone == -1 and game.right_bound() == game.relays.right_bound(game.WORLD_END-35))
			await complete_ready_relays(zone_id)
	check("boss_completion_wins", game.mode == "win" and game.saved_checkpoint == 0)

func complete_ready_relays(zone_id: int) -> void:
	for station in LevelData.RELAY_STATIONS:
		if int(station.after_zone) != zone_id: continue
		for terminal in station.switches:
			# Grounded terminal fixture uses the real interact contract. Physical
			# climbing and gate collision are exercised by the level-flow suite.
			game.player.reset_at(terminal.feet-Vector2(0,2))
			for _i in 6:
				await get_tree().physics_frame
				game.player.tick(1.0/60.0,0.0)
			game.interact()
			game.update_relay_guards()
			for guard in game.enemies:
				if not guard.dead and guard.relay_station==station.id:
					# Fixture clear isolates gate logic; actual guard combat is in flow/autoplay.
					guard.hit(guard.hp,false,game.player.position.x,90000+int(station.id),game)
		check("relay_%d_guard_spawned_once" % station.id, game.relay_guard_spawned.has(station.id))
		check("relay_%d_after_room_opens" % station.id, game.relays.is_station_open(station.id))

func test_checkpoint_retry() -> void:
	await settle_player()
	game.completed_zones = LevelData.CHECKPOINT_COMPLETED_ZONES.duplicate()
	game.relays.reset(1)
	game.player.position = Vector2(LevelData.NPC_X,game.FLOOR)
	game.player.hp = 20
	game.player.skill_cd = 7
	game.interact()
	check("checkpoint_repairs_and_saves", game.checkpoint == 1 and game.saved_checkpoint == 1 and game.player.hp == 100 and game.player.skill_cd == 0 and FileAccess.file_exists(game.SAVE_PATH))
	# v0.3 checkpoint now precedes the first post-repair combat room, not the boss.
	var next_room: int = LevelData.CHECKPOINT_COMPLETED_ZONES.size()
	var first_wave: Array = game.zones[next_room].waves[0]
	game.player.position.x = game.zones[next_room].start+1.0
	game.update_zones()
	check("checkpoint_next_zone_enters", game.active_zone == next_room and game.alive_count() == first_wave.size())
	game.enemies[0].hp = 1
	game.projectiles.append({"pos":Vector2(LevelData.CHECKPOINT_X,500),"life":5})
	game.player.invuln = 0
	game.player.damage(100,game.player.position.x+100,"test retry")
	game.retry_checkpoint()
	check("retry_restores_checkpoint", game.mode == "play" and game.player.hp == 100 and is_equal_approx(game.player.position.x,float(LevelData.CHECKPOINT_X)) and game.retries == 1)
	check("retry_clears_current_room", game.active_zone == -1 and game.enemies.is_empty() and game.projectiles.is_empty() and game.completed_zones == LevelData.CHECKPOINT_COMPLETED_ZONES)
	game.player.position.x = game.zones[next_room].start+1.0
	game.update_zones()
	var pristine_wave: bool = game.enemies.size() == first_wave.size()
	for enemy in game.enemies:
		pristine_wave = pristine_wave and enemy.hp == enemy.max_hp and not enemy.dead
	check("retry_rebuilds_current_zone", game.active_zone == next_room and game.wave_index == 0 and pristine_wave)
	game.start_run(false)
	game.player.invuln = 0
	game.player.damage(100,400,"test no checkpoint")
	game.retry_checkpoint()
	check("retry_without_checkpoint_restarts_entry", game.checkpoint == 0 and is_equal_approx(game.player.position.x,210.0) and game.completed_zones.is_empty())
	game.saved_checkpoint = 1
	game.start_run(true)
	check("resume_uses_saved_checkpoint", game.checkpoint == 1 and game.completed_zones == LevelData.CHECKPOINT_COMPLETED_ZONES and is_equal_approx(game.player.position.x,float(LevelData.CHECKPOINT_X)))
	game.player.position.x = game.zones[next_room].start+1.0
	game.update_zones()
	check("resume_reenters_next_zone", game.active_zone == next_room and game.alive_count() == first_wave.size())

func test_save_recovery() -> void:
	remove_test_saves()
	reset_save_fields()
	game.saved_checkpoint = 1
	game.best_time = 123.5
	game.volume = 0.4
	game.shake_amount = 0.2
	game.save_game()
	check("save_atomic_primary_written", FileAccess.file_exists(game.SAVE_PATH) and not FileAccess.file_exists(game.SAVE_PATH+".tmp"))
	reset_save_fields()
	game.load_save()
	check("save_round_trip", game.saved_checkpoint == 1 and is_equal_approx(game.best_time,123.5) and is_equal_approx(game.volume,0.4) and is_equal_approx(game.shake_amount,0.2), "loaded checkpoint="+str(game.saved_checkpoint)+"; warning="+game.save_warning+"; raw="+FileAccess.get_file_as_string(game.SAVE_PATH))
	game.start_run(true)
	check("disk_save_resumes_checkpoint", game.checkpoint == 1 and game.completed_zones == LevelData.CHECKPOINT_COMPLETED_ZONES and is_equal_approx(game.player.position.x,float(LevelData.CHECKPOINT_X)))
	game.save_game()
	check("save_backup_created", FileAccess.file_exists(game.SAVE_PATH+".bak"))
	write_save(game.SAVE_PATH,"{corrupt invalid json")
	reset_save_fields()
	game.load_save()
	check("corrupt_primary_uses_backup", game.saved_checkpoint == 1 and is_equal_approx(game.best_time,123.5) and not game.save_warning.is_empty())
	write_save(game.SAVE_PATH,JSON.stringify({"version":0,"checkpoint":1,"best_time":99,"volume":1,"shake":1}))
	reset_save_fields()
	game.load_save()
	check("old_version_uses_backup", game.saved_checkpoint == 1 and is_equal_approx(game.best_time,123.5) and not game.save_warning.is_empty())
	DirAccess.remove_absolute(game.SAVE_PATH+".bak")
	reset_save_fields()
	game.load_save()
	check("old_version_without_backup_defaults", game.saved_checkpoint == 0 and game.best_time == 0 and is_equal_approx(game.volume,0.6) and not game.save_warning.is_empty())
	write_save(game.SAVE_PATH,"{corrupt again")
	reset_save_fields()
	game.load_save()
	check("corrupt_without_backup_defaults", game.saved_checkpoint == 0 and game.best_time == 0 and not game.save_warning.is_empty())
	write_save(game.SAVE_PATH,JSON.stringify({"version":1,"checkpoint":1,"best_time":-10,"volume":3,"shake":-1}))
	reset_save_fields()
	game.load_save()
	check("save_clamps_numeric_ranges", game.saved_checkpoint == 1 and game.best_time == 0 and game.volume == 1 and game.shake_amount == 0)
	for invalid in [null,[],{"version":true,"checkpoint":1,"volume":0.5,"shake":0.5,"best_time":1},{"version":"1","checkpoint":1,"volume":0.5,"shake":0.5,"best_time":1},{"version":1,"checkpoint":0.5,"volume":0.5,"shake":0.5,"best_time":1},{"version":1,"checkpoint":true,"volume":0.5,"shake":0.5,"best_time":1},{"version":1,"checkpoint":"1","volume":0.5,"shake":0.5,"best_time":1},{"version":1,"checkpoint":9,"volume":0.5,"shake":0.5,"best_time":1},{"version":1,"checkpoint":1,"volume":"loud","shake":0.5,"best_time":1}]:
		check("save_schema_rejects_"+str(results.size()), not game.valid_save(invalid))

func test_death_priority_at_gate() -> void:
	await settle_player()
	game.completed_zones = range(game.zones.size()-1)
	game.active_zone = game.zones.size()-1
	game.wave_index = game.zones[-1].waves.size()-1
	game.player.position = Vector2(game.zones[-1].left+350.0,game.FLOOR)
	var boss = EnemyScript.new("boss", Vector2(game.zones[-1].right-150.0,game.FLOOR))
	boss.dead = true
	boss.hp = 0
	game.enemies = [boss]
	game.player.hp = 8
	game.player.invuln = 0
	game.projectiles = [{"pos":game.player.position+Vector2(0,-40),"vx":0.0,"life":1.0,"friendly":false,"damage":20,"radius":23.0}]
	game.test_mode = false
	game._physics_process(1.0/60.0)
	game.test_mode = true
	check("death_priority_over_same_frame_victory", game.player.hp == 0 and game.player.state == "dead" and game.mode == "dead", "hp="+str(game.player.hp)+"; state="+game.player.state+"; mode="+game.mode)

func finish() -> void:
	var report = {"suite":"Starport MVP deterministic rule/integration fixtures","godot":Engine.get_version_info().string,"source_sha256":{"game.gd":FileAccess.get_sha256("res://scripts/game.gd"),"player.gd":FileAccess.get_sha256("res://scripts/player.gd"),"enemy.gd":FileAccess.get_sha256("res://scripts/enemy.gd"),"level_data.gd":FileAccess.get_sha256("res://scripts/level_data.gd"),"relay_controller.gd":FileAccess.get_sha256("res://scripts/relay_controller.gd"),"test_suite.gd":FileAccess.get_sha256("res://tests/test_suite.gd")},"test_count":results.size(),"passed":results.size()-failures,"failed":failures,"duration_ms":Time.get_ticks_msec()-started_msec,"user_data_dir":OS.get_user_data_dir(),"scope":"Actual game scripts, real CharacterBody2D collision frames for ground setup, deterministic state fixtures for combat/gates/save recovery. This is not an unassisted end-to-end run, visual QA, or export validation.","results":results}
	var file = FileAccess.open("res://qa/v03-relay-test-results.json",FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report,"  "))
		file.close()
	print("TEST_SUMMARY "+str(results.size()-failures)+"/"+str(results.size())+" passed; "+str(failures)+" failed")
	# Allow the audio mixer to release active test sound streams before exit.
	for audio in game.audio_pool:
		audio.stop()
		audio.stream = null
	game.music.stop()
	game.music.stream = null
	await get_tree().create_timer(0.1).timeout
	get_tree().quit(1 if failures>0 else 0)
