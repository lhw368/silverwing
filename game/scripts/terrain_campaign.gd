extends "res://scripts/terrain_combat.gd"
## v0.8 terrain and optional supplies. The v0.7 save remains untouched.
const TerrainEnemyScript=preload("res://scripts/furnace_raider.gd")
const OverloadBossScript=preload("res://scripts/furnace_overload_boss.gd")
const DropsScript=preload("res://scripts/battle_drops.gd")
const BridgeDiagnosticsScript=preload("res://scripts/bridge_diagnostics.gd")
const SAVE_V08="user://starport_save_v09.json"
const PREVIOUS_TERRAIN_SAVE="user://starport_save_v08.json"
var battle_drops=DropsScript.new()
var drop_checkpoint:Dictionary={"version":1,"claimed":[],"pending":[]}
var _interaction_save:bool=false
var _save_backoff:float=0.0
var qa_no_drops:bool=false
var qa_drop_seed:int=0
var qa_upper_route:bool=false
var qa_upper_step:int=0
var terrain_art:Dictionary={}
var bridge_diagnostics=BridgeDiagnosticsScript.new()
func _ready()->void:
 for arg in OS.get_cmdline_user_args():
  if arg=="--no-drops":qa_no_drops=true
  if arg=="--route=upper":qa_upper_route=true;qa_without_exosuit=true
  if arg.begins_with("--drop-seed="):qa_drop_seed=int(arg.trim_prefix("--drop-seed="))
 super._ready()
func _unhandled_input(event:InputEvent)->void:
 if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F10:
  var path:String=bridge_diagnostics.save_report(self)
  show_status("关卡诊断已保存：bridge_diagnostics_v08.json" if not path.is_empty() else "诊断保存失败。",4)
  get_viewport().set_input_as_handled();return
 super._unhandled_input(event)
func load_assets()->void:
 super.load_assets()
 var base="res://assets/environment/furnace-terrain/"
 for entry in [["container","cargo-container"],["low-cover","low-barricade"],["deck","freight-deck"],["capacitor","capacitor"]]:
  if ResourceLoader.exists(base+entry[1]+".webp"):terrain_art[entry[0]]=load(base+entry[1]+".webp")
 if terrain_art.has("capacitor"):item_textures.capacitor=terrain_art.capacitor
func start_run(resume:bool)->void:
 qa_upper_step=0
 if not resume:
  battle_drops.reset_run(qa_drop_seed);drop_checkpoint=battle_drops.capture_checkpoint()
 super.start_run(resume)
 if resume:
  if not battle_drops.restore_checkpoint(drop_checkpoint):save_warning="补给检查点读取失败，请重新开始本关。"
 else:
  # Every new action starts a matching level/entry save. Subsequent supply
  # autosaves must never attach a new run ledger to another level's checkpoint.
  saved_level_id=level_id;saved_checkpoint=0;saved_has_run=true
  if level_id==2:saved_second_snapshot=second_snapshot().duplicate(true)
  if level_id==3:saved_furnace_snapshot=furnace_snapshot().duplicate(true)
  drop_checkpoint=battle_drops.capture_checkpoint()
 if level_id==3 and not resume:
  show_status("米米：切断双路电源，前往第二维修点；之后可驾驶赤隼连续突破到出口。" if feiren_unlocked else "米米：先切断双路电源、救出绯刃；维修点后只有一台赤隼，接连续撤离战。",6)
 save_game()
func clear_combat()->void:
 super.clear_combat()
 battle_drops.clear_world()
func retry_checkpoint()->void:
 super.retry_checkpoint()
 if not battle_drops.restore_checkpoint(drop_checkpoint):save_warning="补给检查点读取失败，请重新开始本关。"
 save_game()
func interact()->void:
 _interaction_save=true
 super.interact()
 _interaction_save=false
func rescue_feiren()->void:
 if level_id!=3 or mode!="play" or paused or exosuit.active:return
 if not "restraint_a" in furnace.opened or not "restraint_b" in furnace.opened:return
 if absf(player.position.x-FurnaceScript.RESCUE_X)>115 or absf(player.position.y-FLOOR)>32:return
 if not feiren_unlocked:
  feiren_unlocked=true;unlock_events+=1;sfx("win");add_sparks(Vector2(FurnaceScript.RESCUE_X,FLOOR-130),ORANGE,28);print("FEIREN_UNLOCK t=",run_time)
 activate_third_checkpoint(2)
 show_status("绯刃：我先撤离！前方赤隼留给你，从货柜战区一路突破到出口。",7)
