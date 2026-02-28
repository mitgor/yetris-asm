# Domain Pitfalls: v1.1 Visual Polish & Gameplay Features

**Domain:** Adding ncurses subwindows, animations, modern scoring, line clear animation, and file I/O to an existing ARM64 assembly Tetris game
**Researched:** 2026-02-27
**Confidence:** HIGH for ncurses subwindow and file I/O pitfalls (verified against ncurses documentation, macOS headers, and existing codebase); MEDIUM for T-spin detection and scoring edge cases (verified against tetris.wiki but no assembly-specific sources)

---

## Critical Pitfalls

Mistakes that cause crashes, visual corruption, or require significant rework.

### Pitfall 1: ncurses Subwindow Refresh Ordering Destroys Parent Content

**What goes wrong:**
The current codebase renders everything on `stdscr` with a single `wrefresh` call at the end of `_render_frame`. Switching to ncurses subwindows (via `derwin`) introduces a strict refresh ordering requirement: parent windows MUST be refreshed before child subwindows, and `touchwin` must be called on the parent before refreshing any subwindow. Getting this wrong causes visual artifacts -- child content disappears, parent borders overwrite child content, or stale content persists from previous frames.

**Why it happens:**
The C++ original (LayoutGame.cpp) handles this by calling `clear()`/`refresh()` on container windows first, then child windows, then a final `refresh()`. This works because each `Window::refresh()` uses `wnoutrefresh()` internally, with `refresh()` (which calls `doupdate()`) at the very end. In assembly, you must replicate this exact bottom-up order manually. There is no class hierarchy to enforce it -- every call is explicit.

**Consequences:**
- Board contents disappear on every frame
- Borders flicker or overlap game content
- Score/next/hold panels show stale data from previous frames
- Subtle: content from one subwindow bleeds into another's region

**Prevention:**
The correct ncurses refresh pattern for subwindows in assembly:
```
1. _werase(parent_win)           // clear parent
2. Draw parent borders/content
3. _touchwin(parent_win)         // mark parent as changed
4. _wnoutrefresh(parent_win)     // copy parent to virtual screen
5. For each child subwindow:
   a. _werase(child_win)
   b. Draw child content
   c. _wnoutrefresh(child_win)   // copy child to virtual screen
6. _doupdate()                   // single physical screen update
```
Never call `_wrefresh()` on individual subwindows -- it triggers `doupdate()` immediately, causing partial-frame rendering. Always use `_wnoutrefresh()` for all windows, then `_doupdate()` once.

**Detection:**
- Board area goes blank after adding subwindows
- Borders drawn on parent appear momentarily then vanish
- Running `_wrefresh` instead of `_wnoutrefresh` on any subwindow

**Phase to address:** First phase (subwindow layout). Get the refresh ordering right before drawing any content into subwindows.

**Severity:** will-corrupt-display

---

### Pitfall 2: Accessing ACS Box-Drawing Characters Requires GOT-Indirect Load of acs_map

**What goes wrong:**
The C++ original uses `ACS_VLINE`, `ACS_HLINE`, `ACS_ULCORNER`, etc. for fancy borders via `wborder()`. These are NOT integer constants -- they are macros that index into ncurses' `acs_map[]` global array. In assembly, you cannot just pass a hardcoded value to `_wborder`. You must load the `_acs_map` symbol (an external `chtype[]` array from libncurses), index into it with the correct character key, and pass the resulting `chtype` value.

**Why it happens:**
The header defines `#define ACS_VLINE NCURSES_ACS('x')` which expands to `acs_map[(unsigned char)'x']`. In C, the compiler handles this transparently. In assembly, you see `ACS_VLINE` in documentation and assume it is a constant like `0x78` ('x'). Passing `0x78` to `_wborder` draws the literal character 'x' instead of a line-drawing character.

On macOS, `NCURSES_REENTRANT` is 0, so `_acs_map` is a plain global array (not a function), accessed via GOT indirection:
```asm
// Load acs_map base via GOT
adrp    x8, _acs_map@GOTPAGE
ldr     x8, [x8, _acs_map@GOTPAGEOFF]
// ACS_VLINE = acs_map['x'] = acs_map[0x78]
// chtype is unsigned int (4 bytes) on macOS
mov     w9, #0x78               // 'x'
ldr     w10, [x8, x9, lsl #2]  // w10 = acs_map['x'] = ACS_VLINE chtype
```

**Consequences:**
- Borders show literal ASCII characters ('x', 'q', 'l', etc.) instead of line-drawing glyphs
- `_wborder` appears to "work" but renders garbage characters

**Prevention:**
- The `acs_map` array is only populated AFTER `_initscr()` returns. Any attempt to read it before initialization returns zero values.
- `chtype` on macOS is `unsigned int` (4 bytes), so index with `lsl #2`.
- Character keys for each ACS character (from curses.h):
  - `ACS_ULCORNER` = acs_map['l'] (0x6C)
  - `ACS_LLCORNER` = acs_map['m'] (0x6D)
  - `ACS_URCORNER` = acs_map['k'] (0x6B)
  - `ACS_LRCORNER` = acs_map['j'] (0x6A)
  - `ACS_HLINE` = acs_map['q'] (0x71)
  - `ACS_VLINE` = acs_map['x'] (0x78)
  - `ACS_LTEE` = acs_map['t'] (0x74)
  - `ACS_RTEE` = acs_map['u'] (0x75)

