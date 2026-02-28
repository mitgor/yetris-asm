# Phase 5: Optimization Research and Documentation - Research

**Researched:** 2026-02-26
**Domain:** ARM64 assembly optimization, NEON SIMD, frame timing, CPU profiling, binary size analysis, research writeup
**Confidence:** HIGH

## Summary

Phase 5 is a research and documentation phase, not a feature phase. The goal is to explore assembly-specific optimization techniques, measure their impact quantitatively, and produce a research writeup comparing the assembly version to the C++ baseline. The binary is already complete and fully playable (Phases 1-4 done). This phase adds instrumentation, attempts optimizations, measures results, and documents findings.

The current assembly binary is 55,352 bytes (unstripped) with 9,376 bytes of actual code in __text, versus the C++ binary's 1,036,152 bytes (345,468 bytes of code). The binary already fits in a single 16KB __TEXT page. The optimization targets are: (1) register packing of game state, (2) NEON SIMD for line detection, (3) NEON SIMD for collision detection, (4) syscall batching, and (5) binary size optimization via linker flags and symbol stripping. Each must be measured before/after with quantitative results.

**Primary recommendation:** Implement frame timing instrumentation first (mach_absolute_time or CNTVCT_EL0), then use it to measure each optimization. NEON line detection (uminv-based full-row check) is the most promising single optimization. Profile with Instruments to validate hotspot assumptions before investing in complex optimizations.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| OPT-01 | Register-only state packing -- compact game flags in callee-saved registers x19-x28 | Current state uses 12+ global memory loads per frame; x19-x23 already used in main.s for gravity; 5 more callee-saved regs available (x24-x28) for game_over, is_paused, can_hold, piece_type, piece_rotation |
| OPT-02 | NEON/SIMD board operations -- vectorized collision detection | Board is 10-byte rows (not 16-aligned); _is_piece_valid iterates 5x5 grid with conditional bounds checks; NEON benefit LIMITED due to branching; documented as "attempted but not beneficial" is a valid research finding |
| OPT-03 | NEON/SIMD line detection -- vectorized full-row scan | VERIFIED WORKING: ld1+uminv pattern detects full rows in 2 instructions vs current 10-iteration byte loop; pad bytes 10-15 with 0xFF; uminv b1, v0.16b finds min; if min > 0 row is full |
| OPT-04 | Syscall batching -- batch frame output to minimize kernel transitions | ncurses already batches output (waddch -> wrefresh); real syscall cost is in wgetch (16ms timeout) and gettimeofday; limited optimization potential here unless bypassing ncurses |
| OPT-05 | Binary size optimization -- dead_strip, symbol stripping, section analysis | VERIFIED: dead_strip has no effect (all symbols referenced); strip reduces 55,352 -> 52,584 bytes (-5%); LINKEDIT shrinks from 6,200 to 3,432 bytes |
| OPT-06 | Each optimization technique measured before/after with quantitative results | Frame timing infrastructure (mach_absolute_time or CNTVCT_EL0) must be built first; then wrap each optimization in before/after measurements |
| MEAS-02 | Frame timing measurements using mach_absolute_time or clock_gettime | VERIFIED: both mach_absolute_time (via bl) and mrs CNTVCT_EL0 (direct register read) work on this Mac; CNTVCT_EL0 ticks at 41.67ns (numer=125, denom=3); mach_absolute_time links from -lSystem |
| MEAS-03 | CPU profiling with Instruments to identify hotspots | xctrace available with "CPU Profiler" and "Time Profiler" templates; command: xcrun xctrace record --template 'Time Profiler' --launch -- ./asm/bin/yetris-asm |
| MEAS-04 | Research writeup documenting all techniques, measurements, tradeoffs, and findings | Output is a markdown document in the project; must cover each OPT-* technique with before/after numbers |
| MEAS-05 | ARM64-specific vs generic assembly optimizations distinguished in writeup | NEON, CNTVCT_EL0, and register packing are ARM64-specific; dead_strip and syscall batching are generic |
</phase_requirements>

## Standard Stack

### Core (Already in Use)
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Apple `as` | Xcode CLT | ARM64 assembler | Only assembler for Darwin Mach-O on Apple Silicon |
| Apple `ld` | Xcode CLT | Mach-O linker | Supports -dead_strip, -arch arm64 |
| `size` | Xcode CLT | Section size analysis | Standard Mach-O binary analysis tool |
| `otool` | Xcode CLT | Load command / section inspection | Standard macOS binary inspector |
| `nm` | Xcode CLT | Symbol table analysis | Shows defined/undefined symbols |
| `strip` | Xcode CLT | Symbol stripping | Removes symbol table entries from binary |

