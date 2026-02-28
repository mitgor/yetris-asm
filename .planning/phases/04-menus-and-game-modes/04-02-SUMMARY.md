---
phase: 04-menus-and-game-modes
plan: 02
subsystem: gameplay
tags: [ncurses, game-modes, arm64-assembly, collision, rendering]

# Dependency graph
requires:
  - phase: 04-menus-and-game-modes
    plan: 01
    provides: "Menu system with _opt_ghost/hold/invisible/noise settings variables"
provides:
  - "Ghost piece toggle: _opt_ghost checked before _draw_ghost_piece"
  - "Hold piece toggle: _opt_hold checked before _hold_piece dispatch"
  - "Invisible mode: locked cells set to value 8 (collision-preserving invisibility)"
  - "Initial noise: _add_noise fills bottom N rows with random garbage"
  - "All four game mode settings fully wired from menu to gameplay"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Cell value 8 as invisible marker: non-zero for collision, skipped in rendering"
    - "_add_noise uses _arc4random_uniform for gap column and block placement"

key-files:
  created: []
  modified:
    - asm/board.s
    - asm/render.s
    - asm/input.s
    - asm/main.s

key-decisions:
  - "Cell value 8 for invisible mode: non-zero preserves collision detection, _draw_board skips rendering"
  - "Invisible mode sets ALL non-zero cells to 8 after each lock (full-board invisibility)"
  - "Noise rows filled bottom-up with 1 guaranteed gap per row and 50% fill probability"

patterns-established:
  - "Game mode options: check _opt_* variable with adrp+ldrb, cbz to skip feature"
  - "Board cell value 8: invisible marker convention for collision-visible but render-hidden cells"

requirements-completed: [UI-04]

# Metrics
duration: 2min
completed: 2026-02-26
---

# Phase 04 Plan 02: Game Mode Settings Summary

**Four game mode toggles (ghost, hold, invisible, noise) wired from menu settings into gameplay via conditional checks in board.s, render.s, input.s, and main.s**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-26T22:13:44Z
- **Completed:** 2026-02-26T22:15:37Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Ghost piece toggle skips _draw_ghost_piece in _render_frame when _opt_ghost is 0
- Hold piece toggle skips _hold_piece dispatch in _handle_input when _opt_hold is 0
- Invisible mode sets all locked board cells to value 8 after each _lock_piece, preserving collision detection while hiding blocks visually
- Initial noise function _add_noise fills bottom N rows with random garbage (1 gap per row, 50% fill, random colors 1-7)
- _add_noise called from game init in main.s when _opt_noise > 0

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement game mode effects** - `2714a97` (feat)
2. **Task 2: Verify complete menu system and all game modes** - auto-approved (checkpoint:human-verify)

## Files Created/Modified
- `asm/board.s` - Added _add_noise function (random garbage row generation) and invisible mode loop in _lock_piece (sets non-zero cells to value 8)
- `asm/render.s` - Added _opt_ghost conditional before _draw_ghost_piece in _render_frame; added cell value 8 skip in _draw_board
- `asm/input.s` - Added _opt_hold conditional before _hold_piece dispatch in _handle_input
- `asm/main.s` - Replaced TODO comment with _add_noise call during game init when _opt_noise > 0

## Decisions Made
- Used cell value 8 as invisible marker: _is_piece_valid treats any non-zero cell as occupied (collision preserved), while _draw_board routes value 8 to the empty-cell rendering path
- Invisible mode sets ALL non-zero board cells to 8 (not just newly locked piece), matching simplified full-board invisibility approach from research
- _add_noise clamps to 19 rows max (must leave at least 1 empty row for spawning)
- Saved _clear_lines return value in w24 callee-saved register before invisible mode loop to preserve lines_cleared count

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 4 complete: full menu system with configurable game modes
- All UI requirements (UI-01 through UI-04) implemented
- Ready for Phase 5 optimization research

## Self-Check: PASSED

All files exist, all commits verified, binary builds successfully.

---
*Phase: 04-menus-and-game-modes*
*Completed: 2026-02-26*
