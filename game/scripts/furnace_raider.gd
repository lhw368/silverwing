extends "res://scripts/terrain_enemy.gd"
## Third-stage roles retain the original kind, HP and save/drop identifiers.
## All attack contacts use the motion returned by the real CharacterBody2D.

const LANCE_WINDUP:float=.64
const LANCE_SPEED:float=590.0
const LANCE_TIME:float=.34
const MINE_ARM_TIME:float=.85
const MINE_FUSE:float=.70
const MINE_LIFETIME:float=6.2
const MINE_RADIUS:float=90.0
const MAX_MINES:int=2
const DIVE_WINDUP:float=.85
const DIVE_SPEED:float=460.0
const DIVE_TIME:float=.62
const STRAFE_TIMES:Array[float]=[.12,.34]
const STRAFE_SPEED:float=440.0

var mines:Array[Dictionary]=[]
var locked_target:Vector2=Vector2.ZERO
var dive_direction:Vector2=Vector2.ZERO
var _contact_pending:bool=false
var _attack_origin:Vector2=Vector2.ZERO
var _mine_sequence:int=0
var attacks_started:int=0
var attacks_landed:int=0
var mines_deployed:int=0
var mine_blasts:int=0
var strafe_attempts:int=0
var strafe_shots_fired:int=0
var _strafe_mask:int=0
var _pending_strafe:Array[int]=[]

func _init(type:String="melee",point:Vector2=Vector2.ZERO)->void:
 super(type,point)
 # A mine carrier is vulnerable from either side. It is not the old shield unit.
 if kind=="shield":shield=0

func role_key()->String:
 return {"melee":"lancer","shield":"minelayer","drone":"drone"}.get(kind,kind)

func animation_state_key()->String:
 if dead:return "death"
 if state=="stun" or flash>0:return "hurt"
 if state in ["windup","attack","recover"]:return state
 return "move" if absf(actual_motion_x)>8 else "idle"

func tick(dt:float,game:Node)->void:
 if dt<=0 or game.paused or game.mode!="play":return
 if dead:mines.clear()
 else:_tick_mines(dt,game)
 _contact_pending=false
 _pending_strafe.clear()
 var previous:Vector2=pos
 super.tick(dt,game)
 if _contact_pending and not dead and not attack_applied:_resolve_attack_contact(previous,pos,game)
 if not dead and game.mode=="play":
  for shot_index in _pending_strafe:_fire_strafe(shot_index,game)

func release_physics()->void:
 mines.clear()
 super.release_physics()

func hit(damage:int,heavy:bool,from_x:float,serial:int,game:Node,ranged:bool=false,contact_point:Variant=null)->bool:
 var accepted:bool=super.hit(damage,heavy,from_x,serial,game,ranged,contact_point)
 if dead:mines.clear()
 return accepted

func _tick_logic(dt:float,game:Node)->void:
 if knock_time>0:
  pos.x+=knock_speed*minf(dt,knock_time)
  pos.x=clampf(pos.x,game.left_bound()+45,game.right_bound()-45)
  knock_time=maxf(0,knock_time-dt)
 flash=maxf(0,flash-dt)
 if dead:death_timer+=dt;return
 timer-=dt
 if state=="stun":
  if timer<=0:state="approach";timer=.45
  return
 if state=="windup":
  if timer<=0:_begin_attack(game)
  return
 if state=="attack":
  var step:float=minf(dt,maxf(0,timer+dt))
  if kind=="melee":pos.x+=facing*LANCE_SPEED*step;_contact_pending=true
  elif kind=="drone":
   pos.x+=dive_direction.x*DIVE_SPEED*step
   _flight_velocity=dive_direction*DIVE_SPEED*(step/maxf(dt,.000001))
   _contact_pending=true
   for shot_index in STRAFE_TIMES.size():
    if not _strafe_mask&(1<<shot_index) and DIVE_TIME-maxf(0,timer)>=STRAFE_TIMES[shot_index]:
     _strafe_mask|=1<<shot_index;_pending_strafe.append(shot_index)
  pos.x=clampf(pos.x,game.left_bound()+45,game.right_bound()-45)
  if timer<=0:
   state="recover";timer=1.18 if kind=="drone" else (1.1 if kind=="shield" else 1.05)
  return
 if state=="recover":
  if timer<=0:state="approach";timer=1.35 if kind=="shield" else .45
  return
 var delta:Vector2=game.player.position-pos
 facing=1 if delta.x>0 else -1
 var origin:Vector2=pos+Vector2(0,-28 if kind=="drone" else -55)
 var visible:bool=game.cover_line_clear(origin,_player_aim_point(origin,game))
 var reach:float=315 if kind=="drone" else (275 if kind=="melee" else 275)
 var can_attack:bool=visible and absf(delta.x)<=reach and absf(delta.y)<(175 if kind=="drone" else 76)
 if kind=="shield":can_attack=can_attack and mines.size()<MAX_MINES and _mine_drop_point(game)!=null
 if kind=="drone":_move_drone(dt,game,can_attack)
 elif not can_attack:
  pos.x+=facing*(82.0 if kind=="shield" else 137.0)*dt
  _plan_ground_jump(game)
 pos.x=clampf(pos.x,game.left_bound()+45,game.right_bound()-45)
 if can_attack and timer<=0 and game.active_attackers()<2 and absf(pos.x-game.camera_x-640)<700:
  _begin_windup(game)

