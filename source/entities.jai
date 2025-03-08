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
}

player: Player;

init_player :: () {
    player.position = .{LOGICAL_WIDTH / 2, LOGICAL_HEIGHT / 2};
    player.velocity = .{0, 0};
    player.map = *path;

    player.stats.current_health = player.stats.max_health;

    level := get_current_level();
    if level {
        player.position = level.spawn_point;
    }

    print("Player initialized at (%, %)\n", player.position.x, player.position.y);
}

update_player :: (dt: float) {
    move_dir: Vector2;
    if key_left > 0  move_dir.x -= 1;
    if key_right > 0 move_dir.x += 1;
    if key_down > 0  move_dir.y -= 1;
    if key_up > 0    move_dir.y += 1;

    if move_dir.x != 0 || move_dir.y != 0 {
        if abs(move_dir.x) > abs(move_dir.y) {
            if move_dir.x > 0 player.direction = .RIGHT;
            else player.direction = .LEFT;
        } else {
            if move_dir.y > 0 player.direction = .UP;
            else player.direction = .DOWN;
        }
    }

    if (move_dir.x != 0) && (move_dir.y != 0) {
        move_dir = unit_vector(move_dir);
    }

    player.is_moving = (move_dir.x != 0) || (move_dir.y != 0);

    if player.is_moving {
        player.animation_time += dt;
        if player.animation_time > 0.2 {
            player.animation_time = 0;
            player.animation_frame = (player.animation_frame + 1) % 4;
        }
    } else {
        player.animation_frame = 0;
    }

    desired_position := player.position + move_dir * player.stats.speed * dt;

    tile_x, tile_y := pixel_to_grid(*tile_system, desired_position.x, desired_position.y);

    if is_position_walkable(*tile_system, tile_x, tile_y) {
        player.position = desired_position;
    } else {
        x_only := player.position;
        x_only.x = desired_position.x;

        tile_x, tile_y = pixel_to_grid(*tile_system, x_only.x, x_only.y);
        if is_position_walkable(*tile_system, tile_x, tile_y) {
            player.position = x_only;
        } else {
            y_only := player.position;
            y_only.y = desired_position.y;

            tile_x, tile_y = pixel_to_grid(*tile_system, y_only.x, y_only.y);
            if is_position_walkable(*tile_system, tile_x, tile_y) {
                player.position = y_only;
            }
        }
    }
}

render_player :: () {
    // First, let's print the player's position to understand where it is
    print("Player position: (%, %), playfield: %x%, logical: %x%\n",
          player.position.x, player.position.y,
          playfield_width, playfield_height,
          LOGICAL_WIDTH, LOGICAL_HEIGHT);

    // Method 1: Direct approach using absolute coordinates
    screen_pos := window_coords_from_absolute(player.position);

    // For debugging: Also draw a circle at the center of the screen
    center_pos := window_coords_from_absolute(.{LOGICAL_WIDTH/2, LOGICAL_HEIGHT/2});
    draw_circle_at(center_pos, 5, 16, .{1, 0, 0, 1});  // Red circle at center

    player_radius := tile_system.tile_width * 0.4 * scale_factor;

    // Draw a larger, semi-transparent circle to make it more visible for debugging
    Simp.set_shader_for_color();
    draw_circle_at(screen_pos, player_radius * 1.5, 32, .{1, 1, 1, 0.5});

    // Draw the colored player circle
    circle_color: Vector4;
    if player.direction == {
        case .DOWN;  circle_color = .{0, 0.7, 0.9, 1};  // Teal
        case .LEFT;  circle_color = .{0.9, 0.7, 0, 1};  // Orange
        case .RIGHT; circle_color = .{0, 0.9, 0.2, 1};  // Green
        case .UP;    circle_color = .{0.9, 0.2, 0.7, 1};  // Pink
    }

    draw_circle_at(screen_pos, player_radius, 32, circle_color);

    // Draw direction marker
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