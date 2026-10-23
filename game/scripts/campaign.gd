extends "res://scripts/game.gd"
## Campaign shell around the preserved 0.4 combat and first-level implementation.
const InventoryScript=preload("res://scripts/consumable_inventory.gd")
const SuppliedPlayerScript=preload("res://scripts/supplied_player.gd")
const CoolantScript=preload("res://scripts/coolant_level.gd")
const CoolantBossScript=preload("res://scripts/coolant_boss.gd")
const CAMPAIGN_SAVE="user://starport_save_v05.json"
var level_id:int=1
var selected_level:int=1
var saved_level_id:int=1
var completed_levels:Array=[]
var best_times:Dictionary={"1":0.0,"2":0.0}
var inventory=InventoryScript.new()
var coolant=CoolantScript.new()
var saved_second_snapshot:Dictionary={}
var checkpoint_second_snapshot:Dictionary={}
var world_geometry:Node2D
var stage_art:Dictionary={}
var boss_art:Dictionary={}
var item_textures:Dictionary={}
var migrated_legacy:bool=false
var qa_no_items:bool=false

func _ready()->void:
 for arg in OS.get_cmdline_user_args():
  if arg=="--level=2":selected_level=2;level_id=2
  if arg=="--no-items":qa_no_items=true
 super._ready()

func load_assets()->void:
 super.load_assets()
 stage_art[1]=parallax_layers.duplicate(true)
 boss_art[1]={"animations":enemy_animations.boss,"meta":enemy_animation_meta.boss,"hurt":boss_hurt_regions}
 var base="res://assets/environment/coolant/"
 if FileAccess.file_exists(base+"manifest.json"):
  var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(base+"manifest.json"))
  var layers:Array=[]
  for data in manifest.layers:
   var path:String=base+str(data.path).get_file()
   if not ResourceLoader.exists(path):path=base+str(data.path)
   var c:Array=data.draw_tint
   layers.append({"id":data.id,"texture":load(path),"factor":float(data.camera_scroll_scale),"width":float(data.size[0]),"height":float(data.size[1]),"y":float(data.draw_origin[1]),"repeat":bool(data.repeat),"foreground":data.id=="foreground","tint":Color(c[0],c[1],c[2],c[3])})
  stage_art[2]=layers
 var boss_path="res://assets/enemies/actions/coolant_boss/"
 if FileAccess.file_exists(boss_path+"manifest.json"):
  var meta:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(boss_path+"manifest.json"))
  var groups:Dictionary={}
  for action in meta.animations:
   var frames:Array=[]
   for filename in meta.animations[action].frames:frames.append(load(boss_path+filename))
   groups[action]=frames
  var hurt:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(boss_path+"hurt_regions.json")) if FileAccess.file_exists(boss_path+"hurt_regions.json") else {}
  boss_art[2]={"animations":groups,"meta":meta,"hurt":hurt}
 for kind in ["bomb","armor","repair","supply_crate"]:
  var path="res://assets/items/"+kind+".png"
  if not ResourceLoader.exists(path):path="res://assets/items/"+kind+".webp"
  if ResourceLoader.exists(path):item_textures[kind]=load(path)

func make_world()->void:
 world_geometry=Node2D.new();world_geometry.name="StageGeometry";add_child(world_geometry)
 rebuild_geometry()
 player=SuppliedPlayerScript.new();add_child(player);player.setup(self);player.reset_at(Vector2(210,FLOOR-2))

func rebuild_geometry()->void:
 for child in world_geometry.get_children():child.free()
 var solids:Array=LevelData.OBSTACLES if level_id==1 else CoolantScript.SOLIDS
 var platforms:Array=LevelData.RELAY_PLATFORMS if level_id==1 else CoolantScript.PLATFORMS
 for r in [Rect2(-200,FLOOR,WORLD_END+400,180)]+solids+platforms:
  var body=StaticBody2D.new();var collider=CollisionShape2D.new();var shape=RectangleShape2D.new()
  shape.size=r.size;collider.shape=shape;collider.position=r.position+r.size/2
  if r in platforms:collider.one_way_collision=true;collider.one_way_collision_margin=8
  body.add_child(collider);world_geometry.add_child(body)

