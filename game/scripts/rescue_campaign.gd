extends "res://scripts/mobile_game.gd"
const FurnaceScript=preload("res://scripts/furnace_level.gd")
const ExosuitScript=preload("res://scripts/firepower_exosuit.gd")
const RescuePlayerScript=preload("res://scripts/rescue_player.gd")
const RescueInventoryScript=preload("res://scripts/rescue_inventory.gd")
const FurnaceBossScript=preload("res://scripts/furnace_boss.gd")
const RescueTouchScript=preload("res://scripts/rescue_touch_controls.gd")
const SAVE_V07="user://starport_save_v07.json"
var furnace=FurnaceScript.new()
var exosuit=ExosuitScript.new()
var feiren_unlocked:bool=false
var selected_character:String="silverwing"
var saved_has_run:bool=false
var spent_pods:Array[String]=[]
var furnace_checkpoint_snapshot:Dictionary={}
var saved_furnace_snapshot:Dictionary={}
var character_frames:Dictionary={}
var furnace_props:Dictionary={}
var stage_floors:Dictionary={}
var unlock_events:int=0
var qa_without_exosuit:bool=false
var auto_climb_enemy:int=0
var auto_climb_index:int=0
var focus_input_blocked:bool=false
func _ready()->void:
 inventory=RescueInventoryScript.new();best_times["3"]=0.0
 for arg in OS.get_cmdline_user_args():
  if arg=="--level=3":selected_level=3;level_id=3
  if arg=="--no-exosuit":qa_without_exosuit=true
 super._ready()
 var parent=touch_ui.get_parent();var was_enabled:bool=touch_ui.enabled
 touch_ui.free();touch_ui=RescueTouchScript.new();parent.add_child(touch_ui);touch_ui.configure(self);touch_ui.set_enabled(was_enabled)
 if "--character=feiren" in OS.get_cmdline_user_args() and feiren_unlocked:selected_character="feiren"
 apply_character()
func _notification(what:int)->void:
 super._notification(what)
 if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_APPLICATION_PAUSED,NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
  clear_touch();focus_input_blocked=true
  if mode=="play":paused=true
func movement_axis()->float:
 if focus_input_blocked:
  if absf(Input.get_axis("left","right"))<.01:focus_input_blocked=false
  return 0.0
 return super.movement_axis()
func load_assets()->void:
 super.load_assets()
 character_frames.silverwing=hero_frames.duplicate(true)
 var groups:Dictionary={}
 for state in ["idle","run","jump","attack1","attack2","attack3","heavy","dodge","skill","hurt","death","rescue"]:
  var directory="res://assets/hero/feiren/"+state+"/";var group:Array=[]
  if DirAccess.dir_exists_absolute(directory):
   var files=ResourceLoader.list_directory(directory);files.sort()
   for file in files:
    if file.ends_with(".webp") or file.ends_with(".png"):group.append(load(directory+file))
  if not group.is_empty():groups[state]=group
 character_frames.feiren=groups
 stage_floors[1]=floor_tex;stage_floors[2]=floor_tex
 var base="res://assets/environment/furnace/"
 if FileAccess.file_exists(base+"manifest.json"):
  var meta:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(base+"manifest.json"));var layers:Array=[]
  for data in meta.layers:
   var c:Array=data.draw_tint
   layers.append({"id":data.id,"texture":load(base+str(data.path).get_file()),"factor":float(data.camera_scroll_scale),"width":float(data.size[0]),"height":float(data.size[1]),"y":float(data.draw_origin[1]),"repeat":bool(data.repeat),"foreground":data.id=="foreground","tint":Color(c[0],c[1],c[2],c[3])})
  stage_art[3]=layers
 for entry in [["floor","platform-furnace-strip.webp"],["rescue","rescue-restraint-terminal.webp"]]:
  if ResourceLoader.exists(base+entry[1]):furnace_props[entry[0]]=load(base+entry[1])
 stage_floors[3]=furnace_props.get("floor",floor_tex)
 exosuit.load_assets()
func make_world()->void:
 super.make_world();player.free();player=RescuePlayerScript.new();add_child(player);player.setup(self);player.reset_at(Vector2(210,FLOOR-2))
func rebuild_geometry()->void:
 if level_id!=3:super.rebuild_geometry();return
 for child in world_geometry.get_children():child.free()
 for r in [Rect2(-200,FLOOR,WORLD_END+400,180)]+FurnaceScript.SOLIDS+FurnaceScript.PLATFORMS:
  var body=StaticBody2D.new();var collider=CollisionShape2D.new();var shape=RectangleShape2D.new()
  shape.size=r.size;collider.shape=shape;collider.position=r.position+r.size*.5
  if r in FurnaceScript.PLATFORMS:collider.one_way_collision=true;collider.one_way_collision_margin=8
  body.add_child(collider);world_geometry.add_child(body)
