simulate_bullets :: () {
    simulate_bullet :: (bullet : * Bullet) -> bool {
        linear_move(*bullet.position, *bullet.velocity, current_dt);

        if bullet.position.y > live_y_max return true;
        if bullet.position.y < live_y_min return true;

        bullet.emitter.position = bullet.position;
        bullet.emitter.velocity = bullet.velocity;

        if bullet.player_friendly {
            if test_against_invaders(bullet) {
                if bullet.bullet_flags & .PENETRATING return false;  // Keep going!
                return true;
            }
        } else {
            if test_against_ship(bullet.position, BULLET_RADIUS) {
                if !ship_is_shielded() destroy_ship();
                return true;
            }
        }

        return false;
    }

    for live_bullets {
        done := simulate_bullet(it);
        if done {
            it.emitter.producing = false;
            remove it;
            free(it);
        }
    }
}

decide_about_strafing :: () {

    now := seconds_since_init();
    elapsed := now - time_of_level_start;

    minutes := elapsed / 60;
    dude_modifier := cast(float) pow(0.5, minutes);

    //
    // How many dudes are alive, as a ratio of dudes spawned?
    //

    assert(live_invaders.count <= dudes_spawned_in_this_level);
    denom := cast(float) max(dudes_spawned_in_this_level, 1);

    dudes_alive_ratio := dude_modifier * (live_invaders.count / denom);

    current_aggro = 1 - dudes_alive_ratio;
    Clamp(*current_aggro, 0, 1);



    num_strafing: s32;

    sleeping: [..] *Invader;
    sleeping.allocator = temp;

    for live_invaders {
        if      it.action == .STRAFING  num_strafing += 1;
        else if it.action == .SLEEPING  array_add(*sleeping, it);
    }

    desired_strafers := 1 + level_index * 1.2 + current_aggro * level_index * 1.3;
    desired := cast(s32) floor(desired_strafers + .5);

    if sleeping && (num_strafing < desired) {
        countdown(*strafe_countdown);
        if strafe_countdown == 0 {
            index := cast(s64) (random_get() % cast(u64) sleeping.count);
            invader := sleeping[index];

            init_strafe_path(*invader.strafe_path, invader.position);
            invader.action = .STRAFING;

            // Reset the strafe countdown.
            delay0 := 0.1;
            delay1 := 5.0 * pow(0.5, level_index / 10.0);

            strafe_countdown = random_get_within_range(delay0, delay1);
            start_shot_countdown(invader);  // If he was on a slow sleep countdown, restart it.
        }
    }
}

simulate_invaders :: () {
    decide_about_strafing();

    for live_invaders {
        if it.shot_countdown > 0  countdown(*it.shot_countdown);

        if it.shot_countdown == 0 {
            invader_fire_bullet(it);
            start_shot_countdown(it);
        }

        if it.action == {
            case .FALLING_IN;  falling_in(it);
            case .SLEEPING;    sleeping(it);
            case .STRAFING;    strafing(it);
        }

        hit := test_against_ship(it.position, current_invader_radius);
        if hit {
            destroy_invader(it);
            if !ship_is_shielded() destroy_ship();
        }
    }
}

//
// Invader Actions:
//

FALLING_IN_SPEED :: 0.45;

falling_in :: (i: *Invader) {
    target := get_target_position(i);

    i.x = target.x;

    ty := target.y;
    if i.y <= ty {
        // We are done!
        i.action = .SLEEPING;
        start_shot_countdown(i);
        return;
    }

    i.y -= FALLING_IN_SPEED * current_dt;
    if i.y < ty  i.y = ty;

    // Compute the new theta.
    denom := ty - i.spawn_position.y;
    if denom {
        t := (i.y - i.spawn_position.y) / denom;   // 0 to 1.

        NUM_CIRCLES := 1;
        theta := 360.0 * NUM_CIRCLES * t - 90;
        i.theta = theta;
    }
}

sleeping :: (i: *Invader) {
    i.position = get_target_position(i);

    DTHETA_DT :: 500;
    turn_toward(*i.theta, -90, current_dt, DTHETA_DT);
}

move_toward :: (a_pointer: *float, target: float, dt: float, rate_up: float, rate_down: float = -1.0) {
    a := << a_pointer;

    if a > target {
        if rate_down == -1 rate_down = rate_up;
        a -= dt * rate_down;
        if a < target  a = target;
        << a_pointer = a;
    } else if a < target {
        a += dt * rate_up;
        if a > target  a = target;
        << a_pointer = a;
    }
}

wrap_degrees :: inline (theta: float) -> float {
    if theta <= -180  theta += 360;
    if theta >   180  theta -= 360;

    return theta;
}

turn_toward :: (a_pointer: *float, target: float, dt: float, rate_up: float, rate_down: float = -1.0) {

    // First, put both the current and target angles into the rnage [-180, 180].
    <<a_pointer = wrap_degrees(<<a_pointer);
    target = wrap_degrees(target);

    // Now, check whether we are trying to turn more than 180 degrees.
    // If so, change 'target' so that we go the short way around instead of the long way.

    dtheta := target - <<a_pointer;
    if      dtheta >  180  target -= 360;
    else if dtheta < -180  target += 360;

    move_toward(a_pointer, target, dt, rate_up, rate_down);
}

