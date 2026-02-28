// ============================================================================
// yetris-asm: AArch64 Assembly Tetris Clone for macOS Apple Silicon
// File: asm/data.s -- All game data tables (read-only) and mutable game state
// Build: make asm
//
// This file is the single source of truth for all game constants and state
// variables. All tables are in read-only __TEXT,__const section. All mutable
// game state is in __DATA,__data section.
//
// Data layout contracts:
//   - Piece data: type*100 + rotation*25 + row*5 + col (700 bytes)
//   - SRS kicks: direction*40 + start_rotation*10 + test*2 + axis (80 bytes each)
//   - Public labels are .globl for cross-file access; table-only strings are file-local
//
// Piece order: O=0, I=1, L=2, J=3, S=4, Z=5, T=6
// Piece values: 0=empty, 1=block, 2=pivot
// ============================================================================

// ============================================================================
// Read-only data tables
// ============================================================================
.section __TEXT,__const

// ----------------------------------------------------------------------------
// _piece_data: 7 tetrominoes x 4 rotations x 5 rows x 5 cols = 700 bytes
// Index: type*100 + rotation*25 + row*5 + col
// Values: 0=empty, 1=block, 2=pivot
// Source: C++ reference PieceDefinitions.cpp (exact transcription)
// Rotation states: 0=spawn, 1=CW(R), 2=180(2), 3=CCW(L)
// ----------------------------------------------------------------------------
.globl _piece_data
.p2align 2
_piece_data:

    // === O piece (type 0) - all 4 rotations identical ===

    // O rotation 0 (spawn)
    .byte 0,0,0,0,0
    .byte 0,0,0,0,0
    .byte 0,0,2,1,0
    .byte 0,0,1,1,0
    .byte 0,0,0,0,0

    // O rotation 1 (R)
    .byte 0,0,0,0,0
    .byte 0,0,0,0,0
    .byte 0,0,2,1,0
    .byte 0,0,1,1,0
    .byte 0,0,0,0,0

    // O rotation 2 (180)
    .byte 0,0,0,0,0
    .byte 0,0,0,0,0
    .byte 0,0,2,1,0
    .byte 0,0,1,1,0
    .byte 0,0,0,0,0

    // O rotation 3 (L)
    .byte 0,0,0,0,0
    .byte 0,0,0,0,0
    .byte 0,0,2,1,0
    .byte 0,0,1,1,0
    .byte 0,0,0,0,0

    // === I piece (type 1) ===

    // I rotation 0 (spawn) - horizontal, row 2
    .byte 0,0,0,0,0
    .byte 0,0,0,0,0
    .byte 0,1,2,1,1
    .byte 0,0,0,0,0
    .byte 0,0,0,0,0

    // I rotation 1 (R) - vertical, col 2
    .byte 0,0,0,0,0
    .byte 0,0,1,0,0
    .byte 0,0,2,0,0
    .byte 0,0,1,0,0
    .byte 0,0,1,0,0

    // I rotation 2 (180) - horizontal, row 2
    .byte 0,0,0,0,0
    .byte 0,0,0,0,0
    .byte 1,1,2,1,0
    .byte 0,0,0,0,0
    .byte 0,0,0,0,0

    // I rotation 3 (L) - vertical, col 2
    .byte 0,0,1,0,0
    .byte 0,0,1,0,0
    .byte 0,0,2,0,0
    .byte 0,0,1,0,0
    .byte 0,0,0,0,0

    // === L piece (type 2) ===

    // L rotation 0 (spawn)
    .byte 0,0,0,0,0
    .byte 0,0,0,1,0
    .byte 0,1,2,1,0
    .byte 0,0,0,0,0
    .byte 0,0,0,0,0

    // L rotation 1 (R)
    .byte 0,0,0,0,0
    .byte 0,0,1,0,0
    .byte 0,0,2,0,0
    .byte 0,0,1,1,0
    .byte 0,0,0,0,0

    // L rotation 2 (180)
    .byte 0,0,0,0,0
    .byte 0,0,0,0,0
    .byte 0,1,2,1,0
    .byte 0,1,0,0,0
    .byte 0,0,0,0,0

    // L rotation 3 (L)
    .byte 0,0,0,0,0
    .byte 0,1,1,0,0
    .byte 0,0,2,0,0
    .byte 0,0,1,0,0
    .byte 0,0,0,0,0

    // === J piece (type 3) ===

    // J rotation 0 (spawn)
    .byte 0,0,0,0,0
    .byte 0,1,0,0,0
    .byte 0,1,2,1,0
    .byte 0,0,0,0,0
    .byte 0,0,0,0,0

    // J rotation 1 (R)
    .byte 0,0,0,0,0
    .byte 0,0,1,1,0
    .byte 0,0,2,0,0
    .byte 0,0,1,0,0
    .byte 0,0,0,0,0

    // J rotation 2 (180)
    .byte 0,0,0,0,0
    .byte 0,0,0,0,0
    .byte 0,1,2,1,0
    .byte 0,0,0,1,0
    .byte 0,0,0,0,0

    // J rotation 3 (L)
    .byte 0,0,0,0,0
    .byte 0,0,1,0,0
    .byte 0,0,2,0,0
    .byte 0,1,1,0,0
    .byte 0,0,0,0,0

    // === S piece (type 4) ===

    // S rotation 0 (spawn)
    .byte 0,0,0,0,0
    .byte 0,1,1,0,0
    .byte 0,0,2,1,0
    .byte 0,0,0,0,0
    .byte 0,0,0,0,0

    // S rotation 1 (R)
    .byte 0,0,0,0,0
    .byte 0,0,0,1,0
    .byte 0,0,2,1,0
    .byte 0,0,1,0,0
    .byte 0,0,0,0,0

    // S rotation 2 (180)
    .byte 0,0,0,0,0
    .byte 0,0,0,0,0
    .byte 0,1,2,0,0
    .byte 0,0,1,1,0
    .byte 0,0,0,0,0

    // S rotation 3 (L)
    .byte 0,0,0,0,0
    .byte 0,0,1,0,0
    .byte 0,1,2,0,0
    .byte 0,1,0,0,0
    .byte 0,0,0,0,0

    // === Z piece (type 5) ===

    // Z rotation 0 (spawn)
    .byte 0,0,0,0,0
    .byte 0,0,1,1,0
    .byte 0,1,2,0,0
    .byte 0,0,0,0,0
    .byte 0,0,0,0,0

    // Z rotation 1 (R)
    .byte 0,0,0,0,0
    .byte 0,0,1,0,0
    .byte 0,0,2,1,0
    .byte 0,0,0,1,0
    .byte 0,0,0,0,0

    // Z rotation 2 (180)
    .byte 0,0,0,0,0
    .byte 0,0,0,0,0
    .byte 0,0,2,1,0
    .byte 0,1,1,0,0
    .byte 0,0,0,0,0

    // Z rotation 3 (L)
    .byte 0,0,0,0,0
    .byte 0,1,0,0,0
    .byte 0,1,2,0,0
    .byte 0,0,1,0,0
    .byte 0,0,0,0,0

    // === T piece (type 6) ===

    // T rotation 0 (spawn)
    .byte 0,0,0,0,0
    .byte 0,0,1,0,0
    .byte 0,1,2,1,0
    .byte 0,0,0,0,0
    .byte 0,0,0,0,0

    // T rotation 1 (R)
    .byte 0,0,0,0,0
    .byte 0,0,1,0,0
    .byte 0,0,2,1,0
    .byte 0,0,1,0,0
    .byte 0,0,0,0,0

    // T rotation 2 (180)
    .byte 0,0,0,0,0
    .byte 0,0,0,0,0
    .byte 0,1,2,1,0
    .byte 0,0,1,0,0
    .byte 0,0,0,0,0

    // T rotation 3 (L)
    .byte 0,0,0,0,0
    .byte 0,0,1,0,0
    .byte 0,1,2,0,0
    .byte 0,0,1,0,0
    .byte 0,0,0,0,0

