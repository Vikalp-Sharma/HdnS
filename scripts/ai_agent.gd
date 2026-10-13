## AI Agent — CharacterBody3D with capsule mesh, vision raycasting, RL brain,
## yellow clearance ring, and thought state tracking.
class_name AIAgent
extends Node3D

const AgentBodyBuilder = preload("res://scripts/agent_body_builder.gd")
const TacticalAdvisor = preload("res://scripts/tactical_advisor.gd")

# ── Enums ──
enum AgentType { HIDER, SEEKER }
enum Action { UP = 0, DOWN = 1, LEFT = 2, RIGHT = 3, STAY = 4 }

# Action names for display
const ACTION_NAMES: Array = ["MOVING NORTH", "MOVING SOUTH", "MOVING WEST", "MOVING EAST", "HOLDING POSITION"]

# ── Configuration ──
const VISION_RAYS: int = 15
const VISION_ANGLE: float = 140.0   # degrees, generous cone angle
const VISION_RANGE: float = 24.0    # world units (12 tiles for 40x40 arena)
const MOVE_SPEED: float = 14.0      # snappy interpolation speed
const CLEARANCE_RADIUS: float = 2.0 # yellow ring radius

# ── State ──
var agent_type: AgentType = AgentType.HIDER
var agent_id: int = 1
var agent_name: String = "Agent 1"
var score: int = 0
var match_wins: int = 0
var match_losses: int = 0

var grid_pos: Vector2i = Vector2i.ZERO
var facing_dir: Vector2i = Vector2i(0, -1)  # Default facing
var brain: RLBrain
var hider_brain: RLBrain
var seeker_brain: RLBrain
var map_ref: MapGenerator  # Reference to map generator

# Vision data (cached after each cast)
var _vision_data: Array = []       # Array of {distance, hit_type} per ray
var _can_see_opponent: bool = false
var _opponent_distance: float = 0.0

# Thought tracking (for agent window display)
var tactical_intent: String = ""
var last_action: int = -1
var last_action_name: String = "—"
var last_q_values: Array = [0.0, 0.0, 0.0, 0.0, 0.0]
var last_reward: float = 0.0

# Smooth movement
var _target_world_pos: Vector3 = Vector3.ZERO
var _is_moving: bool = false

var _mesh_instance: Node3D
var _light: OmniLight3D
var _searchlight: SpotLight3D
var _clearance_ring: MeshInstance3D
var _clearance_ring_outer: MeshInstance3D
var _clearance_pulse_time: float = 0.0

# High-performance vision ray renderer (reused mesh, 0 allocations)
var _vision_mesh: ImmediateMesh
var _vision_mi: MeshInstance3D


func setup(type: AgentType, start_pos: Vector2i, map: MapGenerator, id: int = 1, a_name: String = "Agent 1") -> void:
	agent_type = type
	grid_pos = start_pos
	map_ref = map
	agent_id = id
	agent_name = a_name

	# Create dedicated RL brains for both roles (40 input features)
	var state_size: int = 4 + VISION_RAYS * 2 + 4 + 1 + 1  # = 40
	hider_brain = RLBrain.new(state_size, 5, true)
	seeker_brain = RLBrain.new(state_size, 5, false)
	brain = hider_brain if agent_type == AgentType.HIDER else seeker_brain

	# Build 3D representation
	_build_visuals()

	# Set initial position
	_target_world_pos = map_ref.grid_to_world(grid_pos)
	_target_world_pos.y = 1.0
	position = _target_world_pos


