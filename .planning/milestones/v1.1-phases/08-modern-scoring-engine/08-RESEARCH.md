# Phase 8: Modern Scoring Engine - Research

**Researched:** 2026-02-27
**Domain:** ARM64 assembly Tetris scoring -- modern guideline scoring with combos, T-spins, back-to-back, perfect clear, and drop points
**Confidence:** HIGH

## Summary

Phase 8 replaces the existing flat scoring system with the full modern Tetris guideline scoring engine. The current codebase already has a `_score_table` (100/300/500/800) and `_clear_lines` that adds flat points. The task is to: (1) multiply line clear scores by level, (2) add combo tracking and scoring, (3) implement T-spin detection using the 3-corner rule, (4) add T-spin-specific scoring values, (5) track back-to-back "difficult" clears with a 1.5x bonus multiplier, (6) detect perfect clears (empty board after line clear) with bonus scoring, and (7) add per-cell scoring for soft and hard drops.

The implementation is almost entirely in `board.s` (where `_clear_lines` and `_lock_piece` live) and `piece.s` (where `_soft_drop`, `_hard_drop`, and `_try_rotate` live), plus new state variables in `data.s`. No new .s files are needed. The T-piece pivot is always at grid position (2,2) in `_piece_data`, which makes the diagonal corner check straightforward: map the 4 corners (-1,-1), (-1,+1), (+1,-1), (+1,+1) relative to the pivot to board coordinates and count occupied cells.

**Primary recommendation:** Split into two plans: (1) line-clear scoring (level multiply + combo + back-to-back + perfect clear) which modifies `_clear_lines` and `_lock_piece` in `board.s`, and (2) T-spin detection + T-spin scoring + drop scoring which modifies `_try_rotate` in `piece.s`, `_soft_drop`/`_hard_drop` in `piece.s`, and the scoring path in `board.s`.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SCORE-01 | Line clear scores multiplied by level (Single=100*lvl, Double=300*lvl, Triple=500*lvl, Tetris=800*lvl) | Existing `_score_table` already has base values {100,300,500,800}. Add one `mul` instruction: `score_table[lines-1] * level`. Current `_clear_lines` loads from `_score_table` and adds to `_score` -- change to multiply by `_level` first. |
| SCORE-02 | Combo system -- 50 * combo_count * level for consecutive line-clearing locks; resets on non-clearing lock | New `_combo_count` byte in `data.s`. In `_lock_piece`: after `_clear_lines` returns, if lines > 0 then increment combo and add `50 * combo * level`; if lines == 0 then reset combo to 0. ~20 instructions. |
| SCORE-03 | Back-to-back bonus -- 1.5x multiplier for consecutive difficult clears (Tetris or T-spin) | New `_b2b_active` byte in `data.s`. After computing line clear score, check if current clear is "difficult" (4 lines OR T-spin with lines > 0). If b2b_active AND current is difficult, add 50% extra (`score >> 1`). Update b2b flag. ~25 instructions. |
| SCORE-04 | T-spin detection using 3-corner rule (after T rotation, 3+ of 4 diagonal corners occupied) | New `_last_was_rotation` byte set in `_try_rotate`, cleared in `_try_move`/`_hard_drop`/`_soft_drop`. At lock time: if piece_type == 6 (T) AND last_was_rotation == 1, check 4 diagonal corners of pivot (board coords: pivot_y +/- 1, pivot_x +/- 1). Count occupied >= 3 means T-spin. ~40 instructions for detection. Pivot always at grid(2,2) in `_piece_data`. |
| SCORE-05 | T-spin scoring values (T-spin zero=400*lvl, Single=800*lvl, Double=1200*lvl, Triple=1600*lvl) | New `_tspin_score_table` in data.s: {400, 800, 1200, 1600}. When T-spin detected and lines cleared, use T-spin table instead of normal `_score_table`. When T-spin with 0 lines, still award 400*lvl. |
| SCORE-06 | Perfect clear detection (board completely empty after line clear) with bonus scoring | After clearing lines in `_clear_lines`, scan all 200 board bytes. NEON approach: 13 x `ld1` (16 bytes each, covering 208 bytes with 8 padding), `orr` all vectors, `umaxv` -- if result == 0, board is empty. New `_perfect_clear_table`: {800, 1200, 1800, 2000, 3200} (indexed by lines-1, with b2b tetris at index 4). ~30 instructions for scan + bonus. |
| SCORE-07 | Soft drop scoring -- 1 point per cell dropped | In `_soft_drop` (piece.s): after successful `_try_move(0,1)`, add 1 to `_score`. In gravity drop (main.s `_soft_drop` call): do NOT award soft drop points for gravity -- only for player-initiated down key. Requires distinguishing user soft drop from gravity. |
| SCORE-08 | Hard drop scoring -- 2 points per cell dropped | In `_hard_drop` (piece.s): record starting `_piece_y` before drop loop. After loop, compute `final_y - start_y`. Count visible cells at each row (from piece grid data). Simpler approach: just count rows dropped * 2 for each cell in the piece = `(final_y - start_y) * 2`. Award points before locking. ~15 instructions. |
</phase_requirements>

