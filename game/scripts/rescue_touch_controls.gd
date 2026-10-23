extends "res://scripts/touch_controls.gd"
var _exo_visible:bool=false
func refresh_layout()->void:
 if not game:return
 var suit:bool=game.exosuit.active
 if suit!=_exo_visible:_exo_visible=suit;_layout_key="";release_all()
 super.refresh_layout()
 if game.mode=="menu":
  buttons.clear()
  var u:float=layout_scale
  for i in 4:_rect(["stage1","stage2","stage3","continue"][i],Rect2(safe.end.x-414*u,safe.position.y+(218+i*84)*u,382*u,66*u),["第一关 · 星港","第二关 · 冷却环线","第三关 · 赤炉救援","继续维修点" if game.can_continue() else "暂无检查点"][i])
  _rect("silverwing",Rect2(safe.position.x+44*u,safe.position.y+184*u,175*u,58*u),"银翼")
  _rect("feiren",Rect2(safe.position.x+235*u,safe.position.y+184*u,175*u,58*u),"绯刃" if game.feiren_unlocked else "绯刃 · 待救援")
 elif game.mode=="win" and not game.paused and game.level_id==2:
  buttons.erase("retry");_rect("next",Rect2(safe.get_center().x-202,safe.position.y+347,404,66),"进入第三关")
 elif game.mode=="play" and not game.paused:
  if game.level_id in [2,3] and not suit:
   for i in 3:_circle(["bomb","armor","repair"][i],Vector2(safe.get_center().x+(-116+116*i)*layout_scale,safe.end.y-64*layout_scale),36*layout_scale,["爆破","护甲","维修"][i])
  if suit:
   for id in ["bomb","armor","repair"]:buttons.erase(id)
   buttons.light.label="连射";buttons.heavy.label="重炮";buttons.skill.label="震荡";buttons.interact.label="脱离"
  elif buttons.has("skill"):buttons.skill.label="焰冲" if game.selected_character=="feiren" else "磁轨"
func _draw()->void:
 if not enabled or not game or not game.font:return
 if game.mode!="menu":
  super._draw()
  if game.mode=="dead" and not game.paused:
   var middle:float=safe.get_center().x
   _panel(Rect2(middle-250,safe.position.y+119,500,61),Color("#0b1920"))
   _center(game.character_name()+"暂时失去连接",middle,safe.position.y+162,32,cyan)
  return
 var u:float=layout_scale
 draw_rect(get_viewport_rect(),Color(.035,.018,.022,.8));_panel(safe.grow(-24))
 _text("星港机甲小队",safe.position+Vector2(44,82)*u,int(43*u),orange)
 _text("第三行动 · 赤炉救援",safe.position+Vector2(47,132)*u,int(26*u))
 var group:Array=game.hero_frames.get("idle",[])
 if not group.is_empty():draw_texture_rect(group[0],Rect2(safe.position+Vector2(116,249)*u,Vector2(315,315)*u),false)
 _text("绯刃：焰冲近身突进" if game.selected_character=="feiren" else "银翼：磁轨远程压制",safe.position+Vector2(48,589)*u,int(21*u),muted)
 _text("MVP 0.9 · 按角色与关卡开始行动",safe.position+Vector2(48,632)*u,int(18*u),orange)
 for id in buttons:_draw_button(id,buttons[id])
