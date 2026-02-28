# Architecture: v1.1 Integration Plan

**Domain:** ARM64 Assembly Tetris -- Visual Polish, Scoring, and File I/O
**Researched:** 2026-02-27
**Confidence:** HIGH for existing codebase analysis (read every line of all 9 source files); MEDIUM for ncurses subwindow integration (well-documented API, verified with official docs); MEDIUM for animation data structures (C++ reference implementations analyzed in full); HIGH for file I/O (Darwin syscalls already used in the codebase for write(2) to stderr).

---

## Current Architecture (v1.0 Actual)

### System Diagram

```
                          asm/main.s
                    State Machine Loop
                    ┌──────────────────┐
                    │ game_state = 0   │──> menu.s: _menu_frame
                    │ game_state = 1   │──> Game Frame (below)
                    │ game_state = 2   │──> menu.s: _help_frame
                    │ game_state = FF  │──> Exit + stats to stderr
                    └──────────────────┘

    ══════════ Game Frame (state 1) ══════════

    _poll_input ──> _handle_input ──> gravity check ──> _render_frame
        │                │                  │                │
      input.s          input.s           main.s          render.s
        │                │                  │                │
        │          piece.s calls      timer.s calls    All draw_*
        │          board.s calls     (_get_time_ms)    functions
        │                                                    │
        └───── All operate on global state in data.s ────────┘
```

### File Inventory (9 files, 5,300 lines)

| File | Lines | Responsibility | Exports |
|------|-------|----------------|---------|
| `main.s` | 572 | Entry, init, state machine, frame timing | `_main` |
| `render.s` | 1,733 | ALL rendering: board, piece, ghost, panels, game over | `_init_colors`, `_draw_board`, `_draw_piece`, `_draw_ghost_piece`, `_draw_next_panel`, `_draw_hold_panel`, `_draw_stats_panel`, `_draw_paused_overlay`, `_draw_score_panel`, `_draw_game_over`, `_render_frame` |
| `board.s` | 683 | Collision, locking, line clearing (NEON), reset, noise | `_is_piece_valid`, `_lock_piece`, `_clear_lines`, `_reset_board`, `_add_noise` |
| `piece.s` | 630 | Movement, SRS rotation, drops, spawning, hold, ghost | `_try_move`, `_try_rotate`, `_hard_drop`, `_soft_drop`, `_spawn_piece`, `_check_game_over`, `_compute_ghost_y`, `_hold_piece` |
| `data.s` | 619 | All constants (__TEXT,__const) and mutable state (__DATA) | All global labels |
| `menu.s` | 653 | Menu rendering, settings adjustment, help screen | `_menu_frame`, `_help_frame` |
| `input.s` | 245 | Key dispatch, ncurses input config | `_init_input`, `_poll_input`, `_handle_input` |
| `random.s` | 123 | 7-bag Fisher-Yates shuffle via arc4random_uniform | `_shuffle_bag`, `_next_piece` |
| `timer.s` | 50 | gettimeofday wrapper returning milliseconds | `_get_time_ms` |

### Key Architectural Facts

**Rendering:** Everything renders to `stdscr` via `wmove` + `waddch` / `waddstr`. There are NO subwindows. A single `wrefresh(stdscr)` at the end of `_render_frame` flushes everything.

**Screen layout:** 80x24 assumed but not enforced. Board occupies cols 1-20 (2 chars per cell), rows 1-20. Next/Hold panels at col 23. Score panel at col 34. All positions are hardcoded literal immediates in render.s.

**Data flow:** All game state lives in `data.s` global labels. Functions read/write these via `adrp+add` (same-binary addressing). There are no function parameters for state -- functions load globals directly.

**Register conventions:** Callee-saved x19-x28, stack frames 16-96 bytes. x28 is a packed bitfield in main.s (game_over, is_paused, game_initialized). stdscr GOT pointer is loaded fresh in each function that needs it (not cached globally).

**Color system:** 7 color pairs (1-7) initialized in `_init_colors`. Board cells store piece_type+1 (1-7) which maps directly to color pair index. No additional color pairs exist for UI, labels, or borders.

**Scoring:** Fixed lookup table: 1 line = 100, 2 = 300, 3 = 500, 4 (tetris) = 800. Plus 10 per lock. No combos, no back-to-back, no T-spin detection, no perfect clear.

---

## v1.1 Feature Integration Analysis

### Feature 1: ncurses Subwindows

