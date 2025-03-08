// Onscreen isn't a real word, you mad?

WHITE :: Vector4.{1., 1., 1., 1.};

// Onscreen control positions are using same window_width relative coords as entities.
// This is maybe a bit odd, as we then have to convert pointer positions to relative, then relative to window again
// to render.
// Also, should maybe define relative to size of the deadzone? Pretty hardcoded to size of deadzone on my phone atm!
JOYSTICK_NEUTRAL_POSITION :: Vector2.{0.3, 0.25};
JOYSTICK_RADIUS :: 0.10;
JOYSTICK_SIZE   :: Vector2.{JOYSTICK_RADIUS*2, JOYSTICK_RADIUS*2};
// Short range feels much better to play, but longer range means we can see the fancy handle texture :)
// JOYSTICK_RANGE  :: JOYSTICK_RADIUS / 3.;
JOYSTICK_RANGE  :: JOYSTICK_RADIUS * 1.1;

JOYSTICK_COMPONENT_THRESHOLD :: 0.3;
JOYSTICK_LERP_RATE :: 0.2;

NOT_HELD :: -1;
Onscreen_Joystick :: struct {
    held_pointer_index := NOT_HELD;
    position: Vector2;
    initial_offset: Vector2;
    theta: float; // Only used for handle, which we don't even show on android.

    lerp_t    := 1.;
    lerp_start: Vector2;

    map: Texture;
    handle_map: Texture;
}
joystick: Onscreen_Joystick;

// Not sure how to declare small helper like this. Macro or inline? If macro does passing by value do a copy?
is_held :: inline (joystick: *Onscreen_Joystick) -> bool {
    return joystick.held_pointer_index >= 0;
}

BUTTON_POSITION :: Vector2.{0.7, 0.25};
BUTTON_RADIUS   :: 0.065;
BUTTON_SEGMENTS :: 36;
BUTTON_COLOR    :: Vector4.{0.6, 0.05, 0.05, 1.};
button_held_index := NOT_HELD;

init_onscreen_controls :: () {
    joystick.position = JOYSTICK_NEUTRAL_POSITION;
    joystick.map        = make_texture("joy_ball.png");
    joystick.handle_map = make_texture("joy_handle.png");
}

#if OS == .ANDROID {
    #import "Android"()(main);

    onscreen_controls_receive_motion_event :: (event: *AInputEvent) -> handled: bool {
        handled := false;

        if AInputEvent_getType(event) == .MOTION {
            action_and_pointer_index := cast(AMOTION_EVENT_ACTION) AMotionEvent_getAction(event);
            action        := action_and_pointer_index & AMOTION_EVENT_ACTION.MASK;
            pointer_index := cast(u64) (action_and_pointer_index) >> AMOTION_EVENT_ACTION_POINTER_INDEX_SHIFT;
            pointer_id    := AMotionEvent_getPointerId(event, pointer_index);
            num_pointers  := AMotionEvent_getPointerCount(event);

            primary_x := AMotionEvent_getX(event, pointer_index);
            primary_y := AMotionEvent_getY(event, pointer_index);

            // The first touch is a down/up. Subsequent touches (while still holding first) will be pointer_up/down
            if action == {
                case .DOWN; #through;
                case .POINTER_DOWN;
                    // log_error("Touched by id % at (%, %)", pointer_id, primary_x, primary_y);
                    android_pointers[pointer_id].state = (Key_Current_State.DOWN | .START);
                    android_pointers[pointer_id].window_position_x = primary_x;
                    android_pointers[pointer_id].window_position_y = primary_y;
                    handled = true;

                case .UP; #through;
                case .POINTER_UP;
                    // log_error("Released by id % at (%, %)", pointer_id, primary_x, primary_y);
                    android_pointers[pointer_id].state = .END;
                    handled = true;

                case .MOVE;
                    // Move gives us the position of every touching pointer so we have to loop and look at them.
                    for 0..num_pointers-1 {
                        pointer_id = AMotionEvent_getPointerId(event, it);

                        pointer := *android_pointers[pointer_id];
                        assert((pointer.state & .DOWN) != 0, "Pointer with id % is received a move event in an unexpected state - %", pointer_id, pointer.state);

                        // Android also gives you a history of positions inbetween motion events if you want, I am
                        // just using current position.
                        // history_size := AMotionEvent_getHistorySize(event);

                        pointer.window_position_x = AMotionEvent_getX(event, it);
                        pointer.window_position_y = AMotionEvent_getY(event, it);
                    }
                    handled = true;

                case;
                    log("Unhandled motion event of type %", action, flags = .WARNING);
            }
        }

        return handled;
    }
} else #if OS == .WINDOWS {
    windows_update_pointers :: () {
        get_mouse_window_position :: () -> Vector2 {
            #import "Window_Creation";

            x, y := get_mouse_pointer_position();
            Clamp(*x, 0, window_width);
            Clamp(*y, 0, window_height);

            return .{xx x, xx y};
        }

        for event : events_this_frame {
            if event.type == .KEYBOARD {
                key := event.key_code;

                if key == .MOUSE_BUTTON_LEFT || key == .MOUSE_BUTTON_RIGHT {
                    pointer_id := ifx key == .MOUSE_BUTTON_LEFT  0 else 1;

                    if event.key_pressed {
                        android_pointers[pointer_id].state = (Key_Current_State.DOWN | .START);
                    } else {
                        android_pointers[pointer_id].state = .END;
                    }
                }
            }
        }

        mouse_position := get_mouse_window_position();
        for * pointers {
            if it.state > 0 it.window_position = mouse_position;
        }
    }
}

