# yetris-asm: ARM Assembly Tetris Research Project

## What This Is

A fully playable Tetris clone written entirely in AArch64 (ARM64) assembly for macOS on Apple Silicon, with pixel-perfect visual parity to the C++ original, full modern Tetris scoring, animated backgrounds, and a comprehensive research writeup on optimization techniques. 8,450 lines of hand-written assembly producing a 77KB binary (13.5x smaller than the C++ original). Lives alongside the original C++ code for direct comparison.

## Core Value

Produce a fully playable Tetris clone in ARM assembly that is measurably smaller and faster than the C++ original, with a documented writeup explaining every technique and tradeoff.

## Requirements

### Validated

- ✓ Full faithful rewrite of yetris in AArch64 assembly (game logic, menus, scoring) — v1.0
- ✓ Minimal ncurses linkage for terminal I/O (no other library dependencies) — v1.0
- ✓ Binary size tracking at each development stage vs C++ baseline — v1.0
- ✓ Frame time and CPU cycle benchmarks via mach_absolute_time — v1.0
- ✓ Register-only game state exploration (x28 bitfield packing) — v1.0
- ✓ ARM NEON/SIMD exploration for line detection (ld1+uminv) and collision analysis — v1.0
- ✓ Syscall analysis documenting ncurses already batches output optimally — v1.0
- ✓ Research writeup documenting all 5 techniques, measurements, and tradeoffs — v1.0
- ✓ Assembly source lives in asm/ directory alongside existing src/ for comparison — v1.0
- ✓ Pixel-perfect layout match to C++ original (80x24 grid, same panel positions, ncurses subwindows) — v1.1
- ✓ ASCII art logo on main menu matching C++ version — v1.1
- ✓ All 4 background animations (fire, water, snakes, Game of Life) — v1.1
- ✓ Full modern scoring (combos, back-to-back, T-spin bonuses, perfect clear) — v1.1
- ✓ Line clear animation (visual flash before row removal) — v1.1
- ✓ Hi-score persistence (single top score saved to file) — v1.1
- ✓ Fancy box-drawing borders (ACS characters, color-coded) — v1.1
- ✓ Color on all UI elements (menu, labels, overlays) — v1.1
- ✓ Menu animations and visual polish — v1.1
- ✓ Dead code removal and codebase cleanup — v1.2
- ✓ Binary size analysis and optimization opportunities — v1.2
- ✓ Research writeup expanded with v1.1 techniques — v1.2
- ✓ Standalone v1.1 techniques document — v1.2

### Active

(None — all milestones complete)

### Out of Scope

- x86/Intel assembly — ARM64 only, targeting Apple Silicon
- GUI or graphical rendering — terminal-only via ncurses
- Cross-platform support — macOS only (Darwin syscall conventions)
- Rewriting ncurses itself — use it as-is for terminal abstraction
- Player profiles — massive complexity (INI parsing, directory management); single global hi-score sufficient
- Top-10 leaderboard — single hi-score sufficient for current scope
- Networked multiplayer — future milestone
- Configurable keybindings from file — requires file parsing; compile-time keys sufficient
- Theme system — C++ theme system spans ~200 lines; hardcoded defaults match C++
- All-spin detection (S/Z/L/J spins) — only T-spin is standard modern Tetris

## Context

- **Shipped:** v1.0 (5 phases, 13 plans), v1.1 (6 phases, 10 plans), v1.2 (3 phases, 6 plans) — all on 2026-02-27
- **Codebase:** 8,450 lines ARM64 assembly across 12 source files in asm/
- **Binary:** 77,016 bytes unstripped (13.5x smaller than C++), 52,720 bytes stripped (20.7x less code)
- **Tech stack:** Apple `as` assembler + `ld` linker, ncurses, libSystem
- **Research output:** 807-line optimization writeup + 232-line binary size analysis + 1,142-line v1.1 techniques deep dive
- **Optimizations implemented:** NEON line detection (ld1+uminv), register packing (x28 bitfield), NEON mask alignment reduction
- **v1.1 additions:** ncurses subwindows, ACS borders, ASCII logo, modern scoring engine (combos, T-spin, B2B, perfect clear), line clear animation, 4 background animations (fire/water/snakes/GoL), hi-score persistence via Darwin syscalls
- **v1.2 cleanup:** Dead code removed (_clear_lines, 4 orphaned strings, 28 .globl directives), binary size analyzed per-section and per-file, all research documentation current
- **Known issues:** `_shuffle_bag` ABI issue (x21 not saved) — runtime-harmless, logged as deferred; 2 stale header comments in render.s and menu.s listing removed data dependencies

## Constraints

- **Architecture**: AArch64 only — Apple M-series chips
- **OS**: macOS (Darwin kernel, Mach-O executable format)
- **Dependencies**: Only ncurses (system-provided on macOS)
- **Toolchain**: Apple's `as` assembler and `ld` linker (Xcode command line tools)
- **Comparison baseline**: Must remain buildable alongside original C++ version

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Full rewrite over incremental | Research value in understanding the complete system in assembly | ✓ Good — complete rewrite in 5 phases |
| ncurses over raw syscalls | Provides terminal abstraction without reinventing cursor control | ✓ Good — only 2 dylib dependencies |
| Alongside in same repo | Enables direct A/B comparison of binary size and performance | ✓ Good — 13.5x binary size reduction documented |
| Byte-per-cell board layout | Simple addressing (row*10+col) over bitfield packing | ✓ Good — enabled NEON line detection with ld1 |
| NEON for line detection, not collision | Contiguous row data suits SIMD; scattered 5x5 collision does not | ✓ Good — valuable negative result documented |
| mach_absolute_time over gettimeofday | Reads CNTVCT_EL0 directly from commpage, no syscall overhead | ✓ Good — 42ns precision timing |
| Named subwindows over stdscr | Proper panel isolation, enables overlays and composition | ✓ Good — clean separation, no visual artifacts |
| wnoutrefresh+doupdate batch refresh | Single terminal write per frame instead of per-panel | ✓ Good — zero flicker |
| Callee-saved regs for animation loops | Avoids stack spills across ncurses calls | ✓ Good — clean register allocation |
| Board cell value 9 as flash marker | Natural extension of 0-8 value space, no extra flags needed | ✓ Good — simple, no-overhead animation state |
| Scoring centralized in _lock_piece | Single pipeline for all score events (clears, combos, T-spins) | ✓ Good — clean integration point |
| Raw 4-byte binary for hi-score file | Simpler than ASCII/text parsing, fits single uint32 | ✓ Good — minimal code, robust |
| Signed halfwords for fire intensity | Handles negative propagation values without clamp logic | ✓ Good — simplified fire algorithm |
| Table-only labels local (no .globl) | Reduces exported symbol count; table-only strings accessed via pointer tables in same file | ✓ Good — 28 labels made local, cleaner symbol table |
| .p2align 2 for NEON mask (not .p2align 4) | ARM64 ld1 does not require 16-byte alignment | ✓ Good — -12 bytes __const (page alignment absorbs file-level savings) |
| stp pairs kept even for "unused" registers | ARM64 ABI requires pair alignment for stack operations | ✓ Good — confirmed no true redundancy in codebase |

---
*Last updated: 2026-02-27 after v1.2 milestone*
