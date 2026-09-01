extends Control


const COLUMNS := 15
const ROWS := 21
const CELL_SIZE := 60.0

const PLAYER_GRAPHITE := 0
const PLAYER_RED := 1

const GRID_COLOR := Color(0.36, 0.55, 0.65, 0.38)
const GRAPHITE_COLOR := Color(0.10, 0.10, 0.11, 1.0)
const RED_COLOR := Color(0.90, 0.10, 0.06, 1.0)

const GRID_WIDTH := 2.0
const POINT_STROKES := 9
const MAX_CYCLE_SEARCH_STEPS := 50000

var current_player := PLAYER_GRAPHITE
var points: Dictionary = {}
var point_styles: Dictionary = {}
var captured_regions: Array = []
var captured_point_owners: Dictionary = {}
var closed_cycles: Array = []

func _draw() -> void:
	var board_width := (COLUMNS - 1) * CELL_SIZE
	var board_height := (ROWS - 1) * CELL_SIZE

	for column in range(COLUMNS):
		var x := column * CELL_SIZE
		draw_line(
			Vector2(x, 0.0),
			Vector2(x, board_height),
			GRID_COLOR,
			GRID_WIDTH,
			true
		)

	for row in range(ROWS):
		var y := row * CELL_SIZE
		draw_line(
			Vector2(0.0, y),
			Vector2(board_width, y),
			GRID_COLOR,
			GRID_WIDTH,
			true
		)

	_draw_captured_regions()
	for grid_position in points:
		var center := Vector2(
			grid_position.x * CELL_SIZE,
			grid_position.y * CELL_SIZE
		)

		var point_color: Color

		if points[grid_position] == PLAYER_GRAPHITE:
			point_color = GRAPHITE_COLOR
		else:
			point_color = RED_COLOR

		_draw_pencil_point(
			center,
			point_color,
			point_styles[grid_position]
		)

func _draw_captured_regions() -> void:
	for region in captured_regions:
		var owner: int = int(region["owner"])
		var cycle = region["cycle"]
		var style_seed: int = int(region["style_seed"])

		var polygon := PackedVector2Array()

		for grid_position in cycle:
			polygon.append(
				Vector2(
					grid_position.x * CELL_SIZE,
					grid_position.y * CELL_SIZE
				)
			)

		if polygon.size() < 3:
			continue

		var base_color: Color

		if owner == PLAYER_GRAPHITE:
			base_color = GRAPHITE_COLOR
		else:
			base_color = RED_COLOR

		var fill_color := base_color
		fill_color.a = 0.10

		draw_colored_polygon(polygon, fill_color)

		var rng := RandomNumberGenerator.new()
		rng.seed = style_seed

		# Aynı sınırı üç kez hafif kaydırarak elle çizilmiş
		# görünümü oluşturuyoruz.
		for trace in range(3):
			var traced_polygon := PackedVector2Array()

			for point in polygon:
				traced_polygon.append(
					point + Vector2(
						rng.randf_range(-2.5, 2.5),
						rng.randf_range(-2.5, 2.5)
					)
				)

			for index in range(traced_polygon.size()):
				var next_index := (
					index + 1
				) % traced_polygon.size()

				var line_color := base_color
				line_color.a = rng.randf_range(0.30, 0.48)

				draw_line(
					traced_polygon[index],
					traced_polygon[next_index],
					line_color,
					rng.randf_range(1.8, 3.2),
					true
				)
				
func _draw_pencil_point(
	center: Vector2,
	base_color: Color,
	style_seed: int
) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = style_seed

	# Noktanın altında kalan hafif pigment lekeleri.
	for layer in range(3):
		var smudge_offset := Vector2(
			rng.randf_range(-2.5, 2.5),
			rng.randf_range(-2.5, 2.5)
		)

		var smudge_color := base_color
		smudge_color.a = rng.randf_range(0.10, 0.18)

		draw_circle(
			center + smudge_offset,
			rng.randf_range(6.0, 10.0),
			smudge_color,
			true,
			-1.0,
			true
		)

	# Aynı yere farklı yönlerde atılmış kısa kalem darbeleri.
	for stroke in range(POINT_STROKES):
		var offset := Vector2(
			rng.randf_range(-3.0, 3.0),
			rng.randf_range(-3.0, 3.0)
		)

		var angle := rng.randf_range(0.0, TAU)
		var half_length := rng.randf_range(4.0, 9.0)

		var direction := Vector2(
			cos(angle),
			sin(angle)
		) * half_length

		var stroke_color := base_color
		stroke_color.a = rng.randf_range(0.30, 0.52)

		draw_line(
			center + offset - direction,
			center + offset + direction,
			stroke_color,
			rng.randf_range(1.8, 3.5),
			true
		)

