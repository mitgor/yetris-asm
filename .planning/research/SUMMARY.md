# Project Research Summary

**Project:** yetris-asm v1.1 — Visual Polish & Gameplay
**Domain:** ARM64 assembly Tetris clone — ncurses subwindows, animations, modern scoring, file I/O
**Researched:** 2026-02-27
**Confidence:** HIGH

## Executive Summary

yetris-asm v1.1 adds visual polish, modern scoring, and file persistence to a proven v1.0 ARM64 assembly Tetris engine. The approach is evolutionary: the v1.0 stack (Apple assembler, macOS ncurses, libSystem, NEON SIMD, Darwin syscalls) is entirely reused, with three new capability domains layered on top — ncurses subwindow management, a modern Tetris guideline scoring engine, and hi-score file persistence. The C++ original (yetris) serves as the definitive feature reference, giving us authoritative algorithms for all 4 background animations, T-spin detection, and pixel-perfect panel layout. All new technology has been verified against macOS SDK headers and darwin-xnu source, so implementation risk is in assembly complexity, not in unknowns.

The recommended build order is dependency-driven: subwindows must come first because nearly every other v1.1 feature depends on having proper WINDOW* objects for each panel. Visual polish and scoring can then proceed in parallel — they share no dependencies after the subwindow foundation is in place. Animations are self-contained enough to live in a new `animation.s` file and are the most LOC-intensive feature (~400–600 lines) but architecturally isolated. The two critical scoring chains — level-multiplied scoring and T-spin detection — must be sequenced with T-spin tracking added to the input and rotation handlers before the corner-check logic in `score.s` can work correctly.

The top risk is ncurses subwindow refresh ordering: `derwin` subwindows share memory with their parent, and calling `werase` on the parent after drawing a child erases the child's content. The entire render loop must follow the strict sequence: erase parent → draw parent borders → `wnoutrefresh` parent → erase child → draw child content → `wnoutrefresh` child → `doupdate`. Getting this wrong produces blank panels or flickering artifacts. The second major risk is the wborder 9-argument ABI trap — the bottom-right corner character is the 9th argument and goes on the stack, not in a register. Both risks are mechanical, well-understood, and fully preventable with the concrete patterns documented in ARCHITECTURE.md and PITFALLS.md.

## Key Findings

### Recommended Stack

The v1.0 technology foundation is unchanged and requires no new dependencies. V1.1 extends three capability domains using what is already linked. ncurses (system, v5.4) has everything needed: `newwin`/`derwin`/`delwin` for subwindow management, `wborder`/`box` for ACS box-drawing borders, `wnoutrefresh`/`doupdate` for batched rendering, and `use_default_colors` for transparent animation backgrounds. File I/O uses Darwin syscalls (open=5, read=3, write=4, close=6, mkdir=136) consistent with the existing `write(2)` pattern already in `main.s`. Modern scoring requires no new libraries — it is pure data tables and integer arithmetic.

**Core technologies:**
- Apple `as` + `ld` (ARM64 Darwin): assembler/linker — unchanged from v1.0; all conventions proven in the existing 5,300-line codebase
- System ncurses (`-lncurses`): UI rendering — adds subwindow API (`newwin`, `derwin`, `delwin`), ACS chars via `acs_map[]`, batched refresh via `wnoutrefresh`+`doupdate`; no new linker flags needed
- libSystem (`-lSystem`): runtime + `_getenv` — file I/O via Darwin syscalls (already used for stderr write); `_getenv("HOME")` for hi-score path construction
- NEON SIMD: already used for line detection in v1.0 — reused for perfect clear board scan (`ld1` + `orr` + `umaxv` pattern) at no additional cost
- tetris.wiki scoring formulas: verified authoritative source for all guideline scoring values (combos, back-to-back, T-spin tables, perfect clear bonuses)

See `.planning/research/STACK.md` for complete ncurses function signatures, ACS character index table, Darwin syscall numbers, scoring data table layouts, and animation buffer sizing.

### Expected Features

