// ============================================================================
// yetris-asm: AArch64 Assembly Tetris Clone for macOS Apple Silicon
// File: asm/layout.s -- Subwindow lifecycle: create and destroy ncurses
//                       window hierarchies for game and menu screens
// Build: make asm
//
// Provides:
//   _init_game_layout:    Create 80x24 game window hierarchy (9 windows)
//   _destroy_game_layout: Delete game windows in reverse order, zero pointers
//   _init_menu_layout:    Create 80x24 menu window hierarchy (3 windows)
//   _destroy_menu_layout: Delete menu windows in reverse order, zero pointers
//
// Window geometry matches C++ LayoutGame.cpp / LayoutMainMenu.cpp:
//
// Game layout (80x24):
//   main:         newwin(24, 80, 0, 0)
//   leftmost:     derwin(main, 24, 12, 0, 0)
//   hold:         derwin(leftmost, 4, 12, 0, 0)
//   score:        derwin(leftmost, 20, 12, 4, 0)
//   middle_left:  derwin(main, 22, 22, 0, 12)
//   board:        derwin(middle_left, 22, 22, 0, 0)
//   middle_right: derwin(main, 4, 10, 0, 34)
//   rightmost:    derwin(main, 24, 35, 0, 44)
//   pause:        derwin(main, 6, 40, 11, 20)
//
// Menu layout (80x24):
//   menu_main:    newwin(24, 80, 0, 0)
//   menu_logo:    derwin(menu_main, 9, 80, 0, 0)
//   menu_items:   derwin(menu_main, 13, 28, 10, 24)
//
// Data dependencies (from asm/data.s):
//   _win_main, _win_leftmost, _win_hold, _win_score,
//   _win_middle_left, _win_board, _win_middle_right, _win_rightmost,
//   _win_pause, _win_menu_main, _win_menu_logo, _win_menu_items
//
// ncurses functions used: _newwin, _derwin, _delwin
//
// Darwin ARM64 ABI: x0-x15 caller-saved, x19-x28 callee-saved, x18 reserved.
// ============================================================================

.section __TEXT,__text,regular,pure_instructions