func apply_level(id:int)->void:
 level_id=clampi(id,1,2)
 zones=LevelData.zones() if level_id==1 else CoolantScript.zones()
 rebuild_geometry()
 parallax_layers=stage_art.get(level_id,stage_art[1]).duplicate(true)
 var art:Dictionary=boss_art.get(level_id,boss_art[1])
 enemy_animations.boss=art.animations;enemy_animation_meta.boss=art.meta;boss_hurt_regions=art.hurt
 best_time=float(best_times.get(str(level_id),0))

func start_run(resume:bool)->void:
 clear_combat();inventory.reset();coolant.reset()
 apply_level(saved_level_id if resume else selected_level)
 selected_level=level_id
 super.start_run(resume)
 if level_id==2:
  if resume and not saved_second_snapshot.is_empty():restore_second_snapshot(saved_second_snapshot)
  checkpoint_second_snapshot=second_snapshot()
  show_status("冷却环线接入。收集补给，关闭三处过压管线。",5)
 else:checkpoint_second_snapshot.clear()

func retry_checkpoint()->void:
 super.retry_checkpoint()
 inventory.release_bombs()
 if level_id==2:
  restore_second_snapshot(checkpoint_second_snapshot)
  show_status("已恢复检查点物资与阀门状态。",3)

func clear_combat()->void:
 super.clear_combat()
 if inventory:inventory.release_bombs()

func checkpoint_zone_ids()->Array:
 return super.checkpoint_zone_ids() if level_id==1 else coolant.checkpoint_zones(checkpoint)
func checkpoint_spawn_x()->float:
 return super.checkpoint_spawn_x() if level_id==1 else float(CoolantScript.CHECKPOINT_SPAWNS[clampi(checkpoint,0,2)])
func right_bound()->float:
 if level_id==1:return super.right_bound()
 var bound:float=float(zones[active_zone].right)-25 if active_zone>=0 else WORLD_END-35
 return coolant.right_bound(bound)
func reset_relay_guards(checkpoint_id:int)->void:
 if level_id==1:super.reset_relay_guards(checkpoint_id)
func update_relay_guards()->void:
 if level_id==1:super.update_relay_guards()
func spawn_wave(wave:Array)->void:
 if level_id==1:super.spawn_wave(wave);return
 for entry in wave:
  var point=Vector2(entry[1],float(entry[2]) if entry.size()>2 else FLOOR)
  var enemy=CoolantBossScript.new(entry[0],point) if entry[0]=="boss" else EnemyScript.new(entry[0],point)
  enemy.attach_physics(self);enemies.append(enemy)

func _physics_process(dt:float)->void:
 super._physics_process(dt)
 if level_id==2 and mode=="play" and not paused and not test_mode:
  inventory.tick(dt,self)
  # A final bomb hit resolves victory before a lingering vent can damage the
  # player, matching first-level last-hit priority in the base combat loop.
  if active_zone==zones.size()-1 and alive_count()==0:update_zones()
  if mode=="play":coolant.tick(dt,self)
  queue_redraw()

func _unhandled_input(event:InputEvent)->void:
 if mode=="menu":
  if event is InputEventKey and event.pressed and not event.echo:
   if event.keycode in [KEY_DOWN,KEY_S]:menu_cursor=(menu_cursor+1)%3
   if event.keycode in [KEY_UP,KEY_W]:menu_cursor=posmod(menu_cursor-1,3)
   if event.keycode==KEY_1:menu_cursor=0
   if event.keycode==KEY_2:menu_cursor=1
   if event.keycode in [KEY_ENTER,KEY_SPACE]:menu_launch()
  elif event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
   for i in 3:
    if Rect2(806,378+i*70,346,56).has_point(event.position):menu_cursor=i;menu_launch()
  return
 if event is InputEventKey and event.pressed and not event.echo:
  if mode=="win" and event.keycode==KEY_ENTER and level_id==1:
   selected_level=2;start_run(false);return
  if mode=="win" and event.keycode==KEY_R:
   selected_level=level_id;start_run(false);return
  if event.keycode in [KEY_1,KEY_2,KEY_3] and mode=="play":
   if level_id==2:inventory.use_item(["bomb","armor","repair"][event.keycode-KEY_1],self)
   return
 super._unhandled_input(event)
func menu_launch()->void:
 if menu_cursor==2:
  if saved_checkpoint>0:start_run(true)
 else:selected_level=menu_cursor+1;start_run(false)

