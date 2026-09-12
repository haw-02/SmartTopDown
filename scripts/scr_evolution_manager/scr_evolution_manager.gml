#macro STD_AI_BEST_FILE "smarttopdown_best_ai.json"
#macro STD_AI_CHECKPOINT_FILE "smarttopdown_training_checkpoint.json"
#macro STD_AI_TRAINING_FILE "smarttopdown_training_results.csv"
#macro STD_AI_BENCHMARK_FILE "smarttopdown_benchmark_results.csv"
#macro STD_AI_BENCHMARK_SUMMARY_FILE "smarttopdown_benchmark_summary.csv"
#macro STD_AI_STALL_TIMEOUT 10
#macro STD_AI_TRAINING_ROUNDS 1
#macro STD_AI_TRAINING_HEADER "generation,stage,agent,match,seed,winner,lifespan,damage_dealt,damage_taken,dps,kills,dodges,success_rate,fitness,population,mutation_rate,crossover_rate,selection_rate,weight_init,weight_range,equal_weight,selection_method,tournament_size,mutation_method,mutation_sigma,uniform_range,architecture,decision_mode,threshold,sensors,training_mode"

function std_manager_copy_sensors(_source) {
    var _copy = array_create(NN_INPUT_SIZE, true);
    if (!is_array(_source) || array_length(_source) != NN_INPUT_SIZE) return _copy;
    for (var i = 0; i < NN_INPUT_SIZE; i++) _copy[i] = (_source[i] == true);
    return _copy;
}

function std_manager_valid_sensors(_sensors) {
    if (!is_array(_sensors) || array_length(_sensors) != NN_INPUT_SIZE) return false;
    for (var i = 0; i < NN_INPUT_SIZE; i++) {
        if (!is_bool(_sensors[i])) return false;
    }
    return true;
}

function std_manager_valid_chromosome(_chromosome, _use_hidden_layers) {
    if (!is_array(_chromosome)) return false;
    if (array_length(_chromosome) != std_nn_expected_chromosome_length(_use_hidden_layers)) return false;
    for (var i = 0; i < array_length(_chromosome); i++) {
        if (!is_real(_chromosome[i])) return false;
    }
    return true;
}

function std_manager_valid_training_config(_config) {
    if (!is_struct(_config)) return false;
    var _numeric = ["population_size", "mutation_rate", "crossover_rate", "selection_rate",
        "weight_init_range", "weight_equal_value", "tournament_size", "mutation_sigma",
        "mutation_range", "decision_threshold", "random_seed", "matches_per_agent"];
    for (var i = 0; i < array_length(_numeric); i++) {
        var _name = _numeric[i];
        if (!variable_struct_exists(_config, _name)
            || !is_real(variable_struct_get(_config, _name))) return false;
    }
    var _strings = ["weight_init_mode", "selection_method", "mutation_method", "decision_mode"];
    for (var j = 0; j < array_length(_strings); j++) {
        var _string_name = _strings[j];
        if (!variable_struct_exists(_config, _string_name)
            || !is_string(variable_struct_get(_config, _string_name))) return false;
    }
    if (!variable_struct_exists(_config, "use_hidden_layers")
        || !is_bool(_config.use_hidden_layers)) return false;
    if (!variable_struct_exists(_config, "sensor_enabled")
        || !std_manager_valid_sensors(_config.sensor_enabled)) return false;
    return true;
}

function std_manager_reject_best(_reason) {
    show_debug_message("MEJOR IA IGNORADA: " + _reason);
    return false;
}

function std_manager_init() {
    global.evo_manager = {
        population_size: 10,
        generation_count: 0,
        max_generations: 100,
        mutation_rate: 0.10,
        crossover_rate: 0.80,
        selection_method: "tournament",
        tournament_size: 3,
        mutation_method: "gaussian",
        mutation_range: 1,
        mutation_sigma: 0.30,
        selection_rate: 0.50,
        weight_init_mode: "random",
        weight_init_range: 1.00,
        weight_equal_value: 0.25,
        use_hidden_layers: true,
        decision_mode: "argmax",
        decision_threshold: 0.22,
        sensor_enabled: [true, true, true, true, true, true],
        population_pool: [],
        active_enemies: [],
        generation_timer: 0,
        generation_timer_limit: 75,
        training_active: false,
        training_paused: false,
        best_chromosome_ever: undefined,
        best_fitness_ever: -99999,
        best_use_hidden_layers: true,
        best_sensor_enabled: [true, true, true, true, true, true],
        best_decision_mode: "argmax",
        best_decision_threshold: 0.22,
        best_generation: -1,
        best_stage_index: -1,
        best_config: undefined,
        progress_chromosome: undefined,
        progress_fitness: -99999,
        progress_use_hidden_layers: true,
        progress_sensor_enabled: [true, true, true, true, true, true],
        progress_decision_mode: "argmax",
        progress_decision_threshold: 0.22,
        progress_generation: -1,
        progress_stage_index: -1,
        progress_config: undefined,
        logs: [],
        fitness_threshold: 45,
        training_stages: [0, 1, 2, 3],
        training_levels: [0, 1, 2, 3],
        training_opponents: ["A", "B", "C", "HUMAN"],
        stage_names: ["Enemigo A", "Enemigo B", "Enemigo C", "Jugador humano"],
        stage_index: 0,
        vs_human: false,
        total_enemies_snapshot: 0,
        matches_per_agent: STD_AI_TRAINING_ROUNDS,
        random_seed: 1337,
        training_mode: "parallel",
        parallel_level: 5,
        evaluation_agent_index: 0,
        evaluation_match_index: 0,
        generation_results: [],
        active_opponents: [],
        pair_finished: [],
        pair_progress_damage: [],
        pair_no_progress_time: [],
        parallel_finished_count: 0,
        episode_progress_damage: 0,
        episode_no_progress_time: 0,
        isolated_evaluation: false,
        human_target_active: false,
        episode_winner: "",
        training_csv_ready: false
    };

    std_manager_load_best();
    std_benchmark_init();
}

function std_manager_set_hidden_layers(_state) {
    var _mgr = global.evo_manager;
    if (_mgr.use_hidden_layers == _state) return;
    _mgr.use_hidden_layers = _state;
    _mgr.population_pool = [];
}

function std_manager_reset_defaults() {
    var _mgr = global.evo_manager;
    _mgr.population_size = 10;
    _mgr.max_generations = 100;
    _mgr.mutation_rate = 0.10;
    _mgr.crossover_rate = 0.80;
    _mgr.selection_method = "tournament";
    _mgr.tournament_size = 3;
    _mgr.mutation_method = "gaussian";
    _mgr.mutation_range = 1;
    _mgr.mutation_sigma = 0.30;
    _mgr.selection_rate = 0.50;
    _mgr.weight_init_mode = "random";
    _mgr.weight_init_range = 1.00;
    _mgr.weight_equal_value = 0.25;
    _mgr.generation_timer_limit = 75;
    _mgr.fitness_threshold = 45;
    _mgr.decision_mode = "argmax";
    _mgr.decision_threshold = 0.22;
    _mgr.sensor_enabled = [true, true, true, true, true, true];
    _mgr.matches_per_agent = STD_AI_TRAINING_ROUNDS;
    _mgr.random_seed = 1337;
    _mgr.training_mode = "parallel";
    if (variable_global_exists("benchmark")) global.benchmark.seed = _mgr.random_seed;
    std_manager_set_hidden_layers(true);
    _mgr.population_pool = [];
}

function std_manager_save_best() {
    var _mgr = global.evo_manager;
    if (is_undefined(_mgr.best_chromosome_ever)) return false;

    var _progress_chromosome = is_undefined(_mgr.progress_chromosome)
        ? _mgr.best_chromosome_ever : _mgr.progress_chromosome;
    var _progress_fitness = is_undefined(_mgr.progress_chromosome)
        ? _mgr.best_fitness_ever : _mgr.progress_fitness;
    var _progress_hidden = is_undefined(_mgr.progress_chromosome)
        ? _mgr.best_use_hidden_layers : _mgr.progress_use_hidden_layers;
    var _progress_sensors = is_undefined(_mgr.progress_chromosome)
        ? _mgr.best_sensor_enabled : _mgr.progress_sensor_enabled;
    var _progress_mode = is_undefined(_mgr.progress_chromosome)
        ? _mgr.best_decision_mode : _mgr.progress_decision_mode;
    var _progress_threshold = is_undefined(_mgr.progress_chromosome)
        ? _mgr.best_decision_threshold : _mgr.progress_decision_threshold;
    var _progress_generation = is_undefined(_mgr.progress_chromosome)
        ? _mgr.best_generation : _mgr.progress_generation;
    var _progress_stage = is_undefined(_mgr.progress_chromosome)
        ? _mgr.best_stage_index : _mgr.progress_stage_index;
    var _progress_config = is_undefined(_mgr.progress_chromosome)
        ? _mgr.best_config : _mgr.progress_config;

    var _file = file_text_open_write(STD_AI_BEST_FILE);
    if (_file < 0) return false;
    var _payload = {
        version: 5,
        input_count: NN_INPUT_SIZE,
        hidden_count: NN_HIDDEN_SIZE,
        output_count: NN_OUTPUT_SIZE,
        chromosome_length: array_length(_mgr.best_chromosome_ever),
        fitness: _mgr.best_fitness_ever,
        generation: _mgr.best_generation,
        stage_index: _mgr.best_stage_index,
        use_hidden_layers: _mgr.best_use_hidden_layers,
        chromosome: _mgr.best_chromosome_ever,
        sensor_enabled: _mgr.best_sensor_enabled,
        decision_mode: _mgr.best_decision_mode,
        decision_threshold: _mgr.best_decision_threshold,
        training_config: _mgr.best_config,
        progress_champion: {
            chromosome_length: array_length(_progress_chromosome),
            fitness: _progress_fitness,
            generation: _progress_generation,
            stage_index: _progress_stage,
            use_hidden_layers: _progress_hidden,
            chromosome: _progress_chromosome,
            sensor_enabled: _progress_sensors,
            decision_mode: _progress_mode,
            decision_threshold: _progress_threshold,
            training_config: _progress_config
        }
    };
    file_text_write_string(_file, json_stringify(_payload));
    file_text_close(_file);
    return true;
}

function std_manager_load_best() {
    if (!file_exists(STD_AI_BEST_FILE)) return false;
    var _file = file_text_open_read(STD_AI_BEST_FILE);
    if (_file < 0) return false;
    var _text = "";
    while (!file_text_eof(_file)) _text += file_text_readln(_file);
    file_text_close(_file);

    try {
        var _data = json_parse(_text);
        if (!is_struct(_data)) return std_manager_reject_best("JSON SIN ESTRUCTURA VALIDA");
        if (!variable_struct_exists(_data, "version") || !is_real(_data.version)
            || (_data.version != 4 && _data.version != 5)) {
            return std_manager_reject_best("VERSION INCOMPATIBLE; ENTRENA UN CAMPEON V9 O POSTERIOR");
        }
        if (!variable_struct_exists(_data, "input_count") || _data.input_count != NN_INPUT_SIZE
            || !variable_struct_exists(_data, "hidden_count") || _data.hidden_count != NN_HIDDEN_SIZE
            || !variable_struct_exists(_data, "output_count") || _data.output_count != NN_OUTPUT_SIZE) {
            return std_manager_reject_best("DIMENSIONES DE RED INCOMPATIBLES");
        }
        if (!variable_struct_exists(_data, "use_hidden_layers") || !is_bool(_data.use_hidden_layers)) {
            return std_manager_reject_best("ARQUITECTURA AUSENTE O INVALIDA");
        }
        var _use_hidden = _data.use_hidden_layers;
        if (!variable_struct_exists(_data, "chromosome")
            || !std_manager_valid_chromosome(_data.chromosome, _use_hidden)) {
            return std_manager_reject_best("CROMOSOMA INVALIDO PARA LA ARQUITECTURA");
        }
        if (!variable_struct_exists(_data, "chromosome_length")
            || !is_real(_data.chromosome_length)
            || _data.chromosome_length != array_length(_data.chromosome)) {
            return std_manager_reject_best("LONGITUD DE CROMOSOMA INCONSISTENTE");
        }
        if (!variable_struct_exists(_data, "sensor_enabled")
            || !std_manager_valid_sensors(_data.sensor_enabled)) {
            return std_manager_reject_best("CONFIGURACION DE SENSORES INVALIDA");
        }
        if (!variable_struct_exists(_data, "decision_mode") || !is_string(_data.decision_mode)
            || (_data.decision_mode != "argmax" && _data.decision_mode != "threshold")) {
            return std_manager_reject_best("MODO DE DECISION INVALIDO");
        }
        if (!variable_struct_exists(_data, "decision_threshold")
            || !is_real(_data.decision_threshold) || _data.decision_threshold < 0
            || _data.decision_threshold > 1) {
            return std_manager_reject_best("UMBRAL DE DECISION INVALIDO");
        }
        if (variable_struct_exists(_data, "fitness") && !is_real(_data.fitness)) {
            return std_manager_reject_best("FITNESS INVALIDO");
        }
        if (variable_struct_exists(_data, "generation") && !is_real(_data.generation)) {
            return std_manager_reject_best("GENERACION INVALIDA");
        }
        if (variable_struct_exists(_data, "stage_index") && !is_real(_data.stage_index)) {
            return std_manager_reject_best("ETAPA INVALIDA");
        }
        var _mgr = global.evo_manager;
        _mgr.best_chromosome_ever = std_ga_copy_chromosome(_data.chromosome);
        _mgr.best_fitness_ever = variable_struct_exists(_data, "fitness") ? _data.fitness : 0;
        _mgr.best_generation = variable_struct_exists(_data, "generation") ? _data.generation : -1;
        _mgr.best_stage_index = variable_struct_exists(_data, "stage_index") ? _data.stage_index : -1;
        _mgr.best_use_hidden_layers = _use_hidden;
        _mgr.best_sensor_enabled = std_manager_copy_sensors(_data.sensor_enabled);
        _mgr.best_decision_mode = _data.decision_mode;
        _mgr.best_decision_threshold = _data.decision_threshold;
        _mgr.best_config = variable_struct_exists(_data, "training_config")
            && std_manager_valid_training_config(_data.training_config)
            ? _data.training_config : undefined;

        // v4 only stored one stage-aware champion. It is imported safely as
        // both the historical record and the furthest-stage progress champion.
        _mgr.progress_chromosome = std_ga_copy_chromosome(_mgr.best_chromosome_ever);
        _mgr.progress_fitness = _mgr.best_fitness_ever;
        _mgr.progress_generation = _mgr.best_generation;
        _mgr.progress_stage_index = _mgr.best_stage_index;
        _mgr.progress_use_hidden_layers = _mgr.best_use_hidden_layers;
        _mgr.progress_sensor_enabled = std_manager_copy_sensors(_mgr.best_sensor_enabled);
        _mgr.progress_decision_mode = _mgr.best_decision_mode;
        _mgr.progress_decision_threshold = _mgr.best_decision_threshold;
        _mgr.progress_config = _mgr.best_config;

        if (_data.version == 5 && variable_struct_exists(_data, "progress_champion")) {
            var _progress = _data.progress_champion;
            var _progress_valid = is_struct(_progress)
                && variable_struct_exists(_progress, "use_hidden_layers") && is_bool(_progress.use_hidden_layers)
                && variable_struct_exists(_progress, "chromosome")
                && std_manager_valid_chromosome(_progress.chromosome, _progress.use_hidden_layers)
                && variable_struct_exists(_progress, "sensor_enabled")
                && std_manager_valid_sensors(_progress.sensor_enabled)
                && variable_struct_exists(_progress, "decision_mode") && is_string(_progress.decision_mode)
                && (_progress.decision_mode == "argmax" || _progress.decision_mode == "threshold")
                && variable_struct_exists(_progress, "decision_threshold")
                && is_real(_progress.decision_threshold) && _progress.decision_threshold >= 0
                && _progress.decision_threshold <= 1
                && variable_struct_exists(_progress, "fitness") && is_real(_progress.fitness)
                && variable_struct_exists(_progress, "generation") && is_real(_progress.generation)
                && variable_struct_exists(_progress, "stage_index") && is_real(_progress.stage_index);
            if (_progress_valid) {
                _mgr.progress_chromosome = std_ga_copy_chromosome(_progress.chromosome);
                _mgr.progress_fitness = _progress.fitness;
                _mgr.progress_generation = _progress.generation;
                _mgr.progress_stage_index = _progress.stage_index;
                _mgr.progress_use_hidden_layers = _progress.use_hidden_layers;
                _mgr.progress_sensor_enabled = std_manager_copy_sensors(_progress.sensor_enabled);
                _mgr.progress_decision_mode = _progress.decision_mode;
                _mgr.progress_decision_threshold = _progress.decision_threshold;
                _mgr.progress_config = variable_struct_exists(_progress, "training_config")
                    && std_manager_valid_training_config(_progress.training_config)
                    ? _progress.training_config : undefined;
            } else {
                show_debug_message("CAMPEON DE PROGRESO INVALIDO; SE USARA EL MEJOR HISTORICO");
            }
        }
        return true;
    } catch (_error) {
        show_debug_message("No se pudo cargar " + STD_AI_BEST_FILE + ": " + string(_error));
        return false;
    }
}

