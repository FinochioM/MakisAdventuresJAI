#import "Basic"()(MEMORY_DEBUGGER = (OS != .ANDROID));
#import "Hash_Table";
#import "Math";
#import "Random";
using Sound :: #import "Sound_Player";
#import "Window_Creation";
#import "File";
#import "String"; // For path_strip_filename.
#import "Thread";
#import "Input";
#import "System";
#import "Sloppy_Math";

Simp    :: #import "Simp";
Texture :: Simp.Texture;

#load "entities.jai";
#load "levels.jai";
#load "particles.jai";
#load "simulate.jai";
#load "pathing.jai";
#load "tiles.jai";

ASPECT :: (1280.0 / 720.0);
VPIXELS :: 720;

playfield_width : s32 = 1280;
playfield_height : s32 = 720;

window_width, window_height: s32;
window_aspect := ASPECT;

LOGICAL_WIDTH   :: 320;
LOGICAL_HEIGHT  :: 180;
scale_factor    : float;

should_ignore_input := false;
should_quit_game := false;

key_left  : u32;
key_right : u32;
key_up    : u32;
key_down  : u32;

sound_alien_dies:          Sound_Data;
sound_fire_bullet1:        Sound_Data;
sound_fire_bullet2:        Sound_Data;
sound_fire_bullet3:        Sound_Data;
sound_invader_fire_bullet: Sound_Data;
sound_new_wave:            Sound_Data;
sound_pickup_fail:         Sound_Data;
sound_pickup_succeed:      Sound_Data;
sound_player_dies:         Sound_Data;
sound_shield_begin:        Sound_Data;
sound_shield_end:          Sound_Data;
sound_shield_loop:         Sound_Data;
sound_bullet_reset:        Sound_Data;

the_music: Sound_Data;

current_dt: float = 0.016667;
last_time:  float64;
DT_MAX : float : 0.15;

shoot_button_down := false;

live_y_max := (1 / ASPECT) * 1.1;
live_y_min := -0.1;

INVADER_RADIUS_AT_SCALE_1 :: .025;
BULLET_RADIUS  :: .015;
SHIP_RADIUS    :: .045;
PICKUP_RADIUS  :: .018;

PICKUP_SPEED :: -.38;

SHIP\  _INVINCIBILITY_TIME :: 8.0;
RESPAWN_INVINCIBILITY_TIME :: 1.0;

SHIP_PENETRATING_TIME   :: 8.0;

TURBO_SHOTS_PER_PICKUP  :: 25;
TURBO_SHOTS_MAX         :: 60;

PARTICLES_PER_SECOND_MULTIPLIER :: 1;
PLAY_SOUND_WHEN_ALIEN_SHOOTS_BULLET :: true;

NUM_UPDATE_PROCS :: 3;

data_folder: string;

Shot_Type :: enum u32 {
    STRAIGHT_SINGLE :: 0;
    STRAIGHT_DOUBLE :: 1;
    STRAIGHT_TRIPLE :: 2;
}


live_invaders : [..] *Invader;
live_pickups  : [..] *Pickup;
live_bullets  : [..] *Bullet;
live_emitters : [..] *Particle_Emitter;

NUM_LIVES :: 2;

lives                  := NUM_LIVES;
shot_index             := 0;
num_invaders_destroyed := 0;
level_index            := 0;
respawn_countdown     := -1.0;

my_font: *Simp.Dynamic_Font;

ship_position: Vector2;

ship_destroyed                := false;
ship_shot_type                := Shot_Type.STRAIGHT_SINGLE;
ship_shot_cooldown            := 0.0;

SHIP_SHOT_COOLDOWN            := 0.3;
SHIP_SHOT_COOLDOWN_TURBO      := 0.10;
SHIP_SHOT_COOLDOWN_PER_BULLET       := 0.10;
SHIP_SHOT_COOLDOWN_PER_BULLET_TURBO := 0.05;

ship_invincibility_countdown    := 0.0;
ship_penetrating\ _countdown    := 0.0;
ship_turbo_shots                := 0;

