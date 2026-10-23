extends SceneTree
const MobileAdapter = preload("res://scripts/mobile_game.gd")
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(id: String, passed: bool, detail: String = "") -> void:
 print(("TOUCH_STARTUP_PASS " if passed else "TOUCH_STARTUP_FAIL ") + id + (" | " + detail if not detail.is_empty() else ""))
 if not passed: failures.append(id)
func run() -> void:
 check("ios_platform_enables_touch", MobileAdapter.is_touch_platform("iOS"))
 check("android_platform_enables_touch", MobileAdapter.is_touch_platform("Android"))
 check("desktop_platform_does_not_force_touch", not MobileAdapter.is_touch_platform("macOS"))
 var game = load("res://main.tscn").instantiate()
 root.add_child(game)
 await process_frame
 check("touch_override_enables_ui", game.touch_ui.enabled and game.touch_ui.visible, "platform=" + OS.get_name())
 game.touch_ui.set_enabled(false)
 check("ui_can_be_hidden", not game.touch_ui.enabled and not game.touch_ui.visible)
 game.touch_ui.set_enabled(true)
 check("menu_controls_populated", game.touch_ui.buttons.has("stage1") and game.touch_ui.buttons.has("stage3"), str(game.touch_ui.buttons.keys()))
 game.mode = "play"
 game.paused = false
 game.player.hp = 100
 game.touch_ui.refresh_layout()
 check("play_buttons_populated", game.touch_ui.buttons.has("jump") and game.touch_ui.buttons.has("light"))
 var stick_down := InputEventScreenTouch.new()
 stick_down.index = 93
 stick_down.position = game.touch_ui.joystick_center + Vector2(game.touch_ui.joystick_radius, 0)
 stick_down.pressed = true
 game.touch_ui.ingest(stick_down)
 check("joystick_input_moves", game.touch_ui.owners.has("stick") and game.touch_ui.axis > 0.9, str(game.touch_ui.axis))
 var stick_up := InputEventScreenTouch.new()
 stick_up.index = 93
 stick_up.position = Vector2.ZERO
 stick_up.pressed = false
 game.touch_ui.ingest(stick_up)
 var jump_down := InputEventScreenTouch.new()
 jump_down.index = 94
 jump_down.position = game.touch_ui.buttons.jump.center
 jump_down.pressed = true
 game.touch_ui.ingest(jump_down)
 check("jump_button_reaches_player", game.player.jump_buffer > 0.0, str(game.player.jump_buffer))
 var jump_up := InputEventScreenTouch.new()
 jump_up.index = 94
 jump_up.position = Vector2.ZERO
 jump_up.pressed = false
 game.touch_ui.ingest(jump_up)
 check("touch_release_clears_owners", game.touch_ui.fingers.is_empty() and game.touch_ui.owners.is_empty())
 game.queue_free()
 await process_frame
 print("TOUCH_STARTUP_RESULT %d checks %d failures" % [10, failures.size()])
 quit(0 if failures.is_empty() else 1)
