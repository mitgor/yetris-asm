---
phase: 06-subwindow-foundation
verified: 2026-02-27T09:07:47Z
status: passed
score: 14/14 must-haves verified
gaps: []
human_verification:
  - test: "Launch game, navigate menu, start a game, play several pieces, pause and resume, return to menu"
    expected: "Menu renders through logo/items subwindows; game board displays at column 12 with hold/score/next/stats panels at exact C++ positions; pause overlay appears; no visual artifacts or flicker"
    why_human: "Visual correctness of ncurses subwindow layout and panel positioning requires terminal execution"
  - test: "Play a full game until game over, then return to menu and start another game"
    expected: "GAME->MENU transition destroys game windows, creates menu windows cleanly; MENU->GAME creates game windows; statistics timer resets"
    why_human: "State transition correctness and clean window teardown requires runtime observation"
  - test: "Open help screen (select Help from menu), verify controls text, press any key to return"
    expected: "Help screen renders on _win_menu_main (full-screen), any key returns to menu"
    why_human: "Help screen rendering and navigation requires runtime observation"
---

# Phase 6: Subwindow Foundation Verification Report

**Phase Goal:** Game renders through named ncurses subwindows with pixel-perfect C++ panel layout
**Verified:** 2026-02-27T09:07:47Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | WINDOW* pointers exist in data.s for all 9 game panels and 3 menu panels | VERIFIED | `nm asm/data.o` shows all 12: _win_main, _win_leftmost, _win_hold, _win_score, _win_middle_left, _win_board, _win_middle_right, _win_rightmost, _win_pause, _win_menu_main, _win_menu_logo, _win_menu_items |
| 2 | _init_game_layout creates the full subwindow hierarchy via newwin+derwin matching C++ 80x24 geometry | VERIFIED | layout.s lines 55-157: newwin(24,80,0,0) for main; 8 derwin calls with exact C++ dimensions and positions |
| 3 | _destroy_game_layout deletes all game windows in reverse creation order and zeroes pointers | VERIFIED | layout.s lines 172-263: deletes pause, rightmost, middle_right, board, middle_left, score, hold, leftmost, main with cbz NULL guards; zeroes all 9 slots after |
| 4 | _init_menu_layout creates menu windows matching C++ menu geometry | VERIFIED | layout.s lines 277-315: newwin(24,80,0,0), derwin(menu_main,9,80,0,0), derwin(menu_main,13,28,10,24) |
| 5 | _destroy_menu_layout deletes all menu windows in reverse creation order and zeroes pointers | VERIFIED | layout.s lines 328-363: deletes menu_items, menu_logo, menu_main with cbz guards; zeroes all 3 slots |
| 6 | Binary compiles and links with layout.s included | VERIFIED | `make asm` output: "Assembly build successful!"; Makefile uses `$(wildcard $(ASM_DIR)/*.s)` which auto-discovers layout.s |
| 7 | Game screen displays 5 distinct panels rendered through separate subwindows at C++ column positions | VERIFIED | render.s: _draw_board loads _win_board; _draw_hold_panel loads _win_hold; _draw_score_panel loads _win_score; _draw_next_panel loads _win_middle_right; _draw_stats_panel loads _win_rightmost; 28 total _win_*@PAGE loads confirmed |
| 8 | Menu screen renders through dedicated subwindows matching C++ menu layout | VERIFIED | menu.s: 10 _win_menu_*@PAGE loads; logo drawn on _win_menu_logo at (2,14); items on _win_menu_items; help on _win_menu_main |
| 9 | Hold panel shows current held piece with 'Hold' title | VERIFIED | render.s line 842: _str_hold_title drawn in _draw_hold_panel on _win_hold; wborder call at line 833 |
| 10 | Score panel shows Score/Level/Lines labels within the score subwindow | VERIFIED | render.s lines 1254-1320: Hi-Score, Score, Level, Lines labels drawn on _win_score |
| 11 | Next panel shows next piece with 'Next' title within middle-right subwindow | VERIFIED | render.s line 771: _str_next_title drawn in _draw_next_panel on _win_middle_right; wborder at line 762 |
| 12 | Statistics panel shows piece counts, line clear counts, timer, and version string | VERIFIED | render.s lines 903-1128: _draw_stats_panel on _win_rightmost; piece letters table, Singles/Doubles/Triples/Tetris labels, timer via _game_start_time+_get_time_ms, _str_version |
| 13 | State transitions create and destroy window sets correctly | VERIFIED | main.s: _init_menu_layout at startup (line 93); _destroy_menu_layout+_init_game_layout on MENU->GAME (lines 131-132); _destroy_game_layout+_init_menu_layout on GAME->MENU (lines 313-314); dual destroy at EXIT (lines 503-504) |
| 14 | _render_frame uses wnoutrefresh+doupdate batch protocol | VERIFIED | render.s: 0 _stdscr@GOTPAGE references; 10 _wnoutrefresh calls; 1 _doupdate call; container erase+wnoutrefresh before leaf draws |

