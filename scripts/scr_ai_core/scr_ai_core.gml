/// scr_ai_core.gml
/// Neuroevolution policy: sensors -> neural network -> combat actuator.

#macro AI_ACTION_ESCAPAR    0
#macro AI_ACTION_PERSEGUIR  1
#macro AI_ACTION_MELEE      2
#macro AI_ACTION_DISTANCIA  3
#macro AI_ACTION_SANAR      4
#macro AI_ACTION_DEFENDER   5
#macro AI_DECISION_INTERVAL 0.12

/// @desc Prepares a newly-created RL agent and its per-generation metrics.
function std_ai_init_agent(_enemy) {
    _enemy.fitness = 0;
    _enemy.hp_prev = _enemy.hp;
    _enemy.shield_prev = _enemy.shield;
    _enemy.damage_dealt = 0;
    _enemy.damage_taken = 0;
    _enemy.kills = 0;
    _enemy.dodges = 0;
    _enemy.actions_taken = 0;
    _enemy.action_time = array_create(NN_OUTPUT_SIZE, 0);
    _enemy.potions_used = 0;
    _enemy.last_player_melee_serial = global.player.melee_serial;
    _enemy.last_hit_melee_serial = -1;
    _enemy.decision_timer = random_range(0, AI_DECISION_INTERVAL);
    _enemy.debug_action = -1;
    _enemy.last_outputs = array_create(NN_OUTPUT_SIZE, 0);
    _enemy.sensor_enabled = std_manager_copy_sensors(global.evo_manager.sensor_enabled);
    _enemy.decision_mode = global.evo_manager.decision_mode;
    _enemy.decision_threshold = global.evo_manager.decision_threshold;
    if (!variable_struct_exists(_enemy, "use_hidden_layers")) {
        _enemy.use_hidden_layers = false;
    }
    std_nn_init_weights(_enemy);
}

/// @desc Returns the nearest living opponent for an RL agent.
/// In automatic training RL fights A/B/C. The empty arena uses the player as a
/// practice target; in normal play every hostile continues targeting the player.
function std_ai_target(_enemy) {
    if (global.state == "TRAIN" || global.state == "BENCHMARK") {
        if (global.state == "TRAIN" && variable_struct_exists(_enemy, "training_target")) {
            var _assigned = _enemy.training_target;
            if (!is_undefined(_assigned) && !_assigned.dead) return _assigned;
            return undefined;
        }
        var _best = undefined;
        var _best_dist = 10000000;
        for (var i = 0; i < array_length(global.enemies); i++) {
            var _candidate = global.enemies[i];
            if (_candidate.dead || _candidate.type == "RL") continue;
            var _dist = point_distance(_enemy.x, _enemy.y, _candidate.x, _candidate.y);
            if (_dist < _best_dist) {
                _best_dist = _dist;
                _best = _candidate;
            }
        }
        if (!is_undefined(_best)) return _best;
        if (global.state == "TRAIN" && global.evo_manager.human_target_active) return global.player;
        if (global.state == "BENCHMARK" && global.benchmark.human_target_active) return global.player;
        return undefined;
    }
    return global.player;
}

/// @desc Builds the six normalized sensors. Melee and ranged readiness are
/// independent inputs. Disabled sensors keep their input
/// slot but emit zero, so toggling them never invalidates a chromosome.
function std_ai_sense(_enemy) {
    var _inputs = array_create(NN_INPUT_SIZE, 0);
    var _target = std_ai_target(_enemy);
    if (is_undefined(_target)) return _inputs;

    var _enabled = variable_struct_exists(_enemy, "sensor_enabled")
        ? _enemy.sensor_enabled : global.evo_manager.sensor_enabled;
    var _dist = point_distance(_enemy.x, _enemy.y, _target.x, _target.y);
    if (_enabled[0]) _inputs[0] = clamp(1 - (_dist / max(_enemy.vision, 1)), 0, 1);
    if (_enabled[1]) _inputs[1] = clamp(_enemy.hp / max(_enemy.hp_max, 1), 0, 1);
    if (_enabled[2]) _inputs[2] = clamp(_enemy.shield / max(_enemy.shield_max, 1), 0, 1);
    if (_enabled[3]) _inputs[3] = std_line_clear(_enemy.x, _enemy.y, _target.x, _target.y) ? 1 : 0;
    if (_enabled[4]) _inputs[4] = 1 - clamp(_enemy.melee_cd / 0.72, 0, 1);
    if (_enabled[5]) _inputs[5] = 1 - clamp(_enemy.ranged_cd / 1.18, 0, 1);
    return _inputs;
}

function std_ai_argmax(_arr) {
    var _best_idx = 0;
    var _best_val = _arr[0];
    for (var i = 1; i < array_length(_arr); i++) {
        if (_arr[i] > _best_val) {
            _best_val = _arr[i];
            _best_idx = i;
        }
    }
    return _best_idx;
}