// Bit of a @Hack to clear the pointer states. For key states in the input module this happens as part update_window_events.
onscreen_controls_pre_input :: () {
    mask     := ~Key_Current_State.START;
    end_mask := ~(Key_Current_State.END | .DOWN | .START);
    for * android_pointers {
        if (it.state & .END) it.state &= end_mask;
        else it.state &= mask;
    }
}

update_and_render_onscreen_controls :: () {
    // For windows emulate pointers with left click = 0, right click = 1. Position is always mouse position.
    #if OS == .WINDOWS windows_update_pointers();

    for * android_pointers {
        if it.state & .START {
            pointer_position := get_pointer_relative_position(it);

            if !is_held(*joystick) {
                if distance(pointer_position, JOYSTICK_NEUTRAL_POSITION) <= JOYSTICK_RADIUS {
                    joystick.held_pointer_index = it_index;
                    joystick.initial_offset = pointer_position - JOYSTICK_NEUTRAL_POSITION;
                }
            }

            if button_held_index == NOT_HELD {
                if distance(pointer_position, BUTTON_POSITION) <= BUTTON_RADIUS {
                    shoot_button_down = true;
                    button_held_index = it_index;
                }
            }

        } else {
            if (it.state & .END) != 0 {
                if joystick.held_pointer_index == it_index {
                    joystick.held_pointer_index = NOT_HELD;
                    joystick.lerp_t = 0.;
                    joystick.lerp_start = joystick.position;
                    key_left, key_right, key_up, key_down = 0;
                }

                if button_held_index == it_index {
                    button_held_index = NOT_HELD;
                    shoot_button_down = false;
                }
            }
        }
    }

    // Why is this separate from the loop above?

    if is_held(*joystick) {
        key_left, key_right, key_up, key_down = 0;
        holding_pointer  := *android_pointers[joystick.held_pointer_index];
        pointer_position := get_pointer_relative_position(holding_pointer);
        pointer_position -= joystick.initial_offset;

        // @TODO Analog input. Would require changing main invaders code.
        diff := pointer_position - JOYSTICK_NEUTRAL_POSITION;
        direction := unit_vector(diff);
        joystick.theta = atan2(direction.y, direction.x);
        if distance(pointer_position, JOYSTICK_NEUTRAL_POSITION) <= JOYSTICK_RANGE {
            joystick.position = pointer_position;
        } else {
            joystick.position = JOYSTICK_NEUTRAL_POSITION + JOYSTICK_RANGE * direction;

            // Apply input
            // Could set the input module key states here instead of invader variables? See my android GetRect example.
            if direction.x >  JOYSTICK_COMPONENT_THRESHOLD key_right = 1;
            if direction.x < -JOYSTICK_COMPONENT_THRESHOLD key_left  = 1;
            if direction.y >  JOYSTICK_COMPONENT_THRESHOLD key_up    = 1;
            if direction.y < -JOYSTICK_COMPONENT_THRESHOLD key_down  = 1;
        }
    } else {
        if joystick.lerp_t < 1. {
            // For how short the distance is this is fine. If it were larger we would want more control.
            joystick.lerp_t += JOYSTICK_LERP_RATE;
            joystick.position = lerp(joystick.lerp_start, JOYSTICK_NEUTRAL_POSITION, joystick.lerp_t);
        }
    }


    HANDLE_RADIUS :: JOYSTICK_RADIUS * 1.;
    handle_size := Vector2.{HANDLE_RADIUS*2, HANDLE_RADIUS*2};
    length := distance(joystick.position, JOYSTICK_NEUTRAL_POSITION);
    handle_size.x = length * 1.5;
    render_sprite_quad_centered_(*joystick.handle_map, JOYSTICK_NEUTRAL_POSITION, handle_size, WHITE, joystick.theta);
    render_sprite_quad_centered_(*joystick.map, joystick.position, JOYSTICK_SIZE, WHITE);

    // px := cast(float) window_width * JOYSTICK_NEUTRAL_POSITION;
    // rx := cast(float) window_width * (JOYSTICK_RADIUS / 3.);
    // draw_circle_at(px, rx, xx BUTTON_SEGMENTS, .{0., 1., 1., 1.});

    button_position_window := cast(float) window_width * BUTTON_POSITION;
    button_radius_window   := cast(float) window_width * BUTTON_RADIUS;
    button_color := BUTTON_COLOR;

    // Draw Button surrounds, gap and button itself.
    draw_circle_at(button_position_window, button_radius_window * 1.4, xx BUTTON_SEGMENTS, button_color);
    draw_circle_at(button_position_window, button_radius_window * 1.075, xx BUTTON_SEGMENTS, .{0.1, 0.1, 0.1, 1.});

    if shoot_button_down  button_color *= 0.7;
    draw_circle_at(button_position_window, button_radius_window, xx BUTTON_SEGMENTS, button_color);
}

