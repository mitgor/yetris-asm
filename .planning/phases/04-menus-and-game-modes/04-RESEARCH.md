# Phase 4: Menus and Game Modes - Research

**Researched:** 2026-02-26
**Domain:** AArch64 assembly menu system (ncurses text menus, game state machine, starting level selection, game mode toggles)
**Confidence:** HIGH

## Summary

Phase 4 adds a menu system to the assembly Tetris game so it launches into a main menu instead of directly into gameplay. The C++ reference (`src/Game/States/GameStateMainMenu.cpp`) implements an elaborate menu hierarchy with submenus for single player options, game settings, GUI options, controls, and profiles. For the assembly version, the requirements (UI-01 through UI-04) call for a simplified subset: a main menu (start game, help, quit), a help screen showing keybindings, starting level selection (1-22), and game mode toggles (initial noise, invisible mode, ghost piece on/off, hold on/off).

The core architectural challenge is introducing a **game state machine** into the assembly binary. Currently, `_main` in `main.s` initializes ncurses and jumps directly into the game loop. Phase 4 requires an outer loop: main menu -> game -> back to menu. This means the game initialization and loop must become callable/restartable, and a new menu rendering + input system must be built. The ncurses infrastructure already in place (stdscr rendering via wmove+waddch, non-blocking wgetch input, color pairs) is sufficient for menu rendering -- no new libraries or ncurses features are needed.

The menu system itself is straightforward in assembly: render text strings at fixed screen positions, highlight the currently selected item, and dispatch arrow key UP/DOWN to move the selection cursor and ENTER to activate. Game mode settings are stored as new global variables in `data.s` and consulted at game start (to set initial level) and during gameplay (to enable/disable ghost piece rendering, hold piece functionality, and invisible mode). Initial noise requires a new `_add_noise` function in `board.s` that fills the bottom N rows with random blocks (at least one gap per row to prevent immediate line clears).

**Primary recommendation:** Structure the implementation in two plans: (1) Create the menu system (menu.s) with main menu, help screen, and game mode settings -- restructure main.s to have an outer state loop (MENU -> GAME -> MENU); (2) Implement game mode effects in-game (starting level, ghost/hold toggles, invisible mode, initial noise) and wire settings into the existing game loop. All menu state and game mode settings go in `data.s`. New rendering functions go in `render.s` (or a new `menu.s` if render.s becomes unwieldy). The existing game loop becomes a subroutine called from the menu state.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| UI-01 | Main menu with game options | The game needs a main menu screen displayed on launch with items: "Start Game", "Help", "Quit". Navigation via UP/DOWN arrow keys, selection via ENTER. The current `_main` function directly initializes and runs the game loop -- it must be restructured to have an outer state machine (MENU state -> GAME state -> back to MENU). Menu rendering uses existing ncurses primitives (wmove, waddch/waddstr, wattr_on for highlighting). The C++ reference uses a `Menu` class with `MenuItem` objects, but in assembly a simple index-based approach suffices: store `_menu_selection` (current highlighted item index), render items with the selected one highlighted via A_REVERSE (0x40000) or A_BOLD (0x200000), and dispatch ENTER to the corresponding action. |
| UI-02 | Help screen with keybinding reference | A full-screen text display showing all keybindings and controls. The C++ `WindowGameHelp` renders a two-tab window (Help + Credits) with keybinding labels and their assigned keys. For the assembly version: render a single page listing all key bindings (Left/Right/Down arrows, Up=rotate CW, z=rotate CCW, Space=hard drop, c=hold, p=pause, q/ESC=quit). The player returns to the main menu by pressing any key or ESC/ENTER. This is pure text rendering -- no new ncurses features needed. All keybinding strings are hardcoded (no configurable keybindings in v1). |
| UI-03 | Starting level selection (1-22) | A numeric selector on the menu screen allowing the player to choose starting level 1 through 22. The C++ reference uses `MenuItemNumberbox` for this. In assembly: add `_starting_level` (.word, default 1) to `data.s`. In the menu, LEFT/RIGHT keys increment/decrement the value (clamped to 1-22). On game start, copy `_starting_level` to `_level` in `_reset_board` (or a new `_start_game` initializer). The gravity delay table (`_gravity_delays`) is already indexed by level-1, so starting at a higher level immediately applies faster gravity. |
| UI-04 | Game mode options (initial noise, invisible mode, ghost/hold toggles) | Four configurable game mode settings: (1) **Initial noise** (0-20): number of garbage rows to place at bottom of board before game starts. Implemented as `_add_noise` in `board.s` -- for each noise row, fill bottom row with random blocks leaving at least 1 gap, then push existing rows up. Uses `_arc4random_uniform` for randomness. (2) **Invisible mode** (on/off): when enabled, locked pieces become invisible after a brief flash. In assembly: set locked board cells to 0 after rendering the lock, or use a special "invisible" cell value (e.g., 8) that renders as blank. The C++ reference flashes pieces visible for 500ms then hides for 3 seconds. (3) **Ghost piece on/off**: skip `_draw_ghost_piece` and `_compute_ghost_y` calls in `_render_frame` when disabled. (4) **Hold on/off**: skip `_hold_piece` call in `_handle_input` when disabled. All four settings stored as globals in `data.s`, toggled via menu LEFT/RIGHT keys before game start. |
</phase_requirements>