/// @desc Converts network probabilities to an action. ARGMAX is the safe
/// default for six softmax outputs; threshold mode remains configurable.
function std_ai_choose_action(_enemy, _outputs) {
    var _best_idx = std_ai_argmax(_outputs);
    var _mode = variable_struct_exists(_enemy, "decision_mode")
        ? _enemy.decision_mode : global.evo_manager.decision_mode;
    var _threshold = variable_struct_exists(_enemy, "decision_threshold")
        ? _enemy.decision_threshold : global.evo_manager.decision_threshold;
    if (_mode == "argmax") return _best_idx;
    if (_outputs[_best_idx] >= _threshold) return _best_idx;
    return -1;
}

/// @desc One-shot fitness events that cannot be farmed every frame.
function std_ai_update_fitness(_enemy) {
    if (_enemy.dead) return;

    // Small survival reward, intentionally far below combat rewards.
    _enemy.fitness += 0.02 * global.dt;

    // A dodge is credited once per player swing, only inside the threatened arc.
    var _serial = global.player.melee_serial;
    if (_serial != _enemy.last_player_melee_serial) {
        _enemy.last_player_melee_serial = _serial;
        var _dist = point_distance(global.player.x, global.player.y, _enemy.x, _enemy.y);
        var _angle = abs(angle_difference(
            point_direction(global.player.x, global.player.y, _enemy.x, _enemy.y),
            global.player.attack_facing
        ));
        if (_dist <= 145 && _angle <= 88 && _enemy.last_hit_melee_serial != _serial) {
            _enemy.dodges += 1;
            _enemy.fitness += 1.5;
        }
    }
}

/// @desc Complete policy. Attacks respect range, line of sight and cooldowns;
/// fleeing both plans and follows its escape path.
function std_rl_policy(_enemy) {
    if (_enemy.dead) return;

    var _target = std_ai_target(_enemy);
    if (is_undefined(_target)) {
        std_set_state(_enemy, "SIN OBJETIVO");
        return;
    }

    _enemy.decision_timer = max(0, _enemy.decision_timer - global.dt);
    var _action = _enemy.debug_action;
    if (_enemy.decision_timer <= 0 || _action < -1 || _action >= NN_OUTPUT_SIZE) {
        var _inputs = std_ai_sense(_enemy);
        var _outputs = std_nn_forward(_enemy, _inputs);
        _action = std_ai_choose_action(_enemy, _outputs);
        _enemy.last_outputs = _outputs;
        _enemy.debug_action = _action;
        _enemy.decision_timer = AI_DECISION_INTERVAL;
    }
    if (_action >= 0 && _action < NN_OUTPUT_SIZE) _enemy.action_time[_action] += global.dt;
    _enemy.defending = false;
    _enemy.moving = false;

    var _distance = point_distance(_enemy.x, _enemy.y, _target.x, _target.y);
    var _visible = std_line_clear(_enemy.x, _enemy.y, _target.x, _target.y);

    switch (_action) {
        case AI_ACTION_ESCAPAR:
            std_set_state(_enemy, "ESCAPAR");
            if (_enemy.repath <= 0) std_choose_flee_cell(_enemy, _target);
            std_follow_path(_enemy, 1.08);
        break;

        case AI_ACTION_PERSEGUIR:
            std_set_state(_enemy, "PERSEGUIR");
            if (_enemy.repath <= 0 || _enemy.path_goal_x != std_grid_x(_target.x)
                || _enemy.path_goal_y != std_grid_y(_target.y)) {
                std_plan_path(_enemy, _target.x, _target.y);
            }
            std_follow_path(_enemy, 1.0);
        break;

        case AI_ACTION_MELEE:
            std_set_state(_enemy, "MELEE");
            if (_enemy.melee_cd <= 0 && _distance <= 86) {
                std_enemy_melee(_enemy, 15, _target);
                _enemy.actions_taken += 1;
            } else if (_distance > 86) {
                if (_enemy.repath <= 0) std_plan_path(_enemy, _target.x, _target.y);
                std_follow_path(_enemy, 0.92);
            }
        break;

        case AI_ACTION_DISTANCIA:
            std_set_state(_enemy, "DISTANCIA");
            if (_enemy.ranged_cd <= 0 && _visible && _distance >= 105 && _distance <= 570) {
                std_enemy_ranged(_enemy, 12, true, _target);
                _enemy.actions_taken += 1;
            } else if (!_visible || _distance > 570) {
                if (_enemy.repath <= 0) std_plan_path(_enemy, _target.x, _target.y);
                std_follow_path(_enemy, 0.88);
            }
        break;

        case AI_ACTION_SANAR:
            std_set_state(_enemy, "SANAR");
            if (_enemy.hp < _enemy.hp_max * 0.85) std_potion_seek(_enemy);
        break;

        case AI_ACTION_DEFENDER:
            std_set_state(_enemy, "DEFENDER");
            _enemy.defending = _enemy.shield > 0;
        break;

        default:
            std_set_state(_enemy, "EVALUAR");
        break;
    }
}