func apply_character()->void:
 if selected_character=="feiren" and not feiren_unlocked:selected_character="silverwing"
 var frames:Dictionary=character_frames.get(selected_character,{})
 if not frames.is_empty():hero_frames=frames
 else:hero_frames=character_frames.get("silverwing",hero_frames)
func choose_character(id:String)->bool:
 if mode!="menu" or id not in ["silverwing","feiren"]:return false
 if id=="feiren" and not feiren_unlocked:show_status("第三关救出绯刃后解锁。",2);return false
 clear_touch();selected_character=id;apply_character();save_game();sfx("ui");return true
func character_name()->String:return "绯刃" if selected_character=="feiren" else "银翼"
func can_continue()->bool:return saved_has_run or saved_checkpoint>0
func apply_level(id:int)->void:
 if id!=3:
  super.apply_level(id);floor_tex=stage_floors.get(id,stage_floors[1]);return
 level_id=3;zones=FurnaceScript.zones();rebuild_geometry();parallax_layers=stage_art.get(3,stage_art[1]).duplicate(true)
 enemy_animations.boss=boss_art[1].animations;enemy_animation_meta.boss=boss_art[1].meta;boss_hurt_regions=boss_art[1].hurt
 floor_tex=stage_floors.get(3,stage_floors[1]);best_time=float(best_times.get("3",0))
func start_run(resume:bool)->void:
 var target:int=saved_level_id if resume else selected_level
 exosuit.reset(self)
 if target==3:
  furnace.reset()
  if not resume:spent_pods.clear()
 super.start_run(resume);apply_character()
 if level_id==1 and selected_character=="feiren":status=status.replace("银翼上线","绯刃上线")
 if level_id==3:
  if resume and not saved_furnace_snapshot.is_empty():restore_furnace_snapshot(saved_furnace_snapshot)
  furnace_checkpoint_snapshot=furnace_snapshot()
  if not resume:
   checkpoint=0;saved_checkpoint=0;saved_level_id=3;saved_has_run=true;saved_furnace_snapshot=furnace_checkpoint_snapshot.duplicate(true);save_game()
  show_status("米米：绯刃的信号在赤炉拘束舱。借助外骨骼，切断电源后救她出来。" if not feiren_unlocked else "赤炉行动重启。绯刃已解锁，检查点保留本次装甲消耗。",6)
func retry_checkpoint()->void:
 var used:Array[String]=spent_pods.duplicate();exosuit.reset(self)
 super.retry_checkpoint()
 if level_id==3:
  restore_furnace_snapshot(furnace_checkpoint_snapshot)
  for id in used:
   if not id in spent_pods:spent_pods.append(id)
  save_game();show_status("检查点恢复。已消耗装甲保持失效，不会补耐久或动力。",4)
func clear_combat()->void:
 if exosuit:exosuit.reset(self)
 super.clear_combat()
 if furnace:furnace.mortars.clear()
func clear_touch()->void:
 super.clear_touch()
 if exosuit:exosuit.fire_armed=false
func checkpoint_zone_ids()->Array:return furnace.checkpoint_zones(checkpoint) if level_id==3 else super.checkpoint_zone_ids()
func checkpoint_spawn_x()->float:return float(FurnaceScript.SPAWNS[clampi(checkpoint,0,2)]) if level_id==3 else super.checkpoint_spawn_x()
func right_bound()->float:
 if level_id!=3:return super.right_bound()
 return furnace.right_bound(float(zones[active_zone].right)-25 if active_zone>=0 else WORLD_END-35,self)
func spawn_wave(wave:Array)->void:
 if level_id!=3:super.spawn_wave(wave);return
 for entry in wave:
  var at=Vector2(entry[1],entry[2] if entry.size()>2 else FLOOR)
  var enemy=FurnaceBossScript.new(entry[0],at) if entry[0]=="boss" else EnemyScript.new(entry[0],at)
  enemy.attach_physics(self);enemies.append(enemy)
func _physics_process(dt:float)->void:
 super._physics_process(dt)
 if level_id==3 and mode=="play" and not paused and not test_mode:
  exosuit.tick(dt,self);inventory.tick(dt,self)
  if active_zone==zones.size()-1 and alive_count()==0:update_zones()
  if mode=="play":furnace.tick(dt,self)
  queue_redraw()
func interact()->void:
 if level_id==3:
  if mode=="play" and not paused:furnace.interact(self)
 else:super.interact()
func activate_third_checkpoint(id:int)->void:
 if exosuit.active:exosuit.exit(self,"manual")
 checkpoint=id;saved_checkpoint=id;saved_level_id=3;saved_has_run=true
 player.hp=100;player.skill_cd=0;furnace_checkpoint_snapshot=furnace_snapshot();saved_furnace_snapshot=furnace_checkpoint_snapshot.duplicate(true)
 dialogue_timer=6;save_game();sfx("checkpoint");show_status("维修点已记录。生命恢复；已消耗装甲不会重新充能。",4)
 print("FURNACE_CHECKPOINT ",id," t=",run_time," spent=",spent_pods)
