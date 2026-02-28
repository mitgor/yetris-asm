---
phase: 11-hi-score-persistence
verified: 2026-02-27T20:15:00Z
status: human_needed
score: 4/4 must-haves verified
human_verification:
  - test: "First launch with no ~/.yetris-hiscore file: score panel shows '(none)' under Hi-Score label"
    expected: "Score panel displays 'Hi-Score' label on row 1 and '(none)' on row 2; no crash, no garbage"
    why_human: "Requires running the binary and visually inspecting the ncurses UI"
  - test: "Score points during gameplay: Hi-Score display updates live to match current score once it exceeds 0"
    expected: "As soon as any piece locks and score increments above 0, the Hi-Score row switches from '(none)' to the numeric value and tracks score in real time"
    why_human: "Real-time rendering behavior cannot be verified statically; requires interactive play"
  - test: "Trigger game over with a non-zero score: verify ~/.yetris-hiscore is created as a 4-byte file"
    expected: "File exists at correct path, is exactly 4 bytes, contains score as little-endian uint32 (confirm with xxd)"
    why_human: "Requires actually running the game to game over; file system state after run"
  - test: "Relaunch the game after saving: score panel shows the numeric hi-score, not '(none)'"
    expected: "Hi-Score row displays the previously-saved value, right-aligned in 8-char field via Ldraw_number"
    why_human: "Cross-session persistence requires two independent runs of the binary"
  - test: "Delete ~/.yetris-hiscore and relaunch: game handles missing file gracefully"
    expected: "Score panel shows '(none)'; no crash, no hang"
    why_human: "Error path (ENOENT from open syscall -> b.cs bail) needs live execution to confirm"
---

# Phase 11: Hi-Score Persistence Verification Report

**Phase Goal:** Top score survives across game sessions via file storage
**Verified:** 2026-02-27T20:15:00Z
**Status:** human_needed (all automated checks passed; 5 interactive tests required)
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #  | Truth | Status | Evidence |
|----|-------|--------|---------|
| 1  | When the player achieves a new high score and the game ends, the score is saved to ~/.yetris-hiscore as a 4-byte uint32 file | VERIFIED (automated) | `main.s:326-337` — `Lgame_over_screen` loads `_score` (w9) and `_hiscore` (w10), `b.ls Lno_new_hiscore` skips save when score <= hiscore, otherwise `str w9, [x8]` updates in-memory and `bl _save_hiscore` is called. `_save_hiscore` in `hiscore.s:122-184` opens with `O_WRONLY|O_CREAT|O_TRUNC`, writes 4 bytes via syscall 4. |
| 2  | On startup, the previous high score loads from ~/.yetris-hiscore and displays in the score panel; if no file exists or is unreadable, it displays '(none)' with a value of 0 | VERIFIED (automated) | `main.s:98-99` — `bl _load_hiscore` called after `_anim_select_random` and before state machine. `_load_hiscore` in `hiscore.s:41-108` uses getenv("HOME") + suffix, opens with O_RDONLY, reads 4 bytes into `_hiscore`, graceful `b.cs Lload_bail` on any error leaving `_hiscore` at 0. `render.s:1537-1560` — `cbnz w20, Ldraw_hiscore_value` branches: when 0 shows "(none)" via `_waddstr`, when >0 shows numeric via `Ldraw_number`. |
| 3  | During gameplay, the Hi-Score display updates live when the current score exceeds the loaded hi-score | VERIFIED (automated) | `board.s:551-559` — at `Lscore_done`, loads `_hiscore` (w9) and `_score` (w11), `csel w9, w11, w9, hi` selects max, stores back. This runs on every piece lock. `render.s:1538-1539` reads `_hiscore` each render frame, so display tracks in real time. |
| 4  | The hi-score file persists across application restarts — quitting and relaunching shows the saved value | VERIFIED (automated wiring) / NEEDS HUMAN (runtime) | Write path: `_save_hiscore` opens `~/.yetris-hiscore` with `O_WRONLY|O_CREAT|O_TRUNC` and writes raw 4-byte uint32. Load path: `_load_hiscore` opens and reads the same path. The binary format (raw uint32) is stable. Cross-session verification requires running the binary twice. |

