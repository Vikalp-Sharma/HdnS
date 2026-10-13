## Pure GDScript feedforward neural network.
## Supports configurable layers, ReLU activations, backpropagation with SGD.
## ~52K parameters with default architecture [40, 256, 128, 64, 5].
class_name NeuralNetwork
extends RefCounted

var weights: Array = []       # Array of 2D weight matrices (Array[Array[float]])
var biases: Array = []        # Array of bias vectors (Array[float])
var layer_sizes: PackedInt32Array
var learning_rate: float = 0.001

# Cached for backpropagation
var _activations: Array = []
var _z_values: Array = []


func _init(sizes: Array = [40, 256, 128, 64, 5], lr: float = 0.001) -> void:
	layer_sizes = PackedInt32Array(sizes)
	learning_rate = lr
	_xavier_init()


func _xavier_init() -> void:
	weights.clear()
	biases.clear()
	for i in range(layer_sizes.size() - 1):
		var fan_in: int = layer_sizes[i]
		var fan_out: int = layer_sizes[i + 1]
		var scale: float = sqrt(2.0 / float(fan_in))

		var w: Array = []
		w.resize(fan_out)
		for r in range(fan_out):
			var row: Array = []
			row.resize(fan_in)
			for c in range(fan_in):
				row[c] = randfn(0.0, scale)
			w[r] = row
		weights.append(w)

		var b: Array = []
		b.resize(fan_out)
		for r in range(fan_out):
			b[r] = 0.0
		biases.append(b)


## Forward pass — returns output Q-values.
func forward(input: Array) -> Array:
	_activations = [input.duplicate()]
	_z_values = []

	var current: Array = input
	for i in range(weights.size()):
		var z: Array = _mat_vec_mul(weights[i], current)
		# Add bias
		for j in range(z.size()):
			z[j] += biases[i][j]
		_z_values.append(z.duplicate())

		# ReLU for hidden layers, linear for output layer
		if i < weights.size() - 1:
			current = _relu(z)
		else:
			current = z.duplicate()
		_activations.append(current.duplicate())

	return current


## Backpropagation with MSE loss. Returns loss value.
func backward(target: Array) -> float:
	var output: Array = _activations[_activations.size() - 1]
	var n_out: int = output.size()

	# Compute MSE loss and output delta
	var loss: float = 0.0
	var delta: Array = []
	delta.resize(n_out)
	for i in range(n_out):
		var err: float = output[i] - target[i]
		delta[i] = 2.0 * err / float(n_out)  # dL/d_output
		loss += err * err
	loss /= float(n_out)

	# Propagate backwards through layers
	for l in range(weights.size() - 1, -1, -1):
		var prev_act: Array = _activations[l]
		var n_rows: int = weights[l].size()
		var n_cols: int = weights[l][0].size()

		# Gradient for output layer is delta directly
		# For hidden layers, apply ReLU derivative
		if l < weights.size() - 1:
			for r in range(n_rows):
				if _z_values[l][r] <= 0.0:
					delta[r] = 0.0

		# Update weights and biases
		for r in range(n_rows):
			var d: float = delta[r]
			var row: Array = weights[l][r]
			for c in range(n_cols):
				row[c] -= learning_rate * d * prev_act[c]
			biases[l][r] -= learning_rate * d

		# Compute delta for previous layer
		if l > 0:
			var new_delta: Array = []
			new_delta.resize(n_cols)
			for j in range(n_cols):
				var s: float = 0.0
				for k in range(n_rows):
					s += weights[l][k][j] * delta[k]
				new_delta[j] = s
			delta = new_delta

	return loss


## Train on a single sample: input → target Q-values.
func train_single(input: Array, target: Array) -> float:
	forward(input)
	return backward(target)


## Copy weights from another network (for target network updates).
func copy_weights_from(source: NeuralNetwork) -> void:
	for i in range(weights.size()):
		for r in range(weights[i].size()):
			for c in range(weights[i][r].size()):
				weights[i][r][c] = source.weights[i][r][c]
			biases[i][r] = source.biases[i][r]


## Get total parameter count.
func get_param_count() -> int:
	var count: int = 0
	for i in range(weights.size()):
		count += weights[i].size() * weights[i][0].size()  # weights
		count += biases[i].size()  # biases
	return count


## Predict best action index (argmax of Q-values).
func predict_action(state: Array) -> int:
	var q_vals: Array = forward(state)
	var best: int = 0
	var best_val: float = q_vals[0]
	for i in range(1, q_vals.size()):
		if q_vals[i] > best_val:
			best_val = q_vals[i]
			best = i
	return best


## Export weights and biases to a Dictionary for serialization.
func export_data() -> Dictionary:
	return {
		"layer_sizes": Array(layer_sizes),
		"learning_rate": learning_rate,
		"weights": weights,
		"biases": biases
	}


## Import weights and biases from a Dictionary.
func import_data(data: Dictionary) -> bool:
	if not data.has("weights") or not data.has("biases"):
		return false
	weights = data["weights"]
	biases = data["biases"]
	if data.has("learning_rate"):
		learning_rate = data["learning_rate"]
	if data.has("layer_sizes"):
		layer_sizes = PackedInt32Array(data["layer_sizes"])
	return true


## Save network parameters to JSON file.
func save_to_json(filepath: String) -> bool:
	var file := FileAccess.open(filepath, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open file for writing: %s" % filepath)
		return false
	var json_str := JSON.stringify(export_data(), "\t")
	file.store_string(json_str)
	file.close()
	return true


## Load network parameters from JSON file.
func load_from_json(filepath: String) -> bool:
	if not FileAccess.file_exists(filepath):
		push_warning("File does not exist: %s" % filepath)
		return false
	var file := FileAccess.open(filepath, FileAccess.READ)
	if file == null:
		return false
	var content := file.get_as_text()
	file.close()
	var test_json_conv := JSON.new()
	var err := test_json_conv.parse(content)
	if err != OK:
		return false
	return import_data(test_json_conv.data)


# ── Internal helpers ──

func _mat_vec_mul(mat: Array, vec: Array) -> Array:
	var rows: int = mat.size()
	var result: Array = []
	result.resize(rows)
	for r in range(rows):
		var s: float = 0.0
		var row: Array = mat[r]
		for c in range(row.size()):
			s += row[c] * vec[c]
		result[r] = s
	return result


func _relu(arr: Array) -> Array:
	var result: Array = []
	result.resize(arr.size())
	for i in range(arr.size()):
		result[i] = maxf(0.0, arr[i])
	return result