// ----------------------------------------------------------------------------
// _srs_kicks_jlstz: SRS wall kick offsets for J, L, S, T, Z pieces
// Layout: direction*40 + start_rotation*10 + test*2 + axis
//         direction: 0=CW, 1=CCW
//         start_rotation: 0-3 (the rotation BEFORE the move)
//         test: 0-4 (5 kick tests)
//         axis: 0=dx, 1=dy
// Values are SIGNED bytes -- use ldrsb to load!
// SRS convention: positive Y = UP (negate when applying to board coords)
// Source: tetris.wiki SRS specification
// Total: 80 bytes (2 directions x 4 rotations x 5 tests x 2 axes)
// ----------------------------------------------------------------------------
.globl _srs_kicks_jlstz
.p2align 2
_srs_kicks_jlstz:
    // CW (direction 0): start_rotation is the state BEFORE rotation
    // CW 0->R: (0,0),(-1,0),(-1,+1),(0,-2),(-1,-2)
    .byte  0, 0,  -1, 0,  -1, 1,   0,-2,  -1,-2
    // CW R->2: (0,0),(+1,0),(+1,-1),(0,+2),(+1,+2)
    .byte  0, 0,   1, 0,   1,-1,   0, 2,   1, 2
    // CW 2->L: (0,0),(+1,0),(+1,+1),(0,-2),(+1,-2)
    .byte  0, 0,   1, 0,   1, 1,   0,-2,   1,-2
    // CW L->0: (0,0),(-1,0),(-1,-1),(0,+2),(-1,+2)
    .byte  0, 0,  -1, 0,  -1,-1,   0, 2,  -1, 2

    // CCW (direction 1): start_rotation is the state BEFORE rotation
    // CCW 0->L: (0,0),(+1,0),(+1,+1),(0,-2),(+1,-2)
    .byte  0, 0,   1, 0,   1, 1,   0,-2,   1,-2
    // CCW R->0: (0,0),(+1,0),(+1,-1),(0,+2),(+1,+2)
    .byte  0, 0,   1, 0,   1,-1,   0, 2,   1, 2
    // CCW 2->R: (0,0),(-1,0),(-1,+1),(0,-2),(-1,-2)
    .byte  0, 0,  -1, 0,  -1, 1,   0,-2,  -1,-2
    // CCW L->2: (0,0),(-1,0),(-1,-1),(0,+2),(-1,+2)
    .byte  0, 0,  -1, 0,  -1,-1,   0, 2,  -1, 2