func _draw_hud()->void:
 super._draw_hud()
 var p:Vector2=safe.position
 if game.level_id==1:
  for enemy in game.enemies:
   if enemy.kind=="boss" and not enemy.dead and enemy.state=="windup" and enemy.move_name in ["sweep","charge"] and enemy.boss_wave_hint(game).text.is_empty():
    var box=Rect2(safe.get_center().x-222,p.y+4,444,98);_panel(box,Color("#0b1920"))
    _text("横扫 · 后撤或闪避" if enemy.move_name=="sweep" else "冲撞 · 闪避或跳开",box.position+Vector2(13,42),23,orange)
 _panel(Rect2(p+Vector2(6,5),Vector2(108,31)),Color("#0b1920"));_text(game.character_name(),p+Vector2(16,29),22,orange if game.selected_character=="feiren" else cyan)
 if game.level_id==3:
  _panel(Rect2(p+Vector2(6,59),Vector2(217,32)),Color("#0b1920"))
  _text("护甲 %d"%game.inventory.armor,p+Vector2(16,80),18,muted)
  _panel(Rect2(Vector2(safe.end.x-322,p.y),Vector2(232,85)),Color("#0b1920"))
  _text("03 赤炉救援",Vector2(safe.end.x-307,p.y+30),20,orange)
  _text("绯刃已解锁" if game.feiren_unlocked else "目标：解救绯刃",Vector2(safe.end.x-307,p.y+62),18,orange)
  var info:String=game.furnace.objective_hint(game)
  var has_boss:bool=false
  for enemy in game.enemies:
   if enemy.kind=="boss" and not enemy.dead:
    has_boss=true
    if enemy.state=="windup" and enemy.move_name=="sweep" and enemy.boss_wave_hint(game).text.is_empty():
     var box=Rect2(safe.get_center().x-222,p.y+4,444,98);_panel(box,Color("#0b1920"))
     _text("横扫 · 后撤或闪避",box.position+Vector2(13,42),23,orange)
    break
  if not info.is_empty() and not has_boss:
   var r=Rect2(safe.get_center().x-222,p.y+4,444,98);_panel(r,Color("#0b1920"))
   for i in range(mini(3,int(ceil(info.length()/21.0)))):_text(info.substr(i*21,21),r.position+Vector2(13,29+28*i),20,orange)
 if game.level_id==3 and game.dialogue_timer>0 and game.checkpoint>=2:
  _panel(Rect2(safe.get_center().x-270,p.y+147,540,61),Color("#0b1920"))
  _center("绯刃：热刃恢复！先突破撤离口！",safe.get_center().x,p.y+175,22,orange)
  _center("已永久解锁 · 返回选关可切换角色",safe.get_center().x,p.y+199,17,muted)
 if game.exosuit.active:
  var r=Rect2(safe.get_center().x-222,p.y+4,444,98);_panel(r,Color("#2b2420"))
  _text("赤隼   耐久 %d / 140"%game.exosuit.durability,r.position+Vector2(14,29),21,orange)
  _text("动力 %.1fs"%game.exosuit.remaining,r.position+Vector2(302,29),20)
  draw_rect(Rect2(r.position+Vector2(15,44),Vector2(414,11)),Color("#53362a"))
  draw_rect(Rect2(r.position+Vector2(15,44),Vector2(414*game.exosuit.durability/140.0,11)),orange)
  draw_rect(Rect2(r.position+Vector2(15,68),Vector2(414*game.exosuit.remaining/30.0,8)),Color("#ffe4ad"))
  _text("脱离后本次不能重新充能",r.position+Vector2(14,93),15,muted)
func _draw_button(id:String,data:Dictionary)->void:
 if id=="continue" and game.can_continue() and game.saved_checkpoint==0:
  _panel(data.rect);_center(data.label,data.rect.get_center().x,data.rect.get_center().y+8,22,cyan);return
 if id in ["silverwing","feiren"]:
  var selected:bool=game.selected_character==id
  _panel(data.rect,Color("#795134") if selected else Color("#2a303a"))
  _center(data.label,data.rect.get_center().x,data.rect.get_center().y+8,int(21*layout_scale),orange if selected else muted);return
 if game.exosuit.active and id in ["heavy","skill"]:
  var cd:float=game.exosuit.heavy_cd if id=="heavy" else game.exosuit.shock_cd
  draw_circle(data.center,data.radius,Color(.16,.1,.07,.65));draw_arc(data.center,data.radius,0,TAU,48,orange,2,true)
  _center("%.1f"%cd if cd>0 else data.label,data.center.x,data.center.y+8,22,orange);return
 super._draw_button(id,data)
