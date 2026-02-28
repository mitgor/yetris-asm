# Phase 9: Line Clear Animation - Research

**Researched:** 2026-02-27
**Domain:** ARM64 assembly game loop timing, ncurses rendering, non-blocking animation
**Confidence:** HIGH

## Summary

Phase 9 adds a visual line clear animation: when rows are completed, they flash with special marker characters (`::`/white) for ~200ms before being removed. This requires splitting the current atomic `_clear_lines` operation into two phases -- a mark phase (replace full rows with flash markers) and a deferred clear phase (collapse rows after the delay expires).

The C++ reference implementation uses a two-frame approach: `markFullLines()` replaces full row cells with `clear_line` blocks (appearance `::`, white color), sets a `willClearLines` flag, and on the *next frame* calls `clearFullLines()` to collapse the rows. The asm implementation needs a similar state machine, but with an explicit timer to achieve the ~200ms delay (the C++ original only waits one frame at ~60fps, which is ~16ms -- the requirement asks for a longer, more visible flash).

The key architectural change is introducing a "line clear pending" state in the game loop. During this state, the board displays flash markers, input continues to be processed (but no gravity ticks), and after the delay expires, rows collapse and the next piece spawns. This keeps the game responsive while showing the animation.

**Primary recommendation:** Add a `_line_clear_state` variable (0=idle, 1=flashing) with `_line_clear_timer` timestamp. Split `_lock_piece` to mark-then-delay instead of mark-then-immediately-clear. The game loop skips gravity during the flash window but continues accepting input and rendering. Use a special board cell value (9) for flash markers, rendered as `::` in white.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CLEAR-01 | Full rows flash with special marker characters (e.g., '::') before removal | Board cell value 9 = flash marker, rendered as `::` with white COLOR_PAIR(3) in `_draw_board`. C++ reference uses `Block(Colors::pair("white", "default"), ':', ':')` |
| CLEAR-02 | 200ms visual delay between flash and row removal, matching C++ behavior | `_line_clear_state` + `_line_clear_timer` state machine in game loop; `_get_time_ms` for timing; gravity paused during flash but input still processed |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ncurses | system (macOS) | Terminal rendering via waddch/wattr_on/wattr_off | Already in use; flash markers rendered through existing `_draw_board` path |
| _get_time_ms | internal (timer.s) | Millisecond timestamps for delay measurement | Already used for gravity timing; same pattern for animation timing |

### Supporting
No new libraries needed. All animation is built on existing infrastructure.

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Timer-based delay (200ms) | Frame-counting delay (12 frames at 16ms) | Timer is more accurate and independent of frame rate; frame counting would drift if frames take variable time |
| Special board cell value (9) | Separate 20-byte bitmask of "flashing rows" | Board cell value is simpler (one check in renderer), bitmask requires extra array and cross-referencing |
| Blocking usleep(200000) | Non-blocking timer check per frame | usleep would freeze input for 200ms -- unacceptable; timer check keeps game responsive |

## Architecture Patterns

### Current Lock+Clear Flow (What Changes)

Current flow in `_lock_piece` (board.s) and `_soft_drop`/`_hard_drop` (piece.s):
```
_hard_drop / _soft_drop:
  1. Lock piece into board (_lock_piece)
     -> writes cells to _board
     -> T-spin detection
     -> calls _clear_lines (immediately removes full rows)
     -> scoring engine (uses lines cleared count)
  2. Spawn next piece (_spawn_piece)
```

### New Mark/Clear Flow

```
_hard_drop / _soft_drop:
  1. Lock piece into board (_lock_piece)
     -> writes cells to _board
     -> T-spin detection
     -> calls _mark_lines (replaces full rows with value 9, does NOT collapse)
     -> scoring engine (uses lines marked count)
     -> if lines > 0: set _line_clear_state=1, record _line_clear_timer
  2. if lines > 0: do NOT spawn next piece yet (defer to after flash)
  3. if lines == 0: spawn next piece immediately

Game loop (main.s Lgame_frame):
  Check _line_clear_state:
    if state == 1 (flashing):
      - Skip gravity (piece not active)
      - Accept input? Only movement keys are irrelevant (no active piece).
        Simplest: skip ALL input during flash (200ms is imperceptible for input loss)
        OR: accept pause/quit input only during flash
      - Check timer: if elapsed >= 200ms:
        -> call _clear_marked_lines (collapse the marked rows)
        -> set _line_clear_state = 0
        -> spawn next piece
        -> reset gravity timer
    if state == 0:
      - Normal game frame (current behavior)
```

