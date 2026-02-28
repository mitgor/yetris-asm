# Phase 5 Measurements

**Measured:** 2026-02-27
**Binary:** asm/bin/yetris-asm (ARM64 macOS Apple Silicon)
**Baseline:** Phase 4 complete (55,352 bytes unstripped pre-timing)

## Binary Size (Current, with Frame Timing Instrumentation)

The binary grew from 55,352 bytes (Phase 4) to 55,624 bytes after adding frame timing
instrumentation (mach_absolute_time calls, 4 data variables, stats printing code).
This is a +272 byte increase for the measurement infrastructure.

| Metric | Phase 4 (pre-timing) | Phase 5 (with timing) | Delta |
|--------|---------------------|-----------------------|-------|
| File size (unstripped) | 55,352 bytes | 55,624 bytes | +272 bytes |

## Binary Size (dead_strip Effect)

| Metric | Without -dead_strip | With -dead_strip | Difference |
|--------|--------------------|--------------------|------------|
| File size | 55,624 bytes | 55,624 bytes | 0 bytes (no effect) |

**Finding:** `-dead_strip` has no measurable effect because all symbols in the assembly
binary are referenced. There are no unreachable functions or data -- every symbol is
used. This confirms the Phase 5 RESEARCH.md prediction.

## Binary Size (Stripped)

| Metric | Unstripped | Stripped (plain strip) | Difference |
|--------|-----------|------------------------|------------|
| File size | 55,624 bytes | 52,720 bytes | -2,904 bytes (-5.2%) |
| LINKEDIT segment | 6,472 bytes | 3,568 bytes | -2,904 bytes (-44.9%) |
| Symbol count | 121 | 22 | -99 symbols |

**Finding:** Plain `strip` removes 99 local symbols from the symbol table, reducing
LINKEDIT from 6,472 to 3,568 bytes. The remaining 22 symbols are the dynamic linker
imports (ncurses functions, libSystem functions) and the _main entry point -- these
cannot be stripped without breaking the binary.

**Note:** `strip -x` (remove only local symbols, keep globals) produced a 55,664-byte
binary -- actually larger than unstripped due to alignment padding changes. Plain
`strip` without flags is the correct choice for maximum size reduction.

## Section Analysis

| Section | Segment | Size (bytes) | Purpose |
|---------|---------|-------------|---------|
| __text | __TEXT | 10,048 | Executable code (all .s files) |
| __stubs | __TEXT | 240 | PLT stubs for dynamic library calls |
| __const | __TEXT | 1,352 | Read-only data (piece shapes, kick tables, gravity delays) |
| __got | __DATA_CONST | 168 | Global offset table entries |
| __const | __DATA_CONST | 136 | Pointer tables (menu dispatch) |
| __data | __DATA | 336 | Mutable state (board, score, game flags, frame timing) |
| LINKEDIT | -- | 6,472 | Symbol table and string table |

**Total code: 10,048 bytes** (up from 9,376 in Phase 4, +672 bytes for frame timing + stats output)
**__TEXT segment: 1 page (16KB)** -- still fits in a single page at 71% utilization.

## Symbol Counts

| State | Symbol Count |
|-------|-------------|
| Unstripped | 121 |
| Stripped (plain) | 22 |

## Instruments Profiling

**Method:** `xcrun xctrace record --template 'Time Profiler' --time-limit 5s --launch -- ./asm/bin/yetris-asm`

**Result:** Instruments successfully launched and profiled the binary. However, since
xctrace launches the process without a TTY, ncurses initialization fails silently and
the game sits at the menu state with no input possible. The 5-second trace captured:

1. **dyld startup** (~2ms): Dynamic linker loading libncurses and libSystem
2. **libncurses init** (~1ms): `_nc_init_keytry` initializing keyboard mappings
3. **Idle loop**: The rest of the trace shows the game loop blocked in `wgetch` waiting
   for input that never arrives

**Conclusion:** Instruments Time Profiler is technically compatible with ncurses
binaries but provides limited value because:
- The game is fundamentally I/O-bound (wgetch blocks for 16ms per frame)
- Without interactive TTY input, the game never enters the GAME state
- The frame timing instrumentation added in Task 1 (mach_absolute_time) provides more
  useful per-frame measurements during actual gameplay

The frame timing instrumentation is the primary profiling mechanism for measuring
optimization impact. Instruments is useful only for startup analysis and confirming
that the binary is spending most of its time in kernel wait (wgetch).

## NEON Line Detection (OPT-03)

**Technique:** Replace scalar 10-iteration byte loop in `_clear_lines` with NEON `ld1`+`uminv` vectorized minimum across 16 bytes.