func interact()->void:
 if level_id==1:
  var near_middle=absf(player.position.x-LevelData.NPC_X)<160 and rooms_completed_through(3)
  var near_core=absf(player.position.x-CORE_NPC_X)<135 and rooms_completed_through(LevelData.BOSS_ZONE_INDEX-1) and relays.is_station_open(2)
  if (near_middle or near_core) and active_zone<0:saved_level_id=1
  super.interact()
 elif not paused and mode=="play":coolant.interact(self)
func activate_second_checkpoint(id:int)->void:
 checkpoint=id;saved_checkpoint=id;saved_level_id=2
 player.hp=100;player.skill_cd=0
 checkpoint_second_snapshot=second_snapshot();saved_second_snapshot=checkpoint_second_snapshot.duplicate(true)
 dialogue_timer=7.0;save_game();sfx("checkpoint");show_status("维修完成 · 生命恢复，物资快照已保存",3)
 print("COOLANT_CHECKPOINT ",id," items=",inventory.counts," t=",run_time)
func second_snapshot()->Dictionary:
 return {"inventory":inventory.snapshot(),"machines":coolant.snapshot()}
func valid_second_snapshot(data:Variant,cp:int=0)->bool:
 if not data is Dictionary or not data.get("inventory") is Dictionary or not coolant.valid_snapshot(data.get("machines")):return false
 var probe=InventoryScript.new()
 if not probe.restore(data.inventory):return false
 var valves:Array=data.machines.opened
 if cp>=1 and (not "intake" in valves or not "return" in valves):return false
 if cp>=2 and not "core" in valves:return false
 return true
func restore_second_snapshot(data:Dictionary)->bool:
 if not valid_second_snapshot(data,checkpoint):return false
 coolant.restore(data.machines);inventory.restore(data.inventory);return true

func player_strike(kind:String,combo:int,serial:int,first_active_tick:bool=true)->void:
 super.player_strike(kind,combo,serial,first_active_tick)
 if level_id==2 and kind!="skill" and mode=="play" and player.hp>0:
  coolant.hit_crates(self,melee_attack_polygon(kind),([10,10,18][combo-1]) if kind=="light" else 28,serial)
func damage_from_bomb(point:Vector2,radius:float,damage:int,serial:int)->void:
 if level_id!=2 or mode!="play" or paused:return
 var blast=PackedVector2Array()
 for i in 24:blast.append(point+Vector2.from_angle(TAU*i/24.0)*radius)
 for enemy in enemies:
  if enemy.dead:continue
  if enemy.kind=="boss":
   var contact:Variant=boss_attack_contact(enemy,blast,point)
   if contact!=null:enemy.hit(damage,true,point.x,serial,self,true,contact)
  else:
   var torso=enemy.pos+Vector2(0,-55)
   if point.distance_to(torso)<=radius+24:enemy.hit(damage,true,point.x,serial,self,true,torso)
 coolant.hit_crates(self,blast,damage,serial)
func float_text(point:Vector2,value:String,color:Color)->void:
 if value!="-0":super.float_text(point,value,color)
func boss_body_polygons(enemy:StarportEnemy)->Array:
 if level_id==1:return super.boss_body_polygons(enemy)
 var result:Array=[]
 if enemy.dead or boss_hurt_regions.is_empty():return result
 var pose=enemy_animation_pose(enemy);var frames:Array=boss_hurt_regions.frames.get(pose.action,[])
 if frames.is_empty():return result
 var data:Dictionary=frames[clampi(pose.frame,0,frames.size()-1)]
 var meta:Dictionary=enemy_animation_meta.boss
 var factor:float=265.0/float(meta.native_body_height)
 for points in data.polygons:
  var polygon=PackedVector2Array()
  for p in points:polygon.append(enemy.pos+Vector2((float(p[0])-float(meta.root[0]))*-enemy.facing,float(p[1])-float(meta.root[1]))*factor)
  result.append(polygon)
 return result

func save_game()->void:
 var data={"version":2,"saved_level":saved_level_id,"checkpoint":saved_checkpoint,"second_snapshot":saved_second_snapshot,"completed_levels":completed_levels,"best_times":best_times,"volume":volume,"shake":shake_amount}
 var temp=FileAccess.open(CAMPAIGN_SAVE+".tmp",FileAccess.WRITE)
 if temp==null:save_warning="无法写入存档；本次可继续游玩。";return
 temp.store_string(JSON.stringify(data));temp.flush();temp.close()
 if FileAccess.file_exists(CAMPAIGN_SAVE):DirAccess.copy_absolute(CAMPAIGN_SAVE,CAMPAIGN_SAVE+".bak")
 if DirAccess.rename_absolute(CAMPAIGN_SAVE+".tmp",CAMPAIGN_SAVE)!=OK:save_warning="存档写入失败；请勿依赖续玩。"