SHIP_V_SHOT_STABILITY_TIME            :: 10.0;
SHIP_V_SHOT_DEGREES_PER_PICKUP        :: 12.0;
SHIP_V_SHOT_DEGREES_MAX               :: 150.0;
SHIP_V_SHOT_SHRINK_DEGREES_PER_SECOND :: 2.0;
SHIP_V_SHOT_EXPAND_DEGREES_PER_SECOND :: 20.0;

ship_v_shot_stability_countdown := 0.0;
ship_v_shot_angle_target        := 0.0;
ship_v_shot_angle_current       := 0.0;

invader_maps : [..] Texture;

sky_map                 : Texture;
ship_map                : Texture;
ship_bullet_map         : Texture;
invader_bullet_map      : Texture;
contrail_map            : Texture;
pickup_map_v_shot       : Texture;
pickup_map_shield       : Texture;
pickup_map_extra_bullet : Texture;
pickup_map_penetrating  : Texture;
pickup_map_turbo        : Texture;
meter_map               : Texture;
grass                   : Texture;

tile_system             : Tile_System;

main :: () {
    base_path := path_strip_filename(get_path_of_running_executable());

    window_width  = playfield_width;
    window_height = playfield_height;

    data_folder = join(base_path, "data");
    print("data_folder is '%'\n", data_folder);

    last_time = seconds_since_init();

    window := create_window(window_name="Invaders", width=window_width, height=window_height);
    Simp.set_render_target(window);

    load_sound :: (basename: string) -> Sound_Data {
        name := tprint("%/%.wav", data_folder, basename);
        data := load_audio_file(name);

        if !data.loaded exit(1);

        return data;
    }

    sound_alien_dies          = load_sound("alien_dies");
    sound_fire_bullet1        = load_sound("fire_bullet1");
    sound_fire_bullet2        = load_sound("fire_bullet2");
    sound_fire_bullet3        = load_sound("fire_bullet3");
    sound_invader_fire_bullet = load_sound("invader_fire_bullet");
    sound_new_wave            = load_sound("new_wave");
    sound_pickup_fail         = load_sound("pickup_fail");
    sound_pickup_succeed      = load_sound("pickup_succeed");
    sound_player_dies         = load_sound("player_dies");
    sound_shield_begin        = load_sound("shield_begin");
    sound_shield_end          = load_sound("shield_end");
    sound_shield_loop         = load_sound("shield_loop");
    sound_bullet_reset        = load_sound("too_many_bullets");

    do_async_audio := (OS != .ANDROID);
    success := sound_player_init(.{update_from_a_thread = do_async_audio});

    {
        name := tprint("%/scare_tactics.ogg", data_folder);

        the_music = load_audio_file(name);

        if !the_music.loaded {
            print("Could not load theme music: %\n", name);
            exit(1);
        }

        stream := Sound.make_stream(*the_music, .MUSIC);
        set_repeating(stream, true);
        stream.user_volume_scale *= 0.2;
        start_playing(stream);
    }

    init_textures();
    resize_playfield();
    my_init_fonts();

    init_ship_position();

    level_index = 0;

    unit_color := Vector4.{1, 1, 1, 1};
    ship_color, invader_color, pickup_color, bullet_color := unit_color;

    ship_size    := Vector2.{SHIP_RADIUS*2,    SHIP_RADIUS*2};
    pickup_size  := Vector2.{PICKUP_RADIUS*2,  PICKUP_RADIUS*2};
    bullet_size  := Vector2.{BULLET_RADIUS*2,  BULLET_RADIUS*2};

    tile_system = init_tile_system(8, 8, LOGICAL_WIDTH / 8, LOGICAL_HEIGHT / 8);

    add_layer(*tile_system, "background", 0);
    add_layer(*tile_system, "objects", 10);
    add_layer(*tile_system, "foreground", 20);

    objects_layer := get_layer(*tile_system, "objects");
    if objects_layer objects_layer.collision_layer = true;

    init_tile_textures();

    while !should_quit_game {
        reset_temporary_storage();

        update_window_events();

        for get_window_resizes() {
            Simp.update_window(it.window);
            if it.window == window {
                should_reinit := (it.width != window_width) || (it.height != window_height);

                window_width  = it.width;
                window_height = it.height;

                if should_reinit {
                    resize_playfield();
                    my_init_fonts();
                }
            }
        }

        invaders_simulate();

        Simp.clear_render_target(.1, .1, .1, 1);

        playfield_x0 := window_coords_from_absolute(.{0, 0});
        playfield_x1 := window_coords_from_absolute(.{xx playfield_width, xx playfield_height});
        Simp.set_scissor(xx playfield_x0.x, xx playfield_x0.y, xx playfield_x1.x, xx playfield_x1.y);

        render_tile_system(*tile_system);

        Simp.clear_scissor();

        Simp.swap_buffers(window);

        memory_visualizer_per_frame_update();
    }

    release_tile_system(*tile_system);
    sound_player_shutdown();
}

