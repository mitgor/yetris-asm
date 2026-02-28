# Phase 6: Subwindow Foundation - Research

**Researched:** 2026-02-27
**Domain:** ncurses subwindow management in AArch64 assembly
**Confidence:** HIGH

## Summary

Phase 6 replaces the current stdscr-only rendering with a hierarchy of ncurses subwindows that match the C++ original's 80x24 panel layout exactly. The current v1.0 assembly draws everything (board, score, hold, next, stats) directly onto stdscr at hardcoded absolute coordinates (board at col 0, panels at cols 23 and 34). The C++ original uses `newwin` for the main container and `derwin` for child subwindows, with each panel as a separate WINDOW* that can be independently cleared, drawn, and refreshed. The v1.1 assembly must adopt this same pattern.

The central challenge is the ncurses refresh ordering protocol. The C++ codebase (Window.cpp line 116) already uses `wnoutrefresh` for all individual windows and calls `refresh()` (which invokes `doupdate()`) once at the end of each draw cycle. The assembly must follow this same pattern: erase each window, draw content, call `wnoutrefresh` for each, then `doupdate` once. Getting this wrong causes visual artifacts -- stale content from parent windows bleeding through child windows.

**Primary recommendation:** Create WINDOW* pointers in data.s for each panel (main, leftmost, hold, score, middle_left, board, middle_right, rightmost, pause), initialize them in a new `_init_layout` function called once at startup, then convert all render functions to draw on their respective WINDOW* instead of stdscr. Use `derwin` for child windows (not `subwin`) because `derwin` uses parent-relative coordinates, matching the C++ original exactly.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| LAYOUT-01 | Game screen uses ncurses subwindows (newwin/derwin) instead of direct stdscr drawing | Core architecture change: create WINDOW* hierarchy, convert all wmove/waddch calls from stdscr to panel-specific windows. See Architecture Patterns section for exact window creation sequence. |
| LAYOUT-02 | Game layout matches C++ original's 80x24 grid with exact panel column positions (leftmost=12w, board=22w, middle_right=10w, rightmost=fills) | Column positions derived from C++ LayoutGame.cpp: leftmost at x=0 w=12, middle_left at x=12 w=22, middle_right at x=34 w=10, rightmost at x=44 w=35. See Code Examples section for exact geometry. |
| LAYOUT-03 | Hold panel displays in leftmost window (4 rows high, titled "Hold") | Hold window created as derwin of leftmost: x=0, y=0, w=12, h=4. Title rendering is Phase 7 (VISUAL-03), but panel geometry and "Hold" text position established here. |
| LAYOUT-04 | Score panel displays Hi-Score, Score, and Level in leftmost window below Hold | Score window created as derwin of leftmost: x=0, y=4, w=12, h=remaining. Labels at relative positions within the window. Hi-Score label placed; value is "0" until Phase 11 implements persistence. |
| LAYOUT-05 | Next piece panel displays in middle-right window (titled "Next") | Middle-right window at x=34, y=0, w=10, h=4 (single next piece). Next piece drawn using window-relative coordinates instead of absolute col 23. |
| LAYOUT-06 | Statistics panel displays in rightmost window with piece counts, line clear counts, timer, and version string (titled "Statistics") | Rightmost window at x=44, y=0, w=35, h=24. All stats drawn using window-relative coordinates. Timer requires elapsed-time tracking (reuse existing _get_time_ms with game-start timestamp). |
| LAYOUT-07 | Menu screen uses ncurses subwindows with logo window and menu window matching C++ layout | Menu layout: logo window at y=0, h=9; menu window centered at x=main_w/3-2, y=10, w=main_w/3+2, h=remaining. Animation container prepared for Phase 10. |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ncurses | System (macOS) | Terminal UI windowing | Only dependency; provides newwin/derwin/wnoutrefresh/doupdate |
| Apple `as` + `ld` | Xcode CLT | Assembly + linking | Project toolchain from v1.0 |