**Implementation:**
- Added `_neon_row_mask` (16 bytes) in `__TEXT,__const`: bytes 0-9 = 0x00, bytes 10-15 = 0xFF
- Added 8 bytes of padding after `_board` in `__DATA,__data` for safe 16-byte `ld1` reads from last row
- Replaced `Lclear_check_col` loop (5 instructions, up to 10 iterations) with straight-line NEON sequence (8 instructions, no loop)

**Code change (scalar -> NEON):**
```
BEFORE (scalar loop, up to 10 iterations):
  ldrb w11, [x19, x10]        // load 1 byte
  cbz w11, Lclear_not_full     // branch if empty
  add x10, x10, #1             // next col
  add w22, w22, #1             // increment counter
  cmp w22, #10                 // check bound
  b.lt Lclear_check_col        // loop

AFTER (NEON, straight-line):
  ld1 {v0.16b}, [x10]         // load 16 bytes
  ldr q1, [x11]               // load mask
  orr v0.16b, v0.16b, v1.16b  // mask padding
  uminv b2, v0.16b            // min across 16 bytes
  umov w11, v2.b[0]           // extract result
  cbz w11, Lclear_not_full    // branch if any empty
```

**Instruction count:** Scalar: 5 instructions per iteration x up to 10 iterations = up to 50 dynamic instructions. NEON: 8 instructions total (no loop). Worst-case reduction: 50 -> 8 dynamic instructions per row check.

**Binary size impact:**
| Metric | Before NEON | After NEON | Delta |
|--------|-------------|------------|-------|
| __text | 10,048 bytes | 10,060 bytes* | +12 bytes |
| __const | 1,352 bytes | 1,375 bytes | +23 bytes (mask) |
| __data | 336 bytes | 344 bytes | +8 bytes (padding) |

*Estimated; combined with register packing in same build.

**Frame timing:** Both optimizations were applied together. The combined binary's frame timing requires interactive gameplay to measure (the game is a terminal ncurses application that needs TTY input). The built-in `mach_absolute_time` instrumentation from Plan 01 will report min/max/avg microseconds to stderr when the game exits after interactive play. Expected: the line detection optimization should show reduced frame time during line-clear events, but the effect may be below noise for typical gameplay since line clearing is infrequent relative to the ~60fps render loop.

**Analysis:** NEON `uminv` replaces a conditional branch loop with a single horizontal-minimum instruction. The key benefit is predictable execution time (no branch misprediction) and reduced instruction count (8 vs up to 50). However, since line clearing occurs at most once per piece lock (every few seconds), the per-frame impact is negligible for average frame time. The research value is demonstrating the NEON technique, not achieving measurable speedup in a 60fps terminal game.

## Register Packing (OPT-01)

**Technique:** Pack `game_over`, `is_paused`, and `game_initialized` flags into callee-saved register `x28` as a bitfield, eliminating redundant `adrp`+`ldrb` memory loads on each frame iteration in the main game loop.

**Implementation:**
- Bit 0: `game_over` (was: `adrp x8, _game_over@PAGE; ldrb w8, [x8, _game_over@PAGEOFF]`)
- Bit 1: `is_paused` (was: `adrp x8, _is_paused@PAGE; ldrb w8, [x8, _is_paused@PAGEOFF]`)
- Bit 2: `game_initialized` (was: `w20` dedicated register)
- Sync points: After `_handle_input` returns (sync both flags), after `_soft_drop` returns (sync game_over)
- Memory globals remain source of truth; x28 is a cache for main.s game loop reads only

**Code change (memory -> register):**
```
BEFORE (3 instructions per check, memory load):
  adrp x8, _game_over@PAGE
  ldrb w8, [x8, _game_over@PAGEOFF]
  cbnz w8, Lgame_over_screen

AFTER (2 instructions per check, register test):
  tst x28, #1
  b.ne Lgame_over_screen
```

**Instruction count per frame:** Removed 3 memory-load checks (9 instructions: 3x adrp+ldrb+cbnz). Added 2 sync blocks (12 instructions total: after handle_input + after soft_drop). Changed 3 checks to register tests (6 instructions: 3x tst+b.ne). Net: in the common case (no input, no gravity), the per-frame cost is 4 instructions (2 tst+b.ne checks) vs 6 instructions (2 adrp+ldrb+cbnz checks). Saves 2 instructions per idle frame.

**Binary size impact:**
| Metric | Before packing | After packing | Delta |
|--------|---------------|---------------|-------|
| __text | ~10,060 bytes | 10,096 bytes | +36 bytes |

The register packing INCREASES code size slightly because the sync blocks after function calls add more instructions than the per-check savings. This is expected -- the optimization trades code size for execution speed (fewer memory loads in the hot path).

**Frame timing:** Combined with NEON optimization. Requires interactive gameplay for measurement. Expected: below noise floor. The game loop runs at 60fps with a 16ms wgetch block per frame; actual game logic takes <1ms. Saving 2 instructions (~2 cycles, ~1ns) per frame is unmeasurable against microsecond-scale frame times. The research value is demonstrating the register packing technique and documenting the (expected) null result.