// ----------------------------------------------------------------------------
// _srs_kicks_i: SRS wall kick offsets for I piece
// Same layout as _srs_kicks_jlstz: direction*40 + start_rotation*10 + test*2 + axis
// Values are SIGNED bytes -- use ldrsb to load!
// Source: tetris.wiki SRS specification (I-piece specific table)
// Total: 80 bytes
// ----------------------------------------------------------------------------
.globl _srs_kicks_i
.p2align 2
_srs_kicks_i:
    // CW (direction 0)
    // CW 0->R: (0,0),(-2,0),(+1,0),(-2,-1),(+1,+2)
    .byte  0, 0,  -2, 0,   1, 0,  -2,-1,   1, 2
    // CW R->2: (0,0),(-1,0),(+2,0),(-1,+2),(+2,-1)
    .byte  0, 0,  -1, 0,   2, 0,  -1, 2,   2,-1
    // CW 2->L: (0,0),(+2,0),(-1,0),(+2,+1),(-1,-2)
    .byte  0, 0,   2, 0,  -1, 0,   2, 1,  -1,-2
    // CW L->0: (0,0),(+1,0),(-2,0),(+1,-2),(-2,+1)
    .byte  0, 0,   1, 0,  -2, 0,   1,-2,  -2, 1

    // CCW (direction 1)
    // CCW 0->L: (0,0),(-1,0),(+2,0),(-1,+2),(+2,-1)
    .byte  0, 0,  -1, 0,   2, 0,  -1, 2,   2,-1
    // CCW R->0: (0,0),(+2,0),(-1,0),(+2,+1),(-1,-2)
    .byte  0, 0,   2, 0,  -1, 0,   2, 1,  -1,-2
    // CCW 2->R: (0,0),(+1,0),(-2,0),(+1,-2),(-2,+1)
    .byte  0, 0,   1, 0,  -2, 0,   1,-2,  -2, 1
    // CCW L->2: (0,0),(-2,0),(+1,0),(-2,-1),(+1,+2)
    .byte  0, 0,  -2, 0,   1, 0,  -2,-1,   1, 2

