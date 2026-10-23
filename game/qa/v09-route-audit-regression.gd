extends SceneTree
## Independent fixtures for the actual v0.9 main scene. Positions are staged
## deliberately to isolate interaction/progression; not a full route traversal.
var game
var results:Array=[]
var failures:Array=[]
const DT:float=1.0/60.0
func _initialize()->void:call_deferred("run")
func check(id:String,condition:bool,detail:String="")->void:
 results.append({"id":id,"passed":condition,"detail":detail})
 if not condition:failures.append(id)
 print("ROUTE_AUDIT_", "PASS " if condition else "FAIL ",id," ",detail)
func stand(point:Vector2)->void:
 game.player.reset_at(point-Vector2(0,2));game.player.invuln=999
 for i in 5:await physics_frame;game.player.tick(DT,0)
func fresh(level:int)->void:
 game.selected_level=level;game.start_run(false);game.test_mode=true;game.set_physics_process(false);game.qa_no_drops=true
 game.feiren_unlocked=false if level==3 else game.feiren_unlocked
func open_devices(level:int)->void:
 if level==1:game.relays.reset(2)
 elif level==2:game.coolant.opened.assign(["intake","return","core"])
 else:game.furnace.opened.assign(["freight","restraint_a","restraint_b"]);game.feiren_unlocked=true
