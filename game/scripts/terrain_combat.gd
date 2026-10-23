extends "res://scripts/rescue_campaign.gd"
## Third-stage cover queries share the real collision geometry. The first two
## stages keep their original combat code, timing, damage and boss anatomy.

class CoverExosuit extends "res://scripts/firepower_exosuit.gd":
 func tick(dt:float,game)->void:
  if game.level_id!=3:super.tick(dt,game);return
  if game.mode!="play" or game.paused:return
  # Preserve the original timers and held-fire behavior while ensuring each
  # newly emitted shot also receives exactly one continuous collision pass.
  for wreck in wrecks:wreck.life-=dt
  wrecks=wrecks.filter(func(w):return w.life>0)
  if active:
   remaining=maxf(0,remaining-dt);elapsed+=dt;anim_time+=dt
   fire_cd=maxf(0,fire_cd-dt);heavy_cd=maxf(0,heavy_cd-dt);shock_cd=maxf(0,shock_cd-dt)
   var held:bool=Input.is_action_pressed("light") or (game.touch_ui and game.touch_ui.enabled and game.touch_ui.owners.has("light"))
   if not held:fire_armed=true
   if held and fire_armed and elapsed>=.35:fire(game,false)
   if remaining<=0:exit(game,"power")
  shots=game.advance_cover_exosuit_shots(shots,dt)

var cover_impact_events:Array=[]

func _cover_impact(point:Vector2,color:Color,count:int)->void:
 cover_impact_events.append(point)
 if cover_impact_events.size()>64:cover_impact_events.pop_front()
 add_sparks(point,color,count)

func _ready()->void:
 exosuit=CoverExosuit.new()
 super._ready()

func terrain_rects()->Array:
 var result:Array=[]
 if not is_instance_valid(world_geometry):return result
 for body in world_geometry.get_children():
  if not body is StaticBody2D or not body.collision_layer&1:continue
  for collider in body.get_children():
   if not collider is CollisionShape2D or collider.disabled or not collider.shape is RectangleShape2D:continue
   var size:Vector2=collider.shape.size*collider.global_scale.abs()
   result.append({"rect":Rect2(collider.global_position-size*.5,size),"one_way":collider.one_way_collision})
 return result

func _rect_polygon(rect:Rect2)->PackedVector2Array:
 return PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])

func cover_enemy_polygons(enemy)->Array:
 if enemy.kind=="boss":return boss_body_polygons(enemy)
 var height:float=65.0 if enemy.kind=="drone" else 100.0
 return [_rect_polygon(Rect2(enemy.pos+Vector2(-27,-height),Vector2(54,height)))]

func _closest_polygon_point(point:Vector2,polygon:PackedVector2Array)->Vector2:
 if Geometry2D.is_point_in_polygon(point,polygon):return point
 var best:Vector2=polygon[0];var distance:float=INF
 for i in polygon.size():
  var candidate:Vector2=Geometry2D.get_closest_point_to_segment(point,polygon[i],polygon[(i+1)%polygon.size()])
  var d:float=point.distance_squared_to(candidate)
  if d<distance:best=candidate;distance=d
 return best

func _segment_circle_time(start:Vector2,motion:Vector2,center:Vector2,radius:float)->float:
 var offset:Vector2=start-center;var a:float=motion.length_squared();var c:float=offset.length_squared()-radius*radius
 if c<=0:return 0.0
 if a<.0000001:return INF
 var b:float=offset.dot(motion);var discriminant:float=b*b-a*c
 if discriminant<0:return INF
 var time:float=(-b-sqrt(discriminant))/a
 return time if time>=0 and time<=1 else INF

func _sweep_circle_polygon(start:Vector2,end:Vector2,radius:float,polygon:PackedVector2Array)->Dictionary:
 if polygon.size()<3:return {}
 var nearest:Vector2=_closest_polygon_point(start,polygon)
 if start.distance_squared_to(nearest)<=radius*radius+.000001:return {"t":0.0,"center":start,"contact":nearest}
 var motion:Vector2=end-start;var best:float=INF
 for i in polygon.size():
  var a:Vector2=polygon[i];var b:Vector2=polygon[(i+1)%polygon.size()];var edge:Vector2=b-a
  best=minf(best,_segment_circle_time(start,motion,a,radius))
  var length:float=edge.length()
  if length<.000001:continue
  var tangent:Vector2=edge/length;var normal:Vector2=Vector2(-tangent.y,tangent.x)
  var travel:float=motion.dot(normal)
  if absf(travel)<.000001:continue
  for side in [-1.0,1.0]:
   var time:float=(side*radius-(start-a).dot(normal))/travel
   if time<0 or time>1 or time>=best:continue
   var along:float=(start+motion*time-a).dot(tangent)
   if along>=0 and along<=length:best=time
 if is_inf(best):return {}
 var center:Vector2=start+motion*best
 return {"t":best,"center":center,"contact":_closest_polygon_point(center,polygon)}