**What changes:** Replace all hardcoded screen coordinates in render.s with window-relative coordinates. Create subwindows matching the C++ layout hierarchy.

**C++ reference layout hierarchy:**
```
main (80x24, newwin)
├── leftmost (12 wide, container)
│   ├── hold (12 wide, 4 tall) -- "Hold" title
│   └── score (12 wide, remaining) -- Hi-Score, Score, Level
├── middle_left (22 wide, 22 tall, container)
│   └── board (borderless child, 20x20 content)
├── middle_right (10 wide, variable) -- "Next" title
│   └── next[0..N] (borderless children, 2 rows each)
└── rightmost (remaining, optional) -- "Statistics" title
```

**Integration approach:**

Create subwindows at game init time using `_newwin` and `_derwin`. Store WINDOW* pointers in data.s as `.quad` globals. All render functions change from `adrp x8, _stdscr@GOTPAGE` to loading the appropriate subwindow pointer.

**Critical detail -- derwin vs subwin vs newwin:**
- `newwin(nlines, ncols, begin_y, begin_x)` -- independent window, separate memory. Each needs its own `wrefresh`.
- `subwin(orig, nlines, ncols, abs_y, abs_x)` -- shares memory with parent. Absolute screen coordinates. `wrefresh` on parent refreshes children.
- `derwin(orig, nlines, ncols, rel_y, rel_x)` -- shares memory with parent. **Relative** coordinates. This is what we want.

Use `_newwin` for the main 80x24 window. Use `_derwin` for all child windows (coordinates relative to parent). This matches the C++ reference which uses child Window construction with relative offsets.

**ncurses calling convention (ARM64):**
```asm
// WINDOW* _newwin(int nlines, int ncols, int begin_y, int begin_x)
mov  w0, #24          // nlines
mov  w1, #80          // ncols
mov  w2, #0           // begin_y
mov  w3, #0           // begin_x
bl   _newwin          // returns WINDOW* in x0

// WINDOW* _derwin(WINDOW* orig, int nlines, int ncols, int begin_y, int begin_x)
ldr  x0, [x_main_win] // parent WINDOW*
mov  w1, #22           // nlines
mov  w2, #22           // ncols
mov  w3, #0            // begin_y (relative to parent)
mov  w4, #12           // begin_x (relative to parent)
bl   _derwin           // returns WINDOW* in x0

// wborder(WINDOW* win, ls, rs, ts, bs, tl, tr, bl, br) -- 9 args
// For ACS characters, pass 0 for defaults or ACS_VLINE etc.
// Note: 9 arguments. x0-x7 are first 8, 9th goes on stack.
// wborder(win, 0, 0, 0, 0, 0, 0, 0, 0) uses defaults.
ldr  x0, [x_board_win]
mov  w1, #0    // ls (ACS_VLINE default)
mov  w2, #0    // rs
mov  w3, #0    // ts (ACS_HLINE default)
mov  w4, #0    // bs
mov  w5, #0    // tl (ACS_ULCORNER default)
mov  w6, #0    // tr
mov  w7, #0    // bl
// 9th arg on stack:
str  wzr, [sp, #-16]!  // br = 0 (ACS_BRCORNER default)
bl   _wborder
add  sp, sp, #16
```

**IMPORTANT -- wborder has 9 arguments.** On ARM64, the first 8 go in x0-x7, the 9th goes on the stack. This is the key trap for assembly callers. The simpler `box(win, 0, 0)` takes only 3 arguments and produces the same default border.

```asm
// Simpler: box(WINDOW* win, chtype verch, chtype horch)
ldr  x0, [x_board_container]
mov  w1, #0    // default vertical char
mov  w2, #0    // default horizontal char
bl   _box
```

**Use `_box` instead of `_wborder` for simplicity.** Only use `_wborder` if we need fancy ACS characters that differ from defaults.

**New globals in data.s:**
```asm
.section __DATA,__data
.globl _win_main
.p2align 3
_win_main:          .quad 0    // WINDOW* from newwin(24, 80, 0, 0)
_win_board_frame:   .quad 0    // derwin(main, 22, 22, 0, 12)
_win_board:         .quad 0    // derwin(board_frame, 20, 20, 1, 1)
_win_hold:          .quad 0    // derwin(main, 4, 12, 0, 0)
_win_score:         .quad 0    // derwin(main, H-4, 12, 4, 0)
_win_next:          .quad 0    // derwin(main, H, 10, 0, 34)
_win_stats:         .quad 0    // derwin(main, H, W-44, 0, 44)
```