### Pattern: Board Cell Value 9 as Flash Marker

The board uses values 0-8 already:
- 0 = empty
- 1-7 = piece colors (piece_type + 1)
- 8 = invisible marker

Value 9 is the natural next choice for the flash marker. The renderer already checks for 0 (empty) and 8 (invisible). Adding a check for 9 to render `::` in white is trivial.

**Rendering in `_draw_board`:**
```asm
// After loading board cell value w23:
cbz     w23, Ldraw_empty_cell       // 0 = empty
cmp     w23, #8
b.eq    Ldraw_empty_cell            // 8 = invisible (draw as empty)
cmp     w23, #9
b.eq    Ldraw_flash_cell            // 9 = flash marker

// ... existing colored block rendering ...

Ldraw_flash_cell:
    // White color: COLOR_PAIR(3) = 0x0300
    mov     x0, x19
    mov     w1, #0x0300              // COLOR_PAIR(3) = white
    mov     x2, #0
    bl      _wattr_on
    mov     x0, x19
    mov     w1, #0x3A               // ':'
    bl      _waddch
    mov     x0, x19
    mov     w1, #0x3A               // ':'
    bl      _waddch
    mov     x0, x19
    mov     w1, #0x0300
    mov     x2, #0
    bl      _wattr_off
    b       Ldraw_col_next
```

### Pattern: Splitting _clear_lines into Mark and Clear

**_mark_lines** (new function, replaces _clear_lines call in _lock_piece):
- Scan board bottom-to-top for full rows (same NEON uminv logic)
- Instead of shifting rows: overwrite all 10 cells in full rows with value 9
- Count lines, update stats (_lines_cleared, _level, line-type stats) -- same as current
- Return lines_cleared count for scoring engine

**_clear_marked_lines** (new function, called from game loop after delay):
- Scan board for rows where cell[0] == 9 (any marked row)
- For each marked row: shift all rows above down by one, fill top row with zeros
- Same shift logic as current `_clear_lines` Lclear_shift_loop

### Pattern: State Machine Integration in Game Loop

The game loop in main.s currently has this structure:
```
Lgame_frame:
  1. _poll_input + _handle_input
  2. Gravity timer check -> _soft_drop
  3. _render_frame
```

With line clear animation, add a check before gravity:
```
Lgame_frame:
  1. _poll_input + _handle_input (conditional: skip during flash, or allow pause/quit only)
  2. Check _line_clear_state:
     if flashing:
       check timer -> if expired: _clear_marked_lines + _spawn_piece + reset state
       skip gravity
     else:
       Gravity timer check -> _soft_drop
  3. _render_frame
```

### Data Variables Needed (in data.s)

```asm
// Line clear animation state
.globl _line_clear_state
_line_clear_state:  .byte 0         // 0=idle, 1=rows flashing

.globl _line_clear_timer
.p2align 3
_line_clear_timer:  .quad 0         // ms timestamp when flash started
```

### Anti-Patterns to Avoid
- **Blocking sleep during flash:** Using `usleep(200000)` or `nanosleep` would freeze the entire game for 200ms. The screen would not update, input would be lost, and it would feel laggy. Use a non-blocking timer check in the game loop instead.
- **Modifying _clear_lines in-place:** The current `_clear_lines` is clean and correct. Rather than adding conditional logic into it, create two new focused functions (`_mark_lines` and `_clear_marked_lines`) and stop calling `_clear_lines` from `_lock_piece`.
- **Spawning next piece during flash:** If the next piece spawns while rows are still flashing, it would appear to overlap with the flash markers and look wrong. Defer spawning until after the clear completes.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Millisecond timing | Custom tick counter | `_get_time_ms` (already exists in timer.s) | Already proven, gettimeofday-based, 64-bit ms resolution |
| Full-row detection | New row scanning | NEON uminv logic from existing `_clear_lines` | Already written and working; copy to `_mark_lines` |
| Board rendering | Separate flash renderer | Add flash case to existing `_draw_board` | One renderer, one code path, no duplication |

**Key insight:** This phase touches 4 files (board.s, main.s, render.s, data.s) but the changes are surgical -- no function signatures change, no new external dependencies, and the existing rendering infrastructure handles flash display naturally.

## Common Pitfalls

