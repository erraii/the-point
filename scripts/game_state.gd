extends RefCounted


const GameGeometry := preload(
	"res://scripts/game_geometry.gd"
)

const CaptureDetectorScript := preload(
	"res://scripts/capture_detector.gd"
)

const PLAYER_GRAPHITE := 0
const PLAYER_RED := 1


var current_player := PLAYER_GRAPHITE
var points: Dictionary = {}
var point_styles: Dictionary = {}
var captured_regions: Array = []
var captured_point_owners: Dictionary = {}

var graphite_score := 0.0
var red_score := 0.0
var consecutive_passes := 0
var game_over := false

var columns: int
var rows: int
var capture_detector


func _init(
	board_columns: int,
	board_rows: int
) -> void:
	columns = board_columns
	rows = board_rows

	capture_detector = CaptureDetectorScript.new(
		columns,
		rows
	)


func can_place_point(
	grid_position: Vector2i
) -> bool:
	if game_over:
		return false

	if grid_position.x < 0 or grid_position.x >= columns:
		return false

	if grid_position.y < 0 or grid_position.y >= rows:
		return false

	if points.has(grid_position):
		return false

	if _is_position_inside_captured_region(
		grid_position
	):
		return false

	return true


func play_move(
	grid_position: Vector2i,
	style_seed: int
) -> bool:
	if not can_place_point(grid_position):
		return false

	var placed_player := current_player

	consecutive_passes = 0
	points[grid_position] = placed_player
	point_styles[grid_position] = style_seed

	var closed_cycles := _find_closed_cycles()
	var capture_happened := _evaluate_all_captures(
		placed_player,
		closed_cycles
	)

	current_player = _get_other_player(
		placed_player
	)

	return capture_happened


func pass_turn() -> void:
	if game_over:
		return

	consecutive_passes += 1

	if consecutive_passes >= 2:
		game_over = true
		return

	current_player = _get_other_player(
		current_player
	)


func get_game_result_text() -> String:
	if is_equal_approx(
		graphite_score,
		red_score
	):
		return "Berabere"

	if graphite_score > red_score:
		return "Siyah kazandı"

	return "Kırmızı kazandı"


func _get_other_player(player: int) -> int:
	if player == PLAYER_GRAPHITE:
		return PLAYER_RED

	return PLAYER_GRAPHITE


func _find_closed_cycles() -> Array:
	var closed_cycles: Array = []

	var players: Array[int] = [
		PLAYER_GRAPHITE,
		PLAYER_RED
	]

	for player in players:
		var player_cycles: Array = (
			capture_detector.find_closed_regions(
				points,
				captured_point_owners,
				player
			)
		)

		for cycle in player_cycles:
			closed_cycles.append(
				{
					"owner": player,
					"cycle": cycle.duplicate()
				}
			)

	return closed_cycles


func _is_cycle_active(
	cycle: Array,
	owner: int
) -> bool:
	for grid_position in cycle:
		if captured_point_owners.has(
			grid_position
		):
			return false

		if int(
			points.get(grid_position, -1)
		) != owner:
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

		if not GameGeometry.is_point_inside_cycle(
			point_position,
			cycle
		):
			continue

		if captured_point_owners.has(
			grid_position
		):
			if int(
				captured_point_owners[
					grid_position
				]
			) != owner:
				return true

		elif int(points[grid_position]) != owner:
			return true

	return false


func _remove_regions_inside_cycle(
	new_cycle: Array
) -> void:
	var new_area := (
		GameGeometry.calculate_cycle_area(
			new_cycle
		)
	)

	for region_index in range(
		captured_regions.size() - 1,
		-1,
		-1
	):
		var old_cycle = (
			captured_regions[region_index]["cycle"]
		)

		var old_area := (
			GameGeometry.calculate_cycle_area(
				old_cycle
			)
		)

		if (
			old_area
			> new_area
			+ GameGeometry.EPSILON
		):
			continue

		if GameGeometry.is_cycle_inside_cycle(
			old_cycle,
			new_cycle
		):
			captured_regions.remove_at(
				region_index
			)


func _capture_cycle(
	owner: int,
	cycle: Array
) -> void:
	for grid_position in points:
		if cycle.has(grid_position):
			continue

		var point_position := Vector2(
			grid_position.x,
			grid_position.y
		)

		if GameGeometry.is_point_inside_cycle(
			point_position,
			cycle
		):
			captured_point_owners[
				grid_position
			] = owner

	_remove_regions_inside_cycle(cycle)

	captured_regions.append(
		{
			"owner": owner,
			"cycle": cycle.duplicate(),
			"style_seed": randi()
		}
	)


func _evaluate_largest_capture_for_player(
	owner: int,
	closed_cycles: Array
) -> bool:
	var largest_cycle: Array = []
	var largest_area := 0.0

	for stored_cycle in closed_cycles:
		if int(stored_cycle["owner"]) != owner:
			continue

		var cycle = stored_cycle["cycle"]

		if not _is_cycle_active(cycle, owner):
			continue

		if not _cycle_has_new_content(
			owner,
			cycle
		):
			continue

		var area := (
			GameGeometry.calculate_cycle_area(
				cycle
			)
		)

		if area > largest_area:
			largest_area = area
			largest_cycle.clear()
			largest_cycle.append_array(cycle)

	if largest_cycle.is_empty():
		return false

	_capture_cycle(owner, largest_cycle)
	return true


func _evaluate_all_captures(
	last_player: int,
	closed_cycles: Array
) -> bool:
	var other_player := _get_other_player(
		last_player
	)

	var maximum_checks := (
		closed_cycles.size() + 1
	)

	var capture_happened := false

	for check in range(maximum_checks):
		if not _evaluate_largest_capture_for_player(
			last_player,
			closed_cycles
		):
			break

		capture_happened = true

	for check in range(maximum_checks):
		if not _evaluate_largest_capture_for_player(
			other_player,
			closed_cycles
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
		if GameGeometry.is_point_inside_cycle(
			point_position,
			region["cycle"]
		):
			return true

	return false


func _recalculate_scores() -> void:
	graphite_score = 0.0
	red_score = 0.0

	for region in captured_regions:
		var owner := int(region["owner"])

		var region_area := (
			GameGeometry.calculate_cycle_area(
				region["cycle"]
			)
		)

		if owner == PLAYER_GRAPHITE:
			graphite_score += region_area
		else:
			red_score += region_area
