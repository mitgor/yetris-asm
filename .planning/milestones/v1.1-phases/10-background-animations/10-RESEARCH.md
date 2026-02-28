# Phase 10: Background Animations - Research

**Researched:** 2026-02-27
**Domain:** ASCII terminal animation algorithms in ARM64 assembly with ncurses rendering
**Confidence:** HIGH

## Summary

Phase 10 implements four animated backgrounds (fire, water, snakes, Game of Life) that run behind both the main menu and game board screens. The C++ original provides complete reference implementations for all four algorithms. Each animation operates on a 2D buffer matching the target window dimensions, updates at its own tick rate via timer comparison, and renders ASCII characters with color attributes through ncurses.

The key architectural challenge is integrating animation rendering into the existing subwindow hierarchy without disrupting the game loop's input responsiveness or frame timing. The animations draw into the parent/container window *before* child windows (logo, menu items, board, panels) are drawn on top. The existing `_render_frame` and `_menu_frame` functions already follow an erase-draw-refresh pattern that naturally supports this: the animation draws into the main/container window, then child windows overlay it.

**Primary recommendation:** Create a new `asm/animation.s` file containing all four animation algorithms, a dispatch table for random selection, shared timer/state variables, and two entry points (`_anim_update_and_draw_menu`, `_anim_update_and_draw_game`) called from `_menu_frame` and `_render_frame` respectively. Each animation uses a static `.bss`/`.data` buffer rather than heap allocation, since window dimensions are fixed at 80x24.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| ANIM-01 | Fire animation -- particle system with heat propagation, cooling map, ASCII grayscale, red/yellow/white colors, 100ms update rate | C++ `AnimationFire.cpp` provides exact algorithm: bottom-row heat spawn, upward propagation with cooling, intensity-to-color mapping. 12-char grayscale: ` .':-=+*#%@#`. Colors: red, redBold, yellow, yellowBold, white by intensity threshold. |
| ANIM-02 | Water animation -- double-buffer wave propagation, ripple simulation, blue/cyan/white colors, 300ms update rate | C++ `AnimationWater.cpp` provides exact algorithm: two int buffers, swap each tick, neighbor-average propagation `(left+right+up+down)/2 - current`, random ripple injection. Colors: blue, blueBold, cyan, cyanBold, white by height threshold. 11-char grayscale: `#@%#*+=-:'.` |
| ANIM-03 | Snakes animation -- falling green "snake" entities (head='@', body='o'), Matrix-style, 50ms update rate, max 50 snakes | C++ `AnimationSnakes.cpp`: struct array of {x, y, size}. Snakes fall 1 row per 50ms tick. New snakes added every 100-300ms. Random burst chance (25%). Head='@' green+bold, body='o' green. Max 50 snakes (requirement says 50, C++ says 100). Remove when fully off-screen. |
| ANIM-04 | Game of Life animation -- Conway's B3/S23 rules, yellow living cells, 200ms update rate | C++ `AnimationGameOfLife.cpp`: bool grid, B3/S23 rules (birth on 3 neighbors, survive on 2-3). Initial 20% random fill. Living cells draw as '#' in yellow. Edges excluded from update. |
| ANIM-05 | Random animation selection at startup for both menu background and game background | C++ uses `Utils::Random::between(0, 3)` to pick one of 4 animations. In asm: call `_arc4random_uniform(4)` once at startup, store selection byte `_anim_type` (0-3). Same animation used for both menu and game. |
| ANIM-06 | Animations run behind menu screen (below logo, behind menu window) | C++ `LayoutMainMenu::draw()`: animation draws into `animationContainer` (full width, below logo), then logo and menu overlay on top. In asm: draw into `_win_menu_main` before `_win_menu_logo` and `_win_menu_items` are refreshed. |
| ANIM-07 | Animations run behind game board during gameplay | C++ `LayoutGame::draw()`: animation draws into board window, then board cells overwrite non-empty positions. In asm: draw animation into `_win_main` (or `_win_board`) before board/piece drawing overlays it. |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ncurses | system (macOS) | Terminal rendering: `mvwaddch`, `wattr_on/off`, `wnoutrefresh`, color pairs | Already used throughout project; all animation output goes through ncurses |
| ARM64 assembly | AArch64 | Implementation language | Project is 100% assembly |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `_arc4random_uniform` | libc | Unbiased random numbers | Snake spawn positions, fire randomness, GoL initial state, animation selection |
| `_get_time_ms` (timer.s) | project | Millisecond timestamps for rate-limiting | Each animation's per-tick timer check |
| `_gettimeofday` | libc | Underlying timer | Already wrapped by project's timer.s |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Static buffers (80*24 bytes) | Heap allocation via `_malloc` | Static is simpler in asm, dimensions are compile-time constants (80x24), no free() needed |
| Single `animation.s` file | Separate files per animation | Single file reduces cross-file symbol management; all animations share common patterns |
| `int` buffers (4 bytes per cell) for fire/water | `byte` buffers (1 byte per cell) | Int matches C++ (intensity 0-100 range fits in a byte, but signed arithmetic during propagation can go negative temporarily). Use signed halfwords (16-bit) as a compromise -- fits in registers cleanly, avoids overflow, halves memory vs int. |