### Supporting
No additional libraries needed. All subwindow management uses ncurses functions already linked.

### ncurses Functions Required (New for Phase 6)
| Function | Signature | Purpose |
|----------|-----------|---------|
| `newwin` | `WINDOW* newwin(int nlines, int ncols, int begin_y, int begin_x)` | Create top-level windows (main game, main menu) |
| `derwin` | `WINDOW* derwin(WINDOW* orig, int nlines, int ncols, int begin_y, int begin_x)` | Create child subwindows with parent-relative coordinates |
| `delwin` | `int delwin(WINDOW* win)` | Destroy windows on screen transitions |
| `wnoutrefresh` | `int wnoutrefresh(WINDOW* win)` | Mark window for batch refresh (no immediate terminal I/O) |
| `doupdate` | `int doupdate(void)` | Flush all wnoutrefresh changes to terminal in one write |
| `werase` | `int werase(WINDOW* win)` | Clear window content (already used on stdscr) |
| `wmove` | `int wmove(WINDOW* win, int y, int x)` | Position cursor (already used with stdscr) |
| `waddch` | `int waddch(WINDOW* win, chtype ch)` | Draw character (already used with stdscr) |
| `waddstr` | `int waddstr(WINDOW* win, const char* str)` | Draw string (already used with stdscr) |
| `wattr_on` | `int wattr_on(WINDOW* win, attr_t attrs, void* opts)` | Enable attribute (already used with stdscr) |
| `wattr_off` | `int wattr_off(WINDOW* win, attr_t attrs, void* opts)` | Disable attribute (already used with stdscr) |
| `wrefresh` | `int wrefresh(WINDOW* win)` | Immediate refresh (keep for menu/help screens) |
| `keypad` | `int keypad(WINDOW* win, bool bf)` | Enable arrow keys on a window |
| `wtimeout` | `void wtimeout(WINDOW* win, int delay)` | Set non-blocking input on a window |
| `wgetch` | `int wgetch(WINDOW* win)` | Read input from a window |

### Functions NOT Needed
| Function | Why Not |
|----------|---------|
| `subwin` | Uses absolute screen coordinates; `derwin` uses parent-relative (matches C++ pattern) |
| `subpad` / `newpad` | Pads are for scrollable content; not needed for fixed 80x24 layout |
| `mvderwin` | Moving subwindows at runtime not needed; positions are fixed |
| `panel.h` | ncurses panel library handles overlapping windows; our windows don't overlap (except pause) |

## Architecture Patterns

### Recommended Data Layout Changes

```
// New in data.s: WINDOW* pointers for all panels
.section __DATA,__data

// Game screen windows (set by _init_game_layout, cleared by _destroy_game_layout)
.globl _win_main
_win_main:          .quad 0     // newwin(24, 80, 0, 0) -- top-level game container
.globl _win_leftmost
_win_leftmost:      .quad 0     // derwin(main, 24, 12, 0, 0) -- left column container
.globl _win_hold
_win_hold:          .quad 0     // derwin(leftmost, 4, 12, 0, 0) -- hold piece
.globl _win_score
_win_score:         .quad 0     // derwin(leftmost, 20, 12, 4, 0) -- score display
.globl _win_middle_left
_win_middle_left:   .quad 0     // derwin(main, 22, 22, 0, 12) -- board container
.globl _win_board
_win_board:         .quad 0     // derwin(middle_left, 22, 22, 0, 0) -- board content
.globl _win_middle_right
_win_middle_right:  .quad 0     // derwin(main, 4, 10, 0, 34) -- next piece
.globl _win_rightmost
_win_rightmost:     .quad 0     // derwin(main, 24, 35, 0, 44) -- statistics
.globl _win_pause
_win_pause:         .quad 0     // derwin(main, 6, 40, 11, 20) -- pause overlay

// Menu screen windows (set by _init_menu_layout, cleared by _destroy_menu_layout)
.globl _win_menu_main
_win_menu_main:     .quad 0     // newwin(24, 80, 0, 0) -- top-level menu container
.globl _win_menu_logo
_win_menu_logo:     .quad 0     // derwin(menu_main, 9, 80, 0, 0) -- logo area
.globl _win_menu_items
_win_menu_items:    .quad 0     // derwin(menu_main, 13, 30, 10, 25) -- menu items

// Elapsed game time tracking (for statistics timer)
.globl _game_start_time
_game_start_time:   .quad 0     // ms timestamp when game started
```