## Standard Stack

### Core

This phase uses no external libraries beyond what is already linked. All implementation is in AArch64 assembly.

| Component | Location | Purpose | Notes |
|-----------|----------|---------|-------|
| board.s | `asm/board.s` | `_clear_lines`, `_lock_piece` -- scoring logic lives here | Primary modification target for line clear scoring, combo, b2b, perfect clear |
| piece.s | `asm/piece.s` | `_try_rotate`, `_soft_drop`, `_hard_drop` -- rotation flag and drop scoring | Set/clear rotation flag, add drop points |
| data.s | `asm/data.s` | All game state variables and score tables | Add new state bytes and score tables |
| input.s | `asm/input.s` | `_handle_input` -- dispatches soft drop key | Must distinguish user soft drop from gravity |

### Supporting

| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| NEON SIMD | ARMv8-A | Vectorized board-empty scan | Perfect clear detection (200 bytes in ~13 loads) |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| NEON board scan for perfect clear | Scalar byte-by-byte loop | NEON is 13 loads vs 200 iterations; but perfect clear is rare, so performance difference is negligible. NEON is already used in `_clear_lines` row detection, so the pattern is established. Use NEON for consistency. |
| Integer multiplication for 1.5x | Shift-and-add (`x + x >> 1`) | Shift-and-add avoids `mul` instruction. Use `add w_bonus, w_score, w_score, lsr #1` for the 1.5x multiplier -- single instruction. |
| T-spin Mini detection | Skip mini, treat all as full T-spin | REQUIREMENTS.md out-of-scope section lists T-spin Mini as out of scope for v1.1. Implement full 3-corner T-spin only. |

## Architecture Patterns

### Current Scoring Flow (What Exists)

```
_handle_input
  -> KEY_DOWN: _soft_drop() -> _try_move(0,1) or _lock_piece + _spawn_piece
  -> SPACE:    _hard_drop() -> loop _is_piece_valid, _lock_piece + _spawn_piece

_lock_piece:
  1. Write piece cells to board array
  2. Add 10 to _score (lock bonus)
  3. Increment _stats_pieces and _stats_piece_counts[type]
  4. Reset _can_hold = 1
  5. Call _clear_lines
  6. Return lines cleared

_clear_lines:
  1. Scan rows bottom-to-top for full rows (NEON uminv)
  2. Shift rows down, fill top with zeros
  3. If lines cleared: add _score_table[lines-1] to _score (FLAT, no level multiply)
  4. Update _lines_cleared total
  5. Recompute _level from _level_thresholds table
  6. Update line-type stats (_stats_singles/doubles/triples/tetris)
  7. Return lines_cleared count
```

### New Scoring Flow (Target State)

