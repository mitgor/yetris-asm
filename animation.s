// ============================================================================
// yetris-asm: AArch64 Assembly Tetris Clone for macOS Apple Silicon
// File: asm/animation.s -- Background animation system (fire, water, snakes,
//                          Game of Life) with dispatch table and timer-gated
//                          updates
// Build: make asm
//
// Phase 10: Four background animation types dispatched via function pointer
// table. A random type is selected at startup.
// Each animation handles its own timer check internally.
//
// Fire: bottom-row heat spawn, upward propagation, cooling map, red/yellow/white
// Water: double-buffer wave propagation, ripple injection, blue/cyan/white
// Snakes: falling green Matrix-style entities, '@' head 'o' body, swap-removal
// Life: Conway B3/S23 rules, double-buffer, yellow '#' living cells
//
// Exports: _anim_select_random, _anim_dispatch, _anim_init
//          _anim_fire_update_and_draw, _anim_fire_init
//          _anim_water_update_and_draw, _anim_water_init
//          _anim_snakes_update_and_draw, _anim_snakes_init
//          _anim_life_update_and_draw, _anim_life_init
//
// Data dependencies (from asm/data.s):
//   _anim_type, _anim_last_update, _anim_buf1, _anim_buf2
//
// ncurses functions used:
//   _wattr_on, _wattr_off, _mvwaddch
//
// Timer function: _get_time_ms (from timer.s)
// Random function: _arc4random_uniform (libc)
// ============================================================================

.section __TEXT,__text,regular,pure_instructions

// ============================================================================
// Constants
// ============================================================================
.equ ANIM_WIDTH, 80
.equ ANIM_HEIGHT, 24
.equ ANIM_CELLS, 1920           // 80 * 24
.equ FIRE_UPDATE_RATE, 100      // ms between fire updates
.equ WATER_UPDATE_RATE, 300     // ms between water updates
.equ LIFE_UPDATE_RATE, 200      // ms between GoL updates
.equ SNAKE_MOVE_RATE, 50        // ms between snake moves
.equ SNAKE_ADD_RATE, 200        // ms between snake adds
.equ SNAKE_MAX, 50              // maximum active snakes

// COLOR_PAIR(n) = n << 8
.equ COLOR_PAIR_1, 0x0100       // yellow on black
.equ COLOR_PAIR_2, 0x0200       // cyan on black
.equ COLOR_PAIR_3, 0x0300       // white on black
.equ COLOR_PAIR_4, 0x0400       // blue on black
.equ COLOR_PAIR_5, 0x0500       // green on black
.equ COLOR_PAIR_6, 0x0600       // red on black
.equ A_BOLD, 0x00200000

// ============================================================================
// _anim_select_random: Select a random animation type at startup
// void _anim_select_random(void)
//
// Calls _arc4random_uniform(4) to pick 0-3, stores in _anim_type,
// then calls _anim_init to initialize the selected animation's buffers.
// ============================================================================
.globl _anim_select_random
.p2align 2
_anim_select_random:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    mov     w0, #4                      // 4 animation types
    bl      _arc4random_uniform         // w0 = 0-3
    adrp    x8, _anim_type@PAGE
    strb    w0, [x8, _anim_type@PAGEOFF]

    bl      _anim_init

    ldp     x29, x30, [sp], #16
    ret

// ============================================================================
// _anim_init: Initialize the selected animation's buffers
// void _anim_init(void)
//
// Dispatches to the appropriate init function based on _anim_type.
// ============================================================================
.globl _anim_init
.p2align 2
_anim_init:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x8, _anim_type@PAGE
    ldrb    w9, [x8, _anim_type@PAGEOFF]

    cbz     w9, Linit_fire              // 0 = fire
    cmp     w9, #1
    b.eq    Linit_water                 // 1 = water
    cmp     w9, #2
    b.eq    Linit_snakes                // 2 = snakes
    cmp     w9, #3
    b.eq    Linit_life                  // 3 = life
    b       Linit_done

Linit_fire:
    bl      _anim_fire_init
    b       Linit_done

Linit_water:
    bl      _anim_water_init
    b       Linit_done

Linit_snakes:
    bl      _anim_snakes_init
    b       Linit_done

Linit_life:
    bl      _anim_life_init

Linit_done:
    ldp     x29, x30, [sp], #16
    ret

