Entity :: struct {
    using position : Vector2;
    velocity : Vector2;

    map: *Texture;
}

Direction :: enum u8 {
    DOWN :: 0;
    LEFT :: 1;
    RIGHT :: 2;
    UP :: 3;
}

Dir :: struct {
    dx: s32;
    dy: s32;
}

Queue_Entry :: struct {
    x, y, dist: s32;
}

Player_Stats :: struct {
    max_health: float = 100.0;
    current_health: float = 100.0;

    speed: float = 80.0;
    attack_power: float = 10.0;
    defense: float = 5.0;

    experience: s64 = 0;
    level: s32 = 1;

    gold: s64 = 0;
    gems: s64 = 0;
}

Player :: struct {
    using entity: Entity;

    stats: Player_Stats;

    direction: Direction = .DOWN;

    is_moving: bool = false;
    animation_time: float = 0;
    animation_frame: s32 = 0;

    is_interacting: bool = false;

    path_status: Path_Status = .IDLE;
    path: [..] Vector2;
    current_path_index: s32 = 0;
    movement_speed: float = 80.0;
}

player: Player;

Path_Node :: struct {
    x, y: s32;
    f, g, h: float;
    parent: *Path_Node;
}

Path_Status :: enum {
    IDLE;
    SELECTING;
    MOVING;
}

init_player :: () {
    player.position = .{LOGICAL_WIDTH / 2, LOGICAL_HEIGHT / 2};
    player.velocity = .{0, 0};
    player.map = *path;

    player.stats.current_health = player.stats.max_health;
    player.movement_speed = player.stats.speed;

    array_reset(*player.path);

    player.path_status = .IDLE;
    player.current_path_index = 0;

    level := get_current_level();
    if level {
        player.position = level.spawn_point;
    }

    print("Player initialized at (%, %)\n", player.position.x, player.position.y);
}

deinit_player :: () {
    array_free(player.path);
}

update_player :: (dt: float) {
    if player.path_status == .MOVING {
        if player.current_path_index < player.path.count {
            target := player.path[player.current_path_index];

            direction := target - player.position;
            distance := length(direction);

            if distance < 1.0 {
                player.current_path_index += 1;

                if player.current_path_index < player.path.count {
                    next_target := player.path[player.current_path_index];
                    dir := unit_vector(next_target - player.position);

                    if abs(dir.x) > abs(dir.y) {
                        if dir.x > 0 player.direction = .RIGHT;
                        else player.direction = .LEFT;
                    } else {
                        if dir.y > 0 player.direction = .UP;
                        else player.direction = .DOWN;
                    }
                }
            } else {
                move_direction := unit_vector(direction);
                move_distance := min(player.movement_speed * dt, distance);
                player.position += move_direction * move_distance;

                player.is_moving = true;
                player.animation_time += dt;
                if player.animation_time > 0.2 {
                    player.animation_time = 0;
                    player.animation_frame = (player.animation_frame + 1) % 4;
                }
            }
        } else {
            player.path_status = .IDLE;
            player.is_moving = false;
            array_free(player.path);
        }
    } else {
        player.is_moving = false;
        player.animation_frame = 0;
    }

    mouse_x, mouse_y := get_mouse_pointer_position();
    mouse_pos := Vector2.{cast(float)mouse_x, cast(float)(window_height - mouse_y)};

    for event: events_this_frame {
        if event.type == .KEYBOARD {
            if event.key_code == .MOUSE_BUTTON_LEFT && event.key_pressed {
                if player.path_status == .IDLE {
                    if is_mouse_over_player(mouse_pos) {
                        player.path_status = .SELECTING;
                        print("Player selected\n");
                    }
                } else if player.path_status == .SELECTING {
                    world_pos := absolute_coords_from_window(mouse_pos);
                    grid_x, grid_y := pixel_to_grid(*tile_system, world_pos.x, world_pos.y);

                    if is_position_walkable(*tile_system, grid_x, grid_y) {
                        player_grid_x, player_grid_y := pixel_to_grid(*tile_system, player.position.x, player.position.y);

                        path := find_path(player_grid_x, player_grid_y, grid_x, grid_y);

                        if path.count > 0 {
                            array_free(player.path);
                            player.path = path;
                            player.current_path_index = 0;
                            player.path_status = .MOVING;
                            print("Moving to (%, %)\n", grid_x, grid_y);
                        } else {
                            print("No path found\n");
                            player.path_status = .IDLE;
                        }
                    } else {
                        player.path_status = .IDLE;
                    }
                }
            } else if event.key_code == .MOUSE_BUTTON_RIGHT && event.key_pressed {
                if player.path_status == .SELECTING {
                    player.path_status = .IDLE;
                    print("Selection canceled\n");
                }
            }
        }
    }
}

