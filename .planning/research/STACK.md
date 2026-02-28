# Technology Stack: v1.1 Additions

**Project:** yetris-asm v1.1 Visual Polish & Gameplay
**Researched:** 2026-02-27
**Confidence:** HIGH -- ncurses functions verified against macOS SDK headers, syscall numbers verified against darwin-xnu source, scoring formulas verified against tetris.wiki

---

## What This Document Covers

This STACK.md covers only the NEW technology needed for v1.1. The v1.0 stack (Apple `as`, `ld`, ncurses basics, libSystem, mach_absolute_time, NEON SIMD) is validated and unchanged. See the v1.0 STACK.md in the git history for foundational ABI/toolchain reference.

v1.1 adds three capability domains:
1. **ncurses subwindows and visual polish** -- newwin/derwin, wborder, ACS characters, expanded color pairs, wnoutrefresh/doupdate
2. **File I/O** -- Darwin syscalls for hi-score persistence
3. **Modern scoring** -- pure data/logic, no new libraries needed

---

## 1. ncurses Subwindow and Visual Polish Functions

### 1.1 Window Creation and Destruction

The C++ original uses `newwin` for top-level windows and `derwin` for child windows (subwindows with coordinates relative to parent). The assembly version currently draws everything on stdscr. v1.1 needs separate WINDOW* objects for board, hold, next, score, and statistics panels.

| Function | Signature | Purpose | Assembly Call Pattern |
|----------|-----------|---------|----------------------|
| `newwin` | `WINDOW* newwin(int nlines, int ncols, int begin_y, int begin_x)` | Create independent window at absolute screen position | `mov w0, #nlines; mov w1, #ncols; mov w2, #begin_y; mov w3, #begin_x; bl _newwin` -- returns WINDOW* in x0 |
| `derwin` | `WINDOW* derwin(WINDOW* orig, int nlines, int ncols, int begin_y, int begin_x)` | Create subwindow with coordinates relative to parent | `mov x0, <parent_win>; mov w1, #nlines; mov w2, #ncols; mov w3, #begin_y; mov w4, #begin_x; bl _derwin` -- returns WINDOW* in x0 |
| `delwin` | `int delwin(WINDOW* win)` | Free window memory (does not erase screen image) | `mov x0, <win>; bl _delwin` |
| `wresize` | `int wresize(WINDOW* win, int lines, int columns)` | Resize existing window | `mov x0, <win>; mov w1, #lines; mov w2, #cols; bl _wresize` |

**Critical note:** `derwin` coordinates are relative to parent origin; `subwin` coordinates are absolute screen positions. The C++ original uses `derwin` exclusively for child windows. Use `derwin` because it naturally expresses hierarchical layout.

**Window storage:** Store WINDOW* pointers in the `__DATA,__data` section. Each pointer is 8 bytes (`.quad 0`). Access via `adrp`/`add` with `@PAGE`/`@PAGEOFF` (local symbols, not GOT-indirect).

```asm
// Window pointer storage
.section __DATA,__data
.globl _win_board
.p2align 3
_win_board:     .quad 0     // board window (derwin of main)
_win_hold:      .quad 0     // hold piece panel
_win_next:      .quad 0     // next piece panel
_win_score:     .quad 0     // score/level panel
_win_stats:     .quad 0     // statistics panel (rightmost)
_win_main:      .quad 0     // main container (newwin)
```

### 1.2 Window Refresh Strategy

The C++ original uses `wnoutrefresh` for all windows followed by a single `refresh()` (which calls `doupdate`). This batches terminal writes for efficiency. The current assembly code calls `wrefresh(stdscr)` once per frame. With multiple windows, switch to the wnoutrefresh/doupdate pattern.

| Function | Signature | Purpose |
|----------|-----------|---------|
| `wnoutrefresh` | `int wnoutrefresh(WINDOW* win)` | Copy window to virtual screen (no terminal I/O) |
| `doupdate` | `int doupdate(void)` | Flush virtual screen to physical terminal (one burst) |
| `werase` | `int werase(WINDOW* win)` | Clear window contents (already used in v1.0 on stdscr) |

**Render loop pattern:**
```asm
// For each window: werase, draw content, wnoutrefresh
// ... draw all windows ...
// Final: doupdate to flush everything at once
bl      _doupdate
```

This replaces the current `wrefresh(stdscr)` call in `_render_frame`. The improvement is that with 5-6 windows, `wnoutrefresh` on each + one `doupdate` produces fewer terminal write operations than separate `wrefresh` calls.