## Standard Stack

### Core

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Apple `as` (Clang integrated assembler) | clang 17.0.0 | Assemble `.s` files | Same as Phases 1-3 -- only assembler on macOS |
| Apple `ld` | ld-1230.1 | Link object files | Same as Phases 1-3 -- wildcard Makefile auto-includes new .s files |
| System ncurses | 5.4 (libncurses.tbd) | Terminal rendering, input, color | All needed primitives already proven: wmove, waddch, wattr_on, wgetch, wrefresh |
| `gettimeofday` (libSystem) | System | Timer for gravity + invisible mode flashing | Same as Phases 2-3 |
| `arc4random_uniform` (libSystem) | System | Random number generation for initial noise | Already used in random.s for 7-bag shuffle |
| GNU Make | System | Multi-file assembly build | `ASM_SOURCES = $(wildcard $(ASM_DIR)/*.s)` auto-includes new menu.s |

### Supporting

| Tool | Purpose | When to Use |
|------|---------|-------------|
| `waddstr` (ncurses) | Render C-strings directly (menu items, help text) | More efficient than character-by-character waddch for static text |
| `werase` / `wclear` (ncurses) | Clear screen between menu and game transitions | Already available via ncurses; `werase` preferred over `wclear` (avoids full terminal repaint flicker) |
| `curs_set(0)` (ncurses) | Hide cursor (already called in _init_colors) | Already in use -- no change needed |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Restructuring main.s as state machine | Separate binary entry points (menu binary + game binary) | A single binary with state machine is simpler to build, distribute, and maintain. Two binaries would require IPC or shared state which is far more complex in assembly. |
| waddstr for menu text | Character-by-character waddch (current approach) | waddstr takes a null-terminated C string pointer and renders the whole string in one call. Avoids needing one waddch per character. Since menu items are static strings, waddstr is the natural fit. The waddch approach still works but produces much larger code for multi-character strings. |
| A_REVERSE for menu highlight | A_BOLD or color pair swap | A_REVERSE (0x40000) inverts foreground/background, making the selected menu item clearly visible. A_BOLD just makes text brighter, which is less distinguishable. A_REVERSE is the standard ncurses convention for menu selection highlighting. |
| Storing game mode settings as individual bytes | Packing all settings into a single bitfield word | Individual bytes are simpler to read/write with `ldrb`/`strb` and match the existing pattern in data.s (e.g., `_is_paused`, `_can_hold`, `_game_over` are all individual bytes). Bitfield packing would save a few bytes of data but adds masking complexity. Save bitfield packing for Phase 5 optimization research. |

## Architecture Patterns

### Game State Machine (main.s restructuring)

The current main.s flow is linear:

```
_main -> init ncurses -> init game -> game loop -> game over -> cleanup -> exit
```

Phase 4 requires an outer state loop:

```
_main -> init ncurses -> STATE LOOP:
  if state == MENU:
    draw menu, handle menu input
    on "Start Game": apply settings, reset board, spawn piece, state = GAME
    on "Help": state = HELP
    on "Quit": break out of state loop
  if state == HELP:
    draw help screen, wait for key
    state = MENU
  if state == GAME:
    existing game loop (poll input, gravity, render)
    on game over + quit key: state = MENU
    on 'q'/ESC during game: state = MENU
-> cleanup -> exit
```

**Implementation:** A `_game_state` variable (.byte) in data.s with values:
- 0 = MENU
- 1 = GAME
- 2 = HELP

The outer loop in main.s checks `_game_state` and branches to the appropriate handler. The existing game loop becomes the GAME state handler, with `_game_over` or quit causing a transition back to MENU state.

### Menu Rendering Pattern

```
// Menu items as null-terminated strings in __TEXT,__const section
_menu_str_start: .asciz "Start Game"
_menu_str_help:  .asciz "Help"
_menu_str_quit:  .asciz "Quit"

// Menu item string address table
_menu_items:
    .quad _menu_str_start
    .quad _menu_str_help
    .quad _menu_str_quit

// Mutable state in __DATA section
_menu_selection: .byte 0    // currently highlighted item (0-2)

// Rendering: loop through items, highlight selected one
for item_index in 0..N:
    wmove(stdscr, start_row + item_index * 2, start_col)
    if item_index == _menu_selection:
        wattr_on(stdscr, A_REVERSE, NULL)  // highlight
    waddstr(stdscr, menu_items[item_index])
    if item_index == _menu_selection:
        wattr_off(stdscr, A_REVERSE, NULL)
```

### String Rendering Pattern

The codebase currently renders text character-by-character with `waddch`. For menus and help screens with many strings, using `waddstr` is more efficient:

```
// waddstr(WINDOW* win, const char* str) -- render null-terminated string
adrp    x8, _help_text@PAGE
add     x1, x8, _help_text@PAGEOFF    // x1 = &string
ldr     x0, [x19]                      // x0 = stdscr
bl      _waddstr
```

**String data layout:** All menu/help strings declared as `.asciz` (null-terminated) in `__TEXT,__const` section. Accessed via `adrp+add` since they are in the same binary.

### Game Mode Settings Variables (data.s additions)

```
// Menu/Game mode settings -- __DATA,__data section
_game_state:      .byte 0        // 0=MENU, 1=GAME, 2=HELP
_starting_level:  .word 1        // 1-22, default 1
_opt_ghost:       .byte 1        // ghost piece on/off, default on
_opt_hold:        .byte 1        // hold piece on/off, default on
_opt_invisible:   .byte 0        // invisible mode on/off, default off
_opt_noise:       .byte 0        // initial noise rows 0-20, default 0
_menu_selection:  .byte 0        // current menu cursor position
```

### Game Start Sequence (applying settings)

When the player selects "Start Game" from the menu:

1. Call `_reset_board` (zeros board, resets score/level/lines/stats/hold/pause)
2. Copy `_starting_level` to `_level` (overrides the default level=1 set by _reset_board)
3. Copy `_opt_ghost` to a runtime flag checked by `_render_frame` and `_draw_ghost_piece`
4. Copy `_opt_hold` to a runtime flag checked by `_handle_input` hold dispatch
5. If `_opt_noise > 0`: call `_add_noise(_opt_noise)` to fill bottom rows
6. Call `_spawn_piece` to get the first piece
7. Record initial `_last_drop_time`
8. Set `_game_state = 1` (GAME)

### Initial Noise Implementation (board.s)

```
// _add_noise(w0 = num_rows) -- fill bottom num_rows with random garbage
// For each noise row (bottom up):
//   1. Choose a random gap column: arc4random_uniform(10)
//   2. For each of 10 columns:
//      if col == gap: leave empty (0)
//      else: 50% chance of placing a block (arc4random_uniform(2))
//            if placing: set cell to random piece type+1 (arc4random_uniform(7)+1)
```

The C++ reference (`Board::pushUp` + `Board::addNoise`) pushes existing rows up and fills the bottom row. However, since noise is added to a fresh board (before any pieces are placed), we can fill bottom rows directly without push-up logic.

### Invisible Mode Implementation

The C++ reference uses a timer-based flash: pieces are visible for 500ms after locking, then hidden for 3 seconds, cycling. In assembly:

**Simplified approach:** When `_opt_invisible` is enabled, after `_lock_piece` completes, zero out the locked piece's cells in the board array (set them to 0). This makes locked pieces immediately invisible. The player only sees the active falling piece and the ghost (if enabled). This is simpler than the C++ flashing behavior but achieves the core gameplay effect.

**Full-featured approach (matching C++ reference):** Use a special cell value (e.g., 8 = invisible) in the board. After locking, start a 500ms timer. During the visible window, render cells normally. After 500ms, set all non-zero cells to value 8. In `_draw_board`, skip rendering cells with value 8 (treat them as empty visually but they still count for collision). Every 3 seconds, briefly set cells back to their original values (flash them visible) for 500ms.

**Recommendation:** Start with the simplified approach (immediately invisible after lock). It is much less code and still delivers a challenging gameplay mode. The flashing behavior is a visual nicety that can be added later if desired.

### Return to Menu from Game

When the game ends (game over + player presses q/ESC) or the player quits mid-game (q/ESC during play), transition back to the menu:

1. Set `_game_state = 0` (MENU)
2. Reset `_menu_selection = 0`
3. The outer state loop in main.s will redraw the menu on next iteration
4. Call `werase(stdscr)` to clear the game screen before drawing menu

The game over screen currently blocks waiting for 'q' or ESC. This behavior is preserved -- when the player presses q/ESC on the game over screen, instead of calling `_endwin` and exiting, we transition back to the menu state.

### Anti-Patterns to Avoid

- **Duplicating initialization logic:** Do NOT copy-paste the game init sequence from main.s into a menu handler. Factor game initialization into a callable `_start_game` function that both the initial startup (if needed) and menu "Start Game" action call.
- **Forgetting to clear screen on state transitions:** Transitioning from GAME to MENU without clearing leaves game board artifacts on the menu screen. Always call `werase(stdscr)` before entering a new state's render.
- **Hardcoding screen positions without constants:** Menu layout positions (row/column offsets) should be defined once (e.g., as .equ or comments) so they can be adjusted. Avoid scattering magic numbers across menu rendering code.
- **Blocking input in menu:** The menu must use the same non-blocking `wgetch` (via `wtimeout(16)`) as the game loop to maintain consistent frame pacing. Do NOT switch to blocking input for the menu -- it would prevent smooth screen updates if terminal resize or other events occur.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| String rendering | Character-by-character loops for every menu string | `waddstr` (ncurses) | Renders null-terminated C strings in one call; already linked via ncurses |
| Screen clearing on transitions | Manual byte-by-byte screen buffer clear | `werase(stdscr)` (ncurses) | Clears the window content without triggering a full terminal redraw |
| Random numbers for noise | Custom PRNG | `_arc4random_uniform` (libSystem) | Already used in random.s; cryptographically unbiased, no seeding needed |
| Number-to-string for level display | New integer rendering code | Existing `_draw_number` in render.s | The digit-rendering loop (stack buffer divide-by-10) already handles arbitrary integers |

**Key insight:** The menu system requires no new external dependencies. Every ncurses function needed (waddstr, werase, wattr_on/off with A_REVERSE) is already linked via libncurses. The only new assembly code is the state machine logic, menu rendering, help text rendering, and settings storage.

## Common Pitfalls

### Pitfall 1: Game state not fully reset between plays
**What goes wrong:** Player finishes a game, returns to menu, starts a new game, but old state (score, board, piece counts, hold piece, bag index) bleeds through.
**Why it happens:** `_reset_board` might not reset all state, or new settings variables (starting level, game modes) are not applied after reset.
**How to avoid:** Create a `_start_game` function that calls `_reset_board` (which already resets board, score, level, lines, game_over, hold, pause, stats) AND THEN applies menu settings (starting_level -> _level, noise, etc.). Verify the reset sequence covers every mutable variable in data.s.
**Warning signs:** Second game starts at the score/level from the first game; board has leftover blocks.

