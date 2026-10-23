extends Node2D
const RelayScript = preload("res://scripts/relay_controller.gd")
const PlayerScript = preload("res://scripts/player.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const FLOOR: float = 574.0
const LevelData = preload("res://scripts/level_data.gd")
var WORLD_END: float = LevelData.WORLD_END
const SAVE_PATH = "user://starport_save_v03.json"
const CYAN = Color("#5ce2ff")
const ORANGE = Color("#ffb56a")
const WHITE = Color("#e8f6ff")
var relays = RelayScript.new()
var relay_guard_spawned: Dictionary = {}
const CORE_NPC_X = 12070.0
const CORE_CHECKPOINT_X = 12110.0
var player: SilverwingPlayer
var mode = "menu"
var paused = false
var camera_x = 0.0
var camera_y = 0.0
var clock_time = 0.0
var run_time = 0.0
var victory_elapsed = 0.0
var shake = 0.0
var shake_amount = 0.6
var volume = 0.6
var enemies: Array = []
var projectiles: Array = []
var sparks: Array = []
var texts: Array = []
var slashes: Array = []
var zones: Array = []
var active_zone = -1
var wave_index = 0
var completed_zones: Array = []
var checkpoint = 0
var hits_taken = 0
var retries = 0
var kills = 0
var best_time = 0.0
var zone_hint = ""
var zone_hint_timer = 0.0
var status = ""
var status_timer = 0.0
var dialogue_timer = 0.0
var freeze = 0.0 # Retained for old QA fixtures; never used to pause the world.
var effects_enabled: bool = true
var hitstop_enabled: bool = true
var impact_count: int = 0
var impact_events: Array = []
var parallax_layers: Array = []
var bg: Texture2D
var floor_tex: Texture2D
var hero_frames: Dictionary = {}
var enemy_tex: Dictionary = {}
var enemy_animations: Dictionary = {}
var enemy_animation_meta: Dictionary = {}
var boss_hurt_regions: Dictionary = {}
var font: Font
var sounds: Dictionary = {}
var music: AudioStreamPlayer
var audio_pool: Array = []
var audio_i = 0
var saved_checkpoint = 0
var save_warning = ""
var menu_cursor = 0
var test_mode = false
var autoplay = false
var screenshot_path = ""
var auto_cooldown = 0.0
var hero_v1 = false
var comparison_path = ""
var qa_clear_pause = false

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--hero-v1" and DirAccess.dir_exists_absolute("res://assets/hero/idle"): hero_v1 = true
		if arg == "--qa-clear-pause": qa_clear_pause = true
		if arg.begins_with("--compare-shot="): comparison_path = arg.trim_prefix("--compare-shot=")
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	font = load("res://assets/fonts/Starport-CJK.otf")
	configure_inputs()
	load_assets()
	relays.reset(0)
	make_world()
	load_save()
	zones = LevelData.zones()
	for arg in OS.get_cmdline_user_args():
		if arg == "--autoplay": autoplay = true
		if arg == "--test-suite": test_mode = true
		if arg.begins_with("--screenshot="): screenshot_path = arg.trim_prefix("--screenshot=")
	if test_mode: call_deferred("run_tests")
	elif autoplay: start_run(false)
	if not comparison_path.is_empty():
		start_run(false)
		test_mode = true
		paused = false
		clock_time = 3.0
		run_time = 3.0
		player.position = Vector2(210,FLOOR-0.0667)
		player.invuln = 0.0
		capture_comparison.call_deferred()

func configure_inputs() -> void:
	var keys = {"left":[KEY_A,KEY_LEFT],"right":[KEY_D,KEY_RIGHT],"jump":[KEY_SPACE,KEY_W,KEY_UP],"light":[KEY_J],"heavy":[KEY_K],"dodge":[KEY_L,KEY_SHIFT],"skill":[KEY_U],"interact":[KEY_E,KEY_S,KEY_DOWN],"pause_game":[KEY_ESCAPE],"restart":[KEY_R]}
	for action in keys:
		if not InputMap.has_action(action): InputMap.add_action(action)
		for key in keys[action]:
			var ev = InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)

func load_assets() -> void:
	if ResourceLoader.exists("res://assets/environment/starport_background.png"):
		bg = load("res://assets/environment/starport_background.png")
	floor_tex = load("res://assets/environment/platform_strip.webp")
	load_parallax_layers()
	for state in ["idle","run","jump","attack1","attack2","attack3","heavy","dodge","skill","hurt","death"]:
		var frames: Array = []
		var path = ("res://assets/hero/" if hero_v1 else "res://assets/hero/v2/")+state+"/"
		if DirAccess.dir_exists_absolute(path):
			var filenames = ResourceLoader.list_directory(path)
			filenames.sort()
			for filename in filenames:
				if filename.ends_with(".png") or filename.ends_with(".webp"): frames.append(load(path+filename))
		hero_frames[state] = frames
	print("HERO_ASSETS idle=%d run=%d jump=%d" % [hero_frames.idle.size(),hero_frames.run.size(),hero_frames.jump.size()])
	for kind in ["melee","shield","drone","boss","repair_npc"]:
		var path = "res://assets/enemies/"+kind+".png"
		if ResourceLoader.exists(path): enemy_tex[kind] = load(path)
	load_enemy_animations()
	for name in ["swing","heavy","skill","dodge","jump","hit","block","break","hurt","shoot","warning","slam","explode","checkpoint","win","ui","hit_light","hit_heavy","armor_hit","armor_break"]:
		var path = "res://assets/audio/"+name+".wav"
		if ResourceLoader.exists(path): sounds[name] = load(path)
	for i in 6:
		var audio = AudioStreamPlayer.new()
		add_child(audio)
		audio_pool.append(audio)
	music = AudioStreamPlayer.new()
	music.volume_db = -18.0
	add_child(music)
	if ResourceLoader.exists("res://assets/audio/starport_loop.wav"):
		music.stream = load("res://assets/audio/starport_loop.wav")
		music.play()
	music.finished.connect(func(): music.play())

