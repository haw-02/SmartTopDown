/// Core gameplay for SMART TOP DOWN - scope: section 3.1 only.

#macro STD_TILE 64
#macro STD_TURRET_BARRIER_CAP 60
#macro STD_TURRET_BARRIER_REGEN 2
#macro STD_TURRET_BARRIER_RECOVERY_DELAY 15

function std_cell_x(_cell) { return _cell * STD_TILE + STD_TILE * 0.5; }
function std_cell_y(_cell) { return _cell * STD_TILE + STD_TILE * 0.5; }
function std_grid_x(_x) { return floor(_x / STD_TILE); }
function std_grid_y(_y) { return floor(_y / STD_TILE); }

function std_play_sfx(_snd) {
    if (!global.muted && _snd >= 0) audio_play_sound(_snd, 0, false);
}

function std_load_sprite(_filename, _frames = 1) {
    var _path = working_directory + "textures/" + _filename;
    if (file_exists(_path)) return sprite_add(_path, _frames, false, false, 32, 32);
    return -1;
}

function std_load_stream(_filename) {
    var _path = working_directory + "audio/" + _filename;
    if (file_exists(_path)) return audio_create_stream(_path);
    return -1;
}

function std_cleanup_level() {
    if (variable_global_exists("enemies")) {
        for (var _i = 0; _i < array_length(global.enemies); _i++) {
            if (global.enemies[_i].path_id >= 0) path_delete(global.enemies[_i].path_id);
        }
    }
    if (variable_global_exists("nav_grid") && global.nav_grid >= 0) {
        mp_grid_destroy(global.nav_grid);
        global.nav_grid = -1;
    }
    if (variable_global_exists("wall_grid") && ds_exists(global.wall_grid, ds_type_grid)) {
        ds_grid_destroy(global.wall_grid);
    }
    if (variable_global_exists("spike_grid") && ds_exists(global.spike_grid, ds_type_grid)) {
        ds_grid_destroy(global.spike_grid);
    }
}

function std_make_player(_cx, _cy) {
    return {
        team: "PLAYER",
        x: std_cell_x(_cx), y: std_cell_y(_cy), radius: 22,
        speed: 245, facing: 0, body_facing: 270, attack_facing: 0,
        hp: 100, hp_max: 100,
        shield: 100, shield_max: 100, shield_broken: 0, shield_hit_fx: 0,
        defending: false, potions: 0,
        weapon: "SWORD", weapon_swap_cd: 0,
        arrows: 5, arrows_max: 5,
        melee_cd: 0, ranged_cd: 0, melee_fx: 0, ranged_fx: 0, melee_serial: 0,
        invuln: 0, hurt_fx: 0,
        moving: false, move_amount: 0, anim_phase: 0
    };
}

function std_make_enemy(_type, _cx, _cy) {
    var _hp = 100;
    var _speed = 175;
    var _vision = 620;
    var _shield = 0;

    switch (_type) {
        case "A":
            _hp = 120;
            _speed = 190;
            _vision = 610;
        break;

        case "B":
            _hp = 95;
            _speed = 0;
            _vision = 700;
            _shield = STD_TURRET_BARRIER_CAP;
        break;

        case "C":
            _hp = 85;
            _speed = 180;
            _vision = 740;
        break;

        case "RL":
            _hp = 135;
            _speed = 200;
            _vision = 760;
            _shield = 100;
        break;
    }

    var _enemy = {
        type: _type,
        team: (_type == "RL") ? "RL" : "HOSTILE",
        use_hidden_layers: false,

        x: std_cell_x(_cx),
        y: std_cell_y(_cy),
        radius: 21,

        hp: _hp,
        hp_max: _hp,
        hp_prev: _hp,

        speed: _speed,
        vision: _vision,

        shield: _shield,
        shield_max: _shield,
        shield_hit_fx: 0,

        barrier_idle_time: 0,

        defending: false,
        state: "VIGILAR",
        state_time: 0,

        memory: 0,
        last_x: std_cell_x(_cx),
        last_y: std_cell_y(_cy),

        facing: 180,

        melee_cd: random_range(0, 0.3),
        ranged_cd: random_range(0, 0.5),

        burst_remaining: 0,
        burst_timer: 0,

        path_id: path_add(),
        path_point: 0,
        repath: 0,
        path_goal_x: -1,
        path_goal_y: -1,

        hurt_fx: 0,
        attack_fx: 0,

        moving: false,
        move_amount: 0,
        anim_phase: random(6.28),

        dead: false,

        fitness: 0,
		debug_action: -1,
		damage_dealt: 0,
		damage_taken: 0,
		kills: 0,
		dodges: 0,
		actions_taken: 0,

        nn_weights: undefined
    };

    // Inicialización exclusiva de los agentes RL.
    if (_type == "RL") {
        std_ai_init_agent(_enemy);
    }

    return _enemy;
}

