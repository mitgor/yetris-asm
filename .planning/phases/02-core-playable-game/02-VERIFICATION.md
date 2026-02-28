---
phase: 02-core-playable-game
verified: 2026-02-26T21:30:00Z
status: human_needed
score: 14/14 automated must-haves verified
human_verification:
  - test: "Run `make asm-run` and play through a complete game session"
    expected: "Pieces spawn and fall automatically; arrow keys move and rotate with wall kicks; space hard-drops; down soft-drops; lines clear and score updates; GAME OVER overlay appears when board fills; q/ESC exit cleanly"
    why_human: "Terminal rendering, real-time gravity feel, SRS wall kick visual behavior, and clean terminal restore cannot be verified programmatically"
  - test: "Verify level-based gravity speed increase is perceptible"
    expected: "Level 1 drop interval (1000ms) is noticeably slower than level 5+ (500ms); by level 10 pieces fall visibly faster"
    why_human: "Timing feel requires interactive play to assess"
  - test: "Verify SRS wall kick correctness at board edges"
    expected: "Rotating a piece flush against the left or right wall succeeds with a visible position correction (kick); rotation fails only when all 5 kick positions are blocked"
    why_human: "Wall kick visual behavior requires live play against actual board state"
  - test: "Verify terminal restores cleanly after exit"
    expected: "Cursor visible, echo restored, no garbled characters in the terminal after the game exits"
    why_human: "Terminal state restoration can only be confirmed by a human looking at the terminal after endwin"
---

# Phase 2: Core Playable Game Verification Report

