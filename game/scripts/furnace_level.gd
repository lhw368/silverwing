class_name FurnaceLevel
extends RefCounted
const FLOOR:float=574.0
const PODS=[{"id":"rescue","x":10150.0}]
const SOLIDS=[Rect2(320,486,160,88),Rect2(10990,484,120,90),Rect2(11270,478,140,96),Rect2(11410,388,240,186),Rect2(11650,478,140,96),Rect2(13740,494,140,80),Rect2(15310,490,150,84),Rect2(2950,510,108,64),Rect2(6320,510,108,64),Rect2(7560,510,100,64),Rect2(8220,510,108,64)]
const PLATFORMS=[Rect2(505,390,160,18),Rect2(695,286,1375,24),Rect2(6320,510,960,18),Rect2(7560,510,610,18),Rect2(3090,432,140,18),Rect2(3250,354,220,18),Rect2(6430,432,145,18),Rect2(6610,354,220,18),Rect2(8380,432,130,18),Rect2(8530,354,210,18),Rect2(6780,440,440,18),Rect2(7700,420,330,18)]
const SWITCHES=[
 {"id":"freight","name":"货运闸机","after":0,"gate":3670.0,"feet":Vector2(3360,354),"route":[Vector2(3000,510),Vector2(3160,432),Vector2(3360,354)]},
 {"id":"restraint_a","name":"拘束电源 A","after":2,"gate":7430.0,"feet":Vector2(6720,354),"route":[Vector2(6368,510),Vector2(6490,432),Vector2(6720,354)]},
 {"id":"restraint_b","name":"拘束电源 B","after":3,"gate":9310.0,"feet":Vector2(8630,354),"route":[Vector2(8270,510),Vector2(8440,432),Vector2(8630,354)]}]
const PICKUPS=[{"id":"fr_bomb","kind":"bomb","count":2,"pos":Vector2(340,574)},{"id":"fr_armor","kind":"armor","count":1,"pos":Vector2(3860,574)},{"id":"fr_repair","kind":"repair","count":1,"pos":Vector2(5980,574)},{"id":"fr_upper","kind":"bomb","count":2,"pos":Vector2(7900,420)},{"id":"fr_rescue_repair","kind":"repair","count":1,"pos":Vector2(9900,574)}]
const CHECKPOINTS=[5630.0,9690.0]
const SPAWNS=[210.0,5760.0,9880.0]
const RESCUE_X:float=9490.0
var opened:Array[String]=[]
var hazard_time:float=0.0
var mortars:Array=[]
var nav_switch:String=""
var nav_index:int=0
static func zones()->Array:
 return [
  {"start":1030.0,"left":680.0,"right":2350.0,"name":"01 / 货运双层通道","hint":"上层栈桥可迎击俯冲无人机；下层应对突枪与布雷兵。两路在右侧汇合。","waves":[[["shield",1490.0],["melee",1710.0],["drone",1850.0,286.0]]]},
  {"start":4090.0,"left":3900.0,"right":5440.0,"name":"02 / 熔炉侧道","hint":"无人机先标记再俯冲。突枪兵蓄力时跳开或闪至身后。","waves":[[["drone",4390.0],["shield",4710.0],["melee",4990.0],["drone",5310.0]]]},
  {"start":6290.0,"left":6150.0,"right":7400.0,"name":"03 / 拘束电源 A","hint":"布雷后地面会亮起预警；离开亮圈再反击，可直接登台切断电源。","waves":[[["shield",6590.0],["drone",7110.0,440.0],["melee",7270.0]]]},
  {"start":7790.0,"left":7580.0,"right":9130.0,"name":"04 / 炉心横桥","hint":"上层有可选补给；第二路电源在右侧高台。注意热浪亮线。","waves":[[["drone",7960.0,440.0],["melee",8540.0],["shield",8880.0]]]},
  {"start":10870.0,"left":10660.0,"right":12130.0,"name":"05 / 货柜掩体战区","hint":"货柜能挡住双方射击。借矮墙躲弹，登上货柜转移或绕后；后方还有装甲突围廊与撤离坡道。","waves":[[["shield",11180.0],["melee",11680.0,478.0],["drone",11920.0]]]},
  {"start":12500.0,"left":12300.0,"right":14100.0,"name":"06 / 装甲突围廊","hint":"连射压制俯冲无人机，重炮击散突枪小队；绕过护栏可继续前进。","waves":[[["melee",12820.0],["drone",13100.0],["melee",13880.0]]]},
  {"start":14500.0,"left":14300.0,"right":16070.0,"name":"07 / 撤离坡道","hint":"尖刺亮线后抬升。可跳过或在安全间隙穿行，驾驶动力不会在这里自动回收。","waves":[[["shield",14770.0],["drone",15570.0]]]},
  {"start":16320.0,"left":16220.0,"right":17530.0,"name":"08 / 赤炉撤离口","hint":"半血会破甲并展开激光斧；看清起手，热浪接近时跳，重斩收招后反击。","waves":[[["boss",17020.0]]]}]
