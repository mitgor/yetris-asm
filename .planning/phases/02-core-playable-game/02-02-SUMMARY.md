---
phase: 02-core-playable-game
plan: 02
subsystem: asm-game-mechanics
tags: [aarch64, arm64, collision-detection, srs-rotation, wall-kicks, line-clearing, hard-drop, soft-drop, game-over]

# Dependency graph
requires:
  - phase: 02-core-playable-game
    plan: 01
    provides: "asm/data.s game data tables (piece_data, srs_kicks, score_table, level_thresholds, spawn positions) and utilities (random.s, timer.s)"
provides:
  - "asm/board.s: Collision detection (_is_piece_valid), piece locking (_lock_piece), line clearing with scoring (_clear_lines), board reset (_reset_board)"
  - "asm/piece.s: Movement (_try_move), SRS rotation with wall kicks (_try_rotate), hard drop (_hard_drop), soft drop (_soft_drop), piece spawning (_spawn_piece), game over detection (_check_game_over)"
affects: [02-03-rendering-input, 02-04-game-loop]

# Tech tracking
tech-stack:
  added: []
  patterns: [5x5-grid-collision-loop, srs-kick-with-y-negation, bottom-to-top-line-clear, callee-saved-register-heavy-functions]

key-files:
  created: [asm/board.s, asm/piece.s]
  modified: []

key-decisions:
  - "Used 64-byte stack frames for complex functions to preserve 6 callee-saved registers across _is_piece_valid loop iterations"
  - "Negated SRS kick Y-values at application time in _try_rotate, matching C++ reference pattern (this->y -= dy)"
  - "Level computation scans _level_thresholds linearly (22 entries max) -- threshold[0] maps to level 2"
  - "Lock piece stores piece_type+1 (values 1-7) in board cells so 0 remains the empty sentinel"

patterns-established:
  - "Board operations in board.s, piece operations in piece.s -- clean separation of concerns"
  - "All piece state loads use ldrsh for signed halfword (piece_x, piece_y) and ldrb for unsigned byte (piece_type, piece_rotation)"
  - "SRS kick table indexed as dir_idx*40 + start_rotation*10 + test*2, loaded with ldrsb for signed offsets"
  - "Functions that call _is_piece_valid save piece state in x19-x22 to survive the bl call"
  - "Line clearing scans bottom-to-top and re-checks same row index after shifting to correctly handle consecutive full rows"

requirements-completed: [MECH-02, MECH-03, MECH-05, MECH-06, MECH-07, MECH-12, MECH-14, MECH-15]

# Metrics
duration: 4min
completed: 2026-02-26
---

# Phase 2 Plan 2: Board and Piece Mechanics Summary

**Collision detection, SRS wall-kick rotation, line clearing with scoring, hard/soft drop, and game over detection in AArch64 assembly**

## Performance

- **Duration:** 4 min
- **Started:** 2026-02-26T19:59:54Z
- **Completed:** 2026-02-26T20:03:51Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Created asm/board.s with 4 functions: _is_piece_valid (25-cell collision loop against walls/floor/blocks), _lock_piece (writes cells to board + lock bonus), _clear_lines (bottom-to-top scan with row shifting, score/lines/level update), _reset_board (zeros board + resets state)
- Created asm/piece.s with 6 functions: _try_move (dx/dy movement), _try_rotate (SRS with 5 kick tests per rotation, separate I-piece table, Y-axis negation), _hard_drop (loop to lowest position + lock + spawn), _soft_drop (down one + lock if blocked), _spawn_piece (7-bag + spawn position), _check_game_over (spawn collision detection)
- All 10 functions link successfully with existing data.s, timer.s, random.s, and main.s into a single Mach-O arm64 binary
- Full SRS wall kick support with separate JLSTZ and I-piece kick tables, correctly negating Y for board coordinate convention

## Task Commits

Each task was committed atomically:

1. **Task 1: Create board.s with collision detection, piece locking, and line clearing** - `db94f5b` (feat)
2. **Task 2: Create piece.s with movement, SRS rotation, drops, spawning, and game over** - `e350f50` (feat)

## Files Created/Modified
- `asm/board.s` - Board operations: collision detection (_is_piece_valid iterates 5x5 grid), piece locking (_lock_piece writes type+1 to board), line clearing (_clear_lines with row shifting and score/level update), board reset (_reset_board)
- `asm/piece.s` - Piece operations: movement (_try_move), SRS rotation with wall kicks (_try_rotate), hard drop (_hard_drop), soft drop (_soft_drop), spawning from 7-bag (_spawn_piece), game over detection (_check_game_over)

## Decisions Made
- Used 64-byte stack frames for _is_piece_valid and _lock_piece to save 6 callee-saved registers (x19-x24) needed across the 25-iteration loop
- Negated SRS kick Y-values at application time in _try_rotate (`neg w10, w10`), keeping the raw tetris.wiki convention in the data tables (as established in plan 01)
- Level computation: threshold[index] maps to level index+2, with level=1 as the base before any thresholds are met
- Lock piece stores piece_type+1 (1-7) rather than piece_type (0-6) so that 0 remains the empty-cell sentinel in the board array

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- `make asm` fails due to a pre-existing untracked `asm/render.s` file (from plan 03 work) that has assembler label naming errors. This is out-of-scope for plan 02. Manual linking of all 6 committed .s files succeeds without errors. Logged to deferred-items.md.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- All game mechanics functions ready for consumption by plan 03 (rendering/input) and plan 04 (game loop)
- _is_piece_valid, _lock_piece, _clear_lines, _reset_board exported from board.s
- _try_move, _try_rotate, _hard_drop, _soft_drop, _spawn_piece, _check_game_over exported from piece.s
- All functions use consistent ABI: callee-saved registers for state across bl calls, signed loads for coordinates, unsigned loads for types

## Self-Check: PASSED

All files verified present, all commits verified in git log, all 10 exported symbols confirmed, binary links successfully.

---
*Phase: 02-core-playable-game*
*Completed: 2026-02-26*