// ============================================================================
// _anim_dispatch: Call the selected animation's update+draw function
// void _anim_dispatch(WINDOW* win)
//
// x0 = WINDOW* to draw into (passed through to animation function)
// Loads _anim_type, indexes into dispatch table, tail-calls the function.
// ============================================================================
.globl _anim_dispatch
.p2align 2
_anim_dispatch:
    stp     x19, x20, [sp, #-16]!
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    mov     x19, x0                     // save WINDOW* in callee-saved

    adrp    x8, _anim_type@PAGE
    ldrb    w9, [x8, _anim_type@PAGEOFF]

    // Index into dispatch table
    adrp    x8, _anim_update_table@PAGE
    add     x8, x8, _anim_update_table@PAGEOFF
    uxtw    x9, w9
    ldr     x10, [x8, x9, lsl #3]      // function pointer

    mov     x0, x19                     // restore WINDOW* as first arg
    blr     x10                         // call animation function

    ldp     x29, x30, [sp], #16
    ldp     x19, x20, [sp], #16
    ret

// ============================================================================
// _anim_fire_init: Initialize fire animation buffers
// void _anim_fire_init(void)
//
// Zeros _anim_buf1 (intensity buffer).
// Creates cooling map in _anim_buf2: random values 0-13 per cell,
// then smoothed 10 times by averaging with 4 neighbors.
// ============================================================================
.globl _anim_fire_init
.p2align 2
_anim_fire_init:
    stp     x22, x21, [sp, #-32]!
    stp     x20, x19, [sp, #16]
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Zero _anim_buf1 (intensity buffer) -- 3840 bytes = 480 quadwords
    adrp    x19, _anim_buf1@PAGE
    add     x19, x19, _anim_buf1@PAGEOFF
    mov     x8, x19
    mov     w9, #480                    // 3840 / 8
Lfire_zero_loop:
    str     xzr, [x8], #8
    subs    w9, w9, #1
    b.ne    Lfire_zero_loop

    // Fill _anim_buf2 (cooling map) with random values 0-13
    adrp    x20, _anim_buf2@PAGE
    add     x20, x20, _anim_buf2@PAGEOFF
    mov     w21, #0                     // cell counter (0..1919)

Lfire_cool_fill:
    cmp     w21, #ANIM_CELLS
    b.ge    Lfire_cool_fill_done

    mov     w0, #14                     // range 0-13
    bl      _arc4random_uniform         // w0 = 0-13
    uxtw    x8, w21
    strh    w0, [x20, x8, lsl #1]       // store as halfword

    add     w21, w21, #1
    b       Lfire_cool_fill

Lfire_cool_fill_done:
    // Smooth cooling map 10 times
    mov     w22, #10                    // smooth passes

Lfire_smooth_pass:
    cbz     w22, Lfire_init_done

    // For interior cells: row 1..22, col 1..78
    mov     w9, #1                      // row
Lfire_smooth_row:
    cmp     w9, #23                     // ANIM_HEIGHT - 1
    b.ge    Lfire_smooth_pass_done

    mov     w10, #1                     // col
Lfire_smooth_col:
    cmp     w10, #79                    // ANIM_WIDTH - 1
    b.ge    Lfire_smooth_col_done

    // cell index = row * 80 + col
    mov     w11, #ANIM_WIDTH
    mul     w12, w9, w11                // row * 80
    add     w12, w12, w10               // + col

    // Load neighbors: up, down, left, right
    sub     w13, w12, #ANIM_WIDTH       // (row-1)*80+col
    add     w14, w12, #ANIM_WIDTH       // (row+1)*80+col
    sub     w15, w12, #1                // row*80+(col-1)
    add     w11, w12, #1                // row*80+(col+1)

    uxtw    x13, w13
    uxtw    x14, w14
    uxtw    x15, w15
    uxtw    x11, w11
    uxtw    x12, w12

    ldrsh   w0, [x20, x13, lsl #1]     // up
    ldrsh   w1, [x20, x14, lsl #1]     // down
    ldrsh   w2, [x20, x15, lsl #1]     // left
    ldrsh   w3, [x20, x11, lsl #1]     // right

    add     w0, w0, w1
    add     w0, w0, w2
    add     w0, w0, w3
    asr     w0, w0, #2                  // / 4

    strh    w0, [x20, x12, lsl #1]      // store smoothed value

    add     w10, w10, #1
    b       Lfire_smooth_col

Lfire_smooth_col_done:
    add     w9, w9, #1
    b       Lfire_smooth_row

Lfire_smooth_pass_done:
    sub     w22, w22, #1
    b       Lfire_smooth_pass

Lfire_init_done:
    ldp     x29, x30, [sp], #16
    ldp     x20, x19, [sp, #16]
    ldp     x22, x21, [sp], #32
    ret

// ============================================================================
// _anim_fire_update_and_draw: Complete fire animation (update + draw)
// void _anim_fire_update_and_draw(WINDOW* win)
//
// Register plan:
//   x19 = WINDOW* (callee-saved)
//   x20 = _anim_buf1 base pointer (intensity)
//   x21 = _anim_buf2 base (cooling map)
//   w22 = row counter
//   w23 = col counter
//   w24 = width constant (80)
//   w25 = height constant (24)
//   x26 = grayscale string pointer
//   w27 = cooling_ratio
// ============================================================================
.globl _anim_fire_update_and_draw
.p2align 2
_anim_fire_update_and_draw:
    stp     x28, x27, [sp, #-80]!
    stp     x26, x25, [sp, #16]
    stp     x24, x23, [sp, #32]
    stp     x22, x21, [sp, #48]
    stp     x20, x19, [sp, #64]
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    mov     x19, x0                     // save WINDOW*
    mov     w24, #ANIM_WIDTH
    mov     w25, #ANIM_HEIGHT

    adrp    x20, _anim_buf1@PAGE
    add     x20, x20, _anim_buf1@PAGEOFF
    adrp    x21, _anim_buf2@PAGE
    add     x21, x21, _anim_buf2@PAGEOFF

    adrp    x26, Lfire_grayscale@PAGE
    add     x26, x26, Lfire_grayscale@PAGEOFF

    // === Timer check ===
    bl      _get_time_ms                // x0 = current ms
    mov     x28, x0                     // save current time in x28 temporarily
    adrp    x8, _anim_last_update@PAGE
    add     x8, x8, _anim_last_update@PAGEOFF
    ldr     x9, [x8]                    // last update time
    sub     x10, x28, x9                // elapsed = now - last
    cmp     x10, #FIRE_UPDATE_RATE
    b.lt    Lfire_draw_only             // skip update, still draw

    // Update timer
    str     x28, [x8]

    // === FIRE UPDATE ===

    // Pick cooling_ratio = arc4random_uniform(10) + 3  (range 3-12)
    mov     w0, #10
    bl      _arc4random_uniform
    add     w27, w0, #3                 // w27 = cooling_ratio (3-12)

    // 10% chance burst (ratio=1): arc4random_uniform(10), if 0 -> ratio=1
    mov     w0, #10
    bl      _arc4random_uniform
    cbnz    w0, Lfire_no_burst
    mov     w27, #1
Lfire_no_burst:

    // 12% chance dim (ratio=30): arc4random_uniform(100), if < 12 -> ratio=30
    mov     w0, #100
    bl      _arc4random_uniform
    cmp     w0, #12
    b.ge    Lfire_no_dim
    mov     w27, #30
Lfire_no_dim:

    // === Bottom row (row 23): set to random high intensity ===
    mov     w23, #0                     // col = 0
Lfire_bottom_loop:
    cmp     w23, #ANIM_WIDTH
    b.ge    Lfire_bottom_done

    mov     w0, #11                     // range 0-10
    bl      _arc4random_uniform
    add     w0, w0, #90                 // range 90-100

    // Store to buf1[23*80+col]
    mov     w8, #23
    mul     w8, w8, w24                 // 23 * 80
    add     w8, w8, w23                 // + col
    uxtw    x8, w8
    strh    w0, [x20, x8, lsl #1]

    add     w23, w23, #1
    b       Lfire_bottom_loop

Lfire_bottom_done:

    // === Sparks: for each col, 2.31% chance to inject spark ===
    mov     w23, #0
Lfire_sparks_loop:
    cmp     w23, #ANIM_WIDTH
    b.ge    Lfire_sparks_done

    mov     w0, #433
    bl      _arc4random_uniform         // w0 = 0-432
    cmp     w0, #10
    b.ge    Lfire_no_spark

    // Inject spark at row (23 - random(3,6)) = 23 - (arc4random(4) + 3)
    mov     w0, #4
    bl      _arc4random_uniform         // w0 = 0-3
    add     w0, w0, #3                  // 3-6
    mov     w8, #23
    sub     w8, w8, w0                  // row = 23 - offset (range 17-20)

    // Spark intensity: random(90,100)
    stp     x8, xzr, [sp, #-16]!       // save row
    mov     w0, #11
    bl      _arc4random_uniform
    add     w9, w0, #90                 // intensity 90-100
    ldp     x8, xzr, [sp], #16         // restore row

    // Store to buf1[row*80+col]
    mul     w10, w8, w24                // row * 80
    add     w10, w10, w23               // + col
    uxtw    x10, w10
    strh    w9, [x20, x10, lsl #1]

Lfire_no_spark:
    add     w23, w23, #1
    b       Lfire_sparks_loop

Lfire_sparks_done:

    // === Propagate upward: row 0 to 22, all cols ===
    // intensity[row*80+col] = intensity[(row+1)*80+col] - cooling_ratio - cooling[row*80+col]
    // Clamp >= 0
    mov     w22, #0                     // row = 0
Lfire_prop_row:
    cmp     w22, #23                    // row < height-1 (23)
    b.ge    Lfire_prop_done

    mov     w23, #0                     // col = 0
Lfire_prop_col:
    cmp     w23, #ANIM_WIDTH
    b.ge    Lfire_prop_col_done

    // Source: buf1[(row+1)*80+col]
    add     w8, w22, #1                 // row + 1
    mul     w8, w8, w24                 // (row+1) * 80
    add     w8, w8, w23                 // + col
    uxtw    x8, w8
    ldrsh   w9, [x20, x8, lsl #1]      // intensity from row below (signed)

    // Destination index: row*80+col
    mul     w10, w22, w24               // row * 80
    add     w10, w10, w23               // + col
    uxtw    x10, w10

    // Cooling from map: buf2[row*80+col]
    ldrsh   w11, [x21, x10, lsl #1]    // cooling map value (signed)

    // new_intensity = source - cooling_ratio - cooling_map
    sub     w9, w9, w27                 // - cooling_ratio
    sub     w9, w9, w11                 // - cooling_map

    // Clamp to 0 if negative
    cmp     w9, #0
    csel    w9, wzr, w9, lt

    // Store to buf1[row*80+col]
    strh    w9, [x20, x10, lsl #1]

    add     w23, w23, #1
    b       Lfire_prop_col

Lfire_prop_col_done:
    add     w22, w22, #1
    b       Lfire_prop_row

Lfire_prop_done:

Lfire_draw_only:
    // === DRAW: For each cell, map intensity to char + color ===
    mov     w22, #0                     // row = 0
Lfire_draw_row:
    cmp     w22, #ANIM_HEIGHT
    b.ge    Lfire_draw_done

    mov     w23, #0                     // col = 0
Lfire_draw_col:
    cmp     w23, #ANIM_WIDTH
    b.ge    Lfire_draw_col_done

    // Load intensity from buf1[row*80+col]
    mul     w8, w22, w24                // row * 80
    add     w8, w8, w23                 // + col
    uxtw    x8, w8
    ldrsh   w9, [x20, x8, lsl #1]      // intensity (signed)

    // Skip if intensity <= 20
    cmp     w9, #20
    b.le    Lfire_draw_next

    // Map intensity to char index: (intensity * 12) / 101 -> 0-11
    mov     w10, #12
    mul     w10, w9, w10                // intensity * 12
    mov     w11, #101
    udiv    w10, w10, w11               // / 101 -> char_index (0-11)

    // Load grayscale char
    uxtw    x10, w10
    ldrb    w12, [x26, x10]             // char from grayscale string

    // Map intensity to color attribute
    cmp     w9, #80
    b.gt    Lfire_color_white
    cmp     w9, #60
    b.gt    Lfire_color_yellow_bold
    cmp     w9, #40
    b.gt    Lfire_color_yellow
    // else: red bold (intensity 21-40)
    mov     w13, #COLOR_PAIR_6
    movk    w13, #0x0020, lsl #16       // | A_BOLD
    b       Lfire_draw_cell

Lfire_color_white:
    mov     w13, #COLOR_PAIR_3
    movk    w13, #0x0020, lsl #16       // | A_BOLD (white bold)
    b       Lfire_draw_cell

Lfire_color_yellow_bold:
    mov     w13, #COLOR_PAIR_1
    movk    w13, #0x0020, lsl #16       // | A_BOLD (yellow bold)
    b       Lfire_draw_cell

Lfire_color_yellow:
    mov     w13, #COLOR_PAIR_1          // yellow (no bold)
    b       Lfire_draw_cell

Lfire_draw_cell:
    // w12 = char, w13 = attr (both caller-saved, need saving across bl)
    // w22, w23 are callee-saved (x19-x28 range) -- survive bl calls

    // wattr_on(win, attr, NULL)
    mov     x0, x19                     // WINDOW*
    mov     w1, w13                     // attr
    mov     x2, #0                      // NULL
    stp     x12, x13, [sp, #-16]!      // save char + attr across calls
    bl      _wattr_on

    // mvwaddch(win, row, col, char)
    ldp     x12, x13, [sp]             // peek char + attr (don't pop yet)
    mov     x0, x19                     // WINDOW*
    mov     w1, w22                     // row (callee-saved, still valid)
    mov     w2, w23                     // col (callee-saved, still valid)
    mov     w3, w12                     // char
    bl      _mvwaddch

    // wattr_off(win, attr, NULL)
    ldp     x12, x13, [sp], #16        // restore + pop char, attr
    mov     x0, x19
    mov     w1, w13                     // attr
    mov     x2, #0
    bl      _wattr_off

Lfire_draw_next:
    add     w23, w23, #1
    b       Lfire_draw_col

Lfire_draw_col_done:
    add     w22, w22, #1
    b       Lfire_draw_row

Lfire_draw_done:
    ldp     x29, x30, [sp], #16
    ldp     x20, x19, [sp, #64]
    ldp     x22, x21, [sp, #48]
    ldp     x24, x23, [sp, #32]
    ldp     x26, x25, [sp, #16]
    ldp     x28, x27, [sp], #80
    ret

// ============================================================================
// _anim_water_init: Initialize water animation buffers
// void _anim_water_init(void)
//
// Fills buf1 with random 0-13 halfwords, buf2 with random 0-25 halfwords.
// Sets swap flag to 0.
// ============================================================================
.globl _anim_water_init
.p2align 2
_anim_water_init:
    stp     x22, x21, [sp, #-32]!
    stp     x20, x19, [sp, #16]
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Fill buf1 with random 0-13
    adrp    x19, _anim_buf1@PAGE
    add     x19, x19, _anim_buf1@PAGEOFF
    mov     w20, #0                     // cell counter

Lwater_init_buf1:
    cmp     w20, #ANIM_CELLS
    b.ge    Lwater_init_buf1_done
    mov     w0, #14                     // range 0-13
    bl      _arc4random_uniform
    uxtw    x8, w20
    strh    w0, [x19, x8, lsl #1]
    add     w20, w20, #1
    b       Lwater_init_buf1

Lwater_init_buf1_done:
    // Fill buf2 with random 0-25
    adrp    x21, _anim_buf2@PAGE
    add     x21, x21, _anim_buf2@PAGEOFF
    mov     w20, #0

Lwater_init_buf2:
    cmp     w20, #ANIM_CELLS
    b.ge    Lwater_init_buf2_done
    mov     w0, #26                     // range 0-25
    bl      _arc4random_uniform
    uxtw    x8, w20
    strh    w0, [x21, x8, lsl #1]
    add     w20, w20, #1
    b       Lwater_init_buf2

Lwater_init_buf2_done:
    // Set swap flag to 0
    adrp    x8, Lanim_buf_swap@PAGE
    strb    wzr, [x8, Lanim_buf_swap@PAGEOFF]

    ldp     x29, x30, [sp], #16
    ldp     x20, x19, [sp, #16]
    ldp     x22, x21, [sp], #32
    ret

// ============================================================================
// _anim_water_update_and_draw: Water animation with wave propagation
// void _anim_water_update_and_draw(WINDOW* win)
//
// Register plan:
//   x19 = WINDOW*
//   x20 = read buffer base (old)
//   x21 = write buffer base (new)
//   w22 = row counter
//   w23 = col counter
//   w24 = ANIM_WIDTH (80)
//   w25 = scratch / height value
//   x26 = grayscale string pointer
//   w27 = scratch
//   x28 = current time
// ============================================================================
.globl _anim_water_update_and_draw
.p2align 2
_anim_water_update_and_draw:
    stp     x28, x27, [sp, #-80]!
    stp     x26, x25, [sp, #16]
    stp     x24, x23, [sp, #32]
    stp     x22, x21, [sp, #48]
    stp     x20, x19, [sp, #64]
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    mov     x19, x0                     // save WINDOW*
    mov     w24, #ANIM_WIDTH

    // Load buffer pointers based on swap flag
    adrp    x8, Lanim_buf_swap@PAGE
    ldrb    w9, [x8, Lanim_buf_swap@PAGEOFF]

    adrp    x20, _anim_buf1@PAGE
    add     x20, x20, _anim_buf1@PAGEOFF
    adrp    x21, _anim_buf2@PAGE
    add     x21, x21, _anim_buf2@PAGEOFF

    // If swap flag = 1, swap read/write
    cbz     w9, Lwater_no_ptr_swap
    mov     x8, x20
    mov     x20, x21
    mov     x21, x8
Lwater_no_ptr_swap:

    // === Timer check ===
    bl      _get_time_ms
    mov     x28, x0
    adrp    x8, _anim_last_update@PAGE
    add     x8, x8, _anim_last_update@PAGEOFF
    ldr     x9, [x8]
    sub     x10, x28, x9
    cmp     x10, #WATER_UPDATE_RATE
    b.lt    Lwater_draw_only

    // Update timer
    str     x28, [x8]

    // === WATER UPDATE ===

    // Toggle swap flag
    adrp    x8, Lanim_buf_swap@PAGE
    ldrb    w9, [x8, Lanim_buf_swap@PAGEOFF]
    eor     w9, w9, #1
    strb    w9, [x8, Lanim_buf_swap@PAGEOFF]

    // After toggling, swap read/write pointers for this update
    mov     x8, x20
    mov     x20, x21
    mov     x21, x8

    // Random ripple injection: 1/323 chance
    mov     w0, #323
    bl      _arc4random_uniform
    cbnz    w0, Lwater_no_ripple

    // Inject ripple: random position, height = 90
    mov     w0, #ANIM_WIDTH
    bl      _arc4random_uniform
    mov     w22, w0                     // col
    mov     w0, #ANIM_HEIGHT
    bl      _arc4random_uniform
    // index = row * 80 + col
    mul     w8, w0, w24
    add     w8, w8, w22
    uxtw    x8, w8
    mov     w9, #90
    strh    w9, [x21, x8, lsl #1]      // write to write-buffer

Lwater_no_ripple:
    // Wave propagation: interior cells (row 1..22, col 1..78)
    mov     w22, #1                     // row = 1
Lwater_prop_row:
    cmp     w22, #23                    // row < 23
    b.ge    Lwater_prop_done

    mov     w23, #1                     // col = 1
Lwater_prop_col:
    cmp     w23, #79                    // col < 79
    b.ge    Lwater_prop_col_done

    // cell index = row * 80 + col
    mul     w8, w22, w24
    add     w8, w8, w23

    // Load 4 neighbors from READ buffer (old)
    sub     w9, w8, #ANIM_WIDTH         // (row-1)*80+col
    add     w10, w8, #ANIM_WIDTH        // (row+1)*80+col
    sub     w11, w8, #1                 // row*80+(col-1)
    add     w12, w8, #1                 // row*80+(col+1)

    uxtw    x9, w9
    uxtw    x10, w10
    uxtw    x11, w11
    uxtw    x12, w12
    uxtw    x8, w8

    ldrsh   w13, [x20, x9, lsl #1]     // up
    ldrsh   w14, [x20, x10, lsl #1]    // down
    ldrsh   w15, [x20, x11, lsl #1]    // left
    ldrsh   w16, [x20, x12, lsl #1]    // right

    // new = ((up + down + left + right) >> 1) - current_write
    add     w13, w13, w14
    add     w13, w13, w15
    add     w13, w13, w16
    asr     w13, w13, #1               // sum / 2

    ldrsh   w14, [x21, x8, lsl #1]    // current write-buffer value
    sub     w13, w13, w14              // - new[row*80+col]

    // Clamp to [0, 100]
    cmp     w13, #0
    csel    w13, wzr, w13, lt
    cmp     w13, #100
    mov     w14, #100
    csel    w13, w14, w13, gt

    strh    w13, [x21, x8, lsl #1]

    add     w23, w23, #1
    b       Lwater_prop_col

Lwater_prop_col_done:
    add     w22, w22, #1
    b       Lwater_prop_row

Lwater_prop_done:

Lwater_draw_only:
    // === DRAW: Map height to char + color ===
    // Reload write-buffer pointer (the one with current data)
    adrp    x8, Lanim_buf_swap@PAGE
    ldrb    w9, [x8, Lanim_buf_swap@PAGEOFF]
    adrp    x20, _anim_buf1@PAGE
    add     x20, x20, _anim_buf1@PAGEOFF
    adrp    x21, _anim_buf2@PAGE
    add     x21, x21, _anim_buf2@PAGEOFF
    // If swap=0: write-buf was buf2. If swap=1: write-buf was buf1.
    // After toggle: swap=0 means last write was to buf2. swap=1 means last write was to buf1.
    // Actually, we draw from the write buffer (the one just updated).
    // swap flag was toggled BEFORE update. If flag now = 1: read was buf1, write was buf2.
    // If flag now = 0: read was buf2, write was buf1.
    // So: if flag=1, draw from buf2. If flag=0, draw from buf1.
    cbz     w9, Lwater_draw_buf1
    mov     x26, x21                   // draw from buf2
    b       Lwater_draw_start
Lwater_draw_buf1:
    mov     x26, x20                   // draw from buf1
Lwater_draw_start:

    adrp    x27, Lwater_grayscale@PAGE
    add     x27, x27, Lwater_grayscale@PAGEOFF

    mov     w22, #0                     // row = 0
Lwater_draw_row:
    cmp     w22, #ANIM_HEIGHT
    b.ge    Lwater_draw_done

    mov     w23, #0                     // col = 0
Lwater_draw_col:
    cmp     w23, #ANIM_WIDTH
    b.ge    Lwater_draw_col_done

    // Load height from draw buffer
    mul     w8, w22, w24
    add     w8, w8, w23
    uxtw    x8, w8
    ldrsh   w25, [x26, x8, lsl #1]     // height (signed)

    // Skip if height <= 0
    cmp     w25, #0
    b.le    Lwater_draw_next

    // Map height to char index: (height * 11) / 101 -> 0-10
    mov     w8, #11
    mul     w8, w25, w8
    mov     w9, #101
    udiv    w8, w8, w9                  // char_index (0-10)

    // Load grayscale char
    uxtw    x8, w8
    ldrb    w12, [x27, x8]             // char

    // Map height to color attribute
    cmp     w25, #80
    b.gt    Lwater_color_white
    cmp     w25, #60
    b.gt    Lwater_color_cyan_bold
    cmp     w25, #40
    b.gt    Lwater_color_cyan
    cmp     w25, #20
    b.gt    Lwater_color_blue
    // else: blue bold (height 1-20)
    mov     w13, #COLOR_PAIR_4
    movk    w13, #0x0020, lsl #16       // | A_BOLD
    b       Lwater_draw_cell

Lwater_color_white:
    mov     w13, #COLOR_PAIR_3
    movk    w13, #0x0020, lsl #16       // | A_BOLD (white bold)
    b       Lwater_draw_cell

Lwater_color_cyan_bold:
    mov     w13, #COLOR_PAIR_2
    movk    w13, #0x0020, lsl #16       // | A_BOLD (cyan bold)
    b       Lwater_draw_cell

Lwater_color_cyan:
    mov     w13, #COLOR_PAIR_2          // cyan
    b       Lwater_draw_cell

Lwater_color_blue:
    mov     w13, #COLOR_PAIR_4          // blue
    b       Lwater_draw_cell

Lwater_draw_cell:
    // wattr_on(win, attr, NULL)
    mov     x0, x19
    mov     w1, w13
    mov     x2, #0
    stp     x12, x13, [sp, #-16]!
    bl      _wattr_on

    // mvwaddch(win, row, col, char)
    ldp     x12, x13, [sp]
    mov     x0, x19
    mov     w1, w22
    mov     w2, w23
    mov     w3, w12
    bl      _mvwaddch

    // wattr_off(win, attr, NULL)
    ldp     x12, x13, [sp], #16
    mov     x0, x19
    mov     w1, w13
    mov     x2, #0
    bl      _wattr_off

Lwater_draw_next:
    add     w23, w23, #1
    b       Lwater_draw_col

Lwater_draw_col_done:
    add     w22, w22, #1
    b       Lwater_draw_row

Lwater_draw_done:
    ldp     x29, x30, [sp], #16
    ldp     x20, x19, [sp, #64]
    ldp     x22, x21, [sp, #48]
    ldp     x24, x23, [sp, #32]
    ldp     x26, x25, [sp, #16]
    ldp     x28, x27, [sp], #80
    ret

// ============================================================================
// _anim_snakes_init: Initialize snakes animation
// void _anim_snakes_init(void)
//
// Creates first snake, sets timers.
// ============================================================================
.globl _anim_snakes_init
.p2align 2
_anim_snakes_init:
    stp     x20, x19, [sp, #-16]!
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Get current time for timers
    bl      _get_time_ms
    mov     x19, x0

    adrp    x8, _anim_last_update@PAGE
    str     x19, [x8, _anim_last_update@PAGEOFF]
    adrp    x8, _anim_last_add@PAGE
    str     x19, [x8, _anim_last_add@PAGEOFF]

    // Set snake count to 1
    adrp    x8, _anim_snake_count@PAGE
    mov     w9, #1
    strb    w9, [x8, _anim_snake_count@PAGEOFF]

    // Create first snake: x = random(1..79), y = 0, size = random(2..14)
    mov     w0, #79
    bl      _arc4random_uniform
    add     w20, w0, #1                 // x = 1..79

    mov     w0, #13
    bl      _arc4random_uniform
    add     w0, w0, #2                  // size = 2..14

    // Store snake[0]: {x, y=0, size, pad=0}
    adrp    x8, _anim_snakes@PAGE
    add     x8, x8, _anim_snakes@PAGEOFF
    strb    w20, [x8, #0]              // x
    strb    wzr, [x8, #1]             // y = 0
    strb    w0, [x8, #2]              // size
    strb    wzr, [x8, #3]             // pad

    ldp     x29, x30, [sp], #16
    ldp     x20, x19, [sp], #16
    ret

// ============================================================================
// _anim_snakes_update_and_draw: Matrix-style falling snakes animation
// void _anim_snakes_update_and_draw(WINDOW* win)
//
// Register plan:
//   x19 = WINDOW*
//   x20 = _anim_snakes base
//   w21 = loop index i
//   w22 = snake count (_anim_snake_count)
//   w23 = snake x
//   w24 = snake y
//   w25 = snake size
//   x26 = scratch for struct address
//   x27 = scratch
//   x28 = current time
// ============================================================================
.globl _anim_snakes_update_and_draw
.p2align 2
_anim_snakes_update_and_draw:
    stp     x28, x27, [sp, #-80]!
    stp     x26, x25, [sp, #16]
    stp     x24, x23, [sp, #32]
    stp     x22, x21, [sp, #48]
    stp     x20, x19, [sp, #64]
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    mov     x19, x0                     // save WINDOW*

    adrp    x20, _anim_snakes@PAGE
    add     x20, x20, _anim_snakes@PAGEOFF

    // === Move timer check (50ms) ===
    bl      _get_time_ms
    mov     x28, x0
    adrp    x8, _anim_last_update@PAGE
    add     x8, x8, _anim_last_update@PAGEOFF
    ldr     x9, [x8]
    sub     x10, x28, x9
    cmp     x10, #SNAKE_MOVE_RATE
    b.lt    Lsnake_check_add

    // Update move timer
    str     x28, [x8]

    // Move all snakes down: increment y, remove if off-screen
    adrp    x8, _anim_snake_count@PAGE
    ldrb    w22, [x8, _anim_snake_count@PAGEOFF]

    mov     w21, #0                     // i = 0
Lsnake_move_loop:
    cmp     w21, w22
    b.ge    Lsnake_move_done

    // Load snake[i]
    uxtw    x26, w21
    lsl     x26, x26, #2               // i * 4
    add     x26, x20, x26              // &snakes[i]

    ldrb    w23, [x26, #0]             // x
    ldrb    w24, [x26, #1]             // y (unsigned byte)
    ldrb    w25, [x26, #2]             // size

    // Increment y
    add     w24, w24, #1

    // Check removal: (y - size) >= 24
    sub     w8, w24, w25
    cmp     w8, #24
    b.lt    Lsnake_keep

    // Remove: swap with last snake
    sub     w22, w22, #1               // decrement count
    uxtw    x8, w22
    lsl     x8, x8, #2                // last * 4
    add     x8, x20, x8
    ldr     w9, [x8]                   // load last snake (4 bytes)
    str     w9, [x26]                  // overwrite current with last
    // Do NOT increment i -- recheck this index
    b       Lsnake_move_loop

Lsnake_keep:
    strb    w24, [x26, #1]             // store updated y
    add     w21, w21, #1
    b       Lsnake_move_loop

Lsnake_move_done:
    // Store updated count
    adrp    x8, _anim_snake_count@PAGE
    strb    w22, [x8, _anim_snake_count@PAGEOFF]

Lsnake_check_add:
    // === Add timer check (200ms) ===
    adrp    x8, _anim_last_add@PAGE
    add     x8, x8, _anim_last_add@PAGEOFF
    ldr     x9, [x8]
    sub     x10, x28, x9
    cmp     x10, #SNAKE_ADD_RATE
    b.lt    Lsnake_draw

    // Update add timer
    str     x28, [x8]

    // Load current count
    adrp    x8, _anim_snake_count@PAGE
    ldrb    w22, [x8, _anim_snake_count@PAGEOFF]

    // Add one snake if room
    cmp     w22, #SNAKE_MAX
    b.ge    Lsnake_draw

    // Create new snake
    mov     w0, #79
    bl      _arc4random_uniform
    add     w23, w0, #1                 // x = 1..79

    mov     w0, #4
    bl      _arc4random_uniform
    mov     w24, w0                     // y = 0..3

    mov     w0, #13
    bl      _arc4random_uniform
    add     w25, w0, #2                 // size = 2..14

    // Store snake[count]
    uxtw    x26, w22
    lsl     x26, x26, #2
    add     x26, x20, x26
    strb    w23, [x26, #0]             // x
    strb    w24, [x26, #1]             // y
    strb    w25, [x26, #2]             // size
    strb    wzr, [x26, #3]             // pad

    add     w22, w22, #1

    // 25% burst chance: add 3-5 extra snakes
    mov     w0, #4
    bl      _arc4random_uniform
    cbnz    w0, Lsnake_add_done

    // Burst: add 3-5 extra snakes
    stp     x22, xzr, [sp, #-16]!     // save count
    mov     w0, #3
    bl      _arc4random_uniform
    add     w27, w0, #3                 // 3..5 extra snakes
    ldp     x22, xzr, [sp], #16

Lsnake_burst_loop:
    cbz     w27, Lsnake_add_done
    cmp     w22, #SNAKE_MAX
    b.ge    Lsnake_add_done

    stp     x27, xzr, [sp, #-16]!     // save burst counter
    mov     w0, #79
    bl      _arc4random_uniform
    add     w23, w0, #1
    mov     w0, #4
    bl      _arc4random_uniform
    mov     w24, w0
    mov     w0, #13
    bl      _arc4random_uniform
    add     w25, w0, #2
    ldp     x27, xzr, [sp], #16       // restore burst counter

    uxtw    x26, w22
    lsl     x26, x26, #2
    add     x26, x20, x26
    strb    w23, [x26, #0]
    strb    w24, [x26, #1]
    strb    w25, [x26, #2]
    strb    wzr, [x26, #3]

    add     w22, w22, #1
    sub     w27, w27, #1
    b       Lsnake_burst_loop

Lsnake_add_done:
    // Store updated count
    adrp    x8, _anim_snake_count@PAGE
    strb    w22, [x8, _anim_snake_count@PAGEOFF]

Lsnake_draw:
    // === DRAW: For each active snake, draw head + body ===
    adrp    x8, _anim_snake_count@PAGE
    ldrb    w22, [x8, _anim_snake_count@PAGEOFF]

    mov     w21, #0                     // i = 0
Lsnake_draw_loop:
    cmp     w21, w22
    b.ge    Lsnake_draw_done

    // Load snake[i]
    uxtw    x26, w21
    lsl     x26, x26, #2
    add     x26, x20, x26

    ldrb    w23, [x26, #0]             // x
    ldrb    w24, [x26, #1]             // y (unsigned)
    ldrb    w25, [x26, #2]             // size

    // Draw head: '@' at (y, x) if 0 <= y < 24
    cmp     w24, #24
    b.ge    Lsnake_draw_body

    // wattr_on: COLOR_PAIR(5) | A_BOLD (green bold)
    mov     x0, x19
    mov     w1, #COLOR_PAIR_5
    movk    w1, #0x0020, lsl #16        // | A_BOLD
    mov     x2, #0
    bl      _wattr_on

    // mvwaddch(win, y, x, '@')
    mov     x0, x19
    mov     w1, w24                     // row = y
    mov     w2, w23                     // col = x
    mov     w3, #'@'
    bl      _mvwaddch

    // wattr_off
    mov     x0, x19
    mov     w1, #COLOR_PAIR_5
    movk    w1, #0x0020, lsl #16
    mov     x2, #0
    bl      _wattr_off

Lsnake_draw_body:
    // Draw body: 'o' at (y-j, x) for j = 1 to size-1
    // wattr_on: COLOR_PAIR(5) (green, no bold)
    mov     x0, x19
    mov     w1, #COLOR_PAIR_5
    mov     x2, #0
    bl      _wattr_on

    mov     w27, #1                     // j = 1
Lsnake_body_loop:
    cmp     w27, w25                    // j < size
    b.ge    Lsnake_body_done

    sub     w8, w24, w27               // body_y = y - j
    // Check 0 <= body_y < 24
    cmp     w8, #0
    b.lt    Lsnake_body_next
    cmp     w8, #24
    b.ge    Lsnake_body_next

    // mvwaddch(win, body_y, x, 'o')
    mov     x0, x19
    mov     w1, w8                      // row = body_y
    mov     w2, w23                     // col = x
    mov     w3, #'o'
    bl      _mvwaddch

Lsnake_body_next:
    add     w27, w27, #1
    b       Lsnake_body_loop

Lsnake_body_done:
    // wattr_off: COLOR_PAIR(5)
    mov     x0, x19
    mov     w1, #COLOR_PAIR_5
    mov     x2, #0
    bl      _wattr_off

    add     w21, w21, #1
    b       Lsnake_draw_loop

Lsnake_draw_done:
    ldp     x29, x30, [sp], #16
    ldp     x20, x19, [sp, #64]
    ldp     x22, x21, [sp, #48]
    ldp     x24, x23, [sp, #32]
    ldp     x26, x25, [sp, #16]
    ldp     x28, x27, [sp], #80
    ret

// ============================================================================
// _anim_life_init: Initialize Game of Life buffers
// void _anim_life_init(void)
//
// 20% random fill in buf1, zero buf2.
// ============================================================================
.globl _anim_life_init
.p2align 2
_anim_life_init:
    stp     x20, x19, [sp, #-16]!
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x19, _anim_buf1@PAGE
    add     x19, x19, _anim_buf1@PAGEOFF

    // 20% random fill for buf1
    mov     w20, #0
Llife_init_fill:
    cmp     w20, #ANIM_CELLS
    b.ge    Llife_init_fill_done

    mov     w0, #5                      // 20% chance (1/5)
    bl      _arc4random_uniform
    uxtw    x8, w20
    cbnz    w0, Llife_init_dead
    mov     w9, #1                      // alive
    strh    w9, [x19, x8, lsl #1]
    b       Llife_init_next
Llife_init_dead:
    strh    wzr, [x19, x8, lsl #1]     // dead
Llife_init_next:
    add     w20, w20, #1
    b       Llife_init_fill

Llife_init_fill_done:
    // Zero buf2 entirely: 3840 bytes = 480 quadwords
    adrp    x8, _anim_buf2@PAGE
    add     x8, x8, _anim_buf2@PAGEOFF
    mov     w9, #480
Llife_zero_buf2:
    str     xzr, [x8], #8
    subs    w9, w9, #1
    b.ne    Llife_zero_buf2

    // Set swap flag to 0
    adrp    x8, Lanim_buf_swap@PAGE
    strb    wzr, [x8, Lanim_buf_swap@PAGEOFF]

    ldp     x29, x30, [sp], #16
    ldp     x20, x19, [sp], #16
    ret

// ============================================================================
// _anim_life_update_and_draw: Conway's Game of Life animation
// void _anim_life_update_and_draw(WINDOW* win)
//
// Register plan:
//   x19 = WINDOW*
//   x20 = read buffer (current gen)
//   x21 = write buffer (next gen)
//   w22 = row counter
//   w23 = col counter
//   w24 = ANIM_WIDTH (80)
//   w25 = neighbor count / cell state
//   w26 = scratch
//   w27 = scratch
//   x28 = current time
// ============================================================================
.globl _anim_life_update_and_draw
.p2align 2
_anim_life_update_and_draw:
    stp     x28, x27, [sp, #-80]!
    stp     x26, x25, [sp, #16]
    stp     x24, x23, [sp, #32]
    stp     x22, x21, [sp, #48]
    stp     x20, x19, [sp, #64]
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    mov     x19, x0                     // save WINDOW*
    mov     w24, #ANIM_WIDTH

    // Load buffer pointers based on swap flag
    adrp    x8, Lanim_buf_swap@PAGE
    ldrb    w9, [x8, Lanim_buf_swap@PAGEOFF]

    adrp    x20, _anim_buf1@PAGE
    add     x20, x20, _anim_buf1@PAGEOFF
    adrp    x21, _anim_buf2@PAGE
    add     x21, x21, _anim_buf2@PAGEOFF

    // If swap=1: read from buf2, write to buf1
    cbz     w9, Llife_no_ptr_swap
    mov     x8, x20
    mov     x20, x21
    mov     x21, x8
Llife_no_ptr_swap:

    // === Timer check ===
    bl      _get_time_ms
    mov     x28, x0
    adrp    x8, _anim_last_update@PAGE
    add     x8, x8, _anim_last_update@PAGEOFF
    ldr     x9, [x8]
    sub     x10, x28, x9
    cmp     x10, #LIFE_UPDATE_RATE
    b.lt    Llife_draw_only

    // Update timer
    str     x28, [x8]

    // === GoL UPDATE ===

    // Clear edge cells of write buffer: set row 0, row 23, col 0, col 79 to 0
    // (Simply set all edges to 0 in the write buffer)
    mov     w22, #0
Llife_clear_edges_col:
    cmp     w22, #ANIM_WIDTH
    b.ge    Llife_clear_edges_row
    uxtw    x8, w22
    strh    wzr, [x21, x8, lsl #1]                 // row 0
    mov     w9, #23
    mul     w9, w9, w24
    add     w9, w9, w22
    uxtw    x9, w9
    strh    wzr, [x21, x9, lsl #1]                 // row 23
    add     w22, w22, #1
    b       Llife_clear_edges_col

Llife_clear_edges_row:
    mov     w22, #0
Llife_clear_edges_rowloop:
    cmp     w22, #ANIM_HEIGHT
    b.ge    Llife_update_interior
    mul     w8, w22, w24
    uxtw    x8, w8
    strh    wzr, [x21, x8, lsl #1]                 // col 0
    add     w9, w8, #79
    uxtw    x9, w9
    strh    wzr, [x21, x9, lsl #1]                 // col 79
    add     w22, w22, #1
    b       Llife_clear_edges_rowloop

Llife_update_interior:
    // For interior cells: row 1..22, col 1..78
    mov     w22, #1
Llife_row:
    cmp     w22, #23
    b.ge    Llife_update_done

    mov     w23, #1
Llife_col:
    cmp     w23, #79
    b.ge    Llife_col_done

    // cell index = row * 80 + col
    mul     w8, w22, w24
    add     w8, w8, w23

    // Count 8 neighbors from read buffer
    // Offsets (in halfword indices): -81, -80, -79, -1, +1, +79, +80, +81
    mov     w25, #0                     // neighbor count

    sub     w9, w8, #81                 // up-left
    uxtw    x9, w9
    ldrsh   w10, [x20, x9, lsl #1]
    cmp     w10, #0
    cinc    w25, w25, ne

    sub     w9, w8, #80                 // up
    uxtw    x9, w9
    ldrsh   w10, [x20, x9, lsl #1]
    cmp     w10, #0
    cinc    w25, w25, ne

    sub     w9, w8, #79                 // up-right
    uxtw    x9, w9
    ldrsh   w10, [x20, x9, lsl #1]
    cmp     w10, #0
    cinc    w25, w25, ne

    sub     w9, w8, #1                  // left
    uxtw    x9, w9
    ldrsh   w10, [x20, x9, lsl #1]
    cmp     w10, #0
    cinc    w25, w25, ne

    add     w9, w8, #1                  // right
    uxtw    x9, w9
    ldrsh   w10, [x20, x9, lsl #1]
    cmp     w10, #0
    cinc    w25, w25, ne

    add     w9, w8, #79                 // down-left
    uxtw    x9, w9
    ldrsh   w10, [x20, x9, lsl #1]
    cmp     w10, #0
    cinc    w25, w25, ne

    add     w9, w8, #80                 // down
    uxtw    x9, w9
    ldrsh   w10, [x20, x9, lsl #1]
    cmp     w10, #0
    cinc    w25, w25, ne

    add     w9, w8, #81                 // down-right
    uxtw    x9, w9
    ldrsh   w10, [x20, x9, lsl #1]
    cmp     w10, #0
    cinc    w25, w25, ne

    // Load current cell state
    uxtw    x8, w8
    ldrsh   w26, [x20, x8, lsl #1]

    // Apply B3/S23 rules
    cbnz    w26, Llife_alive
    // Dead cell: born if neighbors == 3
    cmp     w25, #3
    mov     w27, #1
    csel    w27, w27, wzr, eq
    strh    w27, [x21, x8, lsl #1]
    b       Llife_next_cell

Llife_alive:
    // Alive cell: survive if neighbors == 2 or 3
    cmp     w25, #2
    b.eq    Llife_survive
    cmp     w25, #3
    b.eq    Llife_survive
    // Die
    strh    wzr, [x21, x8, lsl #1]
    b       Llife_next_cell

Llife_survive:
    mov     w27, #1
    strh    w27, [x21, x8, lsl #1]

Llife_next_cell:
    add     w23, w23, #1
    b       Llife_col

Llife_col_done:
    add     w22, w22, #1
    b       Llife_row

Llife_update_done:
    // Toggle swap flag so next time we read from the just-written buffer
    adrp    x8, Lanim_buf_swap@PAGE
    ldrb    w9, [x8, Lanim_buf_swap@PAGEOFF]
    eor     w9, w9, #1
    strb    w9, [x8, Lanim_buf_swap@PAGEOFF]

    // Swap read/write so draw reads from the just-written buffer
    mov     x8, x20
    mov     x20, x21
    mov     x21, x8

Llife_draw_only:
    // === DRAW: For each cell, if alive draw '#' yellow ===
    mov     w22, #0
Llife_draw_row:
    cmp     w22, #ANIM_HEIGHT
    b.ge    Llife_draw_done

    mov     w23, #0
Llife_draw_col:
    cmp     w23, #ANIM_WIDTH
    b.ge    Llife_draw_col_done

    mul     w8, w22, w24
    add     w8, w8, w23
    uxtw    x8, w8
    ldrsh   w25, [x20, x8, lsl #1]     // cell state from read buffer (current gen)

    cbz     w25, Llife_draw_next        // skip dead cells

    // Draw '#' with COLOR_PAIR(1) (yellow)
    mov     x0, x19
    mov     w1, #COLOR_PAIR_1
    mov     x2, #0
    bl      _wattr_on

    mov     x0, x19
    mov     w1, w22
    mov     w2, w23
    mov     w3, #'#'
    bl      _mvwaddch

    mov     x0, x19
    mov     w1, #COLOR_PAIR_1
    mov     x2, #0
    bl      _wattr_off

Llife_draw_next:
    add     w23, w23, #1
    b       Llife_draw_col

Llife_draw_col_done:
    add     w22, w22, #1
    b       Llife_draw_row

Llife_draw_done:
    ldp     x29, x30, [sp], #16
    ldp     x20, x19, [sp, #64]
    ldp     x22, x21, [sp, #48]
    ldp     x24, x23, [sp, #32]
    ldp     x26, x25, [sp, #16]
    ldp     x28, x27, [sp], #80
    ret

// ============================================================================
// Read-only data
// ============================================================================
.section __TEXT,__const

// Fire grayscale characters (12 chars, indices 0-11)
// Space, dot, apostrophe, colon, dash, equals, plus, star, hash, percent, at, hash
Lfire_grayscale:
    .ascii " .':-=+*#%@#"

// Water grayscale characters (11 chars, indices 0-10)
Lwater_grayscale:
    .ascii "#@%#*+=-:'."

// ============================================================================
// Animation mutable state (local to animation.s)
// ============================================================================
.section __DATA,__data

// Buffer swap flag: 0 = read buf1/write buf2, 1 = read buf2/write buf1
// Shared by water and GoL (only one animation active at a time)
Lanim_buf_swap:
    .byte 0

// ============================================================================
// Dispatch table (in __DATA,__const for relocatable function pointers)
// ============================================================================
.section __DATA,__const

.globl _anim_update_table
.p2align 3
_anim_update_table:
    .quad _anim_fire_update_and_draw
    .quad _anim_water_update_and_draw
    .quad _anim_snakes_update_and_draw
    .quad _anim_life_update_and_draw

// ============================================================================
.subsections_via_symbols