**Must have (table stakes — required for C++ parity):**
- ncurses subwindows for each panel (board, hold, next, score, stats) — C++ uses ~10 WINDOW* objects via `derwin`
- Pixel-perfect 80×24 layout matching C++ `LayoutGame` geometry with exact panel positions
- ACS box-drawing borders with color-coded shadows (bright left/top, dim right/bottom) via `wborder`
- Window titles ("Hold", "Next", "Statistics") rendered over panel borders at top-left
- Additional ncurses color pairs (pairs 8–16) for UI labels, dim borders, and animation colors
- ASCII art "YETRIS" logo on main menu (7-line, ~40 chars wide)
- Hi-score display in score panel
- Line clear flash animation (visual delay before row collapse, ~200ms)

**Should have (differentiators — modern Tetris guideline scoring):**
- Level-multiplied line scores (100/300/500/800 × level)
- Combo system (50 × combo_count × level for consecutive line-clearing placements)
- Back-to-back bonus (1.5× for consecutive "difficult" clears: Tetris or T-spin)
- T-spin detection (3-corner rule) with full T-spin scoring table (400–1600 × level)
- Perfect clear bonus (800–2000 × level, added on top of line clear score)
- Soft/hard drop scoring (1/2 points per cell dropped)
- Background animations: Snakes and Game of Life (medium complexity)
- Background animations: Fire and Water (high complexity, particle/wave simulation)
- Hi-score file persistence (`~/.yetris-asm-hiscore`, 4-byte binary or ASCII digits)

**Defer (anti-features for v1.1):**
- Profile system (C++ version is ~600 lines; single global hi-score is sufficient)
- Configurable keybindings from file
- Theme system (hardcode C++ defaults)
- Top-10 leaderboard (single top score only per PROJECT.md)
- All-spin detection (T-spin only)
- Menu animations (in-game animations sufficient for v1.1)
- T-spin Mini vs Proper full distinction (basic 3-corner rule first, mini as stretch goal)

See `.planning/research/FEATURES.md` for complete feature dependency graph, complexity estimates, and assembly LOC sizing (~2,500 lines added, binary grows from 52KB to ~62KB).

### Architecture Approach

V1.1 adds 3 new source files (`score.s`, `animation.s`, `hiscore.s`) and makes targeted modifications to 7 of the 9 existing files. The global-variable data model from v1.0 is preserved — all game state lives in `data.s`, all functions read/write globals via `adrp+add`. The subwindow transition changes every rendering function's coordinate origin (from absolute stdscr positions to panel-relative 0,0), but the drawing primitives (`wmove`, `waddch`, `waddstr`) are unchanged. The render loop switches from `wrefresh(stdscr)` to `wnoutrefresh` per window + single `doupdate`. Animations live entirely in `animation.s` and are called from `_render_frame` as update/draw pairs; they write into `_win_board` before locked blocks are drawn on top, exactly matching the C++ layering order.

**Major components:**
1. `data.s` (extended) — adds WINDOW* pointers (7 × `.quad`), scoring state (`_combo_count`, `_back_to_back`, `_last_move_was_rotation`, `_last_kick_index`), animation buffers (~3.9KB in `.bss`), `_hi_score` variable, logo strings, additional color pair data
2. `render.s` (extensively modified) — replaces all stdscr references with subwindow pointers; adds ACS borders via `box`/`wborder`, color attributes on labels, animation draw integration, line-clear flash rendering; ~500 lines modified or added
3. `score.s` (new, ~250 lines) — exports `_detect_tspin`, `_compute_score`, `_check_perfect_clear`, `_reset_scoring_state`; called from `board.s` at lock time
4. `animation.s` (new, ~500 lines) — exports `_init_animation`, `_update_animation`, `_draw_animation`, `_reset_animation`; branches internally on `_anim_type` for fire/water/snakes/life
5. `hiscore.s` (new, ~125 lines) — exports `_load_hiscore`, `_save_hiscore`, `_check_hiscore`; uses Darwin syscalls for file I/O
6. `board.s` (modified) — `_clear_lines` split into `_mark_full_lines` + `_execute_clear` to support line-clear animation; calls `_compute_score` from `score.s`
7. `input.s` (modified) — sets `_last_move_was_rotation` flag on successful rotation vs. move/drop

