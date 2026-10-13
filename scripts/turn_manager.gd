## Turn-based game manager.
## Alternates between Hider and Seeker, handles episodes, scoring, and speed.
class_name TurnManager
extends Node

const TacticalAdvisor = preload("res://scripts/tactical_advisor.gd")

# ── Signals ──
signal turn_completed(agent_name: String, action: int, reward: float)
signal episode_ended(winner: String, episode: int)
signal stats_updated(data: Dictionary)

# ── Configuration ──
const EPISODE_TIME_LIMIT: float = 180.0  # 3 minutes countdown
const BASE_TURN_TIME: float = 0.15       # Seconds per step at 1x speed

# ── State ──
var hider: AIAgent
var seeker: AIAgent
var agent1: AIAgent
var agent2: AIAgent
var map_gen: MapGenerator

var current_episode: int = 0
var current_turn: int = 0
var time_left: float = EPISODE_TIME_LIMIT
var _turn_accumulator: float = 0.0
var is_hider_turn: bool = true
var episode_active: bool = false
var sim_speed: int = 1        # 1, 5, 20, or 100
var hider_wins: int = 0
var seeker_wins: int = 0
var paused: bool = false
var seeker_patrol_idx: int = 0

# Track last known positions for state construction
var _hider_last_seen_pos: Vector2i = Vector2i.ZERO
var _seeker_last_seen_pos: Vector2i = Vector2i.ZERO

# Memory of last transition for terminal rewards in 2-player RL
var _hider_last_state: Array = []
var _hider_last_action: int = 0
var _hider_last_next_state: Array = []

var _seeker_last_state: Array = []
var _seeker_last_action: int = 0
var _seeker_last_next_state: Array = []


func setup(a1: AIAgent, a2: AIAgent, m: MapGenerator) -> void:
	agent1 = a1
	agent2 = a2
	map_gen = m
	hider = a1 if a1.agent_type == AIAgent.AgentType.HIDER else a2
	seeker = a2 if a1.agent_type == AIAgent.AgentType.HIDER else a1


## Swaps roles between Agent 1 and Agent 2.
func swap_roles() -> void:
	if agent1 == null or agent2 == null:
		return

	if agent1.agent_type == AIAgent.AgentType.HIDER:
		agent1.set_role(AIAgent.AgentType.SEEKER)
		agent2.set_role(AIAgent.AgentType.HIDER)
		hider = agent2
		seeker = agent1
	else:
		agent1.set_role(AIAgent.AgentType.HIDER)
		agent2.set_role(AIAgent.AgentType.SEEKER)
		hider = agent1
		seeker = agent2

	print("═══════════════════════════════════════════")
	print("  ROLES SWAPPED!")
	print("  HIDER  : %s (Blue)" % hider.agent_name)
	print("  SEEKER : %s (Red)" % seeker.agent_name)
	print("═══════════════════════════════════════════")


func start_episode() -> void:
	current_turn = 0
	time_left = EPISODE_TIME_LIMIT
	_turn_accumulator = 0.0
	is_hider_turn = true
	episode_active = true
	current_episode += 1
	seeker_patrol_idx = 0

	# Reset agent positions to spawn points
	var spawns: Array = map_gen.get_spawn_points()
	if spawns.size() >= 2:
		hider.grid_pos = spawns[0]
		hider._target_world_pos = map_gen.grid_to_world(spawns[0])
		hider._target_world_pos.y = 1.0
		hider.position = hider._target_world_pos
		hider.facing_dir = Vector2i(0, 1)

		seeker.grid_pos = spawns[1]
		seeker._target_world_pos = map_gen.grid_to_world(spawns[1])
		seeker._target_world_pos.y = 1.0
		seeker.position = seeker._target_world_pos
		seeker.facing_dir = Vector2i(0, -1)

	_hider_last_seen_pos = hider.grid_pos
	_seeker_last_seen_pos = seeker.grid_pos

	# Clear previous transitions for new episode
	_hider_last_state.clear()
	_seeker_last_state.clear()

	# Cast initial vision for both units
	hider.cast_vision(seeker.get_sim_world_pos())
	seeker.cast_vision(hider.get_sim_world_pos())