### Measurement Tools
| Tool | Purpose | When to Use |
|------|---------|-------------|
| `mach_absolute_time` | High-resolution monotonic timer | Frame timing, before/after measurements |
| `mrs CNTVCT_EL0` | Direct counter register read (no function call overhead) | Micro-benchmarks where function call cost matters |
| `mach_timebase_info` | Get tick-to-nanosecond conversion factor (125/3 on Apple Silicon) | Convert CNTVCT_EL0 or mach_absolute_time ticks to real time |
| `xcrun xctrace` | CPU profiling via Instruments | Identify actual hotspots in game loop |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| mach_absolute_time | gettimeofday (already used in timer.s) | gettimeofday has microsecond precision only; mach_absolute_time has ~42ns precision |
| mach_absolute_time | mrs CNTVCT_EL0 direct | CNTVCT_EL0 avoids function call overhead but requires manual commpage offset handling for full mach_absolute_time equivalence; simpler to just call mach_absolute_time for frame timing |
| Instruments (xctrace) | Manual timestamp instrumentation | Instruments provides sampling without code changes; manual instrumentation is more precise for specific code paths |

## Architecture Patterns

### Measurement Infrastructure

The measurement approach should be non-invasive: wrap existing frame logic with timing calls rather than restructuring the game loop. Store timing results in new data section variables and output them on exit or log to memory for post-hoc analysis.

```
// Pattern: Frame timing wrapper in main.s game loop
Lgame_frame:
    bl      _mach_absolute_time     // x0 = frame_start_ticks
    mov     x24, x0                 // save in callee-saved reg

    // ... existing game frame logic (input, gravity, render) ...

    bl      _mach_absolute_time     // x0 = frame_end_ticks
    sub     x0, x0, x24             // elapsed ticks
    // Convert: elapsed_ns = ticks * 125 / 3
    mov     w8, #125
    mul     x0, x0, x8
    mov     w8, #3
    udiv    x0, x0, x8              // elapsed_ns

    // Accumulate into running stats (min/max/sum/count)
```

### Optimization Attempt Pattern

Each optimization should follow this pattern:
1. Measure baseline (existing code) with frame timing
2. Implement optimization in a new function or modified function
3. Measure optimized version
4. Record both numbers
5. If optimization is worse or negligible, REVERT and document "did not help"

### Research Writeup Structure

```
research/
  optimization-writeup.md     # Main research document
```

The writeup is a markdown file documenting:
- Technique description
- Implementation approach
- Before/after measurements (table)
- Whether the optimization is ARM64-specific or generic
- Conclusion (keep/revert/partial)

### Anti-Patterns to Avoid
- **Optimizing without measuring first:** Always get baseline numbers before changing code. The bottleneck may not be where expected.
- **Keeping broken optimizations:** If NEON collision detection is slower than scalar (likely due to setup overhead), revert it and document the finding. A negative result is still a valid research finding.
- **Changing the game behavior:** Optimizations must not alter game behavior. The game should play identically before and after each optimization.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| High-res timing | Custom timer from raw syscalls | mach_absolute_time (bl call) | Already available in libSystem, handles commpage reads and timebase conversion internally |
| Timebase conversion | Manual numer/denom lookup | mach_timebase_info struct | Apple may change timebase ratios on future hardware |
| CPU profiling | Manual instruction counting | xcrun xctrace with Time Profiler | Sampling profiler gives actual hotspot data without instrumentation |
| Binary analysis | Manual hex inspection | size, otool -l, nm | Standard tools parse Mach-O headers correctly |

## Common Pitfalls

### Pitfall 1: Measuring ncurses call overhead instead of game logic
**What goes wrong:** Frame timing shows 16ms per frame, but that is the wtimeout(16) blocking period, not actual CPU work.
**Why it happens:** wgetch blocks for up to 16ms waiting for input. This dominates frame time.
**How to avoid:** Measure game logic (input dispatch + gravity + render) separately from the wgetch poll. Start timer AFTER _poll_input returns, stop BEFORE wrefresh.
**Warning signs:** All frames measure ~16000us regardless of game state.