See `.planning/research/ARCHITECTURE.md` for complete data flow diagrams for scoring, rendering, and animations; anti-patterns to avoid; and recommended build order with per-phase validation goals.

### Critical Pitfalls

1. **ncurses subwindow refresh ordering corrupts display** — `derwin` shares parent buffer memory; erasing the parent erases child content. Always follow: erase parent → draw parent → `wnoutrefresh` parent → erase child → draw child → `wnoutrefresh` child → `doupdate`. Never call `wrefresh` on individual subwindows (triggers immediate `doupdate`, causing partial frames). PITFALLS.md Pitfalls 1 and 3.

2. **ACS box-drawing characters require GOT-indirect load of `acs_map`** — ACS constants are NOT integer literals; they are indices into `_acs_map[]` (an ncurses global). Access: `adrp x8, _acs_map@GOTPAGE; ldr x8, [x8, _acs_map@GOTPAGEOFF]; ldr w10, [x8, x9, lsl #2]`. The `acs_map` array is only populated after `_initscr` returns. PITFALLS.md Pitfall 2.

3. **`wborder` takes 9 arguments — the 9th goes on the stack** — ARM64 passes 8 integer args in x0–x7; the bottom-right corner char is the 9th and must be pushed on the stack. Use `_box(win, 0, 0)` (3 args only) as the simpler default-border alternative. PITFALLS.md Pitfall 8.

4. **T-spin detection requires "last move was rotation" state tracking** — The current codebase does not track what kind of move was last performed. Add `_last_move_was_rotation` byte: set to 1 in `_try_rotate` on success, set to 0 in `_try_move`, `_soft_drop`, `_hard_drop`. Without this, T-spin cannot be distinguished from a translated placement. PITFALLS.md Pitfall 6.

5. **Line clear animation: non-blocking state machine, not `usleep`** — The C++ reference uses a blocking `delay_ms()`. In assembly, prefer the non-blocking state machine: mark rows with value 9, set `_line_clear_anim_active` + timestamp, render flash each frame, execute actual clear after 200ms timer fires. The blocking approach drops inputs and skews frame timing. PITFALLS.md Pitfall 12.

6. **File I/O error handling is mandatory — every call** — Darwin syscalls set the carry flag on error with errno in x0. Prefer `bl _open` (libSystem) which returns -1 on error with standard POSIX semantics. Check every return: `cmn x0, #1; b.eq Lopen_failed`. An unchecked open failure passes an error code as an fd to subsequent write calls, causing silent data loss or a crash. PITFALLS.md Pitfall 7.

## Implications for Roadmap

Based on research, the dependency graph has two parallel tracks after the foundational subwindow phase. This suggests a 6-phase structure.

### Phase 1: Subwindow Foundation
**Rationale:** The longest dependency chain starts here — nearly all v1.1 features draw into named subwindows. Converting from stdscr to WINDOW* objects first means every subsequent feature uses window-relative coordinates from the start, eliminating coordinate system churn later. This is the highest-risk phase structurally and must be validated before proceeding. FEATURES.md critical path: `subwindows → borders → layout → animations`.
**Delivers:** Working game with the same visual behavior as v1.0 but rendered through 7 named subwindows; `newwin`/`derwin` init/cleanup in `main.s`; `wnoutrefresh`+`doupdate` render loop; `_box` borders on all panels; terminal size guard (80×24 minimum with `_LINES`/`_COLS` check); NULL return value check on every `_newwin`/`_derwin` call.
**Addresses:** ncurses subwindows, 80×24 geometry, basic borders (FEATURES.md table stakes)
**Avoids:** Pitfall 1 (refresh ordering), Pitfall 3 (derwin shared memory), Pitfall 8 (wborder 9-arg ABI), Pitfall 13 (NULL check on failed window creation), Pitfall 16 (register pressure — use globals for WINDOW*)