### Pitfall 1: Scoring Timing with Deferred Clear
**What goes wrong:** If scoring happens in `_clear_marked_lines` instead of at mark time, the score update is delayed 200ms after the player sees the lines complete.
**Why it happens:** Confusion about when scoring should occur relative to the visual animation.
**How to avoid:** Score at mark time (in `_lock_piece`, immediately when lines are detected), not at clear time. The scoring engine already runs in `_lock_piece` after `_clear_lines` returns the count -- just change `_clear_lines` to `_mark_lines` and the scoring pipeline is unaffected.
**Warning signs:** Score panel number jumps 200ms after piece locks.

### Pitfall 2: Gravity Timer Not Reset After Flash
**What goes wrong:** After the 200ms flash, gravity immediately fires because the timer was still running during the flash period.
**Why it happens:** `_last_drop_time` was set before the flash started; 200ms of flash time counts as gravity time.
**How to avoid:** Reset `_last_drop_time` to current time when exiting the flash state (same as pause resume does).
**Warning signs:** New piece drops instantly after spawning post-flash.

### Pitfall 3: Input During Flash Period
**What goes wrong:** Player presses keys during the 200ms flash. If movement keys are processed, they operate on... what piece? There is no active piece during flash.
**Why it happens:** The input handler tries to move/rotate a piece that doesn't exist yet.
**How to avoid:** Two safe options: (a) Skip all input processing during flash (simplest; 200ms is too short for the player to notice). (b) Only process pause/quit keys during flash. Option (a) is recommended.
**Warning signs:** Crash or undefined behavior when trying to validate piece position during flash.

### Pitfall 4: Hard Drop Double-Lock
**What goes wrong:** `_hard_drop` calls `_lock_piece` then `_spawn_piece` in sequence. If `_lock_piece` detects lines, it should NOT be followed by `_spawn_piece`.
**Why it happens:** Current code unconditionally calls `_spawn_piece` after `_lock_piece`.
**How to avoid:** `_lock_piece` returns lines cleared count in w0. Check w0: if > 0, skip `_spawn_piece` (it will be called after the flash delay). Same change needed in `_soft_drop` and `_user_soft_drop`.
**Warning signs:** New piece appears and is playable while flash is still showing.

### Pitfall 5: Game Over Check During Flash
**What goes wrong:** If the last piece locked triggers game over AND clears lines, the game over state might be checked before the flash completes, cutting the animation short.
**Why it happens:** `_spawn_piece` sets `_game_over` if the new piece collides. But `_spawn_piece` is deferred during flash.
**How to avoid:** Game over is only possible when spawning fails. Since spawning is deferred until after flash, game over naturally happens after the flash completes. No special handling needed.
**Warning signs:** None -- this pitfall is avoided by the deferred spawn pattern.

### Pitfall 6: _mark_lines Must Not Shift Rows
**What goes wrong:** If `_mark_lines` copies the shift logic from `_clear_lines`, it will collapse rows before the flash is visible.
**Why it happens:** Copy-paste from `_clear_lines` includes the shift loop.
**How to avoid:** `_mark_lines` ONLY overwrites full-row cells with value 9. No shifting. Shifting happens exclusively in `_clear_marked_lines`.
**Warning signs:** Rows disappear instantly without any flash.

## Code Examples

### Example 1: _mark_lines (new function for board.s)
```asm
// _mark_lines() -> w0 = number of lines marked (0-4)
// Scan board for full rows, replace cells with value 9 (flash marker).
// Updates _lines_cleared, _level, and line-type stats.
// Does NOT shift rows -- that happens in _clear_marked_lines after delay.
_mark_lines:
    // ... prologue (same as _clear_lines) ...

    // Load board base
    adrp    x19, _board@PAGE
    add     x19, x19, _board@PAGEOFF

    mov     w21, #0                 // lines_marked_count = 0
    mov     w20, #19                // row = 19 (bottom)

Lmark_row_loop:
    cmp     w20, #0
    b.lt    Lmark_done

    // NEON full-row check (same as _clear_lines)
    mov     w10, #10
    mul     w10, w20, w10
    uxtw    x10, w10
    add     x10, x19, x10
    ld1     {v0.16b}, [x10]
    adrp    x11, _neon_row_mask@PAGE
    add     x11, x11, _neon_row_mask@PAGEOFF
    ldr     q1, [x11]
    orr     v0.16b, v0.16b, v1.16b
    uminv   b2, v0.16b
    umov    w11, v2.b[0]
    cbz     w11, Lmark_not_full

    // Row is full -- overwrite all 10 cells with value 9
    add     w21, w21, #1
    mov     w22, #0
    mov     w10, #10
    mul     w10, w20, w10
    uxtw    x10, w10
Lmark_fill:
    mov     w8, #9
    strb    w8, [x19, x10]
    add     x10, x10, #1
    add     w22, w22, #1
    cmp     w22, #10
    b.lt    Lmark_fill

Lmark_not_full:
    sub     w20, w20, #1
    b       Lmark_row_loop

Lmark_done:
    // Update _lines_cleared, _level, stats (same as _clear_lines Lclear_done)
    // ... (identical stat update logic) ...

    mov     w0, w21                 // return lines marked count
    // ... epilogue ...
    ret
```

