# Phase 3: Gameplay Feature Completeness - Research

**Researched:** 2026-02-26
**Domain:** AArch64 assembly game features (ghost piece, hold mechanic, next preview, pause/resume, statistics panel, binary size measurement)
**Confidence:** HIGH

## Summary

Phase 3 extends the Phase 2 playable Tetris with the remaining in-game mechanics that match the C++ yetris feature set: ghost piece (landing preview), hold piece (swap to hold slot), next piece preview panel, pause/resume, a statistics panel showing piece counts and line clear counts, and the first binary size comparison against the C++ baseline.

The C++ reference implementation (`src/Game/Entities/Game.cpp`, `PieceGhost.cpp`, `Statistics.hpp`, `LayoutGame.cpp`) was analyzed in detail. The ghost piece is implemented by copying the current piece's type/rotation/position and then hard-dropping it to compute the landing position -- this requires no new data structures, only a `_compute_ghost_y` function that reuses `_is_piece_valid`. The hold mechanic needs one new global variable (`_hold_piece_type`, plus a `_can_hold` flag) and a `_hold_piece` function that swaps the current piece into the hold slot. The next piece preview requires exposing the 7-bag's upcoming pieces (the bag array already exists in `data.s`). The pause mechanic is a single flag that gates the game loop's gravity timer and input dispatch. Statistics tracking needs 11 new `.word` counters in `data.s`. All features are additions to existing files with no structural changes required.

The screen layout needs expansion. Currently the score panel occupies column 24+. The new layout adds: a hold piece display (rows 10-14, column 24+), next piece preview (rows 1-8, right of board or further right), and a statistics panel (below score or further right). The ghost piece renders inline on the board using the piece's color with the A_DIM attribute (0x100000, verified on target) to distinguish it from the active piece. The binary size measurement is straightforward: record `wc -c` and `size` output for both asm and C++ binaries.