**Render function changes:** Every `_draw_*` function currently loads stdscr. Instead, each loads its designated window pointer. For example, `_draw_board` loads `_win_board`, `_draw_score_panel` loads `_win_score`. The coordinate system becomes window-relative (0,0 is top-left of each panel), eliminating all the hardcoded offset arithmetic.

**Refresh strategy:** With `derwin`, touching a subwindow marks the parent as needing refresh. Call `_wnoutrefresh` on each subwindow, then one final `_doupdate` instead of `_wrefresh`. This is more efficient than refreshing each window separately.

```asm
_render_frame:
    // ... draw to all subwindows ...
    ldr x0, [_win_board]
    bl  _wnoutrefresh
    ldr x0, [_win_score]
    bl  _wnoutrefresh
    // ... etc for each window ...
    bl  _doupdate      // single terminal write
```

**Menu subwindows:** The menu currently renders on stdscr too. Create separate windows for the menu state:
```
_win_menu_logo:    -- ASCII art area (top ~9 rows)
_win_menu_content: -- menu items and settings area
_win_menu_anim:    -- animation background area (behind content)
```

### Feature 2: Fancy Box-Drawing Borders (ACS Characters)

**What changes:** Replace `+`, `-`, `|` ASCII borders in `_draw_board` with ncurses ACS characters.

**Current border drawing (render.s):**
```asm
// Top border: wmove to row 0, then '+', then 20 '-', then '+'
// Side borders: '|' at column 0 and column 21 of each row
// Bottom border: same as top
```

**New approach:** Once subwindows exist, borders are drawn by ncurses automatically with `_box` or `_wborder`. The board container window (`_win_board_frame`) gets `_box(win, 0, 0)` which draws ACS_VLINE/ACS_HLINE/ACS_ULCORNER etc. The actual board content window is a borderless `_derwin` inside it.

**Color on borders:** Use `wattr_on` before `_box`:
```asm
ldr  x0, [_win_board_frame]
mov  w1, #COLOR_PAIR_mask  // construct attribute
mov  x2, #0
bl   _wattr_on
ldr  x0, [_win_board_frame]
mov  w1, #0
mov  w2, #0
bl   _box
ldr  x0, [_win_board_frame]
mov  w1, #COLOR_PAIR_mask
mov  x2, #0
bl   _wattr_off
```

**New color pairs needed:** Currently 7 pairs (pieces only). Need additional pairs for:
- Pair 8: UI label text (cyan or white bold on black)
- Pair 9: Border color (white on black, or cyan)
- Pair 10: Menu highlight (specific color)
- Pair 11: Fire animation colors (red bold, yellow bold)
- Pair 12-16: Additional animation colors

The `_init_colors` function in render.s must be extended. ncurses supports up to 256 color pairs on modern terminals, so this is not a constraint.

### Feature 3: Background Animations (Fire, Water, Snakes, Game of Life)

**What changes:** New file `animation.s` implementing 4 animation algorithms that render into the board background.

**C++ reference analysis -- data structures per animation:**

| Animation | Data Size | Algorithm | Update Rate |
|-----------|-----------|-----------|-------------|
| Fire | 2x (W*H) int arrays (particle + coolingMap) = 2 * 20 * 20 * 4 = 3,200 bytes | Bottom-up heat diffusion with cooling | 100ms |
| Water | 2x (W*H) int arrays (buffer1 + buffer2) = 3,200 bytes | Ripple propagation via neighbor averaging | 300ms |
| Snakes | Dynamic list of (x, y, size) triples, max ~64 snakes | Spawn at top, fall down, delete when off-screen | 50ms |
| Game of Life | 1x (W*H) bool array = 400 bytes | Conway's rules: birth/survival by neighbor count | 200ms |

**Critical simplification for assembly:** The C++ uses dynamic allocation (Array2D with `new`). In assembly, allocate fixed-size buffers in `__DATA` since the board size is constant (20x20 = 400 cells, but animations use window dimensions which are 20 cols * 20 rows = 400, or with 2-char-wide cells, the animation grid could be 20x20).

