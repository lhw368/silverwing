extends "res://scripts/supplied_player.gd"
var feiren_dash_started:bool=false
func set_exosuit_shape(value:bool)->void:
 var collider:CollisionShape2D=get_child(0)
 var shape=CapsuleShape2D.new();shape.radius=50 if value else 22;shape.height=150 if value else 96
 collider.shape=shape;collider.position.y=-shape.height*.5
func begin_action(action:String)->bool:
 if game.paused:return false
 if game.exosuit.active and action in ["light","heavy","skill"]:return game.exosuit.command(game,action)
 var accepted:bool=super.begin_action(action)
 if accepted and action=="skill" and game.selected_character=="feiren" and not game.exosuit.active:
  feiren_dash_started=false;invuln=maxf(invuln,.22)
 return accepted
func tick(dt:float,axis:float)->void:
 if game.exosuit.active:
  super.tick(dt,axis*.78 if game.exosuit.elapsed>=.35 else 0.0)
  position.x=clampf(position.x,game.left_bound()+28,game.right_bound()-28)
  return
 if game.selected_character=="feiren" and state=="skill" and elapsed>=.10 and elapsed<.40:
  velocity.x=facing*680
  if not feiren_dash_started:feiren_dash_started=true;game.sfx("skill")
 super.tick(dt,axis)
func damage(amount:int,from_x:float,cause:String)->bool:
 if game.exosuit.active:return game.exosuit.damage(game,amount,from_x,cause)
 if game.level_id==3:
  if not can_take_damage():return false
  var absorbed:int=mini(maxi(amount,0),game.inventory.armor);game.inventory.armor-=absorbed
  var accepted:bool=super.damage(maxi(0,amount-absorbed),from_x,cause)
  if absorbed>0:game.float_text(position+Vector2(0,-166),"护甲吸收 %d"%absorbed,Color("#ffd19c"))
  return accepted
 return super.damage(amount,from_x,cause)
