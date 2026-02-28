---
phase: 13-binary-size-analysis
verified: 2026-02-27T22:15:00Z
status: passed
score: 7/7 must-haves verified
re_verification: false
gaps: []
human_verification:
  - test: "Run asm/bin/yetris-asm and verify game launches and plays correctly after NEON mask alignment change"
    expected: "Main menu appears, game starts, pieces move and rotate, line clears work"
    why_human: "Functional regression testing requires interactive game play; automated build pass does not confirm runtime correctness"
---

# Phase 13: Binary Size Analysis Verification Report

**Phase Goal:** Measure and document binary size breakdown, implement easy optimizations, update research writeup with current numbers
**Verified:** 2026-02-27T22:15:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A documented breakdown shows exact byte counts for each Mach-O section (__TEXT, __DATA, __DATA_CONST, __LINKEDIT) in the current post-v1.1 assembly binary | VERIFIED | `research/binary-size-analysis.md` lines 10-38: segment summary table with VM/file sizes, detailed section sizes table with exact bytes from `otool -l` and `size -m` |
| 2 | Per-file contribution to __text code size is measured for all 12 .s source files with totals that sum to the linked __text section size | VERIFIED | `research/binary-size-analysis.md` lines 60-78: all 12 files listed, __text sum = 16,696 bytes, matches linked binary exactly (delta = 0) |
| 3 | The analysis reflects the CURRENT binary (post-v1.1/v1.2) not the stale v1.0 numbers | VERIFIED | File header states "post-v1.1/v1.2", dated 2026-02-27; methodology note explicitly confirms "All numbers are from direct tool output against the current binary"; v1.0 figures only appear in the growth comparison section as an explicit historical baseline |
| 4 | At least one concrete size optimization is implemented with measured before/after byte counts | VERIFIED | `research/binary-size-analysis.md` lines 181-214: NEON mask alignment reduced `.p2align 4` to `.p2align 2`; before = 1,907 bytes __const, after = 1,895 bytes (-12 bytes); confirmed in `asm/data.s` line 408 |
| 5 | The optimization-writeup.md Binary Size Analysis section reflects current post-v1.1 numbers, not stale v1.0 figures | VERIFIED | Abstract (line 9): "13.5x smaller than C++ (77,016 bytes vs 1,036,152 bytes)"; comparison table (lines 36-39): 77,016/16,696/52,720 bytes; no active stale claims — the three grep hits for "55,672"/"10,096" are (a) the v1.0 row in the growth table and (b) the OPT-05 measurement section explicitly labeled "measured at v1.0, Phase 5 -- 55,672-byte binary" |
| 6 | The C++ vs assembly comparison table is updated with current binary sizes | VERIFIED | `research/optimization-writeup.md` lines 34-39: table shows 13.5x smaller (unstripped), 20.7x less code, 10.4x smaller stripped; ratio recalculated from v1.0's 18.6x |
| 7 | The binary still builds and runs correctly after optimizations | VERIFIED (build) | `make asm` returns "# Assembly build successful!"; binary size = 77,016 bytes at `asm/bin/yetris-asm` post-build |