func _begin_windup(game:Node)->void:
 state="windup";attack_applied=false;attacks_started+=1
 _strafe_mask=0
 locked_x=game.player.position.x
 locked_target=_player_aim_point(pos+Vector2(0,-28 if kind=="drone" else -55),game)
 _attack_origin=pos
 timer=DIVE_WINDUP if kind=="drone" else (.9 if kind=="shield" else LANCE_WINDUP)
 if kind=="drone":
  dive_direction=(locked_target-(pos+Vector2(0,-28))).normalized()
  if dive_direction.length_squared()<.1:dive_direction=Vector2(facing,.2).normalized()
 elif kind=="shield":
  var target:Variant=_mine_drop_point(game)
  if target!=null:locked_target=target
 game.sfx("warning")

func _begin_attack(game:Node)->void:
 state="attack";attack_applied=false
 timer=DIVE_TIME if kind=="drone" else (.22 if kind=="shield" else LANCE_TIME)
 if kind=="shield":
  _deploy_mine(game);attack_applied=true
 else:game.sfx("swing")

func _resolve_attack_contact(previous:Vector2,current:Vector2,game:Node)->void:
 # One swept contact per attack, even if the player dodges or remains overlapping.
 # Cover is checked from the body's side as well as along the weapon's path.
 var offset:Vector2=Vector2(facing*39,-55) if kind=="melee" else Vector2(0,-28)
 var start:Vector2=previous+offset;var end:Vector2=current+offset
 var hit_result:Dictionary=game._sweep_circle_polygon(start,end,22 if kind=="melee" else 29,game._rect_polygon(game.player_body_rect()))
 if hit_result.is_empty():return
 var source:Vector2=previous+Vector2(0,-55 if kind=="melee" else -28)
 if not game.cover_line_clear(source,hit_result.contact):return
 if not game.cover_line_clear(start,hit_result.contact):return
 attack_applied=true
 if game.player.damage(11 if kind=="melee" else 10,previous.x,"突刺机兵冲锋" if kind=="melee" else "无人机俯冲"):
  attacks_landed+=1
 game.add_sparks(hit_result.contact,Color("#ffd186"),7)

func _fire_strafe(shot_index:int,game:Node)->void:
 # Two scheduled shots aim at the original marker. Emission follows physics,
 # so a stopped dive cannot carry its muzzle through a wall in the same frame.
 strafe_attempts+=1
 var source:Vector2=pos+Vector2(0,-28)
 var aim:Vector2=(locked_target-source).normalized()
 if aim.length_squared()<.1:aim=dive_direction
 var muzzle:Vector2=source+aim*32
 var wall:Dictionary=game.terrain_sweep(source,muzzle,5)
 if not wall.is_empty():
  game.add_sparks(wall.contact,Color("#ffc878"),5);return
 game.projectiles.append({"pos":muzzle,"vx":aim.x*STRAFE_SPEED,"vy":aim.y*STRAFE_SPEED,"life":1.2,"friendly":false,"damage":7,"radius":5.0,"furnace_strafe":true,"owner":get_instance_id(),"volley":shot_index})
 strafe_shots_fired+=1;game.sfx("shoot")

func _move_drone(dt:float,game:Node,can_attack:bool)->void:
 # Cruise high enough to show a downward dive, but route around actual decks.
 # The visibility graph inherited from terrain_enemy uses solid body clearance.
 var target:Vector2=game.player.position+Vector2(0,-100)
 # Low one-way bridges allow bodies below their deck. Cruise below the deck
 # when the usual high target would put the drone on the player's other side.
 for item in game.terrain_rects():
  var rect:Rect2=item.rect
  if item.one_way and game.player.position.x>=rect.position.x and game.player.position.x<=rect.end.x and game.player.position.y>rect.end.y+8 and target.y<rect.end.y+62:
   target.y=minf(game.FLOOR-4,game.player.position.y-4)
 target.x=clampf(target.x,game.left_bound()+55,game.right_bound()-55)
 if not _drone_route.is_empty() and absf(game.player.position.y-_route_player_y)>95:_drone_route.clear()
 if _drone_route.is_empty() and not _drone_body_clear(pos,target,game):_build_drone_route(target,game)
 var destination:Vector2=target
 if not _drone_route.is_empty():
  destination=_drone_route[0]
  if pos.distance_to(destination)<8:
   _drone_route.pop_front();destination=_drone_route[0] if not _drone_route.is_empty() else target
 var difference:Vector2=destination-pos
 var motion:Vector2=Vector2.ZERO
 if not _drone_route.is_empty():motion=difference.normalized()*125.0
 else:
  motion.y=clampf(difference.y*3,-125,125)
  if not can_attack:motion.x=signf(difference.x)*125.0
  elif absf(game.player.position.x-pos.x)<170:motion.x=-facing*42.0
 _flight_velocity=motion;pos.x+=motion.x*dt

