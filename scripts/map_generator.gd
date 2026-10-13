## Procedural map generator using BSP (Binary Space Partitioning).
## Creates rooms connected by corridors on a grid, builds 3D wall/floor geometry.
class_name MapGenerator
extends Node3D

const TILE_SIZE: float = 2.0
const WALL_HEIGHT: float = 3.0
const MIN_PARTITION: int = 6
const MIN_ROOM: int = 4
const ROOM_MARGIN: int = 1

var grid_width: int = 40
var grid_height: int = 40
var grid: Array = []        # 2D array: 0=floor, 1=wall
var rooms: Array = []       # Array of Rect2i
var _wall_material: StandardMaterial3D
var _floor_material: StandardMaterial3D

# Inner class for BSP tree node
class BSPNode:
	var rect: Rect2i
	var left: BSPNode = null
	var right: BSPNode = null
	var room: Rect2i = Rect2i(0, 0, 0, 0)
	var split_horizontal: bool = false

	func _init(r: Rect2i) -> void:
		rect = r

	func is_leaf() -> bool:
		return left == null and right == null

	func get_room_center() -> Vector2i:
		if room.size.x > 0:
			return room.position + room.size / 2
		if left != null:
			return left.get_room_center()
		if right != null:
			return right.get_room_center()
		return rect.position + rect.size / 2


## Generate a new random map.
func generate(width: int = 40, height: int = 40, seed_val: int = -1) -> void:
	grid_width = width
	grid_height = height

	if seed_val >= 0:
		seed(seed_val)
	else:
		randomize()

	# Clear old geometry immediately (no await — must be synchronous)
	var old_children := get_children()
	for child in old_children:
		remove_child(child)
		child.queue_free()

	_create_materials()
	_init_grid()

	# BSP partition
	var root := BSPNode.new(Rect2i(1, 1, grid_width - 2, grid_height - 2))
	_split_node(root, 0)

	# Carve rooms into leaves
	rooms.clear()
	_carve_rooms(root)

	# Connect sibling rooms with corridors
	_connect_rooms(root)

	# Guarantee all rooms are in a single connected graph
	_ensure_all_rooms_connected()

	# Ensure border walls
	_enforce_border()

	# Build 3D meshes and atmospheric lighting
	_build_floor()
	_build_walls()
	_build_room_lights()


## Check if a grid position is walkable (floor).
func is_walkable(pos: Vector2i) -> bool:
	if pos.x < 0 or pos.x >= grid_width or pos.y < 0 or pos.y >= grid_height:
		return false
	return grid[pos.x][pos.y] == 0


## Convert grid coords to world position (center of tile).
func grid_to_world(pos: Vector2i) -> Vector3:
	return Vector3(pos.x * TILE_SIZE + TILE_SIZE * 0.5,
				   0.0,
				   pos.y * TILE_SIZE + TILE_SIZE * 0.5)


## Convert world position to grid coords.
func world_to_grid(world_pos: Vector3) -> Vector2i:
	return Vector2i(int(world_pos.x / TILE_SIZE), int(world_pos.z / TILE_SIZE))


## Get two spawn points in different rooms, as far apart as possible.
func get_spawn_points() -> Array:
	if rooms.size() < 2:
		# Fallback: find any two walkable tiles
		var points: Array = []
		for x in range(grid_width):
			for y in range(grid_height):
				if grid[x][y] == 0:
					points.append(Vector2i(x, y))
					if points.size() >= 2:
						return points
		return points

	# Pick the two rooms farthest apart
	var best_dist: float = 0.0
	var room_a: Rect2i = rooms[0]
	var room_b: Rect2i = rooms[1] if rooms.size() > 1 else rooms[0]

	for i in range(rooms.size()):
		for j in range(i + 1, rooms.size()):
			var ci: Vector2 = Vector2(rooms[i].position + rooms[i].size / 2)
			var cj: Vector2 = Vector2(rooms[j].position + rooms[j].size / 2)
			var d: float = ci.distance_to(cj)
			if d > best_dist:
				best_dist = d
				room_a = rooms[i]
				room_b = rooms[j]

	var spawn_a := Vector2i(room_a.position.x + room_a.size.x / 2,
							room_a.position.y + room_a.size.y / 2)
	var spawn_b := Vector2i(room_b.position.x + room_b.size.x / 2,
							room_b.position.y + room_b.size.y / 2)

	spawn_a = _find_walkable_in_room(room_a, spawn_a)
	spawn_b = _find_walkable_in_room(room_b, spawn_b)

	# Guarantee spawn_a and spawn_b are mutually reachable
	if not is_path_connected(spawn_a, spawn_b):
		_carve_corridor(spawn_a, spawn_b)
		_enforce_border()

	return [spawn_a, spawn_b]


