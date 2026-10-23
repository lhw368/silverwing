extends "res://scripts/furnace_presentation.gd"
## v0.9: encounters are independent occupants, never player bounds.
## Only physical world edges and unoperated devices constrain traversal.
const SkillPresentationScript=preload("res://scripts/skill_presentation.gd")
var skill_vfx=SkillPresentationScript.new()
const RoadTrapsScript=preload("res://scripts/road_traps.gd")
var encounter_waves:Dictionary={}
var road_traps=RoadTrapsScript.new()
var _spawning_encounter:int=-1

func apply_level(id:int)->void:
 WORLD_END=17600.0 if id==3 else LevelData.WORLD_END
 super.apply_level(id)

func clear_combat()->void:
 encounter_waves.clear()
 if skill_vfx:skill_vfx.reset()
 if road_traps:road_traps.reset()
 super.clear_combat()

func left_bound()->float:return 35.0
func right_bound()->float:
 var bound:float=WORLD_END-35.0
 if level_id==1:return relays.right_bound(bound)
 if level_id==2:return coolant.right_bound(bound)
 return furnace.right_bound(bound,self)

func spawn_wave(wave:Array)->void:
 var first:int=enemies.size()
 super.spawn_wave(wave)
 for index in range(first,enemies.size()):
  enemies[index].set_meta("encounter_zone",_spawning_encounter if _spawning_encounter>=0 else active_zone)

func encounter_alive(id:int)->int:
 var result:int=0
 for enemy in enemies:
  if not enemy.dead and int(enemy.get_meta("encounter_zone",-1))==id:result+=1
 return result

func _spawn_encounter_wave(id:int,index:int)->void:
 _spawning_encounter=id
 var previous:int=active_zone
 active_zone=id;wave_index=index
 spawn_wave(zones[id].waves[index])
 active_zone=previous;_spawning_encounter=-1
 encounter_waves[id]=index

func update_zones()->void:
 if mode!="play":return
 # Resolve each started encounter independently. Old enemies never block the
 # next trigger, a device interaction, a checkpoint, or a dead Boss's result.
 for id in encounter_waves.keys():
  if id in completed_zones or encounter_alive(id)>0:continue
  var next:int=int(encounter_waves[id])+1
  if next<zones[id].waves.size():_spawn_encounter_wave(id,next)
  else:
   completed_zones.append(id)
   print("ZONE_CLEAR ",id," t=",run_time)
   if id==zones.size()-1:
    victory();return
 for id in zones.size():
  if id in completed_zones or encounter_waves.has(id) or player.position.x<float(zones[id].start):continue
  _spawn_encounter_wave(id,0)
  print("ZONE_START %d t=%.2f"%[id,run_time])
  show_status(zones[id].name+" · 可继续前进或迎战",2.8)
  zone_hint=zones[id].get("hint","");zone_hint_timer=6.0
  if id==zones.size()-1:
   dialogue_timer=0;set_boss_music()
   if level_id==3:show_status("撤离守卫 · 重装耐弹结构，装甲火力效能45%。破甲后观察激光斧起手。",5)
 active_zone=-1
 var nearest:float=INF
 for id in encounter_waves:
  if id in completed_zones:continue
  var z:Dictionary=zones[id]
  if player.position.x<float(z.left)-160 or player.position.x>float(z.right)+160:continue
  var score:float=absf(player.position.x-(float(z.left)+float(z.right))*.5)
  if score<nearest:nearest=score;active_zone=id

func update_relay_guards()->void:
 # Relay terminals now control only their own power circuit. No extra guard
 # is created as a hidden prerequisite for operating the second terminal.
 pass

func interact()->void:
 if mode!="play" or paused:return
 if level_id!=1:super.interact();return
 if relays.interact(self):return
 var middle:bool=absf(player.position.x-LevelData.NPC_X)<160 and relays.is_station_open(0) and relays.is_station_open(1)
 var core:bool=absf(player.position.x-CORE_NPC_X)<135 and relays.is_station_open(2)
 if not (middle or core) or not player.is_on_floor():return
 checkpoint=2 if core else 1;saved_checkpoint=checkpoint;saved_level_id=1;saved_has_run=true
 player.hp=100;player.skill_cd=0;dialogue_timer=9.0
 drop_checkpoint=battle_drops.capture_checkpoint()
 save_game();sfx("checkpoint");show_status("检查点已保存 · 生命与技能恢复",3)

func _physics_process(dt:float)->void:
 super._physics_process(dt)
 road_traps.tick(dt,self)
 skill_vfx.tick(dt,self)

func draw_world()->void:
 super.draw_world()
 road_traps.draw(self)

func autopilot(dt:float)->float:
 var axis:float=super.autopilot(dt)
 # QA uses the same jump action as a player, never disables trap damage.
 if player.is_on_floor() and absf(axis)>.1:
  for trap in road_traps.layout(level_id):
   var distance:float=(float(trap.x)-player.position.x)*signf(axis)
   if distance>24 and distance<118:player.begin_action("jump")
 return axis

func player_strike(kind:String,combo:int,serial:int,first_active_tick:bool=true)->void:
 if kind=="skill" and first_active_tick:skill_vfx.on_skill(self,serial)
 super.player_strike(kind,combo,serial,first_active_tick)

func enemy_hit_feedback(enemy:StarportEnemy,damage:int,heavy:bool,source_x:float,serial:int,ranged:bool,blocked:bool,armor_broken:bool,contact_point:Variant=null)->void:
 skill_vfx.on_hit(self,serial,contact_point if contact_point!=null else enemy.pos+Vector2(0,-55),blocked)
 super.enemy_hit_feedback(enemy,damage,heavy,source_x,serial,ranged,blocked,armor_broken,contact_point)

func draw_hero()->void:
 skill_vfx.draw_back(self)
 super.draw_hero()

func draw_effects()->void:
 super.draw_effects()
 skill_vfx.draw(self)