func reset()->void:
 opened.clear();hazard_time=0;mortars.clear();nav_switch="";nav_index=0
func snapshot()->Dictionary:return {"opened":opened.duplicate()}
func valid_snapshot(data:Variant)->bool:
 if not data is Dictionary or not data.get("opened") is Array:return false
 if data.opened.size()>3:return false
 for id in data.opened:
  if not id is String or id not in ["freight","restraint_a","restraint_b"]:return false
 return true
func restore(data:Dictionary)->bool:
 if not valid_snapshot(data):return false
 reset()
 for id in data.opened:
  if not id in opened:opened.append(id)
 return true
func checkpoint_zones(cp:int)->Array:return [0,1,2,3] if cp>=2 else ([0,1] if cp==1 else [])
func right_bound(bound:float,game)->float:
 for item in SWITCHES:
  if not item.id in opened:bound=minf(bound,item.gate-35)
 if not game.feiren_unlocked:bound=minf(bound,RESCUE_X+150.0)
 return bound
func interact(game)->bool:
 if game.exosuit.active:game.exosuit.exit(game,"manual");return true
 for pod in PODS:
  if absf(game.player.position.x-pod.x)<100 and absf(game.player.position.y-FLOOR)<24 and game.player.is_on_floor():
   if pod.id in game.spent_pods:game.show_status("这台装甲已消耗。本次行动不能补充动力。",2)
   else:game.exosuit.enter(game,pod.id)
   return true
 for item in SWITCHES:
  if absf(game.player.position.x-item.feet.x)<65 and absf(game.player.position.y-item.feet.y)<28 and game.player.is_on_floor():
   if not item.id in opened:opened.append(item.id);game.sfx("checkpoint");print("FURNACE_SWITCH ",item.id," t=",game.run_time)
   game.show_status(item.name+" · 已断开，通路开启",3);return true
 if absf(game.player.position.x-RESCUE_X)<115 and absf(game.player.position.y-FLOOR)<32:
  if not "restraint_a" in opened or not "restraint_b" in opened:game.show_status("先切断两路拘束电源。",3);return true
  game.rescue_feiren();return true
 for i in CHECKPOINTS.size():
  if absf(game.player.position.x-CHECKPOINTS[i])<100 and absf(game.player.position.y-FLOOR)<30:
   if (i==0 and "freight" in opened) or (i==1 and "restraint_a" in opened and "restraint_b" in opened and game.feiren_unlocked):game.activate_third_checkpoint(i+1)
   return true
 return false
func objective_hint(game)->String:
 if game.exosuit.active:return "赤隼支援：连射 / 重炮。交互可提前退出；已用装甲不会在重试时补满。"
 for pod in PODS:
  if absf(game.player.position.x-pod.x)<220 and absf(game.player.position.y-FLOOR)<40 and not pod.id in game.spent_pods:return "E / 交互：驾驶赤隼外骨骼。限时30秒，耐久耗尽也会退出。"
 if game.active_zone>=0:return game.zones[game.active_zone].hint
 for item in SWITCHES:
  if not item.id in opened and game.player.position.x>item.feet.x-600:return "登上检修台，E / 交互切断"+item.name
 if game.player.position.x>RESCUE_X-160 and not game.feiren_unlocked:return "绯刃仍在拘束舱中。靠近她，E / 交互解救。"
 if game.player.position.x>RESCUE_X and game.feiren_unlocked:return "同伴已撤离。驾驶唯一赤隼或步行突破掩体区与首领，中间无需下机交互。"
 return ""