func spawn_wave(wave:Array)->void:
 var first:int=enemies.size()
 if level_id!=3:super.spawn_wave(wave)
 else:
  for entry in wave:
   var point=Vector2(entry[1],float(entry[2]) if entry.size()>2 else FLOOR)
   var enemy=OverloadBossScript.new(entry[0],point) if entry[0]=="boss" else TerrainEnemyScript.new(entry[0],point)
   enemy.attach_physics(self);enemies.append(enemy)
 for i in range(first,enemies.size()):
  var enemy=enemies[i]
  enemy.set_meta("supply_key","L%d|Z%d|W%d|I%d|%s|%d|%d"%[level_id,active_zone,wave_index,i-first,enemy.kind,roundi(enemy.home),roundi(enemy.ground_y)])
func enemy_hit_feedback(enemy:StarportEnemy,damage:int,heavy:bool,source_x:float,serial:int,ranged:bool,blocked:bool,armor_broken:bool,contact_point:Variant=null)->void:
 super.enemy_hit_feedback(enemy,damage,heavy,source_x,serial,ranged,blocked,armor_broken,contact_point)
 if qa_no_drops or enemy.hp>0:return
 var key:String=enemy.get_meta("supply_key","L%d|relay%d|%s|%d|%d"%[level_id,enemy.relay_station,enemy.kind,roundi(enemy.home),roundi(enemy.ground_y)])
 battle_drops.on_defeat(self,enemy,key)
func _physics_process(dt:float)->void:
 var previous_y:float=camera_y
 super._physics_process(dt)
 bridge_diagnostics.tick(dt,self)
 if level_id==3 and player.position.x<2450:camera_y=lerpf(previous_y,minf(0.0,player.position.y-304.0),1-exp(-7.0*dt))
 if not qa_no_drops:battle_drops.tick(dt,self)
 _save_backoff=maxf(0.0,_save_backoff-dt)
 if battle_drops.is_dirty() and _save_backoff<=0:save_game()
func draw_effects()->void:
 super.draw_effects();battle_drops.draw(self)
func draw_world()->void:
 super.draw_world()
 if level_id!=3:return
 for rect in FurnaceScript.SOLIDS:
  if rect.position.x<500 or rect.position.x>10000:
   var key:String="container" if rect.size.y>140 else "low-cover"
   if terrain_art.has(key):draw_texture_rect(terrain_art[key],rect,false)
 if terrain_art.has("deck"):
  for start in range(695,2070,320):
   var width:float=minf(320,2070-start)
   draw_texture_rect_region(terrain_art.deck,Rect2(start,286,width,64),Rect2(0,0,terrain_art.deck.get_width()*width/320.0,terrain_art.deck.get_height()))
 text_at("上层货运栈桥 →",Vector2(700,260),20,ORANGE)
 text_at("下层战斗通道 →",Vector2(1080,456),18,ORANGE)
 text_at("两路汇合 ↓",Vector2(2100,345),18,ORANGE)
 text_at("实心货柜 · 双向挡弹",Vector2(11190,357),20,ORANGE)
func save_game()->void:
 if saved_checkpoint>0:saved_has_run=true
 if mode=="win":saved_has_run=false
 if _interaction_save and not exosuit.active:drop_checkpoint=battle_drops.capture_checkpoint()
 var data={"version":4,"unlocked_feiren":feiren_unlocked,"character":selected_character,"has_run":saved_has_run,"saved_level":saved_level_id,"checkpoint":saved_checkpoint,"second_snapshot":saved_second_snapshot,"furnace_snapshot":saved_furnace_snapshot,"spent_pods":spent_pods,"completed_levels":completed_levels,"best_times":best_times,"volume":volume,"shake":shake_amount,"drops":battle_drops.snapshot(),"drop_checkpoint":drop_checkpoint}
 var file=FileAccess.open(SAVE_V08+".tmp",FileAccess.WRITE)
 if not file:save_warning="保存失败；本次可继续，进度可能无法保留。";_save_backoff=1.0;return
 file.store_string(JSON.stringify(data));file.flush();file.close()
 if FileAccess.file_exists(SAVE_V08):DirAccess.copy_absolute(SAVE_V08,SAVE_V08+".bak")
 if DirAccess.rename_absolute(SAVE_V08+".tmp",SAVE_V08)!=OK:save_warning="保存失败，请保留当前游戏。";_save_backoff=1.0;return
 battle_drops.mark_saved();save_warning=""
