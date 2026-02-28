# yetris-asm

A fully playable Tetris clone written entirely in AArch64 (ARM64) assembly for macOS on Apple Silicon.

8,450 lines of hand-written assembly producing a 77KB binary — 13.5x smaller than the [C++ original](https://github.com/alexdantas/yetris).

## Features

- **Full Tetris gameplay** — 7 pieces, SRS rotation, wall kicks, gravity, levels
- **Modern scoring** — combos, back-to-back bonus, T-spin detection, perfect clear, drop points
- **4 background animations** — fire, water, snakes, Game of Life
- **Line clear animation** — visual flash with 200ms non-blocking delay
- **Hi-score persistence** — saved to `~/.yetris-hiscore`
- **Pixel-perfect layout** — 80x24 terminal, 12 ncurses subwindows matching the C++ original
- **Visual polish** — ACS box-drawing borders, ASCII art logo, colored UI

## Requirements

- macOS on Apple Silicon (M1/M2/M3/M4)
- Xcode Command Line Tools (`xcode-select --install`)

## Build

```
make        # build
make run    # build and run
make strip  # build and create stripped binary
make clean  # remove build artifacts
```

## Binary Size

| Build | Size | vs C++ original |
|-------|------|-----------------|
| Unstripped | 77 KB | 13.5x smaller |
| Stripped | 53 KB | 20.7x smaller |

## Architecture

12 source files, each handling a distinct subsystem:

| File | Purpose |
|------|---------|
| `main.s` | Entry point, state machine, game loop |
| `board.s` | Board state, collision, line clearing |
| `piece.s` | Piece definitions, SRS rotation, wall kicks |
| `render.s` | All ncurses drawing, subwindow composition |
| `input.s` | Keyboard handling |
| `data.s` | All mutable game state (single file) |
| `menu.s` | Menu system, pause overlay |
| `animation.s` | Fire, water, snakes, Game of Life |
| `layout.s` | Subwindow creation and positioning |
| `hiscore.s` | File I/O via Darwin syscalls |
| `timer.s` | Frame timing via `mach_absolute_time` |
| `random.s` | 7-bag piece randomizer |

Key technical choices:
- **Darwin ARM64 ABI** — `svc #0x80` syscalls, x16 for syscall number, x18 reserved
- **NEON SIMD** — `ld1`+`uminv` for full-row line detection
- **Register packing** — x28 bitfield for game state flags
- **Batch refresh** — `wnoutrefresh`+`doupdate` for zero-flicker rendering
- **Commpage timing** — `mach_absolute_time` reads `CNTVCT_EL0` with no syscall overhead

## Development History

The `.planning/` directory contains the full development history across 3 milestones, 14 phases, and 29 plans — including research notes, phase plans, verification reports, and a project retrospective.

## License

GPLv3 — see [COPYING](COPYING).

Based on [yetris](https://github.com/alexdantas/yetris) by Alexandre Dantas.