**Recommended fixed buffers in data.s:**
```asm
.section __DATA,__data
.globl _anim_type
_anim_type:         .byte 0         // 0=none, 1=fire, 2=water, 3=snakes, 4=life
.globl _anim_timer
.p2align 3
_anim_timer:        .quad 0         // last update timestamp (ms)

// Fire/Water: 2 grids of 20x20 = 400 words each
.globl _anim_buf1
.p2align 2
_anim_buf1:         .space 1600, 0  // 400 x 4 bytes (int per cell)
.globl _anim_buf2
_anim_buf2:         .space 1600, 0  // 400 x 4 bytes (int per cell)

// Snakes: fixed array of 64 snake structs (x: byte, y: hword, size: byte = 4 bytes each)
.globl _anim_snakes
_anim_snakes:       .space 256, 0   // 64 snakes x 4 bytes
.globl _anim_snake_count
_anim_snake_count:  .byte 0

// Game of Life: 1 grid of 20x20 bytes
.globl _anim_life
_anim_life:         .space 400, 0
```

Total animation data: ~3,856 bytes in __DATA. This is acceptable -- the current binary is 52KB.

**Integration into render pipeline:**
```
_render_frame (modified):
  1. Clear board window
  2. IF animation enabled: _update_animation, _draw_animation (writes to _win_board)
  3. _draw_board_cells (draws locked blocks ON TOP of animation -- non-zero cells overwrite)
  4. _draw_ghost_piece
  5. _draw_piece
  6. ... panels ...
  7. _doupdate
```

The animation renders dim background characters. Locked board blocks and active pieces render on top with bright colors. The C++ does exactly this: `animation->draw()` then `board->draw()` on the same window.

**New file: `animation.s`**
```
Exports:
  _init_animation(w0 = type)  -- allocate/init for selected type
  _update_animation()         -- advance state if enough time elapsed
  _draw_animation()           -- render current state to _win_board
  _reset_animation()          -- clear all buffers

Internal (L-prefix labels, not exported):
  Lfire_update, Lfire_draw
  Lwater_update, Lwater_draw
  Lsnakes_update, Lsnakes_draw
  Llife_update, Llife_draw
```

Estimated size: 400-600 lines (each animation is ~80-120 lines in C++, assembly will be 2-3x).

### Feature 4: Modern Scoring (Combos, Back-to-Back, T-Spin, Perfect Clear)

**What changes:** Replace the simple `_score_table[lines-1]` lookup in `_clear_lines` (board.s) with a scoring engine that tracks combo chains, back-to-back status, detects T-spins, and detects perfect clears.

**New scoring state in data.s:**
```asm
// Modern scoring state
.globl _combo_count
.p2align 2
_combo_count:       .word 0     // consecutive clears (0 = first clear, no bonus)
.globl _back_to_back
_back_to_back:      .byte 0     // 1 = last clear was "difficult" (tetris or T-spin)
.globl _last_clear_type
_last_clear_type:   .byte 0     // 0=none, 1=single, 2=double, 3=triple, 4=tetris
                                // 5=tspin_mini, 6=tspin_single, 7=tspin_double, 8=tspin_triple
.globl _last_piece_was_rotation
_last_piece_was_rotation: .byte 0  // 1 = last move before lock was a rotation
.globl _last_kick_index
_last_kick_index:   .byte 0     // which SRS kick test succeeded (0-4), for T-spin mini detection
```

**T-spin detection algorithm:**
1. Track whether the last input before lock was a rotation (`_last_piece_was_rotation`)
2. After locking piece_type == 6 (T-piece), check 3-corner rule:
   - Load T-piece position (piece_x, piece_y)
   - The T-piece pivot is at grid position (2,2) within the 5x5 grid
   - Board coordinates of pivot: (piece_x + 2, piece_y + 2)
   - Check the 4 diagonal corners of the pivot on the board
   - If 3+ corners are occupied AND last move was rotation: T-spin
   - If only 2 front corners occupied (based on rotation state): T-spin Mini
3. Which corners are "front" depends on `_piece_rotation`:
   - Rotation 0 (spawn): front corners are top-left and top-right
   - Rotation 1 (R): front corners are top-right and bottom-right
   - Rotation 2 (180): front corners are bottom-left and bottom-right
   - Rotation 3 (L): front corners are top-left and bottom-left

**Integration points in existing code:**

1. **input.s `_handle_input`:** Set `_last_piece_was_rotation = 0` after any move. Set `_last_piece_was_rotation = 1` after any rotation call. This is a small addition to each dispatch case.

2. **piece.s `_try_rotate`:** Store the successful kick index in `_last_kick_index`.

3. **board.s `_lock_piece`:** After locking, before calling `_clear_lines`:
   - If piece was T (type 6) AND `_last_piece_was_rotation`: call `_detect_tspin`.

