extends SceneTree
## Actual main scene; deterministic production-source hits plus real physics dt.
## Fixtures deliberately position combatants; not a normal route or device test.
const Main = preload("res://main.tscn")
const Enemy = preload("res://scripts/enemy.gd")
const CoolantBossScript = preload("res://scripts/coolant_boss.gd")
const FurnaceBossScript = preload("res://scripts/furnace_boss.gd")
const AxeBoss = preload("res://scripts/furnace_overload_boss.gd")
const Raider = preload("res://scripts/furnace_raider.gd")
var game: Node
var ui: Control
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var source_hashes: Dictionary = {}
var deltas: Array[float] = []
func _initialize() -> void: call_deferred("run")
func check(id: String, ok: bool, detail: String = "") -> void:
	checks.append({"id":id,"passed":ok,"detail":detail})
	if not ok: failures.append(id)
	print(("V09_DODGE_MAIN_PASS " if ok else "V09_DODGE_MAIN_FAIL ")+id+(" | "+detail if not detail.is_empty() else ""))
func hush() -> void:
	if is_instance_valid(game.music): game.music.stop(); game.music.stream=null
	for audio in game.audio_pool: audio.stop(); audio.stream=null
	game.sounds.clear()
func fresh(level: int=3, who: String="silverwing", mounted: bool=false) -> void:
	for action in ["left","right","light","heavy","skill","dodge","jump"]: Input.action_release(action)
	game.clear_touch(); game.exosuit.active=false; game.clear_combat()
	if game.level_id!=level: game.apply_level(level)
	game.mode="play"; game.paused=false; game.test_mode=false; game.autoplay=false; game.focus_input_blocked=false
	game.effects_enabled=false; game.hitstop_enabled=false; game.qa_no_drops=true; game.hits_taken=0
	game.feiren_unlocked=true; game.selected_character=who
	game.completed_zones.assign(range(game.zones.size())); game.encounter_waves.clear(); game.active_zone=-1
	game.furnace.reset(); game.coolant.reset(); game.road_traps.reset()
	game.furnace.opened.assign(["freight","restraint_a","restraint_b"])
	game.inventory.armor=0; game.inventory.counts={"bomb":0,"armor":0,"repair":0}
	game.player.set_exosuit_shape(false); game.player.reset_at(Vector2(700,574)); game.player.invuln=0
	game.exosuit.active=mounted; game.exosuit.elapsed=1; game.exosuit.remaining=30; game.exosuit.durability=140
	game.exosuit.fire_cd=0; game.exosuit.shock_cd=0; game.exosuit.heavy_cd=0
	if mounted: game.player.set_exosuit_shape(true)
	ui.set_enabled(true); ui.set_process(false); ui.refresh_layout()
func step(count: int=1) -> void:
	for _i in count:
		await physics_frame
		var dt: float=game.get_physics_process_delta_time(); deltas.append(dt)
		game._physics_process(dt)
func pointer(id: String, pressed: bool=true, index: int=17) -> void:
	var event:=InputEventScreenTouch.new(); event.index=index; event.pressed=pressed
	var data: Dictionary=ui.buttons[id]
	event.position=data.center if data.has("center") else data.rect.get_center()
	ui.ingest(event)
func run() -> void:
	var scratch: String=OS.get_environment("SILVERWING_QA_DIR")
	check("isolated_userdata",scratch.begins_with("Silverwing-OpenSource-QA-") and ProjectSettings.get_setting("application/config/use_custom_user_dir", false) and OS.get_user_data_dir().simplify_path().ends_with("/"+scratch),OS.get_user_data_dir())
	if not failures.is_empty(): finish(); return
	for path in ["main.tscn","scripts/player.gd","scripts/supplied_player.gd","scripts/rescue_player.gd","scripts/firepower_exosuit.gd","scripts/road_traps.gd"]:
		source_hashes[path]=FileAccess.get_sha256("res://"+path)
	game=Main.instantiate(); root.add_child(game); game.set_physics_process(false); game.hide(); hush()
	ui=game.touch_ui; ui.set_process(false)
	check("actual_v09_main",game.get_script().resource_path=="res://scripts/free_route_campaign.gd" and game.has_method("encounter_alive"),game.get_script().resource_path)
	await physics_frame
	await input_pause_checks()
	damage_source_checks()
	for path in source_hashes: check("stable_source_"+path,source_hashes[path]==FileAccess.get_sha256("res://"+path))
	check("engine_delta_used",not deltas.is_empty() and deltas.all(func(dt):return absf(dt-1.0/60)<1e-8),"physics_frames=%d"%deltas.size())
	game.exosuit.active=false; game.clear_combat(); hush(); game.queue_free()
	await process_frame; await process_frame
	finish()