func integral(value:Variant,low:int,high:int)->bool:
 return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and float(value)==floorf(float(value)) and float(value)>=low and float(value)<=high
func valid_campaign_save(data:Variant)->bool:
 if not data is Dictionary or not integral(data.get("version"),2,2) or not integral(data.get("saved_level"),1,2) or not integral(data.get("checkpoint"),0,2):return false
 for key in ["volume","shake"]:
  if not typeof(data.get(key)) in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(data[key])) or float(data[key])<0 or float(data[key])>1:return false
 if not data.get("best_times") is Dictionary or not data.get("completed_levels") is Array or not data.get("second_snapshot") is Dictionary:return false
 for id in ["1","2"]:
  var value:Variant=data.best_times.get(id)
  if not typeof(value) in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or float(value)<0:return false
 for id in data.completed_levels:
  if not integral(id,1,2):return false
 if int(data.saved_level)==2 and int(data.checkpoint)>0 and not valid_second_snapshot(data.second_snapshot,int(data.checkpoint)):return false
 return true
func load_save()->void:
 var data:Variant=null
 if FileAccess.file_exists(CAMPAIGN_SAVE):
  data=read_saved_json(CAMPAIGN_SAVE)
  if not valid_campaign_save(data):
   save_warning="存档格式异常，已回退安全记录。"
   if FileAccess.file_exists(CAMPAIGN_SAVE+".bak"):data=read_saved_json(CAMPAIGN_SAVE+".bak")
  if valid_campaign_save(data):
   saved_level_id=int(data.saved_level);saved_checkpoint=int(data.checkpoint)
   saved_second_snapshot=data.second_snapshot.duplicate(true)
   completed_levels=[]
   for id in data.completed_levels:
    if not int(id) in completed_levels:completed_levels.append(int(id))
   best_times=data.best_times.duplicate(true);volume=float(data.volume);shake_amount=float(data.shake)
   AudioServer.set_bus_volume_db(0,linear_to_db(maxf(volume,.0001)));return
 # Preserve the old file byte-for-byte and import its checkpoint/settings once.
 if FileAccess.file_exists(SAVE_PATH):
  data=read_saved_json(SAVE_PATH)
  if not valid_save(data) and FileAccess.file_exists(SAVE_PATH+".bak"):data=read_saved_json(SAVE_PATH+".bak")
  if valid_save(data):
   saved_level_id=1;saved_checkpoint=int(data.checkpoint);volume=clampf(data.volume,0,1);shake_amount=clampf(data.shake,0,1)
   best_times["1"]=maxf(0,float(data.best_time));migrated_legacy=true
   if best_times["1"]>0:completed_levels=[1]
   AudioServer.set_bus_volume_db(0,linear_to_db(maxf(volume,.0001)))
   save_game()
func victory()->void:
 if not level_id in completed_levels:completed_levels.append(level_id)
 var previous=float(best_times.get(str(level_id),0))
 best_times[str(level_id)]=run_time if previous<=0 else minf(previous,run_time)
 saved_level_id=level_id
 super.victory()
func draw_world()->void:
 if level_id==1:super.draw_world()
 else:coolant.draw_world(self)
func draw_effects()->void:
 super.draw_effects()
 if level_id==2:inventory.draw_world(self)