func terrain_sweep(start:Vector2,end:Vector2,radius:float=0.0,ignore_floor:bool=false)->Dictionary:
 var best:Dictionary={}
 for item in terrain_rects():
  var rect:Rect2=item.rect
  if ignore_floor and rect.position.y>=FLOOR-.1:continue
  var hit:Dictionary=_sweep_circle_polygon(start,end,maxf(radius,0.0),_rect_polygon(rect))
  if not hit.is_empty() and (best.is_empty() or hit.t<best.t):best=hit;best.rect=rect
 return best

func cover_line_clear(start:Vector2,end:Vector2)->bool:
 # Inset a fraction of a pixel so explosions on a wall face can hit their own
 # side. A ray entering the wall still immediately meets its interior.
 for item in terrain_rects():
  var rect:Rect2=item.rect
  if rect.size.x<=.1 or rect.size.y<=.1:continue
  var hit:Dictionary=_sweep_circle_polygon(start,end,0.0,_rect_polygon(rect.grow(-.045)))
  if not hit.is_empty() and hit.t<.9999:return false
 return true

func enemy_attack_contact(enemy,shape:PackedVector2Array,source:Vector2)->Variant:
 if level_id!=3:return super.enemy_attack_contact(enemy,shape,source)
 var best:Variant=null;var distance:float=INF
 for body in cover_enemy_polygons(enemy):
  for overlap in Geometry2D.intersect_polygons(shape,body):
   for i in overlap.size():
    var a:Vector2=overlap[i];var b:Vector2=overlap[(i+1)%overlap.size()]
    for candidate in [Geometry2D.get_closest_point_to_segment(source,a,b),a,(a+b)*.5]:
     var d:float=source.distance_squared_to(candidate)
     if d<distance and cover_line_clear(source,candidate):best=candidate;distance=d
 return best

func _player_melee_contact(enemy,shape:PackedVector2Array,source:Vector2)->Variant:
 # One-way catwalks may legally overlap a standing body's torso. Only melee
 # may move its source to the exposed part of that same body and same tier.
 # Explosions, projectile clearance and ranged contacts never call this helper.
 if absf(enemy.pos.y-player.position.y)>=45.0:return enemy_attack_contact(enemy,shape,source)
 var geometry:Array=terrain_rects();var containing:Array=[];var exposed:Vector2=source
 for entry in geometry:
  var rect:Rect2=entry.rect
  if not rect.grow(-.045).has_point(source):continue
  if not entry.one_way or rect.size.y>32.0:return enemy_attack_contact(enemy,shape,source)
  containing.append(rect);exposed.y=maxf(exposed.y,rect.end.y+2.0)
 if containing.is_empty():return enemy_attack_contact(enemy,shape,source)
 if not player_body_rect().has_point(exposed) or not Geometry2D.is_point_in_polygon(exposed,shape):return null
 for entry in geometry:
  var rect:Rect2=entry.rect
  # The adjustment can leave only the already-overlapping thin one-way slab.
  # It cannot jump over a solid or a different platform inside the character.
  if rect in containing and entry.one_way:continue
  if not _sweep_circle_polygon(source,exposed,0.0,_rect_polygon(rect.grow(-.045))).is_empty():return null
 return enemy_attack_contact(enemy,shape,exposed)

func radial_damage(point:Vector2,radius:float,damage:int,serial:int,heavy:bool)->void:
 if level_id!=3:super.radial_damage(point,radius,damage,serial,heavy);return
 super.radial_damage(point,radius,damage,serial,heavy)

func player_strike(kind:String,combo:int,serial:int,first_active_tick:bool=true)->void:
 if level_id!=3:super.player_strike(kind,combo,serial,first_active_tick);return
 if player.hp<=0 or mode!="play":return
 if kind=="skill" and selected_character=="feiren" and not exosuit.active:
  var shape:PackedVector2Array=melee_attack_polygon("heavy")
  for enemy in enemies:
   if enemy.dead:continue
   var contact:Variant=_player_melee_contact(enemy,shape,player.position+Vector2(0,-65))
   if contact!=null:enemy.hit(42,true,player.position.x,serial,self,false,contact)
  if first_active_tick:add_sparks(player.position+Vector2(player.facing*70,-65),Color("#ffb54e"),22);sfx("heavy")
  return
 if first_active_tick:sfx("swing" if kind=="light" else kind)
 if kind=="skill":
  if not first_active_tick:return
  var source:Vector2=player.position+Vector2(0,-60)
  var muzzle:Vector2=source+Vector2(player.facing*40,0)
  var wall:Dictionary=terrain_sweep(source,muzzle,36)
  if not wall.is_empty():_cover_impact(wall.contact,CYAN,10)
  else:projectiles.append({"pos":muzzle,"vx":player.facing*640.0,"vy":0.0,"life":.85,"friendly":true,"damage":24,"radius":36.0,"serial":serial,"from_x":player.position.x})
 else:
  var damage:int=[10,10,18][combo-1] if kind=="light" else 28
  var shape:PackedVector2Array=melee_attack_polygon(kind)
  for enemy in enemies:
   if enemy.dead:continue
   var contact:Variant=_player_melee_contact(enemy,shape,player.position+Vector2(0,-65))
   if contact!=null:enemy.hit(damage,kind=="heavy",player.position.x,serial,self,false,contact)
 if first_active_tick:slashes.append({"pos":player.position+Vector2(player.facing*65,-65),"facing":player.facing,"life":.12 if kind=="light" else .14,"heavy":kind=="heavy","combo":combo})