func rescue_feiren()->void:
 if level_id!=3 or mode!="play" or paused or exosuit.active:return
 if not "restraint_a" in furnace.opened or not "restraint_b" in furnace.opened:return
 if absf(player.position.x-FurnaceScript.RESCUE_X)>115 or absf(player.position.y-FLOOR)>32:return
 if not feiren_unlocked:
  feiren_unlocked=true;unlock_events+=1;sfx("win");add_sparks(Vector2(FurnaceScript.RESCUE_X,FLOOR-130),ORANGE,28);print("FEIREN_UNLOCK t=",run_time)
  show_status("绯刃：热刃已恢复！多谢你，撤离后我来接替。绯刃已永久解锁。",7)
 activate_third_checkpoint(2)
 show_status("绯刃：热刃恢复！多谢，先突破撤离口。绯刃已永久解锁，返回选关可换人！",7)
func furnace_snapshot()->Dictionary:return {"machines":furnace.snapshot(),"inventory":inventory.snapshot()}
func valid_furnace_snapshot(data:Variant,cp:int,unlocked:bool)->bool:
 if not data is Dictionary or not furnace.valid_snapshot(data.get("machines")) or not data.get("inventory") is Dictionary:return false
 var probe=RescueInventoryScript.new()
 if not probe.restore(data.inventory):return false
 var allowed:Array=[]
 for item in FurnaceScript.PICKUPS:allowed.append(item.id)
 for id in data.inventory.collected:
  if not id in allowed:return false
 if cp>=1 and not "freight" in data.machines.opened:return false
 if cp>=2 and (not unlocked or not "restraint_a" in data.machines.opened or not "restraint_b" in data.machines.opened):return false
 return true
func restore_furnace_snapshot(data:Dictionary)->bool:
 if not valid_furnace_snapshot(data,checkpoint,feiren_unlocked):return false
 furnace.restore(data.machines);inventory.restore(data.inventory);return true
func save_game()->void:
 if saved_checkpoint>0:saved_has_run=true
 if mode=="win":saved_has_run=false
 var data={"version":3,"unlocked_feiren":feiren_unlocked,"character":selected_character,"has_run":saved_has_run,"saved_level":saved_level_id,"checkpoint":saved_checkpoint,"second_snapshot":saved_second_snapshot,"furnace_snapshot":saved_furnace_snapshot,"spent_pods":spent_pods,"completed_levels":completed_levels,"best_times":best_times,"volume":volume,"shake":shake_amount}
 var file=FileAccess.open(SAVE_V07+".tmp",FileAccess.WRITE)
 if not file:save_warning="保存失败；本次仍可继续，解锁可能无法保留。";return
 file.store_string(JSON.stringify(data));file.flush();file.close()
 if FileAccess.file_exists(SAVE_V07):DirAccess.copy_absolute(SAVE_V07,SAVE_V07+".bak")
 if DirAccess.rename_absolute(SAVE_V07+".tmp",SAVE_V07)!=OK:save_warning="保存失败，请保留当前游戏。"
func valid_rescue_save(data:Variant)->bool:
 if not data is Dictionary or not integral(data.get("version"),3,3) or not integral(data.get("saved_level"),1,3) or not integral(data.get("checkpoint"),0,2):return false
 if not data.get("unlocked_feiren") is bool or not data.get("has_run") is bool:return false
 if data.get("character") not in ["silverwing","feiren"] or (data.character=="feiren" and not data.unlocked_feiren):return false
 for key in ["volume","shake"]:
  if not typeof(data.get(key)) in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(data[key])) or float(data[key])<0 or float(data[key])>1:return false
 if not data.get("best_times") is Dictionary or not data.get("completed_levels") is Array or not data.get("spent_pods") is Array:return false
 for key in ["1","2","3"]:
  if not typeof(data.best_times.get(key)) in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(data.best_times[key])) or float(data.best_times[key])<0:return false
 if data.completed_levels.size()>3 or data.spent_pods.size()>2:return false
 if not data.has_run and int(data.checkpoint)>0:return false
 var seen:Dictionary={}
 for id in data.completed_levels:
  if not integral(id,1,3) or seen.has(int(id)):return false
  seen[int(id)]=true
 seen.clear()
 for id in data.spent_pods:
  if seen.has(id):return false
  seen[id]=true
 for id in data.completed_levels:
  if not integral(id,1,3):return false
 for id in data.spent_pods:
  if not id is String or id not in ["dock","rescue"]:return false
 if not data.get("second_snapshot") is Dictionary or not data.get("furnace_snapshot") is Dictionary:return false
 if int(data.saved_level)==2 and int(data.checkpoint)>0 and not valid_second_snapshot(data.second_snapshot,int(data.checkpoint)):return false
 if int(data.saved_level)==3 and (data.has_run or int(data.checkpoint)>0) and not valid_furnace_snapshot(data.furnace_snapshot,int(data.checkpoint),data.unlocked_feiren):return false
 return true
