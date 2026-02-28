---
phase: 08-modern-scoring-engine
verified: 2026-02-27T17:00:00Z
status: passed
score: 11/11 must-haves verified
re_verification: false
gaps: []
human_verification:
  - test: "Play a full game to end, awarding single/double/triple/Tetris line clears at various levels"
    expected: "Score increments by exactly 100*level, 300*level, 500*level, and 800*level respectively for each clear type"
    why_human: "Cannot run the terminal application in this environment; score arithmetic is verified by code inspection but runtime accumulation needs manual play"
  - test: "Clear lines consecutively (combo): watch score panel after each clear"
    expected: "Each consecutive clearing lock adds 50*combo_count*level bonus on top of the base line clear score; score resets combo bonus after a non-clearing lock"
    why_human: "Combo accumulation across real gameplay locks requires interactive testing"
  - test: "Land two Tetris clears in a row"
    expected: "Second Tetris line clear awards 1200 points at level 1 (800 * 1.5 B2B bonus)"
    why_human: "Runtime behavior of B2B flag across two consecutive lock events needs interactive confirmation"
  - test: "Place a T-piece after a rotation into a T-slot with 3+ corners blocked"
    expected: "Score jumps by 800*level for T-spin single, 1200*level for double, 1600*level for triple; 400*level for T-spin zero (no lines cleared)"
    why_human: "T-spin detection path in real board state needs interactive verification"
  - test: "Press the Down arrow key while a piece is falling"
    expected: "Score increases by exactly 1 per cell dropped; gravity-driven drops (no key press) do NOT increase score"
    why_human: "Distinction between user-input path (_user_soft_drop) and gravity path (_soft_drop) requires runtime observation"
  - test: "Hard-drop a piece from spawn position"
    expected: "Score increases by (number of rows dropped) * 2 before any line-clear bonus is applied"
    why_human: "Hard drop row-distance calculation requires observing actual piece spawn height vs landing position"
  - test: "Clear all blocks from the board (perfect clear)"
    expected: "After the perfect clear line clear, an additional bonus of 800/1200/1800/2000*level is added depending on lines cleared"
    why_human: "Perfect clear is rare; board-empty scan result needs runtime confirmation"
---

# Phase 8: Modern Scoring Engine Verification Report

**Phase Goal:** Scoring matches modern Tetris guideline with combos, T-spins, and all bonus systems
**Verified:** 2026-02-27T17:00:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #  | Truth | Status | Evidence |
|----|-------|--------|---------|
| 1  | Line clears award level-multiplied points (Single=100*lvl, Double=300*lvl, Triple=500*lvl, Tetris=800*lvl) | VERIFIED | `board.s` line 431-435: `_score_table` indexed by `lines-1`, result multiplied by `_level` at `Lbase_score_done` |
| 2  | Consecutive line-clearing locks accumulate combo counter adding 50*combo*level bonus; counter resets on non-clearing lock | VERIFIED | `board.s` lines 498-515: `_combo_count` incremented before bonus, `50 * combo_count * level` added to `_score`; lines 419-422: `_combo_count` stored as zero when `lines_cleared == 0` |
| 3  | Consecutive difficult clears (Tetris or T-spin) receive 1.5x back-to-back bonus; non-difficult line clear breaks the chain; locks with 0 lines do not break it | VERIFIED | `board.s` lines 451-489: `is_difficult = (lines==4 OR is_tspin)`, B2B active flag read/written; `Lb2b_not_difficult` only reached when `lines > 0` and non-difficult, zeroing `_b2b_active`; zero-line path skips B2B logic entirely |
| 4  | Clearing all blocks from the board triggers a perfect clear bonus (800/1200/1800/2000 * level by lines cleared) | VERIFIED | `board.s` lines 517-544: 200-byte scalar OR-loop scan; on empty board, `_perfect_clear_table[lines-1] * level` added to `_score` |
| 5  | Flat +10 lock bonus is removed (modern guideline compliance) | VERIFIED | No `+10` or `#10` addition to `_score` exists anywhere in `_lock_piece`; `_clear_lines` (`board.s` lines 681-756) contains no score writes at all |
| 6  | T-piece placement after rotation with 3+ diagonal corners occupied is detected as a T-spin | VERIFIED | `board.s` lines 260-383: T-spin detection block checks `piece_type==6`, `_last_was_rotation==1`, then counts all 4 diagonal corners (out-of-bounds as occupied), sets `_is_tspin=1` when count >= 3 |
| 7  | T-spin awards T-spin scoring values (zero=400*lvl, single=800*lvl, double=1200*lvl, triple=1600*lvl) | VERIFIED | `board.s` lines 400-415: T-spin zero path loads `_tspin_score_table[0]` (400) * level; lines 437-442: T-spin with lines uses `_tspin_score_table[lines]` (800/1200/1600) * level |
| 8  | T-spin line clears count as difficult for back-to-back bonus (1.5x) | VERIFIED | `board.s` lines 454-459: `is_difficult` check: after Tetris branch, loads `_is_tspin`; non-zero sets `w12=1` (difficult) |
| 9  | Soft drop awards 1 point per cell dropped (user-initiated only, not gravity) | VERIFIED | `input.s` lines 104-136: `_user_soft_drop` calls `_try_move(0,1)`, on success adds 1 to `_score`; `_handle_input` line 275: KEY_DOWN dispatches to `_user_soft_drop`; gravity path calls `_soft_drop` in `piece.s` which never touches `_score` |
| 10 | Hard drop awards 2 points per cell dropped | VERIFIED | `piece.s` lines 362-368: `(final_y - start_y) << 1` added to `_score` before `bl _lock_piece`; starting y saved in `w23` at line 339 |
| 11 | `_last_was_rotation` flag is cleared on any non-rotation move (left, right, down, hard drop) | VERIFIED | `piece.s` lines 88-90: cleared in `_try_move` success path; lines 370-372: cleared before `_lock_piece` in `_hard_drop`; set to 1 on both `Lrotate_accept_basic` (line 239) and `Lrotate_accept_kick` (line 283) |

