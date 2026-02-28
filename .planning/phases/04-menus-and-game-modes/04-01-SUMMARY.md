---
phase: 04-menus-and-game-modes
plan: 01
subsystem: ui
tags: [ncurses, menu, state-machine, arm64-assembly]

# Dependency graph
requires:
  - phase: 03-gameplay-features
    provides: "Complete gameplay with hold, ghost, stats, pause"
provides:
  - "Main menu with 3 actions (Start/Help/Quit) and 5 settings"
  - "Help screen with full keybinding reference"
  - "Game state machine (MENU/GAME/HELP/EXIT) in main.s"
  - "Starting level selector (1-22)"
  - "Game over returns to menu instead of exiting"
affects: [04-02-PLAN]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "State machine dispatch via _game_state byte variable"
    - "A_REVERSE (0x40000) for menu item highlighting"
    - "Pointer tables in __DATA,__const for relocatable .quad references"
    - "w20 callee-saved register as game_initialized flag across state transitions"

key-files:
  created:
    - asm/menu.s
  modified:
    - asm/data.s
    - asm/main.s

key-decisions:
  - "Moved pointer tables (.quad arrays) to __DATA,__const to avoid illegal text relocations in __TEXT,__const"
  - "Menu selection range 0-7: items 0-2 are actions, 3-7 are settings for unified UP/DOWN navigation"
  - "Used w20 callee-saved register as game_initialized flag, shifting gravity timing to x21-x23"
  - "Implemented local Lmenu_draw_small_number/Lmenu_draw_on_off helpers since render.s Ldraw_number is L-prefixed (file-local)"

patterns-established:
  - "State machine: _game_state byte dispatches outer loop in main.s"
  - "Menu rendering: wattr_on(A_REVERSE) for selected item, wattr_off after drawing"
  - "Settings: LEFT/RIGHT adjusts values with per-type clamping"

requirements-completed: [UI-01, UI-02, UI-03]

# Metrics
duration: 4min
completed: 2026-02-26
---

# Phase 04 Plan 01: Menu System Summary

**Main menu with Start/Help/Quit actions, 5 configurable settings, help screen, and MENU/GAME/HELP state machine replacing linear game flow**

## Performance

- **Duration:** 4 min
- **Started:** 2026-02-26T22:05:45Z
- **Completed:** 2026-02-26T22:10:16Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Created complete menu system with title, 3 action items, and 5 settings with A_REVERSE highlighting
- Built help screen showing all 9 keybindings with "Press any key to return" prompt
- Restructured main.s from linear init-game-exit flow to MENU/GAME/HELP/EXIT state machine
- Game over now returns to menu for multiple games per session

## Task Commits

Each task was committed atomically:

1. **Task 1: Add game state/settings variables to data.s and create menu.s** - `dea57f8` (feat)
2. **Task 2: Restructure main.s as a state machine** - `cf14647` (feat)

## Files Created/Modified
- `asm/menu.s` - New file: _menu_frame (menu rendering + input), _help_frame (controls screen), local number/on-off drawing helpers
- `asm/data.s` - Added _game_state, _menu_selection, _starting_level, _opt_ghost/hold/invisible/noise variables; menu/help string constants; pointer tables in __DATA,__const
- `asm/main.s` - Replaced linear game loop with state machine outer loop; game init deferred to GAME state entry; game over transitions to menu

## Decisions Made
- Moved pointer tables (.quad arrays referencing string labels) from __TEXT,__const to __DATA,__const section to avoid linker "illegal text-relocations" errors. Text sections cannot contain relocatable pointers on Darwin.
- Unified menu selection range 0-7 (0-2 = actions, 3-7 = settings) for seamless UP/DOWN navigation across all items.
- Implemented file-local helper functions (Lmenu_draw_small_number, Lmenu_draw_on_off) rather than making render.s Ldraw_number global, keeping render.s unchanged.
- Used w20 as game_initialized flag, shifting gravity timing registers to x21-x23 (from original x20-x22).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Moved pointer tables to __DATA,__const to fix text relocation errors**
- **Found during:** Task 1 (data.s + menu.s creation)
- **Issue:** .quad pointer tables in __TEXT,__const caused "Found illegal text-relocations" linker error. Darwin requires relocatable data in DATA segments.
- **Fix:** Added `.section __DATA,__const` before the three pointer tables (_menu_items, _settings_labels, _help_lines)
- **Files modified:** asm/data.s
- **Verification:** `make asm` builds successfully
- **Committed in:** dea57f8 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Necessary linker fix. No scope creep.

## Issues Encountered
None beyond the text relocation fix documented above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Menu system fully operational, ready for plan 04-02 (game mode features: noise rows, invisible mode, ghost/hold toggles)
- _opt_ghost, _opt_hold, _opt_invisible, _opt_noise variables are set by menu but not yet consumed by gameplay code (deferred to 04-02)

## Self-Check: PASSED

All files exist, all commits verified, binary builds successfully.

---
*Phase: 04-menus-and-game-modes*
*Completed: 2026-02-26*