render_player :: () {
    render_player_path();
    render_available_moves();

    screen_pos := window_coords_from_absolute(player.position);

    center_pos := window_coords_from_absolute(.{LOGICAL_WIDTH/2, LOGICAL_HEIGHT/2});
    draw_circle_at(center_pos, 5, 16, .{1, 0, 0, 1});

    player_radius := tile_system.tile_width * 0.4 * scale_factor;

    Simp.set_shader_for_color();
    draw_circle_at(screen_pos, player_radius * 1.5, 32, .{1, 1, 1, 0.5});

    circle_color: Vector4;
    if player.direction == {
        case .DOWN;  circle_color = .{0, 0.7, 0.9, 1};  // Teal
        case .LEFT;  circle_color = .{0.9, 0.7, 0, 1};  // Orange
        case .RIGHT; circle_color = .{0, 0.9, 0.2, 1};  // Green
        case .UP;    circle_color = .{0.9, 0.2, 0.7, 1};  // Pink
    }

    if player.path_status == .SELECTING {
        Simp.set_shader_for_color();
        draw_circle_at(screen_pos, player_radius * 1.2, 32, .{1, 1, 0.5, 0.5});
    }

    draw_circle_at(screen_pos, player_radius, 32, circle_color);

    direction_marker := screen_pos;
    marker_size := player_radius * 0.5;

    if player.direction == {
        case .DOWN;  direction_marker.y -= player_radius * 0.6;
        case .LEFT;  direction_marker.x -= player_radius * 0.6;
        case .RIGHT; direction_marker.x += player_radius * 0.6;
        case .UP;    direction_marker.y += player_radius * 0.6;
    }

    draw_circle_at(direction_marker, marker_size, 16, .{1, 1, 1, 1});
}

draw_circle_at :: (center: Vector2, r: float, N: s32, color: Vector4) {
    if !N return;

    Simp.set_shader_for_color();

    dtheta := TAU / N;
    p0 := Vector3.{center.x, center.y, 0};

    for i: 0..N-1 {
        theta0 := dtheta * i;
        theta1 := dtheta * (i+1);

        ct0 := cos(theta0);
        st0 := sin(theta0);
        ct1 := cos(theta1);
        st1 := sin(theta1);

        p1 := Vector3.{center.x + ct0 * r, center.y + st0 * r, 0};
        p2 := Vector3.{center.x + ct1 * r, center.y + st1 * r, 0};

        Simp.immediate_triangle(p0, p1, p2, color, color, color);
    }
}

is_mouse_over_player :: (mouse_pos: Vector2) -> bool {
    player_pos := window_coords_from_absolute(player.position);
    player_radius := tile_system.tile_width * 0.4 * scale_factor;

    return distance(mouse_pos, player_pos) < player_radius;
}

get_available_moves :: (grid_x: s32, grid_y: s32, max_distance: s32 = 5) -> [..] Vector2 {
    moves: [..] Vector2;

    visited: Table(s64, bool);
    queue: [..] Queue_Entry;
    queue.allocator = temp;

    enqueue :: (queue: *[..] Queue_Entry, x: s32, y: s32, dist: s32) {
        entry: Queue_Entry;
        entry.x = x;
        entry.y = y;
        entry.dist = dist;
        array_add(queue, entry);
    }

    enqueue(*queue, grid_x, grid_y, 0);

    encode_pos :: (x: s32, y: s32) -> s64 {
        return (cast(s64)x << 32) | (cast(s64)y & 0xFFFFFFFF);
    }

    while queue.count > 0 {
        current := queue[0];
        array_ordered_remove_by_index(*queue, 0);

        key := encode_pos(current.x, current.y);
        if table_contains(*visited, key) continue;
        table_set(*visited, key, true);

        if !(current.x == grid_x && current.y == grid_y) {
            pixel_x, pixel_y := grid_to_pixel(*tile_system, current.x, current.y);
            array_add(*moves, Vector2.{pixel_x, pixel_y});
        }

        if current.dist >= max_distance continue;

        directions: [4]Dir;
        directions[0] = .{1, 0};
        directions[1] = .{-1, 0};
        directions[2] = .{0, 1};
        directions[3] = .{0, -1};

        for dir: directions {
            next_x := current.x + dir.dx;
            next_y := current.y + dir.dy;

            if is_position_walkable(*tile_system, next_x, next_y) {
                enqueue(*queue, next_x, next_y, current.dist + 1);
            }
        }
    }

    return moves;
}