func make_world() -> void:
	for r in [Rect2(-200,FLOOR,WORLD_END+400,180)]+LevelData.OBSTACLES+LevelData.RELAY_PLATFORMS:
		var body = StaticBody2D.new()
		var collision = CollisionShape2D.new()
		var box = RectangleShape2D.new()
		box.size = r.size
		collision.shape = box
		collision.position = r.position+r.size/2
		if r in LevelData.RELAY_PLATFORMS:
			collision.one_way_collision = true
			collision.one_way_collision_margin = 8.0
		body.add_child(collision)
		add_child(body)
	player = PlayerScript.new()
	add_child(player)
	player.setup(self)
	player.reset_at(Vector2(210,FLOOR-2))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F8:
			effects_enabled = not effects_enabled
			show_status("命中特效 "+("开启" if effects_enabled else "关闭"),2.0)
		if event.keycode == KEY_F9:
			hitstop_enabled = not hitstop_enabled
			show_status("局部顿帧 "+("开启" if hitstop_enabled else "关闭"),2.0)
		if event.keycode == KEY_F12:
			capture_frame("user://screenshot.png")
		if mode == "menu":
			if event.keycode in [KEY_DOWN,KEY_S,KEY_UP,KEY_W]: menu_cursor = (menu_cursor+1)%2
			if event.keycode in [KEY_ENTER,KEY_SPACE]: start_run(menu_cursor == 1 and saved_checkpoint > 0)
			return
		if event.is_action_pressed("pause_game") and mode == "play":
			paused = not paused
			sfx("ui")
			return
		if paused:
			if event.keycode == KEY_M:
				mode = "menu"
				paused = false
			if event.keycode == KEY_V:
				volume = 0.0 if volume > 0.0 else 0.6
				AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume,0.0001)))
				save_game()
			if event.keycode == KEY_H:
				shake_amount = 0.0 if shake_amount>0.4 else (0.35 if shake_amount<=0.0 else 0.65)
				save_game()
			return
		if mode in ["dead","win"]:
			if event.is_action_pressed("restart") or event.keycode == KEY_ENTER:
				if mode == "dead": retry_checkpoint()
				else: start_run(false)
			if event.keycode == KEY_M: mode = "menu"
			return
		if mode == "play":
			for action in ["jump","light","heavy","dodge","skill"]:
				if event.is_action_pressed(action): player.begin_action(action)
			if event.is_action_pressed("interact"): interact()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if mode == "menu":
			if Rect2(820,450,310,58).has_point(event.position): start_run(false)
			if Rect2(820,525,310,48).has_point(event.position) and saved_checkpoint>0: start_run(true)

func start_run(resume: bool) -> void:
	mode = "play"
	paused = false
	run_time = 0.0
	hits_taken = 0
	retries = 0
	kills = 0
	completed_zones.clear()
	checkpoint = saved_checkpoint if resume else 0
	completed_zones = checkpoint_zone_ids()
	relays.reset(checkpoint)
	reset_relay_guards(checkpoint)
	active_zone = -1
	clear_combat()
	zone_hint_timer = 0.0
	player.reset_at(Vector2(checkpoint_spawn_x(),FLOOR-2))
	camera_x = clampf(player.position.x-420,0,WORLD_END-1120)
	camera_y = 0.0
	show_status("银翼上线。穿过星港，关闭失控中继器。",5.0)
	sfx("ui")
	if ResourceLoader.exists("res://assets/audio/starport_loop.wav"):
		music.stream = load("res://assets/audio/starport_loop.wav")
		music.play()

func clear_enemies() -> void:
	for enemy in enemies:
		enemy.release_physics()
	enemies.clear()

func clear_combat() -> void:
	clear_enemies()
	projectiles.clear()
	sparks.clear()
	texts.clear()
	slashes.clear()

func retry_checkpoint() -> void:
	retries += 1
	mode = "play"
	paused = false
	clear_combat()
	active_zone = -1
	completed_zones = checkpoint_zone_ids()
	relays.reset(checkpoint)
	reset_relay_guards(checkpoint)
	player.reset_at(Vector2(checkpoint_spawn_x(),FLOOR-2))
	camera_x = clampf(player.position.x-420,0,WORLD_END-1120)
	camera_y = 0.0
	show_status("维修完成。观察起手，闪开后再还击。",3.5)

func movement_axis() -> float:
	return Input.get_axis("left","right")

func _physics_process(dt: float) -> void:
	if not paused: clock_time += dt
	if mode=="win" and not paused and not test_mode:
		victory_elapsed += dt
		for enemy in enemies:
			if enemy.dead and enemy.death_timer<0.75: enemy.tick(dt,self)
	if mode != "play" or paused or test_mode:
		queue_redraw()
		return
	run_time += dt
	status_timer = maxf(0,status_timer-dt)
	zone_hint_timer = maxf(0,zone_hint_timer-dt)
	dialogue_timer = maxf(0,dialogue_timer-dt)
	shake = move_toward(shake,0,30*dt)
	var axis = movement_axis()
	if autoplay: axis = autopilot(dt)
	player.tick(dt,axis)
	camera_x = lerpf(camera_x,clampf(player.position.x-420,0,WORLD_END-1120),1-exp(-6.0*dt))
	camera_y = lerpf(camera_y,minf(0.0,player.position.y-360.0),1-exp(-7.0*dt))
	for enemy in enemies: enemy.tick(dt,self)
	update_effects(dt)
	update_zones()
	update_relay_guards()
	queue_redraw()
	if not screenshot_path.is_empty() and run_time>3.0:
		capture_frame.call_deferred(screenshot_path)
		screenshot_path = ""

func update_effects(dt: float) -> void:
	for p in projectiles:
		p.pos.x += p.vx*dt
		p.life -= dt
		if p.friendly:
			for enemy in enemies:
				if enemy.dead: continue
				if enemy.kind=="boss":
					var arc = PackedVector2Array()
					for i in 12: arc.append(p.pos+Vector2.from_angle(TAU*i/12.0)*float(p.radius))
					var contact: Variant = boss_attack_contact(enemy,arc,p.pos-Vector2(signf(p.vx)*40,0))
					if contact != null: enemy.hit(int(p.damage),false,p.pos.x-p.vx,p.serial,self,true,contact)
				elif absf(enemy.pos.x-p.pos.x)<65 and absf(enemy.pos.y-55-p.pos.y)<120:
					enemy.hit(int(p.damage),false,p.pos.x-p.vx,p.serial,self,true)
		else:
			if absf(player.position.x-p.pos.x)<27+p.radius and p.pos.y>player.position.y-93 and p.pos.y<player.position.y+5:
				if player.damage(int(p.damage),p.pos.x-p.vx,"地面震波" if p.radius>10 else "无人机射击"): p.life = 0
	projectiles = projectiles.filter(func(p): return p.life>0)
	for p in sparks:
		p.pos += p.vel*dt
		p.vel.y += 650*dt
		p.life -= dt
	sparks = sparks.filter(func(p): return p.life>0)
	for p in texts:
		p.pos.y -= 42*dt
		p.life -= dt
	texts = texts.filter(func(p): return p.life>0)
	for p in slashes:
		if player.hitstop <= 0.0: p.life -= dt
	slashes = slashes.filter(func(p): return p.life>0)

func update_zones() -> void:
	if mode != "play": return
	if active_zone >= 0:
		if alive_count() == 0:
			var waves = zones[active_zone].waves
			wave_index += 1
			if wave_index < waves.size():
				spawn_wave(waves[wave_index])
				show_status("下一波机械正在接近",2.0)
			else:
				completed_zones.append(active_zone)
				if active_zone == zones.size()-1:
					victory()
					return
				show_status("战区已清理 · 通路开放 →",3.0)
				sfx("checkpoint")
				active_zone = -1
	else:
		for i in zones.size():
			if not i in completed_zones and player.position.x>=zones[i].start:
				active_zone = i
				print("ZONE_START %d t=%.2f" % [i,run_time])
				wave_index = 0
				clear_enemies()
				projectiles.clear()
				spawn_wave(zones[i].waves[0])
				show_status(zones[i].name+" · 封锁启动",2.8)
				zone_hint = zones[i].get("hint","")
				zone_hint_timer = 6.0
				if i == zones.size()-1:
					dialogue_timer = 0.0
					set_boss_music()
				break