**Score:** 14/14 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `asm/data.s` | WINDOW* pointer slots for all subwindows + _game_start_time | VERIFIED | 12 _win_* slots + _game_start_time, all .quad 0, .globl, .p2align 3; 19 panel title strings added |
| `asm/layout.s` | Window lifecycle functions | VERIFIED | 4 exported functions: _init_game_layout, _destroy_game_layout, _init_menu_layout, _destroy_menu_layout confirmed via `nm asm/layout.o` |
| `asm/render.s` | All game rendering through subwindows | VERIFIED | All 10 functions present (.globl verified); 0 stdscr refs; 10 wnoutrefresh + 1 doupdate |
| `asm/menu.s` | Menu rendering through subwindows | VERIFIED | _menu_frame and _help_frame use _win_menu_logo, _win_menu_items, _win_menu_main |
| `asm/main.s` | Window lifecycle calls on state transitions | VERIFIED | 7 lifecycle bl calls at correct transition points |
| `Makefile` | layout.s in assembly build | VERIFIED | `$(wildcard $(ASM_DIR)/*.s)` auto-discovers layout.s; no explicit edit needed |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `asm/layout.s` | `asm/data.s` | adrp+str to store WINDOW* pointers | VERIFIED | All 12 _win_*@PAGE patterns present; store via str after bl _newwin/_derwin |
| `asm/layout.s` | ncurses | bl _newwin, bl _derwin, bl _delwin | VERIFIED | newwin/derwin calls in both init functions; delwin calls in both destroy functions |
| `asm/render.s` | `asm/data.s` | WINDOW* pointer loads | VERIFIED | 28 _win_*@PAGE loads across render functions; each draw function loads its target window |
| `asm/main.s` | `asm/layout.s` | bl calls on state transitions | VERIFIED | 4 unique lifecycle functions referenced as U in main.o; 7 call sites in main.s |
| `asm/render.s` | ncurses | wnoutrefresh+doupdate replacing wrefresh(stdscr) | VERIFIED | 0 stdscr@GOTPAGE in render.s; 10 _wnoutrefresh + 1 _doupdate; wborder for bordered panels |
| `asm/menu.s` | `asm/data.s` | _win_menu_*@PAGE loads | VERIFIED | 10 _win_menu_*@PAGE loads in menu.s; input still uses stdscr via _poll_input |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| LAYOUT-01 | 06-01 | Game screen uses ncurses subwindows (newwin/derwin) instead of direct stdscr drawing | SATISFIED | layout.s provides _init_game_layout with newwin+derwin hierarchy; render.s has 0 stdscr refs |
| LAYOUT-02 | 06-01 | Game layout matches C++ original's 80x24 grid with exact panel column positions | SATISFIED | layout.s: leftmost=12w at col 0, board=22w at col 12, middle_right=10w at col 34, rightmost=35w at col 44; exact match to C++ geometry |
| LAYOUT-03 | 06-02 | Hold panel displays in leftmost window (4 rows high, titled "Hold") | SATISFIED | derwin(leftmost, 4, 12, 0, 0) in layout.s; _draw_hold_panel on _win_hold with "Hold" title at render.s line 842 |
| LAYOUT-04 | 06-02 | Score panel displays Hi-Score, Score, and Level in leftmost window below Hold | SATISFIED | derwin(leftmost, 20, 12, 4, 0) in layout.s; _draw_score_panel draws Hi-Score/(none), Score, Level, Lines labels on _win_score |
| LAYOUT-05 | 06-02 | Next piece panel displays in middle-right window (titled "Next") | SATISFIED | derwin(main, 4, 10, 0, 34) in layout.s; _draw_next_panel on _win_middle_right with "Next" title |
| LAYOUT-06 | 06-02 | Statistics panel displays in rightmost window with piece counts, line clear counts, timer, and version string (titled "Statistics") | SATISFIED | derwin(main, 24, 35, 0, 44) in layout.s; _draw_stats_panel on _win_rightmost with all required content |
| LAYOUT-07 | 06-02 | Menu screen uses ncurses subwindows with logo window and menu window matching C++ layout | SATISFIED | _init_menu_layout creates menu_main(24,80), menu_logo(9,80), menu_items(13,28,10,24); menu.s draws through these |

