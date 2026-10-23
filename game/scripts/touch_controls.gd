extends Control
## Finger-owned touch input. No synthetic keyboard actions or shared Input state.
const DEADZONE:float=.18
const REPEAT_INTERVAL:float=.20
var game:Node
var enabled:bool=false
var axis:float=0.0
var fingers:Dictionary={}
var owners:Dictionary={}
var buttons:Dictionary={}
var joystick_center:Vector2=Vector2.ZERO
var joystick_radius:float=74.0
var layout_scale:float=1.0
var joystick_tip:Vector2=Vector2.ZERO
var safe:Rect2=Rect2(16,16,1248,688)
var qa_safe_rect:Rect2=Rect2()
var _layout_key:String=""
var _repeat_left:float=0.0
var _mouse_down:bool=false
var _last_gate:String=""
var cyan=Color("77eee3")
var orange=Color("ffbc76")
var muted=Color("a8c5d5")
func configure(owner_game:Node)->void:
 game=owner_game;mouse_filter=Control.MOUSE_FILTER_IGNORE
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 refresh_layout()
func set_enabled(value:bool)->void:
 release_all();enabled=value;visible=value;_layout_key="";refresh_layout()
func release_all()->void:
 fingers.clear();owners.clear();axis=0.0;joystick_tip=Vector2.ZERO;_repeat_left=0;_mouse_down=false
 queue_redraw()
func _input(event:InputEvent)->void:
 if ingest(event):get_viewport().set_input_as_handled()
func ingest(event:InputEvent)->bool:
 if event is InputEventScreenTouch:
  if not enabled and event.pressed and not event.canceled:set_enabled(true)
  if not enabled:return false
  refresh_layout()
  # iOS4.6 may cancel with pressed=false at(-1,-1); release by ID first.
  if event.canceled or not event.pressed:_release(event.index)
  else:_press(event.index,event.position)
  return true
 if event is InputEventScreenDrag:
  if not enabled:return false
  _drag(event.index,event.position);return true
 if enabled and event is InputEventMouse:
  # Touch-generated mouse events must never become a second action.
  if event.device==InputEvent.DEVICE_ID_EMULATION:return true
  if OS.has_feature("mobile"):return true
  refresh_layout()
  if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
   if event.pressed:_mouse_down=true;_press(-100,event.position)
   else:_mouse_down=false;_release(-100)
  elif event is InputEventMouseMotion and _mouse_down:_drag(-100,event.position)
  return true
 return false
func _press(index:int,point:Vector2)->void:
 if fingers.has(index):_release(index)
 fingers[index]={"id":"","point":point}
 if game.mode=="play" and not game.paused and game.player.hp>0 and point.distance_to(joystick_center)<=joystick_radius+16 and not owners.has("stick"):
  owners.stick=index;fingers[index].id="stick";_move_stick(point);return
 for id in buttons:
  if _contains(buttons[id],point) and not owners.has(id):
   owners[id]=index;fingers[index].id=id
   if id=="light":_repeat_left=REPEAT_INTERVAL
   game.touch_command(id);queue_redraw();return
func _drag(index:int,point:Vector2)->void:
 if not fingers.has(index):return
 var id:String=fingers[index].id
 fingers[index].point=point
 if id=="stick":
  if not Rect2(Vector2.ZERO,get_viewport_rect().size).has_point(point):_release(index)
  else:_move_stick(point)
 elif not id.is_empty() and (not buttons.has(id) or not _contains(buttons[id],point)):
  # A finger leaving a button cannot enter/retrigger any button until lifted.
  owners.erase(id);fingers[index].id=""
  if id=="light":_repeat_left=0
 queue_redraw()
func _release(index:int)->void:
 if not fingers.has(index):return
 var id:String=fingers[index].id
 if owners.get(id,999999)==index:owners.erase(id)
 if id=="stick":axis=0;joystick_tip=Vector2.ZERO
 if id=="light":_repeat_left=0
 fingers.erase(index);queue_redraw()
func _move_stick(point:Vector2)->void:
 joystick_tip=(point-joystick_center).limit_length(joystick_radius)
 var raw:float=clampf(joystick_tip.x/joystick_radius,-1,1)
 axis=0.0 if absf(raw)<=DEADZONE else signf(raw)*(absf(raw)-DEADZONE)/(1.0-DEADZONE)
 queue_redraw()
