extends "res://scripts/enemy.gd"
## Only the third stage instantiates this enemy. Positions come back from
## CharacterBody2D.move_and_slide; route planning never teleports the body.
var _jump_requested:bool=false
var _flight_velocity:Vector2=Vector2.ZERO
var _locked_aim:Vector2=Vector2.LEFT
var _drone_route:Array[Vector2]=[]
var _route_player_y:float=0
var navigation_jumps:int=0
var navigation_distance_y:float=0.0

func tick(dt:float,game:Node)->void:
 _jump_requested=false;_flight_velocity=Vector2.ZERO
 super.tick(dt,game)

func _resolve_physics(displacement:Vector2,dt:float)->void:
 if not is_instance_valid(physics_body):return
 physics_body.velocity.x=displacement.x/maxf(dt,.000001)
 if kind=="drone":
  physics_body.velocity.y=_flight_velocity.y
  physics_body.motion_mode=CharacterBody2D.MOTION_MODE_FLOATING
 else:
  if _jump_requested and physics_body.is_on_floor():physics_body.velocity.y=-660.0;navigation_jumps+=1
  physics_body.velocity.y+=1750.0*dt
 var previous:Vector2=physics_body.position
 physics_body.move_and_slide();pos=physics_body.position
 navigation_distance_y+=absf(pos.y-previous.y)

func _tick_logic(dt:float,game:Node)->void:
 if game.level_id!=3 or kind=="boss":super._tick_logic(dt,game);return
 if knock_time>0:
  pos.x+=knock_speed*minf(dt,knock_time);pos.x=clampf(pos.x,game.left_bound()+45,game.right_bound()-45);knock_time=maxf(0,knock_time-dt)
 flash=maxf(0,flash-dt)
 if dead:death_timer+=dt;return
 timer-=dt
 var p:SilverwingPlayer=game.player
 var delta:Vector2=p.position-pos
 if state=="stun":
  if timer<=0:state="approach";timer=.3
  return
 if state=="windup":
  if timer<=0:
   state="attack";timer=.20
   if kind=="drone":_fire_drone(game)
   elif absf(delta.x)<114 and absf(delta.y)<70 and delta.x*facing>=-20 and game.cover_line_clear(pos+Vector2(0,-55),p.position+Vector2(0,-50)):
    p.damage(12 if kind=="shield" else 8,pos.x,"盾兵撞击" if kind=="shield" else "机兵挥击")
   game.add_sparks(pos+Vector2(facing*70,-55),Color("#ffab6b"),5)
  return
 if state=="attack":
  if timer<=0:state="recover";timer=.95
  return
 if state=="recover":
  if timer<=0:state="approach"
  return
 facing=1 if delta.x>0 else -1
 var visible:bool=game.cover_line_clear(pos+Vector2(0,-48 if kind=="drone" else -55),p.position+Vector2(0,-50))
 var reach:float=420 if kind=="drone" else 85
 var can_attack:bool=visible and absf(delta.x)<=reach+5 and (absf(delta.y)<65 if kind=="drone" else absf(delta.y)<70)
 if kind=="drone":_move_drone(dt,game,can_attack)
 else:
  if not can_attack:
   pos.x+=facing*(80.0 if kind=="shield" else 105.0)*dt
   _plan_ground_jump(game)
 pos.x=clampf(pos.x,game.left_bound()+45,game.right_bound()-45)
 if can_attack and timer<=0 and game.active_attackers()<2 and absf(pos.x-game.camera_x-640)<640:
  state="windup";timer=.65 if kind=="drone" else .5;locked_x=p.position.x
  _locked_aim=(p.position+Vector2(0,-50)-(pos+Vector2(facing*34,-48))).normalized()
  game.sfx("warning")

