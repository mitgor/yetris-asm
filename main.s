// ============================================================================
// yetris-asm: AArch64 Assembly Tetris Clone for macOS Apple Silicon
// File: asm/main.s -- Entry point, initialization, state machine loop
// Build: make asm
//
// State machine:
//   _game_state = 0  -> MENU:  call _menu_frame each iteration
//   _game_state = 1  -> GAME:  run one game frame (input + gravity + render)
//   _game_state = 2  -> HELP:  call _help_frame each iteration
//   _game_state = FF -> EXIT:  cleanup and return 0
//
// Register allocation in state loop:
//   x19 = current time ms (game frame gravity)
//   x21 = last_drop_time (game frame gravity)
//   x22 = elapsed ms / level index (game frame gravity)
//   x23 = gravity delay (game frame gravity)
//   x24 = frame_start_ticks (mach_absolute_time, for frame timing)
//   x25 = elapsed_ticks per frame (frame timing scratch)
//   x28 = packed game state bitfield (game loop only):
//         bit 0 = game_over, bit 1 = is_paused, bit 2 = game_initialized
//         (x28 repurposed for stats output in Lstate_exit after game loop)
//
// Darwin ARM64 ABI Conventions (all 9 rules applied in this file):
//
//   1. Underscore prefixes: All C-visible symbols prefixed with _ (_main,
//      _initscr, _endwin, _stdscr, etc.)
//
//   2. x16 for syscalls: Syscall number goes in x16 (not x8 as on Linux).
//      Raw Unix numbers on ARM64 (no 0x2000000 offset).
//
//   3. svc #0x80: Supervisor call instruction to trap into the kernel.
//      The immediate 0x80 is convention (CPU ignores it; kernel reads x16).
//
//   4. x18 reserved: NEVER use x18 for any purpose. Apple reserves it
//      for platform use (TLS, kernel pointers). Violation causes crashes.
//      Temporaries: x9-x15. Callee-saved: x19-x28.
//
//   5. 16-byte stack alignment: SP must be 16-byte aligned at all times,
//      especially before any bl instruction. Violation causes SIGBUS.
//      Always allocate in multiples of 16 bytes.
//
//   6. Valid frame pointer (x29): x29 must always point to a valid frame
//      record (saved x29 + x30 pair). Required for debuggers/crash reports.
//
//   7. adrp+add for local data: Use adrp xN, label@PAGE followed by
//      add xN, xN, label@PAGEOFF for symbols within the same binary.
//
//   8. GOT-indirect for external globals: Use @GOTPAGE/@GOTPAGEOFF to
//      access symbols from dynamic libraries (e.g., _stdscr from ncurses).
//      Result is a pointer TO the variable -- must dereference with ldr.
//
//   9. Variadic args on stack: On Darwin ARM64, variadic function args
//      (after the fixed params) go on the stack, NOT in registers. Differs
//      from Linux ARM64. Not used in this file -- no variadic calls needed.
//
// ============================================================================

.section __TEXT,__text,regular,pure_instructions
.globl _main
.p2align 2