```
_try_rotate:
  [EXISTING rotation logic]
  -> On success: set _last_was_rotation = 1

_try_move:
  [EXISTING move logic]
  -> On success: set _last_was_rotation = 0

_soft_drop (user-initiated only):
  -> On successful down move: add 1 to _score
  [Gravity-initiated soft_drop does NOT award points]

_hard_drop:
  -> Record start_y before drop loop
  -> After loop: add (final_y - start_y) * 2 to _score
  -> Clear _last_was_rotation = 0
  -> Call _lock_piece

_lock_piece:
  1. Write piece cells to board array
  2. [REMOVED: flat +10 lock bonus -- not in modern guideline]
  3. Detect T-spin: if piece_type==6 AND _last_was_rotation==1, check 3 corners
  4. Call _clear_lines -> returns lines_cleared
  5. Compute score based on clear type:
     - T-spin with lines: _tspin_score_table[lines-1] * level
     - T-spin no lines: 400 * level
     - Normal lines: _score_table[lines-1] * level
  6. Apply combo: if lines > 0, combo++, add 50 * combo * level
  7. Apply back-to-back: if difficult clear AND _b2b_active, add score * 0.5
  8. Update _b2b_active flag
  9. If lines == 0: reset _combo_count = 0
  10. Check perfect clear: scan board, if empty add perfect_clear bonus
  11. Stats, _can_hold reset (existing)

_clear_lines:
  [SIMPLIFIED: no longer does scoring -- just detects and removes full rows]
  1. Scan/clear full rows (existing NEON detection + shift logic)
  2. Update _lines_cleared total
  3. Recompute _level
  4. Update line-type stats
  5. Return lines_cleared count
  [Score computation moved to _lock_piece for access to T-spin/combo/b2b state]
```

### Pattern 1: T-Spin Corner Detection

**What:** Check 4 diagonal corners of T-piece pivot after rotation
**When to use:** At lock time, when piece_type == 6 (T) and _last_was_rotation == 1

The T-piece pivot is always at grid position (2,2) within the 5x5 piece grid. In board coordinates:
- `pivot_board_x = piece_x + 2`
- `pivot_board_y = piece_y + 2`

The 4 diagonal corners in board coordinates:
- `(pivot_board_y - 1, pivot_board_x - 1)` -- top-left
- `(pivot_board_y - 1, pivot_board_x + 1)` -- top-right
- `(pivot_board_y + 1, pivot_board_x - 1)` -- bottom-left
- `(pivot_board_y + 1, pivot_board_x + 1)` -- bottom-right

A corner is "occupied" if:
- It is outside the board bounds (walls/floor count as occupied), OR
- `board[y * 10 + x] != 0`

Count occupied corners >= 3 means T-spin.

```asm
// T-spin detection pseudocode
// Precondition: piece_type == 6, _last_was_rotation == 1
// x19 = piece_x, x20 = piece_y (from _lock_piece callee-saved)

add     w8, w19, #2          // pivot_x = piece_x + 2
add     w9, w20, #2          // pivot_y = piece_y + 2

mov     w10, #0              // occupied_count = 0

// Corner 1: (pivot_y-1, pivot_x-1)
sub     w11, w9, #1          // cy = pivot_y - 1
sub     w12, w8, #1          // cx = pivot_x - 1
// Check bounds: if cx < 0 || cx >= 10 || cy < 0 || cy >= 20 -> occupied
// Else: check board[cy * 10 + cx] != 0
// If occupied: add w10, w10, #1

// Repeat for 3 more corners...
// Compare: cmp w10, #3; b.ge -> is_tspin
```

### Pattern 2: Score Accumulation in _lock_piece

**What:** Centralize all scoring computation in `_lock_piece` instead of `_clear_lines`
**When to use:** Always -- this restructuring gives `_lock_piece` access to T-spin state, combo state, and b2b state that `_clear_lines` cannot see.

The key insight: `_clear_lines` currently both clears lines AND computes score. Moving score computation to `_lock_piece` (which already calls `_clear_lines`) allows scoring to use T-spin detection results, combo counter, and b2b flag that are all determined at lock time.

`_clear_lines` is stripped down to: detect full rows, remove them, update `_lines_cleared` and `_level`, update stats, return count. Score addition is removed from `_clear_lines`.

### Pattern 3: Distinguishing User Soft Drop from Gravity

**What:** Only award soft drop points (1 per cell) for player-initiated drops, not gravity
**When to use:** SCORE-07 requires this distinction

Two approaches:
1. **Separate function:** Create `_user_soft_drop` that awards points then calls `_soft_drop`. Input handler calls `_user_soft_drop`, gravity timer calls `_soft_drop`.
2. **Flag parameter:** Pass a flag to `_soft_drop` indicating user vs gravity.

Recommended: **Approach 1** (separate function). Cleaner than modifying `_soft_drop`'s signature. `_user_soft_drop` adds 1 to score if the move succeeds, then calls existing `_soft_drop`. The gravity path in `main.s` continues calling `_soft_drop` directly.