func reset_relay_guards(checkpoint_id: int) -> void:
	relay_guard_spawned.clear()
	for station in LevelData.RELAY_STATIONS:
		if checkpoint_id>=2 or (checkpoint_id==1 and int(station.id) in LevelData.CHECKPOINT_RELAY_IDS):
			relay_guard_spawned[int(station.id)] = true

func update_relay_guards() -> void:
	if mode!="play" or active_zone>=0: return
	for station in LevelData.RELAY_STATIONS:
		var id: int = int(station.id)
		if relay_guard_spawned.has(id) or relays.is_station_open(id): continue
		if not completed_zones.has(int(station.after_zone)): continue
		if relays.activated_switches.get(id,[]).is_empty(): continue
		var terminal: Dictionary = station.switches.back()
		var enemy = EnemyScript.new("drone",terminal.feet)
		enemy.relay_station = id
		enemy.attach_physics(self)
		enemies.append(enemy)
		relay_guard_spawned[id] = true
		show_status("供电接入 · 上层安保机启动",3.0)
		print("RELAY_GUARD station=%d t=%.2f"%[id,run_time])

func spawn_wave(wave: Array) -> void:
	for entry in wave:
		var enemy = EnemyScript.new(entry[0],Vector2(entry[1],float(entry[2]) if entry.size()>2 else FLOOR))
		enemy.attach_physics(self)
		enemies.append(enemy)
func alive_count() -> int:
	var count = 0
	for enemy in enemies:
		if not enemy.dead: count += 1
	return count
func active_attackers() -> int:
	var count = 0
	for enemy in enemies:
		if not enemy.dead and enemy.state in ["windup","attack"]: count += 1
	return count
func left_bound() -> float:
	return float(zones[active_zone].left)+25 if active_zone>=0 else 35.0
func right_bound() -> float:
	var bound = float(zones[active_zone].right)-25 if active_zone>=0 else WORLD_END-35
	return relays.right_bound(bound)

func rooms_completed_through(last_id: int) -> bool:
	for id in range(last_id+1):
		if not completed_zones.has(id): return false
	return true

func checkpoint_zone_ids() -> Array:
	if checkpoint>=2: return range(LevelData.BOSS_ZONE_INDEX)
	return LevelData.CHECKPOINT_COMPLETED_ZONES.duplicate() if checkpoint==1 else []

func checkpoint_spawn_x() -> float:
	if checkpoint>=2: return CORE_CHECKPOINT_X
	return LevelData.CHECKPOINT_X if checkpoint==1 else LevelData.START_X

func player_strike(kind: String, combo: int, serial: int, first_active_tick: bool = true) -> void:
	if player.hp<=0 or mode!="play": return
	var range_x: float = 145.0 if kind=="light" else 175.0
	var damage: int = ([10,10,18][combo-1]) if kind=="light" else 28
	if first_active_tick:
		sfx("swing" if kind=="light" else kind)
	if kind=="skill":
		if not first_active_tick: return
		projectiles.append({"pos":player.position+Vector2(player.facing*40,-60),"vx":player.facing*640.0,"life":0.85,"friendly":true,"damage":24,"radius":36.0,"serial":serial})
	else:
		for enemy in enemies:
			if enemy.dead: continue
			if enemy.kind=="boss":
				var contact: Variant = boss_attack_contact(enemy,melee_attack_polygon(kind),player.position+Vector2(0,-65))
				if contact != null: enemy.hit(damage,kind=="heavy",player.position.x,serial,self,false,contact)
			else:
				var dx: float = (enemy.pos.x-player.position.x)*player.facing
				if dx>=-24 and dx<=range_x and absf(enemy.pos.y-player.position.y)<110:
					enemy.hit(damage,kind=="heavy",player.position.x,serial,self)
	if first_active_tick and kind!="skill":
		slashes.append({"pos":player.position+Vector2(player.facing*65,-65),"facing":player.facing,"life":0.12 if kind=="light" else 0.14,"heavy":kind=="heavy","combo":combo})

func interact() -> void:
	if relays.interact(self): return
	var at_middle: bool = absf(player.position.x-LevelData.NPC_X)<160 and rooms_completed_through(3)
	var at_core: bool = absf(player.position.x-CORE_NPC_X)<135 and rooms_completed_through(LevelData.BOSS_ZONE_INDEX-1) and relays.is_station_open(2)
	if (at_middle or at_core) and active_zone<0:
		checkpoint = 2 if at_core else 1
		saved_checkpoint = checkpoint
		player.hp = 100
		player.skill_cd = 0
		dialogue_timer = 9.0
		save_game()
		sfx("checkpoint")
		show_status("核心检查点已保存 · 生命与技能恢复" if at_core else "检查点已保存 · 生命与技能恢复",3.0)

func on_player_death() -> void:
	print("RUN_DEATH t=%.2f zone=%d hp=%d hits=%d" % [run_time,active_zone,player.hp,hits_taken])
	if autoplay:
		var log = FileAccess.open("res://qa/autoplay-result.json",FileAccess.WRITE)
		log.store_string(JSON.stringify({"outcome":"dead","seconds":run_time,"zone":active_zone,"hp":player.hp,"hits":hits_taken,"kills":kills}))
		finish_autoplay.call_deferred(2)
	mode = "dead"
	paused = false
func victory() -> void:
	print("RUN_VICTORY t=%.2f hits=%d retries=%d" % [run_time,hits_taken,retries])
	if autoplay:
		var log = FileAccess.open("res://qa/autoplay-result.json",FileAccess.WRITE)
		log.store_string(JSON.stringify({"outcome":"win","seconds":run_time,"hp":player.hp,"hits":hits_taken,"kills":kills}))
		finish_autoplay.call_deferred(0)
	mode = "win"
	victory_elapsed = 0.0
	best_time = run_time if best_time<=0 else minf(best_time,run_time)
	saved_checkpoint = 0
	checkpoint = 0
	save_game()
	sfx("win")
func show_status(message: String, duration: float = 3.0) -> void:
	status = message
	status_timer = duration
func float_text(point: Vector2, value: String, color: Color) -> void:
	texts.append({"pos":point,"value":value,"color":color,"life":0.8})
func add_sparks(point: Vector2, color: Color, count: int) -> void:
	if not effects_enabled: return
	for i in mini(count,maxi(0,120-sparks.size())):
		var angle = randf()*TAU
		sparks.append({"pos":point,"vel":Vector2(cos(angle),sin(angle))*randf_range(70,330),"life":randf_range(0.16,0.45),"color":color})