_main:
    // ---- Prologue ----
    // Save callee-saved registers x19-x28 + frame pointer (x29) + link
    // register (x30). Total: 12 registers = 96 bytes (already 16-byte
    // aligned). [ABI rules 5, 6]
    stp     x29, x30, [sp, #-96]!
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]
    stp     x27, x28, [sp, #80]
    mov     x29, sp

    // ==== INITIALIZATION ====

    // Initialize ncurses -- _initscr(void) -> WINDOW* in x0 [rule 1]
    bl      _initscr

    // _cbreak(void) -- disable line buffering (char-at-a-time input)
    bl      _cbreak

    // _noecho(void) -- suppress automatic echo of typed characters
    bl      _noecho

    // Initialize 7 color pairs for piece types + hide cursor
    bl      _init_colors

    // Configure non-blocking input: keypad + wtimeout(16ms) + noecho + cbreak
    bl      _init_input

    // Create menu subwindows (must exist before first _menu_frame call)
    bl      _init_menu_layout

    // Select random animation for the session (Phase 10)
    bl      _anim_select_random

    // Load hi-score from ~/.yetris-hiscore (Phase 11)
    bl      _load_hiscore

    // Set initial state: MENU
    adrp    x8, _game_state@PAGE
    strb    wzr, [x8, _game_state@PAGEOFF]

    // Initialize packed game state: all bits clear (game_over=0, is_paused=0, game_initialized=0)
    mov     x28, #0

    // ==== STATE MACHINE LOOP ====
Lstate_loop:
    adrp    x8, _game_state@PAGE
    ldrb    w9, [x8, _game_state@PAGEOFF]

    // Dispatch by state
    cbz     w9, Lstate_menu             // 0 = MENU
    cmp     w9, #1
    b.eq    Lstate_game                 // 1 = GAME
    cmp     w9, #2
    b.eq    Lstate_help                 // 2 = HELP
    b       Lstate_exit                 // 0xFF or unknown = EXIT

Lstate_menu:
    bl      _menu_frame
    b       Lstate_loop

Lstate_help:
    bl      _help_frame
    b       Lstate_loop

Lstate_game:
    // Check if game needs initialization (transition from menu)
    // x28 bit 2 == 0: needs init, 1: already running
    tst     x28, #4                     // test bit 2 (game_initialized)
    b.ne    Lgame_frame

    // ---- GAME INITIALIZATION ----
    // Destroy menu windows, create game windows
    bl      _destroy_menu_layout
    bl      _init_game_layout

    // Zero board and reset score/level/lines/game_over
    bl      _reset_board

    // Apply starting level: copy _starting_level to _level
    adrp    x8, _starting_level@PAGE
    ldr     w9, [x8, _starting_level@PAGEOFF]
    adrp    x8, _level@PAGE
    str     w9, [x8, _level@PAGEOFF]

    // Apply initial noise if _opt_noise > 0
    adrp    x8, _opt_noise@PAGE
    ldrb    w0, [x8, _opt_noise@PAGEOFF]
    cbz     w0, Lskip_noise
    bl      _add_noise              // w0 already has noise count
Lskip_noise:

    // Get first piece from 7-bag, set spawn position
    bl      _spawn_piece

    // Record initial gravity timestamp so first tick doesn't fire immediately
    bl      _get_time_ms
    adrp    x8, _last_drop_time@PAGE
    str     x0, [x8, _last_drop_time@PAGEOFF]

    // Record game start time for statistics timer
    adrp    x8, _game_start_time@PAGE
    str     x0, [x8, _game_start_time@PAGEOFF]

    // Mark game as initialized (set bit 2 of x28)
    orr     x28, x28, #4

Lgame_frame:
    // ---- ONE GAME FRAME ----

    // 1. Poll input -- returns w0 = key code or -1 (ERR)
    bl      _poll_input
    cmn     w0, #1                      // compare with -1 (ERR = no key pressed)
    b.eq    Lno_input                   // skip if no key pressed
    bl      _handle_input               // dispatch key to game action

    // Sync memory flags to x28 after input handling
    // (_handle_input may set game_over via 'q', or toggle is_paused via 'p')
    adrp    x8, _game_over@PAGE
    ldrb    w9, [x8, _game_over@PAGEOFF]
    bic     x28, x28, #1               // clear bit 0
    orr     x28, x28, x9               // bit 0 = game_over

    adrp    x8, _is_paused@PAGE
    ldrb    w9, [x8, _is_paused@PAGEOFF]
    bic     x28, x28, #2               // clear bit 1
    orr     x28, x28, x9, lsl #1       // bit 1 = is_paused
Lno_input:

    // ---- FRAME TIMING START ----
    // Measure game logic time AFTER _poll_input returns (excludes wgetch block).
    // x24 = frame_start_ticks
    bl      _mach_absolute_time
    mov     x24, x0

    // 2. Check game over from x28 register (bit 0)
    tst     x28, #1                     // test bit 0 (game_over)
    b.ne    Lgame_over_screen

    // 2b. Check if paused from x28 register (bit 1)
    tst     x28, #2                     // test bit 1 (is_paused)
    b.ne    Lskip_gravity               // paused: skip gravity, go straight to render

    // 2c. Check line clear animation state
    adrp    x8, _line_clear_state@PAGE
    ldrb    w9, [x8, _line_clear_state@PAGEOFF]
    cbnz    w9, Lflash_active

    // 3. Gravity timer check
    bl      _get_time_ms                // x0 = current time in ms
    mov     x19, x0                     // save current time in callee-saved reg

    // Load last_drop_time
    adrp    x8, _last_drop_time@PAGE
    ldr     x21, [x8, _last_drop_time@PAGEOFF]

    // Compute elapsed = current - last_drop
    sub     x22, x19, x21              // x22 = elapsed ms

    // Load gravity delay for current level
    adrp    x8, _level@PAGE
    ldr     w23, [x8, _level@PAGEOFF]  // w23 = level (1-22)
    sub     w23, w23, #1                // index = level - 1

    adrp    x8, _gravity_delays@PAGE
    add     x8, x8, _gravity_delays@PAGEOFF
    ldrh    w9, [x8, x23, lsl #1]      // w9 = delay_ms for current level

    // If elapsed >= delay: apply gravity
    cmp     x22, x9
    b.lt    Lskip_gravity

    // Apply gravity: try to move piece down
    bl      _soft_drop                  // moves down or locks+spawns

    // Sync game_over to x28 after gravity (soft_drop may trigger game_over via lock+spawn)
    adrp    x8, _game_over@PAGE
    ldrb    w9, [x8, _game_over@PAGEOFF]
    bic     x28, x28, #1               // clear bit 0
    orr     x28, x28, x9               // bit 0 = game_over

    // Reset gravity timer to current time
    adrp    x8, _last_drop_time@PAGE
    str     x19, [x8, _last_drop_time@PAGEOFF]

    b       Lskip_gravity

Lflash_active:
    // Flash animation is active -- check if 200ms delay has expired
    bl      _get_time_ms                // x0 = current time ms
    mov     x19, x0                     // save current time
    adrp    x8, _line_clear_timer@PAGE
    ldr     x9, [x8, _line_clear_timer@PAGEOFF]
    sub     x10, x19, x9               // elapsed = current - start
    cmp     x10, #200
    b.lt    Lskip_gravity              // still flashing, skip gravity, go to render

    // Flash expired: clear marked lines, spawn next piece
    bl      _clear_marked_lines
    bl      _spawn_piece

    // Reset line clear state
    adrp    x8, _line_clear_state@PAGE
    strb    wzr, [x8, _line_clear_state@PAGEOFF]

    // Reset gravity timer (prevent instant drop after flash)
    bl      _get_time_ms
    adrp    x8, _last_drop_time@PAGE
    str     x0, [x8, _last_drop_time@PAGEOFF]

    // Sync game_over from _spawn_piece (new piece may collide)
    adrp    x8, _game_over@PAGE
    ldrb    w9, [x8, _game_over@PAGEOFF]
    bic     x28, x28, #1               // clear bit 0
    orr     x28, x28, x9               // bit 0 = game_over

Lskip_gravity:

    // 4. Render frame (board + piece + score panel + wrefresh)
    bl      _render_frame

    // ---- FRAME TIMING END ----
    // Measure elapsed ticks since frame start and update running stats.
    bl      _mach_absolute_time
    sub     x25, x0, x24               // x25 = elapsed_ticks this frame

    // Update _frame_count
    adrp    x8, _frame_count@PAGE
    add     x8, x8, _frame_count@PAGEOFF
    ldr     x9, [x8]
    add     x9, x9, #1
    str     x9, [x8]

    // Update _frame_time_sum
    adrp    x8, _frame_time_sum@PAGE
    add     x8, x8, _frame_time_sum@PAGEOFF
    ldr     x9, [x8]
    add     x9, x9, x25
    str     x9, [x8]

    // Update _frame_time_min (min = min(current_min, elapsed))
    adrp    x8, _frame_time_min@PAGE
    add     x8, x8, _frame_time_min@PAGEOFF
    ldr     x9, [x8]
    cmp     x25, x9
    csel    x9, x25, x9, lo
    str     x9, [x8]

    // Update _frame_time_max (max = max(current_max, elapsed))
    adrp    x8, _frame_time_max@PAGE
    add     x8, x8, _frame_time_max@PAGEOFF
    ldr     x9, [x8]
    cmp     x25, x9
    csel    x9, x25, x9, hi
    str     x9, [x8]

    // 5. Check game over after render from x28 register (bit 0)
    tst     x28, #1                     // test bit 0 (game_over)
    b.eq    Lstate_loop                 // not game over, continue state loop

    // Fall through to game over screen

Lgame_over_screen:
    // Check if current score beats hi-score, save if so (Phase 11)
    adrp    x8, _score@PAGE
    ldr     w9, [x8, _score@PAGEOFF]
    adrp    x8, _hiscore@PAGE
    add     x8, x8, _hiscore@PAGEOFF
    ldr     w10, [x8]
    cmp     w9, w10
    b.ls    Lno_new_hiscore            // score <= hiscore, skip save
    str     w9, [x8]                   // update in-memory hiscore
    bl      _save_hiscore              // persist to disk
Lno_new_hiscore:

    // Render one more time to show the GAME OVER overlay
    bl      _render_frame

    // Switch to blocking input so we wait for 'q' without busy-waiting
    adrp    x8, _stdscr@GOTPAGE
    ldr     x8, [x8, _stdscr@GOTPAGEOFF]
    ldr     x0, [x8]                   // x0 = stdscr (WINDOW*)
    mov     w1, #-1                     // -1 = blocking mode (no timeout)
    bl      _wtimeout

    // Wait for 'q' or ESC key to return to menu
Lwait_quit:
    adrp    x8, _stdscr@GOTPAGE
    ldr     x8, [x8, _stdscr@GOTPAGEOFF]
    ldr     x0, [x8]                   // reload stdscr
    bl      _wgetch
    cmp     w0, #113                    // 'q' = 0x71 = 113
    b.eq    Lreturn_to_menu
    cmp     w0, #27                     // ESC = 0x1B = 27
    b.ne    Lwait_quit

Lreturn_to_menu:
    // Transition back to menu state
    adrp    x8, _game_state@PAGE
    strb    wzr, [x8, _game_state@PAGEOFF]      // _game_state = 0 (MENU)
    mov     x28, #0                              // clear all packed state (game_over, is_paused, game_initialized)

    // Destroy game windows, create menu windows
    bl      _destroy_game_layout
    bl      _init_menu_layout

    // Reset _menu_selection to 0
    adrp    x8, _menu_selection@PAGE
    strb    wzr, [x8, _menu_selection@PAGEOFF]

    // Restore non-blocking input for menu (wtimeout(16))
    adrp    x8, _stdscr@GOTPAGE
    ldr     x8, [x8, _stdscr@GOTPAGEOFF]
    ldr     x0, [x8]
    mov     w1, #16
    bl      _wtimeout

    // Clear stdscr before showing menu (prevent stale content)
    adrp    x8, _stdscr@GOTPAGE
    ldr     x8, [x8, _stdscr@GOTPAGEOFF]
    ldr     x0, [x8]
    bl      _werase

    b       Lstate_loop

Lstate_exit:
    // ==== PRINT FRAME TIMING STATS TO STDERR ====
    // Only print if at least one frame was timed
    adrp    x8, _frame_count@PAGE
    add     x8, x8, _frame_count@PAGEOFF
    ldr     x26, [x8]                  // x26 = frame_count
    cbz     x26, Lskip_stats

    // Load raw tick values
    adrp    x8, _frame_time_sum@PAGE
    add     x8, x8, _frame_time_sum@PAGEOFF
    ldr     x27, [x8]                  // x27 = sum_ticks

    adrp    x8, _frame_time_min@PAGE
    add     x8, x8, _frame_time_min@PAGEOFF
    ldr     x28, [x8]                  // x28 = min_ticks

    adrp    x8, _frame_time_max@PAGE
    add     x8, x8, _frame_time_max@PAGEOFF
    ldr     x25, [x8]                  // x25 = max_ticks

    // Convert ticks to microseconds: us = ticks * 125 / 3 / 1000
    // Simplify: us = ticks * 125 / 3000
    // min_us
    mov     w8, #125
    mul     x9, x28, x8               // min_ticks * 125
    mov     w8, #3000
    udiv    x28, x9, x8               // x28 = min_us

    // max_us
    mov     w8, #125
    mul     x9, x25, x8               // max_ticks * 125
    mov     w8, #3000
    udiv    x25, x9, x8               // x25 = max_us

    // sum_us (for average calculation)
    mov     w8, #125
    mul     x9, x27, x8               // sum_ticks * 125
    mov     w8, #3000
    udiv    x27, x9, x8               // x27 = sum_us

    // avg_us = sum_us / count
    udiv    x24, x27, x26             // x24 = avg_us

    // ---- Build output string in stack buffer ----
    // Format: "Frames: NNNN  Min: NNNus  Max: NNNus  Avg: NNNus\n"
    // Allocate 128-byte buffer on stack (plenty for this output)
    sub     sp, sp, #128
    mov     x9, sp                     // x9 = write pointer into buffer

    // "Frames: "
    mov     w10, #0x46                 // 'F'
    strb    w10, [x9], #1
    mov     w10, #0x72                 // 'r'
    strb    w10, [x9], #1
    mov     w10, #0x61                 // 'a'
    strb    w10, [x9], #1
    mov     w10, #0x6D                 // 'm'
    strb    w10, [x9], #1
    mov     w10, #0x65                 // 'e'
    strb    w10, [x9], #1
    mov     w10, #0x73                 // 's'
    strb    w10, [x9], #1
    mov     w10, #0x3A                 // ':'
    strb    w10, [x9], #1
    mov     w10, #0x20                 // ' '
    strb    w10, [x9], #1

    // Write frame_count number
    mov     x0, x26                    // value = frame_count
    // Fall through to Lwrite_number, which writes digits at x9 and advances x9
    bl      Lwrite_number_to_buf

    // "  Min: "
    mov     w10, #0x20                 // ' '
    strb    w10, [x9], #1
    strb    w10, [x9], #1
    mov     w10, #0x4D                 // 'M'
    strb    w10, [x9], #1
    mov     w10, #0x69                 // 'i'
    strb    w10, [x9], #1
    mov     w10, #0x6E                 // 'n'
    strb    w10, [x9], #1
    mov     w10, #0x3A                 // ':'
    strb    w10, [x9], #1
    mov     w10, #0x20                 // ' '
    strb    w10, [x9], #1

    // Write min_us number
    mov     x0, x28
    bl      Lwrite_number_to_buf

    // "us"
    mov     w10, #0x75                 // 'u'
    strb    w10, [x9], #1
    mov     w10, #0x73                 // 's'
    strb    w10, [x9], #1

    // "  Max: "
    mov     w10, #0x20
    strb    w10, [x9], #1
    strb    w10, [x9], #1
    mov     w10, #0x4D                 // 'M'
    strb    w10, [x9], #1
    mov     w10, #0x61                 // 'a'
    strb    w10, [x9], #1
    mov     w10, #0x78                 // 'x'
    strb    w10, [x9], #1
    mov     w10, #0x3A                 // ':'
    strb    w10, [x9], #1
    mov     w10, #0x20                 // ' '
    strb    w10, [x9], #1

    // Write max_us number
    mov     x0, x25
    bl      Lwrite_number_to_buf

    // "us"
    mov     w10, #0x75                 // 'u'
    strb    w10, [x9], #1
    mov     w10, #0x73                 // 's'
    strb    w10, [x9], #1

    // "  Avg: "
    mov     w10, #0x20
    strb    w10, [x9], #1
    strb    w10, [x9], #1
    mov     w10, #0x41                 // 'A'
    strb    w10, [x9], #1
    mov     w10, #0x76                 // 'v'
    strb    w10, [x9], #1
    mov     w10, #0x67                 // 'g'
    strb    w10, [x9], #1
    mov     w10, #0x3A                 // ':'
    strb    w10, [x9], #1
    mov     w10, #0x20                 // ' '
    strb    w10, [x9], #1

    // Write avg_us number
    mov     x0, x24
    bl      Lwrite_number_to_buf

    // "us\n"
    mov     w10, #0x75                 // 'u'
    strb    w10, [x9], #1
    mov     w10, #0x73                 // 's'
    strb    w10, [x9], #1
    mov     w10, #0x0A                 // '\n'
    strb    w10, [x9], #1

    // ---- Write to stderr using write(2, buf, len) syscall ----
    // x0 = fd (2 = stderr)
    // x1 = buf pointer
    // x2 = length
    mov     x0, #2                     // fd = stderr
    mov     x1, sp                     // buf = start of buffer
    mov     x2, sp
    sub     x2, x9, x2                 // len = write_ptr - buf_start
    mov     x16, #4                    // syscall 4 = write
    svc     #0x80

    // Free the 128-byte buffer
    add     sp, sp, #128

Lskip_stats:

    // ==== CLEANUP ====
    // Destroy whichever layout is active (both destroy functions have NULL guards)
    bl      _destroy_game_layout
    bl      _destroy_menu_layout

    // Restore terminal to pre-ncurses state
    bl      _endwin

    // Return 0 (success)
    mov     w0, #0

    // ---- Epilogue ----
    // Restore callee-saved registers
    ldp     x27, x28, [sp, #80]
    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #96
    ret

// ============================================================================
// Lwrite_number_to_buf: Convert unsigned integer to ASCII and append to buffer
// Input:  x0 = value to convert
//         x9 = pointer to output buffer (current write position)
// Output: x9 advanced past the written digits
// Clobbers: x0, x10, x11, x12, x13, x14, x15
// Note: This is a local helper, not a separate function. It uses bl/ret
//       pattern but does NOT save/restore callee-saved registers. It must
//       only be called from within Lstate_exit where callee-saved regs are
//       already safely stored. We use a small scratch area on the stack.
// ============================================================================
.p2align 2
Lwrite_number_to_buf:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp

    // Use stack space at sp+16 for digit buffer (16 bytes max)
    add     x11, sp, #16              // x11 = base of digit scratch buffer
    mov     x12, #0                    // digit count
    mov     x13, #10                   // divisor

    // Handle zero specially
    cbnz    x0, Lwnb_extract
    mov     w10, #0x30                 // '0'
    strb    w10, [x9], #1
    b       Lwnb_done

Lwnb_extract:
    cbz     x0, Lwnb_write
    udiv    x14, x0, x13               // quotient
    msub    x15, x14, x13, x0          // remainder = value - quotient*10
    add     w15, w15, #0x30            // ASCII digit
    strb    w15, [x11, x12]            // store in scratch buffer
    add     x12, x12, #1
    mov     x0, x14                    // value = quotient
    b       Lwnb_extract

Lwnb_write:
    // Digits are in scratch buffer in reverse order [0..digit_count-1]
    // Write them to output buffer in correct order (last stored = MSB)
    sub     x12, x12, #1              // index = digit_count - 1

Lwnb_write_loop:
    cmp     x12, #0
    b.lt    Lwnb_done
    ldrb    w10, [x11, x12]
    strb    w10, [x9], #1
    sub     x12, x12, #1
    b       Lwnb_write_loop

Lwnb_done:
    ldp     x29, x30, [sp], #32
    ret

// ============================================================================
// Frame timing data section
// ============================================================================
.section __DATA,__data
.globl _frame_count
_frame_count: .quad 0
.globl _frame_time_sum
_frame_time_sum: .quad 0
.globl _frame_time_min
_frame_time_min: .quad 0x7FFFFFFFFFFFFFFF
.globl _frame_time_max
_frame_time_max: .quad 0

// ============================================================================
.subsections_via_symbols
