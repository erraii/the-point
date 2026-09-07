extends Control


const COLUMNS := 15
const ROWS := 21
const CELL_SIZE := 60.0

const PLAYER_GRAPHITE := 0
const PLAYER_RED := 1

const GRID_COLOR := Color(0.36, 0.55, 0.65, 0.38)
const GRAPHITE_COLOR := Color(0.10, 0.10, 0.11, 1.0)
const RED_COLOR := Color(0.90, 0.10, 0.06, 1.0)
const HUD_BACKGROUND_COLOR := Color(1.0, 1.0, 1.0, 0.90)
const HUD_TEXT_COLOR := Color(0.12, 0.12, 0.13, 1.0)
const HUD_FONT_SIZE := 34

const GRID_WIDTH := 2.0
const POINT_STROKES := 9
const MAX_FACE_WALK_STEPS := COLUMNS * ROWS * 8
const HUD_HEIGHT := 130.0
const HUD_BOARD_GAP := 35.0
const BOARD_TOP := HUD_HEIGHT + HUD_BOARD_GAP
const GEOMETRY_EPSILON := 0.001

var current_player := PLAYER_GRAPHITE
var points: Dictionary = {}
var point_styles: Dictionary = {}
var captured_regions: Array = []
var captured_point_owners: Dictionary = {}
var closed_cycles: Array = []
var graphite_score := 0.0
var red_score := 0.0
var consecutive_passes := 0
var game_over := false

var pending_position := Vector2i(-1, -1)
var pending_style_seed := 0
var has_pending_move := false

var last_placed_position := Vector2i(-1, -1)
var has_last_move := false

func _draw() -> void:
	var board_width := (COLUMNS - 1) * CELL_SIZE
	var board_height := (ROWS - 1) * CELL_SIZE

	for column in range(COLUMNS):
		var x := column * CELL_SIZE
		draw_line(
			Vector2(x, BOARD_TOP),
			Vector2(x, BOARD_TOP + board_height),
			GRID_COLOR,
			GRID_WIDTH,
			true
		)

	for row in range(ROWS):
		var y := BOARD_TOP + row * CELL_SIZE
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
			BOARD_TOP + grid_position.y * CELL_SIZE
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
	_draw_move_indicators()
	_draw_hud()
	
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
					BOARD_TOP + grid_position.y * CELL_SIZE
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

func _is_active_player_point(
	grid_position: Vector2i,
	player: int
) -> bool:
	return (
		_is_inside_board(grid_position)
		and not captured_point_owners.has(grid_position)
		and int(points.get(grid_position, -1)) == player
	)


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

			# Karenin dört köşesi de aynı renkteyse,
			# çapraz çizgiler yerine dış kareyi kullan.
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

func _cycle_has_repeated_points(
	cycle: Array
) -> bool:
	var visited_positions: Dictionary = {}

	for grid_position in cycle:
		if visited_positions.has(grid_position):
			return true

		visited_positions[grid_position] = true

	return false

func _find_closed_regions_for_player(
	player: int
) -> Array:
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

func _rebuild_closed_cycles() -> void:
	closed_cycles.clear()

	var players: Array[int] = [
		PLAYER_GRAPHITE,
		PLAYER_RED
	]

	for player in players:
		var player_cycles := (
			_find_closed_regions_for_player(player)
		)

		for cycle in player_cycles:
			closed_cycles.append(
				{
					"owner": player,
					"cycle": cycle.duplicate()
				}
			)

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
	var new_area := _calculate_cycle_area(
		new_cycle
	)

	for region_index in range(
		captured_regions.size() - 1,
		-1,
		-1
	):
		var old_cycle = (
			captured_regions[region_index]["cycle"]
		)

		var old_area := _calculate_cycle_area(
			old_cycle
		)

		if (
			old_area
			> new_area
			+ GEOMETRY_EPSILON
		):
			continue

		if _is_cycle_inside_cycle(
			old_cycle,
			new_cycle
		):
			captured_regions.remove_at(
				region_index
			)
			
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
) -> bool:
	var other_player := _get_other_player(last_player)
	var maximum_checks := closed_cycles.size() + 1
	var capture_happened := false

	# Öncelik hamleyi yapan oyuncudadır.
	for check in range(maximum_checks):
		if not _evaluate_largest_capture_for_player(
			last_player
		):
			break

		capture_happened = true

	# Ardından rakibin hâlâ geçerli olan çevrelerini kontrol et.
	for check in range(maximum_checks):
		if not _evaluate_largest_capture_for_player(
			other_player
		):
			break

		capture_happened = true

	if capture_happened:
		_recalculate_scores()

	return capture_happened
	
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

