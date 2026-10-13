## Tactical Advisor — Domain Knowledge & Common Rules Teacher Policy
## Provides deterministic, expert hide-and-seek rules for both Seeker and Hider.
## Used for teacher-guided exploration and tactical decision advice.
class_name TacticalAdvisor
extends RefCounted


## Check if two 3D world points have unobstructed Line-of-Sight (no walls between them).
static func has_line_of_sight(from_world: Vector3, to_world: Vector3, space_state: PhysicsDirectSpaceState3D) -> bool:
	if space_state == null:
		return false

	var query := PhysicsRayQueryParameters3D.create(from_world, to_world)
	query.collision_mask = 0xFFFFFFFF
	var hit := space_state.intersect_ray(query)

	if hit.is_empty():
		return true

	var hit_pos: Vector3 = hit["position"]
	# If hit occurs virtually at the destination target, consider it clear
	return hit_pos.distance_to(to_world) < 0.35


## Get tactical recommendation for the SEEKER (The Apex Hunter).
## Rules:
## 1. If Hider currently in LoS -> BFS pursuit towards Hider's tile.
## 2. Else if last seen position known -> BFS investigate last seen position.
## 3. Else -> Systematically patrol room centers and sweep corridors.
## 4. Never walk into walls. Never stand still when hunting.
static func get_seeker_advice(
	seeker_pos: Vector2i,
	hider_pos: Vector2i,
	can_see_hider: bool,
	last_seen_pos: Vector2i,
	map_ref: MapGenerator,
	patrol_idx: int = 0
) -> Dictionary:
	var valid_actions: Array = get_valid_movement_actions(seeker_pos, map_ref)
	if valid_actions.is_empty():
		return {"action": 4, "intent": "CORNERED", "patrol_idx": patrol_idx}

	# Rule 0: Strike / Tag Range -> Direct Strike!
	# Sound/light/footsteps in close quarters mean seeker lunges directly to tag target!
	var path_to_hider: int = map_ref.get_path_distance(seeker_pos, hider_pos)
	if path_to_hider >= 0 and path_to_hider <= 2:
		var step: int = map_ref.get_next_step_towards(seeker_pos, hider_pos)
		if step in valid_actions:
			return {"action": step, "intent": "TAGGING TARGET (STRIKE)", "patrol_idx": patrol_idx}

	# Rule 1: Visual Contact -> Relentless Pursuit
	if can_see_hider:
		var step: int = map_ref.get_next_step_towards(seeker_pos, hider_pos)
		if step in valid_actions:
			return {"action": step, "intent": "PURSUING TARGET (LoS)", "patrol_idx": patrol_idx}

	# Rule 2: Lost Sight -> Investigate Last Known Location
	if last_seen_pos != Vector2i.ZERO and seeker_pos != last_seen_pos:
		var step: int = map_ref.get_next_step_towards(seeker_pos, last_seen_pos)
		if step in valid_actions:
			return {"action": step, "intent": "INVESTIGATING LAST SEEN", "patrol_idx": patrol_idx}

	# Rule 3: No Contact -> Systematic Room Patrol
	var room_centers := map_ref.get_room_centers()
	var current_idx := patrol_idx
	if not room_centers.is_empty():
		current_idx = patrol_idx % room_centers.size()
		var target_room: Vector2i = room_centers[current_idx]

		# If already at the patrol room center, advance to the next room
		if seeker_pos == target_room:
			current_idx = (current_idx + 1) % room_centers.size()
			target_room = room_centers[current_idx]

		var step: int = map_ref.get_next_step_towards(seeker_pos, target_room)
		if step in valid_actions:
			var intent_str := "SWEEPING ROOM %d/%d" % [current_idx + 1, room_centers.size()]
			return {"action": step, "intent": intent_str, "patrol_idx": current_idx}

	# Fallback: Pick any valid movement action (prefer non-stay)
	var move_actions: Array = []
	for a in valid_actions:
		if a != 4:
			move_actions.append(a)
	var chosen: int = move_actions.pick_random() if not move_actions.is_empty() else valid_actions[0]
	return {"action": chosen, "intent": "PATROLLING CORRIDORS", "patrol_idx": current_idx}


