---
phase: 04-menus-and-game-modes
verified: 2026-02-26T23:00:00Z
status: human_needed
score: 13/13 must-haves verified
re_verification: false
human_verification:
  - test: "Launch binary and observe startup behavior"
    expected: "Binary shows main menu with title 'Y E T R I S', three action items (Start Game, Help, Quit) at rows 5/7/9, and five settings (Starting Level, Ghost Piece, Hold Piece, Invisible, Noise Rows) at rows 13-21. No direct entry into gameplay."
    why_human: "Terminal rendering output cannot be verified programmatically."
  - test: "Navigate menu with UP/DOWN arrow keys"
    expected: "Selected item is visually highlighted with reverse video (A_REVERSE). Highlight moves between all 8 items (0-7) and clamps at boundaries."
    why_human: "Visual ncurses attribute rendering requires terminal observation."
  - test: "Press ENTER on Help, then press any key"
    expected: "Help screen displays '-- CONTROLS --' title and all 9 keybindings. Any keypress returns to the main menu."
    why_human: "Help screen content and transition require visual confirmation."
  - test: "Adjust Starting Level with LEFT/RIGHT, then select Start Game"
    expected: "Level value changes (clamped 1-22). Game begins at the selected level's gravity speed (level 10+ noticeably faster than level 1)."
    why_human: "Gravity speed difference requires real-time observation."
  - test: "Set Ghost Piece to OFF, start game"
    expected: "No ghost piece (dim landing indicator) is visible below the active piece."
    why_human: "Visual absence of ghost piece requires terminal observation."
  - test: "Set Hold Piece to OFF, start game, press 'c'"
    expected: "Nothing happens when 'c' is pressed. Hold panel remains empty."
    why_human: "Input suppression behavior requires interactive testing."
  - test: "Set Invisible to ON, start game and place a piece"
    expected: "After a piece locks, all locked blocks disappear visually. Active piece still visible. Collision detection still works (new pieces stack on invisible blocks)."
    why_human: "Invisible mode rendering and collision preservation require interactive verification."
  - test: "Set Noise Rows to 5, start game"
    expected: "Bottom 5 rows have random garbage blocks, each row has at least one gap, blocks have random colors."
    why_human: "Random board state at startup requires visual verification."
  - test: "Play to game over, then press q/ESC"
    expected: "Game over overlay shown. After pressing q/ESC, returns to main menu (not program exit). Board resets cleanly. Score/level reset to initial values."
    why_human: "State transition correctness and clean screen redraw require interactive testing."
  - test: "Start multiple games in sequence without relaunching"
    expected: "Each new game starts fresh. Previously configured settings are preserved between games."
    why_human: "Session persistence behavior requires multi-game interactive testing."
  - test: "Press q/ESC during gameplay (not at game over)"
    expected: "Game over screen appears. Pressing q/ESC again returns to main menu."
    why_human: "Mid-game quit flow requires interactive verification."
---

# Phase 4: Menus and Game Modes Verification Report

**Phase Goal:** The game has a main menu, help screen, and configurable game modes -- it launches into a menu, not directly into gameplay
**Verified:** 2026-02-26T23:00:00Z
**Status:** human_needed
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|---------|
| 1 | Binary launches to main menu, not directly into game | VERIFIED | `main.s:89-90` explicitly sets `_game_state=0` before state loop; `Lstate_loop` dispatches `cbz w9, Lstate_menu` -> `bl _menu_frame` |
| 2 | UP/DOWN navigation works and selected item is visually highlighted | VERIFIED | `menu.s:271-287` decrement/increment `_menu_selection` (clamped 0-7); `menu.s:99-123` applies `wattr_on(A_REVERSE=0x40000)` for selected item, `wattr_off` after |
| 3 | Selecting 'Start Game' transitions to gameplay | VERIFIED | `menu.s:331-335` sets `_game_state=1` on ENTER when `w20==0`; `main.s:116-148` handles `Lstate_game` with full init sequence |
| 4 | Selecting 'Help' shows keybinding screen; any key returns to menu | VERIFIED | `menu.s:337-341` sets `_game_state=2`; `_help_frame` (menu.s:567-649) renders 9 keybinding lines, polls input, sets `_game_state=0` on any keypress |
| 5 | Selecting 'Quit' or pressing q/ESC exits cleanly | VERIFIED | `menu.s:325-329` sets `_game_state=0xFF` for Quit action; `menu.s:343-353` handles q/ESC keys; `main.s:106,259-265` exits via `Lstate_exit` -> `_endwin` -> `ret` |
| 6 | Player can adjust starting level (1-22) with LEFT/RIGHT | VERIFIED | `menu.s:373-381` decrements with floor clamp at 1; `menu.s:420-428` increments with ceiling clamp at 22; stored in `_starting_level` (.word in data.s) |
| 7 | Game over + q/ESC returns to menu (not program exit) | VERIFIED | `main.s:212-257`: game over screen -> `_wtimeout(-1)` blocking -> wait for q/ESC -> `Lreturn_to_menu` sets `_game_state=0`, resets `w20=0`, restores `_wtimeout(16)`, calls `_werase` |
| 8 | Ghost piece toggle works: OFF disables ghost rendering | VERIFIED | `render.s:1694-1699` checks `_opt_ghost` before `bl _draw_ghost_piece`; `cbz w8, Lskip_ghost_draw` skips rendering when 0 |
| 9 | Hold piece toggle works: OFF ignores 'c' key | VERIFIED | `input.s:197-200` checks `_opt_hold` before `_hold_piece`; `cbz w8, Lhandle_done` skips hold dispatch when 0 |
| 10 | Invisible mode: locked cells become value 8 (hidden but collision-active) | VERIFIED | `board.s:271-291`: after `_clear_lines`, checks `_opt_invisible`, iterates 200 board cells and sets all non-zero to 8; `render.s:214-216` routes value 8 to `Ldraw_empty_cell` |
| 11 | Initial noise fills bottom N rows with random garbage | VERIFIED | `board.s:604-677`: `_add_noise(w0)` fills from row 19 upward, random gap column per row, 50% fill probability, random color 1-7; clamped to 19 rows max |
| 12 | Starting level applied at game start | VERIFIED | `main.s:126-129`: copies `_starting_level` to `_level` during game init (before `_spawn_piece`) |
| 13 | `_add_noise` called from game init when noise > 0 | VERIFIED | `main.s:131-136`: loads `_opt_noise`, `cbz w0, Lskip_noise`, calls `bl _add_noise` with noise count in w0 |

