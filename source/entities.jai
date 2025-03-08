Entity :: struct {
    using position : Vector2;
    velocity : Vector2;

    map: *Texture;
}

Pickup_Type :: enum u32 {
    UNINITIALIZED;
    EXTRA_BULLET;
    SHIELD;
    V_SHOT;
    PENETRATING;
    TURBO;
}

Pickup :: struct {
    using entity: Entity;
    type := Pickup_Type.UNINITIALIZED;
}

Invader_Action :: enum u8 {
    FALLING_IN    :: 0;
    SPLINING      :: 1;
    POST_SPLINING :: 2;
    SLEEPING      :: 3;
    STRAFING      :: 4;
}

Invader :: struct {
    using entity: Entity;

    spawn_position:  Vector2;
    
    shot\_countdown := -1.0;
    
    line_index: s32;
    slot_index: s32;

    action: Invader_Action;

    theta := -90.0;  // In degrees.

    strafe_path: Path;
}

Bullet :: struct {
    using entity: Entity;

    color: Vector4;
    emitter: *Particle_Emitter;
    player_friendly := true;

    bullet_flags: enum_flags u16 {
        PENETRATING :: 0x1; 
    }
}

release :: (invader: *Invader) {
    release(*invader.strafe_path);
}