**No external installation needed** -- all dependencies are already present.

## Architecture Patterns

### Recommended Project Structure
```
asm/
├── animation.s      # NEW: All 4 animations + dispatch + shared state
├── data.s           # ADD: animation state variables, color pair constants
├── render.s         # MODIFY: _render_frame calls _anim_draw_game
├── menu.s           # MODIFY: _menu_frame calls _anim_draw_menu
├── layout.s         # MODIFY: _init_game_layout / _init_menu_layout call _anim_init
├── main.s           # MODIFY: startup calls _anim_select_random
└── (existing files unchanged)
```

### Pattern 1: Timer-Gated Update
**What:** Each animation checks elapsed time against its update rate before doing work
**When to use:** Every animation tick
**Example:**
```asm
// Check if enough time has elapsed for this animation's update rate
_anim_fire_update:
    stp     x29, x30, [sp, #-32]!
    stp     x19, x20, [sp, #16]
    mov     x29, sp

    bl      _get_time_ms                    // x0 = current ms
    mov     x19, x0                         // save current time
    adrp    x8, _anim_last_update@PAGE
    ldr     x9, [x8, _anim_last_update@PAGEOFF]
    sub     x10, x19, x9                    // elapsed = now - last
    cmp     x10, #100                       // fire rate = 100ms
    b.lt    Lfire_skip_update               // not time yet

    // ... do update logic ...

    // Reset timer
    adrp    x8, _anim_last_update@PAGE
    str     x19, [x8, _anim_last_update@PAGEOFF]

Lfire_skip_update:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
```

### Pattern 2: Animation Dispatch Table
**What:** Function pointer table indexed by `_anim_type` (0-3) for update+draw
**When to use:** Common entry points call the selected animation without branching
**Example:**
```asm
// In __DATA,__const section
.globl _anim_update_table
.p2align 3
_anim_update_table:
    .quad _anim_fire_update_and_draw
    .quad _anim_water_update_and_draw
    .quad _anim_snakes_update_and_draw
    .quad _anim_life_update_and_draw

// Dispatch: load _anim_type, index into table, call
_anim_dispatch:
    adrp    x8, _anim_type@PAGE
    ldrb    w9, [x8, _anim_type@PAGEOFF]
    adrp    x8, _anim_update_table@PAGE
    add     x8, x8, _anim_update_table@PAGEOFF
    ldr     x10, [x8, x9, lsl #3]          // function pointer
    br      x10                             // tail call
```

### Pattern 3: Background Drawing Into Parent Window
**What:** Animation renders into the parent container window; child subwindows overlay on top
**When to use:** Both menu and game screens
**Detail for menu:**
```
1. werase _win_menu_main          (clear parent)
2. _anim_draw_menu(_win_menu_main) (draw animation chars into parent)
3. wnoutrefresh _win_menu_main    (mark parent dirty)
4. werase + draw + wnoutrefresh _win_menu_logo   (logo overlays)
5. werase + draw + wnoutrefresh _win_menu_items  (menu overlays)
6. doupdate                        (single terminal flush)
```
**Detail for game:**
```
1. werase _win_main               (clear parent -- already done in _render_frame)
2. _anim_draw_game(_win_main)     (draw animation into main window background)
3. wnoutrefresh _win_main         (already done in _render_frame)
4. ... existing panel/board drawing overlays animation ...
5. doupdate
```