func _process(delta: float) -> void:
	if not episode_active or paused:
		return

	# 1. Decrement 3-minute round countdown scaled by simulation speed
	time_left = maxf(0.0, time_left - delta * float(sim_speed))

	# 2. Check 3-minute timeout: if time expires before seeker catches hider, Hider wins!
	if time_left <= 0.0 and episode_active:
		_handle_timeout()
		_emit_stats()
		return

	# 3. Accumulate simulation time for discrete turn stepping
	_turn_accumulator += delta * float(sim_speed)
	if _turn_accumulator > BASE_TURN_TIME * 10:
		_turn_accumulator = BASE_TURN_TIME * 10

	var steps_done: int = 0
	var max_steps: int = maxi(sim_speed * 2, 20)
	var stepped_agents: Dictionary = {}
	while _turn_accumulator >= BASE_TURN_TIME and steps_done < max_steps and episode_active:
		_turn_accumulator -= BASE_TURN_TIME
		var active: AIAgent = _process_single_turn()
		if active:
			stepped_agents[active] = true
		steps_done += 1

	# At high simulation speeds, throttle training to 1 batch per active agent per frame
	if sim_speed > 2:
		for ag in stepped_agents.keys():
			if ag and ag.brain:
				ag.brain.train_step()

	_emit_stats()


func _handle_timeout() -> void:
	var winner: String = "Hider"
	hider_wins += 1

	# Seeker was unable to find Hider: Seeker gets a loss, Hider gets points & win!
	if hider:
		hider.score += 100
		hider.match_wins += 1
	if seeker:
		seeker.match_losses += 1

	# Symmetric terminal experiences for surviving the full 3 minutes
	if _hider_last_state.size() > 0:
		hider.brain.store_experience(_hider_last_state, _hider_last_action, 50.0, _hider_last_next_state, true)
		hider.brain.train_step()

	if _seeker_last_state.size() > 0:
		seeker.brain.store_experience(_seeker_last_state, _seeker_last_action, -50.0, _seeker_last_next_state, true)
		seeker.brain.train_step()

	hider.brain.end_episode()
	seeker.brain.end_episode()
	episode_active = false
	_emit_stats()
	print("═══════════════════════════════════════════")
	print("  ⏳ ROUND TIMEOUT (3 MINUTES EXPIRED)!")
	print("  WINNER: %s (+100 PTS)" % hider.agent_name)
	print("  LOSER : %s (LOSS)" % seeker.agent_name)
	print("═══════════════════════════════════════════")
	emit_signal("episode_ended", winner, current_episode)


## Returns true if the Seeker has successfully caught/tagged the Hider.
## Conditions:
## 1. Exact same tile (distance 0)
## 2. Adjacent walkable tile (path distance <= 1 tile, representing tag reach without wall occlusion)
## 3. Physical 3D distance <= 2.4 meters with unobstructed Line-of-Sight
func is_hider_caught() -> bool:
	if hider == null or seeker == null:
		return false
	# 1. Exact same tile
	if hider.grid_pos == seeker.grid_pos:
		return true
	# 2. Adjacent tile along open path (tag range)
	if map_gen != null:
		var d: int = map_gen.get_path_distance(seeker.grid_pos, hider.grid_pos)
		if d >= 0 and d <= 1:
			return true
	# 3. Physical 3D world proximity with clear line-of-sight
	var h_pos: Vector3 = hider.get_sim_world_pos()
	var s_pos: Vector3 = seeker.get_sim_world_pos()
	if h_pos.distance_to(s_pos) <= 2.4:
		var world := get_tree().root.get_world_3d() if is_inside_tree() else null
		var space_state := world.direct_space_state if world != null else null
		if space_state == null or TacticalAdvisor.has_line_of_sight(s_pos + Vector3(0, 0.7, 0), h_pos + Vector3(0, 0.7, 0), space_state):
			return true
	return false


