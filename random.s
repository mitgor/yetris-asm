// ============================================================================
// yetris-asm: AArch64 Assembly Tetris Clone for macOS Apple Silicon
// File: asm/random.s -- 7-bag random piece generator
// Build: make asm
//
// Provides:
//   _shuffle_bag: Fisher-Yates shuffle of indices 0-6 into _bag, resets _bag_index
//   _next_piece:  Returns next piece type (0-6) from bag, refills when empty
//
// Uses arc4random_uniform(n) for unbiased random numbers (no seeding needed).
// References _bag and _bag_index from data.s via adrp+add (same binary).
//
// Darwin ARM64 ABI: x0-x15 caller-saved, x19-x28 callee-saved, x18 reserved.
// ============================================================================

.section __TEXT,__text,regular,pure_instructions

// ----------------------------------------------------------------------------
// _shuffle_bag: Fill _bag[0..6] with a Fisher-Yates shuffle of 0-6
// Args: none
// Returns: nothing (modifies _bag and _bag_index globals)
// Uses callee-saved: x19 (bag address), x20 (loop counter i), x21 (random j)
// Stack: 32 bytes (x19-x20 + x29/x30)
// ----------------------------------------------------------------------------
.globl _shuffle_bag
.p2align 2
_shuffle_bag:
    // Prologue: save callee-saved registers + frame pointer
    stp     x20, x19, [sp, #-32]!
    stp     x29, x30, [sp, #16]
    add     x29, sp, #16

    // Load _bag address (same binary, use adrp+add)
    adrp    x19, _bag@PAGE
    add     x19, x19, _bag@PAGEOFF

    // Initialize bag with sequential values 0,1,2,3,4,5,6
    mov     x8, #0
1:  strb    w8, [x19, x8]
    add     x8, x8, #1
    cmp     x8, #7
    b.lt    1b

    // Fisher-Yates shuffle: for i from 6 down to 1
    mov     w20, #6
2:
    // j = arc4random_uniform(i + 1)  -- random in [0, i]
    add     w0, w20, #1
    bl      _arc4random_uniform
    mov     w21, w0             // w21 = j

    // Swap bag[i] and bag[j]
    // Use x-width registers for offset addressing
    uxtw    x10, w20                // x10 = zero-extended i
    uxtw    x11, w21                // x11 = zero-extended j
    ldrb    w8, [x19, x10]          // w8 = bag[i]
    ldrb    w9, [x19, x11]          // w9 = bag[j]
    strb    w9, [x19, x10]          // bag[i] = bag[j]
    strb    w8, [x19, x11]          // bag[j] = old bag[i]

    sub     w20, w20, #1
    cbnz    w20, 2b

    // Reset _bag_index to 0
    adrp    x8, _bag_index@PAGE
    strb    wzr, [x8, _bag_index@PAGEOFF]

    // Epilogue
    ldp     x29, x30, [sp, #16]
    ldp     x20, x19, [sp], #32
    ret

// ----------------------------------------------------------------------------
// _next_piece: Get next piece type from 7-bag
// Args: none
// Returns: w0 = piece type (0-6)
// If bag is empty (bag_index >= 7), calls _shuffle_bag to refill first.
// Uses callee-saved: x19 (bag address), x20 (bag_index address)
// Stack: 32 bytes (x19-x20 + x29/x30)
// ----------------------------------------------------------------------------
.globl _next_piece
.p2align 2
_next_piece:
    // Prologue: save callee-saved registers + frame pointer
    stp     x20, x19, [sp, #-32]!
    stp     x29, x30, [sp, #16]
    add     x29, sp, #16

    // Load _bag_index address
    adrp    x20, _bag_index@PAGE
    add     x20, x20, _bag_index@PAGEOFF

    // Check if bag needs refill
    ldrb    w8, [x20]           // w8 = bag_index
    cmp     w8, #7
    b.lt    3f                  // if bag_index < 7, skip refill

    // Bag empty -- reshuffle
    bl      _shuffle_bag
    // After shuffle, bag_index is 0

3:
    // Load bag address
    adrp    x19, _bag@PAGE
    add     x19, x19, _bag@PAGEOFF

    // Read bag[bag_index]
    ldrb    w8, [x20]           // w8 = bag_index (may have been reset by shuffle)
    uxtw    x9, w8              // x9 = zero-extended bag_index
    ldrb    w0, [x19, x9]      // w0 = bag[bag_index] = piece type

    // Increment bag_index
    add     w8, w8, #1
    strb    w8, [x20]           // store updated bag_index

    // Epilogue
    ldp     x29, x30, [sp, #16]
    ldp     x20, x19, [sp], #32
    ret

// ============================================================================
.subsections_via_symbols