Wait -- `_soft_drop` calls `_try_move(0,1)` and if blocked calls `_lock_piece`. For user soft drop scoring, points are only awarded when the piece actually moves down (not when it locks). So:

```
_user_soft_drop:
  1. Call _try_move(0, 1)
  2. If moved (w0 == 1): add 1 to _score, return 1
  3. If blocked (w0 == 0): call _lock_piece, call _spawn_piece, return 0
```

This duplicates `_soft_drop` logic but with the scoring addition. Alternative: keep `_soft_drop` as-is, and in the input handler for KEY_DOWN, just check if _try_move(0,1) succeeded first, add 1 point, then proceed. Actually simplest: inline the soft drop in the input handler. But that changes the existing pattern. Best: create a new `_user_soft_drop` wrapper.

### Anti-Patterns to Avoid

- **Scoring in _clear_lines:** Don't keep score computation inside `_clear_lines`. It lacks access to T-spin state, combo, and b2b. Move scoring up to `_lock_piece`.
- **Modifying _soft_drop signature:** Adding a parameter changes the ABI for all callers. Use a separate wrapper function instead.
- **Forgetting to clear _last_was_rotation:** The flag MUST be cleared on any non-rotation move (left, right, down, hard drop). Otherwise a prior rotation could incorrectly trigger T-spin detection.
- **Integer overflow in score multiplication:** `score_table[3] * level * 1.5` max = 800 * 22 * 1.5 = 26,400. Adding perfect clear of 3,200 * 22 = 70,400. Total worst case per lock < 100,000. `_score` is `uint32`, max 4.29 billion. No overflow risk.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| 1.5x multiplier | General-purpose fixed-point multiply | `add w_result, w_score, w_score, lsr #1` | Single ARM64 instruction computes `x + x/2 = 1.5x`. No need for a multiply routine. |
| Board-empty scan | Scalar loop over 200 bytes | NEON `ld1` + `orr` + `umaxv` pattern | Already established in `_clear_lines` for row scanning. Extend to full board: load 13 x 16-byte vectors, OR them all, check max == 0. |
| Score table lookup | If/else chain for line clear values | `ldr w_score, [x_table, w_index, uxtw #2]` | Existing pattern from `_score_table`. Add new tables for T-spin and perfect clear with same indexed access. |

**Key insight:** The existing codebase already has every assembly pattern needed (table lookups, NEON vectorized scans, flag tracking, conditional scoring). This phase is "wiring" rather than "inventing."

## Common Pitfalls

### Pitfall 1: Lock Bonus Conflict with Modern Scoring
**What goes wrong:** The current `_lock_piece` adds a flat +10 to score on every lock. Modern Tetris guideline does NOT include a lock bonus -- points come only from line clears, combos, T-spins, and drops.
**Why it happens:** The C++ original adds `+10` per lock (`Game::lockCurrentPiece()` line: `score.points += 10`). This is a non-standard feature of the original.
**How to avoid:** Remove the +10 lock bonus from `_lock_piece` to match modern guideline. Document this as a deliberate deviation from the C++ original.
**Warning signs:** Scores slightly inflated compared to expected guideline values.

### Pitfall 2: _last_was_rotation Not Cleared Properly
**What goes wrong:** T-spin detection triggers falsely because `_last_was_rotation` was set by a rotation but not cleared by a subsequent move.
**Why it happens:** The flag must be cleared in `_try_move`, `_hard_drop`, and gravity drop. Missing any clear path causes phantom T-spins.
**How to avoid:** Clear the flag at the START of `_try_move` (before checking validity) and at the START of `_hard_drop`. This covers all non-rotation movement paths including left/right/down/gravity/harddrop.
**Warning signs:** T-spins detected when the last action was not a rotation.

### Pitfall 3: Combo Count Off-By-One
**What goes wrong:** Combo counter is 0 on the first consecutive clear, so `50 * 0 * level = 0` -- no combo bonus on first consecutive clear.
**Why it happens:** The guideline says combo starts at 0 and increments BEFORE awarding bonus, OR starts at -1 and increments BEFORE use. Different implementations differ.
**How to avoid:** Use the convention where combo starts at -1 (or equivalently 0 but treated as 0-indexed). On first clear: combo goes from -1 to 0, bonus = 50 * 0 * level = 0 (no bonus). On second consecutive clear: combo = 1, bonus = 50 * 1 * level. This matches the standard guideline where the first clear in a chain has no combo bonus.
**Warning signs:** Compare: first clear = 100*level only. Second consecutive clear = 100*level + 50*1*level. If the first clear also gets combo bonus, the counter initialization is wrong.