## Swaps or updates agent role dynamically, updating active brain, body model, light, and state.
func set_role(new_type: AgentType) -> void:
	agent_type = new_type
	brain = hider_brain if agent_type == AgentType.HIDER else seeker_brain

	# Physically morph the 3D agent character body to match the new role
	if _mesh_instance:
		AgentBodyBuilder.build_body(_mesh_instance, agent_type, false)

	# Update light glow color and intensity
	if _light:
		_light.light_color = Color(0.18, 0.72, 1.0) if agent_type == AgentType.HIDER else Color(1.0, 0.22, 0.15)
		_light.light_energy = 1.1 if agent_type == AgentType.HIDER else 1.5
		_light.omni_range = 5.5 if agent_type == AgentType.HIDER else 6.5

	# Update tactical searchlight
	if _searchlight:
		_searchlight.light_color = Color(1.0, 0.22, 0.15) if agent_type == AgentType.SEEKER else Color(0.18, 0.72, 1.0)
		_searchlight.light_energy = 2.6 if agent_type == AgentType.SEEKER else 0.0
		_searchlight.visible = (agent_type == AgentType.SEEKER)

	facing_dir = Vector2i(0, 1) if agent_type == AgentType.HIDER else Vector2i(0, -1)
	_can_see_opponent = false
	_opponent_distance = VISION_RANGE
	if _vision_mesh:
		_vision_mesh.clear_surfaces()


## Repositions agent on a new map without re-initializing neural network weights.
func reposition_on_new_map(new_pos: Vector2i, new_map: MapGenerator) -> void:
	grid_pos = new_pos
	map_ref = new_map
	_target_world_pos = map_ref.grid_to_world(grid_pos)
	_target_world_pos.y = 1.0
	position = _target_world_pos
	facing_dir = Vector2i(0, 1) if agent_type == AgentType.HIDER else Vector2i(0, -1)
	_can_see_opponent = false
	_opponent_distance = VISION_RANGE
	if _vision_mesh:
		_vision_mesh.clear_surfaces()


## Returns current simulation world position (target tile center), avoiding lerp lag.
func get_sim_world_pos() -> Vector3:
	if _target_world_pos != Vector3.ZERO:
		return _target_world_pos
	if map_ref != null:
		return map_ref.grid_to_world(grid_pos) + Vector3(0, 1.0, 0)
	return position


func _build_visuals() -> void:
	# Root container node for the agent's procedural character body
	_mesh_instance = Node3D.new()
	_mesh_instance.name = "CharacterBody"
	add_child(_mesh_instance)
	AgentBodyBuilder.build_body(_mesh_instance, agent_type, false)

	# OmniLight for role ambient aura
	_light = OmniLight3D.new()
	_light.light_energy = 1.1 if agent_type == AgentType.HIDER else 1.5
	_light.omni_range = 5.5 if agent_type == AgentType.HIDER else 6.5
	_light.omni_attenuation = 1.2
	_light.shadow_enabled = false
	_light.light_color = Color(0.18, 0.72, 1.0) if agent_type == AgentType.HIDER else Color(1.0, 0.22, 0.15)
	_light.position = Vector3(0, 1.4, 0)
	add_child(_light)

	# Tactical Searchlight (forward spotlight for Seeker hunter)
	_searchlight = SpotLight3D.new()
	_searchlight.name = "TacticalSearchlight"
	_searchlight.spot_range = 28.0
	_searchlight.spot_angle = 38.0
	_searchlight.spot_attenuation = 1.2
	_searchlight.position = Vector3(0, 1.3, 0)
	_searchlight.shadow_enabled = true
	_searchlight.shadow_bias = 0.04
	_searchlight.light_color = Color(1.0, 0.22, 0.15) if agent_type == AgentType.SEEKER else Color(0.18, 0.72, 1.0)
	_searchlight.light_energy = 2.6 if agent_type == AgentType.SEEKER else 0.0
	_searchlight.visible = (agent_type == AgentType.SEEKER)
	add_child(_searchlight)

	# ── Yellow clearance ring (inner) ──
	_clearance_ring = MeshInstance3D.new()
	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = CLEARANCE_RADIUS
	ring_mesh.bottom_radius = CLEARANCE_RADIUS
	ring_mesh.height = 0.02
	ring_mesh.radial_segments = 48
	_clearance_ring.mesh = ring_mesh

	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(1.0, 0.92, 0.3, 0.10)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring_mat.no_depth_test = false
	_clearance_ring.material_override = ring_mat
	_clearance_ring.position = Vector3(0, -0.9, 0)  # At feet
	add_child(_clearance_ring)

	# ── Yellow clearance ring (outer, fainter) ──
	_clearance_ring_outer = MeshInstance3D.new()
	var ring_mesh2 := CylinderMesh.new()
	ring_mesh2.top_radius = CLEARANCE_RADIUS * 1.5
	ring_mesh2.bottom_radius = CLEARANCE_RADIUS * 1.5
	ring_mesh2.height = 0.015
	ring_mesh2.radial_segments = 48
	_clearance_ring_outer.mesh = ring_mesh2

	var ring_mat2 := StandardMaterial3D.new()
	ring_mat2.albedo_color = Color(1.0, 0.85, 0.2, 0.05)
	ring_mat2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat2.cull_mode = BaseMaterial3D.CULL_DISABLED
	_clearance_ring_outer.material_override = ring_mat2
	_clearance_ring_outer.position = Vector3(0, -0.92, 0)
	add_child(_clearance_ring_outer)

	# Vision debug rays (reused ImmediateMesh, 1 draw call)
	_vision_mesh = ImmediateMesh.new()
	_vision_mi = MeshInstance3D.new()
	_vision_mi.name = "VisionRays"
	_vision_mi.mesh = _vision_mesh
	var ray_mat := StandardMaterial3D.new()
	ray_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ray_mat.vertex_color_use_as_albedo = true
	ray_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ray_mat.no_depth_test = true
	_vision_mi.material_override = ray_mat
	add_child(_vision_mi)


