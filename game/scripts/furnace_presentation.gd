extends "res://scripts/terrain_campaign.gd"
var furnace_enemy_art:Dictionary={}
var qa_enemy_boxes:bool=false
var furnace_mine_texture:Texture2D
func _ready()->void:
 qa_enemy_boxes="--enemy-boxes" in OS.get_cmdline_user_args()
 super._ready()
func load_assets()->void:
 super.load_assets()
 for role in ["lancer","minelayer"]:_load_furnace_actor(role,"res://assets/enemies/furnace-v08/"+role+"/")
 _load_furnace_actor("overload","res://assets/enemies/furnace-boss-v08/")
 if ResourceLoader.exists("res://assets/enemies/furnace-v08/minelayer/mine.webp"):furnace_mine_texture=load("res://assets/enemies/furnace-v08/minelayer/mine.webp")
func _load_furnace_actor(role:String,path:String)->void:
 if not FileAccess.file_exists(path+"manifest.json"):return
 var meta:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path+"manifest.json"))
 var groups:Dictionary={}
 var animation_data:Dictionary=meta.get("animations",meta.get("animation_groups",{}))
 for action in animation_data:
  var frames:Array=[]
  for file in animation_data[action].frames:frames.append(load(path+file))
  groups[action]=frames
 var hurt:Dictionary={}
 if FileAccess.file_exists(path+"hurt_regions.json"):hurt=JSON.parse_string(FileAccess.get_file_as_string(path+"hurt_regions.json"))
 furnace_enemy_art[role]={"meta":meta,"groups":groups,"hurt":hurt}
func _broken_art_active(enemy)->bool:
 return enemy.phase_two and (enemy.state!="transform" or enemy.timer<=.55) and furnace_enemy_art.has("overload")
func furnace_pose(enemy,role:String)->Dictionary:
 var action:String="idle";var frame:int=0
 var elapsed:float=enemy.state_elapsed if enemy.visual_state==enemy.state else 0.0
 if enemy.dead:action="death";frame=int(enemy.death_timer*5)
 elif role=="overload":
  if enemy.state=="transform":action="phase_transition";frame=0
  elif enemy.state=="windup":action="axe_windup" if enemy.move_name=="axe" else "idle"
  elif enemy.state=="attack":action="axe_attack" if enemy.move_name=="axe" else "recover";frame=int(elapsed*8)
  elif enemy.state=="recover":action="recover";frame=int(elapsed*3)
  elif enemy.flash>0:action="hurt"
  elif absf(enemy.actual_motion_x)>8:action="move";frame=int(enemy.visual_clock*8)
 else:
  action=enemy.animation_state_key()
  if action=="recover":action="attack";frame=1
  elif action in ["idle","move"]:frame=int(enemy.visual_clock*(8 if action=="move" else 3))
  elif action=="attack":frame=0
  else:frame=int(elapsed*5)
 var groups:Dictionary=furnace_enemy_art[role].groups
 if not groups.has(action):action="recover" if groups.has("recover") else "idle"
 frame=posmod(frame,groups[action].size()) if action in ["idle","move"] else clampi(frame,0,groups[action].size()-1)
 return {"action":action,"frame":frame}
func _actor_polygons(enemy,role:String)->Array:
 var result:Array=[]
 if enemy.dead or not furnace_enemy_art.has(role):return result
 var data:Dictionary=furnace_enemy_art[role];var pose:Dictionary=furnace_pose(enemy,role)
 var frames:Array=data.hurt.get("frames",{}).get(pose.action,[])
 if frames.is_empty():return result
 var meta:Dictionary=data.meta;var height:float=265 if role=="overload" else 130
 var factor:float=height/float(meta.native_body_height)
 var direction:int=enemy.facing*(-1 if meta.get("orientation",meta.get("source_facing","left"))=="left" else 1)
 for points in frames[mini(pose.frame,frames.size()-1)].polygons:
  var polygon=PackedVector2Array()
  for point in points:polygon.append(enemy.pos+Vector2((float(point[0])-float(meta.root[0]))*direction,float(point[1])-float(meta.root[1]))*factor)
  result.append(polygon)
 return result
func boss_body_polygons(enemy:StarportEnemy)->Array:
 if level_id==3 and _broken_art_active(enemy):return _actor_polygons(enemy,"overload")
 return super.boss_body_polygons(enemy)
func cover_enemy_polygons(enemy)->Array:
 if level_id==3 and enemy.kind in ["melee","shield"] and enemy.has_method("role_key") and furnace_enemy_art.has(enemy.role_key()):return _actor_polygons(enemy,enemy.role_key())
 return super.cover_enemy_polygons(enemy)