### Example 2: _clear_marked_lines (new function for board.s)
```asm
// _clear_marked_lines() -> void
// Scan for rows marked with value 9, collapse them by shifting rows down.
_clear_marked_lines:
    // ... prologue ...
    adrp    x19, _board@PAGE
    add     x19, x19, _board@PAGEOFF

    mov     w20, #19                // row = 19 (bottom)

Lcml_row_loop:
    cmp     w20, #0
    b.lt    Lcml_done

    // Check if row[0] == 9 (marked)
    mov     w10, #10
    mul     w10, w20, w10
    uxtw    x10, w10
    ldrb    w11, [x19, x10]
    cmp     w11, #9
    b.ne    Lcml_not_marked

    // Shift all rows above down (same as _clear_lines shift loop)
    // ... identical shift logic ...

    // Re-check same row (don't decrement)
    b       Lcml_row_loop

Lcml_not_marked:
    sub     w20, w20, #1
    b       Lcml_row_loop

Lcml_done:
    // ... epilogue ...
    ret
```

### Example 3: Game Loop Integration (main.s)
```asm
Lgame_frame:
    // 1. Check line clear animation state FIRST
    adrp    x8, _line_clear_state@PAGE
    ldrb    w9, [x8, _line_clear_state@PAGEOFF]
    cbz     w9, Lnormal_frame           // state 0: normal game frame

    // State 1: flashing -- check if 200ms delay has expired
    bl      _get_time_ms                // x0 = current time ms
    adrp    x8, _line_clear_timer@PAGE
    ldr     x9, [x8, _line_clear_timer@PAGEOFF]
    sub     x10, x0, x9                 // elapsed = current - start
    cmp     x10, #200
    b.lt    Lflash_render               // still flashing, just render

    // Flash expired: clear marked lines, spawn next piece
    bl      _clear_marked_lines
    bl      _spawn_piece

    // Reset state
    adrp    x8, _line_clear_state@PAGE
    strb    wzr, [x8, _line_clear_state@PAGEOFF]

    // Reset gravity timer (same as pause resume)
    bl      _get_time_ms
    adrp    x8, _last_drop_time@PAGE
    str     x0, [x8, _last_drop_time@PAGEOFF]

    // Sync game_over from _spawn_piece
    adrp    x8, _game_over@PAGE
    ldrb    w9, [x8, _game_over@PAGEOFF]
    bic     x28, x28, #1
    orr     x28, x28, x9

    b       Lnormal_input               // continue to normal frame with new piece

Lflash_render:
    // During flash: skip input, skip gravity, just render
    bl      _render_frame
    // ... frame timing ...
    b       Lstate_loop

Lnormal_frame:
    // ... existing game frame code (input + gravity + render) ...
```