init_textures :: () {
    ship_map                = make_texture("ship.png");

    sky_map                 = make_texture("sky.png");
    meter_map               = make_texture("meter.png");

    ship_bullet_map         = make_texture("bullet.png");
    invader_bullet_map      = make_texture("invader_bullet.png");
    contrail_map            = make_texture("contrail.png");
    pickup_map_penetrating  = make_texture("pickup_penetrating.png");
    pickup_map_turbo        = make_texture("pickup_turbo.png");
    pickup_map_v_shot       = make_texture("pickup_v_shot.png");
    pickup_map_shield       = make_texture("pickup_shield.png");
    pickup_map_extra_bullet = make_texture("pickup_extra_bullet.png");

    grass                   = make_texture("grass.png");

    bug1 := make_texture("bug1.png");
    bug2 := make_texture("bug2.png");
    bug3 := make_texture("bug3.png");
    bug4 := make_texture("bug4.png");

    array_add(*invader_maps, bug1);
    array_add(*invader_maps, bug2);
    array_add(*invader_maps, bug3);
    array_add(*invader_maps, bug4);
}

init_tile_textures :: () {
    simple_tile_index := load_tile_texture(*tile_system, "grass.png");

    if simple_tile_index >= 0 {
        background_layer := get_layer(*tile_system, "background");
        if background_layer {
            for x: 0..tile_system.grid_width-1 {
                set_tile(*tile_system, "background", x, 0, simple_tile_index);
                set_tile(*tile_system, "background", x, tile_system.grid_height-1, simple_tile_index);
            }

            for y: 1..tile_system.grid_height-2 {
                set_tile(*tile_system, "background", 0, y, simple_tile_index);
                set_tile(*tile_system, "background", tile_system.grid_width-1, y, simple_tile_index);
            }
        }
    }
}

make_texture :: (name: string) -> Texture, bool {
    filename := tprint("%/%", data_folder, name);

    result: Texture;
    success := Simp.texture_load_from_file(*result, filename);

    return result, success;
}

MIDFIELD :: (1 / ASPECT) * .75;

countdown :: (value_pointer: *float) {
    value := << value_pointer;
    value -= current_dt;
    if value < 0 value = 0;
    <<value_pointer = value;
}

