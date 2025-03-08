fader_alpha : float = 0;
fader_text := "";

Level_Config :: struct {
    invaders_per_line : s32 = 3;
    num_lines         : s32 = 3;

    enemy_scale       := 1.0;
}

DEFINED_LEVELS :: Level_Config.[
    .{num_lines = 2, invaders_per_line = 5, enemy_scale = 1.4},
    .{num_lines = 3, invaders_per_line = 4, enemy_scale = 1.4},
    .{num_lines = 3, invaders_per_line = 5, enemy_scale = 1.3},
    .{num_lines = 4, invaders_per_line = 5, enemy_scale = 1.3},
    .{num_lines = 4, invaders_per_line = 7, enemy_scale = 1.2},
    .{num_lines = 5, invaders_per_line = 7, enemy_scale = 1.2},
    .{num_lines = 6, invaders_per_line = 7, enemy_scale = 1.1},
    .{num_lines = 6, invaders_per_line = 8, enemy_scale = 1.0},
];

init_new_level :: (index: int) {
    orig_index := index;
    
    time_of_level_start := seconds_since_init();
    dudes_spawned_in_this_level = 0;
    strafe_countdown = 2.0;
    
    Clamp(*index, 0, DEFINED_LEVELS.count-1);
    config := DEFINED_LEVELS[index];

    current_invader_radius = INVADER_RADIUS_AT_SCALE_1 * config.enemy_scale;
    
    for * layout_lines release(it);
    array_reset(*layout_lines);

    for line_index: 0..config.num_lines-1 {
        line := array_add(*layout_lines);
        line.y  = 0.6 + 0.1 * line_index;
        line.line_index = line_index;
        
        num_invaders := config.invaders_per_line;

        margin := current_invader_radius * 0.2;
        line_width := num_invaders * current_invader_radius * 2 + (num_invaders - 1) * margin;

        x0 := 0.5 - line_width * .5;
        x1 := 0.5 + line_width * .5;

        line.x0 = x0;
        line.x1 = x1;

        line.spawn_countdown = 0.1 + line_index * 1.0;
        array_resize(*line.invader_slots, num_invaders);
        
        for invader_index: 0..num_invaders-1 {
            t := invader_index / cast(float)(num_invaders - 1);
            position := Vector2.{lerp(line.x0, line.x1, t), line.y};
            line.invader_slots[invader_index].position = position;
        }
    }

    // play_sound(*entity_manager, "new_wave");

    if fader_text free(fader_text.data);

    fader_text = sprint("Stage %", orig_index);
    fader_alpha = 1;

    play_sound(*sound_new_wave, false);
}

spawn_invaders :: (line: *Layout_Line) {
    num_invaders := cast(s32) line.invader_slots.count;
    dudes_spawned_in_this_level += num_invaders;
    
    for invader_index: 0..num_invaders-1 {
        add_invader(line.line_index, invader_index);
    }
}

add_invader :: (line_index: s32, slot_index: s32) {
    invader := New(Invader);
    which := random_get() % cast(u32) invader_maps.count;
    invader.map = *invader_maps[which];
    invader.line_index = line_index;
    invader.slot_index = slot_index;

    invader.position   = get_target_position(invader);
    invader.position.y = live_y_max;
    invader.spawn_position = invader.position;
    
    invader.action = .FALLING_IN;
    
    array_add(*live_invaders, invader);
}



Layout_Line :: struct {
    x0, x1: float;
    y:      float;
    
    horizontal_spacing := 1.0;
    line_index: s32;

    spawn_countdown := 0.1;
    
    invader_slots: [..] Layout_Slot;
}

Layout_Slot :: struct {
    position: Vector2;
}

layout_lines: [..] Layout_Line;

release :: (line: *Layout_Line) {
    array_free(line.invader_slots);
}


formation_offset: Vector2;
time_of_level_start: float64;
dudes_spawned_in_this_level := 0;
current_aggro: float;
strafe_countdown := 2.0;
current_invader_radius: float;
