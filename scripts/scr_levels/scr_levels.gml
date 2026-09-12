/// @function std_level_data(index)
/// @description Returns one of the three handcrafted section 3.1 levels.
function std_level_data(_index) {
    switch (_index) {
        case 0:
            return {
                name: "01 - Distrito Neon",
                subtitle: "Callejones de la corporacion Nova",
                cols: 30,
                rows: 19,
                floor_sprite: 0,
                player: [2, 2],
                exit_cell: [27, 16],
                walls: [
                    [7, 2, 1, 6], [7, 10, 1, 7],
                    [11, 5, 8, 1], [11, 13, 8, 1],
                    [22, 2, 1, 6], [22, 10, 1, 7],
                    [12, 8, 2, 2], [17, 9, 2, 2],
                    [25, 5, 3, 1], [2, 12, 3, 1]
                ],
                spikes: [[5, 8], [6, 8], [14, 11], [15, 11], [23, 8], [24, 8], [25, 8]],
                potions: [[5, 15], [14, 3], [20, 15], [26, 3]],
                enemies: [
                    { type: "A", cell: [10, 3] },
                    { type: "B", cell: [19, 3] },
                    { type: "C", cell: [10, 15] },
                    { type: "RL", cell: [24, 14] }
                ]
            };

        case 1:
            return {
                name: "02 - Laboratorio Cobalto",
                subtitle: "Instalacion de pruebas biologicas",
                cols: 32,
                rows: 20,
                floor_sprite: 1,
                player: [2, 17],
                exit_cell: [29, 2],
                walls: [
                    [5, 2, 1, 7], [5, 12, 1, 6],
                    [10, 1, 1, 5], [10, 8, 1, 8],
                    [15, 4, 1, 13],
                    [20, 1, 1, 6], [20, 10, 1, 8],
                    [25, 3, 1, 6], [25, 12, 1, 6],
                    [6, 9, 4, 1], [21, 8, 4, 1],
                    [11, 17, 4, 1], [26, 10, 4, 1],
                    [12, 2, 3, 1], [17, 7, 3, 1]
                ],
                spikes: [[7, 7], [8, 7], [12, 12], [13, 12], [18, 3], [18, 4], [23, 15], [24, 15], [28, 7]],
                potions: [[3, 4], [8, 15], [13, 6], [18, 16], [23, 5], [28, 14]],
                enemies: [
                    { type: "A", cell: [7, 4] },
                    { type: "A", cell: [13, 15] },
                    { type: "B", cell: [18, 5] },
                    { type: "B", cell: [28, 8] },
                    { type: "C", cell: [23, 16] },
                    { type: "RL", cell: [28, 3] }
                ]
            };
			
			case 3:
            // Arena de entrenamiento: sin A/B/C ni RL fijo, el manager
            // spawnea la población. Solo pociones para el Escenario 1.
            return {
                name: "TRAINING - Escenario 1",
                subtitle: "Poblacion RL vs pociones",
                cols: 20,
                rows: 14,
                floor_sprite: 0,
                player: [2, 2],
                exit_cell: [17, 11],
                walls: [],
                spikes: [],
                potions: [[6, 3], [13, 3], [6, 10], [13, 10], [10, 6]],
	                enemies: []
	            };

        case 4:
            // Unseen validation arena. Training never loads this geometry;
            // the benchmark runner inserts the exact scenario combatants.
            return {
                name: "BENCHMARK - Arena Sigma",
                subtitle: "Validacion controlada en geometria no entrenada",
                cols: 28,
                rows: 18,
                floor_sprite: 1,
                player: [2, 9],
                exit_cell: [25, 9],
                walls: [
                    [7, 2, 1, 5], [7, 11, 1, 5],
                    [13, 4, 2, 3], [13, 11, 2, 3],
                    [20, 2, 1, 5], [20, 11, 1, 5],
                    [9, 8, 3, 2], [16, 8, 3, 2]
                ],
                spikes: [[5, 5], [5, 13], [11, 3], [11, 14], [17, 3], [17, 14], [23, 5], [23, 13]],
                potions: [[4, 3], [4, 14], [13, 8], [23, 3], [23, 14]],
                enemies: []
            };

        case 5:
            // Twenty-four isolated combat lanes for parallel neuroevolution.
            // Each chromosome fights its own copy of A/B/C without sharing
            // targets, projectiles or healing resources with other candidates.
            return {
                name: "TRAINING - Arena Paralela",
                subtitle: "Hasta 24 evaluaciones independientes por ronda",
                cols: 50,
                rows: 30,
                floor_sprite: 0,
                player: [1, 1],
                exit_cell: [48, 28],
                walls: [
                    [8, 1, 1, 28], [16, 1, 1, 28], [24, 1, 1, 28],
                    [32, 1, 1, 28], [40, 1, 1, 28],
                    [1, 7, 48, 1], [1, 14, 48, 1], [1, 21, 48, 1]
                ],
                spikes: [],
                potions: [
                    [4, 5], [12, 5], [20, 5], [28, 5], [36, 5], [44, 5],
                    [4, 12], [12, 12], [20, 12], [28, 12], [36, 12], [44, 12],
                    [4, 19], [12, 19], [20, 19], [28, 19], [36, 19], [44, 19],
                    [4, 26], [12, 26], [20, 26], [28, 26], [36, 26], [44, 26]
                ],
                enemies: []
            };

        default:
            return {
                name: "03 - Fortaleza Carmesi",
                subtitle: "Nucleo de defensa del proyecto SMART",
                cols: 34,
                rows: 22,
                floor_sprite: 2,
                player: [2, 2],
                exit_cell: [31, 19],
                walls: [
                    [6, 2, 1, 8], [6, 13, 1, 7],
                    [11, 1, 1, 6], [11, 9, 1, 9],
                    [16, 4, 1, 14],
                    [21, 1, 1, 7], [21, 11, 1, 9],
                    [27, 2, 1, 7], [27, 13, 1, 7],
                    [7, 10, 4, 1], [12, 7, 4, 1],
                    [17, 9, 4, 1], [22, 10, 5, 1],
                    [28, 11, 4, 1], [1, 15, 5, 1],
                    [12, 19, 4, 1], [22, 3, 5, 1],
                    [14, 2, 2, 1], [18, 18, 3, 1]
                ],
                spikes: [
                    [4, 7], [5, 7], [8, 12], [9, 12],
                    [13, 14], [14, 14], [18, 6], [19, 6],
                    [23, 9], [24, 9], [25, 9], [29, 15],
                    [30, 15], [19, 20], [20, 20]
                ],
                potions: [[3, 18], [8, 5], [13, 17], [18, 2], [19, 13], [24, 17], [30, 5]],
                enemies: [
                    { type: "A", cell: [8, 3] },
                    { type: "A", cell: [14, 16] },
                    { type: "A", cell: [24, 6] },
                    { type: "B", cell: [9, 18] },
                    { type: "B", cell: [19, 4] },
                    { type: "C", cell: [14, 10] },
                    { type: "C", cell: [29, 18] },
                    { type: "RL", cell: [30, 3] },
                    { type: "RL", cell: [24, 14] }
                ]
            };
    }
}