func _plan_ground_jump(game:Node)->void:
 if not is_instance_valid(physics_body) or not physics_body.is_on_floor():return
 for item in game.terrain_rects():
  var r:Rect2=item.rect;var rise:float=pos.y-r.position.y
  if rise<3 or rise>96.5:continue
  var edge:float=r.position.x if facing>0 else r.end.x
  var gap:float=(edge-pos.x)*facing
  if gap < -22 or gap>38:continue
  if item.one_way and game.player.position.y>r.position.y+65:continue
  _jump_requested=true;return

func _drone_body_clear(a:Vector2,b:Vector2,game:Node)->bool:
 # Drone physics is a 20-radius, 56-high capsule anchored at its feet.
 # A 28-radius route envelope safely clears both decks and solid containers.
 return game.terrain_sweep(a+Vector2(0,-28),b+Vector2(0,-28),29).is_empty()

func _route_clear(a:Vector2,b:Vector2,rects:Array,game:Node)->bool:
 for item in rects:
  if not game._sweep_circle_polygon(a+Vector2(0,-28),b+Vector2(0,-28),29,game._rect_polygon(item.rect)).is_empty():return false
 return true

func _build_drone_route(target:Vector2,game:Node)->void:
 _drone_route.clear();_route_player_y=game.player.position.y
 var rects:Array=game.terrain_rects()
 if _route_clear(pos,target,rects,game):return
 # A visibility graph around actual obstacle corners also handles stacked
 # one-way decks: crossing a deck requires reaching its physical edge first.
 var points:Array[Vector2]=[pos,target]
 var left:float=game.left_bound()+45;var right:float=game.right_bound()-45
 for item in rects:
  var r:Rect2=item.rect
  if r.position.y>=game.FLOOR-.1 or r.end.x<left or r.position.x>right:continue
  if r.end.x<minf(pos.x,target.x)-600 or r.position.x>maxf(pos.x,target.x)+600:continue
  for x in [r.position.x-40.0,r.end.x+40.0]:
   for y in [r.position.y-6.0,r.end.y+63.0]:
    var point:Vector2=Vector2(x,y)
    if x>=left and x<=right and y<game.FLOOR-2 and _route_clear(point,point,rects,game):points.append(point)
 var cost:Array[float]=[];var previous:Array[int]=[];var visited:Array[bool]=[]
 for i in points.size():cost.append(INF);previous.append(-1);visited.append(false)
 cost[0]=0
 for iteration in points.size():
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

func _move_drone(dt:float,game:Node,can_attack:bool)->void:
 var target:Vector2=game.player.position+Vector2(0,-28)
 target.x=clampf(target.x,game.left_bound()+55,game.right_bound()-55)
 if not _drone_route.is_empty() and absf(game.player.position.y-_route_player_y)>95:_drone_route.clear()
 if _drone_route.is_empty() and not _drone_body_clear(pos,target,game):_build_drone_route(target,game)
 var destination:Vector2=target
 if not _drone_route.is_empty():
  destination=_drone_route[0]
  if pos.distance_to(destination)<8:_drone_route.pop_front();destination=_drone_route[0] if not _drone_route.is_empty() else target
 var difference:Vector2=destination-pos
 var velocity:Vector2=Vector2.ZERO
 if not _drone_route.is_empty():velocity=difference.normalized()*105.0
 else:
  velocity.y=clampf(difference.y*3,-105,105)
  if not can_attack:velocity.x=signf(difference.x)*105.0
  elif absf(game.player.position.x-pos.x)<220:velocity.x=-facing*45.0
 _flight_velocity=velocity;pos.x+=velocity.x*dt

func _fire_drone(game:Node)->void:
 var source:Vector2=pos+Vector2(0,-48)
 var muzzle:Vector2=source+Vector2(facing*34,0)
 var wall:Dictionary=game.terrain_sweep(source,muzzle,8)
 if not wall.is_empty():game.add_sparks(wall.contact,Color("#ffab6b"),5);return
 game.projectiles.append({"pos":muzzle,"vx":_locked_aim.x*440.0,"vy":_locked_aim.y*440.0,"life":3.0,"friendly":false,"damage":10,"radius":8.0})
 game.sfx("shoot")