### 1.3 Box-Drawing with ACS Characters and wborder

The C++ original supports two border styles:
- **BORDER_FANCY**: Uses ACS line-drawing characters with per-element color (shadows)
- **BORDER_REGULAR**: Uses ASCII `|`, `-`, `+` with dim color

For v1.1, implement fancy borders using `wborder`:

| Function | Signature | Purpose |
|----------|-----------|---------|
| `wborder` | `int wborder(WINDOW* win, chtype ls, chtype rs, chtype ts, chtype bs, chtype tl, chtype tr, chtype bl, chtype br)` | Draw border around window edges using specified characters |
| `box` | `int box(WINDOW* win, chtype verch, chtype horch)` | Shortcut: box(win, 0, 0) uses ACS defaults |

**wborder arguments:** ls=left side, rs=right side, ts=top side, bs=bottom side, tl=top-left corner, tr=top-right corner, bl=bottom-left corner, br=bottom-right corner. Pass 0 for any argument to use the ACS default.

**ACS character access from assembly:**

ACS characters are NOT simple constants. They are entries in the `acs_map` array (an exported ncurses global), indexed by ASCII character codes. The macro `NCURSES_ACS('q')` expands to `acs_map[(unsigned char)'q']`.

```asm
// Load ACS_HLINE (horizontal line): acs_map['q'] = acs_map[0x71]
adrp    x8, _acs_map@GOTPAGE
ldr     x8, [x8, _acs_map@GOTPAGEOFF]  // x8 = pointer to acs_map array
// acs_map is chtype[] where chtype is 32-bit unsigned int on macOS ncurses
mov     w9, #0x71                        // 'q' = ACS_HLINE index
ldr     w10, [x8, x9, lsl #2]           // w10 = ACS_HLINE value (chtype = 4 bytes)
```

**ACS character index table (ASCII codes for acs_map lookup):**

| ACS Constant | Index Char | ASCII Value | Visual |
|-------------|------------|-------------|--------|
| `ACS_ULCORNER` | `'l'` | 0x6C | upper-left corner |
| `ACS_LLCORNER` | `'m'` | 0x6D | lower-left corner |
| `ACS_URCORNER` | `'k'` | 0x6B | upper-right corner |
| `ACS_LRCORNER` | `'j'` | 0x6A | lower-right corner |
| `ACS_LTEE` | `'t'` | 0x74 | tee pointing right |
| `ACS_RTEE` | `'u'` | 0x75 | tee pointing left |
| `ACS_BTEE` | `'v'` | 0x76 | tee pointing up |
| `ACS_TTEE` | `'w'` | 0x77 | tee pointing down |
| `ACS_HLINE` | `'q'` | 0x71 | horizontal line |
| `ACS_VLINE` | `'x'` | 0x78 | vertical line |
| `ACS_PLUS` | `'n'` | 0x6E | crossover (+) |
| `ACS_DIAMOND` | `` '`' `` | 0x60 | diamond |
| `ACS_CKBOARD` | `'a'` | 0x61 | checkerboard (stipple) |
| `ACS_BLOCK` | `'0'` | 0x30 | solid block |
| `ACS_BULLET` | `'~'` | 0x7E | bullet |

**Important:** `acs_map` is a dynamic library global (like `stdscr`), so it must be accessed via GOT-indirect addressing (`@GOTPAGE`/`@GOTPAGEOFF`), not `@PAGE`/`@PAGEOFF`.

**Fancy border call pattern (matching C++ BORDER_FANCY):**

The C++ code ORs ACS characters with color pair attributes to create color-coded borders:
```c
wborder(win,
    ACS_VLINE    | dim_pair,      // left side
    ACS_VLINE    | dim_dim_pair,  // right side
    ACS_HLINE    | dim_pair,      // top side
    ACS_HLINE    | dim_dim_pair,  // bottom side
    ACS_ULCORNER | text_pair,     // top-left
    ACS_URCORNER | dim_pair,      // top-right
    ACS_LLCORNER | dim_pair,      // bottom-left
    ACS_LRCORNER | dim_dim_pair); // bottom-right
```

In assembly, OR the loaded ACS value with the COLOR_PAIR attribute before passing to wborder. Since wborder takes 9 arguments (win + 8 chtype), arguments 0-7 go in x0-x7, and the 9th argument (br, bottom-right) goes on the stack per the Darwin ARM64 ABI.

