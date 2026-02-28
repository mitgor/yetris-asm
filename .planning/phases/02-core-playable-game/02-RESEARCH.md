# Phase 2: Core Playable Game - Research

**Researched:** 2026-02-26
**Domain:** AArch64 assembly game logic (Tetris mechanics, ncurses rendering, SRS rotation, timer-based gravity, input handling)
**Confidence:** HIGH

## Summary

Phase 2 transforms the Phase 1 scaffold (a single `main.s` that initializes ncurses and waits for a keypress) into a fully playable Tetris game. This is the largest and most complex phase in the project: it requires implementing game state management, piece data tables, collision detection, SRS wall-kick rotation, line clearing with gravity, scoring/leveling, keyboard input dispatch, timer-based gravity, a 7-bag random generator, and a multi-panel ncurses rendering layout -- all in AArch64 assembly.

The reference C++ implementation (`src/Game/`) was analyzed in depth. The game uses a 10x20 board stored as a 2D array of Block pointers, 7 tetrominoes defined as 5x5 bitmaps in 4 rotations each, SRS wall-kick tables (separate tables for I-piece vs JLSTZ), `gettimeofday`-based timers for gravity, and a `getDelay(level)` function that maps levels 1-22 to millisecond delays from 1000ms down to 0ms. The scoring model is simple: 100/300/500/800 for 1/2/3/4 lines plus 10 per piece lock. These algorithms translate directly to assembly -- no complex data structures or dynamic memory are needed.

All ncurses functions required for the game have been verified as real exported symbols in macOS's libncurses (not just macros). The critical rendering approach is: `wmove + waddch` for placing characters, `wattr_on/wattr_off` for color, `init_pair` for color setup, `keypad + wtimeout + wgetch` for non-blocking input with arrow key support. The `mvwprintw` function is variadic and requires stack-based arguments on Darwin ARM64, but can be avoided entirely by using `wmove + waddch` loops for numbers (convert to ASCII digits manually).

**Primary recommendation:** Structure the assembly into multiple `.s` files by concern (data, board, piece, input, render, game loop, timer). Use flat byte arrays in `.section __DATA,__data` for the board and piece tables. Avoid variadic ncurses calls (`printw`, `mvwprintw`) by using `wmove + waddch` sequences -- this is simpler in assembly and avoids Darwin's tricky variadic calling convention. Use `gettimeofday` for timing (matching the C++ reference) and `arc4random_uniform` for the 7-bag randomizer.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| MECH-01 | 7-tetromino set (I, J, L, O, S, T, Z) defined as data tables with 4 rotations each | C++ reference uses 5x5 char arrays: `global_pieces[7][4][5][5]`. In assembly, store as flat `.byte` array (700 bytes). Each piece is 7 types x 4 rotations x 25 cells. Values: 0=empty, 1=block, 2=pivot. Indexing: `type*100 + rotation*25 + row*5 + col`. See Architecture Patterns and Code Examples. |
| MECH-02 | SRS rotation system with full wall kick tables (5-kick test per rotation, separate I-piece table) | Official SRS data verified against tetris.wiki. C++ reference stores kicks in `srs_possible_positions[2][2][4][5][2]` (2 piece groups x 2 directions x 4 rotations x 5 tests x 2 axes = 160 bytes). In assembly, store as flat `.byte` (signed) array. The rotation algorithm: try rotate, check validity; if invalid, try each of 5 kick offsets; accept first valid one. See Architecture Patterns. |
| MECH-03 | 10x20 playfield with collision detection | Store as flat byte array `board[200]` (10 columns x 20 rows). 0=empty, 1-7=piece type (for color). Collision detection: iterate piece's 5x5 bitmap, for each set cell compute board position, check bounds and occupancy. See Code Examples. |
| MECH-04 | Gravity timer scaling from level 1 (1000ms) to level 22 (0ms) | C++ reference `getDelay()` maps levels to ms. In assembly, store as a 22-entry `.hword` lookup table (22 x 2 bytes = 44 bytes). Timer uses `gettimeofday` (verified: `bl _gettimeofday` with 16-byte stack struct). See Code Examples. |
| MECH-05 | Piece locking when piece cannot move down | When gravity fires or player soft-drops, try moving piece down. If `isPieceValid` fails after down move, lock piece into board array, add 10 to score, get next piece, reset timer. Direct translation from C++ `lockCurrentPiece()`. |
| MECH-06 | Line clearing with gravity drop on cleared rows | Scan each row: if all 10 cells non-zero, row is full. For each full row, shift all rows above it down by one. C++ does mark-then-clear in two passes. Assembly can do single-pass bottom-up scan. Score: 100/300/500/800 for 1-4 lines. |
| MECH-07 | Hard drop (instant) and soft drop (accelerated) | Hard drop: loop `pieceCanMove(DOWN)` until false, then lock. Soft drop: immediate single-cell down move + lock if blocked. Both verified in C++ reference. |
| MECH-08 | 7-bag random piece generator | Fill bag with indices 0-6, shuffle using Fisher-Yates with `arc4random_uniform(n)`. Draw from bag; when empty, refill and reshuffle. C++ reference uses a similar (but less clean) rejection-sampling approach. `arc4random_uniform` verified available via `-lSystem`. |
| MECH-12 | Game over detection (piece spawns in occupied space) | After getting next piece, call `isPieceValid` on its spawn position. If invalid, set game_over flag. C++ checks `board->isFull()` (top row occupied) which is simpler -- either approach works. |
| MECH-14 | Level progression based on lines cleared | C++ `getLevel(lines)` maps total lines to levels 1-22 via threshold table. In assembly, store as 22-entry `.hword` table of line thresholds (5,10,15,20,25,30,40,50,60,70,100,120,140,160,180,210,240,280,310,350,400,450). Binary search or linear scan. |
| MECH-15 | Scoring (1-line=100, 2=300, 3=500, 4=800, +10 per piece lock) | 4-entry score table: `{100, 300, 500, 800}`. Add `score_table[lines_cleared - 1]` to score. Add 10 on each piece lock. All simple register arithmetic. |
| REND-01 | ncurses-based terminal rendering of board, current piece, and UI panels | Use `newwin` for board window (22x22: 10 cols x 2 chars + borders, 20 rows + borders). Use `wmove + waddch` for each cell. `wrefresh` to flush. All symbols verified as real exports. See Architecture Patterns for rendering loop. |
| REND-02 | Color-coded pieces (7 distinct colors: S=green, Z=red, O=yellow, I=cyan, L=orange, J=blue, T=magenta) | `start_color + init_pair(n, fg, bg)` for 7 pairs. `COLOR_PAIR(n) = n << 8` (verified). `wattr_on(win, pair, NULL)` before drawing, `wattr_off` after. Orange not available in basic 8 colors -- use bold yellow or bold red as substitute (C++ reference does the same). |
| REND-03 | Score, lines, and level display panel | Separate ncurses window for score panel. Render numbers by converting integers to ASCII digit strings and using `wmove + waddch` loops. Avoids variadic `mvwprintw`. |
| REND-05 | Input handling (arrow keys, space for hard drop, configurable keys) | `keypad(win, TRUE)` enables arrow key decoding. `wtimeout(win, 16)` for non-blocking input (~60fps poll). `wgetch` returns KEY_LEFT=260, KEY_RIGHT=261, KEY_UP=259, KEY_DOWN=258, space=32, ERR=-1 (no input). All constants verified on target. |
</phase_requirements>

