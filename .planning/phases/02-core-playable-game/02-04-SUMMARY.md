---
phase: 02-core-playable-game
plan: 04
subsystem: asm-game-loop
tags: [aarch64, arm64, game-loop, gravity, ncurses, tetris, integration]

# Dependency graph
requires:
  - phase: 02-core-playable-game
    provides: "Data tables (02-01), board/piece mechanics (02-02), rendering/input (02-03)"
provides:
  - "asm/main.s: Complete Tetris game loop -- init, input poll, gravity timer, rendering, game over"
  - "Playable Tetris binary via `make asm-run`"
affects: [03-gameplay-feature-completeness]

# Tech tracking
tech-stack:
  added: []
  patterns: [game-loop-with-timer-gravity, callee-saved-register-allocation, wtimeout-frame-pacing]

key-files:
  created: []
  modified: [asm/main.s, asm/timer.s, asm/input.s]

key-decisions:
  - "Used x19-x23 callee-saved registers for gravity timing state across function calls, requiring 64-byte stack frame"
  - "Used wtimeout(16) for natural 60fps frame pacing instead of usleep/napms"
  - "Dual game_over checks per loop iteration -- after input and after gravity -- for immediate game-over response"
  - "Switch to blocking wtimeout(-1) on game over screen to avoid CPU busy-wait while waiting for quit key"

patterns-established:
  - "Game loop structure: poll input -> check game_over -> gravity timer -> render -> loop"
  - "Gravity timer: compare elapsed ms against _gravity_delays[level-1], reset on drop"
  - "ESC key (27) as quit alternative to 'q' for ergonomic exit"

requirements-completed: [MECH-04]

# Metrics
duration: 11min
completed: 2026-02-26
---

# Phase 2 Plan 4: Game Loop Integration Summary

**Complete Tetris game loop in ARM64 assembly wiring together all 8 source files into a playable binary with gravity timer, input polling, and game-over handling**

## Performance

- **Duration:** 11 min
- **Started:** 2026-02-26T20:10:36Z
- **Completed:** 2026-02-26T20:21:28Z
- **Tasks:** 2 (plus 1 bug fix)
- **Files modified:** 3

## Accomplishments
- Rewrote main.s from Phase 1 hello-world into complete Tetris game loop: initialization sequence (initscr, cbreak, noecho, init_colors, init_input, reset_board, spawn_piece), main loop (poll_input, handle_input, gravity timer, render_frame), and shutdown (game over display, endwin cleanup)
- All 8 assembly source files (main.s, data.s, timer.s, random.s, board.s, piece.s, render.s, input.s) link into a single playable binary
- Gravity timer properly scales from 1000ms (level 1) to 0ms (level 22) using _gravity_delays lookup table
- Human verified as playable: pieces fall, controls work (arrows, space, z, q, ESC), lines clear, score updates, game over triggers, terminal restores cleanly
- Fixed timer.s stack corruption (bus error) and added ESC key support based on user feedback

## Task Commits

Each task was committed atomically:

1. **Task 1: Rewrite main.s with complete Tetris game loop** - `ad146c2` (feat)
2. **Task 2: Human verification of playable Tetris** - Approved by user (no commit)
3. **Bug fix: timer.s stack corruption + ESC key support** - `74203a9` (fix)

## Files Created/Modified
- `asm/main.s` - Complete game loop: init sequence, input polling, gravity timer with level-based delays, render frame dispatch, game-over screen with blocking quit wait, clean shutdown
- `asm/timer.s` - Fixed stack frame to use stp/ldp pairs with proper 16-byte aligned frame (was using misaligned str/ldr causing bus error)
- `asm/input.s` - Added ESC key (ASCII 27) as alternative quit key alongside 'q'

## Decisions Made
- Used x19-x23 callee-saved registers for gravity timing state (current_time, last_drop_time, elapsed, level_index, delay) to avoid reloading across bl calls, requiring a 64-byte stack frame in _main
- Used wtimeout(16) via _init_input for natural ~60fps frame pacing rather than explicit sleep calls -- wgetch blocks up to 16ms providing natural frame timing
- Implemented dual game_over checks per loop iteration (after input dispatch and after gravity/render) to ensure immediate game-over response whether triggered by quit key, hard drop collision, or gravity-induced spawn failure
- On game over, switch wtimeout to -1 (blocking) so the program waits for 'q' without burning CPU

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed timer.s stack frame corruption causing bus error**
- **Found during:** Post-Task 2 human verification (user reported crash)
- **Issue:** timer.s _get_time_ms used misaligned `str x30, [sp, #-8]!` / `ldr x30, [sp], #8` which violated 16-byte stack alignment requirement, causing bus error on some code paths
- **Fix:** Changed to proper `stp x29, x30, [sp, #-16]!` / `ldp x29, x30, [sp], #16` pair with frame pointer setup
- **Files modified:** asm/timer.s
- **Verification:** Game runs without crashing, gravity timer works correctly
- **Committed in:** 74203a9

**2. [Rule 2 - Missing Critical] Added ESC key as quit alternative**
- **Found during:** Post-Task 2 user feedback (requested ESC key support)
- **Issue:** Only 'q' key could quit the game; ESC is a more intuitive quit key
- **Fix:** Added `cmp w0, #27` (ESC) check in input.s key dispatch, setting _game_over flag
- **Files modified:** asm/input.s, asm/main.s (ESC check in game-over wait loop)
- **Verification:** Both 'q' and ESC properly exit the game
- **Committed in:** 74203a9

---

**Total deviations:** 2 auto-fixed (1 bug, 1 missing critical)
**Impact on plan:** Bug fix was essential for stability (bus error crash). ESC key was user-requested usability improvement. No scope creep.

## Issues Encountered

- Timer stack corruption caused intermittent bus errors during gameplay. Root cause was 8-byte stack push violating Darwin's 16-byte alignment requirement. Fixed by switching to standard stp/ldp frame setup.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Phase 2 complete: all 8 assembly files produce a fully playable Tetris game
- `make asm-run` launches the game directly -- no additional setup needed
- Ready for Phase 3 feature additions: ghost piece, hold, next preview, pause, statistics
- Binary is a single Mach-O arm64 executable linking only against libSystem and libncurses

## Self-Check: PASSED

All files verified present, all commits verified in git log.

---
*Phase: 02-core-playable-game*
*Completed: 2026-02-26*