func tick(dt:float,game)->void:
 hazard_time+=dt
 for item in PICKUPS:game.inventory.try_pickup(item,game)
 var body:Rect2=game.player_body_rect()
 for at in [Vector2(3530,574),Vector2(8400,574)]:
  var disabled=("freight" in opened if at.x<4000 else "restraint_b" in opened)
  if disabled:continue
  var phase=fposmod(hazard_time+(1.2 if at.x>4000 else 0),4.5)
  if phase>=1.0 and phase<1.35 and body.intersects(Rect2(at-Vector2(55,78),Vector2(110,78))):game.player.damage(10,at.x,"熔炉热浪")
 for shell in mortars:
  shell.life-=dt
  if shell.life<=.22 and shell.life>0 and body.intersects(Rect2(shell.x-58,FLOOR-105,116,105)):game.player.damage(16,shell.x,"赤炉守卫定点炮击")
 mortars=mortars.filter(func(s):return s.life>0)
func draw_world(game)->void:
 for i in range(-1,int(game.WORLD_END/870.0)+2):
  var x=i*870.0
  if game.floor_tex:game.draw_texture_rect(game.floor_tex,Rect2(x,FLOOR,870,120),false)
  game.draw_rect(Rect2(x,FLOOR+103,870,65),Color("#201812"))
  game.draw_line(Vector2(x,FLOOR+1),Vector2(x+870,FLOOR+1),Color("#f4bb81"),2)
 for r in SOLIDS+PLATFORMS:
  if game.floor_tex:game.draw_texture_rect_region(game.floor_tex,r,Rect2(70,0,r.size.x*2.4,r.size.y*2.4))
  game.draw_line(r.position,r.position+Vector2(r.size.x,0),Color("#f7bf83"),3)
 for item in SWITCHES:
  var done:bool=item.id in opened;var at:Vector2=item.feet;var tint=Color("#e9c286") if not done else Color("#a7d7a7")
  game.draw_rect(Rect2(at+Vector2(-25,-76),Vector2(50,76)),Color("#432f2a"));game.draw_circle(at+Vector2(0,-52),17,tint)
  game.text_at(item.name+(" 已断开" if done else " / E"),at+Vector2(-84,-98),18,tint)
  if not done:
   game.draw_line(Vector2(item.gate,FLOOR-220),Vector2(item.gate,FLOOR),tint,4)
   game.draw_polyline(PackedVector2Array([at+Vector2(0,-8),Vector2(at.x,FLOOR+22),Vector2(item.gate,FLOOR+22)]),Color(tint,.4),3)
 for at in [Vector2(3530,574),Vector2(8400,574)]:
  var disabled=("freight" in opened if at.x<4000 else "restraint_b" in opened)
  if disabled:continue
  var phase=fposmod(hazard_time+(1.2 if at.x>4000 else 0),4.5);var r=Rect2(at-Vector2(55,78),Vector2(110,78))
  if phase<1:game.draw_rect(r,Color(1,.45,.12,.11));game.draw_rect(r,Color("#ffbd6d"),false,2)
  elif phase<1.35:game.draw_rect(r,Color(1,.3,.1,.48));game.draw_line(at-Vector2(44,0),at-Vector2(44,70),Color("#ffe4a1"),5)
 for pod in PODS:game.exosuit.draw_pod(game,pod, pod.id in game.spent_pods)
 for item in PICKUPS:game.inventory.draw_pickup(item,game)
 for x in CHECKPOINTS:game.draw_repair_station(x)
 if not game.feiren_unlocked:game.draw_feiren_npc(Vector2(RESCUE_X,FLOOR-54))
 if game.furnace_props.has("rescue"):
  game.draw_texture_rect(game.furnace_props.rescue,Rect2(RESCUE_X-105,FLOOR-228,210,228),false,Color(.6,.52,.45,.68) if game.feiren_unlocked else Color.WHITE)
 if not game.feiren_unlocked:
  game.text_at("拘束中 · 绯刃",Vector2(RESCUE_X-78,FLOOR-250),23,Color("#ffd29b"))
  if game.run_time>0:game.text_at("解除电源后 E 救援",Vector2(RESCUE_X-93,FLOOR-275),17,Color("#ffe6c3"))
 else:game.text_at("救援完成 · 同伴已撤离",Vector2(RESCUE_X-116,FLOOR-235),20,Color("#f0c28e"))
 for shell in mortars:
  var r=Rect2(shell.x-58,FLOOR-105,116,105)
  game.draw_rect(r,Color(1,.38,.09,.5 if shell.life<=.22 else .12));game.draw_rect(r,Color("#ffbf71"),false,3)
  if shell.life>.22:game.text_at("炮击预警",Vector2(shell.x-41,FLOOR-120),17,Color("#ffe4b9"))
 for z in game.zones:game.text_at(z.name,Vector2(z.left+55,FLOOR-235),20,Color("#dca579"))
