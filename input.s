// ============================================================================
// yetris-asm: AArch64 Assembly Tetris Clone for macOS Apple Silicon
// File: asm/input.s -- Input initialization and key dispatch
// Build: make asm
//
// Non-blocking keyboard input using ncurses keypad + wtimeout + wgetch.
// Arrow keys are decoded by ncurses when keypad(stdscr, TRUE) is enabled.
//
// Key mapping:
//   KEY_LEFT  (260) -> _try_move(-1, 0)   move left
//   KEY_RIGHT (261) -> _try_move(+1, 0)   move right
//   KEY_DOWN  (258) -> _soft_drop()        soft drop
//   KEY_UP    (259) -> _try_rotate(1)      rotate CW
//   Space     (32)  -> _hard_drop()        hard drop
//   'z'       (122) -> _try_rotate(3)      rotate CCW (3 = -1 mod 4)
//   'q'       (113) -> set _game_over = 1  quit game
//   ESC       (27)  -> set _game_over = 1  quit game
//
// Exports: _init_input, _poll_input, _handle_input
//
// Cross-file dependencies:
//   From asm/piece.s (plan 02): _try_move, _try_rotate, _hard_drop, _soft_drop
//   From asm/data.s (plan 01):  _game_over
//   From ncurses (dylib):       _stdscr, _keypad, _wtimeout, _noecho,
//                                _cbreak, _wgetch
// ============================================================================

.section __TEXT,__text,regular,pure_instructions