**Score:** 4/4 truths verified at wiring level; 5 interactive tests needed to confirm runtime behavior

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `asm/hiscore.s` | `_load_hiscore` and `_save_hiscore` functions using Darwin syscalls and getenv(HOME) | VERIFIED | File exists, 187 lines, both functions present with `.globl` declarations, full syscall-based I/O implementation including error paths |
| `asm/data.s` | `_hiscore` global word, `_str_home_env` and `_str_hiscore_suffix` string constants | VERIFIED | `_hiscore` at line 647 (`.word 0`), `_str_home_env: .asciz "HOME"` at line 429, `_str_hiscore_suffix: .asciz "/.yetris-hiscore"` at line 431 |
| `asm/main.s` | `bl _load_hiscore` at startup, hi-score comparison and `bl _save_hiscore` at game over | VERIFIED | `bl _load_hiscore` at line 99 (after `_anim_select_random`). `Lgame_over_screen` at line 326-337 with comparison and conditional `bl _save_hiscore` |
| `asm/render.s` | `_draw_score_panel` conditionally shows `_hiscore` numeric value or '(none)' when zero | VERIFIED | Lines 1537-1560: loads `_hiscore`, `cbnz w20, Ldraw_hiscore_value` branches correctly, numeric path calls `Ldraw_number`, zero path calls `_waddstr` with `_str_hiscore_none` |
| `asm/board.s` | Live `_hiscore` update via `csel` at end of scoring pipeline in `_lock_piece` | VERIFIED | Lines 551-559 at `Lscore_done`: `csel w9, w11, w9, hi` computes max and stores to `_hiscore` |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `asm/main.s` | `asm/hiscore.s` | `bl _load_hiscore` at startup | WIRED | `main.s:99` — `bl _load_hiscore` present, positioned after `_anim_select_random` (line 96) and before state machine initialization |
| `asm/main.s` | `asm/hiscore.s` | `bl _save_hiscore` at `Lgame_over_screen` (only when score > hiscore) | WIRED | `main.s:336` — `bl _save_hiscore` inside conditional branch at `Lgame_over_screen`; `b.ls Lno_new_hiscore` guard (line 334) ensures save only when `_score > _hiscore` |
| `asm/render.s` | `asm/data.s` | `_draw_score_panel` loads `_hiscore` and branches on zero | WIRED | `render.s:1538` — `adrp x8, _hiscore@PAGE` / `ldr w20, [x8, _hiscore@PAGEOFF]` / `cbnz w20, Ldraw_hiscore_value` |
| `asm/board.s` | `asm/data.s` | `csel` at `Lscore_done` updates `_hiscore = max(_score, _hiscore)` | WIRED | `board.s:552-559` — `_hiscore@PAGE` adrp, `_score@PAGE` adrp, cmp, csel, str |
| `asm/hiscore.s` | `asm/data.s` | `_load_hiscore` stores to `_hiscore`; `_save_hiscore` reads `_hiscore` | WIRED | `hiscore.s:93-94` — `adrp x9, _hiscore@PAGE` / `str w8, [x9, _hiscore@PAGEOFF]` (load). `hiscore.s:162-163` — `adrp x8, _hiscore@PAGE` / `ldr w8, [x8, _hiscore@PAGEOFF]` (save). Both also reference `_str_hiscore_suffix@PAGEOFF` |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|---------|
| HISCORE-01 | 11-01-PLAN.md | Top score saved to ~/.yetris-hiscore as 4-byte uint32 on game over (if new high) | SATISFIED | `_save_hiscore` in `hiscore.s` uses `O_WRONLY|O_CREAT|O_TRUNC` + 4-byte `str w8, [sp]` + syscall write; only called when `_score > _hiscore` at `Lgame_over_screen` |
| HISCORE-02 | 11-01-PLAN.md | Top score loaded from file on startup (defaults to 0 if missing/unreadable) | SATISFIED | `_load_hiscore` called at `main.s:99`; `b.cs Lload_bail` on open failure leaves `_hiscore` at default 0 from `data.s:650` (`.word 0`) |
| HISCORE-03 | 11-01-PLAN.md | Hi-Score displayed in score panel with "Hi-Score" label and "(none)" when zero | SATISFIED | `render.s:1529-1560` — label drawn at row 1 via `_str_hiscore_label`, conditional at row 2: "(none)" when `_hiscore == 0`, numeric via `Ldraw_number` when `_hiscore > 0`. Live update in `board.s:551-559` |