func _draw_actor(enemy,role:String)->void:
 var art:Dictionary=furnace_enemy_art[role];var meta:Dictionary=art.meta;var pose:Dictionary=furnace_pose(enemy,role)
 var factor:float=(265.0 if role=="overload" else 130.0)/float(meta.native_body_height)
 var direction:int=enemy.facing*(-1 if meta.get("orientation",meta.get("source_facing","left"))=="left" else 1)
 var root:Vector2=Vector2(meta.root[0],meta.root[1])*factor
 var size:Vector2=Vector2(meta.frame_size[0],meta.frame_size[1])*factor
 # Godot flips a negative texture width in place. Use the already verified
 # shared helper; moving the rectangle's X on flip would shift a whole canvas.
 var rect:Rect2=sprite_rect_for(enemy.pos,size,root.y,direction)
 var tint:Color=Color(1,.82,.65) if enemy.state=="windup" else Color.WHITE
 if enemy.flash>0 and effects_enabled:tint=Color(1.65,1.65,1.65)
 if enemy.dead:tint.a=clampf((.72-enemy.death_timer)/.20,0,1)
 draw_texture_rect(art.groups[pose.action][pose.frame],rect,false,tint)
func draw_enemy(enemy:StarportEnemy)->void:
 if level_id!=3:super.draw_enemy(enemy);return
 if enemy.dead and enemy.death_timer>.72:return
 if enemy.has_method("draw_extra"):enemy.draw_extra(self)
 if enemy.has_method("role_key") and enemy.role_key()=="minelayer" and furnace_mine_texture:
  for mine in enemy.mines:
   if not mine.spent:draw_texture_rect(furnace_mine_texture,Rect2(Vector2(mine.pos)+Vector2(-19,-15),Vector2(38,18)),false)
 if enemy.kind in ["melee","shield"] and enemy.has_method("role_key") and furnace_enemy_art.has(enemy.role_key()):
  draw_circle(enemy.pos+Vector2(0,1),30,Color(.06,.025,.02,.3));_draw_actor(enemy,enemy.role_key())
  if not enemy.dead:
   bar(Rect2(enemy.pos+Vector2(-32,-147),Vector2(64,5)),float(enemy.hp)/enemy.max_hp,ORANGE)
   if enemy.state=="windup":text_at("!",enemy.pos+Vector2(-6,-157),25,ORANGE)
 elif enemy.kind=="boss" and _broken_art_active(enemy):
  draw_circle(enemy.pos+Vector2(0,1),74,Color(.06,.025,.02,.3));_draw_actor(enemy,"overload")
  if enemy.state=="windup" and enemy.move_name=="axe":
   draw_line(enemy.pos+Vector2(enemy.facing*48,-4),enemy.pos+Vector2(enemy.facing*230,-4),Color(1,.37,.12,.6),8)
   text_at("激光斧蓄力",enemy.pos+Vector2(-62,-285),22,ORANGE)
  elif enemy.state=="windup" and enemy.move_name=="charge":
   # Phase two retains the same early, clamped landing markers as the
   # actual mortar spawns, including when the pilot is near an arena wall.
   for target_x in [enemy.locked_x-115,enemy.locked_x+115]:
    var at:float=clampf(target_x,left_bound()+70,right_bound()-70)
    draw_rect(Rect2(at-58,FLOOR-105,116,105),Color(1,.48,.12,.16))
    draw_rect(Rect2(at-58,FLOOR-105,116,105),ORANGE,false,2)
  if enemy.state=="attack" and enemy.move_name=="axe" and enemy.timer<=.24 and enemy.timer>=.10:
   draw_polyline(enemy.axe_blade_edge(),Color(1,.42,.1,.58),24)
   draw_polyline(enemy.axe_blade_edge(),Color(1,.92,.5,.85),3)
 else:super.draw_enemy(enemy)
 if enemy.kind=="boss" and enemy.state=="transform":
  var amount:float=1-clampf(enemy.timer/1.1,0,1)
  for i in 6:
   var angle:float=float(i)*TAU/6
   var at:Vector2=enemy.pos+Vector2(0,-155)+Vector2(cos(angle),sin(angle))*amount*150
   draw_rect(Rect2(at,Vector2(16,9)),Color(.68,.53,.39,1-amount))
 if qa_enemy_boxes and not enemy.dead:
  for polygon in cover_enemy_polygons(enemy):
   var line:PackedVector2Array=polygon.duplicate();line.append(line[0]);draw_polyline(line,Color.GREEN,1.5)
  draw_circle(enemy.pos,4,Color.MAGENTA)
  if enemy.kind=="boss" and enemy.phase_two and enemy.move_name=="axe" and enemy.state in ["windup","attack"]:
   for polygon in enemy.axe_attack_polygons():
    var line:PackedVector2Array=polygon.duplicate();line.append(line[0]);draw_polyline(line,Color.RED,2)