**Score:** 11/11 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `asm/data.s` | New scoring state variables and score tables | VERIFIED | Contains `_perfect_clear_table` (.word 800,1200,1800,2000 lines 342-343), `_tspin_score_table` (.word 400,800,1200,1600 lines 353-354), `_combo_count` (.word 0 line 709), `_b2b_active` (.byte 0 line 712), `_last_was_rotation` (.byte 0 line 715), `_is_tspin` (.byte 0 line 718) |
| `asm/board.s` | Restructured `_lock_piece` with scoring pipeline, simplified `_clear_lines`, `_reset_board` with new vars | VERIFIED | `_lock_piece` has full T-spin detection + scoring pipeline (lines 260-548); `_clear_lines` has no score writes (confirmed by absence of `_score` references); `_reset_board` zeros `_combo_count`, `_b2b_active`, `_last_was_rotation`, `_is_tspin` (lines 858-874) |
| `asm/piece.s` | Rotation flag setting; `_last_was_rotation` cleared on move/drop; hard drop scoring | VERIFIED | `_try_rotate` sets flag on both accept paths (lines 239, 283); `_try_move` clears flag on success (line 90); `_hard_drop` computes and awards 2pt/cell, clears flag (lines 339, 362-372) |
| `asm/input.s` | `_user_soft_drop` wrapper; KEY_DOWN dispatches to it | VERIFIED | `_user_soft_drop` defined at line 104-136 with 1pt/cell scoring; `_handle_input` dispatches KEY_DOWN to `_user_soft_drop` at line 275 |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `board.s (_lock_piece)` | `data.s (_combo_count, _b2b_active)` | adrp+add load/store | WIRED | `_combo_count` loaded at line 501, stored at 503; `_b2b_active` loaded at line 468, stored at 479/487 |
| `board.s (_lock_piece)` | `data.s (_score_table, _perfect_clear_table)` | indexed table lookup | WIRED | `_score_table` at line 431-434; `_perfect_clear_table` at line 532-535 |
| `board.s (_reset_board)` | `data.s (_combo_count, _b2b_active)` | zero on game reset | WIRED | `_combo_count` zeroed at line 860-861; `_b2b_active` zeroed at line 865-866 |
| `piece.s (_try_rotate)` | `data.s (_last_was_rotation)` | set flag to 1 on successful rotation | WIRED | Set at `Lrotate_accept_basic` (line 239) and `Lrotate_accept_kick` (line 283) |
| `piece.s (_try_move)` | `data.s (_last_was_rotation)` | clear flag to 0 on successful move | WIRED | Cleared via `strb wzr` at line 90 |
| `board.s (_lock_piece)` | `data.s (_last_was_rotation, _is_tspin, _tspin_score_table)` | T-spin detection and scoring at lock time | WIRED | All three read in T-spin detection block (lines 264-442); `_tspin_score_table` used at lines 405-415, 441-442 |
| `input.s (_handle_input)` | `input.s (_user_soft_drop)` | KEY_DOWN dispatches to `_user_soft_drop` | WIRED | Line 275: `bl _user_soft_drop` in `Lcheck_down` block |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|---------|
| SCORE-01 | 08-01 | Line clear scores multiplied by level | SATISFIED | `_score_table[lines-1] * _level` in `_lock_piece` scoring pipeline |
| SCORE-02 | 08-01 | Combo system — 50*combo_count*level for consecutive clearing locks | SATISFIED | `_combo_count` incremented before bonus, `50 * combo * level` applied |
| SCORE-03 | 08-01 | Back-to-back bonus — 1.5x for consecutive difficult clears | SATISFIED | `_b2b_active` flag + `score += score >> 1` for B2B path |
| SCORE-04 | 08-02 | T-spin detection using 3-corner rule | SATISFIED | 4-corner check inline code, `_is_tspin` set when count >= 3 |
| SCORE-05 | 08-02 | T-spin scoring values (zero=400*lvl, single=800*lvl, double=1200*lvl, triple=1600*lvl) | SATISFIED | `_tspin_score_table` (400,800,1200,1600) with correct index selection |
| SCORE-06 | 08-01 | Perfect clear detection and bonus scoring | SATISFIED | 200-byte OR scan, `_perfect_clear_table[lines-1] * level` bonus |
| SCORE-07 | 08-02 | Soft drop scoring — 1 point per cell dropped | SATISFIED | `_user_soft_drop` awards `+1` to `_score` per successful `_try_move` |
| SCORE-08 | 08-02 | Hard drop scoring — 2 points per cell dropped | SATISFIED | `(final_y - start_y) << 1` added to `_score` in `_hard_drop` before lock |

