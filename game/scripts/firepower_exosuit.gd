class_name FirepowerExosuit
extends RefCounted
const POWER_SECONDS:float=30.0
const MAX_DURABILITY:int=140
const FIRE_INTERVAL:float=.14
var active:bool=false
var remaining:float=0
var durability:int=0
var pod_id:String=""
var elapsed:float=0
var fire_cd:float=0
var heavy_cd:float=0
var shock_cd:float=0
var anim:String="idle"
var anim_time:float=0
var fire_armed:bool=false
var exit_count:int=0
var last_reason:String=""
var shots:Array=[]
var wrecks:Array=[]
var _serial:int=-1000000
var attack_serials:Dictionary={}
var frames:Dictionary={}
var pilots:Dictionary={}
var metadata:Dictionary={}
func load_assets()->void:
 var base="res://assets/exosuit/"
 if not FileAccess.file_exists(base+"manifest.json"):return
 metadata=JSON.parse_string(FileAccess.get_file_as_string(base+"manifest.json"))
 pilots={"silverwing":{},"feiren":{}}
 for action in metadata.get("animations",{}):
  var group:Array=[];var silver:Array=[];var feiren:Array=[]
  for name in metadata.animations[action].frames:
   var entry:Dictionary=metadata.frames[name]
   group.append(load(base+entry.texture))
   silver.append(load(base+entry.pilots.silverwing));feiren.append(load(base+entry.pilots.feiren))
  frames[action]=group;pilots.silverwing[action]=silver;pilots.feiren[action]=feiren
func reset(game)->void:
 if active:exit(game,"reset")
 attack_serials.clear()
 shots.clear();wrecks.clear();remaining=0;durability=0;fire_cd=0;heavy_cd=0;shock_cd=0
func can_enter(game)->bool:
 if game.mode!="play" or game.paused or active or game.player.hp<=0 or not game.player.is_on_floor() or game.player.state not in ["idle","run"]:return false
 var shape=CapsuleShape2D.new();shape.radius=50;shape.height=150
 var q=PhysicsShapeQueryParameters2D.new();q.shape=shape;q.transform=Transform2D(0,game.player.position+Vector2(0,-75));q.collision_mask=1;q.exclude=[game.player.get_rid()]
 return game.get_world_2d().direct_space_state.intersect_shape(q,1).is_empty()
func enter(game,id:String)->bool:
 if id in game.spent_pods:return false
 if not can_enter(game):game.show_status("这里空间不足。回到装甲旁的空地再试。",2);return false
 game.clear_touch();active=true;remaining=POWER_SECONDS;durability=MAX_DURABILITY;pod_id=id;elapsed=0;anim="mount";anim_time=0
 fire_cd=0;heavy_cd=0;shock_cd=0;fire_armed=false
 game.spent_pods.append(id);game.player.set_exosuit_shape(true);game.player.velocity=Vector2.ZERO
 game.save_game();game.sfx("armor_hit");game.show_status("赤隼启动：30秒动力 · J连射 / K重炮 / U震荡 / E退出",4)
 print("EXO_ENTER ",id," time=",game.run_time);return true
func exit(game,reason:String)->bool:
 if not active:return false
 active=false;remaining=maxf(remaining,0);durability=maxi(durability,0);exit_count+=1;last_reason=reason
 game.clear_touch();game.player.set_exosuit_shape(false);game.player.velocity.x*=.3
 game.player.state="dead" if game.player.hp<=0 else ("idle" if game.player.is_on_floor() else "air")
 game.player.invuln=maxf(game.player.invuln,.55)
 if reason!="reset":
  wrecks.append({"pos":game.player.position,"facing":game.player.facing,"life":1.1,"reason":reason})
  game.sfx("explode" if reason=="damage" else "armor_break")
  game.show_status("装甲受损 · 安全脱离" if reason=="damage" else ("动力耗尽 · 安全脱离" if reason=="power" else "已退出装甲 · 本次动力不再补充"),3)
 print("EXO_EXIT ",reason," count=",exit_count," remaining=",remaining," durability=",durability)
 return true
func damage(game,amount:int,source_x:float,cause:String)->bool:
 if not active or not game.player.can_take_damage():return false
 durability=maxi(0,durability-maxi(amount,0));game.player.invuln=.7;game.player.hitstop=.025
 game.player.state="hurt";game.player.elapsed=0;game.player.velocity.x=120*signf(game.player.position.x-source_x)
 game.hits_taken+=1;anim="hurt";anim_time=0
 game.float_text(game.player.position+Vector2(0,-220),"装甲 -%d"%amount,Color("#ffbb7b"));game.sfx("armor_hit");game.kick_shake(3)
 if durability<=0:exit(game,"damage")
 return true
