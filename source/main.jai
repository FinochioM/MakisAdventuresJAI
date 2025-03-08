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

//#load "entities.jai";
//#load "levels.jai";
//#load "particles.jai";
//#load "simulate.jai";
//#load "pathing.jai";
#load "tiles.jai";
#load "map_editor.jai";

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

my_font: *Simp.Dynamic_Font;

current_dt: float = 0.016667;
last_time:  float64;
DT_MAX : float : 0.15;

data_folder: string;

path                    : Texture;
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

    tile_system = init_tile_system(8, 8, LOGICAL_WIDTH / 8, LOGICAL_HEIGHT / 8);

    add_layer(*tile_system, "background", 0);
    add_layer(*tile_system, "objects", 10);
    add_layer(*tile_system, "foreground", 20);

    objects_layer := get_layer(*tile_system, "objects");
    if objects_layer objects_layer.collision_layer = true;

    init_tile_textures();

    init_editor(*tile_system);

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
        update_editor(*tile_system);

        Simp.clear_render_target(.1, .1, .1, 1);

        playfield_x0 := window_coords_from_absolute(.{0, 0});
        playfield_x1 := window_coords_from_absolute(.{xx playfield_width, xx playfield_height});
        Simp.set_scissor(xx playfield_x0.x, xx playfield_x0.y, xx playfield_x1.x, xx playfield_x1.y);

        render_tile_system(*tile_system);
        render_editor_overlay(*tile_system);

        Simp.clear_scissor();

        Simp.swap_buffers(window);

        memory_visualizer_per_frame_update();
    }

    release_tile_system(*tile_system);
    sound_player_shutdown();
}

init_textures :: () {
    grass                   = make_texture("grass.png");
    path                    = make_texture("path.png");
}

init_tile_textures :: () {
    grass_tile_index := load_tile_texture(*tile_system, "grass.png");
    path_tile_index := load_tile_texture(*tile_system, "path.png");
}

make_texture :: (name: string) -> Texture, bool {
    filename := tprint("%/%", data_folder, name);

    result: Texture;
    success := Simp.texture_load_from_file(*result, filename, nearest = true);

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

    for event : events_this_frame {
        if event.type == .QUIT {
            should_quit_game = true;
            break;
        }

        if is_blocking_keys && event.type == .KEYBOARD continue;

        if event.key_code == .ESCAPE
            if event.key_pressed should_quit_game = true;

        if event.key_code == #char "E"
            if event.key_pressed toggle_editor();
    }
}

linear_move :: (position : *Vector2, velocity : *Vector2, dt : float) {
    position.x += velocity.x * dt;
    position.y += velocity.y * dt;
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
    pixel_height := playfield_height / 12;

    my_font = Simp.get_font_at_size("data", "Anonymous Pro.ttf", pixel_height);
    assert(my_font != null);
}

resize_playfield :: () {
    if !window_height return;  // Avoid dividing by zero!

    window_aspect = window_width / cast(float) window_height;

    playfield_width = LOGICAL_WIDTH;
    playfield_height = LOGICAL_HEIGHT;

    scale_x := window_width / cast(float) LOGICAL_WIDTH;
    scale_y := window_height / cast(float) LOGICAL_HEIGHT;

    if scale_x < scale_y {
        scale_factor = scale_x;
    } else {
        scale_factor = scale_y;
    }

    print("Playfield: %x%, Scale: %\n", playfield_width, playfield_height, scale_factor);
}

window_coords_from_relative :: (v: Vector2) -> Vector2 {
    return window_coords_from_absolute(v * cast(float) playfield_width);
}

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

load_map_by_name :: (tile_system: *Tile_System, map_name: string) -> bool {
    filename := map_name;
    if !ends_with(filename, ".map") {
        filename = sprint("%%.map", filename);
    }

    file, success := file_open(filename, for_writing=false);
    if !success {
        print("Failed to load map %\n", filename);
        return false;
    }

    for * layer: tile_system.layers {
        free(layer.tiles.data);
        free(layer.name);
    }
    array_reset(*tile_system.layers);

    read_struct(*file, *tile_system.tile_width);
    read_struct(*file, *tile_system.tile_height);
    read_struct(*file, *tile_system.grid_width);
    read_struct(*file, *tile_system.grid_height);

    layer_count: s32;
    read_struct(*file, *layer_count);

    for 0..layer_count-1 {
        name_length: s32;
        read_struct(*file, *name_length);
        name_data := alloc(name_length);
        read_bytes(*file, name_data, name_length);
        name: string;
        name.data = name_data;
        name.count = cast(s64) name_length;

        layer := array_add(*tile_system.layers);
        layer.name = name;

        read_struct(*file, *layer.z_index);
        read_struct(*file, *layer.visible);
        read_struct(*file, *layer.collision_layer);
        read_struct(*file, *layer.update_layer);

        layer.tiles = NewArray(tile_system.grid_width * tile_system.grid_height, Tile);
        for * tile: layer.tiles {
            read_struct(*file, tile);
        }
    }

    file_close(*file);
    print("Map % loaded successfully\n", filename);
    return true;
}