### Pitfall 2: Screen artifacts during state transitions
**What goes wrong:** Switching from game to menu shows remnants of the game board; switching from menu to game shows menu text overlapping the board.
**Why it happens:** ncurses buffers screen content. Without explicitly clearing, the old content persists.
**How to avoid:** Call `werase(stdscr)` (or `wclear(stdscr)`) at every state transition before drawing the new state's content. Prefer `werase` over `wclear` to avoid flicker.
**Warning signs:** Visual glitches on the first frame after transitioning between states.

### Pitfall 3: Gravity timer fires immediately after game start
**What goes wrong:** The first piece drops instantly or multiple rows when a new game begins, especially if the player spent time in the menu.
**Why it happens:** `_last_drop_time` was set during a previous game or before the menu was displayed. By the time the new game starts, the elapsed time far exceeds the gravity delay.
**How to avoid:** Set `_last_drop_time` to the current time (via `_get_time_ms`) as the LAST step of game initialization, after `_spawn_piece`. This is already done in the current main.s but must be preserved in the new `_start_game` function.
**Warning signs:** First piece locks immediately on game start.

### Pitfall 4: Menu input conflicts with game input
**What goes wrong:** Arrow keys have different meanings in menu (navigate items) vs game (move piece). If input handling is shared, menu navigation could trigger piece movement or vice versa.
**Why it happens:** Using the same `_handle_input` function for both states.
**How to avoid:** The state machine dispatches to different input handlers: `_handle_menu_input` in MENU state, existing `_handle_input` in GAME state. Never call game input handling from menu state or vice versa.
**Warning signs:** Pressing UP in the menu rotates a piece; pressing LEFT in the game scrolls the menu.

### Pitfall 5: waddstr requires null-terminated strings
**What goes wrong:** waddstr reads past the string data, printing garbage characters or crashing.
**Why it happens:** String literals defined with `.ascii` instead of `.asciz` (which appends the null terminator).
**How to avoid:** Always use `.asciz` for strings passed to `waddstr`. Alternatively, use `.ascii "text"` followed by `.byte 0` for explicit null termination.
**Warning signs:** Menu items render with trailing garbage characters.

### Pitfall 6: Invisible mode cell value collision
**What goes wrong:** Using cell value 0 for invisible cells causes the collision system to treat them as empty, allowing pieces to overlap invisible locked blocks.
**Why it happens:** `_is_piece_valid` treats 0 as empty. If invisible mode sets locked cells to 0, the collision detection breaks.
**How to avoid:** For the simplified approach (immediate invisibility), use a special cell value (e.g., 8) that `_is_piece_valid` still treats as occupied (any non-zero value) but `_draw_board` renders as empty/blank. This preserves collision integrity while hiding the visual representation.
**Warning signs:** In invisible mode, pieces stack on top of each other or fall through previously placed pieces.

## Code Examples

### Example 1: Menu rendering with waddstr and A_REVERSE highlighting

```asm
// Draw a single menu item at (row, col), highlighted if selected
// x19 = stdscr GOT pointer (already loaded)
// w20 = current item index
// w21 = _menu_selection value
// x22 = pointer to null-terminated string

    // wmove(stdscr, row, col)
    ldr     x0, [x19]
    mov     w1, w_row           // screen row
    mov     w2, w_col           // screen column
    bl      _wmove

    // If this item is selected, enable A_REVERSE
    cmp     w20, w21
    b.ne    Lskip_highlight_on

    // wattr_on(stdscr, A_REVERSE, NULL)
    // A_REVERSE = 0x40000 on macOS ncurses
    ldr     x0, [x19]
    mov     w1, #0x4            // 0x40000 = 0x4 << 16
    lsl     w1, w1, #16
    mov     x2, #0              // NULL (opts pointer)
    bl      _wattr_on

Lskip_highlight_on:
    // waddstr(stdscr, string)
    ldr     x0, [x19]
    mov     x1, x22             // pointer to menu string
    bl      _waddstr

    // If highlighted, turn off A_REVERSE
    cmp     w20, w21
    b.ne    Lskip_highlight_off

    ldr     x0, [x19]
    mov     w1, #0x4
    lsl     w1, w1, #16
    mov     x2, #0
    bl      _wattr_off

Lskip_highlight_off:
```

### Example 2: State machine outer loop skeleton

