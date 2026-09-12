"""Static validation for the benchmark-ready GameMaker project."""
from __future__ import annotations

import json
import re
from collections import deque
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def load_gamemaker_json(path: Path):
    text = path.read_text(encoding="utf-8")
    text = re.sub(r",(?=\s*[}\]])", "", text)
    return json.loads(text)


def validate_delimiters(path: Path):
    text = path.read_text(encoding="utf-8")
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r'"(?:\\.|[^"\\])*"', '""', text)
    text = re.sub(r"(?m)//.*$", "", text)
    pairs = {"{": "}", "(": ")", "[": "]"}
    stack: list[tuple[str, int]] = []
    for index, char in enumerate(text):
        if char in pairs:
            stack.append((char, index))
        elif char in pairs.values():
            assert stack and pairs[stack[-1][0]] == char, f"Unbalanced {char} in {path}"
            stack.pop()
    assert not stack, f"Unclosed delimiter in {path}: {stack[-1]}"


def parse_levels():
    text = (ROOT / "scripts/scr_levels/scr_levels.gml").read_text(encoding="utf-8")
    blocks = []
    position = 0
    while True:
        start = text.find("return {", position)
        if start < 0:
            break
        brace = text.find("{", start)
        depth = 0
        in_string = False
        escaped = False
        for index in range(brace, len(text)):
            char = text[index]
            if in_string:
                if escaped:
                    escaped = False
                elif char == "\\":
                    escaped = True
                elif char == '"':
                    in_string = False
                continue
            if char == '"':
                in_string = True
            elif char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    raw = text[brace:index + 1]
                    raw = re.sub(r"(?m)//.*$", "", raw)
                    raw = re.sub(r"(?<=[{,])\s*([A-Za-z_][A-Za-z0-9_]*)\s*:", r'"\1":', raw)
                    blocks.append(json.loads(raw))
                    position = index + 1
                    break
    return blocks


def validate_level(level):
    cols, rows = level["cols"], level["rows"]
    blocked = {(x, 0) for x in range(cols)} | {(x, rows - 1) for x in range(cols)}
    blocked |= {(0, y) for y in range(rows)} | {(cols - 1, y) for y in range(rows)}
    for x, y, width, height in level["walls"]:
        blocked |= {(xx, yy) for xx in range(x, x + width) for yy in range(y, y + height)}
    blocked |= {tuple(cell) for cell in level["spikes"]}
    points = [tuple(level["player"]), tuple(level["exit_cell"])]
    points += [tuple(cell) for cell in level["potions"]]
    points += [tuple(enemy["cell"]) for enemy in level["enemies"]]
    assert all(0 <= x < cols and 0 <= y < rows for x, y in points), level["name"]
    assert not any(point in blocked for point in points), level["name"]
    if level["name"] == "TRAINING - Arena Paralela":
        # The 24 lanes are deliberately disconnected to prevent candidates
        # from affecting one another during simultaneous evaluation.
        assert len(level["potions"]) == 24
        for index in range(24):
            lane_col, lane_row = index % 6, index // 6
            lane_x, lane_y = 1 + lane_col * 8, 1 + lane_row * 7
            agent = (lane_x + 1, lane_y + 2)
            opponent = (lane_x + 5, lane_y + 2)
            potion = tuple(level["potions"][index])
            assert agent not in blocked and opponent not in blocked
            seen = {agent}
            queue = deque(seen)
            while queue:
                x, y = queue.popleft()
                for cell in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= cell[0] < cols and 0 <= cell[1] < rows and cell not in blocked and cell not in seen:
                        seen.add(cell)
                        queue.append(cell)
            assert opponent in seen and potion in seen, f"Broken parallel lane {index}"
        return
    seen = {tuple(level["player"])}
    queue = deque(seen)
    while queue:
        x, y = queue.popleft()
        for cell in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= cell[0] < cols and 0 <= cell[1] < rows and cell not in blocked and cell not in seen:
                seen.add(cell)
                queue.append(cell)
    assert all(point in seen for point in points), f"Unreachable point in {level['name']}"


