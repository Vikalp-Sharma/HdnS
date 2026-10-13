## Main game orchestrator.
## Creates the map, agents, camera, HUD, lighting, and two agent monitor windows.
extends Node3D

# ── References ──
var map_generator: MapGenerator
var hider_agent: AIAgent
var seeker_agent: AIAgent
var turn_manager: TurnManager
var free_camera: FreeCamera
var hud: GameHUD
var _world_env: WorldEnvironment

# Agent monitor windows
var hider_window: AgentWindow
var seeker_window: AgentWindow

# ── Config ──
var map_width: int = 40
var map_height: int = 40
var _cached_q_grid: Array = []
var _last_heatmap_time: float = 0.0
var _r_press_count: int = 0
var _last_r_press_time: float = 0.0
var _reset_dialog: ConfirmationDialog
var _is_restarting: bool = false


func _ready() -> void:
	# Ensure multi-window OS desktop popouts
	get_viewport().gui_embed_subwindows = false

	# Build the game world
	_setup_environment()
	_setup_lighting()
	_setup_map()
	# One frame for physics server to register wall collision shapes
	await get_tree().process_frame
	_setup_agents()
	_setup_camera()
	_setup_hud()
	_setup_turn_manager()
	_setup_agent_windows()
	_setup_reset_dialog()

	# Start the first episode
	turn_manager.start_episode()

	print("═══════════════════════════════════════════")
	print("    HIDE & SEEK RL SIMULATION")
	print("═══════════════════════════════════════════")
	print("Hider NN params: ", hider_agent.brain.policy_net.get_param_count())
	print("Seeker NN params: ", seeker_agent.brain.policy_net.get_param_count())
	print("")
	print("Controls:")
	print("  WASD         : Fly camera")
	print("  Right-Click  : Hold to look around")
	print("  Scroll       : Camera speed")
	print("  C            : Toggle mouse lock")
	print("  ESC          : Release mouse cursor")
	print("  TAB          : Toggle HUD")
	print("  1/2/3/4      : Sim speed (1x/5x/20x/100x)")
	print("  R            : New map (press 5x to delete RL data)")
	print("  P            : Pause/Resume")
	print("═══════════════════════════════════════════")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			var now := Time.get_ticks_msec() / 1000.0
			# If more than 4 seconds elapsed since last R press, reset count
			if now - _last_r_press_time > 4.0:
				_r_press_count = 0
			_last_r_press_time = now
			_r_press_count += 1

			if _r_press_count >= 5:
				_r_press_count = 0
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				if _reset_dialog:
					_reset_dialog.popup_centered()
			else:
				if hud:
					hud.show_toast("Map re-rolled (%d/5 'R' presses to reset RL)" % _r_press_count)
				_regenerate_map()


func _setup_reset_dialog() -> void:
	_reset_dialog = ConfirmationDialog.new()
	_reset_dialog.name = "ResetRLDialog"
	_reset_dialog.title = "Delete RL Data?"
	_reset_dialog.dialog_text = "You pressed 'R' 5 times in a row.\n\nDo you want to DELETE ALL Q-tables and neural network models for both Hider and Seeker?\n\nThis will reset training back to Episode 0."
	_reset_dialog.ok_button_text = "Yes, Delete Q-Tables"
	_reset_dialog.cancel_button_text = "Cancel"
	_reset_dialog.confirmed.connect(_on_reset_dialog_confirmed)
	_reset_dialog.canceled.connect(_on_reset_dialog_canceled)
	add_child(_reset_dialog)


func _on_reset_dialog_confirmed() -> void:
	print("═══════════════════════════════════════════")
	print("  DELETING ALL Q-TABLES & RL DATA")
	print("═══════════════════════════════════════════")
	if turn_manager:
		turn_manager.reset_all_rl()
	_cached_q_grid.clear()
	_regenerate_map()
	if hud:
		hud.show_toast("RL Data Wiped! Starting fresh from Episode 0.")


func _on_reset_dialog_canceled() -> void:
	if hud:
		hud.show_toast("RL reset canceled. Kept existing models.")


