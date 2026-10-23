extends RefCounted
## Presentation only. Owns no collision, damage, cooldown, movement or hitstop.
## Integration: on_skill BEFORE the authoritative strike; tick AFTER simulation;
## on_hit only from accepted enemy_hit_feedback; draw_back before the hero,
## draw after ordinary effects. All coordinates are world-space.

const MAX_MOTES := 56
const MAX_TRAILS := 16
const MAX_FLASHES := 20
const MAX_RAILS := 8
const FLAME_PATH := "res://assets/effects/skill-v09/feiren-flame-sheet.webp"
const CYAN := Color("69ddff")
const WHITE := Color("eaffff")
const GOLD := Color("ffbc48")
var rails: Dictionary = {}
var motes: Array = []
var trails: Array = []
var flashes: Array = []
var solids: Array = []
var flame_texture: Texture2D
var rng := RandomNumberGenerator.new()
var visual_clock: float = 0.0
var emission_clock: float = 0.0
var last_flame_root := Vector2.INF
var total_confirmed_hits: int = 0
var total_wall_impacts: int = 0

func _init() -> void:
 rng.seed = 906031
 if ResourceLoader.exists(FLAME_PATH): flame_texture = load(FLAME_PATH)

func reset() -> void:
 rails.clear(); motes.clear(); trails.clear(); flashes.clear(); solids.clear()
 emission_clock = 0.0; last_flame_root = Vector2.INF

func handles_projectile(shot: Dictionary) -> bool:
 # Player rail shots are the only friendly entries in this array. Vehicle shots
 # have their own owner/list and remain unchanged.
 return bool(shot.get("friendly", false))

func on_skill(game, serial: int) -> void:
 if game.mode != "play" or game.player.hp <= 0 or game.exosuit.active: return
 var role: String = game.selected_character
 var facing: int = game.player.facing
 var source: Vector2 = game.player.position + Vector2(0, -60)
 rails[serial] = {"role":role, "age":0.0, "life":1.5, "facing":facing,
  "source":source, "muzzle":source + Vector2(facing*40, 0),
  "last":source + Vector2(facing*40, 0), "shot_life":.85,
  "observed":false, "terminated":false}
 while rails.size() > MAX_RAILS: rails.erase(rails.keys()[0])
 if not game.effects_enabled: return
 _flash(source + Vector2(facing*(66 if role == "feiren" else 42), 0), role, .20, facing, false)
 _emit(source + Vector2(facing*48, 0), role, 10, facing)

func on_hit(game, serial: int, contact: Vector2, blocked: bool = false) -> void:
 if not rails.has(serial) or game.mode != "play": return
 total_confirmed_hits += 1
 if not game.effects_enabled: return
 var record: Dictionary = rails[serial]
 _flash(contact, record.role, .27 if blocked else .34, record.facing, true, blocked)
 _emit(contact, record.role, 7 if blocked else 13, record.facing)

func tick(dt: float, game) -> void:
 if game.paused: return
 if game.mode != "play": reset(); return
 visual_clock += dt
 solids.clear()
 if game.level_id == 3 and game.has_method("terrain_rects"):
  for item in game.terrain_rects(): solids.append(item.rect)
 for serial in rails.keys():
  var record: Dictionary = rails[serial]
  record.age += dt; record.life -= dt
  if record.life <= 0: rails.erase(serial); continue
  if record.role != "silverwing" or record.terminated: continue
  var actual: Dictionary = {}
  for shot in game.projectiles:
   if shot.get("friendly", false) and int(shot.get("serial", -1)) == int(serial): actual = shot; break
  if not actual.is_empty():
   record.last = actual.pos; record.shot_life = actual.life; record.observed = true
  else:
   # Reproduce only the real projectile's last swept segment for visual contact.
   # This never calls enemy.hit or manufactures an enemy impact.
   if game.level_id == 3 and game.has_method("terrain_sweep"):
    var begin: Vector2 = record.last if record.observed else record.source
    var end: Vector2 = begin + Vector2(record.facing*640.0*minf(dt, maxf(0,record.shot_life)), 0) if record.observed else record.muzzle
    var wall: Dictionary = game.terrain_sweep(begin, end, 36.0)
    if not wall.is_empty():
     total_wall_impacts += 1
     if game.effects_enabled:
      _flash(wall.contact, "silverwing", .26, record.facing, true, true)
      _emit(wall.contact, "silverwing", 8, -record.facing)
   record.terminated = true
 if not game.effects_enabled:
  motes.clear(); trails.clear(); flashes.clear(); last_flame_root = Vector2.INF
  return
 for particle in motes:
  particle.life -= dt
  particle.pos += particle.vel*dt
  particle.vel.y -= 100*dt if particle.role == "feiren" else -30*dt
 motes = motes.filter(func(p): return p.life > 0)
 for trail in trails: trail.life -= dt
 trails = trails.filter(func(p): return p.life > 0)
 for effect in flashes: effect.life -= dt
 flashes = flashes.filter(func(p): return p.life > 0)
 var player = game.player
 if not game.exosuit.active and game.selected_character == "feiren" and player.state == "skill" and player.elapsed >= .10 and player.elapsed < .40:
  emission_clock += dt
  if emission_clock >= .023 and (last_flame_root == Vector2.INF or last_flame_root.distance_to(player.position) > 4.0):
   emission_clock = 0.0; last_flame_root = player.position
   trails.append({"pos":player.position + Vector2(-player.facing*8,-53), "facing":player.facing, "life":.24, "max_life":.24, "frame":int(visual_clock*24)%6})
   while trails.size() > MAX_TRAILS: trails.pop_front()
   _emit(player.position + Vector2(-player.facing*30,-57), "feiren", 2, -player.facing)
 else: emission_clock = 0.0; last_flame_root = Vector2.INF

