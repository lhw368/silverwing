class_name CoolantLevel
extends RefCounted
## Stage 2: physical route choices, supply economy, and local machine hazards.
## No item is a gate key. Every encounter can be cleared with base attacks.
const END:float=13600.0
const FLOOR:float=574.0
const START:float=210.0
const CHECKPOINTS=[Vector2(7040,574),Vector2(12070,574)]
const CHECKPOINT_SPAWNS=[210.0,7180.0,12120.0]
const SOLIDS=[Rect2(580,538,86,36),Rect2(2260,518,100,56),Rect2(4850,518,100,56),Rect2(7620,514,120,60),Rect2(11490,518,100,56)]
const PLATFORMS=[
 Rect2(2240,440,125,18),Rect2(2390,354,170,18),Rect2(2590,354,230,18),
 Rect2(2870,440,160,18),
 Rect2(4720,440,140,18),Rect2(4910,354,150,18),
 Rect2(7660,428,160,18),Rect2(7860,340,155,18),Rect2(8050,340,240,18),
 Rect2(8340,340,250,18),Rect2(8640,340,220,18),Rect2(8900,428,180,18),
 Rect2(11480,440,140,18),Rect2(11670,354,160,18),Rect2(11850,270,180,18)]
const VALVES=[
 {"id":"intake","name":"进水分流阀","after":0,"gate":3240.0,"feet":Vector2(2690,354),"route":[Vector2(2300,518),Vector2(2300,440),Vector2(2470,354),Vector2(2690,354)],"hint":"沿上层检修桥接通进水阀；下方蒸汽有提前预警。"},
 {"id":"return","name":"回流平衡阀","after":1,"gate":5190.0,"feet":Vector2(4980,354),"route":[Vector2(4885,518),Vector2(4790,440),Vector2(4980,354)],"hint":"从货箱折返上行，接通回流阀，停止泄压喷口。"},
 {"id":"core","name":"中枢冷却阀","after":4,"gate":12200.0,"feet":Vector2(11930,270),"route":[Vector2(11520,518),Vector2(11550,440),Vector2(11740,354),Vector2(11930,270)],"hint":"关闭最后一处过压管线，然后到米米处保存。"}]
const PICKUPS=[
 {"id":"starter_bomb","kind":"bomb","count":2,"pos":Vector2(410,574)},
 {"id":"armor_lesson","kind":"armor","count":1,"pos":Vector2(3120,574)},
 {"id":"repair_lesson","kind":"repair","count":1,"pos":Vector2(5250,574)},
 {"id":"upper_bomb","kind":"bomb","count":2,"pos":Vector2(8240,340)},
 {"id":"upper_armor","kind":"armor","count":1,"pos":Vector2(8740,340)},
 {"id":"core_repair","kind":"repair","count":1,"pos":Vector2(11930,270)},
 {"id":"core_bomb","kind":"bomb","count":1,"pos":Vector2(12020,574)}]
const CRATES=[{"id":"cache_a","pos":Vector2(2120,574),"drop":"repair"},{"id":"cache_b","pos":Vector2(7390,574),"drop":"bomb"}]
const MACHINES=[
 {"id":"steam_a","kind":"steam","pos":Vector2(2870,574),"width":140.0,"disabled_by":"intake","phase":0.0},
 {"id":"steam_b","kind":"steam","pos":Vector2(5070,574),"width":130.0,"disabled_by":"return","phase":1.1},
 {"id":"scan_a","kind":"scan","pos":Vector2(8190,574),"width":36.0,"disabled_by":"scanner","phase":0.0},
 {"id":"scan_b","kind":"scan","pos":Vector2(8690,574),"width":36.0,"disabled_by":"scanner","phase":1.7},
 {"id":"steam_c","kind":"steam","pos":Vector2(11820,574),"width":130.0,"disabled_by":"core","phase":1.5}]
