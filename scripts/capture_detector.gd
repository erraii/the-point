extends RefCounted


const GameGeometry := preload(
	"res://scripts/game_geometry.gd"
)

var columns: int
var rows: int
var maximum_face_walk_steps: int

var points: Dictionary
var captured_point_owners: Dictionary


func _init(
	board_columns: int,
	board_rows: int
) -> void:
	columns = board_columns
	rows = board_rows
	maximum_face_walk_steps = columns * rows * 8


func find_closed_regions(
	board_points: Dictionary,
	board_captured_point_owners: Dictionary,
	player: int
) -> Array:
	points = board_points
	captured_point_owners = (
		board_captured_point_owners
	)

	var result: Array = []
	var components := (
		_find_biconnected_components(player)
	)

	for component in components:
		var outer_cycle := (
			_find_component_outer_cycle(
				component,
				player
			)
		)

		if outer_cycle.size() >= 3:
			result.append(outer_cycle)

	return result


func _is_inside_board(
	grid_position: Vector2i
) -> bool:
	return (
		grid_position.x >= 0
		and grid_position.x < columns
		and grid_position.y >= 0
		and grid_position.y < rows
	)


func _is_active_player_point(
	grid_position: Vector2i,
	player: int
) -> bool:
	return (
		_is_inside_board(grid_position)
		and not captured_point_owners.has(
			grid_position
		)
		and int(
			points.get(grid_position, -1)
		) == player
	)


func _get_same_player_neighbors(
	grid_position: Vector2i,
	player: int
) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []

	for row_offset in range(-1, 2):
		for column_offset in range(-1, 2):
			if (
				column_offset == 0
				and row_offset == 0
			):
				continue

			var neighbor_position := (
				grid_position
				+ Vector2i(
					column_offset,
					row_offset
				)
			)

			if not _is_active_player_point(
				neighbor_position,
				player
			):
				continue

			neighbors.append(neighbor_position)

	return neighbors


func _get_neighbor_angle(
	center: Vector2i,
	neighbor: Vector2i
) -> float:
	var direction := neighbor - center

	return atan2(
		float(direction.y),
		float(direction.x)
	)


func _sort_neighbors_by_angle(
	center: Vector2i,
	neighbors: Array[Vector2i]
) -> Array[Vector2i]:
	var sorted_neighbors: Array[Vector2i] = []

	for neighbor in neighbors:
		var neighbor_angle := _get_neighbor_angle(
			center,
			neighbor
		)

		var insert_index := 0

		while insert_index < sorted_neighbors.size():
			var existing_neighbor := (
				sorted_neighbors[insert_index]
			)

			var existing_angle := _get_neighbor_angle(
				center,
				existing_neighbor
			)

			if neighbor_angle < existing_angle:
				break

			insert_index += 1

		sorted_neighbors.insert(
			insert_index,
			neighbor
		)

	return sorted_neighbors


func _get_planar_neighbors(
	grid_position: Vector2i,
	player: int
) -> Array[Vector2i]:
	var planar_neighbors: Array[Vector2i] = []

	for neighbor in _get_same_player_neighbors(
		grid_position,
		player
	):
		var column_offset := (
			neighbor.x - grid_position.x
		)

		var row_offset := (
			neighbor.y - grid_position.y
		)

		var is_diagonal := (
			absi(column_offset) == 1
			and absi(row_offset) == 1
		)

		if is_diagonal:
			var horizontal_corner := (
				grid_position
				+ Vector2i(column_offset, 0)
			)

			var vertical_corner := (
				grid_position
				+ Vector2i(0, row_offset)
			)

			if (
				_is_active_player_point(
					horizontal_corner,
					player
				)
				and _is_active_player_point(
					vertical_corner,
					player
				)
			):
				continue

		planar_neighbors.append(neighbor)

	return _sort_neighbors_by_angle(
		grid_position,
		planar_neighbors
	)


func _edge_matches(
	edge: Array,
	first: Vector2i,
	second: Vector2i
) -> bool:
	return (
		(
			edge[0] == first
			and edge[1] == second
		)
		or
		(
			edge[0] == second
			and edge[1] == first
		)
	)


func _pop_biconnected_component(
	edge_stack: Array,
	stop_first: Vector2i,
	stop_second: Vector2i
) -> Array[Vector2i]:
	var component_positions: Dictionary = {}

	while not edge_stack.is_empty():
		var edge: Array = edge_stack.pop_back()

		component_positions[edge[0]] = true
		component_positions[edge[1]] = true

		if _edge_matches(
			edge,
			stop_first,
			stop_second
		):
			break

	var component: Array[Vector2i] = []

	for raw_position in component_positions:
		var grid_position: Vector2i = raw_position
		component.append(grid_position)

	return component