find_path :: (start_x: s32, start_y: s32, end_x: s32, end_y: s32) -> [..] Vector2 {
    result: [..] Vector2;
    all_nodes: [..] *Path_Node;

    defer {
        for node: all_nodes {
            free(node);
        }
        array_free(all_nodes);
    }

    if start_x == end_x && start_y == end_y return result;

    encode_pos :: (x: s32, y: s32) -> s64 {
        return (cast(s64)x << 32) | (cast(s64)y & 0xFFFFFFFF);
    }

    heuristic :: (x1: s32, y1: s32, x2: s32, y2: s32) -> float {
        return cast(float)(abs(x2 - x1) + abs(y2 - y1));
    }

    open_set: [..] *Path_Node;
    closed_set: Table(s64, bool);
    nodes: Table(s64, *Path_Node);

    start_node := New(Path_Node);
    array_add(*all_nodes, start_node);

    start_node.x = start_x;
    start_node.y = start_y;
    start_node.g = 0;
    start_node.h = heuristic(start_x, start_y, end_x, end_y);
    start_node.f = start_node.g + start_node.h;
    start_node.parent = null;

    array_add(*open_set, start_node);
    table_set(*nodes, encode_pos(start_x, start_y), start_node);

    while open_set.count > 0 {
        current_index := 0;
        for open_set {
            if it.f < open_set[current_index].f {
                current_index = it_index;
            }
        }

        current := open_set[current_index];
        array_ordered_remove_by_index(*open_set, current_index);

        table_set(*closed_set, encode_pos(current.x, current.y), true);

        if current.x == end_x && current.y == end_y {
            node := current;
            while node {
                pixel_x, pixel_y := grid_to_pixel(*tile_system, node.x, node.y);
                array_insert_at(*result, Vector2.{pixel_x, pixel_y}, 0);
                node = node.parent;
            }

            array_free(open_set);
            return result;
        }

        directions: [4]Dir;
        directions[0] = .{1, 0};
        directions[1] = .{-1, 0};
        directions[2] = .{0, 1};
        directions[3] = .{0, -1};

        for dir: directions {
            neighbor_x := current.x + dir.dx;
            neighbor_y := current.y + dir.dy;

            if !is_position_walkable(*tile_system, neighbor_x, neighbor_y) continue;
            if table_contains(*closed_set, encode_pos(neighbor_x, neighbor_y)) continue;

            tentative_g := current.g + 1.0;

            found_node, found_success := table_find(*nodes, encode_pos(neighbor_x, neighbor_y));

            if !found_success || tentative_g < found_node.g {
                neighbor: *Path_Node;
                if found_success {
                    neighbor = found_node;
                } else {
                    neighbor = New(Path_Node);
                    array_add(*all_nodes, neighbor);

                    neighbor.x = neighbor_x;
                    neighbor.y = neighbor_y;
                    table_set(*nodes, encode_pos(neighbor_x, neighbor_y), neighbor);
                }

                neighbor.parent = current;
                neighbor.g = tentative_g;
                neighbor.h = heuristic(neighbor_x, neighbor_y, end_x, end_y);
                neighbor.f = neighbor.g + neighbor.h;

                found_in_open := false;
                for open_set {
                    if it.x == neighbor.x && it.y == neighbor.y {
                        found_in_open = true;
                        break;
                    }
                }

                if !found_in_open {
                    array_add(*open_set, neighbor);
                }
            }
        }
    }

    array_free(open_set);
    return result;
}

render_available_moves :: () {
    if player.path_status != .SELECTING return;

    player_grid_x, player_grid_y := pixel_to_grid(*tile_system, player.position.x, player.position.y);
    available_moves := get_available_moves(player_grid_x, player_grid_y);

    Simp.set_shader_for_color();

    for move: available_moves {
        pos := window_coords_from_absolute(move);
        tile_radius := tile_system.tile_width * 0.4 * scale_factor;

        draw_circle_at(pos, tile_radius, 16, Vector4.{0.2, 0.8, 0.3, 0.5});
    }

    array_free(available_moves);
}

render_player_path :: () {
    if player.path_status != .MOVING || player.path.count <= 1 return;

    Simp.set_shader_for_color();

    for i: 0..player.path.count-2 {
        start_pos := window_coords_from_absolute(player.path[i]);
        end_pos := window_coords_from_absolute(player.path[i+1]);

        dir := end_pos - start_pos;
        length := sqrt(dir.x * dir.x + dir.y * dir.y);

        if length < 0.0001 continue;

        dir.x /= length;
        dir.y /= length;

        thickness := 2.0;
        perp := Vector2.{-dir.y, dir.x} * (thickness * 0.5);

        p1 := Vector2.{start_pos.x + perp.x, start_pos.y + perp.y};
        p2 := Vector2.{start_pos.x - perp.x, start_pos.y - perp.y};
        p3 := Vector2.{end_pos.x - perp.x, end_pos.y - perp.y};
        p4 := Vector2.{end_pos.x + perp.x, end_pos.y + perp.y};

        Simp.immediate_quad(p1, p2, p3, p4, Vector4.{0.8, 0.6, 0.2, 0.7});

        draw_circle_at(start_pos, 3, 8, Vector4.{0.8, 0.6, 0.2, 0.7});
    }

    if player.path.count > 0 {
        end_pos := window_coords_from_absolute(player.path[player.path.count-1]);
        draw_circle_at(end_pos, 5, 8, Vector4.{1.0, 0.8, 0.3, 0.8});
    }
}