### Phase 2: Visual Polish
**Rationale:** Purely additive and low-risk once subwindows exist. Color pairs, ACS border glyphs, window titles, and the ASCII logo can all be applied incrementally with no game logic changes. Completing this phase makes the game visually match the C++ original before touching any gameplay logic.
**Delivers:** ACS box-drawing borders with color-coded shadows (GOT-indirect `acs_map` load, color pairs ORed via `n << 8`); 9 additional color pairs (pairs 8–16); colored UI labels in score/next/hold panels; window title text overlaid on panel borders; 7-line ASCII art logo centered on main menu.
**Uses:** `_acs_map` GOT-indirect addressing (STACK.md §1.3); `COLOR_PAIR(n) = n << 8` bit pattern (STACK.md §1.4); `use_default_colors` for animation color transparency
**Avoids:** Pitfall 2 (ACS char loading — GOT-indirect, not literal), Pitfall 14 (COLOR_PAIR bit shifting)

### Phase 3: Modern Scoring Engine
**Rationale:** The scoring chain is dependency-ordered within itself: level multiplier → combo → T-spin detection → back-to-back → perfect clear. All scoring logic is isolated in the new `score.s` file plus targeted modifications to `board.s`, `input.s`, and `piece.s`. This phase is independent of visual polish (parallel track) and should be developed and tested against the existing simple rendering before animations are added.
**Delivers:** `score.s` with `_detect_tspin`, `_compute_score`, `_check_perfect_clear`; `_last_move_was_rotation` and `_last_kick_index` tracking in `input.s`/`piece.s`; level-multiplied line scores replacing flat table; combo bonus (`_combo_count` initialized to -1, increments on clear, resets on non-clearing lock); back-to-back 1.5× multiplier (`score + score >> 1` integer approximation); T-spin scoring table (STACK.md §3.2); perfect clear detection via NEON board scan; soft/hard drop point awards.
**Implements:** Modern scoring component (ARCHITECTURE.md §Feature 4); score data tables in `__TEXT,__const` (STACK.md §3.2–3.4)
**Avoids:** Pitfall 6 (T-spin rotation flag tracking), Pitfall 9 (combo counter lifecycle — reset on non-clear, not on every lock), Pitfall 10 (B2B difficulty classification requires T-spin working first), Pitfall 11 (perfect clear scan timing — after clear_lines, before spawn)

### Phase 4: Line Clear Animation
**Rationale:** Depends on both Phase 1 (subwindows must be stable — the flash renders into named windows) and Phase 3 (the mark/execute split of `_clear_lines` is the same refactor needed for scoring correctness). This phase implements the non-blocking state machine approach to avoid input drops during the animation.
**Delivers:** `_mark_full_lines` + `_execute_clear` split in `board.s`; `_pending_clear_count` and `_line_clear_anim_active` state in `data.s`; flash rendering (value-9 cells rendered as A_REVERSE or bright white); 200ms non-blocking timer between mark and execute; gravity paused during animation window.
**Avoids:** Pitfall 12 (blocking `usleep` drops inputs — use state machine with `_get_time_ms` check instead)

### Phase 5: Background Animations
**Rationale:** Fully self-contained in the new `animation.s` file. Depends on Phase 1 (animations write into `_win_board`) but is independent of scoring changes. Sequenced after core gameplay features because it has the highest LOC cost and the lowest impact on game correctness. Start with Snakes (simplest — dynamic list of structs) to validate the animation framework, then Game of Life, then Fire and Water.
**Delivers:** `animation.s` with `_init_animation`/`_update_animation`/`_draw_animation`/`_reset_animation` for all 4 types; static `.bss` buffers for fire (~3.2KB), water (~3.2KB), life (~400B), snakes (~256B); per-animation timer globals in `data.s` (not registers); random animation type selection at game start via `_arc4random_uniform(4)`; animation type menu option.
**Uses:** `_arc4random_uniform` (existing in `random.s`); `_get_time_ms` (existing timer); C++ algorithm reference for all 4 animation types (ARCHITECTURE.md §Feature 3); NEON for potential animation inner loop acceleration
**Avoids:** Pitfall 4 (animation buffers in `.bss`, not stack — 3.2KB exceeds stack frame budgets), Pitfall 5 (timer globals, not caller-saved registers — ncurses calls clobber x9–x15)