// Position in window_width relative coords.
get_pointer_relative_position :: (pointer_info: *Android_Pointer_Info) -> Vector2 {
    result: Vector2;
    result.x = pointer_info.window_position_x;
    result.y = pointer_info.window_position_y;
    result.y = window_height - result.y;
    result /= cast(float) window_width;
    return result;
}

// @MODIFIED Dumb @CopyPasta as on screen controls want to be outside the playfield! This is just what the orignal
// function did before my modification for aspect ratio lol. Should probalby combine, but trying to avoid too many
// changes...
render_sprite_quad_centered_ :: (texture: *Texture, _pos: Vector2, size: Vector2, color: Vector4, theta := 0.0) {
    Simp.set_shader_for_images(texture);

    pos := cast(float) window_width * _pos;
    h := Vector2.{size.x*.5*window_width, 0};
    v := Vector2.{0, size.y*.5*window_width};

    radians := (TAU / 360.0) * theta;
    radians = theta; // @Hack handle theta stored in radians!

    h = rotate(h, radians);
    v = rotate(v, radians);

    p0 := pos - h - v;
    p1 := pos + h - v;
    p2 := pos + h + v;
    p3 := pos - h + v;

    Simp.immediate_quad(p0, p1, p2, p3,  color);
}

// Yoinked from GetRect/widgets/color_picker.jai
draw_circle_at :: (center: Vector2, r: float, N: s32, color: Vector4) {
    if !N return;

    Simp.set_shader_for_color();

    dtheta := TAU / N;
    p0 := Vector3.{center.x, center.y, 0};

    // @Speed: Factor apart the loop below to save the previous points.
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