function std_manager_config_snapshot() {
    var _mgr = global.evo_manager;
    return {
        population_size: _mgr.population_size,
        max_generations: _mgr.max_generations,
        generation_timer_limit: _mgr.generation_timer_limit,
        fitness_threshold: _mgr.fitness_threshold,
        mutation_rate: _mgr.mutation_rate,
        crossover_rate: _mgr.crossover_rate,
        selection_rate: _mgr.selection_rate,
        weight_init_mode: _mgr.weight_init_mode,
        weight_init_range: _mgr.weight_init_range,
        weight_equal_value: _mgr.weight_equal_value,
        selection_method: _mgr.selection_method,
        tournament_size: _mgr.tournament_size,
        mutation_method: _mgr.mutation_method,
        mutation_sigma: _mgr.mutation_sigma,
        mutation_range: _mgr.mutation_range,
        use_hidden_layers: _mgr.use_hidden_layers,
        decision_mode: _mgr.decision_mode,
        decision_threshold: _mgr.decision_threshold,
        random_seed: _mgr.random_seed,
        matches_per_agent: _mgr.matches_per_agent,
        training_mode: _mgr.training_mode,
        sensor_enabled: std_manager_copy_sensors(_mgr.sensor_enabled)
    };
}

function std_manager_apply_config_snapshot(_config) {
    if (!std_manager_valid_training_config(_config)) return false;
    var _mgr = global.evo_manager;
    _mgr.population_size = clamp(round(_config.population_size), 2, 24);
    if (variable_struct_exists(_config, "max_generations") && is_real(_config.max_generations)) {
        _mgr.max_generations = clamp(round(_config.max_generations), 1, 1000);
    }
    if (variable_struct_exists(_config, "generation_timer_limit") && is_real(_config.generation_timer_limit)) {
        _mgr.generation_timer_limit = clamp(round(_config.generation_timer_limit), 15, 180);
    }
    if (variable_struct_exists(_config, "fitness_threshold") && is_real(_config.fitness_threshold)) {
        _mgr.fitness_threshold = clamp(_config.fitness_threshold, 10, 300);
    }
    _mgr.mutation_rate = clamp(_config.mutation_rate, 0, 0.50);
    _mgr.crossover_rate = clamp(_config.crossover_rate, 0, 1);
    _mgr.selection_rate = clamp(_config.selection_rate, 0.10, 1);
    _mgr.weight_init_mode = _config.weight_init_mode;
    _mgr.weight_init_range = _config.weight_init_range;
    _mgr.weight_equal_value = _config.weight_equal_value;
    _mgr.selection_method = _config.selection_method;
    _mgr.tournament_size = clamp(round(_config.tournament_size), 2, 8);
    _mgr.mutation_method = _config.mutation_method;
    _mgr.mutation_sigma = _config.mutation_sigma;
    _mgr.mutation_range = _config.mutation_range;
    _mgr.use_hidden_layers = _config.use_hidden_layers;
    _mgr.decision_mode = _config.decision_mode;
    _mgr.decision_threshold = _config.decision_threshold;
    _mgr.random_seed = round(_config.random_seed);
    // Training always evaluates the whole population once per generation.
    // Keep the legacy field in snapshots/CSV so v12-v13 saves remain readable,
    // but never let it control benchmark repetitions or create extra rounds.
    _mgr.matches_per_agent = STD_AI_TRAINING_ROUNDS;
    _mgr.sensor_enabled = std_manager_copy_sensors(_config.sensor_enabled);
    if (variable_struct_exists(_config, "training_mode") && is_string(_config.training_mode)) {
        _mgr.training_mode = _config.training_mode;
    }
    return true;
}

function std_manager_valid_population(_population, _count, _use_hidden_layers) {
    if (!is_array(_population) || array_length(_population) != _count) return false;
    for (var i = 0; i < _count; i++) {
        if (!std_manager_valid_chromosome(_population[i], _use_hidden_layers)) return false;
    }
    return true;
}

function std_manager_valid_generation_results(_results, _count) {
    if (!is_array(_results) || array_length(_results) != _count) return false;
    var _numeric = ["fitness_sum", "lifespan_sum", "damage_dealt_sum", "damage_taken_sum",
        "kills_sum", "dodges_sum", "wins", "losses", "draws", "timeouts"];
    for (var i = 0; i < _count; i++) {
        var _result = _results[i];
        if (!is_struct(_result)) return false;
        for (var n = 0; n < array_length(_numeric); n++) {
            var _name = _numeric[n];
            if (!variable_struct_exists(_result, _name)
                || !is_real(variable_struct_get(_result, _name))) return false;
        }
        if (!variable_struct_exists(_result, "action_time")
            || !is_array(_result.action_time)
            || array_length(_result.action_time) != NN_OUTPUT_SIZE) return false;
    }
    return true;
}

function std_manager_checkpoint_save() {
    var _mgr = global.evo_manager;
    if (!std_manager_valid_population(_mgr.population_pool, _mgr.population_size, _mgr.use_hidden_layers)) return false;
    var _file = file_text_open_write(STD_AI_CHECKPOINT_FILE);
    if (_file < 0) return false;
    var _payload = {
        version: 1,
        generation_count: _mgr.generation_count,
        stage_index: _mgr.stage_index,
        evaluation_agent_index: _mgr.evaluation_agent_index,
        evaluation_match_index: _mgr.evaluation_match_index,
        config: std_manager_config_snapshot(),
        population_pool: _mgr.population_pool,
        generation_results: _mgr.generation_results
    };
    file_text_write_string(_file, json_stringify(_payload));
    file_text_close(_file);
    return true;
}

function std_manager_checkpoint_load() {
    if (!file_exists(STD_AI_CHECKPOINT_FILE)) return false;
    var _file = file_text_open_read(STD_AI_CHECKPOINT_FILE);
    if (_file < 0) return false;
    var _text = "";
    while (!file_text_eof(_file)) _text += file_text_readln(_file);
    file_text_close(_file);

    try {
        var _data = json_parse(_text);
        if (!is_struct(_data) || !variable_struct_exists(_data, "version") || _data.version != 1) return false;
        var _required_numbers = ["generation_count", "stage_index", "evaluation_agent_index", "evaluation_match_index"];
        for (var r = 0; r < array_length(_required_numbers); r++) {
            var _required_name = _required_numbers[r];
            if (!variable_struct_exists(_data, _required_name)
                || !is_real(variable_struct_get(_data, _required_name))) return false;
        }
        if (!variable_struct_exists(_data, "config")) return false;
        var _legacy_multi_round = variable_struct_exists(_data.config, "matches_per_agent")
            && is_real(_data.config.matches_per_agent)
            && round(_data.config.matches_per_agent) != STD_AI_TRAINING_ROUNDS;
        if (!std_manager_apply_config_snapshot(_data.config)) return false;
        var _mgr = global.evo_manager;
        if (!variable_struct_exists(_data, "population_pool")
            || !std_manager_valid_population(_data.population_pool, _mgr.population_size, _mgr.use_hidden_layers)) return false;
        if (!variable_struct_exists(_data, "generation_results")
            || !std_manager_valid_generation_results(_data.generation_results, _mgr.population_size)) return false;

        _mgr.population_pool = [];
        for (var i = 0; i < _mgr.population_size; i++) {
            array_push(_mgr.population_pool, std_ga_copy_chromosome(_data.population_pool[i]));
        }
        _mgr.generation_results = _data.generation_results;
        _mgr.generation_count = max(0, round(_data.generation_count));
        _mgr.stage_index = clamp(round(_data.stage_index), 0, array_length(_mgr.training_stages) - 1);
        if (_legacy_multi_round) {
            // A v12/v13 checkpoint can contain a partially accumulated 3-round
            // generation. Re-evaluate only that unfinished generation once so
            // old sums cannot inflate the new single-round fitness.
            _mgr.evaluation_agent_index = 0;
            _mgr.evaluation_match_index = 0;
            std_manager_reset_generation_results();
            show_debug_message("CHECKPOINT LEGACY: GENERACION PARCIAL REINICIADA EN RONDA UNICA");
        } else {
            _mgr.evaluation_agent_index = clamp(round(_data.evaluation_agent_index), 0, _mgr.population_size - 1);
            _mgr.evaluation_match_index = 0;
        }
        return true;
    } catch (_error) {
        show_debug_message("No se pudo cargar checkpoint: " + string(_error));
        return false;
    }
}

function std_manager_seed_population_from_best() {
    var _mgr = global.evo_manager;
    if (is_undefined(_mgr.progress_chromosome)) return false;
    if (!is_undefined(_mgr.progress_config)) std_manager_apply_config_snapshot(_mgr.progress_config);
    _mgr.use_hidden_layers = _mgr.progress_use_hidden_layers;
    _mgr.sensor_enabled = std_manager_copy_sensors(_mgr.progress_sensor_enabled);
    _mgr.decision_mode = _mgr.progress_decision_mode;
    _mgr.decision_threshold = _mgr.progress_decision_threshold;
    if (!std_manager_valid_chromosome(_mgr.progress_chromosome, _mgr.use_hidden_layers)) return false;

    random_set_seed(_mgr.random_seed + max(0, _mgr.progress_generation + 1) * 100000);
    _mgr.population_pool = [];
    array_push(_mgr.population_pool, std_ga_copy_chromosome(_mgr.progress_chromosome));
    for (var i = 1; i < _mgr.population_size; i++) {
        var _child = std_ga_copy_chromosome(_mgr.progress_chromosome);
        if (_mgr.mutation_method == "gaussian") {
            _child = std_ga_mutate_gaussian(_child, _mgr.mutation_rate, _mgr.mutation_sigma);
        } else {
            _child = std_ga_mutate_uniform(_child, _mgr.mutation_rate, _mgr.mutation_range);
        }
        array_push(_mgr.population_pool, _child);
    }
    _mgr.generation_count = max(0, _mgr.progress_generation + 1);
    _mgr.stage_index = clamp(max(0, _mgr.progress_stage_index), 0, array_length(_mgr.training_stages) - 1);
    _mgr.evaluation_agent_index = 0;
    _mgr.evaluation_match_index = 0;
    std_manager_reset_generation_results();
    return true;
}

