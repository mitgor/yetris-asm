# Feature Landscape: v1.1 Visual Polish & Gameplay

**Domain:** ARM64 assembly Tetris clone -- visual polish, modern scoring, animations, hi-score persistence
**Researched:** 2026-02-27
**Scope:** Features NEW to v1.1 only (v1.0 game mechanics already shipped)

---

## Table Stakes

Features the C++ original has that the assembly version must match for parity. Missing these = incomplete v1.1.

### Visual Layout & Subwindows

| Feature | Why Expected | Complexity | Dependencies | Notes |
|---------|--------------|------------|--------------|-------|
| ncurses subwindows (newwin/derwin) | C++ uses per-panel WINDOW* for isolated drawing | HIGH | ncurses init | Currently all drawing is on stdscr via wmove+waddch. C++ creates ~10 ncurses WINDOW* objects: main, leftmost, hold, score, middle_left, board, middle_right, next[], rightmost, pause. Each uses `derwin()` for parent-relative positioning. Assembly must call `_newwin`/`_derwin`/`_delwin` and manage WINDOW* pointers in data segment. |
| Pixel-perfect 80x24 layout | C++ `LayoutGame(this, 80, 24)` with exact panel positions | MEDIUM | Subwindows | C++ layout: leftmost (col 0, w=12), hold (w=12, h=4), score (below hold), middle_left (board container, w=22, h=22), board (inside middle_left, borderless), middle_right (next pieces, w=10), rightmost (statistics, fills remaining). Current asm layout is approximate and hand-positioned on stdscr. |
| Fancy box-drawing borders (ACS chars) | C++ Window::BORDER_FANCY uses ACS_VLINE, ACS_HLINE, ACS_ULCORNER etc. | LOW | Subwindows | C++ applies color-coded "shadow" borders: left/top brighter, right/bottom dimmer. Uses `wborder()` with 8 ACS parameters, each OR'd with a color pair. Assembly calls `_wborder` with same ACS constants. |
| Window titles ("Hold", "Next", "Statistics", "Paused") | C++ `setTitle()` renders text over border at top-left/right | LOW | Borders | After `wborder()`, overwrite specific positions on row 0/bottom row with title text in highlight color. |
| Color on all UI elements | C++ uses theme colors for labels, values, borders, menu items | MEDIUM | Color pairs | Current asm only has 7 piece color pairs. Need additional pairs: highlight text (cyan on black), dim text (dim white), dim-dim text (dark gray), text (white on black). C++ uses ~6 theme color pairs beyond piece colors. |

### ASCII Art & Menu Polish

| Feature | Why Expected | Complexity | Dependencies | Notes |
|---------|--------------|------------|--------------|-------|
| ASCII art logo on main menu | C++ `LayoutMainMenu` renders 7-line ASCII art "YETRIS" banner | LOW | String data, subwindows | 7 lines of ASCII art, each ~39 chars wide. Store in __TEXT,__const as 7 .asciz strings. Center at `(window_width/2 - 19)`. |
| Menu item highlight colors | C++ uses cyan for first letter, default for rest | LOW | Color pairs | Current asm uses A_REVERSE for selection. Add color pair for menu highlight text. |
| Settings display in menu | C++ shows settings with highlighted labels | LOW | Color pairs | Already implemented in asm, but without color. Add color to labels and values. |

### Line Clear Animation

| Feature | Why Expected | Complexity | Dependencies | Notes |
|---------|--------------|------------|--------------|-------|
| Visual flash before row removal | C++ `markFullLines()` replaces cells with ':' clear_line theme, then `LayoutGame::draw()` calls `delay_ms(200)` before `clearFullLines()` removes them | MEDIUM | Board rendering | Two-phase approach in C++: (1) mark full lines with special block type, render, delay 200ms, (2) clear. Assembly needs: detect full rows, temporarily change their cell values to a "flash" marker (e.g., value 9), render the flash state, call `_usleep()` or `_nanosleep()` for delay, then do normal line clear. The delay freezes the game loop for one frame -- acceptable because the C++ original does the same thing. |

### Scoring Display