// ----------------------------------------------------------------------------
// _gravity_delays: 22-entry .hword table (milliseconds per level)
// Level 1 = 1000ms, level 22 = 0ms (instant)
// Index: (level - 1) * 2  (since .hword = 2 bytes)
// Total: 44 bytes
// ----------------------------------------------------------------------------
.globl _gravity_delays
.p2align 1
_gravity_delays:
    .hword 1000, 900, 800, 700, 600, 500, 450, 400, 350, 300, 250
    .hword  200, 150, 120, 100,  80,  60,  40,  30,  20,  10,   0

// ----------------------------------------------------------------------------
// _score_table: 4-entry .word table for line clears
// Index: (lines_cleared - 1) * 4  (since .word = 4 bytes)
// 1 line=100, 2 lines=300, 3 lines=500, 4 lines(tetris)=800
// Total: 16 bytes
// ----------------------------------------------------------------------------
.globl _score_table
.p2align 2
_score_table:
    .word 100, 300, 500, 800

// ----------------------------------------------------------------------------
// _perfect_clear_table: 4-entry .word table for perfect clear bonuses
// Index: (lines_cleared - 1) * 4  (since .word = 4 bytes)
// 1 line=800, 2 lines=1200, 3 lines=1800, 4 lines=2000
// Base values (multiply by level at use site)
// Total: 16 bytes
// ----------------------------------------------------------------------------
.globl _perfect_clear_table
.p2align 2
_perfect_clear_table:
    .word 800, 1200, 1800, 2000

// ----------------------------------------------------------------------------
// _tspin_score_table: 4-entry .word table for T-spin scoring
// Index 0 = T-spin zero (no lines), 1 = T-spin single, 2 = double, 3 = triple
// Base values (multiply by level at use site)
// Total: 16 bytes
// ----------------------------------------------------------------------------
.globl _tspin_score_table
.p2align 2
_tspin_score_table:
    .word 400, 800, 1200, 1600

// ----------------------------------------------------------------------------
// _level_thresholds: 22-entry .hword table of cumulative lines for each level
// Level N requires level_thresholds[N-1] total lines cleared
// Index: (level - 1) * 2  (since .hword = 2 bytes)
// Total: 44 bytes
// ----------------------------------------------------------------------------
.globl _level_thresholds
.p2align 1
_level_thresholds:
    .hword 5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 100
    .hword 120, 140, 160, 180, 210, 240, 280, 310, 350, 400, 450

// ----------------------------------------------------------------------------
// _color_pairs: 7 bytes mapping piece type (0-6) to ncurses color pair (1-7)
// O=1(yellow), I=2(cyan), L=3(white), J=4(blue), S=5(green), Z=6(red), T=7(magenta)
// Total: 7 bytes
// ----------------------------------------------------------------------------
.globl _color_pairs
_color_pairs:
    .byte 1, 2, 3, 4, 5, 6, 7

// ----------------------------------------------------------------------------
// _piece_spawn_x: 7 signed bytes -- spawn X position for each piece type
// All pieces spawn at x=2 to center 5x5 grid on 10-wide board
// (board cols 2-6 covered, leaving 0-1 and 7-9 free)
// Total: 7 bytes
// ----------------------------------------------------------------------------
.globl _piece_spawn_x
_piece_spawn_x:
    .byte 2, 2, 2, 2, 2, 2, 2