### Phase 6: Hi-Score File Persistence
**Rationale:** Fully independent of all other phases. Can be done at any point after Phase 3 (scoring must be finalized before the hi-score comparison logic is meaningful). Placed last because it has the lowest visibility impact relative to implementation effort, and because all file I/O must have robust error handling that benefits from being developed in isolation.
**Delivers:** `hiscore.s` with `_load_hiscore`, `_save_hiscore`, `_check_hiscore`; `_getenv("HOME")` + string concatenation for file path on a stack buffer; Darwin syscalls (or libSystem wrappers) for open/read/write/close; `_hi_score` display in score panel render; graceful handling of missing/unreadable file (default to 0, no crash).
**Avoids:** Pitfall 7 (check every file I/O return value; prefer libSystem `_open`/`_read`/`_write` over raw syscalls for cleaner `-1` error semantics)

### Phase Ordering Rationale

- **Subwindows first:** The FEATURES.md critical path is explicit: `subwindows → borders → layout → animations`. Every draw function must be converted before any content-specific feature is usable at the correct coordinate origin.
- **Visual polish before gameplay changes:** Applying color and borders to existing render functions while they are still coordinate-stable is lower risk than doing it simultaneously with scoring refactors that also touch `board.s` and `input.s`.
- **Scoring before line-clear animation:** The mark/execute split of `_clear_lines` is required for both the flash animation and for correct scoring timing. Doing scoring first produces the right refactored structure that the animation phase builds on.
- **Animations last among game features:** Highest LOC cost, lowest correctness impact. If timeline is tight, Phase 5 can be scoped down (deliver Snakes only for v1.1, defer Fire/Water to v1.2).
- **Hi-score independent:** Phase 6 can be interleaved with any other phase; the ordering is cosmetic. Placed last to allow scoring logic to be fully settled before the comparison logic is finalized.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 3 (T-spin detection):** The 3-corner rule with front/back corner distinction for T-spin Mini is rotation-state-dependent. Confirm the `_piece_data` 5×5 grid layout to verify the T-piece pivot cell offset (expected: row 2, col 2 within the 5×5 grid). The assembly `_piece_rotation` encoding must match the ARCHITECTURE.md rotation-state table before the front/back corner lookup table is built. A mismatch here silently produces wrong T-spin scores.
- **Phase 5 (Animations — Fire and Water):** The fire and water algorithms use integer grid cells sized for the C++ `Array2D`. Buffer dimensions must match the actual `_win_board` inner dimensions established in Phase 1. Do not hardcode buffer sizes until Phase 1 confirms exact panel geometry.

Phases with standard patterns (skip research-phase):
- **Phase 1 (Subwindows):** ncurses subwindow API is well-documented; assembly call patterns are fully specified in STACK.md §1.1–1.2 and ARCHITECTURE.md §Feature 1. No unknowns.
- **Phase 2 (Visual Polish):** ACS character indices and COLOR_PAIR bit layout verified against macOS SDK `curses.h`. No ambiguity.
- **Phase 4 (Line Clear Animation):** Pattern is a straightforward state machine using the existing `_get_time_ms` timer infrastructure. Direct analog to the gravity timer already in `main.s`.
- **Phase 6 (Hi-Score):** Darwin syscall numbers verified against darwin-xnu source; `_getenv` is standard libSystem usage; file path construction with `strcpy`/`strcat` analogs is routine. No novel patterns needed.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All ncurses functions, syscall numbers, and ABI details verified against macOS SDK headers, darwin-xnu source, and tetris.wiki. The v1.0 codebase is direct evidence that core calling conventions are correct on the target hardware. |
| Features | HIGH | C++ original source code read directly for all features. Scoring values cross-referenced with tetris.wiki. Anti-features explicitly scoped by PROJECT.md. Complexity estimates are assembly-specific (5–15× C++ LOC). |
| Architecture | HIGH for existing code; MEDIUM for integration | All 9 existing source files read in full. Integration analysis based on reading C++ reference and tracing data flows — correct in approach, but specific instruction sequences will surface edge cases during implementation (especially around register pressure in `render.s`). |
| Pitfalls | HIGH for ncurses/ABI pitfalls; MEDIUM for scoring edge cases | ncurses pitfalls verified against official documentation and macOS headers. Scoring pitfalls (T-spin Mini, combo lifecycle) verified against tetris.wiki but no assembly-specific prior art exists for the exact ARM64 implementation path. |

