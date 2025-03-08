Filename_Mode :: enum { SAVE; LOAD; };

Map_Editor :: struct {
    active: bool;
    current_layer_index: s32;
    current_tile_index: s32;
    show_grid: bool = true;
    save_filename: string = "map.dat";

    is_entering_filename: bool;
    filename_buffer: [256] u8;
    filename_length: s32;
    filename_mode: Filename_Mode;

    is_placing: bool;
    is_erasing: bool;
}

editor: Map_Editor;

is_blocking_keys: bool;

toggle_editor :: () {
    editor.active = !editor.active;
}

init_editor :: (tile_system: *Tile_System) {
    editor.active = false;
    editor.current_layer_index = 0;
    editor.current_tile_index = 0;
    editor.is_placing = false;
    editor.is_erasing = false;
    editor.is_entering_filename = false;
    editor.filename_length = 0;
    memset(editor.filename_buffer.data, 0, 256);
    is_blocking_keys = false;
}

update_editor :: (tile_system: *Tile_System) {
    if !editor.active return;

    if editor.is_entering_filename {
        is_blocking_keys = true;

        for event: events_this_frame {
            if event.type == .KEYBOARD {
                if event.key_pressed {
                    if event.key_code == .ESCAPE {
                        editor.is_entering_filename = false;
                        is_blocking_keys = false;
                    } else if event.key_code == .ENTER {
                        editor.is_entering_filename = false;
                        is_blocking_keys = false;

                        if editor.filename_length > 0 {
                            new_filename: string;
                            new_filename.data = editor.filename_buffer.data;
                            new_filename.count = cast(s64) editor.filename_length;

                            if !ends_with(new_filename, ".map") {
                                new_filename = sprint("%.map", new_filename);
                            }

                            if editor.filename_mode == .SAVE {
                                save_map(tile_system, new_filename);
                            } else {
                                load_map(tile_system, new_filename);
                            }
                        }
                    } else if event.key_code == .BACKSPACE {
                        if editor.filename_length > 0 editor.filename_length -= 1;
                    } else {
                        key := cast(u8) event.key_code;
                        if (key >= #char "a" && key <= #char "z") ||
                           (key >= #char "A" && key <= #char "Z") ||
                           (key >= #char "0" && key <= #char "9") ||
                           key == #char "_" || key == #char "-" || key == #char "." {
                            if editor.filename_length < 255 {
                                editor.filename_buffer[editor.filename_length] = key;
                                editor.filename_length += 1;
                            }
                        }
                    }
                }
            }
        }

        return;
    } else {
        is_blocking_keys = false;
    }

    for event: events_this_frame {
        if event.type == .KEYBOARD && event.key_pressed {
            if event.key_code == {
                case #char "G"; editor.show_grid = !editor.show_grid;
                case #char "S";
                    if (input_button_states[Key_Code.CTRL] & Key_Current_State.DOWN) != 0 {
                        start_filename_entry(.SAVE);
                    }
                case #char "L";
                    if (input_button_states[Key_Code.CTRL] & Key_Current_State.DOWN) != 0 {
                        start_filename_entry(.LOAD);
                    }
                case .ARROW_RIGHT;    cycle_tile(tile_system, 1);
                case .ARROW_LEFT;     cycle_tile(tile_system, -1);
                case .ARROW_UP;       cycle_layer(tile_system, 1);
                case .ARROW_DOWN;     cycle_layer(tile_system, -1);
            }
        }
    }

    mouse_x, mouse_y := get_mouse_pointer_position();
    v := Vector2.{
        cast(float) mouse_x,
        cast(float) (window_height - mouse_y)
    };
    world_pos := absolute_coords_from_window(v);
    grid_x, grid_y := pixel_to_grid(tile_system, world_pos.x, world_pos.y);

    if (input_button_states[Key_Code.MOUSE_BUTTON_LEFT] & Key_Current_State.DOWN) != 0 {
        editor.is_placing = true;
    }
    if (input_button_states[Key_Code.MOUSE_BUTTON_RIGHT] & Key_Current_State.DOWN) != 0 {
        editor.is_erasing = true;
    }

    if (input_button_states[Key_Code.MOUSE_BUTTON_LEFT] & Key_Current_State.DOWN) == 0 {
        editor.is_placing = false;
    }
    if (input_button_states[Key_Code.MOUSE_BUTTON_RIGHT] & Key_Current_State.DOWN) == 0 {
        editor.is_erasing = false;
    }

    if editor.is_placing && is_valid_grid_pos(tile_system, grid_x, grid_y) {
        place_tile(tile_system, grid_x, grid_y);
    }

    if editor.is_erasing && is_valid_grid_pos(tile_system, grid_x, grid_y) {
        erase_tile(tile_system, grid_x, grid_y);
    }
}

start_filename_entry :: (mode: Filename_Mode) {
    editor.is_entering_filename = true;
    editor.filename_mode = mode;
    editor.filename_length = 0;
    memset(editor.filename_buffer.data, 0, 256);
}

render_editor_overlay :: (tile_system: *Tile_System) {
    if !editor.active return;
    if editor.show_grid {
        render_grid(tile_system);
    }
    layer := get_layer_by_index(tile_system, editor.current_layer_index);
    layer_name := ifx layer then layer.name else "None";

    Simp.set_shader_for_text();
    text_y := cast(float) (window_height - 20);
    Simp.draw_text(my_font, xx 20.0, xx text_y, tprint("Editor Mode - Layer: % (%)",
                  layer_name, editor.current_layer_index));

    text_y -= 30.0;
    Simp.draw_text(my_font, xx 20.0, xx text_y, tprint("Tile: % - Grid: Show=%",
                  editor.current_tile_index, editor.show_grid));

    text_y -= 30.0;
    Simp.draw_text(my_font, xx 20.0, xx text_y, "Controls: Arrows=cycle layers/tiles, G=grid, Ctrl+S=save, Ctrl+L=load");

    if editor.is_entering_filename {
        Simp.set_shader_for_color();
        Simp.immediate_quad(
            cast(float) (window_width/2 - 200), cast(float) (window_height/2 - 50),
            cast(float) (window_width/2 + 200), cast(float) (window_height/2 + 50),
            Vector4.{0.1, 0.1, 0.1, 0.8}
        );

        Simp.set_shader_for_text();
        mode_text := ifx editor.filename_mode == .SAVE then "Save Map As:" else "Load Map:";
        Simp.draw_text(my_font, xx cast(float) (window_width/2 - 180), xx cast(float) (window_height/2 + 20), mode_text);


        filename: string;
        filename.data = editor.filename_buffer.data;
        filename.count = cast(s64) editor.filename_length;

        text_x := cast(float) (window_width/2 - 180);
        text_y := cast(float) (window_height/2 - 10);
        text_width := Simp.draw_text(my_font, xx text_x, xx text_y, filename);

        if (cast(s64)(seconds_since_init() * 2) % 2) == 0 {
            cursor_x := text_x + cast(float) text_width;
            Simp.draw_text(my_font, xx cursor_x, xx text_y, "|");
        }

        Simp.draw_text(my_font, xx cast(float) (window_width/2 - 180), xx cast(float) (window_height/2 - 40), "Press Enter to confirm, Esc to cancel");
    }

    render_tile_preview(tile_system);
}

render_grid :: (tile_system: *Tile_System) {
    Simp.set_shader_for_color();

    grid_color := Vector4.{0.5, 0.5, 0.5, 0.3};
    line_thickness := 1.0;

    for x: 0..tile_system.grid_width {
        pixel_x := x * tile_system.tile_width;
        screen_x := window_coords_from_absolute(.{xx pixel_x, 0});

        Simp.immediate_quad(
            screen_x.x - line_thickness/2, 0.0,
            screen_x.x + line_thickness/2, cast(float) window_height,
            grid_color
        );
    }

    for y: 0..tile_system.grid_height {
        pixel_y := y * tile_system.tile_height;
        screen_y := window_coords_from_absolute(.{0, xx pixel_y});

        Simp.immediate_quad(
            0.0, screen_y.y - line_thickness/2,
            cast(float) window_width, screen_y.y + line_thickness/2,
            grid_color
        );
    }
}

is_valid_grid_pos :: (tile_system: *Tile_System, x: s32, y: s32) -> bool {
    return x >= 0 && x < tile_system.grid_width && y >= 0 && y < tile_system.grid_height;
}

cycle_tile :: (tile_system: *Tile_System, direction: s32) {
    editor.current_tile_index += direction;

    if editor.current_tile_index < -1 {
        editor.current_tile_index = cast(s32) tile_system.tile_textures.count - 1;
    } else if editor.current_tile_index >= tile_system.tile_textures.count {
        editor.current_tile_index = -1;
    }
}

cycle_layer :: (tile_system: *Tile_System, direction: s32) {
    editor.current_layer_index += direction;

    if editor.current_layer_index < 0 {
        editor.current_layer_index = cast(s32) tile_system.layers.count - 1;
    } else if editor.current_layer_index >= tile_system.layers.count {
        editor.current_layer_index = 0;
    }
}

get_layer_by_index :: (tile_system: *Tile_System, index: s32) -> *Layer {
    if index < 0 || index >= tile_system.layers.count return null;
    return *tile_system.layers[index];
}

place_tile :: (tile_system: *Tile_System, x: s32, y: s32) {
    layer := get_layer_by_index(tile_system, editor.current_layer_index);
    if !layer return;

    set_tile(tile_system, layer.name, x, y, editor.current_tile_index);
}

erase_tile :: (tile_system: *Tile_System, x: s32, y: s32) {
    layer := get_layer_by_index(tile_system, editor.current_layer_index);
    if !layer return;

    set_tile(tile_system, layer.name, x, y, -1); // -1 represents "no tile"
}

render_tile_preview :: (tile_system: *Tile_System) {
    if editor.current_tile_index < 0 || editor.current_tile_index >= tile_system.tile_textures.count return;

    preview_size := 64.0;
    texture := *tile_system.tile_textures[editor.current_tile_index];

    Simp.set_shader_for_images(texture);
    Simp.immediate_quad(
        cast(float) window_width - preview_size - 10.0,
        cast(float) window_height - preview_size - 10.0,
        cast(float) window_width - 10.0,
        cast(float) window_height - 10.0,
        .{1, 1, 1, 1}
    );
}

save_map :: (tile_system: *Tile_System, filename := "") {
    save_path := filename;
    if save_path == "" save_path = editor.save_filename;

    file, success := file_open(save_path, for_writing=true, keep_existing_content=false);
    if !success {
        print("Failed to open % for writing\n", save_path);
        return;
    }

    write_struct(*file, *tile_system.tile_width);
    write_struct(*file, *tile_system.tile_height);
    write_struct(*file, *tile_system.grid_width);
    write_struct(*file, *tile_system.grid_height);

    layer_count := cast(s32) tile_system.layers.count;
    write_struct(*file, *layer_count);

    for * layer: tile_system.layers {
        name_length := cast(s32) layer.name.count;
        write_struct(*file, *name_length);
        write_bytes(*file, layer.name.data, name_length);

        write_struct(*file, *layer.z_index);
        write_struct(*file, *layer.visible);
        write_struct(*file, *layer.collision_layer);
        write_struct(*file, *layer.update_layer);

        for tile: layer.tiles {
            write_struct(*file, *tile);
        }
    }

    file_close(*file);
    print("Map saved to %\n", save_path);
}

load_map :: (tile_system: *Tile_System, filename := "") {
    load_path := filename;
    if load_path == "" load_path = editor.save_filename;

    file, success := file_open(load_path, for_writing=false);
    if !success {
        print("Failed to open % for reading\n", load_path);
        return;
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
    print("Map loaded from %\n", load_path);
}

Input :: #import "Input";
#import "Basic";

write_struct :: (file: *File, data: *$T) {
    success := file_write(file, data, size_of(T));
    assert(success);
}

read_struct :: (file: *File, data: *$T) {
    success := file_read(file, data, size_of(T));
    assert(success);
}

write_bytes :: (file: *File, data: *void, size: s64) {
    success := file_write(file, data, size);
    assert(success);
}

read_bytes :: (file: *File, data: *void, size: s64) {
    success := file_read(file, data, size);
    assert(success);
}