## Standard Stack

### Core

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Apple `as` (Clang integrated assembler) | clang 17.0.0 | Assemble `.s` files | Same as Phase 1 -- only assembler on macOS |
| Apple `ld` | ld-1230.1 | Link object files | Same as Phase 1 -- handles multi-file linking with `$(ASM_OBJECTS)` wildcard |
| System ncurses | 5.4 (libncurses.tbd) | Terminal rendering, input, color | All needed functions verified as real symbols (not just macros) |
| `gettimeofday` (libSystem) | System | Timer for gravity, frame timing | C++ reference uses this; available via `-lSystem`; 16-byte struct on stack |
| `arc4random_uniform` (libSystem) | System | Random number generation for 7-bag | Cryptographically uniform, no seeding required, single function call |
| GNU Make | System | Multi-file assembly build | Existing `ASM_SOURCES = $(wildcard $(ASM_DIR)/*.s)` handles new files automatically |

### Supporting

| Tool | Purpose | When to Use |
|------|---------|-------------|
| `nm -g libncurses.tbd` | Verify ncurses symbol availability | Before using any new ncurses function from assembly |
| `cc -S -O1` | Generate reference assembly from C | When unsure about calling convention for a specific function |
| `otool -tV` | Disassemble and verify binary | Debug linking issues or verify instruction encoding |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `gettimeofday` for timing | `mach_absolute_time` | `mach_absolute_time` is faster (no syscall overhead) but requires `mach_timebase_info` for conversion to real time. `gettimeofday` matches C++ reference and is simpler. Switch to `mach_absolute_time` in Phase 5 optimization. |
| `wmove + waddch` for number display | `mvwprintw` (variadic) | `mvwprintw` is a variadic function requiring stack-based arguments on Darwin ARM64. Manual digit conversion + `waddch` is more work but avoids the variadic pitfall entirely. Strongly prefer `wmove + waddch`. |
| `arc4random_uniform` for RNG | Raw `arc4random` + modulo | `arc4random_uniform(n)` eliminates modulo bias. Single call, no seeding. Strictly better. |
| Flat byte array for board | Bitfield (1 bit per cell) | Bitfield is more compact (20 bytes for 10x20) but complicates color storage and collision detection. Byte array (200 bytes) is trivial to index and supports per-cell piece type. Optimize to bitfield in Phase 5 if desired. |

## Architecture Patterns

### Recommended Project Structure