func _is_inside_board(grid_position: Vector2i) -> bool:
	return (
		grid_position.x >= 0
		and grid_position.x < COLUMNS
		and grid_position.y >= 0
		and grid_position.y < ROWS
	)


func _get_same_player_neighbors(
	grid_position: Vector2i,
	player: int
) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []

	for row_offset in range(-1, 2):
		for column_offset in range(-1, 2):
			if column_offset == 0 and row_offset == 0:
				continue

			var neighbor_position := grid_position + Vector2i(
				column_offset,
				row_offset
			)

			if not _is_inside_board(neighbor_position):
				continue
				
			if captured_point_owners.has(neighbor_position):
				continue

			if points.get(neighbor_position, -1) == player:
				neighbors.append(neighbor_position)

	return neighbors

func _search_path(
	current: Vector2i,
	target: Vector2i,
	player: int,
	blocked_point: Vector2i,
	visited: Dictionary,
	path: Array[Vector2i]
) -> bool:
	visited[current] = true
	path.append(current)

	if current == target:
		return true

	for neighbor in _get_same_player_neighbors(current, player):
		if neighbor == blocked_point:
			continue

		if visited.has(neighbor):
			continue

		if _search_path(
			neighbor,
			target,
			player,
			blocked_point,
			visited,
			path
		):
			return true

	path.pop_back()
	return false


func _find_path_without_point(
	start: Vector2i,
	target: Vector2i,
	player: int,
	blocked_point: Vector2i
) -> Array[Vector2i]:
	var visited: Dictionary = {}
	var path: Array[Vector2i] = []

	if _search_path(
		start,
		target,
		player,
		blocked_point,
		visited,
		path
	):
		return path

	return []

func _cross_product(
	first: Vector2i,
	second: Vector2i,
	third: Vector2i
) -> int:
	return (
		(second.x - first.x)
		* (third.y - first.y)
		- (second.y - first.y)
		* (third.x - first.x)
	)


func _segments_cross(
	first_start: Vector2i,
	first_end: Vector2i,
	second_start: Vector2i,
	second_end: Vector2i
) -> bool:
	# Ortak noktada birleşmek normaldir; bu kesişme sayılmaz.
	if (
		first_start == second_start
		or first_start == second_end
		or first_end == second_start
		or first_end == second_end
	):
		return false

	var first_side := _cross_product(
		first_start,
		first_end,
		second_start
	)

	var second_side := _cross_product(
		first_start,
		first_end,
		second_end
	)

	var third_side := _cross_product(
		second_start,
		second_end,
		first_start
	)

	var fourth_side := _cross_product(
		second_start,
		second_end,
		first_end
	)

	return (
		(
			(first_side > 0 and second_side < 0)
			or (first_side < 0 and second_side > 0)
		)
		and
		(
			(third_side > 0 and fourth_side < 0)
			or (third_side < 0 and fourth_side > 0)
		)
	)


func _cycle_crosses_itself(cycle: Array) -> bool:
	for first_index in range(cycle.size()):
		var first_start = cycle[first_index]
		var first_end = cycle[
			(first_index + 1) % cycle.size()
		]

		for second_index in range(
			first_index + 1,
			cycle.size()
		):
			# Yan yana duran çizgiler aynı köşede birleşebilir.
			if second_index == first_index + 1:
				continue

			if (
				first_index == 0
				and second_index == cycle.size() - 1
			):
				continue

			var second_start = cycle[second_index]
			var second_end = cycle[
				(second_index + 1) % cycle.size()
			]

			if _segments_cross(
				first_start,
				first_end,
				second_start,
				second_end
			):
				return true

	return false