### Pitfall 4: Back-to-Back Applies to Score Before Addition
**What goes wrong:** The 1.5x B2B bonus is applied to the line clear score, but the implementation adds the bonus after adding the base score, resulting in double-counting.
**Why it happens:** The bonus should be computed as `base_score * 0.5` (the extra 50%), not `total_accumulated_score * 1.5`.
**How to avoid:** Compute line clear score first, then if B2B applies, add `line_score >> 1` as the bonus. Do NOT multiply the accumulated `_score` by 1.5.
**Warning signs:** Scores jump wildly during B2B chains.

### Pitfall 5: Perfect Clear After T-Spin Tetris
**What goes wrong:** A T-spin triple that also results in a perfect clear should receive both T-spin bonus AND perfect clear bonus. Missing stacking of bonuses.
**Why it happens:** Early return after T-spin scoring skips the perfect clear check.
**How to avoid:** Structure scoring as sequential steps that all execute: (1) line clear base score, (2) T-spin override, (3) B2B bonus, (4) combo bonus, (5) perfect clear bonus. Each adds to total independently.

### Pitfall 6: Soft Drop During Gravity
**What goes wrong:** The gravity timer calls `_soft_drop` which is the same function the user's DOWN key calls. If scoring is added to `_soft_drop`, gravity gives free points every tick.
**Why it happens:** `_soft_drop` is shared between user input and gravity.
**How to avoid:** Create `_user_soft_drop` for input handler. Gravity continues calling `_soft_drop`. Only `_user_soft_drop` awards the 1-point bonus.

## Code Examples

### Example 1: Level-Multiplied Score (replacing flat score in _clear_lines)

```asm
// Current code in _clear_lines (to be modified):
//   ldr w10, [x8, w9, uxtw #2]    // load score_table[lines-1]
//   add w11, w11, w10               // _score += flat score
//
// New code (compute score_table[lines-1] * level):
    ldr     w10, [x8, w9, uxtw #2]    // w10 = base score (100/300/500/800)
    adrp    x12, _level@PAGE
    ldr     w12, [x12, _level@PAGEOFF] // w12 = current level
    mul     w10, w10, w12              // w10 = base * level
    // w10 now holds the level-multiplied score
```

### Example 2: Combo Scoring

```asm
// After _clear_lines returns w0 = lines_cleared:
    cbz     w0, Lreset_combo           // no lines cleared -> reset combo

    // Lines were cleared: increment combo
    adrp    x8, _combo_count@PAGE
    add     x8, x8, _combo_count@PAGEOFF
    ldr     w9, [x8]
    add     w9, w9, #1
    str     w9, [x8]                   // _combo_count++

    // Combo bonus = 50 * combo * level
    mov     w10, #50
    mul     w10, w9, w10               // combo * 50
    adrp    x11, _level@PAGE
    ldr     w11, [x11, _level@PAGEOFF]
    mul     w10, w10, w11              // combo * 50 * level

    // Add to score
    adrp    x8, _score@PAGE
    add     x8, x8, _score@PAGEOFF
    ldr     w11, [x8]
    add     w11, w11, w10
    str     w11, [x8]
    b       Lcombo_done

Lreset_combo:
    adrp    x8, _combo_count@PAGE
    str     wzr, [x8, _combo_count@PAGEOFF]  // _combo_count = 0

Lcombo_done:
```

### Example 3: Back-to-Back 1.5x Bonus

