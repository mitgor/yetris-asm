# Phase 7: Visual Polish - Research

**Researched:** 2026-02-27
**Domain:** ncurses ACS characters, color attributes, ASCII art rendering in ARM64 assembly
**Confidence:** HIGH

## Summary

Phase 7 transforms the assembly Tetris clone from functional-but-plain rendering to visually matching the C++ original's styled appearance. The C++ original uses a theme system with 6 named color pairs (text, hilite_text, hilite_hilite_text, dim_text, dim_dim_text, textbox) and an elaborate border system that creates a shadow/depth effect using different brightness levels on different border edges. The assembly version currently uses only 7 color pairs (one per piece type) and plain ASCII borders (`+`, `-`, `|` via `wborder(win, 0,0,0,0,0,0,0,0)`).

The core technical challenge is accessing `_acs_map` (an extern array in libncurses) from assembly to get ACS box-drawing character values, then ORing those with color attributes to create the shadow effect. Additionally, new color pairs must be initialized beyond the existing 7 piece pairs, the multi-line ASCII art logo must be stored as string data and rendered centered, and the pause/game-over overlays need to be redesigned with styled menu items instead of plain text.

**Primary recommendation:** Add 4 new color pairs (8-11) for dim_text, dim_dim_text, hilite_text, textbox. Build a reusable `_draw_fancy_border` routine that loads ACS characters from `_acs_map` and calls `wborder` with per-edge color attributes ORed onto each character. Then update all existing draw functions to apply hilite_text color on labels and titles, and implement the logo + overlay systems.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| VISUAL-01 | ASCII art multi-line "YETRIS" logo renders on main menu, horizontally centered | Logo is 7 lines x 39 chars from C++ `LayoutMainMenu::draw()`. Store as 7 `.asciz` strings in data.s. Center at `(win_width/2 - 39/2 - 1, 1)` matching C++ offset. Render via loop of wmove+waddstr on `_win_menu_logo`. |
| VISUAL-02 | All window borders use ACS box-drawing chars with color-coded shadow effect | C++ `Window::borders(BORDER_FANCY)` uses `wborder()` with 8 ACS chars each ORed with different color pair attrs. Left/top edges use dim_text (bright black), right/bottom edges use dim_dim_text (dark black), corners transition. Access `_acs_map` via `@GOTPAGE/@GOTPAGEOFF` in assembly. |
| VISUAL-03 | Window titles render in highlight color over border | C++ `Window::clear()` prints titles at `(1,0)` using `hilite_hilite_text`. In assembly: after drawing border, wmove to title position and waddstr with wattr_on(hilite_hilite_text). Already partially done (titles drawn at border row 0), just needs color. |
| VISUAL-04 | UI labels render in highlight color (cyan) | C++ uses `EngineGlobals::Theme::hilite_text` = cyan+default for all stat/score labels. In assembly: wattr_on with COLOR_PAIR(8) for cyan before drawing label strings, wattr_off after. |
| VISUAL-05 | Menu items show colored first-letter mnemonics with highlight on selected item | C++ `LayoutMainMenu::draw()` renders first letter in hilite_text, rest in text color. Profiles menu: "C"reate, "D"elete, "S"witch. Assembly: for each menu item, draw char[0] with hilite color, then draw rest of string with text color. Selected item still uses A_REVERSE on whole string. |
| VISUAL-06 | Additional color pairs initialized beyond piece colors | C++ initializes all 64 pairs. Assembly needs 4 more: pair 8=dim_text (black+default, bold), pair 9=dim_dim_text (black+default), pair 10=hilite_text (cyan+default), pair 11=hilite_hilite_text (cyan+default, bold). These map to the C++ theme. |
| VISUAL-07 | Pause overlay as bordered subwindow with Resume/Quit to Menu/Quit Game options | C++ Game creates a Menu with 3 items: "Resume", blank, "Quit to Main Menu", "Quit Game". These render in the pause window via Menu::draw(). Assembly must replace current static "PAUSED"/"Press p to resume" with 3 selectable items. Requires menu_selection logic for the pause overlay. |
| VISUAL-08 | Game over overlay with styled text | C++ calls `this->game->isOver()` then delays 500ms and restarts. The game-over text should be styled (e.g., A_BOLD + color). Assembly currently draws plain "GAME OVER"/"Press q to quit". Need A_BOLD attribute and possibly a border around the game-over text. |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ncurses | 5.4 (macOS system) | Terminal UI rendering | Already linked; provides ACS chars, color pairs, wborder, wattr_on/off |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| _acs_map (ncurses extern) | - | Access ACS box-drawing characters | When building fancy border chtype values |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| ACS box chars | Raw Unicode box drawing (U+2500 series) | ACS is portable across terminals; Unicode requires wide char support; ACS is what C++ uses |
| wborder with per-char color OR | Manual mvwaddch for each border cell | wborder is a single call; manual drawing is more flexible but 4x more code |

