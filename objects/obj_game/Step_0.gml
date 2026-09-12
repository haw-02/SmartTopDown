global.dt = min(delta_time / 1000000, 0.033333);
global.menu_time += global.dt;
global.menu_change_fx = max(0, global.menu_change_fx - global.dt);

if (keyboard_check_pressed(ord("M"))) global.muted = !global.muted;

if (global.state == "BENCH_MENU") {
    std_benchmark_menu_step();
} else if (global.state == "AI_MENU") {
    std_ai_menu_step();
} else if (global.state == "MENU") {
    var _mouse_x = device_mouse_x_to_gui(0);
    var _mouse_y = device_mouse_y_to_gui(0);
    var _mouse_option = -1;
    for (var _hover_i = 0; _hover_i < 4; _hover_i++) {
        var _hover_y = 254 + _hover_i * 78;
        if (point_in_rectangle(_mouse_x, _mouse_y, 790, _hover_y, 1190, _hover_y + 60)) {
            _mouse_option = _hover_i;
        }
    }
    if (_mouse_option >= 0) global.menu_option = _mouse_option;

    var _menu_move = keyboard_check_pressed(vk_down) || keyboard_check_pressed(ord("S"));
    _menu_move -= keyboard_check_pressed(vk_up) || keyboard_check_pressed(ord("W"));
    if (_menu_move != 0) global.menu_option = (global.menu_option + _menu_move + 4) mod 4;

    if (global.menu_option != global.menu_last_option) {
        global.menu_last_option = global.menu_option;
        global.menu_change_fx = 0.16;
    }

    var _menu_confirm = keyboard_check_pressed(vk_enter) || keyboard_check_pressed(vk_space);
    _menu_confirm = _menu_confirm || (_mouse_option >= 0 && mouse_check_button_pressed(mb_left));
    if (_menu_confirm) {
        switch (global.menu_option) {
            case 0: std_load_level(0); break;
            case 1: std_ai_menu_open("MENU"); break;
            case 2: global.state = "CONTROLS"; break;
            case 3: game_end(); break;
        }
    }
} else if (global.state == "CONTROLS") {
    if (keyboard_check_pressed(vk_escape) || keyboard_check_pressed(vk_enter)
        || keyboard_check_pressed(vk_space)) {
        global.state = "MENU";
    }
}

if ((global.state == "PLAY" || global.state == "TRAIN" || global.state == "BENCHMARK")
    && keyboard_check_pressed(ord("H"))) {
    global.debug_ai = !global.debug_ai;
}
if ((global.state == "PLAY" || global.state == "PAUSE") && keyboard_check_pressed(ord("R"))) {
    std_load_level(global.level_index);
}
if ((global.state == "PLAY" || global.state == "TRAIN") && keyboard_check_pressed(ord("I"))) {
    std_ai_menu_open(global.state);
}

if (keyboard_check_pressed(vk_escape)) {
    if (global.state == "PLAY") global.state = "PAUSE";
    else if (global.state == "PAUSE") global.state = "PLAY";
    else if (global.state == "TRAIN") std_manager_toggle_pause();
    else if (global.state == "BENCHMARK") global.benchmark.paused = !global.benchmark.paused;
}
if (global.state == "TRAIN" && keyboard_check_pressed(ord("P"))) std_manager_toggle_pause();
if (global.state == "TRAIN" && keyboard_check_pressed(ord("T"))) std_manager_stop_training();
if (global.state == "BENCHMARK" && keyboard_check_pressed(ord("P"))) {
    global.benchmark.paused = !global.benchmark.paused;
}
if (global.state == "BENCHMARK" && keyboard_check_pressed(ord("T"))) std_benchmark_abort();

if ((global.state == "GAMEOVER" || global.state == "VICTORY") && keyboard_check_pressed(vk_enter)) {
    if (global.state == "VICTORY") {
        std_load_level(0);
        global.state = "MENU";
        global.menu_option = 0;
    } else {
        std_load_level(global.level_index);
    }
}

if (global.state == "PLAY" && global.level_banner <= 0) {
    std_update_game();
}
if (global.state == "TRAIN" && global.level_banner <= 0
    && global.evo_manager.training_active && !global.evo_manager.training_paused) {
    std_update_game();
    std_manager_tick();
}
if (global.state == "BENCHMARK" && global.level_banner <= 0
    && global.benchmark.active && !global.benchmark.paused) {
    std_update_game();
    std_benchmark_tick();
}

global.message_time = max(0, global.message_time - global.dt);
global.level_banner = max(0, global.level_banner - global.dt);