var opened:Array[String]=[]
var broken:Array[String]=[]
var crate_hp:Dictionary={}
var crate_serials:Dictionary={}
var hazard_time:float=0.0
var vents:Array=[]
var nav_valve:String=""
var nav_index:int=0
var lesson_seen:Dictionary={}

static func zones()->Array:
 return [
 {"start":900.0,"left":760.0,"right":2180.0,"name":"01 / 装备试用区","hint":"靠近补给拾取炸弹。1 投掷：清理聚集目标；J / K 也能完成战斗。","waves":[[["shield",1640.0],["melee",1870.0],["melee",2050.0]]]},
 {"start":3540.0,"left":3340.0,"right":4680.0,"name":"02 / 进水管廊","hint":"2 装载临时护甲：吸收30点伤害。护甲未耗尽时不会重复消耗。","waves":[[["melee",3790.0],["shield",4140.0],["drone",4490.0]]]},
 {"start":5470.0,"left":5300.0,"right":6670.0,"name":"03 / 回流封锁","hint":"3 使用维修包恢复35HP；满血不消耗。清理后前往米米维修点。","waves":[[["melee",5790.0],["melee",6130.0],["drone",6480.0]]]},
 {"start":8010.0,"left":7790.0,"right":9240.0,"name":"04 / 扫描回廊","hint":"激光亮线后才触发：闪避穿过，或走上层检修桥。E 可关闭末端扫描电源。","waves":[[["drone",8540.0],["shield",9030.0]]]},
 {"start":10140.0,"left":9950.0,"right":11460.0,"name":"05 / 过压隔离区","hint":"合理保留物资；消耗品用光也可通关。最后一段需要关闭高处冷却阀。","waves":[[["shield",10420.0],["drone",11250.0]],[["melee",10150.0],["melee",11060.0]]]},
 {"start":12320.0,"left":12220.0,"right":13530.0,"name":"06 / 冷却中枢","hint":"离开地面锁定区，迎着冷凝波起跳；钻臂收回后就是反击窗口。","waves":[[["boss",13020.0]]]}]

func reset()->void:
 opened.clear();broken.clear();crate_hp.clear();crate_serials.clear();vents.clear();lesson_seen.clear()
 hazard_time=0.0;nav_valve="";nav_index=0
 for c in CRATES:crate_hp[c.id]=35
func snapshot()->Dictionary:
 return {"opened":opened.duplicate(),"broken":broken.duplicate()}
func valid_snapshot(data:Variant)->bool:
 if not data is Dictionary or not data.get("opened") is Array or not data.get("broken") is Array:return false
 for id in data.opened:
  if not id is String or not id in ["intake","return","core","scanner"]:return false
 for id in data.broken:
  if not id is String or not id in ["cache_a","cache_b"]:return false
 return data.opened.size()<=4 and data.broken.size()<=2
func restore(data:Dictionary)->bool:
 if not valid_snapshot(data):return false
 reset()
 for id in data.opened:
  if not id in opened:opened.append(id)
 for id in data.broken:
  if not id in broken:broken.append(id)
 return true
func right_bound(bound:float)->float:
 for valve in VALVES:
  if not valve.id in opened:bound=minf(bound,valve.gate-35)
 return bound
func checkpoint_zones(cp:int)->Array:
 return [0,1,2,3,4] if cp>=2 else ([0,1,2] if cp==1 else [])
func interact(game)->bool:
 for valve in VALVES:
  if absf(game.player.position.x-valve.feet.x)<60 and absf(game.player.position.y-valve.feet.y)<30 and game.player.is_on_floor():
   if valve.id in opened:game.show_status(valve.name+" · 已接通",2);return true
   opened.append(valve.id);game.sfx("checkpoint");game.show_status(valve.name+" · 压力已释放，通路开启",3)
   print("COOLANT_VALVE ",valve.id," t=",game.run_time);return true
 if absf(game.player.position.x-9140)<70 and game.player.is_on_floor():
  if not "scanner" in opened:opened.append("scanner");game.sfx("checkpoint")
  game.show_status("扫描电源已关闭",2);return true
 for i in CHECKPOINTS.size():
  var point:Vector2=CHECKPOINTS[i]
  if absf(game.player.position.x-point.x)<120 and absf(game.player.position.y-point.y)<40:
   var needed=2 if i==0 else 4
   if not "intake" in opened or not "return" in opened:game.show_status("先接通前方两处阀门。",2);return true
   if i==1 and not "core" in opened:game.show_status("先接通高处中枢冷却阀。",2);return true
   game.activate_second_checkpoint(i+1);return true
 return false
