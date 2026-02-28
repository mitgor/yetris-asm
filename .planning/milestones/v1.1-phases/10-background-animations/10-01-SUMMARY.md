---
phase: 10-background-animations
plan: 01
subsystem: animation
tags: [arm64, ncurses, fire-animation, dispatch-table, timer-gated]

# Dependency graph
requires:
  - phase: 06-subwindow-foundation
    provides: "_win_main and _win_menu_main WINDOW* pointers for animation drawing"
  - phase: 09-line-clear-animation
    provides: "Timer-gated animation pattern and _get_time_ms usage"
provides:
  - "Animation dispatch infrastructure: _anim_select_random, _anim_dispatch, dispatch table"
  - "Fire animation with cooling map, intensity propagation, and red/yellow/white color mapping"
  - "Animation state variables in data.s: _anim_type, _anim_buf1, _anim_buf2, _anim_snakes"
  - "Stub functions for water, snakes, and Game of Life animations"
  - "Integration hooks in render.s (_render_frame) and menu.s (_menu_frame)"
affects: [10-02-PLAN]

# Tech tracking
tech-stack:
  added: []
  patterns: [dispatch-table, timer-gated-update, static-buffer-animation, cooling-map-smoothing]

key-files:
  created: [asm/animation.s]
  modified: [asm/data.s, asm/main.s, asm/render.s, asm/menu.s]

key-decisions:
  - "Callee-saved registers (x19-x28) for fire draw loop state to avoid excessive stack spills across ncurses calls"
  - "Signed halfwords (ldrsh/strh) for fire intensity buffers to handle negative intermediate values during propagation"
  - "Animation draws into parent container windows (_win_main, _win_menu_main) so subwindows naturally overlay"

patterns-established:
  - "Animation dispatch: load _anim_type, index into function pointer table, blr to selected handler"
  - "Timer-gated animation: check elapsed ms vs rate constant, skip update but still draw if not time"
  - "Per-cell wattr_on/mvwaddch/wattr_off pattern for colored character rendering"

requirements-completed: [ANIM-01, ANIM-05, ANIM-06, ANIM-07]

# Metrics
duration: 3min
completed: 2026-02-27
---

# Phase 10 Plan 01: Animation Infrastructure + Fire Summary

**Fire animation with cooling-map propagation, dispatch table infrastructure, and menu/game integration hooks for all four animation types**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-27T17:56:02Z
- **Completed:** 2026-02-27T17:59:52Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Created complete animation dispatch infrastructure with function pointer table for 4 animation types
- Implemented fire algorithm: bottom-row heat spawn, upward propagation with cooling map, intensity-to-grayscale mapping, red/yellow/white color by intensity threshold
- Integrated animation rendering into both menu (_menu_frame) and game (_render_frame) loops between werase and wnoutrefresh of parent windows
- Random animation selection at startup via _arc4random_uniform(4)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add animation state variables and create animation.s** - `d5645ea` (feat)
2. **Task 2: Integrate animation dispatch into main.s, render.s, menu.s** - `ecf2bf5` (feat)

## Files Created/Modified
- `asm/animation.s` - New file: dispatch table, fire init/update/draw, stubs for water/snakes/life
- `asm/data.s` - Added _anim_type, _anim_last_update, _anim_buf1 (3840 bytes), _anim_buf2 (3840 bytes), _anim_snakes (200 bytes), _anim_snake_count, _anim_last_add
- `asm/main.s` - Added bl _anim_select_random after _init_menu_layout
- `asm/render.s` - Added bl _anim_dispatch between werase/wnoutrefresh of _win_main in _render_frame
- `asm/menu.s` - Added bl _anim_dispatch between werase/wnoutrefresh of _win_menu_main in _menu_frame

## Decisions Made
- Used callee-saved registers (x19-x28) for fire draw loop state (WINDOW*, buffers, row/col counters, grayscale pointer) to minimize stack spills across ncurses function calls
- Used signed halfwords (ldrsh/strh) for fire intensity buffers -- handles negative intermediate values during propagation without overflow
- Animation draws into parent container windows (_win_main, _win_menu_main) rather than child windows, allowing subwindows to naturally overlay the animation

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Animation infrastructure complete and ready for plan 10-02 (water, snakes, Game of Life)
- Stub functions exist for all three remaining animations -- plan 10-02 fills in implementations
- Integration hooks already in place in render.s and menu.s -- no further changes needed to those files

---
*Phase: 10-background-animations*
*Completed: 2026-02-27*