func _search_cycle_paths(
	current: Vector2i,
	target: Vector2i,
	player: int,
	blocked_point: Vector2i,
	new_point: Vector2i,
	visited: Dictionary,
	path: Array[Vector2i],
	search_state: Dictionary
) -> void:
	if (
		int(search_state["steps"])
		>= MAX_CYCLE_SEARCH_STEPS
	):
		return

	search_state["steps"] = (
		int(search_state["steps"]) + 1
	)

	visited[current] = true
	path.append(current)

	if current == target:
		var candidate_cycle: Array[Vector2i] = [
			new_point
		]
		candidate_cycle.append_array(path)

		var candidate_area := (
			_calculate_cycle_area(candidate_cycle)
		)

		var largest_area := float(
			search_state["largest_area"]
		)

		if (
			not _cycle_crosses_itself(candidate_cycle)
			and candidate_area > largest_area
		):
			search_state["largest_area"] = candidate_area
			search_state["largest_cycle"] = (
				candidate_cycle.duplicate()
			)

	else:
		for neighbor in _get_same_player_neighbors(
			current,
			player
		):
			if neighbor == blocked_point:
				continue

			if visited.has(neighbor):
				continue

			if (
				int(search_state["steps"])
				>= MAX_CYCLE_SEARCH_STEPS
			):
				break

			_search_cycle_paths(
				neighbor,
				target,
				player,
				blocked_point,
				new_point,
				visited,
				path,
				search_state
			)

	path.pop_back()
	visited.erase(current)

func _find_cycle_from_new_point(
	new_point: Vector2i,
	player: int
) -> Array[Vector2i]:
	var neighbors := _get_same_player_neighbors(
		new_point,
		player
	)

	var result: Array[Vector2i] = []

	if neighbors.size() < 2:
		return result

	var search_state: Dictionary = {
		"steps": 0,
		"largest_area": 0.0,
		"largest_cycle": []
	}

	for first_index in range(neighbors.size()):
		for second_index in range(
			first_index + 1,
			neighbors.size()
		):
			var visited: Dictionary = {}
			var path: Array[Vector2i] = []

			_search_cycle_paths(
				neighbors[first_index],
				neighbors[second_index],
				player,
				new_point,
				new_point,
				visited,
				path,
				search_state
			)

			if (
				int(search_state["steps"])
				>= MAX_CYCLE_SEARCH_STEPS
			):
				break

		if (
			int(search_state["steps"])
			>= MAX_CYCLE_SEARCH_STEPS
		):
			break

	for grid_position in search_state["largest_cycle"]:
		result.append(grid_position)

	return result

func _get_cycle_center(cycle: Array) -> Vector2:
	var center := Vector2.ZERO

	for grid_position in cycle:
		center += Vector2(
			grid_position.x,
			grid_position.y
		)

	return center / cycle.size()


func _is_point_inside_cycle(
	point: Vector2,
	cycle: Array
) -> bool:
	var inside := false
	var previous_index := cycle.size() - 1

	for current_index in range(cycle.size()):
		var current := Vector2(
			cycle[current_index].x,
			cycle[current_index].y
		)

		var previous := Vector2(
			cycle[previous_index].x,
			cycle[previous_index].y
		)

		var crosses_horizontal_ray := (
			(current.y > point.y)
			!= (previous.y > point.y)
		)

		if crosses_horizontal_ray:
			var intersection_x := (
				(previous.x - current.x)
				* (point.y - current.y)
				/ (previous.y - current.y)
				+ current.x
			)

			if point.x < intersection_x:
				inside = not inside

		previous_index = current_index

	return inside


func _remove_regions_inside_cycle(
	new_cycle: Array
) -> void:
	var new_area := _calculate_cycle_area(new_cycle)

	for region_index in range(
		captured_regions.size() - 1,
		-1,
		-1
	):
		var old_cycle = (
			captured_regions[region_index]["cycle"]
		)
		var old_area := _calculate_cycle_area(old_cycle)

		if old_area >= new_area:
			continue

		var old_center := _get_cycle_center(old_cycle)

		if _is_point_inside_cycle(
			old_center,
			new_cycle
		):
			captured_regions.remove_at(region_index)
			
func _get_other_player(player: int) -> int:
	if player == PLAYER_GRAPHITE:
		return PLAYER_RED

	return PLAYER_GRAPHITE


