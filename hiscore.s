// ============================================================================
// yetris-asm: AArch64 Assembly Tetris Clone for macOS Apple Silicon
// File: asm/hiscore.s -- Hi-score persistence via Darwin ARM64 syscalls
// Build: make asm
//
// Provides:
//   _load_hiscore: Load 4-byte uint32 from ~/.yetris-hiscore into _hiscore
//   _save_hiscore: Write _hiscore as 4-byte uint32 to ~/.yetris-hiscore
//
// File format: Raw little-endian uint32 (4 bytes). No header, no text.
// Path resolution: getenv("HOME") + "/.yetris-hiscore"
// Error handling: On any failure (no HOME, open/read/write error), bail
//                 silently. _hiscore remains at its current value (default 0).
//
// Darwin ARM64 syscalls used:
//   #5 = open, #3 = read, #4 = write, #6 = close
//   Error convention: carry flag set = error, x0 = errno
//
// Data dependencies (from asm/data.s):
//   _hiscore, _str_home_env, _str_hiscore_suffix
// ============================================================================

.section __TEXT,__text,regular,pure_instructions

// ----------------------------------------------------------------------------
// _load_hiscore: Load hi-score from ~/.yetris-hiscore
// Called once at startup from _main. On failure, _hiscore remains 0.
//
// Register usage:
//   x19 = path buffer base (callee-saved, survives bl _getenv)
//   x20 = saved file descriptor (callee-saved)
//
// Stack layout (from high to low):
//   [x20, x19]  +32 bytes (callee-saved pair)
//   [x29, x30]  +16 bytes (frame record)
//   [path buf]  256 bytes
//   [read buf]  16 bytes (allocated after open, freed before bail)
// ----------------------------------------------------------------------------
.globl _load_hiscore
.p2align 2
_load_hiscore:
    stp     x20, x19, [sp, #-32]!
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    sub     sp, sp, #256               // allocate path buffer

    // 1. Get HOME directory
    adrp    x0, _str_home_env@PAGE
    add     x0, x0, _str_home_env@PAGEOFF
    bl      _getenv
    cbz     x0, Lload_bail             // no HOME -> leave _hiscore at 0

    // 2. Copy HOME string to stack buffer
    mov     x19, sp                    // x19 = path buffer base
    mov     x1, x19                    // dest pointer
Lload_copy_home:
    ldrb    w8, [x0], #1
    strb    w8, [x1], #1
    cbnz    w8, Lload_copy_home
    sub     x1, x1, #1                // back up over NUL terminator

    // 3. Append "/.yetris-hiscore" suffix
    adrp    x0, _str_hiscore_suffix@PAGE
    add     x0, x0, _str_hiscore_suffix@PAGEOFF
Lload_copy_suffix:
    ldrb    w8, [x0], #1
    strb    w8, [x1], #1
    cbnz    w8, Lload_copy_suffix

    // 4. open(path, O_RDONLY, 0)
    mov     x0, x19                    // path
    mov     w1, #0                     // O_RDONLY = 0
    mov     w2, #0                     // mode (ignored)
    mov     x16, #5                    // syscall 5 = open
    svc     #0x80
    b.cs    Lload_bail                 // carry set = error (file doesn't exist)

    // 5. Save fd, allocate read buffer
    mov     w20, w0                    // save fd in callee-saved register
    sub     sp, sp, #16                // 16-byte aligned read buffer
    str     wzr, [sp]                  // zero the buffer first

    // 6. read(fd, buf, 4)
    mov     w0, w20                    // fd
    mov     x1, sp                     // buf
    mov     x2, #4                     // count = 4 bytes
    mov     x16, #3                    // syscall 3 = read
    svc     #0x80
    b.cs    Lload_close                // read error -> close and bail

    // 7. Store loaded value to _hiscore
    ldr     w8, [sp]
    adrp    x9, _hiscore@PAGE
    str     w8, [x9, _hiscore@PAGEOFF]

Lload_close:
    // Free read buffer and close fd
    add     sp, sp, #16                // free read buffer
    mov     w0, w20                    // fd
    mov     x16, #6                    // syscall 6 = close
    svc     #0x80

Lload_bail:
    // Free path buffer, restore frame, return
    add     sp, sp, #256
    ldp     x29, x30, [sp], #16
    ldp     x20, x19, [sp], #32
    ret

// ----------------------------------------------------------------------------
// _save_hiscore: Save _hiscore to ~/.yetris-hiscore
// Called from game-over path in main.s (only when score > previous hiscore).
//
// Register usage:
//   x19 = path buffer base (callee-saved)
//   x20 = saved file descriptor (callee-saved)
//
// Stack layout: same as _load_hiscore
// ----------------------------------------------------------------------------
.globl _save_hiscore
.p2align 2
_save_hiscore:
    stp     x20, x19, [sp, #-32]!
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    sub     sp, sp, #256               // allocate path buffer

    // 1. Get HOME directory
    adrp    x0, _str_home_env@PAGE
    add     x0, x0, _str_home_env@PAGEOFF
    bl      _getenv
    cbz     x0, Lsave_bail             // no HOME -> can't save

    // 2. Copy HOME string to stack buffer
    mov     x19, sp                    // x19 = path buffer base
    mov     x1, x19                    // dest pointer
Lsave_copy_home:
    ldrb    w8, [x0], #1
    strb    w8, [x1], #1
    cbnz    w8, Lsave_copy_home
    sub     x1, x1, #1                // back up over NUL terminator

    // 3. Append "/.yetris-hiscore" suffix
    adrp    x0, _str_hiscore_suffix@PAGE
    add     x0, x0, _str_hiscore_suffix@PAGEOFF
Lsave_copy_suffix:
    ldrb    w8, [x0], #1
    strb    w8, [x1], #1
    cbnz    w8, Lsave_copy_suffix

    // 4. open(path, O_WRONLY|O_CREAT|O_TRUNC, 0644)
    mov     x0, x19                    // path
    mov     w1, #0x0601                // O_WRONLY(0x1) | O_CREAT(0x200) | O_TRUNC(0x400)
    mov     w2, #0x1A4                 // 0644 octal = 0x1A4
    mov     x16, #5                    // syscall 5 = open
    svc     #0x80
    b.cs    Lsave_bail                 // carry set = error

    // 5. Save fd, prepare write buffer
    mov     w20, w0                    // save fd
    sub     sp, sp, #16                // 16-byte aligned write buffer
    adrp    x8, _hiscore@PAGE
    ldr     w8, [x8, _hiscore@PAGEOFF]
    str     w8, [sp]                   // store _hiscore value in buffer

    // 6. write(fd, buf, 4)
    mov     w0, w20                    // fd
    mov     x1, sp                     // buf
    mov     x2, #4                     // count = 4 bytes
    mov     x16, #4                    // syscall 4 = write
    svc     #0x80

    // 7. Free write buffer and close fd
    add     sp, sp, #16                // free write buffer
    mov     w0, w20                    // fd
    mov     x16, #6                    // syscall 6 = close
    svc     #0x80

Lsave_bail:
    // Free path buffer, restore frame, return
    add     sp, sp, #256
    ldp     x29, x30, [sp], #16
    ldp     x20, x19, [sp], #32
    ret

// ============================================================================
.subsections_via_symbols