```asm
// wborder(win, ls, rs, ts, bs, tl, tr, bl, br)
// x0=win, w1=ls, w2=rs, w3=ts, w4=bs, w5=tl, w6=tr, w7=bl
// stack[0]=br (9th argument, goes on stack)

// Load ACS values and OR with color attributes...
// Push 9th arg (br) onto stack before bl _wborder
str     w8, [sp, #-16]!        // push br on stack (maintain 16-byte alignment)
mov     x0, <win_ptr>
mov     w1, <ls_acs_or_color>
mov     w2, <rs_acs_or_color>
// ... w3-w7 ...
bl      _wborder
add     sp, sp, #16             // clean up stack
```

### 1.4 Expanded Color Pairs

v1.0 uses 7 color pairs (piece colors on black). v1.1 needs additional pairs for:
- UI labels (highlighted text)
- Dim/shadow borders
- Animation colors (fire: red, yellow, white; water: blue, cyan; snakes: green; life: yellow)
- Menu highlighting

**ncurses attribute bit layout (verified from macOS SDK curses.h):**

```
NCURSES_ATTR_SHIFT = 8
NCURSES_BITS(mask, shift) = mask << (shift + 8)

Attribute constants (32-bit chtype):
  A_NORMAL     = 0x00000000
  A_CHARTEXT   = 0x000000FF   (bits 0-7: character)
  A_COLOR      = 0x0000FF00   (bits 8-15: color pair number)
  COLOR_PAIR(n) = n << 8
  A_STANDOUT   = 0x00010000   (bit 16)
  A_UNDERLINE  = 0x00020000   (bit 17)
  A_REVERSE    = 0x00040000   (bit 18)
  A_BLINK      = 0x00080000   (bit 19)
  A_DIM        = 0x00100000   (bit 20)
  A_BOLD       = 0x00200000   (bit 21)
  A_ALTCHARSET = 0x00400000   (bit 22)
  A_INVIS      = 0x00800000   (bit 23)
```

**COLOR_PAIR in assembly:**
```asm
// COLOR_PAIR(n) = n << 8
mov     w0, #3                  // pair number 3
lsl     w0, w0, #8              // COLOR_PAIR(3) = 0x300

// A_BOLD | COLOR_PAIR(n)
mov     w0, #3
lsl     w0, w0, #8              // COLOR_PAIR(3)
mov     w1, #0x0020
lsl     w1, w1, #16             // A_BOLD = 0x00200000
orr     w0, w0, w1              // A_BOLD | COLOR_PAIR(3)
```

**Recommended color pair allocation for v1.1:**

| Pair # | Foreground | Background | Purpose | Hex Value for init_pair |
|--------|-----------|------------|---------|------------------------|
| 1-7 | (existing piece colors) | BLACK | Piece rendering | (unchanged) |
| 8 | WHITE | BLACK | UI labels, normal text | fg=7, bg=0 |
| 9 | WHITE+BOLD | BLACK | Highlighted text (hilite) | fg=7, bg=0 + A_BOLD |
| 10 | BLACK | BLACK | Dim shadow (dim_dim) | fg=0, bg=0 |
| 11 | RED | DEFAULT | Fire animation (low) | fg=1, bg=-1 |
| 12 | YELLOW | DEFAULT | Fire animation (mid) / Game of Life | fg=3, bg=-1 |
| 13 | BLUE | DEFAULT | Water animation | fg=4, bg=-1 |
| 14 | CYAN | DEFAULT | Water animation (bright) | fg=6, bg=-1 |
| 15 | GREEN | DEFAULT | Snakes animation | fg=2, bg=-1 |
| 16 | WHITE | BLUE | Menu selection highlight | fg=7, bg=4 |

**Using use_default_colors for transparent backgrounds:**

The C++ original calls `use_default_colors()` to enable COLOR_DEFAULT (-1) as a background, making the terminal's native background show through. This is important for animations.

```asm
bl      _use_default_colors     // Enable -1 as default color
// Now init_pair can use -1 for default background:
mov     w0, #11                 // pair 11
mov     w1, #1                  // COLOR_RED foreground
mov     w2, #-1                 // COLOR_DEFAULT background (-1)
bl      _init_pair
```

**Note:** `use_default_colors` is an ncurses extension (not in X/Open Curses), but is available on macOS system ncurses. The symbol is `_use_default_colors`.

### 1.5 Additional Rendering Functions