```asm
// w10 = line clear score (already level-multiplied)
// w_is_difficult = 1 if this clear is Tetris or T-spin, 0 otherwise

    cbz     w_is_difficult, Lb2b_break  // not difficult -> break chain

    // Check if B2B was active
    adrp    x8, _b2b_active@PAGE
    add     x8, x8, _b2b_active@PAGEOFF
    ldrb    w9, [x8]
    cbz     w9, Lb2b_set_active         // first difficult clear, no bonus yet

    // B2B active: add 50% bonus
    add     w10, w10, w10, lsr #1       // score = score * 1.5
    b       Lb2b_set_active

Lb2b_break:
    // Non-difficult clear: deactivate B2B (but only if lines were cleared)
    // Note: a lock with 0 lines does NOT break B2B chain
    cbz     w_lines, Lb2b_done          // 0 lines: don't touch b2b flag
    adrp    x8, _b2b_active@PAGE
    strb    wzr, [x8, _b2b_active@PAGEOFF]
    b       Lb2b_done

Lb2b_set_active:
    adrp    x8, _b2b_active@PAGE
    mov     w9, #1
    strb    w9, [x8, _b2b_active@PAGEOFF]

Lb2b_done:
```

### Example 4: T-Spin 3-Corner Check

```asm
// Precondition: piece_type == 6 (T), _last_was_rotation == 1
// w19 = piece_x, w20 = piece_y (callee-saved from _lock_piece)

    add     w8, w19, #2               // pivot_x = piece_x + 2
    add     w9, w20, #2               // pivot_y = piece_y + 2
    mov     w10, #0                    // occupied_count = 0

    // Load board base
    adrp    x11, _board@PAGE
    add     x11, x11, _board@PAGEOFF

    // Check corner (pivot_y-1, pivot_x-1)
    sub     w12, w9, #1               // cy
    sub     w13, w8, #1               // cx
    bl      Lcheck_corner              // adds to w10 if occupied

    // Check corner (pivot_y-1, pivot_x+1)
    sub     w12, w9, #1
    add     w13, w8, #1
    bl      Lcheck_corner

    // Check corner (pivot_y+1, pivot_x-1)
    add     w12, w9, #1
    sub     w13, w8, #1
    bl      Lcheck_corner

    // Check corner (pivot_y+1, pivot_x+1)
    add     w12, w9, #1
    add     w13, w8, #1
    bl      Lcheck_corner

    // Result: w10 >= 3 means T-spin
    cmp     w10, #3
    b.ge    Lis_tspin

// Helper: check one corner
Lcheck_corner:
    // w12 = cy, w13 = cx, w10 = count (increment if occupied)
    // Wall/floor counts as occupied
    cmp     w13, #0
    b.lt    Lcorner_occupied
    cmp     w13, #10
    b.ge    Lcorner_occupied
    cmp     w12, #0
    b.lt    Lcorner_occupied
    cmp     w12, #20
    b.ge    Lcorner_occupied
    // In bounds: check board cell
    mov     w14, #10
    mul     w14, w12, w14
    add     w14, w14, w13
    uxtw    x14, w14
    ldrb    w15, [x11, x14]
    cbz     w15, Lcorner_done          // empty -> not occupied
Lcorner_occupied:
    add     w10, w10, #1
Lcorner_done:
    ret
```

### Example 5: Perfect Clear Board Scan (NEON)

```asm
// After clearing lines, check if entire board is empty
    adrp    x8, _board@PAGE
    add     x8, x8, _board@PAGEOFF

    // Load 13 x 16-byte chunks and OR them together
    // Board is 200 bytes. 12 * 16 = 192, plus partial load.
    ld1     {v0.16b}, [x8], #16       // bytes 0-15
    ld1     {v1.16b}, [x8], #16       // bytes 16-31
    orr     v0.16b, v0.16b, v1.16b
    ld1     {v1.16b}, [x8], #16       // bytes 32-47
    orr     v0.16b, v0.16b, v1.16b
    // ... repeat for remaining chunks ...
    ld1     {v1.16b}, [x8], #16       // bytes 176-191
    orr     v0.16b, v0.16b, v1.16b
    // Load final 8 bytes (192-199) -- use ld1 with 8-byte variant
    ld1     {v1.8b}, [x8]
    // Zero-extend v1 to 16 bytes and OR
    uxtl    v1.8h, v1.8b              // widen to halfwords (zeros upper)
    xtn     v2.8b, v1.8h              // narrow back (still 8 bytes, upper 8 are 0)
    orr     v0.16b, v0.16b, v2.16b

    // Check if any byte is non-zero
    umaxv   b1, v0.16b                // max across all 16 bytes
    umov    w9, v1.b[0]
    cbnz    w9, Lnot_perfect_clear    // board not empty

    // Board is empty! Award perfect clear bonus
    // ...
```