function std_load_level(_index) {
    std_cleanup_level();
    global.level_index = _index;
    global.level = std_level_data(_index);
    global.world_w = global.level.cols * STD_TILE;
    global.world_h = global.level.rows * STD_TILE;
    global.wall_grid = ds_grid_create(global.level.cols, global.level.rows);
    global.spike_grid = ds_grid_create(global.level.cols, global.level.rows);
    ds_grid_clear(global.wall_grid, 0);
    ds_grid_clear(global.spike_grid, 0);

    // Solid outer border.
    for (var _x = 0; _x < global.level.cols; _x++) {
        global.wall_grid[# _x, 0] = 1;
        global.wall_grid[# _x, global.level.rows - 1] = 1;
    }
    for (var _y = 0; _y < global.level.rows; _y++) {
        global.wall_grid[# 0, _y] = 1;
        global.wall_grid[# global.level.cols - 1, _y] = 1;
    }

    for (var _w = 0; _w < array_length(global.level.walls); _w++) {
        var _rect = global.level.walls[_w];
        for (var _yy = _rect[1]; _yy < _rect[1] + _rect[3]; _yy++) {
            for (var _xx = _rect[0]; _xx < _rect[0] + _rect[2]; _xx++) {
                global.wall_grid[# _xx, _yy] = 1;
            }
        }
    }
    for (var _s = 0; _s < array_length(global.level.spikes); _s++) {
        var _sp = global.level.spikes[_s];
        global.spike_grid[# _sp[0], _sp[1]] = 1;
    }

    global.nav_grid = mp_grid_create(0, 0, global.level.cols, global.level.rows, STD_TILE, STD_TILE);
    for (var _gy = 0; _gy < global.level.rows; _gy++) {
        for (var _gx = 0; _gx < global.level.cols; _gx++) {
            if (global.wall_grid[# _gx, _gy] == 1 || global.spike_grid[# _gx, _gy] == 1) {
                mp_grid_add_cell(global.nav_grid, _gx, _gy);
            }
        }
    }

    global.player = std_make_player(global.level.player[0], global.level.player[1]);
    global.enemies = [];
    for (var _e = 0; _e < array_length(global.level.enemies); _e++) {
        var _def = global.level.enemies[_e];
        var _spawned_enemy = std_make_enemy(_def.type, _def.cell[0], _def.cell[1]);
        // RL agents authored into normal levels use the persisted champion.
        // Training/benchmark agents are spawned later with their controlled weights.
        if (_def.type == "RL" && variable_global_exists("evo_manager")) {
            std_manager_apply_best_to_enemy(_spawned_enemy);
        }
        array_push(global.enemies, _spawned_enemy);
    }
    global.potions = [];
    for (var _p = 0; _p < array_length(global.level.potions); _p++) {
        var _pc = global.level.potions[_p];
        array_push(global.potions, { x: std_cell_x(_pc[0]), y: std_cell_y(_pc[1]), active: true, bob: random(6.28) });
    }
    global.projectiles = [];
    global.exit_x = std_cell_x(global.level.exit_cell[0]);
    global.exit_y = std_cell_y(global.level.exit_cell[1]);
    global.exit_open = false;
    global.cam_x = clamp(global.player.x - 640, 0, max(0, global.world_w - 1280));
    global.cam_y = clamp(global.player.y - 360, 0, max(0, global.world_h - 720));
    global.state = "PLAY";
    global.level_banner = 3.2;
    global.message = "ELIMINA LAS AMENAZAS Y LLEGA A LA SALIDA";
    global.message_time = 3.5;
}

function std_wall_cell(_cx, _cy) {
    if (_cx < 0 || _cy < 0 || _cx >= global.level.cols || _cy >= global.level.rows) return true;
    return global.wall_grid[# _cx, _cy] == 1;
}

function std_spike_at(_x, _y) {
    var _cx = std_grid_x(_x);
    var _cy = std_grid_y(_y);
    if (_cx < 0 || _cy < 0 || _cx >= global.level.cols || _cy >= global.level.rows) return false;
    return global.spike_grid[# _cx, _cy] == 1;
}

function std_circle_wall(_x, _y, _r) {
    var _minx = std_grid_x(_x - _r);
    var _maxx = std_grid_x(_x + _r);
    var _miny = std_grid_y(_y - _r);
    var _maxy = std_grid_y(_y + _r);
    for (var _cy = _miny; _cy <= _maxy; _cy++) {
        for (var _cx = _minx; _cx <= _maxx; _cx++) {
            if (std_wall_cell(_cx, _cy)) {
                var _left = _cx * STD_TILE;
                var _top = _cy * STD_TILE;
                var _qx = clamp(_x, _left, _left + STD_TILE);
                var _qy = clamp(_y, _top, _top + STD_TILE);
                if (point_distance(_x, _y, _qx, _qy) < _r) return true;
            }
        }
    }
    return false;
}

function std_move_entity(_entity, _dx, _dy) {
    var _nx = _entity.x + _dx;
    if (!std_circle_wall(_nx, _entity.y, _entity.radius)) _entity.x = _nx;
    var _ny = _entity.y + _dy;
    if (!std_circle_wall(_entity.x, _ny, _entity.radius)) _entity.y = _ny;
}

function std_line_clear(_x1, _y1, _x2, _y2) {
    var _dist = point_distance(_x1, _y1, _x2, _y2);
    var _steps = max(1, ceil(_dist / 22));
    for (var _i = 1; _i < _steps; _i++) {
        var _t = _i / _steps;
        if (std_wall_cell(std_grid_x(lerp(_x1, _x2, _t)), std_grid_y(lerp(_y1, _y2, _t)))) return false;
    }
    return true;
}

function std_entity_random(_entity, _maximum = 1) {
    var _parallel_rng = global.state == "TRAIN"
        && variable_global_exists("evo_manager")
        && global.evo_manager.training_mode == "parallel"
        && variable_struct_exists(_entity, "training_rng_state");
    if (!_parallel_rng) return random(_maximum);

    // Independent deterministic stream per combatant. All candidates begin
    // from the same stream, so one lane cannot consume another lane's random
    // values and alter its evaluation.
    var _state = (_entity.training_rng_state * 48271) mod 2147483647;
    if (_state <= 0) _state += 2147483646;
    _entity.training_rng_state = _state;
    return (_state / 2147483647) * _maximum;
}

function std_entity_flee_offset(_entity) {
    var _options = [0, 35, -35, 70, -70];
    var _index = min(array_length(_options) - 1,
        floor(std_entity_random(_entity, 1) * array_length(_options)));
    return _options[_index];
}

function std_nearest_potion(_x, _y, _pair_index = -1) {
    var _best = -1;
    var _best_dist = 1000000;
    for (var _i = 0; _i < array_length(global.potions); _i++) {
        var _p = global.potions[_i];
        var _pair_ok = _pair_index < 0
            || (variable_struct_exists(_p, "training_pair_index")
                && _p.training_pair_index == _pair_index);
        if (_p.active && _pair_ok) {
            var _d = point_distance(_x, _y, _p.x, _p.y);
            if (_d < _best_dist) { _best_dist = _d; _best = _i; }
        }
    }
    return _best;
}

function std_plan_path(_enemy, _tx, _ty) {
    var _gcx = clamp(std_grid_x(_tx), 1, global.level.cols - 2);
    var _gcy = clamp(std_grid_y(_ty), 1, global.level.rows - 2);
    if (std_wall_cell(_gcx, _gcy) || global.spike_grid[# _gcx, _gcy] == 1) return false;
    path_clear_points(_enemy.path_id);
    var _ok = mp_grid_path(global.nav_grid, _enemy.path_id, _enemy.x, _enemy.y, std_cell_x(_gcx), std_cell_y(_gcy), false);
    if (_ok) {
        _enemy.path_point = min(1, path_get_number(_enemy.path_id) - 1);
        _enemy.path_goal_x = _gcx;
        _enemy.path_goal_y = _gcy;
        _enemy.repath = 0.32 + std_entity_random(_enemy, 0.18);
    }
    return _ok;
}

function std_follow_path(_enemy, _speed_mul) {
    var _count = path_get_number(_enemy.path_id);
    if (_count <= 0 || _enemy.path_point >= _count) return false;
    var _tx = path_get_point_x(_enemy.path_id, _enemy.path_point);
    var _ty = path_get_point_y(_enemy.path_id, _enemy.path_point);
    var _dist = point_distance(_enemy.x, _enemy.y, _tx, _ty);
    if (_dist < 10) {
        _enemy.path_point++;
        if (_enemy.path_point >= _count) return false;
        _tx = path_get_point_x(_enemy.path_id, _enemy.path_point);
        _ty = path_get_point_y(_enemy.path_id, _enemy.path_point);
    }
    _enemy.facing = point_direction(_enemy.x, _enemy.y, _tx, _ty);
    var _step = _enemy.speed * _speed_mul * global.dt;
    std_move_entity(_enemy, lengthdir_x(_step, _enemy.facing), lengthdir_y(_step, _enemy.facing));
    _enemy.moving = true;
    return true;
}

function std_set_state(_enemy, _state) {
    if (_enemy.state != _state) {
        _enemy.state = _state;
        _enemy.state_time = 0;
    }
}

function std_spawn_projectile(_x, _y, _direction, _team, _damage, _speed, _color, _owner = undefined) {
    array_push(global.projectiles, {
        x: _x, y: _y, direction: _direction, team: _team,
        damage: _damage, speed: _speed, color: _color,
        life: 2.2, radius: 8, owner: _owner
    });
    std_play_sfx(global.sfx_shot);
}

function std_training_same_pair(_source, _target) {
    if (global.state != "TRAIN" || global.evo_manager.training_mode != "parallel") return true;
    if (is_undefined(_source) || is_undefined(_target)) return true;
    if (!variable_struct_exists(_source, "training_pair_index")
        || !variable_struct_exists(_target, "training_pair_index")) return true;
    return _source.training_pair_index == _target.training_pair_index;
}

function std_ai_credit_damage(_source, _amount, _kill = false) {
    if (is_undefined(_source) || !variable_struct_exists(_source, "type") || _source.type != "RL") return;
    _source.damage_dealt += max(0, _amount);
    _source.fitness += max(0, _amount) * 0.12;
    if (_kill) {
        _source.kills += 1;
        _source.fitness += 20;
    }
}

function std_damage_player(_damage, _direction, _source = undefined) {
    var _p = global.player;
    if (_p.invuln > 0 || (global.state != "PLAY" && global.state != "TRAIN"
        && global.state != "BENCHMARK")) return;
    var _before_total = _p.hp + _p.shield;
    if (_p.defending && _p.shield > 0) {
        _p.shield = max(0, _p.shield - _damage * 1.35);
        _p.shield_hit_fx = 0.22;
        std_play_sfx(global.sfx_block);
        if (_p.shield <= 0) {
            _p.shield_broken = 4.0;
            _p.defending = false;
            global.message = "BARRERA AGOTADA";
            global.message_time = 1.5;
        }
    } else {
        _p.hp = max(0, _p.hp - _damage);
        _p.invuln = 0.15;
        _p.hurt_fx = 0.20;
        std_play_sfx(global.sfx_hit);
        std_move_entity(_p, lengthdir_x(16, _direction), lengthdir_y(16, _direction));
        if (_p.hp <= 0) {
            if (global.state == "TRAIN" || global.state == "BENCHMARK") {
                var _training_damage = max(0, _before_total - (_p.hp + _p.shield));
                std_ai_credit_damage(_source, _training_damage, true);
                // Isolated training and benchmark episodes need a real winner.
                // The manager closes the episode after observing hp == 0.
                return;
            } else {
                global.state = "GAMEOVER";
                global.message = "HAS CAIDO";
            }
        }
    }
    std_ai_credit_damage(_source, max(0, _before_total - (_p.hp + _p.shield)), false);
}

function std_damage_enemy(_enemy, _damage, _direction, _source = undefined) {
    if (_enemy.dead) return;
    var _before_total = _enemy.hp + _enemy.shield;
    if (_enemy.type == "B") {
        _enemy.shield_max = STD_TURRET_BARRIER_CAP;
        _enemy.shield = clamp(_enemy.shield, 0, STD_TURRET_BARRIER_CAP);
        // Every confirmed hit restarts the barrier's recovery lockout,
        // whether the damage lands on the barrier or directly on the turret.
        _enemy.barrier_idle_time = 0;
    }
    if (_enemy.defending && _enemy.shield > 0) {
        _enemy.shield = max(0, _enemy.shield - _damage * 1.2);
        _enemy.shield_hit_fx = 0.22;
        std_play_sfx(global.sfx_block);
    } else {
        _enemy.hp -= _damage;
        _enemy.hurt_fx = 0.12;
        std_play_sfx(global.sfx_hit);
        std_move_entity(_enemy, lengthdir_x(10, _direction), lengthdir_y(10, _direction));
        if (_enemy.hp <= 0) {
            _enemy.dead = true;
            if (_enemy.type == "RL") _enemy.fitness -= 15;
            std_play_sfx(global.sfx_down);
            if (!is_undefined(_source) && variable_struct_exists(_source, "team") && _source.team == "PLAYER") {
                var _missing_arrows = global.player.arrows_max - global.player.arrows;
                global.player.arrows = global.player.arrows_max;
                if (_missing_arrows > 0) {
                    global.message = "CARCAJ RECARGADO +" + string(_missing_arrows) + " (5/5)";
                    global.message_time = 1.25;
                }
            }
        }
    }
    var _actual_damage = max(0, _before_total - (max(_enemy.hp, 0) + _enemy.shield));
    if (_enemy.type == "RL") {
        _enemy.damage_taken += _actual_damage;
        _enemy.fitness -= _actual_damage * 0.10;
    }
    std_ai_credit_damage(_source, _actual_damage, _enemy.dead);
}

/// @desc Applies the same RL damage and death penalties used by lethal combat
/// when an environmental hazard kills an agent.
function std_kill_enemy_hazard(_enemy) {
    if (_enemy.dead) return;
    var _actual_damage = max(_enemy.hp, 0);
    _enemy.hp = 0;
    _enemy.dead = true;
    if (_enemy.type == "RL") {
        _enemy.damage_taken += _actual_damage;
        _enemy.fitness -= _actual_damage * 0.10;
        _enemy.fitness -= 15;
    }
    std_play_sfx(global.sfx_down);
}

function std_player_melee() {
    var _p = global.player;
    // Melee is intentionally the high-risk/high-reward option: it reaches a
    // little beyond one tile, cleaves a generous frontal arc and hits more
    // than twice as hard as one projectile.
    _p.melee_cd = 0.48;
    _p.melee_fx = 0.28;
    _p.attack_facing = _p.facing;
    _p.melee_serial += 1;
    std_play_sfx(global.sfx_swing);
    std_move_entity(_p, lengthdir_x(12, _p.facing), lengthdir_y(12, _p.facing));
    for (var _i = 0; _i < array_length(global.enemies); _i++) {
        var _e = global.enemies[_i];
        var _d = point_distance(_p.x, _p.y, _e.x, _e.y);
        var _angle = angle_difference(point_direction(_p.x, _p.y, _e.x, _e.y), _p.facing);
        if (!_e.dead && _d <= 124 && abs(_angle) <= 82) {
            _e.last_hit_melee_serial = _p.melee_serial;
            std_damage_enemy(_e, 47, _p.facing, _p);
            std_move_entity(_e, lengthdir_x(8, _p.facing), lengthdir_y(8, _p.facing));
        }
    }
}

function std_enemy_melee(_enemy, _damage, _target = undefined) {
    if (is_undefined(_target)) _target = global.player;
    _enemy.melee_cd = 0.72;
    _enemy.attack_fx = 0.24;
    _enemy.facing = point_direction(_enemy.x, _enemy.y, _target.x, _target.y);
    if (point_distance(_enemy.x, _enemy.y, _target.x, _target.y) <= 82) {
        if (variable_struct_exists(_target, "team") && _target.team == "PLAYER") {
            std_damage_player(_damage, _enemy.facing, _enemy);
        } else {
            std_damage_enemy(_target, _damage, _enemy.facing, _enemy);
        }
    }
}

function std_enemy_ranged(_enemy, _damage, _set_cooldown = true, _target = undefined) {
    if (is_undefined(_target)) _target = global.player;
    if (_set_cooldown) _enemy.ranged_cd = 1.18;
    _enemy.attack_fx = 0.18;
    _enemy.facing = point_direction(_enemy.x, _enemy.y, _target.x, _target.y);
    var _sx = _enemy.x + lengthdir_x(30, _enemy.facing);
    var _sy = _enemy.y + lengthdir_y(30, _enemy.facing);
    var _projectile_team = (_enemy.type == "RL") ? "RL" : "HOSTILE";
    std_spawn_projectile(_sx, _sy, _enemy.facing, _projectile_team, _damage, 430,
        make_color_rgb(255, 74, 96), _enemy);
}

function std_start_turret_burst(_enemy) {
    _enemy.burst_remaining = 5;
    _enemy.burst_timer = 0;
    _enemy.ranged_cd = 0;
}

function std_update_turret_burst(_enemy, _target = undefined) {
    if (_enemy.burst_remaining <= 0) return false;
    if (is_undefined(_target)) _target = global.player;
    _enemy.burst_timer = max(0, _enemy.burst_timer - global.dt);
    _enemy.facing = point_direction(_enemy.x, _enemy.y, _target.x, _target.y);
    if (_enemy.burst_timer <= 0) {
        std_enemy_ranged(_enemy, 14, false, _target);
        _enemy.burst_remaining--;
        _enemy.burst_timer = 0.13;
        if (_enemy.burst_remaining <= 0) {
            _enemy.ranged_cd = 3.0;
            _enemy.burst_timer = 0;
        }
    }
    return true;
}

function std_update_player() {
    var _p = global.player;
    _p.melee_cd = max(0, _p.melee_cd - global.dt);
    _p.ranged_cd = max(0, _p.ranged_cd - global.dt);
    _p.melee_fx = max(0, _p.melee_fx - global.dt);
    _p.ranged_fx = max(0, _p.ranged_fx - global.dt);
    _p.weapon_swap_cd = max(0, _p.weapon_swap_cd - global.dt);
    _p.invuln = max(0, _p.invuln - global.dt);
    _p.hurt_fx = max(0, _p.hurt_fx - global.dt);
    _p.shield_broken = max(0, _p.shield_broken - global.dt);
    _p.shield_hit_fx = max(0, _p.shield_hit_fx - global.dt);
    _p.moving = false;

    var _mx = device_mouse_x_to_gui(0) + global.cam_x;
    var _my = device_mouse_y_to_gui(0) + global.cam_y;
    _p.facing = point_direction(_p.x, _p.y, _mx, _my);

    var _next_weapon = _p.weapon;
    if (keyboard_check_pressed(ord("1")) || mouse_wheel_up()) _next_weapon = "SWORD";
    if (keyboard_check_pressed(ord("2")) || mouse_wheel_down()) _next_weapon = "BOW";
    if (_next_weapon != _p.weapon) {
        _p.weapon = _next_weapon;
        _p.weapon_swap_cd = 0.18;
        _p.melee_fx = 0;
        _p.ranged_fx = 0;
        global.message = (_p.weapon == "SWORD") ? "ESPADA EQUIPADA" : "ARCO EQUIPADO";
        global.message_time = 0.8;
    }

    _p.defending = keyboard_check(vk_shift) && _p.shield > 0 && _p.shield_broken <= 0 && _p.weapon_swap_cd <= 0;
    if (_p.defending) {
        _p.shield = max(0, _p.shield - 4 * global.dt);
        if (_p.shield <= 0) {
            _p.shield_broken = 4.0;
            _p.defending = false;
            global.message = "BARRERA AGOTADA";
            global.message_time = 1.5;
        }
    } else if (_p.shield_broken <= 0) {
        _p.shield = min(_p.shield_max, _p.shield + 12 * global.dt);
    }

    if (!_p.defending) {
        var _hx = keyboard_check(ord("D")) + keyboard_check(vk_right) - keyboard_check(ord("A")) - keyboard_check(vk_left);
        var _hy = keyboard_check(ord("S")) + keyboard_check(vk_down) - keyboard_check(ord("W")) - keyboard_check(vk_up);
        if (_hx != 0 || _hy != 0) {
            var _len = point_distance(0, 0, _hx, _hy);
            std_move_entity(_p, (_hx / _len) * _p.speed * global.dt, (_hy / _len) * _p.speed * global.dt);
            _p.body_facing = point_direction(0, 0, _hx, _hy);
            _p.moving = true;
        }
        if (mouse_check_button_pressed(mb_left) && _p.weapon_swap_cd <= 0) {
            _p.body_facing = _p.facing;
            if (_p.weapon == "SWORD" && _p.melee_cd <= 0) {
                std_player_melee();
            } else if (_p.weapon == "BOW" && _p.ranged_cd <= 0 && _p.arrows > 0) {
                _p.arrows--;
                _p.ranged_cd = 0.48;
                _p.ranged_fx = 0.20;
                std_spawn_projectile(_p.x + lengthdir_x(38, _p.facing), _p.y + lengthdir_y(38, _p.facing),
                    _p.facing, "PLAYER", 28, 620, make_color_rgb(115, 235, 255), _p);
            } else if (_p.weapon == "BOW" && _p.arrows <= 0) {
                global.message = "SIN FLECHAS - ELIMINA UN ENEMIGO CON LA ESPADA";
                global.message_time = 1.25;
            }
        }
    }

    var _move_target = _p.moving ? 1 : 0;
    _p.move_amount = lerp(_p.move_amount, _move_target, min(1, global.dt * 12));
    _p.anim_phase += global.dt * lerp(2.2, 11.5, _p.move_amount);

    if (keyboard_check_pressed(ord("Q")) && _p.potions > 0 && _p.hp < _p.hp_max) {
        _p.potions--;
        _p.hp = min(_p.hp_max, _p.hp + 52);
        std_play_sfx(global.sfx_heal);
        global.message = "POCIMA UTILIZADA";
        global.message_time = 1.2;
    }

    if (std_spike_at(_p.x, _p.y)) {
        _p.hp = 0;
        global.state = "GAMEOVER";
        global.message = "LAS PUAS SON LETALES";
        std_play_sfx(global.sfx_down);
    }
}

function std_potion_seek(_enemy) {
    var _pair_index = variable_struct_exists(_enemy, "training_pair_index")
        ? _enemy.training_pair_index : -1;
    var _pi = std_nearest_potion(_enemy.x, _enemy.y, _pair_index);
    if (_pi < 0) return false;
    var _p = global.potions[_pi];
    if (_enemy.repath <= 0 || _enemy.path_goal_x != std_grid_x(_p.x) || _enemy.path_goal_y != std_grid_y(_p.y)) {
        std_plan_path(_enemy, _p.x, _p.y);
    }
    std_follow_path(_enemy, 1.05);
    if (point_distance(_enemy.x, _enemy.y, _p.x, _p.y) < 35) {
        _p.active = false;
        _enemy.hp = min(_enemy.hp_max, _enemy.hp + 48);
        if (_enemy.type == "RL") _enemy.potions_used += 1;
        std_play_sfx(global.sfx_heal);
        return false;
    }
    return true;
}

function std_flee_cell_clearance(_cx, _cy) {
    var _clear = 0;
    var _dx = [1, -1, 0, 0];
    var _dy = [0, 0, 1, -1];
    for (var i = 0; i < 4; i++) {
        var _nx = _cx + _dx[i];
        var _ny = _cy + _dy[i];
        if (!std_wall_cell(_nx, _ny) && global.spike_grid[# _nx, _ny] == 0) _clear += 1;
    }
    return _clear;
}

/// @desc Selects the safest reachable-looking cell instead of repeatedly
/// trying the blocked straight-away direction. The clearance bonus makes C
/// sidestep along a wall instead of vibrating in a corner.
function std_choose_flee_cell(_enemy, _target = undefined) {
    if (is_undefined(_target)) _target = global.player;
    var _base_cx = std_grid_x(_enemy.x);
    var _base_cy = std_grid_y(_enemy.y);
    var _best_score = -10000000;
    var _best_cx = -1;
    var _best_cy = -1;

    for (var _dx = -4; _dx <= 4; _dx++) {
        for (var _dy = -4; _dy <= 4; _dy++) {
            if (max(abs(_dx), abs(_dy)) < 2) continue;
            var _cx = _base_cx + _dx;
            var _cy = _base_cy + _dy;
            if (std_wall_cell(_cx, _cy) || global.spike_grid[# _cx, _cy] == 1) continue;

            var _wx = std_cell_x(_cx);
            var _wy = std_cell_y(_cy);
            if (!std_line_clear(_enemy.x, _enemy.y, _wx, _wy)) continue;
            var _target_distance = point_distance(_wx, _wy, _target.x, _target.y);
            var _travel_distance = point_distance(_enemy.x, _enemy.y, _wx, _wy);
            var _clearance = std_flee_cell_clearance(_cx, _cy);
            var _score = _target_distance + _clearance * 34 - _travel_distance * 0.10;
            if (_score > _best_score) {
                _best_score = _score;
                _best_cx = _cx;
                _best_cy = _cy;
            }
        }
    }

    if (_best_cx >= 0 && std_plan_path(_enemy, std_cell_x(_best_cx), std_cell_y(_best_cy))) {
        return true;
    }

    // Fallback angular sweep for unusual disconnected geometry.
    var _away = point_direction(_target.x, _target.y, _enemy.x, _enemy.y);
    var _offsets = [0, 45, -45, 90, -90, 135, -135, 180];
    for (var _i = 0; _i < array_length(_offsets); _i++) {
        var _tx = _enemy.x + lengthdir_x(220, _away + _offsets[_i]);
        var _ty = _enemy.y + lengthdir_y(220, _away + _offsets[_i]);
        var _fallback_cx = clamp(std_grid_x(_tx), 1, global.level.cols - 2);
        var _fallback_cy = clamp(std_grid_y(_ty), 1, global.level.rows - 2);
        if (!std_wall_cell(_fallback_cx, _fallback_cy)
            && global.spike_grid[# _fallback_cx, _fallback_cy] == 0
            && std_plan_path(_enemy, std_cell_x(_fallback_cx), std_cell_y(_fallback_cy))) {
            return true;
        }
    }
    return false;
}

/// @desc During training, scripted hostiles fight the evolving RL population.
/// During normal play every enemy continues using the human player as target.
function std_enemy_combat_target(_enemy) {
    if (_enemy.type == "RL") return std_ai_target(_enemy);
    if (global.state != "TRAIN" && global.state != "BENCHMARK") return global.player;

    if (global.state == "TRAIN" && variable_struct_exists(_enemy, "training_target")) {
        var _assigned = _enemy.training_target;
        if (!is_undefined(_assigned) && !_assigned.dead) return _assigned;
        return undefined;
    }

    var _best = undefined;
    var _best_dist = 10000000;
    for (var i = 0; i < array_length(global.enemies); i++) {
        var _candidate = global.enemies[i];
        if (_candidate.dead || _candidate.type != "RL") continue;
        var _dist = point_distance(_enemy.x, _enemy.y, _candidate.x, _candidate.y);
        if (_dist < _best_dist) {
            _best_dist = _dist;
            _best = _candidate;
        }
    }
    return _best;
}

function std_update_enemy(_enemy) {
    if (_enemy.dead) return;
    _enemy.state_time += global.dt;
    _enemy.repath -= global.dt;
    _enemy.melee_cd = max(0, _enemy.melee_cd - global.dt);
    _enemy.ranged_cd = max(0, _enemy.ranged_cd - global.dt);
    _enemy.hurt_fx = max(0, _enemy.hurt_fx - global.dt);
    _enemy.attack_fx = max(0, _enemy.attack_fx - global.dt);
    _enemy.shield_hit_fx = max(0, _enemy.shield_hit_fx - global.dt);
    _enemy.defending = false;
    _enemy.moving = false;

    var _target = std_enemy_combat_target(_enemy);
    if (is_undefined(_target)) {
        std_set_state(_enemy, "SIN OBJETIVO");
        _enemy.anim_phase += global.dt * 1.7;
        return;
    }

    var _dist = point_distance(_enemy.x, _enemy.y, _target.x, _target.y);
    var _visible = _dist <= _enemy.vision && std_line_clear(_enemy.x, _enemy.y, _target.x, _target.y);
    if (_visible) {
        _enemy.memory = 3.0;
        _enemy.last_x = _target.x;
        _enemy.last_y = _target.y;
    } else {
        _enemy.memory = max(0, _enemy.memory - global.dt);
    }

    switch (_enemy.type) {
        case "A":
            var _pair_a = variable_struct_exists(_enemy, "training_pair_index")
                ? _enemy.training_pair_index : -1;
            if (_enemy.hp / _enemy.hp_max < 0.28
                && std_nearest_potion(_enemy.x, _enemy.y, _pair_a) >= 0) {
                std_set_state(_enemy, "BUSCAR POCIMA");
                std_potion_seek(_enemy);
            } else if ((_visible || _enemy.memory > 0) && _dist <= 78 && _enemy.melee_cd <= 0) {
                std_set_state(_enemy, "ATACAR MELEE");
                std_enemy_melee(_enemy, 22, _target);
            } else if (_visible || _enemy.memory > 0) {
                std_set_state(_enemy, "PERSEGUIR");
                if (_enemy.repath <= 0) std_plan_path(_enemy, _enemy.last_x, _enemy.last_y);
                std_follow_path(_enemy, 1.0);
            } else {
                std_set_state(_enemy, "VIGILAR");
                _enemy.facing += 24 * global.dt;
            }
        break;

        case "B":
            // Hard invariant: elapsed level time and repeated recharge cycles
            // can never stack the turret barrier above this fixed capacity.
            _enemy.shield_max = STD_TURRET_BARRIER_CAP;
            _enemy.shield = clamp(_enemy.shield, 0, STD_TURRET_BARRIER_CAP);
            _enemy.facing = point_direction(_enemy.x, _enemy.y, _target.x, _target.y);
            // Weapon recharge never restores barrier energy. Recovery begins
            // only after fifteen uninterrupted seconds without being hit.
            _enemy.barrier_idle_time = min(STD_TURRET_BARRIER_RECOVERY_DELAY,
                _enemy.barrier_idle_time + global.dt);
            if (_enemy.barrier_idle_time >= STD_TURRET_BARRIER_RECOVERY_DELAY) {
                _enemy.shield = min(STD_TURRET_BARRIER_CAP,
                    _enemy.shield + STD_TURRET_BARRIER_REGEN * global.dt);
            }
            var _close_defense = _visible && _dist <= 220;
            _enemy.defending = _close_defense && _enemy.shield > 0;
            if (_close_defense) {
                // Type B obeys the specification: close range is a defensive
                // state, never simultaneous defense and ranged fire.
                _enemy.burst_remaining = 0;
                _enemy.burst_timer = 0;
                _enemy.ranged_cd = max(_enemy.ranged_cd, 0.25);
                std_set_state(_enemy, _enemy.shield > 0 ? "DEFENSA CERCANA" : "BARRERA ROTA");
            } else if (_enemy.burst_remaining > 0) {
                std_set_state(_enemy, "RAFAGA 5");
                std_update_turret_burst(_enemy, _target);
            } else if (_visible && _enemy.ranged_cd <= 0) {
                std_set_state(_enemy, "INICIAR RAFAGA");
                std_start_turret_burst(_enemy);
                std_update_turret_burst(_enemy, _target);
            } else if (_visible) {
                std_set_state(_enemy, "RECARGANDO");
            } else if (!_visible) {
                std_set_state(_enemy, "VIGILAR");
            }
        break;

        case "C":
            var _pair_c = variable_struct_exists(_enemy, "training_pair_index")
                ? _enemy.training_pair_index : -1;
            if (_enemy.hp / _enemy.hp_max < 0.3
                && std_nearest_potion(_enemy.x, _enemy.y, _pair_c) >= 0) {
                std_set_state(_enemy, "BUSCAR POCIMA");
                std_potion_seek(_enemy);
            } else if (_visible && _dist < 82) {
                std_set_state(_enemy, "CONTRAATACAR");
                if (_enemy.melee_cd <= 0) std_enemy_melee(_enemy, 17, _target);
            } else if (_visible && (_dist < 235 || (_enemy.state == "ESCAPAR" && _dist < 285))) {
                std_set_state(_enemy, "ESCAPAR");
                if (_enemy.repath <= 0) std_choose_flee_cell(_enemy, _target);
                std_follow_path(_enemy, 1.08);
            } else if (_visible) {
                std_set_state(_enemy, "ATACAR DISTANCIA");
                _enemy.facing = point_direction(_enemy.x, _enemy.y, _target.x, _target.y);
                if (_enemy.ranged_cd <= 0) std_enemy_ranged(_enemy, 15, true, _target);
            } else {
                std_set_state(_enemy, "VIGILAR");
                _enemy.facing -= 20 * global.dt;
            }
        break;

        case "RL":
           std_rl_policy(_enemy)
        break;
    }

    if (std_spike_at(_enemy.x, _enemy.y)) {
        std_kill_enemy_hazard(_enemy);
    }

    var _move_target = _enemy.moving ? 1 : 0;
    _enemy.move_amount = lerp(_enemy.move_amount, _move_target, min(1, global.dt * 10));
    _enemy.anim_phase += global.dt * lerp(1.7, 9.2, _enemy.move_amount);
}

function std_update_projectiles() {
    for (var _i = array_length(global.projectiles) - 1; _i >= 0; _i--) {
        var _p = global.projectiles[_i];
        _p.life -= global.dt;
        _p.x += lengthdir_x(_p.speed * global.dt, _p.direction);
        _p.y += lengthdir_y(_p.speed * global.dt, _p.direction);
        var _remove = _p.life <= 0 || std_circle_wall(_p.x, _p.y, _p.radius) || std_spike_at(_p.x, _p.y);
        if (!_remove && _p.team == "PLAYER") {
            for (var _e = 0; _e < array_length(global.enemies); _e++) {
                var _enemy = global.enemies[_e];
                if (!_enemy.dead && point_distance(_p.x, _p.y, _enemy.x, _enemy.y) < _p.radius + _enemy.radius) {
                    std_damage_enemy(_enemy, _p.damage, _p.direction, _p.owner);
                    _remove = true;
                    break;
                }
            }
        } else if (!_remove && _p.team == "RL") {
            for (var _h = 0; _h < array_length(global.enemies); _h++) {
                var _hostile = global.enemies[_h];
                if (!_hostile.dead && _hostile.type != "RL"
                    && std_training_same_pair(_p.owner, _hostile)
                    && point_distance(_p.x, _p.y, _hostile.x, _hostile.y) < _p.radius + _hostile.radius) {
                    std_damage_enemy(_hostile, _p.damage, _p.direction, _p.owner);
                    _remove = true;
                    break;
                }
            }
            var _human_target = (global.state == "TRAIN" && global.evo_manager.human_target_active)
                || (global.state == "BENCHMARK" && global.benchmark.human_target_active);
            if (!_remove && _human_target && point_distance(_p.x, _p.y, global.player.x, global.player.y)
                < _p.radius + global.player.radius) {
                std_damage_player(_p.damage, _p.direction, _p.owner);
                _remove = true;
            }
        } else if (!_remove && _p.team == "HOSTILE") {
            if (global.state == "TRAIN" || global.state == "BENCHMARK") {
                for (var _r = 0; _r < array_length(global.enemies); _r++) {
                    var _rl = global.enemies[_r];
                    if (!_rl.dead && _rl.type == "RL"
                        && std_training_same_pair(_p.owner, _rl)
                        && point_distance(_p.x, _p.y, _rl.x, _rl.y) < _p.radius + _rl.radius) {
                        std_damage_enemy(_rl, _p.damage, _p.direction, _p.owner);
                        _remove = true;
                        break;
                    }
                }
            } else if (point_distance(_p.x, _p.y, global.player.x, global.player.y)
                < _p.radius + global.player.radius) {
                std_damage_player(_p.damage, _p.direction, _p.owner);
                _remove = true;
            }
        }
        if (_remove) array_delete(global.projectiles, _i, 1);
    }
}

function std_update_pickups_and_goal() {
    var _p = global.player;
    var _human_active = true;
    if (global.state == "TRAIN") _human_active = global.evo_manager.human_target_active;
    if (global.state == "BENCHMARK") _human_active = global.benchmark.human_target_active;
    for (var _i = 0; _i < array_length(global.potions); _i++) {
        var _pot = global.potions[_i];
        _pot.bob += global.dt * 3.2;
        if (_human_active && _pot.active && point_distance(_p.x, _p.y, _pot.x, _pot.y) < 38) {
            _pot.active = false;
            _p.potions++;
            std_play_sfx(global.sfx_heal);
            global.message = "POCIMA RECOGIDA - Q PARA USAR";
            global.message_time = 1.8;
        }
    }

    if (global.state != "TRAIN" && global.state != "BENCHMARK"
        && array_length(global.enemies) == 0 && !global.exit_open) {
        global.exit_open = true;
        global.message = "SALIDA DESBLOQUEADA";
        global.message_time = 2.0;
        std_play_sfx(global.sfx_heal);
    }
    if (global.state != "TRAIN" && global.state != "BENCHMARK" && global.exit_open
        && point_distance(_p.x, _p.y, global.exit_x, global.exit_y) < 42) {
        if (global.level_index < 2) {
            std_load_level(global.level_index + 1);
        } else {
            global.state = "VICTORY";
            global.message = "MISION COMPLETADA";
            std_play_sfx(global.sfx_heal);
        }
    }
}

function std_update_game() {
    var _human_active = true;
    if (global.state == "TRAIN") _human_active = global.evo_manager.human_target_active;
    if (global.state == "BENCHMARK") _human_active = global.benchmark.human_target_active;
    if (_human_active) std_update_player();
    for (var _i = array_length(global.enemies) - 1; _i >= 0; _i--) {
        var _e = global.enemies[_i];
        std_update_enemy(_e);
		
		if (_e.type == "RL" && !_e.dead) {
			std_ai_update_fitness(_e);
		}
        if (_e.dead) {
            if (_e.path_id >= 0) path_delete(_e.path_id);
            array_delete(global.enemies, _i, 1);
        }
    }
    std_update_projectiles();
    std_update_pickups_and_goal();

    var _focus_x = global.player.x;
    var _focus_y = global.player.y;
    if (!_human_active) {
        for (var _focus_i = 0; _focus_i < array_length(global.enemies); _focus_i++) {
            if (!global.enemies[_focus_i].dead && global.enemies[_focus_i].type == "RL") {
                _focus_x = global.enemies[_focus_i].x;
                _focus_y = global.enemies[_focus_i].y;
                break;
            }
        }
    }
    var _target_x = clamp(_focus_x - 640, 0, max(0, global.world_w - 1280));
    var _target_y = clamp(_focus_y - 360, 0, max(0, global.world_h - 720));
    global.cam_x = lerp(global.cam_x, _target_x, min(1, 8 * global.dt));
    global.cam_y = lerp(global.cam_y, _target_y, min(1, 8 * global.dt));
}

function std_sprite_for_enemy(_type) {
    switch (_type) {
        case "A": return global.spr_enemy_a;
        case "B": return global.spr_enemy_b;
        case "C": return global.spr_enemy_c;
        default: return global.spr_enemy_rl;
    }
}

function std_direction_index(_facing) {
    var _angle = ((_facing mod 360) + 360) mod 360;
    if (_angle >= 45 && _angle < 135) return 3;  // UP
    if (_angle >= 135 && _angle < 225) return 1; // LEFT
    if (_angle >= 225 && _angle < 315) return 0; // DOWN
    return 2;                                     // RIGHT
}

function std_walk_frame(_move_amount, _phase) {
    if (_move_amount < 0.22) return 1;
    var _cycle = floor(_phase * 0.45) mod 4;
    if (_cycle == 1) return 0;
    if (_cycle == 3) return 2;
    return 1;
}

function std_draw_enemy_sprite_safe(_spr, _enemy, _x, _y, _xscale, _yscale, _color) {
    if (_spr >= 0) {
        var _faction = clamp(global.level_index, 0, 2);
        var _direction = std_direction_index(_enemy.facing);
        var _pose = std_walk_frame(_enemy.move_amount, _enemy.anim_phase);
        var _frame = _faction * 12 + _direction * 3 + _pose;
        draw_sprite_ext(_spr, _frame, _x, _y, _xscale, _yscale, 0, _color, 1);
    } else {
        draw_set_color(_color);
        draw_circle(_x, _y, 22 * _xscale, false);
    }
}

function std_draw_sprite_safe(_spr, _x, _y, _rot, _scale, _color) {
    if (_spr >= 0) {
        draw_sprite_ext(_spr, 0, _x, _y, _scale, _scale, _rot, _color, 1);
    } else {
        draw_set_color(_color);
        draw_circle(_x, _y, 22 * _scale, false);
    }
}

function std_draw_bar(_x, _y, _w, _h, _value, _maximum, _back, _fill) {
    draw_set_color(_back);
    draw_rectangle(_x, _y, _x + _w, _y + _h, false);
    draw_set_color(_fill);
    draw_rectangle(_x + 2, _y + 2, _x + 2 + max(0, (_w - 4) * (_value / _maximum)), _y + _h - 2, false);
}

function std_draw_barrier(_x, _y, _energy, _maximum, _active, _hit_fx, _phase, _color) {
    if (!_active || _maximum <= 0 || _energy <= 0) return;
    var _ratio = clamp(_energy / _maximum, 0, 1);
    var _impact = (_hit_fx > 0) ? sin((_hit_fx / 0.22) * pi) : 0;
    var _radius = 34 + sin(_phase * 2.2) * 1.5 + _impact * 7;
    draw_set_color(_color);
    draw_set_alpha(0.055 + _ratio * 0.055 + _impact * 0.08);
    draw_circle(_x, _y, _radius, false);
    draw_set_alpha(0.44 + _ratio * 0.30);
    draw_circle(_x, _y, _radius, true);
    draw_set_alpha(0.22 + _impact * 0.45);
    draw_circle(_x, _y, _radius - 4, true);
    for (var _node = 0; _node < 6; _node++) {
        var _ang = _node * 60 + _phase * 22;
        draw_circle(_x + lengthdir_x(_radius, _ang), _y + lengthdir_y(_radius, _ang), 2 + _impact, false);
    }
    draw_set_alpha(1);
}

function std_draw_bow(_x, _y, _facing, _draw_fx) {
    var _draw_amount = clamp(_draw_fx / 0.20, 0, 1);
    var _bow_x = _x + lengthdir_x(27, _facing);
    var _bow_y = _y + lengthdir_y(27, _facing);
    var _front_x = _bow_x + lengthdir_x(13, _facing);
    var _front_y = _bow_y + lengthdir_y(13, _facing);
    var _back_x = _bow_x - lengthdir_x(6 + _draw_amount * 7, _facing);
    var _back_y = _bow_y - lengthdir_y(6 + _draw_amount * 7, _facing);
    var _top_x = _front_x + lengthdir_x(18, _facing + 90);
    var _top_y = _front_y + lengthdir_y(18, _facing + 90);
    var _bottom_x = _front_x + lengthdir_x(18, _facing - 90);
    var _bottom_y = _front_y + lengthdir_y(18, _facing - 90);
    draw_set_color(make_color_rgb(179, 112, 54));
    draw_line_width(_top_x, _top_y, _front_x + lengthdir_x(5, _facing + 90), _front_y + lengthdir_y(5, _facing + 90), 4);
    draw_line_width(_front_x + lengthdir_x(5, _facing - 90), _front_y + lengthdir_y(5, _facing - 90), _bottom_x, _bottom_y, 4);
    draw_set_color(make_color_rgb(220, 235, 240));
    draw_line(_top_x, _top_y, _back_x, _back_y);
    draw_line(_back_x, _back_y, _bottom_x, _bottom_y);
    draw_set_color(make_color_rgb(115, 235, 255));
    draw_line_width(_back_x, _back_y, _back_x + lengthdir_x(35, _facing), _back_y + lengthdir_y(35, _facing), 2);
}

function std_draw_game() {
    draw_clear(make_color_rgb(7, 10, 20));
    var _floor = global.spr_floor[global.level.floor_sprite];
    var _wall = global.spr_wall[global.level.floor_sprite];
    var _min_cx = max(0, floor(global.cam_x / STD_TILE));
    var _max_cx = min(global.level.cols - 1, ceil((global.cam_x + 1280) / STD_TILE));
    var _min_cy = max(0, floor(global.cam_y / STD_TILE));
    var _max_cy = min(global.level.rows - 1, ceil((global.cam_y + 720) / STD_TILE));

    for (var _cy = _min_cy; _cy <= _max_cy; _cy++) {
        for (var _cx = _min_cx; _cx <= _max_cx; _cx++) {
            var _sx = std_cell_x(_cx) - global.cam_x;
            var _sy = std_cell_y(_cy) - global.cam_y;
            std_draw_sprite_safe(_floor, _sx, _sy, 0, 1, c_white);
            if (global.wall_grid[# _cx, _cy] == 1) std_draw_sprite_safe(_wall, _sx, _sy, 0, 1, c_white);
            if (global.spike_grid[# _cx, _cy] == 1) std_draw_sprite_safe(global.spr_spike, _sx, _sy, 0, 1, c_white);
        }
    }

    var _exit_color = global.exit_open ? c_white : make_color_rgb(70, 70, 80);
    std_draw_sprite_safe(global.spr_exit, global.exit_x - global.cam_x, global.exit_y - global.cam_y, current_time * 0.03, 1, _exit_color);

    for (var _p = 0; _p < array_length(global.potions); _p++) {
        var _pot = global.potions[_p];
        if (_pot.active) std_draw_sprite_safe(global.spr_potion, _pot.x - global.cam_x, _pot.y - global.cam_y + sin(_pot.bob) * 5, 0, 0.78, c_white);
    }

    for (var _pr = 0; _pr < array_length(global.projectiles); _pr++) {
        var _proj = global.projectiles[_pr];
        std_draw_sprite_safe(global.spr_projectile, _proj.x - global.cam_x, _proj.y - global.cam_y, _proj.direction, 0.45, _proj.color);
    }

    for (var _e = 0; _e < array_length(global.enemies); _e++) {
        var _enemy = global.enemies[_e];
        var _ex = _enemy.x - global.cam_x;
        var _ey = _enemy.y - global.cam_y;
        var _tint = (_enemy.hurt_fx > 0) ? c_white : make_color_rgb(235, 235, 245);
        var _walk = _enemy.move_amount;
        var _step_wave = sin(_enemy.anim_phase);
        var _enemy_bob = abs(_step_wave) * -2.2 * _walk + sin(_enemy.anim_phase * 0.47) * (1 - _walk) * 0.7;
        var _enemy_recoil = (_enemy.attack_fx > 0) ? sin((_enemy.attack_fx / 0.24) * pi) : 0;
        var _enemy_hurt = (_enemy.hurt_fx > 0) ? sin((_enemy.hurt_fx / 0.12) * pi) : 0;
        var _enemy_xscale = 1 + _enemy_hurt * 0.06;
        var _enemy_yscale = 1 - _enemy_hurt * 0.05;
        var _draw_ex = _ex - lengthdir_x(_enemy_recoil * 5, _enemy.facing);
        var _draw_ey = _ey + _enemy_bob - lengthdir_y(_enemy_recoil * 5, _enemy.facing);

        draw_set_alpha(0.28);
        draw_set_color(c_black);
        draw_ellipse(_ex - 19, _ey + 17, _ex + 19, _ey + 27, false);
        draw_set_alpha(1);
        std_draw_enemy_sprite_safe(std_sprite_for_enemy(_enemy.type), _enemy, _draw_ex, _draw_ey, _enemy_xscale, _enemy_yscale, _tint);
        std_draw_barrier(_draw_ex, _draw_ey, _enemy.shield, _enemy.shield_max, _enemy.defending,
            _enemy.shield_hit_fx, _enemy.state_time, make_color_rgb(255, 88, 135));
        std_draw_bar(_ex - 25, _ey - 38, 50, 6, _enemy.hp, _enemy.hp_max, make_color_rgb(35, 12, 18), make_color_rgb(255, 65, 86));
        draw_set_halign(fa_center);
        draw_set_color(c_white);
        draw_text(_ex, _ey + 29, _enemy.type);
        if (global.debug_ai) {
            draw_set_color(make_color_rgb(255, 235, 120));
            draw_text(_ex, _ey - 56, _enemy.state);
            draw_set_alpha(0.16);
            draw_circle(_ex, _ey, min(_enemy.vision, 220), true);
            draw_set_alpha(1);
        }
    }

    var _pl = global.player;
    var _px = _pl.x - global.cam_x;
    var _py = _pl.y - global.cam_y;
    var _player_step = sin(_pl.anim_phase);
    var _player_bob = abs(_player_step) * -2.6 * _pl.move_amount + sin(_pl.anim_phase * 0.43) * (1 - _pl.move_amount) * 0.85;
    var _player_hurt = (_pl.hurt_fx > 0) ? sin((_pl.hurt_fx / 0.20) * pi) : 0;
    var _attack_t = (_pl.melee_fx > 0) ? 1 - (_pl.melee_fx / 0.28) : 0;
    var _attack_push = (_pl.melee_fx > 0) ? sin(_attack_t * pi) : 0;
    var _bow_recoil = (_pl.ranged_fx > 0) ? sin((_pl.ranged_fx / 0.20) * pi) : 0;
    var _visual_facing = (_pl.melee_fx > 0) ? _pl.attack_facing : _pl.facing;
    var _body_x = _px + lengthdir_x(_attack_push * 5 - _bow_recoil * 3, _visual_facing);
    var _body_y = _py + _player_bob + lengthdir_y(_attack_push * 5 - _bow_recoil * 3, _visual_facing);
    var _blink = (_pl.invuln > 0 && (current_time div 50) mod 2 == 0) ? 0.4 : 1;
    draw_set_alpha(0.30);
    draw_set_color(c_black);
    draw_ellipse(_px - 20, _py + 17, _px + 20, _py + 28, false);
    draw_set_alpha(_blink);
    if (global.spr_player >= 0) {
        var _player_direction = std_direction_index((_pl.melee_fx > 0) ? _pl.attack_facing : _pl.body_facing);
        var _player_pose = std_walk_frame(_pl.move_amount, _pl.anim_phase);
        var _player_frame = _player_direction * 3 + _player_pose;
        if (_pl.weapon == "SWORD" && _pl.melee_fx > 0) {
            var _attack_pose = min(2, floor(_attack_t * 3));
            _player_frame = 12 + _player_direction * 3 + _attack_pose;
        }
        draw_sprite_ext(global.spr_player, _player_frame, _body_x, _body_y,
            1 + _player_hurt * 0.06,
            1 - _player_hurt * 0.05,
            0, c_white, 1);
    } else {
        std_draw_sprite_safe(global.spr_player, _body_x, _body_y, _pl.facing, 1, c_white);
    }
    draw_set_alpha(1);

    // The sword is part of the directional attack frames, so hand, grip and
    // blade always move as one pose. Only the bow remains procedurally drawn.
    if (_pl.weapon == "BOW") {
        std_draw_bow(_body_x, _body_y, _pl.facing, _pl.ranged_fx);
    }
    std_draw_barrier(_body_x, _body_y, _pl.shield, _pl.shield_max, _pl.defending,
        _pl.shield_hit_fx, _pl.anim_phase, make_color_rgb(72, 218, 255));
    if (_pl.weapon == "SWORD" && _pl.melee_fx > 0) {
        draw_set_color(make_color_rgb(95, 235, 255));
        draw_set_alpha(sin(_attack_t * pi) * 0.36);
        for (var _arc = -52; _arc <= 52; _arc += 13) {
            var _a1 = _pl.attack_facing + _arc;
            var _a2 = _pl.attack_facing + _arc + 9;
            draw_line_width(_body_x + lengthdir_x(42, _a1), _body_y + lengthdir_y(42, _a1), _body_x + lengthdir_x(72, _a2), _body_y + lengthdir_y(72, _a2), 3);
        }
        draw_set_alpha(1);
    }
    draw_set_halign(fa_left);
}

function std_draw_gui() {
    if (global.state == "BENCH_MENU") {
        std_draw_benchmark_menu();
        return;
    }
    if (global.state == "AI_MENU") {
        std_draw_ai_menu();
        return;
    }
    if (global.state == "MENU" || global.state == "CONTROLS") {
        std_draw_menu();
        return;
    }

    var _p = global.player;
    draw_set_alpha(0.88);
    draw_set_color(make_color_rgb(8, 12, 25));
    draw_roundrect(18, 18, 410, 128, false);
    draw_set_alpha(1);
    draw_set_color(c_white);
    draw_text(34, 28, global.level.name);
    draw_set_color(make_color_rgb(160, 180, 205));
    draw_text(34, 49, global.level.subtitle);
    draw_set_color(c_white);
    draw_text(34, 75, "SALUD");
    std_draw_bar(105, 78, 250, 15, _p.hp, _p.hp_max, make_color_rgb(38, 18, 25), make_color_rgb(255, 65, 86));
    draw_text(34, 101, "BARRERA");
    var _shield_color = (_p.shield_broken > 0) ? make_color_rgb(110, 110, 120) : make_color_rgb(50, 196, 255);
    std_draw_bar(105, 104, 250, 15, _p.shield, _p.shield_max, make_color_rgb(15, 30, 44), _shield_color);
    draw_text(367, 75, string(floor(_p.hp)));
    draw_text(367, 101, string(floor(_p.shield)));

    draw_set_alpha(0.88);
    draw_set_color(make_color_rgb(8, 12, 25));
    draw_roundrect(1020, 18, 1262, 158, false);
    draw_set_alpha(1);
    draw_set_color(c_white);
    draw_text(1040, 32, "AMENAZAS: " + string(array_length(global.enemies)));
    draw_text(1040, 57, "ARMA: " + ((_p.weapon == "SWORD") ? "ESPADA" : "ARCO"));
    draw_text(1040, 82, "FLECHAS: " + string(_p.arrows) + "/" + string(_p.arrows_max));
    draw_text(1040, 104, "POCIMAS: " + string(_p.potions));
    draw_set_color(global.exit_open ? make_color_rgb(80, 255, 175) : make_color_rgb(255, 190, 80));
    draw_text(1040, 126, global.exit_open ? "SALIDA ABIERTA" : "SALIDA BLOQUEADA");

    draw_set_alpha(0.82);
    draw_set_color(make_color_rgb(8, 12, 25));
    draw_roundrect(18, 646, 1262, 702, false);
    draw_set_alpha(1);
    draw_set_color(make_color_rgb(215, 225, 240));
    draw_text(34, 659, "WASD/FLECHAS Mover  |  1/2 o rueda Cambiar arma  |  CLICK IZQ. Atacar  |  SHIFT Barrera  |  Q Pocima");
    draw_text(34, 680, "R Reiniciar  |  H Estados IA  |  I Configurar IA  |  P Pausa prueba  |  T Detener  |  M Sonido");

    if (global.state == "TRAIN") {
        var _mgr = global.evo_manager;
        draw_set_alpha(0.92);
        draw_set_color(make_color_rgb(7, 18, 31));
        draw_roundrect(438, 18, 842, 126, false);
        draw_set_alpha(1);
        draw_set_halign(fa_center);
        draw_set_color(_mgr.training_paused ? make_color_rgb(255, 194, 92) : make_color_rgb(77, 255, 175));
        var _parallel_stage = std_manager_parallel_enabled_for_stage();
        draw_text(640, 30, _mgr.training_paused ? "ENTRENAMIENTO EN PAUSA"
            : (_parallel_stage ? "NEUROEVOLUCION SIMULTANEA" : "NEUROEVOLUCION SECUENCIAL"));
        draw_set_color(c_white);
        draw_text(640, 55, "GEN " + string(_mgr.generation_count) + "/" + string(_mgr.max_generations)
            + "  |  " + _mgr.stage_names[_mgr.stage_index]);
        draw_set_color(make_color_rgb(158, 185, 204));
        var _history_fitness_text = is_undefined(_mgr.best_chromosome_ever)
            ? "--" : string_format(_mgr.best_fitness_ever, 0, 1);
        var _stage_fitness_text = (!is_undefined(_mgr.progress_chromosome)
            && _mgr.progress_stage_index == _mgr.stage_index)
            ? string_format(_mgr.progress_fitness, 0, 1) : "--";
        draw_text(640, 79, "HIST. " + _history_fitness_text
            + "  |  ETAPA " + _stage_fitness_text
            + "  |  T " + string_format(_mgr.generation_timer, 0, 1)
            + "/" + string(_mgr.generation_timer_limit));
        if (_parallel_stage) {
            draw_text(640, 101, "ACTIVOS "
                + string(_mgr.population_size - _mgr.parallel_finished_count) + "/" + string(_mgr.population_size)
                + "  |  RONDA " + string(_mgr.evaluation_match_index + 1) + "/" + string(_mgr.matches_per_agent));
        } else {
            draw_text(640, 101, "AGENTE " + string(_mgr.evaluation_agent_index + 1) + "/" + string(_mgr.population_size)
                + "  |  PARTIDA " + string(_mgr.evaluation_match_index + 1) + "/" + string(_mgr.matches_per_agent));
        }
        draw_set_halign(fa_left);
    }

    if (global.state == "BENCHMARK") {
        var _bench = global.benchmark;
        var _scenario = _bench.scenarios[_bench.scenario_cursor];
        var _episode_seed = _bench.seed + _scenario.id * 10000 + _bench.repetition_index;
        draw_set_alpha(0.94);
        draw_set_color(make_color_rgb(7, 18, 31));
        draw_roundrect(428, 18, 852, 124, false);
        draw_set_alpha(1);
        draw_set_halign(fa_center);
        draw_set_color(_bench.paused ? make_color_rgb(255, 194, 92) : make_color_rgb(77, 255, 175));
        draw_text(640, 29, _bench.paused ? "BENCHMARK EN PAUSA" : "BENCHMARK ACTIVO");
        draw_set_color(c_white);
        draw_text(640, 53, "ESCENARIO " + string(_scenario.id) + "  |  " + _scenario.name);
        draw_set_color(make_color_rgb(158, 185, 204));
        draw_text(640, 77, "REPETICION " + string(_bench.repetition_index + 1) + "/" + string(_bench.repetitions)
            + "  |  TIEMPO " + string_format(_bench.episode_time, 0, 1) + "/" + string(_bench.timeout));
        draw_text(640, 101, "SEMILLA EPISODIO " + string(_episode_seed) + "  |  P PAUSA  |  T DETENER");
        draw_set_halign(fa_left);
    }

    if (global.message_time > 0) {
        draw_set_halign(fa_center);
        draw_set_color(make_color_rgb(255, 235, 120));
        draw_text(640, 158, global.message);
        draw_set_halign(fa_left);
    }
    if (global.level_banner > 0) {
        draw_set_alpha(min(1, global.level_banner));
        draw_set_color(make_color_rgb(4, 7, 15));
        draw_rectangle(0, 270, 1280, 450, false);
        draw_set_halign(fa_center);
        draw_set_color(c_white);
        draw_text_transformed(640, 315, global.level.name, 2.0, 2.0, 0);
        draw_set_color(make_color_rgb(70, 220, 255));
        draw_text(640, 375, global.level.subtitle);
        draw_set_halign(fa_left);
        draw_set_alpha(1);
    }

    if (global.state != "PLAY" && global.state != "TRAIN" && global.state != "BENCHMARK") {
        draw_set_alpha(0.92);
        draw_set_color(make_color_rgb(4, 6, 14));
        draw_rectangle(0, 0, 1280, 720, false);
        draw_set_alpha(1);
        draw_set_halign(fa_center);
        if (global.state == "PAUSE") {
            draw_set_color(c_white);
            draw_text_transformed(640, 280, "PAUSA", 2.4, 2.4, 0);
            draw_text(640, 350, "ESC para continuar");
        } else if (global.state == "VICTORY") {
            draw_set_color(make_color_rgb(80, 255, 175));
            draw_text_transformed(640, 250, "MISION COMPLETADA", 2.0, 2.0, 0);
            draw_set_color(c_white);
            draw_text(640, 330, "Los tres niveles de la seccion 3.1 han sido superados.");
            draw_text(640, 370, "ENTER para volver al menu");
			
        } else {
            draw_set_color(make_color_rgb(255, 65, 86));
            draw_text_transformed(640, 250, "HAS CAIDO", 2.4, 2.4, 0);
            draw_set_color(c_white);
            draw_text(640, 330, global.message);
            draw_text(640, 370, "ENTER para reintentar");
        }
        draw_set_halign(fa_left);
    }
}

function std_draw_menu() {
    // Dark expedition briefing: animated sky, route map and live operative card.
    draw_set_alpha(1);
    draw_set_color(make_color_rgb(3, 7, 15));
    draw_rectangle(0, 0, 1280, 720, false);

    var _pulse = 0.5 + sin(global.menu_time * 2.1) * 0.5;
    var _drift = (global.menu_time * 13) mod 160;
    draw_set_alpha(0.12);
    draw_set_color(make_color_rgb(35, 184, 220));
    for (var _gx = -160 + _drift; _gx < 1280; _gx += 160) draw_line(_gx, 0, _gx + 360, 720);
    draw_set_alpha(0.25);
    for (var _star = 0; _star < 30; _star++) {
        var _sx = (_star * 173 + floor(global.menu_time * (5 + (_star mod 4)))) mod 1320 - 20;
        var _sy = (_star * 97) mod 690 + 15;
        draw_circle(_sx, _sy, 1 + (_star mod 3) * 0.45, false);
    }
    draw_set_alpha(1);

    // Header and operation status.
    draw_set_halign(fa_left);
    draw_set_color(make_color_rgb(73, 225, 245));
    draw_rectangle(54, 54, 61, 132, false);
    draw_set_color(c_white);
    draw_text_transformed(82, 54, "SMART", 2.35, 2.35, 0);
    draw_text_transformed(82, 103, "TOP DOWN", 2.35, 2.35, 0);
    draw_set_color(make_color_rgb(140, 166, 188));
    draw_text(84, 158, "OPERACION NEXUS  //  EXPEDICION 01");
    draw_set_color(make_color_rgb(74, 255, 172));
    draw_circle(1082, 75, 5 + _pulse * 2, false);
    draw_text(1096, 66, "SISTEMA EN LINEA");
    draw_set_color(make_color_rgb(76, 100, 126));
    draw_line(54, 198, 1226, 198);

    if (global.state == "MENU") {
        var _labels = ["JUGAR", "CONFIGURAR IA", "CONTROLES", "SALIR"];
        var _details = [
            "Iniciar infiltracion en el Sector Neon",
            "Red neuronal, sensores y entrenamiento genetico",
            "Armas, movimiento y protocolo de campo",
            "Cerrar la operacion y volver al escritorio"
        ];

        // Left operative panel, assembled from existing runtime sprites.
        draw_set_alpha(0.72);
        draw_set_color(make_color_rgb(7, 18, 31));
        draw_roundrect(54, 228, 735, 646, false);
        draw_set_alpha(1);
        draw_set_color(make_color_rgb(34, 92, 112));
        draw_roundrect(54, 228, 735, 646, true);
        draw_set_color(make_color_rgb(122, 151, 174));
        draw_text(82, 250, "AGENTE SELECCIONADO");
        draw_set_color(make_color_rgb(74, 225, 245));
        draw_text(82, 276, "EL EXPLORADOR");

        var _hero_y = 430 + sin(global.menu_time * 2.4) * 4;
        draw_set_alpha(0.13 + _pulse * 0.05);
        draw_set_color(make_color_rgb(52, 221, 246));
        draw_circle(286, _hero_y, 116 + _pulse * 6, false);
        draw_set_alpha(0.28);
        draw_ellipse(190, 537, 382, 568, false);
        draw_set_alpha(1);
        if (global.spr_player >= 0) {
            var _hero_frame = 1;
            if ((floor(global.menu_time * 2.4) mod 4) == 0) _hero_frame = 0;
            if ((floor(global.menu_time * 2.4) mod 4) == 2) _hero_frame = 2;
            draw_sprite_ext(global.spr_player, _hero_frame, 286, _hero_y, 3.15, 3.15, 0, c_white, 1);
        }

        draw_set_color(make_color_rgb(172, 195, 214));
        draw_text(435, 329, "OBJETIVO");
        draw_set_color(c_white);
        draw_text(435, 356, "Romper el cerco enemigo");
        draw_text(435, 380, "y alcanzar cada salida.");
        draw_set_color(make_color_rgb(172, 195, 214));
        draw_text(435, 425, "EQUIPO");
        draw_set_color(make_color_rgb(244, 203, 105));
        draw_text(435, 452, "ESPADA  +  ARCO [5]");
        draw_set_color(make_color_rgb(172, 195, 214));
        draw_text(435, 497, "AMENAZAS");
        draw_set_color(make_color_rgb(255, 105, 130));
        draw_text(435, 524, "4 CLASES DE HOSTILES");

        // Three-stage route communicates the full run before starting.
        draw_set_color(make_color_rgb(65, 91, 112));
        draw_line_width(128, 603, 653, 603, 3);
        var _zone_colors = [make_color_rgb(65, 222, 244), make_color_rgb(74, 133, 255), make_color_rgb(232, 75, 104)];
        var _zone_names = ["NEON", "COBALTO", "CARMESI"];
        for (var _zone = 0; _zone < 3; _zone++) {
            var _zx = 128 + _zone * 262;
            draw_set_color(_zone_colors[_zone]);
            draw_circle(_zx, 603, 8 + sin(global.menu_time * 2 + _zone) * 1.5, false);
            draw_set_halign(fa_center);
            draw_text(_zx, 619, _zone_names[_zone]);
        }

        // Right command terminal and selectable cards.
        draw_set_halign(fa_left);
        draw_set_alpha(0.90);
        draw_set_color(make_color_rgb(6, 14, 26));
        draw_roundrect(760, 228, 1226, 646, false);
        draw_set_alpha(1);
        draw_set_color(make_color_rgb(43, 73, 96));
        draw_roundrect(760, 228, 1226, 646, true);
        draw_set_color(c_white);
        draw_text_transformed(790, 248, "CENTRO DE MANDO", 1.2, 1.2, 0);
        draw_set_color(make_color_rgb(112, 139, 160));
        draw_text(790, 273, "Selecciona el siguiente protocolo");

        for (var _i = 0; _i < array_length(_labels); _i++) {
            var _ypos = 254 + _i * 78;
            var _selected = global.menu_option == _i;
            var _select_scale = (_selected && global.menu_change_fx > 0) ? 4 : 0;
            draw_set_alpha(_selected ? 0.98 : 0.60);
            draw_set_color(_selected ? make_color_rgb(18, 73, 93) : make_color_rgb(11, 25, 40));
            draw_roundrect(790 - _select_scale, _ypos, 1190 + _select_scale, _ypos + 60, false);
            draw_set_alpha(1);
            draw_set_color(_selected ? make_color_rgb(72, 225, 245) : make_color_rgb(55, 81, 102));
            draw_rectangle(790 - _select_scale, _ypos, 796, _ypos + 60, false);
            draw_set_color(_selected ? c_white : make_color_rgb(190, 205, 218));
            draw_text_transformed(816, _ypos + 7, _labels[_i], _selected ? 1.14 : 1.02, _selected ? 1.14 : 1.02, 0);
            draw_set_color(_selected ? make_color_rgb(170, 211, 222) : make_color_rgb(103, 127, 146));
            draw_text(816, _ypos + 35, _details[_i]);
            if (_selected) {
                draw_set_color(make_color_rgb(244, 203, 105));
                draw_text(1156, _ypos + 19, ">");
            }
        }
        draw_set_color(make_color_rgb(123, 149, 169));
        draw_text(790, 580, "W/S o FLECHAS  Seleccionar");
        draw_text(790, 603, "ENTER / ESPACIO / CLICK  Confirmar");
        draw_set_color(global.muted ? make_color_rgb(255, 112, 125) : make_color_rgb(74, 255, 172));
        draw_text(790, 626, global.muted ? "M  SONIDO: DESACTIVADO" : "M  SONIDO: ACTIVO");
    } else {
        draw_set_halign(fa_left);
        draw_set_color(c_white);
        draw_text_transformed(72, 235, "PROTOCOLO DE CAMPO", 1.65, 1.65, 0);
        draw_set_color(make_color_rgb(130, 158, 180));
        draw_text(74, 278, "Consulta rapida antes del despliegue");
        var _control_titles = ["MOVIMIENTO", "COMBATE", "SUPERVIVENCIA", "SISTEMA"];
        var _control_lines = [
            "WASD / FLECHAS|Desplazarse por el sector",
            "1 / 2 o RUEDA|Elegir espada o arco\nCLICK IZQ.|Usar arma equipada\nARCO|5 flechas; una baja rellena a 5",
            "SHIFT|Mantener barrera inmovil\nQ|Consumir pocima recogida",
            "ESC|Pausar partida\nR|Reiniciar nivel\nH|Mostrar estados IA\nI|Configurar IA\nP|Pausar entrenamiento\nM|Activar o silenciar audio"
        ];
        for (var _card = 0; _card < 4; _card++) {
            var _cx = 72 + (_card mod 2) * 590;
            var _cy = 322 + floor(_card / 2) * 158;
            draw_set_color(make_color_rgb(7, 18, 31));
            draw_roundrect(_cx, _cy, _cx + 548, _cy + 132, false);
            draw_set_color((_card == 1) ? make_color_rgb(244, 203, 105) : make_color_rgb(62, 187, 211));
            draw_rectangle(_cx, _cy, _cx + 6, _cy + 132, false);
            draw_text(_cx + 24, _cy + 16, _control_titles[_card]);
            draw_set_color(make_color_rgb(196, 213, 225));
            draw_text(_cx + 24, _cy + 45, _control_lines[_card]);
        }
        draw_set_halign(fa_center);
        draw_set_color(make_color_rgb(244, 203, 105));
        draw_text(640, 658, "ENTER, ESPACIO o ESC  //  VOLVER AL CENTRO DE MANDO");
    }
    draw_set_halign(fa_left);
    draw_set_alpha(1);
}