func objective_hint(game)->String:
 for valve in VALVES:
  if not valve.id in opened and game.player.position.x>valve.feet.x-600:
   if absf(game.player.position.x-valve.feet.x)<60 and absf(game.player.position.y-valve.feet.y)<30:return "E  接通 "+valve.name
   return valve.hint
 if game.player.position.x>7500 and game.player.position.x<9250 and not "scanner" in opened:return "上层有额外补给。避开扫描亮线，末端 E 可断电。"
 return ""
func all_pickups()->Array:
 var result=PICKUPS.duplicate(true)
 for c in CRATES:
  if c.id in broken:result.append({"id":c.id+"_drop","kind":c.drop,"count":1,"pos":c.pos})
 return result
func tick(dt:float,game)->void:
 hazard_time+=dt
 for p in all_pickups():game.inventory.try_pickup(p,game)
 var body=Rect2(game.player.position+Vector2(-20,-94),Vector2(40,94))
 for machine in MACHINES:
  if machine.disabled_by in opened:continue
  if machine_phase(machine)=="active" and body.intersects(machine_rect(machine)):
   game.player.damage(10 if machine.kind=="steam" else 12,machine.pos.x,"泄压蒸汽" if machine.kind=="steam" else "扫描激光")
 for vent in vents:
  vent.life-=dt
  if vent.life>0 and body.intersects(Rect2(vent.x-70,FLOOR-100,140,100)):
   game.player.damage(16,vent.x,"首领定点冷却喷流")
 vents=vents.filter(func(v):return v.life>0)
func machine_phase(m:Dictionary)->String:
 var time=fposmod(hazard_time+float(m.phase),4.0)
 if time<1.0:return "warning"
 if time<1.4:return "active"
 return "off"
func machine_rect(m:Dictionary)->Rect2:
 var h=190.0 if m.kind=="scan" else 92.0
 return Rect2(m.pos-Vector2(float(m.width)/2,h),Vector2(float(m.width),h))
func hit_crates(game,attack:PackedVector2Array,damage:int,serial:int)->void:
 for c in CRATES:
  if c.id in broken:continue
  var r=Rect2(c.pos+Vector2(-29,-56),Vector2(58,56))
  var shape=PackedVector2Array([r.position,Vector2(r.end.x,r.position.y),r.end,Vector2(r.position.x,r.end.y)])
  if Geometry2D.intersect_polygons(attack,shape).is_empty():continue
  var key=c.id+":"+str(serial)
  if crate_serials.has(key):continue
  crate_serials[key]=true;crate_hp[c.id]=int(crate_hp[c.id])-damage
  game.add_sparks(c.pos+Vector2(0,-30),Color("#ffc684"),8);game.sfx("armor_hit")
  if int(crate_hp[c.id])<=0:
   broken.append(c.id);game.sfx("break");game.show_status("物资箱已开启 · 靠近拾取",2)