func load_save()->void:
 var data:Variant=read_saved_json(SAVE_V07)
 if not valid_rescue_save(data) and FileAccess.file_exists(SAVE_V07+".bak"):data=read_saved_json(SAVE_V07+".bak")
 if valid_rescue_save(data):
  feiren_unlocked=data.unlocked_feiren;selected_character=data.character;saved_has_run=data.has_run
  saved_level_id=int(data.saved_level);saved_checkpoint=int(data.checkpoint);saved_second_snapshot=data.second_snapshot.duplicate(true);saved_furnace_snapshot=data.furnace_snapshot.duplicate(true)
  spent_pods.clear()
  for id in data.spent_pods:
   if not id in spent_pods:spent_pods.append(id)
  completed_levels.clear()
  for id in data.completed_levels:completed_levels.append(int(id))
  best_times=data.best_times.duplicate(true);volume=data.volume;shake_amount=data.shake
  AudioServer.set_bus_volume_db(0,linear_to_db(maxf(volume,.0001)));return
 super.load_save()
 best_times["3"]=0.0;feiren_unlocked=false;selected_character="silverwing";saved_has_run=saved_checkpoint>0
 if FileAccess.file_exists(CAMPAIGN_SAVE) or FileAccess.file_exists(SAVE_PATH):save_game()
func on_player_death()->void:
 if exosuit.active:exosuit.exit(self,"damage")
 super.on_player_death()
 if level_id==3:save_game()
func victory()->void:
 if exosuit.active:exosuit.exit(self,"manual")
 clear_touch();super.victory()
func player_body_rect()->Rect2:
 return Rect2(player.position+Vector2(-46,-146),Vector2(92,146)) if exosuit.active else Rect2(player.position+Vector2(-20,-94),Vector2(40,94))
func enemy_attack_contact(enemy,shape:PackedVector2Array,source:Vector2)->Variant:
 if enemy.kind=="boss":return boss_attack_contact(enemy,shape,source)
 var r=Rect2(enemy.pos+Vector2(-27,-100 if enemy.kind!="drone" else -65),Vector2(54,100 if enemy.kind!="drone" else 65))
 var body=PackedVector2Array([r.position,Vector2(r.end.x,r.position.y),r.end,Vector2(r.position.x,r.end.y)])
 var contacts=Geometry2D.intersect_polygons(shape,body)
 return null if contacts.is_empty() else Geometry2D.get_closest_point_to_segment(source,contacts[0][0],contacts[0][1])
func radial_damage(point:Vector2,radius:float,damage:int,serial:int,heavy:bool)->void:
 var shape=PackedVector2Array()
 for i in 24:shape.append(point+Vector2.from_angle(TAU*i/24.0)*radius)
 for enemy in enemies:
  if enemy.dead:continue
  var hit:Variant=enemy_attack_contact(enemy,shape,point)
  if hit!=null:enemy.hit(damage,heavy,point.x,serial,self,true,hit)
func damage_from_bomb(point:Vector2,radius:float,damage:int,serial:int)->void:
 if level_id!=3:super.damage_from_bomb(point,radius,damage,serial)
 elif mode=="play" and not paused:radial_damage(point,radius,damage,serial,true)
func player_strike(kind:String,combo:int,serial:int,first_active_tick:bool=true)->void:
 if kind=="skill" and selected_character=="feiren" and not exosuit.active:
  if player.hp<=0 or mode!="play":return
  var shape=melee_attack_polygon("heavy")
  for enemy in enemies:
   if enemy.dead:continue
   var contact:Variant=enemy_attack_contact(enemy,shape,player.position+Vector2(0,-65))
   if contact!=null:enemy.hit(42,true,player.position.x,serial,self,false,contact)
  if first_active_tick:add_sparks(player.position+Vector2(player.facing*70,-65),Color("#ffb54e"),22);sfx("heavy")
  return
 super.player_strike(kind,combo,serial,first_active_tick)