**Overall confidence:** HIGH

### Gaps to Address

- **T-spin pivot cell offset in existing piece data:** The 3-corner rule requires knowing which cell in the 5×5 piece grid is the T-piece pivot. Verify `_piece_data` layout during Phase 3 planning before writing `_detect_tspin`. If the pivot is not at grid (2,2), the board coordinate calculation for the diagonal corner check changes.
- **Actual board panel dimensions:** ARCHITECTURE.md projects the board window as 20×20 cells, but the exact `derwin` parameters for `_win_board` inside `_win_board_frame` will be determined when Phase 1 is implemented. Animation buffer sizes in `.bss` should not be finalized until these dimensions are confirmed.
- **T-spin Mini vs Proper:** Research recommends implementing basic 3-corner T-spin first and Mini as a stretch goal. If Mini scoring is required for v1.1, kick index tracking in `_try_rotate` must be fully plumbed through before Phase 3 is marked complete. The separate scoring table already supports it (STACK.md §3.2).
- **libSystem vs raw syscalls for file I/O:** PITFALLS.md recommends `bl _open` (libSystem) for cleaner POSIX error semantics; STACK.md documents raw syscall numbers as the alternative consistent with the v1.0 pattern. Both work. Recommendation: use libSystem wrappers for `hiscore.s` since robust error handling is simpler with `-1` return values than carry-flag checking.

## Sources

### Primary (HIGH confidence)
- macOS SDK `curses.h` (`/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/curses.h`) — ACS character indices, attribute bit layout, COLOR_PAIR encoding, function signatures, verified locally
- [apple/darwin-xnu syscalls.master](https://github.com/apple/darwin-xnu/blob/main/bsd/kern/syscalls.master) — open(5), close(6), read(3), write(4), mkdir(136), access(33)
- [tetris.wiki/Scoring](https://tetris.wiki/Scoring) — guideline line clear, T-spin, back-to-back, combo, perfect clear formulas
- [tetris.wiki/T-Spin](https://tetris.wiki/T-Spin) — 3-corner detection algorithm, front/back corner definitions, mini vs proper distinction
- yetris C++ source (read directly): LayoutGame.cpp, Window.cpp, Board.cpp, Game.cpp, ScoreFile.cpp, AnimationFire.cpp, AnimationWater.cpp, AnimationSnakes.cpp, AnimationGameOfLife.cpp
- Existing assembly source (read directly): asm/main.s, asm/render.s, asm/board.s, asm/piece.s, asm/data.s, asm/input.s, asm/menu.s, asm/random.s, asm/timer.s

### Secondary (MEDIUM confidence)
- [ncurses curs_window(3x)](https://invisible-island.net/ncurses/man/curs_window.3x.html) — newwin/derwin/subwin/delwin signatures and shared-memory semantics
- [ncurses intro — wnoutrefresh/doupdate pattern](https://invisible-island.net/ncurses/ncurses-intro.html) — batch refresh documentation
- [tetris.wiki/Combo](https://tetris.wiki/Combo) — combo counter lifecycle rules
- [HelloSilicon ARM64 macOS examples](https://github.com/below/HelloSilicon) — assembly file I/O patterns on Apple Silicon
- [ncurses wborder man page](https://linux.die.net/man/3/wborder) — 9-argument signature, default ACS values

### Tertiary (LOW confidence — verify before using)
- [Hard Drop Wiki: T-Spin Guide](https://harddrop.com/wiki/T-Spin_Guide) — community detection rules confirmation
- [katyscode.wordpress.com — Coding for T-Spins](https://katyscode.wordpress.com/2012/10/13/tetris-aside-coding-for-t-spins/) — C implementation guide for T-spin detection

---
*Research completed: 2026-02-27*
*Ready for roadmap: yes*