| Function | Signature | Purpose |
|----------|-----------|---------|
| `mvwaddstr` | `int mvwaddstr(WINDOW* win, int y, int x, const char* str)` | Move cursor and write string to specific window |
| `mvwaddch` | `int mvwaddch(WINDOW* win, int y, int x, chtype ch)` | Move cursor and write character to window |
| `mvwhline` | `int mvwhline(WINDOW* win, int y, int x, chtype ch, int n)` | Draw horizontal line of n characters |
| `wattrset` | `int wattrset(WINDOW* win, int attrs)` | Set all attributes at once (replaces current) |
| `wattr_on` | `int wattr_on(WINDOW* win, attr_t attrs, void* opts)` | Turn on specified attributes (additive) |
| `wattr_off` | `int wattr_off(WINDOW* win, attr_t attrs, void* opts)` | Turn off specified attributes |
| `wbkgd` | `int wbkgd(WINDOW* win, chtype ch)` | Set window background character and attribute |

**Note on wattr_on/wattr_off:** The third argument (`opts`) is always NULL. The existing v1.0 code already passes NULL (xzr) correctly.

### 1.6 mvwprintw -- Variadic Function Calling Convention

The C++ original uses `mvwprintw` extensively for formatted number display (e.g., `mvwprintw(win, y, x, "%10u", score)`). This is a variadic function, and **Darwin ARM64 passes variadic arguments on the stack, not in registers**.

| Function | Signature | Purpose |
|----------|-----------|---------|
| `mvwprintw` | `int mvwprintw(WINDOW* win, int y, int x, const char* fmt, ...)` | Formatted print at position in window |

```asm
// mvwprintw(win, 5, 1, "%10u", score_value)
// Fixed args: x0=win, w1=y, w2=x, x3=fmt_str
// Variadic args: go on stack
sub     sp, sp, #16             // allocate stack for variadic arg
str     w20, [sp]               // push score_value (variadic)
mov     x0, <win>               // WINDOW*
mov     w1, #5                  // y
mov     w2, #1                  // x
adrp    x3, _fmt_10u@PAGE
add     x3, x3, _fmt_10u@PAGEOFF  // "%10u"
bl      _mvwprintw
add     sp, sp, #16             // clean up
```

**Alternative approach (recommended):** Convert numbers to ASCII strings in assembly (the project already has `Lwrite_number_to_buf` in main.s) and use `mvwaddstr` instead. This avoids variadic calling complexity entirely and keeps the binary smaller. Use `mvwprintw` only if right-justified formatting with `%10u` is critical for layout alignment.

---

## 2. File I/O for Hi-Score Persistence

### 2.1 Approach: Direct Darwin Syscalls

The v1.0 code already uses `mov x16, #4; svc #0x80` for write(2, buf, len) to stderr. Extend this pattern for file operations. The hi-score file is a trivial format (single 32-bit integer as ASCII digits), so direct syscalls are appropriate here -- no need for C library `fopen`/`fprintf`.

**Confirmed note on x16 values:** The existing v1.0 code uses raw BSD numbers in x16 (e.g., `mov x16, #4` for write, NOT `0x2000004`). This works on macOS ARM64. The `0x2000000` prefix is documented in some references but the raw numbers work because the kernel dispatches BSD syscalls via the same trap. The v1.0 code is evidence that raw numbers are correct on this platform. Maintain consistency and use raw numbers.

### 2.2 Required Syscall Numbers

All verified against `apple/darwin-xnu/bsd/kern/syscalls.master`:

| Syscall | x16 Value | Signature | Purpose |
|---------|-----------|-----------|---------|
| `open` | 5 | `open(x0=path, w1=flags, w2=mode) -> fd in x0` | Open/create hi-score file |
| `close` | 6 | `close(w0=fd) -> 0 on success` | Close file descriptor |
| `read` | 3 | `read(w0=fd, x1=buf, x2=count) -> bytes_read in x0` | Read hi-score from file |
| `write` | 4 | `write(w0=fd, x1=buf, x2=count) -> bytes_written in x0` | Write hi-score to file |
| `mkdir` | 136 | `mkdir(x0=path, w1=mode) -> 0 on success` | Create ~/.yetris-asm/ directory |
| `access` | 33 | `access(x0=path, w1=mode) -> 0 if accessible` | Check if file/dir exists |

**open() flags (from fcntl.h):**