**Installation:** No additional dependencies. All functionality comes from the already-linked ncurses.

## Architecture Patterns

### Recommended Project Structure
```
asm/
├── data.s          # ADD: logo strings, new color pair constants, pause menu strings
├── render.s        # MODIFY: _init_colors, all draw_*_panel, _draw_game_over
│                   # ADD: _draw_fancy_border helper, _draw_logo
├── menu.s          # MODIFY: _menu_frame for colored first-letter mnemonics
├── main.s          # MODIFY: pause state machine for 3-option pause menu
└── layout.s        # NO CHANGES (window geometry unchanged)
```

### Pattern 1: Accessing `_acs_map` from Assembly
**What:** `_acs_map` is an extern `chtype[]` (array of unsigned 32-bit ints) in ncurses. ACS characters are looked up by ASCII key (e.g., `'l'` = 0x6C for ULCORNER). Each entry is a 32-bit chtype combining the alternate character set flag with the character value.
**When to use:** Every time we need an ACS box-drawing character for borders.
**Example:**
```asm
// Load ACS_ULCORNER = acs_map['l'] = acs_map[0x6C]
// _acs_map is an extern from ncurses, access via GOT
adrp    x8, _acs_map@GOTPAGE
ldr     x8, [x8, _acs_map@GOTPAGEOFF]   // x8 = &acs_map[0]
mov     w9, #0x6C                         // 'l' = ACS_ULCORNER key
ldr     w10, [x8, w9, uxtw #2]           // w10 = acs_map['l'] (chtype, 4 bytes each)
// Now w10 contains the ACS_ULCORNER chtype value
// OR with color attribute: w10 = w10 | COLOR_PAIR(n) | A_BOLD
```

### Pattern 2: Color Attribute Computation
**What:** ncurses attributes on macOS use `chtype` (unsigned 32-bit). Color pairs occupy bits 8-15. Attributes like A_BOLD, A_DIM use higher bits.
**When to use:** When building border characters with embedded color, or when applying attributes to text.
**Constants needed:**
```
COLOR_PAIR(n) = n << 8           // bits [8:15]
A_BOLD        = 1 << 21          // 0x00200000
A_DIM         = 1 << 20          // 0x00100000
A_REVERSE     = 1 << 18          // 0x00040000 (already used in menu.s)
A_NORMAL      = 0
```
**Example:**
```asm
// Build attribute: COLOR_PAIR(10) | A_BOLD  (hilite_hilite_text = bold cyan)
mov     w1, #10, lsl #8          // COLOR_PAIR(10) = 0x0A00
movk    w1, #0x0020, lsl #16     // | A_BOLD = 0x00200000
// w1 = 0x00200A00 = bold cyan on default
```