**Detection:**
- Box borders render as regular ASCII letters instead of line-drawing characters
- `_wborder` takes 10 arguments (win + 8 border chars) -- incorrect argument count is another failure mode

**Phase to address:** First phase (subwindow layout with borders).

**Severity:** visual-corruption (not a crash, but the feature is fundamentally broken)

---

### Pitfall 3: derwin Shares Memory with Parent -- Writing to Parent Overwrites Child Content

**What goes wrong:**
`derwin()` creates a subwindow that shares the same character buffer as the parent window. Calling `_werase()` on the parent clears the child's content too, because they share memory. If you erase the parent and then draw parent content (borders) that overlaps the child's region, the child's content is destroyed before the child has a chance to redraw.

**Why it happens:**
The C++ original handles this by design: it erases containers, refreshes them, THEN erases and draws child windows. The LayoutGame::draw() method calls `this->main->clear()` / `this->main->refresh()` on the main window first, then proceeds to draw children. If the assembly implementation erases the parent window AFTER drawing child content, the child content vanishes.

**Consequences:**
- Content drawn to a subwindow is invisible because the parent was erased afterward
- Flickering where child content appears for one frame then disappears
- Especially dangerous with the board subwindow: animation drawn behind the board can erase the board content if refresh order is wrong

**Prevention:**
- Always erase and refresh parent containers BEFORE drawing child content
- The draw order must be: erase parent -> draw parent borders -> wnoutrefresh parent -> erase child -> draw child content -> wnoutrefresh child -> doupdate
- An alternative: use `_newwin()` (independent windows) instead of `_derwin()` (subwindows) to avoid shared memory. Independent windows are simpler in assembly but lose the parent-relative coordinate convenience. Given the fixed 80x24 layout with known positions, independent `_newwin()` windows are the safer choice for this project.

**Detection:**
- Subwindow content disappears after parent operations
- Drawing to board window then erasing parent makes board blank

**Phase to address:** First phase (subwindow layout). Decide between `derwin` and `newwin` early.

**Severity:** will-corrupt-display

---

### Pitfall 4: Animation State Buffers Consume Significant .data Section Space

**What goes wrong:**
The four background animations (fire, water, snakes, Game of Life) each require per-cell state buffers. The board area is approximately 20x20 characters (inside borders). The fire animation needs a `particle` array + `coolingMap` array = 2 x 400 = 800 integers. Water needs two double-buffered integer arrays = 2 x 400 = 800 integers. Game of Life needs a boolean array = 400 bytes. These must be allocated in the `.data` or `.bss` section. At 4 bytes per int, fire alone needs 3,200 bytes, water needs 3,200 bytes.

**Why it happens:**
In C++, these are heap-allocated (`new Array2D<int>`). In assembly, there is no heap allocator unless you call `_malloc`. The project's existing pattern uses static `.data` section allocations (the 200-byte board, etc.). Following this pattern for animation buffers is correct but the size increase is significant.

**Consequences:**
- Binary size increases by approximately 6-8KB for animation buffers (if statically allocated in .data)
- If using `.space` in `.bss`, no binary size impact but alignment and access patterns matter
- Stack allocation is NOT viable -- 3,200 bytes exceeds typical stack frame budgets and complicates prologue/epilogue

**Prevention:**
- Use `.section __DATA,__bss` with `.space` for animation buffers -- zero binary size cost, kernel provides zero-filled pages
- Alternatively, call `_malloc` at animation init time and `_free` at cleanup. This matches the C++ original's pattern and avoids static buffer bloat. The returned pointer must be stored in a callee-saved register or global.
- Do NOT try to allocate animation buffers on the stack -- a 3,200-byte stack allocation requires careful alignment and complicates the prologue
- Consider: only one animation type is active at a time, so a single shared buffer region (sized for the largest animation) works

**Detection:**
- Binary size jumps significantly after adding animation data sections
- Stack overflow if buffers are stack-allocated in the game loop frame

**Phase to address:** Animation implementation phase.

**Severity:** design-constraint (not a crash, but must be decided architecturally)

---

### Pitfall 5: Animation Timing Without Floating Point Causes Drift or Jitter

**What goes wrong:**
The C++ animations throttle updates with `timer.delta_ms() < 100` (fire), `< 200` (Game of Life), `< 300` (water), `< 50` (snakes update). The existing assembly timer (`_get_time_ms`) returns milliseconds via `gettimeofday`, which works. The pitfall is implementing the "has enough time elapsed" check incorrectly in integer arithmetic, causing either: (a) animations that never update because the comparison is wrong, or (b) animations that update every frame because the elapsed calculation wraps or overflows.

