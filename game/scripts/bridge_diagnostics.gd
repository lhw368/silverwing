extends RefCounted
## Read-only, bounded gameplay diagnostics. No account, device, file-system,
## keyboard text, or personal data is captured. Never changes gates or gameplay.
const SAMPLE_INTERVAL:float=.10
const MAX_SAMPLES:int=600
const REPORT_PATH:String="user://bridge_diagnostics_v08.json"
var samples:Array[Dictionary]=[]
var elapsed:float=0.0

func _point(value:Vector2)->Array:return [snappedf(value.x,.01),snappedf(value.y,.01)]

func snapshot(game)->Dictionary:
 var enemies:Array=[]
 for enemy in game.enemies:
  if enemy.dead:continue
  var entry:Dictionary={"kind":enemy.kind,"pos":_point(enemy.pos),"state":enemy.state}
  if is_instance_valid(enemy.physics_body):
   entry["velocity"]=_point(enemy.physics_body.velocity)
   entry["floor"]=enemy.physics_body.is_on_floor();entry["wall"]=enemy.physics_body.is_on_wall()
  enemies.append(entry)
 var player=game.player
 return {"time":snappedf(game.run_time,.001),"level":game.level_id,"mode":game.mode,"paused":game.paused,"player":{"pos":_point(player.position),"state":player.state,"velocity":_point(player.velocity),"floor":player.is_on_floor(),"wall":player.is_on_wall()},"active_zone":game.active_zone,"completed":game.completed_zones.duplicate(),"switches":game.furnace.opened.duplicate(),"bounds":[game.left_bound(),game.right_bound()],"enemies":enemies,"exosuit":{"active":game.exosuit.active,"remaining":snappedf(game.exosuit.remaining,.01),"durability":game.exosuit.durability}}

func tick(dt:float,game)->void:
 if not is_instance_valid(game.player) or game.level_id!=3 or game.paused or game.mode!="play":return
 if game.active_zone!=3 and (game.player.position.x<7300 or game.player.position.x>9500):return
 elapsed+=maxf(0,dt)
 if elapsed<SAMPLE_INTERVAL:return
 elapsed=fmod(elapsed,SAMPLE_INTERVAL)
 samples.append(snapshot(game))
 if samples.size()>MAX_SAMPLES:samples.pop_front()

func save_report(game)->String:
 var output:Dictionary={"schema_version":1,"purpose":"furnace_bridge_gameplay_diagnostics","sample_interval":SAMPLE_INTERVAL,"max_samples":MAX_SAMPLES,"latest":snapshot(game),"samples":samples.duplicate(true)}
 var file:FileAccess=FileAccess.open(REPORT_PATH+".tmp",FileAccess.WRITE)
 if not file:return ""
 file.store_string(JSON.stringify(output,"  "));file.flush();file.close()
 if DirAccess.rename_absolute(REPORT_PATH+".tmp",REPORT_PATH)!=OK:return ""
 return REPORT_PATH