### Pattern 1: Window Creation Sequence
**What:** Create the full window hierarchy using newwin for the root, derwin for children.
**When to use:** At game-start transition (MENU -> GAME) and at menu entry.

```asm
// _init_game_layout: Create all game subwindows
// Called once when transitioning from MENU to GAME state
// Must be called AFTER initscr (stdscr already exists)
_init_game_layout:
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    // 1. Create main window: newwin(24, 80, 0, 0)
    mov w0, #24         // nlines
    mov w1, #80         // ncols
    mov w2, #0          // begin_y
    mov w3, #0          // begin_x
    bl  _newwin
    adrp x8, _win_main@PAGE
    str  x0, [x8, _win_main@PAGEOFF]
    mov  x19, x0        // save main WINDOW*

    // 2. Create leftmost: derwin(main, 24, 12, 0, 0)
    mov x0, x19         // parent = main
    mov w1, #24         // nlines (full height)
    mov w2, #12         // ncols (4*2+2+2)
    mov w3, #0          // begin_y
    mov w4, #0          // begin_x
    bl  _derwin
    adrp x8, _win_leftmost@PAGE
    str  x0, [x8, _win_leftmost@PAGEOFF]
    mov  x20, x0        // save leftmost

    // 3. Create hold: derwin(leftmost, 4, 12, 0, 0)
    mov x0, x20         // parent = leftmost
    mov w1, #4
    mov w2, #12
    mov w3, #0
    mov w4, #0
    bl  _derwin
    adrp x8, _win_hold@PAGE
    str  x0, [x8, _win_hold@PAGEOFF]

    // 4. Create score: derwin(leftmost, 20, 12, 4, 0)
    mov x0, x20         // parent = leftmost
    mov w1, #20
    mov w2, #12
    mov w3, #4          // y = below hold
    mov w4, #0
    bl  _derwin
    adrp x8, _win_score@PAGE
    str  x0, [x8, _win_score@PAGEOFF]

    // ... continue for all windows
    ldp x29, x30, [sp], #16
    ret
```

### Pattern 2: Rendering with Subwindows (Refresh Protocol)
**What:** Draw each panel into its own WINDOW*, then batch-flush to terminal.
**When to use:** Every game frame render cycle.

The C++ code follows this exact sequence in LayoutGame::draw():
1. Clear and wnoutrefresh all container windows (main, leftmost, middle_left, middle_right, rightmost)
2. Clear and draw content into each leaf window (hold, score, board, next, rightmost)
3. wnoutrefresh each leaf window
4. Call refresh() which triggers doupdate()