| Feature | Why Expected | Complexity | Dependencies | Notes |
|---------|--------------|------------|--------------|-------|
| Hi-score display in score panel | C++ renders "Hi-Score" label + value above current score | LOW | Hi-score state variable | C++ `LayoutGame::draw()` shows `highScore->points` or "(none)". Assembly needs a `_hi_score` word in data segment, displayed via `_mvwprintw` or manual digit rendering. |

---

## Differentiators

Features that go beyond the C++ original's basic scoring or add genuine improvement. Not strictly required for "parity" but listed as v1.1 targets.

### Modern Tetris Scoring

The C++ original uses a simplified scoring model: 1=100, 2=300, 3=500, 4=800 flat points (no level multiplier, no combos, no T-spin). v1.1 explicitly adds modern guideline scoring.

| Feature | Value Proposition | Complexity | Dependencies | Notes |
|---------|-------------------|------------|--------------|-------|
| Level-multiplied line scores | Standard: Single=100*level, Double=300*level, Triple=500*level, Tetris=800*level | LOW | Current score system | Replace flat `_score_table` lookup with `score_table[lines-1] * level`. One `mul` instruction added to `_clear_lines`. |
| Combo system | 50 * combo_count * level for consecutive line clears | LOW | New state: `_combo_count` byte | Track consecutive line-clearing locks. Reset to 0 when a lock produces no line clears. Increment on each lock that clears lines. Add `50 * combo * level` to score. Single new byte in data segment, ~15 instructions in `_lock_piece`. |
| Back-to-back bonus | 1.5x multiplier for consecutive "difficult" clears (Tetris or T-spin) | MEDIUM | New state: `_b2b_flag` byte, T-spin detection | Track whether last line clear was "difficult" (Tetris = 4 lines, or any T-spin clear). If current clear is also difficult and flag was set, multiply score by 1.5 (actually add 50% extra: `score + score >> 1`). Only Tetris matters until T-spin detection exists; T-spin adds to this later. |
| T-spin detection | 3-corner rule: after T rotation, check 4 diagonal corners of T center; 3+ occupied = T-spin | HIGH | SRS rotation tracking, board state | Must track: (a) last move was rotation, (b) piece is T, (c) 3 of 4 diagonal corners occupied. Requires new flag `_last_was_rotate` set in rotation handler, cleared on move/drop. Corner check: 4 `ldrb` from board at `(center_y +/- 1, center_x +/- 1)`, count non-zero, compare >= 3. T-spin mini: only 1 front corner + 2 back corners; promoted to full if kick offset was (1,2) or (2,1). |
| T-spin scoring values | T-spin zero=400*lvl, Mini zero=100*lvl, Single=800*lvl, Mini single=200*lvl, Double=1200*lvl, Triple=1600*lvl | MEDIUM | T-spin detection | New score table `_tspin_score_table` in data segment. Indexed by (is_mini * 4 + lines_cleared). Applied instead of normal line score when T-spin detected. |
| Perfect clear bonus | Empty board after clear: Single=800*lvl, Double=1200*lvl, Triple=1800*lvl, Tetris=2000*lvl, B2B Tetris=3200*lvl | MEDIUM | Line clear, board scan | After clearing lines, scan entire board for all-zero (NEON `ld1` + `orr` across 13 loads, `umaxv` == 0). If empty, add perfect clear bonus from table. Rare event, but impressive when it happens. Bonus values stored as 5-entry `.word` table. |
| Soft drop scoring | 1 point per cell dropped | LOW | Input handler | In soft drop handler: after successful `_is_piece_valid` for down move, add 1 to `_score`. One `add` + `str` instruction. |
| Hard drop scoring | 2 points per cell dropped | LOW | Hard drop handler | Count cells traversed during hard drop (difference between start Y and final Y for each cell in piece). Multiply by 2. Add to `_score` before locking. |

### Background Animations

All 4 animations run inside the board WINDOW (behind the game pieces), updating each frame on a timer.