### Pitfall 2: NEON overhead exceeding scalar benefit on small data
**What goes wrong:** NEON line detection is slower than byte loop for a single row.
**Why it happens:** Setting up NEON registers (ld1, padding, uminv, umov) has fixed overhead. For 10 bytes, the scalar loop (10 comparisons) may be faster.
**How to avoid:** Measure NEON vs scalar for the actual workload (20 rows checked per clear_lines call). NEON wins when checking multiple rows in sequence.
**Warning signs:** NEON version is slower on first measurement -- check if you are timing setup cost vs amortized cost.

### Pitfall 3: Register packing breaking callee-saved contract
**What goes wrong:** Packing game state into x24-x28 in main.s game loop works, but calling functions that also use those registers clobbers the state.
**Why it happens:** Functions like _lock_piece already use x19-x24 as callee-saved registers. They save/restore correctly, but if main.s adds x24-x28 for state packing, the stack frames must account for this.
**How to avoid:** Audit every function's register usage before claiming registers for state packing. The callee-saved registers are "saved" -- the callee saves and restores them. Main.s can use them freely as long as its own prologue/epilogue is correct.
**Warning signs:** Game state corruption after function calls.

### Pitfall 4: Instruments profiling a 16ms-blocked binary
**What goes wrong:** Time Profiler shows 99% of time in _wgetch because the game blocks waiting for input.
**Why it happens:** The game runs at ~60fps via wtimeout(16) which means most CPU time is kernel wait time.
**How to avoid:** Either (a) accept that the profiler shows wait time and focus on the remaining 1% of samples, or (b) temporarily reduce wtimeout to 1ms for profiling to increase the ratio of work-to-wait, or (c) use "CPU Profiler" template which may filter idle time better.
**Warning signs:** Flat profile with no clear hotspot in user code.

### Pitfall 5: strip removing symbols needed by dyld
**What goes wrong:** Stripped binary crashes on launch.
**Why it happens:** strip without -x removes too many symbols; dynamic linker needs some symbols for lazy binding.
**How to avoid:** Use `strip -x` (remove local symbols only) or `strip -u -r` (remove debug symbols). Test stripped binary immediately.
**Warning signs:** Dyld error "Symbol not found" on launch.

## Code Examples

### Frame Timing with mach_absolute_time

```asm
// Source: Verified working on this Mac (numer=125, denom=3)
// Call: bl _mach_absolute_time -> x0 = ticks (monotonic, ~42ns resolution)
// Convert: elapsed_ns = (end_ticks - start_ticks) * 125 / 3
// Convert to us: elapsed_us = elapsed_ns / 1000

// Example: measure _render_frame cost
    bl      _mach_absolute_time
    mov     x25, x0                     // save start

    bl      _render_frame               // the thing we are measuring

    bl      _mach_absolute_time
    sub     x0, x0, x25                 // elapsed ticks
    mov     w8, #125
    mul     x0, x0, x8
    mov     w8, #3
    udiv    x0, x0, x8                  // x0 = elapsed nanoseconds
    mov     w8, #1000
    udiv    x0, x0, x8                  // x0 = elapsed microseconds
```

### NEON Line Detection (Full-Row Check)

```asm
// Source: Verified working proof-of-concept on this Mac
// Check if a 10-byte board row is full (all non-zero)
// Input: x9 = pointer to row start (10 bytes of board data)
// Output: w0 = 1 if full, 0 if not
// Clobbers: v0, v1

// Problem: ld1 loads 16 bytes but row is only 10 bytes
// Solution: Use a mask -- load 16 bytes, OR with a mask that
// sets bytes 10-15 to 0xFF, then check min > 0

// Simpler approach: load 10 bytes into GPR and check manually,
// OR restructure board to 16-byte rows (wastes 6 bytes/row = 120 bytes)

// Best approach for 10-byte rows:
    ld1     {v0.16b}, [x9]             // load 16 bytes (10 data + 6 junk)
    ldr     q1, [x8]                   // load mask: 0xFF for bytes 10-15, 0x00 for 0-9
    orr     v0.16b, v0.16b, v1.16b     // force padding bytes to non-zero
    uminv   b2, v0.16b                 // find minimum across all 16 bytes
    umov    w0, v2.b[0]                // extract scalar minimum
    // if w0 > 0: all 10 data bytes are non-zero (row is full)
    cmp     w0, #0
    cset    w0, ne                     // w0 = 1 if full, 0 if not
```

### Binary Size Optimization (Linker Flags)

