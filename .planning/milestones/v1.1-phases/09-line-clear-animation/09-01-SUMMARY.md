---
phase: 09-line-clear-animation
plan: 01
subsystem: game-engine
tags: [arm64, ncurses, animation, neon, state-machine]

# Dependency graph
requires:
  - phase: 08-modern-scoring-engine
    provides: "Scoring pipeline in _lock_piece, _clear_lines with NEON row detection"
provides:
  - "_mark_lines: replaces _clear_lines call, overwrites full rows with flash value 9"
  - "_clear_marked_lines: collapses flash-marked rows after delay"
  - "_line_clear_state / _line_clear_timer: animation state variables"
  - "Flash cell rendering (value 9 -> '::' white) in _draw_board"
  - "Game loop Lflash_active state machine with 200ms non-blocking delay"
  - "Deferred spawn in _hard_drop, _soft_drop, _user_soft_drop"
affects: [10-background-animations, 11-hi-score]

# Tech tracking
tech-stack:
  added: []
  patterns: [mark-then-delay-then-clear animation, board cell value 9 as flash marker, non-blocking timer state machine]

key-files:
  created: []
  modified:
    - asm/data.s
    - asm/board.s
    - asm/render.s
    - asm/piece.s
    - asm/input.s
    - asm/main.s

key-decisions:
  - "Board cell value 9 used as flash marker -- natural extension of 0-8 value space"
  - "Scoring happens at mark time (immediately), not after 200ms delay"
  - "_mark_lines sets _line_clear_state internally, callers check w0 for spawn deferral"
  - "Input still processes during flash (movement/rotation are no-ops with no active piece)"
  - "_clear_lines kept as dead code for reference until mark/clear proven"

patterns-established:
  - "Mark-then-delay-then-clear: two-phase line removal with non-blocking timer"
  - "Deferred spawn: _lock_piece returns lines count, callers conditionally skip _spawn_piece"

requirements-completed: [CLEAR-01, CLEAR-02]

# Metrics
duration: 3min
completed: 2026-02-27
---

# Phase 9 Plan 01: Line Clear Animation Summary

**Two-phase mark/clear line removal with 200ms '::' white flash using non-blocking game loop state machine**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-27T16:18:03Z
- **Completed:** 2026-02-27T16:22:00Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- Split atomic _clear_lines into _mark_lines (overwrite with value 9) and _clear_marked_lines (collapse rows) for two-phase animation
- Added flash cell rendering: board value 9 displays as '::' in white COLOR_PAIR(3) via Ldraw_flash_cell in render.s
- Implemented non-blocking 200ms animation state machine in game loop (Lflash_active) -- gravity paused during flash, timer-based expiry triggers collapse + spawn + gravity reset
- All three lock-then-spawn call sites (_hard_drop, _soft_drop, _user_soft_drop) now conditionally defer spawn when lines are cleared

## Task Commits

Each task was committed atomically:

1. **Task 1: Add animation state variables and create _mark_lines/_clear_marked_lines** - `37d6f72` (feat)
2. **Task 2: Add flash rendering, deferred spawn, and game loop animation state machine** - `9267356` (feat)

## Files Created/Modified
- `asm/data.s` - Added _line_clear_state (byte) and _line_clear_timer (quad) after _last_drop_time
- `asm/board.s` - Created _mark_lines (NEON row scan, overwrite with 9, update stats, set flash state), _clear_marked_lines (collapse marked rows), changed _lock_piece to call _mark_lines, added reset in _reset_board
- `asm/render.s` - Added Ldraw_flash_cell label: value 9 renders as '::' in white COLOR_PAIR(3)
- `asm/piece.s` - _hard_drop and _soft_drop conditionally skip _spawn_piece via cbnz on _lock_piece return
- `asm/input.s` - _user_soft_drop conditionally skips _spawn_piece via cbnz on _lock_piece return
- `asm/main.s` - Added Lflash_active block: checks 200ms timer, calls _clear_marked_lines + _spawn_piece on expiry, resets gravity timer and syncs game_over

## Decisions Made
- Board cell value 9 chosen as flash marker (natural extension of 0=empty, 1-7=colors, 8=invisible)
- Scoring happens at mark time (in _lock_piece immediately), not after 200ms delay -- consistent with modern guidelines
- _mark_lines sets _line_clear_state=1 internally rather than callers setting it -- keeps flash state co-located with marking logic
- _clear_lines kept as dead code for reference (linker strips it since nothing calls it)
- Input continues to process during flash (movement keys are no-ops since no active piece; pause/quit still work)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Line clear animation fully functional with 200ms flash delay
- All scoring, combo, T-spin, and perfect clear mechanics unchanged (scoring at mark time)
- Ready for Phase 10 (background animations) or Phase 11 (hi-score)

## Self-Check: PASSED

- All 6 modified files exist on disk
- Both task commits verified (37d6f72, 9267356)
- `make asm` builds successfully with no errors
- All 4 new symbols verified in binary: _mark_lines, _clear_marked_lines, _line_clear_state, _line_clear_timer

---
*Phase: 09-line-clear-animation*
*Completed: 2026-02-27*