func _flash(point: Vector2, role: String, duration: float, facing: int, contact: bool, blocked: bool = false) -> void:
 flashes.append({"pos":point,"role":role,"life":duration,"max_life":duration,"facing":facing,"contact":contact,"blocked":blocked})
 while flashes.size() > MAX_FLASHES: flashes.pop_front()

func _emit(point: Vector2, role: String, count: int, facing: int) -> void:
 for i in mini(count, MAX_MOTES-motes.size()):
  var angle: float = rng.randf_range(-1.25,1.25) + (PI if facing<0 else 0.0)
  var duration: float = rng.randf_range(.13,.37)
  motes.append({"pos":point,"vel":Vector2.from_angle(angle)*rng.randf_range(90,250),"life":duration,"max_life":duration,"role":role,"size":rng.randf_range(1.2,2.7)})

func _inside_solid(point: Vector2) -> bool:
 for rect in solids:
  if rect.has_point(point): return true
 return false

func _visible_rects(area: Rect2) -> Array:
 var pieces: Array = [area]
 for solid in solids:
  if not area.intersects(solid): continue
  var next: Array = []
  for piece in pieces:
   var cut: Rect2 = piece.intersection(solid)
   if not cut.has_area(): next.append(piece); continue
   for remaining in [Rect2(piece.position,Vector2(piece.size.x,cut.position.y-piece.position.y)),
    Rect2(Vector2(piece.position.x,cut.end.y),Vector2(piece.size.x,piece.end.y-cut.end.y)),
    Rect2(Vector2(piece.position.x,cut.position.y),Vector2(cut.position.x-piece.position.x,cut.size.y)),
    Rect2(Vector2(cut.end.x,cut.position.y),Vector2(piece.end.x-cut.end.x,cut.size.y))]:
    if remaining.has_area(): next.append(remaining)
  pieces = next
  if pieces.is_empty(): break
 return pieces

func _flame(game, tip: Vector2, facing: int, width: float, height: float, frame: int, opacity: float) -> void:
 if not flame_texture or opacity <= 0: return
 # Trim sheet cells in UV space only; original authored pixels/alpha are intact.
 # Original hot-tip registration is x=495, y=294 within each 512px cell.
 var cell := Vector2((frame%3)*512, (frame/3)*512)
 var source := Rect2(cell+Vector2(26,125),Vector2(478,288))
 var area := Rect2(tip+Vector2(-width if facing>0 else 0,-height*.585),Vector2(width,height))
 for piece in _visible_rects(area):
  var fraction: Vector2 = (piece.position-area.position)/area.size
  var fraction_size: Vector2 = piece.size/area.size
  var region: Rect2 = Rect2(source.position+Vector2((fraction.x if facing>0 else 1.0-fraction.x-fraction_size.x)*source.size.x,fraction.y*source.size.y),fraction_size*source.size)
  var target: Rect2 = piece
  if facing<0: target.size.x = -target.size.x
  game.draw_texture_rect_region(flame_texture,target,region,Color(1,1,1,opacity))

func draw_back(game) -> void:
 if not game.effects_enabled or game.exosuit.active or game.mode == "menu": return
 for trail in trails:
  var fade: float = trail.life/trail.max_life
  _flame(game,trail.pos,trail.facing,118*(.7+.3*fade),64,trail.frame,.33*fade)
 var p = game.player
 if game.selected_character == "feiren" and p.state == "skill":
  var strength: float = clampf((p.elapsed-.07)/.05,0,1)*clampf((.48-p.elapsed)/.10,0,1)
  if strength>0: _flame(game,p.position+Vector2(p.facing*87,-65),p.facing,193,101,int(visual_clock*24)%6,.84*strength)

func draw(game) -> void:
 if game.mode == "menu": return
 for shot in game.projectiles:
  if handles_projectile(shot): _draw_rail(game,shot)
 if not game.effects_enabled: return
 _draw_charge(game)
 for effect in flashes: _draw_flash(game,effect)
 for particle in motes:
  if _inside_solid(particle.pos): continue
  var alpha: float = minf(1.0,particle.life/particle.max_life*1.8)
  var color: Color = GOLD if particle.role == "feiren" else CYAN
  color.a = alpha
  var tail: Vector2 = particle.pos-particle.vel.normalized()*(5+particle.size*2)
  if _inside_solid(tail): tail=particle.pos
  game.draw_line(tail,particle.pos,color,particle.size,true)
  game.draw_circle(particle.pos,particle.size*.55,Color(1,.97,.8,alpha))

