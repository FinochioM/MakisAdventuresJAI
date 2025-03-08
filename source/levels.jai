Level :: struct {
    name: string;
    map_name: string;

    // level-specific data here:
    spawn_point: Vector2 = .{0, 0};  // Default player spawn position
    background_music: string;        // Music file to play

    // Custom level data (for game progression, etc.)
    custom_flags: u32;
}

game_levels: [..] Level;

current_level_index: s32 = -1;

init_levels :: () {
    for * game_levels {
        if it.name free(it.name);
        if it.map_name free(it.map_name);
        if it.background_music.count > 0 free(it.background_music);
    }
    array_reset(*game_levels);

    register_level("Home Village", "LEVEL1", .{LOGICAL_WIDTH / 2, LOGICAL_HEIGHT / 2});
    register_level("Dark Forest", "LEVEL2", .{LOGICAL_WIDTH / 2, LOGICAL_HEIGHT / 2});

    print("Registered % levels\n", game_levels.count);

    if game_levels.count > 0 {
        success := load_level(0);
        if !success {
            print("Failed to load initial level!\n");
        }
    } else {
        print("No levels registered!\n");
    }
}

register_level :: (name: string, map_name: string, spawn_point: Vector2 = .{0, 0},
                  background_music: string = "", custom_flags: u32 = 0) -> s32 {
    level := array_add(*game_levels);
    level.name = copy_string(name);
    level.map_name = copy_string(map_name);
    level.spawn_point = spawn_point;

    if background_music.count > 0 {
        level.background_music = copy_string(background_music);
    } else {
        level.background_music = "";
    }

    level.custom_flags = custom_flags;
    return cast(s32) game_levels.count - 1;
}

load_level :: (level_index: s32) -> bool {
    if level_index < 0 || level_index >= game_levels.count {
        print("Error: Invalid level index %\n", level_index);
        return false;
    }

    level := *game_levels[level_index];

    success := load_map_by_name(*tile_system, level.map_name);
    if !success {
        print("Failed to load map for level: %\n", level.name);
        return false;
    }

    // Update current level index
    current_level_index = level_index;

    // Handle level-specific initialization here
    // setting player position to spawn point could be an example.

    print("Successfully loaded level: %\n", level.name);
    return true;
}

load_level_by_name :: (level_name: string) -> bool {
    for game_levels {
        if it.name == level_name {
            return load_level(cast(s32) it_index);
        }
    }

    print("Error: Level '%' not found\n", level_name);
    return false;
}

load_next_level :: () -> bool {
    next_index := (current_level_index + 1) % game_levels.count;
    return load_level(cast(s32) next_index);
}

get_current_level :: () -> *Level {
    if current_level_index < 0 || current_level_index >= game_levels.count {
        return null;
    }
    return *game_levels[current_level_index];
}

update_current_level :: (dt: float) {
    level := get_current_level();
    if !level return;

    // I could mplement level-specific update logic here
    // checking win conditions, spawning enemies, etc.?
}

release_levels :: () {
    for * game_levels {
        free(it.name);
        free(it.map_name);
        if it.background_music.count > 0 free(it.background_music);
    }
    array_free(game_levels);
}

fader_alpha : float = 0;
fader_text := "";

update_level_transition :: (dt: float) -> bool {
    if fader_alpha > 0 {
        fader_alpha -= dt;
        if fader_alpha < 0 fader_alpha = 0;
        return true;
    }
    return false;
}

start_level_transition :: (text: string) {
    if fader_text free(fader_text.data);
    fader_text = copy_string(text);
    fader_alpha = 1.0;
}

render_level_transition :: () {
    if fader_alpha <= 0 return;

    Simp.set_shader_for_color();
    Simp.immediate_quad(
        0, 0,
        cast(float) window_width, cast(float) window_height,
        Vector4.{0, 0, 0, fader_alpha}
    );

    if fader_text.count > 0 {
        Simp.set_shader_for_text();

        text_width := Simp.draw_text(my_font, -10000, -10000, fader_text);

        text_x := (window_width - text_width) * 0.5;
        text_y := window_height * 0.5;

        Simp.draw_text(my_font, xx text_x, xx text_y, fader_text, Vector4.{1, 1, 1, fader_alpha});
    }
}

load_map_by_name :: (tile_system: *Tile_System, map_name: string) -> bool {
    possible_filenames: [..] string;
    possible_filenames.allocator = temp;

    array_add(*possible_filenames, map_name);

    if !ends_with(map_name, ".map") {
        array_add(*possible_filenames, tprint("%1.map", map_name));
    }

    if !ends_with(map_name, ".dat") {
        array_add(*possible_filenames, tprint("%1.dat", map_name));
    }

    array_add(*possible_filenames, tprint("%/%", data_folder, map_name));
    if !ends_with(map_name, ".map") {
        array_add(*possible_filenames, tprint("%/%1.map", data_folder, map_name));
    }
    if !ends_with(map_name, ".dat") {
        array_add(*possible_filenames, tprint("%/%1.dat", data_folder, map_name));
    }

    success := false;
    filename: string;

    print("Trying to load map %... Checking these locations:\n", map_name);
    for possible_filenames {
        print("  %\n", it);
        file, file_success := file_open(it, for_writing=false);
        if file_success {
            success = true;
            filename = it;
            print("Found map at: %\n", filename);

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

            print("Map % has % layers\n", filename, layer_count);

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

                print("  Loaded layer '%' with %x% tiles\n",
                      layer.name, tile_system.grid_width, tile_system.grid_height);
            }

            file_close(*file);
            print("Map % loaded successfully\n", filename);
            break;
        }
    }

    if !success {
        print("Failed to load map % from any location.\n", map_name);
    }

    return success;
}

render_level_info :: () {
    level := get_current_level();
    if !level return;

    Simp.set_shader_for_text();

    level_text := tprint("Current Level: % (%)", level.name, current_level_index);
    Simp.draw_text(my_font, 20, window_height - 60, level_text, Vector4.{1, 1, 0, 1});

    map_text := tprint("Map: %", level.map_name);
    Simp.draw_text(my_font, 20, window_height - 90, map_text, Vector4.{1, 1, 0, 1});

    help_text := "Press N to switch levels";
    Simp.draw_text(my_font, 20, window_height - 120, help_text, Vector4.{0.7, 0.7, 0.7, 1});
}