**Requirements coverage:** 8/8 — all SCORE-01 through SCORE-08 satisfied. No orphaned requirements.

### Anti-Patterns Found

No anti-patterns detected. Grep of all four modified files (`asm/data.s`, `asm/board.s`, `asm/piece.s`, `asm/input.s`) found zero instances of TODO, FIXME, XXX, HACK, PLACEHOLDER, empty returns, or stub implementations.

### Human Verification Required

The build compiles cleanly (`make asm` exits with "Assembly build successful!"). The code logic is fully verified by inspection. The following items require interactive gameplay to confirm runtime behavior:

#### 1. Level-multiplied line clear scoring at runtime

**Test:** Clear one line at level 1; then clear a Tetris at level 2
**Expected:** Score shows 100 after single at level 1; score increases by 1600 (800*2) after Tetris at level 2
**Why human:** Cannot run the ncurses application in this environment

#### 2. Combo accumulation over multiple locks

**Test:** Clear lines on three consecutive locks at level 1
**Expected:** Lock 1: base + 50*1*1 = base + 50; Lock 2: base + 50*2*1 = base + 100; Lock 3: base + 50*3*1 = base + 150
**Why human:** Multi-lock sequence requires interactive gameplay

#### 3. Back-to-back Tetris bonus

**Test:** Clear a Tetris, then clear another Tetris immediately
**Expected:** Second Tetris awards 1200 points (800 * 1.5) at level 1
**Why human:** B2B state across two separate lock events needs runtime confirmation

#### 4. T-spin detection in real play

**Test:** Rotate T-piece into a tight slot with 3+ corner cells blocked
**Expected:** Score jumps by T-spin scoring table values (800+/level for single line clear)
**Why human:** T-spin 3-corner condition depends on real board state

#### 5. User soft drop vs gravity distinction

**Test:** Watch score during auto-gravity drop vs pressing Down arrow
**Expected:** Down-arrow adds 1 per row; gravity drops add 0
**Why human:** Requires observing the two code paths in real time

#### 6. Hard drop distance scoring

**Test:** Hard-drop a piece from spawn height (approx 17 rows above landing)
**Expected:** Score increases by approximately 30-34 before line-clear bonus
**Why human:** Actual spawn-to-landing distance depends on board state

#### 7. Perfect clear bonus

**Test:** Arrange board so one clear empties it entirely
**Expected:** After clearing N lines, score gets an extra 800/1200/1800/2000*level bonus
**Why human:** Perfect clear is difficult to set up without automated board control

### Gaps Summary

No gaps found. All 11 observable truths are verified by code inspection, all 4 artifacts pass all three levels (exists, substantive, wired), all 7 key links are confirmed wired, and all 8 requirements are satisfied with concrete implementation evidence. The build succeeds cleanly. Seven human verification items are identified as expected for a terminal game — they verify runtime behavior, not code correctness.

---

_Verified: 2026-02-27T17:00:00Z_
_Verifier: Claude (gsd-verifier)_