### Pattern 3: Fancy Border Drawing (matching C++ Window::borders BORDER_FANCY)
**What:** The C++ original calls `wborder()` with each of the 8 border characters (ls, rs, ts, bs, tl, tr, bl, br) being an ACS character ORed with a specific theme color to create a 3D shadow effect.
**When to use:** Every bordered window (hold, score, middle_right, rightmost, pause, menu_items).
**C++ reference:**
```cpp
wborder(win,
    ACS_VLINE    | dim_text,       // left side (brighter)
    ACS_VLINE    | dim_dim_text,   // right side (dimmer)
    ACS_HLINE    | dim_text,       // top (brighter)
    ACS_HLINE    | dim_dim_text,   // bottom (dimmer)
    ACS_ULCORNER | text,           // top-left (brightest)
    ACS_URCORNER | dim_text,       // top-right (medium)
    ACS_LLCORNER | dim_text,       // bottom-left (medium)
    ACS_LRCORNER | dim_dim_text);  // bottom-right (dimmest)
```
**Assembly implementation pattern:**
```asm
// _draw_fancy_border: Draw fancy border on window in x0
// Load acs_map base
adrp    x8, _acs_map@GOTPAGE
ldr     x8, [x8, _acs_map@GOTPAGEOFF]
// Load each ACS char and OR with color
// ls = acs_map['x'] | dim_text_attr
mov     w9, #0x78               // 'x' = ACS_VLINE key
ldr     w1, [x8, w9, uxtw #2]
orr     w1, w1, w_dim_text_attr // left side = dim_text
// ... repeat for all 8 border characters ...
// Push 8th arg on stack, call wborder
```

### Pattern 4: Title Drawing with Color
**What:** After drawing the border, overwrite a portion of the top border row with the title string in hilite_hilite_text color.
**When to use:** All titled windows (Hold, Next, Statistics, Paused).
**Example:**
```asm
// Draw title "Hold" at (0, col) in hilite_hilite_text
mov     x0, x19                 // WINDOW*
mov     w1, #10, lsl #8         // COLOR_PAIR(10) = hilite attr
movk    w1, #0x0020, lsl #16    // | A_BOLD
mov     x2, #0                  // NULL
bl      _wattr_on
mov     x0, x19
mov     w1, #0                  // row 0 (on border)
mov     w2, #4                  // centered col
bl      _wmove
mov     x0, x19
adrp    x1, _str_hold_title@PAGE
add     x1, x1, _str_hold_title@PAGEOFF
bl      _waddstr
// Turn off
mov     x0, x19
mov     w1, #10, lsl #8
movk    w1, #0x0020, lsl #16
mov     x2, #0
bl      _wattr_off
```

### Pattern 5: ASCII Art Logo Rendering
**What:** Store the 7-line YETRIS logo as separate strings, render line-by-line in the `_win_menu_logo` window.
**Logo from C++ source:**
```
 __ __    ___ ______  ____   ____ _____
|  |  |  /  _]      ||    \ |    / ___/
|  |  | /  [_|      ||  D  ) |  (   \_
|  ~  ||    _]_|  |_||    /  |  |\__  |
|___, ||   [_  |  |  |    \  |  |/  \ |
|     ||     | |  |  |  .  \ |  |\    |
|____/ |_____| |__|  |__|\_||____|\___|
```
**Rendering:** Center at `(logo_win_width/2 - 39/2 - 1, 1)`. Since `_win_menu_logo` is 80 wide, center_col = 80/2 - 19 - 1 = 20.

### Anti-Patterns to Avoid
- **Loading acs_map repeatedly per frame:** Load the base pointer once, cache in a callee-saved register within the border-drawing function.
- **Hardcoding ACS chtype values:** ACS values are terminal-dependent; always look them up from `_acs_map` at runtime.
- **Forgetting wattr_off after wattr_on:** Every wattr_on MUST have a matching wattr_off, or color/attribute bleeding occurs across subsequent text.
- **Using @PAGE/@PAGEOFF for _acs_map:** It is an extern symbol from a dynamic library -- MUST use `@GOTPAGE/@GOTPAGEOFF` (same as `_stdscr`).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Box-drawing characters | Hardcoded Unicode or ASCII chars | `_acs_map` lookup + `wborder()` | Terminal-portable; what C++ original uses |
| Color pair attribute math | Manual bit shifting each time | Pre-computed constants in data.s | Eliminates repeated computation, reduces code size |
| Border drawing per-window | Inline border code in each draw function | Shared `_draw_fancy_border(WINDOW*)` helper | 6+ windows need borders; deduplication saves ~200 instructions |