| Feature | Value Proposition | Complexity | Dependencies | Notes |
|---------|-------------------|------------|--------------|-------|
| Animation: Fire | Particle system with heat propagation, cooling map, ASCII grayscale rendering | HIGH | Subwindows, timer, RNG | C++ implementation: 2D array of ParticleFire (intensity values). Bottom row spawns at 90-100% intensity. Each frame, particles rise (copy from below minus cooling). Cooling map is smoothed random noise. ASCII chars from grayscale " .':-=+*#%@#". Colors: red/yellow/white by intensity threshold. Update rate: 100ms. Random bursts (10% chance) and dims (12% chance) per frame. Data: width*height bytes for particles + width*height words for cooling map = ~1.7KB for 22x20. |
| Animation: Water | Ripple simulation with double-buffer wave propagation | HIGH | Subwindows, timer, RNG | C++ implementation: Two 2D int arrays (buffer1, buffer2). Each frame: swap buffers, propagate ripples via `new[i][j] = ((old[i-1][j] + old[i+1][j] + old[i][j-1] + old[i][j+1]) >> 1) - new[i][j]`. Random drops (0.31% chance per frame). ASCII chars from grayscale "#@%#*+=-:'.". Colors: blue/cyan/white by height. Update rate: 300ms. Data: 2 * width*height*4 bytes = ~3.5KB for 22x20. |
| Animation: Snakes | Multiple falling "snake" entities, Matrix-style | MEDIUM | Subwindows, timer, RNG | C++ implementation: Vector of LilSnake structs (x, y, size). New snakes spawn every 100-300ms at random x, random small y, random length 2-14. Each moves down every 50ms. Head = '@' (bright green), body = 'o' (green). Removed when fully off-screen. Max ~50 snakes. Occasional burst (25% chance) adds 3-5 at once. Data: 50 * 3 bytes (x, y, size) = 150 bytes. Simplest animation. |
| Animation: Game of Life | Conway's Game of Life cellular automaton | MEDIUM | Subwindows, timer, RNG | C++ implementation: 2D bool array. Initial state: 20% random cells alive. Standard B3/S23 rules applied every 200ms. Living cells drawn as '#' in yellow. Dead cells as ' '. Data: width*height bytes = ~440 bytes for 22x20. Edges not updated (boundary condition). May stagnate -- C++ doesn't handle this (acceptable). |
| Animation selection (random) | C++ picks one of 4 animations randomly for menu and game | LOW | All 4 animations | Use `_arc4random_uniform(4)` at game start to select. Store selection as byte. Call appropriate update/draw function pointer or branch table. |

### Hi-Score Persistence

| Feature | Value Proposition | Complexity | Dependencies | Notes |
|---------|-------------------|------------|--------------|-------|
| Save single hi-score to file | Survives app restart; C++ has complex per-profile per-settings system, but v1.1 scope is single top score | MEDIUM | File I/O syscalls or C library | **Simplified vs C++ original:** C++ uses base64-encoded INI files with per-game-settings entries. v1.1 scope: save a single 4-byte unsigned integer to `~/.yetris-hiscore`. Use `_open`/`_read`/`_write`/`_close` from libSystem (not raw syscalls -- Apple discourages direct syscalls). File path: use `_getenv("HOME")` + "/.yetris-hiscore" suffix. On game over: if score > hi_score, write new value. On startup: read file, parse 4 bytes as uint32. If file missing or unreadable, default to 0. Total: ~80 instructions for load, ~60 for save. |

---

## Anti-Features

Features to explicitly NOT build in v1.1.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Profile system (per-user settings/scores) | Massive complexity (INI parsing, directory management, Base64 encoding); the C++ version is ~600 lines of C++ for profiles alone | Single global hi-score file. No profiles. |
| Configurable keybindings from file | Requires file parsing, string matching, key code mapping | Keep compile-time keybindings as in v1.0. |
| Theme system (configurable colors/block chars) | C++ theme system spans ~200 lines of Profile.cpp | Hardcoded theme matching C++ defaults. |
| Top-10 leaderboard | PROJECT.md explicitly scopes to "single hi-score sufficient for v1.1" | Single top score only. |
| Game-over animation (cascading fill) | C++ has an optional game-over cascade animation; visual only, not core feature | Simple game-over overlay text as currently implemented. |
| Menu animations (separate from game) | C++ runs animations behind the main menu too | Animations only in-game for v1.1. Menu stays as-is. |
| wnoutrefresh batching | C++ uses wnoutrefresh+doupdate pattern for performance; adds API complexity | Use wrefresh on each window; if flickering occurs, upgrade to wnoutrefresh pattern. Start simple. |
| All-spin detection | Some modern Tetris variants detect spins for all piece types, not just T | Only T-spin detection. No S-spin, Z-spin, L-spin, etc. |
| T-spin Mini distinction in scoring | The full mini vs. proper T-spin rules require tracking kick offset magnitude | Implement basic 3-corner T-spin. Mini detection is stretch goal: if kick offset was NOT (1,2)/(2,1), mark as mini. Separate scoring table already supports it. |

