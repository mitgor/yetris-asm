// ============================================================================
// yetris-asm: AArch64 Assembly Tetris Clone for macOS Apple Silicon
// File: asm/board.s -- Board operations: collision detection, piece locking,
//                      line marking and clearing, board reset
// Build: make asm
//
// Provides:
//   _is_piece_valid:       Check if a piece at (type, rotation, px, py) fits on board
//   _lock_piece:            Lock current piece into board array, add score, clear lines
//   _mark_lines:            Detect full rows and mark with flash value (9)
//   _clear_marked_lines:    Collapse marked rows after flash delay
//   _reset_board:            Zero board and reset all game state to initial values
//   _add_noise:              Fill bottom rows with random garbage blocks
//
// All functions operate on global state variables defined in data.s.
// Data access uses adrp+add (@PAGE/@PAGEOFF) since all .s files link into
// the same binary.
//
// Darwin ARM64 ABI: x0-x15 caller-saved, x19-x28 callee-saved, x18 reserved.
// ============================================================================

.section __TEXT,__text,regular,pure_instructions

// ----------------------------------------------------------------------------
// _is_piece_valid(w0=type, w1=rotation, w2=px, w3=py) -> w0=1 valid, 0 invalid
//
// Core collision detection. Iterates the piece's 5x5 grid and checks each
// non-empty cell against board bounds and occupancy.
//
// piece_data index: type*100 + rotation*25 + row*5 + col
// board index: board_y * 10 + board_x
//
// Uses callee-saved: x19=type, x20=rotation, x21=px(signed), x22=py(signed),
//                    x23=row counter, x24=col counter
// Stack: 64 bytes (6 callee-saved + x29/x30)
// ----------------------------------------------------------------------------
.globl _is_piece_valid
.p2align 2
_is_piece_valid:
    // Prologue: save callee-saved registers + frame pointer
    stp     x29, x30, [sp, #-64]!
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    mov     x29, sp

    // Save arguments in callee-saved registers
    mov     w19, w0                 // w19 = type (0-6)
    mov     w20, w1                 // w20 = rotation (0-3)
    sxtw    x21, w2                 // x21 = px (sign-extended)
    sxtw    x22, w3                 // x22 = py (sign-extended)

    // Load _piece_data base address
    adrp    x8, _piece_data@PAGE
    add     x8, x8, _piece_data@PAGEOFF

    // Compute base offset: type*100 + rotation*25
    mov     w9, #100
    mul     w9, w19, w9             // type * 100
    mov     w10, #25
    mul     w10, w20, w10           // rotation * 25
    add     w9, w9, w10             // base offset
    add     x8, x8, x9             // x8 = &piece_data[type][rotation][0][0]

    // Load _board base address
    adrp    x9, _board@PAGE
    add     x9, x9, _board@PAGEOFF  // x9 = &board[0]

    // Iterate 5x5 grid: row 0-4, col 0-4
    mov     w23, #0                 // row = 0
Lvalid_row_loop:
    mov     w24, #0                 // col = 0
Lvalid_col_loop:
    // Load piece cell: piece_data[row*5 + col]
    mov     w10, #5
    mul     w10, w23, w10           // row * 5
    add     w10, w10, w24           // row*5 + col
    ldrb    w11, [x8, x10]         // w11 = cell value

    // If cell == 0 (empty), skip this cell
    cbz     w11, Lvalid_next_col

    // Compute board coordinates
    add     w12, w21, w24           // board_x = px + col (signed)
    add     w13, w22, w23           // board_y = py + row (signed)
    sxtw    x12, w12               // sign-extend for comparisons
    sxtw    x13, w13

    // Check wall collision: board_x < 0
    cmp     x12, #0
    b.lt    Lvalid_fail

    // Check wall collision: board_x >= 10
    cmp     x12, #10
    b.ge    Lvalid_fail

    // Check floor collision: board_y >= 20
    cmp     x13, #20
    b.ge    Lvalid_fail

    // If board_y < 0: above board, valid (piece still spawning)
    cmp     x13, #0
    b.lt    Lvalid_next_col

    // Check block collision: board[board_y * 10 + board_x]
    mov     w14, #10
    mul     w14, w13, w14           // board_y * 10
    add     w14, w14, w12           // board_y*10 + board_x
    uxtw    x14, w14
    ldrb    w15, [x9, x14]         // board cell value
    cbnz    w15, Lvalid_fail       // if non-zero, collision

Lvalid_next_col:
    add     w24, w24, #1
    cmp     w24, #5
    b.lt    Lvalid_col_loop

    // Next row
    add     w23, w23, #1
    cmp     w23, #5
    b.lt    Lvalid_row_loop

    // All 25 cells checked, no collision
    mov     w0, #1
    b       Lvalid_epilogue

Lvalid_fail:
    mov     w0, #0

Lvalid_epilogue:
    // Epilogue: restore callee-saved registers
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

// ----------------------------------------------------------------------------
// _lock_piece() -> w0 = number of lines cleared (0-4)
//
// Locks the current piece into the board array and handles scoring/clearing:
// 1. Load current piece state from data.s globals
// 2. For each non-zero cell in piece's 5x5 grid, write (piece_type+1) to board
// 3. Update stats (_stats_pieces, _stats_piece_counts)
// 4. Call _mark_lines to detect full rows and mark for flash animation
// 5. Scoring engine: base_score*level, b2b bonus, combo bonus, perfect clear
// 6. Return lines cleared count
//
// Uses callee-saved: x19=piece_type, x20=piece_rotation, x21=piece_x,
//                    x22=piece_y, x23=row, x24=col
// Stack: 64 bytes (6 callee-saved + x29/x30)
// ----------------------------------------------------------------------------
.globl _lock_piece
.p2align 2
_lock_piece:
    // Prologue
    stp     x29, x30, [sp, #-64]!
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    mov     x29, sp

    // Load current piece state from data.s globals
    adrp    x8, _piece_type@PAGE
    add     x8, x8, _piece_type@PAGEOFF
    ldrb    w19, [x8]              // w19 = piece_type (0-6)

    adrp    x8, _piece_rotation@PAGE
    add     x8, x8, _piece_rotation@PAGEOFF
    ldrb    w20, [x8]              // w20 = piece_rotation (0-3)

    adrp    x8, _piece_x@PAGE
    add     x8, x8, _piece_x@PAGEOFF
    ldrsh   w21, [x8]              // w21 = piece_x (signed)

    adrp    x8, _piece_y@PAGE
    add     x8, x8, _piece_y@PAGEOFF
    ldrsh   w22, [x8]              // w22 = piece_y (signed)

    // Load _piece_data base address
    adrp    x8, _piece_data@PAGE
    add     x8, x8, _piece_data@PAGEOFF

    // Compute piece grid base: type*100 + rotation*25
    mov     w9, #100
    mul     w9, w19, w9
    mov     w10, #25
    mul     w10, w20, w10
    add     w9, w9, w10
    add     x8, x8, x9             // x8 = &piece_data[type][rotation][0][0]

    // Load _board base address
    adrp    x9, _board@PAGE
    add     x9, x9, _board@PAGEOFF

    // Store piece_type + 1 as the board cell value (1-7 for color)
    add     w15, w19, #1            // w15 = piece_type + 1

    // Iterate 5x5 grid
    mov     w23, #0                 // row = 0
Llock_row_loop:
    mov     w24, #0                 // col = 0
Llock_col_loop:
    // Load piece cell
    mov     w10, #5
    mul     w10, w23, w10
    add     w10, w10, w24
    ldrb    w11, [x8, x10]
    cbz     w11, Llock_next_col     // skip empty cells

    // Compute board position
    add     w12, w21, w24           // board_x = piece_x + col
    add     w13, w22, w23           // board_y = piece_y + row

    // Bounds check: only write if within board
    cmp     w13, #0
    b.lt    Llock_next_col          // above board, skip
    cmp     w13, #20
    b.ge    Llock_next_col          // below board, skip
    cmp     w12, #0
    b.lt    Llock_next_col          // left of board, skip
    cmp     w12, #10
    b.ge    Llock_next_col          // right of board, skip

    // Write to board: board[board_y * 10 + board_x] = piece_type + 1
    mov     w14, #10
    mul     w14, w13, w14
    add     w14, w14, w12
    uxtw    x14, w14
    strb    w15, [x9, x14]

Llock_next_col:
    add     w24, w24, #1
    cmp     w24, #5
    b.lt    Llock_col_loop

    add     w23, w23, #1
    cmp     w23, #5
    b.lt    Llock_row_loop

    // Increment _stats_pieces (total pieces locked)
    adrp    x8, _stats_pieces@PAGE
    add     x8, x8, _stats_pieces@PAGEOFF
    ldr     w9, [x8]
    add     w9, w9, #1
    str     w9, [x8]

    // Increment _stats_piece_counts[piece_type]
    adrp    x8, _stats_piece_counts@PAGE
    add     x8, x8, _stats_piece_counts@PAGEOFF
    uxtw    x9, w19                     // w19 = piece_type (0-6)
    ldr     w10, [x8, x9, lsl #2]      // load count (each .word = 4 bytes)
    add     w10, w10, #1
    str     w10, [x8, x9, lsl #2]      // store incremented count

    // Reset _can_hold to 1 (allow hold again for next piece)
    adrp    x8, _can_hold@PAGE
    add     x8, x8, _can_hold@PAGEOFF
    mov     w9, #1
    strb    w9, [x8]

    // =====================================================================
    // T-SPIN DETECTION (before _mark_lines, after piece written to board)
    // Check: piece_type==6 (T) AND _last_was_rotation==1 AND 3+ corners occupied
    // =====================================================================
    adrp    x8, _is_tspin@PAGE
    strb    wzr, [x8, _is_tspin@PAGEOFF]       // default: not a T-spin

    cmp     w19, #6                             // w19 = piece_type (loaded earlier)
    b.ne    Ltspin_done                         // not T-piece -> skip

    adrp    x8, _last_was_rotation@PAGE
    ldrb    w8, [x8, _last_was_rotation@PAGEOFF]
    cbz     w8, Ltspin_done                     // last action was not rotation -> skip

    // T-piece placed after rotation -- check 3-corner rule
    // Pivot is at grid position (2,2) in piece_data
    // Board pivot coords: pivot_x = piece_x + 2, pivot_y = piece_y + 2
    add     w8, w21, #2                         // w8 = pivot_x (w21 = piece_x)
    add     w9, w22, #2                         // w9 = pivot_y (w22 = piece_y)

    // Load board base for corner checks
    adrp    x10, _board@PAGE
    add     x10, x10, _board@PAGEOFF

    mov     w11, #0                             // occupied_count = 0

    // Corner 1: (pivot_y-1, pivot_x-1)
    sub     w12, w9, #1                         // cy
    sub     w13, w8, #1                         // cx
    // Bounds check: out-of-bounds counts as occupied
    cmp     w13, #0
    b.lt    Lc1_occ
    cmp     w13, #10
    b.ge    Lc1_occ
    cmp     w12, #0
    b.lt    Lc1_occ
    cmp     w12, #20
    b.ge    Lc1_occ
    // In bounds: check board cell
    mov     w14, #10
    mul     w14, w12, w14
    add     w14, w14, w13
    uxtw    x14, w14
    ldrb    w15, [x10, x14]
    cbz     w15, Lc1_done                       // empty -> not occupied
Lc1_occ:
    add     w11, w11, #1
Lc1_done:

    // Corner 2: (pivot_y-1, pivot_x+1)
    sub     w12, w9, #1
    add     w13, w8, #1
    cmp     w13, #0
    b.lt    Lc2_occ
    cmp     w13, #10
    b.ge    Lc2_occ
    cmp     w12, #0
    b.lt    Lc2_occ
    cmp     w12, #20
    b.ge    Lc2_occ
    mov     w14, #10
    mul     w14, w12, w14
    add     w14, w14, w13
    uxtw    x14, w14
    ldrb    w15, [x10, x14]
    cbz     w15, Lc2_done
Lc2_occ:
    add     w11, w11, #1
Lc2_done:

    // Corner 3: (pivot_y+1, pivot_x-1)
    add     w12, w9, #1
    sub     w13, w8, #1
    cmp     w13, #0
    b.lt    Lc3_occ
    cmp     w13, #10
    b.ge    Lc3_occ
    cmp     w12, #0
    b.lt    Lc3_occ
    cmp     w12, #20
    b.ge    Lc3_occ
    mov     w14, #10
    mul     w14, w12, w14
    add     w14, w14, w13
    uxtw    x14, w14
    ldrb    w15, [x10, x14]
    cbz     w15, Lc3_done
Lc3_occ:
    add     w11, w11, #1
Lc3_done:

    // Corner 4: (pivot_y+1, pivot_x+1)
    add     w12, w9, #1
    add     w13, w8, #1
    cmp     w13, #0
    b.lt    Lc4_occ
    cmp     w13, #10
    b.ge    Lc4_occ
    cmp     w12, #0
    b.lt    Lc4_occ
    cmp     w12, #20
    b.ge    Lc4_occ
    mov     w14, #10
    mul     w14, w12, w14
    add     w14, w14, w13
    uxtw    x14, w14
    ldrb    w15, [x10, x14]
    cbz     w15, Lc4_done
Lc4_occ:
    add     w11, w11, #1
Lc4_done:

    // Check: occupied_count >= 3 means T-spin
    cmp     w11, #3
    b.lt    Ltspin_done
    // T-spin detected!
    adrp    x8, _is_tspin@PAGE
    mov     w9, #1
    strb    w9, [x8, _is_tspin@PAGEOFF]

Ltspin_done:
    // =====================================================================
    // END T-SPIN DETECTION
    // =====================================================================

    // Call _mark_lines to detect full rows and mark with value 9 (flash)
    bl      _mark_lines
    // w0 = lines marked count (returned by _mark_lines)
    mov     w24, w0                 // save lines_cleared in callee-saved reg

    // =====================================================================
    // SCORING ENGINE (Phase 8: modern guideline scoring)
    // All scoring happens here in _lock_piece after _mark_lines returns.
    // Pipeline: base_score -> b2b bonus -> add to _score -> combo -> perfect clear
    // =====================================================================

    // If lines_cleared == 0: check T-spin zero, then reset combo
    cbnz    w24, Lscore_lines_cleared

    // No lines cleared: check for T-spin zero first
    adrp    x8, _is_tspin@PAGE
    ldrb    w8, [x8, _is_tspin@PAGEOFF]
    cbz     w8, Ltspin_zero_skip

    // T-spin with 0 lines: award _tspin_score_table[0] * _level = 400 * level
    adrp    x8, _tspin_score_table@PAGE
    add     x8, x8, _tspin_score_table@PAGEOFF
    ldr     w10, [x8]                // w10 = 400 (T-spin zero base)
    adrp    x8, _level@PAGE
    ldr     w11, [x8, _level@PAGEOFF]
    mul     w10, w10, w11            // w10 = 400 * level
    adrp    x8, _score@PAGE
    add     x8, x8, _score@PAGEOFF
    ldr     w11, [x8]
    add     w11, w11, w10
    str     w11, [x8]                // _score += tspin_zero_bonus

Ltspin_zero_skip:
    // Reset _combo_count to 0 (T-spin zero does NOT contribute to combo)
    adrp    x8, _combo_count@PAGE
    add     x8, x8, _combo_count@PAGEOFF
    str     wzr, [x8]
    b       Lscore_done

Lscore_lines_cleared:
    // --- Base score: select table based on T-spin ---
    adrp    x8, _is_tspin@PAGE
    ldrb    w8, [x8, _is_tspin@PAGEOFF]
    cbnz    w8, Ltspin_base_score

    // Normal line clear: _score_table[lines-1] * _level
    adrp    x8, _score_table@PAGE
    add     x8, x8, _score_table@PAGEOFF
    sub     w9, w24, #1              // index = lines - 1
    ldr     w10, [x8, w9, uxtw #2]  // w10 = base (100/300/500/800)
    b       Lbase_score_done

Ltspin_base_score:
    // T-spin with lines: _tspin_score_table[lines] * _level
    // Index = lines (not lines-1): table[1]=800, table[2]=1200, table[3]=1600
    adrp    x8, _tspin_score_table@PAGE
    add     x8, x8, _tspin_score_table@PAGEOFF
    ldr     w10, [x8, w24, uxtw #2] // w10 = tspin base (800/1200/1600)

Lbase_score_done:
    adrp    x8, _level@PAGE
    ldr     w11, [x8, _level@PAGEOFF]
    mul     w10, w10, w11            // w10 = base * level (line_clear_score)

    // --- Back-to-back check ---
    // Difficult = Tetris (lines == 4) OR (T-spin with lines > 0)
    mov     w12, #0
    cmp     w24, #4                  // Tetris?
    b.eq    Lset_difficult
    adrp    x8, _is_tspin@PAGE
    ldrb    w8, [x8, _is_tspin@PAGEOFF]
    cbz     w8, Lnot_difficult       // not T-spin -> not difficult
    // T-spin with lines > 0 is difficult (we already know lines > 0 here)
Lset_difficult:
    mov     w12, #1
Lnot_difficult:

    // If b2b_active AND is_difficult: apply 1.5x bonus to line_clear_score
    cbz     w12, Lb2b_not_difficult

    // Current clear is difficult -- check if b2b was active
    adrp    x8, _b2b_active@PAGE
    add     x8, x8, _b2b_active@PAGEOFF
    ldrb    w9, [x8]
    cbz     w9, Lb2b_set_active       // first difficult clear, no bonus yet

    // B2B active + current difficult: apply 1.5x bonus
    add     w10, w10, w10, lsr #1    // score = score * 1.5
    b       Lb2b_set_active

Lb2b_not_difficult:
    // Non-difficult clear with lines > 0: break B2B chain
    adrp    x8, _b2b_active@PAGE
    add     x8, x8, _b2b_active@PAGEOFF
    strb    wzr, [x8]                 // _b2b_active = 0
    b       Lb2b_done

Lb2b_set_active:
    // Set _b2b_active = 1 (current clear is difficult)
    adrp    x8, _b2b_active@PAGE
    add     x8, x8, _b2b_active@PAGEOFF
    mov     w9, #1
    strb    w9, [x8]

Lb2b_done:
    // --- Add line clear score to _score ---
    adrp    x8, _score@PAGE
    add     x8, x8, _score@PAGEOFF
    ldr     w11, [x8]
    add     w11, w11, w10
    str     w11, [x8]

    // --- Combo bonus ---
    // Increment _combo_count, then add 50 * _combo_count * _level
    adrp    x8, _combo_count@PAGE
    add     x8, x8, _combo_count@PAGEOFF
    ldr     w9, [x8]
    add     w9, w9, #1
    str     w9, [x8]                  // _combo_count++

    mov     w10, #50
    mul     w10, w9, w10              // combo_count * 50
    adrp    x11, _level@PAGE
    ldr     w11, [x11, _level@PAGEOFF]
    mul     w10, w10, w11             // combo_count * 50 * level

    adrp    x8, _score@PAGE
    add     x8, x8, _score@PAGEOFF
    ldr     w11, [x8]
    add     w11, w11, w10
    str     w11, [x8]                 // _score += combo bonus

    // --- Perfect clear check ---
    // Scan entire 200-byte board to check if empty
    adrp    x8, _board@PAGE
    add     x8, x8, _board@PAGEOFF
    mov     w9, #0                    // byte index
    mov     w13, #0                   // accumulator (OR all bytes)
Lpc_scan:
    ldrb    w14, [x8, x9]
    orr     w13, w13, w14
    add     w9, w9, #1
    cmp     w9, #200
    b.lt    Lpc_scan
    cbnz    w13, Lscore_done          // any non-zero byte -> not perfect

    // Board is empty! Award perfect clear bonus
    adrp    x8, _perfect_clear_table@PAGE
    add     x8, x8, _perfect_clear_table@PAGEOFF
    sub     w9, w24, #1
    ldr     w10, [x8, w9, uxtw #2]   // base perfect clear bonus
    adrp    x8, _level@PAGE
    ldr     w11, [x8, _level@PAGEOFF]
    mul     w10, w10, w11             // bonus * level

    adrp    x8, _score@PAGE
    add     x8, x8, _score@PAGEOFF
    ldr     w11, [x8]
    add     w11, w11, w10
    str     w11, [x8]                 // _score += perfect clear bonus

Lscore_done:
    // =====================================================================
    // END SCORING ENGINE
    // =====================================================================

    // Live hi-score update: _hiscore = max(_score, _hiscore) (Phase 11)
    adrp    x8, _hiscore@PAGE
    add     x8, x8, _hiscore@PAGEOFF
    ldr     w9, [x8]                   // current hiscore
    adrp    x10, _score@PAGE
    ldr     w11, [x10, _score@PAGEOFF] // current score
    cmp     w11, w9
    csel    w9, w11, w9, hi            // w9 = max(score, hiscore)
    str     w9, [x8]                   // update hiscore if score is higher

    // Check invisible mode: if enabled, hide all locked cells
    adrp    x8, _opt_invisible@PAGE
    ldrb    w9, [x8, _opt_invisible@PAGEOFF]
    cbz     w9, Llock_skip_invisible

    // Set all non-zero board cells to 8 (invisible marker)
    adrp    x8, _board@PAGE
    add     x8, x8, _board@PAGEOFF
    mov     w9, #0
Llock_invis_loop:
    ldrb    w10, [x8, x9]
    cbz     w10, Llock_invis_next   // skip empty cells
    mov     w10, #8                 // invisible marker
    strb    w10, [x8, x9]
Llock_invis_next:
    add     w9, w9, #1
    cmp     w9, #200
    b.lt    Llock_invis_loop

Llock_skip_invisible:
    mov     w0, w24                 // restore lines_cleared return value

    // Epilogue
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

// ----------------------------------------------------------------------------
// _mark_lines() -> w0 = number of lines marked (0-4)
//
// Scan the board bottom-to-top for full rows. When found:
// 1. Overwrite all 10 cells in the row with value 9 (flash marker)
// 2. Do NOT shift rows -- that happens in _clear_marked_lines after delay
// 3. After marking, update _lines_cleared, _level, and line-type stats
// 4. If lines > 0: set _line_clear_state=1 and record _line_clear_timer
// 5. Return lines_marked count in w0
//
// Uses callee-saved: x19=board base, x20=row counter, x21=lines marked count,
//                    x22=col/byte counter, x23=shift row, x24=temp
// Stack: 64 bytes
// ----------------------------------------------------------------------------
.globl _mark_lines
.p2align 2
_mark_lines:
    // Prologue
    stp     x29, x30, [sp, #-64]!
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    mov     x29, sp

    // Load board base address
    adrp    x19, _board@PAGE
    add     x19, x19, _board@PAGEOFF

    mov     w21, #0                 // lines_marked_count = 0
    mov     w20, #19                // row = 19 (bottom)

Lmark_row_loop:
    cmp     w20, #0
    b.lt    Lmark_done              // if row < 0, done scanning

    // NEON full-row check: vectorized min across 16 bytes
    mov     w10, #10
    mul     w10, w20, w10           // row * 10 = row offset
    uxtw    x10, w10
    add     x10, x19, x10          // x10 = &board[row*10]

    ld1     {v0.16b}, [x10]        // load 16 bytes (10 data + 6 padding)
    adrp    x11, _neon_row_mask@PAGE
    add     x11, x11, _neon_row_mask@PAGEOFF
    ldr     q1, [x11]              // load mask (0x00*10 + 0xFF*6)
    orr     v0.16b, v0.16b, v1.16b // force padding bytes to non-zero
    uminv   b2, v0.16b             // unsigned min across all 16 bytes
    umov    w11, v2.b[0]           // extract scalar minimum
    cbz     w11, Lmark_not_full    // if min==0, at least one cell empty

    // Row is full -- increment count
    add     w21, w21, #1

    // Overwrite all 10 cells with value 9 (flash marker)
    mov     w10, #10
    mul     w10, w20, w10           // row * 10 = row offset
    uxtw    x10, w10
    mov     w22, #0                 // col counter
Lmark_fill:
    mov     w8, #9
    add     x9, x19, x10           // &board[row*10]
    strb    w8, [x9, x22]
    add     w22, w22, #1
    cmp     w22, #10
    b.lt    Lmark_fill

Lmark_not_full:
    // Move up one row (always decrement -- no re-check needed since we don't shift)
    sub     w20, w20, #1
    b       Lmark_row_loop

Lmark_done:
    // If lines were marked, update lines/level/stats
    cbz     w21, Lmark_return

    // Add lines to _lines_cleared
    adrp    x8, _lines_cleared@PAGE
    add     x8, x8, _lines_cleared@PAGEOFF
    ldr     w11, [x8]
    add     w11, w11, w21
    str     w11, [x8]              // _lines_cleared += count

    // Recompute _level: scan _level_thresholds to find highest level
    // where threshold <= _lines_cleared
    // w11 still holds total _lines_cleared
    adrp    x8, _level_thresholds@PAGE
    add     x8, x8, _level_thresholds@PAGEOFF

    mov     w12, #1                 // level = 1 (minimum)
    mov     w13, #0                 // index = 0
Lmark_level_scan:
    cmp     w13, #22
    b.ge    Lmark_level_done
    ldrh    w14, [x8, w13, uxtw #1] // threshold = level_thresholds[index]
    cmp     w11, w14
    b.lt    Lmark_level_done        // lines_cleared < threshold, stop
    add     w12, w13, #2            // level = index + 2
    add     w13, w13, #1
    b       Lmark_level_scan

Lmark_level_done:
    // Store computed level
    adrp    x8, _level@PAGE
    add     x8, x8, _level@PAGEOFF
    str     w12, [x8]

    // Increment line clear type statistic based on w21 (lines_marked_count)
    cmp     w21, #1
    b.ne    Lmark_not_single
    adrp    x8, _stats_singles@PAGE
    add     x8, x8, _stats_singles@PAGEOFF
    ldr     w9, [x8]
    add     w9, w9, #1
    str     w9, [x8]
    b       Lmark_stats_done

Lmark_not_single:
    cmp     w21, #2
    b.ne    Lmark_not_double
    adrp    x8, _stats_doubles@PAGE
    add     x8, x8, _stats_doubles@PAGEOFF
    ldr     w9, [x8]
    add     w9, w9, #1
    str     w9, [x8]
    b       Lmark_stats_done

Lmark_not_double:
    cmp     w21, #3
    b.ne    Lmark_not_triple
    adrp    x8, _stats_triples@PAGE
    add     x8, x8, _stats_triples@PAGEOFF
    ldr     w9, [x8]
    add     w9, w9, #1
    str     w9, [x8]
    b       Lmark_stats_done

Lmark_not_triple:
    // Must be 4 (tetris)
    adrp    x8, _stats_tetris@PAGE
    add     x8, x8, _stats_tetris@PAGEOFF
    ldr     w9, [x8]
    add     w9, w9, #1
    str     w9, [x8]

Lmark_stats_done:
    // Set _line_clear_state = 1 (flash active)
    adrp    x8, _line_clear_state@PAGE
    mov     w9, #1
    strb    w9, [x8, _line_clear_state@PAGEOFF]

    // Record current time as flash start
    bl      _get_time_ms            // x0 = current time ms
    adrp    x8, _line_clear_timer@PAGE
    str     x0, [x8, _line_clear_timer@PAGEOFF]

Lmark_return:
    mov     w0, w21                 // return lines marked count
    // Epilogue
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

// ----------------------------------------------------------------------------
// _clear_marked_lines() -> void
//
// Scan board for rows marked with value 9 (flash marker) and collapse them
// by shifting all rows above down. Called from game loop after flash delay.
//
// Uses callee-saved: x19=board base, x20=row counter, x21=unused,
//                    x22=col counter, x23=shift row, x24=temp
// Stack: 64 bytes
// ----------------------------------------------------------------------------
.globl _clear_marked_lines
.p2align 2
_clear_marked_lines:
    // Prologue
    stp     x29, x30, [sp, #-64]!
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    mov     x29, sp

    // Load board base address
    adrp    x19, _board@PAGE
    add     x19, x19, _board@PAGEOFF

    mov     w20, #19                // row = 19 (bottom)

Lcml_row_loop:
    cmp     w20, #0
    b.lt    Lcml_done               // if row < 0, done scanning

    // Check if row is marked: cell[0] == 9
    mov     w10, #10
    mul     w10, w20, w10           // row * 10
    uxtw    x10, w10
    ldrb    w11, [x19, x10]        // board[row*10 + 0]
    cmp     w11, #9
    b.ne    Lcml_not_marked

    // Row is marked: shift all rows above down by one
    mov     w23, w20                // j = current row
Lcml_shift_loop:
    cmp     w23, #0
    b.le    Lcml_fill_top           // if j <= 0, done shifting

    // Copy row (j-1) to row j: 10 bytes
    sub     w24, w23, #1            // source row = j-1
    mov     w10, #10
    mul     w11, w23, w10           // dest offset = j * 10
    mul     w12, w24, w10           // src offset = (j-1) * 10
    uxtw    x11, w11
    uxtw    x12, w12

    // Copy 10 bytes from src to dest
    mov     w22, #0                 // byte counter
Lcml_copy_byte:
    ldrb    w14, [x19, x12]
    strb    w14, [x19, x11]
    add     x11, x11, #1
    add     x12, x12, #1
    add     w22, w22, #1
    cmp     w22, #10
    b.lt    Lcml_copy_byte

    sub     w23, w23, #1
    b       Lcml_shift_loop

Lcml_fill_top:
    // Fill row 0 with zeros (10 bytes at offset 0)
    mov     w22, #0
Lcml_zero_top:
    strb    wzr, [x19, x22]
    add     w22, w22, #1
    cmp     w22, #10
    b.lt    Lcml_zero_top

    // Re-check same row (don't decrement -- new content from above)
    b       Lcml_row_loop

Lcml_not_marked:
    // Row not marked, move to next row above
    sub     w20, w20, #1
    b       Lcml_row_loop

Lcml_done:
    // Epilogue
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

// ----------------------------------------------------------------------------
// _reset_board()
//
// Zero all 200 bytes of _board. Reset _score=0, _level=1, _lines_cleared=0,
// _game_over=0.
//
// Stack: 16 bytes (x29/x30 only)
// ----------------------------------------------------------------------------
.globl _reset_board
.p2align 2
_reset_board:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Zero the 200-byte board array
    adrp    x8, _board@PAGE
    add     x8, x8, _board@PAGEOFF
    mov     w9, #0
Lreset_board_loop:
    strb    wzr, [x8, x9]
    add     w9, w9, #1
    cmp     w9, #200
    b.lt    Lreset_board_loop

    // Reset _score to 0
    adrp    x8, _score@PAGE
    add     x8, x8, _score@PAGEOFF
    str     wzr, [x8]

    // Reset _level to 1
    adrp    x8, _level@PAGE
    add     x8, x8, _level@PAGEOFF
    mov     w9, #1
    str     w9, [x8]

    // Reset _lines_cleared to 0
    adrp    x8, _lines_cleared@PAGE
    add     x8, x8, _lines_cleared@PAGEOFF
    str     wzr, [x8]

    // Reset _game_over to 0
    adrp    x8, _game_over@PAGE
    add     x8, x8, _game_over@PAGEOFF
    strb    wzr, [x8]

    // Reset _hold_piece_type to 0xFF (empty)
    adrp    x8, _hold_piece_type@PAGE
    add     x8, x8, _hold_piece_type@PAGEOFF
    mov     w9, #0xFF
    strb    w9, [x8]

    // Reset _can_hold to 1
    adrp    x8, _can_hold@PAGE
    add     x8, x8, _can_hold@PAGEOFF
    mov     w9, #1
    strb    w9, [x8]

    // Reset _is_paused to 0
    adrp    x8, _is_paused@PAGE
    add     x8, x8, _is_paused@PAGEOFF
    strb    wzr, [x8]

    // Reset _stats_pieces to 0
    adrp    x8, _stats_pieces@PAGE
    add     x8, x8, _stats_pieces@PAGEOFF
    str     wzr, [x8]

    // Reset _stats_piece_counts (7 words = 28 bytes)
    adrp    x8, _stats_piece_counts@PAGE
    add     x8, x8, _stats_piece_counts@PAGEOFF
    mov     w9, #0
Lreset_stats_loop:
    str     wzr, [x8, w9, uxtw]
    add     w9, w9, #4
    cmp     w9, #28
    b.lt    Lreset_stats_loop

    // Reset _stats_singles/doubles/triples/tetris to 0
    adrp    x8, _stats_singles@PAGE
    add     x8, x8, _stats_singles@PAGEOFF
    str     wzr, [x8]

    adrp    x8, _stats_doubles@PAGE
    add     x8, x8, _stats_doubles@PAGEOFF
    str     wzr, [x8]

    adrp    x8, _stats_triples@PAGE
    add     x8, x8, _stats_triples@PAGEOFF
    str     wzr, [x8]

    adrp    x8, _stats_tetris@PAGE
    add     x8, x8, _stats_tetris@PAGEOFF
    str     wzr, [x8]

    // Reset _combo_count to 0
    adrp    x8, _combo_count@PAGE
    add     x8, x8, _combo_count@PAGEOFF
    str     wzr, [x8]

    // Reset _b2b_active to 0
    adrp    x8, _b2b_active@PAGE
    add     x8, x8, _b2b_active@PAGEOFF
    strb    wzr, [x8]

    // Reset _last_was_rotation to 0
    adrp    x8, _last_was_rotation@PAGE
    strb    wzr, [x8, _last_was_rotation@PAGEOFF]

    // Reset _is_tspin to 0
    adrp    x8, _is_tspin@PAGE
    strb    wzr, [x8, _is_tspin@PAGEOFF]

    // Reset _line_clear_state to 0
    adrp    x8, _line_clear_state@PAGE
    strb    wzr, [x8, _line_clear_state@PAGEOFF]

    ldp     x29, x30, [sp], #16
    ret

// ----------------------------------------------------------------------------
// _add_noise(w0 = num_rows)
//
// Fill the bottom num_rows of the board with random garbage blocks.
// Each row has at least 1 gap (random empty column). Other cells have
// a 50% chance of being filled with a random piece color (1-7).
//
// Precondition: board is empty (called after _reset_board, before _spawn_piece)
// Clamps num_rows to 0-19 (must leave at least 1 empty row for spawning).
//
// Uses callee-saved: x19=num_rows, x20=board_base, x21=current_row,
//                    x22=gap_col, x23=col_counter
// Stack: 64 bytes
// ----------------------------------------------------------------------------
.globl _add_noise
.p2align 2
_add_noise:
    stp     x29, x30, [sp, #-64]!
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    mov     x29, sp

    mov     w19, w0                 // w19 = num_rows to fill
    cbz     w19, Lnoise_done        // 0 rows = nothing to do
    cmp     w19, #19
    b.le    Lnoise_clamp_ok
    mov     w19, #19                // clamp to 19 max
Lnoise_clamp_ok:

    adrp    x20, _board@PAGE
    add     x20, x20, _board@PAGEOFF  // x20 = board base

    // Fill from row 19 (bottom) upward, filling w19 rows total
    mov     w21, #19                // w21 = current row (start at bottom)

Lnoise_row:
    // Check if we've filled enough rows
    mov     w8, #19
    sub     w8, w8, w21             // rows_filled = 19 - current_row
    cmp     w8, w19
    b.ge    Lnoise_done

    // Choose random gap column: arc4random_uniform(10)
    mov     w0, #10
    bl      _arc4random_uniform
    mov     w22, w0                 // w22 = gap column

    // Fill 10 columns of this row
    mov     w23, #0                 // col = 0
Lnoise_col:
    cmp     w23, w22
    b.eq    Lnoise_skip             // this is the gap, leave empty

    // 50% chance of placing a block
    mov     w0, #2
    bl      _arc4random_uniform
    cbz     w0, Lnoise_skip         // 0 = no block

    // Random piece color: arc4random_uniform(7) + 1
    mov     w0, #7
    bl      _arc4random_uniform
    add     w0, w0, #1              // cell value 1-7

    // Store in board[row * 10 + col]
    mov     w8, #10
    mul     w8, w21, w8
    add     w8, w8, w23
    uxtw    x8, w8
    strb    w0, [x20, x8]
    b       Lnoise_next_col

Lnoise_skip:
    // Leave cell as 0 (empty)
Lnoise_next_col:
    add     w23, w23, #1
    cmp     w23, #10
    b.lt    Lnoise_col

    sub     w21, w21, #1            // move up one row
    b       Lnoise_row

Lnoise_done:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

// ============================================================================
.subsections_via_symbols