func _handle_catch(active_agent: AIAgent) -> void:
	var winner: String = "Seeker"
	seeker_wins += 1

	if seeker:
		seeker.score += 100
		seeker.match_wins += 1
	if hider:
		hider.match_losses += 1

	# Terminal transitions
	if active_agent == seeker:
		if _seeker_last_state.size() > 0:
			seeker.brain.store_experience(_seeker_last_state, _seeker_last_action, 100.0, [], true)
			seeker.brain.train_step()
		if _hider_last_state.size() > 0:
			hider.brain.store_experience(_hider_last_state, _hider_last_action, -100.0, [], true)
			hider.brain.train_step()
	else:
		if _hider_last_state.size() > 0:
			hider.brain.store_experience(_hider_last_state, _hider_last_action, -100.0, [], true)
			hider.brain.train_step()
		if _seeker_last_state.size() > 0:
			seeker.brain.store_experience(_seeker_last_state, _seeker_last_action, 100.0, [], true)
			seeker.brain.train_step()

	hider.brain.end_episode()
	seeker.brain.end_episode()
	episode_active = false
	_emit_stats()
	print("═══════════════════════════════════════════")
	print("  🎯 SEEKER CAUGHT HIDER!")
	print("  WINNER: %s (+100 PTS) [W:%d | L:%d]" % [seeker.agent_name, seeker.match_wins, seeker.match_losses])
	print("  LOSER : %s (LOSS)     [W:%d | L:%d]" % [hider.agent_name, hider.match_wins, hider.match_losses])
	print("═══════════════════════════════════════════")
	emit_signal("episode_ended", winner, current_episode)