func _search_biconnected_components(
	current: Vector2i,
	player: int,
	search_state: Dictionary
) -> void:
	var discovery: Dictionary = (
		search_state["discovery"]
	)

	var low: Dictionary = search_state["low"]
	var parents: Dictionary = search_state["parents"]
	var edge_stack: Array = search_state["edge_stack"]

	search_state["time"] = int(
		search_state["time"]
	) + 1

	var current_time := int(
		search_state["time"]
	)

	discovery[current] = current_time
	low[current] = current_time

	var no_parent := Vector2i(-1000, -1000)
	var parent: Vector2i = parents.get(
		current,
		no_parent
	)

	for neighbor in _get_planar_neighbors(
		current,
		player
	):
		if not discovery.has(neighbor):
			parents[neighbor] = current

			edge_stack.append([
				current,
				neighbor
			])

			_search_biconnected_components(
				neighbor,
				player,
				search_state
			)

			low[current] = mini(
				int(low[current]),
				int(low[neighbor])
			)

			if (
				int(low[neighbor])
				>= int(discovery[current])
			):
				var component := (
					_pop_biconnected_component(
						edge_stack,
						current,
						neighbor
					)
				)

				if component.size() >= 3:
					var components: Array = (
						search_state["components"]
					)

					components.append(component)
					search_state["components"] = (
						components
					)

		elif (
			neighbor != parent
			and int(discovery[neighbor])
			< int(discovery[current])
		):
			low[current] = mini(
				int(low[current]),
				int(discovery[neighbor])
			)

			edge_stack.append([
				current,
				neighbor
			])

	search_state["discovery"] = discovery
	search_state["low"] = low
	search_state["parents"] = parents
	search_state["edge_stack"] = edge_stack


func _find_biconnected_components(
	player: int
) -> Array:
	var search_state: Dictionary = {
		"time": 0,
		"discovery": {},
		"low": {},
		"parents": {},
		"edge_stack": [],
		"components": []
	}

	for raw_position in points:
		var grid_position: Vector2i = raw_position

		if not _is_active_player_point(
			grid_position,
			player
		):
			continue

		var discovery: Dictionary = (
			search_state["discovery"]
		)

		if discovery.has(grid_position):
			continue

		_search_biconnected_components(
			grid_position,
			player,
			search_state
		)

	return search_state["components"]


func _directed_edge_key(
	first: Vector2i,
	second: Vector2i
) -> String:
	return "%d,%d>%d,%d" % [
		first.x,
		first.y,
		second.x,
		second.y
	]


func _get_component_neighbors(
	grid_position: Vector2i,
	player: int,
	component_lookup: Dictionary
) -> Array[Vector2i]:
	var component_neighbors: Array[Vector2i] = []

	for neighbor in _get_planar_neighbors(
		grid_position,
		player
	):
		if component_lookup.has(neighbor):
			component_neighbors.append(neighbor)

	return _sort_neighbors_by_angle(
		grid_position,
		component_neighbors
	)


func _walk_component_face(
	start_from: Vector2i,
	start_to: Vector2i,
	player: int,
	component_lookup: Dictionary,
	visited_edges: Dictionary
) -> Array[Vector2i]:
	var face: Array[Vector2i] = []
	var from_position := start_from
	var to_position := start_to

	for step in range(maximum_face_walk_steps):
		var edge_key := _directed_edge_key(
			from_position,
			to_position
		)

		if visited_edges.has(edge_key):
			return []

		visited_edges[edge_key] = true
		face.append(from_position)

		var neighbors := _get_component_neighbors(
			to_position,
			player,
			component_lookup
		)

		if neighbors.size() < 2:
			return []

		var incoming_index := neighbors.find(
			from_position
		)

		if incoming_index < 0:
			return []

		var next_index := (
			incoming_index - 1
			+ neighbors.size()
		) % neighbors.size()

		var next_position := neighbors[next_index]

		from_position = to_position
		to_position = next_position

		if (
			from_position == start_from
			and to_position == start_to
		):
			return face

	return []


func _find_component_outer_cycle(
	component: Array,
	player: int
) -> Array[Vector2i]:
	var component_lookup: Dictionary = {}

	for raw_position in component:
		var grid_position: Vector2i = raw_position
		component_lookup[grid_position] = true

	var visited_edges: Dictionary = {}
	var largest_cycle: Array[Vector2i] = []
	var largest_area := 0.0

	for raw_position in component:
		var grid_position: Vector2i = raw_position

		for neighbor in _get_component_neighbors(
			grid_position,
			player,
			component_lookup
		):
			var edge_key := _directed_edge_key(
				grid_position,
				neighbor
			)

			if visited_edges.has(edge_key):
				continue

			var candidate_cycle := (
				_walk_component_face(
					grid_position,
					neighbor,
					player,
					component_lookup,
					visited_edges
				)
			)

			if candidate_cycle.size() < 3:
				continue

			if GameGeometry.cycle_has_repeated_points(
				candidate_cycle
			):
				continue

			if GameGeometry.cycle_crosses_itself(
				candidate_cycle
			):
				continue

			var candidate_area := (
				GameGeometry.calculate_cycle_area(
					candidate_cycle
				)
			)

			if candidate_area > largest_area:
				largest_area = candidate_area
				largest_cycle.clear()
				largest_cycle.append_array(
					candidate_cycle
				)

	return largest_cycle