invaders_simulate :: () {
    now := seconds_since_init();
    delta : float64 = now - last_time;
    current_dt = cast(float) delta;

    if current_dt > DT_MAX current_dt = DT_MAX;

    last_time = now;

    // Sound.update();

    old_invincibility := ship_invincibility_countdown;

    countdown(*ship_shot_cooldown);
    countdown(*ship_invincibility_countdown);
    countdown(*ship_v_shot_stability_countdown);
    countdown(*ship_penetrating_countdown);

    if ship_v_shot_stability_countdown <= 0 {
        ship_v_shot_angle_target = 0;

        // We are shrinking.
        if ship_v_shot_angle_current > ship_v_shot_angle_target {
            d_angle := SHIP_V_SHOT_SHRINK_DEGREES_PER_SECOND * current_dt;
            ship_v_shot_angle_current -= d_angle;
            if ship_v_shot_angle_current < 0  ship_v_shot_angle_current = 0;
        }
    } else {
        // We are growing.
        if ship_v_shot_angle_current < ship_v_shot_angle_target {
            ship_v_shot_angle_current += SHIP_V_SHOT_EXPAND_DEGREES_PER_SECOND * current_dt;
            if ship_v_shot_angle_current > ship_v_shot_angle_target  ship_v_shot_angle_current = ship_v_shot_angle_target;
        }
    }

    if ship_invincibility_countdown <= 0 && old_invincibility > 0 {
        play_sound(*sound_shield_end);
    }

    if respawn_countdown >= 0 {
        respawn_countdown -= current_dt;
        if respawn_countdown < 0 {
            lives -= 1;

            if lives < 0 {
                should_quit_game = true;
            } else {
                init_ship_position();
                ship_destroyed = false;
            }
        }
    }

    if !live_invaders {
        found := false;
        for * layout_lines {
            if it.spawn_countdown >= 0 {
                found = true;
                break;
            }
        }

        if !found {
            level_index += 1;
            init_new_level(level_index);
        }
    }

    for event : events_this_frame {
        if event.type == .QUIT {
            should_quit_game = true;
            break;
        }

        if event.key_code == .ESCAPE
            if event.key_pressed should_quit_game = true;

        if event.type == .KEYBOARD {
            key := event.key_code;

            if key == .ARROW_LEFT   key_left  = event.key_pressed;
            if key == .ARROW_RIGHT  key_right = event.key_pressed;
            if key == .ARROW_DOWN   key_down  = event.key_pressed;
            if key == .ARROW_UP     key_up    = event.key_pressed;

            if key == .SHIFT        shoot_button_down = cast(bool) event.key_pressed;
        }
    }

    if shoot_button_down {
        maybe_fire_bullets();
    }

    dx: Vector2;

    if key_up     dx.y += 1;
    if key_left   dx.x -= 1;
    if key_down   dx.y -= 1;
    if key_right  dx.x += 1;

    if length(dx) > 1 {
        dx = unit_vector(dx);
    }

    ship_position += dx * .5 * current_dt;

    x0 := 0.03;
    x1 := 1 - x0;
    y0 := 0.03;
    y1 := 0.35;

    Clamp(*ship_position.x, x0, x1);
    Clamp(*ship_position.y, y0, y1);

    simulate_spawns();
    simulate_bullets();
    simulate_invaders();
    simulate_pickups();

    for live_emitters update_emitter(it, current_dt);
}

do_fire_bullets :: () {

    speed := 1.2;

    fire_bullet :: (speed: float, angle: float) -> * Bullet {
        bullet := New(Bullet);

        bullet.position = ship_position;

        radians := (angle + 90) * (TAU / 360.0);

        bullet.velocity = speed * Vector2.{cos(radians), sin(radians)};
        bullet.map = *ship_bullet_map;

        if ship_penetrating_countdown  bullet.bullet_flags |= .PENETRATING;

        {
            bullet.emitter = New(Particle_Emitter);

            using bullet.emitter;

            theta0 = TAU * 0.6;
            theta1 = TAU * 0.9;
            drag0 = 0.9;
            drag1 = 0.97;

            if bullet.bullet_flags & .PENETRATING {
                size0 = 0.0065;
                size1 = 0.012;

                k0 := 1.0;
                k1 := 0.5;
                color0 = .{k0, k0*.8, k0*.05, 1};
                color1 = .{k1, k1*.95, k1*.05, 1};
            } else {
                size0 = 0.0045;
                size1 = 0.008;

                k0 := 1.0;
                k1 := 0.1;
                color0 = .{k0, k0*.3, k0*.3, 1};
                color1 = .{k1, k1*.3, k1*.3, 1};
            }

            lifetime0 = 0.3;
            lifetime1 = 0.55;

            fadeout_period = 0.12;

            array_add(*live_emitters, bullet.emitter);

        }

        array_add(*live_bullets, bullet);

        return bullet;
    }

    num_shots_fired := 0;
    shot_index += 1;

    v_shot_angle := ship_v_shot_angle_current * .5;

    if ship_shot_type == .STRAIGHT_SINGLE || ship_shot_type == .STRAIGHT_TRIPLE {
        angle: float;
        if ship_shot_type == .STRAIGHT_SINGLE {
            if shot_index % 2  angle =  v_shot_angle;
            else               angle = -v_shot_angle;
        }

        front := fire_bullet(speed, angle);
        front.position.y += 0.015;

        num_shots_fired += 1;
    }

    if ship_shot_type == .STRAIGHT_DOUBLE || ship_shot_type == .STRAIGHT_TRIPLE {
        left  := fire_bullet(speed,  v_shot_angle);
        right := fire_bullet(speed, -v_shot_angle);

        offset := 0.023;

        left .position.x -= offset;
        right.position.x += offset;

        num_shots_fired += 2;
    }

    turbo := false;
    if ship_turbo_shots {
        ship_turbo_shots -= 1;
        turbo = true;
    }

    base := ifx turbo then SHIP_SHOT_COOLDOWN_TURBO else SHIP_SHOT_COOLDOWN;
    per  := ifx turbo then SHIP_SHOT_COOLDOWN_PER_BULLET_TURBO else SHIP_SHOT_COOLDOWN_PER_BULLET;

    ship_shot_cooldown += base + (cast(float) num_shots_fired) * per;

    if num_shots_fired == {
        case 1; play_sound(*sound_fire_bullet1);
        case 2; play_sound(*sound_fire_bullet2);
        case 3; play_sound(*sound_fire_bullet3);
    }

}