function std_manager_prepare_training_csv(_replace = false) {
    if (_replace || !file_exists(STD_AI_TRAINING_FILE)) {
        return std_csv_write_new(STD_AI_TRAINING_FILE, STD_AI_TRAINING_HEADER);
    }
    return true;
}

function std_manager_remove_unmanaged_rl() {
    for (var i = array_length(global.enemies) - 1; i >= 0; i--) {
        var _enemy = global.enemies[i];
        if (_enemy.type == "RL") {
            if (_enemy.path_id >= 0) path_delete(_enemy.path_id);
            array_delete(global.enemies, i, 1);
        }
    }
}

function std_manager_cell_used(_cx, _cy, _used) {
    for (var i = 0; i < array_length(_used); i++) {
        if (_used[i][0] == _cx && _used[i][1] == _cy) return true;
    }
    return false;
}

function std_manager_find_free_cell(_base_cx, _base_cy, _used) {
    for (var _ring = 0; _ring < 14; _ring++) {
        for (var _dx = -_ring; _dx <= _ring; _dx++) {
            for (var _dy = -_ring; _dy <= _ring; _dy++) {
                if (max(abs(_dx), abs(_dy)) != _ring) continue;
                var _cx = clamp(_base_cx + _dx, 1, global.level.cols - 2);
                var _cy = clamp(_base_cy + _dy, 1, global.level.rows - 2);
                if (!std_wall_cell(_cx, _cy) && global.spike_grid[# _cx, _cy] == 0
                    && !std_manager_cell_used(_cx, _cy, _used)) {
                    return { x: _cx, y: _cy };
                }
            }
        }
    }
    return { x: _base_cx, y: _base_cy };
}

function std_csv_write_new(_filename, _header) {
    var _file = file_text_open_write(_filename);
    if (_file < 0) return false;
    file_text_write_string(_file, _header);
    file_text_writeln(_file);
    file_text_close(_file);
    return true;
}

function std_csv_append(_filename, _row) {
    var _file = file_text_open_append(_filename);
    if (_file < 0) return false;
    file_text_write_string(_file, _row);
    file_text_writeln(_file);
    file_text_close(_file);
    return true;
}

function std_manager_clear_enemies() {
    for (var i = 0; i < array_length(global.enemies); i++) {
        if (global.enemies[i].path_id >= 0) path_delete(global.enemies[i].path_id);
    }
    global.enemies = [];
    global.projectiles = [];
}

function std_manager_empty_result() {
    return {
        fitness_sum: 0, lifespan_sum: 0, damage_dealt_sum: 0, damage_taken_sum: 0,
        kills_sum: 0, dodges_sum: 0, wins: 0, losses: 0, draws: 0, timeouts: 0,
        action_time: array_create(NN_OUTPUT_SIZE, 0)
    };
}

function std_manager_reset_generation_results() {
    var _mgr = global.evo_manager;
    _mgr.generation_results = [];
    for (var i = 0; i < _mgr.population_size; i++) {
        array_push(_mgr.generation_results, std_manager_empty_result());
    }
}

function std_manager_build_initial_population() {
    var _mgr = global.evo_manager;
    random_set_seed(_mgr.random_seed);
    _mgr.population_pool = [];
    var _length = std_nn_expected_chromosome_length(_mgr.use_hidden_layers);
    for (var i = 0; i < _mgr.population_size; i++) {
        array_push(_mgr.population_pool, std_ga_init_chromosome(
            _length, _mgr.weight_init_mode, _mgr.weight_init_range, _mgr.weight_equal_value
        ));
    }
}

function std_manager_parallel_pair_cells(_index) {
    // Arena 5 contains 24 isolated lanes: six columns by four rows.
    var _lane_col = _index mod 6;
    var _lane_row = floor(_index / 6);
    var _lane_x = 1 + _lane_col * 8;
    var _lane_y = 1 + _lane_row * 7;
    return {
        agent_x: _lane_x + 1,
        agent_y: _lane_y + 2,
        opponent_x: _lane_x + 5,
        opponent_y: _lane_y + 2
    };
}

function std_manager_parallel_enabled_for_stage() {
    var _mgr = global.evo_manager;
    return _mgr.training_mode == "parallel"
        && _mgr.training_opponents[_mgr.stage_index] != "HUMAN";
}

function std_manager_spawn_parallel_round() {
    var _mgr = global.evo_manager;
    var _seed = _mgr.random_seed + _mgr.generation_count * 100000
        + _mgr.stage_index * 10000 + _mgr.evaluation_match_index;
    random_set_seed(_seed);

    std_load_level(_mgr.parallel_level);
    std_manager_clear_enemies();
    _mgr.active_enemies = [];
    _mgr.active_opponents = [];
    _mgr.pair_finished = array_create(_mgr.population_size, false);
    _mgr.pair_progress_damage = array_create(_mgr.population_size, 0);
    _mgr.pair_no_progress_time = array_create(_mgr.population_size, 0);
    _mgr.parallel_finished_count = 0;
    _mgr.generation_timer = 0;
    _mgr.episode_winner = "";
    _mgr.human_target_active = false;
    _mgr.total_enemies_snapshot = 1;

    // Each lane owns one potion, preventing candidates from competing for the
    // same healing resource during simultaneous evaluation.
    for (var p = 0; p < array_length(global.potions); p++) {
        global.potions[p].training_pair_index = p;
    }

    for (var i = 0; i < _mgr.population_size; i++) {
        var _cells = std_manager_parallel_pair_cells(i);
        var _opponent = std_make_enemy(
            _mgr.training_opponents[_mgr.stage_index], _cells.opponent_x, _cells.opponent_y
        );
        var _agent = std_make_enemy("RL", _cells.agent_x, _cells.agent_y);
        _agent.use_hidden_layers = _mgr.use_hidden_layers;
        std_ai_init_agent(_agent);
        _agent.lifespan_time = 0;
        _agent.logged = false;
        _agent.training_pair_index = i;
        _opponent.training_pair_index = i;
        _agent.training_target = _opponent;
        _opponent.training_target = _agent;
        _agent.training_rng_state = 1 + (abs(_seed) mod 2147483646);
        _opponent.training_rng_state = 1 + ((abs(_seed) + 9973) mod 2147483646);
        _agent.melee_cd = 0.15;
        _agent.ranged_cd = 0.25;
        _agent.anim_phase = 0;
        _agent.decision_timer = 0;
        _opponent.melee_cd = 0.15;
        _opponent.ranged_cd = 0.25;
        _opponent.anim_phase = 0;
        std_nn_unflatten(_agent, _mgr.population_pool[i]);

        array_push(_mgr.active_enemies, _agent);
        array_push(_mgr.active_opponents, _opponent);
        array_push(global.enemies, _opponent);
        array_push(global.enemies, _agent);
    }

    global.state = "TRAIN";
    global.level_banner = 0.35;
    global.message = "MODO SIMULTANEO - " + string(_mgr.population_size)
        + " AGENTES - RONDA " + string(_mgr.evaluation_match_index + 1)
        + "/" + string(_mgr.matches_per_agent);
    global.message_time = 1.2;
}

function std_manager_spawn_training_episode() {
    var _mgr = global.evo_manager;
    // Every chromosome in one generation receives the same seed per match.
    // Agent index is deliberately excluded so fitness comparisons are fair.
    var _seed = _mgr.random_seed + _mgr.generation_count * 100000
        + _mgr.stage_index * 10000 + _mgr.evaluation_match_index;
    random_set_seed(_seed);

    var _level_index = _mgr.training_levels[_mgr.stage_index];
    std_load_level(_level_index);
    std_manager_clear_enemies();
    _mgr.active_enemies = [];
    _mgr.generation_timer = 0;
    _mgr.episode_progress_damage = 0;
    _mgr.episode_no_progress_time = 0;
    _mgr.episode_winner = "";
    _mgr.human_target_active = _mgr.training_opponents[_mgr.stage_index] == "HUMAN";
    _mgr.total_enemies_snapshot = 1;

    var _used = [];
    if (!_mgr.human_target_active) {
        var _opponent_cell = std_manager_find_free_cell(
            floor(global.level.cols * 0.72), floor(global.level.rows * 0.50), _used
        );
        array_push(_used, [_opponent_cell.x, _opponent_cell.y]);
        array_push(global.enemies, std_make_enemy(
            _mgr.training_opponents[_mgr.stage_index], _opponent_cell.x, _opponent_cell.y
        ));
    }

    var _agent_cell = std_manager_find_free_cell(
        floor(global.level.cols * 0.28), floor(global.level.rows * 0.50), _used
    );
    var _agent = std_make_enemy("RL", _agent_cell.x, _agent_cell.y);
    _agent.use_hidden_layers = _mgr.use_hidden_layers;
    std_ai_init_agent(_agent);
    _agent.lifespan_time = 0;
    _agent.logged = false;
    std_nn_unflatten(_agent, _mgr.population_pool[_mgr.evaluation_agent_index]);
    array_push(_mgr.active_enemies, _agent);
    array_push(global.enemies, _agent);

    global.state = "TRAIN";
    global.level_banner = 0.35;
    global.message = "AGENTE " + string(_mgr.evaluation_agent_index + 1) + "/" + string(_mgr.population_size)
        + " - PARTIDA " + string(_mgr.evaluation_match_index + 1) + "/" + string(_mgr.matches_per_agent);
    global.message_time = 1.0;
}

function std_manager_spawn_population() {
    if (std_manager_parallel_enabled_for_stage()) std_manager_spawn_parallel_round();
    else std_manager_spawn_training_episode();
}

function std_manager_start_training(_restart_progress = true) {
    var _mgr = global.evo_manager;
    _mgr.matches_per_agent = STD_AI_TRAINING_ROUNDS;
    if (_restart_progress) {
        _mgr.stage_index = 0;
        _mgr.generation_count = 0;
        _mgr.logs = [];
        _mgr.vs_human = false;
        _mgr.best_chromosome_ever = undefined;
        _mgr.best_fitness_ever = -99999;
        _mgr.best_generation = -1;
        _mgr.best_stage_index = -1;
        _mgr.best_config = undefined;
        _mgr.progress_chromosome = undefined;
        _mgr.progress_fitness = -99999;
        _mgr.progress_use_hidden_layers = true;
        _mgr.progress_sensor_enabled = [true, true, true, true, true, true];
        _mgr.progress_decision_mode = "argmax";
        _mgr.progress_decision_threshold = 0.22;
        _mgr.progress_generation = -1;
        _mgr.progress_stage_index = -1;
        _mgr.progress_config = undefined;
        _mgr.evaluation_agent_index = 0;
        _mgr.evaluation_match_index = 0;
        std_manager_build_initial_population();
        std_manager_reset_generation_results();
        _mgr.training_csv_ready = std_manager_prepare_training_csv(true);
        std_manager_checkpoint_save();
    } else if (array_length(_mgr.population_pool) != _mgr.population_size) {
        std_manager_build_initial_population();
        std_manager_reset_generation_results();
    }
    _mgr.training_active = true;
    _mgr.training_paused = false;
    _mgr.isolated_evaluation = true;
    std_manager_spawn_population();
}

/// @desc Continues an exact v12 generation-boundary checkpoint when present.
/// A v11 installation has no checkpoint, so it falls back to its automatically
/// saved champion and rebuilds a compatible population around that elite.
function std_manager_resume_training() {
    var _mgr = global.evo_manager;
    _mgr.matches_per_agent = STD_AI_TRAINING_ROUNDS;
    var _requested_max_generations = _mgr.max_generations;
    var _exact = std_manager_checkpoint_load();
    var _from_best = false;
    if (!_exact) _from_best = std_manager_seed_population_from_best();
    if (!_exact && !_from_best) return false;
    _mgr.max_generations = max(_mgr.max_generations, _requested_max_generations);

    if (_mgr.generation_count >= _mgr.max_generations) {
        global.ai_menu_message = "AUMENTA MAX. GENERACIONES PARA CONTINUAR";
        return true;
    }

    _mgr.logs = [];
    _mgr.vs_human = false;
    _mgr.training_csv_ready = std_manager_prepare_training_csv(false);
    _mgr.training_active = true;
    _mgr.training_paused = false;
    _mgr.isolated_evaluation = true;
    std_manager_checkpoint_save();
    std_manager_spawn_population();
    global.message = _exact ? "CHECKPOINT COMPLETO CARGADO" : "CAMPEON V11 RECUPERADO";
    global.message_time = 2.2;
    return true;
}

function std_manager_stop_training() {
    var _mgr = global.evo_manager;
    _mgr.training_active = false;
    _mgr.training_paused = false;
    _mgr.isolated_evaluation = false;
    _mgr.human_target_active = false;
    _mgr.active_enemies = [];
    _mgr.active_opponents = [];
    _mgr.pair_finished = [];
    std_load_level(0);
    global.state = "MENU";
    global.menu_option = 0;
}

function std_manager_toggle_pause() {
    var _mgr = global.evo_manager;
    if (!_mgr.training_active) return;
    _mgr.training_paused = !_mgr.training_paused;
    global.message = _mgr.training_paused ? "ENTRENAMIENTO EN PAUSA" : "ENTRENAMIENTO REANUDADO";
    global.message_time = 1.2;
}

function std_manager_test_best() {
    var _mgr = global.evo_manager;
    if (is_undefined(_mgr.progress_chromosome)) return false;
    _mgr.training_active = false;
    _mgr.training_paused = false;
    _mgr.isolated_evaluation = false;
    _mgr.human_target_active = false;
    std_load_level(3);
    std_manager_remove_unmanaged_rl();
    var _enemy = std_make_enemy("RL", floor(global.level.cols / 2), floor(global.level.rows / 2));
    _enemy.use_hidden_layers = _mgr.progress_use_hidden_layers;
    std_ai_init_agent(_enemy);
    if (!std_manager_apply_best_to_enemy(_enemy)) {
        if (_enemy.path_id >= 0) path_delete(_enemy.path_id);
        return false;
    }
    _mgr.sensor_enabled = std_manager_copy_sensors(_mgr.progress_sensor_enabled);
    _mgr.decision_mode = _mgr.progress_decision_mode;
    _mgr.decision_threshold = _mgr.progress_decision_threshold;
    array_push(global.enemies, _enemy);
    global.state = "PLAY";
    global.message = "CAMPEON DE PROGRESO CARGADO - FITNESS " + string_format(_mgr.progress_fitness, 0, 1);
    global.message_time = 2;
    return true;
}

function std_manager_count_training_targets() {
    var _mgr = global.evo_manager;
    if (_mgr.human_target_active) return (global.player.hp > 0) ? 1 : 0;
    var _alive = 0;
    for (var i = 0; i < array_length(global.enemies); i++) {
        if (!global.enemies[i].dead && global.enemies[i].type != "RL") _alive += 1;
    }
    return _alive;
}

function std_manager_training_row(_enemy, _winner, _agent_index = -1, _match_index = -1) {
    var _mgr = global.evo_manager;
    if (_agent_index < 0) _agent_index = _mgr.evaluation_agent_index;
    if (_match_index < 0) _match_index = _mgr.evaluation_match_index;
    var _lifespan = max(_enemy.lifespan_time, 0.001);
    var _dps = _enemy.damage_dealt / _lifespan;
    var _success = min(1, _enemy.kills / max(_mgr.total_enemies_snapshot, 1));
    var _episode_seed = _mgr.random_seed + _mgr.generation_count * 100000
        + _mgr.stage_index * 10000 + _match_index;
    var _sensors = "";
    for (var s = 0; s < NN_INPUT_SIZE; s++) _sensors += _mgr.sensor_enabled[s] ? "1" : "0";
    return string(_mgr.generation_count) + "," + _mgr.stage_names[_mgr.stage_index] + ","
        + string(_agent_index) + "," + string(_match_index) + ","
        + string(_episode_seed) + "," + _winner + ","
        + string_format(_lifespan, 0, 3) + "," + string_format(_enemy.damage_dealt, 0, 3) + ","
        + string_format(_enemy.damage_taken, 0, 3) + "," + string_format(_dps, 0, 4) + ","
        + string(_enemy.kills) + "," + string(_enemy.dodges) + "," + string_format(_success, 0, 4) + ","
        + string_format(_enemy.fitness, 0, 3) + "," + string(_mgr.population_size) + ","
        + string_format(_mgr.mutation_rate, 0, 3) + "," + string_format(_mgr.crossover_rate, 0, 3) + ","
        + string_format(_mgr.selection_rate, 0, 3) + "," + _mgr.weight_init_mode + ","
        + string_format(_mgr.weight_init_range, 0, 3) + "," + string_format(_mgr.weight_equal_value, 0, 3) + ","
        + _mgr.selection_method + "," + string(_mgr.tournament_size) + "," + _mgr.mutation_method + ","
        + string_format(_mgr.mutation_sigma, 0, 3) + "," + string_format(_mgr.mutation_range, 0, 3) + ","
        + (_mgr.use_hidden_layers ? "6-8-6" : "6-6") + "," + _mgr.decision_mode + ","
        + string_format(_mgr.decision_threshold, 0, 3) + "," + _sensors + ","
        + (std_manager_parallel_enabled_for_stage() ? "parallel" : "sequential");
}

function std_manager_finish_training_episode(_winner) {
    var _mgr = global.evo_manager;
    if (array_length(_mgr.active_enemies) == 0) return;
    var _enemy = _mgr.active_enemies[0];
    if (_winner == "AGENTE") _enemy.fitness += 30;
    else if (_winner == "OPONENTE") _enemy.fitness -= 15;
    else if (_winner == "TIMEOUT") _enemy.fitness -= 2;

    var _result = _mgr.generation_results[_mgr.evaluation_agent_index];
    _result.fitness_sum += _enemy.fitness;
    _result.lifespan_sum += _enemy.lifespan_time;
    _result.damage_dealt_sum += _enemy.damage_dealt;
    _result.damage_taken_sum += _enemy.damage_taken;
    _result.kills_sum += _enemy.kills;
    _result.dodges_sum += _enemy.dodges;
    if (_winner == "AGENTE") _result.wins += 1;
    else if (_winner == "OPONENTE") _result.losses += 1;
    else if (_winner == "EMPATE") _result.draws += 1;
    else _result.timeouts += 1;
    for (var a = 0; a < NN_OUTPUT_SIZE; a++) _result.action_time[a] += _enemy.action_time[a];

    var _row = std_manager_training_row(_enemy, _winner);
    if (_mgr.training_csv_ready) std_csv_append(STD_AI_TRAINING_FILE, _row);
    show_debug_message("TRAINING_METRICS," + _row);

    _mgr.evaluation_match_index += 1;
    if (_mgr.evaluation_match_index >= _mgr.matches_per_agent) {
        _mgr.evaluation_match_index = 0;
        _mgr.evaluation_agent_index += 1;
    }
    if (_mgr.evaluation_agent_index >= _mgr.population_size) {
        std_manager_next_generation();
    } else {
        std_manager_checkpoint_save();
        std_manager_spawn_training_episode();
    }
}

function std_manager_finish_parallel_pair(_pair_index, _winner) {
    var _mgr = global.evo_manager;
    if (_pair_index < 0 || _pair_index >= _mgr.population_size) return;
    if (_mgr.pair_finished[_pair_index]) return;

    var _enemy = _mgr.active_enemies[_pair_index];
    if (_winner == "AGENTE") _enemy.fitness += 30;
    else if (_winner == "OPONENTE") _enemy.fitness -= 15;
    else if (_winner == "TIMEOUT") _enemy.fitness -= 2;

    var _result = _mgr.generation_results[_pair_index];
    _result.fitness_sum += _enemy.fitness;
    _result.lifespan_sum += _enemy.lifespan_time;
    _result.damage_dealt_sum += _enemy.damage_dealt;
    _result.damage_taken_sum += _enemy.damage_taken;
    _result.kills_sum += _enemy.kills;
    _result.dodges_sum += _enemy.dodges;
    if (_winner == "AGENTE") _result.wins += 1;
    else if (_winner == "OPONENTE") _result.losses += 1;
    else if (_winner == "EMPATE") _result.draws += 1;
    else _result.timeouts += 1;
    for (var a = 0; a < NN_OUTPUT_SIZE; a++) _result.action_time[a] += _enemy.action_time[a];

    var _row = std_manager_training_row(
        _enemy, _winner, _pair_index, _mgr.evaluation_match_index
    );
    if (_mgr.training_csv_ready) std_csv_append(STD_AI_TRAINING_FILE, _row);
    show_debug_message("TRAINING_METRICS," + _row);

    _mgr.pair_finished[_pair_index] = true;
    _mgr.parallel_finished_count += 1;
    // Retire the completed isolated pair so it cannot keep consuming CPU or
    // emitting projectiles while other lanes finish their evaluation.
    _enemy.dead = true;
    _mgr.active_opponents[_pair_index].dead = true;
}

function std_manager_finish_parallel_round(_force_timeout = false) {
    var _mgr = global.evo_manager;
    if (_force_timeout) {
        for (var i = 0; i < _mgr.population_size; i++) {
            if (!_mgr.pair_finished[i]) std_manager_finish_parallel_pair(i, "TIMEOUT");
        }
    }

    _mgr.evaluation_match_index += 1;
    if (_mgr.evaluation_match_index >= _mgr.matches_per_agent) {
        _mgr.evaluation_match_index = 0;
        _mgr.evaluation_agent_index = 0;
        std_manager_next_generation();
    } else {
        std_manager_checkpoint_save();
        std_manager_spawn_population();
    }
}

function std_manager_tick_parallel() {
    var _mgr = global.evo_manager;
    _mgr.generation_timer += global.dt;

    for (var i = 0; i < _mgr.population_size; i++) {
        if (_mgr.pair_finished[i]) continue;
        var _agent = _mgr.active_enemies[i];
        var _opponent = _mgr.active_opponents[i];
        if (!_agent.dead) _agent.lifespan_time += global.dt;

        var _progress_damage = _agent.damage_dealt + _agent.damage_taken;
        if (_progress_damage > _mgr.pair_progress_damage[i] + 0.001) {
            _mgr.pair_progress_damage[i] = _progress_damage;
            _mgr.pair_no_progress_time[i] = 0;
        } else {
            _mgr.pair_no_progress_time[i] += global.dt;
        }

        if (_agent.dead && _opponent.dead) std_manager_finish_parallel_pair(i, "EMPATE");
        else if (_agent.dead) std_manager_finish_parallel_pair(i, "OPONENTE");
        else if (_opponent.dead) std_manager_finish_parallel_pair(i, "AGENTE");
        else if (_mgr.pair_no_progress_time[i] >= STD_AI_STALL_TIMEOUT) {
            std_manager_finish_parallel_pair(i, "TIMEOUT");
        }
    }

    if (_mgr.parallel_finished_count >= _mgr.population_size) {
        std_manager_finish_parallel_round(false);
    } else if (_mgr.generation_timer >= _mgr.generation_timer_limit) {
        std_manager_finish_parallel_round(true);
    }
}

function std_manager_tick() {
    var _mgr = global.evo_manager;
    if (!_mgr.training_active || _mgr.training_paused || array_length(_mgr.active_enemies) == 0) return;
    if (std_manager_parallel_enabled_for_stage()) {
        std_manager_tick_parallel();
        return;
    }
    _mgr.generation_timer += global.dt;
    var _agent = _mgr.active_enemies[0];
    if (!_agent.dead) _agent.lifespan_time += global.dt;
    var _progress_damage = _agent.damage_dealt + _agent.damage_taken;
    if (_progress_damage > _mgr.episode_progress_damage + 0.001) {
        _mgr.episode_progress_damage = _progress_damage;
        _mgr.episode_no_progress_time = 0;
    } else {
        _mgr.episode_no_progress_time += global.dt;
    }
    var _agent_alive = !_agent.dead;
    var _targets_alive = std_manager_count_training_targets();
    if (!_agent_alive && _targets_alive <= 0) std_manager_finish_training_episode("EMPATE");
    else if (!_agent_alive) std_manager_finish_training_episode("OPONENTE");
    else if (_targets_alive <= 0) std_manager_finish_training_episode("AGENTE");
    else if (!_mgr.human_target_active && _mgr.episode_no_progress_time >= STD_AI_STALL_TIMEOUT) {
        std_manager_finish_training_episode("TIMEOUT");
    }
    else if (_mgr.generation_timer >= _mgr.generation_timer_limit) std_manager_finish_training_episode("TIMEOUT");
}

function std_manager_force_end_generation() {
    if (std_manager_parallel_enabled_for_stage()) std_manager_finish_parallel_round(true);
    else std_manager_finish_training_episode("TIMEOUT");
}

function std_manager_collect_fitness() {
    var _mgr = global.evo_manager;
    var _fitness = array_create(_mgr.population_size, 0);
    for (var i = 0; i < _mgr.population_size; i++) {
        _fitness[i] = _mgr.generation_results[i].fitness_sum / max(_mgr.matches_per_agent, 1);
    }
    return _fitness;
}

function std_manager_next_generation() {
    var _mgr = global.evo_manager;
    var _fitness = std_manager_collect_fitness();
    var _best_idx = 0;
    var _sum_lifespan = 0;
    var _wins = 0;
    var _episodes = _mgr.population_size * _mgr.matches_per_agent;
    for (var i = 0; i < _mgr.population_size; i++) {
        if (_fitness[i] > _fitness[_best_idx]) _best_idx = i;
        _sum_lifespan += _mgr.generation_results[i].lifespan_sum;
        _wins += _mgr.generation_results[i].wins;
    }

    var _best_fitness = _fitness[_best_idx];
    var _save_needed = false;

    // Historical numeric record: it is never allowed to decrease, even when
    // the curriculum advances to a harder opponent.
    if (is_undefined(_mgr.best_chromosome_ever) || _best_fitness > _mgr.best_fitness_ever) {
        _mgr.best_fitness_ever = _best_fitness;
        _mgr.best_chromosome_ever = std_ga_copy_chromosome(_mgr.population_pool[_best_idx]);
        _mgr.best_use_hidden_layers = _mgr.use_hidden_layers;
        _mgr.best_sensor_enabled = std_manager_copy_sensors(_mgr.sensor_enabled);
        _mgr.best_decision_mode = _mgr.decision_mode;
        _mgr.best_decision_threshold = _mgr.decision_threshold;
        _mgr.best_generation = _mgr.generation_count;
        _mgr.best_stage_index = _mgr.stage_index;
        _mgr.best_config = std_manager_config_snapshot();
        _save_needed = true;
    }

    // Progress champion: later stages outrank earlier stages. Inside one stage,
    // only a strictly higher fitness may replace it. This is the chromosome
    // used by CONTINUAR, PROBAR and BENCHMARK.
    if (is_undefined(_mgr.progress_chromosome)
        || _mgr.stage_index > _mgr.progress_stage_index
        || (_mgr.stage_index == _mgr.progress_stage_index
            && _best_fitness > _mgr.progress_fitness)) {
        _mgr.progress_fitness = _best_fitness;
        _mgr.progress_chromosome = std_ga_copy_chromosome(_mgr.population_pool[_best_idx]);
        _mgr.progress_use_hidden_layers = _mgr.use_hidden_layers;
        _mgr.progress_sensor_enabled = std_manager_copy_sensors(_mgr.sensor_enabled);
        _mgr.progress_decision_mode = _mgr.decision_mode;
        _mgr.progress_decision_threshold = _mgr.decision_threshold;
        _mgr.progress_generation = _mgr.generation_count;
        _mgr.progress_stage_index = _mgr.stage_index;
        _mgr.progress_config = std_manager_config_snapshot();
        _save_needed = true;
    }
    if (_save_needed) std_manager_save_best();

    var _avg_lifespan = _sum_lifespan / max(_episodes, 1);
    var _win_rate = _wins / max(_episodes, 1);
    array_push(_mgr.logs, {
        gen_number: _mgr.generation_count,
        best_fitness: _best_fitness,
        avg_lifespan: _avg_lifespan,
        win_rate: _win_rate,
        stage: _mgr.stage_names[_mgr.stage_index]
    });
    show_debug_message("TRAINING_GENERATION," + string(_mgr.generation_count) + ","
        + string_format(_best_fitness, 0, 3) + "," + string_format(_avg_lifespan, 0, 3) + ","
        + string_format(_win_rate, 0, 4) + "," + _mgr.stage_names[_mgr.stage_index]);

    var _best_result = _mgr.generation_results[_best_idx];
    var _stage_passed = _best_fitness >= _mgr.fitness_threshold && _best_result.wins > 0;
    if (_stage_passed && _mgr.stage_index < array_length(_mgr.training_stages) - 1) {
        _mgr.stage_index += 1;
    } else if (_stage_passed) {
        _mgr.vs_human = true;
        _mgr.training_active = false;
        _mgr.training_paused = false;
        _mgr.isolated_evaluation = false;
        _mgr.human_target_active = false;
        global.state = "AI_MENU";
        global.ai_menu_message = "ENTRENAMIENTO COMPLETADO - CAMPEON GUARDADO";
        return;
    }

    var _ga_params = {
        selection_method: _mgr.selection_method,
        tournament_size: _mgr.tournament_size,
        selection_rate: _mgr.selection_rate,
        mutation_method: _mgr.mutation_method,
        mutation_rate: _mgr.mutation_rate,
        crossover_rate: _mgr.crossover_rate,
        mutation_range: _mgr.mutation_range,
        mutation_sigma: _mgr.mutation_sigma,
        elitism: true
    };
    _mgr.population_pool = std_ga_evolve_population(_mgr.population_pool, _fitness, _ga_params);
    _mgr.generation_count += 1;
    _mgr.evaluation_agent_index = 0;
    _mgr.evaluation_match_index = 0;
    std_manager_reset_generation_results();
    std_manager_checkpoint_save();
    if (_mgr.generation_count >= _mgr.max_generations) {
        _mgr.training_active = false;
        _mgr.training_paused = false;
        _mgr.isolated_evaluation = false;
        _mgr.human_target_active = false;
        global.state = "AI_MENU";
        global.ai_menu_message = "LIMITE DE " + string(_mgr.max_generations)
            + " GENERACIONES - MEJOR CAMPEON GUARDADO";
        return;
    }
    std_manager_spawn_population();
}

function std_manager_apply_best_to_enemy(_enemy) {
    var _mgr = global.evo_manager;
    if (is_undefined(_mgr.progress_chromosome)) return false;
    _enemy.use_hidden_layers = _mgr.progress_use_hidden_layers;
    if (!std_manager_valid_chromosome(_mgr.progress_chromosome, _enemy.use_hidden_layers)) return false;
    std_nn_unflatten(_enemy, _mgr.progress_chromosome);
    _enemy.sensor_enabled = std_manager_copy_sensors(_mgr.progress_sensor_enabled);
    _enemy.decision_mode = _mgr.progress_decision_mode;
    _enemy.decision_threshold = _mgr.progress_decision_threshold;
    return true;
}

// -----------------------------------------------------------------------------
// Reproducible benchmark runner
// -----------------------------------------------------------------------------

function std_benchmark_init() {
    global.benchmark = {
        scenarios: [
            { id: 1, name: "1 A vs 1 agente", level: 4, types: ["A"], opponents: 1, agents: 1, human: false },
            { id: 2, name: "1 B vs 1 agente", level: 4, types: ["B"], opponents: 1, agents: 1, human: false },
            { id: 3, name: "1 C vs 1 agente", level: 4, types: ["C"], opponents: 1, agents: 1, human: false },
            { id: 4, name: "Humano vs 1 agente", level: 4, types: [], opponents: 1, agents: 1, human: true },
            { id: 5, name: "3 A vs 1 agente", level: 4, types: ["A"], opponents: 3, agents: 1, human: false },
            { id: 6, name: "3 B vs 1 agente", level: 4, types: ["B"], opponents: 3, agents: 1, human: false },
            { id: 7, name: "3 C vs 1 agente", level: 4, types: ["C"], opponents: 3, agents: 1, human: false },
            { id: 8, name: "6 A-B-C vs 1 agente", level: 4, types: ["A", "B", "C"], opponents: 6, agents: 1, human: false },
            { id: 9, name: "6 A-B-C vs 3 agentes", level: 4, types: ["A", "B", "C"], opponents: 6, agents: 3, human: false },
            { id: 10, name: "Humano vs 3 agentes", level: 4, types: [], opponents: 1, agents: 3, human: true }
        ],
        selected_scenario: 0,
        repetitions: 20,
        timeout: 60,
        seed: 1337,
        active: false,
        paused: false,
        run_all: true,
        scenario_cursor: 0,
        final_scenario: 9,
        repetition_index: 0,
        episode_time: 0,
        episode_agents: [],
        episode_opponents: [],
        human_target_active: false,
        results: [],
        frozen_chromosome: undefined,
        frozen_hidden: true,
        frozen_sensors: [true, true, true, true, true, true],
        frozen_decision_mode: "argmax",
        frozen_threshold: 0.22,
        frozen_config: undefined,
        message: "",
        hover: ""
    };
}

function std_benchmark_action_name(_index) {
    var _names = ["ESCAPAR", "PERSEGUIR", "MELEE", "DISTANCIA", "SANAR", "DEFENDER"];
    if (_index < 0 || _index >= array_length(_names)) return "NINGUNA";
    return _names[_index];
}

function std_benchmark_dominant_action(_times) {
    var _best = 0;
    for (var i = 1; i < array_length(_times); i++) {
        if (_times[i] > _times[_best]) _best = i;
    }
    return std_benchmark_action_name(_best);
}

function std_benchmark_sensor_code() {
    var _mgr = global.evo_manager;
    var _code = "";
    for (var i = 0; i < NN_INPUT_SIZE; i++) _code += _mgr.sensor_enabled[i] ? "1" : "0";
    return _code;
}

function std_benchmark_prepare_csv() {
    var _header = "scenario_id,scenario,repetition,episode_seed,winner,episode_time,avg_lifespan,total_agent_life,damage_dealt,damage_taken,dps,kills,target_count,success_rate,agent_count,opponent_count,agent_deaths,opponent_deaths,potions_used,action_escape,action_chase,action_melee,action_ranged,action_heal,action_defend,dominant_action,population,mutation_rate,crossover_rate,selection_rate,weight_init,weight_range,equal_weight,selection_method,tournament_size,mutation_method,mutation_sigma,uniform_range,architecture,decision_mode,threshold,sensors,training_seed,matches_per_agent";
    return std_csv_write_new(STD_AI_BENCHMARK_FILE, _header);
}

function std_benchmark_spawn_episode() {
    var _bench = global.benchmark;
    var _scenario = _bench.scenarios[_bench.scenario_cursor];
    var _episode_seed = _bench.seed + _scenario.id * 10000 + _bench.repetition_index;
    random_set_seed(_episode_seed);
    std_load_level(_scenario.level);
    std_manager_clear_enemies();
    _bench.episode_agents = [];
    _bench.episode_opponents = [];
    _bench.episode_time = 0;
    _bench.human_target_active = _scenario.human;

    var _used = [];
    if (!_scenario.human) {
        for (var o = 0; o < _scenario.opponents; o++) {
            var _row_offset = (o mod 3) - 1;
            var _col_offset = floor(o / 3);
            var _op_cell = std_manager_find_free_cell(
                floor(global.level.cols * 0.72) + _col_offset,
                floor(global.level.rows * 0.50) + _row_offset * 2,
                _used
            );
            array_push(_used, [_op_cell.x, _op_cell.y]);
            var _type = _scenario.types[o mod array_length(_scenario.types)];
            var _opponent = std_make_enemy(_type, _op_cell.x, _op_cell.y);
            array_push(_bench.episode_opponents, _opponent);
            array_push(global.enemies, _opponent);
        }
    }

    for (var a = 0; a < _scenario.agents; a++) {
        var _agent_cell = std_manager_find_free_cell(
            floor(global.level.cols * 0.28),
            floor(global.level.rows * 0.50) + (a - floor(_scenario.agents / 2)) * 2,
            _used
        );
        array_push(_used, [_agent_cell.x, _agent_cell.y]);
        var _agent = std_make_enemy("RL", _agent_cell.x, _agent_cell.y);
        _agent.use_hidden_layers = _bench.frozen_hidden;
        std_ai_init_agent(_agent);
        _agent.lifespan_time = 0;
        std_nn_unflatten(_agent, _bench.frozen_chromosome);
        array_push(_bench.episode_agents, _agent);
        array_push(global.enemies, _agent);
    }

    global.state = "BENCHMARK";
    global.level_banner = 0.35;
    global.message = "ESCENARIO " + string(_scenario.id) + " - REPETICION "
        + string(_bench.repetition_index + 1) + "/" + string(_bench.repetitions);
    global.message_time = 1.0;
}

function std_benchmark_start(_run_all) {
    var _mgr = global.evo_manager;
    var _bench = global.benchmark;
    if (is_undefined(_mgr.progress_chromosome)) {
        _bench.message = "ENTRENA O CARGA UN MEJOR AGENTE ANTES DEL BENCHMARK";
        return false;
    }
    if (!std_manager_valid_chromosome(_mgr.progress_chromosome, _mgr.progress_use_hidden_layers)
        || !std_manager_valid_sensors(_mgr.progress_sensor_enabled)) {
        _bench.message = "EL MEJOR AGENTE ES INCOMPATIBLE O ESTA DANADO";
        return false;
    }
    _mgr.training_active = false;
    _mgr.training_paused = false;
    _mgr.isolated_evaluation = false;
    _mgr.sensor_enabled = std_manager_copy_sensors(_mgr.progress_sensor_enabled);
    _mgr.decision_mode = _mgr.progress_decision_mode;
    _mgr.decision_threshold = _mgr.progress_decision_threshold;
    _bench.frozen_chromosome = std_ga_copy_chromosome(_mgr.progress_chromosome);
    _bench.frozen_hidden = _mgr.progress_use_hidden_layers;
    _bench.frozen_sensors = std_manager_copy_sensors(_mgr.progress_sensor_enabled);
    _bench.frozen_decision_mode = _mgr.progress_decision_mode;
    _bench.frozen_threshold = _mgr.progress_decision_threshold;
    _bench.frozen_config = is_undefined(_mgr.progress_config)
        ? std_manager_config_snapshot() : _mgr.progress_config;
    _bench.run_all = _run_all;
    global.ai_menu_return_state = "MENU";
    _bench.scenario_cursor = _run_all ? 0 : _bench.selected_scenario;
    _bench.final_scenario = _run_all ? array_length(_bench.scenarios) - 1 : _bench.selected_scenario;
    _bench.repetition_index = 0;
    _bench.results = [];
    _bench.active = true;
    _bench.paused = false;
    _bench.message = "";
    if (!std_benchmark_prepare_csv()) {
        _bench.active = false;
        _bench.message = "NO SE PUDO CREAR EL CSV DE RESULTADOS";
        return false;
    }
    std_benchmark_spawn_episode();
    return true;
}

function std_benchmark_count_alive(_entities) {
    var _alive = 0;
    for (var i = 0; i < array_length(_entities); i++) {
        if (!_entities[i].dead) _alive += 1;
    }
    return _alive;
}

function std_benchmark_episode_row(_winner) {
    var _bench = global.benchmark;
    var _mgr = global.evo_manager;
    var _scenario = _bench.scenarios[_bench.scenario_cursor];
    var _config = _bench.frozen_config;
    var _life_total = 0;
    var _damage_dealt = 0;
    var _damage_taken = 0;
    var _kills = 0;
    var _potions = 0;
    var _action_time = array_create(NN_OUTPUT_SIZE, 0);
    for (var i = 0; i < array_length(_bench.episode_agents); i++) {
        var _agent = _bench.episode_agents[i];
        _life_total += _agent.lifespan_time;
        _damage_dealt += _agent.damage_dealt;
        _damage_taken += _agent.damage_taken;
        _kills += _agent.kills;
        _potions += _agent.potions_used;
        for (var a = 0; a < NN_OUTPUT_SIZE; a++) _action_time[a] += _agent.action_time[a];
    }
    var _avg_life = _life_total / max(array_length(_bench.episode_agents), 1);
    var _dps = _damage_dealt / max(_bench.episode_time, 0.001);
    var _success = min(1, _kills / max(_scenario.opponents, 1));
    var _agent_deaths = array_length(_bench.episode_agents) - std_benchmark_count_alive(_bench.episode_agents);
    var _opponent_alive = _scenario.human ? ((global.player.hp > 0) ? 1 : 0)
        : std_benchmark_count_alive(_bench.episode_opponents);
    var _opponent_deaths = _scenario.opponents - _opponent_alive;
    var _episode_seed = _bench.seed + _scenario.id * 10000 + _bench.repetition_index;
    var _row = string(_scenario.id) + "," + _scenario.name + "," + string(_bench.repetition_index) + ","
        + string(_episode_seed) + "," + _winner + "," + string_format(_bench.episode_time, 0, 3) + ","
        + string_format(_avg_life, 0, 3) + "," + string_format(_life_total, 0, 3) + ","
        + string_format(_damage_dealt, 0, 3) + "," + string_format(_damage_taken, 0, 3) + ","
        + string_format(_dps, 0, 4) + "," + string(_kills) + "," + string(_scenario.opponents) + ","
        + string_format(_success, 0, 4) + "," + string(_scenario.agents) + ","
        + string(_scenario.opponents) + "," + string(_agent_deaths) + "," + string(_opponent_deaths) + ","
        + string(_potions);
    for (var t = 0; t < NN_OUTPUT_SIZE; t++) _row += "," + string_format(_action_time[t], 0, 3);
    _row += "," + std_benchmark_dominant_action(_action_time) + "," + string(_config.population_size) + ","
        + string_format(_config.mutation_rate, 0, 3) + "," + string_format(_config.crossover_rate, 0, 3) + ","
        + string_format(_config.selection_rate, 0, 3) + "," + _config.weight_init_mode + ","
        + string_format(_config.weight_init_range, 0, 3) + "," + string_format(_config.weight_equal_value, 0, 3) + ","
        + _config.selection_method + "," + string(_config.tournament_size) + "," + _config.mutation_method + ","
        + string_format(_config.mutation_sigma, 0, 3) + "," + string_format(_config.mutation_range, 0, 3) + ","
        + (_bench.frozen_hidden ? "6-8-6" : "6-6") + "," + _bench.frozen_decision_mode + ","
        + string_format(_bench.frozen_threshold, 0, 3) + "," + std_benchmark_sensor_code() + ","
        + string(_config.random_seed) + "," + string(_config.matches_per_agent);

    array_push(_bench.results, {
        scenario_index: _bench.scenario_cursor, winner: _winner, episode_time: _bench.episode_time,
        avg_lifespan: _avg_life, dps: _dps, success_rate: _success, action_time: _action_time
    });
    return _row;
}

function std_benchmark_finish_episode(_winner) {
    var _bench = global.benchmark;
    var _row = std_benchmark_episode_row(_winner);
    std_csv_append(STD_AI_BENCHMARK_FILE, _row);
    show_debug_message("BENCHMARK_METRICS," + _row);
    _bench.repetition_index += 1;
    if (_bench.repetition_index >= _bench.repetitions) {
        _bench.repetition_index = 0;
        _bench.scenario_cursor += 1;
    }
    if (_bench.scenario_cursor > _bench.final_scenario) {
        std_benchmark_complete();
    } else {
        std_benchmark_spawn_episode();
    }
}

function std_benchmark_tick() {
    var _bench = global.benchmark;
    if (!_bench.active || _bench.paused) return;
    _bench.episode_time += global.dt;
    for (var i = 0; i < array_length(_bench.episode_agents); i++) {
        if (!_bench.episode_agents[i].dead) _bench.episode_agents[i].lifespan_time += global.dt;
    }
    var _agents_alive = std_benchmark_count_alive(_bench.episode_agents);
    var _opponents_alive = _bench.human_target_active ? ((global.player.hp > 0) ? 1 : 0)
        : std_benchmark_count_alive(_bench.episode_opponents);
    if (_agents_alive <= 0 && _opponents_alive <= 0) std_benchmark_finish_episode("EMPATE");
    else if (_agents_alive <= 0) std_benchmark_finish_episode("OPONENTE");
    else if (_opponents_alive <= 0) std_benchmark_finish_episode("AGENTE");
    else if (_bench.episode_time >= _bench.timeout) std_benchmark_finish_episode("TIMEOUT");
}

function std_benchmark_mean(_values) {
    if (array_length(_values) <= 0) return 0;
    var _sum = 0;
    for (var i = 0; i < array_length(_values); i++) _sum += _values[i];
    return _sum / array_length(_values);
}

function std_benchmark_stddev(_values, _mean) {
    if (array_length(_values) <= 1) return 0;
    var _sum = 0;
    for (var i = 0; i < array_length(_values); i++) {
        var _delta = _values[i] - _mean;
        _sum += _delta * _delta;
    }
    return sqrt(_sum / (array_length(_values) - 1));
}

function std_benchmark_write_summary() {
    var _bench = global.benchmark;
    std_csv_write_new(STD_AI_BENCHMARK_SUMMARY_FILE,
        "scenario_id,scenario,runs,agent_wins,opponent_wins,draws,timeouts,agent_win_rate,mean_lifespan,std_lifespan,mean_dps,std_dps,mean_success_rate,std_success_rate,dominant_action");
    for (var s = 0; s < array_length(_bench.scenarios); s++) {
        var _life = [];
        var _dps = [];
        var _success = [];
        var _actions = array_create(NN_OUTPUT_SIZE, 0);
        var _agent_wins = 0;
        var _opponent_wins = 0;
        var _draws = 0;
        var _timeouts = 0;
        for (var r = 0; r < array_length(_bench.results); r++) {
            var _result = _bench.results[r];
            if (_result.scenario_index != s) continue;
            array_push(_life, _result.avg_lifespan);
            array_push(_dps, _result.dps);
            array_push(_success, _result.success_rate);
            if (_result.winner == "AGENTE") _agent_wins += 1;
            else if (_result.winner == "OPONENTE") _opponent_wins += 1;
            else if (_result.winner == "EMPATE") _draws += 1;
            else _timeouts += 1;
            for (var a = 0; a < NN_OUTPUT_SIZE; a++) _actions[a] += _result.action_time[a];
        }
        var _runs = array_length(_life);
        if (_runs <= 0) continue;
        var _mean_life = std_benchmark_mean(_life);
        var _mean_dps = std_benchmark_mean(_dps);
        var _mean_success = std_benchmark_mean(_success);
        var _scenario = _bench.scenarios[s];
        var _row = string(_scenario.id) + "," + _scenario.name + "," + string(_runs) + ","
            + string(_agent_wins) + "," + string(_opponent_wins) + "," + string(_draws) + ","
            + string(_timeouts) + "," + string_format(_agent_wins / max(_runs, 1), 0, 4) + ","
            + string_format(_mean_life, 0, 4) + "," + string_format(std_benchmark_stddev(_life, _mean_life), 0, 4) + ","
            + string_format(_mean_dps, 0, 4) + "," + string_format(std_benchmark_stddev(_dps, _mean_dps), 0, 4) + ","
            + string_format(_mean_success, 0, 4) + "," + string_format(std_benchmark_stddev(_success, _mean_success), 0, 4) + ","
            + std_benchmark_dominant_action(_actions);
        std_csv_append(STD_AI_BENCHMARK_SUMMARY_FILE, _row);
    }
}

function std_benchmark_complete() {
    var _bench = global.benchmark;
    _bench.active = false;
    _bench.paused = false;
    std_benchmark_write_summary();
    _bench.message = "BENCHMARK COMPLETADO - CSV DETALLADO Y RESUMEN CREADOS";
    global.state = "BENCH_MENU";
}

function std_benchmark_abort() {
    global.benchmark.active = false;
    global.benchmark.paused = false;
    if (array_length(global.benchmark.results) > 0) std_benchmark_write_summary();
    global.benchmark.message = "BENCHMARK DETENIDO; LOS EPISODIOS COMPLETOS QUEDARON EN EL CSV";
    global.state = "BENCH_MENU";
}

function std_benchmark_clear_files() {
    if (file_exists(STD_AI_BENCHMARK_FILE)) file_delete(STD_AI_BENCHMARK_FILE);
    if (file_exists(STD_AI_BENCHMARK_SUMMARY_FILE)) file_delete(STD_AI_BENCHMARK_SUMMARY_FILE);
    global.benchmark.results = [];
    global.benchmark.message = "RESULTADOS ANTERIORES ELIMINADOS";
}

function std_benchmark_menu_open() {
    global.benchmark.hover = "";
    global.benchmark.message = "";
    global.state = "BENCH_MENU";
}

function std_benchmark_menu_controls() {
    var _controls = [];
    for (var s = 0; s < 10; s++) {
        array_push(_controls, { id: "scenario" + string(s), kind: "scenario", rect: [42, 128 + s * 43, 650, 165 + s * 43] });
    }
    var _ids = ["repetitions", "timeout", "seed", "selection_rate", "uniform_range"];
    for (var i = 0; i < array_length(_ids); i++) {
        array_push(_controls, { id: _ids[i], kind: "number", rect: [720, 138 + i * 48, 956, 176 + i * 48] });
    }
    array_push(_controls, { id: "back", kind: "action", rect: [42, 628, 190, 682] });
    array_push(_controls, { id: "clear", kind: "action", rect: [206, 628, 386, 682] });
    array_push(_controls, { id: "run_selected", kind: "action", rect: [700, 614, 946, 682] });
    array_push(_controls, { id: "run_all", kind: "action", rect: [966, 614, 1238, 682] });
    return _controls;
}

function std_benchmark_menu_value(_id) {
    var _bench = global.benchmark;
    var _mgr = global.evo_manager;
    switch (_id) {
        case "repetitions": return string(_bench.repetitions);
        case "timeout": return string(_bench.timeout) + " s";
        case "seed": return string(_bench.seed);
        case "selection_rate": return string_format(_mgr.selection_rate, 0, 2);
        case "uniform_range": return string_format(_mgr.mutation_range, 0, 2);
    }
    return "";
}

function std_benchmark_menu_adjust(_id, _direction) {
    var _bench = global.benchmark;
    var _mgr = global.evo_manager;
    switch (_id) {
        case "repetitions": _bench.repetitions = clamp(_bench.repetitions + _direction, 1, 50); break;
        case "timeout": _bench.timeout = clamp(_bench.timeout + _direction * 5, 15, 180); break;
        case "seed":
            _bench.seed = max(1, _bench.seed + _direction);
            _mgr.random_seed = _bench.seed;
        break;
        case "selection_rate": _mgr.selection_rate = clamp(_mgr.selection_rate + _direction * 0.05, 0.10, 1); break;
        case "uniform_range": _mgr.mutation_range = clamp(_mgr.mutation_range + _direction * 0.25, 0.25, 5); break;
    }
}

function std_benchmark_menu_step() {
    var _mx = device_mouse_x_to_gui(0);
    var _my = device_mouse_y_to_gui(0);
    var _controls = std_benchmark_menu_controls();
    global.benchmark.hover = "";
    var _kind = "";
    var _zone = "";
    for (var i = 0; i < array_length(_controls); i++) {
        var _c = _controls[i];
        var _r = _c.rect;
        if (point_in_rectangle(_mx, _my, _r[0], _r[1], _r[2], _r[3])) {
            global.benchmark.hover = _c.id;
            _kind = _c.kind;
            if (_kind == "number") {
                if (_mx < _r[0] + 42) _zone = "minus";
                else if (_mx > _r[2] - 42) _zone = "plus";
            }
        }
    }
    if (keyboard_check_pressed(vk_escape)) {
        global.state = "AI_MENU";
        return;
    }
    if (mouse_check_button_pressed(mb_left) && global.benchmark.hover != "") {
        var _id = global.benchmark.hover;
        if (_kind == "scenario") {
            global.benchmark.selected_scenario = real(string_delete(_id, 1, 8));
        } else if (_kind == "number") {
            if (_zone == "minus") std_benchmark_menu_adjust(_id, -1);
            else if (_zone == "plus") std_benchmark_menu_adjust(_id, 1);
        } else if (_kind == "enum") {
            std_benchmark_menu_adjust(_id, 1);
        } else if (_kind == "action") {
            if (_id == "back") global.state = "AI_MENU";
            else if (_id == "clear") std_benchmark_clear_files();
            else if (_id == "run_selected") std_benchmark_start(false);
            else if (_id == "run_all") std_benchmark_start(true);
        }
    }
}

function std_draw_benchmark_menu() {
    var _bench = global.benchmark;
    var _mgr = global.evo_manager;
    draw_clear(make_color_rgb(4, 8, 16));
    draw_set_alpha(0.14);
    draw_set_color(make_color_rgb(66, 205, 233));
    for (var gx = 0; gx <= 1280; gx += 40) draw_line(gx, 0, gx, 720);
    for (var gy = 0; gy <= 720; gy += 40) draw_line(0, gy, 1280, gy);
    draw_set_alpha(1);
    draw_set_halign(fa_left);
    draw_set_color(make_color_rgb(76, 226, 245));
    draw_text_transformed(42, 28, "CENTRO DE BENCHMARK", 1.65, 1.65, 0);
    draw_set_color(make_color_rgb(145, 171, 192));
    draw_text(44, 78, "10 ESCENARIOS CONTROLADOS  //  PESOS CONGELADOS  //  CSV REPRODUCIBLE");

    draw_set_color(make_color_rgb(7, 18, 31));
    draw_roundrect(28, 108, 668, 600, false);
    draw_roundrect(688, 108, 1252, 600, false);
    draw_set_color(make_color_rgb(45, 82, 104));
    draw_roundrect(28, 108, 668, 600, true);
    draw_roundrect(688, 108, 1252, 600, true);
    draw_set_color(make_color_rgb(139, 166, 187));
    draw_text(710, 116, "EJECUCION Y COMPARACION");

    for (var s = 0; s < array_length(_bench.scenarios); s++) {
        var _y = 128 + s * 43;
        var _selected = s == _bench.selected_scenario;
        var _hover = _bench.hover == "scenario" + string(s);
        draw_set_color((_selected || _hover) ? make_color_rgb(20, 78, 98) : make_color_rgb(11, 29, 43));
        draw_roundrect(42, _y, 650, _y + 37, false);
        draw_set_color(_selected ? make_color_rgb(244, 205, 105) : make_color_rgb(202, 218, 230));
        draw_text(58, _y + 10, string(_bench.scenarios[s].id) + ".  " + _bench.scenarios[s].name);
    }

    var _labels = ["REPETICIONES", "TIMEOUT", "SEMILLA", "TASA SELECCION", "RANGO MUT. UNIFORME"];
    var _ids = ["repetitions", "timeout", "seed", "selection_rate", "uniform_range"];
    for (var i = 0; i < array_length(_ids); i++) {
        var _y2 = 138 + i * 48;
        var _hover2 = _bench.hover == _ids[i];
        draw_set_color(_hover2 ? make_color_rgb(26, 91, 111) : make_color_rgb(12, 35, 51));
        draw_roundrect(720, _y2, 956, _y2 + 38, false);
        draw_set_color(make_color_rgb(63, 104, 128));
        draw_line(762, _y2, 762, _y2 + 38);
        draw_line(914, _y2, 914, _y2 + 38);
        draw_set_halign(fa_center);
        draw_set_color(c_white);
        draw_text(741, _y2 + 11, "-");
        draw_text(935, _y2 + 11, "+");
        draw_set_color(make_color_rgb(245, 204, 103));
        draw_text(838, _y2 + 11, std_benchmark_menu_value(_ids[i]));
        draw_set_halign(fa_left);
        draw_set_color(make_color_rgb(193, 213, 228));
        draw_text(974, _y2 + 11, _labels[i]);
    }
    draw_set_color(make_color_rgb(132, 158, 178));
    draw_text(710, 426, "Entrenamiento: 1 ronda fija por generacion.");
    draw_text(710, 456, "Los pesos iniciales se configuran antes de entrenar");
    draw_text(710, 478, "en CONFIGURAR IA. El benchmark usa el campeon congelado.");
    draw_text(710, 512, "La arquitectura principal es 6 > 8 > 6.");

    var _actions = ["back", "clear", "run_selected", "run_all"];
    var _action_labels = ["VOLVER", "BORRAR CSV", "EJECUTAR SELECCIONADO", "EJECUTAR LOS 10"];
    var _controls = std_benchmark_menu_controls();
    for (var b = 0; b < array_length(_actions); b++) {
        for (var c = 0; c < array_length(_controls); c++) {
            if (_controls[c].id != _actions[b]) continue;
            var _r = _controls[c].rect;
            var _hover3 = _bench.hover == _actions[b];
            draw_set_color(_hover3 ? make_color_rgb(68, 220, 237) : make_color_rgb(17, 58, 76));
            draw_roundrect(_r[0], _r[1], _r[2], _r[3], false);
            draw_set_halign(fa_center);
            draw_set_color(_hover3 ? make_color_rgb(4, 15, 23) : c_white);
            draw_text((_r[0] + _r[2]) * 0.5, _r[1] + 19, _action_labels[b]);
        }
    }
    draw_set_halign(fa_left);
    if (_bench.message != "") {
        draw_set_color(make_color_rgb(255, 132, 148));
        draw_text(414, 96, _bench.message);
    }
    draw_set_color(is_undefined(_mgr.progress_chromosome) ? make_color_rgb(255, 116, 132) : make_color_rgb(78, 255, 176));
    draw_text(710, 596, is_undefined(_mgr.progress_chromosome)
        ? "SIN CAMPEON DE PROGRESO GUARDADO"
        : "CAMPEON CONGELABLE: ETAPA " + string(_mgr.progress_stage_index + 1)
            + " / FITNESS " + string_format(_mgr.progress_fitness, 0, 2));
    draw_set_alpha(1);
    draw_set_halign(fa_left);
}

// -----------------------------------------------------------------------------
// AI configuration menu
// -----------------------------------------------------------------------------

function std_ai_menu_open(_return_state) {
    global.ai_menu_return_state = _return_state;
    global.ai_menu_hover = "";
    global.ai_menu_message = "";
    global.state = "AI_MENU";
}

function std_ai_menu_controls() {
    var _controls = [];
    var _ids = ["population", "mutation", "crossover", "sigma", "duration", "threshold", "tournament", "fitness", "max_generations"];
    var _labels = ["POBLACION", "PROB. MUTACION", "PROB. CRUCE", "RUIDO GAUSSIANO", "DURACION COMBATE", "UMBRAL DECISION", "TAMANO TORNEO", "META FITNESS", "MAX. GENERACIONES"];
    for (var i = 0; i < array_length(_ids); i++) {
        var _y = 140 + i * 28;
        array_push(_controls, { id: _ids[i], kind: "number", rect: [825, _y, 1045, _y + 24], label: _labels[i] });
    }
    array_push(_controls, { id: "weight_init", kind: "enum", rect: [825, 398, 1045, 422], label: "PESOS INICIALES" });
    array_push(_controls, { id: "init_range", kind: "number", rect: [825, 426, 1045, 450], label: "RANGO PESOS" });
    array_push(_controls, { id: "equal_weight", kind: "number", rect: [825, 454, 1045, 478], label: "PESO IGUAL" });
    array_push(_controls, { id: "architecture", kind: "enum", rect: [825, 482, 1045, 506], label: "ARQUITECTURA" });
    array_push(_controls, { id: "decision", kind: "enum", rect: [825, 510, 1045, 534], label: "DECISION" });
    array_push(_controls, { id: "selection", kind: "enum", rect: [825, 538, 1045, 562], label: "SELECCION" });
    array_push(_controls, { id: "mutation_type", kind: "enum", rect: [825, 566, 1045, 590], label: "MUTACION" });
    array_push(_controls, { id: "training_mode", kind: "enum", rect: [825, 594, 1045, 618], label: "MODO ENTRENO" });

    var _sensor_y = [164, 232, 300, 368, 436, 504];
    for (var s = 0; s < NN_INPUT_SIZE; s++) {
        array_push(_controls, { id: "sensor" + string(s), kind: "sensor", rect: [54, _sensor_y[s] - 18, 250, _sensor_y[s] + 22], label: "" });
    }

    array_push(_controls, { id: "back", kind: "action", rect: [54, 650, 154, 696], label: "VOLVER" });
    array_push(_controls, { id: "defaults", kind: "action", rect: [164, 650, 284, 696], label: "REINICIAR" });
    array_push(_controls, { id: "test", kind: "action", rect: [294, 650, 414, 696], label: "PROBAR" });
    array_push(_controls, { id: "benchmark", kind: "action", rect: [424, 650, 544, 696], label: "BENCHMARK" });
    array_push(_controls, { id: "continue", kind: "action", rect: [554, 650, 674, 696], label: "CONTINUAR" });
    array_push(_controls, { id: "train", kind: "action", rect: [684, 650, 790, 696], label: "ENTRENAR" });
    return _controls;
}

function std_ai_menu_value(_id) {
    var _mgr = global.evo_manager;
    switch (_id) {
        case "population": return string(_mgr.population_size);
        case "mutation": return string_format(_mgr.mutation_rate, 0, 2);
        case "crossover": return string_format(_mgr.crossover_rate, 0, 2);
        case "sigma": return string_format(_mgr.mutation_sigma, 0, 2);
        case "duration": return string(_mgr.generation_timer_limit) + " s";
        case "threshold": return string_format(_mgr.decision_threshold, 0, 2);
        case "tournament": return string(_mgr.tournament_size);
        case "fitness": return string(_mgr.fitness_threshold);
        case "max_generations": return string(_mgr.max_generations);
        case "weight_init": return string_upper(_mgr.weight_init_mode);
        case "init_range": return string_format(_mgr.weight_init_range, 0, 2);
        case "equal_weight": return string_format(_mgr.weight_equal_value, 0, 2);
        case "architecture": return _mgr.use_hidden_layers ? "6 > 8 > 6" : "6 > 6";
        case "decision": return (_mgr.decision_mode == "argmax") ? "ARGMAX" : "UMBRAL";
        case "selection": return (_mgr.selection_method == "tournament") ? "TORNEO" : "RULETA";
        case "mutation_type": return (_mgr.mutation_method == "gaussian") ? "GAUSSIANA" : "UNIFORME";
        case "training_mode": return (_mgr.training_mode == "parallel") ? "SIMULTANEO" : "SECUENCIAL";
    }
    return "";
}

function std_ai_menu_adjust(_id, _direction) {
    var _mgr = global.evo_manager;
    if (_mgr.training_active) {
        global.ai_menu_message = "DETEN EL ENTRENAMIENTO PARA CAMBIAR LA CONFIGURACION";
        return;
    }
    switch (_id) {
        case "population": _mgr.population_size = clamp(_mgr.population_size + _direction, 2, 24); break;
        case "mutation": _mgr.mutation_rate = clamp(_mgr.mutation_rate + _direction * 0.01, 0, 0.50); break;
        case "crossover": _mgr.crossover_rate = clamp(_mgr.crossover_rate + _direction * 0.05, 0, 1); break;
        case "sigma": _mgr.mutation_sigma = clamp(_mgr.mutation_sigma + _direction * 0.05, 0.05, 1); break;
        case "duration": _mgr.generation_timer_limit = clamp(_mgr.generation_timer_limit + _direction * 5, 15, 180); break;
        case "threshold": _mgr.decision_threshold = clamp(_mgr.decision_threshold + _direction * 0.05, 0.10, 0.95); break;
        case "tournament": _mgr.tournament_size = clamp(_mgr.tournament_size + _direction, 2, 8); break;
        case "fitness": _mgr.fitness_threshold = clamp(_mgr.fitness_threshold + _direction * 5, 10, 300); break;
        case "max_generations": _mgr.max_generations = clamp(_mgr.max_generations + _direction * 10, 1, 1000); break;
        case "weight_init":
            if (_mgr.weight_init_mode == "random") _mgr.weight_init_mode = "equal";
            else if (_mgr.weight_init_mode == "equal") _mgr.weight_init_mode = "zero";
            else _mgr.weight_init_mode = "random";
            _mgr.population_pool = [];
        break;
        case "init_range":
            _mgr.weight_init_range = clamp(_mgr.weight_init_range + _direction * 0.25, 0.25, 5);
            _mgr.population_pool = [];
        break;
        case "equal_weight":
            _mgr.weight_equal_value = clamp(_mgr.weight_equal_value + _direction * 0.05, -2, 2);
            _mgr.population_pool = [];
        break;
        case "architecture": std_manager_set_hidden_layers(!_mgr.use_hidden_layers); break;
        case "decision": _mgr.decision_mode = (_mgr.decision_mode == "argmax") ? "threshold" : "argmax"; break;
        case "selection": _mgr.selection_method = (_mgr.selection_method == "tournament") ? "roulette" : "tournament"; break;
        case "mutation_type": _mgr.mutation_method = (_mgr.mutation_method == "gaussian") ? "uniform" : "gaussian"; break;
        case "training_mode":
            if (_mgr.training_active) {
                global.ai_menu_message = "DETEN EL ENTRENAMIENTO PARA CAMBIAR EL MODO";
            } else {
                _mgr.training_mode = (_mgr.training_mode == "parallel") ? "sequential" : "parallel";
            }
        break;
    }
}

function std_ai_menu_raw_number(_id) {
    var _mgr = global.evo_manager;
    switch (_id) {
        case "population": return _mgr.population_size;
        case "mutation": return _mgr.mutation_rate;
        case "crossover": return _mgr.crossover_rate;
        case "sigma": return _mgr.mutation_sigma;
        case "duration": return _mgr.generation_timer_limit;
        case "threshold": return _mgr.decision_threshold;
        case "tournament": return _mgr.tournament_size;
        case "fitness": return _mgr.fitness_threshold;
        case "max_generations": return _mgr.max_generations;
        case "init_range": return _mgr.weight_init_range;
        case "equal_weight": return _mgr.weight_equal_value;
    }
    return 0;
}

function std_ai_menu_numeric_text_valid(_text) {
    if (!is_string(_text) || string_length(_text) <= 0) return false;
    var _digits = 0;
    var _dots = 0;
    for (var i = 1; i <= string_length(_text); i++) {
        var _ch = string_char_at(_text, i);
        if (string_pos(_ch, "0123456789") > 0) _digits += 1;
        else if (_ch == ".") {
            _dots += 1;
            if (_dots > 1) return false;
        } else if (_ch == "-" && i == 1) {
            // Negative values are useful for PESO IGUAL.
        } else return false;
    }
    return _digits > 0;
}

function std_ai_menu_edit_number(_id) {
    var _mgr = global.evo_manager;
    if (_mgr.training_active) {
        global.ai_menu_message = "DETEN EL ENTRENAMIENTO PARA CAMBIAR LA CONFIGURACION";
        return;
    }
    var _entered = get_string("ESCRIBE EL NUEVO VALOR", string(std_ai_menu_raw_number(_id)));
    if (!is_string(_entered) || string_length(_entered) <= 0) return;
    _entered = string_replace_all(_entered, ",", ".");
    if (!std_ai_menu_numeric_text_valid(_entered)) {
        global.ai_menu_message = "VALOR NUMERICO INVALIDO";
        return;
    }
    var _value = real(_entered);
    switch (_id) {
        case "population":
            _mgr.population_size = clamp(round(_value), 2, 24);
            _mgr.population_pool = [];
        break;
        case "mutation": _mgr.mutation_rate = clamp(_value, 0, 0.50); break;
        case "crossover": _mgr.crossover_rate = clamp(_value, 0, 1); break;
        case "sigma": _mgr.mutation_sigma = clamp(_value, 0.05, 1); break;
        case "duration": _mgr.generation_timer_limit = clamp(round(_value), 15, 180); break;
        case "threshold": _mgr.decision_threshold = clamp(_value, 0.10, 0.95); break;
        case "tournament": _mgr.tournament_size = clamp(round(_value), 2, 8); break;
        case "fitness": _mgr.fitness_threshold = clamp(_value, 10, 300); break;
        case "max_generations": _mgr.max_generations = clamp(round(_value), 1, 1000); break;
        case "init_range":
            _mgr.weight_init_range = clamp(_value, 0.25, 5);
            _mgr.population_pool = [];
        break;
        case "equal_weight":
            _mgr.weight_equal_value = clamp(_value, -2, 2);
            _mgr.population_pool = [];
        break;
    }
    global.ai_menu_message = "VALOR ACTUALIZADO";
}

function std_ai_menu_help(_id) {
    switch (_id) {
        case "population": return "Agentes evaluados por generacion. Mas diversidad tambien exige mas procesamiento.";
        case "mutation": return "Probabilidad de alterar cada peso al crear un descendiente.";
        case "crossover": return "Probabilidad de combinar dos padres; sin cruce se conserva una copia del padre A.";
        case "sigma": return "Intensidad del ajuste cuando la mutacion es gaussiana.";
        case "duration": return "Tiempo maximo de cada combate antes de cerrarlo como TIMEOUT.";
        case "threshold": return "Confianza minima en modo UMBRAL. ARGMAX siempre elige la salida mayor.";
        case "tournament": return "Cantidad de candidatos comparados en cada seleccion por torneo.";
        case "fitness": return "Puntuacion y al menos una baja necesarias para avanzar de escenario.";
        case "max_generations": return "Limite total de la corrida. Al alcanzarlo guarda el campeon y se detiene.";
        case "weight_init": return "Inicializa una poblacion nueva con pesos RANDOM, EQUAL o ZERO.";
        case "init_range": return "Limite absoluto de los pesos iniciales cuando el modo es RANDOM.";
        case "equal_weight": return "Valor comun de todos los pesos iniciales cuando el modo es EQUAL.";
        case "architecture": return "Red directa 6>6 o red con una capa oculta de 8 neuronas.";
        case "decision": return "ARGMAX siempre actua; UMBRAL exige la confianza configurada.";
        case "selection": return "TORNEO favorece estabilidad; RULETA conserva mas azar.";
        case "mutation_type": return "GAUSSIANA ajusta pesos; UNIFORME los reemplaza dentro del rango.";
        case "training_mode": return "SIMULTANEO evalua toda la poblacion a la vez; contra HUMANO cambia a secuencial.";
        case "sensor0": return "Distancia normalizada al objetivo actual.";
        case "sensor1": return "Proporcion de salud propia.";
        case "sensor2": return "Energia disponible en la barrera.";
        case "sensor3": return "Linea de vision hacia el objetivo.";
        case "sensor4": return "Disponibilidad independiente del ataque cuerpo a cuerpo.";
        case "sensor5": return "Disponibilidad independiente del ataque a distancia.";
        case "train": return "Inicia una sesion nueva o pausa/reanuda la sesion activa.";
        case "continue": return "Recupera el checkpoint o el campeon de progreso compatible guardado por v11-v13.";
        case "test": return "Carga el mejor cerebro guardado para combatir contra el jugador.";
        case "benchmark": return "Abre los 10 escenarios, repeticiones, semillas y variables experimentales.";
        case "defaults": return "Restaura parametros recomendados sin borrar el mejor cerebro guardado.";
        case "back": return "Vuelve a la pantalla anterior.";
    }
    return "Configura la red, los sensores y el algoritmo genetico antes de entrenar.";
}

function std_ai_menu_step() {
    var _mx = device_mouse_x_to_gui(0);
    var _my = device_mouse_y_to_gui(0);
    var _controls = std_ai_menu_controls();
    global.ai_menu_hover = "";
    var _hover_kind = "";
    var _hover_zone = "";

    for (var i = 0; i < array_length(_controls); i++) {
        var _c = _controls[i];
        var _r = _c.rect;
        if (point_in_rectangle(_mx, _my, _r[0], _r[1], _r[2], _r[3])) {
            global.ai_menu_hover = _c.id;
            _hover_kind = _c.kind;
            if (_c.kind == "number") {
                if (_mx < _r[0] + 42) _hover_zone = "minus";
                else if (_mx > _r[2] - 42) _hover_zone = "plus";
                else _hover_zone = "value";
            }
        }
    }

    if (keyboard_check_pressed(vk_escape)) {
        global.state = global.ai_menu_return_state;
        return;
    }

    if (mouse_check_button_pressed(mb_left) && global.ai_menu_hover != "") {
        var _id = global.ai_menu_hover;
        if (_hover_kind == "number") {
            if (_hover_zone == "minus") std_ai_menu_adjust(_id, -1);
            if (_hover_zone == "plus") std_ai_menu_adjust(_id, 1);
            if (_hover_zone == "value") std_ai_menu_edit_number(_id);
        } else if (_hover_kind == "enum") {
            std_ai_menu_adjust(_id, 1);
        } else if (_hover_kind == "sensor") {
            var _sensor_index = real(string_delete(_id, 1, 6));
            if (global.evo_manager.training_active) {
                global.ai_menu_message = "DETEN EL ENTRENAMIENTO PARA CAMBIAR LA CONFIGURACION";
            } else {
                global.evo_manager.sensor_enabled[_sensor_index] = !global.evo_manager.sensor_enabled[_sensor_index];
            }
        } else if (_hover_kind == "action") {
            switch (_id) {
                case "back": global.state = global.ai_menu_return_state; break;
                case "defaults":
                    if (global.evo_manager.training_active) {
                        global.ai_menu_message = "DETEN EL ENTRENAMIENTO PARA REINICIAR VALORES";
                    } else {
                        std_manager_reset_defaults();
                        global.ai_menu_message = "CONFIGURACION RESTABLECIDA";
                    }
                break;
                case "test":
                    if (global.evo_manager.training_active) {
                        global.ai_menu_message = "DETEN EL ENTRENAMIENTO ANTES DE PROBAR";
                    } else if (!std_manager_test_best()) {
                        global.ai_menu_message = "AUN NO HAY UN MEJOR AGENTE GUARDADO";
                    }
                break;
                case "benchmark":
                    if (global.evo_manager.training_active) {
                        global.ai_menu_message = "DETEN EL ENTRENAMIENTO ANTES DEL BENCHMARK";
                    } else std_benchmark_menu_open();
                break;
                case "continue":
                    if (global.evo_manager.training_active) {
                        global.ai_menu_message = "EL ENTRENAMIENTO YA ESTA ACTIVO";
                    } else if (!std_manager_resume_training()) {
                        global.ai_menu_message = "NO HAY CHECKPOINT NI CAMPEON PARA CONTINUAR";
                    }
                break;
                case "train":
                    if (!global.evo_manager.training_active) {
                        std_manager_start_training(true);
                    } else {
                        std_manager_toggle_pause();
                        global.state = "TRAIN";
                    }
                break;
            }
        }
    }
}

function std_draw_ai_menu() {
    var _mgr = global.evo_manager;
    draw_clear(make_color_rgb(5, 9, 18));
    draw_set_alpha(0.16);
    draw_set_color(make_color_rgb(54, 202, 232));
    for (var gx = 0; gx <= 1280; gx += 40) draw_line(gx, 0, gx, 720);
    for (var gy = 0; gy <= 720; gy += 40) draw_line(0, gy, 1280, gy);
    draw_set_alpha(1);

    draw_set_halign(fa_left);
    draw_set_color(make_color_rgb(72, 225, 245));
    draw_rectangle(34, 26, 42, 94, false);
    draw_set_color(c_white);
    draw_text_transformed(62, 25, "LABORATORIO DE IA", 1.75, 1.75, 0);
    draw_set_color(make_color_rgb(133, 161, 184));
    draw_text(64, 76, "CONFIGURA, ENTRENA Y PRUEBA EL CEREBRO DEL AGENTE");

    draw_set_alpha(0.92);
    draw_set_color(make_color_rgb(7, 17, 30));
    draw_roundrect(34, 112, 790, 626, false);
    draw_roundrect(808, 112, 1246, 696, false);
    draw_set_alpha(1);
    draw_set_color(make_color_rgb(42, 80, 103));
    draw_roundrect(34, 112, 790, 626, true);
    draw_roundrect(808, 112, 1246, 696, true);

    var _sensor_names = ["DISTANCIA", "SALUD", "BARRERA", "VISION", "MELEE LISTO", "DISPARO LISTO"];
    var _sensor_y = [164, 232, 300, 368, 436, 504];
    var _action_names = ["ESCAPAR", "PERSEGUIR", "MELEE", "DISTANCIA", "SANAR", "DEFENDER"];
    var _action_y = [158, 232, 306, 380, 454, 528];

    // Connections first, with low alpha to keep the diagram readable.
    draw_set_alpha(0.18);
    draw_set_color(make_color_rgb(111, 211, 229));
    if (_mgr.use_hidden_layers) {
        for (var si = 0; si < NN_INPUT_SIZE; si++) {
            for (var hi = 0; hi < 8; hi++) {
                draw_line(264, _sensor_y[si], 456, 152 + hi * 55);
            }
        }
        for (var hj = 0; hj < 8; hj++) {
            for (var ao = 0; ao < 6; ao++) {
                draw_line(474, 152 + hj * 55, 652, _action_y[ao]);
            }
        }
    } else {
        for (var sd = 0; sd < NN_INPUT_SIZE; sd++) {
            for (var ad = 0; ad < 6; ad++) draw_line(264, _sensor_y[sd], 652, _action_y[ad]);
        }
    }
    draw_set_alpha(1);

    for (var s = 0; s < NN_INPUT_SIZE; s++) {
        var _enabled = _mgr.sensor_enabled[s];
        draw_set_color(_enabled ? make_color_rgb(18, 84, 103) : make_color_rgb(38, 43, 52));
        draw_roundrect(54, _sensor_y[s] - 18, 250, _sensor_y[s] + 22, false);
        draw_set_color(_enabled ? make_color_rgb(80, 232, 247) : make_color_rgb(105, 112, 123));
        draw_circle(264, _sensor_y[s], 10, false);
        draw_set_color(_enabled ? c_white : make_color_rgb(130, 137, 148));
        draw_text(70, _sensor_y[s] - 8, "X" + string(s + 1) + "  " + _sensor_names[s]);
        draw_set_halign(fa_right);
        draw_text(238, _sensor_y[s] - 8, _enabled ? "ON" : "OFF");
        draw_set_halign(fa_left);
    }

    if (_mgr.use_hidden_layers) {
        draw_set_halign(fa_center);
        draw_set_color(make_color_rgb(140, 166, 188));
        draw_text(465, 124, "CAPA OCULTA [8]");
        for (var h = 0; h < 8; h++) {
            draw_set_color(make_color_rgb(245, 198, 93));
            draw_circle(465, 152 + h * 55, 11, false);
        }
    }

    draw_set_halign(fa_center);
    draw_set_color(make_color_rgb(140, 166, 188));
    draw_text(665, 124, "ACCIONES [6]");
    for (var a = 0; a < 6; a++) {
        draw_set_color(make_color_rgb(255, 103, 132));
        draw_circle(665, _action_y[a], 11, false);
        draw_set_halign(fa_left);
        draw_set_color(c_white);
        draw_text(685, _action_y[a] - 8, _action_names[a]);
        draw_set_halign(fa_center);
    }

    draw_set_halign(fa_left);
    draw_set_color(c_white);
    draw_text_transformed(830, 126, "AJUSTAR SIMULACION", 1.16, 1.16, 0);
    var _controls = std_ai_menu_controls();
    for (var i = 0; i < array_length(_controls); i++) {
        var _c = _controls[i];
        if (_c.kind == "sensor" || _c.kind == "action") continue;
        var _r = _c.rect;
        var _hover = global.ai_menu_hover == _c.id;
        draw_set_color(_hover ? make_color_rgb(27, 95, 116) : make_color_rgb(13, 35, 51));
        draw_roundrect(_r[0], _r[1], _r[2], _r[3], false);
        draw_set_color(_hover ? make_color_rgb(78, 229, 244) : make_color_rgb(50, 93, 116));
        draw_roundrect(_r[0], _r[1], _r[2], _r[3], true);
        if (_c.kind == "number") {
            draw_line(_r[0] + 42, _r[1], _r[0] + 42, _r[3]);
            draw_line(_r[2] - 42, _r[1], _r[2] - 42, _r[3]);
            draw_set_halign(fa_center);
            draw_set_color(c_white);
            draw_text(_r[0] + 21, _r[1] + 10, "-");
            draw_text(_r[2] - 21, _r[1] + 10, "+");
        }
        draw_set_halign(fa_center);
        draw_set_color(make_color_rgb(244, 203, 105));
        draw_text((_r[0] + _r[2]) * 0.5, _r[1] + 10, std_ai_menu_value(_c.id));
        draw_set_halign(fa_left);
        draw_set_color(make_color_rgb(196, 214, 227));
        draw_text(_r[2] + 12, _r[1] + 10, _c.label);
    }

    var _actions = ["back", "defaults", "test", "benchmark", "continue", "train"];
    for (var b = 0; b < array_length(_actions); b++) {
        var _bid = _actions[b];
        for (var ci = 0; ci < array_length(_controls); ci++) {
            var _button = _controls[ci];
            if (_button.id != _bid) continue;
            var _br = _button.rect;
            var _bhover = global.ai_menu_hover == _bid;
            var _label = _button.label;
            if (_bid == "train" && _mgr.training_active) _label = _mgr.training_paused ? "REANUDAR" : "PAUSAR";
            draw_set_color(_bhover ? make_color_rgb(69, 219, 235) : make_color_rgb(17, 57, 75));
            draw_roundrect(_br[0], _br[1], _br[2], _br[3], false);
            draw_set_halign(fa_center);
            draw_set_color(_bhover ? make_color_rgb(5, 18, 27) : c_white);
            draw_text((_br[0] + _br[2]) * 0.5, _br[1] + 14, _label);
        }
    }

    draw_set_halign(fa_left);
    draw_set_color(make_color_rgb(255, 224, 148));
    draw_text(54, 606, std_ai_menu_help(global.ai_menu_hover));
    if (global.ai_menu_message != "") {
        draw_set_halign(fa_center);
        draw_set_color(make_color_rgb(255, 124, 145));
        draw_text(640, 98, global.ai_menu_message);
    }
    draw_set_halign(fa_left);
    draw_set_alpha(1);
}
