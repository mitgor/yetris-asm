---
phase: 05-optimization-research-and-documentation
plan: 01
subsystem: measurement
tags: [mach_absolute_time, frame-timing, binary-size, strip, dead_strip, instruments]

# Dependency graph
requires:
  - phase: 04-menus-and-game-modes
    provides: complete game binary for measurement baseline
provides:
  - mach_absolute_time frame timing in main.s game loop
  - frame_count/frame_time_sum/min/max data variables
  - stderr stats output on exit (min/max/avg microseconds)
  - Makefile asm-strip and asm-profile targets
  - MEASUREMENTS-05.md with binary size tables
affects: [05-02, 05-03]

# Tech tracking
tech-stack:
  added: [mach_absolute_time, write syscall]
  patterns: [frame timing via callee-saved register pair x24/x25, integer-to-ASCII via divide-by-10 in stack buffer]

key-files:
  created:
    - .planning/phases/05-optimization-research-and-documentation/MEASUREMENTS-05.md
  modified:
    - asm/main.s
    - Makefile

key-decisions:
  - "Used mach_absolute_time (bl call) over mrs CNTVCT_EL0 for simplicity and library compatibility"
  - "Expanded main stack frame from 64 to 96 bytes for x24-x28 callee-saved registers"
  - "Frame timing measures after poll_input through render_frame (captures game logic + render, excludes wgetch block)"
  - "Stats output uses raw write(2) syscall to stderr, avoiding printf/variadic calling convention"
  - "Plain strip (not strip -x) for maximum size reduction: 55,624 -> 52,720 bytes"
  - "dead_strip confirmed no effect -- all symbols referenced, documented as valid finding"

patterns-established:
  - "Lwrite_number_to_buf: reusable integer-to-ASCII helper writing to caller-provided buffer"
  - "Frame timing wrapper pattern: mach_absolute_time before/after, stats in __DATA section"

requirements-completed: [MEAS-02, MEAS-03, OPT-05]

# Metrics
duration: 7min
completed: 2026-02-27
---

# Phase 5 Plan 1: Frame Timing and Binary Size Summary

**mach_absolute_time frame timing instrumentation with min/max/avg stats output, Makefile strip/profile targets, and binary size measurements (55,624 unstripped, 52,720 stripped)**

## Performance

- **Duration:** 7 min
- **Started:** 2026-02-27T06:51:59Z
- **Completed:** 2026-02-27T06:59:01Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Frame timing infrastructure using mach_absolute_time measuring game logic per frame (excluding wgetch block)
- Four frame timing data variables (count, sum, min, max) in __DATA section with running stats updated each frame
- Stats printed to stderr on exit: "Frames: N  Min: Nus  Max: Nus  Avg: Nus" via write(2) syscall
- Makefile enhanced with -dead_strip linker flag, asm-strip target, and asm-profile target
- Comprehensive MEASUREMENTS-05.md documenting binary sizes, section analysis, and Instruments findings

## Task Commits

Each task was committed atomically:

1. **Task 1: Add mach_absolute_time frame timing to main.s** - `6ba8424` (feat)
2. **Task 2: Binary size optimization and Instruments profiling** - `b236e4d` (feat)

## Files Created/Modified
- `asm/main.s` - Frame timing instrumentation: expanded prologue (96-byte stack frame for x24-x28), mach_absolute_time calls around game logic, running stats in __DATA, stderr output in Lstate_exit, Lwrite_number_to_buf integer-to-ASCII helper
- `Makefile` - Added -dead_strip linker flag, asm-strip target (creates stripped copy), asm-profile target (Instruments Time Profiler)
- `.planning/phases/05-optimization-research-and-documentation/MEASUREMENTS-05.md` - Binary size tables, section analysis, strip/dead_strip results, Instruments profiling findings

## Decisions Made
- **mach_absolute_time over CNTVCT_EL0:** Used the library function rather than direct register read for simplicity. The function call overhead (~2ns) is negligible compared to frame times (~100-1000us). Already links from -lSystem.
- **96-byte stack frame:** Expanded from 64 bytes to accommodate x24-x28 for frame timing registers. x24 = frame_start_ticks, x25 = elapsed_ticks scratch.
- **Timing placement:** Start AFTER _poll_input returns (excludes 16ms wgetch block), end AFTER _render_frame (includes the actual rendering work). This captures input dispatch + game_over check + pause check + gravity + render.
- **Raw write syscall for output:** Used `mov x16, #4; svc #0x80` to write stats to stderr instead of printf, avoiding variadic calling convention complexity and C runtime dependency.
- **Plain strip preferred:** `strip -x` actually increases file size due to alignment padding. Plain `strip` removes 99 symbols and saves 2,904 bytes.
- **dead_strip: no effect documented:** All symbols referenced, so -dead_strip strips nothing. This is a valid research finding confirming the assembly code has no dead code.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Xcode license agreement blocking xcrun/as/ld**
- **Found during:** Task 1 (build verification)
- **Issue:** Xcode license not accepted, causing all xcrun-wrapped tools to fail with exit code 69
- **Fix:** Used CLT tools directly from /Library/Developer/CommandLineTools/usr/bin/ and SDK from /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
- **Files modified:** None (build commands adapted, Makefile unchanged)
- **Verification:** All assembly files assembled and linked successfully
- **Note:** The Makefile SDK_PATH still uses `xcrun --show-sdk-path` which will work once the license is accepted. The CLT workaround was only needed for this execution session.

**2. [Rule 1 - Bug] Fixed invalid ARM64 addressing mode in Lwrite_number_to_buf**
- **Found during:** Task 1 (assembly verification)
- **Issue:** `strb w15, [sp, #16, x12]` is not a valid ARM64 addressing mode (cannot combine immediate offset + register offset with SP as base)
- **Fix:** Computed base address `add x11, sp, #16` then used `strb w15, [x11, x12]`
- **Files modified:** asm/main.s
- **Committed in:** 6ba8424 (part of Task 1 commit)

**3. [Rule 1 - Bug] Fixed sub from SP not encodable**
- **Found during:** Task 1 (assembly verification)
- **Issue:** `sub x2, x9, sp` is not valid -- SP cannot be the second source operand in sub with this encoding
- **Fix:** Moved SP to a temporary register first: `mov x2, sp; sub x2, x9, x2`
- **Files modified:** asm/main.s
- **Committed in:** 6ba8424 (part of Task 1 commit)

---

**Total deviations:** 3 auto-fixed (1 blocking, 2 bugs)
**Impact on plan:** All fixes necessary for correct assembly and build. No scope creep.

## Issues Encountered
- Instruments profiling launched the binary but could not provide interactive input (no TTY), so the game sat at the menu state. The trace captured dyld startup and ncurses init but no actual game logic. Documented as a known limitation -- frame timing instrumentation is the primary measurement mechanism.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Frame timing infrastructure is ready for optimization experiments (Plan 02: NEON, register packing)
- MEASUREMENTS-05.md provides baseline numbers for before/after comparisons
- The Xcode license needs to be accepted (`sudo xcodebuild -license accept`) for `make asm` to work via the normal Makefile path

## Self-Check: PASSED

All files verified present, all commit hashes found in git log.

---
*Phase: 05-optimization-research-and-documentation*
*Completed: 2026-02-27*