No orphaned requirements: REQUIREMENTS.md maps HISCORE-01, HISCORE-02, HISCORE-03 to Phase 11, all accounted for by 11-01-PLAN.md.

### Anti-Patterns Found

No TODOs, FIXMEs, placeholder strings, empty implementations, or stub returns found in any of the five modified files (`hiscore.s`, `data.s`, `main.s`, `render.s`, `board.s`).

Build confirmation: `make asm` exits with "Assembly build successful!" — all 5 files compile and link cleanly including the auto-discovered `asm/hiscore.s`.

### Human Verification Required

#### 1. First Launch (No Existing File)

**Test:** Delete `~/.yetris-hiscore` if present (`rm -f ~/.yetris-hiscore`), then run `./asm/bin/yetris`
**Expected:** Score panel shows "Hi-Score" label (cyan) on row 1 and "(none)" on row 2; game runs normally with no crash
**Why human:** ncurses visual output and the O_RDONLY fail path require live execution

#### 2. Live Score Panel Update During Gameplay

**Test:** Start a game, lock pieces until any score is earned
**Expected:** As soon as `_score` increments above 0 (first line clear or soft/hard drop), the Hi-Score row transitions from "(none)" to the numeric value and continues tracking
**Why human:** Real-time rendering behavior through the `csel` + `_draw_score_panel` loop cannot be verified statically

#### 3. Game Over File Creation

**Test:** Play until game over with a non-zero score; then run `ls -la ~/.yetris-hiscore && xxd ~/.yetris-hiscore`
**Expected:** File is exactly 4 bytes; `xxd` output shows the score encoded as little-endian uint32
**Why human:** File system state after runtime execution; requires actually triggering game over

#### 4. Cross-Session Persistence (Core Goal)

**Test:** After step 3, quit and relaunch `./asm/bin/yetris`
**Expected:** Score panel immediately shows the saved numeric value (not "(none)"); value is right-aligned in 8-char field
**Why human:** This is the primary phase goal — "top score survives across game sessions" — and requires two independent binary runs

#### 5. Missing File Graceful Fallback

**Test:** Run `rm ~/.yetris-hiscore && ./asm/bin/yetris`
**Expected:** Game launches without crash; score panel shows "(none)"; no error output
**Why human:** The `b.cs Lload_bail` error path on `open` failure needs runtime confirmation

### Gaps Summary

No automated gaps found. All five required artifacts exist and are substantive (no stubs, no placeholders). All five key links are wired with correct assembly patterns verified by direct file inspection. All three requirement IDs (HISCORE-01, HISCORE-02, HISCORE-03) are fully accounted for with implementation evidence.

The phase goal — "Top score survives across game sessions via file storage" — is structurally complete. The entire feature chain is implemented:

1. `data.s` provides `_hiscore` (default 0) and path string constants
2. `hiscore.s` provides load and save with carry-flag error handling
3. `main.s` calls load at startup and conditionally saves at game over
4. `board.s` keeps `_hiscore` current during play via `csel`
5. `render.s` displays numeric value or "(none)" conditionally each frame

Runtime verification (5 interactive tests) is required to confirm behavior under actual execution, including the cross-session persistence path that is the core deliverable of this phase.

---

_Verified: 2026-02-27T20:15:00Z_
_Verifier: Claude Sonnet 4.6 (gsd-verifier)_