func _unhandled_input(event:InputEvent)->void:
 if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_A,KEY_D,KEY_LEFT,KEY_RIGHT]:focus_input_blocked=false
 if mode=="menu":
  if event is InputEventKey and event.pressed and not event.echo:
   if event.keycode==KEY_F7:super._unhandled_input(event);return
   if event.keycode in [KEY_A,KEY_D,KEY_LEFT,KEY_RIGHT,KEY_TAB]:choose_character("feiren" if selected_character=="silverwing" else "silverwing")
   if event.keycode in [KEY_DOWN,KEY_S]:menu_cursor=(menu_cursor+1)%4
   if event.keycode in [KEY_UP,KEY_W]:menu_cursor=posmod(menu_cursor-1,4)
   if event.keycode in [KEY_1,KEY_2,KEY_3]:menu_cursor=event.keycode-KEY_1
   if event.keycode in [KEY_ENTER,KEY_SPACE]:menu_launch()
  elif event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
   for i in 4:
    if Rect2(818,236+i*84,382,66).has_point(event.position):menu_cursor=i;menu_launch()
   if Rect2(74,238,175,58).has_point(event.position):choose_character("silverwing")
   if Rect2(266,238,175,58).has_point(event.position):choose_character("feiren")
  return
 if event is InputEventKey and event.pressed and not event.echo:
  if mode=="win" and event.keycode==KEY_ENTER and level_id<3:selected_level=level_id+1;start_run(false);return
  if mode=="play" and not paused and event.keycode in [KEY_1,KEY_2,KEY_3] and level_id==3:inventory.use_item(["bomb","armor","repair"][event.keycode-KEY_1],self);return
 super._unhandled_input(event)
func menu_launch()->void:
 if menu_cursor==3:
  if can_continue():start_run(true)
 else:selected_level=menu_cursor+1;start_run(false)
func touch_command(id:String)->bool:
 if not touch_ui or not touch_ui.enabled:return false
 if mode=="menu":
  if id in ["silverwing","feiren"]:return choose_character(id)
  if id in ["stage1","stage2","stage3"]:selected_level=int(id.right(1));start_run(false);return true
  if id=="continue" and can_continue():start_run(true);return true
  return false
 if mode=="win" and id=="next" and level_id<3 and victory_elapsed>=.72:selected_level=level_id+1;start_run(false);return true
 if id in ["bomb","armor","repair"] and level_id==3 and mode=="play" and not paused:return inventory.use_item(id,self)
 return super.touch_command(id)
func draw_world()->void:
 if level_id==3:furnace.draw_world(self)
 else:super.draw_world()
func draw_effects()->void:
 super.draw_effects()
 if level_id==3:inventory.draw_world(self);exosuit.draw(self)
func draw_feiren_npc(at:Vector2)->void:
 var group:Array=character_frames.feiren.get("rescue",character_frames.feiren.get("idle",[]))
 if not group.is_empty():draw_texture_rect(group[0],sprite_rect_for(at,Vector2(264,264),474*264.0/512.0,1),false)
func draw_hero()->void:
 if exosuit.active:exosuit.draw_at(self,player.position,player.facing,exosuit.current_action(self),exosuit.anim_time if exosuit.current_action(self) not in ["walk","idle"] else clock_time,true);return
 if selected_character!="feiren":super.draw_hero();return
 var state:String="attack"+str(player.combo) if player.state=="light" else ("jump" if player.state=="air" else player.state)
 if state=="dead":state="death"
 var group:Array=hero_frames.get(state,hero_frames.get("idle",[]))
 if group.is_empty():return
 var index:int=int(clock_time*(9 if state=="run" else 3))%group.size()
 if state not in ["idle","run"]:index=mini(int(player.elapsed*7),group.size()-1)
 if state=="idle":index=1 if group.size()>1 and fposmod(clock_time,2.8)>=2.68 else 0
 elif state=="attack1":index=mini(1 if player.elapsed>=.10 else 0,group.size()-1)
 elif state=="heavy":index=mini(1 if player.elapsed>=.30 else 0,group.size()-1)
 elif state=="skill":index=mini(0 if player.elapsed<.10 else (1 if player.elapsed<.40 else 2),group.size()-1)
 elif state=="jump":index=mini(0 if player.velocity.y< -300 else (1 if player.velocity.y< -80 else (2 if player.velocity.y<80 else (3 if player.velocity.y<330 else 4))),group.size()-1)
 var alpha:float=.55 if player.is_invulnerable() and int(clock_time*20)%2==0 else 1.0
 draw_circle(player.position+Vector2(0,1),35,Color(.08,.025,.015,.3))
 if player.state in ["dodge","skill"]:
  for i in [3,2,1]:draw_texture_rect(group[index],sprite_rect_for(player.position+Vector2(-player.facing*i*23,0),Vector2(264,264),474*264.0/512.0,player.facing),false,Color(1,.35,.12,.10+i*.025))
 draw_texture_rect(group[index],sprite_rect_for(player.position,Vector2(264,264),474*264.0/512.0,player.facing),false,Color(1,.7,.6,alpha) if player.state=="hurt" else Color(1,1,1,alpha))