func sfx(name: String) -> void:
	if not effects_enabled and name in ["swing","heavy","skill","dodge","hit","block","break","hurt","shoot","slam","explode","hit_light","hit_heavy","armor_hit","armor_break"]: return
	if not sounds.has(name) or audio_pool.is_empty(): return
	var audio = audio_pool[audio_i%audio_pool.size()]
	audio_i += 1
	audio.stream = sounds[name]
	audio.pitch_scale = randf_range(0.97,1.03) if name in ["hit_light","hit_heavy","armor_hit","armor_break","swing","heavy"] else 1.0
	audio.volume_db = -10.0
	audio.play()
func set_boss_music() -> void:
	if ResourceLoader.exists("res://assets/audio/boss_loop.wav"):
		music.stream = load("res://assets/audio/boss_loop.wav")
		music.play()

func save_game() -> void:
	var data = {"version":1,"checkpoint":saved_checkpoint,"best_time":best_time,"volume":volume,"shake":shake_amount}
	var temp = FileAccess.open(SAVE_PATH+".tmp",FileAccess.WRITE)
	if temp == null:
		save_warning = "无法写入存档；本次可继续游玩。"
		return
	temp.store_string(JSON.stringify(data))
	temp.flush()
	temp.close()
	if FileAccess.file_exists(SAVE_PATH): DirAccess.copy_absolute(SAVE_PATH,SAVE_PATH+".bak")
	if DirAccess.rename_absolute(SAVE_PATH+".tmp",SAVE_PATH) != OK: save_warning = "存档写入失败；请勿依赖续玩。"
func valid_save(data: Variant) -> bool:
	return data is Dictionary and typeof(data.get("version")) in [TYPE_FLOAT,TYPE_INT] and data.get("version",0)==1 and typeof(data.get("checkpoint")) in [TYPE_FLOAT,TYPE_INT] and (data.get("checkpoint",-1)==0 or data.get("checkpoint",-1)==1 or data.get("checkpoint",-1)==2) and typeof(data.get("volume")) in [TYPE_FLOAT,TYPE_INT] and typeof(data.get("shake")) in [TYPE_FLOAT,TYPE_INT] and typeof(data.get("best_time")) in [TYPE_FLOAT,TYPE_INT]
func read_saved_json(path: String) -> Variant:
	var parser = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK: return null
	return parser.data

func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH): return
	var data = read_saved_json(SAVE_PATH)
	if not valid_save(data):
		save_warning = "存档格式异常，已安全回退。"
		if FileAccess.file_exists(SAVE_PATH+".bak"): data = read_saved_json(SAVE_PATH+".bak")
		if not valid_save(data): return
	saved_checkpoint = int(data.checkpoint)
	volume = clampf(float(data.volume),0,1)
	shake_amount = clampf(float(data.shake),0,1)
	best_time = maxf(0,float(data.best_time))
	AudioServer.set_bus_volume_db(0,linear_to_db(maxf(volume,0.0001)))

func load_parallax_layers() -> void:
	var base = "res://assets/environment/parallax/"
	if not FileAccess.file_exists(base+"manifest.json"): return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base+"manifest.json"))
	for data in manifest.layers:
		var texture: Texture2D = load(base+str(data.path).get_file())
		var c: Array = data.draw_tint
		parallax_layers.append({"id":data.id,"texture":texture,"factor":float(data.camera_scroll_scale),"width":float(data.size[0]),"height":float(data.size[1]),"y":float(data.draw_origin[1]),"repeat":bool(data.repeat),"foreground":data.id=="foreground","tint":Color(c[0],c[1],c[2],c[3])})

func parallax_rects(layer: Dictionary, camera: float) -> Array:
	var rects: Array = []
	var offset: float = camera*float(layer.factor)
	if not layer.repeat:
		rects.append(Rect2(-offset,layer.y,layer.width,layer.height))
	else:
		offset = fposmod(offset,float(layer.width))
		for i in range(-1,2): rects.append(Rect2(i*float(layer.width)-offset,layer.y,layer.width,layer.height))
	return rects

func draw_parallax_layers(foreground: bool) -> void:
	for layer in parallax_layers:
		if layer.foreground != foreground: continue
		for rect in parallax_rects(layer,camera_x):
			if layer.foreground: rect.position.y -= camera_y*float(layer.factor)
			draw_texture_rect(layer.texture,rect,false,layer.tint)

func _draw() -> void:
	if not font: return
	if not parallax_layers.is_empty():
		draw_parallax_layers(false)
	elif bg:
		var offset = fposmod(camera_x*0.12,1510.0)
		for i in range(-1,2): draw_texture_rect(bg,Rect2(i*1510-offset,0,1510,850),false,Color(0.72,0.82,0.95))
	draw_rect(Rect2(0,0,1280,720),Color(0.01,0.035,0.09,0.12))
	var jitter = Vector2(randf_range(-shake,shake),randf_range(-shake,shake))*shake_amount if not paused and effects_enabled else Vector2.ZERO
	draw_set_transform(Vector2(-camera_x,-camera_y)+jitter)
	draw_world()
	for enemy in enemies: draw_enemy(enemy)
	if mode != "menu": draw_hero()
	draw_effects()
	draw_set_transform(Vector2.ZERO)
	draw_parallax_layers(true)
	if mode == "menu": draw_menu()
	else:
		draw_hud()
		if paused:
			if qa_clear_pause: text_at("QA PAUSED · 时间/物理已暂停",Vector2(440,148),18,CYAN)
			else: draw_pause()
		elif mode=="dead": draw_result(false)
		elif mode=="win" and victory_elapsed>=0.72: draw_result(true)

func draw_world() -> void:
	for i in range(-1,int(WORLD_END/870.0)+2):
		var x = i*870.0
		if floor_tex: draw_texture_rect(floor_tex,Rect2(x,FLOOR-10,880,115),false)
		draw_rect(Rect2(x,FLOOR+103,870,65),Color("#091724"))
		draw_line(Vector2(x,FLOOR+1),Vector2(x+870,FLOOR+1),Color(0.5,0.85,1,0.5),2)
	for r in LevelData.OBSTACLES:
		if floor_tex:
			draw_texture_rect_region(floor_tex,r,Rect2(64,0,r.size.x*2.468,r.size.y*2.468))
		else: draw_rect(r,Color("#34495b"))
		draw_rect(Rect2(r.position,Vector2(r.size.x,3)),Color("#91d8ee"))
	for x in [120.0,LevelData.NPC_X-250.0,WORLD_END-1200.0]:
		draw_rect(Rect2(x,FLOOR-110,58,110),Color("#142a42"))
		draw_rect(Rect2(x+6,FLOOR-104,46,8),Color("#447188"))
		for y in 3: draw_rect(Rect2(x+7,FLOOR-84+y*24,18,12),Color("#30506a"))
	draw_repair_station(LevelData.NPC_X)
	draw_repair_station(CORE_NPC_X)
	relays.draw_world(self)
	for zone in zones:
		var x: float = zone.left+70.0
		draw_rect(Rect2(x-12,FLOOR-244,370,44),Color(0.015,0.05,0.09,0.75))
		text_at(zone.name,Vector2(x,FLOOR-216),20,Color("#72afc9"))
	for i in 2: draw_rect(Rect2(WORLD_END-65+i*28,FLOOR-290,20,290),Color("#28435b"))
	for j in 4: draw_line(Vector2(WORLD_END-59,FLOOR-258+j*55),Vector2(WORLD_END-25,FLOOR-258+j*55),ORANGE,3)

