/// scr_ga.gml
/// Algoritmo genético agnóstico a la NN: opera sobre "cromosomas" (arrays planos de floats)
/// obtenidos vía std_nn_flatten() / std_nn_unflatten().

/// @desc Copia profunda de un array de 1 nivel (GML no tiene array_duplicate genérico seguro).
function std_ga_copy_chromosome(_chromosome) {
    var _len = array_length(_chromosome);
    var _copy = array_create(_len, 0);
    for (var i = 0; i < _len; i++) {
        _copy[i] = _chromosome[i];
    }
    return _copy;
}

function std_ga_random_weight(_range = 1) {
    return random_range(-abs(_range), abs(_range));
}

/// @desc Initial chromosome with RANDOM, EQUAL or ZERO weights.
function std_ga_init_chromosome(_length, _mode = "random", _range = 1, _equal_value = 0.25) {
    var _c = array_create(_length, 0);
    for (var i = 0; i < _length; i++) {
        if (_mode == "equal") _c[i] = _equal_value;
        else if (_mode == "zero") _c[i] = 0;
        else _c[i] = std_ga_random_weight(_range);
    }
    return _c;
}

function std_ga_init_random_chromosome(_length) {
    return std_ga_init_chromosome(_length, "random", 1, 0.25);
}

/// @desc Restricts reproduction to the best configured fraction of the population.
function std_ga_parent_pool(_population, _fitness, _selection_rate) {
    var _pop_size = array_length(_population);
    var _selected_count = clamp(ceil(_pop_size * _selection_rate), 2, _pop_size);
    var _used = array_create(_pop_size, false);
    var _parents = [];
    var _parent_fitness = [];
    for (var rank = 0; rank < _selected_count; rank++) {
        var _best_idx = -1;
        for (var i = 0; i < _pop_size; i++) {
            if (!_used[i] && (_best_idx < 0 || _fitness[i] > _fitness[_best_idx])) _best_idx = i;
        }
        _used[_best_idx] = true;
        array_push(_parents, _population[_best_idx]);
        array_push(_parent_fitness, _fitness[_best_idx]);
    }
    return { population: _parents, fitness: _parent_fitness };
}

/// @desc Selección por Torneo: toma _tournament_size individuos al azar, devuelve el mejor.
function std_ga_selection_tournament(_population, _fitness, _tournament_size) {
    var _pop_size = array_length(_population);

    var _best_idx = irandom(_pop_size - 1);
    var _best_fit = _fitness[_best_idx];

    for (var i = 1; i < _tournament_size; i++) {
        var _idx = irandom(_pop_size - 1);
        if (_fitness[_idx] > _best_fit) {
            _best_fit = _fitness[_idx];
            _best_idx = _idx;
        }
    }

    return std_ga_copy_chromosome(_population[_best_idx]);
}

/// @desc Selección por Ruleta. Desplaza fitness negativo a positivo antes de acumular
/// (la ruleta clásica requiere pesos >= 0).
function std_ga_selection_roulette(_population, _fitness) {
    var _pop_size = array_length(_population);

    var _min_fit = _fitness[0];
    for (var i = 1; i < _pop_size; i++) {
        if (_fitness[i] < _min_fit) _min_fit = _fitness[i];
    }
    var _shift = (_min_fit < 0) ? (-_min_fit + 1) : 0;

    var _total = 0;
    for (var i = 0; i < _pop_size; i++) {
        _total += _fitness[i] + _shift;
    }

    if (_total <= 0) {
        return std_ga_copy_chromosome(_population[irandom(_pop_size - 1)]);
    }

    var _pick = random(_total);
    var _accum = 0;
    for (var i = 0; i < _pop_size; i++) {
        _accum += _fitness[i] + _shift;
        if (_accum >= _pick) {
            return std_ga_copy_chromosome(_population[i]);
        }
    }

    return std_ga_copy_chromosome(_population[_pop_size - 1]);
}

/// @desc Cruce de un punto. Corta en índice aleatorio dentro del cromosoma.
function std_ga_crossover_single_point(_parent_a, _parent_b) {
    var _len = array_length(_parent_a);
    var _point = irandom_range(1, _len - 1);

    var _child = array_create(_len, 0);
    for (var i = 0; i < _len; i++) {
        _child[i] = (i < _point) ? _parent_a[i] : _parent_b[i];
    }
    return _child;
}

