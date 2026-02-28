---
phase: 08-modern-scoring-engine
plan: 02
subsystem: scoring
tags: [arm64, assembly, tetris-guideline, t-spin, hard-drop, soft-drop, back-to-back]

# Dependency graph
requires:
  - phase: 08-modern-scoring-engine
    plan: 01
    provides: "Scoring pipeline in _lock_piece, _score_table, _combo_count, _b2b_active, _perfect_clear_table"
  - phase: 02-core-game
    provides: "_lock_piece, _clear_lines, _try_move, _try_rotate, _hard_drop, _soft_drop"
provides:
  - "3-corner T-spin detection at lock time (_is_tspin flag)"
  - "T-spin scoring (zero=400*lvl, single=800*lvl, double=1200*lvl, triple=1600*lvl)"
  - "T-spin line clears count as difficult for B2B 1.5x bonus"
  - "Hard drop scoring: 2 points per cell dropped"
  - "User soft drop scoring: 1 point per cell dropped (gravity excluded)"
  - "_last_was_rotation flag tracking for T-spin detection"
  - "_user_soft_drop function separating user input from gravity drops"
affects: [11-hi-score-system]

# Tech tracking
tech-stack:
  added: []
  patterns: ["Inline 4-corner bounds-check with out-of-bounds-as-occupied for T-spin detection", "Wrapper function pattern (_user_soft_drop wrapping _try_move) for input-specific scoring"]

key-files:
  created: []
  modified: ["asm/data.s", "asm/piece.s", "asm/input.s", "asm/board.s"]

key-decisions:
  - "T-spin zero awards points but does NOT contribute to combo or B2B"
  - "Hard drop clears _last_was_rotation to prevent false T-spin after hard drop"
  - "_user_soft_drop uses _try_move + score increment rather than wrapping _soft_drop to keep gravity path clean"
  - "Fully inlined corner checks (no bl calls) to avoid clobbering x30 inside _lock_piece"

patterns-established:
  - "T-spin detection at lock time: piece_type==6 AND _last_was_rotation==1 AND 3+ diagonal corners occupied"
  - "Separate user-input vs gravity drop paths for scoring correctness"

requirements-completed: [SCORE-04, SCORE-05, SCORE-07, SCORE-08]

# Metrics
duration: 4min
completed: 2026-02-27
---

# Phase 8 Plan 02: T-Spin Detection, T-Spin Scoring, and Drop Point Awards Summary

**3-corner T-spin detection with scoring table lookup, hard drop 2pt/cell, and user-only soft drop 1pt/cell in ARM64 assembly**

## Performance

- **Duration:** 4 min
- **Started:** 2026-02-27T15:45:32Z
- **Completed:** 2026-02-27T15:49:33Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Added T-spin detection using the 3-corner rule: checks 4 diagonal corners around T-piece pivot after rotation, out-of-bounds corners count as occupied
- T-spin scoring integrates with existing pipeline: T-spin zero (400*level) awards points without combo/B2B; T-spin line clears use dedicated score table and count as difficult for B2B
- Hard drop awards 2 points per cell dropped (computed from starting vs final Y position)
- User soft drop awards 1 point per cell via _user_soft_drop wrapper; gravity drops through _soft_drop award nothing

## Task Commits

Each task was committed atomically:

1. **Task 1: Add T-spin data, rotation flag, and _user_soft_drop** - `2808242` (feat)
2. **Task 2: Add T-spin detection and T-spin scoring to _lock_piece** - `5326862` (feat)

## Files Created/Modified
- `asm/data.s` - Added _tspin_score_table (400/800/1200/1600), _last_was_rotation (.byte 0), _is_tspin (.byte 0)
- `asm/piece.s` - Set _last_was_rotation=1 on rotation success (basic+kick), clear on _try_move success, hard drop scoring (2pt/cell) with _last_was_rotation clear, expanded _hard_drop stack frame to 64 bytes
- `asm/input.s` - Added _user_soft_drop function (1pt/cell wrapper), wired KEY_DOWN to _user_soft_drop instead of _soft_drop
- `asm/board.s` - Added 3-corner T-spin detection before _clear_lines, T-spin zero scoring (400*level), T-spin line clear scoring via _tspin_score_table, updated is_difficult for B2B to include T-spin, zeroed new flags in _reset_board

## Decisions Made
- T-spin zero awards 400*level but does NOT contribute to combo counter or B2B chain (matches modern guideline behavior where T-spin zero is a bonus but not a "clear")
- Hard drop clears _last_was_rotation before calling _lock_piece to prevent false T-spin detection (hard drop is not a rotation)
- _user_soft_drop calls _try_move(0,1) directly and handles lock+spawn itself, rather than wrapping _soft_drop, to keep the gravity code path completely separate from user-input scoring
- All T-spin corner checks are fully inlined (no bl calls) to avoid clobbering x30 link register inside the _lock_piece function body

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 8 (Modern Scoring Engine) is now complete: all 8 scoring requirements implemented
- Complete scoring system: level-multiplied line clears, combo, B2B, perfect clear, T-spin detection+scoring, soft/hard drop points
- Ready for Phase 9 (Line Clear Animation) which depends on the mark/execute split already in place

## Self-Check: PASSED

All files exist, all commits verified.

---
*Phase: 08-modern-scoring-engine*
*Completed: 2026-02-27*