func _process(delta: float) -> void:
	var tm = get_tree().root.find_child("TurnManager", true, false) if is_inside_tree() else null
	if tm and tm.sim_speed >= 20:
		position = _target_world_pos
		_is_moving = false
	elif position.distance_to(_target_world_pos) > 0.05:
		position = position.lerp(_target_world_pos, MOVE_SPEED * delta)
		_is_moving = true
	else:
		position = _target_world_pos
		_is_moving = false

	# Face movement direction
	var face_world := Vector3(facing_dir.x, 0, facing_dir.y)
	if _mesh_instance != null and face_world.length_squared() > 0.01:
		var target_angle := atan2(face_world.x, face_world.z)
		_mesh_instance.rotation.y = lerp_angle(_mesh_instance.rotation.y, target_angle + PI, 5.0 * delta)
		if _searchlight != null and _searchlight.visible:
			var target_look: Vector3 = _searchlight.global_position + face_world * 5.0
			_searchlight.look_at(target_look, Vector3.UP)

	# Pulse clearance rings
	_clearance_pulse_time += delta
	if _clearance_ring:
		var pulse: float = 0.08 + 0.05 * sin(_clearance_pulse_time * 2.0)
		var ring_mat: StandardMaterial3D = _clearance_ring.material_override
		if ring_mat:
			ring_mat.albedo_color.a = pulse
	if _clearance_ring_outer:
		var pulse2: float = 0.04 + 0.03 * sin(_clearance_pulse_time * 1.5 + 0.8)
		var ring_mat2: StandardMaterial3D = _clearance_ring_outer.material_override
		if ring_mat2:
			ring_mat2.albedo_color.a = pulse2


## Returns valid movement actions that do not collide with walls.
func get_valid_actions() -> Array:
	var valids: Array = []
	if map_ref == null:
		return [0, 1, 2, 3, 4]
	# UP
	if map_ref.is_walkable(grid_pos + Vector2i(0, -1)): valids.append(0)
	# DOWN
	if map_ref.is_walkable(grid_pos + Vector2i(0, 1)):  valids.append(1)
	# LEFT
	if map_ref.is_walkable(grid_pos + Vector2i(-1, 0)): valids.append(2)
	# RIGHT
	if map_ref.is_walkable(grid_pos + Vector2i(1, 0)):  valids.append(3)
	# STAY
	valids.append(4)
	return valids


