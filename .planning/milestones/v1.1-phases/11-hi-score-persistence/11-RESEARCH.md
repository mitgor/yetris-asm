# Phase 11: Hi-Score Persistence - Research

**Researched:** 2026-02-27
**Domain:** File I/O (Darwin ARM64 syscalls), ASCII integer parsing, score panel rendering
**Confidence:** HIGH

## Summary

Phase 11 adds hi-score persistence to the assembly Tetris clone. The feature requires three capabilities: (1) loading a saved hi-score from `~/.yetris-hiscore` on startup, (2) saving the hi-score to disk on game over when the player beats the current record, and (3) displaying the hi-score value (or "(none)" when zero) in the existing score panel.

The codebase already has all the foundation pieces in place. The score panel (`_draw_score_panel` in render.s) already draws "Hi-Score" and "(none)" labels at fixed positions. The binary links against `-lSystem`, making `_getenv` available for `HOME` directory resolution. The existing `svc #0x80` syscall pattern in main.s provides a proven template for `open`/`read`/`write`/`close`. The requirement specifies a 4-byte uint32 binary file at `~/.yetris-hiscore` -- no INI parsing, no Base64, no subdirectory creation needed.

**Primary recommendation:** Create a new `hiscore.s` file with `_load_hiscore` and `_save_hiscore` functions using raw Darwin syscalls. Add a `_hiscore` global (.word) to data.s. Wire load into `_main` init, wire save into `Lgame_over_screen`, and update `_draw_score_panel` to display the loaded value.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| HISCORE-01 | Top score saved to ~/.yetris-hiscore as 4-byte uint32 on game over (if new high) | `_save_hiscore` uses getenv("HOME") + syscall open/write/close to write 4 raw bytes. Comparison logic: only write if `_score > _hiscore`. Integration at `Lgame_over_screen` in main.s. |
| HISCORE-02 | Top score loaded from file on startup (defaults to 0 if missing/unreadable) | `_load_hiscore` uses getenv("HOME") + syscall open/read/close to read 4 bytes into `_hiscore`. On any failure (no HOME, open fails, short read), leaves `_hiscore` at default 0. Called in `_main` after ncurses init. |
| HISCORE-03 | Hi-Score displayed in score panel with "Hi-Score" label and "(none)" when zero | `_draw_score_panel` already draws "Hi-Score" label and "(none)". Modify it to: if `_hiscore > 0`, display the numeric value instead of "(none)". Also update `_hiscore` in-memory when `_score` exceeds it during gameplay (for live display). |
</phase_requirements>

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Darwin syscalls (via svc #0x80) | macOS 15+ ARM64 | File open/read/write/close | Already used in main.s for stderr write; zero-dependency, minimal code |
| libSystem (_getenv) | System | Resolve HOME directory | Already linked (-lSystem in Makefile); only reliable way to get $HOME |
| ncurses (mvwprintw) | System | Score panel rendering | Already used throughout render.s |

### Supporting

No additional libraries needed. Everything required is already linked.

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Raw syscalls (svc #0x80) | libc _open/_read/_write/_close | libc wrappers add errno handling automatically, but raw syscalls match existing codebase pattern and avoid function call overhead |
| 4-byte binary format | ASCII decimal text file | ASCII is human-readable but requires atoi/itoa conversion; binary is simpler (4-byte read/write) and matches HISCORE-01 spec exactly |
| getenv("HOME") | Hardcoded /tmp path | /tmp doesn't persist across reboots; HOME is the correct Unix convention for user data |

## Architecture Patterns

### Recommended Project Structure

```
asm/
├── hiscore.s     # NEW: _load_hiscore, _save_hiscore (50-120 lines)
├── data.s        # MODIFY: add _hiscore (.word), _hiscore_path (.space 256),
│                 #          _str_hiscore_suffix, _str_home_env
├── main.s        # MODIFY: call _load_hiscore at init, _save_hiscore at game over
├── render.s      # MODIFY: _draw_score_panel to show _hiscore value
└── (unchanged)   # board.s, piece.s, input.s, menu.s, etc.
```

### Pattern 1: Path Construction via getenv + Manual Concatenation

**What:** Build `$HOME/.yetris-hiscore` path in a stack buffer using `_getenv("HOME")` then manual byte-copy of the suffix string.
**When to use:** Every time load or save is called (path is transient on stack).
**Example:**
```asm
// Get HOME directory
adrp    x0, _str_home_env@PAGE
add     x0, x0, _str_home_env@PAGEOFF   // "HOME"
bl      _getenv                           // x0 -> "/Users/username" or NULL
cbz     x0, Lhiscore_bail               // no HOME -> bail, leave hiscore=0

// Copy HOME to stack buffer
sub     sp, sp, #256                     // allocate path buffer
mov     x19, sp                          // x19 = buffer base
mov     x1, x19                          // dest
// byte-copy loop: while (*src) { *dst++ = *src++; }
Lcopy_home:
    ldrb    w8, [x0], #1
    strb    w8, [x1], #1
    cbnz    w8, Lcopy_home
sub     x1, x1, #1                       // back up over NUL

// Append "/.yetris-hiscore\0"
adrp    x0, _str_hiscore_suffix@PAGE
add     x0, x0, _str_hiscore_suffix@PAGEOFF
Lcopy_suffix:
    ldrb    w8, [x0], #1
    strb    w8, [x1], #1
    cbnz    w8, Lcopy_suffix
// x19 now points to complete NUL-terminated path
```

### Pattern 2: Raw Syscall File I/O (Darwin ARM64)

**What:** Use `svc #0x80` with x16=syscall_number for open/read/write/close. Check carry flag for errors.
**When to use:** All file operations in this phase.
**Example:**
```asm
// open(path, O_RDONLY, 0) -> fd in x0
mov     x0, x19                // path buffer
mov     w1, #0                 // O_RDONLY = 0
mov     w2, #0                 // mode (ignored for O_RDONLY)
mov     x16, #5               // syscall 5 = open
svc     #0x80
b.cs    Lopen_failed           // carry set = error

// read(fd, buf, 4) -> bytes_read in x0
mov     w20, w0                // save fd
mov     x1, sp                 // 4-byte buffer on stack
mov     x2, #4                 // read 4 bytes
mov     x16, #3               // syscall 3 = read
svc     #0x80

// close(fd)
mov     w0, w20                // fd
mov     x16, #6               // syscall 6 = close
svc     #0x80
```

### Pattern 3: Conditional Save (Only on New High)

**What:** At game over, compare `_score` with `_hiscore`. Only write to disk if `_score > _hiscore`.
**When to use:** `Lgame_over_screen` in main.s, BEFORE displaying the game-over overlay.
**Example:**
```asm
// In Lgame_over_screen (main.s), before the render:
adrp    x8, _score@PAGE
ldr     w9, [x8, _score@PAGEOFF]
adrp    x8, _hiscore@PAGE
add     x8, x8, _hiscore@PAGEOFF
ldr     w10, [x8]
cmp     w9, w10
b.ls    Lno_new_hiscore        // score <= hiscore, skip save
str     w9, [x8]               // update in-memory hiscore
bl      _save_hiscore          // persist to disk
Lno_new_hiscore:
```

### Pattern 4: Live Hi-Score Update During Gameplay

**What:** Update `_hiscore` in memory whenever `_score` exceeds it, so the score panel shows the new record in real-time (matching C++ behavior).
**When to use:** In the scoring pipeline (board.s `Lscore_done`) or in `_draw_score_panel` itself.
**Example:**
```asm
// At end of scoring in board.s (after all score additions):
adrp    x8, _hiscore@PAGE
add     x8, x8, _hiscore@PAGEOFF
ldr     w9, [x8]                // current hiscore
adrp    x10, _score@PAGE
ldr     w11, [x10, _score@PAGEOFF]  // current score
cmp     w11, w9
csel    w9, w11, w9, hi         // w9 = max(score, hiscore)
str     w9, [x8]                // update hiscore if score is higher
```

### Anti-Patterns to Avoid

- **Don't use libc `_fopen`/`_fread`/`_fwrite`:** These require FILE* struct management. Raw syscalls are simpler and match the existing codebase pattern (main.s stderr write).
- **Don't create a subdirectory:** The requirement says `~/.yetris-hiscore` (flat file in HOME), not a nested path. Avoid the complexity of `mkdir`.
- **Don't store as ASCII text:** The requirement says "4-byte uint32". Store raw binary -- `str w0, [sp]` then `write(fd, sp, 4)`. No number-to-string conversion needed for the file.
- **Don't persist path in .data:** Build the path on the stack each time. A .data buffer wastes 256 bytes permanently and requires careful initialization ordering.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| HOME resolution | Manual parsing of /etc/passwd | `bl _getenv` with "HOME" string | getenv is 1 instruction, already linked via -lSystem |
| String concatenation | Complex memcpy with length tracking | Simple byte-copy loop (ldrb/strb/cbnz) | NUL-terminated strings, paths are short (<256 bytes) |

**Key insight:** The entire feature is straightforward because the requirement deliberately chose a simple binary file format (4-byte uint32). The C++ version's Base64+INI approach is explicitly not needed.

## Common Pitfalls

### Pitfall 1: Carry Flag Error Checking After Syscalls
**What goes wrong:** Forgetting to check carry flag after `svc #0x80`. On Darwin ARM64, a failed syscall sets the carry flag and puts errno in x0.
**Why it happens:** Linux ARM64 returns negative values for errors; Darwin uses carry flag.
**How to avoid:** Always follow `svc #0x80` with `b.cs Lerror_label` for calls that can fail (open, read, write).
**Warning signs:** Hi-score file created but empty, or crashes on first run when file doesn't exist.

### Pitfall 2: Stack Alignment Before bl Calls
**What goes wrong:** If the 256-byte path buffer allocation makes sp unaligned, subsequent `bl _getenv` or ncurses calls crash with SIGBUS.
**Why it happens:** Darwin ARM64 requires 16-byte aligned SP at all `bl` sites.
**How to avoid:** Allocate stack in multiples of 16 (256 is already 16-aligned, so `sub sp, sp, #256` is safe). Ensure frame pointer + path buffer total is 16-aligned.
**Warning signs:** SIGBUS crash during _getenv call.

### Pitfall 3: Forgetting to Close File Descriptor
**What goes wrong:** File descriptor leak. If the game runs many sessions without quitting, eventually open() fails with EMFILE.
**Why it happens:** Assembly has no RAII or defer; every error path must manually close the fd.
**How to avoid:** Save fd in a callee-saved register (e.g., x20) immediately after open(). Have a single exit path that closes it, or close in every branch before returning.
**Warning signs:** After ~250 game sessions, hi-score stops saving.

### Pitfall 4: Byte Order Assumption
**What goes wrong:** Writing uint32 as raw bytes assumes the reader uses the same endianness.
**Why it happens:** ARM64 is little-endian by default, but someone might read the file on a different platform.
**How to avoid:** This is not a real concern since the requirement is for a single-machine hi-score file. Document the format as little-endian uint32. The same binary always reads back what it wrote.
**Warning signs:** None -- this is a theoretical concern only.

### Pitfall 5: Not Updating In-Memory Hiscore During Game
**What goes wrong:** The score panel shows the old hi-score even after the player has surpassed it during the current game session.
**Why it happens:** `_hiscore` is only loaded at startup and saved at game over, but never updated mid-game.
**How to avoid:** Either update `_hiscore` in the scoring pipeline (board.s) whenever `_score > _hiscore`, or check in `_draw_score_panel` and display `max(_score, _hiscore)`.
**Warning signs:** Player beats hi-score mid-game but panel still shows old value until next launch.

### Pitfall 6: Clobbering Callee-Saved Registers in _getenv Call
**What goes wrong:** `_getenv` follows C calling convention and may clobber x0-x17. If path buffer pointer is in a temporary register, it's lost.
**Why it happens:** Assembly code forgetting ABI rules for C library calls.
**How to avoid:** Save important values in callee-saved registers (x19-x28) before calling `bl _getenv`. The returned pointer (x0) must be copied to a callee-saved register if needed across subsequent bl calls.
**Warning signs:** Path buffer contains garbage; file created at wrong location.

## Code Examples

### _load_hiscore: Complete Implementation Sketch

```asm
// _load_hiscore: Load hi-score from ~/.yetris-hiscore
// Called once at startup from _main. On failure, _hiscore remains 0.
// Stack: 16 (frame) + 256 (path buffer) = 272, rounded to 288 (16-aligned)
.globl _load_hiscore
.p2align 2
_load_hiscore:
    stp     x20, x19, [sp, #-32]!
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    sub     sp, sp, #256               // path buffer

    // 1. Get HOME
    adrp    x0, _str_home_env@PAGE
    add     x0, x0, _str_home_env@PAGEOFF
    bl      _getenv
    cbz     x0, Lload_bail             // no HOME, leave at 0

    // 2. Copy HOME to buffer
    mov     x19, sp                     // x19 = path buffer
    mov     x1, x19
Lload_copy_home:
    ldrb    w8, [x0], #1
    strb    w8, [x1], #1
    cbnz    w8, Lload_copy_home
    sub     x1, x1, #1                 // back up over NUL

    // 3. Append suffix
    adrp    x0, _str_hiscore_suffix@PAGE
    add     x0, x0, _str_hiscore_suffix@PAGEOFF
Lload_copy_suffix:
    ldrb    w8, [x0], #1
    strb    w8, [x1], #1
    cbnz    w8, Lload_copy_suffix

    // 4. open(path, O_RDONLY, 0)
    mov     x0, x19
    mov     w1, #0                     // O_RDONLY
    mov     w2, #0
    mov     x16, #5
    svc     #0x80
    b.cs    Lload_bail                 // file doesn't exist

    // 5. read(fd, &buf, 4)
    mov     w20, w0                    // save fd
    sub     sp, sp, #16                // 4-byte read buffer (16-aligned)
    str     wzr, [sp]                  // zero it first
    mov     w0, w20                    // fd
    mov     x1, sp                     // buf
    mov     x2, #4                     // count
    mov     x16, #3
    svc     #0x80
    b.cs    Lload_close                // read error

    // 6. Store to _hiscore
    ldr     w8, [sp]
    adrp    x9, _hiscore@PAGE
    str     w8, [x9, _hiscore@PAGEOFF]

Lload_close:
    add     sp, sp, #16                // free read buffer
    mov     w0, w20
    mov     x16, #6                    // close
    svc     #0x80

Lload_bail:
    add     sp, sp, #256               // free path buffer
    ldp     x29, x30, [sp], #16
    ldp     x20, x19, [sp], #32
    ret
```

### _save_hiscore: Complete Implementation Sketch

```asm
// _save_hiscore: Save _hiscore to ~/.yetris-hiscore
// Called from game-over path in main.s (only when score > previous hiscore)
.globl _save_hiscore
.p2align 2
_save_hiscore:
    stp     x20, x19, [sp, #-32]!
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    sub     sp, sp, #256

    // 1. Get HOME + build path (same as load)
    adrp    x0, _str_home_env@PAGE
    add     x0, x0, _str_home_env@PAGEOFF
    bl      _getenv
    cbz     x0, Lsave_bail

    mov     x19, sp
    mov     x1, x19
Lsave_copy_home:
    ldrb    w8, [x0], #1
    strb    w8, [x1], #1
    cbnz    w8, Lsave_copy_home
    sub     x1, x1, #1

    adrp    x0, _str_hiscore_suffix@PAGE
    add     x0, x0, _str_hiscore_suffix@PAGEOFF
Lsave_copy_suffix:
    ldrb    w8, [x0], #1
    strb    w8, [x1], #1
    cbnz    w8, Lsave_copy_suffix

    // 2. open(path, O_WRONLY|O_CREAT|O_TRUNC, 0644)
    mov     x0, x19
    mov     w1, #0x0601                // O_WRONLY(0x1) | O_CREAT(0x200) | O_TRUNC(0x400)
    mov     w2, #0x1A4                 // 0644 octal = 0x1A4
    mov     x16, #5
    svc     #0x80
    b.cs    Lsave_bail

    // 3. write(fd, &_hiscore, 4)
    mov     w20, w0                    // save fd
    sub     sp, sp, #16
    adrp    x8, _hiscore@PAGE
    ldr     w8, [x8, _hiscore@PAGEOFF]
    str     w8, [sp]                   // write buffer on stack
    mov     w0, w20
    mov     x1, sp
    mov     x2, #4
    mov     x16, #4                    // write
    svc     #0x80

    // 4. close
    add     sp, sp, #16
    mov     w0, w20
    mov     x16, #6
    svc     #0x80

Lsave_bail:
    add     sp, sp, #256
    ldp     x29, x30, [sp], #16
    ldp     x20, x19, [sp], #32
    ret
```

### Render Modification: Score Panel Hi-Score Display

```asm
// In _draw_score_panel (render.s), replace the unconditional "(none)" draw:
// BEFORE:
//     mov x0, x19; mov w1, #2; mov w2, #1; bl _wmove
//     adrp x1, _str_hiscore_none@PAGE ...
//     bl _waddstr
//
// AFTER:
    adrp    x8, _hiscore@PAGE
    ldr     w20, [x8, _hiscore@PAGEOFF]
    cbz     w20, Ldraw_hiscore_none    // if hiscore == 0, show "(none)"

    // Display numeric hiscore
    mov     w0, w20                    // value
    mov     w1, #2                     // row
    mov     w2, #1                     // col
    bl      Ldraw_number               // reuse existing helper
    b       Ldraw_hiscore_done

Ldraw_hiscore_none:
    mov     x0, x19
    mov     w1, #2
    mov     w2, #1
    bl      _wmove
    mov     x0, x19
    adrp    x1, _str_hiscore_none@PAGE
    add     x1, x1, _str_hiscore_none@PAGEOFF
    bl      _waddstr

Ldraw_hiscore_done:
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| C++ Base64+INI score file with profiles | Raw 4-byte binary file | This phase | Eliminates ~200 lines of C++ parsing, 0 dependencies |
| Score display hardcoded to "(none)" | Dynamic hiscore display from memory | This phase | Score panel becomes functional for hi-score tracking |

**Deprecated/outdated:**
- The C++ score file format (Base64-encoded INI with per-profile multi-entry tracking) is intentionally not replicated. Out of Scope per REQUIREMENTS.md.

## Open Questions

1. **Live vs. end-of-game hiscore update**
   - What we know: C++ updates highScore pointer in `handle()` which is called at game over. Display reads `highScore->points` each frame.
   - What's unclear: Should the assembly version update `_hiscore` live during gameplay (so the panel shows the new record immediately) or only at game over?
   - Recommendation: Update in-memory `_hiscore` during gameplay (in scoring pipeline or render) for better UX. Only persist to disk at game over. This is a minor addition (a single `csel` instruction).

2. **Path buffer: stack vs. .data**
   - What we know: The prior architecture research suggested both approaches. Stack is cleaner (no persistent allocation). Data is simpler (no repeated construction).
   - What's unclear: Performance difference (negligible for a 2x-per-session operation).
   - Recommendation: Use stack buffer. It follows the existing codebase pattern (main.s stats output uses stack buffer) and avoids wasting 256 bytes of permanent .data space.

## Sources

### Primary (HIGH confidence)
- Existing codebase: `asm/main.s` lines 524-533 -- proven syscall write pattern with `svc #0x80`
- Existing codebase: `asm/render.s` lines 1492-1630 -- `_draw_score_panel` implementation with "Hi-Score"/"(none)" strings
- Existing codebase: `asm/data.s` lines 624-641 -- score state variables (_score, _level, _lines_cleared)
- Existing codebase: `Makefile` line 220 -- confirms `-lSystem` linking (enables _getenv)
- REQUIREMENTS.md: HISCORE-01/02/03 exact specifications
- `.planning/research/STACK.md` lines 275-371 -- verified Darwin ARM64 syscall numbers against darwin-xnu source

### Secondary (MEDIUM confidence)
- `.planning/research/ARCHITECTURE.md` lines 421-468 -- architecture analysis of hi-score feature
- C++ reference: `src/Game/Entities/ScoreFile.cpp` -- C++ save/load pattern (Base64+INI, NOT replicated)
- C++ reference: `src/Game/States/GameStateGame.cpp` lines 43-46 -- game-over score handling flow

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All tools already linked and proven in codebase (syscalls, -lSystem, ncurses)
- Architecture: HIGH - Existing code patterns directly applicable; prior research validates syscall numbers
- Pitfalls: HIGH - Well-understood domain (file I/O + ARM64 ABI); pitfalls are standard assembly concerns

**Research date:** 2026-02-27
**Valid until:** 2026-03-27 (stable domain -- Darwin syscall numbers and ARM64 ABI do not change)