func _player_aim_point(origin:Vector2,game:Node)->Vector2:
 # An old bridge can overlap the upper part of the player's body from below.
 # Select an actually exposed body point instead of aiming inside its deck.
 for height in [-48.0,-24.0,-72.0]:
  var candidate:Vector2=game.player.position+Vector2(0,height)
  if game.cover_line_clear(origin,candidate):return candidate
 return game.player.position+Vector2(0,-48)

func _drone_body_clear(a:Vector2,b:Vector2,game:Node)->bool:
 return _route_clear(a,b,game.terrain_rects(),game)

func _route_clear(a:Vector2,b:Vector2,rects:Array,game:Node)->bool:
 for item in rects:
  var rect:Rect2=item.rect
  # Match one-way physics from the underside. A drone must still reach a
  # deck's edge before descending from above, but may travel beneath it.
  if item.one_way and minf(a.y,b.y)>rect.end.y+8:continue
  if not game._sweep_circle_polygon(a+Vector2(0,-28),b+Vector2(0,-28),29,game._rect_polygon(rect)).is_empty():return false
 return true

func _build_drone_route(target:Vector2,game:Node)->void:
 _drone_route.clear();_route_player_y=game.player.position.y
 var rects:Array=game.terrain_rects()
 if _route_clear(pos,target,rects,game):return
 var points:Array[Vector2]=[pos,target]
 var left:float=game.left_bound()+45;var right:float=game.right_bound()-45
 for item in rects:
  var rect:Rect2=item.rect
  if rect.position.y>=game.FLOOR-.1 or rect.end.x<left or rect.position.x>right:continue
  if rect.end.x<minf(pos.x,target.x)-600 or rect.position.x>maxf(pos.x,target.x)+600:continue
  for x in [rect.position.x-40.0,rect.end.x+40.0]:
   for y in [rect.position.y-6.0,minf(rect.end.y+63.0,game.FLOOR-4.0)]:
    var point:Vector2=Vector2(x,y)
    if x>=left and x<=right and _route_clear(point,point,rects,game):points.append(point)
 var cost:Array[float]=[];var previous:Array[int]=[];var visited:Array[bool]=[]
 for _i in points.size():cost.append(INF);previous.append(-1);visited.append(false)
 cost[0]=0
 for _iteration in points.size():
  var next:int=-1;var smallest:float=INF
  for i in points.size():
   if not visited[i] and cost[i]<smallest:next=i;smallest=cost[i]
  if next<0:return
  if next==1:break
  visited[next]=true
  for i in points.size():
   if visited[i] or i==next:continue
   var distance:float=cost[next]+points[next].distance_to(points[i])
   if distance>=cost[i] or not _route_clear(points[next],points[i],rects,game):continue
   cost[i]=distance;previous[i]=next
 if previous[1]<0:return
 var index:int=1
 while index>0:
  _drone_route.push_front(points[index]);index=previous[index]

func _mine_drop_point(game:Node)->Variant:
 if not is_instance_valid(physics_body) or not physics_body.is_on_floor():return null
 var x:float=clampf(pos.x+facing*55,game.left_bound()+35,game.right_bound()-35)
 var start:Vector2=Vector2(x,pos.y-22)
 if not game.cover_line_clear(pos+Vector2(0,-22),start):return null
 var ground:Dictionary=game.terrain_sweep(start,start+Vector2(0,60))
 if ground.is_empty() or absf(ground.contact.y-pos.y)>28:return null
 var point:Vector2=Vector2(x,ground.contact.y-3)
 for mine in mines:
  if Vector2(mine.pos).distance_to(point)<72:return null
 return point

func _deploy_mine(game:Node)->void:
 if mines.size()>=MAX_MINES:return
 var point:Variant=_mine_drop_point(game)
 if point==null:return
 _mine_sequence+=1;mines_deployed+=1
 mines.append({"id":_mine_sequence,"pos":point,"age":0.0,"fuse":-1.0,"blast":0.0,"spent":false})
 game.add_sparks(point,Color("#ffcb73"),5)