func _contains(data:Dictionary,point:Vector2)->bool:
 return point.distance_to(data.center)<=float(data.radius) if data.has("radius") else data.rect.has_point(point)
func _process(dt:float)->void:
 if not game or not enabled:return
 var gate:String=game.mode+str(game.paused)+str(game.player.hp<=0)
 if gate!=_last_gate:release_all();_last_gate=gate
 refresh_layout()
 if game.mode=="play" and not game.paused and game.player.hp>0 and owners.has("light"):
  _repeat_left-=dt
  if _repeat_left<=0:_repeat_left=REPEAT_INTERVAL;game.touch_command("light")
 queue_redraw()
func refresh_layout()->void:
 if not game:return
 var bounds=Rect2(Vector2.ZERO,get_viewport_rect().size)
 var area:Rect2=bounds
 if qa_safe_rect.has_area():area=bounds.intersection(qa_safe_rect)
 elif OS.has_feature("mobile"):
  var pixels=Rect2(DisplayServer.get_display_safe_area())
  if pixels.has_area():area=bounds.intersection(get_viewport().get_screen_transform().affine_inverse()*pixels)
 if area.size.x<640 or area.size.y<360:area=bounds
 var next_safe:Rect2=area.grow(-16)
 var key:String=str(next_safe)+game.mode+str(game.paused)+str(game.level_id)+str(game.saved_checkpoint)+str(game.victory_elapsed>=.72)+str(game.volume)+str(game.shake_amount)
 if key==_layout_key:return
 release_all();safe=next_safe;_layout_key=key;_last_gate=game.mode+str(game.paused)+str(game.player.hp<=0);buttons.clear()
 layout_scale=minf(1.0,minf(safe.size.x/1248.0,safe.size.y/688.0))
 joystick_radius=74.0*layout_scale
 joystick_center=Vector2(safe.position.x+104*layout_scale,safe.end.y-102*layout_scale)
 var middle:float=safe.get_center().x
 if game.mode=="menu":
  for row in 3:_rect(["stage1","stage2","continue"][row],Rect2(safe.end.x-414*layout_scale,safe.position.y+(244+row*83)*layout_scale,382*layout_scale,68*layout_scale),["第一关 · 星港","第二关 · 冷却环线","继续维修点" if game.saved_checkpoint>0 else "暂无检查点"][row])
 elif game.paused:
  _rect("resume",Rect2(middle-188,safe.position.y+215,376,64),"继续行动")
  _rect("volume",Rect2(middle-188,safe.position.y+299,182,62),"声音 "+("开" if game.volume>0 else "关"))
  _rect("shake",Rect2(middle+6,safe.position.y+299,182,62),"震屏 "+("关" if game.shake_amount<=0 else ("轻" if game.shake_amount<.4 else "标准")))
  _rect("menu",Rect2(middle-188,safe.position.y+383,376,64),"返回选关")
 elif game.mode in ["dead","win"]:
  _rect("next" if game.mode=="win" and game.level_id==1 else "retry",Rect2(middle-202,safe.position.y+347,404,66),"进入第二关" if game.mode=="win" and game.level_id==1 else ("重玩本关" if game.mode=="win" else "从检查点重试"))
  _rect("menu",Rect2(middle-202,safe.position.y+436,404,62),"返回选关")
 elif game.mode=="play":
  _rect("pause",Rect2(safe.end.x-76,safe.position.y,76,60),"暂停")
  _circle("light",Vector2(safe.end.x-76*layout_scale,safe.end.y-106*layout_scale),58*layout_scale,"攻击")
  _circle("jump",Vector2(safe.end.x-200*layout_scale,safe.end.y-83*layout_scale),46*layout_scale,"跳跃")
  _circle("heavy",Vector2(safe.end.x-191*layout_scale,safe.end.y-203*layout_scale),44*layout_scale,"重击")
  _circle("dodge",Vector2(safe.end.x-78*layout_scale,safe.end.y-235*layout_scale),44*layout_scale,"闪避")
  _circle("skill",Vector2(safe.end.x-296*layout_scale,safe.end.y-76*layout_scale),44*layout_scale,"磁轨")
  _circle("interact",Vector2(safe.end.x-299*layout_scale,safe.end.y-187*layout_scale),38*layout_scale,"交互")
  if game.level_id==2:
   for i in 3:_circle(["bomb","armor","repair"][i],Vector2(middle+(-116+116*i)*layout_scale,safe.end.y-48*layout_scale),36*layout_scale,["爆破","护甲","维修"][i])
 queue_redraw()