// ----------------------------------------------------------------------------
// _piece_spawn_y: 7 signed bytes -- spawn Y position for each piece type
// Pieces spawn above the board so lowest blocks appear at row 0.
// Negative values mean rows above the visible board.
// O=0,I=1,L=2,J=3,S=4,Z=5,T=6
// Values from C++ reference: global_pieces_position[type][0][1]
//   O: -4  I: -3  L: -3  J: -3  S: -3  Z: -3  T: -3
// These match the C++ reference spawn y positions (rotation 0)
// Total: 7 bytes
// ----------------------------------------------------------------------------
.globl _piece_spawn_y
_piece_spawn_y:
    .byte 0xFC, 0xFD, 0xFD, 0xFD, 0xFD, 0xFD, 0xFD  // -4, -3, -3, -3, -3, -3, -3 (signed)

// ----------------------------------------------------------------------------
// _neon_row_mask: 16-byte mask for NEON line detection
// Bytes 0-9 = 0x00 (pass through real board data)
// Bytes 10-15 = 0xFF (force padding to non-zero so uminv ignores them)
// Used in _mark_lines to vectorize full-row check with ld1+uminv
// ----------------------------------------------------------------------------
.globl _neon_row_mask
.p2align 2                          // 4-byte aligned (ld1 does not require 16-byte alignment on AArch64)
_neon_row_mask:
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF

// ----------------------------------------------------------------------------
// Panel title strings (Phase 6)
// ----------------------------------------------------------------------------
.globl _str_hold_title
_str_hold_title:    .asciz "Hold"
.globl _str_next_title
_str_next_title:    .asciz "Next"
.globl _str_stats_title
_str_stats_title:   .asciz "Statistics"
.globl _str_paused_title
_str_paused_title:  .asciz "Paused"
.globl _str_hiscore_label
_str_hiscore_label: .asciz "Hi-Score"
.globl _str_hiscore_none
_str_hiscore_none:  .asciz "(none)"
.globl _str_home_env
_str_home_env:      .asciz "HOME"
.globl _str_hiscore_suffix
_str_hiscore_suffix: .asciz "/.yetris-hiscore"
.globl _str_timer_label
_str_timer_label:   .asciz "Timer"
.globl _str_version
_str_version:       .asciz "yetris v1.2"
.globl _str_score_label
_str_score_label:   .asciz "Score"
.globl _str_level_lbl
_str_level_lbl:     .asciz "Level"
.globl _str_lines_label
_str_lines_label:   .asciz "Lines"
.globl _str_single_label
_str_single_label:  .asciz "Single"
.globl _str_double_label
_str_double_label:  .asciz "Double"
.globl _str_triple_label
_str_triple_label:  .asciz "Triple"
.globl _str_tetris_label
_str_tetris_label:  .asciz "Tetris"
.globl _str_game_over
_str_game_over:     .asciz "GAME OVER"
.globl _str_press_q_quit
_str_press_q_quit:  .asciz "Press q to quit"

// ----------------------------------------------------------------------------
// ASCII art logo strings (7 lines, from C++ LayoutMainMenu::draw)
// ----------------------------------------------------------------------------
_logo_line0: .asciz " __ __    ___ ______  ____   ____ _____"
_logo_line1: .asciz "|  |  |  /  _]      ||    \\ |    / ___/"
_logo_line2: .asciz "|  |  | /  [_|      ||  D  ) |  (   \\_"
_logo_line3: .asciz "|  ~  ||    _]_|  |_||    /  |  |\\__  |"
_logo_line4: .asciz "|___, ||   [_  |  |  |    \\  |  |/  \\ |"
_logo_line5: .asciz "|     ||     | |  |  |  .  \\ |  |\\    |"
_logo_line6: .asciz "|____/ |_____| |__|  |__|\\_ ||____|\\___| "