func draw_enemy(enemy:StarportEnemy)->void:
 if level_id!=3 or enemy.kind!="boss":super.draw_enemy(enemy);return
 if enemy.dead and enemy.death_timer>.72:return
 var pose=enemy_animation_pose(enemy);var group:Array=enemy_animations.boss[pose.action];var meta:Dictionary=enemy_animation_meta.boss
 var factor:float=265.0/float(meta.native_body_height)
 draw_texture_rect(group[clampi(pose.frame,0,group.size()-1)],sprite_rect_for(enemy.pos,Vector2(meta.frame_size[0],meta.frame_size[1])*factor,meta.root[1]*factor,-enemy.facing),false,Color(1,.84,.68,clampf((.72-enemy.death_timer)/.2,0,1) if enemy.dead else 1))
 if enemy.state=="windup":
  text_at("!",enemy.pos+Vector2(-7,-282),30,ORANGE)
  if enemy.move_name=="charge":
   for x in [enemy.locked_x-115,enemy.locked_x+115]:draw_rect(Rect2(x-58,FLOOR-105,116,105),Color(1,.48,.12,.16));draw_rect(Rect2(x-58,FLOOR-105,116,105),ORANGE,false,2)
  elif enemy.move_name=="sweep":draw_line(enemy.pos+Vector2(0,-5),enemy.pos+Vector2(enemy.facing*185,-5),ORANGE,8)
func draw_menu()->void:
 if touch_ui and touch_ui.enabled:return
 draw_rect(Rect2(0,0,1280,720),Color(.02,.018,.028,.78));panel(Rect2(42,46,1196,628),Color("#181b29"),Color("#c69772"))
 text_at("星港机甲小队",Vector2(74,123),46,Color("#ffd2a2"));text_at("第三行动 · 赤炉救援",Vector2(76,171),27)
 for item in [["silverwing","银翼",74],["feiren","绯刃" if feiren_unlocked else "绯刃 · 待救援",266]]:
  var rect=Rect2(item[2],238,175,58);panel(rect,Color("#794e35") if selected_character==item[0] else Color("#28303a"));text_at(item[1],rect.position+Vector2(17,36),21)
 var group:Array=hero_frames.get("idle",[])
 if not group.is_empty():draw_texture_rect(group[0],Rect2(175,293,310,310),false)
 text_at("← → / TAB 选人 · 1 / 2 / 3 选关",Vector2(74,625),18,Color("#d4b79c"));text_at("MVP 0.9 · F7 触控预览",Vector2(74,655),17,ORANGE)
 var labels=["第一关 · 失控星港","第二关 · 冷却环线","第三关 · 赤炉救援","继续第%d关维修点"%saved_level_id if can_continue() else "暂无检查点"]
 for i in 4:
  var rect=Rect2(818,236+i*84,382,66);panel(rect,Color("#80502f") if menu_cursor==i else Color("#28303a"),ORANGE if menu_cursor==i else Color("#6b6962"));text_at(labels[i],rect.position+Vector2(25,41),22)
 if status_timer>0:text_at(status,Vector2(70,211),17,ORANGE)
func draw_hud()->void:
 if touch_ui and touch_ui.enabled:return
 if level_id!=3:
  super.draw_hud()
  panel(Rect2(24,22,390,111),Color("#091726"))
  var tone:Color=ORANGE if selected_character=="feiren" else CYAN
  text_at(character_name()+" / "+("FEIREN" if selected_character=="feiren" else "SILVERWING"),Vector2(43,51),22,tone)
  bar(Rect2(43,66,274,15),player.hp/100.0,tone);text_at("%d / 100"%player.hp,Vector2(329,80),16)
  text_at("U "+("焰冲" if selected_character=="feiren" else "磁轨斩"),Vector2(43,112),16,tone)
  bar(Rect2(129,102,123,6),1-player.skill_cd/8,tone)
  text_at("就绪" if player.skill_cd<=0 else "%.1fs"%player.skill_cd,Vector2(263,113),15,tone)
  text_at("闪避 "+("就绪" if player.dodge_cd<=0 else "%.1fs"%player.dodge_cd),Vector2(322,112),14)
  panel(Rect2(1181,633,75,27),Color("#102936"));text_at("v0.9",Vector2(1194,653),14,CYAN)
  panel(Rect2(24,665,1232,38),Color("#091726"))
  text_at("A/D移动 · SPACE跳 · J连击 · K重击 · L闪避 · U"+("焰冲" if selected_character=="feiren" else "磁轨")+" · E交互"+(" · 1炸弹 · 2护甲 · 3维修" if level_id==2 else "")+" · ESC暂停",Vector2(43,690),17)
  return
 panel(Rect2(24,22,322,100));text_at(character_name()+" / 赤炉救援",Vector2(42,50),22,ORANGE);bar(Rect2(42,66,250,13),player.hp/100.0,ORANGE);text_at("%d / 100"%player.hp,Vector2(240,107),17)
 text_at("%02d:%02d 受击%d 重试%d"%[int(run_time)/60,int(run_time)%60,hits_taken,retries],Vector2(40,107),16)
 panel(Rect2(919,22,337,85));text_at("03 赤炉救援",Vector2(940,52),24,ORANGE);text_at("绯刃已解锁" if feiren_unlocked else "目标：解救绯刃",Vector2(940,85),19)
 inventory.draw_hud(self)
 panel(Rect2(762,602,494,55))
 var a:float=exosuit.heavy_cd if exosuit.active else player.skill_cd
 var b:float=exosuit.shock_cd if exosuit.active else player.dodge_cd
 text_at(("重炮 " if exosuit.active else ("焰冲 " if selected_character=="feiren" else "磁轨 "))+("就绪" if a<=0 else "%.1fs"%a),Vector2(780,635),19,ORANGE)
 text_at(("震荡 " if exosuit.active else "闪避 ")+("就绪" if b<=0 else "%.1fs"%b),Vector2(1018,635),19,ORANGE)
 var info=furnace.objective_hint(self)
 for enemy in enemies:
  if enemy.kind=="boss" and not enemy.dead:
   panel(Rect2(365,214,550,50));bar(Rect2(385,249,510,8),float(enemy.hp)/enemy.max_hp,ORANGE);centered("赤炉撤离守卫",236,18,ORANGE)
   var hint:Dictionary=enemy.boss_wave_hint(self);info=hint.text if not hint.text.is_empty() else ("冷却中 · 靠近反击" if enemy.state=="recover" else "观察起手，避开横扫")
 if not info.is_empty():
  panel(Rect2(373,22,518,120))
  for row in range(mini(4,int(ceil(info.length()/27.0)))):text_at(info.substr(row*27,27),Vector2(389,50+26*row),17,ORANGE)
 if exosuit.active:draw_exosuit_hud()
 panel(Rect2(24,665,1232,38));text_at("A/D移动 · SPACE跳跃 · J攻击/连射 · K重击/重炮 · U技能/震荡 · L闪避 · E交互/退出装甲 · ESC暂停",Vector2(37,690),16)
 if status_timer>0:panel(Rect2(300,148,680,44));centered(status.substr(0,38),169,16,ORANGE);centered(status.substr(38,38),187,16,ORANGE)