func command(game,action:String)->bool:
 if not active or game.mode!="play" or game.paused or elapsed<.35:return false
 if action=="light":fire_armed=true;return fire(game,false)
 if action=="heavy":return fire(game,true)
 if action=="skill" and shock_cd<=0:
  shock_cd=3.5;_serial-=1;attack_serials[_serial]=true;game.radial_damage(game.player.position+Vector2(0,-55),185,32,_serial,true)
  game.add_sparks(game.player.position+Vector2(0,-35),Color("#ffd59a"),26);game.sfx("slam");game.kick_shake(4);anim="heavy";anim_time=0;return true
 return false
func fire(game,heavy:bool)->bool:
 if not active or elapsed<.35 or (heavy_cd>0 if heavy else fire_cd>0):return false
 if game.player.state in ["hurt","dead"]:return false
 if heavy:heavy_cd=1.2
 else:fire_cd=FIRE_INTERVAL
 anim="heavy" if heavy else "fire";anim_time=0;_serial-=1;attack_serials[_serial]=true
 var origin:Vector2=muzzle(game,heavy);var aim=Vector2(game.player.facing,0);var target=null;var nearest:float=850
 for enemy in game.enemies:
  var forward:float=(enemy.pos.x-origin.x)*game.player.facing
  if not enemy.dead and forward>0 and forward<nearest:target=enemy;nearest=forward
 if target!=null:
  var delta:Vector2=target.pos+Vector2(0,-100 if target.kind=="boss" else -50)-origin
  delta.y=clampf(delta.y,-absf(delta.x)*.35,absf(delta.x)*.35);aim=delta.normalized()
 var speed:float=650.0 if heavy else 1050.0
 # Trace the short breech-to-muzzle segment too: a foe or wall can stand
 # inside the long visual barrel, but a shot must not teleport beyond it.
 var breech=Vector2(game.player.position.x+game.player.facing*40,origin.y)
 var clearance=Rect2(Vector2(minf(breech.x,origin.x)-5,origin.y-5),Vector2(absf(origin.x-breech.x)+10,10))
 var polygon=PackedVector2Array([clearance.position,Vector2(clearance.end.x,clearance.position.y),clearance.end,Vector2(clearance.position.x,clearance.end.y)])
 var blocked:Variant=null;var victim=null;var distance:float=INF
 for enemy in game.enemies:
  if enemy.dead:continue
  var contact:Variant=game.enemy_attack_contact(enemy,polygon,breech)
  if contact!=null and contact.distance_squared_to(breech)<distance:blocked=contact;victim=enemy;distance=contact.distance_squared_to(breech)
 var wall:Dictionary=game.get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(breech,origin,1))
 if not wall.is_empty() and (blocked==null or wall.position.distance_squared_to(breech)<distance):blocked=wall.position;victim=null
 if blocked!=null:
  if heavy:game.radial_damage(blocked,155,72,_serial,true)
  elif victim!=null:victim.hit(8,false,game.player.position.x,_serial,game,true,blocked)
  game.add_sparks(blocked,Color("#ffc878"),10 if heavy else 4);game.sfx("heavy" if heavy else "shoot");return true
 shots.append({"pos":origin,"vx":aim.x*speed,"vy":aim.y*speed,"age":0.0,"life":1.7 if heavy else 1.0,"heavy":heavy,"serial":_serial,"from_x":game.player.position.x})
 game.sfx("heavy" if heavy else "shoot");return true
func muzzle(game,heavy:bool)->Vector2:
 var point=Vector2(570,315) if heavy else Vector2(593,368)
 var key="heavy" if heavy else "fire"
 var group:Dictionary=metadata.get("animations",{}).get(key,{})
 if not group.is_empty():
  var name:String=group.frames[0]
  var value:Variant=metadata.frames[name].muzzles.get("heavy" if heavy else "rotary",[])
  if value is Array and value.size()==2:point=Vector2(value[0],value[1])
 var root:Array=metadata.get("root",[320,592]);var factor=225.0/float(metadata.get("nominal_standing_body_height",420))
 return game.player.position+Vector2((point.x-float(root[0]))*game.player.facing,point.y-float(root[1]))*factor