func _rect(id:String,r:Rect2,label:String)->void:buttons[id]={"rect":r,"label":label}
func _circle(id:String,center:Vector2,radius:float,label:String)->void:buttons[id]={"center":center,"radius":radius,"rect":Rect2(center-Vector2.ONE*radius,Vector2.ONE*radius*2),"label":label}
func _panel(r:Rect2,tint:Color=Color(.025,.075,.12,.88))->void:
 var box=StyleBoxFlat.new();box.bg_color=tint;box.border_color=Color(.31,.67,.73,.7);box.set_border_width_all(1);box.set_corner_radius_all(13);draw_style_box(box,r)
func _text(value:String,point:Vector2,size_px:int=22,tint:Color=Color.WHITE)->void:draw_string(game.font,point,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px,tint)
func _center(value:String,x:float,y:float,size_px:int=22,tint:Color=Color.WHITE)->void:_text(value,Vector2(x-game.font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x/2,y),size_px,tint)
func _draw()->void:
 if not enabled or not game or not game.font:return
 var mid:float=safe.get_center().x
 if game.mode=="menu":
  draw_rect(get_viewport_rect(),Color(.005,.025,.055,.70));_panel(safe.grow(-24))
  _text("星港机甲小队",safe.position+Vector2(52,99),46,cyan)
  _text("银翼 · 触屏行动",safe.position+Vector2(54,150),27)
  var frame=game.hero_frames.idle[0];draw_texture_rect(frame,Rect2(safe.position+Vector2(120,170),Vector2(350,350)),false)
  _text("左摇杆移动 · 右侧出招",safe.position+Vector2(54,550),24,muted)
  _text("按住攻击连续出招 · 点按跳跃 / 闪避",safe.position+Vector2(54,589),20,muted)
  _text("MVP 0.6  /  两关可选",safe.position+Vector2(54,629),19,cyan)
 elif game.paused or game.mode in ["dead","win"]:
  draw_rect(get_viewport_rect(),Color(.005,.02,.05,.74));_panel(Rect2(mid-278,safe.position.y+100,556,496))
  _center("行动暂停" if game.paused else ("行动完成" if game.mode=="win" else "银翼暂时失去连接"),mid,safe.position.y+162,32,cyan)
  if not game.paused:
   _center("用时 %02d:%02d · 受击 %d · 重试 %d"%[int(game.run_time)/60,int(game.run_time)%60,game.hits_taken,game.retries],mid,safe.position.y+232,22)
   _center("维修点会恢复保存的物资" if game.mode=="dead" else "星港行动记录已保存",mid,safe.position.y+286,20,muted)
 else:
  _draw_hud()
  draw_circle(joystick_center,joystick_radius,Color(.025,.08,.12,.38))
  draw_arc(joystick_center,joystick_radius,0,TAU,64,Color(.50,.91,.93,.65),2,true)
  draw_line(joystick_center-Vector2(50,0),joystick_center+Vector2(50,0),Color(.5,.85,.9,.35),2,true)
  draw_circle(joystick_center+joystick_tip*.64,30,Color(.35,.84,.88,.70) if owners.has("stick") else Color(.18,.44,.51,.60))
  _center("移动",joystick_center.x,joystick_center.y+joystick_radius+24,18,muted)
 for id in buttons:_draw_button(id,buttons[id])
 if not OS.has_feature("mobile"):_text("触控预览 · F7切换",safe.position+Vector2(6,safe.size.y-4),15,muted)
