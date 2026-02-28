// ============================================================================
// yetris-asm: AArch64 Assembly Tetris Clone for macOS Apple Silicon
// File: asm/timer.s -- gettimeofday wrapper returning milliseconds
// Build: make asm
//
// Provides _get_time_ms: returns current time in milliseconds (64-bit in x0).
// Uses gettimeofday(2) which fills struct timeval { tv_sec (8B), tv_usec (4B) }.
//
// Darwin ARM64 ABI: x0-x15 caller-saved, x19-x28 callee-saved, x18 reserved.
// ============================================================================

.section __TEXT,__text,regular,pure_instructions

// ----------------------------------------------------------------------------
// _get_time_ms: Get current time in milliseconds
// Args: none
// Returns: x0 = current time in milliseconds (64-bit)
// Clobbers: x8-x10 (caller-saved temporaries)
// Stack: 48 bytes (16 for saved fp/lr at [sp+0], 16 for struct timeval at [sp+16])
// ----------------------------------------------------------------------------
.globl _get_time_ms
.p2align 2
_get_time_ms:
    // Prologue: save frame pointer and link register
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp

    // Call gettimeofday(&tv, NULL)
    // struct timeval at [sp+16..31]: tv_sec (8 bytes at +16), tv_usec (4 bytes at +24)
    add     x0, sp, #16         // x0 = &tv (separate from saved regs)
    mov     x1, #0              // x1 = NULL (timezone, not used)
    bl      _gettimeofday

    // Load results from struct timeval on stack
    ldr     x8, [sp, #16]       // x8 = tv_sec (64-bit)
    ldrsw   x9, [sp, #24]       // x9 = tv_usec (sign-extend 32->64)

    // Compute: result = tv_sec * 1000 + tv_usec / 1000
    mov     w10, #1000
    mul     x0, x8, x10         // x0 = tv_sec * 1000
    sdiv    x9, x9, x10         // x9 = tv_usec / 1000
    add     x0, x0, x9          // x0 = total milliseconds

    // Epilogue: restore frame pointer and link register
    ldp     x29, x30, [sp], #48
    ret

// ============================================================================
.subsections_via_symbols