4. **board.s `_clear_lines`:** After counting lines cleared:
   - Call `_compute_score(w0=lines, w1=tspin_type)` instead of the inline score table lookup.
   - `_compute_score` handles combos, back-to-back multiplier, perfect clear.

5. **board.s `_clear_lines` or new score.s:** After clearing, check if board is empty (perfect clear):
   ```asm
   // Check all 200 bytes of _board for zero
   // Can use NEON: ld1 16 bytes at a time, orr accumulator, check if zero
   ```

**New file: `score.s`** (or extend board.s)
```
Exports:
  _detect_tspin() -> w0 = 0 (no tspin), 1 (tspin mini), 2 (full tspin)
  _compute_score(w0=lines, w1=tspin_type) -- updates _score with full scoring
  _check_perfect_clear() -> w0 = 1 if board empty
  _reset_scoring_state()  -- reset combo, b2b, etc on game start

Internal scoring formula (Tetris Guideline):
  Base points (no T-spin):
    Single=100, Double=300, Triple=500, Tetris=800
  T-spin bonuses:
    T-spin Mini (0 lines)=100, T-spin Mini Single=200
    T-spin (0 lines)=400, T-spin Single=800, T-spin Double=1200, T-spin Triple=1600
  Back-to-back: 1.5x multiplier on "difficult" clears (Tetris or any T-spin line clear)
  Combo: +50 * combo_count * level (combo_count increments each consecutive clear)
  Perfect clear: +3000 (on top of line clear score)
```

Estimated size: 200-300 lines.

### Feature 5: Line Clear Animation

**What changes:** When lines are cleared, flash the full rows before removing them, creating a visual delay.

**C++ reference approach (from Board.cpp):**
1. `markFullLines()` -- scan board, replace full-row cells with a "clear_line" marker block, return line count
2. Render the board (shows the marked rows with special appearance)
3. `delay_ms()` -- wait (configurable, typically 100-200ms)
4. `clearFullLines()` -- actually remove the marked rows and shift down

**Assembly integration:**

Currently `_clear_lines` in board.s does detection AND removal in one pass. Split into two phases:

**Phase A -- Mark (in `_clear_lines`):**
```asm
_mark_full_lines:
    // Scan board bottom-to-top (same NEON check as current)
    // For each full row: set all cells to value 9 (flash marker)
    // Store count in _pending_clear_count
    // Do NOT shift rows yet
    ret
```

**Phase B -- Actually clear (new `_execute_clear`):**
```asm
_execute_clear:
    // Scan for rows containing value 9
    // Shift rows down (existing shift logic)
    // Update score/lines/level
    ret
```

**Render integration:**
```
_render_frame:
    if _pending_clear_count > 0:
        // Flash frame: draw board with value-9 cells as bright white
        _draw_board()          // value 9 cells rendered as bright flash
        _doupdate()
        delay_ms(150)          // visual pause
        _execute_clear()       // now actually remove rows
        _pending_clear_count = 0
    // Normal render continues...
```

**New data:**
```asm
.globl _pending_clear_count
_pending_clear_count: .byte 0   // lines marked for clearing (0 = none)
```

**Warning:** The delay_ms inside _render_frame blocks the game loop. This matches the C++ behavior. An alternative (non-blocking) would use a state flag and timer, but the C++ reference uses a synchronous delay, so we match that.

### Feature 6: Hi-Score File Persistence

**What changes:** Save top score to `~/.yetris-asm-hiscore` using Darwin syscalls. Load on startup, save on game over if score beats hi-score.

**C++ reference:** Uses C++ fstream with Base64 encoding and INI parsing. This is massively overengineered for our needs. The assembly version should write a simple 4-byte binary file (just the uint32 score value).

**Darwin syscall numbers (ARM64, raw -- no 0x2000000 prefix on ARM64):**
```
open  = 5   // x16 = 5, x0 = path, x1 = flags, x2 = mode
read  = 3   // x16 = 3, x0 = fd, x1 = buf, x2 = count
write = 4   // x16 = 4, x0 = fd, x1 = buf, x2 = count  (already used in main.s!)
close = 6   // x16 = 6, x0 = fd
```

**Note:** main.s already uses `write(2)` syscall to stderr for frame timing stats. The pattern is established:
```asm
mov  x0, #2          // fd
mov  x1, sp          // buf
sub  x2, x9, x2      // len
mov  x16, #4         // write
svc  #0x80
```