### Pattern 4: Static Buffer Allocation
**What:** Pre-allocate animation buffers in `.data`/`.bss` section at fixed 80x24 dimensions
**When to use:** All animations that need per-cell state (fire, water, GoL)
**Example:**
```asm
// In data.s __DATA,__data section
.globl _anim_buf1
.p2align 2
_anim_buf1: .space 3840, 0    // 80 * 24 * 2 bytes (halfword per cell for fire/water)

.globl _anim_buf2
_anim_buf2: .space 3840, 0    // second buffer for water double-buffer / GoL next-gen

// Snakes: fixed-size struct array
// Each snake = 4 bytes: x(byte) + y(signed byte) + size(byte) + padding(byte) = 4 bytes
.globl _anim_snakes
_anim_snakes: .space 200, 0   // 50 snakes * 4 bytes each

.globl _anim_snake_count
_anim_snake_count: .byte 0
```

### Anti-Patterns to Avoid
- **Drawing animation into child subwindows directly:** The animation must draw into the parent (`_win_main` or `_win_menu_main`). Drawing into `_win_board` would mean board cells and animation compete in the same window -- the C++ version for game draws animation into the board window and then overwrites with board cells, but our asm architecture erases children separately. Drawing into `_win_main` lets subwindows naturally overlay.
- **Heap allocation in assembly:** `_malloc`/`_free` adds complexity and error potential. All buffer sizes are known at compile time (80*24).
- **Updating animation state in the draw function:** Keep update (state mutation) and draw (rendering) separate as in C++. This makes it easy to skip update while still drawing if the timer hasn't elapsed.
- **Using `wrefresh` instead of `wnoutrefresh`:** The project already uses batched `wnoutrefresh` + single `doupdate`. Animation rendering must follow this pattern.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Random numbers | Custom PRNG | `_arc4random_uniform` | Already used in random.s; unbiased, no seeding |
| Millisecond timing | Raw `mach_absolute_time` conversion | `_get_time_ms` from timer.s | Already tested, handles gettimeofday correctly |
| Color pair setup | New init_pair calls per animation | Reuse existing color pairs 1-11 | Pairs 1(yellow), 2(cyan), 3(white), 4(blue), 5(green), 6(red) already cover all animation colors |
| ncurses window management | New window creation | Draw into existing `_win_main` / `_win_menu_main` | Parent windows already exist; no new windows needed |

**Key insight:** The existing color pairs cover nearly all animation needs. Fire uses red(6), yellow(1), white(3). Water uses blue(4), cyan(2/10), white(3). Snakes uses green(5). GoL uses yellow(1). The only potentially missing pair is "blue+bold" which can be achieved with COLOR_PAIR(4)|A_BOLD. All existing pairs use black background, which is correct for animations.

## Common Pitfalls

### Pitfall 1: Animation Buffer Dimensions Mismatch
**What goes wrong:** Animation assumes wrong width/height, causing out-of-bounds writes or visual artifacts
**Why it happens:** The animation draws into the 80x24 parent window but different windows have different addressable areas
**How to avoid:** For menu: draw into `_win_menu_main` which is 80x24 (full area). For game: draw into `_win_main` which is also 80x24. Use constants (80 cols, 24 rows) throughout. The C++ version passes `window->getW()` and `window->getH()` -- in asm these are compile-time constants.
**Warning signs:** Characters appearing at wrong positions, crashes from buffer overrun

### Pitfall 2: Signed Arithmetic Overflow in Fire/Water Propagation
**What goes wrong:** Fire intensity goes negative during cooling; water height goes negative during propagation
**Why it happens:** C++ uses `int` (32-bit signed) naturally handling negatives. In asm with byte buffers, subtraction wraps unsigned.
**How to avoid:** Use signed halfwords (16-bit, `ldrsh`/`strh`) for fire intensity and water height buffers. Clamp values after subtraction: `cmp x, #0; csel x, xzr, x, lt` (clamp to 0 if negative). Fire intensities range 0-100, water heights 0-100 -- both fit comfortably in signed 16-bit.
**Warning signs:** Sudden bright flashes where dark areas should be (unsigned wrap of negative to large positive)

### Pitfall 3: Animation Slowing Down Game Input
**What goes wrong:** Animation update takes too long, causing input lag or dropped keys
**Why it happens:** Full 80x24 buffer iteration (1920 cells) with per-cell ncurses calls is expensive
**How to avoid:** The animation update is O(width*height) = O(1920) per tick, with ticks rate-limited to 50-300ms. The game loop polls input every 16ms (wtimeout). Since animation update only runs on its own timer (not every frame), the amortized cost is small. Draw only non-empty cells (fire/water skip low-intensity, GoL skips dead cells) to minimize ncurses calls. Use `mvwaddch` which combines wmove+waddch.
**Warning signs:** Visible stutter when animation update coincides with game frame

