---
phase: 05-optimization-research-and-documentation
verified: 2026-02-27T08:30:00Z
status: human_needed
score: 8/9 must-haves verified
re_verification: false
human_verification:
  - test: "Play the game interactively, clear several lines, then quit with 'q'"
    expected: "stderr prints 'Frames: N  Min: Nus  Max: Nus  Avg: Nus' with real microsecond values demonstrating the frame timing instrumentation works end-to-end during actual gameplay"
    why_human: "The game requires a TTY for ncurses input. The frame timing infrastructure is present and wired, but no actual min/max/avg measurements could be collected during automated execution. OPT-06 requires quantitative before/after frame timing measurements; the binary size data satisfies this for OPT-05, but frame timing before/after for OPT-01 and OPT-03 are analytical estimates only."
---

# Phase 5: Optimization Research and Documentation Verification Report

**Phase Goal:** Assembly-specific optimization techniques are explored, measured with quantitative before/after results, and documented in a research writeup comparing the assembly version to the C++ baseline.
**Verified:** 2026-02-27T08:30:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Frame timing data is collected per game frame using mach_absolute_time, measuring game logic only (excluding wgetch block) | VERIFIED | `_mach_absolute_time` called at lines 179 and 234 in `asm/main.s`; `_frame_count`, `_frame_time_sum`, `_frame_time_min`, `_frame_time_max` symbols confirmed in binary via `nm` |
| 2 | On game exit, min/max/avg frame times print to stderr in microseconds | VERIFIED | Lstate_exit in `asm/main.s` (lines 323-388) reads all four frame stat variables and writes formatted output to stderr via raw write(2) syscall; binary tested — launches correctly |
| 3 | NEON line detection replaces the scalar 10-byte loop in _clear_lines with ld1+uminv+umov pattern | VERIFIED | `ld1 {v0.16b}`, `uminv b2, v0.16b` confirmed in `asm/board.s` (lines 340, 344); `otool -tv` confirms 2 NEON instructions in binary |
| 4 | _neon_row_mask 16-byte constant exists in data.s for NEON padding | VERIFIED | `_neon_row_mask` at line 384 in `asm/data.s`; confirmed in `nm` output as symbol `S _neon_row_mask` at 0x0000000100003180 |
| 5 | Register packing moves game_over, is_paused, and game_initialized into x28 bitfield | VERIFIED | 11 tst/orr/bic operations on x28 confirmed in `asm/main.s`; bit 0=game_over, bit 1=is_paused, bit 2=game_initialized with sync points after _handle_input and _soft_drop |
| 6 | -dead_strip linker flag and asm-strip target added to Makefile | VERIFIED | `-dead_strip` at Makefile line 222; `asm-strip` target at lines 237-242; `asm-profile` target at line 244; all declared in .PHONY at line 252 |
| 7 | Binary size before/after strip and dead_strip documented in MEASUREMENTS-05.md | VERIFIED | MEASUREMENTS-05.md contains: dead_strip table (0 bytes effect), strip table (55,624 -> 52,720, -5.2%), LINKEDIT reduction (6,472 -> 3,568), symbol count (121 -> 22); all quantitative |
| 8 | A 150+ line research writeup exists covering all 5 optimization techniques with ARM64-specific vs generic classification | VERIFIED | `research/optimization-writeup.md` is 530 lines; all 5 techniques (OPT-01 through OPT-05) covered; ARM64-Specific vs Generic classification table at line 438; binary comparison table (18.6x smaller than C++) present |
| 9 | Before/after frame timing measurements (actual microsecond values) exist for NEON line detection and register packing | UNCERTAIN — needs human | MEASUREMENTS-05.md contains only analytical estimates for frame timing impact of OPT-01 and OPT-03 ("below noise floor expected", "requires interactive gameplay to measure"). Actual before/after run data was not collected due to TTY limitation during automated execution. Binary size before/after IS quantitative for OPT-05. |