func input_pause_checks() -> void:
	for who in ["silverwing","feiren"]:
		for mounted in [false,true]:
			var tag: String=who+("_exo" if mounted else "_foot")
			fresh(3,who,mounted); await step(4)
			game.player.invuln=0; game.player.dodge_cd=0
			pointer("dodge"); pointer("dodge",false)
			check(tag+"_touch_starts_dodge",game.player.state=="dodge" and game.player.elapsed==0 and game.player.invuln==0)
			await step(6)
			check(tag+"_sixth_frame_enters",game.player.is_dodge_invulnerable() and absf(game.player.elapsed-.1)<1e-9)
			await step(3)
			var elapsed: float=game.player.elapsed; var pos: Vector2=game.player.position
			var cd: float=game.player.dodge_cd; var power: float=game.exosuit.remaining; var time: float=game.road_traps.time
			pointer("pause"); pointer("pause",false); ui.refresh_layout()
			await step(12)
			check(tag+"_pause_freezes_action_and_world",game.paused and game.player.elapsed==elapsed and game.player.position==pos and game.player.dodge_cd==cd and game.exosuit.remaining==power and game.road_traps.time==time and game.player.is_dodge_invulnerable())
			var hp: int=game.player.hp; var dur: int=game.exosuit.durability
			check(tag+"_paused_stale_hit_rejected",not game.player.damage(20,0,"paused delayed hit") and game.player.hp==hp and game.exosuit.durability==dur)
			pointer("resume"); pointer("resume",false); ui.refresh_layout()
			await step(3)
			check(tag+"_resume_twelfth_frame_exits",not game.paused and absf(game.player.elapsed-.2)<1e-9 and not game.player.is_dodge_invulnerable() and game.player.can_take_damage())
			await step(6)
			check(tag+"_eighteenth_frame_finishes",game.player.state=="idle" and absf(game.player.elapsed-.3)<1e-9)
			await step(31); pointer("dodge"); pointer("dodge",false)
			check(tag+"_fresh_touch_repeats_after_cd",game.player.state=="dodge" and game.player.elapsed==0 and game.player.invuln==0)
			game.player.hitstop=.035; var start: float=game.player.elapsed
			await step(3)
			check(tag+"_actual_local_hitstop_freezes",game.player.elapsed==start and game.player.hitstop==0)
			await step(6)
			check(tag+"_hitstop_resume_enters_at_action_100ms",absf(game.player.elapsed-.1)<1e-9 and game.player.is_dodge_invulnerable())
	fresh(); await step(5)
	var serial: int=game.player.attack_serial
	pointer("light"); pointer("light",false); await step(6); pointer("light"); pointer("light",false); await step(17)
	check("touch_light_combo_still_chains",game.player.state=="light" and game.player.combo==2 and game.player.attack_serial==serial+2)
	fresh(3,"feiren"); await step(5); pointer("skill"); pointer("skill",false)
	check("actual_feiren_skill_retains_220ms_immunity",game.player.state=="skill" and game.player.invuln==.22 and not game.player.is_dodge_invulnerable())
	fresh(); await step(5)
	var event:=InputEventKey.new(); event.keycode=KEY_L; event.physical_keycode=KEY_L; event.pressed=true
	Input.parse_input_event(event); Input.flush_buffered_events()
	check("keyboard_L_dodge_dispatch",game.player.state=="dodge" and game.player.invuln==0)
	event=event.duplicate(); event.pressed=false; Input.parse_input_event(event); Input.flush_buffered_events()