**Score:** 13/13 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `asm/menu.s` | Menu rendering, help screen, menu input handling | VERIFIED | 652 lines. Exports `_menu_frame` and `_help_frame`. Contains full rendering loops, A_REVERSE highlighting, setting adjusters, and input dispatch for all 8 menu items. |
| `asm/data.s` | Game state machine variable, menu/settings variables | VERIFIED | Contains `_game_state`, `_menu_selection`, `_starting_level`, `_opt_ghost`, `_opt_hold`, `_opt_invisible`, `_opt_noise` in `__DATA,__data`. String tables and pointer tables in `__TEXT,__const` / `__DATA,__const`. |
| `asm/main.s` | Outer state machine loop dispatching MENU/GAME/HELP states | VERIFIED | `Lstate_loop` dispatches to `Lstate_menu`, `Lstate_game`, `Lstate_help`, `Lstate_exit`. Game init conditional via `w20` flag. Return-to-menu path complete. |
| `asm/board.s` | `_add_noise` function and invisible mode cell zeroing in `_lock_piece` | VERIFIED | `_add_noise` at line 604 (globl, substantive, 74 lines). Invisible mode loop at lines 271-291 in `_lock_piece`. |
| `asm/render.s` | Ghost piece conditional skip and invisible cell value 8 handling | VERIFIED | Lines 1694-1699: `_opt_ghost` check before `_draw_ghost_piece`. Lines 214-216: `cmp w23, #8` / `b.eq Ldraw_empty_cell` in `_draw_board`. |
| `asm/input.s` | Hold piece conditional skip based on `_opt_hold` | VERIFIED | Lines 197-200: `_opt_hold` check before `_hold_piece` dispatch in `Lcheck_c`. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `asm/main.s` | `asm/menu.s` | `bl _menu_frame` / `bl _help_frame` from state loop | WIRED | `main.s:109` `bl _menu_frame`; `main.s:113` `bl _help_frame` |
| `asm/main.s` | `asm/data.s` | `_game_state` checked every iteration | WIRED | `main.s:97-98` loads `_game_state` via `adrp+ldrb` each loop iteration |
| `asm/menu.s` | `asm/data.s` | `_menu_selection`, `_starting_level`, `_opt_*` reads/writes | WIRED | menu.s references all 7 settings variables via `adrp+ldrb/str` patterns throughout |
| `asm/main.s` | `asm/board.s` | `bl _add_noise` during game init when `_opt_noise > 0` | WIRED | `main.s:135` `bl _add_noise` inside `cbz w0, Lskip_noise` conditional |
| `asm/render.s` | `asm/data.s` | `_opt_ghost` checked before `_draw_ghost_piece` call | WIRED | `render.s:1695-1697` `adrp+ldrb _opt_ghost` + `cbz w8, Lskip_ghost_draw` |
| `asm/input.s` | `asm/data.s` | `_opt_hold` checked before `bl _hold_piece` | WIRED | `input.s:198-200` `adrp+ldrb _opt_hold` + `cbz w8, Lhandle_done` |
| `asm/board.s` | `asm/data.s` | `_opt_invisible` checked after locking to set cells to 8 | WIRED | `board.s:272-274` `adrp+ldrb _opt_invisible` + `cbz w9, Llock_skip_invisible` |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|---------|
| UI-01 | 04-01-PLAN | Main menu with game options | SATISFIED | `_menu_frame` in menu.s renders title, 3 action items, 5 settings. State machine in main.s dispatches to menu. Binary launches to menu (game_state=0). |
| UI-02 | 04-01-PLAN | Help screen with keybinding reference | SATISFIED | `_help_frame` renders "-- CONTROLS --" + 9 keybinding lines + "Press any key to return". Any key sets game_state=0. |
| UI-03 | 04-01-PLAN | Starting level selection (1-22) | SATISFIED | `_starting_level` variable in data.s, adjusted via menu LEFT/RIGHT (clamp 1-22), applied to `_level` at game init in main.s. |
| UI-04 | 04-02-PLAN | Game mode options (initial noise, invisible mode, ghost/hold toggles) | SATISFIED | All four modes implemented: ghost toggle in render.s, hold toggle in input.s, invisible mode in board.s, noise in board.s + main.s. |