---

## Feature Dependencies

```
[ncurses subwindows]
    required by --> [Fancy borders (wborder on WINDOW*)]
    required by --> [Window titles]
    required by --> [80x24 pixel-perfect layout]
    required by --> [Background animations (draw into board WINDOW)]
    required by --> [Hi-score display in score panel]

[Additional color pairs (highlight, dim, dim-dim)]
    required by --> [Fancy borders (color-coded shadows)]
    required by --> [Menu highlight colors]
    required by --> [UI label coloring]
    required by --> [Animation color rendering]

[Line clear detection (existing _clear_lines)]
    required by --> [Line clear animation (flash before clear)]
    required by --> [Combo tracking (consecutive clears)]
    required by --> [Perfect clear detection (board empty after clear)]

[SRS rotation (existing)]
    required by --> [T-spin detection (last move was rotation)]

[T-spin detection]
    required by --> [T-spin scoring]
    required by --> [Back-to-back flag (T-spin clears are "difficult")]

[Back-to-back flag]
    required by --> [Back-to-back bonus scoring]
    required by --> [Perfect clear B2B Tetris bonus (3200*lvl)]

[Combo count state]
    required by --> [Combo scoring (50*combo*level)]

[File I/O (open/read/write/close)]
    required by --> [Hi-score load on startup]
    required by --> [Hi-score save on game over]

[Background animation framework (update/draw per frame)]
    required by --> [Fire animation]
    required by --> [Water animation]
    required by --> [Snakes animation]
    required by --> [Game of Life animation]

[Timer (existing _get_time_ms)]
    required by --> [Animation update throttling]
    required by --> [Line clear delay]
```

### Critical Path

The longest dependency chain is:
```
subwindows --> borders --> layout --> animations --> fire/water/snakes/GoL
```

And independently:
```
rotation tracking --> T-spin detection --> T-spin scoring --> B2B bonus
```

These two chains are parallel -- visual polish and scoring can be developed independently.

---

## MVP Recommendation for v1.1

### Phase 1: Visual Foundation
Prioritize subwindows and layout first because nearly everything else depends on having proper WINDOW* pointers:
1. **ncurses subwindows** -- creates WINDOW* for each panel
2. **80x24 layout** -- positions all panels correctly
3. **Fancy borders** -- wborder with ACS chars and color pairs
4. **Additional color pairs** -- enables all UI coloring
5. **ASCII art logo** -- string data + centered rendering
6. **Window titles** -- text over borders

### Phase 2: Scoring & Animation
Modern scoring is independent of visual layout; animations require subwindows from Phase 1:
1. **Level-multiplied scoring** -- trivial change to existing code
2. **Combo system** -- new state byte + scoring logic
3. **Soft/hard drop scoring** -- small additions to existing handlers
4. **Line clear animation** -- flash + delay before clear
5. **Back-to-back tracking** -- new flag + 1.5x bonus
6. **Snakes animation** -- simplest animation, proves the framework
7. **Game of Life animation** -- second simplest

### Phase 3: Advanced Features
Higher complexity features that can be deferred if timeline is tight:
1. **T-spin detection** -- corner checking + rotation tracking
2. **T-spin scoring** -- new score table, integrates with B2B
3. **Perfect clear detection** -- board-empty scan after line clear
4. **Fire animation** -- most complex (particle system + cooling map)
5. **Water animation** -- double-buffer wave simulation
6. **Hi-score file persistence** -- file I/O