| Flag | Value | Purpose |
|------|-------|---------|
| `O_RDONLY` | 0x0000 | Read only |
| `O_WRONLY` | 0x0001 | Write only |
| `O_RDWR` | 0x0002 | Read/write |
| `O_CREAT` | 0x0200 | Create if not exists |
| `O_TRUNC` | 0x0400 | Truncate to zero length |

**access() mode:**

| Mode | Value | Purpose |
|------|-------|---------|
| `F_OK` | 0 | Test for existence |

**Error handling:** On error, the carry flag is set after `svc #0x80` and x0 contains the errno value. Check with `b.cs error_label`.

### 2.3 Hi-Score File Format

The C++ original uses Base64-encoded INI files -- wildly overengineered for a single score. For the assembly version, use a minimal plain-text format:

```
// File: ~/.yetris-asm/hiscore
// Content: single line of ASCII decimal digits followed by newline
// Example: "12345\n"
```

**File path construction:**

The HOME environment variable is not directly accessible via syscall. Two options:
1. **Link getenv from libSystem** (already linked): `adrp x0, str_HOME@PAGE; add x0, x0, str_HOME@PAGEOFF; bl _getenv` -- returns char* in x0 or NULL
2. **Hardcode `~/.yetris-asm/hiscore`** -- but `~` expansion requires shell; not usable in syscalls

**Recommended:** Use `_getenv("HOME")` from libSystem (already linked), then concatenate `"/.yetris-asm/hiscore"` in a stack buffer.

```asm
// Get home directory
adrp    x0, _str_HOME@PAGE
add     x0, x0, _str_HOME@PAGEOFF   // "HOME"
bl      _getenv                       // x0 = "/Users/mit" or NULL
cbz     x0, Lno_hiscore             // bail if no HOME

// Build path in stack buffer: $HOME/.yetris-asm/hiscore
sub     sp, sp, #256                 // path buffer on stack
mov     x1, sp                       // x1 = destination
// ... strcpy home, strcat suffix ...
```

### 2.4 Implementation Skeleton

```asm
// _save_hiscore: Write current score to ~/.yetris-asm/hiscore
// Input: none (reads _score global)
// Clobbers: x0-x15
_save_hiscore:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    // 1. Build path (getenv + concatenate)
    // 2. mkdir ~/.yetris-asm/ (ignore EEXIST error)
    //    mov x16, #136; svc #0x80
    // 3. Convert _score to ASCII digits (reuse Lwrite_number_to_buf pattern)
    // 4. open(path, O_WRONLY|O_CREAT|O_TRUNC, 0644)
    //    mov w1, #0x0601    // O_WRONLY|O_CREAT|O_TRUNC = 0x0001|0x0200|0x0400
    //    mov w2, #0644      // octal 0644 = 0x1A4
    //    mov x16, #5; svc #0x80
    // 5. write(fd, buf, len)
    // 6. close(fd)
    ldp     x29, x30, [sp], #48
    ret

// _load_hiscore: Read hi-score from file into _hiscore global
// Input: none
// Output: updates _hiscore in __DATA
_load_hiscore:
    // 1. Build path
    // 2. open(path, O_RDONLY)
    //    b.cs Lno_file  // file doesn't exist, leave hiscore at 0
    // 3. read(fd, buf, 16)  // score is at most ~10 digits
    // 4. Parse ASCII to integer (atoi equivalent)
    // 5. Store to _hiscore
    // 6. close(fd)
    ret
```

---

## 3. Modern Tetris Scoring System

No new libraries needed. This is pure game logic implemented in data tables and scoring functions.

### 3.1 Guideline Scoring Formulas