func _is_cycle_active(
	cycle: Array,
	owner: int
) -> bool:
	for grid_position in cycle:
		if captured_point_owners.has(grid_position):
			return false

		if int(points.get(grid_position, -1)) != owner:
			return false

	return true


func _store_closed_cycle(
	owner: int,
	new_cycle: Array[Vector2i]
) -> void:
	var new_area := _calculate_cycle_area(new_cycle)

	if new_area <= 0.0:
		return

	var new_center := _get_cycle_center(new_cycle)

	for cycle_index in range(
		closed_cycles.size() - 1,
		-1,
		-1
	):
		var stored_cycle = closed_cycles[cycle_index]
		var stored_owner := int(stored_cycle["owner"])
		var old_cycle = stored_cycle["cycle"]

		if stored_owner != owner:
			continue

		if not _is_cycle_active(old_cycle, owner):
			closed_cycles.remove_at(cycle_index)
			continue

		var old_area := _calculate_cycle_area(old_cycle)
		var old_center := _get_cycle_center(old_cycle)

		# Yeni çevre zaten daha büyük bir çevrenin içindeyse
		# ayrıca saklanmasına gerek yok.
		if (
			old_area >= new_area
			and _is_point_inside_cycle(
				new_center,
				old_cycle
			)
		):
			return

		# Yeni çevre eskisini kapsıyorsa yalnızca büyük olanı sakla.
		if (
			new_area > old_area
			and _is_point_inside_cycle(
				old_center,
				new_cycle
			)
		):
			closed_cycles.remove_at(cycle_index)

	closed_cycles.append(
		{
			"owner": owner,
			"cycle": new_cycle.duplicate()
		}
	)


func _cycle_has_new_content(
	owner: int,
	cycle: Array
) -> bool:
	for grid_position in points:
		if cycle.has(grid_position):
			continue

		var point_position := Vector2(
			grid_position.x,
			grid_position.y
		)

		if not _is_point_inside_cycle(
			point_position,
			cycle
		):
			continue

		if captured_point_owners.has(grid_position):
			# Rakibin sahip olduğu eski bir bölge yeniden çevrilmiş.
			if int(
				captured_point_owners[grid_position]
			) != owner:
				return true

		elif int(points[grid_position]) != owner:
			# Aktif rakip noktası çevrilmiş.
			return true

	return false


func _remove_inactive_closed_cycles() -> void:
	for cycle_index in range(
		closed_cycles.size() - 1,
		-1,
		-1
	):
		var stored_cycle = closed_cycles[cycle_index]
		var owner := int(stored_cycle["owner"])
		var cycle = stored_cycle["cycle"]

		if not _is_cycle_active(cycle, owner):
			closed_cycles.remove_at(cycle_index)


func _capture_cycle(
	owner: int,
	cycle: Array
) -> void:
	# Sınırın içerisindeki bütün mevcut noktalar pasifleşir.
	for grid_position in points:
		if cycle.has(grid_position):
			continue

		var point_position := Vector2(
			grid_position.x,
			grid_position.y
		)

		if _is_point_inside_cycle(
			point_position,
			cycle
		):
			captured_point_owners[grid_position] = owner

	# Büyük çevre, içindeki eski küçük bölgelerin yerini alır.
	_remove_regions_inside_cycle(cycle)

	captured_regions.append(
		{
			"owner": owner,
			"cycle": cycle.duplicate(),
			"style_seed": randi()
		}
	)

	_remove_inactive_closed_cycles()


func _evaluate_largest_capture_for_player(
	owner: int
) -> bool:
	var largest_cycle: Array = []
	var largest_area := 0.0

	for stored_cycle in closed_cycles:
		if int(stored_cycle["owner"]) != owner:
			continue

		var cycle = stored_cycle["cycle"]

		if not _is_cycle_active(cycle, owner):
			continue

		if not _cycle_has_new_content(owner, cycle):
			continue

		var area := _calculate_cycle_area(cycle)

		if area > largest_area:
			largest_area = area
			largest_cycle.clear()
			largest_cycle.append_array(cycle)

	if largest_cycle.is_empty():
		return false

	_capture_cycle(owner, largest_cycle)
	return true