func _find_walkable_in_room(r: Rect2i, fallback: Vector2i) -> Vector2i:
	if is_walkable(fallback):
		return fallback
	for x in range(r.position.x, r.position.x + r.size.x):
		for y in range(r.position.y, r.position.y + r.size.y):
			if is_walkable(Vector2i(x, y)):
				return Vector2i(x, y)
	for x in range(grid_width):
		for y in range(grid_height):
			if grid[x][y] == 0:
				return Vector2i(x, y)
	return fallback


## Return a copy of the wall grid (for HUD heatmap drawing).
func get_wall_grid() -> Array:
	return grid.duplicate(true)


# ── Private Methods ──

func _create_materials() -> void:
	_wall_material = StandardMaterial3D.new()
	_wall_material.albedo_color = Color(0.24, 0.25, 0.29)
	_wall_material.roughness = 0.55
	_wall_material.metallic = 0.25
	_wall_material.rim_enabled = true
	_wall_material.rim = 0.25
	_wall_material.rim_tint = 0.4

	_floor_material = StandardMaterial3D.new()
	_floor_material.albedo_color = Color(0.12, 0.13, 0.16)
	_floor_material.roughness = 0.35
	_floor_material.metallic = 0.3
	_floor_material.metallic_specular = 0.65


func _init_grid() -> void:
	grid.clear()
	for x in range(grid_width):
		var col: Array = []
		col.resize(grid_height)
		for y in range(grid_height):
			col[y] = 1  # wall
		grid.append(col)


func _split_node(node: BSPNode, depth: int) -> void:
	if depth >= 6:
		return
	if node.rect.size.x < MIN_PARTITION * 2 and node.rect.size.y < MIN_PARTITION * 2:
		return

	# Choose split direction
	var split_h: bool
	if node.rect.size.x > node.rect.size.y * 1.3:
		split_h = false
	elif node.rect.size.y > node.rect.size.x * 1.3:
		split_h = true
	else:
		split_h = randf() > 0.5

	var max_dim: int = (node.rect.size.y if split_h else node.rect.size.x) - MIN_PARTITION
	if max_dim < MIN_PARTITION:
		return

	var split_pos: int = randi_range(MIN_PARTITION, max_dim)
	node.split_horizontal = split_h

	if split_h:
		node.left = BSPNode.new(Rect2i(node.rect.position.x, node.rect.position.y,
										node.rect.size.x, split_pos))
		node.right = BSPNode.new(Rect2i(node.rect.position.x,
										node.rect.position.y + split_pos,
										node.rect.size.x,
										node.rect.size.y - split_pos))
	else:
		node.left = BSPNode.new(Rect2i(node.rect.position.x, node.rect.position.y,
										split_pos, node.rect.size.y))
		node.right = BSPNode.new(Rect2i(node.rect.position.x + split_pos,
										node.rect.position.y,
										node.rect.size.x - split_pos,
										node.rect.size.y))

	_split_node(node.left, depth + 1)
	_split_node(node.right, depth + 1)


func _carve_rooms(node: BSPNode) -> void:
	if node.is_leaf():
		# Create a room inside this leaf partition
		var rw: int = randi_range(MIN_ROOM, maxi(MIN_ROOM, node.rect.size.x - ROOM_MARGIN * 2))
		var rh: int = randi_range(MIN_ROOM, maxi(MIN_ROOM, node.rect.size.y - ROOM_MARGIN * 2))
		var rx: int = randi_range(node.rect.position.x + ROOM_MARGIN,
								  maxi(node.rect.position.x + ROOM_MARGIN,
									   node.rect.position.x + node.rect.size.x - rw - ROOM_MARGIN))
		var ry: int = randi_range(node.rect.position.y + ROOM_MARGIN,
								  maxi(node.rect.position.y + ROOM_MARGIN,
									   node.rect.position.y + node.rect.size.y - rh - ROOM_MARGIN))

		node.room = Rect2i(rx, ry, rw, rh)
		rooms.append(node.room)

		# Carve floor
		for x in range(rx, rx + rw):
			for y in range(ry, ry + rh):
				if x >= 0 and x < grid_width and y >= 0 and y < grid_height:
					grid[x][y] = 0

		# In large rooms (rw >= 6 and rh >= 6), place tactical interior cover pillars
		if rw >= 6 and rh >= 6:
			_place_room_tactical_cover(node.room)
	else:
		if node.left:
			_carve_rooms(node.left)
		if node.right:
			_carve_rooms(node.right)