**Phase Goal:** Playable Tetris game in ARM64 assembly with all core mechanics — 7 tetrominoes with SRS rotation, gravity with level-based speed, line clearing with scoring, hard/soft drop, ncurses rendering with colors, keyboard input, and game over detection. `make asm-run` launches a working game.
**Verified:** 2026-02-26T21:30:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|---------|
| 1 | All 7 tetrominoes defined with 4 rotation states each as 5x5 grids | VERIFIED | `_piece_data`: 700 bytes at binary address 0x10000178c (7 * 4 * 25 = 700, confirmed by nm address diff) |
| 2 | SRS wall kick tables exist for JLSTZ and I-piece with correct values | VERIFIED | `_srs_kicks_jlstz` and `_srs_kicks_i`: 80 bytes each; values match tetris.wiki spec; loaded with `ldrsb`; Y negated in piece.s via `neg w10, w10` |
| 3 | Gravity timer scales from 1000ms (level 1) to 0ms (level 22) | VERIFIED | `_gravity_delays`: 44 bytes / 22 .hword entries; values 1000,900,...,0; indexed by (level-1)*2 in main.s game loop |
| 4 | Score table maps 1-4 line clears to 100/300/500/800 | VERIFIED | `_score_table`: 16 bytes / 4 .word entries with values 100,300,500,800; +10 lock bonus in `_lock_piece` |
| 5 | Collision detection rejects walls, floor, and existing blocks | VERIFIED | `_is_piece_valid`: 5x5 loop with signed bounds checks (board_x<0, board_x>=10, board_y>=20, board[]=nonzero); above-board (board_y<0) is valid |
| 6 | SRS rotation tries 5 kick tests with separate I-piece table | VERIFIED | `_try_rotate`: test 0 (no kick) then tests 1-4 from either `_srs_kicks_i` or `_srs_kicks_jlstz`; selected by `cmp w19, #1`; Y negated at application |
| 7 | Line clearing removes full rows, collapses above, updates score/lines/level | VERIFIED | `_clear_lines`: scans row 19 down to 0; re-checks same row after shift (Lclear_row_loop w/o decrement); updates `_score`, `_lines_cleared`, `_level` |
| 8 | Hard drop moves piece to lowest valid position and locks immediately | VERIFIED | `_hard_drop`: loops `try_y+1` until `_is_piece_valid` fails, stores final y, calls `_lock_piece` then `_spawn_piece` |
| 9 | Soft drop moves down one row, locks if blocked | VERIFIED | `_soft_drop`: `_try_move(0,1)`; on failure calls `_lock_piece` + `_spawn_piece` |
| 10 | 7-bag random generator shuffles and draws without repeats within a bag | VERIFIED | `_shuffle_bag`: Fisher-Yates with `arc4random_uniform`; `_next_piece`: auto-refills when bag_index>=7 |
| 11 | Timer returns milliseconds via gettimeofday | VERIFIED | `_get_time_ms`: `gettimeofday` -> tv_sec*1000 + tv_usec/1000; correct stp/ldp stack frame (bus error fixed in 74203a9) |
| 12 | Board + piece + score panel rendered using ncurses wmove+waddch with 7 colors | VERIFIED | `_draw_board`, `_draw_piece`, `_draw_score_panel`: 68 wmove/waddch/werase calls; 7 init_pair calls; no printw/mvwprintw; `_wattr_on`/`_wattr_off` with 3 args (x2=#0) |
| 13 | Input non-blocking with 16ms timeout; arrow keys, space, z, q dispatched | VERIFIED | `_init_input`: keypad(TRUE)+wtimeout(16); `_handle_input`: cmp chain for KEY_LEFT(260)/RIGHT(261)/DOWN(258)/UP(259)/space(32)/z(122)/q(113)/ESC(27) |
| 14 | Game loop: input poll -> gravity timer -> render, exits on game over | VERIFIED | `_main` game loop: `_poll_input` -> `_handle_input` -> `_game_over` check -> gravity compare -> `_soft_drop` -> `_render_frame`; blocking wtimeout(-1) on game over |

**Score:** 14/14 truths verified by static analysis

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `asm/data.s` | All game data tables + mutable state | VERIFIED | 453 lines; 21 exported symbols confirmed by nm; piece_data=700B, srs_kicks=80B each, board=200B |
| `asm/timer.s` | gettimeofday wrapper returning ms | VERIFIED | Exports `_get_time_ms`; correct stp/ldp frame; tv_sec*1000+tv_usec/1000 |
| `asm/random.s` | 7-bag Fisher-Yates generator | VERIFIED | Exports `_shuffle_bag`, `_next_piece`; arc4random_uniform; auto-refill on bag_index>=7 |
| `asm/board.s` | Collision detection, locking, line clearing | VERIFIED | Exports `_is_piece_valid`, `_lock_piece`, `_clear_lines`, `_reset_board`; 25-cell loop; bottom-to-top scan |
| `asm/piece.s` | Movement, SRS rotation, drops, spawn, game over | VERIFIED | Exports `_try_move`, `_try_rotate`, `_hard_drop`, `_soft_drop`, `_spawn_piece`, `_check_game_over`; SRS Y-negation at line 210,252 |
| `asm/render.s` | Board, piece, score panel, colors, game over screen | VERIFIED | 835 lines; exports `_init_colors`, `_draw_board`, `_draw_piece`, `_draw_score_panel`, `_draw_game_over`, `_render_frame`; single wrefresh in `_render_frame` |
| `asm/input.s` | Non-blocking input setup and key dispatch | VERIFIED | 193 lines; exports `_init_input`, `_poll_input`, `_handle_input`; 7 key bindings + ESC |
| `asm/main.s` | Complete game loop with init and shutdown | VERIFIED | `_main`: init sequence -> game loop -> game over screen -> endwin; gravity timer with `_gravity_delays` lookup |
| `asm/bin/yetris-asm` | Mach-O arm64 binary | VERIFIED | 52856 bytes; `file` confirms Mach-O 64-bit arm64; `make asm` succeeds cleanly |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `board.s::_is_piece_valid` | `data.s::_piece_data`, `_board` | Loads 5x5 grid cells, checks board array | WIRED | 23 references to `_piece_data`/`_board` in board.s |
| `piece.s::_try_rotate` | `data.s::_srs_kicks_jlstz`, `_srs_kicks_i` | Loads kick offsets, calls `_is_piece_valid` per test | WIRED | 4 references to `_srs_kicks`; 6 calls to `_is_piece_valid`; `neg w10` Y-inversion at lines 210,252 |
| `piece.s::_spawn_piece` | `random.s::_next_piece` | Gets piece type from 7-bag | WIRED | `bl _next_piece` in `_spawn_piece` |
| `board.s::_clear_lines` | `data.s::_score`, `_lines_cleared`, `_level` | Updates after clearing | WIRED | 36 references to score/level/lines in board.s; all three updated in `Lclear_done` |
| `render.s::_draw_board` | `data.s::_board` | Reads board cells for color/char | WIRED | `_board` loaded in `_draw_board`; `ldrb w23, [x20, w8, uxtw]` for each cell |
| `render.s::_draw_piece` | `data.s::_piece_data`, `_piece_type`, `_piece_x`, `_piece_y` | Renders falling piece at current position | WIRED | All four symbols loaded at top of `_draw_piece`; 6 piece references in render.s |
| `render.s::_draw_score_panel` | `data.s::_score`, `_level`, `_lines_cleared` | Reads and converts to ASCII for display | WIRED | All three loaded for `Ldraw_number` calls; no variadic printw |
| `input.s::_handle_input` | `piece.s::_try_move`, `_try_rotate`, `_hard_drop`, `_soft_drop` | Maps key codes to game actions | WIRED | 19 references across 7 dispatch branches; key preserved in callee-saved w19 |
| `main.s::game_loop` | `input.s::_poll_input`, `_handle_input` | Polls key, dispatches each frame | WIRED | `bl _poll_input` -> `cmn w0,#1` -> `bl _handle_input`; w0 preserved |
| `main.s::game_loop` | `timer.s::_get_time_ms` + `data.s::_gravity_delays` | Gravity timer comparison | WIRED | `_get_time_ms` called -> elapsed vs `_gravity_delays[level-1]` -> `_soft_drop` |
| `main.s::game_loop` | `render.s::_render_frame` | Single render call per iteration | WIRED | `bl _render_frame` after gravity; wrefresh only inside `_render_frame` |
| `main.s::init` | `_init_colors`, `_init_input`, `_reset_board`, `_spawn_piece` | Initialization sequence | WIRED | All 4 called sequentially before game loop |

All 12 key links WIRED.

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|---------|
| MECH-01 | 02-01 | 7-tetromino set with 4 rotations each | SATISFIED | `_piece_data`: 700 bytes, 7 types x 4 rotations x 25 cells; all 28 states in data.s |
| MECH-02 | 02-02 | SRS rotation with full wall kick tables (5-kick, separate I-piece) | SATISFIED | `_try_rotate`: 5 tests per rotation; `_srs_kicks_i` selected for type==1; Y negated |
| MECH-03 | 02-02 | 10x20 playfield with collision detection | SATISFIED | `_is_piece_valid`: board_x<0, board_x>=10, board_y>=20 bounds; board[200B] |
| MECH-04 | 02-04 | Gravity timer scaling level 1(1000ms) to level 22(0ms) | SATISFIED | `_gravity_delays[22]` used in main.s loop; level-1 index; cmp+soft_drop |
| MECH-05 | 02-02 | Piece locking when piece cannot move down | SATISFIED | `_soft_drop`: on `_try_move` failure -> `_lock_piece` + `_spawn_piece` |
| MECH-06 | 02-02 | Line clearing with gravity drop on cleared rows | SATISFIED | `_clear_lines`: full-row scan, row-shift loop, re-check same index |
| MECH-07 | 02-02 | Hard drop (instant) and soft drop (accelerated) | SATISFIED | `_hard_drop`: loop to lowest valid y; `_soft_drop`: move down one row |
| MECH-08 | 02-01 | 7-bag random piece generator | SATISFIED | `_shuffle_bag` (Fisher-Yates, arc4random_uniform) + `_next_piece` (auto-refill) |
| MECH-12 | 02-02 | Game over detection (piece spawns in occupied space) | SATISFIED | `_check_game_over`: `_is_piece_valid` on spawn position; sets `_game_over=1` if invalid |
| MECH-14 | 02-02 | Level progression based on lines cleared | SATISFIED | `Lclear_level_scan`: linear scan of `_level_thresholds[22]`; level=index+2 |
| MECH-15 | 02-02 | Scoring (1=100, 2=300, 3=500, 4=800, +10 per lock) | SATISFIED | `_score_table`: {100,300,500,800}; `_lock_piece`: adds 10 before `_clear_lines` |
| REND-01 | 02-03 | ncurses board, piece, and UI panel rendering | SATISFIED | `_draw_board`, `_draw_piece`, `_draw_score_panel`, `_draw_game_over` via wmove+waddch |
| REND-02 | 02-03 | 7 color-coded pieces (S=green, Z=red, O=yellow, I=cyan, L=orange/white, J=blue, T=magenta) | SATISFIED | `_init_colors`: 7 `init_pair` calls; colors match spec (note: L=white as orange substitute) |
| REND-03 | 02-03 | Score, lines, and level display panel | SATISFIED | `_draw_score_panel`: Score/Level/Lines labels + `Ldraw_number` at (2,24),(5,24),(8,24) |
| REND-05 | 02-03 | Input handling (arrow keys, space for hard drop, configurable keys) | SATISFIED | `_handle_input`: KEY_LEFT/RIGHT/DOWN/UP, space(32), z(122), q(113), ESC(27) |

All 15 phase-2 requirements SATISFIED.

**No orphaned requirements:** REQUIREMENTS.md traceability table assigns exactly MECH-01,02,03,04,05,06,07,08,12,14,15 and REND-01,02,03,05 to Phase 2. All accounted for in plan frontmatter.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None found | — | — | — | — |

No TODOs, FIXMEs, placeholders, empty implementations, or variadic ncurses calls found across all 8 source files. No usage of x18. wrefresh called exactly once (render.s:828, inside `_render_frame`). wattr_on/wattr_off called with 3 arguments (x2=#0) at render.s:205,221,388,418.

---

### Human Verification Required

All 14 automated must-haves pass. The following items require a human to play the game to fully confirm goal achievement:

#### 1. End-to-End Playability

**Test:** Run `make asm-run` and play a complete game session (5-10 minutes)
**Expected:** Pieces spawn and fall automatically; all 7 piece shapes appear over time (7-bag distribution); arrow keys move and rotate correctly with wall kick corrections visible at board edges; space hard-drops to floor instantly; down arrow accelerates fall; full rows disappear with rows above collapsing; score increments on piece lock (+10) and line clears (100/300/500/800); GAME OVER text overlays the board when pieces stack to spawn zone; q or ESC exits to clean terminal
**Why human:** Interactive terminal game — rendering correctness, gravity feel, SRS wall kick visual behavior, and terminal state restoration require live observation

#### 2. Level-Based Gravity Speed Feel

**Test:** Play until reaching level 2-3, observe drop speed change
**Expected:** Drop interval visibly slows at level 1 (1 second between gravity ticks) and speeds up progressively; by level 5 (500ms) the difference from level 1 is clearly perceptible
**Why human:** Timing perception is subjective and requires interactive play

#### 3. SRS Wall Kick Visual Correctness

**Test:** Push a piece against the right wall; attempt rotation that would clip the wall
**Expected:** Piece rotates with a leftward position correction (kick applied); no through-wall clipping; only fails when no kick position is valid
**Why human:** Visual board state during wall kicks requires live observation

#### 4. Terminal Restore on Exit

**Test:** Exit game via q or ESC after `make asm-run`
**Expected:** Terminal returns to normal state — cursor visible, text echo restored, no garbled characters, shell prompt appears normally
**Why human:** Terminal state (cursor, echo, raw mode) can only be confirmed by a human observing the terminal after `_endwin` runs

---

### Gaps Summary

No gaps found. All 14 automated must-haves are fully verified:
- All 8 assembly source files exist and are substantive (no stubs, no placeholders)
- All 24 exported functions (code) and 21 exported symbols (data) are present in the linked binary
- All 12 key links between modules are wired and active
- All 15 phase-2 requirements are satisfied by concrete implementation evidence
- `make asm` builds successfully; `asm/bin/yetris-asm` is a 52856-byte Mach-O arm64 binary
- No anti-patterns (no x18 usage, no variadic ncurses calls, no TODO/placeholders, single wrefresh)

The only remaining gate is human confirmation that the running game is actually playable — which was reportedly approved during plan 04 execution (02-04-SUMMARY.md documents human verification approved). That approval predates this formal verification pass; the items above re-confirm the requirement for a human to observe the live game.

---

_Verified: 2026-02-26T21:30:00Z_
_Verifier: Claude (gsd-verifier)_