```asm
// Updated _render_frame using subwindows:
_render_frame:
    // 1. Clear + refresh containers (parent before child)
    //    This prevents stale parent content from showing through
    ldr x0, [_win_main]
    bl  _werase
    ldr x0, [_win_main]
    bl  _wnoutrefresh

    ldr x0, [_win_leftmost]
    bl  _werase
    ldr x0, [_win_leftmost]
    bl  _wnoutrefresh

    ldr x0, [_win_middle_left]
    bl  _werase
    ldr x0, [_win_middle_left]
    bl  _wnoutrefresh

    ldr x0, [_win_middle_right]
    bl  _werase
    ldr x0, [_win_middle_right]
    bl  _wnoutrefresh

    ldr x0, [_win_rightmost]
    bl  _werase
    ldr x0, [_win_rightmost]
    bl  _wnoutrefresh

    // 2. Draw content into leaf windows
    bl  _draw_board          // draws into _win_board
    bl  _draw_hold_panel     // draws into _win_hold
    bl  _draw_score_panel    // draws into _win_score
    bl  _draw_next_panel     // draws into _win_middle_right
    bl  _draw_stats_panel    // draws into _win_rightmost
    // (each function calls wnoutrefresh on its window)

    // 3. Draw active piece and ghost into board window
    bl  _draw_ghost_piece    // draws into _win_board
    bl  _draw_piece          // draws into _win_board

    // 4. wnoutrefresh for board (after all board content drawn)
    ldr x0, [_win_board]
    bl  _wnoutrefresh

    // 5. Single terminal flush
    bl  _doupdate
    ret
```

### Pattern 3: Coordinate Translation
**What:** Convert absolute stdscr coordinates to window-relative coordinates.
**When to use:** When adapting existing draw functions.

Current v1.0 uses absolute coordinates:
- Board cell (row, col) -> screen (row+1, col*2+1) on stdscr
- Next panel at absolute col 23, row 1
- Hold panel at absolute col 23, row 10
- Score panel at absolute col 34
- Stats at absolute col 23, row 16+

With subwindows, each panel uses coordinates relative to its own origin (0,0):
- Board cell (row, col) -> (row+1, col*2+1) on _win_board (same because board starts at origin within its container)
- Next panel: (0, 0) within _win_middle_right for the "Next" title
- Hold panel: (0, 0) within _win_hold for the "Hold" title
- Score: (0, 0) within _win_score for labels/values
- Stats: (0, 0) within _win_rightmost for all statistics

The key simplification: each panel function only needs to know its own WINDOW* pointer and draws starting from (0,0) or (1,1) if bordered.

### Pattern 4: State Transition Window Management
**What:** Create/destroy window sets on state transitions.
**When to use:** MENU->GAME and GAME->MENU transitions.

```
State machine window lifecycle:
  Program start:
    initscr() -> stdscr exists
    _init_menu_layout() -> create menu windows

  MENU -> GAME transition:
    _destroy_menu_layout() -> delwin all menu windows
    _init_game_layout() -> create game windows

  GAME -> MENU transition:
    _destroy_game_layout() -> delwin all game windows
    _init_menu_layout() -> create menu windows

  HELP state:
    Reuse menu windows (or draw on stdscr as current)

  Program exit:
    _destroy_*_layout() -> clean up
    endwin()
```

### Anti-Patterns to Avoid
- **Drawing on stdscr after creating subwindows:** Once subwindows exist, all drawing must go through them. Drawing on stdscr will be overwritten by subwindow refreshes.
- **Calling wrefresh on parent after drawing on child:** Parent wrefresh overwrites child content. Always use wnoutrefresh on parents, wnoutrefresh on children, then doupdate.
- **Destroying child before parent:** Delete child windows (derwin'd) before the parent (newwin'd). Reverse creation order.
- **Forgetting keypad/wtimeout on new windows:** If input polling uses wgetch on a specific window, that window needs keypad() and wtimeout() configured. Simplest approach: keep using stdscr for input (wgetch on stdscr), draw on subwindows.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Window clipping | Manual bounds checking for drawing near edges | derwin + ncurses clipping | ncurses automatically clips content that falls outside a window's bounds |
| Batch screen update | Manual terminal escape sequence batching | wnoutrefresh + doupdate | ncurses computes minimal terminal diff internally |
| Window overlap handling | Z-order management for pause overlay | Draw pause last, wnoutrefresh last | ncurses wnoutrefresh marks virtual screen; last writer wins |
| Coordinate translation | Manual offset arithmetic in every draw call | derwin parent-relative coordinates | derwin handles the translation; draw at (0,0) within each panel |