## Adds tactical interior obstacles (pillars/server racks) in spacious rooms.
func _place_room_tactical_cover(r: Rect2i) -> void:
	var cx: int = r.position.x + r.size.x / 2
	var cy: int = r.position.y + r.size.y / 2
	var pattern: int = randi() % 3
	match pattern:
		0:
			# Central 2x2 pillar cluster
			if r.size.x >= 7 and r.size.y >= 7:
				grid[cx][cy] = 1
				grid[cx + 1][cy] = 1
				grid[cx][cy + 1] = 1
				grid[cx + 1][cy + 1] = 1
			else:
				grid[cx][cy] = 1
		1:
			# Dual cover barricades
			var off_x: int = maxi(1, r.size.x / 4)
			if cx - off_x > r.position.x + 1 and cx + off_x < r.position.x + r.size.x - 2:
				grid[cx - off_x][cy] = 1
				grid[cx + off_x][cy] = 1
		2:
			# Single central cover block
			grid[cx][cy] = 1


func _connect_rooms(node: BSPNode) -> void:
	if node.is_leaf():
		return
	if node.left:
		_connect_rooms(node.left)
	if node.right:
		_connect_rooms(node.right)
	if node.left and node.right:
		var c1: Vector2i = node.left.get_room_center()
		var c2: Vector2i = node.right.get_room_center()
		_carve_corridor(c1, c2)


func _carve_corridor(from: Vector2i, to: Vector2i) -> void:
	var x: int = from.x
	var y: int = from.y

	# Carve L-shaped corridor with safe playable bounds (1 .. size-2)
	while x != to.x:
		if x >= 1 and x < grid_width - 1 and y >= 1 and y < grid_height - 1:
			grid[x][y] = 0
			# Make corridor 2 tiles wide for clearance
			if y + 1 < grid_height - 1:
				grid[x][y + 1] = 0
		x += 1 if to.x > x else -1

	while y != to.y:
		if x >= 1 and x < grid_width - 1 and y >= 1 and y < grid_height - 1:
			grid[x][y] = 0
			if x + 1 < grid_width - 1:
				grid[x + 1][y] = 0
		y += 1 if to.y > y else -1

	# Explicitly carve destination tile
	if to.x >= 1 and to.x < grid_width - 1 and to.y >= 1 and to.y < grid_height - 1:
		grid[to.x][to.y] = 0
		if to.x + 1 < grid_width - 1:
			grid[to.x + 1][to.y] = 0
		if to.y + 1 < grid_height - 1:
			grid[to.x][to.y + 1] = 0


## BFS path existence check between any two grid points
func is_path_connected(start: Vector2i, target: Vector2i) -> bool:
	return get_path_distance(start, target) >= 0


## BFS shortest path finding between any two walkable grid points.
## Returns Array[Vector2i] including start and target, or empty array if unreachable.
func find_path(start: Vector2i, target: Vector2i) -> Array[Vector2i]:
	if not is_walkable(start) or not is_walkable(target):
		return []
	if start == target:
		return [start]

	var queue: Array = [start]
	var visited := {start: true}
	var parent := {}

	var dirs: Array = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

	while not queue.is_empty():
		var curr: Vector2i = queue.pop_front()
		if curr == target:
			# Reconstruct path
			var path: Array[Vector2i] = []
			var step: Vector2i = target
			while step != start:
				path.push_front(step)
				step = parent[step]
			path.push_front(start)
			return path

		for d in dirs:
			var nxt: Vector2i = curr + d
			if is_walkable(nxt) and not visited.has(nxt):
				visited[nxt] = true
				parent[nxt] = curr
				queue.push_back(nxt)

	return []


## Returns BFS shortest path distance (in grid steps), or -1 if unreachable.
func get_path_distance(start: Vector2i, target: Vector2i) -> int:
	if not is_walkable(start) or not is_walkable(target):
		return -1
	if start == target:
		return 0

	var queue: Array = [start]
	var dist_map := {start: 0}
	var dirs: Array = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

	while not queue.is_empty():
		var curr: Vector2i = queue.pop_front()
		var d_curr: int = dist_map[curr]

		for d in dirs:
			var nxt: Vector2i = curr + d
			if nxt == target:
				return d_curr + 1
			if is_walkable(nxt) and not dist_map.has(nxt):
				dist_map[nxt] = d_curr + 1
				queue.push_back(nxt)

	return -1