### Pitfall 4: ncurses Subwindow Refresh Ordering
**What goes wrong:** Animation draws into parent but child window refresh clobbers it, or animation bleeds through child windows
**Why it happens:** ncurses subwindow refresh ordering is critical (documented in Phase 6 blockers)
**How to avoid:** The existing pattern already handles this: erase parent -> draw parent (animation here) -> wnoutrefresh parent -> erase child -> draw child -> wnoutrefresh child -> doupdate. Animation inserts between "erase parent" and "wnoutrefresh parent". Subwindows automatically overlay.
**Warning signs:** Animation characters visible inside bordered panels, flickering

### Pitfall 5: Game of Life Updating In-Place
**What goes wrong:** GoL rules read neighbors that have already been updated this generation, producing incorrect evolution
**Why it happens:** Reading and writing the same buffer during update
**How to avoid:** Use double-buffering: read from buf1, write to buf2, then swap pointers (or just swap which is "current"). The C++ code appears to update in-place (which is technically a bug in the C++ original), but for visual aesthetics it doesn't matter much. For correctness, use two buffers and swap.
**Warning signs:** GoL patterns don't match expected behavior (blinkers don't blink correctly)

### Pitfall 6: Snake Removal Creating Gaps in Array
**What goes wrong:** Removing a dead snake from the middle of the array leaves a hole or requires expensive shifting
**Why it happens:** Fixed array with count-based tracking
**How to avoid:** Use swap-with-last removal: when snake[i] is dead, copy snake[count-1] to snake[i], decrement count. This is O(1) and maintains a compact array. The C++ version uses `std::vector::erase` which does the shifting automatically.
**Warning signs:** Ghost snakes, incorrect snake count, array corruption

## Code Examples

### Fire Animation Update Core (Pseudocode -> ASM Pattern)
```asm
// Propagate heat upward: for each cell (col, row) where row < height-1:
//   intensity[col][row] = intensity[col][row+1] - cooling_ratio - coolingMap[col][row]
//   clamp to 0 if negative

// Bottom row: set to random high intensity (90-100)
// Sparks: randomly inject high intensity at rows 3-6 from bottom

// Register plan for inner loop:
//   x19 = buffer base
//   x20 = cooling_map base
//   w21 = cooling_ratio (random 3-12% of 100)
//   w22 = row counter
//   w23 = col counter
//   w24 = width (80)
//   w25 = height (24)
```

### Water Animation Double-Buffer Swap
```asm
// Swap buffer pointers (or swap a flag byte)
// For each interior cell (1..width-2, 1..height-2):
//   new[x][y] = ((old[x-1][y] + old[x+1][y] + old[x][y-1] + old[x][y+1]) >> 1) - new[x][y]
//   clamp to [0, 100]

// Random ripple: 0.31% chance -> inject 90 at random position
```

### Drawing a Single Animation Cell
```asm
// Given: x0 = WINDOW*, w1 = row, w2 = col, w3 = char, w4 = color_pair_attr
// Apply color attribute
mov     x0, x19                     // WINDOW*
mov     w1, w4                      // COLOR_PAIR(n) | A_BOLD
mov     x2, #0                      // NULL (opts)
bl      _wattr_on

// Move and draw character
mov     x0, x19                     // WINDOW*
mov     w1, w22                     // row
mov     w2, w23                     // col
mov     w3, w26                     // character
// Use mvwaddch: combined wmove+waddch
bl      _mvwaddch

// Turn off attribute
mov     x0, x19
mov     w1, w4
mov     x2, #0
bl      _wattr_off
```