func _setup_environment() -> void:
	# World environment with sky and ambient light
	_world_env = WorldEnvironment.new()
	_world_env.name = "WorldEnvironment"

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.05, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.09, 0.12, 0.18)
	env.ambient_light_energy = 0.35

	# Atmospheric depth fog
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.07, 0.12)
	env.fog_density = 0.008
	env.fog_aerial_perspective = 0.4

	# ACES Film Tonemapper
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.15
	env.tonemap_white = 6.0

	# High-tech bloom glow for visors, lasers & light seams
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.25
	env.glow_hdr_threshold = 0.85
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	# Rich contact shadows (SSAO)
	env.ssao_enabled = true
	env.ssao_radius = 2.2
	env.ssao_intensity = 2.8
	env.ssao_power = 1.5
	env.ssao_detail = 0.8

	# Screen-Space Reflections (SSR) for polished facility floor
	env.ssr_enabled = true
	env.ssr_max_steps = 64
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 1.0
	env.ssr_depth_tolerance = 0.25

	_world_env.environment = env
	add_child(_world_env)


func _setup_lighting() -> void:
	# Main directional key light (cool industrial lunar key)
	var dir_light := DirectionalLight3D.new()
	dir_light.name = "SunLight"
	dir_light.light_color = Color(0.85, 0.90, 1.0)
	dir_light.light_energy = 1.0
	dir_light.shadow_enabled = true
	dir_light.shadow_bias = 0.02
	dir_light.shadow_opacity = 0.85
	dir_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	dir_light.rotation = Vector3(deg_to_rad(-52), deg_to_rad(35), 0)
	dir_light.position = Vector3(0, 22, 0)
	add_child(dir_light)

	# Atmospheric rim/fill light (deep cyan-indigo)
	var fill_light := DirectionalLight3D.new()
	fill_light.name = "FillLight"
	fill_light.light_color = Color(0.25, 0.35, 0.55)
	fill_light.light_energy = 0.45
	fill_light.shadow_enabled = false
	fill_light.rotation = Vector3(deg_to_rad(-25), deg_to_rad(-135), 0)
	add_child(fill_light)

	# Overhead facility ambient fill (centered over map)
	var center_x := map_width * MapGenerator.TILE_SIZE * 0.5
	var center_z := map_height * MapGenerator.TILE_SIZE * 0.5

	var overhead := OmniLight3D.new()
	overhead.name = "OverheadLight"
	overhead.light_color = Color(0.70, 0.82, 1.0)
	overhead.light_energy = 0.45
	overhead.omni_range = 65.0
	overhead.omni_attenuation = 1.2
	overhead.shadow_enabled = false
	overhead.position = Vector3(center_x, 20, center_z)
	add_child(overhead)


func _setup_map() -> void:
	map_generator = MapGenerator.new()
	map_generator.name = "MapGenerator"
	add_child(map_generator)
	map_generator.generate(map_width, map_height)


func _setup_agents() -> void:
	var spawns: Array = map_generator.get_spawn_points()

	# Agent 1 (initially Hider, blue)
	hider_agent = AIAgent.new()
	hider_agent.name = "Agent1"
	add_child(hider_agent)
	hider_agent.setup(AIAgent.AgentType.HIDER,
					  spawns[0] if spawns.size() > 0 else Vector2i(2, 2),
					  map_generator,
					  1,
					  "Agent 1 (Alpha)")

	# Agent 2 (initially Seeker, red)
	seeker_agent = AIAgent.new()
	seeker_agent.name = "Agent2"
	add_child(seeker_agent)
	seeker_agent.setup(AIAgent.AgentType.SEEKER,
					  spawns[1] if spawns.size() > 1 else Vector2i(map_width - 3, map_height - 3),
					  map_generator,
					  2,
					  "Agent 2 (Omega)")


func _setup_camera() -> void:
	free_camera = FreeCamera.new()
	free_camera.name = "SpectatorCamera"

	# Position camera overlooking the map
	var center_x := map_width * MapGenerator.TILE_SIZE * 0.5
	var center_z := map_height * MapGenerator.TILE_SIZE * 0.5
	var overview_pos := Vector3(center_x, 32.0, center_z + 28.0)
	free_camera.position = overview_pos
	free_camera.rotation = Vector3(deg_to_rad(-45), 0, 0)
	free_camera.setup_targets(hider_agent, seeker_agent, overview_pos)

	free_camera.current = true
	add_child(free_camera)


func _setup_hud() -> void:
	hud = GameHUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.set_wall_grid(map_generator.get_wall_grid(), map_width, map_height)


