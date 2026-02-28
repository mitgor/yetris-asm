// ============================================================================
// yetris-asm: AArch64 Assembly Tetris Clone for macOS Apple Silicon
// File: asm/render.s -- All rendering functions (board, piece, score panel,
//                       ghost piece, hold/next previews, stats, pause, colors,
//                       game over screen)
// Build: make asm
//
// Phase 6: All rendering uses named subwindows (WINDOW* pointers from data.s)
// instead of stdscr. Each draw function loads its target WINDOW* via
// adrp+ldr PAGE/PAGEOFF (local symbol, NOT GOT-indirect).
// _render_frame uses wnoutrefresh per window + doupdate once.
// wattr_on/wattr_off take 3 arguments: (win, attr, NULL).
//
// Subwindow layout (Phase 6):
//   Col: 0         12          34    44                 79
//   [leftmost 12w][middle_left 22w][mid_r 10w][rightmost 35w]
//   hold (4h)     board (22x22)    next (4h)  statistics (24h)
//   score (20h)
//
//   Board cell (row, col) -> _win_board (row+1, col*2+1)
//   Each board cell = 2 chars wide: "[]"
//
// Exports: _init_colors, _draw_board, _draw_piece, _draw_ghost_piece,
//          _draw_next_panel, _draw_hold_panel, _draw_stats_panel,
//          _draw_paused_overlay, _draw_score_panel, _draw_game_over,
//          _render_frame
//
// Data dependencies (from asm/data.s):
//   _board, _piece_type, _piece_rotation, _piece_x, _piece_y,
//   _piece_data, _color_pairs, _score, _level, _lines_cleared, _game_over,
//   _hold_piece_type, _can_hold, _is_paused, _bag, _bag_index,
//   _stats_pieces, _stats_piece_counts, _stats_singles, _stats_doubles,
//   _stats_triples, _stats_tetris,
//   _win_board, _win_hold, _win_score, _win_middle_right, _win_rightmost,
//   _win_pause, _win_main, _win_leftmost, _win_middle_left,
//   _game_start_time, _str_hold_title, _str_next_title, _str_stats_title,
//   _str_paused_title, _str_hiscore_label, _str_hiscore_none,
//   _str_timer_label, _str_version, _str_colon, _str_score_label,
//   _str_level_lbl, _str_lines_label, _piece_letters
// ============================================================================

.section __TEXT,__text,regular,pure_instructions

// ============================================================================
// _init_colors: Initialize ncurses color support and hide cursor
// void _init_colors(void)
// ============================================================================
.globl _init_colors
.p2align 2
_init_colors:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    bl      _start_color

    // Pair 1: O piece = Yellow on Black
    mov     w0, #1
    mov     w1, #3              // COLOR_YELLOW
    mov     w2, #0              // COLOR_BLACK
    bl      _init_pair

    // Pair 2: I piece = Cyan on Black
    mov     w0, #2
    mov     w1, #6              // COLOR_CYAN
    mov     w2, #0
    bl      _init_pair

    // Pair 3: L piece = White on Black
    mov     w0, #3
    mov     w1, #7              // COLOR_WHITE
    mov     w2, #0
    bl      _init_pair

    // Pair 4: J piece = Blue on Black
    mov     w0, #4
    mov     w1, #4              // COLOR_BLUE
    mov     w2, #0
    bl      _init_pair

    // Pair 5: S piece = Green on Black
    mov     w0, #5
    mov     w1, #2              // COLOR_GREEN
    mov     w2, #0
    bl      _init_pair

    // Pair 6: Z piece = Red on Black
    mov     w0, #6
    mov     w1, #1              // COLOR_RED
    mov     w2, #0
    bl      _init_pair

    // Pair 7: T piece = Magenta on Black
    mov     w0, #7
    mov     w1, #5              // COLOR_MAGENTA
    mov     w2, #0
    bl      _init_pair

    // Pair 8: dim_text = black on black (used with A_BOLD for bright black / dark gray)
    mov     w0, #8
    mov     w1, #0              // COLOR_BLACK
    mov     w2, #0              // COLOR_BLACK
    bl      _init_pair

    // Pair 9: dim_dim_text = black on black (without A_BOLD = near-invisible shadow)
    mov     w0, #9
    mov     w1, #0
    mov     w2, #0
    bl      _init_pair

    // Pair 10: hilite_text = cyan on black (labels, titles with A_BOLD)
    mov     w0, #10
    mov     w1, #6              // COLOR_CYAN
    mov     w2, #0
    bl      _init_pair

    // Pair 11: textbox = white on cyan (for future input prompts)
    mov     w0, #11
    mov     w1, #7              // COLOR_WHITE
    mov     w2, #6              // COLOR_CYAN
    bl      _init_pair

    // Hide cursor
    mov     w0, #0
    bl      _curs_set

    // Set solid black background on stdscr (all windows inherit)
    adrp    x8, _stdscr@GOTPAGE
    ldr     x8, [x8, _stdscr@GOTPAGEOFF]
    ldr     x0, [x8]               // x0 = stdscr WINDOW*
    mov     w1, #0x20               // ' ' (space character)
    bl      _wbkgd

    ldp     x29, x30, [sp], #16
    ret

