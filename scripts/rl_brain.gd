## Deep Q-Learning brain for AI agents.
## Uses NeuralNetwork for function approximation with experience replay.
class_name RLBrain
extends RefCounted

# ── Configuration ──
const REPLAY_BUFFER_SIZE: int = 10000
const BATCH_SIZE: int = 16
const TARGET_UPDATE_FREQ: int = 100
const GAMMA: float = 0.95
const EPSILON_START: float = 1.0
const EPSILON_END: float = 0.05
const EPSILON_DECAY: float = 0.9995
const LEARNING_RATE: float = 0.001

# ── State ──
var policy_net: NeuralNetwork
var target_net: NeuralNetwork
var replay_buffer: Array = []
var epsilon: float = EPSILON_START
var total_steps: int = 0
var episode_reward: float = 0.0
var total_reward_history: Array = []  # Last N episode rewards
var loss_history: Array = []
var is_hider: bool
var state_size: int
var action_count: int = 5  # UP, DOWN, LEFT, RIGHT, STAY
var last_q_values: Array = []  # Cached Q-values from last action selection


func _init(s_size: int = 40, a_count: int = 5, hider: bool = true) -> void:
	state_size = s_size
	action_count = a_count
	is_hider = hider
	last_q_values.resize(action_count)
	last_q_values.fill(0.0)

	# Network architecture: state → 256 → 128 → 64 → actions
	var arch: Array = [state_size, 256, 128, 64, action_count]
	policy_net = NeuralNetwork.new(arch, LEARNING_RATE)
	target_net = NeuralNetwork.new(arch, LEARNING_RATE)
	target_net.copy_weights_from(policy_net)


## Select action using epsilon-greedy policy with valid-action masking and teacher guidance.
func select_action(state: Array, valid_actions: Array = [], teacher_action: int = -1) -> int:
	last_q_values = policy_net.forward(state).duplicate()

	var valids: Array = valid_actions.duplicate()
	if valids.is_empty():
		for i in range(action_count):
			valids.append(i)

	if randf() < epsilon:
		# Teacher guidance: follow recommended common rule action with 80% probability
		if teacher_action >= 0 and teacher_action in valids and randf() < 0.80:
			return teacher_action
		# Otherwise explore among valid, legal moves (never hit walls!)
		return valids.pick_random()
	else:
		# Masked ArgMax over valid actions
		var best: int = valids[0]
		var best_val: float = -1e9
		for act in valids:
			if act >= 0 and act < last_q_values.size():
				if last_q_values[act] > best_val:
					best_val = last_q_values[act]
					best = act
		return best


## Store a transition in the replay buffer.
func store_experience(state: Array, action: int, reward: float,
					  next_state: Array, done: bool) -> void:
	var experience := {
		"state": state.duplicate(),
		"action": action,
		"reward": reward,
		"next_state": next_state.duplicate(),
		"done": done
	}

	if replay_buffer.size() >= REPLAY_BUFFER_SIZE:
		replay_buffer.pop_front()
	replay_buffer.append(experience)

	episode_reward += reward
	total_steps += 1


## Train on a mini-batch from replay buffer. Returns average loss.
func train_step() -> float:
	if replay_buffer.size() < BATCH_SIZE:
		return 0.0

	var total_loss: float = 0.0

	# Sample mini-batch
	for _i in range(BATCH_SIZE):
		var idx: int = randi() % replay_buffer.size()
		var exp: Dictionary = replay_buffer[idx]

		# Current Q-values
		var q_values: Array = policy_net.forward(exp["state"]).duplicate()

		# Target Q-value for the taken action
		var target_q: float
		if exp["done"]:
			target_q = exp["reward"]
		else:
			var next_q: Array = target_net.forward(exp["next_state"])
			var max_next_q: float = next_q[0]
			for j in range(1, next_q.size()):
				max_next_q = maxf(max_next_q, next_q[j])
			target_q = exp["reward"] + GAMMA * max_next_q

		# Build target array (only modify the taken action's Q-value)
		var target_arr: Array = q_values.duplicate()
		target_arr[exp["action"]] = target_q

		total_loss += policy_net.train_single(exp["state"], target_arr)

	var avg_loss: float = total_loss / BATCH_SIZE

	# Decay epsilon
	epsilon = maxf(EPSILON_END, epsilon * EPSILON_DECAY)

	# Update target network periodically
	if total_steps % TARGET_UPDATE_FREQ == 0:
		target_net.copy_weights_from(policy_net)

	if loss_history.size() > 200:
		loss_history.pop_front()
	loss_history.append(avg_loss)

	return avg_loss