func _draw_charge(game) -> void:
 var p = game.player
 if p.state != "skill" or p.elapsed >= .24 or game.exosuit.active: return
 var t: float = clampf(p.elapsed/.24,0,1)
 var point: Vector2 = p.position+Vector2(p.facing*65,-77)
 if _inside_solid(point): return
 if game.selected_character == "feiren":
  _flame(game,point,p.facing,55+45*t,40+12*t,int(visual_clock*24)%6,t*.8)
  return
 # Mechanical focusing coils contract towards a tight beam emitter.
 for layer in 3:
  var radius: float = (35-layer*7)*(1.15-t*.48)
  var start: float = visual_clock*(5+layer*2)*(1 if layer%2==0 else -1)
  for quadrant in 3:
   var angle: float = start+TAU*quadrant/3
   game.draw_arc(point,radius,angle,angle+1.16,12,Color(.23,.7,1,.28+t*.48),1.4+layer*.4,true)
 for i in 6:
  var phase: float = fposmod(t*1.7+i/6.0,1.0)
  var angle: float = TAU*i/6+visual_clock*.4
  var a: Vector2 = point+Vector2.from_angle(angle)*(11+37*(1-phase))
  var b: Vector2 = point+Vector2.from_angle(angle)*(7+23*(1-phase))
  game.draw_line(a,b,Color(.5,.87,1,phase*.8),1.2,true)
 game.draw_circle(point,9*t,Color(.35,.85,1,t*.36))
 game.draw_circle(point,3.5*t,Color(1,1,1,t))

func _draw_rail(game, shot: Dictionary) -> void:
 var direction: int = 1 if shot.vx>0 else -1
 var center: Vector2 = shot.pos
 if not game.effects_enabled:
  game.draw_line(center-Vector2(direction*19,0),center+Vector2(direction*22,0),CYAN,3,true)
  return
 var record: Dictionary = rails.get(int(shot.get("serial",-1)),{})
 var traveled: float = absf(center.x-float(record.get("muzzle",center-Vector2(direction*110,0)).x))
 var length: float = minf(156, 30+traveled)
 var collapse: float = clampf(float(shot.get("life",.85))/.14,0,1)
 var tail: Vector2 = center-Vector2(direction*length*(.45+.55*collapse),0)
 var tip: Vector2 = center+Vector2(direction*31,0)
 # Head remains within the real 36px hit radius; the tail is decorative wake.
 for item in [[32.0,.07],[20.0,.15],[10.0,.38],[4.5,.95]]:
  game.draw_line(tail,tip,Color(.22,.73,1,item[1]*(.4+.6*collapse)),item[0]*(.45+.55*collapse),true)
 game.draw_line(tail+Vector2(direction*17,0),tip,WHITE,2.0,true)
 for side in [-1,1]:
  var edge := PackedVector2Array([tail+Vector2(direction*13,side*3),center+Vector2(-direction*27,side*17),tip])
  game.draw_polyline(edge,Color(.36,.84,1,.64),1.5,true)
  var filament := PackedVector2Array()
  for i in 12:
   var x: float = float(i)/11
   filament.append(tail.lerp(center,x)+Vector2(0,sin(x*TAU*1.7-visual_clock*31+side)*7*(1-x*.5)))
  game.draw_polyline(filament,Color(.65,.94,1,.38),1.0,true)
 var angle: float = 0 if direction>0 else PI
 game.draw_arc(center,23,angle-1.18,angle+1.18,18,Color(.27,.7,1,.6),2,true)
 game.draw_circle(tip,3,WHITE)

func _draw_flash(game, effect: Dictionary) -> void:
 var fade: float = effect.life/effect.max_life
 var progress: float = 1.0-fade
 var p: Vector2 = effect.pos
 var fire: bool = effect.role == "feiren"
 var color: Color = GOLD if fire else CYAN
 var radius: float = (11+progress*35)*(1 if effect.contact else .66)
 if fire:
  _flame(game,p+Vector2(effect.facing*24,0),effect.facing,95+progress*48,65+progress*28,int(progress*5)%6,fade*.83)
 # Contact spokes are clipped against the same solids used by gameplay.
 for i in 7:
  var angle: float = TAU*i/7+.26
  var a: Vector2 = p+Vector2.from_angle(angle)*radius*.3
  var b: Vector2 = p+Vector2.from_angle(angle)*radius*(1.1 if i%2==0 else .7)
  if _inside_solid(a) or _inside_solid(b): continue
  game.draw_line(a,b,Color(color,fade*.84),2.4*fade+.7,true)
 if not _inside_solid(p):
  game.draw_circle(p,10*fade,Color(color,fade*.22))
  game.draw_line(p-Vector2(0,radius*.85),p+Vector2(0,radius*.85),Color(1,1,.92,fade*.9),2*fade+1,true)
  game.draw_circle(p,3*fade,Color(1,1,1,fade))