### Random Animation Selection at Startup
```asm
_anim_select_random:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    mov     w0, #4                      // 4 animation types
    bl      _arc4random_uniform         // w0 = 0-3
    adrp    x8, _anim_type@PAGE
    strb    w0, [x8, _anim_type@PAGEOFF]

    ldp     x29, x30, [sp], #16
    ret
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| C++ virtual dispatch for animations | Assembly function pointer dispatch table | This phase | Eliminates vtable overhead; direct jump via table lookup |
| Heap-allocated 2D arrays (Array2D class) | Static .data section buffers | This phase | Zero allocation overhead; fixed 80x24 dimensions known at compile time |
| C++ `std::vector` for snake list | Fixed-capacity array with count | This phase | Bounded memory, O(1) removal via swap-with-last |

## Open Questions

1. **Animation in game: draw into `_win_main` or `_win_board`?**
   - What we know: C++ draws animation into the board window, then board cells overwrite. In our asm architecture, `_win_board` is a derwin of `_win_middle_left` which is a derwin of `_win_main`. Drawing animation into `_win_main` at the board's coordinates would work since child windows overlay. Drawing into `_win_board` directly would also work but requires the animation to use board-relative coordinates.
   - What's unclear: Which approach produces cleaner rendering without artifacts.
   - Recommendation: Draw animation into `_win_main` for both menu and game. For game, the animation fills the full 80x24 area (same as menu). Subwindows with their own content naturally overlay. This is simpler (one target window) and matches the menu pattern.

2. **Color pair reuse vs. new pairs**
   - What we know: Existing pairs 1-7 cover yellow, cyan, white, blue, green, red, magenta. Pairs 8-11 cover dim, hilite, textbox. Fire needs red+bold (pair 6 + A_BOLD), water needs blue+bold (pair 4 + A_BOLD). Both achievable with existing pairs + A_BOLD flag.
   - What's unclear: Whether any animation needs a color pair not achievable with existing 11 pairs + attribute flags.
   - Recommendation: No new color pairs needed. Use existing pairs with A_BOLD for "bold" variants. Verify during implementation.

3. **GoL in-place vs. double-buffer**
   - What we know: C++ updates in-place (technically incorrect for GoL). Memory cost of second buffer is 80*24 = 1920 bytes (or 3840 bytes if using halfwords).
   - What's unclear: Whether visual difference matters for a background animation.
   - Recommendation: Use double-buffer for correctness -- the memory cost (1920 bytes for a bool/byte grid) is negligible, and swap-with-last pattern is trivial. Fire already needs one buffer + cooling map. Water needs two buffers. GoL can share the second buffer slot since only one animation runs at a time.

4. **Buffer sharing across animations**
   - What we know: Only one animation runs at any time. Fire needs: intensity buffer (80*24*2=3840 bytes) + cooling map (80*24*2=3840 bytes). Water needs: two int buffers (80*24*2=3840 bytes each). GoL needs: two bool buffers (80*24=1920 bytes each, can use the halfword buffers). Snakes needs: struct array (50*4=200 bytes).
   - Recommendation: Allocate two halfword buffers (`_anim_buf1`, `_anim_buf2`, 3840 bytes each = 7680 total) shared by all animations. Plus the snake struct array (200 bytes) and snake count (1 byte). Total static memory: ~7881 bytes. Each animation reuses the same buffers for different purposes since they never run simultaneously.

## Data Requirements Summary

### New Data Variables (in data.s)
```
_anim_type:           .byte 0         // 0=fire, 1=water, 2=snakes, 3=life
_anim_last_update:    .quad 0         // ms timestamp of last update
_anim_last_add:       .quad 0         // ms timestamp for snake add timer
_anim_snake_count:    .byte 0         // current number of active snakes
_anim_buf1:           .space 3840, 0  // 80*24 halfwords -- primary buffer
_anim_buf2:           .space 3840, 0  // 80*24 halfwords -- secondary buffer
_anim_snakes:         .space 200, 0   // 50 snakes * 4 bytes each
```

### New Color Pairs Needed
None -- all animation colors achievable with existing pairs 1-7 plus A_BOLD attribute flag.

### Existing Color Pair Mapping for Animations
| Animation | Color | Pair | Attribute | Combined |
|-----------|-------|------|-----------|----------|
| Fire | red | 6 | none | COLOR_PAIR(6) |
| Fire | red bold | 6 | A_BOLD | COLOR_PAIR(6)\|A_BOLD |
| Fire | yellow | 1 | none | COLOR_PAIR(1) |
| Fire | yellow bold | 1 | A_BOLD | COLOR_PAIR(1)\|A_BOLD |
| Fire | white | 3 | A_BOLD | COLOR_PAIR(3)\|A_BOLD |
| Water | blue | 4 | none | COLOR_PAIR(4) |
| Water | blue bold | 4 | A_BOLD | COLOR_PAIR(4)\|A_BOLD |
| Water | cyan | 2 | none | COLOR_PAIR(2) |
| Water | cyan bold | 2 | A_BOLD | COLOR_PAIR(2)\|A_BOLD |
| Water | white | 3 | A_BOLD | COLOR_PAIR(3)\|A_BOLD |
| Snakes | green | 5 | none | COLOR_PAIR(5) |
| Snakes | green bold | 5 | A_BOLD | COLOR_PAIR(5)\|A_BOLD |
| GoL | yellow | 1 | none | COLOR_PAIR(1) |

## Algorithm Summaries (from C++ Reference)

### Fire Algorithm
1. **Init:** Allocate intensity buffer (80x24 halfwords, all 0). Create cooling map: random values 0-13, smoothed 10 times (neighbor average).
2. **Update (every 100ms):**
   - Pick cooling_ratio = random(3, 12). 10% chance burst (ratio=1), 12% chance dim (ratio=30).
   - Bottom row: set to random(90, 100).
   - Sparks: for each column, 2.31% chance to inject random(90,100) at height-random(3,6).
   - Propagate: for row 0 to height-2: `cell[col][row] = cell[col][row+1] - cooling_ratio - coolingMap[col][row]`. Clamp >= 0.
3. **Draw:** For each cell with intensity > 20: map intensity to grayscale char ` .':-=+*#%@#`, apply color by intensity range. Skip cells with intensity <= 20.