**Score:** 8/9 truths verified — 1 requires human confirmation

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `asm/main.s` | Frame timing instrumentation wrapping game logic in Lgame_frame; contains _mach_absolute_time | VERIFIED | mach_absolute_time at lines 179 and 234; frame stat variables at lines 561-568; stats output in Lstate_exit |
| `asm/main.s` | Register packing of game_over/is_paused/game_initialized into x28 bitfield | VERIFIED | 11 x28 bitfield operations; tst x28 #1 (game_over), tst x28 #2 (is_paused), tst x28 #4 (game_initialized) |
| `asm/board.s` | NEON line detection in _clear_lines; contains uminv | VERIFIED | ld1/uminv/umov pattern at lines 340-347; replaces Lclear_check_col scalar loop |
| `asm/data.s` | 16-byte NEON mask for padding bytes 10-15 to 0xFF; contains _neon_row_mask | VERIFIED | `_neon_row_mask` at line 384 with `.p2align 4` (16-byte aligned) |
| `Makefile` | asm-strip target and -dead_strip linker flag; contains strip | VERIFIED | -dead_strip at line 222; asm-strip target at lines 237-242 |
| `.planning/phases/05-optimization-research-and-documentation/MEASUREMENTS-05.md` | Before/after frame timing data for NEON and register packing; contains NEON|Register Packing | PARTIAL | Contains NEON Line Detection and Register Packing sections with instruction count analysis and binary size data. Frame timing before/after data is analytical estimation only — no actual run measurements due to TTY limitation. |
| `research/optimization-writeup.md` | Complete research document covering all optimization techniques; min 150 lines; contains ARM64-specific | VERIFIED | 530 lines; ARM64-specific appears at lines 137, 211, 448, 515; all 5 techniques with classifications |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `asm/main.s` | libSystem `_mach_absolute_time` | `bl _mach_absolute_time` | WIRED | Pattern confirmed at lines 179 and 234; symbol `U _mach_absolute_time` in nm output |
| `Makefile` | `asm/bin/yetris-asm` | `-dead_strip` linker flag and strip post-link | WIRED | -dead_strip in link command; asm-strip target creates stripped copy |
| `asm/board.s _clear_lines` | `asm/data.s _neon_row_mask` | `adrp+add` load of mask, `ldr q1` for NEON OR | WIRED | `adrp x11, _neon_row_mask@PAGE` at board.s line 341-342; mask loaded into q1 for orr |
| `asm/main.s Lgame_frame` | x28 bitfield | `tst/orr/bic` instructions on x28 | WIRED | 11 matching instructions found; tst x28 #1, tst x28 #2, tst x28 #4 for checks; bic+orr for sync |
| `research/optimization-writeup.md` | `MEASUREMENTS-05.md` | References measurement data with before/after tables | WIRED | Binary size tables in writeup match MEASUREMENTS-05.md values exactly; writeup references frame timing methodology from instrumentation |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| OPT-01 | 05-02 | Register-only state packing of game flags in callee-saved registers | SATISFIED | x28 bitfield with game_over(bit 0), is_paused(bit 1), game_initialized(bit 2) in asm/main.s; sync points after _handle_input and _soft_drop |
| OPT-02 | 05-03 | NEON/SIMD collision detection (analyzed, not implemented) | SATISFIED | OPT-02 analyzed in MEASUREMENTS-05.md with instruction count comparison (scalar ~145 dynamic, NEON ~44+); documented as negative result with technical reasoning; covered in research writeup section 4 |
| OPT-03 | 05-02 | NEON/SIMD line detection | SATISFIED | ld1+uminv+umov pattern in asm/board.s replacing scalar Lclear_check_col loop; _neon_row_mask in asm/data.s; uminv confirmed in binary |
| OPT-04 | 05-03 | Syscall batching (analyzed, not applicable) | SATISFIED | OPT-04 analyzed in MEASUREMENTS-05.md with per-frame syscall profile (3-4 total); documented as not applicable; covered in research writeup section 5 |
| OPT-05 | 05-01 | Binary size optimization via dead_strip, symbol stripping, section analysis | SATISFIED | -dead_strip in Makefile; asm-strip target; MEASUREMENTS-05.md has size tables; 5.2% reduction documented; C++ comparison in writeup |
| OPT-06 | 05-01, 05-02, 05-03 | Each optimization technique measured before/after with quantitative results | PARTIALLY SATISFIED | Binary size data is quantitative (55,624->52,720 for strip, 0 effect for dead_strip). Instruction count analysis for OPT-01/OPT-03 is quantitative. Frame timing before/after for OPT-01/OPT-03 is estimated only — no actual run data collected. Negative results (OPT-02/OPT-04) have analytical instruction count estimates. |
| MEAS-02 | 05-01 | Frame timing measurements using mach_absolute_time or clock_gettime | SATISFIED | mach_absolute_time implemented in asm/main.s; four data variables tracking count/sum/min/max; stderr output on exit |
| MEAS-03 | 05-01 | CPU profiling with Instruments to identify hotspots | SATISFIED (with documented limitation) | xcrun xctrace attempted and run; documented in MEASUREMENTS-05.md that ncurses requires TTY so game sat at menu state; limitation and findings documented; frame timing instrumentation serves as primary profiling mechanism |
| MEAS-04 | 05-03 | Research writeup documenting all techniques, measurements, tradeoffs, and findings | SATISFIED | research/optimization-writeup.md is 530 lines; covers all 5 techniques; binary comparison; frame timing methodology; key findings; methodology notes; conclusion |
| MEAS-05 | 05-03 | ARM64-specific vs generic assembly optimizations distinguished in writeup | SATISFIED | Classification present for each technique; summary table in writeup (line 438); 3 ARM64-specific, 2 generic; technical justification for each |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `Makefile` | 240 | `strip -x` used in asm-strip target instead of plain `strip` | Warning | MEASUREMENTS-05.md documents that plain `strip` gives 52,720 bytes while `strip -x` gives 55,664 bytes (larger than unstripped). The asm-strip target uses `strip -x` but the stripped binary in `asm/bin/yetris-asm-stripped` (52,720 bytes) suggests the documentation reflects plain strip results. The Makefile target is inconsistent with the documented "preferred" approach. |
| `MEASUREMENTS-05.md` | 123, 159 | Frame timing before/after tables contain binary size data, not actual frame time measurements | Warning | The "Before NEON" and "Before packing" tables show binary size deltas only. The frame timing sections state "requires interactive gameplay to measure" — this means OPT-06's "quantitative before/after results" for frame impact is not fully satisfied for OPT-01 and OPT-03. |

