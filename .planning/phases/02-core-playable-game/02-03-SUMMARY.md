---
phase: 02-core-playable-game
plan: 03
subsystem: asm-rendering-input
tags: [aarch64, arm64, ncurses, rendering, input, color-pairs, wmove, waddch, keypad, non-blocking-input]

# Dependency graph
requires:
  - phase: 01-foundation-and-darwin-abi-scaffold
    provides: "Makefile asm build pipeline, Darwin ABI conventions, main.s entry point"
  - phase: 02-core-playable-game
    plan: 01
    provides: "asm/data.s: board, piece_data, color_pairs, score/level/lines state, game_over flag"
provides:
  - "asm/render.s: _init_colors, _draw_board, _draw_piece, _draw_score_panel, _draw_game_over, _render_frame"
  - "asm/input.s: _init_input, _poll_input, _handle_input"
affects: [02-04-game-loop]

# Tech tracking
tech-stack:
  added: []
  patterns: [wmove-waddch-rendering, color-pair-block-drawing, integer-to-ascii-digit-extraction, non-blocking-input-polling, keypad-arrow-key-dispatch]

key-files:
  created: [asm/render.s, asm/input.s]
  modified: []

key-decisions:
  - "Used L-prefix local labels for all internal branch targets (Apple as requires assembler-local labels for conditional branches)"
  - "Used callee-saved registers (x19-x27) extensively to preserve loop counters and pointers across ncurses bl calls"
  - "Integer-to-ASCII conversion done via stack buffer with divide-by-10 loop, avoiding variadic printw/mvwprintw"
  - "Screen coordinates computed inline: board cell (row,col) maps to screen (row+1, col*2+1) with 2-char-wide blocks"

patterns-established:
  - "L-prefix local labels for all conditional branch targets in Apple as assembler"
  - "stdscr loaded via GOT at function entry, stored in x19 for reuse across all ncurses calls"
  - "wattr_on/wattr_off always called with 3 args (win, attr, NULL) -- third arg is opts parameter"
  - "wrefresh called exactly once per frame in _render_frame after all drawing completes"
  - "Key dispatch via sequential cmp+b.ne chain with key code preserved in callee-saved register"

requirements-completed: [REND-01, REND-02, REND-03, REND-05]

# Metrics
duration: 6min
completed: 2026-02-26
---

# Phase 2 Plan 3: Rendering and Input Summary

**ncurses rendering with 7-color board/piece/score drawing via wmove+waddch and non-blocking keyboard input dispatch for arrow keys, space, z, and q**

## Performance

- **Duration:** 6 min
- **Started:** 2026-02-26T20:00:04Z
- **Completed:** 2026-02-26T20:06:06Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Created asm/render.s (835 lines) with 6 exported rendering functions: color initialization (7 pairs), board drawing with borders and colored locked blocks, falling piece overlay with 5x5 grid traversal, score/level/lines panel with integer-to-ASCII conversion, game over screen, and frame orchestrator with single wrefresh
- Created asm/input.s (193 lines) with 3 exported input functions: non-blocking input configuration (keypad+wtimeout 16ms), key polling wrapper, and key dispatch mapping 7 keys to game actions
- All 8 assembly files (main.s, data.s, timer.s, random.s, board.s, piece.s, render.s, input.s) link into a single Mach-O arm64 binary via `make asm`
- All rendering avoids variadic ncurses functions (printw, mvwprintw) -- uses exclusively wmove+waddch

## Task Commits

Each task was committed atomically:

1. **Task 1: Create render.s with board, piece, score panel, and color rendering** - `3d903a7` (feat)
2. **Task 2: Create input.s with non-blocking input setup and key dispatch** - `ef7b3e7` (feat)

## Files Created/Modified
- `asm/render.s` - All visual rendering: _init_colors (7 color pairs), _draw_board (borders + locked blocks with color), _draw_piece (falling piece overlay), _draw_score_panel (score/level/lines with integer-to-ASCII), _draw_game_over (centered text), _render_frame (orchestrator with single wrefresh)
- `asm/input.s` - Input handling: _init_input (keypad TRUE + wtimeout 16ms + noecho + cbreak), _poll_input (wgetch wrapper), _handle_input (dispatches KEY_LEFT/RIGHT/DOWN/UP, space, z, q to game actions)

## Decisions Made
- Used L-prefix local labels for all internal branch targets after discovering Apple's assembler requires assembler-local labels for conditional branches (labels starting with _ are treated as external symbols)
- Preserved cell values in callee-saved register w23 in _draw_board to avoid reloading board data after ncurses calls (which clobber x0-x15)
- Recomputed screen coordinates after wattr_on call in _draw_piece since w10/w11 (caller-saved temporaries) are clobbered by the function call
- Used sequential cmp+b.ne chain for key dispatch rather than a jump table -- simpler and sufficient for 7 keys

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Changed underscore-prefixed labels to L-prefixed local labels**
- **Found during:** Task 1 (render.s assembly)
- **Issue:** Labels like `_draw_top_border_done`, `_draw_empty_cell`, etc. were treated as external symbols by Apple's `as`, causing "conditional branch requires assembler-local label" errors on all cbz/cbnz/b.eq branches
- **Fix:** Renamed all internal branch target labels from `_name` prefix to `Lname` prefix (e.g., `_draw_top_border_done` -> `Ltop_border_done`). The `L` prefix marks labels as assembler-local (private) in Mach-O convention.
- **Files modified:** asm/render.s, asm/input.s
- **Verification:** Both files assemble cleanly without errors
- **Committed in:** 3d903a7 (Task 1 commit -- fix applied before first successful assembly)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Minor assembler convention issue. No scope creep. Pattern now established for all future assembly files.

## Issues Encountered

None beyond the label naming convention fix documented above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- All rendering functions ready for the game loop (plan 04): _init_colors for setup, _render_frame for per-frame display
- All input functions ready for the game loop: _init_input for setup, _poll_input + _handle_input for per-frame key processing
- 9 total exported symbols across both files, all accessible via bl from other assembly files
- Pattern established: L-prefix local labels, stdscr in x19, 3-arg wattr_on/wattr_off, single wrefresh per frame

## Self-Check: PASSED

All files verified present, all commits verified in git log, binary builds successfully.

---
*Phase: 02-core-playable-game*
*Completed: 2026-02-26*