### Water Algorithm
1. **Init:** Allocate two halfword buffers (80x24). Fill with random low values (buf1: 0-13, buf2: 0-25).
2. **Update (every 300ms):**
   - Swap buf1 and buf2 pointers.
   - 0.31% chance: inject 90 at random position.
   - For interior cells (1..w-2, 1..h-2): `buf2[x][y] = ((buf1[x-1][y] + buf1[x+1][y] + buf1[x][y-1] + buf1[x][y+1]) >> 1) - buf2[x][y]`. Clamp to [0, 100].
3. **Draw:** For each cell: map height to grayscale char `#@%#*+=-:'.`, apply color by height range (>80=white, >60=cyanBold, >40=cyan, >20=blue, else blueBold). Skip out-of-range.

### Snakes Algorithm
1. **Init:** Add one initial snake. Start both timers.
2. **Update:**
   - Add timer (every 100-300ms random): add new snake at random x (1..w-1), y (0..3), size (2..14). 25% chance burst: add 3-5 extra snakes. Cap at 50 total.
   - Move timer (every 50ms): increment y for all snakes. Remove if (y - size) > window_height.
3. **Draw:** For each snake: draw '@' (green bold) at (x, y) for head. Draw 'o' (green) at (x, y-1) through (x, y-size+1) for body. Skip off-screen positions (y < 0 or y >= height).

### Game of Life Algorithm
1. **Init:** Allocate two bool buffers (80x24 bytes). Fill current with 20% random true.
2. **Update (every 200ms):** For interior cells (1..w-2, 1..h-2): count 8 neighbors. If alive: survive if 2-3 neighbors, die otherwise. If dead: born if exactly 3 neighbors. Write to next buffer, then swap.
3. **Draw:** For each cell: if alive draw '#' (yellow), else draw ' ' (space).

## Sources

### Primary (HIGH confidence)
- C++ source: `deps/Engine/Graphics/Animation/AnimationFire.cpp` -- exact fire algorithm
- C++ source: `deps/Engine/Graphics/Animation/AnimationWater.cpp` -- exact water algorithm
- C++ source: `deps/Engine/Graphics/Animation/AnimationSnakes.cpp` -- exact snakes algorithm
- C++ source: `deps/Engine/Graphics/Animation/AnimationGameOfLife.cpp` -- exact GoL algorithm
- C++ source: `src/Game/Display/Layouts/LayoutGame.cpp` -- game animation integration (draw before board)
- C++ source: `src/Game/Display/Layouts/LayoutMainMenu.cpp` -- menu animation integration (animationContainer)
- ASM source: `asm/render.s` -- existing _render_frame pattern (erase-draw-refresh)
- ASM source: `asm/menu.s` -- existing _menu_frame pattern
- ASM source: `asm/layout.s` -- window hierarchy and dimensions
- ASM source: `asm/data.s` -- existing color pairs, data layout patterns

### Secondary (MEDIUM confidence)
- ncurses documentation: `mvwaddch`, `wattr_on`, `wnoutrefresh` -- standard ncurses API, well-documented

### Tertiary (LOW confidence)
- None -- all findings based on actual project source code

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all tools already in the project (ncurses, arc4random, get_time_ms)
- Architecture: HIGH -- C++ reference provides exact algorithms; asm patterns well-established from phases 6-9
- Pitfalls: HIGH -- identified from direct code analysis and project history (subwindow refresh ordering documented as Phase 6 blocker)

**Research date:** 2026-02-27
**Valid until:** Indefinite -- based on project source code, not external dependencies