**Why it happens:**
The existing game gravity timer stores `_last_drop_time` as a 64-bit millisecond value and computes `elapsed = current - last_drop`. This pattern works. But animation timers introduce MULTIPLE independent timers (one per animation type, plus the snake's `addTimer` and `updateTimer`). Managing 2-3 independent 64-bit timer variables while keeping callee-saved registers for other state becomes a register allocation challenge.

**Consequences:**
- Animations freeze (timer never fires)
- Animations run at full frame rate (visual noise, high CPU)
- Timer variable stored in a caller-saved register gets clobbered by an ncurses call between timer reads

**Prevention:**
- Store all animation timer values as 64-bit `.quad` globals in `.data`, not in registers. The game loop only needs to load them once per frame.
- The pattern: `_get_time_ms` -> load `_anim_last_update` -> subtract -> compare -> if elapsed >= threshold, update and store new timestamp
- Use SEPARATE timer variables per animation (fire_timer, water_timer, etc.) since they run at different rates
- The snakes animation needs TWO timers (add and update) -- plan for this in the data section

**Detection:**
- Animation visuals are static (never update)
- Animation updates every frame (threshold check always passes)
- Timer values are garbled (stored in x9-x15, clobbered by ncurses calls)

**Phase to address:** Animation implementation phase.

**Severity:** subtle-bug

---

### Pitfall 6: T-Spin Detection Requires Tracking "Last Move Was Rotation" State

**What goes wrong:**
T-spin scoring requires knowing that the last successful movement of the T-piece was a rotation (not a translation). The current assembly codebase does not track what kind of move was last performed -- `_try_move` and `_try_rotate` are independent functions that update piece position but do not record which was called last. Without this state, T-spin detection cannot distinguish between a T-piece that rotated into a corner (T-spin) and one that was moved sideways into the same position (not a T-spin).

**Why it happens:**
The original scoring system is simple: 100/300/500/800 points for 1/2/3/4 lines. T-spin detection adds a new requirement: at lock time, the system must know (a) the piece is type T, (b) the last action was a rotation, and (c) at least 3 of 4 diagonal corners around T's center are occupied. Requirement (b) is the one that requires new state tracking that does not exist in the current architecture.

**Consequences:**
- Without last-move tracking: all T-placements in corners would incorrectly count as T-spins, or none would
- Incorrect scoring inflates or deflates scores
- Players familiar with modern Tetris will notice immediately

**Prevention:**
- Add a `_last_move_was_rotation` byte to `.data` section
- Set to 1 in `_try_rotate` on successful rotation (after updating piece position)
- Set to 0 in `_try_move` on successful move
- Set to 0 in `_soft_drop` and `_hard_drop` (gravity/drop is not a rotation)
- At lock time in `_lock_piece`, check this flag before performing corner detection
- The corner check itself is straightforward: read 4 board cells at the T-piece center's diagonals. The center is at `(piece_x + 2, piece_y + 2)` in the 5x5 grid (where the pivot cell marked `2` in `_piece_data` is located). Check board cells at `(cx-1,cy-1)`, `(cx+1,cy-1)`, `(cx-1,cy+1)`, `(cx+1,cy+1)`.

**Detection:**
- T-spin bonus awarded when piece was translated into position (not rotated)
- T-spin bonus never awarded despite correct rotation placement

**Phase to address:** Modern scoring phase.

**Severity:** wrong-behavior

---

### Pitfall 7: File I/O Error Handling in Assembly -- Silent Data Loss

**What goes wrong:**
Hi-score persistence requires `open()`, `write()`, `read()`, `close()` syscalls (or their libSystem equivalents). In assembly, every one of these can fail, and on Darwin, errors are indicated by the carry flag being set with a non-negative error code in x0. If the carry flag is not checked after each call, the code proceeds with an error code treated as a file descriptor or byte count, causing silent corruption: writing the "score" to file descriptor 2 (stderr) instead of the actual file, or reading 0 bytes and treating uninitialized buffer content as the saved score.

**Why it happens:**
The existing codebase does no file I/O. The only syscall (`write` to stderr for frame timing stats) does not check for errors because writing stats to stderr is best-effort. Adding hi-score persistence requires robust error handling that the project has no existing pattern for.

**Consequences:**
- Hi-score silently lost (file creation failed, no error reported)
- Score file contains garbage (partial write, no error check on write byte count)
- Score always reads as 0 (file does not exist, read returns -1 treated as score value)
- Crash: open returns -1 (error), passed to write as fd, write to fd -1 may crash or corrupt

**Prevention:**
- Use libSystem wrappers (`_open`, `_write`, `_read`, `_close`) via `bl` instead of raw syscalls. These set errno and return -1 on error with standard POSIX semantics, not carry-flag based.
- Darwin syscall numbers for reference: open=5, read=3, write=4, close=6
- After EVERY file operation, check return value:
  ```asm
  bl      _open
  cmn     x0, #1          // compare with -1
  b.eq    Lopen_failed    // handle error
  // x0 is now a valid file descriptor
  ```
- For a simple single-score file: the format should be minimal. Write 4 bytes (a 32-bit unsigned integer) as raw binary. No text parsing needed. Read 4 bytes, check that exactly 4 bytes were returned.
- Determine file path: the C++ original stores scores in a user profile directory with Base64 encoding and INI parsing. For the assembly version, a single file at a fixed path (`~/.yetris_hiscore` or similar) with a raw 4-byte score is dramatically simpler and appropriate for assembly.
- Expanding `~` requires calling `_getenv("HOME")` and concatenating strings -- use a fixed stack buffer for the path.

**Detection:**
- Hi-score is always 0 after restart (file was never created/written)
- Hi-score shows garbage values (partial read or uninitialized buffer)
- Program crashes on first game over if score directory does not exist

**Phase to address:** Hi-score persistence phase.

**Severity:** subtle-bug (no crash, but data silently lost)

---

### Pitfall 8: wborder Takes 9 Arguments on Darwin -- Miscounting Causes Crash or Wrong Borders

**What goes wrong:**
`_wborder` takes 9 arguments: (WINDOW*, ls, rs, ts, bs, tl, tr, bl, br) where each border character is a `chtype` (4-byte unsigned int on macOS). On ARM64 Darwin, the first 8 arguments go in x0-x7. The 9th argument (br = bottom-right corner) must go in... actually all 9 fit in registers since ARM64 passes the first 8 integer arguments in registers x0-x7, and the window pointer is x0, leaving 8 chtype arguments for x1-x7 plus one on the stack. Wait -- that is 9 total arguments: 1 window + 8 border chars. x0-x7 = 8 registers. The 9th argument goes on the stack.

**Why it happens:**
The `wborder` prototype is: `int wborder(WINDOW*, chtype, chtype, chtype, chtype, chtype, chtype, chtype, chtype)`. That is 9 parameters. ARM64 ABI passes the first 8 in x0-x7. The 9th (bottom-right corner character) must be passed on the stack. Forgetting the stack argument causes `_wborder` to read garbage from the stack as the bottom-right corner, or worse, misalign the stack.

**Consequences:**
- Bottom-right corner of every bordered window shows garbage character
- If stack is not properly prepared, `_wborder` reads past valid memory

**Prevention:**
- Pass 0 for all 8 border arguments to get default ACS characters (simplest approach -- `_wborder(win, 0, 0, 0, 0, 0, 0, 0, 0)` uses defaults):
  ```asm
  ldr     x0, [x19]       // WINDOW* stdscr
  mov     x1, #0          // ls = default
  mov     x2, #0          // rs = default
  mov     x3, #0          // ts = default
  mov     x4, #0          // bs = default
  mov     x5, #0          // tl = default
  mov     x6, #0          // tr = default
  mov     x7, #0          // bl = default
  // 9th arg (br) on stack
  sub     sp, sp, #16     // maintain alignment
  str     xzr, [sp]       // br = 0 (default)
  bl      _wborder
  add     sp, sp, #16
  ```
- Alternatively, use `_box(win, 0, 0)` which is a simplified 3-argument version that uses default border characters. Only 3 args, all in registers, no stack required.
- For fancy borders with custom ACS characters, you must load each from `_acs_map` (see Pitfall 2) AND put the 9th on the stack.

**Detection:**
- Bottom-right corner of windows shows wrong character
- Crash inside `_wborder` (stack misread)

**Phase to address:** First phase (subwindow layout with borders).

**Severity:** will-crash or visual-corruption

---

## Moderate Pitfalls

### Pitfall 9: Combo Counter Must Reset on Non-Clearing Placement, Not on Lock

**What goes wrong:**
Modern Tetris combo scoring awards `50 * combo_count * level` for each consecutive line-clearing placement. The combo counter increments when a lock clears lines and resets to -1 when a lock does NOT clear lines. The current `_lock_piece` function calls `_clear_lines` and gets a line count, but there is no state variable tracking the combo chain. Adding the combo counter in the wrong place (e.g., resetting on every lock instead of only on non-clearing locks) breaks combo scoring.

**Why it happens:**
The existing scoring in `_clear_lines` adds `_score_table[lines-1]` (100/300/500/800) to the score and returns. There is no concept of consecutive clears. Adding combos requires a persistent `_combo_count` variable that survives across multiple lock-spawn-lock cycles.

**Prevention:**
- Add `_combo_count` as a signed word in `.data` initialized to -1 (0xFFFFFFFF)
- In `_lock_piece`, AFTER `_clear_lines` returns:
  - If lines_cleared > 0: increment `_combo_count`; add `50 * _combo_count * _level` to score
  - If lines_cleared == 0: set `_combo_count` to -1
- The multiplication `50 * combo * level` is three integer multiplies -- straightforward in ARM64 with `mul`
- Reset `_combo_count` to -1 in `_reset_board` for new games

**Phase to address:** Modern scoring phase.

**Severity:** wrong-behavior

---

### Pitfall 10: Back-to-Back Detection Requires Classifying "Difficult" Clears

**What goes wrong:**
Back-to-back scoring gives 1.5x points for consecutive "difficult" line clears (Tetris = 4-line clear, or any T-spin clear). A "Single" (1-line), "Double" (2-line), or "Triple" (3-line) that is NOT a T-spin breaks the B2B chain. The implementation must classify each clear as difficult or easy, maintain a `_b2b_flag`, and apply the multiplier. The tricky part: a T-spin that clears 0 lines does NOT break the chain (it is not a line clear at all), but a non-T-spin single/double/triple DOES break it.

**Why it happens:**
This requires combining T-spin detection (Pitfall 6) with line clear count to produce a difficulty classification. Both systems must be implemented and working before B2B can function.

**Prevention:**
- Add `_b2b_active` byte in `.data` (0 = no chain, 1 = chain active)
- After each line clear, determine if the clear is "difficult": `(lines == 4) || (is_tspin && lines > 0)`
- If difficult and `_b2b_active` == 1: multiply score by 1.5 (use integer: `score = score * 3 / 2`, or `score + score / 2`)
- If difficult: set `_b2b_active` = 1
- If NOT difficult AND lines > 0: set `_b2b_active` = 0
- If lines == 0 (no clear, including T-spin 0): do NOT change `_b2b_active`
- The 1.5x multiplier in integer: `add x0, x0, x0, lsr #1` (x0 = x0 + x0/2). Be aware this truncates; for exact results, compute `x0 * 3` then `udiv x0, x0, 2` but division is expensive. The simpler `add + lsr` pattern is sufficient -- Tetris scores are not precision-critical.

**Phase to address:** Modern scoring phase (requires T-spin detection first).

**Severity:** wrong-behavior

---

### Pitfall 11: Perfect Clear Detection Must Scan Entire Board After Line Clear

**What goes wrong:**
A perfect clear (all 200 board cells are 0 after line clear) awards bonus points. The check must happen AFTER `_clear_lines` removes full rows, not before. If checked before clearing, the board still has the full rows and the check always fails. If the check is done at the wrong time in the lock-spawn cycle, the newly spawned piece's cells could be on the board, making a valid perfect clear appear as non-perfect.

**Why it happens:**
The current `_lock_piece` flow is: write piece to board -> clear lines -> spawn next piece. The perfect clear check must happen after clear lines but BEFORE the next piece is spawned (since spawn does not write to the board, this is actually fine -- but the timing must be explicit).

**Prevention:**
- Check perfect clear immediately after `_clear_lines` returns (and only if lines_cleared > 0)
- Use the existing NEON pattern: `ld1` + `uminv` can check 16 bytes at a time. For 200 bytes, that is 13 loads. If all `uminv` results are 0 AND all `umaxv` results are 0, the board is empty.
- Simpler scalar approach: loop over 200 bytes, `orr` them together, check if result is 0. Approximately 200 iterations but only needed when lines are cleared.
- Perfect clear scoring from modern Tetris guidelines (points added ON TOP of regular line clear score):
  - Single PC: 800 * level
  - Double PC: 1200 * level
  - Triple PC: 1800 * level
  - Tetris PC: 2000 * level
  - B2B Tetris PC: 3200 * level

**Phase to address:** Modern scoring phase (can be deferred as it is rare and complex).

**Severity:** wrong-behavior (but low-frequency -- perfect clears are rare)

---

### Pitfall 12: Line Clear Animation Introduces a Multi-Frame Delay into the Game Loop

**What goes wrong:**
The C++ original implements line clear animation by: (1) marking full rows with a special "clear_line" block type, (2) drawing the board with these marked rows highlighted, (3) calling `Utils::Time::delay_ms()` to pause, (4) then removing the rows. In LayoutGame.cpp line 394-401, it explicitly uses a blocking delay: `if (this->game->willClearLines) { draw board; delay_ms(line_clear_delay); }`. Translating this to assembly naively means calling `_usleep()` or similar inside the game loop, which BLOCKS input processing during the animation.

**Why it happens:**
The C++ original gets away with a blocking delay because the animation is brief (a few hundred ms). But in the assembly version, the game loop structure is `poll_input -> gravity -> render -> loop`. Inserting a blocking delay disrupts the frame timing measurements and prevents the player from inputting moves during the animation.

**Consequences:**
- Input is unresponsive during line clear animation (keys pressed during animation are lost)
- Frame timing statistics are skewed by the animation delay
- If the delay is too long, the game feels sluggish

**Prevention:**
- Use a state-based approach instead of blocking delay:
  1. Add `_line_clear_anim_timer` (64-bit quad) and `_line_clear_anim_active` (byte) to `.data`
  2. When lines are cleared in `_clear_lines`, mark the rows (set cell values to a special marker like 9) but do NOT remove them yet
  3. Set `_line_clear_anim_active = 1` and record current time in `_line_clear_anim_timer`
  4. In the render loop, if `_line_clear_anim_active`, draw marked rows with a flash effect (A_REVERSE or alternate color)
  5. After the animation duration elapses (check `_get_time_ms - _line_clear_anim_timer >= 200`), actually remove the rows and set `_line_clear_anim_active = 0`
- This keeps the game loop non-blocking and allows input processing during animation
- Gravity should be paused during line clear animation (do not advance `_last_drop_time`)

**Detection:**
- Game freezes briefly when lines are cleared
- Keys pressed during animation are ignored
- Frame timing stats show outlier frames during line clears

**Phase to address:** Line clear animation phase.

**Severity:** design-constraint (blocking approach works but degrades UX)

---

### Pitfall 13: _newwin and _derwin Return NULL on Failure -- Must Check Before Use

**What goes wrong:**
Both `_newwin()` and `_derwin()` return NULL (0) if the requested window dimensions exceed the available terminal size or if memory allocation fails. The existing assembly code does not create any windows (it uses `stdscr` directly). Adding subwindows means calling `_derwin()` multiple times, and any failure returns 0 in x0. Storing this NULL pointer and later passing it to `_wmove`, `_waddch`, or `_wrefresh` causes a segfault inside ncurses.

**Why it happens:**
The 80x24 layout assumes the terminal is at least 80 columns by 24 rows. If the terminal is smaller (e.g., user resized it), `_derwin` fails because the subwindow does not fit inside the parent.

**Consequences:**
- Crash (segfault) on game start if terminal is too small
- Crash on specific subwindow creation (e.g., statistics panel that extends beyond terminal width)

**Prevention:**
- Check return value of every `_newwin` / `_derwin` call: `cbz x0, Lcreation_failed`
- At game start, check terminal dimensions with `_getmaxy(stdscr)` and `_getmaxx(stdscr)` (or `_LINES` and `_COLS` globals). If smaller than 80x24, display an error message and exit gracefully.
- The C++ original creates the layout as `LayoutGame(this, 80, 24)` assuming this size.

**Phase to address:** First phase (subwindow layout).

**Severity:** will-crash (on small terminals)

---

## Minor Pitfalls

### Pitfall 14: Color Pair ORing with ACS Characters Requires Correct Bit Shifting

**What goes wrong:**
The C++ original's fancy borders use `ACS_VLINE | theme_color.ncurses_pair` to combine line-drawing characters with color attributes. In ncurses, `chtype` is a 32-bit value where the character is in the low bits and attributes (including color pair) are in the high bits. The color pair must be shifted to the correct bit position using `COLOR_PAIR(n)` macro, which on macOS ncurses is `((n) << 8)`. Passing an unshifted color pair number results in the wrong color or a corrupted character.

**Prevention:**
- `COLOR_PAIR(n)` on macOS = `n << 8` (shift left by 8 bits)
- To combine: `chtype value = acs_char | (pair_number << 8)`
- In assembly: `orr w_result, w_acs_char, w_pair, lsl #8`

**Phase to address:** Fancy borders/color phase.

**Severity:** visual-corruption

---

### Pitfall 15: T-Spin Mini vs Proper T-Spin Distinction

**What goes wrong:**
Modern Tetris distinguishes between "T-Spin Mini" and "T-Spin Proper" for scoring. A proper T-spin has the two "front" corners (facing the flat side of the T) occupied. A mini T-spin has only the two "back" corners occupied. The front/back distinction depends on the T-piece's rotation state, making the detection rotation-dependent. Implementing only the basic 3-corner check without front/back distinction gives incorrect scores for mini T-spins.

**Prevention:**
- The "front" corners depend on rotation:
  - Rotation 0 (T points up): front corners are (cx-1, cy-1) and (cx+1, cy-1)
  - Rotation 1 (T points right): front corners are (cx+1, cy-1) and (cx+1, cy+1)
  - Rotation 2 (T points down): front corners are (cx-1, cy+1) and (cx+1, cy+1)
  - Rotation 3 (T points left): front corners are (cx-1, cy-1) and (cx-1, cy+1)
- Use a lookup table (4 entries of 4 offsets each) indexed by rotation to get the front/back corner positions
- For v1.1 scope: implementing only basic T-spin (3-corner rule without mini distinction) is acceptable as a first pass

**Phase to address:** Modern scoring phase (can defer mini distinction).

**Severity:** wrong-behavior (subtle scoring inaccuracy)

---

### Pitfall 16: Register Pressure During Render Frame with Multiple Windows

**What goes wrong:**
The current `_render_frame` function uses callee-saved registers extensively (x19-x28) for board coordinates, color states, and loop counters. Adding subwindow management requires storing multiple WINDOW* pointers (board_win, score_win, next_win, hold_win, stats_win, main_win) plus the existing rendering state. With only 10 callee-saved registers (x19-x28), there are not enough registers to hold all window pointers plus rendering state simultaneously.

**Prevention:**
- Store WINDOW* pointers as globals in `.data` section (they do not change after initialization)
- Load window pointers with `adrp + add` pattern at the start of each render sub-function, not as callee-saved register allocation
- The existing pattern of loading `_stdscr` via GOT for every call is already correct -- extend this pattern to the new window pointers
- Alternative: create a "window table" in `.data` -- an array of WINDOW* quads indexed by panel ID. One `adrp + add` to get the table base, then `ldr x0, [xbase, #offset]` to get each window pointer.

**Phase to address:** Subwindow layout phase (rendering refactor).

**Severity:** design-constraint (not a crash, but must be planned)

---

### Pitfall 17: Score Overflow at High Combo/Level Combinations

**What goes wrong:**
The current `_score` is a 32-bit unsigned word (max 4,294,967,295). Modern scoring with level multipliers, combos, B2B, and perfect clears can accumulate large scores. A level 22 Tetris B2B clear is `800 * 1.5 * 22 = 26,400` plus combo bonus. This is well within 32-bit range for individual clears, but sustained play at high levels with B2B chains could theoretically overflow. More practically, the display formatting assumes a certain digit count.

**Prevention:**
- 32-bit score is sufficient for realistic gameplay (would need ~162,000 Tetris clears to overflow)
- Ensure display formatting handles scores up to 10 digits (4,294,967,295 is 10 digits)
- The existing `_draw_score_panel` formats numbers with the `Lwrite_number_to_buf` helper which handles arbitrary unsigned values

**Phase to address:** Scoring display (minor concern).

**Severity:** cosmetic (extremely unlikely to occur in practice)

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Subwindow layout | Refresh ordering (Pitfall 1, 3) | Use wnoutrefresh + doupdate pattern; test with borders-only before content |
| Fancy borders | ACS character loading (Pitfall 2, 8) | Verify acs_map access with a test border before full implementation |
| Background animations | Buffer allocation + timing (Pitfall 4, 5) | Use .bss for buffers; use global timer variables, not registers |
| Modern scoring (combos) | Combo counter lifecycle (Pitfall 9) | Unit test: lock piece without clear resets combo; lock with clear increments |
| T-spin detection | Last-move tracking + corner check (Pitfall 6, 15) | Add _last_move_was_rotation flag; start with 3-corner basic, add mini later |
| Back-to-back | Difficulty classification (Pitfall 10) | Requires T-spin working first; test: Tetris then single breaks chain |
| Perfect clear | Board scan timing (Pitfall 11) | Check after clear_lines, before spawn; NEON scan is elegant but scalar works |
| Line clear animation | Blocking vs state-based (Pitfall 12) | Use state machine with timer, not usleep; keep game loop non-blocking |
| Hi-score file I/O | Error handling on every call (Pitfall 7) | Check every return value; use libSystem _open/_read/_write, not raw syscalls |
| Color + UI polish | COLOR_PAIR bit shifting (Pitfall 14) | COLOR_PAIR(n) = n << 8 on macOS; verify with single colored character first |

---

## Integration Pitfalls (Adding to Existing Codebase)

These pitfalls are specific to integrating new features into the existing v1.0 assembly without breaking it.

| Integration Point | Risk | Prevention |
|-------------------|------|------------|
| Replacing stdscr rendering with subwindows | All existing render functions write to stdscr via GOT load. Changing to subwindows requires updating EVERY drawing function. | Create a `_game_board_win` global. Update `_draw_board`, `_draw_piece`, `_draw_ghost_piece` to load from this global instead of `_stdscr`. Test each function individually after conversion. |
| Adding new state variables to data.s | Alignment requirements. The current data.s has careful `.p2align` directives. Adding bytes between aligned words breaks alignment of subsequent variables. | Always add new variables at the END of the data section, with appropriate `.p2align` before any multi-byte variable. |
| Modifying _lock_piece for modern scoring | Current function has a clean flow: write to board -> add 10 -> clear lines -> return. T-spin check, combo update, B2B check all add complexity. | Keep _lock_piece calling new functions (_check_tspin, _update_combo, _check_perfect_clear) rather than inlining all logic. Preserve the existing return value (lines cleared count). |
| Adding animation update to game loop | The main.s game loop is tight: poll_input -> gravity check -> render_frame. Animation update must happen between gravity and render. | Add `bl _update_animation` between gravity check and render_frame. The animation function itself handles timer-based throttling internally (returns immediately if not enough time has passed). |
| New ncurses functions not yet linked | The current binary links against ncurses but only uses a subset. `_derwin`, `_newwin`, `_delwin`, `_touchwin`, `_wnoutrefresh`, `_doupdate`, `_wborder`, `_box` are all in libncurses but not yet referenced. | No linker changes needed -- dynamic linking resolves all ncurses symbols automatically. But the symbols must be declared in assembly with the correct underscore prefix and called via `bl`. |
| x28 packed bitfield register repurpose | In main.s, x28 is used as a packed game state bitfield (bits 0-2). Adding new game state flags (line_clear_anim_active, etc.) to x28 adds complexity and makes the bitfield harder to debug. | Store new state flags as separate `.byte` globals in data.s rather than packing into x28. The x28 bitfield was a v1.0 optimization experiment; new state should use the simpler global pattern. |

---

## "Looks Done But Isn't" Checklist for v1.1

- [ ] **Subwindow refresh order:** Board renders correctly with borders -- resize terminal smaller than 80x24 and verify graceful handling (not a crash)
- [ ] **ACS characters:** Borders show line-drawing glyphs, not ASCII letters -- check in a terminal that supports UTF-8 and one that does not
- [ ] **Animation timing:** Fire/water/snakes/life update at their intended rate (100ms/300ms/50ms/200ms), not every frame or never
- [ ] **T-spin scoring:** T-spin double awards 1200 points (not 300 for a regular double) -- manually set up a T-spin scenario in testing
- [ ] **Combo scoring:** Three consecutive line clears award increasing combo bonus -- verify combo resets after a non-clearing lock
- [ ] **B2B scoring:** Tetris followed by Tetris gives 1.5x on second -- verify single between two Tetris clears resets B2B
- [ ] **Hi-score persistence:** Score survives quit and relaunch -- delete the score file and verify graceful handling (no crash, score shows 0)
- [ ] **Line clear animation:** Flash effect visible for ~200ms before rows collapse -- verify input is still responsive during animation
- [ ] **Perfect clear:** All cells empty after clear triggers bonus -- verify bonus is ON TOP of regular score, not replacing it
- [ ] **Color on borders:** Fancy border colors match C++ original (dim/bright sides) -- verify color pairs are shifted correctly (not ORed unshifted)

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Wrong refresh ordering (Pitfalls 1, 3) | MEDIUM | Restructure render loop to wnoutrefresh + doupdate pattern; may require rewriting _render_frame |
| ACS character loading wrong (Pitfall 2) | LOW | Fix GOT load of _acs_map; update all wborder calls |
| wborder 9th argument missing (Pitfall 8) | LOW | Add stack push for 9th arg; or switch to _box(win, 0, 0) |
| Missing last-move-was-rotation flag (Pitfall 6) | MEDIUM | Add flag to data.s; modify _try_rotate and _try_move; add T-spin check in _lock_piece |
| Combo counter lifecycle wrong (Pitfall 9) | LOW | Fix reset condition in _lock_piece |
| File I/O error handling missing (Pitfall 7) | MEDIUM | Add error checking branches after every file operation; test with read-only filesystem |
| Line clear animation blocks input (Pitfall 12) | HIGH | Requires refactoring from blocking delay to state-machine approach; touches game loop structure |
| Register pressure in render (Pitfall 16) | LOW | Move window pointers to globals; no register allocation needed |

---

## Sources

- [ncurses curs_window(3x) man page -- derwin, subwin, newwin](https://invisible-island.net/ncurses/man/curs_window.3x.html) -- HIGH confidence; official ncurses documentation
- [ncurses intro -- refresh ordering with wnoutrefresh and doupdate](https://invisible-island.net/ncurses/ncurses-intro.html) -- HIGH confidence; official ncurses tutorial
- [GUILE NCURSES 2.2 -- Window creation and subwindow pitfalls](https://www.gnu.org/software/guile-ncurses/manual/html_node/Window-creation.html) -- HIGH confidence; GNU documentation
- [Terminal Tricks -- Curses Windows, Pads, and Panels](http://graysoftinc.com/terminal-tricks/curses-windows-pads-and-panels) -- MEDIUM confidence; comprehensive tutorial
- [T-Spin -- TetrisWiki](https://tetris.wiki/T-Spin) -- HIGH confidence; authoritative community reference
- [Scoring -- TetrisWiki](https://tetris.wiki/Scoring) -- HIGH confidence; authoritative community reference
- [Combo -- TetrisWiki](https://tetris.wiki/Combo) -- HIGH confidence; authoritative community reference
- [Back-to-Back -- Hard Drop Tetris Wiki](https://harddrop.com/wiki/Back-to-Back) -- HIGH confidence; competitive Tetris community reference
- [Tetris Aside: Coding for T-Spins -- katyscode](https://katyscode.wordpress.com/2012/10/13/tetris-aside-coding-for-t-spins/) -- MEDIUM confidence; implementation guide
- [macOS ncurses curses.h header](/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/curses.h) -- HIGH confidence; actual system header inspected
- [macOS ncurses_dll.h header](/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/ncurses_dll.h) -- HIGH confidence; NCURSES_PUBLIC_VAR definition verified
- [macOS sys/syscall.h](/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/syscall.h) -- HIGH confidence; Darwin syscall numbers
- [HelloSilicon -- ARM64 Assembly on Apple Silicon](https://github.com/below/HelloSilicon) -- HIGH confidence; Apple Silicon assembly reference
- Existing codebase: asm/render.s, asm/main.s, asm/board.s, asm/data.s, asm/piece.s -- PRIMARY SOURCE; actual code being modified
- C++ reference: src/Game/Display/Layouts/LayoutGame.cpp, deps/Engine/Graphics/Window.cpp, deps/Engine/Graphics/Animation/*.cpp -- PRIMARY SOURCE; target behavior to match

---

*Pitfalls research for: v1.1 Visual Polish & Gameplay features on existing ARM64 assembly Tetris*
*Researched: 2026-02-27*