```asm
// In _main, after ncurses initialization:

Lstate_loop:
    // Load current game state
    adrp    x8, _game_state@PAGE
    ldrb    w9, [x8, _game_state@PAGEOFF]

    // Dispatch based on state
    cbz     w9, Lstate_menu         // state 0 = MENU
    cmp     w9, #1
    b.eq    Lstate_game             // state 1 = GAME
    cmp     w9, #2
    b.eq    Lstate_help             // state 2 = HELP
    b       Lstate_exit             // unknown state = exit

Lstate_menu:
    bl      _menu_frame             // render menu + handle input
    // _menu_frame sets _game_state to 1 (GAME), 2 (HELP), or 0xFF (QUIT)
    adrp    x8, _game_state@PAGE
    ldrb    w9, [x8, _game_state@PAGEOFF]
    cmp     w9, #0xFF
    b.eq    Lstate_exit
    b       Lstate_loop

Lstate_game:
    bl      _game_frame             // one iteration of existing game loop
    // _game_frame transitions to state 0 on game over + quit
    b       Lstate_loop

Lstate_help:
    bl      _help_frame             // render help + wait for key
    // _help_frame sets _game_state back to 0 (MENU)
    b       Lstate_loop

Lstate_exit:
    // Cleanup and exit...
```

### Example 3: Initial noise (add N garbage rows)

```asm
// _add_noise(w0 = num_rows)
// Fills bottom num_rows of board with random blocks, each row with at least 1 gap
// Precondition: board is empty (called after _reset_board, before _spawn_piece)

_add_noise:
    stp     x29, x30, [sp, #-64]!
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    mov     x29, sp

    mov     w19, w0                 // w19 = num_rows to fill
    cmp     w19, #20
    b.le    Lnoise_clamp_done
    mov     w19, #19                // clamp to 19 (leave at least 1 empty row)
Lnoise_clamp_done:

    adrp    x20, _board@PAGE
    add     x20, x20, _board@PAGEOFF  // x20 = board base

    // Fill rows from bottom (row 19) up to (20 - num_rows)
    mov     w21, #19                // w21 = current row (start at bottom)

Lnoise_row_loop:
    // Calculate how many rows we've filled
    mov     w8, #19
    sub     w8, w8, w21             // rows_filled = 19 - current_row
    cmp     w8, w19
    b.ge    Lnoise_done             // filled enough rows

    // Choose random gap column: arc4random_uniform(10)
    mov     w0, #10
    bl      _arc4random_uniform
    mov     w22, w0                 // w22 = gap column

    // Fill this row
    mov     w23, #0                 // w23 = col counter
Lnoise_col_loop:
    cmp     w23, w22
    b.eq    Lnoise_skip_col         // this is the gap column, leave empty

    // 50% chance of placing a block: arc4random_uniform(2)
    mov     w0, #2
    bl      _arc4random_uniform
    cbz     w0, Lnoise_skip_col     // 0 = no block

    // Place a block: random type 1-7 (arc4random_uniform(7) + 1)
    mov     w0, #7
    bl      _arc4random_uniform
    add     w0, w0, #1              // cell value 1-7

    // Store in board[row * 10 + col]
    mov     w8, #10
    mul     w8, w21, w8
    add     w8, w8, w23
    uxtw    x8, w8
    strb    w0, [x20, x8]
    b       Lnoise_next_col

Lnoise_skip_col:
    // Leave cell as 0 (empty)
Lnoise_next_col:
    add     w23, w23, #1
    cmp     w23, #10
    b.lt    Lnoise_col_loop

    sub     w21, w21, #1            // move up one row
    b       Lnoise_row_loop

Lnoise_done:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
```

### Example 4: ncurses A_REVERSE attribute value

