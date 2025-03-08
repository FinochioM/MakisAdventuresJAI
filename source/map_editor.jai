Map_Editor :: struct {
    active: bool;
    current_layer_index: s32;
    current_tile_index: s32;
    show_grid: bool = true;
    save_filename: string = "map.dat";

    is_placing: bool;
    is_erasing: bool;
}

editor: Map_Editor;

toggle_editor :: () {
    editor.active = !editor.active;
}

init_editor :: (tile_system: *Tile_System) {
    editor.active = false;
    editor.current_layer_index = 0;
    editor.current_tile_index = 0;
    editor.is_placing = false;
    editor.is_erasing = false;
}

update_editor :: (tile_system: *Tile_System) {
    if !editor.active return;

    for event: events_this_frame {
        if event.type == .KEYBOARD && event.key_pressed {
            if event.key_code == {
                case #char "G"; editor.show_grid = !editor.show_grid;
                case #char "S"; if (input_button_states[Key_Code.CTRL] & Key_Current_State.DOWN) != 0 save_map(tile_system);
                case #char "L"; if (input_button_states[Key_Code.CTRL] & Key_Current_State.DOWN) != 0 load_map(tile_system);
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

render_editor_overlay :: (tile_system: *Tile_System) {
    if !editor.active return;

    // Render grid if enabled
    if editor.show_grid {
        render_grid(tile_system);
    }

    // Show current editor state info
    layer := get_layer_by_index(tile_system, editor.current_layer_index);
    layer_name := ifx layer then layer.name else "None";

    Simp.set_shader_for_text();

    text_y := window_height - 20;
    Simp.draw_text(my_font, 20, text_y, tprint("Editor Mode - Layer: % (%)",
                  layer_name, editor.current_layer_index));

    text_y -= 20;
    Simp.draw_text(my_font, 20, text_y, tprint("Tile: % - Grid: Show=%",
                  editor.current_tile_index, editor.show_grid));

    text_y -= 20;
    Simp.draw_text(my_font, 20, text_y, "Controls: Arrows=cycle layers/tiles, G=grid, S=save, L=load");

    // Show currently selected tile as a preview
    render_tile_preview(tile_system);
}

render_grid :: (tile_system: *Tile_System) {
    Simp.set_shader_for_color();

    // Calculate grid spacing based on tile dimensions and scale
    grid_color := Vector4.{0.5, 0.5, 0.5, 0.3};
    line_thickness := 1.0;  // Thickness of grid lines in pixels

    // Draw vertical lines
    for x: 0..tile_system.grid_width {
        pixel_x := x * tile_system.tile_width;
        screen_x := window_coords_from_absolute(.{xx pixel_x, 0});

        // Draw a thin vertical rectangle instead of a line
        Simp.immediate_quad(
            screen_x.x - line_thickness/2, 0.0,
            screen_x.x + line_thickness/2, cast(float) window_height,
            grid_color
        );
    }

    // Draw horizontal lines
    for y: 0..tile_system.grid_height {
        pixel_y := y * tile_system.tile_height;
        screen_y := window_coords_from_absolute(.{0, xx pixel_y});

        // Draw a thin horizontal rectangle instead of a line
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
        editor.current_tile_index = -1; // -1 represents "no tile"
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

    preview_size := 64.0;  // Make this a float
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

save_map :: (tile_system: *Tile_System) {
    file, success := file_open(editor.save_filename, for_writing=true, keep_existing_content=false);
    if !success {
        print("Failed to open % for writing\n", editor.save_filename);
        return;
    }

    // Write header info
    write_struct(*file, *tile_system.tile_width);
    write_struct(*file, *tile_system.tile_height);
    write_struct(*file, *tile_system.grid_width);
    write_struct(*file, *tile_system.grid_height);

    layer_count := cast(s32) tile_system.layers.count;
    write_struct(*file, *layer_count);

    // Write each layer
    for * layer: tile_system.layers {
        name_length := cast(s32) layer.name.count;
        write_struct(*file, *name_length);
        write_bytes(*file, layer.name.data, name_length);

        write_struct(*file, *layer.z_index);
        write_struct(*file, *layer.visible);
        write_struct(*file, *layer.collision_layer);
        write_struct(*file, *layer.update_layer);

        // Write tiles
        for tile: layer.tiles {
            write_struct(*file, *tile);
        }
    }

    file_close(*file);
    print("Map saved to %\n", editor.save_filename);
}

load_map :: (tile_system: *Tile_System) {
    file, success := file_open(editor.save_filename, for_writing=false);
    if !success {
        print("Failed to open % for reading\n", editor.save_filename);
        return;
    }

    // Release existing layers
    for * layer: tile_system.layers {
        free(layer.tiles.data);
        free(layer.name);
    }
    array_reset(*tile_system.layers);

    // Read header info
    read_struct(*file, *tile_system.tile_width);
    read_struct(*file, *tile_system.tile_height);
    read_struct(*file, *tile_system.grid_width);
    read_struct(*file, *tile_system.grid_height);

    layer_count: s32;
    read_struct(*file, *layer_count);

    // Read each layer
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

        // Read tiles
        layer.tiles = NewArray(tile_system.grid_width * tile_system.grid_height, Tile);
        for * tile: layer.tiles {
            read_struct(*file, tile);
        }
    }

    file_close(*file);
    print("Map loaded from %\n", editor.save_filename);
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