### Example 4: Modified _hard_drop (piece.s)
```asm
_hard_drop:
    // ... existing drop loop + scoring + clear rotation flag ...

    bl      _lock_piece             // w0 = lines cleared count

    // If lines were cleared, defer spawn (flash animation handles it)
    cbnz    w0, Lhdrop_flash_started

    // No lines: spawn immediately (existing behavior)
    bl      _spawn_piece
    b       Lhdrop_epilogue

Lhdrop_flash_started:
    // Lines are marked with value 9 by _lock_piece/_mark_lines
    // _lock_piece already set _line_clear_state=1 and _line_clear_timer
    // Do NOT call _spawn_piece -- game loop will handle it after flash
    // ... epilogue ...
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Immediate line clear (current asm) | Mark-then-delay-then-clear (this phase) | Phase 9 | Visual feedback for player, matches C++ original behavior |
| C++ one-frame flash (~16ms) | Explicit 200ms timer | Phase 9 (requirement) | More visible animation, better player experience |

**Deprecated/outdated:**
- The current `_clear_lines` function will no longer be called from `_lock_piece`. It can be kept as dead code or removed. Recommend keeping it as a reference until `_mark_lines` + `_clear_marked_lines` are proven correct.

## Open Questions

1. **Input during flash: skip all or allow pause/quit?**
   - What we know: 200ms is too short for the player to meaningfully miss input. The C++ reference doesn't explicitly block input during the one-frame flash.
   - What's unclear: Whether blocking all input for 200ms could cause a key press to be "eaten" and feel unresponsive.
   - Recommendation: Skip all input during flash (simplest). The 16ms wgetch timeout means at most ~12 frames of no-input. If testing reveals this feels bad, add pause/quit handling only. Input queueing is NOT needed -- ncurses' internal buffer holds pending keypresses.

2. **Should _lock_piece set _line_clear_state, or should the caller (hard_drop/soft_drop)?**
   - What we know: `_lock_piece` already handles all scoring. Setting the flash state there keeps the "mark lines" and "start flash" logic co-located.
   - What's unclear: Whether callers need to know the state changed (for conditional spawn).
   - Recommendation: Have `_lock_piece` set the state internally AND return lines cleared in w0. Callers check w0 to decide whether to call `_spawn_piece`. This is cleaner than having callers set the state.

3. **NEON padding safety for _mark_lines overwriting cells with 9**
   - What we know: The board has 8 bytes of NEON padding after the 200-byte data area. `_mark_lines` writes value 9 to cells [0..9] of full rows. The NEON ld1 reads 16 bytes starting at row offset (10 data + 6 padding).
   - What's unclear: If a row is already fully marked (all 9s), the NEON uminv will see min=9 (non-zero) and treat it as "full" again on re-scan. This is only an issue if `_mark_lines` is called while a flash is already active.
   - Recommendation: Not a problem. `_mark_lines` is only called from `_lock_piece`, which only runs when a piece locks. During flash state, no piece can lock (no active piece). So `_mark_lines` will never encounter rows with value 9.

## Sources

### Primary (HIGH confidence)
- `/Users/mit/Documents/GitHub/yetris/asm/board.s` - Current `_clear_lines` implementation with NEON full-row detection
- `/Users/mit/Documents/GitHub/yetris/asm/main.s` - Game loop state machine, gravity timing, frame timing
- `/Users/mit/Documents/GitHub/yetris/asm/render.s` - `_draw_board` rendering, `_render_frame` orchestration
- `/Users/mit/Documents/GitHub/yetris/asm/data.s` - Board layout (200 bytes, values 0-8), state variables
- `/Users/mit/Documents/GitHub/yetris/asm/piece.s` - `_hard_drop`, `_soft_drop`, `_spawn_piece` flow
- `/Users/mit/Documents/GitHub/yetris/asm/input.s` - `_handle_input`, `_user_soft_drop` lock-and-spawn pattern
- `/Users/mit/Documents/GitHub/yetris/asm/timer.s` - `_get_time_ms` implementation (gettimeofday wrapper)

### Secondary (MEDIUM confidence)
- `/Users/mit/Documents/GitHub/yetris/src/Game/Entities/Board.cpp` - C++ reference `markFullLines()` and `clearFullLines()` two-phase approach
- `/Users/mit/Documents/GitHub/yetris/src/Game/Entities/Game.cpp` - C++ reference `willClearLines` flag and frame-delayed clear pattern
- `/Users/mit/Documents/GitHub/yetris/src/Game/Entities/Profile.cpp` - C++ clear_line block: `Block(Colors::pair("white", "default"), ':', ':')` -- white colons as flash appearance
- `/Users/mit/Documents/GitHub/yetris/src/Game/Entities/Block.hpp` - Block structure with 2-char appearance and color pair

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - No new dependencies; all infrastructure exists (ncurses, timer, board rendering)
- Architecture: HIGH - C++ reference provides proven two-phase pattern; direct port to assembly state machine
- Pitfalls: HIGH - Analyzed from actual codebase; timing/scoring/input interactions identified from real code paths

**Research date:** 2026-02-27
**Valid until:** indefinite (assembly project with stable dependencies)
