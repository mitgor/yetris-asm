---
phase: 02-core-playable-game
plan: 01
subsystem: asm-data
tags: [aarch64, arm64, tetromino, srs-kicks, game-data, timer, random, fisher-yates]

# Dependency graph
requires:
  - phase: 01-foundation-and-darwin-abi-scaffold
    provides: "Makefile asm build pipeline, Darwin ABI conventions, main.s entry point"
provides:
  - "asm/data.s: All game data tables (pieces, kicks, colors, scores, delays, levels) and mutable state"
  - "asm/timer.s: gettimeofday wrapper (_get_time_ms) returning milliseconds"
  - "asm/random.s: 7-bag random piece generator (_shuffle_bag, _next_piece)"
affects: [02-02-board-piece-mechanics, 02-03-rendering-input, 02-04-game-loop]

# Tech tracking
tech-stack:
  added: [gettimeofday, arc4random_uniform]
  patterns: [flat-byte-array-tables, fisher-yates-shuffle, 7-bag-randomizer, adrp-add-cross-file-globals]

key-files:
  created: [asm/data.s, asm/timer.s, asm/random.s]
  modified: []

key-decisions:
  - "Used 5x5 byte grid format (700 bytes) for piece data matching C++ reference exactly, avoiding compact representation bugs"
  - "Stored SRS kick values in raw tetris.wiki convention (positive Y = up), deferring Y-axis negation to piece.s"
  - "Used adrp+add (@PAGE/@PAGEOFF) for cross-file data access since all .s files link into same binary"
  - "Spawn Y values transcribed from C++ reference global_pieces_position table (-4 for O, -3 for all others)"

patterns-established:
  - "Data tables in __TEXT,__const (read-only), mutable state in __DATA,__data"
  - "All exported labels use .globl with .p2align for proper alignment"
  - "Cross-file globals accessed via adrp+add (same binary, not GOT)"
  - "x-width registers for register offset addressing in strb/ldrb"

requirements-completed: [MECH-01, MECH-08]

# Metrics
duration: 4min
completed: 2026-02-26
---

# Phase 2 Plan 1: Game Data Tables and Utilities Summary

**All 7 tetrominoes with SRS kick tables, gravity/score/level lookups, gettimeofday timer, and 7-bag Fisher-Yates random generator in AArch64 assembly**

## Performance

- **Duration:** 4 min
- **Started:** 2026-02-26T19:52:46Z
- **Completed:** 2026-02-26T19:56:44Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Created asm/data.s (453 lines) with all game data tables: 7 tetrominoes in 5x5 grid format (700 bytes), SRS wall kick tables for JLSTZ and I-piece (80 bytes each), gravity delays, score table, level thresholds, color pairs, and spawn positions
- Created asm/timer.s with _get_time_ms wrapping gettimeofday to return milliseconds
- Created asm/random.s with Fisher-Yates shuffle (_shuffle_bag) using arc4random_uniform and 7-bag drawer (_next_piece) with auto-refill
- All 4 .s files (main.s, data.s, timer.s, random.s) link into a single Mach-O arm64 binary via `make asm`
- All data sizes verified: piece_data=700B, srs_kicks=80B each, board=200B

## Task Commits

Each task was committed atomically:

1. **Task 1: Create data.s with all game data tables and mutable game state** - `7f4b9f6` (feat)
2. **Task 2: Create timer.s and random.s utility functions** - `61a1cd6` (feat)

## Files Created/Modified
- `asm/data.s` - All game constants (piece shapes, SRS kicks, gravity/score/level tables, color pairs, spawn positions) and mutable game state (board, piece, score, bag, timer)
- `asm/timer.s` - gettimeofday wrapper returning current time in milliseconds (64-bit)
- `asm/random.s` - 7-bag random piece generator with Fisher-Yates shuffle via arc4random_uniform

## Decisions Made
- Used 5x5 byte grid format for piece data (700 bytes) rather than compact 4-cell representation to match C++ reference collision detection exactly, eliminating a class of bugs at the cost of ~476 bytes
- Stored SRS kick values in raw tetris.wiki convention (positive Y = up) -- the Y-axis negation will happen in piece.s (plan 02) when applying kicks to board coordinates, matching the C++ reference pattern (`this->y -= dy`)
- Used adrp+add (@PAGE/@PAGEOFF) instead of GOT access for cross-file data since all assembly files link into the same binary
- Transcribed all 28 piece rotation states directly from C++ PieceDefinitions.cpp for byte-perfect compatibility
- Used x-width registers for register offset addressing after discovering `strb w, [x, w, uxtw]` is not supported by the assembler

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed register offset addressing mode for strb/ldrb**
- **Found during:** Task 2 (random.s assembly)
- **Issue:** `strb w8, [x19, w8, uxtw]` and similar instructions using w-register with uxtw extend are not supported for byte-size store/load
- **Fix:** Changed to x-width registers with explicit `uxtw` zero-extension into x-registers, then used `strb w, [x, x]` addressing
- **Files modified:** asm/random.s
- **Verification:** File assembles cleanly, full project links without errors
- **Committed in:** 61a1cd6 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Minor assembler syntax correction. No scope creep.

## Issues Encountered

None beyond the addressing mode fix documented above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- All data tables ready for consumption by plan 02 (board/piece mechanics): _piece_data indexed by type*100 + rotation*25 + row*5 + col, _srs_kicks indexed by direction*40 + start_rotation*10 + test*2 + axis
- Timer utility (_get_time_ms) ready for gravity timing in plan 04 (game loop)
- Random piece generator (_next_piece, _shuffle_bag) ready for piece spawning in plan 02
- 21 exported symbols from data.s, 1 from timer.s, 2 from random.s -- all accessible via adrp+add

## Self-Check: PASSED

All files verified present, all commits verified in git log, binary builds successfully.

---
*Phase: 02-core-playable-game*
*Completed: 2026-02-26*