func _sweep_enemy(enemy,start:Vector2,end:Vector2,radius:float)->Dictionary:
 var best:Dictionary={}
 for body in cover_enemy_polygons(enemy):
  var hit:Dictionary=_sweep_circle_polygon(start,end,radius,body)
  if not hit.is_empty() and (best.is_empty() or hit.t<best.t):best=hit
 return best

func update_effects(dt:float)->void:
 if level_id!=3:super.update_effects(dt);return
 var survivors:Array=[]
 for shot in projectiles:
  if shot.life<=0:continue
  var old:Vector2=shot.pos
  var end:Vector2=old+Vector2(shot.vx,shot.get("vy",0.0))*minf(dt,maxf(0.0,shot.life))
  var wall:Dictionary=terrain_sweep(old,end,shot.radius,shot.get("boss_wave",false))
  var limit:float=wall.t if not wall.is_empty() else INF
  if shot.friendly:
   for enemy in enemies:
    if enemy.dead or enemy.hit_serials.has(int(shot.serial)):continue
    var hit:Dictionary=_sweep_enemy(enemy,old,end,shot.radius)
    if not hit.is_empty() and hit.t<limit-.00001 and cover_line_clear(old,hit.contact):
     enemy.hit(int(shot.damage),false,shot.get("from_x",old.x-shot.vx),shot.serial,self,true,hit.contact)
  else:
   var hit:Dictionary=_sweep_circle_polygon(old,end,shot.radius,_rect_polygon(player_body_rect()))
   if not hit.is_empty() and hit.t<limit-.00001 and cover_line_clear(old,hit.contact):
    player.damage(int(shot.damage),old.x-shot.vx,"地面震波" if shot.get("boss_wave",false) else "无人机射击")
    add_sparks(hit.contact,ORANGE,5);shot.life=0.0
  shot.life-=dt
  if not wall.is_empty():
   shot.pos=wall.center;shot.life=0.0;_cover_impact(wall.contact,CYAN if shot.friendly else ORANGE,8)
  else:shot.pos=end
  if shot.life>0:survivors.append(shot)
 # Preserve exactly one update of inherited sparks/text/slashes. Passing an
 # empty projectile list prevents the old discrete collision pass firing twice.
 projectiles=[];super.update_effects(dt);projectiles=survivors

func advance_cover_exosuit_shots(shots:Array,dt:float)->Array:
 var survivors:Array=[]
 for shot in shots:
  if shot.life<=0:continue
  var old:Vector2=shot.pos
  var end:Vector2=old+Vector2(shot.vx,shot.vy)*minf(dt,maxf(0.0,shot.life))
  shot.life-=dt;shot.age=float(shot.get("age",0.0))+dt
  var radius:float=13.0 if shot.heavy else 5.0
  var wall:Dictionary=terrain_sweep(old,end,radius)
  var limit:float=wall.t if not wall.is_empty() else INF
  var contact:Variant=null;var victim=null;var best:float=limit
  for enemy in enemies:
   if enemy.dead:continue
   var hit:Dictionary=_sweep_enemy(enemy,old,end,radius)
   if not hit.is_empty() and hit.t<best-.00001 and cover_line_clear(old,hit.contact):best=hit.t;contact=hit.contact;victim=enemy
  if contact==null and not wall.is_empty():contact=wall.contact
  if contact==null and shot.heavy and shot.age>=.10:
   var proximity:PackedVector2Array=PackedVector2Array()
   for i in 16:proximity.append(end+Vector2.from_angle(TAU*i/16.0)*90)
   for enemy in enemies:
    if not enemy.dead and enemy_attack_contact(enemy,proximity,end)!=null:contact=end;break
  if contact!=null:
   if shot.heavy:radial_damage(contact,155,72,shot.serial,true)
   elif victim!=null:victim.hit(8,false,shot.from_x,shot.serial,self,true,contact)
   add_sparks(contact,Color("#ffc878"),14 if shot.heavy else 4)
   if shot.heavy:sfx("explode");kick_shake(4)
  elif shot.life>0:shot.pos=end;survivors.append(shot)
 return survivors