```asm
// A_REVERSE on macOS ncurses = 0x40000 (262144)
// Construction: movz w1, #0x4, lsl #16  (same pattern used for A_DIM in Phase 3)
//
// Alternatively: mov w1, #0x40000 -- but this is NOT encodable as an ARM64
// logical immediate. Use movz with lsl instead.
//
// A_BOLD = 0x200000 -> movz w1, #0x20, lsl #16
// A_DIM  = 0x100000 -> movz w1, #0x10, lsl #16 (already verified in Phase 3)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Direct game entry (Phases 1-3) | State machine with MENU/GAME/HELP states | Phase 4 | Binary launches to menu instead of directly into game |
| All settings hardcoded | Runtime-configurable game mode settings | Phase 4 | Starting level, ghost, hold, invisible, noise are player-selectable |
| Game over exits program | Game over returns to menu | Phase 4 | Player can play multiple games without re-launching binary |

**Deprecated/outdated:**
- The current pattern of `_game_over` flag leading to program exit (wait for q, then `_endwin` + `ret`) is replaced by state transition back to menu.

## Open Questions

1. **Menu screen layout dimensions**
   - What we know: The game board occupies columns 0-21 and rows 0-21. The menu only needs text centered on screen.
   - What's unclear: Exact centering depends on terminal size. The game currently assumes an 80-column terminal (C++ reference uses 80x24).
   - Recommendation: Center menu text assuming 80x24 terminal (consistent with game layout assumptions). Use `getmaxy`/`getmaxx` if dynamic centering is desired, but hardcoded positions are simpler and match the game's approach.

2. **Game settings submenu vs flat menu**
   - What we know: The C++ reference has nested submenus (Main Menu -> Single Player -> settings). UI-01 through UI-04 require starting level and mode toggles.
   - What's unclear: Should settings be on a separate submenu screen, or inline on the main menu?
   - Recommendation: Use a single-screen approach with the main menu items at top (Start Game / Help / Quit) and settings below (Starting Level, Ghost, Hold, Invisible, Noise). This avoids submenu navigation complexity in assembly and fits on one 80x24 screen. The LEFT/RIGHT keys adjust settings for the selected item, ENTER activates menu actions.

3. **Invisible mode: simplified vs full C++ behavior**
   - What we know: C++ reference flashes pieces visible/invisible on a timer (500ms visible, 3s invisible). Simplified approach is immediate invisibility after lock.
   - What's unclear: Which approach the user prefers.
   - Recommendation: Implement simplified approach (immediate invisible after lock using cell value 8). Document the C++ flash behavior as a potential enhancement. The simplified version is functionally correct for the "invisible mode" requirement and avoids complex timer management for a secondary game mode.

## Sources

### Primary (HIGH confidence)
- C++ reference source: `src/Game/States/GameStateMainMenu.cpp` -- Full menu structure, item types, settings save/load
- C++ reference source: `src/Game/Display/WindowGameHelp.cpp` -- Help screen layout and keybinding display
- C++ reference source: `src/Game/Entities/Game.cpp` -- Game mode application (invisible, ghost, hold, noise, starting level)
- C++ reference source: `src/Game/Entities/Board.cpp` -- addNoise/pushUp implementation, turnInvisible behavior
- Assembly codebase: `asm/main.s`, `asm/render.s`, `asm/data.s`, `asm/input.s`, `asm/board.s`, `asm/piece.s` -- Current architecture, patterns, conventions
- Phase 3 research: `.planning/phases/03-gameplay-feature-completeness/03-RESEARCH.md` -- Established patterns for ncurses attribute construction (A_DIM), screen layout, data variable conventions

### Secondary (MEDIUM confidence)
- ncurses function signatures (waddstr, werase, wattr_on, wattr_off) -- from training knowledge, consistent with macOS system ncurses 5.4 behavior already verified in Phases 1-3
- A_REVERSE value (0x40000) -- consistent with ncurses header definitions and the same bit-shifting pattern used for verified A_DIM (0x100000) and A_BOLD (0x200000) values

### Tertiary (LOW confidence)
- None -- all findings verified against the codebase or consistent with previously verified patterns

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no new dependencies; all tools already proven in Phases 1-3
- Architecture: HIGH -- state machine pattern is well-understood; C++ reference provides exact menu structure to replicate; existing assembly patterns (adrp+add, callee-saved registers, stdscr rendering) are proven
- Pitfalls: HIGH -- identified from direct analysis of current code and C++ reference behavior; state reset, screen clearing, and collision integrity are concrete concerns with clear mitigations

**Research date:** 2026-02-26
**Valid until:** 2026-03-26 (stable -- no external dependencies to age)
