extends "res://scripts/campaign.gd"
## Mobile adapter. Combat, physics, inventory and saves remain in the campaign.
const TouchScript=preload("res://scripts/touch_controls.gd")
var touch_ui:Control
static func is_touch_platform(platform:String)->bool:
 return platform in ["iOS", "Android"]
func _ready()->void:
 super._ready()
 var layer=CanvasLayer.new();layer.layer=20;add_child(layer)
 touch_ui=TouchScript.new();layer.add_child(touch_ui);touch_ui.configure(self)
 var platform:String=OS.get_name()
 var touch_platform:bool=is_touch_platform(platform) or OS.has_feature("mobile")
 touch_ui.set_enabled(touch_platform or "--touch" in OS.get_cmdline_user_args())
func movement_axis()->float:
 var keyboard:float=super.movement_axis()
 if touch_ui and touch_ui.enabled and touch_ui.axis!=0.0:return touch_ui.axis
 return keyboard
func clear_touch()->void:
 if touch_ui:touch_ui.release_all()
 if is_instance_valid(player):player.jump_buffer=0.0;player.combo_buffer=false
func _notification(what:int)->void:
 if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_APPLICATION_PAUSED,NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
  if touch_ui and touch_ui.enabled:
   clear_touch()
   if mode=="play":paused=true
func _unhandled_input(event:InputEvent)->void:
 if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F7:
  clear_touch();touch_ui.set_enabled(not touch_ui.enabled);get_viewport().set_input_as_handled();return
 var old_mode:String=mode;var old_pause:bool=paused
 super._unhandled_input(event)
 if old_mode!=mode or old_pause!=paused:clear_touch()
func start_run(resume:bool)->void:
 clear_touch();super.start_run(resume)
func retry_checkpoint()->void:
 clear_touch();super.retry_checkpoint()
func on_player_death()->void:
 clear_touch();super.on_player_death()
func touch_command(id:String)->bool:
 if not touch_ui or not touch_ui.enabled:return false
 if mode=="menu":
  if id in ["stage1","stage2"]:selected_level=1 if id=="stage1" else 2;start_run(false);return true
  if id=="continue" and saved_checkpoint>0:start_run(true);return true
  return false
 if id=="pause" and mode=="play" and not paused:clear_touch();paused=true;sfx("ui");return true
 if paused:
  if id=="resume":clear_touch();paused=false;return true
  if id=="menu":clear_touch();mode="menu";paused=false;return true
  if id=="volume":volume=0.0 if volume>0 else .6;AudioServer.set_bus_volume_db(0,linear_to_db(maxf(volume,.0001)));save_game();return true
  if id=="shake":shake_amount=0.0 if shake_amount>.4 else (.35 if shake_amount<=0 else .65);save_game();return true
  return false
 if mode in ["dead","win"]:
  if mode=="win" and victory_elapsed<.72:return false
  if id=="menu":clear_touch();mode="menu";return true
  if id=="retry":
   if mode=="dead":retry_checkpoint()
   else:selected_level=level_id;start_run(false)
   return true
  if id=="next" and mode=="win" and level_id==1:selected_level=2;start_run(false);return true
  return false
 if mode!="play" or player.hp<=0:return false
 if id in ["jump","light","heavy","dodge","skill"]:return player.begin_action(id)
 if id=="interact":interact();return true
 if id in ["bomb","armor","repair"] and level_id==2:return inventory.use_item(id,self)
 return false
func draw_menu()->void:
 if touch_ui and touch_ui.enabled:return
 super.draw_menu()
 panel(Rect2(66,650,650,44));text_at("F7 触控预览 · MVP 0.6 · 保留键盘操作",Vector2(82,679),19,CYAN)
func draw_hud()->void:
 if touch_ui and touch_ui.enabled:return
 super.draw_hud()
 panel(Rect2(1181,633,75,27),Color("#102936"));text_at("v0.6",Vector2(1194,653),14,CYAN)
func draw_pause()->void:
 if not (touch_ui and touch_ui.enabled):super.draw_pause()
func draw_result(won:bool)->void:
 if not (touch_ui and touch_ui.enabled):super.draw_result(won)