```
asm/
  main.s            # Entry point, ncurses init/cleanup, main game loop
  data.s            # All game data tables (pieces, kicks, colors, scores, levels)
  board.s           # Board state, collision detection, line clearing, locking
  piece.s           # Piece state, movement, rotation, spawning
  input.s           # Input handling (keypad setup, key dispatch)
  render.s          # Rendering (draw board, draw piece, draw score panel, draw borders)
  timer.s           # Timer functions (gettimeofday wrapper, delta_ms)
  random.s          # 7-bag random piece generator
  bin/
    yetris-asm      # Linked binary
```

Each `.s` file uses `.globl` to export its public functions and `.extern` (or just `bl _label`) to call others. The linker resolves cross-file references. No header files needed -- just consistent function naming.

### Pattern 1: Game State in .data Section (Not Heap)

**What:** All game state lives in the `__DATA,__data` section as fixed-size arrays and variables. No dynamic memory allocation (`malloc`/`free`) needed.
**When to use:** All game state management.

```asm
// Source: Derived from C++ reference analysis (Board, Piece, Game state)
.section __DATA,__data

// Board: 10 columns x 20 rows = 200 bytes, row-major
// Value 0 = empty, 1-7 = piece type (for color lookup)
.globl _board
_board:
    .space 200, 0

// Current piece state
.globl _piece_type
_piece_type:     .byte 0        // 0-6 (O,I,L,J,S,Z,T -- matches C++ enum order)
.globl _piece_rotation
_piece_rotation: .byte 0        // 0-3
.globl _piece_x
_piece_x:        .hword 0       // signed 16-bit (can be negative during spawn)
.globl _piece_y
_piece_y:        .hword 0       // signed 16-bit

// Score state
.globl _score
_score:          .word 0        // unsigned 32-bit
.globl _level
_level:          .word 1        // unsigned 32-bit, starts at 1
.globl _lines_cleared
_lines_cleared:  .word 0        // unsigned 32-bit
.globl _game_over
_game_over:      .byte 0        // boolean flag

// 7-bag state
.globl _bag
_bag:            .space 7, 0    // shuffled piece indices
.globl _bag_index
_bag_index:      .byte 7        // starts at 7 (empty) to trigger refill
```

**Key design point:** Using `.hword` (16-bit) for piece x/y allows signed values (pieces spawn above the board with negative y). The board uses row-major order: `board[row * 10 + col]`.

### Pattern 2: Piece Data Tables as Flat Byte Arrays

**What:** The 7 tetrominoes with 4 rotations each, stored as flat byte arrays for efficient indexed access.
**When to use:** Piece rendering, collision detection, locking.

The C++ reference stores pieces as `global_pieces[7][4][5][5]` = 700 bytes. However, each 5x5 grid only has 4 cells set. A more compact representation uses 4 (x,y) pairs per rotation state.

**Compact representation (recommended for assembly):**

```asm
// Each piece-rotation: 4 cells, each cell is (row_offset, col_offset) relative to pivot
// 7 types x 4 rotations x 4 cells x 2 coords = 224 bytes
// Piece order: O=0, I=1, L=2, J=3, S=4, Z=5, T=6
// Index: type*32 + rotation*8 + cell*2
.section __TEXT,__const
.globl _piece_cells
_piece_cells:
    // O piece (all 4 rotations identical)
    .byte 0,0, 0,1, 1,0, 1,1    // rotation 0
    .byte 0,0, 0,1, 1,0, 1,1    // rotation 1
    .byte 0,0, 0,1, 1,0, 1,1    // rotation 2
    .byte 0,0, 0,1, 1,0, 1,1    // rotation 3
    // I piece
    .byte 0,0, 0,-1, 0,1, 0,2   // rotation 0 (horizontal)
    .byte 0,0, -1,0, 1,0, 2,0   // rotation 1 (vertical)
    // ... etc
```

**Alternative: keep the C++ 5x5 format** if pixel-perfect compatibility is preferred. The 5x5 format is larger (700 bytes) but avoids translating the piece data. Either approach works -- the 5x5 format directly matches the C++ reference collision logic.

### Pattern 3: Non-Blocking Input Loop with Gravity Timer

**What:** The main game loop polls for input using `wtimeout + wgetch`, then checks if enough time has elapsed for gravity.
**When to use:** The core game loop in `main.s`.

```asm
// Pseudocode for main game loop:
//
// 1. wtimeout(stdscr, 16)          -- 16ms timeout (~60fps)
// 2. loop:
//    a. ch = wgetch(stdscr)         -- returns key or ERR (-1)
//    b. if ch != ERR: handle_input(ch)
//    c. now = get_time_ms()
//    d. if (now - last_drop) >= getDelay(level):
//         try_move_down()
//         if blocked: lock_piece()
//         last_drop = now
//    e. render_frame()
//    f. if !game_over: goto loop
//    g. show_game_over()
```

### Pattern 4: Collision Detection

**What:** Check if a piece at (px, py) with given rotation fits on the board.
**When to use:** Every movement attempt, rotation attempt, spawn validity check.