**Analysis:** Register packing is a classic assembly optimization that eliminates memory loads in tight loops. In this game, the loop is not tight (60fps with 16ms I/O blocking), so the optimization has no practical impact. The technique is architecturally sound and would be meaningful in a higher-frequency loop (e.g., 1000+ iterations per second with actual CPU-bound work). Documenting this null result is valuable for the research writeup -- it demonstrates that optimization must target actual bottlenecks.

## Combined Optimization Impact

| Metric | Pre-optimization (05-01) | Post-optimization (05-02) | Delta |
|--------|-------------------------|--------------------------|-------|
| File size (unstripped) | 55,624 bytes | 55,672 bytes | +48 bytes |
| __text (code) | 10,048 bytes | 10,096 bytes | +48 bytes |
| __const (read-only data) | 1,352 bytes | 1,375 bytes | +23 bytes |
| __data (mutable state) | 336 bytes | 344 bytes | +8 bytes |
| __TEXT pages | 1 (16KB) | 1 (16KB) | 0 (still single page) |

**Key finding:** Both optimizations increase binary size slightly (+79 bytes total across all sections). The NEON optimization replaces a compact loop with straight-line SIMD instructions plus a 16-byte mask constant. The register packing adds sync blocks. Neither optimization reduces binary size -- they trade space for execution characteristics (NEON: predictable timing; register packing: fewer memory loads). The binary still fits comfortably in a single 16KB __TEXT page at 72% utilization.

## NEON Collision Detection (OPT-02)

**Status:** Analyzed, not implemented (negative expected outcome confirmed)

**Classification:** ARM64-specific (NEON is ARM Advanced SIMD)

**Technique:** Vectorize `_is_piece_valid` board lookups using NEON to check multiple cells simultaneously.

**Analysis of `_is_piece_valid` in board.s:**

The function iterates a 5x5 piece grid. For each non-empty cell (at most 4 cells for a T/L/J/S/Z piece, 4 for I, 4 for O), it:
1. Computes board coordinates: `board_x = px + col`, `board_y = py + row`
2. Checks 4 bounds conditions: `board_x < 0`, `board_x >= 10`, `board_y >= 20`, `board_y < 0`
3. If in-bounds: loads `board[board_y * 10 + board_x]` and checks for non-zero (collision)

**Why NEON does not help:**

1. **Scattered memory access.** Each active piece cell maps to a different board offset computed from `(py + row) * 10 + (px + col)`. These offsets are non-contiguous -- a T-piece at (3, 5) accesses board offsets 53, 62, 63, 64. NEON excels at contiguous vector loads (`ld1`), not gathering bytes from computed offsets. ARM64 NEON has no hardware gather instruction (unlike x86 AVX2 `vpgatherdd`).

2. **Per-cell conditional branching.** Each cell requires 4 bounds checks with early-exit semantics. If `board_x < 0`, the function returns invalid immediately -- no remaining cells matter. NEON cannot short-circuit: it would compute all cells then check results, wasting work when the first cell already indicates collision.

3. **Small working set.** A tetromino has exactly 4 active cells in its 5x5 grid. The scalar loop body executes only 4 times for most pieces (plus up to 21 empty-cell skips via `cbz`). The total dynamic instruction count for a typical validity check:
   - Empty cell skip: 5 instructions (mul, add, ldrb, cbz, add/cmp) x ~21 skipped cells
   - Active cell check: ~10 instructions x 4 active cells = ~40 instructions
   - Total: ~145 dynamic instructions per call (mostly cheap skips)