**File path approach:**
- Hardcode path as string in data.s: `.asciz "/tmp/yetris-asm-hiscore"` (simple, works without HOME lookup)
- Or use `_getenv("HOME")` to construct `~/.yetris-asm-hiscore` (more proper, requires calling C library getenv)

Recommended: Use `/tmp/yetris-asm-hiscore` for v1.1 simplicity, since the C++ version already uses a profile-specific path under the user directory. We can match the C++ path in a future version. Actually, better: use the existing `_getenv` from libSystem (already linked) to get HOME, then construct the path.

**New file: `hiscore.s`**
```
Exports:
  _load_hiscore()   -- read 4 bytes from file into _hi_score, or set 0 if file missing
  _save_hiscore()   -- write _hi_score to file (only if > previously loaded value)
  _check_hiscore()  -- compare current _score with _hi_score, update if higher

Data:
  _hi_score:       .word 0        // loaded from file
  _hiscore_path:   .space 256, 0  // constructed path buffer
  _str_hiscore_filename: .asciz "/.yetris-asm-hiscore"
  _str_home:       .asciz "HOME"
```

Estimated size: 100-150 lines.

**Integration points:**
- `_main` initialization: call `_load_hiscore` after ncurses init
- `Lgame_over_screen` in main.s: call `_check_hiscore` then `_save_hiscore`
- `_draw_score_panel` in render.s: display `_hi_score` above current score

### Feature 7: ASCII Art Logo

**What changes:** Add the C++ yetris ASCII art logo to the menu screen.

**C++ reference logo (from LayoutMainMenu.cpp):**
```
 __ __    ___ ______  ____   ____ _____
|  |  |  /  _]      ||    \ |    / ___/
|  |  | /  [_|      ||  D  ) |  (   \_
|  ~  ||    _]_|  |_||    /  |  |\__  |
|___, ||   [_  |  |  |    \  |  |/  \ |
|     ||     | |  |  |  .  \ |  |\    |
|____/ |_____| |__|  |__|\_||____|\___|
```

This is 7 lines, ~40 chars wide. Store as 7 `.asciz` strings in data.s, with a pointer table in `__DATA,__const`.

**Integration:** In `_menu_frame` (menu.s), draw the logo strings at rows 1-7, centered. Replace the current `"Y E T R I S"` title with the full ASCII art.

### Feature 8: Color on UI Elements

**What changes:** Add color attributes to menu labels, score panel labels, stats labels. Currently everything is plain white.

**New color pairs needed (extending `_init_colors`):**
```
Pair  8: White on Black (bold) -- UI labels
Pair  9: Cyan on Black -- borders, highlights
Pair 10: Yellow on Black (bold) -- selected menu item / score values
Pair 11: Red on Black (bold) -- fire animation
Pair 12: Blue on Black -- water animation
Pair 13: Blue on Black (bold) -- water animation bright
Pair 14: Cyan on Black (bold) -- water animation bright
```

**Approach:** Before each `waddstr` or `waddch` call that draws a label, call `wattr_on` with the appropriate `COLOR_PAIR(n) | A_BOLD` attribute. After drawing, call `wattr_off`.

The `COLOR_PAIR(n)` macro on ncurses encodes as `(n << 8)`. In assembly:
```asm
// COLOR_PAIR(8) | A_BOLD = (8 << 8) | 0x200000 = 0x800 | 0x200000 = 0x200800
movz  w1, #0x0800              // COLOR_PAIR(8) = 8 << 8
movk  w1, #0x0020, lsl #16    // | A_BOLD = 0x200000
```

---

## New Files Summary

| New File | Purpose | Estimated Lines | Dependencies |
|----------|---------|-----------------|--------------|
| `score.s` | T-spin detection, combo/B2B scoring, perfect clear | 200-300 | board.s (called from _lock_piece), data.s |
| `animation.s` | 4 background animations (fire, water, snakes, life) | 400-600 | render.s (called from _render_frame), data.s, timer.s |
| `hiscore.s` | File I/O for hi-score persistence | 100-150 | data.s, libSystem (syscalls) |

## Modified Files Summary