// Pause menu item strings
.globl _str_pause_resume
_str_pause_resume:     .asciz "Resume"
.globl _str_pause_quit_menu
_str_pause_quit_menu:  .asciz "Quit to Main Menu"
.globl _str_pause_quit_game
_str_pause_quit_game:  .asciz "Quit Game"

// Piece type letters for stats display
.globl _piece_letters
_piece_letters:     .asciz "OILJSZT"

// ----------------------------------------------------------------------------
// Menu and help screen strings
// ----------------------------------------------------------------------------
_str_start:         .asciz "Start Game"
_str_help:          .asciz "Help"
_str_quit:          .asciz "Quit"

_str_level_label:   .asciz "Starting Level: "
_str_ghost_label:   .asciz "Ghost Piece:  "
_str_hold_label:    .asciz "Hold Piece:   "
_str_invis_label:   .asciz "Invisible:    "
_str_noise_label:   .asciz "Noise Rows:   "

.globl _str_on
_str_on:            .asciz "ON "
.globl _str_off
_str_off:           .asciz "OFF"

.globl _str_help_title
_str_help_title:    .asciz "-- CONTROLS --"
_str_help_left:     .asciz "Left Arrow    Move Left"
_str_help_right:    .asciz "Right Arrow   Move Right"
_str_help_down:     .asciz "Down Arrow    Soft Drop"
_str_help_up:       .asciz "Up Arrow      Rotate CW"
_str_help_z:        .asciz "Z             Rotate CCW"
_str_help_space:    .asciz "Space         Hard Drop"
_str_help_c:        .asciz "C             Hold Piece"
_str_help_p:        .asciz "P             Pause"
_str_help_q:        .asciz "Q / ESC       Quit"
.globl _str_help_back
_str_help_back:     .asciz "Press any key to return"

// ============================================================================
// Pointer tables (require relocations, must be in __DATA section)
// ============================================================================
.section __DATA,__const

// Menu item string pointer table (3 entries: Start, Help, Quit)
.globl _menu_items
.p2align 3
_menu_items:
    .quad _str_start
    .quad _str_help
    .quad _str_quit

// Settings label pointer table (5 entries)
.globl _settings_labels
.p2align 3
_settings_labels:
    .quad _str_level_label
    .quad _str_ghost_label
    .quad _str_hold_label
    .quad _str_invis_label
    .quad _str_noise_label

// Help text pointer table (9 entries)
.globl _help_lines
.p2align 3
_help_lines:
    .quad _str_help_left
    .quad _str_help_right
    .quad _str_help_down
    .quad _str_help_up
    .quad _str_help_z
    .quad _str_help_space
    .quad _str_help_c
    .quad _str_help_p
    .quad _str_help_q

// Logo line pointer table (7 entries)
.globl _logo_lines
.p2align 3
_logo_lines:
    .quad _logo_line0
    .quad _logo_line1
    .quad _logo_line2
    .quad _logo_line3
    .quad _logo_line4
    .quad _logo_line5
    .quad _logo_line6

// ============================================================================
// Mutable game state variables
// ============================================================================
.section __DATA,__data

// ----------------------------------------------------------------------------
// _board: 10 columns x 20 rows = 200 bytes, row-major
// Value 0 = empty, 1-7 = piece type + 1 (for color lookup)
// Index: row * 10 + col
// ----------------------------------------------------------------------------
.globl _board
.p2align 2
_board:
    .space 200, 0
    .space 8, 0                     // NEON padding: ld1 reads 16 bytes from last row (offset 190-205)

// ----------------------------------------------------------------------------
// Current piece state
// ----------------------------------------------------------------------------
.globl _piece_type
_piece_type:
    .byte 0                 // 0-6 (O,I,L,J,S,Z,T)

.globl _piece_rotation
_piece_rotation:
    .byte 0                 // 0-3

.globl _piece_x
.p2align 1
_piece_x:
    .hword 0                // signed 16-bit (can be negative during spawn/kick)