func _setup_turn_manager() -> void:
	turn_manager = TurnManager.new()
	turn_manager.name = "TurnManager"
	add_child(turn_manager)
	turn_manager.setup(hider_agent, seeker_agent, map_generator)

	# Connect signals
	turn_manager.stats_updated.connect(_on_stats_updated)
	turn_manager.episode_ended.connect(_on_episode_ended)


func _setup_agent_windows() -> void:
	# Get main window position to place monitor windows beside it
	var main_pos: Vector2i = DisplayServer.window_get_position()
	var main_size: Vector2i = DisplayServer.window_get_size()

	# ── Agent 1 Monitor Window (left of main) ──
	hider_window = AgentWindow.new()
	hider_window.name = "Agent1Window"
	add_child(hider_window)
	var hider_win_pos := Vector2i(maxi(main_pos.x - 470, 10), main_pos.y)
	hider_window.setup(hider_agent, "◆ AGENT 1 [HIDER] ◆", hider_win_pos, get_world_3d())

	# ── Agent 2 Monitor Window (right of main) ──
	seeker_window = AgentWindow.new()
	seeker_window.name = "Agent2Window"
	add_child(seeker_window)
	var seeker_win_pos := Vector2i(main_pos.x + main_size.x + 10, main_pos.y)
	seeker_window.setup(seeker_agent, "◆ AGENT 2 [SEEKER] ◆", seeker_win_pos, get_world_3d())


func _on_stats_updated(data: Dictionary) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	# Recalculate heatmap ~4 times per second with stepped sampling (step 2) for ultra-fast 60 FPS
	if _cached_q_grid.is_empty() or now - _last_heatmap_time >= 0.25:
		_last_heatmap_time = now
		_cached_q_grid.clear()
		# Pre-allocate 2D array
		for x in range(map_width):
			var col: Array = []
			col.resize(map_height)
			col.fill(0.0)
			_cached_q_grid.append(col)

		var current_seeker: AIAgent = turn_manager.seeker if turn_manager else seeker_agent
		for x in range(0, map_width, 2):
			for y in range(0, map_height, 2):
				var sample_val := 0.0
				if map_generator.is_walkable(Vector2i(x, y)):
					var state: Array = _make_heatmap_state(Vector2i(x, y))
					var q_vals: Array = current_seeker.brain.get_q_values(state)
					var max_q: float = q_vals[0]
					for qv in q_vals:
						max_q = maxf(max_q, qv)
					sample_val = clampf(max_q / 20.0, -1.0, 1.0)

				# Fill 2x2 block
				_cached_q_grid[x][y] = sample_val
				if y + 1 < map_height:
					_cached_q_grid[x][y + 1] = sample_val
				if x + 1 < map_width:
					_cached_q_grid[x + 1][y] = sample_val
					if y + 1 < map_height:
						_cached_q_grid[x + 1][y + 1] = sample_val

	data["q_value_grid"] = _cached_q_grid
	hud.update_stats(data)

	# Update agent monitor windows with thought data
	if hider_window and hider_agent:
		hider_window.set_thought_data(hider_agent.get_thoughts())
	if seeker_window and seeker_agent:
		seeker_window.set_thought_data(seeker_agent.get_thoughts())


func _on_episode_ended(winner: String, episode: int) -> void:
	if _is_restarting:
		return
	_is_restarting = true

	# Immediately pause turn manager so no further turn steps run during restart delay
	if turn_manager:
		turn_manager.paused = true

	var h_agent: AIAgent = turn_manager.hider
	var s_agent: AIAgent = turn_manager.seeker
	var winner_agent: AIAgent = h_agent if winner == "Hider" else s_agent

	print("═══════════════════════════════════════════")
	print("  ROUND OVER: %s [%s] WINS (EP %d)!" % [winner_agent.agent_name, winner, episode])
	print("  %s score=%d (W:%d L:%d)" % [turn_manager.agent1.agent_name, turn_manager.agent1.score, turn_manager.agent1.match_wins, turn_manager.agent1.match_losses])
	print("  %s score=%d (W:%d L:%d)" % [turn_manager.agent2.agent_name, turn_manager.agent2.score, turn_manager.agent2.match_wins, turn_manager.agent2.match_losses])
	print("═══════════════════════════════════════════")

	# Show round result on HUD
	if hud:
		hud.show_round_winner(winner, winner_agent.agent_name)

	# Update thoughts on monitor windows immediately
	if hider_window and hider_agent:
		hider_window.set_thought_data(hider_agent.get_thoughts())
	if seeker_window and seeker_agent:
		seeker_window.set_thought_data(seeker_agent.get_thoughts())

	# When round ends: restart, swap roles, and randomize map WITHOUT resetting Q-tables
	call_deferred("_restart_with_new_map")