4. **NEON setup overhead.** A NEON approach would require:
   - Loading the 25-byte piece grid into registers: ~4 instructions
   - Computing 4 board offsets for active cells: ~16 instructions (can't vectorize: dependent on piece grid scan)
   - Gathering 4 non-contiguous board bytes: ~12 instructions (4x address compute + ldrb + ins into vector)
   - Bounds checking as mask operations: ~8 instructions
   - Reducing results: ~4 instructions
   - Total NEON: ~44+ instructions, but with MORE complexity and no early-exit capability

5. **The board is 10 bytes wide.** NEON operates on 16-byte vectors. Board rows are not 16-byte aligned, and loading a 16-byte vector from a row start would cross into the next row. This misalignment adds masking complexity without benefit for scattered single-byte lookups.

**Instruction count comparison:**
| Approach | Instructions (typical 4-cell check) | Early exit? | Memory pattern |
|----------|-------------------------------------|-------------|----------------|
| Scalar (current) | ~145 dynamic (mostly skips) | Yes | 4 computed loads |
| NEON (hypothetical) | ~44+ setup + compute | No | 4 gathered loads + setup |

The NEON version would NOT be faster despite fewer total instructions because:
- The scalar version's "skipped" instructions are nearly free (cbz on zero is a single-cycle operation with good branch prediction since most cells ARE zero)
- NEON setup cost (gathering scattered bytes, computing masks) has no parallelism benefit for 4 data points
- Loss of early-exit means NEON always does maximum work even when the first cell collides

**Conclusion:** Not beneficial. NEON collision detection for a 5x5 piece grid with scattered board access, per-cell branching, and only 4 active cells per piece offers no advantage over the scalar implementation. The technique would be appropriate for a game with larger uniform grids (e.g., checking an entire 16-byte row for collisions) but not for per-cell conditional lookups.

## Syscall Batching (OPT-04)

**Status:** Analyzed, not applicable

**Classification:** Generic (syscall reduction applies to any architecture)

**Technique:** Reduce kernel transitions per frame by batching I/O operations.

**Analysis of per-frame syscall profile:**

**Output path (write syscalls):**
1. `_render_frame` calls ncurses functions: `wmove`, `waddch`, `wattr_on`, `wattr_off`, `mvwaddstr`, `wcolor_set` -- typically 200+ calls per frame to draw the board, piece, score panel, etc.
2. ncurses internally buffers ALL of these in a userspace screen buffer. No kernel transitions occur during rendering.
3. `_wrefresh` (called once at the end of `_render_frame`) diffs the screen buffer against the previous frame and emits a single optimized `write()` syscall containing only terminal escape sequences for changed cells.
4. **Result: 1 write syscall per frame** (already optimal).

**Input path (read syscalls):**
1. `_poll_input` calls `_wgetch` with `wtimeout(16)`.
2. `wgetch` internally calls `read()` on stdin with a 16ms timeout (via `select()` + `read()`).
3. This is 1-2 syscalls per frame (`select` + `read`, or just `read` with O_NONBLOCK depending on ncurses implementation).
4. **Result: 1-2 read syscalls per frame** (irreducible -- interactive input requires checking for keypresses each frame).

**Timer path (time syscalls):**
1. `_get_time_ms` calls `_gettimeofday` for gravity timing: 1 syscall per frame (when not paused).
2. `_mach_absolute_time` (added in Plan 01) for frame timing: reads the ARM64 `CNTVCT_EL0` counter register via the commpage. On Apple Silicon, `mach_absolute_time` does NOT make a syscall -- it reads directly from the userspace-accessible counter register. **Result: 0 syscalls** for frame timing.
3. **Result: 1 gettimeofday syscall per frame** (for gravity check).

**Total syscall profile per frame:**

| Syscall | Source | Count | Reducible? |
|---------|--------|-------|------------|
| write() | wrefresh (ncurses output flush) | 1 | No -- already batched by ncurses |
| select()/read() | wgetch (keyboard input) | 1-2 | No -- interactive input is irreducible |
| gettimeofday() | _get_time_ms (gravity timer) | 1 | Possible: could replace with mach_absolute_time (0 syscalls) |
| **Total** | | **3-4** | **At most 1 reducible** |

**Potential optimization -- replace gettimeofday with mach_absolute_time:**
The gravity timer in `timer.s` uses `gettimeofday`, which is a real syscall. It could be replaced with `mach_absolute_time` (which reads CNTVCT_EL0 from userspace, no syscall). This would reduce per-frame syscalls from 3-4 to 2-3. However:
- The gettimeofday call takes ~1 microsecond (kernel entry/exit)
- The frame budget is 16,000 microseconds (16ms at 60fps)
- Saving 1us per frame is a 0.006% improvement
- The game is I/O-bound, not syscall-bound

**Why further batching is impossible without rewriting ncurses:**
To reduce the remaining 2-3 syscalls, you would need to:
- Replace ncurses output with direct terminal escape sequence writes (bypassing wrefresh)
- Replace ncurses input with direct read() calls (bypassing wgetch)
- This is a complete I/O layer rewrite, not an optimization

**Conclusion:** Not applicable. ncurses already implements optimal output batching via its screen buffer and diff-based wrefresh. The input syscall is irreducible (interactive games must poll for keypresses). The only reducible syscall is gettimeofday (replaceable with mach_absolute_time for a 0.006% improvement), which is not worth the code change complexity. The game makes 3-4 syscalls per frame, which is already near the theoretical minimum for an interactive terminal application.

## Size Comparison with C++ Version

| Metric | Assembly | C++ | Ratio |
|--------|----------|-----|-------|
| File size (unstripped) | 55,672 bytes | 1,036,152 bytes | 18.6x smaller |
| File size (stripped) | ~52,768 bytes | ~546,000 bytes | ~10.3x smaller |
| __text (code only) | 10,096 bytes | 345,468 bytes | 34.2x smaller |
| __TEXT pages | 1 (16KB) | 24 (384KB) | 24x fewer |