Note: The simpler scalar approach (loop 200 bytes, `orr` into accumulator) is also fine since perfect clear is extremely rare. Use NEON only if consistency with existing patterns is preferred.

## Data Section Changes

### New State Variables (data.s)

```asm
// Combo counter (starts at 0, increments on consecutive line-clearing locks)
.globl _combo_count
.p2align 2
_combo_count:       .word 0          // signed 32-bit (or use -1 initial for 0-indexed combo)

// Back-to-back flag (1 = last line clear was "difficult", 0 = not)
.globl _b2b_active
_b2b_active:        .byte 0

// Last move was rotation flag (1 = yes, 0 = no)
.globl _last_was_rotation
_last_was_rotation: .byte 0

// T-spin detected flag (set during _lock_piece, used for scoring)
.globl _is_tspin
_is_tspin:          .byte 0
```

### New Score Tables (data.s, __TEXT,__const)

```asm
// T-spin scoring: lines_cleared index (0=zero, 1=single, 2=double, 3=triple)
.globl _tspin_score_table
.p2align 2
_tspin_score_table:
    .word 400, 800, 1200, 1600

// Perfect clear scoring: lines_cleared index (1-based: 0=single, 1=double, 2=triple, 3=tetris)
// Index 4 = B2B Tetris perfect clear
.globl _perfect_clear_table
.p2align 2
_perfect_clear_table:
    .word 800, 1200, 1800, 2000, 3200
```

### Variables to Reset in _reset_board

All new state variables must be zeroed in `_reset_board`:
- `_combo_count` = 0
- `_b2b_active` = 0
- `_last_was_rotation` = 0
- `_is_tspin` = 0

## Open Questions

1. **Lock bonus removal:**
   - What we know: The C++ original awards +10 per lock. Modern guideline does NOT include lock bonus. Current asm code adds +10 in `_lock_piece`.
   - What's unclear: Whether to keep +10 for compatibility with C++ original or remove it for guideline compliance.
   - Recommendation: Remove the +10 lock bonus. The phase goal explicitly says "modern Tetris guideline." The +10 is non-standard. This is a minor scoring difference that makes the system cleaner.

2. **Combo counter initial value:**
   - What we know: Guideline says combo starts at -1 or 0 depending on implementation. First consecutive clear should give 0 combo bonus.
   - What's unclear: Whether to use signed -1 start or unsigned 0 start with different formula.
   - Recommendation: Start at 0, but only award combo bonus when combo_count >= 1 (i.e., second consecutive clear onwards). Increment BEFORE scoring check. This avoids signed arithmetic.

3. **T-spin Mini (SCORE-04/SCORE-05 scope):**
   - What we know: REQUIREMENTS.md out-of-scope section says "T-spin Mini distinction in scoring (full vs. mini based on kick offset)" is out of scope.
   - Recommendation: Implement only full T-spin (3-corner rule). All T-spins are scored as full T-spins. No mini distinction. This simplifies implementation significantly -- no need to track kick offsets or distinguish front/back corners.

## Sources

### Primary (HIGH confidence)
- yetris assembly source code (read directly): `asm/data.s`, `asm/board.s`, `asm/piece.s`, `asm/input.s`, `asm/main.s`, `asm/render.s`
- yetris C++ source code (read directly): `src/Game/Entities/Game.cpp`, `src/Game/Entities/Board.cpp`
- [Tetris Wiki: Scoring](https://tetris.wiki/Scoring) -- verified modern guideline scoring values
- [Tetris Wiki: T-Spin](https://tetris.wiki/T-Spin) -- verified 3-corner detection algorithm

### Secondary (MEDIUM confidence)
- `.planning/research/FEATURES.md` -- previous v1.1 research covering scoring complexity estimates

### Tertiary (LOW confidence)
- None -- all findings verified against primary sources.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - all code is in existing asm files, no new dependencies
- Architecture: HIGH - scoring flow redesign verified against existing code structure
- Pitfalls: HIGH - all pitfalls derived from direct code reading and guideline verification
- T-spin detection: HIGH - pivot position verified in `_piece_data` (always row=2, col=2 for T-piece)

**Research date:** 2026-02-27
**Valid until:** Indefinite (Tetris guideline is stable; codebase changes are tracked)
