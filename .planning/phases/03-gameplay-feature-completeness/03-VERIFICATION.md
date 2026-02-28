---
phase: 03-gameplay-feature-completeness
verified: 2026-02-26T22:30:00Z
status: human_needed
score: 9/10 must-haves verified
re_verification: false
human_verification:
  - test: "Run `make asm-run` and verify ghost piece renders as dimmed blocks at landing position, updates when piece is moved/rotated"
    expected: "A dim version of the current piece appears at the bottom showing where it will land; ghost follows movement and rotation in real-time"
    why_human: "A_DIM visual attribute (0x100000) cannot be verified programmatically; requires terminal observation"
  - test: "Press 'c' to hold current piece; press 'c' again to swap; press 'c' a third time before next lock to confirm rejection"
    expected: "First hold stores piece in Hold panel and spawns next; second hold swaps; third hold before lock is silently ignored"
    why_human: "can_hold flag logic correctness under real input timing requires interactive confirmation"
  - test: "Press 'p' to pause; attempt movement; press 'p' again to resume; observe that piece resumes falling at normal speed without sudden burst"
    expected: "Pause freezes gravity and blocks all movement/rotation keys; resume resets timer so no accumulated drops fire"
    why_human: "Gravity timer reset on unpause and key-blocking correctness require runtime observation"
  - test: "Lock multiple pieces and clear lines; verify Statistics panel shows correct per-piece-type counts and singles/doubles/triples/tetris counts"
    expected: "Stats panel increments correctly: piece counts by type, line clear type counters after each clear"
    why_human: "Counter accuracy under real gameplay requires interactive inspection of side panel"
---

# Phase 3: Gameplay Feature Completeness Verification Report