strafing :: (i: *Invader) {
    speed_slow := 0.4  + 0.03  * level_index;
    speed_fast := 0.55 + 0.042 * level_index;

    speed := lerp(speed_slow, speed_fast, current_aggro);

    path := *i.strafe_path;
    if path.path_flags & .ENDPOINT_IS_IN_FORMATION {
        path.waypoints[path.waypoints.count-1] = get_target_position(i);
    }

    distance_to_travel := speed * current_dt;
    new_position, target_theta, done := follow_path(i.position, path, distance_to_travel);

    {
        // Update theta to be like target_theta.

        DTHETA_DT :: 150;
        turn_toward(*i.theta, target_theta, current_dt, DTHETA_DT);
    }

    i.position = new_position;

    if done {
        if path.path_flags & .ENDPOINT_IS_IN_FORMATION {
            i.action = .SLEEPING;
        } else if path.path_flags & .ENDPOINT_IS_OFF_THE_BOTTOM {
            i.position.y = live_y_max;
            i.action = .FALLING_IN;
        } else {
            // Default...
            i.action = .SLEEPING;
        }
    }
}

simulate_pickups :: () {

    simulate_pickup :: (pickup: *Pickup) -> bool {
        linear_move(*pickup.position, *pickup.velocity, current_dt);

        if pickup.position.y > live_y_max
            return true;
        if pickup.position.y < live_y_min
            return true;

        if test_against_ship(pickup.position, PICKUP_RADIUS) {
            if ship_is_shielded() {
                play_sound(*sound_pickup_fail);
            } else {
                player_got_pickup(pickup);
                play_sound(*sound_pickup_succeed);
            }

            return true;
        }

        return false;
    }


    for live_pickups {
        done := simulate_pickup(it);
        if done {
            remove it;
            free(it);
        }
    }
}

simulate_spawns :: () {
    for * line: layout_lines {
        if line.spawn_countdown < 0  continue;  // Already spawned!

        countdown(*line.spawn_countdown);

        if line.spawn_countdown == 0 {
            line.spawn_countdown = -1;  // Mark us as already spawned.
            spawn_invaders(line);
        }
    }

    //
    // Update formation stuff:
    //
    last := formation_offset;

    now := seconds_since_init();
    theta := cast(float) fmod_cycling(90 * now, 360);
    radians := theta * (TAU / 360);

    xscale := .05;
    yscale := .02;
    formation_offset = .{xscale*cos(radians), yscale*sin(2*radians)};
}


ilength :: (x: float, y: float) -> float {
    length := x * x + y * y;
    denom := 1.0 / sqrt(length);
    return denom;
}

test_against_ship :: (position: Vector2, radius: float) -> bool {
    if ship_destroyed return false;
    return distance(position, ship_position) < radius + SHIP_RADIUS;
}

destroy_invader :: (invader: *Invader) {
    num_invaders_destroyed += 1;

    array_unordered_remove_by_value(*live_invaders, invader);
    release(invader);

    {
        emitter := New(Particle_Emitter);
        array_add(*live_emitters, emitter);

        emitter.size0 = 0.0008;
        emitter.size1 = 0.01;

        emitter.speed0 = 0.1;
        emitter.speed1 = 0.3;

        emitter.color0 = .{1, 1, 0.3, 1};
        emitter.color1 = .{1, 1, 1, 1};

        emitter.fadeout_period = 0.1;
        emitter.emitter_lifetime = 0.2;

        emitter.position = invader.position;
    }

    {
        emitter := New(Particle_Emitter);
        array_add(*live_emitters, emitter);

        emitter.size0 = 0.015;
        emitter.size1 = 0.06;

        emitter.color0 = .{1, 1, 1, 1};
        emitter.color1 = .{1, 0.7, 0.1, 1};

        emitter.fadeout_period = 0.3;
        emitter.emitter_lifetime = 0.3;

        emitter.position = invader.position;
    }

    drop_roll := random_get() % 100;
    if drop_roll < 25 {
        pickup := New(Pickup);
        array_add(*live_pickups, pickup);


        roll := random_get() % 100;

        pickup.position = invader.position;
        pickup.velocity = .{0, PICKUP_SPEED * random_get_within_range(0.7, 1.7)};

        if roll < 10 {
            pickup.type = .PENETRATING;
            pickup.map = *pickup_map_penetrating;
        } else if roll < 20 {
            pickup.type = .TURBO;
            pickup.map = *pickup_map_turbo;
        } else if roll < 47 {
            pickup.type = .V_SHOT;
            pickup.map = *pickup_map_v_shot;
        } else if roll < 65 {
            pickup.type = .EXTRA_BULLET;
            pickup.map = *pickup_map_extra_bullet;
        } else {
            pickup.type = .SHIELD;
            pickup.map = *pickup_map_shield;
        }
    }

    play_sound(*sound_alien_dies);
}

start_shot_countdown :: (i: *Invader) {
    if i.action == {
        case .FALLING_IN;  i.shot_countdown = -1;
        case .SLEEPING;    i.shot_countdown = random_get_within_range(5, 10);  // @Incomplete: Adjust based on level?
        case .STRAFING;    i.shot_countdown = random_get_within_range(.2, 1.2);
        case;              i.shot_countdown = -1;
    }
}

get_target_position :: (invader: *Invader) -> Vector2 {
    line := layout_lines[invader.line_index];
    slot := line.invader_slots[invader.slot_index];

    return slot.position + formation_offset;
}