func _draw_button(id:String,data:Dictionary)->void:
 var pressed:bool=owners.has(id)
 var ready:bool=true
 var cd:float=0.0
 if id=="skill":cd=game.player.skill_cd
 if id=="dodge":cd=game.player.dodge_cd
 if id in ["bomb","armor","repair"]:ready=game.inventory.counts[id]>0;cd=game.inventory.cooldown
 if id=="continue":ready=game.saved_checkpoint>0
 var tone:Color=cyan if ready else Color(.42,.53,.59)
 if data.has("radius"):
  var center:Vector2=data.center;var radius:float=data.radius
  draw_circle(center,radius,Color(.055,.24,.29,.75) if pressed else Color(.015,.05,.09,.49))
  draw_arc(center,radius,0,TAU,48,tone if pressed else Color(tone,.65),2.5 if pressed else 1.5,true)
  if id in ["bomb","armor","repair"]:
   if game.item_textures.has(id):draw_texture_rect(game.item_textures[id],Rect2(center-Vector2(20,25),Vector2(40,40)),false,Color.WHITE if ready else Color(.5,.5,.5,.7))
   _center(str(game.inventory.counts[id]),center.x+23,center.y+22,20,tone)
   _center(data.label,center.x,center.y+radius+21,17,muted)
  else:_center(data.label,center.x,center.y+7,26 if id=="light" else 22,tone)
  if cd>0:
   draw_circle(center,radius,Color(.01,.025,.05,.65));_center("%.1f"%cd,center.x,center.y+8,24,Color.WHITE)
 else:
  _panel(data.rect,Color(.045,.37,.40,.96) if pressed else Color(.045,.18,.24,.94))
  _center(data.label,data.rect.get_center().x,data.rect.get_center().y+8,22,tone)
func _draw_hud()->void:
 var p:Vector2=safe.position
 _panel(Rect2(p,Vector2(306,97)))
 _text("银翼",p+Vector2(16,29),22,cyan)
 _text("%d / 100"%game.player.hp,p+Vector2(206,28),18)
 draw_rect(Rect2(p+Vector2(16,44),Vector2(274,12)),Color(.13,.20,.27,.9))
 draw_rect(Rect2(p+Vector2(16,44),Vector2(274*game.player.hp/100.0,12)),cyan if game.player.hp>25 else orange)
 _text("护甲 %d"%game.inventory.armor if game.level_id==2 else "观察起手 · 收招反击",p+Vector2(16,80),18,muted)
 _text("%02d:%02d"%[int(game.run_time)/60,int(game.run_time)%60],p+Vector2(231,80),17,muted)
 _panel(Rect2(Vector2(safe.end.x-322,p.y),Vector2(232,85)))
 _text("01 失控的星港" if game.level_id==1 else "02 冷却环线",Vector2(safe.end.x-307,p.y+30),20)
 _text("敌情 · 剩余 %d"%game.alive_count() if game.active_zone>=0 else "向右推进 →",Vector2(safe.end.x-307,p.y+62),18,orange if game.active_zone>=0 else cyan)
 var info:String="";var boss=null
 for enemy in game.enemies:
  if enemy.kind=="boss" and not enemy.dead:boss=enemy;break
 if boss:
  var hint:Dictionary=boss.boss_wave_hint(game);info=hint.text
  if info.is_empty():info="冷却中 · 靠近身体反击" if boss.state=="recover" else ("前刺 · 后撤或闪避" if boss.state=="windup" else "观察起手")
  var r=Rect2(safe.get_center().x-225,p.y+114,450,12)
  draw_rect(r,Color(.1,.14,.2,.9));draw_rect(Rect2(r.position,Vector2(r.size.x*boss.hp/boss.max_hp,12)),orange)
 else:
  if game.level_id==2:info=game.coolant.objective_hint(game)
  if info.is_empty() and game.status_timer>0:info=game.status
 if not info.is_empty():
  var r=Rect2(safe.get_center().x-222,p.y+4,444,98)
  _panel(r)
  for line in range(mini(3,int(ceil(info.length()/21.0)))):_text(info.substr(line*21,21),r.position+Vector2(13,29+28*line),20,cyan)
 if game.dialogue_timer>0:
  _panel(Rect2(safe.get_center().x-270,p.y+147,540,61));_center("米米：维修完成，检查点已保存",safe.get_center().x,p.y+185,22,cyan)
 if not game.save_warning.is_empty():_center(game.save_warning,safe.get_center().x,p.y+232,18,orange)
