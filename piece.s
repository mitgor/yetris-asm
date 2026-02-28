// ============================================================================
// yetris-asm: AArch64 Assembly Tetris Clone for macOS Apple Silicon
// File: asm/piece.s -- Piece operations: movement, SRS rotation, drops,
//                      spawning, game over detection
// Build: make asm
//
// Provides:
//   _try_move:        Attempt to move current piece by (dx, dy)
//   _try_rotate:      Attempt SRS rotation with wall kicks
//   _hard_drop:       Instant drop to lowest valid position, lock, spawn next
//   _soft_drop:       Move down one row; if blocked, lock and spawn next
//   _spawn_piece:     Get next piece from 7-bag and set spawn position
//   _check_game_over: Check if spawned piece collides (game over condition)
//
// All functions read/write global state in data.s and call board.s functions.
// Data access uses adrp+add (@PAGE/@PAGEOFF) -- same binary linking.
//
// SRS rotation: The kick table uses math convention (positive Y = up).
// Board uses screen convention (positive Y = down). Kick dy is NEGATED
// when applied to board coordinates, matching C++ reference (this->y -= dy).
//
// Darwin ARM64 ABI: x0-x15 caller-saved, x19-x28 callee-saved, x18 reserved.
// ============================================================================

.section __TEXT,__text,regular,pure_instructions

