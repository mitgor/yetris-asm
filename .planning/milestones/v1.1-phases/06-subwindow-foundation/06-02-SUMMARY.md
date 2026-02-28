---
phase: 06-subwindow-foundation
plan: 02
subsystem: ui
tags: [ncurses, subwindows, arm64, rendering, window-lifecycle, wnoutrefresh, doupdate]

# Dependency graph
requires:
  - phase: 06-subwindow-foundation
    provides: "12 WINDOW* pointer slots in data.s, 4 lifecycle functions in layout.s"
  - phase: 01-foundation
    provides: "data.s mutable state pattern, render.s/menu.s draw functions"
provides:
  - "All game rendering through subwindows (board, hold, score, next, stats, pause, game over)"
  - "All menu rendering through subwindows (logo, menu items, help)"
  - "wnoutrefresh+doupdate batch refresh protocol in _render_frame"
  - "Window lifecycle wired into state machine (startup, MENU->GAME, GAME->MENU, EXIT)"
  - "Panel title strings and gameplay strings in data.s"
  - "Game start time recording for statistics timer"
affects: [07-visual-polish, 08-scoring, 09-line-clear-animation, 10-background-animations, 11-hiscore]

# Tech tracking
tech-stack:
  added: [wborder, wnoutrefresh, doupdate]
  patterns: ["adrp+ldr for WINDOW* pointer access (local symbol, not GOT)", "wnoutrefresh per window + doupdate once per frame", "wborder for bordered panels (hold, score, next, rightmost, pause)", "container erase+wnoutrefresh before child draw"]

key-files:
  created: []
  modified: [asm/render.s, asm/menu.s, asm/main.s, asm/data.s]

key-decisions:
  - "Board coordinates unchanged (row+1, col*2+1) since board window fills its container at origin"
  - "Ldraw_mini_piece and Ldraw_number recover x19 from stack to use caller's WINDOW* pointer"
  - "Menu settings use compact single-row spacing (rows 7-11) to fit in 13-row bordered menu_items window"
  - "Help screen draws on _win_menu_main directly (full-screen text display, no panel split)"
  - "Arrow hints removed from menu (A_REVERSE highlight is sufficient indicator in bordered window)"
  - "wborder added to bordered panels instead of manual ASCII border drawing"

patterns-established:
  - "Subwindow draw pattern: load WINDOW* via adrp+ldr, draw content, call wnoutrefresh"
  - "Container erase protocol: werase+wnoutrefresh all containers before drawing children"
  - "State transition lifecycle: destroy old layout, create new layout at each state change"

requirements-completed: [LAYOUT-03, LAYOUT-04, LAYOUT-05, LAYOUT-06, LAYOUT-07]

# Metrics
duration: 7min
completed: 2026-02-27
---

# Phase 6 Plan 02: Subwindow Rendering Conversion Summary

**Complete rendering conversion from stdscr to named subwindows with wnoutrefresh+doupdate batch protocol, panel borders, timer display, and state-machine lifecycle wiring**

## Performance

- **Duration:** 7 min
- **Started:** 2026-02-27T08:56:07Z
- **Completed:** 2026-02-27T09:03:49Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- All 10 render.s draw functions converted from stdscr to WINDOW* pointers (_win_board, _win_hold, _win_score, _win_middle_right, _win_rightmost, _win_pause)
- Menu rendering converted to use _win_menu_logo and _win_menu_items subwindows
- _render_frame rewrites refresh protocol: erase containers, draw leaves, wnoutrefresh each, doupdate once
- Window lifecycle wired into all 4 state transitions in main.s
- Panel title strings (Hold, Next, Statistics, Paused), Hi-Score placeholder, timer display (MM:SS), and version string added
- 0 stdscr references remain in render.s; 10 wnoutrefresh + 1 doupdate calls

## Task Commits

Each task was committed atomically:

1. **Task 1: Convert render.s to subwindow rendering and add panel strings to data.s** - `9f3562f` (feat)
2. **Task 2: Convert menu.s to subwindow rendering and wire lifecycle into main.s** - `8803ee3` (feat)

## Files Created/Modified
- `asm/render.s` - Complete rewrite: all draw functions use WINDOW* pointers, _render_frame uses wnoutrefresh+doupdate, wborder for bordered panels
- `asm/data.s` - Added panel title strings, gameplay strings, piece letter table for stats display
- `asm/menu.s` - _menu_frame draws through _win_menu_logo/_win_menu_items, _help_frame uses _win_menu_main
- `asm/main.s` - Added _init_menu_layout at startup, lifecycle calls at MENU<->GAME transitions, dual destroy at EXIT, game_start_time recording

## Decisions Made
- Board window coordinates remain identical (row+1, col*2+1) since _win_board fills middle_left at origin
- Used wborder(win, 0,0,0,0,0,0,0,0) for default ACS box-drawing borders on all bordered panels
- Menu settings compacted to single-row spacing to fit in 13-row bordered window
- Help screen renders on _win_menu_main (the 80x24 container) since it's a full-screen reference
- Removed arrow hints from menu since A_REVERSE highlighting is sufficient in bordered context

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added wborder calls for all bordered panels**
- **Found during:** Task 1 (render.s conversion)
- **Issue:** Plan described bordered windows but didn't specify how borders would be drawn. Without explicit wborder calls, bordered panels would show no visible borders.
- **Fix:** Added wborder(win, 0,0,...) calls at the top of each bordered panel's draw function (hold, score, next, rightmost, pause, menu_items). The 8th arg goes on stack per Darwin ARM64 ABI.
- **Files modified:** asm/render.s, asm/menu.s
- **Verification:** make asm compiles cleanly
- **Committed in:** 9f3562f, 8803ee3

**2. [Rule 2 - Missing Critical] Added string constants for all text labels**
- **Found during:** Task 1 (data.s strings)
- **Issue:** Plan specified only a subset of strings. Additional labels needed for score panel (Score, Level, Lines), stats panel (Single, Double, Triple, Tetris), game over screen, and pause messages.
- **Fix:** Added all missing string constants to data.s, plus _piece_letters lookup table for stats display.
- **Files modified:** asm/data.s
- **Verification:** All strings referenced from render.s and menu.s resolve at link time
- **Committed in:** 9f3562f

---

**Total deviations:** 2 auto-fixed (2 missing critical)
**Impact on plan:** Both additions were necessary for complete rendering. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All rendering now goes through named subwindows at exact C++ column positions
- Phase 7 (Visual Polish) can build on this foundation for ACS box-drawing characters, color enhancements
- Phase 8 (Scoring) can modify _draw_score_panel for enhanced scoring display
- Phase 10 (Animations) has the subwindow infrastructure needed for animation compositing
- Phase 11 (Hi-Score) can replace the "(none)" placeholder in the score panel

## Self-Check: PASSED

- [x] asm/render.s exists and modified
- [x] asm/data.s exists and modified
- [x] asm/menu.s exists and modified
- [x] asm/main.s exists and modified
- [x] 06-02-SUMMARY.md exists
- [x] Commit 9f3562f found
- [x] Commit 8803ee3 found

---
*Phase: 06-subwindow-foundation*
*Completed: 2026-02-27*
