---
phase: 08-modern-scoring-engine
plan: 01
subsystem: scoring
tags: [arm64, assembly, tetris-guideline, scoring, combo, back-to-back, perfect-clear]

# Dependency graph
requires:
  - phase: 02-core-game
    provides: "_lock_piece, _clear_lines, _reset_board functions and _score_table"
provides:
  - "Level-multiplied line clear scoring (Single=100*lvl, Double=300*lvl, Triple=500*lvl, Tetris=800*lvl)"
  - "Combo tracking and scoring (50 * combo_count * level for consecutive line-clearing locks)"
  - "Back-to-back difficult clear bonus (1.5x for consecutive Tetris; Plan 08-02 extends to T-spins)"
  - "Perfect clear detection and bonus scoring (800/1200/1800/2000 * level)"
  - "_combo_count and _b2b_active state variables for scoring engine"
  - "Scoring centralized in _lock_piece (removed from _clear_lines)"
affects: [08-modern-scoring-engine, 11-hi-score-system]

# Tech tracking
tech-stack:
  added: []
  patterns: ["Centralized scoring pipeline in _lock_piece after _clear_lines returns", "Scalar board-empty scan for perfect clear detection (200-byte OR loop)"]

key-files:
  created: []
  modified: ["asm/data.s", "asm/board.s"]

key-decisions:
  - "Removed flat +10 lock bonus for modern guideline compliance"
  - "Combo counter starts at 0, increments BEFORE computing bonus: first consecutive clear gets combo=1 (50*1*level bonus)"
  - "Scalar loop for perfect clear board scan instead of NEON (simpler, rare event)"
  - "B2B only tracks Tetris as difficult for now; Plan 08-02 adds T-spin"

patterns-established:
  - "Scoring pipeline: base*level -> b2b check -> add to _score -> combo increment+bonus -> perfect clear check"
  - "All score computation in _lock_piece; _clear_lines only detects/removes rows and updates lines/level/stats"

requirements-completed: [SCORE-01, SCORE-02, SCORE-03, SCORE-06]

# Metrics
duration: 3min
completed: 2026-02-27
---

# Phase 8 Plan 01: Modern Scoring Engine Summary

**Level-multiplied line clear scoring with combo tracking, back-to-back 1.5x bonus, and perfect clear detection in ARM64 assembly**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-27T15:39:18Z
- **Completed:** 2026-02-27T15:43:09Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Restructured scoring from flat values to level-multiplied modern guideline scoring
- Added combo system: consecutive line-clearing locks accumulate bonus (50 * combo * level)
- Added back-to-back tracking: consecutive Tetris clears receive 1.5x base score bonus
- Added perfect clear detection: scanning 200-byte board after line clear with bonus scoring
- Removed non-standard flat +10 lock bonus for guideline compliance

## Task Commits

Each task was committed atomically:

1. **Task 1: Add scoring state variables and tables to data.s** - `c462171` (feat)
2. **Task 2: Restructure _lock_piece, simplify _clear_lines, update _reset_board** - `0ec6ac5` (feat)

## Files Created/Modified
- `asm/data.s` - Added _perfect_clear_table (800/1200/1800/2000), _combo_count (.word 0), _b2b_active (.byte 0)
- `asm/board.s` - Removed score from _clear_lines, removed +10 lock bonus, added full scoring pipeline in _lock_piece, zeroed new vars in _reset_board

## Decisions Made
- Removed flat +10 lock bonus: modern guideline does not include lock bonus; points come only from line clears, combos, T-spins, and drops
- Combo starts at 0, increments before bonus computation: first clear in chain gets combo=1 giving 50*1*level bonus. This matches the plan specification where the first consecutive clear awards a combo bonus
- Used scalar byte-by-byte loop for perfect clear detection instead of NEON: simpler code, perfect clears are extremely rare, performance difference negligible
- B2B flag only considers Tetris (lines==4) as "difficult" for now; Plan 08-02 will extend this to include T-spins

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Scoring engine foundation complete; Plan 08-02 can add T-spin detection and drop scoring on top
- _b2b_active and combo tracking are ready for T-spin integration (just add `|| _is_tspin` to the `is_difficult` check)
- _clear_lines is now cleanly separated from scoring; only returns line count

---
*Phase: 08-modern-scoring-engine*
*Completed: 2026-02-27*