All values verified against [tetris.wiki/Scoring](https://tetris.wiki/Scoring):

**Base line clear scores (multiply by level):**

| Action | Base Points | Multiplier | "Difficult" Flag |
|--------|-------------|------------|------------------|
| Single | 100 | x level | No |
| Double | 300 | x level | No |
| Triple | 500 | x level | No |
| Tetris | 800 | x level | Yes |

**T-Spin scores (multiply by level):**

| Action | Base Points | "Difficult" Flag |
|--------|-------------|------------------|
| T-Spin (no lines) | 400 | No |
| Mini T-Spin (no lines) | 100 | No |
| T-Spin Single | 800 | Yes |
| Mini T-Spin Single | 200 | Yes |
| T-Spin Double | 1200 | Yes |
| Mini T-Spin Double | 400 | Yes |
| T-Spin Triple | 1600 | Yes |

**Back-to-Back bonus:**
- Consecutive "difficult" actions (Tetris, T-Spin Single/Double/Triple, Mini T-Spin Single/Double) get a 1.5x multiplier on the action score
- Only a non-difficult line clear (Single, Double, Triple without T-Spin) breaks the chain
- T-Spin with no lines does NOT break the chain

**Combo bonus:**
- 50 x combo_count x level
- Combo count increments for each consecutive piece that clears at least one line
- Resets to 0 when a piece locks without clearing lines

**Drop scoring:**
- Soft drop: 1 point per cell dropped
- Hard drop: 2 points per cell dropped

**Perfect clear bonus (added ON TOP of line clear score):**

| Perfect Clear Type | Bonus Points |
|-------------------|-------------|
| Single-line PC | 800 x level |
| Double-line PC | 1200 x level |
| Triple-line PC | 1800 x level |
| Tetris PC | 2000 x level |
| Back-to-back Tetris PC | 3200 x level |

### 3.2 Score Table Data Layout

Replace the current simple `_score_table` (4 entries: 100, 300, 500, 800) with an expanded table:

```asm
// Scoring tables for v1.1 modern scoring
// All values are base points (multiply by level at runtime)

.section __TEXT,__const

// Line clear base scores (index: lines_cleared - 1)
.globl _score_line_clear
.p2align 2
_score_line_clear:
    .word 100, 300, 500, 800    // single, double, triple, tetris

// T-Spin base scores (index: lines_cleared, 0=no lines)
.globl _score_tspin
.p2align 2
_score_tspin:
    .word 400, 800, 1200, 1600  // 0-line, single, double, triple

// Mini T-Spin base scores
.globl _score_tspin_mini
.p2align 2
_score_tspin_mini:
    .word 100, 200, 400         // 0-line, single, double (no mini triple)

// Perfect clear bonus scores (index: lines_cleared - 1)
.globl _score_perfect_clear
.p2align 2
_score_perfect_clear:
    .word 800, 1200, 1800, 2000 // single, double, triple, tetris

// "Difficult" action flag table for back-to-back tracking
// Index: action type (0=normal clear, 1=tetris, 2=tspin, 3=mini tspin)
// Value: 0=not difficult, 1=difficult
.globl _difficult_flags
_difficult_flags:
    .byte 0     // normal single/double/triple
    .byte 1     // tetris
    .byte 1     // T-spin (any lines)
    .byte 1     // mini T-spin (any lines)
```

### 3.3 New Game State Variables

```asm
.section __DATA,__data

// Scoring state for modern system
.globl _combo_count
.p2align 2
_combo_count:       .word 0     // current combo counter (0 = no active combo)

.globl _back_to_back
_back_to_back:      .byte 0     // 1 = last scoring action was "difficult"

.globl _last_action_was_tspin
_last_action_was_tspin: .byte 0 // set by rotation handler, read by lock handler

.globl _last_action_was_mini_tspin
_last_action_was_mini_tspin: .byte 0

.globl _last_move_was_rotation
_last_move_was_rotation: .byte 0  // cleared on translate, set on rotate

.globl _last_kick_was_heavy
_last_kick_was_heavy: .byte 0     // 1 if last SRS kick moved center by (1,2)

.globl _hiscore
.p2align 2
_hiscore:           .word 0     // loaded from file at startup
```

### 3.4 T-Spin Detection Algorithm

The 3-corner rule (modern Tetris guideline):

1. **Prerequisite:** The last successful move was a rotation of the T piece (`_last_move_was_rotation == 1`)
2. **Check 4 diagonal corners** of the T piece's center (pivot cell at piece grid [2,2]):
   - Corner A = board[center_y-1][center_x-1] (upper-left)
   - Corner B = board[center_y-1][center_x+1] (upper-right)
   - Corner C = board[center_y+1][center_x-1] (lower-left)
   - Corner D = board[center_y+1][center_x+1] (lower-right)
   - Walls and floor count as "occupied"
3. **At least 3 of 4 corners must be occupied**
4. **Front vs back corners** (depends on rotation state):

| Rotation | T points | Front corners | Back corners |
|----------|----------|---------------|--------------|
| 0 (spawn) | Up | A, B | C, D |
| 1 (CW/R) | Right | B, D | A, C |
| 2 (180) | Down | C, D | A, B |
| 3 (CCW/L) | Left | A, C | B, D |

5. **Full T-Spin:** Both front corners occupied (and at least one back corner)
6. **Mini T-Spin:** Only one front corner occupied (both back corners occupied)
7. **Exception:** If the last SRS wall kick offset was (1,2) or (2,1) magnitude (the 5th kick test), a Mini T-Spin is promoted to a full T-Spin

### 3.5 Perfect Clear Detection

After clearing lines, check if the entire board is empty:

```asm
// NEON-accelerated perfect clear check
// Load all 200 bytes of _board using ld1 in 16-byte chunks
// ORR all chunks together; if result is all-zero, board is empty
_check_perfect_clear:
    adrp    x0, _board@PAGE
    add     x0, x0, _board@PAGEOFF
    movi    v0.16b, #0              // accumulator = 0
    // 200 bytes = 12 x 16 + 8 bytes
    // Load 12 full vectors, ORR into accumulator
    .rept 12
    ld1     {v1.16b}, [x0], #16
    orr     v0.16b, v0.16b, v1.16b
    .endr
    // Load remaining 8 bytes
    ld1     {v1.8b}, [x0]
    orr     v0.8b, v0.8b, v1.8b    // merge into lower 8 bytes
    // Check if accumulator is all zeros
    umaxv   b2, v0.16b             // max of all bytes
    umov    w0, v2.b[0]            // w0 = max byte
    // w0 == 0 means perfect clear
    ret
```

This reuses the NEON pattern already proven in v1.0's line detection.

---

## 4. Animation System

### 4.1 No New Libraries

All 4 animations (fire, water, snakes, Game of Life) are pure computational -- they operate on 2D arrays of integers/booleans and render to a window using `mvwaddch` with color attributes. No additional ncurses functions beyond what is documented above.

### 4.2 Animation Data Structures

Each animation needs a 2D buffer. The board window is approximately 20x20 characters (10 columns x 2 chars wide = 20 chars, 20 rows). Allocate fixed-size buffers in `__DATA`:

```asm
.section __DATA,__bss

// Fire animation: 20x20 intensity values (1 byte each = 400 bytes)
.globl _anim_fire_buf
.p2align 2
_anim_fire_buf:     .space 400

// Fire cooling map: 20x20 (400 bytes)
.globl _anim_fire_cool
.p2align 2
_anim_fire_cool:    .space 400

// Water animation: two 20x20 buffers of 16-bit values (800 bytes each)
.globl _anim_water_buf1
.p2align 2
_anim_water_buf1:   .space 800
.globl _anim_water_buf2
.p2align 2
_anim_water_buf2:   .space 800

// Game of Life: 20x20 boolean grid (400 bytes)
.globl _anim_life_cells
.p2align 2
_anim_life_cells:   .space 400

// Snakes: array of snake structs (x:byte, y:byte, size:byte, pad:byte = 4 bytes each)
// Max 32 snakes = 128 bytes
.globl _anim_snakes
.p2align 2
_anim_snakes:       .space 128
.globl _anim_snake_count
_anim_snake_count:  .byte 0
```

### 4.3 Animation Timing

Each animation has its own update interval. Use `_get_time_ms` (already in v1.0) with per-animation last-update timestamps:

| Animation | Update Interval | Frame Character Set |
|-----------|----------------|---------------------|
| Fire | 100ms | ` .':-=+*#%@#` (12 chars, intensity-mapped) |
| Water | 300ms | `#@%#*+=-:'.` (11 chars, height-mapped) |
| Snakes | 50ms (movement), 100-300ms (add) | `@` (head), `o` (body) |
| Game of Life | 200ms | `#` (alive), ` ` (dead) |

---

## 5. What NOT to Add

| Temptation | Why to Resist | What to Do Instead |
|-----------|---------------|-------------------|
| Homebrew ncurses | System ncurses (5.4) has everything needed: subwindows, ACS chars, 256 color pairs, use_default_colors | Stay with system ncurses via `-lncurses` |
| C library fopen/fprintf for file I/O | Adds unnecessary dependency complexity; hi-score is just one integer | Direct syscalls (open/read/write/close) -- already have the pattern from v1.0's stderr write |
| ncurses panels library (-lpanel) | Panels manage overlapping window z-order; we have non-overlapping layout | Use plain newwin/derwin with explicit refresh ordering |
| ncurses forms/menu library | Over-engineered for a simple menu with 3-8 items | Continue manual menu rendering (already works in v1.0) |
| sprintf/snprintf for number formatting | Pulls in more of libSystem's stdio | Extend existing `Lwrite_number_to_buf` to write to a buffer for mvwaddstr |
| Wide character ncurses (ncursesw) | Unicode box-drawing would be nice but ACS characters work fine; wide chars add complexity to the assembly calling convention | Use ACS_* characters via acs_map lookup |
| External random number library | Animations need randomness but the existing LFSR/LCG in random.s is sufficient | Extend existing `_random_range` function |

---

## 6. Summary of New ncurses Symbols to Link

All symbols come from the already-linked `-lncurses`. No new linker flags needed.

**New function symbols (bl targets):**

| Symbol | Args | Returns | New in v1.1 |
|--------|------|---------|-------------|
| `_newwin` | w0=lines, w1=cols, w2=y, w3=x | x0=WINDOW* | Yes |
| `_derwin` | x0=parent, w1=lines, w2=cols, w3=y, w4=x | x0=WINDOW* | Yes |
| `_delwin` | x0=win | w0=OK/ERR | Yes |
| `_wnoutrefresh` | x0=win | w0=OK/ERR | Yes |
| `_doupdate` | (none) | w0=OK/ERR | Yes |
| `_wborder` | x0=win + 8 chtype args | w0=OK/ERR | Yes |
| `_box` | x0=win, w1=verch, w2=horch | w0=OK/ERR | Yes |
| `_mvwaddstr` | x0=win, w1=y, w2=x, x3=str | w0=OK/ERR | Yes |
| `_use_default_colors` | (none) | w0=OK/ERR | Yes |
| `_mvwprintw` | x0=win, w1=y, w2=x, x3=fmt, ... (stack) | w0=OK/ERR | Yes (if used) |
| `_wattrset` | x0=win, w1=attrs | w0=OK/ERR | Yes |
| `_wbkgd` | x0=win, w1=ch | w0=OK/ERR | Yes |
| `_getenv` | x0=name | x0=value or NULL | Yes (from libSystem) |

**New global symbols (GOT-indirect access):**

| Symbol | Type | New in v1.1 |
|--------|------|-------------|
| `_acs_map` | chtype[] (32-bit array) | Yes -- for ACS box-drawing characters |

**Existing symbols (no changes):**

`_stdscr`, `_initscr`, `_endwin`, `_wrefresh`, `_wmove`, `_waddch`, `_werase`, `_wattr_on`, `_wattr_off`, `_wtimeout`, `_wgetch`, `_cbreak`, `_noecho`, `_start_color`, `_init_pair`, `_curs_set`, `_keypad`

---

## Sources

- macOS SDK curses.h: `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/curses.h` -- verified attribute bit positions, ACS character indices, function signatures [HIGH confidence -- local system verification]
- [darwin-xnu syscalls.master](https://github.com/apple/darwin-xnu/blob/main/bsd/kern/syscalls.master) -- syscall numbers for open(5), close(6), read(3), write(4), mkdir(136), access(33) [HIGH confidence -- Apple kernel source]
- [tetris.wiki/Scoring](https://tetris.wiki/Scoring) -- modern guideline scoring formulas, back-to-back rules, combo formula [HIGH confidence -- authoritative community wiki, cross-referenced with multiple sources]
- [tetris.wiki/T-Spin](https://tetris.wiki/T-Spin) -- 3-corner detection algorithm, front/back corner definitions, mini vs full T-spin [HIGH confidence]
- [ncurses newwin man page](https://linux.die.net/man/3/newwin) -- newwin/derwin/subwin/delwin signatures [HIGH confidence]
- [ncurses wborder man page](https://linux.die.net/man/3/wborder) -- wborder 8-argument signature, default ACS values [HIGH confidence]
- [ncurses wnoutrefresh man page](https://linux.die.net/man/3/doupdate) -- batch refresh pattern documentation [HIGH confidence]
- C++ original source code: `deps/Engine/Graphics/Window.cpp` -- derwin usage, border styles, wnoutrefresh pattern [HIGH confidence -- direct codebase reference]
- C++ original source code: `deps/Engine/Graphics/Animation/*.cpp` -- all 4 animation algorithms [HIGH confidence]
- C++ original source code: `src/Game/Entities/ScoreFile.cpp` -- file I/O approach (overengineered, simplified for asm) [HIGH confidence]
- Existing v1.0 assembly: `asm/main.s`, `asm/render.s`, `asm/data.s` -- confirmed calling conventions, GOT access patterns, syscall usage [HIGH confidence]

---

*Stack research for: yetris-asm v1.1 visual polish, animations, modern scoring, file I/O*
*Researched: 2026-02-27*
