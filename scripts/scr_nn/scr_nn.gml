/// scr_nn.gml
/// Red neuronal del agente RL. Arquitectura fija: 6 inputs, 6 outputs, capa oculta opcional.
/// Supuesto: std_make_enemy() no inicializa nn_weights -> lo hace std_nn_init_weights().
/// Supuesto: array_concat() disponible (GMS 2.3+). Si tu runtime no lo tiene, reemplazar
/// std_nn_flatten() por concatenación manual con bucles.

#macro NN_INPUT_SIZE  6
#macro NN_HIDDEN_SIZE 8
#macro NN_OUTPUT_SIZE 6

/// @desc Crea nn_weights en _enemy con pesos aleatorios [-1,1]. Guarda AMBOS juegos de pesos
/// (shallow y con capa oculta) para poder alternar use_hidden_layers sin perder entrenamiento previo.
function std_nn_init_weights(_enemy) {
    var _w = {
        input_output:         array_create(NN_INPUT_SIZE * NN_OUTPUT_SIZE, 0),
        output_bias_shallow:  array_create(NN_OUTPUT_SIZE, 0),
        input_hidden:         array_create(NN_INPUT_SIZE * NN_HIDDEN_SIZE, 0),
        hidden_bias:          array_create(NN_HIDDEN_SIZE, 0),
        hidden_output:        array_create(NN_HIDDEN_SIZE * NN_OUTPUT_SIZE, 0),
        output_bias:          array_create(NN_OUTPUT_SIZE, 0)
    };

    var _keys = variable_struct_get_names(_w);
    for (var i = 0; i < array_length(_keys); i++) {
        var _arr = variable_struct_get(_w, _keys[i]);
        for (var j = 0; j < array_length(_arr); j++) {
            _arr[j] = random_range(-1, 1);
        }
    }

    // 1. Esto asegura que el enemigo que pasas ya tenga sus pesos.
    _enemy.nn_weights = _w; 
    
    // 2. ¡ESTO ES LO QUE FALTA! 
    // Permite que la función entregue el "cerebro" a quien lo pida.
    return _w; 
}

/// @desc tanh manual (GML no trae tanh nativo en todas las versiones).
function std_nn_tanh(_x) {
    var _e2x = exp(2 * _x);
    return (_e2x - 1) / (_e2x + 1);
}

/// @desc Normaliza un array de salidas crudas a distribución de probabilidad (softmax).
function std_nn_softmax(_arr) {
    var _n = array_length(_arr);

    var _max = _arr[0];
    for (var i = 1; i < _n; i++) {
        if (_arr[i] > _max) _max = _arr[i];
    }

    var _sum = 0;
    var _exp = array_create(_n, 0);
    for (var i = 0; i < _n; i++) {
        _exp[i] = exp(_arr[i] - _max);
        _sum += _exp[i];
    }

    var _result = array_create(_n, 0);
    for (var i = 0; i < _n; i++) {
        _result[i] = _exp[i] / _sum;
    }
    return _result;
}

/// @desc Forward pass. Usa _enemy.use_hidden_layers para decidir shallow vs 3 capas.
/// @param {Struct} _enemy
/// @param {Array}  _inputs  Array de NN_INPUT_SIZE floats
/// @return {Array} NN_OUTPUT_SIZE floats normalizados (softmax)
function std_nn_forward(_enemy, _inputs) {
    var _w = _enemy.nn_weights;
    var _raw_output = array_create(NN_OUTPUT_SIZE, 0);

    if (_enemy.use_hidden_layers) {
        var _hidden = array_create(NN_HIDDEN_SIZE, 0);

        for (var h = 0; h < NN_HIDDEN_SIZE; h++) {
            var _sum = _w.hidden_bias[h];
            for (var i = 0; i < NN_INPUT_SIZE; i++) {
                _sum += _inputs[i] * _w.input_hidden[i * NN_HIDDEN_SIZE + h];
            }
            _hidden[h] = std_nn_tanh(_sum);
        }

        for (var o = 0; o < NN_OUTPUT_SIZE; o++) {
            var _sum2 = _w.output_bias[o];
            for (var h2 = 0; h2 < NN_HIDDEN_SIZE; h2++) {
                _sum2 += _hidden[h2] * _w.hidden_output[h2 * NN_OUTPUT_SIZE + o];
            }
            _raw_output[o] = _sum2;
        }
    } else {
        for (var o2 = 0; o2 < NN_OUTPUT_SIZE; o2++) {
            var _sum3 = _w.output_bias_shallow[o2];
            for (var i2 = 0; i2 < NN_INPUT_SIZE; i2++) {
                _sum3 += _inputs[i2] * _w.input_output[i2 * NN_OUTPUT_SIZE + o2];
            }
            _raw_output[o2] = _sum3;
        }
    }

    return std_nn_softmax(_raw_output);
}

/// @desc Copia _target.length valores desde _flat comenzando en _start. Devuelve el nuevo cursor.
function std_nn_copy_segment(_flat, _start, _target) {
    var _len = array_length(_target);
    for (var i = 0; i < _len; i++) {
        _target[i] = _flat[_start + i];
    }
    return _start + _len;
}

/// @desc Aplana el juego de pesos ACTIVO (según use_hidden_layers) en un solo array.
/// Usado por el GA como "cromosoma".
function std_nn_flatten(_enemy) {
    var _w = _enemy.nn_weights;

    if (_enemy.use_hidden_layers) {
        return array_concat(_w.input_hidden, _w.hidden_bias, _w.hidden_output, _w.output_bias);
    } else {
        return array_concat(_w.input_output, _w.output_bias_shallow);
    }
}

/// @desc Vuelca un cromosoma plano de vuelta a la estructura nn_weights activa.
function std_nn_unflatten(_enemy, _flat) {
    var _w = _enemy.nn_weights;
    var _idx = 0;

    if (_enemy.use_hidden_layers) {
        _idx = std_nn_copy_segment(_flat, _idx, _w.input_hidden);
        _idx = std_nn_copy_segment(_flat, _idx, _w.hidden_bias);
        _idx = std_nn_copy_segment(_flat, _idx, _w.hidden_output);
        _idx = std_nn_copy_segment(_flat, _idx, _w.output_bias);
    } else {
        _idx = std_nn_copy_segment(_flat, _idx, _w.input_output);
        _idx = std_nn_copy_segment(_flat, _idx, _w.output_bias_shallow);
    }
}

/// @desc Longitud del cromosoma según el modo activo del enemigo. Útil para inicializar
/// el population_pool con el tamaño correcto.
function std_nn_chromosome_length(_enemy) {
    if (_enemy.use_hidden_layers) {
        return (NN_INPUT_SIZE * NN_HIDDEN_SIZE) + NN_HIDDEN_SIZE
             + (NN_HIDDEN_SIZE * NN_OUTPUT_SIZE) + NN_OUTPUT_SIZE;
    } else {
        return (NN_INPUT_SIZE * NN_OUTPUT_SIZE) + NN_OUTPUT_SIZE;
    }
}

/// @desc Chromosome size without instantiating an agent. Used by reproducible experiments.
function std_nn_expected_chromosome_length(_use_hidden_layers) {
    if (_use_hidden_layers) {
        return (NN_INPUT_SIZE * NN_HIDDEN_SIZE) + NN_HIDDEN_SIZE
             + (NN_HIDDEN_SIZE * NN_OUTPUT_SIZE) + NN_OUTPUT_SIZE;
    }
    return (NN_INPUT_SIZE * NN_OUTPUT_SIZE) + NN_OUTPUT_SIZE;
}