func _recalculate_scores() -> void:
	graphite_score = 0.0
	red_score = 0.0

	for region in captured_regions:
		var owner := int(region["owner"])
		var cycle = region["cycle"]
		var region_area := _calculate_cycle_area(cycle)

		if owner == PLAYER_GRAPHITE:
			graphite_score += region_area
		else:
			red_score += region_area
	
func _gui_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
	):
		if _try_press_action_button(event.position):
			return

		_try_place_point(event.position)

	elif (
		event is InputEventScreenTouch
		and event.pressed
	):
		if _try_press_action_button(event.position):
			return

		_try_place_point(event.position)

func _try_place_point(local_position: Vector2) -> void:
	var board_position := (
		local_position - Vector2(0.0, BOARD_TOP)
	)

	if board_position.y < 0.0:
		return

	var column := roundi(
		board_position.x / CELL_SIZE
	)

	var row := roundi(
		board_position.y / CELL_SIZE
	)
	if game_over:
		return
		
	if column < 0 or column >= COLUMNS:
		return

	if row < 0 or row >= ROWS:
		return

	var grid_position := Vector2i(column, row)

	if points.has(grid_position):
		return

	if _is_position_inside_captured_region(
		grid_position
	):
		return

	pending_position = grid_position
	pending_style_seed = randi()
	has_pending_move = true

	queue_redraw()
	
func _format_score(score: float) -> String:
	if is_equal_approx(score, roundf(score)):
		return str(int(round(score)))

	return String.num(score, 1)


func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	var panel_rectangle := Rect2(
		Vector2(0.0, 0.0),
		Vector2(
			(COLUMNS - 1) * CELL_SIZE,
			HUD_HEIGHT
		)
	)
	draw_rect(
		panel_rectangle,
		HUD_BACKGROUND_COLOR,
		true
	)

	draw_rect(
		panel_rectangle,
		Color(0.25, 0.25, 0.25, 0.35),
		false,
		2.0
	)

	draw_string(
		font,
		Vector2(30.0, 50.0),
		"Siyah: %s" % _format_score(graphite_score),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		HUD_FONT_SIZE,
		GRAPHITE_COLOR
	)

	draw_string(
		font,
		Vector2(420.0, 50.0),
		"Kırmızı: %s" % _format_score(red_score),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		HUD_FONT_SIZE,
		RED_COLOR
	)

	var current_color: Color
	var current_player_text: String

	if game_over:
		if graphite_score > red_score:
			current_color = GRAPHITE_COLOR
		elif red_score > graphite_score:
			current_color = RED_COLOR
		else:
			current_color = HUD_TEXT_COLOR

		current_player_text = _get_game_result_text()
	elif current_player == PLAYER_GRAPHITE:
		current_color = GRAPHITE_COLOR
		current_player_text = "Sıra: Siyah"

	else:
		current_color = RED_COLOR
		current_player_text = "Sıra: Kırmızı"
		
	draw_circle(
		Vector2(34.0, 98.0),
		10.0,
		current_color
	)

	draw_string(
		font,
		Vector2(58.0, 109.0),
		current_player_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		HUD_FONT_SIZE,
		HUD_TEXT_COLOR
	)
	
	_draw_action_buttons()

