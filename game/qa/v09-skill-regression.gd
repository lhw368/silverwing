extends SceneTree
const FX=preload("res://scripts/skill_presentation.gd")
const Game=preload("res://scripts/furnace_presentation.gd")
const Enemy=preload("res://scripts/terrain_enemy.gd")
var checks:Array=[]
var failures:Array=[]
var game
var fx
func _initialize()->void: call_deferred("run")
func check(id:String,ok:bool,detail:String="")->void:
 checks.append({"id":id,"passed":ok,"detail":detail})
 if not ok:failures.append(id)
 print(("SKILL_PASS " if ok else "SKILL_FAIL ")+id+" "+detail)
func reset(rects:Array=[])->void:
 game.clear_combat();fx.reset();game.level_id=3;game.mode="play";game.paused=false;game.effects_enabled=true
 game.selected_character="silverwing";game.feiren_unlocked=true;game.player.reset_at(Vector2(300,574));game.player.invuln=0
 game.furnace.opened.assign(["freight","restraint_a","restraint_b"])
 for child in game.world_geometry.get_children():child.free()
 for rect in [Rect2(-500,574,15000,300)]+rects:
  var body=StaticBody2D.new();var collider=CollisionShape2D.new();var box=RectangleShape2D.new();box.size=rect.size;collider.shape=box;collider.position=rect.get_center();body.add_child(collider);game.world_geometry.add_child(body)
func enemy(at:Vector2):
 var e=Enemy.new("melee",at);e.attach_physics(game);e.hp=200;e.max_hp=200;game.enemies.append(e);return e
func snapshot()->Dictionary:
 return {"hp":game.player.hp,"pos":game.player.position,"velocity":game.player.velocity,"state":game.player.state,"elapsed":game.player.elapsed,"skill_cd":game.player.skill_cd,"hitstop":game.player.hitstop,"projectiles":game.projectiles.duplicate(true)}
func run()->void:
 game=Game.new();root.add_child(game);game.set_physics_process(false);game.hide();game.test_mode=true
 fx=FX.new();reset()
 check("generated_flame_texture_imported",fx.flame_texture!=null)
 var initial:Dictionary=snapshot();fx.on_skill(game,9000);fx.tick(1.0/60,game);check("helper_does_not_mutate_combat",snapshot()==initial)
 seed(99191);var expected_random:float=randf();seed(99191);fx._emit(Vector2.ZERO,"silverwing",4,1);check("vfx_rng_does_not_change_loot_rng",randf()==expected_random)
 reset();var e=enemy(Vector2(410,574));fx.on_skill(game,9001);game.player_strike("skill",1,9001,true)
 check("silverwing_original_projectile_contract",game.projectiles.size()==1 and game.projectiles[0].damage==24 and game.projectiles[0].radius==36 and game.projectiles[0].vx==640 and game.projectiles[0].life==.85)
 for i in 20:game.update_effects(1.0/60);fx.tick(1.0/60,game)
 check("silverwing_original_damage_and_one_hit",e.hp==176 and e.hit_serials.has(9001))
 var before:int=fx.total_confirmed_hits;fx.on_hit(game,111111,Vector2.ZERO);check("unrelated_attack_no_skill_impact",fx.total_confirmed_hits==before)
 fx.on_hit(game,9001,Vector2(400,520));check("accepted_contact_has_local_impact",fx.total_confirmed_hits==before+1 and fx.flashes.back().pos==Vector2(400,520))
 reset([Rect2(445,350,30,224)]);fx.on_skill(game,9002);game.player_strike("skill",1,9002,true)
 for i in 18:game.update_effects(1.0/60);fx.tick(1.0/60,game)
 check("real_wall_stops_rail_and_has_contact",game.projectiles.is_empty() and fx.total_wall_impacts>0)
 var pieces:Array=fx._visible_rects(Rect2(400,400,140,100));var clear:bool=true
 for piece in pieces:
  if piece.intersects(Rect2(445,350,30,224)):clear=false
 check("flame_crop_respects_real_solids",clear and pieces.size()==2)
 reset([Rect2(170,350,30,224)]);game.player.facing=-1;var left_before:int=fx.total_wall_impacts;fx.on_skill(game,9102);game.player_strike("skill",1,9102,true)
 for i in 18:game.update_effects(1.0/60);fx.tick(1.0/60,game)
 check("left_facing_wall_stops_at_true_contact",game.projectiles.is_empty() and fx.total_wall_impacts==left_before+1)
 reset([Rect2(345,400,50,174)]);var impacts:int=fx.total_wall_impacts;fx.on_skill(game,9003);game.player_strike("skill",1,9003,true);fx.tick(1.0/60,game)
 check("muzzle_blocked_no_phantom_projectile",game.projectiles.is_empty() and fx.total_wall_impacts==impacts+1)
 reset();game.selected_character="feiren";game.player.state="skill";game.player.elapsed=.25;e=enemy(Vector2(400,574))
 fx.on_skill(game,9004);game.player_strike("skill",1,9004,true);check("feiren_keeps_42_damage_and_no_projectile",e.hp==158 and game.projectiles.is_empty())
 for i in 90:
  game.player.position.x+=7;game.player.elapsed=.25;fx.tick(1.0/60,game);fx.on_hit(game,9004,game.player.position+Vector2(50,-60))
 check("bounded_particles_and_trails",fx.motes.size()<=56 and fx.trails.size()<=16 and fx.flashes.size()<=20)
 var count:int=fx.trails.size();var life:float=fx.trails[0].life;game.paused=true;fx.tick(.4,game);check("pause_freezes_visual_time",fx.trails.size()==count and fx.trails[0].life==life)
 game.paused=false;game.effects_enabled=false;initial=snapshot();fx.tick(1.0/60,game);check("f8_clears_decorative_effects_only",fx.motes.is_empty() and fx.trails.is_empty() and fx.flashes.is_empty() and snapshot()==initial)
 game.mode="dead";fx.tick(1.0/60,game);check("death_clears_stale_visuals",fx.rails.is_empty() and fx.trails.is_empty())
 var file=FileAccess.open("res://qa/v09-skill-results.json",FileAccess.WRITE);file.store_string(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures},"  "));file.close()
 game.clear_combat();game.music.stop();game.music.stream=null
 for audio in game.audio_pool:audio.stop();audio.stream=null
 game.queue_free();await process_frame;await process_frame
 print("SKILL_RESULT ",checks.size()," checks; failures=",failures);quit(0 if failures.is_empty() else 1)