func _process_single_turn() -> AIAgent:
	var active_agent: AIAgent
	var opponent: AIAgent

	if is_hider_turn:
		active_agent = hider
		opponent = seeker
	else:
		active_agent = seeker
		opponent = hider

	# 0. Check pre-move catch condition (e.g. if agents are already within tag range)
	if is_hider_caught():
		_handle_catch(active_agent)
		return active_agent

	# 1. Ensure vision is updated before state sampling using true simulation positions
	hider.cast_vision(seeker.get_sim_world_pos())
	seeker.cast_vision(hider.get_sim_world_pos())

	# 2. Get current state based on vision
	var opponent_pos: Vector2i
	if active_agent == hider:
		opponent_pos = _seeker_last_seen_pos if not hider.can_see_opponent() else seeker.grid_pos
		if hider.can_see_opponent():
			_seeker_last_seen_pos = seeker.grid_pos
	else:
		opponent_pos = _hider_last_seen_pos if not seeker.can_see_opponent() else hider.grid_pos
		if seeker.can_see_opponent():
			_hider_last_seen_pos = hider.grid_pos

	var time_ratio: float = clampf(time_left / EPISODE_TIME_LIMIT, 0.0, 1.0)
	var state: Array = active_agent.get_state(opponent_pos, time_ratio)

	# 3. Retrieve Domain Knowledge / Common Rules teacher recommendation
	var teacher_action: int = -1
	if active_agent == seeker:
		var advice: Dictionary = TacticalAdvisor.get_seeker_advice(
			seeker.grid_pos,
			hider.grid_pos,
			seeker.can_see_opponent(),
			_hider_last_seen_pos,
			map_gen,
			seeker_patrol_idx
		)
		seeker_patrol_idx = advice.get("patrol_idx", seeker_patrol_idx)
		active_agent.tactical_intent = advice.get("intent", "HUNTING")
		teacher_action = advice.get("action", -1)
	else:
		var world := active_agent.get_world_3d() if active_agent.is_inside_tree() else null
		var space_state: PhysicsDirectSpaceState3D = world.direct_space_state if world != null else null
		var advice: Dictionary = TacticalAdvisor.get_hider_advice(
			hider.grid_pos,
			seeker.grid_pos,
			hider.can_see_opponent(),
			map_gen,
			space_state
		)
		active_agent.tactical_intent = advice.get("intent", "CONCEALING")
		teacher_action = advice.get("action", -1)

	# 4. Select action via RL brain with valid action masking & teacher guidance
	var valid_actions: Array = active_agent.get_valid_actions()
	var action: int = active_agent.brain.select_action(state, valid_actions, teacher_action)
	active_agent.last_q_values = active_agent.brain.last_q_values.duplicate()

	# 5. Execute action
	var move_result: Dictionary = active_agent.perform_action(action)

	# 6. Post-move: update vision immediately from new tile position
	hider.cast_vision(seeker.get_sim_world_pos())
	seeker.cast_vision(hider.get_sim_world_pos())

	if hider.can_see_opponent():
		_seeker_last_seen_pos = seeker.grid_pos
	if seeker.can_see_opponent():
		_hider_last_seen_pos = hider.grid_pos

	# 7. Calculate turn reward
	var reward: float = _calculate_reward(active_agent, opponent, move_result)

	# 8. Get next state after movement & fresh vision
	var next_opponent_pos: Vector2i = _seeker_last_seen_pos if active_agent == hider else _hider_last_seen_pos
	var next_time_ratio: float = clampf(time_left / EPISODE_TIME_LIMIT, 0.0, 1.0)
	var next_state: Array = active_agent.get_state(next_opponent_pos, next_time_ratio)

	# 9. Check catch condition post-movement
	var done: bool = is_hider_caught()
	var winner: String = ""

	if done:
		winner = "Seeker"
		seeker_wins += 1

		# Seeker caught Hider: Seeker gets points & win, Hider gets loss!
		if seeker:
			seeker.score += 100
			seeker.match_wins += 1
		if hider:
			hider.match_losses += 1

		if active_agent == seeker:
			reward += 100.0
		else:
			reward -= 100.0

	# 10. Store experience and train active agent
	active_agent.brain.store_experience(state, action, reward, next_state, done)
	if sim_speed <= 2:
		active_agent.brain.train_step()

	# Record last transitions
	if active_agent == hider:
		_hider_last_state = state.duplicate()
		_hider_last_action = action
		_hider_last_next_state = next_state.duplicate()
	else:
		_seeker_last_state = state.duplicate()
		_seeker_last_action = action
		_seeker_last_next_state = next_state.duplicate()

	# 11. Symmetric terminal transition: ensure inactive opponent learns end-game outcome
	if done:
		if active_agent == seeker and _hider_last_state.size() > 0:
			hider.brain.store_experience(_hider_last_state, _hider_last_action, -100.0, _hider_last_next_state, true)
			hider.brain.train_step()
		elif active_agent == hider and _seeker_last_state.size() > 0:
			seeker.brain.store_experience(_seeker_last_state, _seeker_last_action, 100.0, _seeker_last_next_state, true)
			seeker.brain.train_step()

	emit_signal("turn_completed", active_agent.get_type_name(), action, reward)

	# 12. Advance turn counter
	if not is_hider_turn:
		current_turn += 1  # One full round = both agents have acted
	is_hider_turn = !is_hider_turn

	# 13. Handle episode end
	if done:
		hider.brain.end_episode()
		seeker.brain.end_episode()
		episode_active = false
		_emit_stats()
		print("═══════════════════════════════════════════")
		print("  🎯 SEEKER CAUGHT HIDER!")
		print("  WINNER: %s (+100 PTS) [W:%d | L:%d]" % [seeker.agent_name, seeker.match_wins, seeker.match_losses])
		print("  LOSER : %s (LOSS)     [W:%d | L:%d]" % [hider.agent_name, hider.match_wins, hider.match_losses])
		print("═══════════════════════════════════════════")
		emit_signal("episode_ended", winner, current_episode)

	return active_agent