func draw_repair_station(x: float) -> void:
	draw_rect(Rect2(x-100,FLOOR-176,52,176),Color("#132b44"))
	draw_rect(Rect2(x-94,FLOOR-168,40,90),Color(0.1,0.8,1,0.18))
	draw_rect(Rect2(x-94,FLOOR-168,40,90),CYAN,false,2)
	draw_line(Vector2(x-74,FLOOR-158),Vector2(x-74,FLOOR-88),CYAN,3)
	draw_line(Vector2(x-86,FLOOR-122),Vector2(x-62,FLOOR-122),CYAN,3)
	if enemy_tex.has("repair_npc"): draw_sprite(enemy_tex.repair_npc,Vector2(x,FLOOR),120,1,Color.WHITE)
	text_at("米米 · 核心维修端" if x==CORE_NPC_X else "维修单元 · 米米",Vector2(x-92,FLOOR-194),19,CYAN)
	if mode=="play" and absf(player.position.x-x)<160:
		panel(Rect2(x-145,FLOOR-260,290,44),Color(0.02,0.08,0.15,0.9),CYAN)
		text_at("E  维修 / 保存检查点",Vector2(x-126,FLOOR-231),21)

func draw_hero() -> void:
	var state_name = player.state
	if state_name=="light": state_name="attack%d"%player.combo
	elif state_name=="air": state_name="jump"
	elif state_name=="dead": state_name="death"
	var frames: Array = hero_frames.get(state_name,[])
	if frames.is_empty(): frames = hero_frames.get("idle",[])
	if frames.is_empty(): return
	var speed = (12.0 if hero_v1 else 9.0) if state_name=="run" else 7.0
	var frame_index = int((clock_time if state_name in ["idle","run"] else player.elapsed)*speed)%frames.size()
	if not state_name in ["idle","run"]: frame_index = mini(int(player.elapsed*speed),frames.size()-1)
	if state_name=="attack1":
		frame_index = mini(1 if player.elapsed>=0.10 else 0,frames.size()-1)
	elif state_name=="heavy":
		frame_index = mini(1 if player.elapsed>=0.30 else 0,frames.size()-1)
	elif state_name=="jump":
		if player.velocity.y < -300: frame_index=0
		elif player.velocity.y < -80: frame_index=1
		elif player.velocity.y < 80: frame_index=2
		elif player.velocity.y < 330: frame_index=3
		else: frame_index=4
		frame_index=mini(frame_index,frames.size()-1)
	var tex: Texture2D = frames[frame_index]
	var alpha = 0.55 if player.is_invulnerable() and int(clock_time*20)%2==0 else 1.0
	var tint = Color(1,0.65,0.6,alpha) if player.state=="hurt" else Color(1,1,1,alpha)
	draw_circle(player.position+Vector2(0,1),35,Color(0.02,0.06,0.1,0.3))
	var bob = sin(clock_time*5)*1.5 if state_name=="idle" else 0.0
	var origin = player.position+Vector2(0,bob)
	if state_name=="run" and not hero_v1:
		var run_root_offsets: Array = [0.0,15.0,-9.0,10.0,-1.0,-18.5]
		origin.x += float(run_root_offsets[frame_index%6])*264.0/512.0*player.facing
	var size = 264.0
	var feet_offset = size*(296.0/320.0 if hero_v1 else 474.0/512.0)
	if player.state=="dodge":
		for i in [3,2,1]:
			var trail = sprite_rect_for(origin+Vector2(-player.facing*i*26,0),Vector2(size,size),feet_offset,player.facing)
			draw_texture_rect(tex,trail,false,Color(0.2,0.8,1,0.1+0.03*i))
	var rect = sprite_rect_for(origin,Vector2(size,size),feet_offset,player.facing)
	draw_texture_rect(tex,rect,false,tint)

func sprite_rect_for(feet: Vector2, size: Vector2, origin_y: float, facing: int) -> Rect2:
	# Godot mirrors negative texture-rect dimensions IN PLACE.
	# Do not add width to position: that shifts the image by one whole frame.
	var rect = Rect2(feet-Vector2(size.x*0.5,origin_y),size)
	if facing < 0: rect.size.x = -size.x
	return rect

func draw_sprite(tex: Texture2D, feet: Vector2, height: float, facing: int, tint: Color) -> void:
	var width = tex.get_width()/float(tex.get_height())*height
	var rect = sprite_rect_for(feet,Vector2(width,height),height,facing)
	draw_texture_rect(tex,rect,false,tint)

func load_enemy_animations() -> void:
	var hurt_path = "res://assets/enemies/actions/boss/hurt_regions.json"
	if FileAccess.file_exists(hurt_path): boss_hurt_regions = JSON.parse_string(FileAccess.get_file_as_string(hurt_path))
	for kind in ["melee","shield","drone","boss"]:
		var path = "res://assets/enemies/actions/"+kind+"/"
		if not FileAccess.file_exists(path+"manifest.json"): continue
		var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path+"manifest.json"))
		var groups: Dictionary = {}
		for action in meta.animations:
			var frames: Array = []
			for filename in meta.animations[action].frames: frames.append(load(path+filename))
			groups[action] = frames
		enemy_animations[kind] = groups
		enemy_animation_meta[kind] = meta

func enemy_animation_pose(enemy: StarportEnemy) -> Dictionary:
	var action = "idle"
	var frame = 0
	var elapsed = enemy.state_elapsed if enemy.visual_state==enemy.state else 0.0
	if enemy.dead:
		action = "death"
		frame = int(enemy.death_timer*(5.0 if enemy.kind=="boss" else 7.0))
	elif enemy.state=="windup":
		action = "attack_"+enemy.move_name if enemy.kind=="boss" else "attack"
		frame = (1 if enemy.timer<0.20 else 0) if enemy.kind=="drone" else 0
	elif enemy.state=="attack":
		action = "attack_"+enemy.move_name if enemy.kind=="boss" else "attack"
		frame = 2 if enemy.kind=="drone" else 1
	elif enemy.state=="stun" or (enemy.flash>0 and enemy.state in ["approach","recover"]):
		action = "hurt"
		frame = int(elapsed*10.0)
	elif enemy.kind=="boss" and enemy.state=="recover":
		# Lowered chassis without baked impact effects: a visible counterattack window.
		action = "attack_charge"
		frame = 0
	elif enemy.state=="recover" and elapsed<0.24 and enemy.kind in ["melee","shield"]:
		action = "attack"
		frame = 2
	elif enemy.state=="approach" and absf(enemy.actual_motion_x)>8.0:
		action = "move"
		frame = int(enemy.visual_clock*9.0)%enemy_animations[enemy.kind].move.size()
	else:
		frame = int(enemy.visual_clock*3.0)%enemy_animations[enemy.kind].idle.size()
	return {"action":action,"frame":frame}

