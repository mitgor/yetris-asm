---
phase: 06-subwindow-foundation
plan: 01
subsystem: ui
tags: [ncurses, subwindows, arm64, layout, window-lifecycle]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: "data.s mutable state pattern, Makefile assembly build"
provides:
  - "12 WINDOW* pointer slots in data.s (9 game + 3 menu)"
  - "_game_start_time elapsed timer slot"
  - "_init_game_layout / _destroy_game_layout lifecycle functions"
  - "_init_menu_layout / _destroy_menu_layout lifecycle functions"
affects: [06-subwindow-foundation, 07-visual-polish, 08-scoring, 10-background-animations]

# Tech tracking
tech-stack:
  added: []
  patterns: ["adrp+str for storing WINDOW* pointers to data slots", "derwin parent hierarchy with callee-saved register preservation", "reverse-order window deletion with cbz NULL guard"]

key-files:
  created: [asm/layout.s]
  modified: [asm/data.s]

key-decisions:
  - "No Makefile change needed -- existing $(wildcard) pattern auto-discovers layout.s"
  - "Used .p2align 3 for all pointer slots (8-byte alignment for 64-bit WINDOW* pointers)"
  - "Callee-saved x19-x21 hold parent WINDOW* across derwin calls in init functions"

patterns-established:
  - "Window lifecycle pattern: init creates hierarchy top-down, destroy deletes bottom-up with NULL guards and pointer zeroing"
  - "Data slot pattern: .globl + .p2align 3 + .quad 0 for each WINDOW* pointer"

requirements-completed: [LAYOUT-01, LAYOUT-02]

# Metrics
duration: 2min
completed: 2026-02-27
---

# Phase 6 Plan 01: Subwindow Foundation Summary

**12 WINDOW* pointer slots in data.s and 4 lifecycle functions in layout.s for ncurses game/menu window hierarchies matching C++ 80x24 geometry**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-27T08:50:59Z
- **Completed:** 2026-02-27T08:53:15Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- 12 WINDOW* pointer slots (9 game + 3 menu) added to data.s with proper 8-byte alignment
- `_game_start_time` elapsed timer slot for future statistics display
- `asm/layout.s` created with 4 exported functions: init/destroy for both game and menu window hierarchies
- All window geometry matches C++ LayoutGame.cpp / LayoutMainMenu.cpp exactly
- Binary compiles and links cleanly -- no regressions (functions defined but not yet called)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add WINDOW* pointer slots and game_start_time to data.s** - `76accbb` (feat)
2. **Task 2: Create layout.s with window lifecycle functions** - `f628480` (feat)

## Files Created/Modified
- `asm/data.s` - Added 12 WINDOW* pointer slots (.quad 0, .globl, .p2align 3) and _game_start_time
- `asm/layout.s` - New file with _init_game_layout, _destroy_game_layout, _init_menu_layout, _destroy_menu_layout

## Decisions Made
- No Makefile edit needed: the existing `$(wildcard $(ASM_DIR)/*.s)` pattern automatically discovers layout.s
- Used x19-x21 callee-saved registers to hold parent WINDOW* pointers across bl _derwin calls
- Destroy functions delete children before parents (reverse creation order) and zero all pointers after deletion

## Deviations from Plan

None - plan executed exactly as written.

(The plan specified adding layout.s to ASM_SRCS in the Makefile, but the actual Makefile uses `$(wildcard ...)` which auto-discovers new .s files. No Makefile edit was necessary -- this is correct behavior, not a deviation.)

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All 12 WINDOW* pointers are available for cross-file access via adrp+ldr
- Plan 06-02 can now call _init_game_layout/_init_menu_layout and wire rendering to subwindows
- No callers added yet -- game runs identically to before this change

## Self-Check: PASSED

- [x] asm/layout.s exists
- [x] asm/data.s exists
- [x] 06-01-SUMMARY.md exists
- [x] Commit 76accbb found
- [x] Commit f628480 found

---
*Phase: 06-subwindow-foundation*
*Completed: 2026-02-27*
