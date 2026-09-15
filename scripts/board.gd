extends Control

const GameStateScript := preload(
	"res://scripts/game_state.gd"
)

const CaptureDetectorScript := preload(
	"res://scripts/capture_detector.gd"
)

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
const HUD_HEIGHT := 130.0
const HUD_BOARD_GAP := 35.0
const BOARD_TOP := HUD_HEIGHT + HUD_BOARD_GAP

var game_state
var capture_detector

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
	for grid_position in game_state.points:
		var center := Vector2(
			grid_position.x * CELL_SIZE,
			BOARD_TOP + grid_position.y * CELL_SIZE
		)

		var point_color: Color

		if game_state.points[grid_position] == PLAYER_GRAPHITE:
			point_color = GRAPHITE_COLOR
		else:
			point_color = RED_COLOR

		_draw_pencil_point(
			center,
			point_color,
			game_state.point_styles[grid_position]
		)
	_draw_move_indicators()
	_draw_hud()
	
func _draw_captured_regions() -> void:
	for region in game_state.captured_regions:
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
	var grid_position := Vector2i(
		column,
		row
	)

	if not game_state.can_place_point(
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
		"Siyah: %s" % _format_score(game_state.graphite_score),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		HUD_FONT_SIZE,
		GRAPHITE_COLOR
	)

	draw_string(
		font,
		Vector2(420.0, 50.0),
		"Kırmızı: %s" % _format_score(game_state.red_score),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		HUD_FONT_SIZE,
		RED_COLOR
	)

	var current_color: Color
	var current_player_text: String

	if game_state.game_over:
		if game_state.graphite_score > game_state.red_score:
			current_color = GRAPHITE_COLOR
		elif game_state.red_score > game_state.graphite_score:
			current_color = RED_COLOR
		else:
			current_color = HUD_TEXT_COLOR

		current_player_text = (
			game_state.get_game_result_text()
		)
	elif game_state.current_player == PLAYER_GRAPHITE:
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
	if game_state.game_over:
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
	if game_state.game_over:
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

func _try_press_action_button(
	local_position: Vector2
) -> bool:
	if game_state.game_over:
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
		game_state.pass_turn()
		queue_redraw()
		return true

	return false
	
func _restart_game() -> void:
	get_tree().reload_current_scene()

func _ready() -> void:
	capture_detector = CaptureDetectorScript.new(
		COLUMNS,
		ROWS
	)
	
	game_state = GameStateScript.new(
		COLUMNS,
		ROWS
	)

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

	if game_state.current_player == PLAYER_GRAPHITE:
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

	var confirmed_position := pending_position

	if not game_state.can_place_point(
		confirmed_position
	):
		_cancel_pending_move()
		return

	game_state.play_move(
		confirmed_position,
		pending_style_seed
	)

	last_placed_position = confirmed_position
	has_last_move = true

	has_pending_move = false
	pending_position = Vector2i(-1, -1)

	queue_redraw()
	
func _cancel_pending_move() -> void:
	has_pending_move = false
	pending_position = Vector2i(-1, -1)
	queue_redraw()