**Primary recommendation:** Implement features in dependency order: (1) ghost piece first (pure computation, reuses existing functions), (2) hold piece and next preview (new state variables + rendering), (3) statistics tracking (counters wired into lock_piece and clear_lines), (4) pause/resume (game loop gate), (5) statistics panel rendering, (6) binary size measurement script. Keep all new state in `data.s`, all new logic in existing files (piece.s, render.s, input.s, main.s), and avoid creating new `.s` files unless a single file becomes unwieldy.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| MECH-09 | Next piece preview (1-7 configurable) | The 7-bag in `data.s` already stores upcoming pieces in `_bag[0..6]` with `_bag_index` tracking position. The next N pieces are `_bag[_bag_index], _bag[_bag_index+1], ...`. Rendering: draw each next piece's 5x5 grid in a panel to the right of the board, stacked vertically. Start with 1 next piece (simplest), matching a common default. C++ reference supports 1-7 via `settings.game.next_pieces`. |
| MECH-10 | Hold piece mechanic (one slot, can't re-hold until lock) | C++ reference: `holdCurrentPiece()` checks `canHold` flag, swaps current piece type into `pieceHold`, resets `canHold = false`. On `lockCurrentPiece()`, sets `canHold = true`. In assembly: add `_hold_piece_type` (.byte, 0xFF = empty) and `_can_hold` (.byte) to `data.s`. New function `_hold_piece` in `piece.s`. New key binding ('c' = hold, matching common Tetris convention). |
| MECH-11 | Ghost piece (landing preview) | C++ reference: `PieceGhost::update()` copies master piece position, then calls `board->hardDrop(this)`. In assembly: `_compute_ghost_y()` takes current piece state, loops `_is_piece_valid(type, rotation, px, py+1)` incrementing py until invalid, returns last valid py. `_draw_ghost_piece()` in render.s renders using A_DIM attribute (0x100000) ORed with the piece's COLOR_PAIR to create a dimmed/translucent appearance. Draw ghost before active piece so active piece overwrites any overlap. |
| MECH-13 | Pause and resume with timer suspension | C++ reference: `Game::pause(bool)` sets `isPaused` flag, pauses/unpauses `timerPiece` and game `timer`. In assembly: add `_is_paused` (.byte) flag to `data.s`. When paused: skip gravity timer check, skip piece input (movement/rotation), draw "PAUSED" overlay on board. On unpause: record current time as `_last_drop_time` to prevent accumulated gravity. Key: 'p' toggles pause. |
| REND-04 | Piece statistics panel (count per type + singles/doubles/triples/tetris) | C++ reference: `Statistics` struct has per-piece counters (I,T,L,J,S,Z,O) and line clear type counters (singles, doubles, triples, tetris), plus total pieces and lines. In assembly: 11 new `.word` counters in `data.s`. Increment piece counter in `_lock_piece` (board.s) based on `_piece_type`. Increment line clear type counter in `_clear_lines` based on count. Render in a panel showing "[I] x  3" style rows with colored piece labels and numeric counts. |
| MEAS-01 | Binary size tracked at each development stage vs C++ yetris baseline | Current measurements (Phase 2 complete): Assembly binary = 52,856 bytes (stripped: 51,632). C++ binary = 1,036,152 bytes (stripped: 546,448). Assembly __TEXT segment = 16,384 bytes (actual code: ~4,556 bytes). The assembly binary is already ~20x smaller than C++ (unstripped) and ~10.6x smaller (stripped). Record these in a measurements table, update after Phase 3 features are added, and again after Phase 4 and 5. |
</phase_requirements>

## Standard Stack

### Core

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Apple `as` (Clang integrated assembler) | clang 17.0.0 | Assemble `.s` files | Same as Phase 1-2 -- only assembler on macOS |
| Apple `ld` | ld-1230.1 | Link object files | Same as Phase 1-2 -- handles multi-file linking |
| System ncurses | 5.4 (libncurses.tbd) | Terminal rendering, input, color | All needed functions verified; A_DIM attribute verified (0x100000) |
| `gettimeofday` (libSystem) | System | Timer for gravity | Same as Phase 2 |
| GNU Make | System | Multi-file assembly build | Existing `ASM_SOURCES = $(wildcard $(ASM_DIR)/*.s)` handles new files automatically |
| `wc -c` / `size` / `otool -l` | System | Binary size measurement | Standard macOS tools for Mach-O binary analysis |

### Supporting

| Tool | Purpose | When to Use |
|------|---------|-------------|
| `strip` | Measure stripped binary size | For fair comparison against stripped C++ binary |
| `nm -g` | Verify symbol exports | When adding new global functions/variables |
| `otool -tV` | Disassemble for debugging | When verifying new feature code |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| A_DIM for ghost piece | A_REVERSE or separate color pair 8 (gray) | A_DIM is standard ncurses for "dimmed" appearance and reuses existing color pairs. A_REVERSE inverts colors which is less visually clear. A separate gray color pair works but adds init_pair calls. A_DIM is simplest and matches the "translucent" intent. |
| Rendering next/hold/stats on stdscr | Using newwin for separate panels | ncurses sub-windows would give cleaner borders and independent refresh, but add window management complexity. Phase 2 successfully uses stdscr with coordinate offsets. Continue this approach for consistency. Can refactor to windows in Phase 4 if needed. |
| Storing hold piece as full piece state | Storing just hold_piece_type (0-6, 0xFF=empty) | Only the piece type matters for hold. Rotation resets to 0 on swap, position is recomputed on spawn. Storing just the type byte is sufficient and matches the C++ reference which creates a fresh Piece object from the type. |

## Architecture Patterns

### Recommended Screen Layout (Phase 3)

```
Col:  0         10        20     24       30       36       44
Row 0:                            +--------+
Row 1:   +--------------------+   | Next   |  Score
Row 2:   |                    |   |  [##]  |  12345
Row 3:   |                    |   |  [##]  |
Row 4:   |                    |   +--------+  Level
Row 5:   |                    |                5
Row 6:   |   (10x20 board)    |   +--------+
Row 7:   |   ghost: dimmed    |   | Stats  |  Lines
Row 8:   |   piece: bright    |   | I x 3  |  42
Row 9:   |                    |   | T x 2  |
Row10:   |                    |   | L x 1  |  Hold
Row11:   |                    |   | ...    |  +------+
Row12:   |                    |   | S 0    |  | [##] |
Row13:   |                    |   | D 0    |  | [##] |
Row14:   |                    |   | T 0    |  +------+
Row15:   |                    |   | Tet 0  |
Row16:   |                    |   +--------+
...
Row20:   |                    |
Row21:   +--------------------+
```

The exact column positions will be determined during implementation. The key constraint is that the board (22 columns: border + 10*2 + border) occupies columns 0-21, with panels starting at column 23+.

### Pattern 1: Ghost Piece Computation

**What:** Compute where the current piece would land if hard-dropped, without modifying game state.
**When to use:** Every frame, before rendering.

```asm
// _compute_ghost_y() -> w0 = ghost_y (the lowest valid y for current piece)
// Reads: _piece_type, _piece_rotation, _piece_x, _piece_y
// Returns: the y coordinate where the piece would land
// Does NOT modify any game state

_compute_ghost_y:
    stp     x29, x30, [sp, #-48]!
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    mov     x29, sp

    // Load current piece state
    adrp    x8, _piece_type@PAGE
    ldrb    w19, [x8, _piece_type@PAGEOFF]     // type
    adrp    x8, _piece_rotation@PAGE
    ldrb    w20, [x8, _piece_rotation@PAGEOFF]  // rotation
    adrp    x8, _piece_x@PAGE
    ldrsh   w21, [x8, _piece_x@PAGEOFF]         // px
    adrp    x8, _piece_y@PAGE
    ldrsh   w22, [x8, _piece_y@PAGEOFF]         // py (current)

Lghost_loop:
    add     w3, w22, #1             // try_y = current_y + 1
    mov     w0, w19                 // type
    mov     w1, w20                 // rotation
    mov     w2, w21                 // px
    bl      _is_piece_valid
    cbz     w0, Lghost_done         // invalid -> stop
    add     w22, w22, #1            // advance y
    b       Lghost_loop

Lghost_done:
    mov     w0, w22                 // return last valid y
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
```

**Key insight:** This is identical to the hard_drop loop in `piece.s` (`_hard_drop`) except it does not modify `_piece_y`, does not lock the piece, and does not spawn the next piece. It is a pure query function.

### Pattern 2: Ghost Piece Rendering with A_DIM

**What:** Draw the ghost piece using the same color as the active piece but with A_DIM attribute to make it visually distinct (dimmed/translucent).
**When to use:** In `_render_frame`, after `_draw_board` and before `_draw_piece`.

```asm
// Draw ghost piece cells with dimmed color
// For each non-empty cell in piece grid:
//   attr = COLOR_PAIR(color_pair_num) | A_DIM
//   wattr_on(stdscr, attr, NULL)
//   wmove + waddch '[' + waddch ']'
//   wattr_off(stdscr, attr, NULL)

// A_DIM = 0x100000 (verified on target macOS ncurses)
// COLOR_PAIR(n) = n << 8
// Combined: (color_pair << 8) | 0x100000
```

**Rendering order matters:** Draw ghost BEFORE active piece. If the ghost and active piece overlap (which they do when at the same position), the active piece's bright colors overwrite the ghost's dimmed colors.

### Pattern 3: Hold Piece Mechanic

**What:** Player presses hold key -> current piece goes to hold slot, held piece (or next piece if hold was empty) becomes current.
**When to use:** On hold key press ('c').

```asm
// _hold_piece() -> void
// Precondition: _can_hold == 1 (checked before calling)
//
// Algorithm:
//   1. If _can_hold == 0, return immediately (already held this turn)
//   2. Set _can_hold = 0
//   3. Save current piece type
//   4. If _hold_piece_type == 0xFF (empty):
//        a. _hold_piece_type = current_type
//        b. Call _spawn_piece (get next from bag)
//   5. Else (hold has a piece):
//        a. tmp = _hold_piece_type
//        b. _hold_piece_type = current_type
//        c. Set _piece_type = tmp, reset rotation to 0
//        d. Set spawn position from tables
//        e. Check game over
```

**C++ reference pattern:** `canHold` is set to `false` when hold is used, reset to `true` in `lockCurrentPiece()`. This prevents hold-spam where a player could hold indefinitely.

### Pattern 4: Pause/Resume State Machine

**What:** A single boolean flag gates the game loop. When paused, gravity timer stops, input is limited to unpause/quit, and the board displays a "PAUSED" overlay.
**When to use:** On 'p' key press.

```asm
// In main game loop (main.s):
//
// After input handling:
//   1. Check _is_paused flag
//   2. If paused: skip gravity check, draw paused overlay, jump to wrefresh
//   3. If not paused: proceed with gravity and normal rendering
//
// On unpause:
//   1. Clear _is_paused flag
//   2. Reset _last_drop_time = current_time
//      (prevents accumulated gravity from firing all at once)
//   3. Resume normal loop
```

**Critical detail:** When unpausing, `_last_drop_time` MUST be reset to `_get_time_ms()`. Otherwise, if the player pauses for 10 seconds, `elapsed = current - last_drop` would be 10000ms, causing the piece to instantly drop many rows.

### Pattern 5: Statistics Tracking in Existing Functions

**What:** Increment statistics counters at the points where relevant events occur, rather than tracking them separately.
**When to use:** In `_lock_piece` (board.s) and `_clear_lines` (board.s).

```asm
// In _lock_piece, after locking the piece into the board:
//   _stats_total_pieces += 1
//   _stats_piece_count[piece_type] += 1  (array of 7 .words)
//
// In _clear_lines, when lines are counted:
//   switch(lines_cleared):
//     1: _stats_singles += 1
//     2: _stats_doubles += 1
//     3: _stats_triples += 1
//     4: _stats_tetris += 1
```

### Pattern 6: Next Piece Preview from 7-Bag

**What:** The next piece(s) are already stored in the `_bag` array. Read them without consuming them.
**When to use:** Rendering the next piece preview panel.

```asm
// To get the next N piece types without consuming them:
//   for i in 0..(N-1):
//     idx = _bag_index + i
//     if idx >= 7:
//       // The next bag hasn't been shuffled yet.
//       // For simplicity, show only pieces within current bag.
//       // OR: maintain a second "preview bag" that's pre-shuffled.
//       break
//     next_type[i] = _bag[idx]
```

**Complication:** When `_bag_index` is close to 7 (e.g., index 6), only 1 piece remains in the current bag. If showing more than 1 preview piece, a second pre-shuffled bag is needed. The C++ reference populates `nextPieces` independently from the bag.

**Recommended approach for assembly:** Keep a separate `_next_queue` array (7 bytes) that is maintained alongside the bag. When `_next_piece` is called, shift the queue left and append a new random piece. This decouples preview from bag implementation. Alternatively, maintain a lookahead by pre-filling a second bag when the current one runs low.

**Simplest approach (1 next piece):** Just read `_bag[_bag_index]` without incrementing. This always shows the next piece that `_next_piece` will return. For 1-piece preview, no additional data structure is needed.

### Anti-Patterns to Avoid

- **Modifying game state in ghost computation:** `_compute_ghost_y` must be a pure query. Do NOT modify `_piece_y` to compute the ghost -- use local registers only. The existing `_hard_drop` function modifies state; the ghost function must not.
- **Forgetting to reset gravity timer on unpause:** If the player pauses for 30 seconds and the gravity delay is 500ms, unpausing without resetting the timer causes 60 gravity ticks to fire instantly, teleporting the piece to the bottom.
- **Drawing ghost piece after active piece:** Ghost should render first (dimmed), then active piece on top (bright). Drawing ghost after active would overwrite the active piece with dimmed colors at overlap positions.
- **Allowing hold during pause:** Hold input should be ignored when paused, same as movement/rotation. Only unpause and quit should work during pause.
- **Not resetting `_can_hold` on lock:** The hold flag must reset to `true` (1) when a piece locks. Forgetting this makes hold a one-time-use feature.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Ghost piece landing position | Custom collision check loop | Reuse `_is_piece_valid` in a `while(valid) y++` loop | `_is_piece_valid` already handles all edge cases (board bounds, cell occupancy, above-board cells). Duplicating this logic risks inconsistency. |
| Dimmed rendering for ghost | Custom terminal escape codes | `A_DIM` attribute (0x100000) via `wattr_on` | ncurses handles terminal-specific dim/half-bright implementation. A_DIM is portable across terminal types. |
| Binary size measurement | Custom measurement script | `wc -c`, `size`, `strip` commands | Standard macOS tools that report file size, segment sizes, and stripped sizes reliably. |
| Statistics counters | Complex tracking system | Simple `.word` counters in `data.s`, incremented at event points | Each counter is a single `ldr + add + str` sequence (3 instructions). No data structures needed. |

**Key insight:** Every Phase 3 feature is an incremental addition to existing infrastructure. Ghost piece reuses collision detection. Hold reuses spawn. Statistics reuses lock/clear events. Pause reuses the timer. No new fundamental algorithms are needed.

## Common Pitfalls

### Pitfall 1: Ghost Piece Modifying Game State

**What goes wrong:** The ghost computation accidentally writes to `_piece_y`, causing the active piece to teleport to the floor.
**Why it happens:** Copying the `_hard_drop` pattern which modifies `_piece_y` after the drop loop.
**How to avoid:** `_compute_ghost_y` must use only callee-saved registers (x19-x22) for the computation loop. It reads `_piece_y` once into a register and increments the register, never writing back to `_piece_y`.
**Warning signs:** Active piece instantly drops to bottom on next frame; piece locks immediately after ghost computation.

### Pitfall 2: Gravity Burst After Unpause

**What goes wrong:** After unpausing, the piece drops multiple rows instantly (or locks immediately).
**Why it happens:** `_last_drop_time` was set 30 seconds ago. `elapsed = now - last_drop` is massive, triggering many gravity ticks at once.
**How to avoid:** On unpause, always call `_get_time_ms` and store result in `_last_drop_time` BEFORE resuming the game loop. This resets the gravity clock.
**Warning signs:** Piece teleports to floor or locks instantly when unpausing, regardless of current level speed.

### Pitfall 3: Next Piece Preview Desync from Bag

**What goes wrong:** The preview shows a piece different from what actually spawns.
**Why it happens:** The preview reads from the bag at a different index than `_next_piece` consumes, or the bag refills between preview and consumption.
**How to avoid:** For 1-piece preview: read `_bag[_bag_index]` (same index that `_next_piece` will consume). For multi-piece preview: either maintain a separate preview queue, or ensure the read window accounts for bag boundaries.
**Warning signs:** Player sees "I" in preview but gets "T" when the piece spawns.

### Pitfall 4: Hold Piece Not Resetting Rotation

**What goes wrong:** After holding, the swapped-in piece appears in a rotated state instead of spawn orientation.
**Why it happens:** The hold stores only the piece type but the swap doesn't reset `_piece_rotation` to 0.
**How to avoid:** When swapping from hold, always set `_piece_rotation = 0` and recompute spawn position from the type's spawn tables. This matches the C++ reference behavior.
**Warning signs:** Held piece reappears rotated; collision occurs at spawn because rotated piece overlaps differently.

### Pitfall 5: Statistics Counter Overflow

**What goes wrong:** After many games or very long games, piece counters wrap around.
**Why it happens:** Using `.byte` or `.hword` for counters that can exceed 255 or 65535.
**How to avoid:** Use `.word` (32-bit) for all statistics counters. Even at 60 pieces per minute for 24 hours = 86,400 pieces, well within `.word` range (max 4,294,967,295).
**Warning signs:** Piece count displays 0 after reaching 256.

### Pitfall 6: Screen Layout Overflow

**What goes wrong:** Panels overlap each other or extend beyond terminal width, causing rendering artifacts.
**Why it happens:** Adding multiple panels (next, hold, stats) without accounting for total width. The board needs 22 columns (border + 20 chars + border). Panels need ~12-14 more columns each.
**How to avoid:** Calculate the minimum terminal width needed. Board = 22 cols. Gap = 1 col. Right panel area starts at col 23. Standard terminal is 80 columns, leaving 57 columns for panels -- plenty. Layout all panels with explicit column constants defined in one place for easy adjustment.
**Warning signs:** Text overlapping other text; borders drawing on top of board content; truncated numbers.

## Code Examples

Verified patterns from existing codebase analysis and target system testing.

### Ghost Piece Y Computation

```asm
// _compute_ghost_y() -> w0 = ghost landing y
// Pure query: does NOT modify game state
// Reuses _is_piece_valid for collision checking
// Identical to _hard_drop loop but without state modification

.globl _compute_ghost_y
.p2align 2
_compute_ghost_y:
    stp     x29, x30, [sp, #-48]!
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    mov     x29, sp

    // Load current piece state into callee-saved registers
    adrp    x8, _piece_type@PAGE
    ldrb    w19, [x8, _piece_type@PAGEOFF]
    adrp    x8, _piece_rotation@PAGE
    ldrb    w20, [x8, _piece_rotation@PAGEOFF]
    adrp    x8, _piece_x@PAGE
    ldrsh   w21, [x8, _piece_x@PAGEOFF]
    adrp    x8, _piece_y@PAGE
    ldrsh   w22, [x8, _piece_y@PAGEOFF]

    // Drop loop: try y+1 until invalid
Lghost_drop_loop:
    add     w3, w22, #1
    mov     w0, w19
    mov     w1, w20
    mov     w2, w21
    bl      _is_piece_valid
    cbz     w0, Lghost_drop_done
    add     w22, w22, #1
    b       Lghost_drop_loop

Lghost_drop_done:
    mov     w0, w22                 // return last valid y

    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
```

### Drawing Ghost Piece with A_DIM

```asm
// Fragment: draw a ghost cell at screen (row, col) with dimmed color
// w25 = color pair number, w10 = screen_y, w11 = screen_x
// x19 = stdscr GOT pointer

    // Compute attribute: COLOR_PAIR(n) | A_DIM
    lsl     w1, w25, #8             // COLOR_PAIR(n) = n << 8
    orr     w1, w1, #0x100000       // | A_DIM (0x100000)

    // wattr_on(stdscr, attr, NULL)
    ldr     x0, [x19]
    mov     x2, #0
    bl      _wattr_on

    // wmove + waddch "[]"
    ldr     x0, [x19]
    mov     w1, w10
    mov     w2, w11
    bl      _wmove
    ldr     x0, [x19]
    mov     w1, #0x5B               // '['
    bl      _waddch
    ldr     x0, [x19]
    mov     w1, #0x5D               // ']'
    bl      _waddch

    // wattr_off(stdscr, attr, NULL)
    ldr     x0, [x19]
    lsl     w1, w25, #8
    orr     w1, w1, #0x100000
    mov     x2, #0
    bl      _wattr_off
```

### Hold Piece State Variables

```asm
// New variables in data.s (__DATA,__data section)

.globl _hold_piece_type
_hold_piece_type:
    .byte 0xFF                  // 0-6 = held piece type, 0xFF = empty (no piece held)

.globl _can_hold
_can_hold:
    .byte 1                     // 1 = can hold, 0 = already held this turn
```

### Statistics Counters in data.s

```asm
// New statistics variables in data.s (__DATA,__data section)

.globl _stats_pieces
.p2align 2
_stats_pieces:
    .word 0                     // total pieces locked

.globl _stats_piece_counts
_stats_piece_counts:
    .word 0                     // O count (type 0)
    .word 0                     // I count (type 1)
    .word 0                     // L count (type 2)
    .word 0                     // J count (type 3)
    .word 0                     // S count (type 4)
    .word 0                     // Z count (type 5)
    .word 0                     // T count (type 6)

.globl _stats_singles
_stats_singles:     .word 0
.globl _stats_doubles
_stats_doubles:     .word 0
.globl _stats_triples
_stats_triples:     .word 0
.globl _stats_tetris
_stats_tetris:      .word 0
```

### Incrementing Statistics in _lock_piece

```asm
// In _lock_piece (board.s), after locking piece into board:

    // Increment total pieces counter
    adrp    x8, _stats_pieces@PAGE
    add     x8, x8, _stats_pieces@PAGEOFF
    ldr     w9, [x8]
    add     w9, w9, #1
    str     w9, [x8]

    // Increment per-piece-type counter: _stats_piece_counts[piece_type]
    adrp    x8, _stats_piece_counts@PAGE
    add     x8, x8, _stats_piece_counts@PAGEOFF
    uxtw    x9, w19                 // w19 = piece_type (0-6)
    ldr     w10, [x8, x9, lsl #2]  // load count (each is .word = 4 bytes)
    add     w10, w10, #1
    str     w10, [x8, x9, lsl #2]  // store incremented count
```

### Incrementing Line Clear Statistics in _clear_lines

```asm
// In _clear_lines (board.s), after all clearing is done:
// w21 = lines_cleared_count (1-4)

    // Increment appropriate line clear stat based on count
    cmp     w21, #1
    b.ne    Lstats_not_single
    adrp    x8, _stats_singles@PAGE
    add     x8, x8, _stats_singles@PAGEOFF
    ldr     w9, [x8]
    add     w9, w9, #1
    str     w9, [x8]
    b       Lstats_done

Lstats_not_single:
    cmp     w21, #2
    b.ne    Lstats_not_double
    adrp    x8, _stats_doubles@PAGE
    add     x8, x8, _stats_doubles@PAGEOFF
    ldr     w9, [x8]
    add     w9, w9, #1
    str     w9, [x8]
    b       Lstats_done

Lstats_not_double:
    cmp     w21, #3
    b.ne    Lstats_not_triple
    adrp    x8, _stats_triples@PAGE
    add     x8, x8, _stats_triples@PAGEOFF
    ldr     w9, [x8]
    add     w9, w9, #1
    str     w9, [x8]
    b       Lstats_done

Lstats_not_triple:
    // Must be 4 (tetris)
    adrp    x8, _stats_tetris@PAGE
    add     x8, x8, _stats_tetris@PAGEOFF
    ldr     w9, [x8]
    add     w9, w9, #1
    str     w9, [x8]

Lstats_done:
```

### Pause Toggle in Input Handler

```asm
// In _handle_input (input.s), add check for 'p' key:

Lcheck_p:
    cmp     w19, #112               // 'p' = 0x70 = 112
    b.ne    Lcheck_next_key

    // Toggle pause
    adrp    x8, _is_paused@PAGE
    add     x8, x8, _is_paused@PAGEOFF
    ldrb    w9, [x8]
    eor     w9, w9, #1              // toggle: 0->1, 1->0
    strb    w9, [x8]

    // If unpausing (new value is 0), reset gravity timer
    cbnz    w9, Lhandle_done        // if now paused, done
    // Unpause: reset last_drop_time to now
    bl      _get_time_ms
    adrp    x8, _last_drop_time@PAGE
    str     x0, [x8, _last_drop_time@PAGEOFF]
    b       Lhandle_done
```

### Drawing a Mini Piece in a Panel (Next/Hold Preview)

```asm
// _draw_mini_piece(w0=piece_type, w1=panel_start_row, w2=panel_start_col)
// Draws a piece's 5x5 grid at the specified panel position
// Uses the piece's color pair for coloring
// Used for both next piece preview and hold piece display
//
// Algorithm:
//   for r in 0..4:
//     for c in 0..4:
//       cell = _piece_data[type*100 + 0*25 + r*5 + c]  // rotation 0 always
//       if cell != 0:
//         screen_y = panel_start_row + r
//         screen_x = panel_start_col + c*2
//         draw colored "[]" at (screen_y, screen_x)
```

### Binary Size Measurement Commands

```bash
# Record binary sizes for comparison
echo "=== Assembly Binary (Phase 3) ==="
wc -c asm/bin/yetris-asm
size asm/bin/yetris-asm
strip -o /tmp/yetris-asm-stripped asm/bin/yetris-asm
wc -c /tmp/yetris-asm-stripped

echo "=== C++ Binary ==="
wc -c bin/yetris
size bin/yetris
strip -o /tmp/yetris-cpp-stripped bin/yetris
wc -c /tmp/yetris-cpp-stripped

echo "=== Segment Analysis (Assembly) ==="
otool -l asm/bin/yetris-asm | grep -A5 "segname __TEXT"
otool -l asm/bin/yetris-asm | grep -A5 "segname __DATA"
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Using `wattron(win, attr)` macro | `wattr_on(win, attr, NULL)` 3-arg function | ncurses 6.0+ | From assembly, must call `_wattr_on` with 3 args. A_DIM goes in the attr parameter. |
| Separate ghost piece rendering pass | Render ghost inline during board draw | Assembly optimization | Drawing ghost during `_draw_board` would mean checking every cell twice. Simpler to draw ghost as a separate pass after board, before active piece. |

**Deprecated/outdated:**
- None specific to Phase 3 features. All ncurses APIs used are stable and unchanged.

## Open Questions

1. **Multi-piece next preview bag boundary**
   - What we know: `_bag[_bag_index]` reliably gives the next 1 piece. For N>1 preview, pieces spanning a bag boundary require a second pre-shuffled bag.
   - What's unclear: Whether implementing a double-bag system is worth the complexity for Phase 3.
   - Recommendation: Start with 1-piece preview (MECH-09 says "1-7 configurable" -- 1 satisfies the requirement). If time permits, extend to 3+ by maintaining a circular queue of pre-fetched piece types.

2. **Ghost piece visibility on terminals without A_DIM support**
   - What we know: A_DIM (0x100000) is defined in macOS ncurses and works in Terminal.app and iTerm2. Some terminals may not render dim differently from normal.
   - What's unclear: Whether there is a fallback visual treatment needed.
   - Recommendation: Use A_DIM as primary approach. If testing reveals it is indistinguishable, consider using a different character pair (e.g., ".." instead of "[]") or A_REVERSE as fallback. This is a visual polish issue, not a blocking one.

3. **Statistics panel and hold panel screen real estate**
   - What we know: The board uses columns 0-21. Standard terminal is 80 columns. That leaves 58 columns for panels. Score panel currently at column 24.
   - What's unclear: The optimal column layout to fit score, next piece, hold piece, and statistics without crowding.
   - Recommendation: Design the layout during implementation. Start with next piece and score in one column (24-33), statistics in the next column (35-50). Hold piece can go below the next piece or in a separate position. The C++ reference places hold on the LEFT of the board, but placing it on the right is fine for the assembly version.

4. **Pause overlay: obscure board or freeze display?**
   - What we know: The C++ reference shows a pause menu overlay (resume/quit options). The success criteria says "board obscured or frozen."
   - What's unclear: Whether a simple "PAUSED" text overlay on the board suffices, or a menu is needed.
   - Recommendation: Simple "PAUSED" text centered on the board (similar to existing "GAME OVER" overlay). A pause menu with options belongs in Phase 4 (Menus). For Phase 3, just toggle pause state with 'p' and display the overlay.

## Binary Size Baseline (Current State)

| Metric | Assembly (Phase 2) | C++ | Ratio |
|--------|-------------------|-----|-------|
| File size (unstripped) | 52,856 bytes | 1,036,152 bytes | **19.6x smaller** |
| File size (stripped) | 51,632 bytes | 546,448 bytes | **10.6x smaller** |
| __TEXT segment | 16,384 bytes | 393,216 bytes | 24.0x smaller |
| Actual code (__text section) | ~4,556 bytes | N/A | -- |
| __DATA segment | 16,384 bytes | 16,384 bytes | Same (page-aligned minimum) |
| Source lines | 2,790 lines (8 .s files) | ~6,500 lines (20+ .cpp/.hpp) | -- |

**Note:** Both binaries are page-aligned (16KB pages on ARM64), so the minimum segment size is 16,384 bytes even for small code. The actual code content in the assembly __TEXT segment is approximately 4,556 bytes (the `__text` section is 0x11CC = 4,556 bytes). After Phase 3 adds ~800-1200 lines of new assembly code, the __TEXT segment will likely remain at 16,384 bytes (one page) unless code exceeds the page boundary.

## Sources

### Primary (HIGH confidence)

- **C++ reference source code analysis** (`src/Game/`): Analyzed PieceGhost.cpp (ghost algorithm), Game.cpp (hold mechanic, pause, statistics tracking), Statistics.hpp (counter fields), LayoutGame.cpp (panel layout and rendering), Profile.hpp/cpp (ghost theme, hold settings). All algorithms extracted directly from working code.
- **Target system ncurses verification**: A_DIM = 0x100000, A_BOLD = 0x200000, A_REVERSE = 0x40000, COLOR_PAIR(n) = n << 8. All verified via compiled test program on target macOS system.
- **Existing assembly codebase analysis**: All 8 .s files (2,790 total lines) read in full. `_is_piece_valid` and `_hard_drop` patterns verified as reusable for ghost computation. `_lock_piece` and `_clear_lines` identified as statistics increment points. `_handle_input` key dispatch chain pattern verified for adding new keys.
- **Binary size measurements**: `wc -c`, `size`, `strip`, `otool -l` run on actual compiled binaries. Assembly = 52,856 bytes, C++ = 1,036,152 bytes (both unstripped, current builds).

### Secondary (MEDIUM confidence)

- Phase 2 Research findings on ncurses rendering patterns, callee-saved register usage, and multi-file assembly architecture. All previously verified and now in production.

### Tertiary (LOW confidence)

- None. All findings verified against source code, compiler output, or target system testing.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Same tools as Phase 2, no new external dependencies. A_DIM verified on target.
- Architecture: HIGH - All patterns are incremental additions to verified Phase 2 codebase. Ghost reuses `_is_piece_valid`. Hold/pause are simple state variables.
- Pitfalls: HIGH - Each pitfall derived from analysis of the existing codebase and C++ reference behavior.
- Binary measurement: HIGH - Measured on actual binaries from current build.

**Research date:** 2026-02-26
**Valid until:** Indefinite for game feature patterns and ncurses API. Binary size measurements valid only for current Phase 2 codebase; will be updated after Phase 3 implementation.
