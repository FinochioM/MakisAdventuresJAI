Path_Cursor :: struct {
    waypoint_index: s32;
}

Path_Flags :: enum_flags u16 {
    ENDPOINT_IS_IN_FORMATION   :: 0x1;
    ENDPOINT_IS_OFF_THE_BOTTOM :: 0x2;
}

Path :: struct {
    waypoints: [..] Vector2;

    cursor: Path_Cursor;

    path_flags: Path_Flags;
}

release :: (path: *Path) {
    array_free(path.waypoints);
}

Strafe_Type :: enum u8 {
    DOWNWARD :: 0;
    SIDEWAYS :: 1;
    KAMIKAZE_STRAIGHT :: 2;
    KAMIKAZE_DRUNKEN  :: 3;
}

NUM_STRAFE_TYPES :: #run enum_highest_value(Strafe_Type) + 1;

random_sign :: () -> float {
    n := random_get();

    return ifx n & 1 then -1.0 else 1.0;
}

init_strafe_path :: (path: *Path, start: Vector2) {
    path.path_flags = 0;
    array_reset(*path.waypoints);
    
    strafe_type := cast(Strafe_Type) (random_get() % NUM_STRAFE_TYPES);

    array_add(*path.waypoints, start);
    pos := start;
    
    if strafe_type == {
        case .DOWNWARD;
            left_or_right: float;
            if      start.x < .2    left_or_right = 1;
            else if start.x > 1-.2  left_or_right = -1;
            else left_or_right = random_sign();

            pos += .{left_or_right * .2, -.25};
            array_add(*path.waypoints, pos);
        
            pos += .{-left_or_right * .4, -.25};
            array_add(*path.waypoints, pos);
        
            pos += .{left_or_right * .5, -.25};
            pos.y = live_y_min;
            array_add(*path.waypoints, pos);
            path.path_flags |= .ENDPOINT_IS_OFF_THE_BOTTOM;
        
        case .SIDEWAYS;
            pos += .{-.1, -.25};
            array_add(*path.waypoints, pos);

            pos += .{.5, 0};
            array_add(*path.waypoints, pos);

            pos += .{.1, .3};
            array_add(*path.waypoints, pos);

            array_add(*path.waypoints, start);
            path.path_flags |= .ENDPOINT_IS_IN_FORMATION;
        
        case .KAMIKAZE_STRAIGHT;
            left_or_right := random_sign();
            pos += .{left_or_right * .08, .08};
            array_add(*path.waypoints, pos);

            pos = ship_position;
            array_add(*path.waypoints, pos);

            pos.y = live_y_min;
            array_add(*path.waypoints, pos);
            path.path_flags |= .ENDPOINT_IS_OFF_THE_BOTTOM;
        
        case .KAMIKAZE_DRUNKEN; 
            left_or_right := random_sign();
            pos += .{left_or_right * .08, .08};
            array_add(*path.waypoints, pos);

            k := 0.17;
        
            pos.x = ship_position.x;
            pos.y -= k;
            array_add(*path.waypoints, pos);

            side := .22;
            pos.x += -left_or_right * side;
            pos.y -= k;
            array_add(*path.waypoints, pos);

            pos.x += left_or_right * side;
            pos.y -= k;
            array_add(*path.waypoints, pos);

            pos.x += -left_or_right * side;
            pos.y -= k;
            array_add(*path.waypoints, pos);

            pos.x += left_or_right * side;
            pos.y -= k;
            array_add(*path.waypoints, pos);

            pos.y = live_y_min;
            array_add(*path.waypoints, pos);
            path.path_flags |= .ENDPOINT_IS_OFF_THE_BOTTOM;
        
    }

    path.cursor.waypoint_index = 1;
}

follow_path :: (pos: Vector2, path: *Path, distance_to_travel: float) -> (result: Vector2, desired_theta: float, done: bool) {
    // Note that we modify the Path_Cursor stored on the Path.

    while distance_to_travel > 0 {
        index := path.cursor.waypoint_index;

        // @Robustness: We might put a bit of stuff here to handle
        // the case when we are a little bit on the opposite direction
        // of the next point.
        
        target := path.waypoints[index];

        dir := unit_vector(target - pos);
        length := distance(target, pos);

        theta := atan2(dir.y, dir.x) * (360 / TAU);
        
        if length <= distance_to_travel {
            // We are going to go past the endpoint of this segment.
            // If it's the last segment, we're done; otherwise, increment
            // and loop.
            
            distance_to_travel -= length;
            path.cursor.waypoint_index += 1;

            if path.cursor.waypoint_index >= path.waypoints.count {
                return target, theta, true;
            }
        } else {
            // Go as far as we can toward the next waypoint, which
            // we will not reach. Break because there's nothing else
            // to do.

            result_pos := pos + dir * distance_to_travel;
            return result_pos, theta, false;
        }
    }

    return pos, 0, false; // Silence a compiler warning that we should fix some day!
}