**All 7 LAYOUT requirements satisfied.**

### Anti-Patterns Found

No anti-patterns detected in phase-modified files.

| File | Pattern | Severity | Verdict |
|------|---------|----------|---------|
| asm/render.s | TODO/FIXME/placeholder | None found | Clean |
| asm/menu.s | TODO/FIXME/placeholder | None found | Clean |
| asm/main.s | TODO/FIXME/placeholder | None found | Clean |
| asm/layout.s | TODO/FIXME/placeholder | None found | Clean |
| asm/data.s | TODO/FIXME/placeholder | None found | Clean |

Note: `_str_hiscore_none: .asciz "(none)"` is an intentional placeholder for Phase 11 (Hi-Score), not an implementation stub. The statistics timer (`_game_start_time`) uses real elapsed-time calculation via `_get_time_ms`.

### Human Verification Required

#### 1. Panel Layout Visual Correctness

**Test:** Run `make asm-run`. Observe the game menu, then start a game.
**Expected:** Menu shows "Y E T R I S" title in upper region (logo window), menu items and settings in bordered center window. Game shows hold panel (leftmost, 4 rows), score below it, board at col 12, next panel at col 34 (4 rows tall), statistics panel from col 44 to edge.
**Why human:** Visual correctness of ncurses subwindow positioning requires terminal execution to confirm pixel-perfect column placement.

#### 2. State Transition Cleanliness

**Test:** Play a game until game over, press 'q' to return to menu, start another game.
**Expected:** No visual artifacts between transitions; menu appears cleanly after game; new game starts with fresh layout; no stale content bleeding between panels.
**Why human:** Runtime window lifecycle management and visual artifact detection require terminal observation.

#### 3. Help Screen

**Test:** From menu, select Help (press Enter), observe controls screen, press any key to return.
**Expected:** Full-screen controls reference displayed on _win_menu_main; pressing any key returns to menu cleanly.
**Why human:** Help screen rendering correctness requires runtime observation.

### Gaps Summary

No gaps found. All 14 observable truths verified against the actual codebase:

- Plan 06-01 delivered: 12 WINDOW* pointer slots in data.s + _game_start_time, layout.s with 4 exported lifecycle functions, binary compiles cleanly.
- Plan 06-02 delivered: Complete rendering conversion from stdscr to named subwindows (0 stdscr references in render.s), wnoutrefresh+doupdate batch protocol (10 wnoutrefresh + 1 doupdate), wborder for all bordered panels, all panel title strings, state machine wired with 7 lifecycle call sites, menu and help screens through subwindows.
- All 7 LAYOUT requirements (LAYOUT-01 through LAYOUT-07) satisfied with direct code evidence.

Phase goal achieved: the game renders through named ncurses subwindows with the C++ 80x24 panel geometry fully reproduced in ARM64 assembly.

---

_Verified: 2026-02-27T09:07:47Z_
_Verifier: Claude (gsd-verifier)_
