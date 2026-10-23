extends "res://scripts/furnace_boss.gd"
## Third-stage only. The half-health transition never heals, shields, or
## silently cancels damage; a killing hit wins instead of entering phase two.
var transition_count:int=0
var axe_hits:int=0
const EXOSUIT_DAMAGE_SCALE:float=.45
const TRANSITION_TIME:float=1.1
const AXE_WINDUP:float=.82
const AXE_ACTIVE:float=.32
func hit(damage:int,heavy:bool,from_x:float,serial:int,game:Node,ranged:bool=false,contact_point:Variant=null)->bool:
 if game.exosuit.attack_serials.has(serial):damage=maxi(1,roundi(damage*EXOSUIT_DAMAGE_SCALE))
 var accepted:bool=super.hit(damage,heavy,from_x,serial,game,ranged,contact_point)
 if accepted and game.exosuit.attack_serials.has(serial):hitstop=minf(hitstop,.01)
 if accepted and not dead and hp<=max_hp/2 and not phase_two:
  phase_two=true;transition_count+=1;state="transform";timer=TRANSITION_TIME;cycle=0;attack_applied=false
  game.sfx("break");game.add_sparks(pos+Vector2(0,-140),Color("ffca82"),24)
  game.show_status("外装甲破裂！激光斧已展开，观察起手，重斩后反击。",3)
  print("FURNACE_PHASE_TWO hp=",hp," t=",game.run_time)
 return accepted
func boss_tick(dt:float,game:Node)->void:
 if not phase_two:
  super.boss_tick(dt,game);return
 if state=="transform":
  if timer<=0:state="recover";timer=1.4
  return
 var p:SilverwingPlayer=game.player;var dx:float=p.position.x-pos.x
 if state=="windup":
  if timer<=0:
   state="attack";timer=AXE_ACTIVE if move_name=="axe" else .28;attack_applied=false
   if move_name=="wave":
    game.projectiles.append({"pos":pos+Vector2(facing*85,-18),"vx":facing*320.0,"life":3.8,"friendly":false,"damage":16,"radius":22.0,"boss_wave":true,"boss_id":get_instance_id(),"furnace_wave":true});game.sfx("slam")
   elif move_name=="charge":
    for x in [locked_x-115,locked_x+115]:game.furnace.mortars.append({"x":clampf(x,game.left_bound()+70,game.right_bound()-70),"life":.9})
    game.sfx("heavy")
  return
 if state=="attack":
  if move_name=="axe" and timer<=.24 and timer>=.10 and not attack_applied:
   var source:Vector2=pos+Vector2(facing*35,-145)
   var contact:bool=false
   for area in axe_attack_polygons():
    if not Geometry2D.intersect_polygons(area,game._rect_polygon(game.player_body_rect())).is_empty():contact=true
   if contact and game.cover_line_clear(source,p.position+Vector2(0,-55)):
    attack_applied=true;p.damage(22,pos.x,"赤炉激光斧");axe_hits+=1;game.sfx("slam")
  if timer<=0:state="recover";timer=1.4
  return
 if state=="recover":
  if timer<=0:state="approach";timer=.4
  return
 facing=1 if dx>0 else -1
 if absf(dx)>230:pos.x+=facing*78*dt
 if timer<=0:
  move_name=["axe","wave","axe","charge"][cycle%4];cycle+=1;state="windup"
  timer=AXE_WINDUP if move_name=="axe" else (1.05 if move_name=="wave" else 1.1)
  locked_x=p.position.x;game.sfx("warning")
func axe_attack_polygons()->Array:
 # From the registered axe_attack cel's cutting edge. The 12-pixel band
 # follows the visible laser blade; the handle/empty upper canvas cannot hit.
 var result:Array=[]
 var edge:PackedVector2Array=axe_blade_edge()
 for i in edge.size():
  var circle=PackedVector2Array()
  for n in 12:circle.append(edge[i]+Vector2(cos(n*TAU/12),sin(n*TAU/12))*12)
  result.append(circle)
  if i>0:
   var side:Vector2=(edge[i]-edge[i-1]).normalized().orthogonal()*12
   result.append(PackedVector2Array([edge[i-1]+side,edge[i]+side,edge[i]-side,edge[i-1]-side]))
 return result
func axe_blade_edge()->PackedVector2Array:
 var points=PackedVector2Array()
 for native in [Vector2(23,551),Vector2(21,600),Vector2(49,658),Vector2(111,692),Vector2(184,707)]:
  points.append(pos+Vector2((384-native.x)*facing,native.y-710)*265.0/438.0)
 return points
func boss_wave_hint(game:Node)->Dictionary:
 var travelling:Dictionary=super.boss_wave_hint(game)
 if not travelling.text.is_empty():return travelling
 if state=="transform":return {"stage":"transform","text":"外装甲破裂 · 激光斧展开","impact_in":timer}
 if phase_two and state=="windup" and move_name=="axe":return {"stage":"axe","text":"激光斧蓄力 · 退后或闪至身后","impact_in":timer+.08}
 if phase_two and state=="recover":return {"stage":"recover","text":"斧刃冷却 · 现在反击","impact_in":INF}
 return travelling