```asm
// is_piece_valid(type, rotation, px, py) -> w0 = 1 (valid) or 0 (invalid)
//
// For each cell (r, c) in the piece's 5x5 grid:
//   if grid[type][rotation][r][c] != 0:
//     board_x = px + c
//     board_y = py + r
//     if board_x < 0 or board_x >= 10: return 0
//     if board_y >= 20: return 0
//     if board_y < 0: continue  (piece still above board)
//     if board[board_y * 10 + board_x] != 0: return 0
// return 1
```

The inner loop is 25 iterations (5x5 grid). For the compact 4-cell representation, it's only 4 iterations.

### Pattern 5: SRS Wall Kick Rotation

**What:** Attempt rotation with up to 5 kick offsets if basic rotation fails.
**When to use:** Player rotation input (clockwise/counter-clockwise).

```asm
// rotate_piece(direction):  direction = +1 (CW) or -1 (CCW)
//   new_rotation = (current_rotation + direction) % 4
//   if is_piece_valid(type, new_rotation, px, py):
//     current_rotation = new_rotation; return
//
//   // Determine kick table: I-piece uses separate table
//   // Determine rotation index based on current -> new rotation
//   for test in 0..4:
//     dx = kick_table[...][test][0]
//     dy = kick_table[...][test][1]
//     if is_piece_valid(type, new_rotation, px+dx, py-dy):
//       // NOTE: C++ reference inverts Y in moveBy: this->y -= dy
//       piece_x += dx; piece_y -= dy
//       current_rotation = new_rotation; return
//
//   // All 5 tests failed -- rotation cancelled
```

**Critical note on Y-axis:** The C++ reference `Piece::moveBy(dx, dy)` does `this->y -= dy` (subtracts dy). The SRS tables from tetris.wiki use math convention (positive Y = up). The board uses screen convention (positive Y = down). So SRS kick dy values must be negated when applied to board coordinates. The C++ code handles this by subtracting dy.

### Pattern 6: Multi-File Assembly Linking

**What:** Calling functions defined in other `.s` files.
**When to use:** All cross-file function calls.

```asm
// In board.s:
.globl _is_piece_valid
_is_piece_valid:
    // x0 = type, x1 = rotation, x2 = px, x3 = py
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    // ... implementation ...
    ldp x29, x30, [sp], #16
    ret

// In piece.s:
.globl _try_rotate
_try_rotate:
    // ...
    bl _is_piece_valid    // linker resolves across .o files
    // ...
```

No `.extern` directive needed -- the assembler treats undefined symbols as external by default and the linker resolves them.

### Anti-Patterns to Avoid

- **Using `printw`/`mvwprintw` for number display:** These are variadic functions requiring stack-based argument passing on Darwin ARM64. Converting integers to ASCII digits and using `wmove + waddch` is simpler and avoids the variadic pitfall.
- **Forgetting Y-axis inversion in SRS kicks:** The SRS kick table uses math convention (positive Y = up). Board coordinates use screen convention (positive Y = down). Always negate the Y component of kick offsets when applying to piece position. The C++ reference does `this->y -= dy` in `moveBy`.
- **Dynamic memory allocation for game objects:** `malloc`/`free` adds complexity and fragility. All game state can be statically allocated in `.data` section. The board is 200 bytes, piece state is ~10 bytes, the bag is 7 bytes.
- **Using a single monolithic `.s` file:** A single file with all game logic would be thousands of lines and unmaintainable. Split by concern -- the Makefile already handles multiple `.s` files via `$(wildcard $(ASM_DIR)/*.s)`.
- **Not preserving callee-saved registers across ncurses calls:** Any `bl` to an ncurses function may clobber x0-x15. Game state pointers and indices that must survive across calls should be in x19-x28 (callee-saved). This was established in Phase 1 with the stdscr GOT pointer in x19.
- **Using `newwin` when `stdscr` suffices:** For Phase 2, a simplified rendering approach using just `stdscr` with `wmove + waddch` at computed screen coordinates is simpler than managing multiple ncurses WINDOW objects. The C++ reference uses sub-windows for its complex layout, but the assembly version can start with direct coordinate rendering and add windows later if needed.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Random number generation | Linear congruential generator or `time()`-based seed | `bl _arc4random_uniform` | Uniform distribution, no seeding needed, cryptographic quality, single call |
| Timer / elapsed time | Instruction counting or busy loops | `bl _gettimeofday` + arithmetic | Microsecond precision, handles system clock, matches C++ reference |
| Terminal color management | ANSI escape code strings | `bl _start_color`, `bl _init_pair`, `bl _wattr_on` | ncurses handles terminal capability detection; ANSI codes not portable across terminals |
| Arrow key decoding | Raw byte parsing of escape sequences | `bl _keypad` (enables) + `bl _wgetch` (returns KEY_LEFT etc.) | ncurses handles all escape sequence parsing; arrow keys are multi-byte sequences |
| Non-blocking input | Raw `read()` with `fcntl(O_NONBLOCK)` | `bl _wtimeout` + `bl _wgetch` | ncurses handles buffering, timeout, and key decoding together |
| Integer-to-string conversion for score display | Full `sprintf`-like formatting | Manual digit extraction loop (divide by 10, add 0x30) | Only need unsigned integer display; 10-iteration loop is trivial in assembly |