func draw_enemy(enemy: StarportEnemy) -> void:
	if enemy.dead and enemy.death_timer>0.72: return
	var height: float = {"melee":164.0,"shield":188.0,"drone":106.0,"boss":265.0}.get(enemy.kind,160.0)
	var offset = Vector2.ZERO
	if enemy.kind=="drone": offset.y=sin(enemy.visual_clock*3+enemy.home)*5

	var tint = Color(1,0.78,0.65) if enemy.state=="windup" else Color.WHITE
	if enemy.flash>0 and effects_enabled: tint=Color(1.8,1.8,1.8)
	if enemy.dead: tint.a=clampf((0.72-enemy.death_timer)/0.20,0.0,1.0)
	draw_circle(Vector2(enemy.pos.x,enemy.ground_y+1),40 if enemy.kind!="boss" else 75,Color(0.01,0.03,0.08,0.3))
	if enemy_animations.has(enemy.kind):
		var pose = enemy_animation_pose(enemy)
		var frames: Array = enemy_animations[enemy.kind][pose.action]
		var tex: Texture2D = frames[clampi(pose.frame,0,frames.size()-1)]
		var meta: Dictionary = enemy_animation_meta[enemy.kind]
		var scale_factor: float = height/float(meta.native_body_height)
		var draw_size = Vector2(float(meta.frame_size[0]),float(meta.frame_size[1]))*scale_factor
		var origin = enemy.pos+offset
		# Drone art is hull-centered; enemy.pos remains the physics bottom root.
		if enemy.kind=="drone": origin.y -= 48.0
		var rect = sprite_rect_for(origin,draw_size,float(meta.root[1])*scale_factor,-enemy.facing)
		draw_texture_rect(tex,rect,false,tint)
	elif enemy_tex.has(enemy.kind): draw_sprite(enemy_tex[enemy.kind],enemy.pos+offset,height,-enemy.facing,tint)
	if enemy.dead: return
	if enemy.kind=="shield" and enemy.shield>0:
		var x = enemy.pos.x+enemy.facing*42
		draw_line(Vector2(x,enemy.pos.y-127),Vector2(x,enemy.pos.y-25),Color(1,0.7,0.3,0.65),4)
	if enemy.kind!="boss": bar(Rect2(enemy.pos+Vector2(-36,-height-16),Vector2(72,5)),float(enemy.hp)/enemy.max_hp,ORANGE)
	if enemy.state=="windup":
		var at = enemy.pos+Vector2(0,-height-33)
		draw_circle(at,12,ORANGE)
		text_at("!",at+Vector2(-4,7),20,Color("#151c27"))
		if enemy.kind=="drone": draw_line(enemy.pos+Vector2(enemy.facing*35,-48),Vector2(enemy.locked_x,enemy.pos.y-48),Color(1,0.6,0.3,0.65),2)
		elif enemy.kind=="boss":
			var label = {"sweep":"横扫 · 拉开 / 闪避","charge":"冲撞 · 穿过 / 跳开","wave":"震波蓄力"}.get(enemy.move_name,"")
			# Boss instructions are drawn in the HUD so the health bar cannot cover them.
			var width = 215.0 if enemy.move_name=="sweep" else 520.0
			if enemy.move_name=="wave": draw_rect(Rect2(zones.back().left,FLOOR-10,float(zones.back().right)-float(zones.back().left),10),Color(1,0.5,0.2,0.35))
			else: draw_rect(Rect2(enemy.pos.x if enemy.facing>0 else enemy.pos.x-width,FLOOR-7,width,7),Color(1,0.5,0.2,0.55))

func draw_effects() -> void:
	for slash in slashes:
		if not effects_enabled: continue
		var t = slash.life/0.18
		var radius = 110.0 if slash.heavy else 83.0
		var angle = 0.0 if slash.facing>0 else PI
		draw_arc(slash.pos,radius,angle-1.0,angle+1.0,24,Color(0.3,0.8,1,t*0.65),18)
		draw_arc(slash.pos,radius,angle-1.0,angle+1.0,24,Color(0.85,1,1,t),4)
	for p in projectiles:
		if p.friendly:
			if get("skill_vfx")!=null and get("skill_vfx").handles_projectile(p):continue
			draw_arc(p.pos,38,-1.2 if p.vx>0 else PI-1.2,1.2 if p.vx>0 else PI+1.2,20,CYAN,10 if effects_enabled else 3)
			if effects_enabled: draw_line(p.pos-Vector2(signf(p.vx)*50,0),p.pos,Color(0.3,0.8,1,0.5),14)
		elif p.radius>10: draw_arc(p.pos,24,PI,TAU,12,ORANGE,7)
		else:
			draw_circle(p.pos,10,Color(1,0.5,0.2,0.25))
			draw_circle(p.pos,5,Color("#ffde94"))
	for p in sparks:
		if effects_enabled: draw_line(p.pos,p.pos-p.vel.normalized()*9,p.color,2)
	for p in texts:
		if effects_enabled: text_at(p.value,p.pos,25,Color(p.color,minf(1,p.life*2)))

func panel(rect: Rect2, fill: Color = Color(0.015,0.04,0.09,0.91), border: Color = Color("#284963")) -> void:
	var style = StyleBoxFlat.new()
	style.bg_color=fill
	style.border_color=border
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	draw_style_box(style,rect)
func text_at(value: String, at: Vector2, size: int = 22, color: Color = WHITE) -> void:
	draw_string(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)
func centered(value: String, y: float, size: int = 28, color: Color = WHITE) -> void:
	text_at(value,Vector2((1280-font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x)/2,y),size,color)
func bar(rect: Rect2, fraction: float, color: Color) -> void:
	draw_rect(rect,Color("#071725"))
	draw_rect(Rect2(rect.position,Vector2(rect.size.x*clampf(fraction,0,1),rect.size.y)),color)