**Key insight:** The entire point of subwindows is to eliminate absolute coordinate math. Each panel function should load its own WINDOW* pointer and draw at panel-relative positions. The 130+ lines of hardcoded column offsets (23, 34, etc.) in the current render.s get replaced by simple small offsets within each panel's local coordinate space.

## Common Pitfalls

### Pitfall 1: Parent-Child Refresh Order
**What goes wrong:** Child window content disappears or shows stale parent content.
**Why it happens:** Calling wrefresh (or wnoutrefresh + doupdate) on a parent window after drawing on a child causes the parent's blank content to overwrite the child's drawn content on the virtual screen.
**How to avoid:** Follow strict order: (1) werase parent, (2) wnoutrefresh parent, (3) werase child, (4) draw on child, (5) wnoutrefresh child, (6) doupdate. This is exactly what the C++ original does in LayoutGame::draw().
**Warning signs:** Panels flickering or appearing blank; content from one panel bleeding into another.

### Pitfall 2: derwin vs subwin Confusion
**What goes wrong:** Child window appears at wrong position on screen.
**Why it happens:** `subwin` uses absolute screen coordinates; `derwin` uses parent-relative coordinates. The C++ original uses `derwin` exclusively (Window.cpp line 59).
**How to avoid:** Always use `derwin`. The coordinates passed are relative to the parent window's origin.
**Warning signs:** Panels appearing offset from expected positions; panels appearing outside their parent's bounds.

### Pitfall 3: Input Window Mismatch
**What goes wrong:** Arrow keys stop working or input is dropped.
**Why it happens:** `keypad()` and `wtimeout()` are per-window settings. If you call `wgetch()` on a different window than the one configured for non-blocking input, behavior changes.
**How to avoid:** Keep input handling on stdscr (which is already configured from v1.0). Only change the draw target, not the input target. stdscr still exists and can receive input even when subwindows handle drawing.
**Warning signs:** Game freezes waiting for input; arrow keys produce escape sequences instead of KEY_UP/KEY_DOWN.

### Pitfall 4: GOT-Indirect for Window Pointers
**What goes wrong:** WINDOW* pointers loaded incorrectly, causing crashes.
**Why it happens:** The existing code uses GOT-indirect access for `_stdscr` (external ncurses symbol). The new WINDOW* pointers (_win_main, etc.) are local to the binary and should use `adrp+add` PAGE/PAGEOFF access, NOT GOT-indirect.
**How to avoid:** Use `adrp x8, _win_main@PAGE` / `ldr x0, [x8, _win_main@PAGEOFF]` for local WINDOW* pointers. Only use `@GOTPAGE/@GOTPAGEOFF` for `_stdscr` (external).
**Warning signs:** Segfault on first attempt to load a WINDOW* pointer.

### Pitfall 5: Window Size for Bordered vs Borderless
**What goes wrong:** Content drawn at wrong positions within bordered windows.
**Why it happens:** The C++ Window class adjusts child coordinates when the parent has borders: if parent has borders, child x defaults to 1 (not 0) and width defaults to parent_width-2. The assembly must replicate this manually.
**How to avoid:** For bordered windows (hold, score, middle_left, middle_right, rightmost), drawable area starts at (1,1) with dimensions (width-2, height-2). For borderless containers (leftmost, board), drawable area starts at (0,0) with full dimensions.
**Warning signs:** Content overwriting border characters; text starting one column too far left.

### Pitfall 6: Forgetting to delwin on State Transition
**What goes wrong:** Memory leak or stale windows cause visual corruption.
**Why it happens:** When transitioning from GAME back to MENU, the game windows must be destroyed. Failing to call delwin leaves orphaned ncurses structures.
**How to avoid:** Implement _destroy_game_layout and _destroy_menu_layout that call delwin on all windows in reverse creation order (children first, then parent). Call these on state transitions.
**Warning signs:** Visual artifacts when returning to menu after a game; increasing memory usage over multiple games.