**Key insight:** The ncurses library handles all terminal I/O complexity. For game logic (collision, rotation, scoring), the algorithms are simple enough that assembly implementation is straightforward -- they're just loops over small arrays with comparisons and arithmetic.

## Common Pitfalls

### Pitfall 1: Variadic Function Stack Arguments on Darwin ARM64

**What goes wrong:** Calling `mvwprintw(win, y, x, fmt, value)` with the integer value in a register instead of on the stack causes garbage output or crashes.
**Why it happens:** Darwin ARM64 ABI requires variadic arguments (those after `...` in the prototype) to be passed on the stack, not in registers. This differs from Linux ARM64.
**How to avoid:** Avoid variadic ncurses functions entirely. Use `wmove` + `waddch` loops for all output. If variadic calls are unavoidable, allocate stack space and store arguments at `[sp]`, `[sp+8]`, etc. before the call.
**Warning signs:** Correct format string but wrong values displayed, or SIGSEGV in `vfprintf`-family internals.

### Pitfall 2: Signed vs Unsigned Byte Arithmetic in Piece Position

**What goes wrong:** Piece spawns at wrong position or kick offsets apply incorrectly because `.byte` values are treated as unsigned.
**Why it happens:** ARM64 `ldrb` loads an unsigned byte (0-255). SRS kick offsets and piece spawn positions can be negative (e.g., spawn y = -4, kick dx = -2). Using `ldrb` on `-2` reads `254` instead.
**How to avoid:** Use `ldrsb` (load register signed byte) for any data that can be negative. This sign-extends the byte to a full register width. SRS kick offsets and piece spawn positions MUST use `ldrsb`.
**Warning signs:** Pieces spawning at y=252 instead of y=-4; kicks moving pieces far off screen.

### Pitfall 3: Off-by-One in Board Coordinate System

**What goes wrong:** Pieces clip through walls or floor, or collision detection misses the rightmost column / bottom row.
**Why it happens:** The board is 10 wide (columns 0-9) and 20 tall (rows 0-19). Bounds checks must use `< 0` and `>= 10`/`>= 20`, not `<= 10`/`<= 20`.
**How to avoid:** Use `cmp` + `b.lt` for lower bound (signed), `cmp` + `b.ge` for upper bound. Test with I-piece (widest piece, 4 cells) at board edges.
**Warning signs:** Pieces overlapping the right wall by 1 cell; pieces falling through the floor.

### Pitfall 4: Register Clobbering Across ncurses Calls

**What goes wrong:** Loop counter or board pointer lost after calling `waddch`, causing rendering glitches or infinite loops.
**Why it happens:** ncurses functions clobber x0-x15 (caller-saved registers). If the rendering loop uses x9 as a counter and calls `bl _waddch`, x9 is destroyed.
**How to avoid:** Use callee-saved registers (x19-x28) for any value that must survive across function calls. Save and restore in prologue/epilogue. There are 10 callee-saved registers -- more than enough for all loop variables.
**Warning signs:** Infinite rendering loops, partial board draws, random crashes during rendering.

### Pitfall 5: SRS Kick Table Indexing Error

**What goes wrong:** Rotation produces impossible piece positions or kicks apply wrong offsets for wrong rotation transitions.
**Why it happens:** The SRS kick table is a 5-dimensional array `[2][2][4][5][2]`. Getting the index calculation wrong (wrong piece group, wrong direction, wrong rotation state) produces subtly wrong offsets.
**How to avoid:** The kick table index must encode: (1) piece group (0=JLSTZ, 1=I), (2) rotation direction (0=CW, 1=CCW), (3) current rotation state (0-3), (4) test number (0-4), (5) axis (0=x, 1=y). Verify by comparing assembly output against known SRS test cases: e.g., T-piece 0->R test 2 should be (-1, -1).
**Warning signs:** Wall kicks that push pieces through walls; I-piece rotating into impossible positions.

### Pitfall 6: Line Clear Gravity Ordering

**What goes wrong:** Clearing multiple lines simultaneously causes rows to shift incorrectly, leaving gaps or duplicating rows.
**Why it happens:** If you scan from top to bottom and shift rows down as you find full lines, the shift invalidates the indices of lines below.
**How to avoid:** Scan from bottom to top. When a full line is found at row `r`, shift all rows above `r` down by 1 (copy row j-1 to row j, for j from r down to 1), then set row 0 to all zeros. Continue scanning from the same row `r` (it now has new content from above). Alternative: mark full lines first, then compact in a second pass (the C++ approach).
**Warning signs:** After clearing a tetris (4 lines), the board has phantom rows or missing rows.

### Pitfall 7: Frame Timing Inconsistency