## Perform an action (move in direction or stay). Returns reward component.
func perform_action(action: int) -> Dictionary:
	var direction := _action_to_direction(action)
	var result := {"new_pos": grid_pos, "valid": true, "hit_wall": false}

	# Track for thought display
	last_action = action
	last_action_name = ACTION_NAMES[action] if action >= 0 and action < ACTION_NAMES.size() else "UNKNOWN"

	if direction != Vector2i.ZERO:
		var new_pos := grid_pos + direction

		if map_ref != null and map_ref.is_walkable(new_pos):
			grid_pos = new_pos
			result["new_pos"] = new_pos
			facing_dir = direction
		else:
			result["valid"] = false
			result["hit_wall"] = true
			last_action_name += " [BLOCKED]"
	else:
		# If holding position, ensure we don't stare directly into an adjacent wall
		if map_ref != null and not map_ref.is_walkable(grid_pos + facing_dir):
			var valids := get_valid_actions()
			for v in valids:
				if v != 4:
					facing_dir = _action_to_direction(v)
					break

	# Update world position
	if map_ref != null:
		_target_world_pos = map_ref.grid_to_world(grid_pos)
		_target_world_pos.y = 1.0

	return result


## Cast vision rays and update _vision_data with direct Line-of-Sight and proximity.
func cast_vision(opponent_world_pos: Vector3) -> void:
	_vision_data.clear()
	_can_see_opponent = false
	_opponent_distance = VISION_RANGE

	var world := get_world_3d() if is_inside_tree() else null
	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state if world != null else null
	if space_state == null:
		for _i in range(VISION_RAYS):
			_vision_data.append({"distance": 1.0, "hit_type": 0.0})
		return

	# Use true simulation target position so multi-step frames cast from the current tile
	var base_pos: Vector3 = _target_world_pos if _target_world_pos != Vector3.ZERO else position
	var ray_origin := base_pos + Vector3(0, 0.7, 0)
	var opp_eye := opponent_world_pos + Vector3(0, 0.7, 0)
	var dist_to_opp := ray_origin.distance_to(opp_eye)

	var forward := Vector3(facing_dir.x, 0, facing_dir.y).normalized()
	if forward.length_squared() < 0.01:
		forward = Vector3(0, 0, -1)

	# 1. Direct Line-of-Sight (LoS) & Hearing / Proximity Detection
	var to_opp := opp_eye - ray_origin
	var fwd_2d := Vector2(forward.x, forward.z).normalized()
	var to_opp_2d := Vector2(to_opp.x, to_opp.z).normalized()
	var angle_to_opp_deg := rad_to_deg(absf(fwd_2d.angle_to(to_opp_2d)))

	# Check field of view cone (140° total) or close proximity awareness (3.6 units = 1.8 tiles)
	var in_view_range: bool = dist_to_opp <= VISION_RANGE
	var in_fov_cone: bool = angle_to_opp_deg <= (VISION_ANGLE * 0.5)
	var in_proximity: bool = dist_to_opp <= 3.6

	if in_view_range and (in_fov_cone or in_proximity):
		var los_query := PhysicsRayQueryParameters3D.create(ray_origin, opp_eye)
		los_query.collision_mask = 0xFFFFFFFF
		var los_hit := space_state.intersect_ray(los_query)

		# Clear LoS if no raycast hit or hit point is right at the opponent
		if los_hit.is_empty() or ray_origin.distance_to(los_hit["position"]) >= (dist_to_opp - 0.35):
			_can_see_opponent = true
			_opponent_distance = dist_to_opp

	# 2. Multi-Ray Visualization (15 rays across 140° cone)
	var half_angle := deg_to_rad(VISION_ANGLE * 0.5)
	var ray_lines: Array = []

	for i in range(VISION_RAYS):
		var angle_offset: float = 0.0
		if VISION_RAYS > 1:
			angle_offset = lerp(-half_angle, half_angle, float(i) / float(VISION_RAYS - 1))

		var ray_dir := forward.rotated(Vector3.UP, angle_offset).normalized()
		var ray_end := ray_origin + ray_dir * VISION_RANGE

		# Raycast against walls
		var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
		query.collision_mask = 0xFFFFFFFF
		var result := space_state.intersect_ray(query)

		var max_ray_dist: float = VISION_RANGE
		var hit_type: float = 0.0  # 0=clear, 0.5=wall, 1.0=opponent

		if result.size() > 0:
			max_ray_dist = ray_origin.distance_to(result["position"])
			hit_type = 0.5

		var actual_ray_dist: float = max_ray_dist

		# Check if this ray aligns with the visible opponent
		if _can_see_opponent and dist_to_opp <= (max_ray_dist + 0.35):
			var ray_dir_2d := Vector2(ray_dir.x, ray_dir.z).normalized()
			var diff_deg := rad_to_deg(absf(ray_dir_2d.angle_to(to_opp_2d)))
			if diff_deg <= 10.0:
				hit_type = 1.0
				actual_ray_dist = minf(max_ray_dist, dist_to_opp)

		var dist_normalized: float = clampf(actual_ray_dist / VISION_RANGE, 0.0, 1.0)
		_vision_data.append({"distance": dist_normalized, "hit_type": hit_type})

		# Ray color
		var ray_color: Color
		if hit_type >= 1.0:
			ray_color = Color(1.0, 0.2, 0.2, 0.85)   # Red: saw opponent!
		elif hit_type >= 0.5:
			ray_color = Color(0.9, 0.85, 0.2, 0.25) # Amber: wall
		else:
			ray_color = Color(0.2, 1.0, 0.3, 0.12)  # Green: clear corridor

		var start_local: Vector3 = ray_origin - position
		var end_local: Vector3 = start_local + ray_dir * actual_ray_dist
		ray_lines.append({"start": start_local, "end": end_local, "color": ray_color})

	# Fast single-pass line rendering
	if _vision_mesh:
		_vision_mesh.clear_surfaces()
		_vision_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for rl in ray_lines:
			_vision_mesh.surface_set_color(rl["color"])
			_vision_mesh.surface_add_vertex(rl["start"])
			_vision_mesh.surface_set_color(rl["color"])
			_vision_mesh.surface_add_vertex(rl["end"])
		_vision_mesh.surface_end()