**Phase Goal:** The assembly Tetris matches the yetris C++ feature set for in-game mechanics, and the first binary size comparison against the C++ baseline is recorded
**Verified:** 2026-02-26T22:30:00Z
**Status:** human_needed
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths (from ROADMAP.md Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Ghost piece shows exactly where current piece will land, updating in real-time | ? HUMAN | `_compute_ghost_y` exists (pure query, no stores), `_draw_ghost_piece` calls it, A_DIM attribute constructed via `movz w9, #0x10, lsl #16 / orr w1, w1, w9`; visual dimming requires human confirmation |
| 2 | Player can hold piece (swapping into hold slot), hold displays in panel; double-hold before lock rejected | ? HUMAN | `_hold_piece` implemented with `_can_hold` guard (cbz exits immediately if 0), `_lock_piece` resets `_can_hold=1`, `_draw_hold_panel` calls `Ldraw_mini_piece`; interactive swap timing requires human confirmation |
| 3 | Next 1+ pieces visible in preview; statistics panel shows piece counts and line clear counts | ? HUMAN | `_draw_next_panel` reads `_bag[_bag_index]` directly, `_draw_stats_panel` reads all 7 `_stats_piece_counts` entries and 4 line clear counters; visual correctness requires human confirmation |
| 4 | Player can pause (timer suspends, board obscured/frozen) and resume without losing state | ? HUMAN | `_is_paused` toggled in `Lcheck_p`, gravity skipped in `main.s` via `cbnz w8, Lskip_gravity`, `_draw_paused_overlay` shown in `_render_frame`; gravity burst absence requires human confirmation |
| 5 | Binary size of assembly version measured and recorded alongside C++ yetris binary size | VERIFIED | `MEASUREMENTS.md` exists with complete table: asm=53,688 bytes unstripped / 51,968 stripped; C++=1,036,152 / 546,448; segment analysis included for both |

**Score:** 1/5 truths fully verified automatically; 4/5 truths verified structurally but require human runtime confirmation

### Must-Have Truths (from PLAN frontmatter -- 03-01-PLAN.md)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Ghost piece shows where piece will land, updates on move/rotate | STRUCTURAL | `_compute_ghost_y` has zero store instructions (pure read); called by `_draw_ghost_piece` at line 481; wired into `_render_frame` before `_draw_piece` |
| 2 | Player can press 'c' to hold; held piece displays in side panel | STRUCTURAL | `Lcheck_c` in `input.s` (line 193), calls `_hold_piece`; `_draw_hold_panel` reads `_hold_piece_type` |
| 3 | Holding again before lock is rejected (can_hold flag resets on lock) | STRUCTURAL | `_hold_piece` checks `_can_hold` and returns immediately if 0; `_lock_piece` resets `_can_hold=1` at line 260-264 |
| 4 | Next piece visible in preview panel | STRUCTURAL | `_draw_next_panel` reads `_bag[_bag_index]` (lines 792-806); calls `Ldraw_mini_piece` (line 812) |
| 5 | Statistics panel shows per-piece-type counts and line clear type counts | STRUCTURAL | `_draw_stats_panel` iterates all 7 types reading `_stats_piece_counts`; shows Singles/Doubles/Triples/Tetris from `_stats_singles/doubles/triples/tetris` |
| 6 | Player can press 'p' to pause; gravity stops; only unpause/quit keys work | STRUCTURAL | Input gate at top of `_handle_input` blocks all keys except p/q/ESC when paused; `main.s` jumps over gravity check when `_is_paused != 0` |
| 7 | Unpausing resets gravity timer so no accumulated drops fire | STRUCTURAL | `Lcheck_p` calls `_get_time_ms` and stores result to `_last_drop_time` when unpausing (new value == 0) |

**Score:** 7/7 must-have truths structurally verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `asm/data.s` | 15 new state variables: hold_piece_type, can_hold, is_paused, stats_pieces, 7x stats_piece_counts, stats_singles/doubles/triples/tetris | VERIFIED | All 15 variables present at lines 455-489; `.globl` declarations confirmed; `_reset_board` zeroes all of them |
| `asm/piece.s` | `_compute_ghost_y` (pure query) and `_hold_piece` (swap mechanic) | VERIFIED | Both exported symbols confirmed in binary (`nm -g` shows `T _compute_ghost_y` at 0x1018, `T _hold_piece` at 0x107c); `_compute_ghost_y` has zero store instructions |
| `asm/board.s` | Stats counter increments in `_lock_piece` and `_clear_lines` | VERIFIED | `_lock_piece` increments `_stats_pieces` (line 246), `_stats_piece_counts[type]` (line 256), resets `_can_hold=1` (line 263); `_clear_lines` increments appropriate line counter via cmp+b.ne chain |
| `asm/input.s` | Key handlers for 'c' (hold) and 'p' (pause toggle) | VERIFIED | `Lcheck_c` at line 193 dispatches to `_hold_piece`; `Lcheck_p` at line 204 toggles `_is_paused` and resets gravity timer; pause gate at top of `_handle_input` |
| `asm/main.s` | Pause gate in game loop, ghost/hold rendering calls, can_hold reset | VERIFIED | Pause check at lines 102-104 (`cbnz w8, Lskip_gravity`); `_render_frame` handles all rendering including ghost/hold |
| `asm/render.s` | `_draw_ghost_piece`, `_draw_hold_panel`, `_draw_next_panel`, `_draw_stats_panel`, `_draw_paused_overlay` | VERIFIED | All 5 exported symbols confirmed in binary; `_render_frame` calls all of them in correct order; score panel at col 34 (confirmed) |
| `.planning/phases/03-gameplay-feature-completeness/MEASUREMENTS.md` | Binary size comparison table: assembly vs C++ | VERIFIED | File exists; contains actual measured values for both binaries (unstripped, stripped, segment analysis, growth from Phase 2) |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `piece.s:_compute_ghost_y` | `board.s:_is_piece_valid` | `bl` call in drop loop | VERIFIED | `bl _is_piece_valid` confirmed inside `_compute_ghost_y` body; no store instructions in function body |
| `piece.s:_hold_piece` | `data.s:_hold_piece_type` | adrp+add read/write | VERIFIED | Lines 577-582: loads `_hold_piece_type`, stores current type into it |
| `render.s:_draw_ghost_piece` | `piece.s:_compute_ghost_y` | `bl` call to get ghost y | VERIFIED | `bl _compute_ghost_y` at line 481 of render.s; result stored in w23 as ghost_y |
| `main.s` | `data.s:_is_paused` | pause gate check in game loop | VERIFIED | Lines 102-104 of main.s: `ldrb w8, [x8, _is_paused@PAGEOFF]` then `cbnz w8, Lskip_gravity` |
| `board.s:_lock_piece` | `data.s:_stats_piece_counts` | counter increment | VERIFIED | Lines 253-258: `adrp`+`add` to `_stats_piece_counts`, `ldr w10, [x8, x9, lsl #2]`, `add w10, w10, #1`, `str w10` |
| `MEASUREMENTS.md` | `asm/bin/yetris-asm` | wc -c output recorded | VERIFIED | File reports 53,688 bytes; `wc -c` confirms same value currently |
| `MEASUREMENTS.md` | `bin/yetris` | C++ binary comparison | VERIFIED | MEASUREMENTS.md contains C++ segment details section with actual values |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| MECH-09 | 03-01-PLAN.md | Next piece preview (1-7 configurable) | SATISFIED | `_draw_next_panel` reads `_bag[_bag_index]`; shows 1-piece preview from 7-bag |
| MECH-10 | 03-01-PLAN.md | Hold piece mechanic (one slot, can't re-hold until lock) | SATISFIED | `_hold_piece` with `_can_hold` guard; `_lock_piece` resets `_can_hold`; `_draw_hold_panel` renders slot |
| MECH-11 | 03-01-PLAN.md | Ghost piece (landing preview) | SATISFIED | `_compute_ghost_y` (pure query) + `_draw_ghost_piece` with A_DIM; wired into `_render_frame` |
| MECH-13 | 03-01-PLAN.md | Pause and resume with timer suspension | SATISFIED | `_is_paused` flag; input gate blocks keys; main.s skips gravity; gravity timer reset on unpause |
| REND-04 | 03-01-PLAN.md | Piece statistics panel (count per type + singles/doubles/triples/tetris) | SATISFIED | `_draw_stats_panel` shows all 7 type counts (colored) + 4 line clear type counts; both `_stats_piece_counts` and `_stats_singles/doubles/triples/tetris` wired |
| MEAS-01 | 03-02-PLAN.md | Binary size tracked at each development stage vs C++ yetris baseline | SATISFIED | `MEASUREMENTS.md` records Phase 3 binary sizes (53,688 asm vs 1,036,152 C++), growth from Phase 2, segment analysis |

**All 6 required requirements satisfied.**

**Orphaned requirements check:** REQUIREMENTS.md maps MECH-09, MECH-10, MECH-11, MECH-13, REND-04, MEAS-01 to Phase 3. All 6 are claimed in plan frontmatter. No orphaned requirements.

### Anti-Patterns Found

| File | Pattern | Severity | Impact |
|------|---------|----------|--------|
| None found | — | — | — |

No TODO/FIXME/placeholder comments found in any of the 6 modified assembly files. No empty handlers, static returns, or stub implementations detected. All functions have substantive implementations.

**Note on ROADMAP.md metadata:** The ROADMAP still shows Phase 3 plans as `[ ]` (unchecked) despite both plans being executed and committed. This is a documentation gap but does not affect code correctness. It does not block phase goal achievement.

### Human Verification Required

#### 1. Ghost Piece Visual Dimming

**Test:** Run `make asm-run`. Observe the ghost piece below the active piece. Move the active piece left/right and rotate it.
**Expected:** A visually dimmed (fainter) version of the active piece appears at its landing position. The ghost updates in real-time as the active piece moves and rotates.
**Why human:** The A_DIM attribute (0x100000) is constructed correctly in code (`movz w9, #0x10, lsl #16`), but whether the terminal renders it as visually distinct from the bright active piece requires runtime observation.

#### 2. Hold Mechanic Swap and Rejection

**Test:** Run `make asm-run`. Press 'c' to hold the first piece. Press 'c' again to swap. Before the swapped piece locks, press 'c' a third time.
**Expected:** First 'c' stores current piece in Hold panel, new piece spawns. Second 'c' swaps hold and active piece. Third 'c' (before lock) is silently rejected -- no swap happens.
**Why human:** The `_can_hold` guard logic is structurally correct, but the reject-before-lock edge case (must fire before `_lock_piece` resets `_can_hold=1`) requires timing-sensitive interactive confirmation.

#### 3. Pause and Resume Without Gravity Burst

**Test:** Run `make asm-run`. Let a piece fall partway. Press 'p' to pause. Wait several seconds. Press 'p' to resume.
**Expected:** During pause, piece stays frozen and all movement keys are blocked (only 'p', 'q', ESC work). On resume, the piece continues falling at normal speed without immediately dropping due to accumulated gravity timer.
**Why human:** The gravity timer reset (writing `_get_time_ms()` result to `_last_drop_time` on unpause) is structurally correct, but the absence of a gravity burst on resume requires runtime observation.

#### 4. Statistics Panel Accuracy

**Test:** Run `make asm-run`. Lock several pieces of different types. Clear lines (singles, doubles if possible). Observe the Stats panel.
**Expected:** Per-piece-type counts in the Stats panel increment when pieces lock. Line clear type counters (Single/Double/Triple/Tetris) increment correctly after each clear.
**Why human:** The increment wiring is structurally verified (`_lock_piece` -> `_stats_piece_counts`, `_clear_lines` -> `_stats_singles/doubles/triples/tetris`), but display accuracy of the side panel requires visual inspection.

### Gaps Summary

No structural gaps found. All 6 requirements are satisfied by substantive, wired implementations. All artifacts exist at all three levels (exists, substantive, wired).

Four items are flagged for human verification because they involve visual rendering behavior (A_DIM attribute appearance), real-time input response (pause gate effectiveness under actual key events), and timer accuracy (gravity burst absence on resume). These cannot be verified programmatically.

The ROADMAP.md status markers for Phase 3 plans remain as `[ ]` unchecked -- this is a metadata inconsistency that does not affect the implementation. The code is complete, compiled, and committed.

---
_Verified: 2026-02-26T22:30:00Z_
_Verifier: Claude (gsd-verifier)_
