Tile_Data :: struct {
    walkable: bool = true;
    // Add more properties prob when needed
    custom_flags: u32 = 0;  // For game-specific flags
    user_data: *void = null;  // For attaching arbitrary data
}

Tile :: struct {
    texture_index: s32 = -1;  // -1 means empty/no texture
    data: Tile_Data;
}

Layer :: struct {
    name: string;
    visible: bool = true;
    z_index: s32;  // For determining render order
    tiles: [] Tile;  // 2D grid stored as 1D array

    // Layer-specific properties
    collision_layer := false;  // If true, this layer affects collision
    update_layer := false;     // If true, this layer contains updatable entities
}

Tile_System :: struct {
    layers: [..] Layer;
    tile_width, tile_height: s32;  // Pixel dimensions of each tile
    grid_width, grid_height: s32;  // Number of tiles in the grid

    // Tile texture atlas
    tile_textures: [..] Texture;
}

init_tile_system :: (tile_width: s32, tile_height: s32, grid_width: s32, grid_height: s32) -> Tile_System {
    system: Tile_System;
    system.tile_width = tile_width;
    system.tile_height = tile_height;
    system.grid_width = grid_width;
    system.grid_height = grid_height;
    return system;
}

add_layer :: (system: *Tile_System, name: string, z_index: s32) -> *Layer {
    layer := array_add(*system.layers);
    layer.name = copy_string(name);
    layer.visible = true;
    layer.z_index = z_index;

    layer.tiles = NewArray(system.grid_width * system.grid_height, Tile);

    quick_sort(system.layers, (a, b) => a.z_index - b.z_index);

    for * system.layers {
        if it.name == name return it;
    }

    return null;
}

remove_layer :: (system: *Tile_System, name: string) -> bool {
    for system.layers {
        if it.name == name {
            free(it.tiles.data);
            free(it.name);
            array_ordered_remove_by_index(*system.layers, it_index);
            return true;
        }
    }
    return false;
}

get_layer :: (system: *Tile_System, name: string) -> *Layer {
    for * system.layers {
        if it.name == name return it;
    }
    return null;
}

get_tile_index :: inline (system: *Tile_System, x: s32, y: s32) -> s32 {
    if x < 0 || x >= system.grid_width || y < 0 || y >= system.grid_height return -1;
    return y * system.grid_width + x;
}

get_tile :: (system: *Tile_System, layer_name: string, x: s32, y: s32) -> *Tile {
    layer := get_layer(system, layer_name);
    if !layer return null;

    index := get_tile_index(system, x, y);
    if index < 0 return null;

    return *layer.tiles[index];
}

set_tile :: (system: *Tile_System, layer_name: string, x: s32, y: s32, texture_index: s32) -> bool {
    tile := get_tile(system, layer_name, x, y);
    if !tile return false;

    tile.texture_index = texture_index;
    return true;
}

set_tile_data :: (system: *Tile_System, layer_name: string, x: s32, y: s32, walkable: bool = true, custom_flags: u32 = 0, user_data: *void = null) -> bool {
    tile := get_tile(system, layer_name, x, y);
    if !tile return false;

    tile.data.walkable = walkable;
    tile.data.custom_flags = custom_flags;
    tile.data.user_data = user_data;
    return true;
}

pixel_to_grid :: (system: *Tile_System, pixel_x: float, pixel_y: float) -> (grid_x: s32, grid_y: s32) {
    grid_x := cast(s32)(pixel_x / system.tile_width);
    grid_y := cast(s32)(pixel_y / system.tile_height);
    return grid_x, grid_y;
}

grid_to_pixel :: (system: *Tile_System, grid_x: s32, grid_y: s32) -> (pixel_x: float, pixel_y: float) {
    pixel_x := (grid_x + 0.5) * system.tile_width;
    pixel_y := (grid_y + 0.5) * system.tile_height;
    return pixel_x, pixel_y;
}

load_tile_texture :: (system: *Tile_System, filename: string) -> s32 {
    texture, success := make_texture(filename);
    if !success return -1;

    index := system.tile_textures.count;
    array_add(*system.tile_textures, texture);
    return cast(s32)index;
}

render_tile_system :: (system: *Tile_System) {
    for * layer: system.layers {
        if !layer.visible continue;

        for y: 0..system.grid_height-1 {
            for x: 0..system.grid_width-1 {
                index := get_tile_index(system, x, y);
                if index < 0 continue;

                tile := *layer.tiles[index];

                if tile.texture_index < 0 continue;

                if tile.texture_index >= system.tile_textures.count {
                    print("ERROR: Invalid texture index % (max %)\n",
                          tile.texture_index, system.tile_textures.count-1);
                    continue;
                }

                texture := *system.tile_textures[tile.texture_index];
                pixel_x, pixel_y := grid_to_pixel(system, x, y);

                window_pos := window_coords_from_absolute(.{xx pixel_x, xx pixel_y});

                scaled_half_width := (system.tile_width * 0.5) * scale_factor;
                scaled_half_height := (system.tile_height * 0.5) * scale_factor;

                Simp.set_shader_for_images(texture);
                Simp.immediate_quad(
                    window_pos.x - scaled_half_width, window_pos.y - scaled_half_height,
                    window_pos.x + scaled_half_width, window_pos.y + scaled_half_height,
                    .{1, 1, 1, 1}
                );
            }
        }
    }
}

release_tile_system :: (system: *Tile_System) {
    for * layer: system.layers {
        free(layer.tiles.data);
        free(layer.name);
    }
    array_free(system.layers);
    array_free(system.tile_textures);
}

is_position_walkable :: (system: *Tile_System, x: s32, y: s32) -> bool {
    for * layer: system.layers {
        if !layer.collision_layer continue;

        index := get_tile_index(system, x, y);
        if index < 0 return false;

        tile := layer.tiles[index];
        if !tile.data.walkable return false;
    }

    return true;
}

#import "Sort";