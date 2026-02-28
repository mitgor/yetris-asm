---
phase: 13-binary-size-analysis
plan: 01
subsystem: research
tags: [mach-o, binary-analysis, arm64, size-optimization]

# Dependency graph
requires:
  - phase: 12-code-cleanup
    provides: cleaned post-v1.2 binary for measurement
provides:
  - Complete Mach-O section breakdown with byte counts
  - Per-file code contribution table for all 12 assembly source files
  - Binary growth analysis (v1.0 vs post-v1.2)
  - Symbol analysis and stripped binary comparison
affects: [13-binary-size-analysis plan 02, optimization-writeup]

# Tech tracking
tech-stack:
  added: []
  patterns: [mach-o-analysis, binary-measurement]

key-files:
  created:
    - research/binary-size-analysis.md
  modified: []

key-decisions:
  - "Documented __TEXT page boundary crossing: v1.2 binary requires 2 pages (32 KB) vs v1.0's single page"
  - "Per-file __text sums match linked binary exactly (16,696 bytes); __const and __data have small linker alignment deltas (+9 and +7 bytes)"
  - "data.s contains zero code but 10,423 bytes of data -- all shared game state lives in one file"

patterns-established:
  - "Binary measurement methodology: size -m for section overview, otool -l for exact offsets/sizes, nm for symbol analysis"

requirements-completed: [SIZE-01, SIZE-02]

# Metrics
duration: 3min
completed: 2026-02-27
---

# Phase 13 Plan 01: Binary Size Analysis Summary

**Complete Mach-O section breakdown and per-file code contribution analysis of the 77,016-byte post-v1.2 assembly binary across 12 source files**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-27T20:48:11Z
- **Completed:** 2026-02-27T20:51:09Z
- **Tasks:** 1
- **Files created:** 1

## Accomplishments

- Measured all Mach-O sections with exact byte counts: __text=16,696, __stubs=336, __const(TEXT)=1,907, __got=240, __const(DATA_CONST)=224, __data=8,396, LINKEDIT=11,480
- Per-file contribution table for all 12 .s files sorted by code size (render.s 27.9%, animation.s 20.3%, board.s 14.4% = top 3 at 62.6%)
- Binary growth documented: 55,672 bytes (v1.0) to 77,016 bytes (v1.2), +38.3% file size, +65.4% code
- Symbol analysis: 227 total (54 text, 60 data, 30 imported from ncurses/libSystem)
- Stripped binary comparison: 52,720 bytes (-31.5% from unstripped)

## Task Commits

Each task was committed atomically:

1. **Task 1: Measure binary sizes and produce binary-size-analysis.md** - `f783e62` (feat)

## Files Created/Modified

- `research/binary-size-analysis.md` - Complete binary size analysis with section breakdown, per-file contributions, growth analysis, and symbol counts

## Decisions Made

- Documented that __TEXT segment crossed the 16 KB page boundary (v1.0 fit in 1 page, v1.2 needs 2 pages at 57.8% utilization)
- Per-file __text sums verified to match linked binary exactly (16,696 bytes); small __const/data discrepancies attributed to linker alignment
- Identified animation.s (3,384 bytes, 20.3%) as the largest single feature contributor to post-v1.0 code growth

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Binary size analysis document ready for Phase 13 Plan 02 to use for optimization work
- Key finding: __TEXT page boundary crossed, providing a clear optimization target (reduce __text below 16 KB threshold)
- Top 3 code-heavy files identified for potential size reduction: render.s, animation.s, board.s

---
*Phase: 13-binary-size-analysis*
*Completed: 2026-02-27*
