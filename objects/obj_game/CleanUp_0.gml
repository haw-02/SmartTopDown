std_cleanup_level();

var _sprites = [
    global.spr_player, global.spr_enemy_a, global.spr_enemy_b,
    global.spr_enemy_c, global.spr_enemy_rl, global.spr_blade,
    global.spr_shield, global.spr_projectile, global.spr_potion,
    global.spr_spike, global.spr_exit,
    global.spr_floor[0], global.spr_floor[1], global.spr_floor[2],
    global.spr_wall[0], global.spr_wall[1], global.spr_wall[2]
];
for (var _i = 0; _i < array_length(_sprites); _i++) {
    if (_sprites[_i] >= 0) sprite_delete(_sprites[_i]);
}

var _sounds = [global.sfx_swing, global.sfx_shot, global.sfx_hit, global.sfx_block, global.sfx_heal, global.sfx_down];
for (var _s = 0; _s < array_length(_sounds); _s++) {
    if (_sounds[_s] >= 0) audio_destroy_stream(_sounds[_s]);
}
