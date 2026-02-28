---
phase: 12-code-cleanup
plan: 01
subsystem: asm
tags: [arm64, dead-code-removal, assembly, neon, globl-cleanup]

# Dependency graph
requires:
  - phase: 09-line-clear-animation
    provides: "_mark_lines + _clear_marked_lines pipeline that superseded _clear_lines"
provides:
  - "board.s without dead _clear_lines function (182 lines removed)"
  - "data.s without orphaned string literals (4 removed)"
  - "Reduced exported symbol count via .globl cleanup for table-only strings"
affects: [13-size-optimization, 14-writeup]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Table-only string labels kept local (no .globl) when accessed only via pointer tables in same file"

key-files:
  created: []
  modified:
    - "asm/board.s"
    - "asm/data.s"

key-decisions:
  - "Removed .globl for 28 table-only string labels while keeping labels for intra-file .quad references"
  - "Confirmed _neon_row_mask still referenced by _mark_lines before removing _clear_lines"

patterns-established:
  - "Audit .globl visibility: strings accessed only via pointer tables in the same file should not be exported"

requirements-completed: [CLEAN-01, CLEAN-02, CLEAN-03]

# Metrics
duration: 5min
completed: 2026-02-27
---

# Phase 12 Plan 01: Dead Code and Orphaned Data Removal Summary

**Removed 182-line dead _clear_lines function from board.s and 4 orphaned string literals from data.s, plus .globl cleanup for 28 table-only labels**

## Performance

- **Duration:** 5 min
- **Started:** 2026-02-27T20:22:31Z
- **Completed:** 2026-02-27T20:27:48Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Deleted entire `_clear_lines` function (182 lines of dead code) superseded by `_mark_lines` + `_clear_marked_lines` pipeline
- Removed 4 orphaned string literals from data.s: `_str_colon`, `_str_paused_msg`, `_str_press_p_resume`, `_str_title`
- Removed `.globl` directives for 28 table-only string labels (logo lines, help lines, menu items, settings labels) -- labels retained for intra-file `.quad` references
- Updated all stale comments referencing `_clear_lines` to reference `_mark_lines`

## Task Commits

Each task was committed atomically:

1. **Task 1: Remove dead _clear_lines function and update board.s** - `c5feb72` (refactor)
2. **Task 2: Remove orphaned data strings and audit .globl symbols** - `0e4108e` (refactor)

## Files Created/Modified
- `asm/board.s` - Removed _clear_lines function, updated header and comments to reference _mark_lines pipeline
- `asm/data.s` - Removed 4 orphaned strings, updated _neon_row_mask comment, removed .globl for 28 table-only labels

## Decisions Made
- Removed `.globl` for 28 table-only string labels while keeping the labels themselves -- the linker resolves intra-file `.quad` references without `.globl` since all labels are in the same translation unit
- Confirmed `_neon_row_mask` is still used by `_mark_lines` (lines 633-634 in updated board.s) before removing `_clear_lines` which also referenced it
- Left stale header comments in render.s and menu.s (referencing removed strings like `_str_colon`, `_str_title`) out of scope -- these are documentation comments listing data dependencies, not code

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- board.s and data.s are cleaner with no dead code or orphaned data
- Binary builds and links cleanly
- Ready for plan 02 (render.s dead code removal) or phase 13 (size optimization)

## Self-Check: PASSED

- asm/board.s: FOUND
- asm/data.s: FOUND
- 12-01-SUMMARY.md: FOUND
- Commit c5feb72: FOUND
- Commit 0e4108e: FOUND

---
*Phase: 12-code-cleanup*
*Completed: 2026-02-27*