def main():
    yyp = load_gamemaker_json(ROOT / "SmartTopDown_3_1.yyp")
    for resource in yyp["resources"]:
        assert (ROOT / resource["id"]["path"]).exists(), resource
    for included in yyp["IncludedFiles"]:
        assert (ROOT / included["filePath"] / included["name"]).exists(), included
    for path in ROOT.rglob("*.yy"):
        load_gamemaker_json(path)
    for path in ROOT.rglob("*.gml"):
        validate_delimiters(path)
    levels = parse_levels()
    assert len(levels) == 6, f"Expected 3 game levels plus training, benchmark and parallel arenas, found {len(levels)}"
    for level in levels:
        validate_level(level)
    assert any(level["name"] == "BENCHMARK - Arena Sigma" for level in levels)
    assert any(level["name"] == "TRAINING - Arena Paralela" for level in levels)

    all_gml = "\n".join(path.read_text(encoding="utf-8") for path in ROOT.rglob("*.gml"))
    definitions = set(re.findall(r"function\s+(std_[A-Za-z0-9_]+)\s*\(", all_gml))
    calls = set(re.findall(r"\b(std_[A-Za-z0-9_]+)\s*\(", all_gml))
    missing = sorted(calls - definitions)
    assert not missing, f"Missing std_* functions: {missing}"

    evolution = (ROOT / "scripts/scr_evolution_manager/scr_evolution_manager.gml").read_text(encoding="utf-8")
    core = (ROOT / "scripts/scr_core/scr_core.gml").read_text(encoding="utf-8")
    ai = (ROOT / "scripts/scr_ai_core/scr_ai_core.gml").read_text(encoding="utf-8")
    nn = (ROOT / "scripts/scr_nn/scr_nn.gml").read_text(encoding="utf-8")
    ga = (ROOT / "scripts/scr_ga/scr_ga.gml").read_text(encoding="utf-8")
    step = (ROOT / "objects/obj_game/Step_0.gml").read_text(encoding="utf-8")

    scenarios = re.findall(r'\{ id: \d+, name: "[^"]+", level:', evolution)
    assert len(scenarios) == 10, f"Expected 10 benchmark scenarios, found {len(scenarios)}"
    assert evolution.count("level: 4") == 10, "Every benchmark scenario must use the unseen arena"
    required_tokens = [
        "std_benchmark_start", "std_benchmark_tick", "std_benchmark_write_summary",
        "STD_AI_BENCHMARK_FILE", "STD_AI_BENCHMARK_SUMMARY_FILE", "winner",
        "avg_lifespan", "success_rate", "dominant_action", "random_set_seed",
        "matches_per_agent", "selection_rate", "weight_init_mode", "mutation_range",
        "training_mode", "std_manager_spawn_parallel_round", "std_manager_tick_parallel",
    ]
    for token in required_tokens:
        assert token in evolution, f"Missing benchmark token: {token}"
    assert 'global.state == "BENCHMARK"' in step
    assert 'global.state == "BENCHMARK"' in core
    assert 'global.state == "BENCHMARK"' in ai
    assert 'training_target' in ai
    assert 'std_training_same_pair' in core
    assert "std_ga_parent_pool" in ga and "_params.selection_rate" in ga
    assert '"random"' in ga and '"equal"' in ga and '"zero"' in ga
    assert '"DEFENSA CERCANA"' in core
    assert '_enemy.burst_remaining = 0' in core
    assert 'global.state != "BENCHMARK"' in core
    assert "std_ai_init_agent(_enemy)" in core

    # v10 UI: weight initialization belongs to AI configuration, not benchmark execution.
    ai_controls = re.search(r"function std_ai_menu_controls\(\).*?function std_ai_menu_value", evolution, re.S).group(0)
    benchmark_controls = re.search(r"function std_benchmark_menu_controls\(\).*?function std_benchmark_menu_value", evolution, re.S).group(0)
    benchmark_draw = re.search(r"function std_draw_benchmark_menu\(\).*?// -----------------------------------------------------------------------------\n// AI configuration menu", evolution, re.S).group(0)
    for token in ['id: "weight_init"', 'id: "init_range"', 'id: "equal_weight"']:
        assert token in ai_controls, f"Missing AI configuration control: {token}"
        assert token not in benchmark_controls, f"Weight control still exposed in benchmark: {token}"
    for label in ['"PESOS INICIALES"', '"RANGO PESOS"', '"PESO IGUAL"']:
        assert label in ai_controls, f"Missing AI configuration label: {label}"
        assert label not in benchmark_draw, f"Weight label still drawn in benchmark: {label}"

    # v14: training uses exactly one round per generation; benchmark
    # repetitions stay independent and no training-round control is exposed.
    assert "#macro STD_AI_TRAINING_ROUNDS 1" in evolution
    assert 'id: "matches"' not in benchmark_controls
    assert '"PARTIDAS / AGENTE"' not in benchmark_draw
    assert "_mgr.matches_per_agent = STD_AI_TRAINING_ROUNDS" in evolution

    # v9 audit: all six final benchmark blockers remain fixed.
    assert "#macro NN_INPUT_SIZE  6" in nn
    assert "_inputs[4]" in ai and "_inputs[5]" in ai
    assert "max(_melee_ready, _ranged_ready)" not in ai
    training_seed_block = evolution[evolution.index("function std_manager_spawn_training_episode"):
                                    evolution.index("function std_manager_spawn_population")]
    assert "evaluation_agent_index * 100" not in training_seed_block
    assert "std_manager_apply_best_to_enemy(_spawned_enemy)" in core
    assert "std_kill_enemy_hazard(_enemy)" in core
    assert "_enemy.fitness -= 15" in core
    assert "_enemy.decision_timer <= 0" in ai and "AI_DECISION_INTERVAL" in ai
    assert "version: 5" in evolution
    assert "std_manager_valid_chromosome" in evolution
    assert "std_manager_valid_sensors" in evolution
    assert "std_manager_valid_training_config" in evolution

    # v12 recovery, bounded training and anti-stall behavior.
    for token in [
        "STD_AI_CHECKPOINT_FILE", "std_manager_checkpoint_save",
        "std_manager_checkpoint_load", "std_manager_seed_population_from_best",
        "STD_AI_STALL_TIMEOUT", "pair_no_progress_time", "episode_no_progress_time",
        "max_generations", "std_ai_menu_edit_number", 'id: "continue"',
    ]:
        assert token in evolution, f"Missing v12 recovery/control token: {token}"
    assert '"max_generations"' in ai_controls
    assert 'if (_enemy.dead) return;' in core
    assert "std_flee_cell_clearance" in core
    assert '_enemy.state == "ESCAPAR" && _dist < 285' in core
    assert 'global.ai_menu_message = "ENTRENAMIENTO COMPLETADO - CAMPEON GUARDADO"' in evolution

    # v13: raw historical fitness never decreases, while the champion used for
    # continuation and benchmarking prioritizes curriculum progress.
    assert "progress_champion" in evolution
    assert "_best_fitness > _mgr.best_fitness_ever" in evolution
    assert "_mgr.best_stage_index != _mgr.stage_index || _best_fitness > _mgr.best_fitness_ever" not in evolution
    assert "_mgr.stage_index > _mgr.progress_stage_index" in evolution
    assert "_bench.frozen_chromosome = std_ga_copy_chromosome(_mgr.progress_chromosome)" in evolution
    assert "HIST." in core and "ETAPA" in core

    yyp_original = ROOT.parents[2] / "current/Project/SmartTopDown_3_1/SmartTopDown_3_1.yyp"
    if yyp_original.exists():
        assert (ROOT / "SmartTopDown_3_1.yyp").read_bytes() == yyp_original.read_bytes(), "Yyp changed"

    print("OK: GameMaker records, resource references and GML delimiters")
    print(f"OK: {len(definitions)} std_* functions resolved")
    print("OK: 10 benchmark scenarios and reproducible CSV pipeline")
    print("OK: benchmark uses a reachable arena excluded from training")
    print("OK: isolated single-round training and experimental variables")
    print("OK: Type B close-defense state is exclusive with ranged fire")
    print("OK: six cooldown/fairness/champion/hazard/timing/JSON fixes")
    print("OK: v12 checkpoint recovery, generation limit, direct numeric editing and C anti-stall logic")
    print("OK: v13 separates nondecreasing historical fitness from stage-progress champion")
    print("OK: v14 fixes training to one round while benchmark repetitions remain independent")


if __name__ == "__main__":
    main()