func valid_terrain_save(data:Variant)->bool:
 if not data is Dictionary or not integral(data.get("version"),4,4):return false
 var legacy:Dictionary=data.duplicate(true);legacy.version=3
 if not valid_rescue_save(legacy):return false
 if int(data.saved_level)==2 and (data.has_run or int(data.checkpoint)>0) and not valid_second_snapshot(data.second_snapshot,int(data.checkpoint)):return false
 var probe=DropsScript.new()
 if not probe.restore(data.get("drops")) or not probe.valid_checkpoint(data.get("drop_checkpoint")):return false
 for entry in probe.entries:
  if int(entry.level)!=int(data.saved_level):return false
 for item in data.drop_checkpoint.pending:
  if int(item.level)!=int(data.saved_level) or not _valid_saved_supply_floor(Vector2(float(item.pos[0]),float(item.pos[1])),int(data.saved_level)):return false
 return true
func _valid_saved_supply_floor(point:Vector2,level:int)->bool:
 var limit:float=17600.0 if level==3 else LevelData.WORLD_END
 if not point.is_finite() or point.x<0 or point.x>limit:return false
 var rects:Array=[Rect2(-200,FLOOR,limit+400,180)]
 if level==1:rects.append_array(LevelData.OBSTACLES);rects.append_array(LevelData.RELAY_PLATFORMS)
 elif level==2:rects.append_array(CoolantScript.SOLIDS);rects.append_array(CoolantScript.PLATFORMS)
 else:rects.append_array(FurnaceScript.SOLIDS);rects.append_array(FurnaceScript.PLATFORMS)
 var supported:bool=false
 for rect in rects:
  if rect.grow(-.01).has_point(point+Vector2(0,-3)):return false
  if point.x>=rect.position.x and point.x<=rect.end.x and absf(point.y-rect.position.y)<=2:supported=true
 return supported
func load_save()->void:
 var data:Variant=read_saved_json(SAVE_V08)
 if not valid_terrain_save(data) and FileAccess.file_exists(SAVE_V08+".bak"):data=read_saved_json(SAVE_V08+".bak")
 if not valid_terrain_save(data):
  var previous:Variant=read_saved_json(PREVIOUS_TERRAIN_SAVE)
  if not valid_terrain_save(previous):previous=read_saved_json(PREVIOUS_TERRAIN_SAVE+".bak")
  if valid_terrain_save(previous):data=previous
 if valid_terrain_save(data):
  feiren_unlocked=data.unlocked_feiren;selected_character=data.character;saved_has_run=data.has_run
  saved_level_id=int(data.saved_level);saved_checkpoint=int(data.checkpoint);saved_second_snapshot=data.second_snapshot.duplicate(true);saved_furnace_snapshot=data.furnace_snapshot.duplicate(true)
  spent_pods.clear()
  for id in data.spent_pods:spent_pods.append(id)
  completed_levels.clear()
  for id in data.completed_levels:completed_levels.append(int(id))
  best_times=data.best_times.duplicate(true);volume=data.volume;shake_amount=data.shake
  battle_drops.restore(data.drops);drop_checkpoint=data.drop_checkpoint.duplicate(true)
  AudioServer.set_bus_volume_db(0,linear_to_db(maxf(volume,.0001)));return
 super.load_save()
 battle_drops.reset_run(qa_drop_seed);drop_checkpoint=battle_drops.capture_checkpoint()
 # One migration write preserves every v0.7/0.6 source file and setting.
 save_game()
func _jump_step_ahead(axis:float)->void:
 if not player.is_on_floor() or absf(axis)<.05 or player.state not in ["idle","run"]:return
 for rect in FurnaceScript.SOLIDS:
  var height:float=player.position.y-rect.position.y
  var edge:float=rect.position.x if axis>0 else rect.end.x
  var distance:float=(edge-player.position.x)*signf(axis)
  if height>14 and height<=124 and distance>=-3 and distance<95:player.begin_action("jump");return