func draw_hud() -> void:
	panel(Rect2(24,22,390,111))
	draw_rect(Rect2(24,22,4,111),CYAN)
	text_at("银翼  /  SILVERWING",Vector2(43,51),22)
	text_at("v0.4",Vector2(1194,653),14,CYAN)
	bar(Rect2(43,66,274,15),player.hp/100.0,CYAN if player.hp>25 else Color("#ff8c7a"))
	text_at("%d / 100"%player.hp,Vector2(329,80),16)
	text_at("U 磁轨斩",Vector2(43,112),16,Color("#a5c5de"))
	bar(Rect2(129,102,123,6),1-player.skill_cd/8,CYAN)
	text_at("就绪" if player.skill_cd<=0 else "%.1fs"%player.skill_cd,Vector2(263,113),15,CYAN)
	text_at("闪避 "+("就绪" if player.dodge_cd<=0 else "%.1fs"%player.dodge_cd),Vector2(322,112),14)
	panel(Rect2(922,22,334,86))
	text_at("01  失控的星港",Vector2(943,51),23)
	text_at("%02d:%02d   ·   受击 %d   ·   重试 %d" %[int(run_time)/60,int(run_time)%60,hits_taken,retries],Vector2(942,82),16,Color("#aac5da"))
	text_at("敌情 · 剩余 %d"%alive_count() if active_zone>=0 else "向右推进 →",Vector2(1060,133),18,ORANGE if active_zone>=0 else CYAN)
	panel(Rect2(24,665,1232,38),Color(0.01,0.03,0.07,0.85))
	text_at("A / D 移动    SPACE 跳跃    J 连击    K 破甲重击    L / SHIFT 闪避    U 磁轨斩    E 交互    ESC 暂停",Vector2(45,690),18,Color("#b6cde0"))
	if status_timer>0:
		panel(Rect2(368,157,544,44),Color(0.01,0.06,0.12,0.92),Color("#2b6179"))
		centered(status,186,20,CYAN)
	var relay_hint: String = relays.hud_hint(self)
	if not relay_hint.is_empty():
		panel(Rect2(433,24,466,100),Color(0.01,0.04,0.09,0.91),CYAN)
		for line in range(mini(3,int(ceil(relay_hint.length()/28.0)))):
			text_at(relay_hint.substr(line*28,28),Vector2(450,49+28*line),15,CYAN)
	if zone_hint_timer>0 and not zone_hint.is_empty():
		panel(Rect2(166,286,948,36),Color(0.01,0.04,0.09,0.86),Color("#244a63"))
		centered(zone_hint,311,17,Color("#b7d6e5"))
	for enemy in enemies:
		if enemy.kind=="boss" and not enemy.dead:
			panel(Rect2(344,214,592,60))
			centered("港卫重装机"+(" / 过载" if enemy.phase_two else ""),236,18,ORANGE)
			bar(Rect2(365,249,550,9),float(enemy.hp)/enemy.max_hp,ORANGE)
			var hint: Dictionary = enemy.boss_wave_hint(self)
			var cue_text: String = str(hint.text)
			var cue_color: Color = CYAN if hint.stage=="jump" else ORANGE
			var cue_detail: String = "SPACE 起跳 · 向震波方向越过"
			if cue_text.is_empty() and enemy.state=="recover":
				cue_text="冷却中 · 反击机会"
				cue_color=CYAN
				cue_detail="靠近躯干与腿部，抓住停顿出手"
			elif cue_text.is_empty() and enemy.state=="windup":
				cue_text={"sweep":"横扫 · 拉开 / 闪避","charge":"冲撞 · 穿过 / 跳开"}.get(enemy.move_name,"")
				cue_detail="看清起手，留出闪避的空间"
			if not cue_text.is_empty():
				panel(Rect2(433,24,466,104),Color(0.015,0.04,0.09,0.94),cue_color)
				text_at(cue_text,Vector2(451,65),23,cue_color)
				text_at(cue_detail,Vector2(451,101),17,WHITE)

	if dialogue_timer>0 and minf(absf(player.position.x-LevelData.NPC_X),absf(player.position.x-CORE_NPC_X))<230:
		panel(Rect2(295,404,735,126),Color(0.015,0.05,0.1,0.96),CYAN)
		text_at("米米 / 维修单元",Vector2(318,439),21,CYAN)
		text_at("核心维修完成！横扫时闪避，震波时起跳，抓住恢复空档。" if checkpoint>=2 else "检修完成！前方还有双盾防线与中继警戒，再往前是港卫。",Vector2(318,476),18)
		text_at("失败会在这里重新启动。别急，等它停下来再还手。",Vector2(318,510),18)
	if not save_warning.is_empty(): text_at(save_warning,Vector2(30,649),17,ORANGE)

func draw_menu() -> void:
	draw_rect(Rect2(0,0,1280,720),Color(0.01,0.03,0.075,0.48))
	panel(Rect2(64,68,668,578),Color(0.02,0.05,0.10,0.65),Color("#2d6580"))
	text_at("S T A R P O R T  /  M E C H A  S Q U A D",Vector2(92,112),19,CYAN)
	text_at("星港机甲小队",Vector2(89,184),52)
	text_at("银翼 · 失控的星港",Vector2(94,225),25,Color("#b4d5ea"))
	text_at("先看清，再出手。",Vector2(94,538),30)
	text_at("三段连击 / 破甲重击 / 无敌闪避 / 首领三招",Vector2(95,577),19,Color("#a7c8dc"))
	text_at("本地单人 · 键盘操作 · MVP 0.4",Vector2(95,619),17,CYAN)
	var idle: Array = hero_frames.get("idle",[])
	if not idle.is_empty(): draw_texture_rect(idle[int(clock_time*5)%idle.size()],Rect2(240,232,315,315),false)
	panel(Rect2(790,165,390,451),Color(0.02,0.055,0.11,0.95),Color("#356d86"))
	text_at("行动简报",Vector2(821,211),25,CYAN)
	text_at("运输与安保机械失控。",Vector2(821,259),21)
	text_at("穿过货运封锁，找到维修员，",Vector2(821,295),21)
	text_at("击败港卫，切断中继器。",Vector2(821,331),21)
	text_at("银翼已就绪。",Vector2(821,388),22,CYAN)
	panel(Rect2(820,450,310,58),Color("#087296"),CYAN)
	text_at(("▶ " if menu_cursor==0 else "  ")+"开始行动 / ENTER",Vector2(842,486),22)
	panel(Rect2(820,525,310,48),Color("#102d44"),Color("#356076"))
	text_at(("▶ " if menu_cursor==1 else "  ")+("从维修站继续" if saved_checkpoint>0 else "暂无检查点"),Vector2(842,557),20,WHITE if saved_checkpoint>0 else Color("#638399"))
	if not save_warning.is_empty(): text_at(save_warning,Vector2(64,687),17,ORANGE)

func draw_pause() -> void:
	draw_rect(Rect2(0,0,1280,720),Color(0.01,0.02,0.06,0.73))
	panel(Rect2(377,155,526,411),Color("#0b2137"),CYAN)
	centered("行动暂停",217,34)
	centered("ESC 继续",278,24,CYAN)
	centered("V 声音："+("开" if volume>0 else "关"),329,21)
	centered("H 震屏："+("关" if shake_amount<=0 else ("轻" if shake_amount<=0.4 else "标准")),373,21)
	centered("M 返回标题",425,21)
	centered("存档仅在维修点、通关和设置变更时写入",498,16,Color("#98b5c9"))
	centered("F8 命中特效开关  /  F9 局部顿帧开关",531,16,Color("#98b5c9"))

func draw_result(won: bool) -> void:
	draw_rect(Rect2(0,0,1280,720),Color(0.01,0.03,0.065,0.76))
	panel(Rect2(325,159,630,409),Color("#0b2137"),CYAN if won else ORANGE)
	centered("星港恢复供电" if won else "银翼暂时失去连接",231,36,CYAN if won else ORANGE)
	centered("中继器已关闭。米米：干得漂亮，欢迎回来！" if won else "受击原因："+player.last_cause,285,21)
	centered("用时 %02d:%02d    受击 %d 次    重试 %d 次"%[int(run_time)/60,int(run_time)%60,hits_taken,retries],342,23)
	centered("击破 %d 台机械"%kills,385,20,Color("#aac6da"))
	centered("R / ENTER "+("再次行动" if won else ("从维修站重试" if checkpoint>0 else "从入口重试")),463,24,CYAN)
	centered("M 返回标题",516,19)