| Existing File | Changes | Complexity |
|---------------|---------|------------|
| `data.s` | Add window pointers, scoring state, animation buffers, hiscore data, logo strings, new color pairs data | Medium (additive only, ~200 lines of new data) |
| `render.s` | Replace stdscr with subwindow pointers, add ACS borders, add color attributes to labels, render animation, handle line clear flash | High (extensive coordinate changes, new draw logic, ~500 lines modified/added) |
| `main.s` | Create/destroy subwindows at init/exit, call hiscore load/save, integrate line clear animation timing | Medium (~50 lines added) |
| `board.s` | Split _clear_lines into mark/execute phases, call score.s for T-spin and scoring | Medium (~80 lines modified) |
| `input.s` | Track _last_piece_was_rotation flag | Low (~10 lines added) |
| `piece.s` | Store kick index in _last_kick_index during _try_rotate | Low (~5 lines added) |
| `menu.s` | Draw ASCII logo, apply color attributes, use subwindows | Medium (~100 lines modified) |
| `timer.s` | No changes needed | None |
| `random.s` | No changes needed | None |

---

## Component Boundaries

### Data Flow for Modern Scoring

```
input.s                    piece.s                   board.s              score.s
_handle_input:             _try_rotate:              _lock_piece:         _detect_tspin:
  set _last_piece_           save kick index           if T-piece:          check 3-corner
  was_rotation=0             in _last_kick_index       call _detect_       rule using
  (on move)                                            tspin               _piece_rotation
  set =1                                               call _mark_full_    and board corners
  (on rotate)                                          lines
                                                       call _compute_      _compute_score:
                                                       score with           combo + b2b +
                                                       lines + tspin        level multiplier
                                                       type

                                                     _execute_clear:       _check_perfect_
                                                       shift rows down      clear:
                                                       (called after         NEON scan of
                                                       flash delay)          entire board
```

### Data Flow for Subwindow Rendering

```
main.s                         render.s
_main init:                    _render_frame:
  _newwin(24,80,0,0)             for each subwindow:
  _derwin for each panel           _werase(win)
  store WINDOW* in data.s          draw content with wmove/waddch
                                   _wnoutrefresh(win)
_main exit:                      _doupdate()  // single terminal write
  _delwin for each subwindow
  _delwin for main
  _endwin
```

### Data Flow for Animations

```
main.s                    animation.s                  render.s
game init:                _init_animation:             _render_frame:
  call _init_animation      fill buffers based on        call _update_animation
  with selected type        type (random seeds etc)      call _draw_animation
                                                          (writes to _win_board)
game exit:                _update_animation:             THEN draw locked blocks
  call _reset_animation     check timer elapsed           on top (overwrite
                            advance simulation             animation chars)
```

---

## Recommended Build Order

### Phase 1: Subwindow Foundation (build first -- everything depends on this)

1. Add new window pointer globals to data.s
2. Create windows in main.s init, destroy in exit
3. Convert render.s to use subwindow pointers (change all stdscr references)
4. Convert menu.s to use subwindow pointers
5. Add box/border drawing with ACS characters
6. Verify all panels render correctly in their subwindows

**Rationale:** Subwindows change the coordinate system that everything else depends on. Do this first so all subsequent features use window-relative coordinates from the start.

### Phase 2: Visual Polish (independent of scoring/animation)

1. Extend _init_colors with new color pairs (8-14)
2. Add color attributes to score panel labels in render.s
3. Add color attributes to menu items in menu.s
4. Add ASCII art logo to data.s and menu.s
5. Add window titles (e.g., "Hold", "Next", "Statistics")

**Rationale:** Pure additive, low risk. Makes the game look complete. Can be done quickly after subwindows are working.

### Phase 3: Modern Scoring (modifies game logic)

1. Add scoring state variables to data.s
2. Create score.s with _detect_tspin and _compute_score
3. Modify input.s to track _last_piece_was_rotation
4. Modify piece.s to store _last_kick_index
5. Modify board.s _lock_piece to call T-spin detection before clearing
6. Replace inline score lookup in _clear_lines with _compute_score call
7. Add perfect clear detection

**Rationale:** Scoring changes are contained to the lock/clear path. The T-spin detection is the trickiest part (3-corner rule), so isolating it in score.s with clear inputs makes it testable.

### Phase 4: Line Clear Animation (requires Phase 1 subwindows + Phase 3 scoring)

1. Split _clear_lines into _mark_full_lines and _execute_clear
2. Add _pending_clear_count to data.s
3. Add flash rendering in _render_frame (value 9 cells as bright white)
4. Add delay between mark and execute in game loop
5. Integrate with _compute_score (scoring happens at mark time, before visual clear)

**Rationale:** Depends on subwindow rendering being stable, and on the scoring refactor (mark/execute split).