## Code Examples

### Exact C++ Panel Geometry (from LayoutGame.cpp)

```
80-column, 24-row main window layout:

Col: 0           12          34    44                 79
     |<--12w-->|  |<---22w--->|<10w>|<------35w------>|
Row 0: [leftmost ]  [middle_left    ][mid_r][rightmost         ]
       [         ]  [  (board 22x22)][     ][                  ]
       [hold 12x4]  [               ][next ][   statistics     ]
Row 4: [         ]  [               ][10x4 ][                  ]
       [score    ]  [               ]       [                  ]
       [12x20    ]  [               ]       [                  ]
       [         ]  [               ]       [                  ]
       ...         ...                      ...
Row 21:[         ]  [               ]       [                  ]
Row 22:[         ]                          [                  ]
Row 23:[         ]                          [                  ]

Window creation parameters (all from C++ LayoutGame.cpp):
  main:         newwin(24, 80, 0, 0)
  leftmost:     derwin(main, 24, 12, 0, 0)     // BORDER_NONE container
  hold:         derwin(leftmost, 4, 12, 0, 0)  // bordered, title="Hold"
  score:        derwin(leftmost, 20, 12, 4, 0) // bordered
  middle_left:  derwin(main, 22, 22, 0, 12)    // bordered, board container
  board:        derwin(middle_left, 22, 22, 0, 0) // BORDER_NONE, fills parent
  middle_right: derwin(main, 4, 10, 0, 34)     // bordered, title="Next"
  rightmost:    derwin(main, 24, 35, 0, 44)    // bordered, title="Statistics"
  pause:        derwin(main, 6, 40, 11, 20)    // bordered, title="Paused"
```

Note: The C++ `WINDOW_FILL` (0) causes the Window constructor to expand to parent size minus borders. In assembly we compute the exact values ahead of time.

### Menu Layout Geometry (from LayoutMainMenu.cpp)

```
80-column, 24-row main window layout:

  main:           newwin(24, 80, 0, 0)
  logo:           derwin(main, 9, 80, 0, 0)     // bordered, top portion
  animContainer:  derwin(main, 14, 80, 10, 0)   // BORDER_NONE, behind menu
  menu:           derwin(main, 13, 30, 10, 25)  // bordered, centered

  logo: height=9 (fixed in C++ -- LayoutMainMenu line 40)
  menu: x = 80/3 - 2 = 24.67 -> 25 (integer division)
        y = 9 + 1 = 10
        w = 80/3 + 2 = 28.67 -> 28 (integer division)
        h = 24 - 9 - 2 = 13

  In assembly (integer arithmetic):
    menu_x = 80/3 - 2 = 26 - 2 = 24  (need to verify: 80/3=26 in integer div)
    menu_w = 80/3 + 2 = 26 + 2 = 28
    menu_y = 9 + 1 = 10
    menu_h = 24 - 9 - 2 = 13
```

### Converting a Draw Function: _draw_score_panel Example

Current v1.0 (draws on stdscr at absolute col 34):
```asm
_draw_score_panel:
    // Load stdscr via GOT
    adrp x19, _stdscr@GOTPAGE
    ldr  x19, [x19, _stdscr@GOTPAGEOFF]
    // Draw "Score" at (1, 34) on stdscr
    ldr  x0, [x19]
    mov  w1, #1       // absolute row
    mov  w2, #34      // absolute col
    bl   _wmove
    ...
```

Phase 6 version (draws on _win_score at relative positions):
```asm
_draw_score_panel:
    // Load score window pointer (local symbol, not GOT)
    adrp x19, _win_score@PAGE
    add  x19, x19, _win_score@PAGEOFF
    // Draw "Score" at (1, 1) within score window (inside border)
    ldr  x0, [x19]        // WINDOW* for score panel
    mov  w1, #1            // relative row (row 0 is top border)
    mov  w2, #1            // relative col (col 0 is left border)
    bl   _wmove
    ...
    // At end: wnoutrefresh instead of nothing
    ldr  x0, [x19]
    bl   _wnoutrefresh
```