/// @desc Mutación Uniforme: con prob. _mutation_rate por gen, lo reemplaza por un valor
/// aleatorio nuevo dentro de [-_range, _range].
function std_ga_mutate_uniform(_chromosome, _mutation_rate, _range) {
    var _len = array_length(_chromosome);
    for (var i = 0; i < _len; i++) {
        if (random(1) < _mutation_rate) {
            _chromosome[i] = random_range(-_range, _range);
        }
    }
    return _chromosome;
}

/// @desc Ruido gaussiano vía Box-Muller (GML no trae random gaussiano nativo).
function std_ga_gaussian_random(_sigma) {
    var _u1 = max(random(1), 0.0001);
    var _u2 = random(1);
    var _z = sqrt(-2 * ln(_u1)) * cos(2 * pi * _u2);
    return _z * _sigma;
}

/// @desc Mutación Gaussiana: con prob. _mutation_rate por gen, SUMA ruido gaussiano
/// (perturbación, no reemplazo -> converge más suave que la uniforme).
function std_ga_mutate_gaussian(_chromosome, _mutation_rate, _sigma) {
    var _len = array_length(_chromosome);
    for (var i = 0; i < _len; i++) {
        if (random(1) < _mutation_rate) {
            _chromosome[i] += std_ga_gaussian_random(_sigma);
        }
    }
    return _chromosome;
}

/// @desc Orquesta una generación completa: elitismo opcional + selección + cruce + mutación.
/// @param {Array}  _population  Array de cromosomas (arrays planos)
/// @param {Array}  _fitness     Array paralelo de fitness por individuo
/// @param {Struct}  _params     {
///     selection_method: "tournament" | "roulette",
///     tournament_size: real,
///     mutation_method: "uniform" | "gaussian",
///     mutation_rate: real (0..1),
///     crossover_rate: real (0..1),
///     mutation_range: real,   // usado por uniform
///     mutation_sigma: real,   // usado por gaussian
///     elitism: bool
/// }
/// @return {Array} Nueva población (misma longitud que _population)
function std_ga_evolve_population(_population, _fitness, _params) {
    var _pop_size = array_length(_population);
    var _new_pop = array_create(_pop_size, 0);
    var _start = 0;
    var _selection_rate = variable_struct_exists(_params, "selection_rate") ? _params.selection_rate : 1;
    var _parent_pool = std_ga_parent_pool(_population, _fitness, _selection_rate);
    var _parent_population = _parent_pool.population;
    var _parent_fitness = _parent_pool.fitness;

    if (_params.elitism) {
        var _best_idx = 0;
        for (var i = 1; i < _pop_size; i++) {
            if (_fitness[i] > _fitness[_best_idx]) _best_idx = i;
        }
        _new_pop[0] = std_ga_copy_chromosome(_population[_best_idx]);
        _start = 1;
    }

    for (var i = _start; i < _pop_size; i++) {
        var _parent_a, _parent_b;

        if (_params.selection_method == "roulette") {
            _parent_a = std_ga_selection_roulette(_parent_population, _parent_fitness);
            _parent_b = std_ga_selection_roulette(_parent_population, _parent_fitness);
        } else {
            var _tournament = min(_params.tournament_size, array_length(_parent_population));
            _parent_a = std_ga_selection_tournament(_parent_population, _parent_fitness, _tournament);
            _parent_b = std_ga_selection_tournament(_parent_population, _parent_fitness, _tournament);
        }

        var _child;
        if (random(1) < _params.crossover_rate) {
            _child = std_ga_crossover_single_point(_parent_a, _parent_b);
        } else {
            _child = std_ga_copy_chromosome(_parent_a);
        }

        if (_params.mutation_method == "gaussian") {
            _child = std_ga_mutate_gaussian(_child, _params.mutation_rate, _params.mutation_sigma);
        } else {
            _child = std_ga_mutate_uniform(_child, _params.mutation_rate, _params.mutation_range);
        }

        _new_pop[i] = _child;
    }

    return _new_pop;
}