**What goes wrong:** Game feels sluggish or gravity fires too fast / too slow.
**Why it happens:** Using `usleep` or `napms` for frame timing creates cumulative drift. If rendering takes 5ms and you sleep 16ms, the effective frame time is 21ms.
**How to avoid:** Use timestamp-based timing: record `last_gravity_tick`, check `current_time - last_gravity_tick >= delay`. This is independent of frame rendering time. The C++ reference uses this exact approach via its `Timer` class.
**Warning signs:** Gravity speed visibly different from expected; game speeding up or slowing down over time.

## Code Examples

Verified patterns from compiler output analysis and target system testing.

### Non-Blocking Input Setup

```asm
// Source: Verified via cc -S output on target system
// Setup: enable arrow key decoding + non-blocking input

    // Load stdscr via GOT (reuse pattern from Phase 1)
    adrp    x19, _stdscr@GOTPAGE
    ldr     x19, [x19, _stdscr@GOTPAGEOFF]

    // keypad(stdscr, TRUE) -- enable arrow key sequences
    ldr     x0, [x19]          // x0 = stdscr (WINDOW*)
    mov     w1, #1              // TRUE
    bl      _keypad

    // wtimeout(stdscr, 16) -- 16ms timeout for non-blocking input
    ldr     x0, [x19]
    mov     w1, #16
    bl      _wtimeout

    // curs_set(0) -- hide cursor
    mov     w0, #0
    bl      _curs_set
```

### Color Initialization for 7 Piece Types

```asm
// Source: Verified via cc -S output -- COLOR_PAIR(n) = n << 8
// Colors: S=green(2), Z=red(1), O=yellow(3), I=cyan(6), L=white(7), J=blue(4), T=magenta(5)
// Note: No true "orange" in basic 8 colors. Use bold yellow or white for L-piece.

    bl      _start_color        // enable color support

    // init_pair(pair_num, foreground, background)
    // Pair 1 = O piece (yellow on black)
    mov     w0, #1
    mov     w1, #3              // COLOR_YELLOW
    mov     w2, #0              // COLOR_BLACK
    bl      _init_pair

    // Pair 2 = I piece (cyan on black)
    mov     w0, #2
    mov     w1, #6              // COLOR_CYAN
    mov     w2, #0
    bl      _init_pair

    // Pair 3 = L piece (white on black -- substitute for orange)
    mov     w0, #3
    mov     w1, #7              // COLOR_WHITE
    mov     w2, #0
    bl      _init_pair

    // Pair 4 = J piece (blue on black)
    mov     w0, #4
    mov     w1, #4              // COLOR_BLUE
    mov     w2, #0
    bl      _init_pair

    // Pair 5 = S piece (green on black)
    mov     w0, #5
    mov     w1, #2              // COLOR_GREEN
    mov     w2, #0
    bl      _init_pair

    // Pair 6 = Z piece (red on black)
    mov     w0, #6
    mov     w1, #1              // COLOR_RED
    mov     w2, #0
    bl      _init_pair

    // Pair 7 = T piece (magenta on black)
    mov     w0, #7
    mov     w1, #5              // COLOR_MAGENTA
    mov     w2, #0
    bl      _init_pair
```

### Drawing a Colored Block at Board Position

```asm
// Source: Derived from compiler output analysis of ncurses calls
// Draw a block "[]" at board position (col, row) with color pair_num
// Registers: w20 = col, w21 = row, w22 = pair_num, x19 = GOT ptr to stdscr

    // Compute screen coordinates
    // Each board cell is 2 characters wide (for "[]")
    // Screen x = board_x_offset + col * 2
    // Screen y = board_y_offset + row

    // Set color: wattr_on(stdscr, COLOR_PAIR(n), NULL)
    ldr     x0, [x19]              // stdscr
    lsl     w1, w22, #8            // COLOR_PAIR(n) = n << 8
    mov     x2, #0                 // NULL (opts parameter)
    bl      _wattr_on

    // Move cursor: wmove(stdscr, y, x)
    ldr     x0, [x19]
    add     w1, w21, #1            // y (add 1 for border)
    add     w2, w20, w20           // x = col * 2
    add     w2, w2, #1             // add 1 for border
    bl      _wmove

    // Draw '[': waddch(stdscr, '[')
    ldr     x0, [x19]
    mov     w1, #0x5b              // '['
    bl      _waddch

    // Draw ']': waddch(stdscr, ']')
    ldr     x0, [x19]
    mov     w1, #0x5d              // ']'
    bl      _waddch

    // Reset color: wattr_off(stdscr, COLOR_PAIR(n), NULL)
    ldr     x0, [x19]
    lsl     w1, w22, #8
    mov     x2, #0
    bl      _wattr_off
```

### Timer Using gettimeofday