**Key insight:** The fancy border is just a single `wborder()` call with 8 carefully constructed chtype values. The complexity is in building those values (ACS char | color pair attr), not in the drawing itself. A helper function that takes a WINDOW* pointer and draws the fancy border eliminates most of the code duplication.

## Common Pitfalls

### Pitfall 1: `_acs_map` Not Initialized Before Use
**What goes wrong:** `_acs_map` entries are all 0 until `initscr()` and `start_color()` have been called.
**Why it happens:** ncurses fills `_acs_map` during terminal initialization based on the terminal's capabilities.
**How to avoid:** All ACS lookups happen during rendering (after ncurses init). Never store ACS values in data.s as constants.
**Warning signs:** All borders show blank/invisible characters.

### Pitfall 2: wborder Arguments Are `chtype` Not `int`
**What goes wrong:** On macOS ARM64, `wborder` expects 9 arguments. The first is WINDOW* (8 bytes), the remaining 8 are `chtype` (unsigned int, 4 bytes each). ARM64 ABI passes first 8 args in registers (x0-x7), but chtype fits in w1-w7. The 8th chtype (br corner) must go on the stack.
**Why it happens:** ARM64 calling convention only has 8 register slots; wborder has 9 parameters.
**How to avoid:** Already handled in current code: `sub sp, sp, #16; str xzr, [sp]; bl _wborder; add sp, sp, #16`. Replace `xzr` with the actual br corner chtype.
**Warning signs:** Crash or garbled bottom-right corner.

### Pitfall 3: A_BOLD vs Separate Bold Color Pair
**What goes wrong:** The C++ theme uses `Colors::pair("black", "default", true)` for dim_text, which produces `COLOR_PAIR(N) | A_BOLD`. Simply using COLOR_PAIR alone without A_BOLD gives a different (darker) shade.
**Why it happens:** The "bright black" (dim_text) in the C++ original is `COLOR_BLACK + A_BOLD`, which on most terminals renders as dark gray. Without A_BOLD, it stays invisible/black.
**How to avoid:** The dim_text color pair MUST include A_BOLD to be visible. The dim_dim_text pair is COLOR_BLACK without A_BOLD (near-invisible, used for shadow effect on right/bottom borders).
**Warning signs:** Borders are invisible or all the same brightness.

### Pitfall 4: Pause Menu State Conflicts with Game Input
**What goes wrong:** Adding a 3-item selectable pause menu requires its own up/down/enter handling. If not carefully isolated, the game's input handler processes pause-menu keys as game actions.
**Why it happens:** Current pause handling is binary (p toggles _is_paused). A multi-item menu needs a separate selection variable and input dispatch.
**How to avoid:** Add `_pause_selection` variable in data.s (0=Resume, 1=Quit to Menu, 2=Quit Game). When paused, route input to pause menu handler, not game handler. Use the existing _menu_selection pattern as template.
**Warning signs:** Pressing Up/Down during pause moves the piece instead of the menu cursor.

### Pitfall 5: Color Pair Number Conflict
**What goes wrong:** Piece colors use pairs 1-7. If new pairs overlap or use wrong numbers, pieces render in wrong colors.
**Why it happens:** Color pair numbers are a global ncurses resource.
**How to avoid:** Piece pairs stay at 1-7. New theme pairs start at 8: dim_text=8, dim_dim_text=9, hilite_text=10, hilite_hilite_text=11, textbox=12. Document the mapping in data.s comments.
**Warning signs:** Pieces change color unexpectedly.

## Code Examples