## Construct state vector for RL input.
## Accepts (opponent_pos, time_remaining_ratio) or (opponent_pos, max_val, current_val).
func get_state(opponent_pos: Vector2i, arg2 = 1.0, arg3 = 0.0) -> Array:
	var state: Array = []
	var gw: float = float(map_ref.grid_width)
	var gh: float = float(map_ref.grid_height)

	# Normalized grid position
	state.append(float(grid_pos.x) / gw)
	state.append(float(grid_pos.y) / gh)

	# Normalized relative opponent position
	state.append(float(opponent_pos.x - grid_pos.x) / gw)
	state.append(float(opponent_pos.y - grid_pos.y) / gh)

	# Vision ray data (15 rays × 2 values = 30)
	for vd in _vision_data:
		state.append(vd["distance"])
		state.append(vd["hit_type"])

	# Pad if vision not yet cast
	while state.size() < 4 + VISION_RAYS * 2:
		state.append(1.0)
		state.append(0.0)

	# Adjacent wall info (N, S, E, W)
	state.append(0.0 if map_ref.is_walkable(grid_pos + Vector2i(0, -1)) else 1.0)
	state.append(0.0 if map_ref.is_walkable(grid_pos + Vector2i(0, 1)) else 1.0)
	state.append(0.0 if map_ref.is_walkable(grid_pos + Vector2i(1, 0)) else 1.0)
	state.append(0.0 if map_ref.is_walkable(grid_pos + Vector2i(-1, 0)) else 1.0)

	# Time remaining normalized (0.0 .. 1.0)
	var time_ratio: float = 1.0
	if typeof(arg2) == TYPE_FLOAT and arg3 == 0.0:
		time_ratio = clampf(arg2, 0.0, 1.0)
	elif float(arg2) > 0.0:
		time_ratio = clampf(float(arg2 - arg3) / float(arg2), 0.0, 1.0)
	state.append(time_ratio)

	# 40th feature: Role identity (1.0 = Hider, 0.0 = Seeker)
	state.append(1.0 if agent_type == AgentType.HIDER else 0.0)

	return state