func _get_pass_button_rectangle() -> Rect2:
	if game_over:
		return Rect2(
			Vector2(720.0, 68.0),
			Vector2(70.0, 52.0)
		)

	return Rect2(
		Vector2(650.0, 72.0),
		Vector2(140.0, 45.0)
	)
	
func _draw_button(
	button_rectangle: Rect2,
	text: String,
	background_color: Color,
	font_size: int = 26
) -> void:
	var font := ThemeDB.fallback_font

	draw_rect(
		button_rectangle,
		background_color,
		true
	)

	draw_rect(
		button_rectangle,
		Color(0.15, 0.15, 0.15, 0.65),
		false,
		2.0
	)

	var text_height := font.get_height(font_size)

	draw_string(
		font,
		Vector2(
			button_rectangle.position.x,
			button_rectangle.position.y
			+ (
				button_rectangle.size.y
				+ text_height
			) * 0.5
			- 4.0
		),
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		button_rectangle.size.x,
		font_size,
		Color.WHITE
	)

func _draw_action_buttons() -> void:
	if game_over:
		_draw_button(
			_get_pass_button_rectangle(),
			"↻",
			Color(0.20, 0.50, 0.30, 1.0),
			36
		)
		return

	if has_pending_move:
		_draw_button(
			_get_cancel_button_rectangle(),
			"×",
			Color(0.45, 0.45, 0.45, 1.0),
			34
		)

		_draw_button(
			_get_confirm_button_rectangle(),
			"✓",
			Color(0.20, 0.55, 0.30, 1.0),
			32
		)
		return

	_draw_button(
		_get_pass_button_rectangle(),
		"Pas",
		Color(0.34, 0.43, 0.48, 1.0)
	)

func _get_game_result_text() -> String:
	if is_equal_approx(graphite_score, red_score):
		return "Berabere"

	if graphite_score > red_score:
		return "Siyah kazandı"

	return "Kırmızı kazandı"

func _finish_game() -> void:
	game_over = true
	queue_redraw()
	
func _pass_turn() -> void:
	if game_over:
		return

	consecutive_passes += 1

	if consecutive_passes >= 2:
		_finish_game()
		return

	current_player = _get_other_player(current_player)
	queue_redraw()

func _try_press_action_button(
	local_position: Vector2
) -> bool:
	if game_over:
		if _get_pass_button_rectangle().has_point(
			local_position
		):
			_restart_game()
			return true

		return false

	if has_pending_move:
		if _get_cancel_button_rectangle().has_point(
			local_position
		):
			_cancel_pending_move()
			return true

		if _get_confirm_button_rectangle().has_point(
			local_position
		):
			_confirm_pending_move()
			return true

		return false

	if _get_pass_button_rectangle().has_point(
		local_position
	):
		_pass_turn()
		return true

	return false
	
func _restart_game() -> void:
	get_tree().reload_current_scene()

func _ready() -> void:
	custom_minimum_size = Vector2(
		(COLUMNS - 1) * CELL_SIZE,
		BOARD_TOP + (ROWS - 1) * CELL_SIZE
	)

func _get_point_center(
	grid_position: Vector2i
) -> Vector2:
	return Vector2(
		grid_position.x * CELL_SIZE,
		BOARD_TOP + grid_position.y * CELL_SIZE
	)


func _draw_move_indicators() -> void:
	if has_last_move:
		draw_circle(
			_get_point_center(last_placed_position),
			15.0,
			Color(0.15, 0.45, 0.75, 0.75),
			false,
			3.0,
			true
		)

	if not has_pending_move:
		return

	var pending_color: Color

	if current_player == PLAYER_GRAPHITE:
		pending_color = GRAPHITE_COLOR
	else:
		pending_color = RED_COLOR

	var center := _get_point_center(
		pending_position
	)

	_draw_pencil_point(
		center,
		pending_color,
		pending_style_seed
	)

	draw_circle(
		center,
		19.0,
		pending_color,
		false,
		4.0,
		true
	)