maybe_fire_bullets :: () {
    if ship_shot_cooldown > 0  return;
    if ship_destroyed          return;

    do_fire_bullets();
}

invader_fire_bullet :: (invader : * Invader) {
    fire_bullet :: () -> * Bullet {
        bullet := New(Bullet);
        bullet.velocity.x = 0;

        if random_get() % 2 bullet.velocity.y = -.5;
        else bullet.velocity.y = -.35;

        bullet.map = *invader_bullet_map;

        array_add(*live_bullets, bullet);

        {
            bullet.emitter = New(Particle_Emitter);

            using bullet.emitter;

            theta0 = TAU * 0.6;
            theta1 = TAU * 0.9;
            drag0 = 0.9;
            drag1 = 0.97;

            size0 = 0.0025;
            size1 = 0.005;

            speed1 = 0.45;

            lifetime0 = 0.2;
            lifetime1 = 0.35;

            fadeout_period = 0.08;

            k0 := 0.7;
            k1 := 0.1;

            color0 = .{k0, k0, k0, 1};
            color1 = .{0.2, 1.0, 0.1, 1};

            array_add(*live_emitters, bullet.emitter);
        }

        return bullet;
    }


    bullet := fire_bullet();
    bullet.player_friendly = false;
    bullet.position = invader.position;

    if PLAY_SOUND_WHEN_ALIEN_SHOOTS_BULLET {
        play_sound(*sound_invader_fire_bullet);
    }
}

destroy_ship :: () {
    ship_destroyed = true;
    respawn_countdown = 2.0;

    position := ship_position;

    {
        emitter := New(Particle_Emitter);
        array_add(*live_emitters, emitter);

        emitter.size0 = 0.0004;
        emitter.size1 = 0.005;

        emitter.speed0 = 0.15;
        emitter.speed1 = 0.45;

        emitter.color0 = .{1, 1, 0.3, 1};
        emitter.color1 = .{1, 1, 1, 1};

        emitter.fadeout_period = 0.1;
        emitter.emitter_lifetime = 0.2;

        emitter.position = position;
    }

    {
        emitter := New(Particle_Emitter);
        array_add(*live_emitters, emitter);

        emitter.size0 = 0.015;
        emitter.size1 = 0.06;

        emitter.color0 = .{1, 1, 1, 1};
        emitter.color1 = .{.94, 1, 0.05, 1};

        emitter.fadeout_period = 0.3;
        emitter.emitter_lifetime = 0.3;

        emitter.position = position;
    }


    play_sound(*sound_player_dies);
}

test_against_invaders :: (bullet: *Bullet) -> bool {
    for live_invaders {
        if distance(bullet.position, it.position) < current_invader_radius {
            destroy_invader(it);
            return true;
        }
    }

    return false;
}

set_invincibility :: (duration: float) {
    if ship_invincibility_countdown <= 0   {
        play_sound(*sound_shield_begin);
    }

    ship_invincibility_countdown = duration;
}