### Phase 5: Background Animations (requires Phase 1 subwindows)

1. Add animation buffers to data.s
2. Create animation.s with init/update/draw for all 4 types
3. Integrate _update_animation + _draw_animation into _render_frame
4. Add animation type selection to menu settings (new menu option)

**Rationale:** Most complex new code but self-contained. Does not affect game logic. Render integration is straightforward once subwindows work.

### Phase 6: Hi-Score Persistence (can be done anytime)

1. Add hiscore data to data.s
2. Create hiscore.s with file I/O via Darwin syscalls
3. Call _load_hiscore in main.s init
4. Call _check_hiscore + _save_hiscore at game over
5. Display _hi_score in score panel render

**Rationale:** Fully independent of other features. Simple file I/O. Can be done in any order, but logically comes after scoring is finalized.

---

## Scalability Considerations

| Concern | Current (v1.0) | After v1.1 |
|---------|----------------|------------|
| File count | 9 files | 12 files (+score.s, +animation.s, +hiscore.s) |
| Total lines | ~5,300 | ~7,500-8,000 estimated |
| Binary size | 52KB stripped | ~65-70KB estimated (animation buffers are data, not code) |
| __DATA size | ~1KB | ~5KB (animation buffers dominate) |
| ncurses calls | wmove/waddch/wrefresh | +newwin/derwin/delwin/box/wnoutrefresh/doupdate |
| Frame time | ~42us avg | ~50-80us estimated (animation update + more draws) |

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Refreshing Each Subwindow Individually
**What:** Calling `_wrefresh` on each subwindow separately.
**Why bad:** Each `_wrefresh` is a separate terminal write. With 6+ windows, this means 6+ writes per frame instead of 1.
**Instead:** Use `_wnoutrefresh` on each window (marks virtual screen dirty), then one `_doupdate` at the end (single terminal write). This is 3-4x fewer syscalls.

### Anti-Pattern 2: Dynamic Memory for Animation Buffers
**What:** Using `_malloc`/`_free` to allocate animation grids.
**Why bad:** Adds complexity, potential leaks, and the sizes are known at compile time.
**Instead:** Static `.space` directives in data.s. The board dimensions are fixed (20x20). Pre-allocate worst-case buffers.

### Anti-Pattern 3: Variadic Printf for Score Display
**What:** Using `_mvwprintw` for number formatting.
**Why bad:** Variadic calling convention on Darwin ARM64 puts non-fixed args on the stack, not registers. The existing codebase carefully avoids this with manual integer-to-ASCII conversion.
**Instead:** Continue using the divide-by-10 loop approach from render.s (Ldraw_number pattern). Extend it for larger numbers if needed.

### Anti-Pattern 4: Storing Window Handles in Registers
**What:** Keeping WINDOW* pointers in callee-saved registers across the game loop.
**Why bad:** x19-x28 are already heavily used. x28 is a packed bitfield. Adding 6+ window pointers exceeds available callee-saved registers.
**Instead:** Store all WINDOW* pointers in data.s globals. Load them fresh in each draw function with `adrp+add` (one instruction pair). This matches the existing pattern for all other globals.

### Anti-Pattern 5: Inline Animation Code in render.s
**What:** Adding 500+ lines of animation logic directly to the already-1700-line render.s.
**Why bad:** render.s is already the largest file. Adding animations would make it unmanageable.
**Instead:** Separate `animation.s` file. render.s just calls `_update_animation` and `_draw_animation`.

---

## Sources

- ncurses window functions: [curs_window(3x)](https://invisible-island.net/ncurses/man/curs_window.3x.html)
- ncurses border functions: [border(3)](https://pubs.opengroup.org/onlinepubs/7908799/xcurses/border.html) and [wborder(3)](https://linux.die.net/man/3/wborder)
- derwin documentation: [derwin(3)](https://linux.die.net/man/3/derwin)
- Darwin ARM64 syscalls: [HelloSilicon](https://github.com/below/HelloSilicon) and [M1 macOS ARM64 assembly](https://gist.github.com/zeusdeux/bb5b5b0aac1a39d4f9cec0d4f9a44ffb)
- Apple ARM64 ABI: [Writing ARM64 code for Apple platforms](https://developer.apple.com/documentation/xcode/writing-arm64-code-for-apple-platforms)
- C++ reference code: yetris source at `src/Game/`, `deps/Engine/Graphics/Animation/`
- Existing assembly codebase: all 9 `.s` files in `asm/` directory (read in full)