```makefile
# Current link command:
ld -o $(ASM_EXE) $(ASM_OBJECTS) -lncurses -lSystem \
    -syslibroot $(SDK_PATH) -arch arm64

# Optimized link command:
ld -o $(ASM_EXE) $(ASM_OBJECTS) -lncurses -lSystem \
    -syslibroot $(SDK_PATH) -arch arm64 \
    -dead_strip

# Post-link strip (removes symbol table, saves ~2.7KB):
strip $(ASM_EXE)
```

### Instruments Profiling Command

```bash
# Record 10 seconds of gameplay with Time Profiler
xcrun xctrace record \
    --template 'Time Profiler' \
    --time-limit 10s \
    --output yetris-profile.trace \
    --launch -- ./asm/bin/yetris-asm

# Open the trace in Instruments GUI
open yetris-profile.trace
```

### Register State Packing (Concept)

```asm
// Current: game state scattered across global memory
// _game_over, _is_paused, _can_hold loaded via adrp+ldrb every frame

// Optimized: pack into x28 bitfield in main.s game loop
// Bit 0: game_over
// Bit 1: is_paused
// Bit 2: can_hold
// Bit 3: game_initialized (currently w20)
// Bits 4-7: piece_type (0-6, fits in 3 bits)
// Bits 8-11: piece_rotation (0-3, fits in 2 bits)

// Extract: tst x28, #1 (test game_over)
// Set:     orr x28, x28, #1
// Clear:   bic x28, x28, #1

// CAVEAT: Functions that read/write these globals must be updated
// to accept/return state via registers instead of memory.
// This is INVASIVE -- affects board.s, piece.s, input.s, render.s.
// Recommended approach: only pack main-loop-only state (game_over,
// is_paused, game_initialized) that are checked in main.s but not
// deeply in other functions.
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| gettimeofday for timing | mach_absolute_time or CNTVCT_EL0 | Always available on ARM64 macOS | ~42ns precision vs ~1us; monotonic vs wall clock |
| instruments CLI | xcrun xctrace | Xcode 12+ (2020) | Old `instruments` command deprecated |
| Manual symbol counting | otool -l + size + nm pipeline | Standard practice | Automated section analysis |

**Deprecated/outdated:**
- `instruments` CLI command: replaced by `xcrun xctrace`
- Kernel PMU access via kperf: requires entitlements on modern macOS, deferred to v2 (ADVR-01)

## Current Binary Profile (Baseline for Phase 5)

| Metric | Assembly | C++ | Ratio |
|--------|----------|-----|-------|
| File size (unstripped) | 55,352 bytes | 1,036,152 bytes | 18.7x smaller |
| File size (stripped) | 52,584 bytes | ~546,000 bytes | ~10.4x smaller |
| __text (code only) | 9,376 bytes | 345,468 bytes | 36.8x smaller |
| __const (data tables) | 1,352 bytes | -- | -- |
| __data (mutable state) | 304 bytes | -- | -- |
| __TEXT pages | 1 (16KB) | 24 (384KB) | 24x fewer |
| LINKEDIT | 6,200 bytes | -- | Reduced to 3,432 with strip |
| Symbol count | 116 | -- | Reduced to 21 with strip |

**Key insight:** The assembly binary grew from Phase 3 (53,688 bytes) to Phase 4 (55,352 bytes) -- only 1,664 bytes for the entire menu system and game mode settings. Code section grew from 7,488 to 9,376 bytes (+1,888 bytes). All code still fits in one 16KB page.

## Optimization Feasibility Assessment

| Technique | Feasibility | Expected Impact | Effort | Priority |
|-----------|------------|-----------------|--------|----------|
| OPT-03: NEON line detection | HIGH -- verified working PoC | Moderate (fewer instructions for row scan) | Low (replace inner loop of _clear_lines) | 1 |
| OPT-05: Binary size (strip) | HIGH -- verified | 55,352 -> 52,584 bytes (-5%) | Trivial (add strip to Makefile) | 2 |
| OPT-01: Register packing (main loop state) | MEDIUM -- partial packing feasible | Low (saves a few adrp+ldrb per frame) | Low (only main.s changes) | 3 |
| MEAS-02: Frame timing | HIGH -- both methods verified | N/A (infrastructure) | Low | 0 (prerequisite) |
| MEAS-03: Instruments profiling | HIGH -- xctrace confirmed available | N/A (analysis tool) | Low | 0 (prerequisite) |
| OPT-02: NEON collision detection | LOW -- poor fit | Likely negative (setup > benefit) | High (restructure board layout) | 5 |
| OPT-04: Syscall batching | LOW -- ncurses already batches | Negligible | Medium | 4 |

## Open Questions

1. **How much CPU time does the game loop actually use per frame?**
   - What we know: wtimeout(16) means wgetch blocks for up to 16ms. Actual game logic (gravity, collision, render) is likely < 1ms.
   - What's unclear: Whether any game logic is even measurable above noise floor.
   - Recommendation: Measure first, then decide which optimizations to pursue. If frame time is 50us, optimizing from 50us to 40us is not meaningful for gameplay but is meaningful for the research writeup.

2. **Should the board layout be restructured for NEON?**
   - What we know: Current layout is 10 bytes/row (200 bytes total). NEON operates on 16-byte vectors. Loading a 10-byte row loads 6 extra bytes that must be masked.
   - What's unclear: Whether padding to 16 bytes/row (320 bytes, +60% memory) would simplify NEON code enough to justify the change.
   - Recommendation: Use the mask approach (OR padding bytes to 0xFF) rather than restructuring the board. Restructuring would require changes to collision detection, rendering, locking -- too invasive for uncertain benefit.

3. **What will Instruments actually show as the hotspot?**
   - What we know: The game is I/O-bound (wgetch blocking, wrefresh output). CPU utilization should be very low.
   - What's unclear: Whether _render_frame (many ncurses calls) or _is_piece_valid (nested loops) dominates the non-idle CPU time.
   - Recommendation: Run the profiler, accept whatever it shows. The research value is in discovering where time actually goes, not in confirming assumptions.

## Sources

### Primary (HIGH confidence)
- Direct testing on this Mac (macOS Darwin 25.3.0, Apple Silicon)
  - mach_absolute_time: links from libSystem, returns monotonic ticks
  - mrs CNTVCT_EL0: assembles and executes, 41.67ns tick rate
  - mach_timebase_info: numer=125, denom=3 on this hardware
  - NEON ld1/uminv/umov: assembles and runs correctly for line detection
  - strip: reduces binary from 55,352 to 52,584 bytes
  - dead_strip: no measurable effect (all symbols referenced)
  - xctrace: "Time Profiler" and "CPU Profiler" templates available
- Phase 3 MEASUREMENTS.md -- binary size baseline data
- Existing assembly source code (8 .s files, ~4000 lines)

### Secondary (MEDIUM confidence)
- [Apple XNU mach_absolute_time.s](https://github.com/apple/darwin-xnu/blob/main/libsyscall/wrappers/mach_absolute_time.s) - ARM64 implementation uses CNTVCT_EL0 + commpage offset
- [ARM CNTVCT_EL0 documentation](https://developer.arm.com/documentation/ddi0601/2024-06/AArch64-Registers/CNTVCT-EL0--Counter-timer-Virtual-Count-Register) - Counter-timer Virtual Count register spec
- [xctrace man page](https://keith.github.io/xcode-man-pages/xctrace.1.html) - Command-line syntax for recording traces
- [Apple Managing Code Size](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/CodeFootprint/Articles/CompilerOptions.html) - dead_strip and code size optimization
- [Arm NEON programming quick reference](https://developer.arm.com/community/arm-community-blogs/b/operating-systems-blog/posts/arm-neon-programming-quick-reference) - NEON instruction reference

### Tertiary (LOW confidence)
- [Studying C++ generated assembly using Xcode Instruments](https://www.jviotti.com/2025/03/21/studying-cpp-generated-assembly-using-xcode-instruments.html) - xctrace workflow with assembly view
- [Using Xcode Instruments for C++ CPU profiling](https://www.jviotti.com/2024/01/29/using-xcode-instruments-for-cpp-cpu-profiling.html) - CPU Profiler template usage patterns

## Metadata

**Confidence breakdown:**
- Frame timing (mach_absolute_time, CNTVCT_EL0): HIGH - verified on this Mac with working test binaries
- NEON line detection: HIGH - verified proof-of-concept assembles, links, and produces correct output
- Binary size optimization: HIGH - measured actual before/after with strip and dead_strip
- NEON collision detection: MEDIUM - likely not beneficial but worth attempting for research completeness
- Register packing: MEDIUM - architecturally sound but impact may be below measurement noise
- Syscall batching: LOW - ncurses already handles buffering; limited room for improvement
- Instruments profiling: HIGH - xctrace confirmed available with correct templates

**Research date:** 2026-02-26
**Valid until:** 2026-03-26 (stable domain; ARM64 ISA and macOS tools unlikely to change)