## Returns the Action enum value (0=UP, 1=DOWN, 2=LEFT, 3=RIGHT, 4=STAY)
## to take from `start` to advance towards `target` along the shortest path.
func get_next_step_towards(start: Vector2i, target: Vector2i) -> int:
	if start == target:
		return 4 # STAY

	var path := find_path(start, target)
	if path.size() < 2:
		return 4 # STAY

	var next_tile: Vector2i = path[1]
	var diff: Vector2i = next_tile - start
	if diff == Vector2i(0, -1): return 0 # UP
	if diff == Vector2i(0, 1):  return 1 # DOWN
	if diff == Vector2i(-1, 0): return 2 # LEFT
	if diff == Vector2i(1, 0):  return 3 # RIGHT
	return 4 # STAY


## Returns list of walkable adjacent neighbors for a given tile.
func get_walkable_neighbors(pos: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	var dirs: Array = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	for d in dirs:
		var n: Vector2i = pos + d
		if is_walkable(n):
			neighbors.append(n)
	return neighbors


## Exposes the centers of all generated rooms for systematic patrol.
func get_room_centers() -> Array[Vector2i]:
	var centers: Array[Vector2i] = []
	for r in rooms:
		var c := Vector2i(r.position.x + r.size.x / 2, r.position.y + r.size.y / 2)
		c = _find_walkable_in_room(r, c)
		if is_walkable(c):
			centers.append(c)
	return centers


## Ensures all generated rooms belong to one continuous connected component
func _ensure_all_rooms_connected() -> void:
	if rooms.size() < 2:
		return

	var root_center: Vector2i = rooms[0].position + rooms[0].size / 2
	for i in range(1, rooms.size()):
		var room_center: Vector2i = rooms[i].position + rooms[i].size / 2
		if not is_path_connected(root_center, room_center):
			var prev_center: Vector2i = rooms[i - 1].position + rooms[i - 1].size / 2
			_carve_corridor(prev_center, room_center)


func _enforce_border() -> void:
	for x in range(grid_width):
		grid[x][0] = 1
		grid[x][grid_height - 1] = 1
	for y in range(grid_height):
		grid[0][y] = 1
		grid[grid_width - 1][y] = 1


func _build_floor() -> void:
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(grid_width * TILE_SIZE, grid_height * TILE_SIZE)

	var floor_inst := MeshInstance3D.new()
	floor_inst.name = "Floor"
	floor_inst.mesh = floor_mesh
	floor_inst.material_override = _floor_material
	floor_inst.position = Vector3(grid_width * TILE_SIZE * 0.5, 0.0, grid_height * TILE_SIZE * 0.5)
	add_child(floor_inst)

	# Floor collision
	var floor_body := StaticBody3D.new()
	floor_body.name = "FloorBody"
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(grid_width * TILE_SIZE, 0.1, grid_height * TILE_SIZE)
	var floor_col := CollisionShape3D.new()
	floor_col.shape = floor_shape
	floor_body.add_child(floor_col)
	floor_body.position = Vector3(grid_width * TILE_SIZE * 0.5, -0.05, grid_height * TILE_SIZE * 0.5)
	add_child(floor_body)


func _build_walls() -> void:
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(TILE_SIZE, WALL_HEIGHT, TILE_SIZE)

	# Use MultiMeshInstance3D for performance
	var wall_positions: Array = []
	for x in range(grid_width):
		for y in range(grid_height):
			if grid[x][y] == 1:
				wall_positions.append(Vector3(
					x * TILE_SIZE + TILE_SIZE * 0.5,
					WALL_HEIGHT * 0.5,
					y * TILE_SIZE + TILE_SIZE * 0.5
				))

	if wall_positions.is_empty():
		return

	# Create MultiMesh for efficient rendering
	var multi_mesh := MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.mesh = wall_mesh
	multi_mesh.instance_count = wall_positions.size()

	for i in range(wall_positions.size()):
		var t := Transform3D.IDENTITY
		t.origin = wall_positions[i]
		multi_mesh.set_instance_transform(i, t)

	var mm_instance := MultiMeshInstance3D.new()
	mm_instance.name = "Walls"
	mm_instance.multimesh = multi_mesh
	mm_instance.material_override = _wall_material
	add_child(mm_instance)

	# Glowing LED cybernetic trim along the top rim of walls
	var trim_mesh := BoxMesh.new()
	trim_mesh.size = Vector3(TILE_SIZE * 0.98, 0.08, TILE_SIZE * 0.98)
	var multi_trim := MultiMesh.new()
	multi_trim.transform_format = MultiMesh.TRANSFORM_3D
	multi_trim.mesh = trim_mesh
	multi_trim.instance_count = wall_positions.size()

	for i in range(wall_positions.size()):
		var t_trim := Transform3D.IDENTITY
		t_trim.origin = wall_positions[i] + Vector3(0, WALL_HEIGHT * 0.5 - 0.04, 0)
		multi_trim.set_instance_transform(i, t_trim)

	var mm_trim := MultiMeshInstance3D.new()
	mm_trim.name = "WallTrims"
	mm_trim.multimesh = multi_trim
	var trim_mat := StandardMaterial3D.new()
	trim_mat.albedo_color = Color(0.2, 0.75, 1.0)
	trim_mat.emission_enabled = true
	trim_mat.emission = Color(0.18, 0.72, 1.0)
	trim_mat.emission_energy_multiplier = 1.8
	trim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm_trim.material_override = trim_mat
	add_child(mm_trim)

	# Individual collision bodies for walls (physics needs them separate)
	var walls_body := StaticBody3D.new()
	walls_body.name = "WallCollisions"
	add_child(walls_body)

	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(TILE_SIZE, WALL_HEIGHT, TILE_SIZE)

	for pos in wall_positions:
		var col := CollisionShape3D.new()
		col.shape = wall_shape
		col.position = pos
		walls_body.add_child(col)


## Adds architectural LED light fixtures and ceiling sconces to each generated room.
func _build_room_lights() -> void:
	var lights_root := Node3D.new()
	lights_root.name = "RoomLights"
	add_child(lights_root)

	var room_palette: Array[Color] = [
		Color(0.25, 0.75, 1.0),   # Cool Cyan Research Lab
		Color(1.0, 0.72, 0.35),   # Warm Amber Facility
		Color(0.85, 0.35, 0.95),  # Deep Violet Mainframe
		Color(0.92, 0.95, 1.0),   # Clean Crisp White Atrium
		Color(0.3, 0.95, 0.65),   # Emerald Terminal Bay
		Color(0.35, 0.55, 1.0),   # Cobalt Cryo Chamber
		Color(1.0, 0.55, 0.25),   # Industrial Halogen
		Color(0.5, 0.4, 0.95),    # Synthwave Lavender
		Color(0.95, 0.45, 0.6),   # Neon Rose Hydroponics
		Color(0.4, 0.85, 0.95),   # Arctic Blue Server Vault
	]

	for i in range(rooms.size()):
		var r: Rect2i = rooms[i]
		var c_grid := Vector2i(r.position.x + r.size.x / 2, r.position.y + r.size.y / 2)
		var c_world := grid_to_world(c_grid)

		var room_light := OmniLight3D.new()
		room_light.name = "RoomLight_%d" % i
		room_light.light_color = room_palette[i % room_palette.size()]
		room_light.light_energy = 1.15
		var room_extent: float = maxf(float(r.size.x), float(r.size.y)) * TILE_SIZE * 0.95
		room_light.omni_range = maxf(11.0, room_extent * 1.1)
		room_light.omni_attenuation = 1.25
		room_light.shadow_enabled = true
		room_light.shadow_bias = 0.05
		room_light.position = Vector3(c_world.x, WALL_HEIGHT - 0.25, c_world.z)
		lights_root.add_child(room_light)

		# Physical glowing ceiling fixture
		var fixture := MeshInstance3D.new()
		var f_mesh := BoxMesh.new()
		f_mesh.size = Vector3(0.9, 0.08, 0.9)
		fixture.mesh = f_mesh
		var f_mat := StandardMaterial3D.new()
		f_mat.albedo_color = Color(0.9, 0.95, 1.0)
		f_mat.emission_enabled = true
		f_mat.emission = room_light.light_color
		f_mat.emission_energy_multiplier = 3.0
		f_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fixture.material_override = f_mat
		fixture.position = Vector3(c_world.x, WALL_HEIGHT - 0.04, c_world.z)
		lights_root.add_child(fixture)