func run()->void:
 game=load("res://main.tscn").instantiate();root.add_child(game);game.set_physics_process(false);game.hide()
 for level in [1,2,3]:await test_route(level)
 await test_switches()
 await test_checkpoints()
 await test_rescue_and_pod()
 test_empty_and_victory()
 var file=FileAccess.open("res://qa/v09-route-audit-results.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"scope":"Independent actual-main deterministic fixtures. Boundary, encounter, device, checkpoint, rescue and boss-victory logic are exercised with deliberately staged positions; not a GUI or complete traversal test.","checks":results.size(),"failures":failures,"results":results},"  "));file.close()
 game.clear_combat();game.music.stop();game.music.stream=null
 for audio in game.audio_pool:audio.stop();audio.stream=null
 game.queue_free();game=null;await process_frame;await process_frame;await create_timer(.05).timeout
 print("ROUTE_AUDIT_FINISHED ",results.size()," checks ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
func test_route(level:int)->void:
 fresh(level)
 var label:String="L%d_"%level
 game.player.position=Vector2(game.zones[0].start+10,574);game.update_zones()
 check(label+"first_wave_spawns",game.enemies.size()==game.zones[0].waves[0].size())
 check(label+"ordinary_fight_not_left_wall",is_equal_approx(game.left_bound(),35))
 check(label+"ordinary_fight_not_right_wall",game.right_bound()>game.zones[0].right)
 var first_ids:Array=[]
 for e in game.enemies:first_ids.append(e.get_instance_id())
 open_devices(level)
 game.player.position=Vector2(game.zones[1].start+10,574);game.update_zones()
 var current_ids:Array=[]
 for e in game.enemies:current_ids.append(e.get_instance_id())
 var retained:bool=true
 for id in first_ids:retained=retained and id in current_ids
 check(label+"next_zone_while_first_alive",game.encounter_waves.has(1) and game.encounter_alive(0)>0)
 check(label+"earlier_enemies_retained",retained)
 var count:int=game.enemies.size()
 game.player.position=Vector2(game.zones[0].start-20,574);game.update_zones()
 game.player.position=Vector2(game.zones[1].start+10,574);game.update_zones()
 check(label+"backtrack_no_duplicate_spawns",game.enemies.size()==count)
 # Each zone resolves its own wave ledger even while another remains alive.
 for e in game.enemies:
  if int(e.get_meta("encounter_zone",-1))==0:e.dead=true
 game.update_zones()
 if game.zones[0].waves.size()>1:check(label+"wave_two_independent",game.encounter_waves[0]==1 and game.encounter_alive(0)==game.zones[0].waves[1].size() and game.encounter_alive(1)>0)
 else:check(label+"completion_independent",0 in game.completed_zones and game.encounter_alive(1)>0)
 game.player.position=Vector2(game.zones[-1].start+5,574);game.update_zones()
 var boss_count:int=0
 for e in game.enemies:
  if e.kind=="boss" and not e.dead:boss_count+=1
 check(label+"boss_spawns_with_earlier_alive",boss_count==1 and game.encounter_alive(1)>0)
 check(label+"world_edge_valid",is_equal_approx(game.right_bound(),17565.0 if level==3 else 13565.0))
func test_switches()->void:
 fresh(1);game.player.position=Vector2(880,574);game.update_zones()
 check("L1_real_gate_remains",is_equal_approx(game.right_bound(),2465))
 for station in game.LevelData.RELAY_STATIONS:
  for terminal in station.switches:
   await stand(terminal.feet);game.active_zone=0;game.interact()
   check("L1_relay_%d_%d_operates_with_living_enemies"%[station.id,terminal.id],game.relays.is_switch_active(station.id,terminal.id) and game.alive_count()>0)
 check("L1_no_extra_guard_required",game.enemies.size()==1 and game.relays.is_station_open(2))
 fresh(2);game.player.position=Vector2(910,574);game.update_zones()
 check("L2_real_gate_remains",is_equal_approx(game.right_bound(),3205))
 for valve in game.CoolantScript.VALVES:
  await stand(valve.feet);game.active_zone=0;game.interact()
  check("L2_valve_"+valve.id+"_operates_with_living_enemies",valve.id in game.coolant.opened and game.alive_count()>0)
 fresh(3);game.player.position=Vector2(1040,574);game.update_zones()
 check("L3_real_gate_remains",is_equal_approx(game.right_bound(),3635))
 for item in game.FurnaceScript.SWITCHES:
  await stand(item.feet);game.active_zone=0;game.interact()
  check("L3_switch_"+item.id+"_operates_with_living_enemies",item.id in game.furnace.opened and game.alive_count()>0)
func test_checkpoints()->void:
 for level in [1,2,3]:
  fresh(level);open_devices(level);game.player.position=Vector2(game.zones[0].start+10,574);game.update_zones()
  var points:Array=[Vector2(game.LevelData.NPC_X,574),Vector2(game.CORE_NPC_X,574)] if level==1 else (game.CoolantScript.CHECKPOINTS if level==2 else [Vector2(game.FurnaceScript.CHECKPOINTS[0],574),Vector2(game.FurnaceScript.CHECKPOINTS[1],574)])
  for i in 2:
   await stand(points[i]);game.active_zone=0;game.interact()
   check("L%d_checkpoint%d_with_living_enemies"%[level,i+1],game.checkpoint==i+1 and game.alive_count()>0)
   var data:Variant=game.read_saved_json(game.SAVE_V08)
   check("L%d_checkpoint%d_valid_save"%[level,i+1],game.valid_terrain_save(data))
  game.mode="dead";game.retry_checkpoint();game.test_mode=true
  check("L%d_retry_resets_encounter_ledger"%level,game.encounter_waves.is_empty() and game.enemies.is_empty())
  check("L%d_retry_correct_world_bound"%level,game.right_bound()>game.player.position.x)
  game.player.position=Vector2(game.zones[-1].start+5,574);game.update_zones()
  check("L%d_retry_can_spawn_boss"%level,game.encounter_alive(game.zones.size()-1)==1)
func test_rescue_and_pod()->void:
 fresh(3);game.player.position=Vector2(1040,574);game.update_zones()
 game.furnace.opened.assign(["freight","restraint_a"])
 game.player.position=Vector2(game.FurnaceScript.RESCUE_X,574);game.rescue_feiren()
 check("rescue_requires_both_switches",not game.feiren_unlocked)
 game.furnace.opened.append("restraint_b");game.player.position=Vector2(game.FurnaceScript.RESCUE_X,574);game.rescue_feiren()
 check("rescue_no_clear_required",game.feiren_unlocked and game.checkpoint==2 and game.alive_count()>0)
 check("single_pod_after_rescue",game.FurnaceScript.PODS.size()==1 and game.FurnaceScript.PODS[0].x>game.FurnaceScript.RESCUE_X)
 await stand(Vector2(game.FurnaceScript.PODS[0].x,574));game.interact()
 check("pod_real_entry_works",game.exosuit.active and game.spent_pods==["rescue"])
 game.exosuit.exit(game,"manual");game.interact()
 check("pod_cannot_refill_after_exit",not game.exosuit.active and game.spent_pods==["rescue"])
 game.mode="dead";game.retry_checkpoint();game.test_mode=true
 await stand(Vector2(game.FurnaceScript.PODS[0].x,574));game.interact()
 check("pod_cannot_refill_after_retry",not game.exosuit.active and "rescue" in game.spent_pods)
func test_empty_and_victory()->void:
 for level in [1,2,3]:
  fresh(level);open_devices(level)
  game.player.position=Vector2(210,574);game.update_zones();check("L%d_empty_world_not_victory"%level,game.mode=="play")
  game.player.position=Vector2(game.zones[-1].start+5,574);game.update_zones()
  var boss=null
  for e in game.enemies:
   if e.kind=="boss":boss=e
  check("L%d_victory_fixture_has_real_boss"%level,boss!=null)
  if boss!=null:boss.hit(99999,true,game.player.position.x,991230+level,game,true,boss.pos)
  var leftovers:int=game.alive_count();game.update_zones()
  check("L%d_boss_death_wins_with_normal_enemies_alive"%level,game.mode=="win" and leftovers>0,"leftovers="+str(leftovers))