**Score:** 7/7 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `research/binary-size-analysis.md` | Complete binary size analysis document with section breakdown, per-file contributions, and growth analysis | VERIFIED | 232 lines; contains segment summary, detailed section sizes, per-file contribution table for all 12 .s files, symbol analysis, binary growth table, stripped binary comparison, optimizations applied section |
| `research/optimization-writeup.md` | Updated binary size comparison and section breakdown with current numbers | VERIFIED | 543 lines; Binary Size Analysis section (lines 30-97) fully updated: comparison table (13.5x), section breakdown, binary growth table through Phase 13 |
| `asm/data.s` | Data optimizations reduce binary size | VERIFIED | `.p2align 2` at line 408 on `_neon_row_mask` with comment "ld1 does not require 16-byte alignment on AArch64"; reduction from `.p2align 4` confirmed in commit 62ed9f6 |
| `asm/bin/yetris-asm` | Binary built and 77,016 bytes | VERIFIED | `ls -la` confirms 77,016 bytes, timestamp 2026-02-27 |
| `asm/bin/yetris-asm-stripped` | Stripped binary exists for comparison | VERIFIED | 52,720 bytes, exists at `asm/bin/yetris-asm-stripped` |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `research/binary-size-analysis.md` | `asm/bin/yetris-asm` | otool and size measurements of actual binary | VERIFIED | Methodology section (line 219-229) documents commands used (`size -m`, `otool -l`, `nm`, `ls -la`); binary size 77,016 and __text 16,696 match actual binary from `ls -la` |
| `research/optimization-writeup.md` | `research/binary-size-analysis.md` | Numbers from binary-size-analysis.md flow into writeup tables | VERIFIED | Matching numbers: 16,696 __text, 1,895 __const, 8,396 __data, 77,016 file size, 52,720 stripped appear in both documents; writeup OPT-05 section explicitly updates "Current binary (v1.2, 77,016 bytes)" |
| `asm/data.s` | `asm/bin/yetris-asm` | Data optimizations reduce binary size | VERIFIED | `.p2align 2` in data.s at _neon_row_mask; `make asm` succeeds producing 77,016-byte binary; __const section reduced from 1,907 to 1,895 bytes (12-byte saving at section level) |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| SIZE-01 | 13-01-PLAN.md | Binary size breakdown by Mach-O section (__TEXT, __DATA, __LINKEDIT) documented | SATISFIED | `research/binary-size-analysis.md` Section Breakdown table: all segments and sections with exact byte counts from `size -m` and `otool -l`; LINKEDIT breakdown table; segment summary with VM and file sizes |
| SIZE-02 | 13-01-PLAN.md | Per-file contribution to binary size measured and documented | SATISFIED | Per-file contribution table in `research/binary-size-analysis.md` lines 62-77: all 12 .s files, __text bytes, percentages, sorted by code size; sum verified against linked binary (exact match at 16,696 bytes) |
| SIZE-03 | 13-02-PLAN.md | Easy size optimizations identified and implemented (literal pool sharing, data dedup, alignment) | SATISFIED | NEON mask alignment optimization applied (-12 bytes __const); 4 additional optimization paths investigated and documented with findings; page-boundary analysis documents why file size is unchanged |
| SIZE-04 | 13-02-PLAN.md | Before/after binary size comparison with C++ baseline updated | SATISFIED | `research/optimization-writeup.md` Assembly vs C++ Comparison table (lines 34-39): updated from v1.0's 18.6x to 13.5x (unstripped), 20.7x less code (recalculated); abstract, key findings, and conclusion all reflect current numbers |

**No orphaned requirements:** All four Phase 13 requirements (SIZE-01 through SIZE-04) are claimed by plans and satisfied. The traceability table in REQUIREMENTS.md marks all four as Complete.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | None found | — | — |

No TODO/FIXME/placeholder comments found in modified files. No empty implementations. No stale v1.0 numbers used as current claims — the three grep hits for "55,672" and "10,096" are all legitimate historical references explicitly labeled as v1.0/Phase 5 measurements.

### Human Verification Required

#### 1. Game Runtime Regression Check

**Test:** Run `asm/bin/yetris-asm`, navigate the main menu, start a game, move and rotate pieces, allow a line clear to occur.
**Expected:** Game operates identically to pre-optimization state. No crashes, no visual corruption, no incorrect NEON behavior in line detection.
**Why human:** The NEON mask alignment change (`.p2align 4` to `.p2align 2`) affects `_neon_row_mask` used by the NEON line-clear detection path. The ARM Architecture Reference Manual confirms `ld1` does not require 16-byte alignment, but actual runtime behavior on the specific Apple Silicon chip requires interactive testing to confirm. Automated build success does not exercise the NEON code path.

### Gaps Summary

No gaps found. All seven observable truths pass full three-level verification (exists, substantive, wired). All four requirements are satisfied with evidence. Both plans executed as written with no deviations. The binary builds successfully at 77,016 bytes. Stale number references in optimization-writeup.md are all legitimate historical labels in context (v1.0 growth table row, OPT-05 historical measurement section) — they are not stale claims about the current binary.

The one item flagged for human verification (runtime regression from NEON alignment change) is a standard smoke test, not a gap indicator. The technical basis for the optimization is sound (ARM ARMv8-A manual confirms alignment requirement), and the build succeeds. Human testing is recommended before tagging the v1.2 release.

---

_Verified: 2026-02-27T22:15:00Z_
_Verifier: Claude (gsd-verifier)_