### Anti-Patterns Found

None. Search for TODO/FIXME/PLACEHOLDER/placeholder across all asm/ files returned no matches.

### Build and Symbol Verification

- `make asm` completes successfully with output `# Assembly build successful!`
- Binary: `asm/bin/yetris-asm`
- All 10 required symbols confirmed in linked binary via `nm -U`:
  - `_add_noise` (T section - code)
  - `_game_state`, `_menu_selection`, `_starting_level`, `_opt_ghost`, `_opt_hold`, `_opt_invisible`, `_opt_noise` (D section - data)
  - `_menu_frame`, `_help_frame` (T section - code)
- Library dependencies: only `libncurses.5.4.dylib` and `libSystem.B.dylib` (no new libraries)

### Human Verification Required

The following items require interactive testing in a terminal and cannot be verified programmatically:

**1. Main Menu Visual Layout**
**Test:** Run `make asm-run` and observe startup
**Expected:** Title "Y E T R I S" visible at row 2, three action items highlighted/navigable, five settings with current values displayed. Binary does NOT jump directly into gameplay.
**Why human:** Terminal ncurses rendering requires visual confirmation.

**2. Menu Navigation and Highlighting**
**Test:** Press UP/DOWN arrow keys to move through all 8 menu positions
**Expected:** One item highlighted with reverse video at a time; highlight clamps at top (Start Game) and bottom (Noise Rows); no wrap-around.
**Why human:** A_REVERSE visual attribute requires terminal observation.

**3. Help Screen and Return**
**Test:** Navigate to "Help" and press ENTER, then press any key
**Expected:** Controls screen shows all 9 keybindings. Any key returns to main menu.
**Why human:** Screen transition and content layout require visual confirmation.

**4. Starting Level Effect on Gravity**
**Test:** Set level to 15+, start a game. Then set level to 1, start a new game.
**Expected:** Level 15+ gravity noticeably faster than level 1 (1000ms vs ~80ms drop interval).
**Why human:** Speed difference requires real-time gameplay observation.

**5. Ghost Piece Toggle**
**Test:** Set Ghost Piece to OFF, start game. Then set to ON, start new game.
**Expected:** OFF: no dim landing indicator below active piece. ON: ghost piece visible.
**Why human:** Visual presence/absence of ghost requires terminal observation.

**6. Hold Piece Toggle**
**Test:** Set Hold Piece to OFF, start game, press 'c' key.
**Expected:** Nothing happens. Hold panel stays empty. ON: 'c' swaps piece into hold slot normally.
**Why human:** Input suppression and hold panel state require interactive testing.

**7. Invisible Mode**
**Test:** Set Invisible to ON, start game, place one piece.
**Expected:** After piece locks, all locked blocks vanish visually. Active piece still visible. New pieces collide with invisible blocks (stack correctly).
**Why human:** Visual disappearance plus collision correctness require interactive gameplay.

**8. Initial Noise Rows**
**Test:** Set Noise Rows to 5, start game. Then set to 0, start new game.
**Expected:** 5: bottom 5 rows have random colored blocks with at least one gap per row. 0: board starts empty.
**Why human:** Random board layout requires visual confirmation.

**9. Game Over Return to Menu**
**Test:** Play until game over (or press q during gameplay), then press q/ESC
**Expected:** Game over overlay displayed. After q/ESC, main menu appears with clean board. Score/level reset. Settings preserved.
**Why human:** State transition, screen clear quality, and setting persistence require interactive testing.

**10. Multiple Game Session**
**Test:** Play 3+ games in sequence adjusting settings between each
**Expected:** Each game starts fresh. No terminal corruption, state leaks, or crashes across sessions.
**Why human:** Session stability cannot be verified without runtime execution.

### Gaps Summary

No automated gaps found. All 13 observable truths are verified by code inspection:
- State machine launch path to menu is wired correctly
- All menu rendering and input handling code is substantive (not stubs)
- All four game mode settings are implemented end-to-end (menu storage -> game init application -> in-game effect)
- Binary compiles and all required symbols are present in the linked output

Phase goal achievement depends only on human verification of visual and interactive behavior.

---

_Verified: 2026-02-26T23:00:00Z_
_Verifier: Claude (gsd-verifier)_