player_got_pickup :: (pickup: *Pickup) {
    if pickup.type == {
        case .EXTRA_BULLET;
            if ship_shot_type == .STRAIGHT_SINGLE then ship_shot_type = .STRAIGHT_DOUBLE;
            else if ship_shot_type == .STRAIGHT_DOUBLE then ship_shot_type = .STRAIGHT_TRIPLE;
            else if ship_shot_type == .STRAIGHT_TRIPLE then {
                ship_shot_type = .STRAIGHT_SINGLE;
                play_sound(*sound_bullet_reset);
            }

        case .SHIELD;
            set_invincibility(SHIP_INVINCIBILITY_TIME);

        case .V_SHOT;
            ship_v_shot_stability_countdown = SHIP_V_SHOT_STABILITY_TIME;
            ship_v_shot_angle_target += SHIP_V_SHOT_DEGREES_PER_PICKUP;
            Clamp(*ship_v_shot_angle_target, 0, SHIP_V_SHOT_DEGREES_MAX);

        case .PENETRATING;
            ship_penetrating_countdown += SHIP_PENETRATING_TIME;

        case .TURBO;
            ship_turbo_shots += TURBO_SHOTS_PER_PICKUP;
            Clamp(*ship_turbo_shots, 0, TURBO_SHOTS_MAX);

            ship_shot_cooldown = 0;
    }
}

linear_move :: (position : *Vector2, velocity : *Vector2, dt : float) {
    position.x += velocity.x * dt;
    position.y += velocity.y * dt;
}

ship_is_shielded :: () -> bool {
    if ship_invincibility_countdown > 0 return true;
    return false;
}

draw_bar :: (pos: Vector2, width: float, height: float, color: Vector4) {
    p0, p1, p2, p3 := pos;
    p0.x -= width * .5;
    p1.x += width * .5;
    p2.x += width * .5;
    p3.x -= width * .5;
    p2.y += height;
    p3.y += height;

    Simp.set_shader_for_images(*meter_map);
    Simp.immediate_begin();
    Simp.immediate_quad(p0, p1, p2, p3, color);
    Simp.immediate_flush();
}

draw_ship_at :: (texture: Texture, pos: Vector2, size: Vector2, color: Vector4) {
    ship_color := color;

    if ship_is_shielded() {
        rate : float64 = 1.5;
        if ship_invincibility_countdown < 1.7 rate = 4.5;

        theta := last_time * TAU64 * rate;
        y := cos(cast(float) theta);

        k := (y + 1.0) * 0.5;

        if k < 0 k = 0;
        if k > 1 k = 1;

        k *= 0.8;

        ship_color.x = 1;
        ship_color.y = k;
        ship_color.z = k;
    }

    render_sprite_quad_centered(*texture, pos, size, ship_color);

    {
        bg_a := Vector4.{.22, .5, .72, 1};
        bg_b := Vector4.{.4,  .8, .8,  1};

        fg_a := Vector4.{.95, .65, .01, 1};
        fg_b := Vector4.{1, .25, .21, 1};

        fg := fg_a;
        bg := bg_a;
        if ship_turbo_shots {
            now := seconds_since_init();
            theta := cast(float) fmod_cycling(2400 * now, 360);
            radians := theta * (TAU / 360);

            t := (cos(radians) + 1) * .5;
            Clamp(*t, 0, 1);

            fg = lerp(fg_a, fg_b, t);
            bg = lerp(bg_a, bg_b, t);
        }

        width  := size.x * .1 * playfield_width;
        height := size.y * .7 * playfield_width;

        bottom_center := window_coords_from_relative(pos);
        bottom_center.y -= height * .5;

        draw_bar(bottom_center, width, height, bg);

        fullness := ship_turbo_shots / cast(float) TURBO_SHOTS_MAX;

        shrink_x := width * .1;
        shrink_y := shrink_x;

        filled_height := (height - 2 * shrink_y) * fullness;
        draw_bar(bottom_center + .{0, shrink_y}, width - 2*shrink_x, filled_height, fg);
    }
}

render_sprite_quad_centered :: (texture: *Texture, _pos: Vector2, size: Vector2, color: Vector4, theta := 0.0) {
    Simp.set_shader_for_images(texture);

    pos := window_coords_from_relative(_pos);
    h := Vector2.{size.x*.5*playfield_width, 0};
    v := Vector2.{0, size.y*.5*playfield_width};

    radians := (TAU / 360.0) * theta;

    h = rotate(h, radians);
    v = rotate(v, radians);

    p0 := pos - h - v;
    p1 := pos + h - v;
    p2 := pos + h + v;
    p3 := pos - h + v;

    Simp.immediate_quad(p0, p1, p2, p3,  color);
}