## Call at end of episode to record reward and reset.
func end_episode() -> void:
	total_reward_history.append(episode_reward)
	if total_reward_history.size() > 100:
		total_reward_history.pop_front()
	episode_reward = 0.0


## Get statistics dictionary for HUD display.
func get_stats() -> Dictionary:
	var avg_reward: float = 0.0
	if total_reward_history.size() > 0:
		for r in total_reward_history:
			avg_reward += r
		avg_reward /= total_reward_history.size()

	var avg_loss: float = 0.0
	if loss_history.size() > 0:
		for l in loss_history:
			avg_loss += l
		avg_loss /= loss_history.size()

	return {
		"epsilon": epsilon,
		"total_steps": total_steps,
		"avg_reward": avg_reward,
		"avg_loss": avg_loss,
		"episode_reward": episode_reward,
		"buffer_size": replay_buffer.size(),
		"param_count": policy_net.get_param_count(),
		"reward_history": total_reward_history.duplicate(),
	}


## Get Q-values for a given state (for heatmap visualization).
func get_q_values(state: Array) -> Array:
	return policy_net.forward(state)


## Completely wipe all learned weights, replay buffer, and stats.
func reset_rl() -> void:
	epsilon = EPSILON_START
	total_steps = 0
	episode_reward = 0.0
	total_reward_history.clear()
	loss_history.clear()
	replay_buffer.clear()
	last_q_values.fill(0.0)

	# Re-create neural networks from scratch with fresh Xavier random weights
	var arch: Array = [state_size, 256, 128, 64, action_count]
	policy_net = NeuralNetwork.new(arch, LEARNING_RATE)
	target_net = NeuralNetwork.new(arch, LEARNING_RATE)
	target_net.copy_weights_from(policy_net)


## Export complete brain state to Dictionary.
func export_brain_data() -> Dictionary:
	return {
		"is_hider": is_hider,
		"epsilon": epsilon,
		"total_steps": total_steps,
		"state_size": state_size,
		"action_count": action_count,
		"policy_net": policy_net.export_data(),
		"target_net": target_net.export_data(),
		"loss_history": loss_history.duplicate(),
		"reward_history": total_reward_history.duplicate()
	}


## Save brain parameters to JSON file.
func save_brain(filepath: String) -> bool:
	var file := FileAccess.open(filepath, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open file for writing: %s" % filepath)
		return false
	var json_str := JSON.stringify(export_brain_data(), "\t")
	file.store_string(json_str)
	file.close()
	return true


## Load brain parameters from JSON file.
func load_brain(filepath: String) -> bool:
	if not FileAccess.file_exists(filepath):
		push_warning("File does not exist: %s" % filepath)
		return false
	var file := FileAccess.open(filepath, FileAccess.READ)
	if file == null:
		return false
	var content := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(content) != OK:
		return false
	var data: Dictionary = parser.data
	if data.has("epsilon"): epsilon = data["epsilon"]
	if data.has("total_steps"): total_steps = data["total_steps"]
	if data.has("policy_net"): policy_net.import_data(data["policy_net"])
	if data.has("target_net"): target_net.import_data(data["target_net"])
	if data.has("loss_history"): loss_history = data["loss_history"]
	if data.has("reward_history"): total_reward_history = data["reward_history"]
	return true