## Get tactical recommendation for the HIDER (The Stealth Infiltrator).
## Rules:
## 1. If Seeker spotted or danger close -> Flee! Pick move maximizing path distance and breaking LoS.
## 2. If safe -> Hold cover in room or deep corner, avoiding open corridors.
## 3. Never walk into walls.
static func get_hider_advice(
	hider_pos: Vector2i,
	seeker_pos: Vector2i,
	can_see_seeker: bool,
	map_ref: MapGenerator,
	space_state: PhysicsDirectSpaceState3D = null
) -> Dictionary:
	var valid_actions: Array = get_valid_movement_actions(hider_pos, map_ref)
	if valid_actions.is_empty():
		return {"action": 4, "intent": "CORNERED"}

	var path_dist: int = map_ref.get_path_distance(hider_pos, seeker_pos)
	var is_in_danger: bool = can_see_seeker or (path_dist >= 0 and path_dist <= 6)

	# Rule 1: Danger / Pursuit -> Evade to cover & maximize distance
	if is_in_danger:
		var best_action: int = 4
		var best_score: float = -99999.0
		var seeker_eye := map_ref.grid_to_world(seeker_pos) + Vector3(0, 1.5, 0)

		# Evaluate all candidate moves (including stay)
		var candidates: Array = [0, 1, 2, 3, 4]
		for action in candidates:
			var dir: Vector2i = _action_to_dir(action)
			var nxt: Vector2i = hider_pos + dir

			if action != 4 and not map_ref.is_walkable(nxt):
				continue

			var target_tile: Vector2i = nxt if action != 4 else hider_pos
			var d: int = map_ref.get_path_distance(target_tile, seeker_pos)
			if d < 0:
				d = int(Vector2(target_tile).distance_to(Vector2(seeker_pos)))

			var score: float = float(d) * 4.0

			# Check if line-of-sight from seeker is broken at this target tile
			var cand_world := map_ref.grid_to_world(target_tile) + Vector3(0, 1.5, 0)
			var has_los := false
			if space_state:
				has_los = has_line_of_sight(seeker_eye, cand_world, space_state)

			if not has_los:
				score += 25.0  # Massive reward for taking cover behind walls!
			else:
				score -= 15.0  # Penalty for staying in seeker's direct LoS

			# Check exits from candidate tile to prevent running into dead-end traps
			var exits: Array[Vector2i] = map_ref.get_walkable_neighbors(target_tile)
			if exits.size() <= 1 and target_tile != hider_pos:
				score -= 30.0  # Avoid dead ends with only 1 exit!
			elif exits.size() >= 3:
				score += 5.0   # Mobility junction bonus

			if score > best_score:
				best_score = score
				best_action = action

		var intent := "EVADING TO COVER" if best_action != 4 else "HOLDING COVER"
		return {"action": best_action, "intent": intent}

	# Rule 2: Safe / Concealed -> Maintain cover or navigate to deep room corner
	# If in an open corridor (only 2 exits), move towards nearest room center
	var neighbors := map_ref.get_walkable_neighbors(hider_pos)
	if neighbors.size() == 2:
		# In a corridor — navigate toward nearest room
		var room_centers := map_ref.get_room_centers()
		if not room_centers.is_empty():
			var nearest_room: Vector2i = room_centers[0]
			var min_d: int = 999
			for rc in room_centers:
				var d: int = map_ref.get_path_distance(hider_pos, rc)
				if d >= 0 and d < min_d:
					min_d = d
					nearest_room = rc
			var step: int = map_ref.get_next_step_towards(hider_pos, nearest_room)
			if step in valid_actions:
				return {"action": step, "intent": "RETREATING TO ROOM"}

	# Safe in a room — hold stealth position with high probability (75%)
	if randf() < 0.75:
		return {"action": 4, "intent": "CONCEALED IN SHADOWS"}

	# Quiet repositioning within room
	var safe_moves: Array = []
	for a in valid_actions:
		if a != 4:
			var nxt_tile := hider_pos + _action_to_dir(a)
			var d_nxt := map_ref.get_path_distance(nxt_tile, seeker_pos)
			if d_nxt >= path_dist:
				safe_moves.append(a)

	var chosen: int = safe_moves.pick_random() if not safe_moves.is_empty() else 4
	return {"action": chosen, "intent": "STALKING SHADOWS"}


## Returns array of valid Action integers that do NOT walk into walls.
## [0=UP, 1=DOWN, 2=LEFT, 3=RIGHT, 4=STAY]
static func get_valid_movement_actions(pos: Vector2i, map_ref: MapGenerator) -> Array:
	var valids: Array = []
	# UP
	if map_ref.is_walkable(pos + Vector2i(0, -1)): valids.append(0)
	# DOWN
	if map_ref.is_walkable(pos + Vector2i(0, 1)):  valids.append(1)
	# LEFT
	if map_ref.is_walkable(pos + Vector2i(-1, 0)): valids.append(2)
	# RIGHT
	if map_ref.is_walkable(pos + Vector2i(1, 0)):  valids.append(3)
	# STAY is always valid
	valids.append(4)
	return valids


static func _action_to_dir(action: int) -> Vector2i:
	match action:
		0: return Vector2i(0, -1)
		1: return Vector2i(0, 1)
		2: return Vector2i(-1, 0)
		3: return Vector2i(1, 0)
		4: return Vector2i(0, 0)
	return Vector2i.ZERO
