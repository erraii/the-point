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


var current_player := PLAYER_GRAPHITE
var points: Dictionary = {}
var point_styles: Dictionary = {}


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

	points[grid_position] = current_player
	point_styles[grid_position] = randi()

	if current_player == PLAYER_GRAPHITE:
		current_player = PLAYER_RED
	else:
		current_player = PLAYER_GRAPHITE

	queue_redraw()
