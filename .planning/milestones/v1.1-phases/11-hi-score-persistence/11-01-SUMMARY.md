---
phase: 11-hi-score-persistence
plan: 01
subsystem: game-state
tags: [file-io, syscall, darwin-arm64, hiscore, persistence, svc]

# Dependency graph
requires:
  - phase: 08-modern-scoring-engine
    provides: _score global word and scoring pipeline in board.s
  - phase: 06-subwindow-foundation
    provides: _win_score WINDOW* and _draw_score_panel in render.s
provides:
  - _load_hiscore and _save_hiscore functions via Darwin syscalls
  - _hiscore global word persisted to ~/.yetris-hiscore
  - Live hi-score tracking during gameplay via csel in board.s
  - Conditional hi-score display in score panel (numeric or "(none)")
affects: []

# Tech tracking
tech-stack:
  added: [Darwin svc #0x80 file I/O (open/read/write/close), _getenv for HOME resolution]
  patterns: [stack-based path construction with getenv + suffix concatenation, carry-flag error checking for syscalls]

key-files:
  created: [asm/hiscore.s]
  modified: [asm/data.s, asm/main.s, asm/render.s, asm/board.s]

key-decisions:
  - "Raw 4-byte binary file format (little-endian uint32) instead of ASCII/text"
  - "Stack-based path buffer (256 bytes) instead of persistent .data allocation"
  - "Live hiscore update via csel in scoring pipeline, not just at game over"

patterns-established:
  - "Syscall file I/O: stp frame + sub sp #256 for path buffer + getenv + byte-copy + svc pattern"
  - "Carry-flag error bail: b.cs to skip-label for graceful syscall failure handling"

requirements-completed: [HISCORE-01, HISCORE-02, HISCORE-03]

# Metrics
duration: 3min
completed: 2026-02-27
---

# Phase 11 Plan 01: Hi-Score Persistence Summary

**File-based hi-score persistence using Darwin ARM64 syscalls with live score tracking and conditional panel display**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-27T18:56:31Z
- **Completed:** 2026-02-27T18:59:16Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Created asm/hiscore.s with _load_hiscore and _save_hiscore using raw Darwin syscalls (open/read/write/close via svc #0x80)
- Added _hiscore global word, _str_home_env and _str_hiscore_suffix string constants to data.s
- Wired load at startup (after _anim_select_random) and conditional save at game over (only when score > hiscore)
- Replaced unconditional "(none)" display with conditional logic: numeric value when hiscore > 0, "(none)" when 0
- Added live hiscore update via csel at Lscore_done in board.s for real-time panel tracking

## Task Commits

Each task was committed atomically:

1. **Task 1: Create hiscore.s with load/save functions and add data variables** - `7695636` (feat)
2. **Task 2: Wire hiscore load/save into main.s, update score panel display in render.s, add live tracking in board.s** - `5eee521` (feat)

## Files Created/Modified
- `asm/hiscore.s` - New file: _load_hiscore and _save_hiscore with Darwin syscall file I/O
- `asm/data.s` - Added _hiscore (.word 0), _str_home_env ("HOME"), _str_hiscore_suffix ("/.yetris-hiscore")
- `asm/main.s` - bl _load_hiscore at startup; score vs hiscore comparison + bl _save_hiscore at game over
- `asm/render.s` - Conditional hi-score display: numeric via Ldraw_number when > 0, "(none)" via _waddstr when 0
- `asm/board.s` - Live _hiscore = max(_score, _hiscore) via csel at Lscore_done

## Decisions Made
- Used raw 4-byte binary format (little-endian uint32) for simplicity -- no text parsing needed
- Path buffer allocated on stack (256 bytes, transient) rather than persistent .data allocation
- Live hiscore update placed in scoring pipeline (board.s Lscore_done) so display stays current during gameplay
- Unsigned comparison (b.ls) at game over ensures 0 score never "beats" 0 hiscore

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Hi-score persistence completes the final v1.1 requirement
- All HISCORE-01, HISCORE-02, HISCORE-03 requirements satisfied
- No further phases planned

## Self-Check: PASSED

- asm/hiscore.s: FOUND
- 11-01-SUMMARY.md: FOUND
- Commit 7695636: FOUND
- Commit 5eee521: FOUND

---
*Phase: 11-hi-score-persistence*
*Completed: 2026-02-27*