### Converting _draw_board: Board Window Coordinates

The board window (_win_board) is BORDER_NONE, created as derwin of middle_left.
Since middle_left has borders, and board fills the entire middle_left:

- Board window is 22 cols wide, 22 rows tall
- Row 0 and row 21 of the board window correspond to where the borders will be drawn
- Board cells map to: cell (row, col) -> board_win position (row+1, col*2+1)
  This is IDENTICAL to the current mapping because the board already starts at col 0 on stdscr.

The key change: instead of `ldr x0, [stdscr_got_ptr]` before every wmove/waddch, use `ldr x0, [_win_board_ptr]`.

### Window Lifecycle Assembly Pattern

```asm
// _init_game_layout: Create all game windows
// Called on MENU -> GAME transition
// Returns: void (all windows stored in global pointers)
// Clobbers: x0-x4, x8, x19-x24 (callee-saved, save in prologue)
_init_game_layout:
    stp x24, x23, [sp, #-48]!
    stp x22, x21, [sp, #16]
    stp x20, x19, [sp, #32]
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    // Create main: newwin(24, 80, 0, 0)
    mov w0, #24
    mov w1, #80
    mov w2, #0
    mov w3, #0
    bl  _newwin
    // Store pointer
    adrp x8, _win_main@PAGE
    str  x0, [x8, _win_main@PAGEOFF]
    mov  x19, x0    // x19 = main WINDOW*

    // Create leftmost: derwin(main, 24, 12, 0, 0)
    mov  x0, x19
    mov  w1, #24
    mov  w2, #12
    mov  w3, #0
    mov  w4, #0
    bl   _derwin
    adrp x8, _win_leftmost@PAGE
    str  x0, [x8, _win_leftmost@PAGEOFF]
    mov  x20, x0    // x20 = leftmost

    // ... (continue for all windows)
    // hold: derwin(leftmost, 4, 12, 0, 0)
    // score: derwin(leftmost, 20, 12, 4, 0)
    // middle_left: derwin(main, 22, 22, 0, 12)
    // board: derwin(middle_left, 22, 22, 0, 0)
    // middle_right: derwin(main, 4, 10, 0, 34)
    // rightmost: derwin(main, 24, 35, 0, 44)
    // pause: derwin(main, 6, 40, 11, 20)

    ldp x29, x30, [sp], #16
    ldp x20, x19, [sp, #32]
    ldp x22, x21, [sp, #16]
    ldp x24, x23, [sp], #48
    ret

// _destroy_game_layout: Delete all game windows (reverse order)
_destroy_game_layout:
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    // Delete children first, then parents
    // pause
    adrp x8, _win_pause@PAGE
    ldr  x0, [x8, _win_pause@PAGEOFF]
    cbz  x0, 1f
    bl   _delwin
1:
    // rightmost
    // middle_right
    // board
    // middle_left
    // score
    // hold
    // leftmost
    // main (last)
    // ... (each follows same pattern: load, cbz skip, delwin)

    // Zero all pointers
    adrp x8, _win_main@PAGE
    str  xzr, [x8, _win_main@PAGEOFF]
    // ... (zero all window pointers)

    ldp x29, x30, [sp], #16
    ret
```

## State of the Art

| Old Approach (v1.0) | New Approach (Phase 6) | Impact |
|----------------------|------------------------|--------|
| All drawing on stdscr | Each panel has own WINDOW* | Enables independent clear/draw/refresh per panel |
| Absolute coordinates (col 23, 34, etc.) | Window-relative coordinates (0,0 or 1,1) | Simpler draw code, easier to maintain |
| Single wrefresh(stdscr) at frame end | wnoutrefresh per window + doupdate | Matches C++ pattern, enables animation compositing in Phase 10 |
| No window borders (ASCII +/-/\|) | ncurses wborder on subwindows | Foundation for Phase 7 ACS box-drawing borders |
| Board at stdscr origin | Board in middle_left subwindow at col 12 | Correct 80x24 layout matching C++ |