func _upper_route_axis()->Variant:
 if not qa_upper_route or player.position.x>2350:return null
 var route:Array=[Vector2(400,486),Vector2(582,390),Vector2(780,286)]
 if qa_upper_step<route.size():
  var target:Vector2=route[qa_upper_step]
  if player.is_on_floor() and absf(player.position.x-target.x)<35 and absf(player.position.y-target.y)<18:qa_upper_step+=1
  if qa_upper_step<route.size():
   target=route[qa_upper_step];var dx:float=target.x-player.position.x
   if player.is_on_floor() and player.position.y>target.y+20 and absf(dx)<180:player.begin_action("jump")
   return signf(dx) if absf(dx)>12 else 0.0
 if player.position.y<420:
  var airborne_enemy=null
  for enemy in enemies:
   if not enemy.dead and absf(enemy.pos.y-player.position.y)<115:airborne_enemy=enemy;break
  if airborne_enemy==null:return 1.0
 return null
func _step_down_axis(enemy)->Variant:
 if enemy==null or enemy.pos.y-player.position.y<=110 or not player.is_on_floor():return null
 for item in terrain_rects():
  var rect:Rect2=item.rect
  if absf(player.position.y-rect.position.y)<8 and player.position.x>=rect.position.x-5 and player.position.x<=rect.end.x+5:
   return -1.0 if enemy.pos.x<rect.get_center().x else 1.0
 return null
func _route_combat_axis(enemy,dt:float)->float:
 auto_cooldown-=dt
 var dx:float=enemy.pos.x-player.position.x;var distance:float=absf(dx);var direction:float=signf(dx)
 if player.state in ["idle","run"] and direction!=0:player.facing=int(direction)
 var down:Variant=_step_down_axis(enemy)
 if down!=null:return float(down)
 var clear:bool=cover_line_clear(player.position+Vector2(0,-65),enemy.pos+Vector2(0,-50))
 var axis:float=direction
 if exosuit.active:
  if clear and distance<180 and exosuit.shock_cd<=0:player.begin_action("skill")
  if clear and distance<800 and auto_cooldown<=0:
   player.begin_action("heavy" if enemy.kind=="shield" and exosuit.heavy_cd<=0 else "light");auto_cooldown=.14
  if clear:axis=direction if distance>400 else (-direction if distance<140 else 0.0)
 else:
  if not qa_no_items:
   if player.hp<65 and inventory.counts.repair>0:inventory.use_item("repair",self)
   elif inventory.armor<=0 and inventory.counts.armor>0:inventory.use_item("armor",self)
  if enemy.state=="windup" and enemy.timer<.12 and distance<170:player.begin_action("dodge")
  if clear and distance<150 and absf(enemy.pos.y-player.position.y)<110 and auto_cooldown<=0:
   player.begin_action("heavy" if enemy.kind=="shield" and enemy.shield>0 else ("skill" if player.skill_cd<=0 else "light"));auto_cooldown=.24
  if player.state=="light" and player.elapsed>.23:player.begin_action("light")
  if clear and distance<=105:axis=0.0
 _jump_step_ahead(axis)
 return axis
func autopilot(dt:float)->float:
 if level_id!=3:return super.autopilot(dt)
 var upper:Variant=_upper_route_axis()
 if upper!=null:return float(upper)
 var nearest=null;var distance:float=INF
 for enemy in enemies:
  if enemy.dead:continue
  if qa_upper_route and active_zone==0 and player.position.y<420 and absf(enemy.pos.y-player.position.y)>115:continue
  var score:float=absf(enemy.pos.x-player.position.x)+absf(enemy.pos.y-player.position.y)*.25
  if score<distance:nearest=enemy;distance=score
 if nearest!=null:
  var down:Variant=_step_down_axis(nearest)
  if down!=null:return float(down)
  if active_zone in [0,1,2,3,4]:
   if active_zone==0 and nearest.pos.y<player.position.y-105:
    var toward_exit:float=signf(2140-player.position.x) if absf(2140-player.position.x)>25 else 0.0
    _jump_step_ahead(toward_exit);return toward_exit
   return _route_combat_axis(nearest,dt)
 var axis:float=super.autopilot(dt)
 _jump_step_ahead(axis)
 return axis
