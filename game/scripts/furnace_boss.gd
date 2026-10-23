extends "res://scripts/enemy.gd"
func boss_tick(dt:float,game:Node)->void:
 var p:SilverwingPlayer=game.player;var dx:float=p.position.x-pos.x
 phase_two=hp<=max_hp/2
 if state=="windup":
  if timer<=0:
   state="attack";timer=.28;attack_applied=false
   if move_name=="wave":
    game.projectiles.append({"pos":pos+Vector2(facing*85,-18),"vx":facing*320.0,"life":3.8,"friendly":false,"damage":16,"radius":22.0,"boss_wave":true,"boss_id":get_instance_id(),"furnace_wave":true})
    game.sfx("slam")
   elif move_name=="charge":
    for x in [locked_x-115,locked_x+115]:game.furnace.mortars.append({"x":clampf(x,game.left_bound()+70,game.right_bound()-70),"life":.9})
    game.sfx("heavy")
  return
 if state=="attack":
  if move_name=="sweep" and not attack_applied:
   attack_applied=true
   if absf(dx)<185 and dx*facing>=-24 and absf(p.position.y-pos.y)<110:p.damage(18,pos.x,"赤炉守卫横扫")
   game.sfx("slam")
  if timer<=0:state="recover";timer=1.8
  return
 if state=="recover":
  if timer<=0:state="approach";timer=.7
  return
 facing=1 if dx>0 else -1
 if absf(dx)>245:pos.x+=facing*65*dt
 if timer<=0:
  move_name=["sweep","wave","charge"][cycle%3];cycle+=1;state="windup"
  timer=1.15 if move_name=="wave" else (1.2 if move_name=="charge" else .9)
  locked_x=p.position.x;game.sfx("warning")
func boss_wave_hint(game:Node)->Dictionary:
 if state=="windup" and move_name=="charge":return {"stage":"move","text":"双点炮击 · 离开两侧标记","impact_in":timer+.68}
 if state=="windup" and move_name=="wave":
  var vx:float=game.player.velocity.x
  var distance:float=(game.player.position.x+vx*maxf(timer,0)-pos.x)*facing-85
  var speed:float=320-vx*facing
  var eta:float=maxf(timer,0)+maxf(0,(distance-49)/speed) if speed>0 else INF
  return {"stage":"jump" if eta<=.38 else "charge","text":"现在起跳" if eta<=.38 else "热浪蓄力 · 等待波近","impact_in":eta}
 var h:Dictionary=super.boss_wave_hint(game)
 if not h.stage.is_empty():h.text="现在起跳" if h.stage=="jump" else "热浪接近 · 等待波近"
 return h