## Open Questions

1. **Board Content Within Bordered Window**
   - What we know: The C++ creates middle_left with borders, then board as BORDER_NONE child filling the full parent. The board child effectively draws "inside" the bordered area.
   - What's unclear: Should the assembly create the board as a separate derwin (like C++), or should middle_left itself serve as the board window? Creating it as a separate child is cleaner but adds one more window to manage.
   - Recommendation: Match C++ exactly -- create board as derwin of middle_left with BORDER_NONE. This keeps the architecture consistent and avoids special-casing border offsets in the board draw code. The board draw code then uses (row+1, col*2+1) within the board window, identical to current code.

2. **Menu Layout: Logo Window Title**
   - What we know: C++ sets the logo window title to the player profile name (e.g., "Rachel's"). Assembly has no profile system.
   - What's unclear: What to show as the logo window title.
   - Recommendation: Skip the title for now. The logo window's primary content is the ASCII art logo (Phase 7). Leave the title empty in Phase 6.

3. **Input Window After Subwindow Creation**
   - What we know: v1.0 configures keypad() and wtimeout() on stdscr. After creating subwindows with newwin, stdscr still exists.
   - What's unclear: Whether wgetch(stdscr) still works correctly when other windows are drawn.
   - Recommendation: Keep all input on stdscr. The ncurses documentation confirms that stdscr persists alongside manually created windows. wgetch(stdscr) will continue to work. No changes needed to input.s.

4. **Integer Division for Menu Layout**
   - What we know: C++ uses `main->getW() / 3` which is 80/3=26 (integer division).
   - Recommendation: Use `udiv` in assembly: 80/3=26. Menu x=26-2=24, menu w=26+2=28.

## Sources

### Primary (HIGH confidence)
- C++ source code analysis: `deps/Engine/Graphics/Window.cpp` -- confirmed derwin usage, wnoutrefresh pattern, border handling
- C++ source code analysis: `src/Game/Display/Layouts/LayoutGame.cpp` -- confirmed exact window geometry: leftmost=12w, middle_left=22w, middle_right=10w, rightmost=35w
- C++ source code analysis: `src/Game/Display/Layouts/LayoutMainMenu.cpp` -- confirmed menu layout: logo h=9, menu centered
- C++ source code analysis: `src/Game/Entities/Game.cpp` line 52 -- confirmed 80x24 layout dimensions
- C++ source code analysis: `src/Game/States/GameStateMainMenu.cpp` line 93 -- confirmed 80x24 menu dimensions
- Assembly codebase analysis: `asm/render.s` -- confirmed current stdscr-only rendering, hardcoded coordinates (col 23, 34)
- Assembly codebase analysis: `asm/data.s` -- confirmed current data layout, all global symbols
- Assembly codebase analysis: `asm/menu.s` -- confirmed current menu draws directly on stdscr

### Secondary (MEDIUM confidence)
- ncurses man pages (system documentation) -- function signatures for newwin, derwin, wnoutrefresh, doupdate, delwin
- STATE.md blocker note on refresh ordering -- "must follow erase parent -> draw parent -> wnoutrefresh parent -> erase child -> draw child -> wnoutrefresh child -> doupdate sequence"

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - ncurses is the only dependency, all functions are well-documented system library calls
- Architecture: HIGH - exact panel geometry derived directly from C++ source code with line-number references
- Pitfalls: HIGH - refresh ordering issue already identified in STATE.md; derwin vs subwin distinction verified in C++ source; GOT access pattern established in v1.0 codebase

**Research date:** 2026-02-27
**Valid until:** 2026-03-27 (stable -- ncurses API and project architecture unlikely to change)