func draw_enemy(enemy:StarportEnemy)->void:
 if level_id==1 or enemy.kind!="boss":super.draw_enemy(enemy);return
 if enemy.dead and enemy.death_timer>.72:return
 var meta:Dictionary=enemy_animation_meta.boss
 var factor:float=265.0/float(meta.native_body_height)
 var pose:Dictionary=enemy_animation_pose(enemy)
 var frames:Array=enemy_animations.boss[pose.action]
 var texture:Texture2D=frames[clampi(pose.frame,0,frames.size()-1)]
 var tint=Color(1,.9,.74) if enemy.state=="windup" else Color.WHITE
 if enemy.flash>0 and effects_enabled:tint=Color(1.7,1.9,1.8)
 if enemy.dead:tint.a=clampf((.72-enemy.death_timer)/.2,0,1)
 draw_circle(Vector2(enemy.pos.x,enemy.ground_y+1),75,Color(.01,.03,.08,.3))
 draw_texture_rect(texture,sprite_rect_for(enemy.pos,Vector2(meta.frame_size[0],meta.frame_size[1])*factor,float(meta.root[1])*factor,-enemy.facing),false,tint)
 if enemy.state=="windup" and not enemy.dead:
  var at=enemy.pos+Vector2(0,-282);draw_circle(at,12,ORANGE);text_at("!",at+Vector2(-4,7),20,Color("#13232b"))
  if enemy.move_name=="wave":
   var r=Rect2(enemy.locked_x-70,FLOOR-100,140,100)
   draw_rect(r,Color(1,.65,.15,.13));draw_rect(r,ORANGE,false,3)
   draw_line(Vector2(enemy.locked_x-65,FLOOR-4),Vector2(enemy.locked_x+65,FLOOR-4),ORANGE,6)
  else:
   var width=185.0 if enemy.move_name=="sweep" else 540.0
   draw_rect(Rect2(enemy.pos.x if enemy.facing>0 else enemy.pos.x-width,FLOOR-8,width,8),Color(1,.7,.25,.55))
func draw_hud()->void:
 if level_id==1:
  super.draw_hud()
  panel(Rect2(1181,633,75,27),Color("#102936"));text_at("v0.5",Vector2(1194,653),14,CYAN)
  return
 var mint=Color("#79edcd")
 panel(Rect2(24,22,390,111));draw_rect(Rect2(24,22,4,111),mint)
 text_at("银翼  /  SILVERWING",Vector2(43,51),22)
 bar(Rect2(43,66,274,15),player.hp/100.0,mint if player.hp>25 else Color("#ff8c7a"));text_at("%d / 100"%player.hp,Vector2(329,80),16)
 text_at("U 磁轨斩",Vector2(43,112),16);bar(Rect2(129,102,123,6),1-player.skill_cd/8,mint)
 text_at("就绪" if player.skill_cd<=0 else "%.1fs"%player.skill_cd,Vector2(263,113),15,mint)
 text_at("闪避 "+("就绪" if player.dodge_cd<=0 else "%.1fs"%player.dodge_cd),Vector2(322,112),14)
 panel(Rect2(922,22,334,86));text_at("02  冷却环线",Vector2(943,51),23)
 text_at("%02d:%02d   ·   受击 %d   ·   重试 %d"%[int(run_time)/60,int(run_time)%60,hits_taken,retries],Vector2(942,82),16,Color("#aac5da"))
 text_at("封锁中 · 剩余 %d"%alive_count() if active_zone>=0 else "向右推进 →",Vector2(1060,133),18,ORANGE if active_zone>=0 else mint)
 inventory.draw_hud(self)
 text_at("v0.5",Vector2(1194,650),14,mint)
 panel(Rect2(24,665,1232,38));text_at("A/D 移动 · SPACE 跳 · J 连击 · K 重击 · L 闪避 · U 技能 · E 交互 · 1 炸弹 · 2 护甲 · 3 维修 · ESC 暂停",Vector2(43,690),17,Color("#b6cde0"))
 if status_timer>0:panel(Rect2(330,149,620,42));centered(status,178,18,mint)
 var objective=coolant.objective_hint(self)
 if not objective.is_empty():
  panel(Rect2(433,24,466,104))
  for line in range(mini(3,int(ceil(objective.length()/26.0)))):text_at(objective.substr(line*26,26),Vector2(449,54+26*line),16,mint)
 if zone_hint_timer>0 and not zone_hint.is_empty() and active_zone>=0 and active_zone<zones.size()-1:
  panel(Rect2(433,24,466,104))
  for line in range(mini(3,int(ceil(zone_hint.length()/26.0)))):
   text_at(zone_hint.substr(line*26,26),Vector2(449,50+26*line),16,Color("#b7d6e5"))
 for enemy in enemies:
  if enemy.kind!="boss" or enemy.dead:continue
  panel(Rect2(344,214,592,60));centered("冷却监理机"+(" / 过压" if enemy.phase_two else ""),236,18,ORANGE)
  bar(Rect2(365,249,550,9),float(enemy.hp)/enemy.max_hp,ORANGE)
  var hint:Dictionary=enemy.boss_wave_hint(self)
  var label:String=hint.text
  var detail="SPACE 起跳 · 迎着冷凝波越过"
  var cue=mint if hint.stage=="jump" else ORANGE
  if hint.stage=="move":detail="锁定后位置不再追踪，移出方框"
  if label.is_empty() and enemy.state=="recover":label="冷却中 · 反击机会";detail="靠近躯干与腿部出手";cue=mint
  elif label.is_empty() and enemy.state=="windup":label="钻臂前刺 · 后撤 / 闪避";detail="方向已锁定，避开前方短距离"
  if not label.is_empty():panel(Rect2(433,24,466,104));text_at(label,Vector2(451,65),23,cue);text_at(detail,Vector2(451,101),17)
 if dialogue_timer>0 and minf(absf(player.position.x-7040),absf(player.position.x-12070))<200:
  panel(Rect2(284,348,750,128),Color(.015,.05,.1,.96),mint)
  text_at("米米 / 冷却检修",Vector2(307,382),21,mint)
  text_at("生命已恢复。库存按这次保存的数量恢复，重复维修不会补道具。",Vector2(307,416),17)
  text_at("地面锁定要移开；冷凝波靠近再跳。抓住收招反击。",Vector2(307,453),17)
 if not save_warning.is_empty():text_at(save_warning,Vector2(30,590),16,ORANGE)
