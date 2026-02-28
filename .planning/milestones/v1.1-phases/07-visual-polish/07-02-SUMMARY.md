---
phase: 07-visual-polish
plan: 02
subsystem: ui
tags: [ncurses, A_REVERSE, A_BOLD, pause-menu, game-over, color-pairs, arm64-assembly]

# Dependency graph
requires:
  - phase: 07-visual-polish
    plan: 01
    provides: "_draw_fancy_border, color pairs 8-11, pause menu strings, _pause_selection variable"
provides:
  - "Interactive 3-item pause menu (Resume, Quit to Main Menu, Quit Game) with UP/DOWN/ENTER navigation"
  - "Styled GAME OVER text with A_BOLD + A_REVERSE emphasis"
  - "Colored first-letter mnemonics on main menu action items (bold cyan first char)"
affects: [phase-08, phase-10]

# Tech tracking
tech-stack:
  added: []
  patterns: [pause menu navigation via _pause_selection + key dispatch, first-char mnemonic coloring]

key-files:
  created: []
  modified: [asm/render.s, asm/input.s, asm/menu.s]

key-decisions:
  - "Pause 'p' during gameplay enters pause; pause gate handles all pause-state keys separately"
  - "Quit to Main Menu sets _game_over=1 to leverage existing game-over-to-menu transition in main.s"
  - "First-letter mnemonics only on 3 action items (Start Game, Help, Quit) -- settings items unchanged"

patterns-established:
  - "Pause menu dispatch: pause gate intercepts all keys when _is_paused != 0, routes to dedicated handlers"
  - "Mnemonic coloring: wattr_on(bold cyan) -> waddch(first char) -> wattr_off -> waddstr(rest)"

requirements-completed: [VISUAL-05, VISUAL-07, VISUAL-08]

# Metrics
duration: 3min
completed: 2026-02-27
---

# Phase 7 Plan 2: Interactive Overlays and Menu Mnemonics Summary

**Interactive 3-item pause menu with UP/DOWN/ENTER navigation, bold+reverse GAME OVER text, and bold cyan first-letter mnemonics on main menu items**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-27T14:04:27Z
- **Completed:** 2026-02-27T14:07:05Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Rewrote _draw_paused_overlay to display 3 selectable menu items (Resume, Quit to Main Menu, Quit Game) with A_REVERSE highlighting on the selected item based on _pause_selection
- Expanded pause gate in _handle_input to support UP/DOWN navigation (clamp 0-2), ENTER activation dispatching to resume/quit-menu/quit-game, and 'p' shortcut for resume
- Added Lpause_resume handler (reset _is_paused + _pause_selection, reset gravity timer) and Lpause_quit_to_menu handler (set _game_over=1, reset pause state)
- Styled "GAME OVER" text with A_BOLD | A_REVERSE for visual emphasis on the board window
- Added colored first-letter mnemonics to main menu action items -- non-selected items show first character in bold cyan (hilite_hilite_text) with rest in normal color

## Task Commits

Each task was committed atomically:

1. **Task 1: Convert pause overlay to 3-item selectable menu with input handling** - `5a20b87` (feat)
2. **Task 2: Style game over overlay and add colored first-letter mnemonics to main menu** - `d71d860` (feat)

## Files Created/Modified
- `asm/render.s` - Rewrote _draw_paused_overlay with 3 selectable items, added A_BOLD|A_REVERSE to _draw_game_over
- `asm/input.s` - Expanded pause gate with UP/DOWN/ENTER navigation, added Lpause_resume and Lpause_quit_to_menu handlers, simplified Lcheck_p for pause-entry-only
- `asm/menu.s` - Added bold cyan first-letter mnemonic coloring for non-selected action items in _menu_frame

## Decisions Made
- Pause 'p' during gameplay enters pause (Lcheck_p); all pause-state key handling moved to dedicated pause gate
- Quit to Main Menu reuses existing _game_over -> Lgame_over_screen -> Lreturn_to_menu flow in main.s
- First-letter mnemonics applied only to 3 action items (Start Game, Help, Quit) -- settings items use label+value format and are left unchanged

## Deviations from Plan

None - plan executed exactly as written.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- All visual polish for phase 7 is complete (borders, colors, logo, pause menu, game over, mnemonics)
- Ready for phase 8 (scoring enhancements) or subsequent phases
- Pause menu navigation is fully functional and integrates with existing game loop

## Self-Check: PASSED

All 3 source files exist, SUMMARY.md created, both task commits verified (5a20b87, d71d860).

---
*Phase: 07-visual-polish*
*Completed: 2026-02-27*