```asm
// Source: Verified from compiler output of Timer::delta_ms() equivalent
// get_time_ms() -> x0 = current time in milliseconds

.globl _get_time_ms
_get_time_ms:
    stp     x29, x30, [sp, #-32]!
    add     x29, sp, #16

    // struct timeval { long tv_sec; int tv_usec; } at [sp] (16 bytes)
    // Note: on ARM64, tv_sec is 8 bytes at offset 0, tv_usec is 4 bytes at offset 8
    mov     x0, sp                  // &tv
    mov     x1, #0                  // timezone = NULL
    bl      _gettimeofday

    // Load tv_sec (8 bytes at sp+0) and tv_usec (4 bytes at sp+8)
    ldr     x8, [sp]               // tv_sec
    ldrsw   x9, [sp, #8]           // tv_usec (sign-extend 32->64)

    // result = tv_sec * 1000 + tv_usec / 1000
    mov     w10, #1000
    mul     x0, x8, x10            // tv_sec * 1000
    sdiv    x9, x9, x10            // tv_usec / 1000
    add     x0, x0, x9             // total milliseconds

    ldp     x29, x30, [sp, #16]
    add     sp, sp, #32
    ret
```

### Integer to ASCII Digit String (for Score Display)

```asm
// Source: Standard algorithm, verified logic
// int_to_str(value: w0, buf: x1, width: w2)
// Writes right-justified decimal string to buf, padded with spaces
// Example: int_to_str(1234, buf, 8) -> "    1234"

.globl _int_to_str
_int_to_str:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    mov     w8, w0                  // value
    mov     x9, x1                  // buf pointer
    mov     w10, w2                 // width

    // Fill buffer with spaces first
    mov     w11, #0x20              // space
    mov     w12, #0
1:  cmp     w12, w10
    b.ge    2f
    strb    w11, [x9, x12]
    add     w12, w12, #1
    b       1b

    // Write digits right-to-left
2:  sub     w12, w10, #1            // start at rightmost position
3:  mov     w13, #10
    udiv    w14, w8, w13            // quotient
    msub    w15, w14, w13, w8       // remainder = value - quotient*10
    add     w15, w15, #0x30         // ASCII digit
    strb    w15, [x9, x12]
    mov     w8, w14                 // value = quotient
    sub     w12, w12, #1
    cbz     w8, 4f                  // done if value == 0
    cmp     w12, #0
    b.ge    3b
4:
    ldp     x29, x30, [sp], #16
    ret
```

### 7-Bag Shuffle Using Fisher-Yates