func draw_menu()->void:
 draw_rect(Rect2(0,0,1280,720),Color(.01,.03,.065,.5))
 panel(Rect2(64,68,668,578),Color(.02,.05,.1,.7),Color("#2d6580"))
 text_at("S T A R P O R T  /  M E C H A  S Q U A D",Vector2(92,112),19,CYAN)
 text_at("星港机甲小队",Vector2(89,184),52);text_at("银翼 · 两段星港行动",Vector2(94,225),25,Color("#b4d5ea"))
 var idle:Array=hero_frames.get("idle",[])
 if not idle.is_empty():draw_texture_rect(idle[0],Rect2(240,232,315,315),false)
 text_at("先看清，再出手。",Vector2(94,538),30)
 text_at("第二关：炸弹 / 临时护甲 / 维修包 / 冷却设施",Vector2(94,577),18,Color("#a7c8dc"))
 text_at("本地单人 · 键盘操作 · MVP 0.6",Vector2(94,619),17,CYAN)
 panel(Rect2(780,142,402,486),Color(.02,.055,.11,.95),Color("#356d86"))
 text_at("选择行动",Vector2(806,188),27,CYAN)
 text_at("01 星港：解除机械封锁",Vector2(806,240),21)
 text_at("02 冷却环线：关闭过压管线",Vector2(806,277),20)
 text_at("两关均可直接试玩；道具只在第二关。",Vector2(806,320),16,Color("#aecfda"))
 var labels=["第一关 / 失控的星港","第二关 / 冷却环线","继续 / 第%d关维修点"%saved_level_id if saved_checkpoint>0 else "暂无检查点"]
 for i in 3:
  var r=Rect2(806,378+i*70,346,56)
  panel(r,Color("#087b80") if menu_cursor==i else Color("#133444"),CYAN if menu_cursor==i else Color("#356076"))
  text_at(("▶ " if menu_cursor==i else "  ")+labels[i],r.position+Vector2(17,35),21,WHITE if i<2 or saved_checkpoint>0 else Color("#638399"))
 text_at("↑↓ 选择 · ENTER 开始",Vector2(822,607),16,CYAN)
 if not save_warning.is_empty():text_at(save_warning,Vector2(64,687),17,ORANGE)
func draw_result(won:bool)->void:
 if not won:super.draw_result(false);return
 draw_rect(Rect2(0,0,1280,720),Color(.01,.03,.065,.76));panel(Rect2(280,151,720,441),Color("#0b2137"),CYAN)
 centered("星港恢复供电" if level_id==1 else "冷却环线恢复正常",220,35,CYAN)
 centered("下一站：冷却环线。米米正在检修入口等你。" if level_id==1 else "三处管线已经稳定。米米：这次真的可以松口气啦。",275,20)
 centered("用时 %02d:%02d    受击 %d 次    重试 %d 次"%[int(run_time)/60,int(run_time)%60,hits_taken,retries],334,23)
 centered("击破 %d 台机械"%kills,376,20,Color("#aac6da"))
 centered("ENTER 进入第二关" if level_id==1 else "ENTER 再玩第二关",447,25,CYAN)
 centered("R 重玩本关    M 返回选关",503,20)
 centered("库存与护甲只在本关生效" if level_id==2 else "第一关手感沿用 0.4 修订",555,16,Color("#aac6da"))