func _restart_with_new_map() -> void:
	# Give spectator 1.5s to see the catch at normal speed, or 0.1s at high speed
	if turn_manager.sim_speed < 20:
		await get_tree().create_timer(1.5).timeout
	else:
		await get_tree().create_timer(0.08).timeout

	# 1. SWAP ROLES! Hider becomes Seeker, Seeker becomes Hider!
	turn_manager.swap_roles()

	# 2. Update agent monitor windows to reflect swapped roles, titles, and 3D showcase models
	if hider_window:
		hider_window.update_role_appearance()
	if seeker_window:
		seeker_window.update_role_appearance()

	# 3. Regenerate map synchronously
	map_generator.generate(map_width, map_height)
	await get_tree().process_frame

	# 4. Reposition agents at new spawns (preserves all learned neural weights & replay buffers)
	var spawns: Array = map_generator.get_spawn_points()
	var spawn_h: Vector2i = spawns[0] if spawns.size() > 0 else Vector2i(2, 2)
	var spawn_s: Vector2i = spawns[1] if spawns.size() > 1 else Vector2i(map_width - 3, map_height - 3)

	turn_manager.hider.reposition_on_new_map(spawn_h, map_generator)
	turn_manager.seeker.reposition_on_new_map(spawn_s, map_generator)

	hud.set_wall_grid(map_generator.get_wall_grid(), map_width, map_height)
	_cached_q_grid.clear()

	turn_manager.paused = false
	turn_manager.start_episode()
	_is_restarting = false
	print("── New round started: Roles swapped on randomized map (Q-tables preserved) ──")


func _regenerate_map() -> void:
	# Pause, regenerate, restart
	turn_manager.paused = true

	# Regenerate map (synchronous now)
	map_generator.generate(map_width, map_height)
	await get_tree().process_frame  # Let physics register new collisions

	# Get new spawn points
	var spawns: Array = map_generator.get_spawn_points()
	var spawn_h: Vector2i = spawns[0] if spawns.size() > 0 else Vector2i(2, 2)
	var spawn_s: Vector2i = spawns[1] if spawns.size() > 1 else Vector2i(map_width - 3, map_height - 3)

	# Reposition existing agents without wiping neural networks or breaking monitor viewports
	turn_manager.hider.reposition_on_new_map(spawn_h, map_generator)
	turn_manager.seeker.reposition_on_new_map(spawn_s, map_generator)

	hud.set_wall_grid(map_generator.get_wall_grid(), map_width, map_height)
	_cached_q_grid.clear()

	turn_manager.paused = false
	turn_manager.start_episode()
	print("── Map re-rolled (RL networks preserved) ──")


## Build a simplified state for Q-value heatmap at a given grid position.
func _make_heatmap_state(pos: Vector2i) -> Array:
	var state: Array = []
	var gw := float(map_width)
	var gh := float(map_height)

	# Position
	state.append(float(pos.x) / gw)
	state.append(float(pos.y) / gh)

	# Relative to active hider
	var current_hider: AIAgent = turn_manager.hider if turn_manager else hider_agent
	state.append(float(current_hider.grid_pos.x - pos.x) / gw)
	state.append(float(current_hider.grid_pos.y - pos.y) / gh)

	# Fake vision data (all clear, no walls visible)
	for _i in range(AIAgent.VISION_RAYS):
		state.append(1.0)  # max distance
		state.append(0.0)  # nothing

	# Adjacent walls
	state.append(0.0 if map_generator.is_walkable(pos + Vector2i(0, -1)) else 1.0)
	state.append(0.0 if map_generator.is_walkable(pos + Vector2i(0, 1)) else 1.0)
	state.append(0.0 if map_generator.is_walkable(pos + Vector2i(1, 0)) else 1.0)
	state.append(0.0 if map_generator.is_walkable(pos + Vector2i(-1, 0)) else 1.0)

	# Turns / time remaining
	state.append(0.5)

	# 40th feature: Role (Seeker evaluating heatmap)
	state.append(0.0)

	return state