### Example 1: New Color Pair Initialization
```asm
// In _init_colors, after existing pairs 1-7:

// Pair 8: dim_text = bright black on default (A_BOLD makes it gray)
// C++: Colors::pair("black", "default", true) -> COLOR_PAIR(64+BLACK) | A_BOLD
// Simplified: pair(COLOR_BLACK, COLOR_BLACK) + A_BOLD used at attribute time
mov     w0, #8
mov     w1, #0              // COLOR_BLACK
mov     w2, #0              // COLOR_BLACK
bl      _init_pair

// Pair 9: dim_dim_text = black on black (near invisible)
mov     w0, #9
mov     w1, #0              // COLOR_BLACK
mov     w2, #0              // COLOR_BLACK
bl      _init_pair

// Pair 10: hilite_text = cyan on black (for labels)
mov     w0, #10
mov     w1, #6              // COLOR_CYAN
mov     w2, #0              // COLOR_BLACK
bl      _init_pair

// Pair 11: hilite_hilite_text = bold cyan on black (for titles)
// Same pair as 10 but used with A_BOLD at attribute time
// (Or could be a separate pair; simplest to reuse 10 and add A_BOLD at call site)

// Pair 12: textbox = white on cyan (for input prompts)
mov     w0, #12
mov     w1, #7              // COLOR_WHITE
mov     w2, #6              // COLOR_CYAN
bl      _init_pair
```

### Example 2: Fancy Border Helper
```asm
// _draw_fancy_border: Draw C++-matching fancy border on WINDOW* in x0
// Clobbers: x0-x7, x8-x10, stack
// Callee-saved: expects caller to save as needed
_draw_fancy_border:
    stp     x20, x19, [sp, #-16]!
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    mov     x19, x0             // save WINDOW*

    // Load _acs_map base (extern, GOT access)
    adrp    x8, _acs_map@GOTPAGE
    ldr     x8, [x8, _acs_map@GOTPAGEOFF]

    // Compute attributes:
    // dim_text_attr     = COLOR_PAIR(8) | A_BOLD = (8 << 8) | 0x200000 = 0x200800
    // dim_dim_text_attr = COLOR_PAIR(9)          = (9 << 8)            = 0x000900
    // text_attr         = COLOR_PAIR(3) | A_BOLD = (3 << 8) | 0x200000 = 0x200300
    //   (pair 3 = white on black; with A_BOLD = bright white = matches C++ "text")

    // ACS_VLINE  = acs_map['x'] = acs_map[0x78]
    // ACS_HLINE  = acs_map['q'] = acs_map[0x71]
    // ACS_ULCORNER = acs_map['l'] = acs_map[0x6C]
    // ACS_URCORNER = acs_map['k'] = acs_map[0x6B]
    // ACS_LLCORNER = acs_map['m'] = acs_map[0x6D]
    // ACS_LRCORNER = acs_map['j'] = acs_map[0x6A]

    // ls = ACS_VLINE | dim_text
    mov     w9, #0x78
    ldr     w1, [x8, w9, uxtw #2]
    mov     w10, #0x0800
    movk    w10, #0x0020, lsl #16   // dim_text_attr = 0x00200800
    orr     w1, w1, w10

    // rs = ACS_VLINE | dim_dim_text
    mov     w9, #0x78
    ldr     w2, [x8, w9, uxtw #2]
    mov     w10, #0x0900            // dim_dim_text_attr = 0x00000900
    orr     w2, w2, w10

    // ts = ACS_HLINE | dim_text
    mov     w9, #0x71
    ldr     w3, [x8, w9, uxtw #2]
    mov     w10, #0x0800
    movk    w10, #0x0020, lsl #16
    orr     w3, w3, w10

    // bs = ACS_HLINE | dim_dim_text
    mov     w9, #0x71
    ldr     w4, [x8, w9, uxtw #2]
    mov     w10, #0x0900
    orr     w4, w4, w10

    // tl = ACS_ULCORNER | text (brightest)
    mov     w9, #0x6C
    ldr     w5, [x8, w9, uxtw #2]
    mov     w10, #0x0300
    movk    w10, #0x0020, lsl #16   // text_attr = 0x00200300
    orr     w5, w5, w10

    // tr = ACS_URCORNER | dim_text
    mov     w9, #0x6B
    ldr     w6, [x8, w9, uxtw #2]
    mov     w10, #0x0800
    movk    w10, #0x0020, lsl #16
    orr     w6, w6, w10

    // bl = ACS_LLCORNER | dim_text
    mov     w9, #0x6D
    ldr     w7, [x8, w9, uxtw #2]
    mov     w10, #0x0800
    movk    w10, #0x0020, lsl #16
    orr     w7, w7, w10

    // br = ACS_LRCORNER | dim_dim_text (8th arg, on stack)
    mov     w9, #0x6A
    ldr     w10, [x8, w9, uxtw #2]
    mov     w11, #0x0900
    orr     w10, w10, w11
    sub     sp, sp, #16
    str     w10, [sp]

    // Call wborder(win, ls, rs, ts, bs, tl, tr, bl, br)
    mov     x0, x19
    bl      _wborder
    add     sp, sp, #16

    ldp     x29, x30, [sp], #16
    ldp     x20, x19, [sp], #16
    ret
```

