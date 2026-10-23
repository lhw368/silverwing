extends RefCounted
## Shallow retracting road spikes. The yellow housings remain visible while
## safe; warning/active cues are essential and are not hidden by effects-off.
const PERIOD:float=4.0
const WARNING:float=1.0
const ACTIVE:float=.65
const DAMAGE:int=10
const HIT_WIDTH:float=64.0
const HIT_HEIGHT:float=34.0
var time:float=0
var accepted_hits:int=0
func reset()->void:time=0;accepted_hits=0
func layout(level:int)->Array:
 if level==1:return [{"x":3570.0,"phase":0.0},{"x":9280.0,"phase":1.4}]
 if level==2:return [{"x":6030.0,"phase":.8},{"x":10630.0,"phase":2.0}]
 return [{"x":4640.0,"phase":.4},{"x":13330.0,"phase":1.5},{"x":14980.0,"phase":2.4}]
func phase(trap:Dictionary)->float:return fposmod(time+float(trap.phase),PERIOD)
func rect(trap:Dictionary,game)->Rect2:return Rect2(float(trap.x)-HIT_WIDTH*.5,game.FLOOR-HIT_HEIGHT,HIT_WIDTH,HIT_HEIGHT)
func tick(dt:float,game)->void:
 if game.mode!="play" or game.paused or game.test_mode:return
 time+=dt
 for trap in layout(game.level_id):
  var t:float=phase(trap)
  if t>=WARNING and t<WARNING+ACTIVE and rect(trap,game).intersects(game.player_body_rect()):
   if game.player.damage(DAMAGE,float(trap.x),"路面尖刺"):accepted_hits+=1
func draw(game)->void:
 for trap in layout(game.level_id):
  var x:float=trap.x
  if x<game.camera_x-120 or x>game.camera_x+1400:continue
  var t:float=phase(trap);var active:bool=t>=WARNING and t<WARNING+ACTIVE
  var height:float=HIT_HEIGHT if active else (6.0+4.0*sin(t*18) if t<WARNING else 3.0)
  var housing=Rect2(x-47,game.FLOOR-5,94,13)
  game.draw_rect(housing,Color("#202633"));game.draw_rect(housing,Color("#aeb9c6"),false,1.5)
  for i in 6:
   var sx:float=x-43+i*16
   game.draw_line(Vector2(sx,game.FLOOR+6),Vector2(sx+7,game.FLOOR-2),Color("#df9a42"),4,true)
  for i in 5:
   var sx:float=x-32+i*16
   var tip=Vector2(sx,game.FLOOR-height)
   game.draw_colored_polygon(PackedVector2Array([Vector2(sx-7,game.FLOOR),tip,Vector2(sx+7,game.FLOOR)]),Color("#e9edf2") if active else Color("#69788a"))
   game.draw_line(tip,Vector2(sx+5,game.FLOOR),Color("#ffaf74") if active else Color("#a2b0c0"),1.8,true)
  if t<WARNING:
   game.draw_rect(Rect2(x-48,game.FLOOR-HIT_HEIGHT-8,96,HIT_HEIGHT+8),Color(1,.6,.15,.1+.08*sin(t*22)))
   game.draw_line(Vector2(x-44,game.FLOOR-45),Vector2(x+44,game.FLOOR-45),Color("#ffc265"),2)
   game.text_at("尖刺预警",Vector2(x-36,game.FLOOR-57),16,Color("#ffcc7d"))
  elif active:game.draw_line(Vector2(x-40,game.FLOOR+1),Vector2(x+40,game.FLOOR+1),Color("#ff865d"),3)