func draw_exosuit_hud()->void:
 panel(Rect2(373,22,518,120),Color("#251e1b"),ORANGE)
 text_at("赤隼  耐久 %d/%d"%[exosuit.durability,exosuit.MAX_DURABILITY],Vector2(392,57),19,ORANGE)
 text_at("动力 %.1fs"%exosuit.remaining,Vector2(708,57),19)
 bar(Rect2(392,82,214,11),float(exosuit.durability)/exosuit.MAX_DURABILITY,ORANGE);bar(Rect2(650,82,211,11),exosuit.remaining/30.0,Color("#ffe9ad"))
func draw_pause()->void:
 super.draw_pause()
 if not (touch_ui and touch_ui.enabled) and not qa_clear_pause:
  draw_rect(Rect2(405,478,470,29),Color("#0b2137"))
  centered("同伴与装甲消耗即时保存；维修点记录战斗进度",498,16,Color("#98b5c9"))
func draw_result(won:bool)->void:
 if touch_ui and touch_ui.enabled:return
 if not won:
  super.draw_result(false)
  draw_rect(Rect2(360,187,560,60),Color("#0b2137"))
  centered(character_name()+"暂时失去连接",231,36,ORANGE)
  return
 draw_rect(Rect2(0,0,1280,720),Color(.035,.02,.03,.8));panel(Rect2(280,150,720,455),Color("#281f24"),ORANGE)
 centered("赤炉救援完成" if level_id==3 else "本关行动完成",222,35,ORANGE)
 centered("绯刃已永久解锁，可在选关处更换角色。" if level_id==3 else "下一关已就绪，继续星港行动。",285,23)
 centered("用时 %02d:%02d · 受击%d · 重试%d"%[int(run_time)/60,int(run_time)%60,hits_taken,retries],343,23)
 centered("ENTER 进入下一关" if level_id<3 else "ENTER / R 重玩第三关",442,25,ORANGE);centered("M 返回选关 · R 重玩本关",512,21)