### Human Verification Required

#### 1. Frame Timing End-to-End Verification (OPT-06, MEAS-02)

**Test:** Build the game with `make asm`. Run `./asm/bin/yetris-asm 2>/tmp/timing.txt`. Play for 30-60 seconds (move pieces, let lines clear), then press 'q' to quit. Run `cat /tmp/timing.txt`.
**Expected:** Output like `Frames: 1800  Min: 142us  Max: 3421us  Avg: 287us` — real microsecond values proving the frame timing infrastructure collects and reports actual measurements during gameplay.
**Why human:** The game requires a TTY for ncurses keyboard input. Automated execution cannot interact with the game. This is the critical missing data point — it confirms OPT-06 has actual quantitative before/after results (even if the "before" baseline was not separately recorded, the current system's frame times demonstrate the measurement works).

#### 2. Game Behavior Correctness After Optimizations

**Test:** Play a full game from menu to game over. Verify: pieces move, rotate, and fall; line clearing works (rows disappear when full, rows above collapse); hold piece works; ghost piece appears; score increments on line clears; game over triggers correctly.
**Expected:** Identical gameplay behavior to Phase 4 — no regressions from the NEON line detection or x28 register packing changes.
**Why human:** Functional correctness of the NEON ld1+uminv substitution and the x28 sync-on-demand pattern (especially correctness around game_over and is_paused flag synchronization) requires playing through scenarios that exercise those code paths interactively.

### Gaps Summary

No hard gaps block the phase goal. The phase achieved its primary deliverables:

1. Frame timing infrastructure is fully implemented and wired (mach_absolute_time, four data variables, stderr output on exit).
2. NEON line detection is implemented (ld1+uminv in board.s, _neon_row_mask in data.s).
3. Register packing is implemented (x28 bitfield with 11 tst/orr/bic operations, sync points after callers that modify flags).
4. Binary size optimization is documented with actual quantitative data.
5. The research writeup (530 lines) covers all 5 techniques with ARM64-specific vs generic classification.
6. All 6 task commits exist in git history.

The one uncertainty is whether actual frame timing microsecond values have been collected from interactive gameplay. The infrastructure is present, but OPT-06 ("measured before/after with quantitative results") is only partially satisfied for OPT-01 and OPT-03 — those techniques have binary size measurements and analytical instruction counts, but not actual run timing data. This is a documentation completeness issue, not a missing implementation.

There is also a minor discrepancy: the Makefile asm-strip target uses `strip -x` while MEASUREMENTS-05.md documents plain `strip` as producing the smaller result (52,720 bytes). The stripped binary on disk happens to be 52,720 bytes, which is consistent with the documentation — this may reflect that the binary was stripped with plain `strip` during plan execution and the Makefile target was not subsequently used to recreate it.

---

_Verified: 2026-02-27T08:30:00Z_
_Verifier: Claude (gsd-verifier)_