play_sound :: (data: *Sound_Data, perturb: bool = true, category := Sound_Category.GENERAL_SFX) -> *Sound_Stream {
    stream := Sound.make_stream(data, category);

    if perturb {
        stream.user_volume_scale = random_get_within_range(0.5,  1);
        stream.rate_scale        = random_get_within_range(0.75, 1.22);
    }

    start_playing(stream);
    return stream;
}

my_init_fonts :: () {
    path := path_strip_filename(get_path_of_running_executable());

    set_working_directory(path);
    pixel_height := playfield_height / 24;

    my_font = Simp.get_font_at_size("data", "Anonymous Pro.ttf", pixel_height);
    assert(my_font != null);
}

/*
resize_playfield :: () {
    if !window_height return;  // Avoid dividing by zero!

    window_aspect = window_width / cast(float) window_height;

   if values_are_close(window_aspect, ASPECT) {
        playfield_width  = window_width;
        playfield_height = window_height;
    } else if window_aspect > ASPECT {
        playfield_height = window_height;
        playfield_width  = cast(s32)(window_height * ASPECT);
    } else {
        playfield_width  = window_width;
        playfield_height = cast(s32)(window_width / ASPECT);
    }
}*/

resize_playfield :: () {
    if !window_height return;  // Avoid dividing by zero!

    window_aspect = window_width / cast(float) window_height;
    logical_aspect := LOGICAL_WIDTH / cast(float) LOGICAL_HEIGHT;

    if values_are_close(window_aspect, logical_aspect) {
        playfield_width  = LOGICAL_WIDTH;
        playfield_height = LOGICAL_HEIGHT;
        scale_factor = window_width / cast(float) LOGICAL_WIDTH;
    } else if window_aspect > logical_aspect {
        playfield_height = LOGICAL_HEIGHT;
        playfield_width  = LOGICAL_WIDTH;
        scale_factor = window_height / cast(float) LOGICAL_HEIGHT;
    } else {
        playfield_width  = LOGICAL_WIDTH;
        playfield_height = LOGICAL_HEIGHT;
        scale_factor = window_width / cast(float) LOGICAL_WIDTH;
    }

    print("Playfield: %x%, Scale: %\n", playfield_width, playfield_height, scale_factor);
}

init_ship_position :: () {
    ship_position.x = .5;
    ship_position.y = .05;

    set_invincibility(RESPAWN_INVINCIBILITY_TIME);
    ship_shot_type = .STRAIGHT_SINGLE;
    ship_shot_cooldown = 0;
    ship_penetrating_countdown = 0;
    ship_turbo_shots = 0;

    ship_v_shot_stability_countdown = 0;
    ship_v_shot_angle_target        = 0;
    ship_v_shot_angle_current       = 0;
}

window_coords_from_relative :: (v: Vector2) -> Vector2 {
    return window_coords_from_absolute(v * cast(float) playfield_width);
}

/*
window_coords_from_absolute :: (v: Vector2) -> Vector2 {
    result := v;

    delta: float;
    if window_aspect > ASPECT {
        delta = (window_width - playfield_width) / 2.;
        result.x += delta;
    } else {
        delta = (window_height - playfield_height) / 2.;
        result.y += delta;
    }
    assert(delta >= 0, "Negative delta (%), wtf bro", delta);

    return result;
}*/

window_coords_from_absolute :: (v: Vector2) -> Vector2 {
    result := v * scale_factor;

    // Center the scaled playfield in the window
    offset_x := (window_width - (playfield_width * scale_factor)) * 0.5;
    offset_y := (window_height - (playfield_height * scale_factor)) * 0.5;

    result.x += offset_x;
    result.y += offset_y;

    return result;
}

absolute_coords_from_window :: (window_pos: Vector2) -> Vector2 {
    offset_x := (window_width - (playfield_width * scale_factor)) * 0.5;
    offset_y := (window_height - (playfield_height * scale_factor)) * 0.5;

    result := window_pos;
    result.x -= offset_x;
    result.y -= offset_y;
    result /= scale_factor;

    return result;
}