## Check if this agent can currently see the opponent.
func can_see_opponent() -> bool:
	return _can_see_opponent


func get_type_name() -> String:
	return "Hider" if agent_type == AgentType.HIDER else "Seeker"


## Get thought data for the agent window display.
func get_thoughts() -> Dictionary:
	var stats: Dictionary = brain.get_stats()
	var status: String
	if not tactical_intent.is_empty():
		status = tactical_intent
	elif agent_type == AgentType.HIDER:
		status = "EVADING TO COVER" if _can_see_opponent else "CONCEALED IN SHADOWS"
	else:
		status = "PURSUING TARGET (LoS)" if _can_see_opponent else "PATROLLING FACILITY"

	return {
		"agent_id": agent_id,
		"agent_name": agent_name,
		"role_name": "HIDER" if agent_type == AgentType.HIDER else "SEEKER",
		"score": score,
		"match_wins": match_wins,
		"match_losses": match_losses,
		"status": status,
		"tactical_intent": tactical_intent,
		"action_name": last_action_name,
		"last_action": last_action,
		"sees_opponent": _can_see_opponent,
		"opponent_dist": _opponent_distance,
		"q_values": last_q_values.duplicate(),
		"epsilon": stats.get("epsilon", 1.0),
		"episode_reward": stats.get("episode_reward", 0.0),
		"avg_reward": stats.get("avg_reward", 0.0),
		"avg_loss": stats.get("avg_loss", 0.0),
		"total_steps": stats.get("total_steps", 0),
		"buffer_size": stats.get("buffer_size", 0),
	}


## Reset both role brains and match records.
func reset_all_rl() -> void:
	if hider_brain:
		hider_brain.reset_rl()
	if seeker_brain:
		seeker_brain.reset_rl()
	score = 0
	match_wins = 0
	match_losses = 0


## Save both hider and seeker brains to a directory.
func save_agent_qtables(base_dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(base_dir)
	var safe_name := agent_name.replace(" ", "_").replace("(", "").replace(")", "").to_lower()
	if hider_brain:
		hider_brain.save_brain(base_dir.path_join("%s_hider_brain.json" % safe_name))
	if seeker_brain:
		seeker_brain.save_brain(base_dir.path_join("%s_seeker_brain.json" % safe_name))


## Load both hider and seeker brains from a directory.
func load_agent_qtables(base_dir: String) -> void:
	var safe_name := agent_name.replace(" ", "_").replace("(", "").replace(")", "").to_lower()
	var hider_path := base_dir.path_join("%s_hider_brain.json" % safe_name)
	var seeker_path := base_dir.path_join("%s_seeker_brain.json" % safe_name)
	if hider_brain and FileAccess.file_exists(hider_path):
		hider_brain.load_brain(hider_path)
	if seeker_brain and FileAccess.file_exists(seeker_path):
		seeker_brain.load_brain(seeker_path)


# ── Private Helpers ──

func _action_to_direction(action: int) -> Vector2i:
	match action:
		Action.UP:    return Vector2i(0, -1)
		Action.DOWN:  return Vector2i(0, 1)
		Action.LEFT:  return Vector2i(-1, 0)
		Action.RIGHT: return Vector2i(1, 0)
		Action.STAY:  return Vector2i(0, 0)
	return Vector2i.ZERO