func autopilot(dt: float) -> float:
	auto_cooldown -= dt
	if absf(player.position.x-LevelData.NPC_X)<120 and checkpoint==0: interact()
	if absf(player.position.x-CORE_NPC_X)<110 and checkpoint<2: interact()
	var relay_axis: Variant = relays.autoplay_axis(self,dt)
	if relay_axis != null: return float(relay_axis)
	var nearest: StarportEnemy = null
	var distance = 99999.0
	for enemy in enemies:
		if not enemy.dead and absf(enemy.pos.x-player.position.x)<distance:
			nearest=enemy
			distance=absf(enemy.pos.x-player.position.x)
	if nearest==null:
		for obstacle in LevelData.OBSTACLES:
			if player.position.x>obstacle.position.x-70 and player.position.x<obstacle.end.x+10 and player.is_on_floor(): player.begin_action("jump")
		return 1.0
	var direction=signf(nearest.pos.x-player.position.x)
	if distance<185 and player.state in ["idle","run"]: player.facing=int(direction)
	if nearest.kind=="boss":
		for p in projectiles:
			if not p.friendly and p.radius>10 and (p.pos.x-player.position.x)*p.vx<0 and absf(p.pos.x-player.position.x)<155:
				player.begin_action("jump")
		if nearest.state=="windup":
			if nearest.move_name=="wave":
				if nearest.timer<0.20 and distance<200: player.begin_action("jump")
			elif nearest.move_name=="charge":
				if nearest.timer<0.16: player.begin_action("jump")
			elif nearest.timer<0.11:
				player.facing=int(direction)
				player.begin_action("dodge")
			return direction if distance>125 else 0.0
		if nearest.state=="attack":
			return 0.0

	if nearest.state=="windup" and nearest.timer<0.11 and (distance<180 or nearest.kind=="drone"): player.begin_action("dodge")
	if distance<150 and auto_cooldown<=0:
		if nearest.kind=="shield" and nearest.shield>0: player.begin_action("heavy")
		elif player.skill_cd<=0: player.begin_action("skill")
		else: player.begin_action("light")
		auto_cooldown=0.24
	if player.state=="light" and player.elapsed>0.23: player.begin_action("light")
	return direction if distance>115 else 0.0

func capture_frame(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("SCREENSHOT_SAVED "+path)

func run_tests() -> void:
	var tester = load("res://tests/test_suite.gd").new()
	add_child(tester)
	await tester.run(self)

func finish_autoplay(code: int) -> void:
	# Let the death animation and result card appear in QA recordings.
	await get_tree().create_timer(1.4).timeout
	music.stop()
	for audio in audio_pool: audio.stop()
	await get_tree().create_timer(0.15).timeout
	OS.delay_msec(180)
	get_tree().quit(code)

func capture_comparison() -> void:
	await RenderingServer.frame_post_draw
	clock_time = 3.0
	queue_redraw()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(comparison_path)
	print("COMPARE_SAVED "+comparison_path)
	await finish_autoplay(0)

func kick_shake(amount: float) -> void:
	if effects_enabled: shake = maxf(shake,minf(amount,8.0))

func enemy_hit_feedback(enemy: StarportEnemy, damage: int, heavy: bool, source_x: float, serial: int, ranged: bool, blocked: bool, armor_broken: bool, contact_point: Variant = null) -> void:
	var direction = 1.0 if enemy.pos.x>=source_x else -1.0
	var contact: Vector2 = contact_point if contact_point is Vector2 else enemy.pos+Vector2(-direction*28.0,-62.0)
	impact_count += 1
	impact_events.append({"serial":serial,"kind":enemy.kind,"damage":damage,"heavy":heavy,"ranged":ranged,"contact":contact})
	if impact_events.size()>64: impact_events.pop_front()
	if hitstop_enabled:
		var stop_time = 0.060 if armor_broken else (0.025 if blocked else (0.050 if heavy else 0.033))
		enemy.hitstop = maxf(enemy.hitstop,stop_time)
		if not ranged and player.state in ["light","heavy"]:
			player.hitstop = maxf(player.hitstop,stop_time)
	if not effects_enabled: return
	var tint = Color("#ffd88a") if blocked else (Color("#b3f3ff") if heavy else Color("#7cecff"))
	add_sparks(contact,tint,26 if armor_broken else (20 if heavy else (6 if blocked else 10)))
	float_text(contact+Vector2(-8,-45),str(damage),Color("#fff3cc") if blocked else WHITE)
	kick_shake(6.0 if armor_broken else (1.5 if blocked else (5.0 if heavy else 2.5)))
	sfx("armor_break" if armor_broken else ("armor_hit" if blocked else ("hit_heavy" if heavy else "hit_light")))

# The attack reach and player timings remain unchanged. Only the boss uses
# pose-matched anatomy instead of testing the distance between two foot roots.
func melee_attack_polygon(kind: String, origin: Variant = null, facing: int = 0) -> PackedVector2Array:
	var at: Vector2 = player.position if origin == null else origin
	var direction: int = player.facing if facing == 0 else facing
	var reach: float = 145.0 if kind=="light" else 175.0
	var shape = PackedVector2Array()
	for point in [Vector2(-24,-110),Vector2(reach,-110),Vector2(reach,-20),Vector2(-24,-20)]:
		shape.append(at+Vector2(point.x*direction,point.y))
	return shape

func boss_body_polygons(enemy: StarportEnemy) -> Array:
	var result: Array = []
	if enemy.dead or boss_hurt_regions.is_empty(): return result
	var pose = enemy_animation_pose(enemy)
	var frames: Array = boss_hurt_regions.frames.get(pose.action,[])
	if frames.is_empty(): return result
	var data: Dictionary = frames[clampi(pose.frame,0,frames.size()-1)]
	var scale_factor: float = 265.0/float(enemy_animation_meta.boss.native_body_height)
	for points in data.polygons:
		var polygon = PackedVector2Array()
		for point in points:
			polygon.append(enemy.pos+Vector2((float(point[0])-384.0)*-enemy.facing,float(point[1])-710.0)*scale_factor)
		result.append(polygon)
	return result

func boss_attack_contact(enemy: StarportEnemy, attack: PackedVector2Array, source: Vector2) -> Variant:
	var closest: Variant = null
	var distance: float = INF
	for body in boss_body_polygons(enemy):
		for overlap in Geometry2D.intersect_polygons(attack,body):
			if overlap.size()<3: continue
			# All authored anatomy regions are convex; an intersection remains convex.
			# A point on its near boundary belongs to both blade and anatomy.
			for i in overlap.size():
				var point: Vector2 = Geometry2D.get_closest_point_to_segment(source,overlap[i],overlap[(i+1)%overlap.size()])
				if point.distance_squared_to(source)<distance:
					closest = point
					distance = point.distance_squared_to(source)
	return closest
