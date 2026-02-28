# Milestones

## v1.0 ARM64 Assembly Tetris (Shipped: 2026-02-27)

**Phases:** 1-5 (5 phases, 13 plans)
**Total LOC:** 5,300 lines ARM64 assembly
**Binary:** 52,720 bytes stripped (18.6x smaller than C++ original)

**Key accomplishments:**
- Full faithful rewrite of yetris in AArch64 assembly (game logic, menus, scoring)
- Minimal ncurses linkage for terminal I/O (no other library dependencies)
- NEON SIMD line detection (ld1+uminv) and register packing (x28 bitfield)
- 530-line optimization research writeup documenting 5 techniques
- 52KB binary vs 980KB C++ original (18.6x size reduction)

**Requirements:** 39/39 satisfied

---


## v1.1 Visual Polish & Gameplay (Shipped: 2026-02-27)

**Phases:** 6-11 (6 phases, 10 plans)
**Feature commits:** 21
**Lines changed:** +4,370 / -1,010
**Total LOC:** 8,664 lines ARM64 assembly
**Timeline:** 2026-02-27 (09:51 → 19:59, ~10 hours)
**Git range:** feat(06-01) → feat(11-01)

**Key accomplishments:**
- Pixel-perfect subwindow layout: 12 named ncurses WINDOW* subwindows matching C++ 80x24 panel positions with wnoutrefresh+doupdate batch refresh
- Full visual polish: ACS box-drawing borders with 3D shadow, ASCII art logo, colored titles/labels, interactive pause menu, styled game over overlay
- Modern scoring engine: Level-multiplied scoring, combo tracking, back-to-back 1.5x bonus, T-spin detection, perfect clear, drop points
- Line clear animation: Mark/clear split with flash rendering, 200ms non-blocking delay, deferred spawn state machine
- All 4 background animations: Fire, water, snakes, Game of Life with double-buffer techniques, timer-gated updates, random selection
- Hi-score persistence: Darwin syscall file I/O saving/loading top score to ~/.yetris-hiscore with live tracking

**Requirements:** 35/35 satisfied

---


## v1.2 Polish (Shipped: 2026-02-27)

**Phases:** 12-14 (3 phases, 6 plans)
**Commits:** 24
**Lines changed:** +3,698 / -291
**Total LOC:** 8,450 lines ARM64 assembly
**Binary:** 77,016 bytes (13.5x smaller than C++ original)
**Timeline:** 2026-02-27
**Git range:** 9802dcc..264deb6

**Key accomplishments:**
- Removed dead `_clear_lines` function (182 lines) and 4 orphaned string literals; audited and cleaned .globl directives for 28 table-only labels
- Created comprehensive Mach-O binary size analysis: section breakdown, per-file contributions for all 12 source files, binary growth trajectory from v1.0 through v1.2
- Applied NEON mask alignment optimization (`.p2align 4` to `.p2align 2`, -12 bytes __const at section level)
- Expanded optimization writeup with 4 new v1.1 technique sections (subwindow composition, animation double-buffering, scoring pipeline, Darwin syscall file I/O)
- Created standalone 1,142-line deep-dive document (`research/v1.1-techniques.md`) with annotated assembly code walkthroughs for all 4 major v1.1 features
- Updated C++ vs assembly comparison: 13.5x smaller unstripped, 20.7x less code, 10.4x smaller stripped

**Requirements:** 11/11 satisfied

---