func _evaluate_all_captures(
	last_player: int
) -> void:
	var other_player := _get_other_player(last_player)
	var maximum_checks := closed_cycles.size() + 1

	# Önce rakibin daha önce kurduğu çevreleri kontrol ediyoruz.
	# Böylece rakip çevresine yapılan "intihar hamlesi"
	# önce yakalanıyor.
	for check in range(maximum_checks):
		if not _evaluate_largest_capture_for_player(
			other_player
		):
			break

	# Sonra hamleyi yapan oyuncunun çevrelerini kontrol ediyoruz.
	for check in range(maximum_checks):
		if not _evaluate_largest_capture_for_player(
			last_player
		):
			break


func _is_position_inside_captured_region(
	grid_position: Vector2i
) -> bool:
	var point_position := Vector2(
		grid_position.x,
		grid_position.y
	)

	for region in captured_regions:
		var cycle = region["cycle"]

		if _is_point_inside_cycle(
			point_position,
			cycle
		):
			return true

	return false

func _get_reachable_positions(player: int) -> Dictionary:
	var reachable: Dictionary = {}
	var positions_to_visit: Array[Vector2i] = [
		Vector2i(-1, -1)
	]
	var current_index := 0

	var directions: Array[Vector2i] = [
		Vector2i(0, -1),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(-1, 0)
	]

	reachable[Vector2i(-1, -1)] = true

	while current_index < positions_to_visit.size():
		var current_position := positions_to_visit[current_index]
		current_index += 1

		for direction in directions:
			var neighbor_position := current_position + direction

			if neighbor_position.x < -1:
				continue

			if neighbor_position.x > COLUMNS:
				continue

			if neighbor_position.y < -1:
				continue

			if neighbor_position.y > ROWS:
				continue

			if reachable.has(neighbor_position):
				continue

			if _is_inside_board(neighbor_position):
				var is_active_player_point: bool = (
					not captured_point_owners.has(neighbor_position)
					and int(
						points.get(neighbor_position, -1)
					) == player
				)

				if is_active_player_point:
					continue

			reachable[neighbor_position] = true
			positions_to_visit.append(neighbor_position)

	return reachable

func _calculate_cycle_area(cycle: Array) -> float:
	if cycle.size() < 3:
		return 0.0

	var double_area := 0.0

	for index in range(cycle.size()):
		var current = cycle[index]
		var next = cycle[(index + 1) % cycle.size()]

		double_area += float(
			current.x * next.y
			- next.x * current.y
		)

	return absf(double_area) * 0.5

func _find_surrounded_opponent_points(
	player: int
) -> Array[Vector2i]:
	var reachable := _get_reachable_positions(player)
	var surrounded_points: Array[Vector2i] = []

	for grid_position in points:
		if int(points[grid_position]) == player:
			continue

		# Daha önce yakalanmış nokta yeni kazanım değildir.
		if captured_point_owners.has(grid_position):
			continue

		if not reachable.has(grid_position):
			surrounded_points.append(grid_position)

	return surrounded_points
	
func _gui_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
	):
		_try_place_point(event.position)

	elif event is InputEventScreenTouch and event.pressed:
		_try_place_point(event.position)

func _try_place_point(local_position: Vector2) -> void:
	var column := roundi(local_position.x / CELL_SIZE)
	var row := roundi(local_position.y / CELL_SIZE)

	if column < 0 or column >= COLUMNS:
		return

	if row < 0 or row >= ROWS:
		return

	var grid_position := Vector2i(column, row)

	if points.has(grid_position):
		return

	# Gerçekten kazanılmış bir alanın içine yeni nokta konulamaz.
	if _is_position_inside_captured_region(grid_position):
		return

	var placed_player := current_player

	points[grid_position] = placed_player
	point_styles[grid_position] = randi()

	# Yeni nokta bir çevre oluşturduysa, içinde henüz rakip
	# olmasa bile bu çevreyi gelecekte kontrol etmek için sakla.
	var new_cycle := _find_cycle_from_new_point(
		grid_position,
		placed_player
	)

	if not new_cycle.is_empty():
		_store_closed_cycle(
			placed_player,
			new_cycle
		)

	# Capture artık son konulan noktaya bağlı değil.
	# Her iki oyuncunun bütün mevcut çevreleri kontrol edilir.
	_evaluate_all_captures(placed_player)

	current_player = _get_other_player(placed_player)
	queue_redraw()
