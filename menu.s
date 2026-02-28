// ============================================================================
// yetris-asm: AArch64 Assembly Tetris Clone for macOS Apple Silicon
// File: asm/menu.s -- Main menu and help screen rendering + input handling
// Build: make asm
//
// Phase 6: Menu draws through subwindows (_win_menu_main, _win_menu_logo,
// _win_menu_items). Input stays on stdscr via _poll_input.
//
// The menu system presents:
//   - Title "Y E T R I S" in _win_menu_logo at (2, 14)
//   - 3 action items: Start Game, Help, Quit in _win_menu_items at (1,1), (3,1), (5,1)
//   - 5 settings in _win_menu_items at (7,1), (9,1), (11,1), (13,1), (15,1)
//     Wait -- menu_items window is only 13 rows tall (bordered). Drawable = 11 rows.
//     Items at rows 1,3,5 for actions. Settings at rows 7,9,11 max. Need to fit.
//   - Selected item highlighted with A_REVERSE
//   - LEFT/RIGHT adjusts settings values
//   - ENTER activates action items
//
// _menu_selection range: 0-7
//   0=Start Game, 1=Help, 2=Quit
//   3=Starting Level, 4=Ghost Piece, 5=Hold Piece, 6=Invisible, 7=Noise Rows
//
// Exports: _menu_frame, _help_frame
//
// Data dependencies (from asm/data.s):
//   _game_state, _menu_selection, _starting_level,
//   _opt_ghost, _opt_hold, _opt_invisible, _opt_noise,
//   _str_title, _str_on, _str_off, _str_help_title, _str_help_back,
//   _menu_items, _settings_labels, _help_lines,
//   _win_menu_main, _win_menu_logo, _win_menu_items
//
// ncurses functions used:
//   _stdscr (for input only), _werase, _wmove, _waddstr, _waddch,
//   _wattr_on, _wattr_off, _wnoutrefresh, _doupdate, _wgetch
// ============================================================================

.section __TEXT,__text,regular,pure_instructions