### Example 3: Logo String Data
```asm
// In data.s, __TEXT,__const section:
.globl _logo_line0
_logo_line0: .asciz " __ __    ___ ______  ____   ____ _____"
.globl _logo_line1
_logo_line1: .asciz "|  |  |  /  _]      ||    \\ |    / ___/"
.globl _logo_line2
_logo_line2: .asciz "|  |  | /  [_|      ||  D  ) |  (   \\_"
.globl _logo_line3
_logo_line3: .asciz "|  ~  ||    _]_|  |_||    /  |  |\\__  |"
.globl _logo_line4
_logo_line4: .asciz "|___, ||   [_  |  |  |    \\  |  |/  \\ |"
.globl _logo_line5
_logo_line5: .asciz "|     ||     | |  |  |  .  \\ |  |\\    |"
.globl _logo_line6
_logo_line6: .asciz "|____/ |_____| |__|  |__|\\_ ||____|\\___| "

// Pointer table in __DATA,__const:
.globl _logo_lines
.p2align 3
_logo_lines:
    .quad _logo_line0
    .quad _logo_line1
    .quad _logo_line2
    .quad _logo_line3
    .quad _logo_line4
    .quad _logo_line5
    .quad _logo_line6
```

### Example 4: Colored First-Letter Mnemonic
```asm
// Draw "Start Game" with 'S' in cyan, rest in white
// x19 = WINDOW*, cursor already positioned

// Turn on hilite_hilite_text for first letter
mov     x0, x19
mov     w1, #0x0A00             // COLOR_PAIR(10)
movk    w1, #0x0020, lsl #16   // | A_BOLD
mov     x2, #0
bl      _wattr_on

// Draw 'S'
mov     x0, x19
mov     w1, #0x53              // 'S'
bl      _waddch

// Turn off hilite, turn on text color
mov     x0, x19
mov     w1, #0x0A00
movk    w1, #0x0020, lsl #16
mov     x2, #0
bl      _wattr_off

mov     x0, x19
mov     w1, #0x0300             // COLOR_PAIR(3) = white
movk    w1, #0x0020, lsl #16   // | A_BOLD
mov     x2, #0
bl      _wattr_on

// Draw rest of string "tart Game"
mov     x0, x19
adrp    x1, _str_start_rest@PAGE   // "tart Game"
add     x1, x1, _str_start_rest@PAGEOFF
bl      _waddstr

// Turn off text color
mov     x0, x19
mov     w1, #0x0300
movk    w1, #0x0020, lsl #16
mov     x2, #0
bl      _wattr_off
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| wborder(win, 0,0,...) plain defaults | wborder with ACS chars + color ORed | Phase 7 | All borders get 3D shadow effect |
| 7 color pairs (pieces only) | 12+ color pairs (pieces + UI theme) | Phase 7 | Full theme color support |
| Single "PAUSED" text + "press p" | 3-item selectable pause menu | Phase 7 | Matches C++ pause behavior |
| Plain "Y E T R I S" text title | Multi-line ASCII art logo | Phase 7 | Visual branding matches C++ |

**Deprecated/outdated:**
- Plain ASCII borders (`+`, `-`, `|`): Replaced by ACS box-drawing characters with color
- Single-color menu items: Replaced by colored first-letter mnemonics

## Open Questions

1. **`use_default_colors()` for transparent background**
   - What we know: C++ calls `use_default_colors()` and uses `COLOR_DEFAULT = -1` for background in theme pairs. This makes the background transparent (uses terminal's default).
   - What's unclear: Whether `_acs_map` is accessible via simple `@GOTPAGE` or needs function-style access on macOS ncurses. Research confirmed it is available as `_acs_map` (not via `_nc_acs_map()` function) per the `.tbd` export list.
   - Recommendation: Call `_use_default_colors` in `_init_colors` before `init_pair` calls. Use -1 as background for theme pairs if supported.

2. **Exact color pair numbers for theme**
   - What we know: C++ uses `fg*8 + bg + 1` formula for pair numbers (e.g., black+default = pair 64+0=64). Assembly uses simple sequential numbering (1-7 for pieces).
   - What's unclear: Whether we should match C++ pair numbering or use our own.
   - Recommendation: Use our own sequential numbering starting at 8 for simplicity. The visual result is identical; only internal pair numbers differ.

3. **Board border: ACS vs current +/-/| **
   - What we know: The C++ board window uses `BORDER_NONE` (the board is borderless; its parent `middle_left` is also borderless). The `+/-/|` borders in the current assembly board drawing are hand-drawn game borders (not ncurses borders).
   - What's unclear: Whether to convert the board's hand-drawn borders to ACS or leave as-is. The C++ board itself has no ncurses border.
   - Recommendation: Convert the board's manual `+/-/|` to ACS_ULCORNER/ACS_HLINE/ACS_VLINE etc. for consistency, but without the shadow color effect (use dim_text uniformly). This matches the C++ approach where the board draws cells and blocks but not a styled border.

## Sources

### Primary (HIGH confidence)
- macOS ncurses headers (`/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/curses.h`) - verified ACS macro definitions, attribute bit positions, chtype size, acs_map access pattern
- C++ source code (`deps/Engine/Graphics/Window.cpp` lines 174-198) - exact BORDER_FANCY wborder arguments and color scheme
- C++ source code (`deps/Engine/EngineGlobals.cpp` lines 27-33) - exact theme color definitions (text, hilite_text, dim_text, etc.)
- C++ source code (`src/Game/Display/Layouts/LayoutMainMenu.cpp` lines 140-148) - exact ASCII art logo content and centering calculation
- C++ source code (`src/Game/Display/Layouts/LayoutGame.cpp` lines 296-386) - exact label colors and statistics panel rendering
- C++ source code (`src/Game/Entities/Game.cpp` lines 76-92) - exact pause menu structure (Resume, blank, Quit to Menu, Quit Game)
- ncurses .tbd library exports - confirmed `_acs_map` is a direct exported symbol (not wrapped function)

### Secondary (MEDIUM confidence)
- ACS character key-to-symbol mapping (from curses.h #define) - standard ncurses, cross-verified with macOS headers

### Tertiary (LOW confidence)
- None - all findings verified against macOS system headers and C++ source

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - ncurses is the only dependency, all APIs verified against macOS headers
- Architecture: HIGH - patterns derived directly from C++ source code and verified ncurses ABI
- Pitfalls: HIGH - all identified from actual assembly codebase patterns and known ncurses behaviors

**Research date:** 2026-02-27
**Valid until:** 2026-03-27 (stable domain; ncurses API unchanging)