// ============================================================================
// _draw_fancy_border: Draw C++-matching fancy border on WINDOW* in x0
// Uses ACS box-drawing chars from _acs_map with shadow color effect.
// Must be called AFTER _initscr (acs_map populated at ncurses init time).
// ============================================================================
.globl _draw_fancy_border
.p2align 2
_draw_fancy_border:
    stp     x20, x19, [sp, #-16]!
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    mov     x19, x0             // save WINDOW*

    // Load _acs_map base (extern from ncurses, GOT-indirect)
    adrp    x8, _acs_map@GOTPAGE
    ldr     x8, [x8, _acs_map@GOTPAGEOFF]

    // Precompute attributes:
    // dim_text_attr     = COLOR_PAIR(8) | A_BOLD = 0x00200800
    // dim_dim_text_attr = COLOR_PAIR(9)          = 0x00000900

    // ls = ACS_VLINE | dim_text_attr
    mov     w9, #0x78               // 'x' = ACS_VLINE key
    ldr     w1, [x8, w9, uxtw #2]  // w1 = acs_map['x']
    mov     w10, #0x0800
    movk    w10, #0x0020, lsl #16   // w10 = 0x00200800 (dim_text)
    orr     w1, w1, w10

    // rs = ACS_VLINE | dim_dim_text_attr
    ldr     w2, [x8, w9, uxtw #2]  // reuse w9=0x78
    mov     w10, #0x0900            // w10 = 0x00000900 (dim_dim_text)
    orr     w2, w2, w10

    // ts = ACS_HLINE | dim_text_attr
    mov     w9, #0x71               // 'q' = ACS_HLINE key
    ldr     w3, [x8, w9, uxtw #2]
    mov     w10, #0x0800
    movk    w10, #0x0020, lsl #16
    orr     w3, w3, w10

    // bs = ACS_HLINE | dim_dim_text_attr
    ldr     w4, [x8, w9, uxtw #2]  // reuse w9=0x71
    mov     w10, #0x0900
    orr     w4, w4, w10

    // tl = ACS_ULCORNER | dim_text_attr
    mov     w9, #0x6C               // 'l' = ACS_ULCORNER key
    ldr     w5, [x8, w9, uxtw #2]
    mov     w10, #0x0800
    movk    w10, #0x0020, lsl #16
    orr     w5, w5, w10

    // tr = ACS_URCORNER | dim_text_attr
    mov     w9, #0x6B               // 'k' = ACS_URCORNER key
    ldr     w6, [x8, w9, uxtw #2]
    mov     w10, #0x0800
    movk    w10, #0x0020, lsl #16
    orr     w6, w6, w10

    // bl = ACS_LLCORNER | dim_text_attr
    mov     w9, #0x6D               // 'm' = ACS_LLCORNER key
    ldr     w7, [x8, w9, uxtw #2]
    mov     w10, #0x0800
    movk    w10, #0x0020, lsl #16
    orr     w7, w7, w10

    // br = ACS_LRCORNER | dim_dim_text_attr (8th arg, goes on stack)
    mov     w9, #0x6A               // 'j' = ACS_LRCORNER key
    ldr     w10, [x8, w9, uxtw #2]
    mov     w11, #0x0900
    orr     w10, w10, w11
    sub     sp, sp, #16
    str     w10, [sp]               // 8th arg on stack

    // Call wborder(win, ls, rs, ts, bs, tl, tr, bl, br)
    mov     x0, x19
    bl      _wborder
    add     sp, sp, #16

    ldp     x29, x30, [sp], #16
    ldp     x20, x19, [sp], #16
    ret

// ============================================================================
// _draw_board: Draw borders and all locked blocks on the board
// void _draw_board(void)
//
// Uses _win_board WINDOW* (22x22, BORDER_NONE, fills middle_left container).
// Board cell (row, col) -> (row+1, col*2+1) within _win_board.
//
// Uses callee-saved registers:
//   x19 = _win_board WINDOW* pointer
//   x20 = board base address
//   w21 = row counter (0-19)
//   w22 = col counter (0-9)
//   w23 = cell value (preserved across calls)
// ============================================================================
.globl _draw_board
.p2align 2
_draw_board:
    stp     x24, x23, [sp, #-48]!
    stp     x22, x21, [sp, #16]
    stp     x20, x19, [sp, #32]
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Load _win_board WINDOW* (local symbol, not GOT)
    adrp    x8, _win_board@PAGE
    ldr     x19, [x8, _win_board@PAGEOFF]

    // Load board base address
    adrp    x20, _board@PAGE
    add     x20, x20, _board@PAGEOFF

    // Load _acs_map base for ACS border characters (GOT-indirect)
    adrp    x8, _acs_map@GOTPAGE
    ldr     x24, [x8, _acs_map@GOTPAGEOFF]

    // dim_text_attr = COLOR_PAIR(8) | A_BOLD = 0x00200800
    // Precompute ACS chars with dim_text attribute (uniform color, no shadow for board)

    // --- Draw top border at row 0 ---
    mov     x0, x19
    mov     w1, #0
    mov     w2, #0
    bl      _wmove

    // Draw ACS_ULCORNER | dim_text
    mov     w9, #0x6C
    ldr     w1, [x24, w9, uxtw #2]
    mov     w10, #0x0800
    movk    w10, #0x0020, lsl #16
    orr     w1, w1, w10
    mov     x0, x19
    bl      _waddch

    // Draw 20 ACS_HLINE | dim_text characters
    mov     w22, #0
Ltop_border_loop:
    cmp     w22, #20
    b.ge    Ltop_border_done
    mov     w9, #0x71
    ldr     w1, [x24, w9, uxtw #2]
    mov     w10, #0x0800
    movk    w10, #0x0020, lsl #16
    orr     w1, w1, w10
    mov     x0, x19
    bl      _waddch
    add     w22, w22, #1
    b       Ltop_border_loop
Ltop_border_done:

    // Draw ACS_URCORNER | dim_text
    mov     w9, #0x6B
    ldr     w1, [x24, w9, uxtw #2]
    mov     w10, #0x0800
    movk    w10, #0x0020, lsl #16
    orr     w1, w1, w10
    mov     x0, x19
    bl      _waddch

    // --- Draw board rows (0-19) ---
    mov     w21, #0             // row = 0
Ldraw_row_loop:
    cmp     w21, #20
    b.ge    Ldraw_rows_done

    // Draw left border ACS_VLINE | dim_text at (row+1, 0)
    mov     x0, x19
    add     w1, w21, #1         // y = row + 1
    mov     w2, #0              // x = 0
    bl      _wmove
    mov     w9, #0x78
    ldr     w1, [x24, w9, uxtw #2]
    mov     w10, #0x0800
    movk    w10, #0x0020, lsl #16
    orr     w1, w1, w10
    mov     x0, x19
    bl      _waddch

    // Draw each column (0-9)
    mov     w22, #0             // col = 0
Ldraw_col_loop:
    cmp     w22, #10
    b.ge    Ldraw_col_done

    // Load board[row*10 + col]
    mov     w8, #10
    mul     w8, w21, w8         // row * 10
    add     w8, w8, w22         // + col
    ldrb    w23, [x20, w8, uxtw]

    // Move cursor to (row+1, col*2+1)
    mov     x0, x19
    add     w1, w21, #1         // y = row + 1
    lsl     w2, w22, #1         // col * 2
    add     w2, w2, #1          // + 1 for left border
    bl      _wmove

    // Check if cell is empty
    cbz     w23, Ldraw_empty_cell

    // Check if cell is invisible marker (value 8)
    cmp     w23, #8
    b.eq    Ldraw_empty_cell

    // Check if cell is flash marker (value 9)
    cmp     w23, #9
    b.eq    Ldraw_flash_cell

    // Non-empty cell: set color pair, draw "[]", unset color
    mov     x0, x19
    lsl     w1, w23, #8         // COLOR_PAIR(cell_value)
    mov     x2, #0
    bl      _wattr_on

    // Draw '['
    mov     x0, x19
    mov     w1, #0x5B           // '['
    bl      _waddch

    // Draw ']'
    mov     x0, x19
    mov     w1, #0x5D           // ']'
    bl      _waddch

    // wattr_off
    mov     x0, x19
    lsl     w1, w23, #8
    mov     x2, #0
    bl      _wattr_off

    b       Ldraw_col_next

Ldraw_flash_cell:
    // Flash marker: draw '::' in white COLOR_PAIR(3)
    mov     x0, x19
    mov     w1, #0x0300             // COLOR_PAIR(3) = white
    mov     x2, #0
    bl      _wattr_on
    mov     x0, x19
    mov     w1, #0x3A               // ':'
    bl      _waddch
    mov     x0, x19
    mov     w1, #0x3A               // ':'
    bl      _waddch
    mov     x0, x19
    mov     w1, #0x0300
    mov     x2, #0
    bl      _wattr_off
    b       Ldraw_col_next

Ldraw_empty_cell:
    // Draw two spaces "  "
    mov     x0, x19
    mov     w1, #0x20           // ' '
    bl      _waddch
    mov     x0, x19
    mov     w1, #0x20           // ' '
    bl      _waddch

Ldraw_col_next:
    add     w22, w22, #1
    b       Ldraw_col_loop

Ldraw_col_done:
    // Draw right border ACS_VLINE | dim_text at (row+1, 21)
    mov     x0, x19
    add     w1, w21, #1         // y = row + 1
    mov     w2, #21             // x = 21
    bl      _wmove
    mov     w9, #0x78
    ldr     w1, [x24, w9, uxtw #2]
    mov     w10, #0x0800
    movk    w10, #0x0020, lsl #16
    orr     w1, w1, w10
    mov     x0, x19
    bl      _waddch

    add     w21, w21, #1        // row++
    b       Ldraw_row_loop

Ldraw_rows_done:
    // --- Draw bottom border at row 21 ---
    mov     x0, x19
    mov     w1, #21
    mov     w2, #0
    bl      _wmove

    // ACS_LLCORNER | dim_text
    mov     w9, #0x6D
    ldr     w1, [x24, w9, uxtw #2]
    mov     w10, #0x0800
    movk    w10, #0x0020, lsl #16
    orr     w1, w1, w10
    mov     x0, x19
    bl      _waddch

    // Draw 20 ACS_HLINE | dim_text
    mov     w22, #0
Lbottom_border_loop:
    cmp     w22, #20
    b.ge    Lbottom_border_done
    mov     w9, #0x71
    ldr     w1, [x24, w9, uxtw #2]
    mov     w10, #0x0800
    movk    w10, #0x0020, lsl #16
    orr     w1, w1, w10
    mov     x0, x19
    bl      _waddch
    add     w22, w22, #1
    b       Lbottom_border_loop
Lbottom_border_done:

    // ACS_LRCORNER | dim_text
    mov     w9, #0x6A
    ldr     w1, [x24, w9, uxtw #2]
    mov     w10, #0x0800
    movk    w10, #0x0020, lsl #16
    orr     w1, w1, w10
    mov     x0, x19
    bl      _waddch

    // Epilogue
    ldp     x29, x30, [sp], #16
    ldp     x20, x19, [sp, #32]
    ldp     x22, x21, [sp, #16]
    ldp     x24, x23, [sp], #48
    ret

// ============================================================================
// _draw_piece: Draw the current falling piece on top of the board
// void _draw_piece(void)
//
// Uses _win_board WINDOW* pointer. Coordinates unchanged since board fills
// its container at origin.
//
// Uses callee-saved registers:
//   x19 = _win_board WINDOW*
//   w20 = piece_type
//   w21 = piece_rotation
//   w22 = piece_x (signed)
//   w23 = piece_y (signed)
//   x24 = piece_data base address
//   w25 = color pair number
//   w26 = r (row in 5x5 grid)
//   w27 = c (col in 5x5 grid)
// ============================================================================
.globl _draw_piece
.p2align 2
_draw_piece:
    stp     x28, x27, [sp, #-80]!
    stp     x26, x25, [sp, #16]
    stp     x24, x23, [sp, #32]
    stp     x22, x21, [sp, #48]
    stp     x20, x19, [sp, #64]
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Load _win_board WINDOW*
    adrp    x8, _win_board@PAGE
    ldr     x19, [x8, _win_board@PAGEOFF]

    // Load piece state
    adrp    x8, _piece_type@PAGE
    ldrb    w20, [x8, _piece_type@PAGEOFF]

    adrp    x8, _piece_rotation@PAGE
    ldrb    w21, [x8, _piece_rotation@PAGEOFF]

    adrp    x8, _piece_x@PAGE
    ldrsh   w22, [x8, _piece_x@PAGEOFF]

    adrp    x8, _piece_y@PAGE
    ldrsh   w23, [x8, _piece_y@PAGEOFF]

    // Load piece_data base address
    adrp    x24, _piece_data@PAGE
    add     x24, x24, _piece_data@PAGEOFF

    // Load color pair: _color_pairs[piece_type]
    adrp    x8, _color_pairs@PAGE
    add     x8, x8, _color_pairs@PAGEOFF
    ldrb    w25, [x8, w20, uxtw]

    // Iterate over 5x5 grid
    mov     w26, #0             // r = 0
Lpiece_row_loop:
    cmp     w26, #5
    b.ge    Lpiece_done

    mov     w27, #0             // c = 0
Lpiece_col_loop:
    cmp     w27, #5
    b.ge    Lpiece_col_done

    // Compute piece_data index: type*100 + rotation*25 + r*5 + c
    mov     w8, #100
    mul     w8, w20, w8
    mov     w9, #25
    mul     w9, w21, w9
    add     w8, w8, w9
    mov     w9, #5
    mul     w9, w26, w9
    add     w8, w8, w9
    add     w8, w8, w27

    // Load cell value
    ldrb    w9, [x24, w8, uxtw]
    cbz     w9, Lpiece_skip

    // Compute screen coordinates
    // screen_y = piece_y + r + 1
    add     w10, w23, w26
    add     w10, w10, #1

    // screen_x = (piece_x + c) * 2 + 1
    add     w11, w22, w27
    lsl     w11, w11, #1
    add     w11, w11, #1

    // Bounds check: screen_y must be in [1, 20]
    cmp     w10, #1
    b.lt    Lpiece_skip
    cmp     w10, #20
    b.gt    Lpiece_skip

    // Bounds check: screen_x must be in [1, 20]
    cmp     w11, #1
    b.lt    Lpiece_skip
    cmp     w11, #20
    b.gt    Lpiece_skip

    // Set color
    mov     x0, x19
    lsl     w1, w25, #8
    mov     x2, #0
    bl      _wattr_on

    // Recompute screen coords (caller-saved regs clobbered by bl)
    add     w10, w23, w26
    add     w10, w10, #1
    add     w11, w22, w27
    lsl     w11, w11, #1
    add     w11, w11, #1

    // wmove
    mov     x0, x19
    mov     w1, w10
    mov     w2, w11
    bl      _wmove

    // Draw '['
    mov     x0, x19
    mov     w1, #0x5B
    bl      _waddch

    // Draw ']'
    mov     x0, x19
    mov     w1, #0x5D
    bl      _waddch

    // Unset color
    mov     x0, x19
    lsl     w1, w25, #8
    mov     x2, #0
    bl      _wattr_off

Lpiece_skip:
    add     w27, w27, #1
    b       Lpiece_col_loop

Lpiece_col_done:
    add     w26, w26, #1
    b       Lpiece_row_loop

Lpiece_done:
    ldp     x29, x30, [sp], #16
    ldp     x20, x19, [sp, #64]
    ldp     x22, x21, [sp, #48]
    ldp     x24, x23, [sp, #32]
    ldp     x26, x25, [sp, #16]
    ldp     x28, x27, [sp], #80
    ret

// ============================================================================
// _draw_ghost_piece: Draw the ghost piece (landing preview) with A_DIM
// void _draw_ghost_piece(void)
//
// Uses _win_board WINDOW*.
// ============================================================================
.globl _draw_ghost_piece
.p2align 2
_draw_ghost_piece:
    stp     x28, x27, [sp, #-80]!
    stp     x26, x25, [sp, #16]
    stp     x24, x23, [sp, #32]
    stp     x22, x21, [sp, #48]
    stp     x20, x19, [sp, #64]
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Get ghost Y position first
    bl      _compute_ghost_y
    mov     w23, w0                     // w23 = ghost_y

    // Load _win_board WINDOW*
    adrp    x8, _win_board@PAGE
    ldr     x19, [x8, _win_board@PAGEOFF]

    // Load piece state
    adrp    x8, _piece_type@PAGE
    ldrb    w20, [x8, _piece_type@PAGEOFF]

    adrp    x8, _piece_rotation@PAGE
    ldrb    w21, [x8, _piece_rotation@PAGEOFF]

    adrp    x8, _piece_x@PAGE
    ldrsh   w22, [x8, _piece_x@PAGEOFF]

    // Load piece_data base address
    adrp    x24, _piece_data@PAGE
    add     x24, x24, _piece_data@PAGEOFF

    // Load color pair
    adrp    x8, _color_pairs@PAGE
    add     x8, x8, _color_pairs@PAGEOFF
    ldrb    w25, [x8, w20, uxtw]

    // Iterate over 5x5 grid
    mov     w26, #0             // r = 0
Lghost_row_loop:
    cmp     w26, #5
    b.ge    Lghost_done

    mov     w27, #0             // c = 0
Lghost_col_loop:
    cmp     w27, #5
    b.ge    Lghost_col_done

    // Compute piece_data index
    mov     w8, #100
    mul     w8, w20, w8
    mov     w9, #25
    mul     w9, w21, w9
    add     w8, w8, w9
    mov     w9, #5
    mul     w9, w26, w9
    add     w8, w8, w9
    add     w8, w8, w27

    ldrb    w9, [x24, w8, uxtw]
    cbz     w9, Lghost_skip

    // Compute screen coordinates using ghost_y
    add     w10, w23, w26
    add     w10, w10, #1

    add     w11, w22, w27
    lsl     w11, w11, #1
    add     w11, w11, #1

    // Bounds check
    cmp     w10, #1
    b.lt    Lghost_skip
    cmp     w10, #20
    b.gt    Lghost_skip
    cmp     w11, #1
    b.lt    Lghost_skip
    cmp     w11, #20
    b.gt    Lghost_skip

    // Set color: COLOR_PAIR(n) | A_DIM
    lsl     w1, w25, #8
    movz    w9, #0x10, lsl #16      // A_DIM = 0x100000
    orr     w1, w1, w9
    mov     x0, x19
    mov     x2, #0
    bl      _wattr_on

    // Recompute screen coords
    add     w10, w23, w26
    add     w10, w10, #1
    add     w11, w22, w27
    lsl     w11, w11, #1
    add     w11, w11, #1

    mov     x0, x19
    mov     w1, w10
    mov     w2, w11
    bl      _wmove

    // Draw '['
    mov     x0, x19
    mov     w1, #0x5B
    bl      _waddch

    // Draw ']'
    mov     x0, x19
    mov     w1, #0x5D
    bl      _waddch

    // wattr_off
    lsl     w1, w25, #8
    movz    w9, #0x10, lsl #16
    orr     w1, w1, w9
    mov     x0, x19
    mov     x2, #0
    bl      _wattr_off

Lghost_skip:
    add     w27, w27, #1
    b       Lghost_col_loop

Lghost_col_done:
    add     w26, w26, #1
    b       Lghost_row_loop

Lghost_done:
    ldp     x29, x30, [sp], #16
    ldp     x20, x19, [sp, #64]
    ldp     x22, x21, [sp, #48]
    ldp     x24, x23, [sp, #32]
    ldp     x26, x25, [sp, #16]
    ldp     x28, x27, [sp], #80
    ret

// ============================================================================
// Ldraw_mini_piece: Internal helper -- draw a piece in a subwindow
// x19 = WINDOW* (must be set by caller before calling)
// w0 = piece_type, w1 = panel_row, w2 = panel_col
//
// Draws a piece's rotation-0 shape at the specified window-relative position.
// Used by next preview and hold preview panels.
// ============================================================================
.p2align 2
Ldraw_mini_piece:
    stp     x28, x27, [sp, #-80]!
    stp     x26, x25, [sp, #16]
    stp     x24, x23, [sp, #32]
    stp     x22, x21, [sp, #48]
    stp     x20, x19, [sp, #64]
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Save args (x19 already has WINDOW* from caller's context, saved on stack)
    mov     w20, w0             // piece_type
    mov     w21, w1             // panel_row
    mov     w22, w2             // panel_col

    // Reload _win_board is NOT what we want here -- caller sets x19 to the correct window
    // x19 was saved in stp above; we need it from the caller. Restore it from stack.
    // Actually stp x20,x19 saved caller's x19 at [sp+#64+8]. We need to re-load it.
    // The caller passes the window in x19 before the call. The stp at entry saves it.
    // But then we need to use it. Let's reload from the stack where we saved it.
    ldr     x19, [sp, #16+64+8]    // x19 saved at sp_outer+64+8 but stack moved...
    // Actually this is tricky with the frame pointer. Let me use a simpler approach:
    // Load the window from the stack. After the two stps:
    //   sp+0: x28,x27  sp+16: x26,x25  sp+32: x24,x23  sp+48: x22,x21  sp+64: x20,x19
    //   then stp x29,x30 at sp-16 (new sp)
    // So x19 is at sp_current+16+64+8 = sp+88
    // Actually: stp x29,x30,[sp,#-16]! moves sp down 16 first.
    // So from current sp: x29 at [sp], x30 at [sp+8],
    //   x20 at [sp+16+64], x19 at [sp+16+64+8] = [sp+88]
    ldr     x19, [sp, #88]

    // Load piece_data base
    adrp    x24, _piece_data@PAGE
    add     x24, x24, _piece_data@PAGEOFF

    // Load color pair
    adrp    x8, _color_pairs@PAGE
    add     x8, x8, _color_pairs@PAGEOFF
    ldrb    w25, [x8, w20, uxtw]

    // Iterate 5x5 grid (rotation 0 always)
    mov     w26, #0             // r = 0
Lmini_row_loop:
    cmp     w26, #5
    b.ge    Lmini_done

    mov     w27, #0             // c = 0
Lmini_col_loop:
    cmp     w27, #5
    b.ge    Lmini_col_done

    // piece_data[type*100 + 0*25 + r*5 + c]
    mov     w8, #100
    mul     w8, w20, w8
    mov     w9, #5
    mul     w9, w26, w9
    add     w8, w8, w9
    add     w8, w8, w27

    ldrb    w9, [x24, w8, uxtw]
    cbz     w9, Lmini_empty

    // Non-empty: draw colored "[]"
    // y = panel_row + r, x = panel_col + c*2
    add     w10, w21, w26       // panel_row + r
    lsl     w11, w27, #1        // c * 2
    add     w11, w22, w11       // panel_col + c*2

    // Set color
    mov     x0, x19
    lsl     w1, w25, #8
    mov     x2, #0
    bl      _wattr_on

    // Recompute coords
    add     w10, w21, w26
    lsl     w11, w27, #1
    add     w11, w22, w11

    // wmove
    mov     x0, x19
    mov     w1, w10
    mov     w2, w11
    bl      _wmove

    // Draw '['
    mov     x0, x19
    mov     w1, #0x5B
    bl      _waddch

    // Draw ']'
    mov     x0, x19
    mov     w1, #0x5D
    bl      _waddch

    // Unset color
    mov     x0, x19
    lsl     w1, w25, #8
    mov     x2, #0
    bl      _wattr_off

    b       Lmini_next

Lmini_empty:
    // Draw two spaces to clear
    add     w10, w21, w26
    lsl     w11, w27, #1
    add     w11, w22, w11

    mov     x0, x19
    mov     w1, w10
    mov     w2, w11
    bl      _wmove

    mov     x0, x19
    mov     w1, #0x20           // ' '
    bl      _waddch
    mov     x0, x19
    mov     w1, #0x20           // ' '
    bl      _waddch

Lmini_next:
    add     w27, w27, #1
    b       Lmini_col_loop

Lmini_col_done:
    add     w26, w26, #1
    b       Lmini_row_loop

Lmini_done:
    ldp     x29, x30, [sp], #16
    ldp     x20, x19, [sp, #64]
    ldp     x22, x21, [sp, #48]
    ldp     x24, x23, [sp, #32]
    ldp     x26, x25, [sp, #16]
    ldp     x28, x27, [sp], #80
    ret

// ============================================================================
// _draw_next_panel: Draw "Next" label and next piece preview
// void _draw_next_panel(void)
//
// Draws on _win_middle_right (10x4, bordered). Drawable area at (1,1) with
// dims (2,8). "Next" title at row 0, centered.
// ============================================================================
.globl _draw_next_panel
.p2align 2
_draw_next_panel:
    stp     x20, x19, [sp, #-16]!
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Load _win_middle_right WINDOW*
    adrp    x8, _win_middle_right@PAGE
    ldr     x19, [x8, _win_middle_right@PAGEOFF]

    // Draw fancy border
    mov     x0, x19
    bl      _draw_fancy_border

    // Draw "Next" title in bold cyan at row 0, col 3
    mov     x0, x19
    mov     w1, #0x0A00             // COLOR_PAIR(10)
    movk    w1, #0x0020, lsl #16   // | A_BOLD = hilite_hilite_text
    mov     x2, #0
    bl      _wattr_on
    mov     x0, x19
    mov     w1, #0              // row 0 (on border)
    mov     w2, #3              // col 3
    bl      _wmove
    mov     x0, x19
    adrp    x1, _str_next_title@PAGE
    add     x1, x1, _str_next_title@PAGEOFF
    bl      _waddstr
    mov     x0, x19
    mov     w1, #0x0A00
    movk    w1, #0x0020, lsl #16
    mov     x2, #0
    bl      _wattr_off

    // Load next piece type from bag: _bag[_bag_index]
    adrp    x8, _bag_index@PAGE
    add     x8, x8, _bag_index@PAGEOFF
    ldrb    w9, [x8]

    cmp     w9, #7
    b.lt    Lnext_have_piece
    mov     w0, #0                      // fallback type
    b       Lnext_draw_piece
Lnext_have_piece:
    adrp    x8, _bag@PAGE
    add     x8, x8, _bag@PAGEOFF
    ldrb    w0, [x8, w9, uxtw]         // w0 = next piece type
Lnext_draw_piece:
    // Draw mini piece at (1, 1) within bordered window
    // x19 is already set to _win_middle_right
    mov     w1, #0              // panel_row (offset within window for piece grid row 0)
    mov     w2, #0              // panel_col
    bl      Ldraw_mini_piece

    // wnoutrefresh
    adrp    x8, _win_middle_right@PAGE
    ldr     x0, [x8, _win_middle_right@PAGEOFF]
    bl      _wnoutrefresh

    ldp     x29, x30, [sp], #16
    ldp     x20, x19, [sp], #16
    ret

// ============================================================================
// _draw_hold_panel: Draw "Hold" label and held piece (or empty)
// void _draw_hold_panel(void)
//
// Draws on _win_hold (12x4, bordered). "Hold" title at row 0, centered.
// ============================================================================
.globl _draw_hold_panel
.p2align 2
_draw_hold_panel:
    stp     x22, x21, [sp, #-32]!
    stp     x20, x19, [sp, #16]
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Load _win_hold WINDOW*
    adrp    x8, _win_hold@PAGE
    ldr     x19, [x8, _win_hold@PAGEOFF]

    // Draw fancy border
    mov     x0, x19
    bl      _draw_fancy_border

    // Draw "Hold" title in bold cyan at row 0, col 4
    mov     x0, x19
    mov     w1, #0x0A00             // COLOR_PAIR(10)
    movk    w1, #0x0020, lsl #16   // | A_BOLD
    mov     x2, #0
    bl      _wattr_on
    mov     x0, x19
    mov     w1, #0
    mov     w2, #4
    bl      _wmove
    mov     x0, x19
    adrp    x1, _str_hold_title@PAGE
    add     x1, x1, _str_hold_title@PAGEOFF
    bl      _waddstr
    mov     x0, x19
    mov     w1, #0x0A00
    movk    w1, #0x0020, lsl #16
    mov     x2, #0
    bl      _wattr_off

    // Load _hold_piece_type
    adrp    x8, _hold_piece_type@PAGE
    ldrb    w20, [x8, _hold_piece_type@PAGEOFF]

    // Check if empty (0xFF)
    cmp     w20, #0xFF
    b.eq    Lhold_done

    // Hold has a piece: draw it within the window
    // x19 is _win_hold for Ldraw_mini_piece
    mov     w0, w20             // piece_type
    mov     w1, #0              // panel_row (piece grid row 0, maps inside border)
    mov     w2, #1              // panel_col (inside left border)
    bl      Ldraw_mini_piece

Lhold_done:
    // wnoutrefresh
    adrp    x8, _win_hold@PAGE
    ldr     x0, [x8, _win_hold@PAGEOFF]
    bl      _wnoutrefresh

    ldp     x29, x30, [sp], #16
    ldp     x20, x19, [sp, #16]
    ldp     x22, x21, [sp], #32
    ret

// ============================================================================
// _draw_stats_panel: Draw statistics panel in rightmost window
// void _draw_stats_panel(void)
//
// Draws on _win_rightmost (35x24, bordered). Drawable area at (1,1).
// Layout:
//   Row 0: border with "Statistics" title
//   Row 1-7: piece type letters + counts
//   Row 9-12: line clear counts (Single/Double/Triple/Tetris)
//   Row 14: "Timer" + MM:SS
//   Row 16: "yetris v1.2"
//
// Uses callee-saved registers:
//   x19 = _win_rightmost WINDOW*
//   w20 = loop counter / piece type
//   x21 = stats_piece_counts base
//   w22 = current count value
//   x23 = color_pairs base
//   w24 = color pair
// ============================================================================
.globl _draw_stats_panel
.p2align 2
_draw_stats_panel:
    stp     x26, x25, [sp, #-64]!
    stp     x24, x23, [sp, #16]
    stp     x22, x21, [sp, #32]
    stp     x20, x19, [sp, #48]
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Load _win_rightmost WINDOW*
    adrp    x8, _win_rightmost@PAGE
    ldr     x19, [x8, _win_rightmost@PAGEOFF]

    // Draw fancy border
    mov     x0, x19
    bl      _draw_fancy_border

    // Draw "Statistics" title in bold cyan at row 0, col 12
    mov     x0, x19
    mov     w1, #0x0A00             // COLOR_PAIR(10)
    movk    w1, #0x0020, lsl #16   // | A_BOLD
    mov     x2, #0
    bl      _wattr_on
    mov     x0, x19
    mov     w1, #0
    mov     w2, #12
    bl      _wmove
    mov     x0, x19
    adrp    x1, _str_stats_title@PAGE
    add     x1, x1, _str_stats_title@PAGEOFF
    bl      _waddstr
    mov     x0, x19
    mov     w1, #0x0A00
    movk    w1, #0x0020, lsl #16
    mov     x2, #0
    bl      _wattr_off

    // Load stats_piece_counts base
    adrp    x21, _stats_piece_counts@PAGE
    add     x21, x21, _stats_piece_counts@PAGEOFF

    // Load color_pairs base
    adrp    x23, _color_pairs@PAGE
    add     x23, x23, _color_pairs@PAGEOFF

    // Load piece_letters base
    adrp    x25, _piece_letters@PAGE
    add     x25, x25, _piece_letters@PAGEOFF

    // --- Part A: Per-piece-type counts (7 rows at rows 1-7) ---
    mov     w20, #0             // type = 0
Lstats_piece_loop:
    cmp     w20, #7
    b.ge    Lstats_line_clears

    // Compute row = 1 + type
    add     w10, w20, #1

    // Load color pair for this type
    ldrb    w24, [x23, w20, uxtw]

    // Set color
    mov     x0, x19
    lsl     w1, w24, #8
    mov     x2, #0
    bl      _wattr_on

    // wmove to (row, 1)
    add     w10, w20, #1
    mov     x0, x19
    mov     w1, w10
    mov     w2, #1
    bl      _wmove

    // Draw the piece type letter from _piece_letters table
    ldrb    w1, [x25, w20, uxtw]
    mov     x0, x19
    bl      _waddch

    // Unset color
    mov     x0, x19
    lsl     w1, w24, #8
    mov     x2, #0
    bl      _wattr_off

    // Load count for this type and draw at (row, 3)
    uxtw    x8, w20
    ldr     w0, [x21, x8, lsl #2]      // stats_piece_counts[type]
    add     w1, w20, #1                 // row
    mov     w2, #3                      // col
    bl      Ldraw_number

    add     w20, w20, #1
    b       Lstats_piece_loop

Lstats_line_clears:
    // --- Part B: Line clear type counts ---

    // Row 9: "Single" + count (label in cyan)
    mov     x0, x19
    mov     w1, #0x0A00             // COLOR_PAIR(10) = hilite_text
    mov     x2, #0
    bl      _wattr_on
    mov     x0, x19
    mov     w1, #9
    mov     w2, #1
    bl      _wmove
    mov     x0, x19
    adrp    x1, _str_single_label@PAGE
    add     x1, x1, _str_single_label@PAGEOFF
    bl      _waddstr
    mov     x0, x19
    mov     w1, #0x0A00
    mov     x2, #0
    bl      _wattr_off
    adrp    x8, _stats_singles@PAGE
    ldr     w0, [x8, _stats_singles@PAGEOFF]
    mov     w1, #9
    mov     w2, #8
    bl      Ldraw_number

    // Row 10: "Double" + count (label in cyan)
    mov     x0, x19
    mov     w1, #0x0A00
    mov     x2, #0
    bl      _wattr_on
    mov     x0, x19
    mov     w1, #10
    mov     w2, #1
    bl      _wmove
    mov     x0, x19
    adrp    x1, _str_double_label@PAGE
    add     x1, x1, _str_double_label@PAGEOFF
    bl      _waddstr
    mov     x0, x19
    mov     w1, #0x0A00
    mov     x2, #0
    bl      _wattr_off
    adrp    x8, _stats_doubles@PAGE
    ldr     w0, [x8, _stats_doubles@PAGEOFF]
    mov     w1, #10
    mov     w2, #8
    bl      Ldraw_number

    // Row 11: "Triple" + count (label in cyan)
    mov     x0, x19
    mov     w1, #0x0A00
    mov     x2, #0
    bl      _wattr_on
    mov     x0, x19
    mov     w1, #11
    mov     w2, #1
    bl      _wmove
    mov     x0, x19
    adrp    x1, _str_triple_label@PAGE
    add     x1, x1, _str_triple_label@PAGEOFF
    bl      _waddstr
    mov     x0, x19
    mov     w1, #0x0A00
    mov     x2, #0
    bl      _wattr_off
    adrp    x8, _stats_triples@PAGE
    ldr     w0, [x8, _stats_triples@PAGEOFF]
    mov     w1, #11
    mov     w2, #8
    bl      Ldraw_number

    // Row 12: "Tetris" + count (label in cyan)
    mov     x0, x19
    mov     w1, #0x0A00
    mov     x2, #0
    bl      _wattr_on
    mov     x0, x19
    mov     w1, #12
    mov     w2, #1
    bl      _wmove
    mov     x0, x19
    adrp    x1, _str_tetris_label@PAGE
    add     x1, x1, _str_tetris_label@PAGEOFF
    bl      _waddstr
    mov     x0, x19
    mov     w1, #0x0A00
    mov     x2, #0
    bl      _wattr_off
    adrp    x8, _stats_tetris@PAGE
    ldr     w0, [x8, _stats_tetris@PAGEOFF]
    mov     w1, #12
    mov     w2, #8
    bl      Ldraw_number

    // --- Part C: Timer ---
    // Row 14: "Timer" label (in cyan)
    mov     x0, x19
    mov     w1, #0x0A00
    mov     x2, #0
    bl      _wattr_on
    mov     x0, x19
    mov     w1, #14
    mov     w2, #1
    bl      _wmove
    mov     x0, x19
    adrp    x1, _str_timer_label@PAGE
    add     x1, x1, _str_timer_label@PAGEOFF
    bl      _waddstr
    mov     x0, x19
    mov     w1, #0x0A00
    mov     x2, #0
    bl      _wattr_off

    // Compute elapsed time: current_time - _game_start_time
    adrp    x8, _game_start_time@PAGE
    ldr     x20, [x8, _game_start_time@PAGEOFF]
    cbz     x20, Lstats_timer_zero      // game_start_time == 0, show 00:00

    bl      _get_time_ms
    sub     x0, x0, x20                 // elapsed_ms
    mov     x8, #1000
    udiv    x0, x0, x8                  // elapsed_s

    // Minutes = elapsed_s / 60
    mov     w8, #60
    udiv    w20, w0, w8                 // w20 = minutes
    msub    w22, w20, w8, w0            // w22 = seconds (elapsed_s - minutes*60)
    b       Lstats_draw_timer

Lstats_timer_zero:
    mov     w20, #0                     // minutes = 0
    mov     w22, #0                     // seconds = 0

Lstats_draw_timer:
    // Draw MM:SS at (14, 7) -- after "Timer "
    mov     x0, x19
    mov     w1, #14
    mov     w2, #7
    bl      _wmove

    // Draw minutes tens digit
    mov     w8, #10
    udiv    w9, w20, w8
    msub    w10, w9, w8, w20
    add     w1, w9, #0x30
    mov     x0, x19
    bl      _waddch
    // Minutes ones
    add     w1, w10, #0x30
    mov     x0, x19
    bl      _waddch
    // Colon
    mov     x0, x19
    mov     w1, #0x3A           // ':'
    bl      _waddch
    // Seconds tens digit
    mov     w8, #10
    udiv    w9, w22, w8
    msub    w10, w9, w8, w22
    add     w1, w9, #0x30
    mov     x0, x19
    bl      _waddch
    // Seconds ones
    add     w1, w10, #0x30
    mov     x0, x19
    bl      _waddch

    // --- Part D: Version string ---
    // Row 16: "yetris v1.2"
    mov     x0, x19
    mov     w1, #16
    mov     w2, #1
    bl      _wmove
    mov     x0, x19
    adrp    x1, _str_version@PAGE
    add     x1, x1, _str_version@PAGEOFF
    bl      _waddstr

    // wnoutrefresh
    adrp    x8, _win_rightmost@PAGE
    ldr     x0, [x8, _win_rightmost@PAGEOFF]
    bl      _wnoutrefresh

    // Epilogue
    ldp     x29, x30, [sp], #16
    ldp     x20, x19, [sp, #48]
    ldp     x22, x21, [sp, #32]
    ldp     x24, x23, [sp, #16]
    ldp     x26, x25, [sp], #64
    ret

// ============================================================================
// _draw_paused_overlay: Draw pause overlay in _win_pause window
// void _draw_paused_overlay(void)
//
// Draws on _win_pause (40x6, bordered). "Paused" title at border.
// Shows 3 selectable items: Resume, Quit to Main Menu, Quit Game.
// Selected item highlighted with A_REVERSE based on _pause_selection.
// ============================================================================
.globl _draw_paused_overlay
.p2align 2
_draw_paused_overlay:
    stp     x20, x19, [sp, #-16]!
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Load _win_pause WINDOW*
    adrp    x8, _win_pause@PAGE
    ldr     x19, [x8, _win_pause@PAGEOFF]

    // Draw fancy border
    mov     x0, x19
    bl      _draw_fancy_border

    // Draw "Paused" title in bold cyan at row 0
    mov     x0, x19
    mov     w1, #0x0A00             // COLOR_PAIR(10)
    movk    w1, #0x0020, lsl #16   // | A_BOLD
    mov     x2, #0
    bl      _wattr_on
    mov     x0, x19
    mov     w1, #0
    mov     w2, #17             // centered in 40-col window
    bl      _wmove
    mov     x0, x19
    adrp    x1, _str_paused_title@PAGE
    add     x1, x1, _str_paused_title@PAGEOFF
    bl      _waddstr
    mov     x0, x19
    mov     w1, #0x0A00
    movk    w1, #0x0020, lsl #16
    mov     x2, #0
    bl      _wattr_off

    // Load _pause_selection into w20
    adrp    x8, _pause_selection@PAGE
    ldrb    w20, [x8, _pause_selection@PAGEOFF]

    // === Draw "Resume" at row 2, centered ===
    // Check if selected (w20 == 0)
    cmp     w20, #0
    b.ne    Lpause_item0_no_hl

    // Apply A_REVERSE for selected item
    mov     x0, x19
    movz    w1, #0x4, lsl #16      // A_REVERSE = 0x00040000
    mov     x2, #0
    bl      _wattr_on

Lpause_item0_no_hl:
    mov     x0, x19
    mov     w1, #2
    mov     w2, #17                 // center "Resume" (6 chars) in 38 cols
    bl      _wmove
    mov     x0, x19
    adrp    x1, _str_pause_resume@PAGE
    add     x1, x1, _str_pause_resume@PAGEOFF
    bl      _waddstr

    cmp     w20, #0
    b.ne    Lpause_item0_no_unhl
    mov     x0, x19
    movz    w1, #0x4, lsl #16
    mov     x2, #0
    bl      _wattr_off
Lpause_item0_no_unhl:

    // === Draw "Quit to Main Menu" at row 3, centered ===
    cmp     w20, #1
    b.ne    Lpause_item1_no_hl

    mov     x0, x19
    movz    w1, #0x4, lsl #16      // A_REVERSE
    mov     x2, #0
    bl      _wattr_on

Lpause_item1_no_hl:
    mov     x0, x19
    mov     w1, #3
    mov     w2, #11                 // center "Quit to Main Menu" (17 chars) in 38 cols
    bl      _wmove
    mov     x0, x19
    adrp    x1, _str_pause_quit_menu@PAGE
    add     x1, x1, _str_pause_quit_menu@PAGEOFF
    bl      _waddstr

    cmp     w20, #1
    b.ne    Lpause_item1_no_unhl
    mov     x0, x19
    movz    w1, #0x4, lsl #16
    mov     x2, #0
    bl      _wattr_off
Lpause_item1_no_unhl:

    // === Draw "Quit Game" at row 4, centered ===
    cmp     w20, #2
    b.ne    Lpause_item2_no_hl

    mov     x0, x19
    movz    w1, #0x4, lsl #16      // A_REVERSE
    mov     x2, #0
    bl      _wattr_on

Lpause_item2_no_hl:
    mov     x0, x19
    mov     w1, #4
    mov     w2, #15                 // center "Quit Game" (9 chars) in 38 cols
    bl      _wmove
    mov     x0, x19
    adrp    x1, _str_pause_quit_game@PAGE
    add     x1, x1, _str_pause_quit_game@PAGEOFF
    bl      _waddstr

    cmp     w20, #2
    b.ne    Lpause_item2_no_unhl
    mov     x0, x19
    movz    w1, #0x4, lsl #16
    mov     x2, #0
    bl      _wattr_off
Lpause_item2_no_unhl:

    // wnoutrefresh
    adrp    x8, _win_pause@PAGE
    ldr     x0, [x8, _win_pause@PAGEOFF]
    bl      _wnoutrefresh

    ldp     x29, x30, [sp], #16
    ldp     x20, x19, [sp], #16
    ret

// ============================================================================
// _draw_score_panel: Draw score, level, and lines display
// void _draw_score_panel(void)
//
// Draws on _win_score (12x20, bordered). Drawable area at (1,1).
// Layout within bordered window:
//   Row 0: border
//   Row 1: "Hi-Score"  Row 2: "(none)"
//   Row 4: "Score"     Row 5: value
//   Row 7: "Level"     Row 8: value
//   Row 10: "Lines"    Row 11: value
// ============================================================================
.globl _draw_score_panel
.p2align 2
_draw_score_panel:
    stp     x22, x21, [sp, #-32]!
    stp     x20, x19, [sp, #16]
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Load _win_score WINDOW*
    adrp    x8, _win_score@PAGE
    ldr     x19, [x8, _win_score@PAGEOFF]

    // Draw fancy border
    mov     x0, x19
    bl      _draw_fancy_border

    // === Draw "Hi-Score" at (1, 1) in cyan ===
    mov     x0, x19
    mov     w1, #0x0A00             // COLOR_PAIR(10) = hilite_text
    mov     x2, #0
    bl      _wattr_on
    mov     x0, x19
    mov     w1, #1
    mov     w2, #1
    bl      _wmove
    mov     x0, x19
    adrp    x1, _str_hiscore_label@PAGE
    add     x1, x1, _str_hiscore_label@PAGEOFF
    bl      _waddstr
    mov     x0, x19
    mov     w1, #0x0A00
    mov     x2, #0
    bl      _wattr_off

    // === Draw hi-score value or "(none)" at (2, 1) ===
    adrp    x8, _hiscore@PAGE
    ldr     w20, [x8, _hiscore@PAGEOFF]
    cbnz    w20, Ldraw_hiscore_value

    // hiscore == 0: show "(none)"
    mov     x0, x19
    mov     w1, #2
    mov     w2, #1
    bl      _wmove
    mov     x0, x19
    adrp    x1, _str_hiscore_none@PAGE
    add     x1, x1, _str_hiscore_none@PAGEOFF
    bl      _waddstr
    b       Ldraw_hiscore_done

Ldraw_hiscore_value:
    // hiscore > 0: show numeric value (right-aligned in 8-char field)
    mov     w0, w20                    // value = _hiscore
    mov     w1, #2                     // row = 2
    mov     w2, #1                     // col = 1
    bl      Ldraw_number               // uses x19 = WINDOW* (already set)

Ldraw_hiscore_done:

    // === Draw "Score" at (4, 1) in cyan ===
    mov     x0, x19
    mov     w1, #0x0A00
    mov     x2, #0
    bl      _wattr_on
    mov     x0, x19
    mov     w1, #4
    mov     w2, #1
    bl      _wmove
    mov     x0, x19
    adrp    x1, _str_score_label@PAGE
    add     x1, x1, _str_score_label@PAGEOFF
    bl      _waddstr
    mov     x0, x19
    mov     w1, #0x0A00
    mov     x2, #0
    bl      _wattr_off

    // === Draw score value at (5, 1) ===
    adrp    x8, _score@PAGE
    ldr     w0, [x8, _score@PAGEOFF]
    mov     w1, #5
    mov     w2, #1
    bl      Ldraw_number

    // === Draw "Level" at (7, 1) in cyan ===
    mov     x0, x19
    mov     w1, #0x0A00
    mov     x2, #0
    bl      _wattr_on
    mov     x0, x19
    mov     w1, #7
    mov     w2, #1
    bl      _wmove
    mov     x0, x19
    adrp    x1, _str_level_lbl@PAGE
    add     x1, x1, _str_level_lbl@PAGEOFF
    bl      _waddstr
    mov     x0, x19
    mov     w1, #0x0A00
    mov     x2, #0
    bl      _wattr_off

    // === Draw level value at (8, 1) ===
    adrp    x8, _level@PAGE
    ldr     w0, [x8, _level@PAGEOFF]
    mov     w1, #8
    mov     w2, #1
    bl      Ldraw_number

    // === Draw "Lines" at (10, 1) in cyan ===
    mov     x0, x19
    mov     w1, #0x0A00
    mov     x2, #0
    bl      _wattr_on
    mov     x0, x19
    mov     w1, #10
    mov     w2, #1
    bl      _wmove
    mov     x0, x19
    adrp    x1, _str_lines_label@PAGE
    add     x1, x1, _str_lines_label@PAGEOFF
    bl      _waddstr
    mov     x0, x19
    mov     w1, #0x0A00
    mov     x2, #0
    bl      _wattr_off

    // === Draw lines_cleared value at (11, 1) ===
    adrp    x8, _lines_cleared@PAGE
    ldr     w0, [x8, _lines_cleared@PAGEOFF]
    mov     w1, #11
    mov     w2, #1
    bl      Ldraw_number

    // wnoutrefresh
    adrp    x8, _win_score@PAGE
    ldr     x0, [x8, _win_score@PAGEOFF]
    bl      _wnoutrefresh

    ldp     x29, x30, [sp], #16
    ldp     x20, x19, [sp, #16]
    ldp     x22, x21, [sp], #32
    ret

// ============================================================================
// Ldraw_number: Internal helper -- draw an unsigned integer at (row, col)
// w0 = value, w1 = row, w2 = col
//
// Uses x19 = WINDOW* (must be set by caller)
// ============================================================================
.p2align 2
Ldraw_number:
    stp     x24, x23, [sp, #-48]!
    stp     x22, x21, [sp, #16]
    stp     x20, x19, [sp, #32]
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Reload x19 from stack (caller saved it, we need to preserve the WINDOW*)
    ldr     x19, [sp, #16+32+8]    // x19 at sp+56 after the stp x29,x30

    mov     w20, w1             // save row
    mov     w21, w2             // save col
    mov     w8, w0              // value

    // Allocate 16 bytes on stack for digit buffer
    sub     sp, sp, #16

    // Extract digits right-to-left into buffer
    mov     w22, #0             // digit count = 0
    mov     w10, #10

    // Handle zero specially
    cbnz    w8, Lextract_digits
    mov     w9, #0x30           // '0'
    strb    w9, [sp]
    mov     w22, #1
    b       Ldigits_done

Lextract_digits:
    cbz     w8, Ldigits_done
    udiv    w9, w8, w10
    msub    w11, w9, w10, w8
    add     w11, w11, #0x30
    strb    w11, [sp, w22, uxtw]
    add     w22, w22, #1
    mov     w8, w9
    b       Lextract_digits

Ldigits_done:
    // Move cursor to start position
    mov     x0, x19
    mov     w1, w20
    mov     w2, w21
    bl      _wmove

    // Draw leading spaces (8 - digit_count)
    mov     w23, #8
    sub     w23, w23, w22
    mov     w24, #0
Ldraw_spaces:
    cmp     w24, w23
    b.ge    Ldraw_digits_start
    mov     x0, x19
    mov     w1, #0x20           // ' '
    bl      _waddch
    add     w24, w24, #1
    b       Ldraw_spaces

Ldraw_digits_start:
    sub     w24, w22, #1

Ldraw_digits_loop:
    cmp     w24, #0
    b.lt    Ldraw_number_done
    ldrb    w9, [sp, w24, uxtw]
    mov     x0, x19
    mov     w1, w9
    bl      _waddch
    sub     w24, w24, #1
    b       Ldraw_digits_loop

Ldraw_number_done:
    add     sp, sp, #16
    ldp     x29, x30, [sp], #16
    ldp     x20, x19, [sp, #32]
    ldp     x22, x21, [sp, #16]
    ldp     x24, x23, [sp], #48
    ret

// ============================================================================
// _draw_game_over: Draw "GAME OVER" text on the board window
// void _draw_game_over(void)
//
// Draws on _win_board at centered positions.
// ============================================================================
.globl _draw_game_over
.p2align 2
_draw_game_over:
    stp     x20, x19, [sp, #-16]!
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Load _win_board WINDOW*
    adrp    x8, _win_board@PAGE
    ldr     x19, [x8, _win_board@PAGEOFF]

    // Apply A_BOLD | A_REVERSE for "GAME OVER" emphasis
    mov     x0, x19
    movz    w1, #0x24, lsl #16     // A_REVERSE | A_BOLD = 0x00240000
    mov     x2, #0
    bl      _wattr_on

    // Draw "GAME OVER" at (10, 6) within board
    mov     x0, x19
    mov     w1, #10
    mov     w2, #6
    bl      _wmove
    mov     x0, x19
    adrp    x1, _str_game_over@PAGE
    add     x1, x1, _str_game_over@PAGEOFF
    bl      _waddstr

    // Turn off bold+reverse
    mov     x0, x19
    movz    w1, #0x24, lsl #16     // A_REVERSE | A_BOLD = 0x00240000
    mov     x2, #0
    bl      _wattr_off

    // Draw "Press q to quit" at (12, 3) in normal text
    mov     x0, x19
    mov     w1, #12
    mov     w2, #3
    bl      _wmove
    mov     x0, x19
    adrp    x1, _str_press_q_quit@PAGE
    add     x1, x1, _str_press_q_quit@PAGEOFF
    bl      _waddstr

    ldp     x29, x30, [sp], #16
    ldp     x20, x19, [sp], #16
    ret

// ============================================================================
// _render_frame: Orchestrate a complete frame render using subwindow protocol
// void _render_frame(void)
//
// Phase 6 rendering order:
//   1. werase + wnoutrefresh all container windows (parent before child)
//   2. Draw content into leaf windows (each handles its own wnoutrefresh)
//   3. Draw active piece/ghost on board
//   4. Final wnoutrefresh for board (after piece drawn on top)
//   5. doupdate() to flush all changes
// ============================================================================
.globl _render_frame
.p2align 2
_render_frame:
    stp     x20, x19, [sp, #-16]!
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // === Step 1: Clear + wnoutrefresh all container windows ===

    // _win_main
    adrp    x8, _win_main@PAGE
    ldr     x0, [x8, _win_main@PAGEOFF]
    bl      _werase

    // Draw animation into _win_main background (Phase 10)
    adrp    x8, _win_main@PAGE
    ldr     x0, [x8, _win_main@PAGEOFF]
    bl      _anim_dispatch

    adrp    x8, _win_main@PAGE
    ldr     x0, [x8, _win_main@PAGEOFF]
    bl      _wnoutrefresh

    // _win_leftmost
    adrp    x8, _win_leftmost@PAGE
    ldr     x0, [x8, _win_leftmost@PAGEOFF]
    bl      _werase
    adrp    x8, _win_leftmost@PAGE
    ldr     x0, [x8, _win_leftmost@PAGEOFF]
    bl      _wnoutrefresh

    // _win_middle_left
    adrp    x8, _win_middle_left@PAGE
    ldr     x0, [x8, _win_middle_left@PAGEOFF]
    bl      _werase
    adrp    x8, _win_middle_left@PAGE
    ldr     x0, [x8, _win_middle_left@PAGEOFF]
    bl      _wnoutrefresh

    // _win_middle_right (also a container for next -- but it IS the leaf; still clear it)
    // Actually middle_right IS the leaf window, no child under it. Skip container erase for it.
    // Same for rightmost -- it IS the leaf. They get erased in their draw functions via wborder.

    // === Step 2: Draw content into leaf windows ===

    // Draw board (into _win_board)
    bl      _draw_board

    // Check game_over flag
    adrp    x8, _game_over@PAGE
    ldrb    w9, [x8, _game_over@PAGEOFF]
    cbnz    w9, Lrender_panels          // game over: skip pieces

    // Check if paused
    adrp    x8, _is_paused@PAGE
    ldrb    w9, [x8, _is_paused@PAGEOFF]
    cbnz    w9, Lrender_paused          // paused: show overlay

    // Game is running: draw ghost then active piece
    adrp    x8, _opt_ghost@PAGE
    ldrb    w8, [x8, _opt_ghost@PAGEOFF]
    cbz     w8, Lskip_ghost_draw
    bl      _draw_ghost_piece
Lskip_ghost_draw:
    bl      _draw_piece
    b       Lrender_panels

Lrender_paused:
    bl      _draw_paused_overlay

Lrender_panels:
    // Draw all panels
    bl      _draw_score_panel
    bl      _draw_next_panel
    bl      _draw_hold_panel
    bl      _draw_stats_panel

    // wnoutrefresh for board (after ghost+piece drawn on top)
    adrp    x8, _win_board@PAGE
    ldr     x0, [x8, _win_board@PAGEOFF]
    bl      _wnoutrefresh

    // Check game_over for overlay
    adrp    x8, _game_over@PAGE
    ldrb    w9, [x8, _game_over@PAGEOFF]
    cbz     w9, Lrender_flush

    bl      _draw_game_over

    // wnoutrefresh board again after game_over overlay
    adrp    x8, _win_board@PAGE
    ldr     x0, [x8, _win_board@PAGEOFF]
    bl      _wnoutrefresh

Lrender_flush:
    // Single terminal flush
    bl      _doupdate

    ldp     x29, x30, [sp], #16
    ldp     x20, x19, [sp], #16
    ret

// ============================================================================
.subsections_via_symbols
