# Phase 3: Binary Size Measurements

**Measured:** 2026-02-26
**Phase:** 3 -- Gameplay Feature Completeness (ghost, hold, next, pause, stats)
**Build:** macOS ARM64, Apple clang / as (assembler), -lncurses, -lSystem

## Binary Size Comparison

| Metric | Assembly | C++ | Ratio (C++/ASM) |
|--------|----------|-----|-----------------|
| File size (unstripped) | 53,688 bytes | 1,036,152 bytes | 19.3x smaller |
| File size (stripped) | 51,968 bytes | 546,448 bytes | 10.5x smaller |
| __TEXT segment (vmsize) | 16,384 bytes | 393,216 bytes | 24.0x smaller |
| __TEXT __text (code) | 7,488 bytes | 345,468 bytes | 46.1x smaller |
| __DATA_CONST (vmsize) | 16,384 bytes | 16,384 bytes | 1.0x (same) |
| __DATA segment (vmsize) | 16,384 bytes | 16,384 bytes | 1.0x (same) |

## Segment Details (Assembly)

### __TEXT Segment (vmsize: 16,384 bytes = 1 x 16KB page)

| Section | Address | Size | Description |
|---------|---------|------|-------------|
| __text | 0x1000004e8 | 7,488 bytes (0x1d40) | Executable code |
| __stubs | 0x100002228 | 216 bytes (0xd8) | Dyld stubs |
| __stub_helper | 0x100002300 | 985 bytes (0x3d9) | Stub helper |
| **Total content** | | **8,689 bytes** | **53% of page utilized** |

### __DATA_CONST Segment (vmsize: 16,384 bytes = 1 x 16KB page)

| Section | Address | Size | Description |
|---------|---------|------|-------------|
| __got | 0x100004000 | 152 bytes (0x98) | Global offset table |

### __DATA Segment (vmsize: 16,384 bytes = 1 x 16KB page)

| Section | Address | Size | Description |
|---------|---------|------|-------------|
| __data | 0x100008000 | 292 bytes (0x124) | Mutable data (board, state) |

## Segment Details (C++)

### __TEXT Segment (vmsize: 393,216 bytes = 24 x 16KB pages)

| Section | Size | Description |
|---------|------|-------------|
| __text | 345,468 bytes (0x5457c) | Executable code |
| __unwind_info | 4,164 bytes (0x1044) | Unwind info |
| __eh_frame | 36 bytes (0x24) | Exception handling |
| __cstring | 19,504 bytes (0x4c30) | String constants |
| __gcc_except_tab | 5,762 bytes (0x1682) | GCC exception tables |
| __oslogstring | 584 bytes (0x248) | OS log strings |
| __stubs | 8,680 bytes (0x21e8) | Dyld stubs |

### __DATA_CONST Segment (vmsize: 16,384 bytes = 1 x 16KB page)

| Section | Size | Description |
|---------|------|-------------|
| __const | 3,080 bytes (0xc08) | Read-only data |
| __got | 2,376 bytes (0x948) | Global offset table |

### __DATA Segment (vmsize: 16,384 bytes = 1 x 16KB page)

| Section | Size | Description |
|---------|------|-------------|
| __la_symbol_ptr | 976 bytes (0x3d0) | Lazy symbol pointers |
| __data | 705 bytes (0x2c1) | Initialized data |
| __bss | 1,152 bytes (0x480) | Uninitialized data |

## Growth from Phase 2

| Metric | Phase 2 | Phase 3 | Growth |
|--------|---------|---------|--------|
| File size (unstripped) | 52,856 | 53,688 | +832 bytes (+1.6%) |
| File size (stripped) | 51,632 | 51,968 | +336 bytes (+0.7%) |
| Source lines | 2,790 | 4,008 | +1,218 lines (+43.7%) |
| __TEXT page count | 1 | 1 | No change (still fits in 1 page) |

## Notes

1. **__TEXT still fits in one 16KB page.** Despite adding 1,218 lines of source (ghost piece, hold, next preview, statistics panel, pause/resume), the executable code grew by only 832 bytes unstripped. The __text section uses 7,488 of 16,384 available bytes (46% utilization), leaving 7,648 bytes (47%) free for Phase 4 features.

2. **Stripped ratio is 10.5x.** The C++ binary is 10.5x larger than assembly when stripped, and 19.3x larger unstripped. The unstripped gap is wider because the C++ binary carries significantly more debug symbols.

3. **Code section ratio is 46.1x.** Comparing just the __text code sections (7,488 vs 345,468 bytes) shows the most dramatic difference. The C++ binary's code section alone is larger than the entire assembly binary file.

4. **Minimal code growth for maximum feature add.** Phase 3 added 5 major gameplay features (ghost, hold, next, stats, pause) but only increased stripped binary by 336 bytes (0.7%), demonstrating the density advantage of hand-written assembly.

5. **DATA segments identical.** Both binaries use exactly 1 page each for __DATA_CONST and __DATA, though the assembly version uses far less of each page (152 bytes GOT vs 2,376 bytes, 292 bytes data vs 2,833 bytes).
