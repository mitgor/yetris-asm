# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v1.0 — ARM64 Assembly Tetris

**Shipped:** 2026-02-27
**Phases:** 5 | **Plans:** 13

### What Was Built
- Complete Tetris rewrite in AArch64 assembly (5,300 LOC, 52KB binary)
- Full game: 7 pieces, SRS rotation, wall kicks, gravity, scoring, menus, game modes
- NEON SIMD line detection, register packing, 530-line optimization research writeup

### What Worked
- Phase-per-subsystem decomposition (foundation -> game -> features -> menus -> research) kept each phase focused
- Byte-per-cell board layout enabled clean NEON integration later
- Research-last ordering: build first, measure second, write third

### What Was Inefficient
- Some phases could have been parallelized (menus and gameplay features are independent)
- Score table entries were reworked when modern scoring arrived in v1.1

### Patterns Established
- data.s as single mutable state file, all other .s files reference via GOT-indirect
- Makefile $(wildcard asm/*.s) auto-discovers new source files
- Callee-saved register conventions for ncurses-heavy functions

### Key Lessons
1. Assembly binary size wins are real (18.6x) but the LOC cost is high (~5x more lines than C++)
2. Negative results (NEON collision, syscall batching) are as valuable as positive ones for the research writeup
3. mach_absolute_time commpage access is the gold standard for ARM64 profiling on macOS

---

## Milestone: v1.1 — Visual Polish & Gameplay

**Shipped:** 2026-02-27
**Phases:** 6 | **Plans:** 10

### What Was Built
- Pixel-perfect 80x24 subwindow layout matching C++ original (12 named WINDOW* panels)
- ACS box-drawing borders, ASCII art logo, colored UI, interactive pause menu
- Modern scoring engine (combos, T-spin, B2B, perfect clear, drop points)
- Line clear flash animation with 200ms non-blocking delay
- All 4 background animations (fire, water, snakes, Game of Life)
- Hi-score persistence via Darwin syscalls to ~/.yetris-hiscore

### What Worked
- Subwindows-first ordering was critical — every subsequent phase depended on named WINDOW* pointers
- Mark/clear split (Phase 9) elegantly solved both animation timing and scoring pipeline ordering
- Double-buffer pattern reused across water and GoL animations with shared swap flag
- Timer-gated animation updates integrated cleanly into existing game loop without frame drops

### What Was Inefficient
- Roadmap phase checkboxes got out of sync with actual completion (some showed unchecked despite SUMMARY.md existing)
- Audit was run before Phase 11, requiring manual assessment that gaps were subsequently closed

### Patterns Established
- wnoutrefresh+doupdate batch refresh as standard frame protocol (zero flicker)
- Board cell value 9 as animation marker (extends 0-8 piece value space)
- Callee-saved registers (x19-x28) for all animation draw loops
- GOT-indirect ACS character loading for terminal independence
- Stack-based transient buffers for file I/O paths

### Key Lessons
1. Subwindow refresh ordering (erase parent -> draw -> wnoutrefresh -> erase child -> draw child -> wnoutrefresh -> doupdate) is the #1 ncurses pitfall — get it right once and never touch it again
2. Signed halfwords for intensity buffers avoid clamping logic in fire/water propagation
3. Running the milestone audit before the final phase is fine — just verify gaps are closed before archival
4. 10 plans across 6 phases in ~10 hours demonstrates the velocity of well-decomposed assembly work

### Cost Observations
- Model mix: ~80% opus, ~20% haiku (for parallel subagents)
- Sessions: ~4
- Notable: Average 3.7 minutes per plan execution — smallest plans (animation, hiscore) took 3 minutes

---

## Milestone: v1.2 — Polish

**Shipped:** 2026-02-27
**Phases:** 3 | **Plans:** 6

### What Was Built
- Codebase cleaned: dead _clear_lines removed (182 lines), 4 orphaned strings removed, 28 .globl directives made local
- Complete Mach-O binary size analysis: section breakdown, per-file contributions for all 12 .s files, growth trajectory
- NEON mask alignment optimization (.p2align 4 to .p2align 2, -12 bytes at section level)
- Research writeup expanded to 807 lines with 4 new v1.1 technique sections
- Standalone 1,142-line v1.1 techniques deep-dive with annotated assembly code walkthroughs
- Updated C++ comparison: 13.5x smaller unstripped, 20.7x less code, 10.4x smaller stripped

### What Worked
- Cleanup-first ordering (Phase 12 before Phase 13) ensured binary measurements reflected the actual shipped codebase
- Integration checker caught 6 stale documentation numbers that manual review missed — fixed inline before completion
- Research-as-code approach (extracting real assembly into docs) produced accurate, verifiable documentation
- Phase 13's measurement-before-optimization order gave clear before/after numbers

### What Was Inefficient
- Phase 13 Plan 02 optimization updated the primary tables but missed 3 peripheral text locations, which then propagated into Phase 14 — a classic "number update fan-out" problem
- The one-liner frontmatter field was null across all 6 SUMMARY.md files, making automated accomplishment extraction fail

### Patterns Established
- Binary analysis methodology: `size -m`, `otool -l`, `nm`, `strip`, per-object-file breakdown
- Page-boundary awareness: understanding that section-level savings may not reduce file size due to Mach-O page alignment
- Deep-dive research format: problem statement + code walkthrough + design rationale + binary cost per technique

### Key Lessons
1. Documentation number propagation requires a checklist — when one number changes, trace all downstream references
2. Page alignment (16 KB on ARM64) means small section-level optimizations may have zero file-size impact
3. ARM64 ld1 does NOT require 16-byte alignment — .p2align 2 (4-byte) is sufficient, saving alignment padding
4. The distinction between fire's source+modifier pattern and true double-buffering matters for accurate documentation

### Cost Observations
- Model mix: ~70% opus, ~30% sonnet/haiku (integration checker, subagents)
- Sessions: ~2
- Notable: 6 plans in ~28 minutes total; documentation-heavy phases averaged 4.7 min/plan vs code-heavy 3.7 min/plan

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Phases | Plans | Key Change |
|-----------|--------|-------|------------|
| v1.0 | 5 | 13 | Established core patterns (data.s, Makefile, register conventions) |
| v1.1 | 6 | 10 | Leaned on subwindow foundation; faster execution with established patterns |
| v1.2 | 3 | 6 | Documentation/cleanup milestone — integration checker caught stale number propagation |

### Top Lessons (Verified Across Milestones)

1. Foundation-first ordering pays dividends — all three milestones benefited from building infrastructure before features
2. Assembly LOC grows ~5x vs C++ but binary shrinks ~13.5x — the tradeoff is real and consistent (ratio narrowed from 18.6x as features added)
3. Plan decomposition at 3-5 minute granularity keeps velocity high and integration risk low
4. Documentation phases need the same rigor as code phases — stale numbers propagate just like stale APIs
5. Milestone audit before completion catches issues that phase-level verification misses (cross-phase number propagation)