func _get_cancel_button_rectangle() -> Rect2:
	return Rect2(
		Vector2(580.0, 72.0),
		Vector2(95.0, 45.0)
	)


func _get_confirm_button_rectangle() -> Rect2:
	return Rect2(
		Vector2(695.0, 72.0),
		Vector2(95.0, 45.0)
	)
	
func _confirm_pending_move() -> void:
	if not has_pending_move:
		return

	var grid_position := pending_position
	var placed_player := current_player

	consecutive_passes = 0

	points[grid_position] = placed_player
	point_styles[grid_position] = pending_style_seed

	last_placed_position = grid_position
	has_last_move = true

	has_pending_move = false
	pending_position = Vector2i(-1, -1)

	_rebuild_closed_cycles()

	var capture_happened := (
		_evaluate_all_captures(placed_player)
	)

	# Capture sonrasında bazı noktalar pasifleştiği için
	# yalnızca o zaman çevreleri tekrar oluşturuyoruz.
	if capture_happened:
		_rebuild_closed_cycles()

	current_player = _get_other_player(
		placed_player
	)

	queue_redraw()
	
func _cancel_pending_move() -> void:
	has_pending_move = false
	pending_position = Vector2i(-1, -1)
	queue_redraw()
	
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

	var current_time := int(search_state["time"])

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

			# Bu bağlantının altında bağımsız bir
			# kapalı döngü grubu tamamlandı.
			if int(low[neighbor]) >= int(
				discovery[current]
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
					search_state["components"] = components

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

	for step in range(MAX_FACE_WALK_STEPS):
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

			if _cycle_has_repeated_points(
				candidate_cycle
			):
				continue

			if _cycle_crosses_itself(
				candidate_cycle
			):
				continue

			var candidate_area := (
				_calculate_cycle_area(
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
	
func _is_point_on_cycle_boundary(
	point: Vector2,
	cycle: Array
) -> bool:
	for index in range(cycle.size()):
		var first := Vector2(
			cycle[index].x,
			cycle[index].y
		)

		var next_index := (
			index + 1
		) % cycle.size()

		var second := Vector2(
			cycle[next_index].x,
			cycle[next_index].y
		)

		var edge := second - first
		var point_direction := point - first

		if absf(edge.cross(point_direction)) > GEOMETRY_EPSILON:
			continue

		var projection := point_direction.dot(edge)

		if projection < -GEOMETRY_EPSILON:
			continue

		if (
			projection
			> edge.length_squared()
			+ GEOMETRY_EPSILON
		):
			continue

		return true

	return false
	
func _is_point_inside_or_on_cycle(
	point: Vector2,
	cycle: Array
) -> bool:
	return (
		_is_point_inside_cycle(point, cycle)
		or _is_point_on_cycle_boundary(
			point,
			cycle
		)
	)
	
func _is_cycle_inside_cycle(
	inner_cycle: Array,
	outer_cycle: Array
) -> bool:
	for index in range(inner_cycle.size()):
		var current := Vector2(
			inner_cycle[index].x,
			inner_cycle[index].y
		)

		var next_index := (
			index + 1
		) % inner_cycle.size()

		var next := Vector2(
			inner_cycle[next_index].x,
			inner_cycle[next_index].y
		)

		if not _is_point_inside_or_on_cycle(
			current,
			outer_cycle
		):
			return false

		# Kenarın ortasını da kontrol ediyoruz.
		# Bu, girintili dış bölgelerde daha güvenlidir.
		var edge_middle := (
			current + next
		) * 0.5

		if not _is_point_inside_or_on_cycle(
			edge_middle,
			outer_cycle
		):
			return false

	return true
	