func autopilot(dt:float)->float:
 if level_id==1:return super.autopilot(dt)
 auto_cooldown-=dt
 if absf(player.position.x-7040)<110 and checkpoint<1 and active_zone<0:interact()
 if checkpoint<2 and active_zone<0 and "core" in coolant.opened and player.position.x>11950:
  if absf(player.position.x-12070)<90 and player.is_on_floor():interact()
  if checkpoint<2:return signf(12070-player.position.x) if absf(player.position.x-12070)>12 else 0.0
 if absf(player.position.x-9140)<65 and not "scanner" in coolant.opened:interact()
 if not qa_no_items:
  if player.hp<65 and inventory.counts.repair>0:inventory.use_item("repair",self)
  elif inventory.armor<=0 and inventory.counts.armor>0:inventory.use_item("armor",self)
 var nearest:StarportEnemy=null
 var distance=INF
 for enemy in enemies:
  if not enemy.dead and absf(enemy.pos.x-player.position.x)<distance:nearest=enemy;distance=absf(enemy.pos.x-player.position.x)
 if nearest==null:
  for valve in CoolantScript.VALVES:
   if not completed_zones.has(valve.after) or valve.id in coolant.opened:continue
   if coolant.nav_valve!=valve.id:coolant.nav_valve=valve.id;coolant.nav_index=0
   var route:Array=valve.route
   var target:Vector2=route[mini(coolant.nav_index,route.size()-1)]
   if absf(player.position.x-target.x)<30 and (player.position.y<=target.y+24 if coolant.nav_index<route.size()-1 else absf(player.position.y-target.y)<24) and player.is_on_floor():
    coolant.nav_index+=1
    if coolant.nav_index>=route.size():interact();return 0
    target=route[coolant.nav_index]
   var dx:float=target.x-player.position.x
   if player.is_on_floor() and target.y<player.position.y-14 and absf(dx)<155:player.begin_action("jump")
   for obstacle in CoolantScript.SOLIDS:
    if player.is_on_floor() and dx>0 and player.position.x>obstacle.position.x-80 and player.position.x<obstacle.end.x+6:player.begin_action("jump")
   return signf(dx) if absf(dx)>14 else 0.0
  for obstacle in CoolantScript.SOLIDS:
   if player.position.x>obstacle.position.x-75 and player.position.x<obstacle.end.x+10 and player.is_on_floor():player.begin_action("jump")
  return 1.0
 var direction=signf(nearest.pos.x-player.position.x)
 if distance<240 and player.state in ["idle","run"]:player.facing=int(direction)
 if nearest.kind=="boss":
  var cue:Dictionary=nearest.boss_wave_hint(self)
  if cue.stage=="jump":player.begin_action("jump")
  if nearest.move_name=="wave" and nearest.state in ["windup","attack"]:
   if absf(player.position.x-nearest.locked_x)<120:return -direction
   return 0
  if nearest.state=="windup":
   if nearest.move_name=="sweep" and nearest.timer<.15:player.begin_action("dodge")
   return direction if distance>220 else 0
  if nearest.state=="attack":return 0
 if not qa_no_items and inventory.counts.bomb>0 and distance>120 and distance<330 and player.state in ["idle","run"]:inventory.use_item("bomb",self)
 if nearest.state=="windup" and nearest.timer<.11 and distance<180:player.begin_action("dodge")
 for machine in CoolantScript.MACHINES:
  if machine.disabled_by in coolant.opened:continue
  if machine.kind=="scan" and absf(player.position.x-machine.pos.x)<90 and coolant.machine_phase(machine)!="off":player.begin_action("dodge")
 if distance<150 and auto_cooldown<=0:
  if nearest.kind=="shield" and nearest.shield>0:player.begin_action("heavy")
  elif player.skill_cd<=0:player.begin_action("skill")
  else:player.begin_action("light")
  auto_cooldown=.24
 if player.state=="light" and player.elapsed>.23:player.begin_action("light")
 return direction if distance>115 else 0.0

func update_effects(dt:float)->void:
 if level_id==2 and mode=="play" and not paused:
  for projectile in projectiles:
   if projectile.get("cold_disc",false):
    projectile.pos.y=minf(FLOOR-18.0,float(projectile.pos.y)+753.0*dt)
 super.update_effects(dt)
