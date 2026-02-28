---
phase: 01-foundation-and-darwin-abi-scaffold
plan: 01
subsystem: asm-build
tags: [aarch64, arm64, darwin-abi, ncurses, assembly, makefile, apple-silicon]

# Dependency graph
requires: []
provides:
  - "asm/main.s: AArch64 ncurses hello-world with all 9 Darwin ABI conventions"
  - "Makefile asm/asm-clean/asm-run targets for assembly build pipeline"
  - ".gitignore rules for asm build artifacts"
affects: [01-02, 02-core-game-loop, all-future-asm-files]

# Tech tracking
tech-stack:
  added: [apple-as, apple-ld, xcrun, ncurses, libSystem]
  patterns: [darwin-arm64-abi, got-indirect-access, adrp-add-local-data, stp-ldp-prologue-epilogue, mach-o-sections]

key-files:
  created: [asm/main.s]
  modified: [Makefile, .gitignore]

key-decisions:
  - "Used _main entry (not _start) with -lSystem for C runtime init required by ncurses"
  - "Stored stdscr GOT pointer in callee-saved x19 to avoid reloading across function calls"
  - "Appended asm rules to end of Makefile, completely independent of C++ build"

patterns-established:
  - "Prologue/epilogue: stp x20,x19,[sp,#-32]! / stp x29,x30,[sp,#16] / add x29,sp,#16"
  - "Local data: adrp+add with @PAGE/@PAGEOFF for same-binary symbols"
  - "External globals: adrp+ldr with @GOTPAGE/@GOTPAGEOFF then dereference"
  - "Mach-O sections: __TEXT,__text for code; __TEXT,__cstring for strings; .subsections_via_symbols"
  - "Build: as -> .o, ld with -lncurses -lSystem -syslibroot $(SDK_PATH) -arch arm64"

requirements-completed: [FOUN-01, FOUN-02, FOUN-03, FOUN-04]

# Metrics
duration: 3min
completed: 2026-02-26
---

# Phase 1 Plan 1: Foundation Assembly Scaffold Summary

**AArch64 ncurses hello-world with all 9 Darwin ABI conventions, Makefile build pipeline, and verified Mach-O arm64 binary**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-26T19:16:12Z
- **Completed:** 2026-02-26T19:18:57Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Created asm/main.s (105 lines) with complete ncurses init/display/keypress/cleanup flow demonstrating all 9 Darwin ABI conventions
- Extended Makefile with asm, asm-clean, asm-run targets that produce a verified Mach-O arm64 binary at asm/bin/yetris-asm
- Verified binary links against libncurses.5.4 and libSystem.B, exports correct symbols (_initscr, _endwin, _stdscr, etc.)
- Confirmed C++ build (make all) and assembly build (make asm) are fully independent

## Task Commits

Each task was committed atomically:

1. **Task 1: Create asm/main.s with ncurses hello-world program** - `0623e88` (feat)
2. **Task 2: Extend Makefile with asm target and update .gitignore** - `c1017b0` (feat)

## Files Created/Modified
- `asm/main.s` - AArch64 assembly ncurses hello-world with Darwin ABI convention header documentation and all 9 rules applied in code
- `Makefile` - Added ASM_DIR/ASM_EXE variables, pattern rule for .s->.o, asm/asm-clean/asm-run targets
- `.gitignore` - Added asm/bin/ and asm/*.o exclusion patterns

## Decisions Made
- Used _main entry point (not _start) because ncurses requires C runtime initialization via -lSystem
- Stored stdscr GOT pointer in callee-saved register x19 to persist across function calls without reloading from GOT
- Placed assembly build rules at end of Makefile, completely independent of existing C++ targets
- Used unversioned ncurses symbols (_initscr vs _initscr$NCURSES60) for simplicity per research recommendation

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Assembly build pipeline fully operational: as -> ld -> Mach-O arm64 binary
- All 9 Darwin ABI patterns established and documented for use in all future assembly files
- asm/main.s serves as the foundation for Phase 1 Plan 2 (verification/testing) and Phase 2 (core game loop)
- C++ build remains unaffected for reference comparison in later optimization phases

## Self-Check: PASSED

All files verified present, all commits verified in git log.

---
*Phase: 01-foundation-and-darwin-abi-scaffold*
*Completed: 2026-02-26*