// ============================================================================
// _init_game_layout: Create the full game subwindow hierarchy
// void _init_game_layout(void)
//
// Creates 9 ncurses windows matching C++ geometry. Parent WINDOW* pointers
// are kept in callee-saved registers across derwin calls.
//
// Uses callee-saved: x19=main, x20=leftmost, x21=middle_left
// Stack: 48 bytes (x19-x21 + x29/x30)
// ============================================================================
.globl _init_game_layout
.p2align 2
_init_game_layout:
    stp     x29, x30, [sp, #-48]!
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    mov     x29, sp

    // --- main: newwin(24, 80, 0, 0) ---
    mov     w0, #24
    mov     w1, #80
    mov     w2, #0
    mov     w3, #0
    bl      _newwin
    mov     x19, x0                     // x19 = main WINDOW*
    adrp    x8, _win_main@PAGE
    str     x0, [x8, _win_main@PAGEOFF]

    // --- leftmost: derwin(main, 24, 12, 0, 0) ---
    mov     x0, x19                     // parent = main
    mov     w1, #24
    mov     w2, #12
    mov     w3, #0
    mov     w4, #0
    bl      _derwin
    mov     x20, x0                     // x20 = leftmost WINDOW*
    adrp    x8, _win_leftmost@PAGE
    str     x0, [x8, _win_leftmost@PAGEOFF]

    // --- hold: derwin(leftmost, 4, 12, 0, 0) ---
    mov     x0, x20                     // parent = leftmost
    mov     w1, #4
    mov     w2, #12
    mov     w3, #0
    mov     w4, #0
    bl      _derwin
    adrp    x8, _win_hold@PAGE
    str     x0, [x8, _win_hold@PAGEOFF]

    // --- score: derwin(leftmost, 20, 12, 4, 0) ---
    mov     x0, x20                     // parent = leftmost
    mov     w1, #20
    mov     w2, #12
    mov     w3, #4
    mov     w4, #0
    bl      _derwin
    adrp    x8, _win_score@PAGE
    str     x0, [x8, _win_score@PAGEOFF]

    // --- middle_left: derwin(main, 22, 22, 0, 12) ---
    mov     x0, x19                     // parent = main
    mov     w1, #22
    mov     w2, #22
    mov     w3, #0
    mov     w4, #12
    bl      _derwin
    mov     x21, x0                     // x21 = middle_left WINDOW*
    adrp    x8, _win_middle_left@PAGE
    str     x0, [x8, _win_middle_left@PAGEOFF]

    // --- board: derwin(middle_left, 22, 22, 0, 0) ---
    mov     x0, x21                     // parent = middle_left
    mov     w1, #22
    mov     w2, #22
    mov     w3, #0
    mov     w4, #0
    bl      _derwin
    adrp    x8, _win_board@PAGE
    str     x0, [x8, _win_board@PAGEOFF]

    // --- middle_right: derwin(main, 4, 10, 0, 34) ---
    mov     x0, x19                     // parent = main
    mov     w1, #4
    mov     w2, #10
    mov     w3, #0
    mov     w4, #34
    bl      _derwin
    adrp    x8, _win_middle_right@PAGE
    str     x0, [x8, _win_middle_right@PAGEOFF]

    // --- rightmost: derwin(main, 24, 35, 0, 44) ---
    mov     x0, x19                     // parent = main
    mov     w1, #24
    mov     w2, #35
    mov     w3, #0
    mov     w4, #44
    bl      _derwin
    adrp    x8, _win_rightmost@PAGE
    str     x0, [x8, _win_rightmost@PAGEOFF]

    // --- pause: derwin(main, 6, 40, 11, 20) ---
    mov     x0, x19                     // parent = main
    mov     w1, #6
    mov     w2, #40
    mov     w3, #11
    mov     w4, #20
    bl      _derwin
    adrp    x8, _win_pause@PAGE
    str     x0, [x8, _win_pause@PAGEOFF]

    // Epilogue
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// ============================================================================
// _destroy_game_layout: Delete all game windows, zero pointers
// void _destroy_game_layout(void)
//
// Deletes in reverse creation order: pause, rightmost, middle_right, board,
// middle_left, score, hold, leftmost, main. Skips NULL pointers (cbz).
// Zeros all pointer slots after deletion.
//
// Uses callee-saved: x19 (temp pointer base)
// Stack: 16 bytes (x29/x30)
// ============================================================================
.globl _destroy_game_layout
.p2align 2
_destroy_game_layout:
    stp     x29, x30, [sp, #-32]!
    stp     x19, x20, [sp, #16]
    mov     x29, sp

    // --- Delete pause ---
    adrp    x8, _win_pause@PAGE
    ldr     x0, [x8, _win_pause@PAGEOFF]
    cbz     x0, Lskip_pause_del
    bl      _delwin
Lskip_pause_del:

    // --- Delete rightmost ---
    adrp    x8, _win_rightmost@PAGE
    ldr     x0, [x8, _win_rightmost@PAGEOFF]
    cbz     x0, Lskip_rightmost_del
    bl      _delwin
Lskip_rightmost_del:

    // --- Delete middle_right ---
    adrp    x8, _win_middle_right@PAGE
    ldr     x0, [x8, _win_middle_right@PAGEOFF]
    cbz     x0, Lskip_middle_right_del
    bl      _delwin
Lskip_middle_right_del:

    // --- Delete board ---
    adrp    x8, _win_board@PAGE
    ldr     x0, [x8, _win_board@PAGEOFF]
    cbz     x0, Lskip_board_del
    bl      _delwin
Lskip_board_del:

    // --- Delete middle_left ---
    adrp    x8, _win_middle_left@PAGE
    ldr     x0, [x8, _win_middle_left@PAGEOFF]
    cbz     x0, Lskip_middle_left_del
    bl      _delwin
Lskip_middle_left_del:

    // --- Delete score ---
    adrp    x8, _win_score@PAGE
    ldr     x0, [x8, _win_score@PAGEOFF]
    cbz     x0, Lskip_score_del
    bl      _delwin
Lskip_score_del:

    // --- Delete hold ---
    adrp    x8, _win_hold@PAGE
    ldr     x0, [x8, _win_hold@PAGEOFF]
    cbz     x0, Lskip_hold_del
    bl      _delwin
Lskip_hold_del:

    // --- Delete leftmost ---
    adrp    x8, _win_leftmost@PAGE
    ldr     x0, [x8, _win_leftmost@PAGEOFF]
    cbz     x0, Lskip_leftmost_del
    bl      _delwin
Lskip_leftmost_del:

    // --- Delete main ---
    adrp    x8, _win_main@PAGE
    ldr     x0, [x8, _win_main@PAGEOFF]
    cbz     x0, Lskip_main_del
    bl      _delwin
Lskip_main_del:

    // --- Zero all game window pointers ---
    adrp    x8, _win_main@PAGE
    str     xzr, [x8, _win_main@PAGEOFF]
    adrp    x8, _win_leftmost@PAGE
    str     xzr, [x8, _win_leftmost@PAGEOFF]
    adrp    x8, _win_hold@PAGE
    str     xzr, [x8, _win_hold@PAGEOFF]
    adrp    x8, _win_score@PAGE
    str     xzr, [x8, _win_score@PAGEOFF]
    adrp    x8, _win_middle_left@PAGE
    str     xzr, [x8, _win_middle_left@PAGEOFF]
    adrp    x8, _win_board@PAGE
    str     xzr, [x8, _win_board@PAGEOFF]
    adrp    x8, _win_middle_right@PAGE
    str     xzr, [x8, _win_middle_right@PAGEOFF]
    adrp    x8, _win_rightmost@PAGE
    str     xzr, [x8, _win_rightmost@PAGEOFF]
    adrp    x8, _win_pause@PAGE
    str     xzr, [x8, _win_pause@PAGEOFF]

    // Epilogue
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// ============================================================================
// _init_menu_layout: Create the menu subwindow hierarchy
// void _init_menu_layout(void)
//
// Creates 3 ncurses windows: menu_main (newwin), menu_logo and menu_items
// (both derwin of menu_main).
//
// Uses callee-saved: x19=menu_main
// Stack: 32 bytes (x19 + x29/x30)
// ============================================================================
.globl _init_menu_layout
.p2align 2
_init_menu_layout:
    stp     x29, x30, [sp, #-32]!
    stp     x19, x20, [sp, #16]
    mov     x29, sp

    // --- menu_main: newwin(24, 80, 0, 0) ---
    mov     w0, #24
    mov     w1, #80
    mov     w2, #0
    mov     w3, #0
    bl      _newwin
    mov     x19, x0                     // x19 = menu_main WINDOW*
    adrp    x8, _win_menu_main@PAGE
    str     x0, [x8, _win_menu_main@PAGEOFF]

    // --- menu_logo: derwin(menu_main, 9, 80, 0, 0) ---
    mov     x0, x19                     // parent = menu_main
    mov     w1, #9
    mov     w2, #80
    mov     w3, #0
    mov     w4, #0
    bl      _derwin
    adrp    x8, _win_menu_logo@PAGE
    str     x0, [x8, _win_menu_logo@PAGEOFF]

    // --- menu_items: derwin(menu_main, 13, 28, 10, 24) ---
    mov     x0, x19                     // parent = menu_main
    mov     w1, #13
    mov     w2, #28
    mov     w3, #10
    mov     w4, #24
    bl      _derwin
    adrp    x8, _win_menu_items@PAGE
    str     x0, [x8, _win_menu_items@PAGEOFF]

    // Epilogue
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// ============================================================================
// _destroy_menu_layout: Delete all menu windows, zero pointers
// void _destroy_menu_layout(void)
//
// Deletes in reverse order: menu_items, menu_logo, menu_main.
// Skips NULL pointers (cbz). Zeros all pointer slots after deletion.
//
// Stack: 16 bytes (x29/x30)
// ============================================================================
.globl _destroy_menu_layout
.p2align 2
_destroy_menu_layout:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // --- Delete menu_items ---
    adrp    x8, _win_menu_items@PAGE
    ldr     x0, [x8, _win_menu_items@PAGEOFF]
    cbz     x0, Lskip_menu_items_del
    bl      _delwin
Lskip_menu_items_del:

    // --- Delete menu_logo ---
    adrp    x8, _win_menu_logo@PAGE
    ldr     x0, [x8, _win_menu_logo@PAGEOFF]
    cbz     x0, Lskip_menu_logo_del
    bl      _delwin
Lskip_menu_logo_del:

    // --- Delete menu_main ---
    adrp    x8, _win_menu_main@PAGE
    ldr     x0, [x8, _win_menu_main@PAGEOFF]
    cbz     x0, Lskip_menu_main_del
    bl      _delwin
Lskip_menu_main_del:

    // --- Zero all menu window pointers ---
    adrp    x8, _win_menu_main@PAGE
    str     xzr, [x8, _win_menu_main@PAGEOFF]
    adrp    x8, _win_menu_logo@PAGE
    str     xzr, [x8, _win_menu_logo@PAGEOFF]
    adrp    x8, _win_menu_items@PAGE
    str     xzr, [x8, _win_menu_items@PAGEOFF]

    // Epilogue
    ldp     x29, x30, [sp], #16
    ret

// ============================================================================
.subsections_via_symbols