// ============================================================================
// _init_input: Configure ncurses for non-blocking game input
// void _init_input(void)
//
// 1. keypad(stdscr, TRUE) -- enable arrow key decoding
// 2. wtimeout(stdscr, 16) -- 16ms non-blocking timeout (~60fps)
// 3. noecho() -- suppress key echo (safe to re-call)
// 4. cbreak() -- char-at-a-time input (safe to re-call)
// ============================================================================
.globl _init_input
.p2align 2
_init_input:
    stp     x20, x19, [sp, #-16]!
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Load stdscr via GOT-indirect access
    adrp    x19, _stdscr@GOTPAGE
    ldr     x19, [x19, _stdscr@GOTPAGEOFF]

    // keypad(stdscr, TRUE) -- enable arrow key decoding
    // Without this, arrow keys produce escape sequences instead of KEY_LEFT etc.
    ldr     x0, [x19]          // WINDOW* stdscr
    mov     w1, #1              // TRUE
    bl      _keypad

    // wtimeout(stdscr, 16) -- 16ms non-blocking timeout for ~60fps polling
    ldr     x0, [x19]
    mov     w1, #16
    bl      _wtimeout

    // noecho() -- suppress key echo (already called in main.s, safe to re-call)
    bl      _noecho

    // cbreak() -- character-at-a-time input (already called in main.s, safe to re-call)
    bl      _cbreak

    ldp     x29, x30, [sp], #16
    ldp     x20, x19, [sp], #16
    ret

// ============================================================================
// _poll_input: Read a key from ncurses (non-blocking)
// int _poll_input(void) -> w0 = key code (or -1/ERR if no input)
//
// Simple wrapper around wgetch(stdscr).
// ============================================================================
.globl _poll_input
.p2align 2
_poll_input:
    stp     x20, x19, [sp, #-16]!
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Load stdscr via GOT
    adrp    x19, _stdscr@GOTPAGE
    ldr     x19, [x19, _stdscr@GOTPAGEOFF]

    // wgetch(stdscr) -> key code in w0 (or ERR=-1 if no input within timeout)
    ldr     x0, [x19]
    bl      _wgetch

    // Return value already in w0
    ldp     x29, x30, [sp], #16
    ldp     x20, x19, [sp], #16
    ret

// ============================================================================
// _user_soft_drop: User-initiated soft drop with scoring
// void _user_soft_drop(void) -> w0=1 moved, w0=0 locked
//
// Wrapper around _try_move that awards 1 point per cell dropped.
// Only called from KEY_DOWN in input handler. Gravity calls _soft_drop directly.
// ============================================================================
.globl _user_soft_drop
.p2align 2
_user_soft_drop:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Try to move down
    mov     w0, #0                  // dx = 0
    mov     w1, #1                  // dy = +1
    bl      _try_move

    cbz     w0, Lusd_blocked        // blocked -> lock and spawn

    // Moved successfully: award 1 point
    adrp    x8, _score@PAGE
    add     x8, x8, _score@PAGEOFF
    ldr     w9, [x8]
    add     w9, w9, #1
    str     w9, [x8]

    mov     w0, #1                  // return 1 (moved)
    b       Lusd_epilogue

Lusd_blocked:
    // Blocked: lock (may start flash)
    bl      _lock_piece             // w0 = lines cleared count
    cbnz    w0, Lusd_flash_started
    bl      _spawn_piece
Lusd_flash_started:

    mov     w0, #0                  // return 0 (locked)

Lusd_epilogue:
    ldp     x29, x30, [sp], #16
    ret

// ============================================================================
// _handle_input: Dispatch key press to the appropriate game action
// void _handle_input(w0 = key_code)
//
// Uses callee-saved register x19 to preserve key code across bl calls.
//
// Key constants:
//   KEY_LEFT  = 260 (0x104)
//   KEY_RIGHT = 261 (0x105)
//   KEY_DOWN  = 258 (0x102)
//   KEY_UP    = 259 (0x103)
//   Space     = 32  (0x20)
//   'z'       = 122 (0x7A)
//   'q'       = 113 (0x71)
// ============================================================================
.globl _handle_input
.p2align 2
_handle_input:
    stp     x20, x19, [sp, #-16]!
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Save key code in callee-saved register (survives bl calls)
    mov     w19, w0

    // Pause gate: if paused, handle pause menu navigation
    adrp    x8, _is_paused@PAGE
    ldrb    w8, [x8, _is_paused@PAGEOFF]
    cbz     w8, Lcheck_left             // not paused, proceed normally

    // Allow 'p' to unpause (same as selecting Resume)
    cmp     w19, #112                   // 'p'
    b.eq    Lpause_resume

    // KEY_UP (259): decrement _pause_selection (clamp to 0)
    mov     w8, #259
    cmp     w19, w8
    b.ne    Lpause_check_down
    adrp    x8, _pause_selection@PAGE
    add     x8, x8, _pause_selection@PAGEOFF
    ldrb    w9, [x8]
    cbz     w9, Lhandle_done            // already at 0
    sub     w9, w9, #1
    strb    w9, [x8]
    b       Lhandle_done

Lpause_check_down:
    // KEY_DOWN (258): increment _pause_selection (clamp to 2)
    mov     w8, #258
    cmp     w19, w8
    b.ne    Lpause_check_enter
    adrp    x8, _pause_selection@PAGE
    add     x8, x8, _pause_selection@PAGEOFF
    ldrb    w9, [x8]
    cmp     w9, #2
    b.ge    Lhandle_done                // already at max
    add     w9, w9, #1
    strb    w9, [x8]
    b       Lhandle_done

Lpause_check_enter:
    // ENTER (10) or KEY_ENTER (343): activate selected pause menu item
    cmp     w19, #10
    b.eq    Lpause_activate
    mov     w8, #343
    cmp     w19, w8
    b.eq    Lpause_activate

    // 'q' or ESC: quit game
    cmp     w19, #113                   // 'q'
    b.eq    Lset_quit
    cmp     w19, #27                    // ESC
    b.eq    Lset_quit
    b       Lhandle_done                // block all other keys

Lpause_activate:
    // Dispatch based on _pause_selection
    adrp    x8, _pause_selection@PAGE
    ldrb    w9, [x8, _pause_selection@PAGEOFF]
    cmp     w9, #0
    b.eq    Lpause_resume               // Resume
    cmp     w9, #1
    b.eq    Lpause_quit_to_menu         // Quit to Main Menu
    // w9 == 2: Quit Game
    b       Lset_quit

Lpause_resume:
    // Unpause: set _is_paused = 0, reset gravity timer, reset _pause_selection
    adrp    x8, _is_paused@PAGE
    strb    wzr, [x8, _is_paused@PAGEOFF]
    adrp    x8, _pause_selection@PAGE
    strb    wzr, [x8, _pause_selection@PAGEOFF]
    bl      _get_time_ms
    adrp    x8, _last_drop_time@PAGE
    str     x0, [x8, _last_drop_time@PAGEOFF]
    b       Lhandle_done

Lpause_quit_to_menu:
    // Set _game_over = 1 to exit game loop, returns to menu via main.s
    adrp    x8, _game_over@PAGE
    mov     w9, #1
    strb    w9, [x8, _game_over@PAGEOFF]
    // Reset pause state
    adrp    x8, _is_paused@PAGE
    strb    wzr, [x8, _is_paused@PAGEOFF]
    adrp    x8, _pause_selection@PAGE
    strb    wzr, [x8, _pause_selection@PAGEOFF]
    b       Lhandle_done

Lcheck_left:
    // --- Check KEY_LEFT (260) ---
    mov     w8, #260
    cmp     w19, w8
    b.ne    Lcheck_right
    // _try_move(-1, 0) -- move left
    mov     w0, #-1
    mov     w1, #0
    bl      _try_move
    b       Lhandle_done

Lcheck_right:
    // --- Check KEY_RIGHT (261) ---
    mov     w8, #261
    cmp     w19, w8
    b.ne    Lcheck_down
    // _try_move(+1, 0) -- move right
    mov     w0, #1
    mov     w1, #0
    bl      _try_move
    b       Lhandle_done

Lcheck_down:
    // --- Check KEY_DOWN (258) ---
    mov     w8, #258
    cmp     w19, w8
    b.ne    Lcheck_up
    // _user_soft_drop() -- awards 1 point per cell (user-initiated only)
    bl      _user_soft_drop
    b       Lhandle_done

Lcheck_up:
    // --- Check KEY_UP (259) ---
    mov     w8, #259
    cmp     w19, w8
    b.ne    Lcheck_space
    // _try_rotate(1) -- rotate clockwise
    mov     w0, #1
    bl      _try_rotate
    b       Lhandle_done

Lcheck_space:
    // --- Check Space (32) ---
    cmp     w19, #32
    b.ne    Lcheck_z
    // _hard_drop()
    bl      _hard_drop
    b       Lhandle_done

Lcheck_z:
    // --- Check 'z' (122) ---
    cmp     w19, #122
    b.ne    Lcheck_c
    // _try_rotate(3) -- rotate counter-clockwise (3 = -1 mod 4)
    mov     w0, #3
    bl      _try_rotate
    b       Lhandle_done

Lcheck_c:
    // --- Check 'c' (99) -- hold piece ---
    cmp     w19, #99
    b.ne    Lcheck_p
    // Check if hold is enabled
    adrp    x8, _opt_hold@PAGE
    ldrb    w8, [x8, _opt_hold@PAGEOFF]
    cbz     w8, Lhandle_done            // hold disabled, ignore 'c'
    // Only hold if not paused (redundant due to pause gate, but safe)
    adrp    x8, _is_paused@PAGE
    ldrb    w8, [x8, _is_paused@PAGEOFF]
    cbnz    w8, Lhandle_done            // ignore hold during pause
    bl      _hold_piece
    b       Lhandle_done

Lcheck_p:
    // --- Check 'p' (112) -- pause toggle ---
    // Note: When paused, 'p' is handled by Lpause_resume in the pause gate above.
    // This code only runs when NOT paused (entering pause).
    cmp     w19, #112
    b.ne    Lcheck_q
    // Enter pause: set _is_paused = 1
    adrp    x8, _is_paused@PAGE
    mov     w9, #1
    strb    w9, [x8, _is_paused@PAGEOFF]
    // Reset pause selection to 0 (highlight Resume by default)
    adrp    x8, _pause_selection@PAGE
    strb    wzr, [x8, _pause_selection@PAGEOFF]
    b       Lhandle_done

Lcheck_q:
    // --- Check 'q' (113) or ESC (27) ---
    cmp     w19, #113
    b.eq    Lset_quit
    cmp     w19, #27
    b.ne    Lhandle_done
Lset_quit:
    // Set _game_over = 1 to quit
    adrp    x8, _game_over@PAGE
    mov     w9, #1
    strb    w9, [x8, _game_over@PAGEOFF]

Lhandle_done:
    ldp     x29, x30, [sp], #16
    ldp     x20, x19, [sp], #16
    ret

// ============================================================================
.subsections_via_symbols
