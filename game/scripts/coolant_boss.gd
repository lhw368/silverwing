class_name CoolantBoss
extends "res://scripts/enemy.gd"
## Second-level controller; first-level Boss remains untouched in enemy.gd.
func boss_tick(dt:float,game:Node)->void:
 var p:SilverwingPlayer=game.player
 var distance:float=p.position.x-pos.x
 phase_two=hp<=max_hp/2
 if state=="windup":
  if timer<=0:
   state="attack";attack_applied=false;timer=.25
   if move_name=="charge":
    game.projectiles.append({"pos":disc_emitter(game),"vx":facing*350.0,"life":4.0,"friendly":false,"damage":18,"radius":23.0,"boss_wave":true,"boss_id":get_instance_id(),"cold_disc":true})
    game.sfx("shoot")
   elif move_name=="wave":
    game.coolant.vents.append({"x":locked_x,"life":.35})
    game.kick_shake(5);game.sfx("slam")
  return
 if state=="attack":
  if move_name=="sweep" and not attack_applied:
   attack_applied=true
   if absf(distance)<185 and distance*facing>=-20 and absf(p.position.y-pos.y)<110:p.damage(18,pos.x,"冷却监理机钻臂")
   game.sfx("slam")
  if timer<=0:state="recover";timer=1.65
  return
 if state=="recover":
  if timer<=0:state="approach";timer=.60
  return
 facing=1 if distance>0 else -1
 if absf(distance)>205:pos.x+=facing*85.0*dt
 if timer<=0:
  var sequence:Array=["sweep","wave","charge"] if not phase_two else ["wave","sweep","charge","wave"]
  move_name=sequence[cycle%sequence.size()];cycle+=1
  state="windup";timer=1.05 if move_name=="wave" else (.95 if move_name=="charge" else .85)
  locked_x=clampf(p.position.x,game.left_bound()+80,game.right_bound()-80)
  game.sfx("warning")
func boss_wave_hint(game:Node)->Dictionary:
 var travelling:Dictionary=super.boss_wave_hint(game)
 # Base helper estimates flight against current relative horizontal velocity.
 if not travelling.stage.is_empty() and not (state=="windup" and move_name=="wave"):
  travelling.stage="jump" if float(travelling.impact_in)<=.42 else "travel"
  travelling.text="现在起跳" if travelling.stage=="jump" else "冷凝波接近 · 等待波近"
  return travelling
 if state=="windup" and move_name=="charge":
  var vx:float=game.player.velocity.x
  var future_dist:float=(game.player.position.x+vx*maxf(timer,0)-disc_emitter(game).x)*facing
  var speed:float=maxf(1.0,350.0-vx*facing)
  var eta:float=maxf(timer,0)+maxf(0,(future_dist-50.0)/speed)
  return {"stage":"jump" if eta<=.42 else "charge","text":"现在起跳" if eta<=.42 else "冷凝波蓄力 · 等待波近","impact_in":eta}
 if state=="windup" and move_name=="wave":return {"stage":"move","text":"地面锁定 · 离开标记","impact_in":timer}
 return {"stage":"","text":"","impact_in":INF}

func disc_emitter(game:Node)->Vector2:
 var meta:Dictionary=game.enemy_animation_meta.boss
 var point:Vector2=Vector2(13,516)
 var entry:Variant=meta.get("emitters",{}).get("attack_charge",[])
 if entry is Array and entry.size()>1 and entry[1] is Dictionary:
  var value:Variant=entry[1].get("point_px",[13,516])
  point=Vector2(value[0],value[1])
 return pos+Vector2((point.x-float(meta.root[0]))*-facing,point.y-float(meta.root[1]))*(265.0/float(meta.native_body_height))