func tick(dt:float,game)->void:
 if game.mode!="play" or game.paused:return
 for wreck in wrecks:wreck.life-=dt
 wrecks=wrecks.filter(func(w):return w.life>0)
 if active:
  remaining=maxf(0,remaining-dt);elapsed+=dt;anim_time+=dt
  fire_cd=maxf(0,fire_cd-dt);heavy_cd=maxf(0,heavy_cd-dt);shock_cd=maxf(0,shock_cd-dt)
  var held:bool=Input.is_action_pressed("light") or (game.touch_ui and game.touch_ui.enabled and game.touch_ui.owners.has("light"))
  if not held:fire_armed=true
  if held and fire_armed and elapsed>=.35:fire(game,false)
  if remaining<=0:exit(game,"power")
 var survivors:Array=[]
 for shot in shots:
  var old:Vector2=shot.pos;shot.pos+=Vector2(shot.vx,shot.vy)*dt;shot.life-=dt;shot.age=float(shot.get("age",0))+dt
  if shot.life<=0:continue
  var ray=PhysicsRayQueryParameters2D.create(old,shot.pos,1)
  var terrain:Dictionary=game.get_world_2d().direct_space_state.intersect_ray(ray)
  var contact:Variant=null;var victim=null;var closest:float=INF
  var radius:float=13 if shot.heavy else 5
  var travel=Rect2(Vector2(minf(old.x,shot.pos.x)-radius,minf(old.y,shot.pos.y)-radius),Vector2(absf(shot.pos.x-old.x)+radius*2,absf(shot.pos.y-old.y)+radius*2))
  var polygon=PackedVector2Array([travel.position,Vector2(travel.end.x,travel.position.y),travel.end,Vector2(travel.position.x,travel.end.y)])
  for enemy in game.enemies:
   if enemy.dead:continue
   var hit:Variant=game.enemy_attack_contact(enemy,polygon,old)
   if hit!=null and old.distance_squared_to(hit)<closest:contact=hit;victim=enemy;closest=old.distance_squared_to(hit)
  if not terrain.is_empty() and (contact==null or old.distance_squared_to(terrain.position)<closest):contact=terrain.position;victim=null
  if contact==null and shot.heavy and shot.age>=.10:
   # Heavy rockets have an armed proximity fuse; only actual anatomy can
   # trigger it. The subsequent explosion still intersects real body shapes.
   var proximity=PackedVector2Array()
   for i in 16:proximity.append(shot.pos+Vector2.from_angle(TAU*i/16.0)*90)
   for enemy in game.enemies:
    if not enemy.dead and game.enemy_attack_contact(enemy,proximity,shot.pos)!=null:contact=shot.pos;break
  if contact!=null:
   if shot.heavy:game.radial_damage(contact,155,72,shot.serial,true)
   elif victim!=null:victim.hit(8,false,shot.from_x,shot.serial,game,true,contact)
   game.add_sparks(contact,Color("#ffc878"),14 if shot.heavy else 4)
   if shot.heavy:game.sfx("explode");game.kick_shake(4)
  else:survivors.append(shot)
 shots=survivors
func current_action(game)->String:
 if elapsed<.35:return "mount"
 if anim_time<(.35 if anim in ["heavy","hurt"] else .18) and frames.has(anim):return anim
 if not game.player.is_on_floor():return "jump"
 return "walk" if absf(game.player.velocity.x)>15 else "idle"
func draw_at(game,at:Vector2,facing:int,action:String,time:float,pilot:bool=true,tint:Color=Color.WHITE)->void:
 if frames.is_empty():return
 if not frames.has(action):action="idle"
 var group:Array=frames[action]
 if group.is_empty():return
 var index:int=int(time*float(metadata.animations[action].get("fps",7)))
 if action in ["walk","idle","fire"]:index%=group.size()
 else:index=mini(index,group.size()-1)
 var factor:float=225.0/float(metadata.get("nominal_standing_body_height",420));var root:Array=metadata.get("root",[320,592]);var canvas:Array=metadata.get("canvas_size",[640,640])
 var rect=game.sprite_rect_for(at,Vector2(canvas[0],canvas[1])*factor,float(root[1])*factor,facing)
 if pilot and pilots.has(game.selected_character):
  var p:Array=pilots[game.selected_character].get(action,[])
  if not p.is_empty():game.draw_texture_rect(p[mini(index,p.size()-1)],rect,false,tint)
 game.draw_texture_rect(group[index],rect,false,tint)
func draw(game)->void:
 for wreck in wrecks:draw_at(game,wreck.pos,wreck.facing,"destroyed" if wreck.reason=="damage" else "exit",1.1-wreck.life,false,Color(1,1,1,minf(1,wreck.life*2)))
 for shot in shots:
  var color=Color("#ffb14d") if shot.heavy else Color("#fff0bd")
  game.draw_line(shot.pos-Vector2(shot.vx,shot.vy).normalized()*(31 if shot.heavy else 22),shot.pos,color,7 if shot.heavy else 3,true)
  if shot.heavy:game.draw_circle(shot.pos,8,color)
func draw_pod(game,pod:Dictionary,spent:bool)->void:
 if active and pod_id==pod.id:return
 draw_at(game,Vector2(pod.x,game.FLOOR),1,"destroyed" if spent else "parked",0,false,Color(.58,.53,.49,.8) if spent else Color.WHITE)
 game.text_at("赤隼 · 已消耗" if spent else "E / 交互 驾驶赤隼",Vector2(pod.x-95,game.FLOOR-246),20,Color("#f7c48b"))