func autopilot(dt:float)->float:
 if level_id!=3:return super.autopilot(dt)
 auto_cooldown-=dt
 if not qa_without_exosuit and not exosuit.active:
  for pod in FurnaceScript.PODS:
   if pod.id not in spent_pods and absf(player.position.x-pod.x)<65 and player.is_on_floor() and player.state in ["idle","run"]:interact();return 0
 if active_zone<0:
  if checkpoint<1 and absf(player.position.x-5630)<90 and player.is_on_floor():
   if exosuit.active:exosuit.exit(self,"manual")
   interact();return 0
  if absf(player.position.x-FurnaceScript.RESCUE_X)<70 and checkpoint<2 and player.is_on_floor():
   if exosuit.active:exosuit.exit(self,"manual")
   interact();return 0
 var nearest=null;var distance:float=INF
 for enemy in enemies:
  if not enemy.dead and absf(enemy.pos.x-player.position.x)<distance:nearest=enemy;distance=absf(enemy.pos.x-player.position.x)
 if nearest==null:
  for item in FurnaceScript.SWITCHES:
   if not completed_zones.has(item.after) or item.id in furnace.opened:continue
   if furnace.nav_switch!=item.id:furnace.nav_switch=item.id;furnace.nav_index=0
   var route:Array=item.route;var target:Vector2=route[mini(furnace.nav_index,route.size()-1)]
   if absf(player.position.x-target.x)<26 and (player.position.y<=target.y+23 if furnace.nav_index<route.size()-1 else absf(player.position.y-target.y)<23) and player.is_on_floor():
    furnace.nav_index+=1
    if furnace.nav_index>=route.size():
     if exosuit.active:exosuit.exit(self,"manual")
     interact();return 0
    target=route[furnace.nav_index]
   var dx:float=target.x-player.position.x
   if player.is_on_floor() and target.y<player.position.y-14 and absf(dx)<153:player.begin_action("jump")
   for r in FurnaceScript.SOLIDS:
    if player.is_on_floor() and dx>0 and player.position.x>r.position.x-78 and player.position.x<r.end.x+8:player.begin_action("jump")
   return signf(dx) if absf(dx)>12 else 0
  if player.is_on_floor():
   for r in FurnaceScript.SOLIDS:
    if player.position.x>r.position.x-75 and player.position.x<r.end.x+10:player.begin_action("jump")
  return 1.0
 var direction:float=signf(nearest.pos.x-player.position.x)
 if player.state in ["idle","run"]:player.facing=int(direction)
 if nearest.kind=="boss":
  var cue:Dictionary=nearest.boss_wave_hint(self)
  if cue.stage=="jump":player.begin_action("jump")
  if nearest.move_name=="charge" and nearest.state in ["windup","attack"]:
   for x in [nearest.locked_x-115,nearest.locked_x+115]:
    if absf(player.position.x-x)<105:return -direction
   return 0
  if nearest.state=="windup" and nearest.move_name=="sweep":
   if nearest.timer<.16 and distance<200:player.begin_action("dodge")
   return direction if distance>250 else 0
 if nearest.pos.y<player.position.y-105:
  if exosuit.active:exosuit.exit(self,"manual")
  var route:Array=[Vector2(6368,510),Vector2(6490,432),Vector2(6720,354)] if nearest.pos.x<7500 else [Vector2(7610,510),Vector2(7810,420)]
  if auto_climb_enemy!=nearest.get_instance_id():auto_climb_enemy=nearest.get_instance_id();auto_climb_index=0
  var target:Vector2=route[mini(auto_climb_index,route.size()-1)]
  if absf(player.position.x-target.x)<28 and player.position.y<=target.y+24 and player.is_on_floor():auto_climb_index+=1
  if auto_climb_index<route.size():
   target=route[auto_climb_index];var dx:float=target.x-player.position.x
   if player.is_on_floor() and target.y<player.position.y-14 and absf(dx)<153:player.begin_action("jump")
   for r in FurnaceScript.SOLIDS:
    if player.is_on_floor() and dx>0 and player.position.x>r.position.x-78 and player.position.x<r.end.x+8:player.begin_action("jump")
   return signf(dx) if absf(dx)>12 else 0
 if player.is_on_floor() and distance>180:
  for r in FurnaceScript.SOLIDS:
   if (direction>0 and player.position.x>r.position.x-80 and player.position.x<r.end.x+5) or (direction<0 and player.position.x<r.end.x+80 and player.position.x>r.position.x-5):player.begin_action("jump")
 if exosuit.active:
  if distance<180 and exosuit.shock_cd<=0:player.begin_action("skill")
  if distance<800 and auto_cooldown<=0:player.begin_action("heavy" if nearest.kind in ["shield","boss"] and exosuit.heavy_cd<=0 else "light");auto_cooldown=.14
  return direction if distance>460 else (-direction if distance<155 else 0)
 if not qa_no_items:
  if player.hp<65 and inventory.counts.repair>0:inventory.use_item("repair",self)
  elif inventory.armor<=0 and inventory.counts.armor>0:inventory.use_item("armor",self)
 if absf(nearest.pos.y-player.position.y)>75 and player.is_on_floor() and distance<165:player.begin_action("jump")
 if nearest.state=="windup" and nearest.timer<.12 and distance<170:player.begin_action("dodge")
 if distance<150 and auto_cooldown<=0:
  if nearest.kind=="shield" and nearest.shield>0:player.begin_action("heavy")
  elif player.skill_cd<=0:player.begin_action("skill")
  else:player.begin_action("light")
  auto_cooldown=.24
 if player.state=="light" and player.elapsed>.23:player.begin_action("light")
 return direction if distance>110 else 0