.globl _piece_y
_piece_y:
    .hword 0                // signed 16-bit (negative when above board)

// ----------------------------------------------------------------------------
// Score state
// ----------------------------------------------------------------------------
.globl _score
.p2align 2
_score:
    .word 0                 // unsigned 32-bit

.globl _level
_level:
    .word 1                 // unsigned 32-bit, starts at level 1

.globl _lines_cleared
_lines_cleared:
    .word 0                 // unsigned 32-bit

.globl _game_over
_game_over:
    .byte 0                 // boolean flag (0=playing, 1=game over)

.globl _hiscore
.p2align 2
_hiscore:
    .word 0                 // unsigned 32-bit hi-score (loaded from disk, default 0)

// ----------------------------------------------------------------------------
// 7-bag random state
// ----------------------------------------------------------------------------
.globl _bag
_bag:
    .space 7, 0             // shuffled piece indices (0-6)

.globl _bag_index
_bag_index:
    .byte 7                 // starts at 7 to trigger initial refill on first _next_piece call

// ----------------------------------------------------------------------------
// Timer state
// ----------------------------------------------------------------------------
.globl _last_drop_time
.p2align 3
_last_drop_time:
    .quad 0                 // 64-bit millisecond timestamp

// ----------------------------------------------------------------------------
// Line clear animation state
// ----------------------------------------------------------------------------
.globl _line_clear_state
_line_clear_state:  .byte 0         // 0=idle, 1=rows flashing

.globl _line_clear_timer
.p2align 3
_line_clear_timer:  .quad 0         // ms timestamp when flash started

// ----------------------------------------------------------------------------
// Hold piece state
// ----------------------------------------------------------------------------
.globl _hold_piece_type
_hold_piece_type:
    .byte 0xFF                  // 0-6 = held type, 0xFF = empty

.globl _can_hold
_can_hold:
    .byte 1                     // 1 = can hold, 0 = already held this turn

// ----------------------------------------------------------------------------
// Pause state
// ----------------------------------------------------------------------------
.globl _is_paused
_is_paused:
    .byte 0                     // 0 = playing, 1 = paused

.globl _pause_selection
_pause_selection:   .byte 0         // 0=Resume, 1=Quit to Menu, 2=Quit Game

// ----------------------------------------------------------------------------
// Statistics counters
// ----------------------------------------------------------------------------
.globl _stats_pieces
.p2align 2
_stats_pieces:
    .word 0                     // total pieces locked

.globl _stats_piece_counts
_stats_piece_counts:
    .word 0, 0, 0, 0, 0, 0, 0  // per-type counts: O, I, L, J, S, Z, T

.globl _stats_singles
_stats_singles:     .word 0
.globl _stats_doubles
_stats_doubles:     .word 0
.globl _stats_triples
_stats_triples:     .word 0
.globl _stats_tetris
_stats_tetris:      .word 0

// ----------------------------------------------------------------------------
// Scoring engine state (Phase 8: modern guideline scoring)
// ----------------------------------------------------------------------------
.globl _combo_count
.p2align 2
_combo_count:       .word 0         // consecutive line-clearing locks; reset to 0 on non-clearing lock

.globl _b2b_active
_b2b_active:        .byte 0         // 1 = last line clear was "difficult" (Tetris/T-spin), 0 = not active

.globl _last_was_rotation
_last_was_rotation: .byte 0         // 1 = last successful action was rotation (for T-spin detection)

.globl _is_tspin
_is_tspin:          .byte 0         // 1 = current lock is a T-spin (set during _lock_piece)

// ----------------------------------------------------------------------------
// Menu and game mode settings
// ----------------------------------------------------------------------------
.globl _game_state
_game_state:        .byte 0         // 0=MENU, 1=GAME, 2=HELP

.globl _menu_selection
_menu_selection:    .byte 0         // current highlighted menu item (0-7)

.globl _starting_level
.p2align 2
_starting_level:    .word 1         // 1-22, default 1