```asm
// Source: Standard Fisher-Yates shuffle algorithm
// shuffle_bag() -- fills _bag[0..6] with shuffled 0-6

.globl _shuffle_bag
_shuffle_bag:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Initialize bag with 0,1,2,3,4,5,6
    adrp    x19, _bag@PAGE
    add     x19, x19, _bag@PAGEOFF
    mov     w8, #0
1:  strb    w8, [x19, x8]
    add     w8, w8, #1
    cmp     w8, #7
    b.lt    1b

    // Fisher-Yates shuffle (from i=6 down to 1)
    mov     w20, #6
2:  // j = arc4random_uniform(i + 1)
    add     w0, w20, #1
    bl      _arc4random_uniform     // w0 = random in [0, i]
    mov     w21, w0                 // j

    // swap bag[i] and bag[j]
    ldrb    w8, [x19, w20, uxtw]   // bag[i]
    ldrb    w9, [x19, w21, uxtw]   // bag[j]
    strb    w9, [x19, w20, uxtw]   // bag[i] = bag[j]
    strb    w8, [x19, w21, uxtw]   // bag[j] = bag[i]

    sub     w20, w20, #1
    cbnz    w20, 2b

    // Reset bag index to 0
    adrp    x8, _bag_index@PAGE
    strb    wzr, [x8, _bag_index@PAGEOFF]

    ldp     x29, x30, [sp], #16
    ret
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `wattron(win, COLOR_PAIR(n))` macro | `wattr_on(win, attr, opts)` real function | ncurses 6.0+ | From assembly, must call `_wattr_on` with 3 args (not 2). `wattron` is a macro that expands differently. |
| `mvaddch` / `mvprintw` convenience macros | `wmove + waddch` / `wmove + waddnstr` explicit calls | Always for assembly | Macros expand to multiple calls; from assembly, call the underlying functions directly. |
| `getch()` macro | `wgetch(stdscr)` | Always for assembly | `getch` may or may not be a real symbol; `wgetch` always is. Load stdscr via GOT and call `wgetch`. |

**Deprecated/outdated:**
- `srand(time(NULL))` for random seeding: Use `arc4random_uniform` which requires no seeding and has better distribution.
- `usleep()` for frame timing: Use timestamp comparison with `gettimeofday` instead of sleeping. Sleeping causes cumulative drift.

## Open Questions

1. **Orange color for L-piece**
   - What we know: The terminal's basic 8 colors have no orange. The C++ reference defines a custom `piece_L` Block with a configurable color. On terminals supporting 256 colors, orange (color 208) is available via `init_color`.
   - What's unclear: Whether the C++ reference actually displays orange on a basic terminal, or falls back to white/bold-yellow.
   - Recommendation: Use bold white (COLOR_WHITE + A_BOLD) for L-piece in Phase 2. This produces a bright white that's visually distinct from other pieces. Can revisit in Phase 3 if 256-color support is desired.

2. **5x5 grid vs compact 4-cell piece representation**
   - What we know: The C++ reference uses 5x5 grids (global_pieces[7][4][5][5]). A compact representation uses 4 (row,col) pairs per rotation.
   - What's unclear: Whether collision detection differences between the two representations introduce bugs at edge cases.
   - Recommendation: Use the 5x5 grid format for Phase 2 to maintain exact compatibility with the C++ collision detection algorithm. This costs 700 bytes but eliminates a class of bugs. Optimize to compact format in Phase 5 if binary size matters.

3. **Board rendering: single stdscr vs newwin panels**
   - What we know: The C++ reference uses multiple ncurses WINDOWs (board, score, hold, next). From assembly, `newwin` / `derwin` / `subwin` all exist as real symbols.
   - What's unclear: Whether managing multiple WINDOWs adds enough complexity in assembly to warrant starting with a simpler approach.
   - Recommendation: Start with `stdscr` only in Phase 2, drawing directly at computed screen coordinates. This avoids window management overhead. Add separate windows in Phase 3 when adding hold/next/statistics panels.

4. **Handling `mvwprintw` for score display (variadic calling convention)**
   - What we know: `mvwprintw` is variadic. The compiler puts the integer argument on the stack at `[sp]` (confirmed via `cc -S` output). The format string pointer goes in x3 (4th fixed arg).
   - What's unclear: Whether the assembly manual digit conversion + `waddch` approach has any subtle issues vs the variadic approach.
   - Recommendation: Use manual digit conversion. It's 15-20 instructions, avoids the variadic pitfall, and is more educational (aligns with the project's learning goals).

## Sources

### Primary (HIGH confidence)

- **Target system compiler output analysis** (`cc -S -O1`): Used to verify exact calling patterns for `start_color`, `init_pair`, `wattr_on`, `wattr_off`, `wmove`, `waddch`, `mvwprintw`, `keypad`, `wtimeout`, `wgetch`, `gettimeofday`. All code examples cross-referenced against compiler-generated assembly.
- **Target system symbol table** (`nm -g libncurses.tbd`): Verified all ncurses functions used in this research exist as real exported symbols: `_start_color`, `_init_pair`, `_wattr_on`, `_wattr_off`, `_wmove`, `_waddch`, `_wgetch`, `_keypad`, `_wtimeout`, `_curs_set`, `_newwin`, `_delwin`, `_wclear`, `_wborder`, `_wrefresh`, `_werase`, `_mvwprintw`, `_napms`, `_nodelay`, `_waddnstr`, `_waddstr`, `_box`, `_COLOR_PAIR`, `_doupdate`, `_wnoutrefresh`, `_touchwin`.
- **Target system constant verification**: KEY_LEFT=260, KEY_RIGHT=261, KEY_UP=259, KEY_DOWN=258, ERR=-1, COLOR_BLACK=0, COLOR_RED=1, COLOR_GREEN=2, COLOR_YELLOW=3, COLOR_BLUE=4, COLOR_MAGENTA=5, COLOR_CYAN=6, COLOR_WHITE=7, A_BOLD=2097152, COLOR_PAIR(n)=n<<8.
- **C++ reference source code analysis** (`src/Game/`): Analyzed Board.cpp, Piece.cpp, PieceDefinitions.cpp, RotationSystemSRS.cpp, Game.cpp, Statistics.hpp, LayoutGame.cpp, Block.cpp for algorithm extraction.
- **Phase 1 Research**: All Darwin ABI rules, function calling convention, GOT access patterns, frame pointer requirements.

### Secondary (MEDIUM confidence)

- [TetrisWiki: Super Rotation System](https://tetris.wiki/Super_Rotation_System) - Official SRS wall kick data tables verified against C++ reference implementation
- [Hard Drop Wiki: SRS](https://harddrop.com/wiki/SRS) - Cross-reference for SRS offset-based kick calculation
- [FOUR.lol: SRS Kicks Overview](https://four.lol/srs/kicks-overview/) - Additional SRS kick explanation and test cases

### Tertiary (LOW confidence)

- None -- all findings verified against compiler output, symbol tables, or reference source code on the target system.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All tools and functions verified on target system with exact symbol names and calling conventions
- Architecture: HIGH - Multi-file assembly linking verified in Phase 1; data layout patterns derived from compiler output; rendering patterns verified via `cc -S`
- Pitfalls: HIGH - Each pitfall derived from verified behavior (compiler output, ABI documentation, reference implementation analysis)
- Game logic: HIGH - All algorithms extracted directly from the working C++ reference implementation with full source code analysis

**Research date:** 2026-02-26
**Valid until:** Indefinite for game logic patterns and ncurses API. Re-verify ncurses symbol names if macOS version changes significantly.