func _tick_mines(dt:float,game:Node)->void:
 var survivors:Array[Dictionary]=[]
 for mine in mines:
  mine.age+=dt
  if mine.spent:
   mine.blast=maxf(0,mine.blast-dt)
   if mine.blast>0:survivors.append(mine)
   continue
  if mine.age>=MINE_LIFETIME:continue # Safe timed expiry, never a surprise blast.
  if mine.fuse>=0:
   mine.fuse-=dt
   if mine.fuse<=0:
    mine.spent=true;mine.blast=.24;_explode_mine(mine,game)
  elif mine.age>=MINE_ARM_TIME:
   var nearest:Vector2=game._closest_polygon_point(mine.pos,game._rect_polygon(game.player_body_rect()))
   if Vector2(mine.pos).distance_to(nearest)<58 and game.cover_line_clear(mine.pos,nearest):
    mine.fuse=MINE_FUSE;game.sfx("warning")
  survivors.append(mine)
 mines=survivors

func _explode_mine(mine:Dictionary,game:Node)->void:
 mine_blasts+=1
 var origin:Vector2=mine.pos+Vector2(0,-8)
 var nearest:Vector2=game._closest_polygon_point(origin,game._rect_polygon(game.player_body_rect()))
 if origin.distance_to(nearest)<=MINE_RADIUS and game.cover_line_clear(origin,nearest):
  game.player.damage(12,origin.x,"布雷机兵感应雷")
 game.add_sparks(origin,Color("#ffc06c"),18);game.sfx("explode")

func draw_extra(game:Node)->void:
 # Essential danger cues stay visible with optional particle effects disabled.
 for mine in mines:
  var at:Vector2=mine.pos
  var warning:bool=mine.fuse>=0
  var color:Color=Color("#ff6a4e") if warning else Color("#ffc975")
  if mine.spent:
   game.draw_circle(at,MINE_RADIUS,Color(1,.35,.1,.18*mine.blast/.24))
   game.draw_arc(at,MINE_RADIUS,PI,TAU,24,Color(1,.72,.35,mine.blast/.24),3)
  else:
   game.draw_circle(at+Vector2(0,-4),9,Color("#523228"))
   game.draw_line(at+Vector2(-10,-3),at+Vector2(10,-3),color,4)
   game.draw_circle(at+Vector2(0,-7),3,color)
   if warning:
    game.draw_arc(at,MINE_RADIUS,PI,TAU,24,color,2)
    game.draw_line(at+Vector2(-MINE_RADIUS,0),at+Vector2(MINE_RADIUS,0),color,2)
    game.text_at("感应雷 · 离开",at+Vector2(-48,-104),15,color)
   elif mine.age<MINE_ARM_TIME:
    game.draw_arc(at,16,PI,PI+PI*mine.age/MINE_ARM_TIME,12,color,2)
 if dead:return
 if state=="windup":
  if kind=="melee":
   var start:Vector2=pos+Vector2(0,-7)
   var end:Vector2=start+Vector2(facing*(LANCE_SPEED*LANCE_TIME+50),0)
   var wall:Dictionary=game.terrain_sweep(start,end,0)
   if not wall.is_empty():end=wall.contact
   game.draw_line(start,end,Color("#ffb367"),3)
   game.draw_line(end,end+Vector2(-facing*14,-8),Color("#ffb367"),3)
   game.text_at("突刺预警",pos+Vector2(-40,-190),16,Color("#ffe0a2"))
  elif kind=="drone":
   var at:Vector2=locked_target
   game.draw_arc(at,24,0,TAU,24,Color("#ffbe6c"),2)
   for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:game.draw_line(at+direction*17,at+direction*32,Color("#ffce7f"),2)
   game.draw_line(pos+Vector2(0,-28),at,Color(1,.66,.3,.5),2)
   game.draw_line(Vector2(at.x,game.player.position.y-4),Vector2(at.x,game.player.position.y-20),Color("#ffbe6c"),3)
   game.text_at("俯冲锁定",at+Vector2(-38,-42),16,Color("#ffe0a2"))
  else:
   game.draw_arc(locked_target,18,PI,TAU,12,Color("#ffce7f"),2)
   game.text_at("布雷预警",pos+Vector2(-40,-211),16,Color("#ffe0a2"))
 elif state=="attack" and kind=="drone":
  var center:Vector2=pos+Vector2(0,-28)
  game.draw_line(center-dive_direction*70,center-dive_direction*28,Color("#ffba68"),5)
 elif state=="recover":
  game.text_at("反击窗口",pos+Vector2(-36,-121 if kind=="drone" else -190),15,Color("#a9e8cf"))