func draw_world(game)->void:
 for i in range(-1,18):
  var x=i*870.0
  if game.floor_tex:game.draw_texture_rect(game.floor_tex,Rect2(x,FLOOR-10,880,115),false,Color(.72,.95,.9))
  game.draw_rect(Rect2(x,FLOOR+103,870,65),Color("#091d22"))
  game.draw_line(Vector2(x,FLOOR+1),Vector2(x+870,FLOOR+1),Color("#6ad7c9"),2)
 for r in SOLIDS+PLATFORMS:
  if game.floor_tex:game.draw_texture_rect_region(game.floor_tex,r,Rect2(70,0,r.size.x*2.4,r.size.y*2.4),Color(.72,.94,.89))
  game.draw_line(r.position,r.position+Vector2(r.size.x,0),Color("#87edda"),3)
 for valve in VALVES:
  var on:bool=valve.id in opened
  var color=Color("#63f4c6") if on else Color("#ffd18b")
  var at:Vector2=valve.feet
  game.draw_rect(Rect2(at+Vector2(-23,-82),Vector2(46,82)),Color("#173a45"))
  game.draw_circle(at+Vector2(0,-55),18,color)
  game.draw_arc(at+Vector2(0,-55),12,0,TAU,20,Color("#173a45"),4)
  game.draw_line(at+Vector2(-12,-55),at+Vector2(12,-55),Color("#173a45"),4)
  game.text_at(valve.name+(" ✓" if on else " / E"),at+Vector2(-82,-100),18,color)
  game.draw_polyline(PackedVector2Array([at+Vector2(0,-15),Vector2(at.x,FLOOR+30),Vector2(valve.gate,FLOOR+30)]),Color(color,.35),3,true)
  if not on:
   game.draw_rect(Rect2(valve.gate-7,FLOOR-240,14,240),Color(color,.28))
   game.draw_line(Vector2(valve.gate,FLOOR-240),Vector2(valve.gate,FLOOR),color,3)
 for machine in MACHINES:
  var r=machine_rect(machine)
  var phase=machine_phase(machine)
  var off=machine.disabled_by in opened
  game.draw_rect(Rect2(machine.pos+Vector2(-float(machine.width)/2,-9),Vector2(machine.width,9)),Color("#315662"))
  if off:game.draw_line(Vector2(r.position.x,FLOOR-10),Vector2(r.end.x,FLOOR-10),Color("#56c5a9"),2);continue
  if phase=="warning":
   game.draw_rect(r,Color(1,.67,.2,.08));game.draw_rect(r,Color(1,.72,.3,.8),false,2)
   game.text_at("!",r.position+Vector2(r.size.x*.5-6,-8),22,Color("#ffd191"))
  elif phase=="active":
   game.draw_rect(r,Color(.5,1,.9,.4) if machine.kind=="steam" else Color(1,.45,.3,.65))
   for j in 5:
    var x=r.position.x+(j+.5)*r.size.x/5
    game.draw_line(Vector2(x,r.position.y),Vector2(x,r.end.y),Color(.7,1,.95,.8),2)
 for vent in vents:
  game.draw_rect(Rect2(vent.x-70,FLOOR-100,140,100),Color(.4,1,.85,.45))
  game.draw_arc(Vector2(vent.x,FLOOR),70,PI,TAU,20,Color("#b6ffef"),5)
 for c in CRATES:
  if c.id in broken:continue
  var tex:Texture2D=game.item_textures.get("supply_crate")
  if tex:game.draw_texture_rect(tex,Rect2(c.pos+Vector2(-35,-70),Vector2(70,70)),false)
  else:
   var box=Rect2(c.pos+Vector2(-29,-56),Vector2(58,56))
   if game.floor_tex:game.draw_texture_rect_region(game.floor_tex,box,Rect2(200,16,145,140),Color(.8,1,.92))
   game.draw_rect(box,Color("#b7e7d9"),false,2)
  game.text_at("物资 / J·K·1",c.pos+Vector2(-49,-77),14,Color("#d7f1e6"))
 for p in all_pickups():game.inventory.draw_pickup(p,game)
 for at in CHECKPOINTS:game.draw_repair_station(at.x)
 var scanner_on:bool=not "scanner" in opened
 game.draw_rect(Rect2(9120,FLOOR-70,40,70),Color("#224753"))
 game.text_at("E 扫描断电" if scanner_on else "扫描已停",Vector2(9080,FLOOR-90),17,Color("#9bead8"))
 for zone in game.zones:game.text_at(zone.name,Vector2(zone.left+70,FLOOR-235),20,Color("#72aaa8"))