// ----------------------------------------------------------------------------
// _try_move(w0=dx, w1=dy) -> w0=1 (moved) or w0=0 (blocked)
//
// Attempt to move the current piece by (dx, dy). Both are signed.
// Left: dx=-1, dy=0. Right: dx=+1, dy=0. Down: dx=0, dy=+1.
//
// Uses callee-saved: x19=dx, x20=dy
// Stack: 32 bytes
// ----------------------------------------------------------------------------
.globl _try_move
.p2align 2
_try_move:
    // Prologue
    stp     x20, x19, [sp, #-32]!
    stp     x29, x30, [sp, #16]
    add     x29, sp, #16

    // Save arguments
    sxtw    x19, w0                 // x19 = dx (sign-extended)
    sxtw    x20, w1                 // x20 = dy (sign-extended)

    // Load current piece state
    adrp    x8, _piece_type@PAGE
    add     x8, x8, _piece_type@PAGEOFF
    ldrb    w0, [x8]               // w0 = piece_type

    adrp    x8, _piece_rotation@PAGE
    add     x8, x8, _piece_rotation@PAGEOFF
    ldrb    w1, [x8]               // w1 = piece_rotation

    adrp    x8, _piece_x@PAGE
    add     x8, x8, _piece_x@PAGEOFF
    ldrsh   w2, [x8]               // w2 = piece_x (signed)

    adrp    x8, _piece_y@PAGE
    add     x8, x8, _piece_y@PAGEOFF
    ldrsh   w3, [x8]               // w3 = piece_y (signed)

    // Compute new position: new_x = piece_x + dx, new_y = piece_y + dy
    add     w2, w2, w19             // w2 = new_x
    add     w3, w3, w20             // w3 = new_y

    // Call _is_piece_valid(type, rotation, new_x, new_y)
    bl      _is_piece_valid

    // If invalid, return 0
    cbz     w0, Lmove_fail

    // Valid: update piece_x and piece_y
    adrp    x8, _piece_x@PAGE
    add     x8, x8, _piece_x@PAGEOFF
    ldrsh   w9, [x8]
    add     w9, w9, w19
    strh    w9, [x8]               // piece_x += dx

    adrp    x8, _piece_y@PAGE
    add     x8, x8, _piece_y@PAGEOFF
    ldrsh   w9, [x8]
    add     w9, w9, w20
    strh    w9, [x8]               // piece_y += dy

    // Clear _last_was_rotation = 0 (non-rotation move)
    adrp    x8, _last_was_rotation@PAGE
    strb    wzr, [x8, _last_was_rotation@PAGEOFF]

    mov     w0, #1                  // return 1 (moved)
    b       Lmove_epilogue

Lmove_fail:
    mov     w0, #0                  // return 0 (blocked)

Lmove_epilogue:
    ldp     x29, x30, [sp, #16]
    ldp     x20, x19, [sp], #32
    ret

// ----------------------------------------------------------------------------
// _try_rotate(w0=direction) -> w0=1 (rotated) or w0=0 (blocked)
//
// Attempt SRS rotation with wall kicks.
// direction: +1 for CW, +3 for CCW (using +3 instead of -1 to avoid negative mod)
//
// Algorithm:
// 1. Compute new_rotation = (current_rotation + direction) & 3
// 2. Try basic rotation (no kick)
// 3. If fails, try 4 wall kick offsets from appropriate table
// 4. Accept first valid position, or return 0 if all 5 tests fail
//
// CRITICAL: SRS kick dy is negated for board coordinates (positive Y = down)
//
// Uses callee-saved: x19=piece_type, x20=piece_rotation(original),
//   x21=piece_x, x22=piece_y, x23=new_rotation, x24=kick table base,
//   x25=test counter, x26=direction index
// Stack: 80 bytes (8 callee-saved + x29/x30)
// ----------------------------------------------------------------------------
.globl _try_rotate
.p2align 2
_try_rotate:
    // Prologue: save 8 callee-saved registers + frame pointer
    stp     x29, x30, [sp, #-80]!
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]
    mov     x29, sp

    // Save direction for later use
    mov     w26, w0                 // w26 = direction (1=CW, 3=CCW)

    // Load current piece state
    adrp    x8, _piece_type@PAGE
    add     x8, x8, _piece_type@PAGEOFF
    ldrb    w19, [x8]              // w19 = piece_type

    adrp    x8, _piece_rotation@PAGE
    add     x8, x8, _piece_rotation@PAGEOFF
    ldrb    w20, [x8]              // w20 = piece_rotation (original)

    adrp    x8, _piece_x@PAGE
    add     x8, x8, _piece_x@PAGEOFF
    ldrsh   w21, [x8]              // w21 = piece_x (signed)

    adrp    x8, _piece_y@PAGE
    add     x8, x8, _piece_y@PAGEOFF
    ldrsh   w22, [x8]              // w22 = piece_y (signed)

    // Compute new_rotation = (piece_rotation + direction) & 3
    add     w23, w20, w26
    and     w23, w23, #3            // w23 = new_rotation

    // Test 0: basic rotation (no kick offset)
    mov     w0, w19                 // type
    mov     w1, w23                 // new_rotation
    mov     w2, w21                 // piece_x
    mov     w3, w22                 // piece_y
    bl      _is_piece_valid

    cbnz    w0, Lrotate_accept_basic

    // Basic rotation failed -- try wall kicks
    // Determine kick table based on piece type
    cmp     w19, #1                 // Is this the I-piece?
    b.eq    Lrotate_use_i_kicks

    // Use JLSTZ kick table
    adrp    x24, _srs_kicks_jlstz@PAGE
    add     x24, x24, _srs_kicks_jlstz@PAGEOFF
    b       Lrotate_kick_start

Lrotate_use_i_kicks:
    adrp    x24, _srs_kicks_i@PAGE
    add     x24, x24, _srs_kicks_i@PAGEOFF

Lrotate_kick_start:
    // Determine direction index: CW(1)->dir_idx=0, CCW(3)->dir_idx=1
    cmp     w26, #1
    b.eq    Lrotate_dir_cw
    mov     w26, #1                 // dir_idx = 1 (CCW)
    b       Lrotate_kick_loop_init
Lrotate_dir_cw:
    mov     w26, #0                 // dir_idx = 0 (CW)

Lrotate_kick_loop_init:
    // Kick tests 1-4 (test 0 was the basic rotation already tried)
    mov     w25, #1                 // test = 1

Lrotate_kick_loop:
    cmp     w25, #5
    b.ge    Lrotate_fail            // all 5 tests failed

    // Compute kick table offset: dir_idx*40 + piece_rotation*10 + test*2
    mov     w8, #40
    mul     w8, w26, w8             // dir_idx * 40
    mov     w9, #10
    mul     w9, w20, w9             // piece_rotation * 10 (ORIGINAL rotation)
    add     w8, w8, w9
    mov     w9, #2
    mul     w9, w25, w9             // test * 2
    add     w8, w8, w9              // total offset

    // Load kick dx and dy (signed bytes!)
    uxtw    x8, w8
    ldrsb   w9, [x24, x8]          // dx = kick_table[offset + 0]
    add     x8, x8, #1
    ldrsb   w10, [x24, x8]         // dy = kick_table[offset + 1]

    // NEGATE dy for board coordinates: SRS +Y=up, board +Y=down
    neg     w10, w10                // kick_y = -dy

    // Compute kicked position
    add     w2, w21, w9             // new_x = piece_x + dx
    add     w3, w22, w10            // new_y = piece_y + kick_y (negated)

    // Test this position
    mov     w0, w19                 // type
    mov     w1, w23                 // new_rotation
    bl      _is_piece_valid

    cbnz    w0, Lrotate_accept_kick

    // This kick failed, try next
    add     w25, w25, #1
    b       Lrotate_kick_loop

Lrotate_accept_basic:
    // Basic rotation succeeded: just update rotation
    adrp    x8, _piece_rotation@PAGE
    add     x8, x8, _piece_rotation@PAGEOFF
    strb    w23, [x8]              // _piece_rotation = new_rotation

    // Set _last_was_rotation = 1 (for T-spin detection at lock time)
    adrp    x8, _last_was_rotation@PAGE
    mov     w9, #1
    strb    w9, [x8, _last_was_rotation@PAGEOFF]

    mov     w0, #1
    b       Lrotate_epilogue

Lrotate_accept_kick:
    // Kick succeeded: update rotation and position
    // Need to recompute dx and dy for the successful test
    // Recompute kick offset for the successful test
    mov     w8, #40
    mul     w8, w26, w8
    mov     w9, #10
    mul     w9, w20, w9
    add     w8, w8, w9
    mov     w9, #2
    mul     w9, w25, w9
    add     w8, w8, w9
    uxtw    x8, w8
    ldrsb   w9, [x24, x8]          // dx
    add     x8, x8, #1
    ldrsb   w10, [x24, x8]         // dy
    neg     w10, w10                // kick_y = -dy

    // Update piece_x += dx
    adrp    x8, _piece_x@PAGE
    add     x8, x8, _piece_x@PAGEOFF
    ldrsh   w11, [x8]
    add     w11, w11, w9
    strh    w11, [x8]

    // Update piece_y += kick_y
    adrp    x8, _piece_y@PAGE
    add     x8, x8, _piece_y@PAGEOFF
    ldrsh   w11, [x8]
    add     w11, w11, w10
    strh    w11, [x8]

    // Update rotation
    adrp    x8, _piece_rotation@PAGE
    add     x8, x8, _piece_rotation@PAGEOFF
    strb    w23, [x8]

    // Set _last_was_rotation = 1 (for T-spin detection at lock time)
    adrp    x8, _last_was_rotation@PAGE
    mov     w9, #1
    strb    w9, [x8, _last_was_rotation@PAGEOFF]

    mov     w0, #1
    b       Lrotate_epilogue

Lrotate_fail:
    mov     w0, #0                  // all tests failed

Lrotate_epilogue:
    // Epilogue: restore callee-saved registers
    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret

// ----------------------------------------------------------------------------
// _hard_drop() -> void
//
// Instantly drop the current piece to its lowest valid position, lock it,
// and spawn the next piece.
//
// Uses callee-saved: x19=piece_type, x20=piece_rotation, x21=piece_x,
//                    x22=piece_y (tracking lowest valid y)
// Stack: 48 bytes
// ----------------------------------------------------------------------------
.globl _hard_drop
.p2align 2
_hard_drop:
    // Prologue
    stp     x29, x30, [sp, #-64]!
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    mov     x29, sp

    // Load current piece state
    adrp    x8, _piece_type@PAGE
    add     x8, x8, _piece_type@PAGEOFF
    ldrb    w19, [x8]

    adrp    x8, _piece_rotation@PAGE
    add     x8, x8, _piece_rotation@PAGEOFF
    ldrb    w20, [x8]

    adrp    x8, _piece_x@PAGE
    add     x8, x8, _piece_x@PAGEOFF
    ldrsh   w21, [x8]

    adrp    x8, _piece_y@PAGE
    add     x8, x8, _piece_y@PAGEOFF
    ldrsh   w22, [x8]

    mov     w23, w22                // w23 = starting y (for hard drop scoring)

    // Loop: try_y = piece_y + 1, check valid, repeat
Lhdrop_loop:
    add     w3, w22, #1             // try_y = current_y + 1
    mov     w0, w19                 // type
    mov     w1, w20                 // rotation
    mov     w2, w21                 // piece_x
    bl      _is_piece_valid

    cbz     w0, Lhdrop_land         // if invalid, stop at current position

    // Valid: move down
    add     w22, w22, #1
    b       Lhdrop_loop

Lhdrop_land:
    // Update _piece_y with final valid position
    adrp    x8, _piece_y@PAGE
    add     x8, x8, _piece_y@PAGEOFF
    strh    w22, [x8]

    // Hard drop score: (final_y - start_y) * 2
    sub     w8, w22, w23            // w8 = rows dropped (final - start)
    lsl     w8, w8, #1              // w8 = rows * 2
    adrp    x9, _score@PAGE
    add     x9, x9, _score@PAGEOFF
    ldr     w10, [x9]
    add     w10, w10, w8
    str     w10, [x9]              // _score += hard_drop_points

    // Clear _last_was_rotation (hard drop is not a rotation)
    adrp    x8, _last_was_rotation@PAGE
    strb    wzr, [x8, _last_was_rotation@PAGEOFF]

    // Lock piece into board
    bl      _lock_piece             // w0 = lines cleared count
    cbnz    w0, Lhdrop_flash_started
    bl      _spawn_piece
    b       Lhdrop_epilogue

Lhdrop_flash_started:
    // Lines marked with value 9, _line_clear_state already set by _lock_piece/_mark_lines
    // Do NOT spawn -- game loop handles it after flash delay

    // Epilogue
Lhdrop_epilogue:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

// ----------------------------------------------------------------------------
// _soft_drop() -> w0=1 (moved down) or w0=0 (locked)
//
// Move piece down by one row. If blocked, lock and spawn next piece.
//
// Stack: 16 bytes
// ----------------------------------------------------------------------------
.globl _soft_drop
.p2align 2
_soft_drop:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Try to move down: dx=0, dy=+1
    mov     w0, #0                  // dx = 0
    mov     w1, #1                  // dy = +1
    bl      _try_move

    cbnz    w0, Lsdrop_moved        // if moved, return 1

    // Blocked: lock (may start flash)
    bl      _lock_piece             // w0 = lines cleared count
    cbnz    w0, Lsdrop_flash_started
    bl      _spawn_piece
Lsdrop_flash_started:

    mov     w0, #0                  // return 0 (locked)
    b       Lsdrop_epilogue

Lsdrop_moved:
    mov     w0, #1                  // return 1 (moved)

Lsdrop_epilogue:
    ldp     x29, x30, [sp], #16
    ret

// ----------------------------------------------------------------------------
// _spawn_piece() -> void
//
// Get the next piece from the 7-bag, set its spawn position, and check
// for game over.
//
// Uses callee-saved: x19=piece type
// Stack: 32 bytes
// ----------------------------------------------------------------------------
.globl _spawn_piece
.p2align 2
_spawn_piece:
    stp     x20, x19, [sp, #-32]!
    stp     x29, x30, [sp, #16]
    add     x29, sp, #16

    // Get next piece type from 7-bag
    bl      _next_piece
    mov     w19, w0                 // w19 = new piece type (0-6)

    // Store piece_type
    adrp    x8, _piece_type@PAGE
    add     x8, x8, _piece_type@PAGEOFF
    strb    w19, [x8]

    // Set rotation to 0
    adrp    x8, _piece_rotation@PAGE
    add     x8, x8, _piece_rotation@PAGEOFF
    strb    wzr, [x8]

    // Load spawn position from tables
    // piece_x = _piece_spawn_x[type]
    adrp    x8, _piece_spawn_x@PAGE
    add     x8, x8, _piece_spawn_x@PAGEOFF
    uxtw    x9, w19
    ldrsb   w10, [x8, x9]          // signed: spawn_x (positive, but consistent)

    adrp    x8, _piece_x@PAGE
    add     x8, x8, _piece_x@PAGEOFF
    strh    w10, [x8]              // _piece_x = spawn_x

    // piece_y = _piece_spawn_y[type]
    adrp    x8, _piece_spawn_y@PAGE
    add     x8, x8, _piece_spawn_y@PAGEOFF
    ldrsb   w10, [x8, x9]          // signed: spawn_y (negative!)

    adrp    x8, _piece_y@PAGE
    add     x8, x8, _piece_y@PAGEOFF
    strh    w10, [x8]              // _piece_y = spawn_y

    // Check for game over
    bl      _check_game_over

    // Epilogue
    ldp     x29, x30, [sp, #16]
    ldp     x20, x19, [sp], #32
    ret

// ----------------------------------------------------------------------------
// _check_game_over() -> void
//
// Check if the current piece at its spawn position collides with existing
// blocks. If so, set _game_over = 1.
//
// Stack: 16 bytes
// ----------------------------------------------------------------------------
.globl _check_game_over
.p2align 2
_check_game_over:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Load current piece state
    adrp    x8, _piece_type@PAGE
    add     x8, x8, _piece_type@PAGEOFF
    ldrb    w0, [x8]

    adrp    x8, _piece_rotation@PAGE
    add     x8, x8, _piece_rotation@PAGEOFF
    ldrb    w1, [x8]

    adrp    x8, _piece_x@PAGE
    add     x8, x8, _piece_x@PAGEOFF
    ldrsh   w2, [x8]

    adrp    x8, _piece_y@PAGE
    add     x8, x8, _piece_y@PAGEOFF
    ldrsh   w3, [x8]

    bl      _is_piece_valid

    // If invalid (w0 == 0), game over
    cbnz    w0, Lgameover_ok

    adrp    x8, _game_over@PAGE
    add     x8, x8, _game_over@PAGEOFF
    mov     w9, #1
    strb    w9, [x8]               // _game_over = 1

Lgameover_ok:
    ldp     x29, x30, [sp], #16
    ret

// ----------------------------------------------------------------------------
// _compute_ghost_y() -> w0 = ghost landing y
//
// Pure query function that returns the lowest valid Y position for the current
// piece without modifying any game state. Identical to _hard_drop loop but
// operates only on registers, never writes back to globals.
//
// Uses callee-saved: x19=type, x20=rotation, x21=px, x22=py(tracking)
// Stack: 48 bytes
// ----------------------------------------------------------------------------
.globl _compute_ghost_y
.p2align 2
_compute_ghost_y:
    stp     x29, x30, [sp, #-48]!
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    mov     x29, sp

    // Load current piece state into callee-saved registers
    adrp    x8, _piece_type@PAGE
    ldrb    w19, [x8, _piece_type@PAGEOFF]
    adrp    x8, _piece_rotation@PAGE
    ldrb    w20, [x8, _piece_rotation@PAGEOFF]
    adrp    x8, _piece_x@PAGE
    ldrsh   w21, [x8, _piece_x@PAGEOFF]
    adrp    x8, _piece_y@PAGE
    ldrsh   w22, [x8, _piece_y@PAGEOFF]

    // Drop loop: try y+1 until invalid
Lghost_drop_loop:
    add     w3, w22, #1             // try_y = current_y + 1
    mov     w0, w19                 // type
    mov     w1, w20                 // rotation
    mov     w2, w21                 // px
    bl      _is_piece_valid
    cbz     w0, Lghost_drop_done    // invalid -> stop
    add     w22, w22, #1            // advance y
    b       Lghost_drop_loop

Lghost_drop_done:
    mov     w0, w22                 // return last valid y

    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// ----------------------------------------------------------------------------
// _hold_piece() -> void
//
// Implements the hold mechanic:
//   1. If _can_hold == 0, return immediately (already held this turn)
//   2. Set _can_hold = 0
//   3. Save current piece type
//   4. If _hold_piece_type == 0xFF (empty):
//        Store current type into hold, call _spawn_piece (gets next from bag)
//   5. Else (hold has a piece):
//        Swap current with hold, reset rotation to 0, set spawn position
//
// Uses callee-saved: x19=current type, x20=held type
// Stack: 32 bytes
// ----------------------------------------------------------------------------
.globl _hold_piece
.p2align 2
_hold_piece:
    stp     x20, x19, [sp, #-32]!
    stp     x29, x30, [sp, #16]
    add     x29, sp, #16

    // Check _can_hold flag
    adrp    x8, _can_hold@PAGE
    add     x8, x8, _can_hold@PAGEOFF
    ldrb    w9, [x8]
    cbz     w9, Lhold_return            // already held this turn, bail

    // Set _can_hold = 0
    strb    wzr, [x8]

    // Load current piece type
    adrp    x8, _piece_type@PAGE
    add     x8, x8, _piece_type@PAGEOFF
    ldrb    w19, [x8]                   // w19 = current piece type

    // Load hold piece type
    adrp    x8, _hold_piece_type@PAGE
    add     x8, x8, _hold_piece_type@PAGEOFF
    ldrb    w20, [x8]                   // w20 = held piece type (or 0xFF)

    // Store current type into hold slot
    strb    w19, [x8]                   // _hold_piece_type = current type

    // Check if hold was empty
    cmp     w20, #0xFF
    b.eq    Lhold_was_empty

    // --- Hold had a piece: swap in the held piece ---
    // Set _piece_type = old held type
    adrp    x8, _piece_type@PAGE
    add     x8, x8, _piece_type@PAGEOFF
    strb    w20, [x8]

    // Reset rotation to 0
    adrp    x8, _piece_rotation@PAGE
    add     x8, x8, _piece_rotation@PAGEOFF
    strb    wzr, [x8]

    // Load spawn position from tables for the swapped-in type
    adrp    x8, _piece_spawn_x@PAGE
    add     x8, x8, _piece_spawn_x@PAGEOFF
    uxtw    x9, w20
    ldrsb   w10, [x8, x9]
    adrp    x8, _piece_x@PAGE
    add     x8, x8, _piece_x@PAGEOFF
    strh    w10, [x8]                   // _piece_x = spawn_x

    adrp    x8, _piece_spawn_y@PAGE
    add     x8, x8, _piece_spawn_y@PAGEOFF
    ldrsb   w10, [x8, x9]
    adrp    x8, _piece_y@PAGE
    add     x8, x8, _piece_y@PAGEOFF
    strh    w10, [x8]                   // _piece_y = spawn_y

    // Check for game over with new piece
    bl      _check_game_over
    b       Lhold_return

Lhold_was_empty:
    // Hold was empty: current type already stored, get next from bag
    bl      _spawn_piece

Lhold_return:
    ldp     x29, x30, [sp, #16]
    ldp     x20, x19, [sp], #32
    ret

// ============================================================================
.subsections_via_symbols