func damage_source_checks() -> void:
	var sources: Array=[
		["base_melee",1],["base_shield",1],["base_boss_charge",1],["base_boss_sweep",1],["projectile",1],
		["coolant_boss",2],["coolant_steam",2],["coolant_scan",2],["coolant_vent",2],["projectile",2],
		["furnace_sweep",3],["lance",3],["drone_dive",3],["mine",3],["axe",3],["projectile",3],["furnace_heat",3],["furnace_mortar",3],
		["road_spike",1],["road_spike",2],["road_spike",3]]
	for source in sources:
		for resource in ["hp","armor","exosuit"]:
			if source[1]==1 and resource=="armor":continue
			if source[1]!=3 and resource=="exosuit":continue
			for target in [.05,.15,.2]:
				fresh(source[1],"silverwing",resource=="exosuit")
				if resource=="armor":game.inventory.armor=40
				game.player.state="dodge"; game.player.elapsed=target
				var before_hp: int=game.player.hp; var before_armor: int=game.inventory.armor; var before_dur: int=game.exosuit.durability
				hit_from(source[0])
				var protected: bool=target==.15
				var changed: bool=game.player.hp<before_hp if resource=="hp" else (game.inventory.armor<before_armor if resource=="armor" else game.exosuit.durability<before_dur)
				var ok: bool=(not changed and game.hits_taken==0 and game.player.state=="dodge" and game.player.invuln==0) if protected else (changed and game.hits_taken==1 and game.player.state=="hurt" and game.player.invuln==.7)
				check("source_%s_l%d_%s_t%.2f"%[source[0],source[1],resource,target],ok,"hp=%d armor=%d durability=%d hits=%d"%[game.player.hp,game.inventory.armor,game.exosuit.durability,game.hits_taken])
func hit_from(kind: String) -> void:
	var point: Vector2=game.player.position
	match kind:
		"base_melee","base_shield":
			var e=Enemy.new("shield" if kind=="base_shield" else "melee",point-Vector2(70,0)); e.facing=1; e.state="windup"; e.timer=0
			e._tick_logic(.001,game)
		"base_boss_charge","base_boss_sweep","coolant_boss","furnace_sweep":
			var script: Script=CoolantBossScript if kind=="coolant_boss" else (FurnaceBossScript if kind=="furnace_sweep" else Enemy)
			var e=script.new("boss",point-Vector2(70,0)); e.facing=1; e.state="attack"; e.timer=.2; e.move_name="charge" if kind=="base_boss_charge" else "sweep"
			e.boss_tick(.001,game)
		"projectile":
			game.projectiles=[{"pos":point+Vector2(0,-50),"vx":1.0,"vy":0.0,"life":1.0,"friendly":false,"damage":10,"radius":8.0}]
			game.update_effects(.001)
		"lance","drone_dive":
			var e=Raider.new("melee" if kind=="lance" else "drone",point-Vector2(20,0)); e.facing=1
			e._resolve_attack_contact(e.pos,e.pos+Vector2(25,0),game)
		"mine":
			var e=Raider.new("shield",point-Vector2(50,0)); e._explode_mine({"pos":point-Vector2(20,0)},game)
		"axe":
			var e=AxeBoss.new("boss",point-Vector2(170,0)); e.facing=1; e.phase_two=true; e.state="attack"; e.move_name="axe"; e.timer=.2
			e.boss_tick(.001,game)
		"coolant_steam","coolant_scan":
			game.player.position=Vector2(2870 if kind=="coolant_steam" else 8190,574)
			game.coolant.hazard_time=1.1; game.coolant.tick(0,game)
		"coolant_vent":
			game.coolant.vents=[{"x":point.x,"life":.2}]; game.coolant.tick(0,game)
		"furnace_heat":
			game.furnace.opened.clear(); game.player.position=Vector2(3530,574); game.furnace.hazard_time=1.1; game.furnace.tick(0,game)
		"furnace_mortar":
			game.furnace.mortars=[{"x":point.x,"life":.15}]; game.furnace.tick(0,game)
		"road_spike":
			var trap: Dictionary=game.road_traps.layout(game.level_id)[0]
			game.player.position=Vector2(trap.x,574); game.road_traps.time=fposmod(1.2-float(trap.phase),4.0); game.road_traps.tick(0,game)
func finish() -> void:
	var output: Dictionary={"passed":failures.is_empty(),"engine":Engine.get_version_info(),"scope":"Actual main scene, production hit sources, synthetic touch/keyboard and actual 60Hz physics dt. Fixture positioning is not a full playthrough.","checks":checks,"failures":failures,"source_sha256":source_hashes,"deltas":deltas}
	var file=FileAccess.open("res://qa/v09-dodge-integration-results.json",FileAccess.WRITE); file.store_string(JSON.stringify(output,"  ")); file.close()
	print("V09_DODGE_MAIN_RESULT checks=%d failures=%s"%[checks.size(),failures])
	quit(0 if failures.is_empty() else 1)