// ============================================================================
// _menu_frame: Render one frame of the main menu and handle menu input
// void _menu_frame(void)
//
// Drawing uses _win_menu_logo and _win_menu_items subwindows.
// Input polling uses stdscr via _poll_input (unchanged).
//
// Uses callee-saved registers:
//   x19 = _win_menu_items WINDOW* (for drawing) / stdscr GOT (for input section)
//   w20 = _menu_selection value
//   w21 = loop counter
//   x22 = pointer base for tables
//   w23 = temp for comparisons
//   x24 = _win_menu_logo WINDOW*
// ============================================================================
.globl _menu_frame
.p2align 2
_menu_frame:
    stp     x24, x23, [sp, #-48]!
    stp     x22, x21, [sp, #16]
    stp     x20, x19, [sp, #32]
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // === Step 1: werase + wnoutrefresh _win_menu_main ===
    adrp    x8, _win_menu_main@PAGE
    ldr     x0, [x8, _win_menu_main@PAGEOFF]
    bl      _werase

    // Draw animation into _win_menu_main background (Phase 10)
    adrp    x8, _win_menu_main@PAGE
    ldr     x0, [x8, _win_menu_main@PAGEOFF]
    bl      _anim_dispatch

    adrp    x8, _win_menu_main@PAGE
    ldr     x0, [x8, _win_menu_main@PAGEOFF]
    bl      _wnoutrefresh

    // === Step 2: Draw logo in _win_menu_logo ===
    adrp    x8, _win_menu_logo@PAGE
    ldr     x24, [x8, _win_menu_logo@PAGEOFF]

    // werase logo window
    mov     x0, x24
    bl      _werase

    // Draw 7-line ASCII logo centered in _win_menu_logo (80 wide)
    // Logo is ~40 chars wide. Center col = (80 - 40) / 2 = 20
    // Start at row 1 (leave row 0 blank for spacing)
    adrp    x22, _logo_lines@PAGE
    add     x22, x22, _logo_lines@PAGEOFF

    // Apply bold cyan for logo
    mov     x0, x24
    mov     w1, #0x0A00             // COLOR_PAIR(10)
    movk    w1, #0x0020, lsl #16   // | A_BOLD = hilite_hilite_text
    mov     x2, #0
    bl      _wattr_on

    mov     w21, #0                 // line counter (0-6)
Llogo_line_loop:
    cmp     w21, #7
    b.ge    Llogo_lines_done

    // wmove to (line + 1, 20)
    mov     x0, x24
    add     w1, w21, #1         // row = line + 1
    mov     w2, #20             // col = center
    bl      _wmove

    // waddstr the logo line
    uxtw    x8, w21
    ldr     x1, [x22, x8, lsl #3]  // _logo_lines[line]
    mov     x0, x24
    bl      _waddstr

    add     w21, w21, #1
    b       Llogo_line_loop

Llogo_lines_done:

    // Turn off bold cyan
    mov     x0, x24
    mov     w1, #0x0A00
    movk    w1, #0x0020, lsl #16
    mov     x2, #0
    bl      _wattr_off

    // wnoutrefresh logo
    mov     x0, x24
    bl      _wnoutrefresh

    // === Step 3: Draw menu items in _win_menu_items ===
    adrp    x8, _win_menu_items@PAGE
    ldr     x19, [x8, _win_menu_items@PAGEOFF]

    // werase menu items window
    mov     x0, x19
    bl      _werase

    // Draw fancy border for menu items window
    mov     x0, x19
    bl      _draw_fancy_border

    // Load current menu selection
    adrp    x8, _menu_selection@PAGE
    ldrb    w20, [x8, _menu_selection@PAGEOFF]

    // === Draw 3 menu action items at rows 1, 3, 5 within _win_menu_items ===
    // (bordered window, drawable area at (1,1) -- items at rows 1, 3, 5)
    adrp    x22, _menu_items@PAGE
    add     x22, x22, _menu_items@PAGEOFF

    mov     w21, #0                 // loop counter (item index 0-2)
Lmenu_item_loop:
    cmp     w21, #3
    b.ge    Lmenu_items_done

    // Calculate row = 1 + item_index * 2 (within bordered window)
    lsl     w1, w21, #1             // item_index * 2
    add     w1, w1, #1              // + 1

    // wmove to (row, 1) within menu_items window
    mov     x0, x19
    mov     w2, #1
    bl      _wmove

    // Check if this item is selected (w21 == w20)
    cmp     w21, w20
    b.eq    Lmenu_selected_item

    // === Non-selected: draw first char in bold cyan, rest in normal ===
    // Apply hilite_hilite_text (bold cyan) for first letter
    mov     x0, x19
    mov     w1, #0x0A00             // COLOR_PAIR(10)
    movk    w1, #0x0020, lsl #16   // | A_BOLD = hilite_hilite_text
    mov     x2, #0
    bl      _wattr_on

    // Load string pointer and draw first char via waddch
    uxtw    x8, w21
    ldr     x8, [x22, x8, lsl #3]  // _menu_items[item_index] -> full string ptr
    ldrb    w1, [x8]               // first character
    mov     x0, x19
    bl      _waddch

    // Turn off bold cyan
    mov     x0, x19
    mov     w1, #0x0A00
    movk    w1, #0x0020, lsl #16
    mov     x2, #0
    bl      _wattr_off

    // Draw rest of string (ptr + 1) in normal color
    uxtw    x8, w21
    ldr     x1, [x22, x8, lsl #3]
    add     x1, x1, #1             // skip first char
    mov     x0, x19
    bl      _waddstr

    b       Lmenu_next_item

Lmenu_selected_item:
    // === Selected: draw full string with A_REVERSE ===
    mov     x0, x19
    movz    w1, #0x4, lsl #16      // A_REVERSE = 0x40000
    mov     x2, #0
    bl      _wattr_on

    // Draw the full menu item string
    uxtw    x8, w21
    ldr     x1, [x22, x8, lsl #3]  // _menu_items[item_index]
    mov     x0, x19
    bl      _waddstr

    // Turn off A_REVERSE
    mov     x0, x19
    movz    w1, #0x4, lsl #16
    mov     x2, #0
    bl      _wattr_off

Lmenu_next_item:
    add     w21, w21, #1
    b       Lmenu_item_loop

Lmenu_items_done:

    // === Draw 5 settings starting at row 8 within menu_items window ===
    // Settings rows: 8, 9, 10, 11, 12 (compact -- no double-spacing to fit)
    // Actually, menu_items window is 13 rows tall, bordered = 11 drawable rows (1-11)
    // Actions at rows 1,3,5. Settings need rows 7,8,9,10,11.
    adrp    x22, _settings_labels@PAGE
    add     x22, x22, _settings_labels@PAGEOFF

    mov     w21, #0                 // settings loop counter (0-4)
Lsettings_loop:
    cmp     w21, #5
    b.ge    Lsettings_done

    // Calculate row = 7 + setting_index within menu_items window
    add     w1, w21, #7

    // wmove to (row, 1)
    mov     x0, x19
    mov     w2, #1
    bl      _wmove

    // Check if this setting is selected (w21 + 3 == w20)
    add     w23, w21, #3
    cmp     w23, w20
    b.ne    Lsetting_no_highlight

    // Apply A_REVERSE
    mov     x0, x19
    movz    w1, #0x4, lsl #16
    mov     x2, #0
    bl      _wattr_on

Lsetting_no_highlight:
    // Draw the setting label string
    uxtw    x8, w21
    ldr     x1, [x22, x8, lsl #3]  // _settings_labels[setting_index]
    mov     x0, x19
    bl      _waddstr

    // Draw the setting value based on setting_index
    cmp     w21, #0
    b.eq    Lsetting_level
    cmp     w21, #1
    b.eq    Lsetting_ghost
    cmp     w21, #2
    b.eq    Lsetting_hold
    cmp     w21, #3
    b.eq    Lsetting_invis
    b       Lsetting_noise

Lsetting_level:
    adrp    x8, _starting_level@PAGE
    ldr     w0, [x8, _starting_level@PAGEOFF]
    bl      Lmenu_draw_small_number
    b       Lsetting_value_done

Lsetting_ghost:
    adrp    x8, _opt_ghost@PAGE
    ldrb    w0, [x8, _opt_ghost@PAGEOFF]
    bl      Lmenu_draw_on_off
    b       Lsetting_value_done

Lsetting_hold:
    adrp    x8, _opt_hold@PAGE
    ldrb    w0, [x8, _opt_hold@PAGEOFF]
    bl      Lmenu_draw_on_off
    b       Lsetting_value_done

Lsetting_invis:
    adrp    x8, _opt_invisible@PAGE
    ldrb    w0, [x8, _opt_invisible@PAGEOFF]
    bl      Lmenu_draw_on_off
    b       Lsetting_value_done

Lsetting_noise:
    adrp    x8, _opt_noise@PAGE
    ldrb    w0, [x8, _opt_noise@PAGEOFF]
    bl      Lmenu_draw_small_number
    b       Lsetting_value_done

Lsetting_value_done:
    // Turn off highlight if it was on
    add     w23, w21, #3
    cmp     w23, w20
    b.ne    Lsetting_no_unhighlight

    mov     x0, x19
    movz    w1, #0x4, lsl #16
    mov     x2, #0
    bl      _wattr_off

Lsetting_no_unhighlight:
    add     w21, w21, #1
    b       Lsettings_loop

Lsettings_done:

    // === Draw arrow hints for settings ===
    cmp     w20, #3
    b.lt    Lno_arrows

    // Calculate row = 7 + (menu_selection - 3) within menu_items window
    sub     w8, w20, #3
    add     w1, w8, #7

    // Draw "<" at col 0 (on border, but visible)
    // Actually draw inside the window to avoid overwriting border
    // We don't have room at col 0 (that's the border). Skip arrows in bordered window.
    // Instead, the highlight (A_REVERSE) is the indicator. Skip arrows.
    b       Lno_arrows

Lno_arrows:

    // wnoutrefresh menu items
    mov     x0, x19
    bl      _wnoutrefresh

    // === doupdate to flush ===
    bl      _doupdate

    // === Poll input (on stdscr) ===
    bl      _poll_input
    mov     w21, w0                 // save key in w21

    // Check for no input
    cmn     w21, #1
    b.eq    Lmenu_input_done

    // === Dispatch menu input ===

    // KEY_UP (259): decrement _menu_selection (clamp to 0)
    mov     w8, #259
    cmp     w21, w8
    b.ne    Lmenu_check_down
    cbz     w20, Lmenu_input_done
    sub     w20, w20, #1
    b       Lmenu_store_selection

Lmenu_check_down:
    // KEY_DOWN (258): increment _menu_selection (clamp to 7)
    mov     w8, #258
    cmp     w21, w8
    b.ne    Lmenu_check_left
    cmp     w20, #7
    b.ge    Lmenu_input_done
    add     w20, w20, #1
    b       Lmenu_store_selection

Lmenu_check_left:
    mov     w8, #260
    cmp     w21, w8
    b.ne    Lmenu_check_right
    cmp     w20, #3
    b.lt    Lmenu_input_done
    b       Lmenu_adjust_left

Lmenu_check_right:
    mov     w8, #261
    cmp     w21, w8
    b.ne    Lmenu_check_enter
    cmp     w20, #3
    b.lt    Lmenu_input_done
    b       Lmenu_adjust_right

Lmenu_check_enter:
    cmp     w21, #10
    b.eq    Lmenu_activate
    mov     w8, #343
    cmp     w21, w8
    b.eq    Lmenu_activate
    b       Lmenu_check_quit

Lmenu_activate:
    cmp     w20, #3
    b.ge    Lmenu_input_done

    cmp     w20, #0
    b.eq    Lmenu_start_game
    cmp     w20, #1
    b.eq    Lmenu_show_help
    // w20 == 2: Quit
    mov     w8, #0xFF
    adrp    x9, _game_state@PAGE
    strb    w8, [x9, _game_state@PAGEOFF]
    b       Lmenu_input_done

Lmenu_start_game:
    mov     w8, #1
    adrp    x9, _game_state@PAGE
    strb    w8, [x9, _game_state@PAGEOFF]
    b       Lmenu_input_done

Lmenu_show_help:
    mov     w8, #2
    adrp    x9, _game_state@PAGE
    strb    w8, [x9, _game_state@PAGEOFF]
    b       Lmenu_input_done

Lmenu_check_quit:
    cmp     w21, #113
    b.eq    Lmenu_do_quit
    cmp     w21, #27
    b.ne    Lmenu_input_done
Lmenu_do_quit:
    mov     w8, #0xFF
    adrp    x9, _game_state@PAGE
    strb    w8, [x9, _game_state@PAGEOFF]
    b       Lmenu_input_done

Lmenu_store_selection:
    adrp    x8, _menu_selection@PAGE
    strb    w20, [x8, _menu_selection@PAGEOFF]
    b       Lmenu_input_done

    // === Setting adjustment: LEFT ===
Lmenu_adjust_left:
    cmp     w20, #3
    b.eq    Ladj_level_dec
    cmp     w20, #4
    b.eq    Ladj_ghost_off
    cmp     w20, #5
    b.eq    Ladj_hold_off
    cmp     w20, #6
    b.eq    Ladj_invis_off
    b       Ladj_noise_dec

Ladj_level_dec:
    adrp    x8, _starting_level@PAGE
    add     x8, x8, _starting_level@PAGEOFF
    ldr     w9, [x8]
    cmp     w9, #1
    b.le    Lmenu_input_done
    sub     w9, w9, #1
    str     w9, [x8]
    b       Lmenu_input_done

Ladj_ghost_off:
    adrp    x8, _opt_ghost@PAGE
    strb    wzr, [x8, _opt_ghost@PAGEOFF]
    b       Lmenu_input_done

Ladj_hold_off:
    adrp    x8, _opt_hold@PAGE
    strb    wzr, [x8, _opt_hold@PAGEOFF]
    b       Lmenu_input_done

Ladj_invis_off:
    adrp    x8, _opt_invisible@PAGE
    strb    wzr, [x8, _opt_invisible@PAGEOFF]
    b       Lmenu_input_done

Ladj_noise_dec:
    adrp    x8, _opt_noise@PAGE
    add     x8, x8, _opt_noise@PAGEOFF
    ldrb    w9, [x8]
    cbz     w9, Lmenu_input_done
    sub     w9, w9, #1
    strb    w9, [x8]
    b       Lmenu_input_done

    // === Setting adjustment: RIGHT ===
Lmenu_adjust_right:
    cmp     w20, #3
    b.eq    Ladj_level_inc
    cmp     w20, #4
    b.eq    Ladj_ghost_on
    cmp     w20, #5
    b.eq    Ladj_hold_on
    cmp     w20, #6
    b.eq    Ladj_invis_on
    b       Ladj_noise_inc

Ladj_level_inc:
    adrp    x8, _starting_level@PAGE
    add     x8, x8, _starting_level@PAGEOFF
    ldr     w9, [x8]
    cmp     w9, #22
    b.ge    Lmenu_input_done
    add     w9, w9, #1
    str     w9, [x8]
    b       Lmenu_input_done

Ladj_ghost_on:
    mov     w9, #1
    adrp    x8, _opt_ghost@PAGE
    strb    w9, [x8, _opt_ghost@PAGEOFF]
    b       Lmenu_input_done

Ladj_hold_on:
    mov     w9, #1
    adrp    x8, _opt_hold@PAGE
    strb    w9, [x8, _opt_hold@PAGEOFF]
    b       Lmenu_input_done

Ladj_invis_on:
    mov     w9, #1
    adrp    x8, _opt_invisible@PAGE
    strb    w9, [x8, _opt_invisible@PAGEOFF]
    b       Lmenu_input_done

Ladj_noise_inc:
    adrp    x8, _opt_noise@PAGE
    add     x8, x8, _opt_noise@PAGEOFF
    ldrb    w9, [x8]
    cmp     w9, #20
    b.ge    Lmenu_input_done
    add     w9, w9, #1
    strb    w9, [x8]
    b       Lmenu_input_done

Lmenu_input_done:
    // Epilogue
    ldp     x29, x30, [sp], #16
    ldp     x20, x19, [sp, #32]
    ldp     x22, x21, [sp, #16]
    ldp     x24, x23, [sp], #48
    ret

// ============================================================================
// Lmenu_draw_small_number: Draw a 1-2 digit number at cursor position
// w0 = value (0-99)
// x19 = WINDOW* (from caller -- _win_menu_items)
// ============================================================================
.p2align 2
Lmenu_draw_small_number:
    stp     x20, x19, [sp, #-16]!
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Recover x19 from stack (caller's _win_menu_items)
    ldr     x19, [sp, #16+8]       // x19 at sp+24 (stp x20,x19 then stp x29,x30)

    mov     w20, w0                 // save value

    cmp     w20, #10
    b.lt    Lsmall_single_digit

    // Two digits: tens then ones
    mov     w8, #10
    udiv    w9, w20, w8
    msub    w10, w9, w8, w20

    add     w1, w9, #0x30
    mov     x0, x19
    bl      _waddch

    add     w1, w10, #0x30
    mov     x0, x19
    bl      _waddch

    b       Lsmall_num_done

Lsmall_single_digit:
    add     w1, w20, #0x30
    mov     x0, x19
    bl      _waddch

    // Pad with space
    mov     x0, x19
    mov     w1, #0x20
    bl      _waddch

Lsmall_num_done:
    ldp     x29, x30, [sp], #16
    ldp     x20, x19, [sp], #16
    ret

// ============================================================================
// Lmenu_draw_on_off: Draw "ON " or "OFF" at cursor position
// w0 = flag (0 = OFF, nonzero = ON)
// x19 = WINDOW* (from caller -- _win_menu_items)
// ============================================================================
.p2align 2
Lmenu_draw_on_off:
    stp     x20, x19, [sp, #-16]!
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Recover x19 from stack
    ldr     x19, [sp, #16+8]

    cbz     w0, Ldraw_off

    // Draw "ON "
    mov     x0, x19
    adrp    x1, _str_on@PAGE
    add     x1, x1, _str_on@PAGEOFF
    bl      _waddstr
    b       Lon_off_done

Ldraw_off:
    mov     x0, x19
    adrp    x1, _str_off@PAGE
    add     x1, x1, _str_off@PAGEOFF
    bl      _waddstr

Lon_off_done:
    ldp     x29, x30, [sp], #16
    ldp     x20, x19, [sp], #16
    ret

// ============================================================================
// _help_frame: Render one frame of the help/controls screen
// void _help_frame(void)
//
// Draws help text on _win_menu_main (80x24) directly, since help is a
// full-screen reference display. Input stays on stdscr.
// ============================================================================
.globl _help_frame
.p2align 2
_help_frame:
    stp     x22, x21, [sp, #-32]!
    stp     x20, x19, [sp, #16]
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Load _win_menu_main WINDOW*
    adrp    x8, _win_menu_main@PAGE
    ldr     x19, [x8, _win_menu_main@PAGEOFF]

    // Clear window
    mov     x0, x19
    bl      _werase

    // === Draw title "-- CONTROLS --" at row 2, col 10 ===
    mov     x0, x19
    mov     w1, #2
    mov     w2, #10
    bl      _wmove

    mov     x0, x19
    adrp    x1, _str_help_title@PAGE
    add     x1, x1, _str_help_title@PAGEOFF
    bl      _waddstr

    // === Draw 9 help lines starting at row 5 ===
    adrp    x21, _help_lines@PAGE
    add     x21, x21, _help_lines@PAGEOFF

    mov     w20, #0
Lhelp_line_loop:
    cmp     w20, #9
    b.ge    Lhelp_lines_done

    add     w1, w20, #5
    mov     x0, x19
    mov     w2, #5
    bl      _wmove

    uxtw    x8, w20
    ldr     x1, [x21, x8, lsl #3]
    mov     x0, x19
    bl      _waddstr

    add     w20, w20, #1
    b       Lhelp_line_loop

Lhelp_lines_done:

    // === Draw "Press any key to return" at row 16, col 5 ===
    mov     x0, x19
    mov     w1, #16
    mov     w2, #5
    bl      _wmove

    mov     x0, x19
    adrp    x1, _str_help_back@PAGE
    add     x1, x1, _str_help_back@PAGEOFF
    bl      _waddstr

    // wnoutrefresh + doupdate
    mov     x0, x19
    bl      _wnoutrefresh
    bl      _doupdate

    // Poll input on stdscr -- if any key pressed, return to menu
    bl      _poll_input
    cmn     w0, #1
    b.eq    Lhelp_no_key

    // Key pressed: set _game_state = 0 (back to MENU)
    adrp    x8, _game_state@PAGE
    strb    wzr, [x8, _game_state@PAGEOFF]

Lhelp_no_key:
    // Epilogue
    ldp     x29, x30, [sp], #16
    ldp     x20, x19, [sp, #16]
    ldp     x22, x21, [sp], #32
    ret

// ============================================================================
.subsections_via_symbols
