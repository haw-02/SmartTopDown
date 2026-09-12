randomize();
display_set_gui_size(1280, 720);

global.muted = false;
global.debug_ai = false;
global.nav_grid = -1;
global.enemies = [];

// Runtime texture loading keeps every visual asset editable in datafiles/textures.
// Frame order: 12 directional walk poses followed by 12 integrated sword
// attack poses (DOWN, LEFT, RIGHT, UP; three phases per direction).
global.spr_player = std_load_sprite("player.png", 24);
// Enemy strips contain 12 directional frames for each of the three factions:
// Neon security, Cobalt laboratory and Crimson fortress.
global.spr_enemy_a = std_load_sprite("enemy_a.png", 36);
global.spr_enemy_b = std_load_sprite("enemy_b.png", 36);
global.spr_enemy_c = std_load_sprite("enemy_c.png", 36);
global.spr_enemy_rl = std_load_sprite("enemy_rl.png", 36);
global.spr_blade = std_load_sprite("blade.png");
global.spr_shield = std_load_sprite("shield.png");
global.spr_projectile = std_load_sprite("projectile.png");
global.spr_potion = std_load_sprite("potion.png");
global.spr_spike = std_load_sprite("spike.png");
global.spr_exit = std_load_sprite("exit.png");
global.spr_floor = [
    std_load_sprite("floor_neon.png"),
    std_load_sprite("floor_lab.png"),
    std_load_sprite("floor_citadel.png")
];
global.spr_wall = [
    std_load_sprite("wall_neon.png"),
    std_load_sprite("wall_lab.png"),
    std_load_sprite("wall_citadel.png")
];

// Lightweight placeholder SFX; section 3.1 audio can be expanded later.
global.sfx_swing = std_load_stream("swing.ogg");
global.sfx_shot = std_load_stream("shot.ogg");
global.sfx_hit = std_load_stream("hit.ogg");
global.sfx_block = std_load_stream("block.ogg");
global.sfx_heal = std_load_stream("heal.ogg");
global.sfx_down = std_load_stream("down.ogg");

std_manager_init();
std_load_level(0);
global.state = "MENU";
global.menu_option = 0;
global.menu_time = 0;
global.menu_last_option = 0;
global.menu_change_fx = 0;
global.ai_menu_return_state = "MENU";
global.ai_menu_hover = "";
global.ai_menu_message = "";
