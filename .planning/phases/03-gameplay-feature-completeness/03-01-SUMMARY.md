---
phase: 03-gameplay-feature-completeness
plan: 01
subsystem: gameplay
tags: [ghost-piece, hold-mechanic, next-preview, pause-resume, statistics, ncurses, aarch64-assembly]

# Dependency graph
requires:
  - phase: 02-core-game
    provides: "Playable Tetris with movement, rotation, scoring, 7-bag, and game over"
provides:
  - "Ghost piece rendering with A_DIM attribute (_compute_ghost_y, _draw_ghost_piece)"
  - "Hold piece mechanic with can_hold guard (_hold_piece, _draw_hold_panel)"
  - "Next piece preview from 7-bag (_draw_next_panel)"
  - "Pause/resume with gravity timer reset (_is_paused flag, pause gate in input.s and main.s)"
  - "Statistics tracking: per-piece-type counts and line clear type counts (_draw_stats_panel)"
  - "15 new state variables in data.s for hold, pause, and statistics"
affects: [04-menus-and-polish, 05-optimization-research]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "A_DIM (0x100000) attribute via movz+orr for ghost piece dimming"
    - "Internal Ldraw_mini_piece helper for reusable piece panel rendering"
    - "Pause gate pattern: check _is_paused before both input dispatch and gravity timer"
    - "Statistics counters wired into _lock_piece and _clear_lines at event points"

key-files:
  created: []
  modified:
    - "asm/data.s - 15 new state variables (hold, pause, statistics counters)"
    - "asm/piece.s - _compute_ghost_y (pure query) and _hold_piece (swap mechanic)"
    - "asm/board.s - stats increments in _lock_piece/_clear_lines, state resets in _reset_board"
    - "asm/input.s - pause gate, 'c' hold key, 'p' pause toggle with gravity reset"
    - "asm/main.s - pause gate before gravity timer check"
    - "asm/render.s - 6 new rendering functions, updated _render_frame orchestration, score panel moved to col 34"

key-decisions:
  - "Score panel shifted from column 24 to column 34 to make room for Next/Hold panels at column 23"
  - "A_DIM constructed via movz w9, #0x10, lsl #16 since 0x100000 is not encodable as ARM64 logical immediate"
  - "1-piece next preview using _bag[_bag_index] direct read (simplest approach, no double-bag needed)"
  - "Pause overlay renders in place of ghost/active pieces, but all panels still render during pause"
  - "Statistics panel uses sequential cmp+b.ne chain for piece type letters (consistent with input dispatch pattern)"

patterns-established:
  - "Panel rendering at fixed column offsets: Next/Hold at col 23, Score at col 34, Stats at col 23 (lower rows)"
  - "Ghost piece rendering BEFORE active piece so bright colors overwrite dim at overlap positions"
  - "Pause gate: input.s blocks all keys except p/q/ESC; main.s skips gravity; render.s shows overlay"
  - "can_hold flag resets in _lock_piece (board.s), not in input handler, ensuring per-lock-cycle hold limit"

requirements-completed: [MECH-09, MECH-10, MECH-11, MECH-13, REND-04]

# Metrics
duration: 6min
completed: 2026-02-26
---

# Phase 3 Plan 1: Gameplay Features Summary

**Ghost piece with A_DIM dimming, hold/swap mechanic with can_hold guard, next piece preview from 7-bag, pause/resume with gravity timer reset, and full statistics panel showing per-piece-type counts and line clear types**

## Performance

- **Duration:** 6 min
- **Started:** 2026-02-26T20:57:30Z
- **Completed:** 2026-02-26T21:04:08Z
- **Tasks:** 3
- **Files modified:** 6

## Accomplishments
- Ghost piece renders as dimmed landing preview using COLOR_PAIR | A_DIM attribute, drawn before active piece so bright colors overwrite at overlap
- Hold mechanic with proper swap logic: first hold stores current and spawns next, subsequent holds swap current with held piece, can_hold flag prevents double-hold within same lock cycle
- Next piece preview reads directly from _bag[_bag_index] without consuming, showing upcoming piece in side panel
- Pause freezes gravity (main.s gate) and blocks all input except p/q/ESC (input.s gate), with gravity timer reset on unpause to prevent burst drops
- Statistics panel tracks 7 per-piece-type counters and 4 line clear type counters (singles/doubles/triples/tetris), incremented at event points in _lock_piece and _clear_lines
- Screen layout reorganized: Next/Hold panels at column 23, Score/Level/Lines shifted to column 34

## Task Commits

Each task was committed atomically:

1. **Task 1: Add state variables and mechanics (data.s, piece.s, board.s)** - `a8eb56f` (feat)
2. **Task 2: Add input keys and game loop integration (input.s, main.s)** - `e50d64f` (feat)
3. **Task 3: Add all new rendering functions (render.s)** - `e10c95a` (feat)

## Files Created/Modified
- `asm/data.s` - 15 new state variables: hold_piece_type, can_hold, is_paused, stats_pieces, 7x stats_piece_counts, stats_singles/doubles/triples/tetris
- `asm/piece.s` - _compute_ghost_y (pure query, never modifies state) and _hold_piece (swap mechanic with can_hold guard)
- `asm/board.s` - Stats increments in _lock_piece (piece counts + can_hold reset) and _clear_lines (line type stats), full state reset in _reset_board
- `asm/input.s` - Pause gate at top of _handle_input, 'c' key for hold, 'p' key for pause toggle with gravity timer reset on unpause
- `asm/main.s` - Pause gate skips gravity timer check when paused
- `asm/render.s` - 6 new functions (_draw_ghost_piece, Ldraw_mini_piece, _draw_next_panel, _draw_hold_panel, _draw_stats_panel, _draw_paused_overlay), updated _render_frame orchestration, score panel moved to col 34

## Decisions Made
- Score panel shifted from column 24 to 34 to accommodate Next/Hold panels at column 23 -- keeps all side panels visible without terminal width concerns
- Used movz w9, #0x10, lsl #16 to construct A_DIM (0x100000) since it cannot be encoded as ARM64 logical immediate for ORR instruction
- Chose 1-piece next preview using direct _bag[_bag_index] read rather than maintaining a separate preview queue -- simplest approach that satisfies MECH-09
- Pause overlay renders instead of ghost/active pieces but panels still render during pause -- player can see score/stats while paused
- Ldraw_mini_piece helper shared between next and hold panels to avoid code duplication

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All Phase 3 gameplay features (ghost, hold, next, pause, stats) are implemented and compiling
- Ready for Phase 3 Plan 2 (binary size measurement) or Phase 4 (menus and polish)
- All existing Phase 2 functionality preserved: movement, rotation, scoring, 7-bag, game over

## Self-Check: PASSED

All 6 modified files exist. All 3 task commit hashes verified (a8eb56f, e50d64f, e10c95a). SUMMARY.md created. Binary compiles and links successfully with all new symbols exported.

---
*Phase: 03-gameplay-feature-completeness*
*Completed: 2026-02-26*