func _calculate_reward(agent: AIAgent, opponent: AIAgent, move_result: Dictionary) -> float:
	var reward: float = 0.0
	var path_d: int = map_gen.get_path_distance(agent.grid_pos, opponent.grid_pos) if map_gen else -1

	if agent.agent_type == AIAgent.AgentType.HIDER:
		# Hider rewards
		reward += 1.5                                  # Survived this turn
		if not opponent.can_see_opponent():
			reward += 4.0                              # Concealed / not seen by seeker
		else:
			reward -= 6.0                              # Spotted by seeker!
		if move_result["hit_wall"]:
			reward -= 5.0                              # Collision penalty
		# Distance reward: farther along walkable path is better
		if path_d >= 0:
			reward += clampf(float(path_d) * 0.4, 0.0, 6.0)
		else:
			var euclid := Vector2(agent.grid_pos).distance_to(Vector2(opponent.grid_pos))
			reward += clampf(euclid * 0.3, 0.0, 5.0)
	else:
		# Seeker rewards
		reward -= 0.2                                  # Time pressure
		if agent.can_see_opponent():
			reward += 12.0                             # Spotted hider!
		# Distance reward: closer to hider along walkable path is better
		if path_d >= 0:
			reward += clampf((25.0 - float(path_d)) * 0.4, 0.0, 8.0)
		else:
			var euclid := Vector2(agent.grid_pos).distance_to(Vector2(opponent.grid_pos))
			reward += clampf((20.0 - euclid) * 0.3, 0.0, 5.0)
		if move_result["hit_wall"]:
			reward -= 5.0

	return reward


func set_speed(speed: int) -> void:
	sim_speed = clampi(speed, 1, 100)


func _emit_stats() -> void:
	var data := {
		"episode": current_episode,
		"turn": current_turn,
		"time_left": time_left,
		"max_time": EPISODE_TIME_LIMIT,
		"speed": sim_speed,
		"hider_wins": hider_wins,
		"seeker_wins": seeker_wins,
		"hider_name": hider.agent_name if hider else "Hider",
		"seeker_name": seeker.agent_name if seeker else "Seeker",
		"agent1": {
			"name": agent1.agent_name if agent1 else "Agent 1",
			"role": "HIDER" if (agent1 and agent1.agent_type == AIAgent.AgentType.HIDER) else "SEEKER",
			"score": agent1.score if agent1 else 0,
			"wins": agent1.match_wins if agent1 else 0,
			"losses": agent1.match_losses if agent1 else 0,
			"stats": agent1.brain.get_stats() if agent1 and agent1.brain else {},
		},
		"agent2": {
			"name": agent2.agent_name if agent2 else "Agent 2",
			"role": "HIDER" if (agent2 and agent2.agent_type == AIAgent.AgentType.HIDER) else "SEEKER",
			"score": agent2.score if agent2 else 0,
			"wins": agent2.match_wins if agent2 else 0,
			"losses": agent2.match_losses if agent2 else 0,
			"stats": agent2.brain.get_stats() if agent2 and agent2.brain else {},
		},
		"hider_stats": hider.brain.get_stats() if hider and hider.brain else {},
		"seeker_stats": seeker.brain.get_stats() if seeker and seeker.brain else {},
		"hider_pos": hider.grid_pos if hider else Vector2i.ZERO,
		"seeker_pos": seeker.grid_pos if seeker else Vector2i.ZERO,
	}
	emit_signal("stats_updated", data)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1: set_speed(1)
			KEY_2: set_speed(5)
			KEY_3: set_speed(20)
			KEY_4: set_speed(100)
			KEY_P: paused = !paused


## Reset all reinforcement learning models, buffers, and win/loss records.
func reset_all_rl() -> void:
	if agent1:
		agent1.reset_all_rl()
	if agent2:
		agent2.reset_all_rl()
	time_left = EPISODE_TIME_LIMIT
	_turn_accumulator = 0.0
	current_episode = 0
	current_turn = 0
	hider_wins = 0
	seeker_wins = 0
	_emit_stats()
