extends RefCounted

const EPSILON := 0.001


static func calculate_cycle_area(
	cycle: Array
) -> float:
	if cycle.size() < 3:
		return 0.0

	var double_area := 0.0

	for index in range(cycle.size()):
		var current = cycle[index]
		var next = cycle[
			(index + 1) % cycle.size()
		]

		double_area += float(
			current.x * next.y
			- next.x * current.y
		)

	return absf(double_area) * 0.5


static func is_point_inside_cycle(
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


static func is_point_on_cycle_boundary(
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

		if absf(
			edge.cross(point_direction)
		) > EPSILON:
			continue

		var projection := point_direction.dot(edge)

		if projection < -EPSILON:
			continue

		if (
			projection
			> edge.length_squared() + EPSILON
		):
			continue

		return true

	return false


static func is_point_inside_or_on_cycle(
	point: Vector2,
	cycle: Array
) -> bool:
	return (
		is_point_inside_cycle(point, cycle)
		or is_point_on_cycle_boundary(
			point,
			cycle
		)
	)


static func is_cycle_inside_cycle(
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

		if not is_point_inside_or_on_cycle(
			current,
			outer_cycle
		):
			return false

		var edge_middle := (
			current + next
		) * 0.5

		if not is_point_inside_or_on_cycle(
			edge_middle,
			outer_cycle
		):
			return false

	return true


static func cycle_has_repeated_points(
	cycle: Array
) -> bool:
	var visited_positions: Dictionary = {}

	for grid_position in cycle:
		if visited_positions.has(grid_position):
			return true

		visited_positions[grid_position] = true

	return false


static func cross_product(
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


static func segments_cross(
	first_start: Vector2i,
	first_end: Vector2i,
	second_start: Vector2i,
	second_end: Vector2i
) -> bool:
	if (
		first_start == second_start
		or first_start == second_end
		or first_end == second_start
		or first_end == second_end
	):
		return false

	var first_side := cross_product(
		first_start,
		first_end,
		second_start
	)

	var second_side := cross_product(
		first_start,
		first_end,
		second_end
	)

	var third_side := cross_product(
		second_start,
		second_end,
		first_start
	)

	var fourth_side := cross_product(
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


static func cycle_crosses_itself(
	cycle: Array
) -> bool:
	for first_index in range(cycle.size()):
		var first_start = cycle[first_index]
		var first_end = cycle[
			(first_index + 1) % cycle.size()
		]

		for second_index in range(
			first_index + 1,
			cycle.size()
		):
			if second_index == first_index + 1:
				continue

			if (
				first_index == 0
				and second_index
				== cycle.size() - 1
			):
				continue

			var second_start = cycle[second_index]
			var second_end = cycle[
				(second_index + 1) % cycle.size()
			]

			if segments_cross(
				first_start,
				first_end,
				second_start,
				second_end
			):
				return true

	return false