### Defer
- T-spin Mini distinction (low value, high complexity)
- Menu animations (game animations sufficient)
- Profile system (out of scope)

---

## Complexity Estimates (Assembly-Specific)

Assembly inflation factor: each "feature" in C++ translates to roughly 5-15x more lines of assembly. These estimates account for that.

| Feature | C++ Lines | Est. ASM Lines | ASM Bytes | Key Challenge |
|---------|-----------|----------------|-----------|---------------|
| Subwindow creation (10 windows) | ~80 | ~300 | ~1.2KB | Managing 10 WINDOW* pointers in data segment; derwin parent-relative coords |
| Fancy borders | ~20 | ~80 | ~320B | Loading ACS constants (GOT-indirect on macOS); OR'ing with color pairs |
| Additional color pairs | ~15 | ~60 | ~240B | More init_pair calls in _init_colors |
| ASCII art logo | ~10 | ~80 | ~600B | 7 strings in data + loop to render each line |
| Line clear animation | ~15 | ~60 | ~240B | Mark rows with value 9, render, usleep(200000), then clear |
| Combo scoring | ~10 | ~40 | ~160B | New _combo_count byte, increment/reset logic, multiply |
| B2B bonus | ~10 | ~50 | ~200B | New _b2b_flag byte, conditional 1.5x multiply |
| T-spin detection | ~30 | ~150 | ~600B | 4 corner loads, count, rotation flag tracking |
| Perfect clear | ~10 | ~80 | ~320B | NEON board scan (reuse existing ld1/orr pattern) |
| Fire animation | ~100 | ~500 | ~2KB | 2D array management, cooling map, per-cell color selection |
| Water animation | ~60 | ~350 | ~1.4KB | Double buffer swap, 4-neighbor averaging |
| Snakes animation | ~40 | ~200 | ~800B | Dynamic list management (fixed-size array of structs) |
| Game of Life | ~50 | ~250 | ~1KB | 8-neighbor counting, birth/death rules |
| Hi-score file I/O | ~60 | ~200 | ~800B | getenv, string concat for path, open/read/write/close |
| **TOTAL** | **~500** | **~2,500** | **~10KB** | Binary size increase from 52KB to ~62KB |

---

## Sources

### Primary (HIGH confidence)
- yetris C++ source code (read directly): LayoutGame.cpp, Window.cpp, Board.cpp, Game.cpp, ScoreFile.cpp, Profile.cpp, AnimationFire.cpp, AnimationWater.cpp, AnimationSnakes.cpp, AnimationGameOfLife.cpp, Animation.hpp
- yetris assembly source (read directly): render.s, data.s, board.s, menu.s
- [Tetris Wiki: Scoring](https://tetris.wiki/Scoring) -- complete modern guideline scoring table
- [Tetris Wiki: T-Spin](https://tetris.wiki/T-Spin) -- 3-corner detection rules, mini vs. proper distinction

### Secondary (MEDIUM confidence)
- [ncurses derwin man page](https://linux.die.net/man/3/derwin) -- subwindow creation API
- [ncurses newwin man page](https://linux.die.net/man/3/newwin) -- window creation API
- [NCURSES Programming HOWTO: Windows](https://tldp.org/HOWTO/NCURSES-Programming-HOWTO/windows.html) -- window management patterns
- [Darwin ARM64 syscall conventions](https://dustin.schultz.io/mac-os-x-64-bit-assembly-system-calls.html) -- file I/O syscall numbers
- [HelloSilicon ARM64 macOS examples](https://github.com/below/HelloSilicon) -- assembly file I/O patterns

### Tertiary (LOW confidence -- verify before using)
- [Hard Drop Wiki: T-Spin Guide](https://harddrop.com/wiki/T-Spin_Guide) -- community T-spin strategy (confirms detection rules)
- [Tetris Fandom Wiki: Scoring](https://tetris.fandom.com/wiki/Scoring) -- cross-reference for scoring values

---

*Feature research for: yetris-asm v1.1 Visual Polish & Gameplay*
*Researched: 2026-02-27*