.globl _opt_ghost
_opt_ghost:         .byte 1         // ghost piece on/off, default on

.globl _opt_hold
_opt_hold:          .byte 1         // hold piece on/off, default on

.globl _opt_invisible
_opt_invisible:     .byte 0         // invisible mode on/off, default off

.globl _opt_noise
_opt_noise:         .byte 0         // initial noise rows 0-20, default 0

// === Subwindow pointers (Phase 6) ===
// WINDOW* pointers for ncurses subwindow hierarchy.
// Game layout: 80x24 main window with 8 derived subwindows
// Menu layout: 80x24 main window with 2 derived subwindows
// All initialized to NULL (0); set by _init_game_layout / _init_menu_layout

// --- Game window pointers ---
// main: newwin(24, 80, 0, 0) -- top-level game container
.globl _win_main
.p2align 3
_win_main:          .quad 0

// leftmost: derwin(main, 24, 12, 0, 0) -- left panel (hold + score)
.globl _win_leftmost
.p2align 3
_win_leftmost:      .quad 0

// hold: derwin(leftmost, 4, 12, 0, 0) -- hold piece display
.globl _win_hold
.p2align 3
_win_hold:          .quad 0

// score: derwin(leftmost, 20, 12, 4, 0) -- score/level/lines display
.globl _win_score
.p2align 3
_win_score:         .quad 0

// middle_left: derwin(main, 22, 22, 0, 12) -- board container
.globl _win_middle_left
.p2align 3
_win_middle_left:   .quad 0

// board: derwin(middle_left, 22, 22, 0, 0) -- game board (fills parent)
.globl _win_board
.p2align 3
_win_board:         .quad 0

// middle_right: derwin(main, 4, 10, 0, 34) -- next piece preview
.globl _win_middle_right
.p2align 3
_win_middle_right:  .quad 0

// rightmost: derwin(main, 24, 35, 0, 44) -- statistics panel
.globl _win_rightmost
.p2align 3
_win_rightmost:     .quad 0

// pause: derwin(main, 6, 40, 11, 20) -- pause overlay (shown only when paused)
.globl _win_pause
.p2align 3
_win_pause:         .quad 0

// --- Menu window pointers ---
// menu_main: newwin(24, 80, 0, 0) -- top-level menu container
.globl _win_menu_main
.p2align 3
_win_menu_main:     .quad 0

// menu_logo: derwin(menu_main, 9, 80, 0, 0) -- logo/title area
.globl _win_menu_logo
.p2align 3
_win_menu_logo:     .quad 0

// menu_items: derwin(menu_main, 13, 28, 10, 24) -- menu item list
.globl _win_menu_items
.p2align 3
_win_menu_items:    .quad 0

// --- Game timer ---
// Millisecond timestamp set when game starts; used for statistics elapsed timer
.globl _game_start_time
.p2align 3
_game_start_time:   .quad 0

// --- Animation state (Phase 10) ---
.globl _anim_type
_anim_type:         .byte 0             // 0=fire, 1=water, 2=snakes, 3=life

.globl _anim_last_update
.p2align 3
_anim_last_update:  .quad 0             // ms timestamp of last animation update

.globl _anim_last_add
.p2align 3
_anim_last_add:     .quad 0             // ms timestamp for snake add timer

.globl _anim_snake_count
_anim_snake_count:  .byte 0             // current number of active snakes

.globl _anim_buf1
.p2align 2
_anim_buf1:         .space 3840, 0      // 80*24 halfwords -- primary buffer (fire intensity / water buf1 / GoL current)

.globl _anim_buf2
.p2align 2
_anim_buf2:         .space 3840, 0      // 80*24 halfwords -- secondary buffer (fire cooling / water buf2 / GoL next)

.globl _anim_snakes
.p2align 2
_anim_snakes:       .space 200, 0       // 50 snakes * 4 bytes each (x:byte, y:signed byte, size:byte, pad:byte)

// ============================================================================
.subsections_via_symbols
