# Phase 1: Foundation and Darwin ABI Scaffold - Research

**Researched:** 2026-02-26
**Domain:** AArch64 assembly on macOS Apple Silicon, Darwin ABI, ncurses interop, Makefile integration
**Confidence:** HIGH

## Summary

Phase 1 establishes the foundational assembly project: a working AArch64 assembly source file that assembles, links against system ncurses, code-signs, and runs on macOS Apple Silicon. The technical domain is well-understood because (a) Apple's toolchain (Clang-based `as` and `ld`) is mature and documented, (b) the Darwin ARM64 ABI is stable and verified against compiler output, and (c) the ncurses C library interface is simple to call from assembly via standard AAPCS64 calling conventions.

All critical patterns were verified on the target system by assembling, linking, and running test binaries. The Clang integrated assembler (`as`) and Apple `ld` linker produce ad-hoc-signed Mach-O arm64 binaries automatically. Calling ncurses functions from hand-written assembly works using `bl _functionname` with AAPCS64 register conventions, and accessing external global variables like `stdscr` requires GOT-indirect addressing (`@GOTPAGE` / `@GOTPAGEOFF`).

The Makefile integration is straightforward: add a separate `asm` target that assembles `.s` files in `asm/`, links them, and produces a binary in `asm/bin/`, completely independent of the existing C++ build rules.

**Primary recommendation:** Use `_main` as the entry point (not `_start`) and link with `-lSystem -lncurses` to get proper C runtime initialization, which ncurses depends on. Avoid raw syscalls for anything ncurses handles; reserve syscall knowledge for understanding and debugging only.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| FOUN-01 | AArch64 assembly project builds and runs on macOS Apple Silicon using Apple `as` and `ld` | Verified: `as -o file.o file.s` + `ld -o binary file.o -lSystem -syslibroot $(xcrun --show-sdk-path) -arch arm64` produces runnable Mach-O binary. See Standard Stack and Code Examples sections. |
| FOUN-02 | Binary links against system ncurses and initializes/cleans up terminal correctly | Verified: `-lncurses` links against system ncurses .tbd stub. `bl _initscr` / `bl _endwin` calls work. `stdscr` accessible via `@GOTPAGE`/`@GOTPAGEOFF`. See Code Examples section. |
| FOUN-03 | Darwin ABI conventions are correct (x16 syscalls, svc #0x80, x18 reserved, 16-byte stack alignment, underscore prefixes) | All 9 Darwin ABI rules documented in Architecture Patterns. Verified by inspecting compiler-generated assembly and running hand-written test binaries. |
| FOUN-04 | Makefile builds assembly source files in asm/ directory alongside existing C++ in src/ | Existing Makefile analyzed. New `asm` target with independent pattern rules will not conflict. See Architecture Patterns for Makefile structure. |
</phase_requirements>

## Standard Stack

### Core

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Apple `as` (Clang integrated assembler) | clang 17.0.0 (clang-1700.6.3.2) | Assemble `.s` files to Mach-O object files | Only assembler on macOS; `as` invokes Clang's integrated assembler. GNU `as` syntax is not available. |
| Apple `ld` | ld-1230.1 | Link object files into Mach-O executables | System linker; handles `-lSystem`, `-lncurses`, `-syslibroot`, auto ad-hoc codesigning |
| System ncurses | 5.4 (via libncurses.tbd) | Terminal I/O: screen init, character input, cursor control, color | System-provided on macOS; project constraint says "use ncurses as-is" |
| `codesign` (automatic) | System | Ad-hoc signing of ARM64 binaries | Apple `ld` automatically ad-hoc signs arm64 binaries; no manual codesign step needed |
| GNU Make | System | Build orchestration | Already used by the C++ project |

### Supporting

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| `xcrun` | Xcode CLI | Locate SDK path dynamically | Always: `xcrun --show-sdk-path` in Makefile to find `-syslibroot` |
| `otool` | System | Inspect Mach-O headers, load commands, disassembly | Debugging: verify binary structure, check linked libraries |
| `nm` | System | List symbols in object files and binaries | Debugging: verify symbol names, check undefined references |
| `file` | System | Verify binary type (Mach-O 64-bit executable arm64) | Quick verification after build |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `_main` entry via `-lSystem` | `_start` entry via `-e _start` | `_start` avoids C runtime but ncurses requires C library initialization; `_main` is required |
| `-lncurses` (unversioned symbols) | `$NCURSES60` versioned symbols | Compiler generates versioned calls; hand-written assembly can use unversioned symbols which resolve fine. Simpler. |
| `as` directly | `clang -c` for .s files | Identical backend (both invoke Clang integrated assembler). `as` is more explicit about intent. |

## Architecture Patterns

### Recommended Project Structure

```
yetris/
├── asm/                    # Assembly source and build output
│   ├── main.s              # Entry point, ncurses init/cleanup
│   ├── bin/                # Build output directory
│   │   └── yetris-asm      # Linked Mach-O binary
│   └── *.o                 # Object files (in .gitignore)
├── src/                    # Existing C++ source (unchanged)
├── bin/                    # Existing C++ binary output
├── Makefile                # Extended with `asm` target
└── ...
```

### Pattern 1: Darwin ARM64 ABI Rules (All 9 Critical Conventions)

**What:** The complete set of Darwin-specific ARM64 conventions that must be correct from the first source file.
**When to use:** Every assembly source file in the project.

**Rule 1 - Underscore-prefixed symbols:** All C-visible symbols must be prefixed with `_`. Functions: `_main`, `_initscr`, `_endwin`. Globals: `_stdscr`.

**Rule 2 - x16 for syscalls:** Place the syscall number in x16 (not x8 as on Linux). On ARM64 macOS, raw Unix numbers are used (1=exit, 4=write) -- NOT the 0x2000000 offset used on x86_64 macOS.

**Rule 3 - svc #0x80 for syscall invocation:** Use `svc #0x80` to trap into the kernel. The literal 0x80 is convention but the CPU ignores the immediate; the kernel reads x16.

**Rule 4 - x18 is reserved:** NEVER use x18 for any purpose. Apple reserves it for platform use (thread-local storage, kernel pointers). Using x18 causes crashes. Libraries like GMP have hit this exact bug.

**Rule 5 - 16-byte stack alignment:** SP must be 16-byte aligned at all times, especially before any `bl` instruction. Violation causes SIGBUS. Always allocate stack in multiples of 16.

**Rule 6 - Frame pointer (x29) must be valid:** x29 must always point to a valid frame record (saved x29 + saved x30 pair). Required for debuggers and crash reporters.

**Rule 7 - adrp+add for local data:** Use `adrp xN, label@PAGE` + `add xN, xN, label@PAGEOFF` to load addresses of symbols in the same binary.

**Rule 8 - GOT-indirect for external symbols:** Use `adrp xN, _symbol@GOTPAGE` + `ldr xN, [xN, _symbol@GOTPAGEOFF]` to access symbols from dynamic libraries (e.g., `_stdscr` from ncurses). The loaded value is a pointer to the symbol, which must then be dereferenced.

**Rule 9 - Variadic functions pass args on stack (NOT registers):** On Darwin ARM64, variadic functions like `printw` (which is `printf`-like) pass the first fixed argument in x0, but all variadic arguments go on the stack. This differs from Linux ARM64 where all args go in registers. Non-variadic ncurses functions (initscr, endwin, cbreak, noecho, getch) pass arguments normally in x0-x7.

### Pattern 2: Function Prologue/Epilogue

**What:** Standard stack frame setup for functions that call other functions.
**When to use:** Every function that uses `bl` (branch with link).

```asm
// Source: Verified against clang -S output on target system
_my_function:
    // Prologue: save frame pointer + link register (+ any callee-saved regs)
    stp x29, x30, [sp, #-16]!      // push fp and lr, decrement sp by 16
    mov x29, sp                      // set frame pointer

    // ... function body (bl calls safe here) ...

    // Epilogue: restore and return
    ldp x29, x30, [sp], #16         // pop fp and lr, increment sp by 16
    ret
```

For functions that also save callee-saved registers (x19-x28):

```asm
// Source: Verified against clang -S -O1 output for ncurses program
_my_function:
    stp x20, x19, [sp, #-32]!      // save callee-saved regs first
    stp x29, x30, [sp, #16]         // save fp + lr at top of frame
    add x29, sp, #16                 // frame pointer points to saved fp/lr pair

    // ... function body, x19/x20 are now safe to use ...

    ldp x29, x30, [sp, #16]         // restore fp + lr
    ldp x20, x19, [sp], #32         // restore callee-saved regs and deallocate
    ret
```

### Pattern 3: Makefile Integration

**What:** Adding an `asm` target to the existing Makefile without breaking the C++ build.
**When to use:** FOUN-04 implementation.

```makefile
# --- Assembly build (appended to existing Makefile) ---
ASM_DIR     = asm
ASM_BIN_DIR = $(ASM_DIR)/bin
ASM_EXE     = $(ASM_BIN_DIR)/yetris-asm
ASM_SOURCES = $(wildcard $(ASM_DIR)/*.s)
ASM_OBJECTS = $(ASM_SOURCES:.s=.o)
SDK_PATH    = $(shell xcrun --show-sdk-path)

$(ASM_DIR)/%.o: $(ASM_DIR)/%.s
	# Assembling $<...
	$(MUTE)as -o $@ $<

$(ASM_EXE): $(ASM_OBJECTS) | $(ASM_BIN_DIR)
	# Linking assembly binary...
	$(MUTE)ld -o $@ $(ASM_OBJECTS) -lncurses -lSystem \
		-syslibroot $(SDK_PATH) -arch arm64

$(ASM_BIN_DIR):
	$(MUTE)mkdir -p $(ASM_BIN_DIR)

asm: $(ASM_EXE)
	# Assembly build successful!

asm-clean:
	$(MUTE)rm -f $(ASM_OBJECTS) $(ASM_EXE)

asm-run: asm
	$(MUTE)./$(ASM_EXE)

.PHONY: asm asm-clean asm-run
```

**Key design points:**
- `asm` target is completely independent of the `all` target
- Pattern rule `$(ASM_DIR)/%.o: $(ASM_DIR)/%.s` handles any number of `.s` files
- `SDK_PATH` uses `xcrun` for portability across Xcode versions
- No `-e` flag needed because `_main` is the default entry point when linking with `-lSystem`
- Linker auto-signs the binary (no `codesign` step)

### Anti-Patterns to Avoid

- **Using `_start` entry point with ncurses:** ncurses depends on C runtime initialization (locale, memory allocation setup). If you use `_start` instead of `_main`, you skip C runtime init and ncurses will crash or behave unpredictably. Always use `_main` and link with `-lSystem`.
- **Using x18 for scratch work:** Will crash. Apple uses x18 for internal platform purposes. Use x9-x15 for scratch (caller-saved) or x19-x28 for preserved values (callee-saved).
- **Hardcoding SDK path:** Never hardcode `/Applications/Xcode.app/...` -- use `$(shell xcrun --show-sdk-path)` which resolves correctly across Xcode and Command Line Tools installations.
- **Using 0x2000000 offset for syscall numbers on ARM64:** The 0x2000000 class offset is x86_64 only. On ARM64 macOS, use raw Unix syscall numbers directly (1=exit, 4=write).
- **Passing variadic arguments in registers:** On Darwin ARM64, variadic args beyond the fixed parameters must go on the stack. This is different from Linux ARM64. If you call `printw(fmt, arg1, arg2)`, `fmt` goes in x0 but `arg1` and `arg2` must be stored to the stack at [sp], [sp+8], etc.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Terminal initialization | Custom termios/ioctl setup | `bl _initscr` / `bl _endwin` | ncurses handles hundreds of terminal type variations, signal handlers, and cleanup |
| Key input handling | Raw `read()` syscall + escape sequence parsing | `bl _getch` / `bl _wgetch` | Escape sequences for arrow keys, function keys, resize events are complex and terminal-dependent |
| Screen output | `write()` syscalls with ANSI escape codes | `bl _printw` / `bl _mvprintw` / `bl _wrefresh` | ncurses handles buffering, partial updates, and terminal-specific output sequences |
| Color support | ANSI color code strings | `bl _start_color` / `bl _init_pair` / `bl _attron` | Terminal color capability detection is handled by ncurses terminfo |
| Codesigning | Manual `codesign -s -` step | Linker automatic ad-hoc signing | Apple's `ld` auto-signs arm64 binaries since Big Sur; adding a manual step is redundant |

**Key insight:** The entire point of using ncurses is to avoid reimplementing terminal abstraction. From assembly, ncurses functions are just `bl _functionname` calls with arguments in registers. The ABI overhead is zero -- you're calling the exact same machine code a C program would.

## Common Pitfalls

### Pitfall 1: Stack Misalignment Before Function Calls

**What goes wrong:** SIGBUS crash when calling any C library function, with no clear error message.
**Why it happens:** ARM64 requires 16-byte aligned SP. If you push an odd number of registers or subtract a non-multiple-of-16 from SP, the next `bl` crashes.
**How to avoid:** Always allocate stack space in multiples of 16. Pair register saves: `stp x29, x30, [sp, #-16]!` saves two registers and maintains alignment. If you need to save an odd register, pair it with xzr or another register.
**Warning signs:** SIGBUS at the first `bl` instruction in a function.

### Pitfall 2: Missing Underscore Prefix on Symbol Names

**What goes wrong:** "Undefined symbols" linker error for functions that clearly exist in the library.
**Why it happens:** Darwin's C ABI prepends `_` to all symbol names. Writing `bl initscr` instead of `bl _initscr` fails at link time.
**How to avoid:** Always prefix external C function names and global variables with `_`. Internal assembly-only labels (like `loop:` or `done:`) do not need the prefix.
**Warning signs:** Linker errors mentioning "Undefined symbols for architecture arm64".

### Pitfall 3: Forgetting GOT Indirection for External Globals

**What goes wrong:** Assembler or linker error when trying to access `stdscr` with `@PAGE`/`@PAGEOFF`.
**Why it happens:** `stdscr` lives in libncurses (a dynamic library). Its address isn't known at link time. You must go through the Global Offset Table.
**How to avoid:** Use `@GOTPAGE`/`@GOTPAGEOFF` for any symbol from a dynamic library. The result is a pointer TO the variable, not the variable itself -- dereference with an additional `ldr`.
**Warning signs:** Relocation errors mentioning "GOT" or "PIC".

### Pitfall 4: Using x18 Register

**What goes wrong:** Seemingly random crashes, corrupted thread state, or security violations.
**Why it happens:** Apple reserves x18 for platform use. Writing to it corrupts internal OS state.
**How to avoid:** Never use x18. Period. Use x9-x15 for temporaries, x19-x28 for callee-saved values.
**Warning signs:** Crashes that don't reproduce deterministically, or crash logs mentioning x18.

### Pitfall 5: ncurses `refresh()` Is Actually `wrefresh(stdscr)`

**What goes wrong:** Confusion about how to call `refresh()` from assembly. There is no standalone `_refresh` function in modern ncurses -- it's a macro that expands to `wrefresh(stdscr)`.
**Why it happens:** Many ncurses "functions" are actually macros in curses.h. From assembly, you must call the underlying function directly.
**How to avoid:** For `refresh()`, load `stdscr` via GOT indirection, then call `bl _wrefresh` with the WINDOW pointer in x0. Similarly, `getch()` is `wgetch(stdscr)`. The compiler output (from `cc -S`) reveals the actual function names: `_wrefresh`, `_wgetch`, `_printw`.
**Warning signs:** Undefined symbol errors for `_refresh` or `_getch` at link time. (Note: both `_getch` and `_wgetch` are exported by the system ncurses -- `_getch` does exist as a real function, not just a macro, in macOS's ncurses. However, the pattern of loading stdscr and calling `_wrefresh` is the correct explicit approach.)

### Pitfall 6: Variadic Function Calling Convention on Darwin ARM64

**What goes wrong:** `printw` prints garbage or crashes when given format arguments.
**Why it happens:** Darwin ARM64 requires variadic arguments (everything after the `...` in the prototype) to be passed on the stack, not in registers. This is unique to Apple's ARM64 ABI.
**How to avoid:** For `printw(fmt, ...)`, put the format string pointer in x0, then store each variadic argument at [sp], [sp+8], [sp+16], etc. Allocate stack space before storing.
**Warning signs:** Correct format string but wrong values printed, or crashes in printf-family functions.

## Code Examples

Verified patterns from assembling, linking, and running on the target system (macOS 26.3, Apple Silicon arm64).

### Complete ncurses Hello World (Verified Working)

```asm
// Source: Hand-written and verified on target system 2026-02-26
// Build: as -o main.o main.s && ld -o yetris-asm main.o -lncurses -lSystem -syslibroot $(xcrun --show-sdk-path) -arch arm64
.section __TEXT,__text,regular,pure_instructions
.globl _main
.p2align 2

_main:
    // Prologue: save callee-saved x19 + frame pointer + link register
    stp x20, x19, [sp, #-32]!
    stp x29, x30, [sp, #16]
    add x29, sp, #16

    // Initialize ncurses
    bl _initscr                     // WINDOW *initscr(void) -> returns in x0

    // Set input modes
    bl _cbreak                      // int cbreak(void) -> disable line buffering
    bl _noecho                      // int noecho(void) -> don't echo input

    // Print text: printw(fmt) -- non-variadic single-arg call, fmt in x0
    adrp x0, hello_str@PAGE
    add x0, x0, hello_str@PAGEOFF
    bl _printw

    // Refresh screen: wrefresh(stdscr)
    adrp x19, _stdscr@GOTPAGE          // load GOT entry page
    ldr x19, [x19, _stdscr@GOTPAGEOFF] // load pointer to stdscr variable
    ldr x0, [x19]                       // dereference: x0 = stdscr value (WINDOW *)
    bl _wrefresh

    // Wait for keypress: wgetch(stdscr)
    ldr x0, [x19]                       // reload stdscr (callee may have clobbered x0)
    bl _wgetch

    // Clean up terminal
    bl _endwin

    // Return 0
    mov w0, #0
    ldp x29, x30, [sp, #16]
    ldp x20, x19, [sp], #32
    ret

// Read-only string data
.section __TEXT,__cstring,cstring_literals
hello_str:
    .asciz "Hello from ARM64 assembly! Press any key to exit..."

.subsections_via_symbols
```

### GOT-Indirect Access for External Globals

```asm
// Source: Verified by inspecting clang -S -O1 output and testing
// Pattern: accessing _stdscr from libncurses (dynamic library)

    adrp x19, _stdscr@GOTPAGE          // Step 1: page of GOT entry
    ldr x19, [x19, _stdscr@GOTPAGEOFF] // Step 2: load GOT entry (pointer to _stdscr)
    ldr x0, [x19]                       // Step 3: dereference to get WINDOW *
    bl _wrefresh                         // Step 4: pass WINDOW * as first argument
```

### Local Data Access (Same Binary)

```asm
// Source: Standard adrp+add pattern for accessing data in same binary
// Pattern: loading address of a string in __TEXT,__cstring

    adrp x0, my_string@PAGE            // load 4KB page containing my_string
    add x0, x0, my_string@PAGEOFF      // add offset within page
    // x0 now holds the address of my_string
```

### Raw Syscall (For Understanding Only -- Use C Library Instead)

```asm
// Source: Verified working on target system 2026-02-26
// NOTE: Prefer C library functions over raw syscalls for stability.
// Apple considers syscall numbers private and subject to change.

    // write(fd=1, buf, len)
    mov x0, #1                         // fd = stdout
    adrp x1, msg@PAGE
    add x1, x1, msg@PAGEOFF
    mov x2, #13                        // length
    mov x16, #4                        // SYS_write (raw number, NOT 0x2000004)
    svc #0x80                           // invoke kernel

    // exit(0)
    mov x0, #0                         // exit code
    mov x16, #1                        // SYS_exit
    svc #0x80
```

### Section Directives for Mach-O

```asm
// Code section (executable instructions)
.section __TEXT,__text,regular,pure_instructions

// Read-only C string literals
.section __TEXT,__cstring,cstring_literals

// Writable initialized data
.section __DATA,__data

// Writable uninitialized data (BSS)
.section __DATA,__bss
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| GNU `as` syntax on macOS | Clang integrated assembler (LLVM) | macOS 11 / Xcode 12 (2020) | Syntax differences: `.p2align` preferred over `.align`, lowercase directives required |
| Manual `codesign -s -` after build | Linker auto ad-hoc signs arm64 | macOS 11 Big Sur (2020) | No manual codesign step needed; linker handles it |
| 0x2000000 syscall number offset | Raw Unix numbers on ARM64 | Apple Silicon launch (2020) | The class-offset scheme was x86_64-only; ARM64 uses raw numbers in x16 |
| `/usr/lib/libncurses.dylib` | `.tbd` stubs in SDK (actual dylib in dyld cache) | macOS 11+ | Must use `-syslibroot` with SDK path; direct `/usr/lib` paths don't work |

**Deprecated/outdated:**
- GNU `as` ARM64 syntax (e.g., uppercase `MOV`, `LDR =label` pseudo-instruction): Does not work with Apple's Clang-based assembler. Use lowercase instructions and `adrp`+`add` addressing.
- Direct syscalls for application code: Apple explicitly warns that Darwin syscall numbers are private API. Use C library wrappers (`_write`, `_exit`) for anything that needs stability. Raw syscalls are acceptable only for understanding the platform.

## Open Questions

1. **ncurses macro vs function availability**
   - What we know: `_initscr`, `_endwin`, `_cbreak`, `_noecho`, `_printw`, `_wrefresh`, `_wgetch` are all real exported symbols. `_getch` and `_refresh` also exist as real functions in macOS ncurses (not just macros).
   - What's unclear: Whether all ncurses "convenience" functions (e.g., `mvaddch`, `attron`, `color_set`) are real symbols or require calling the `w`-prefixed variant with explicit WINDOW argument. This matters in later phases (Phase 2+).
   - Recommendation: For Phase 1, use the verified set above. In Phase 2, run `nm -g $(xcrun --show-sdk-path)/usr/lib/libncurses.tbd | grep _functionname` to check any new function before using it.

2. **ncurses versioned vs unversioned symbols**
   - What we know: macOS ncurses exports both `_initscr` and `_initscr$NCURSES60`. The compiler generates calls to the versioned variants. Hand-written assembly calling unversioned symbols links and runs correctly.
   - What's unclear: Whether Apple will eventually remove unversioned symbols in a future macOS release.
   - Recommendation: Use unversioned symbols for simplicity. If linking breaks in a future OS update, switch to `$NCURSES60` suffixed names. This is a LOW-risk concern.

## Sources

### Primary (HIGH confidence)

- Compiler output analysis: `cc -S -O1 test_ncurses.c -o test_ncurses.s` on target system (macOS 26.3, arm64) -- reveals exact calling patterns, GOT access syntax, section directives, and ncurses symbol names
- Hand-written test binaries: assembled, linked, and executed on target system to verify every pattern documented above
- System toolchain versions: `as --version` (clang 17.0.0), `ld -v` (ld-1230.1), verified on target
- [Apple Developer Documentation: Writing ARM64 code for Apple platforms](https://developer.apple.com/documentation/xcode/writing-arm64-code-for-apple-platforms) -- x18 reservation, stack alignment, frame pointer requirements
- [ARM AAPCS64 Specification](https://github.com/ARM-software/abi-aa/blob/main/aapcs64/aapcs64.rst) -- Official calling convention, register usage, stack frame layout

### Secondary (MEDIUM confidence)

- [HelloSilicon GitHub repository](https://github.com/below/HelloSilicon) -- ARM64 assembly tutorial for Apple Silicon, build commands, Darwin ABI notes
- [Variadic Functions on ARM64 macOS](https://cpufun.substack.com/p/what-about-) -- Detailed analysis of Darwin's stack-based variadic argument passing with code examples
- [Apple Developer Forums: linker and _main entry](https://developer.apple.com/forums/thread/669094) -- `-lSystem` linking, LC_MAIN, entry point conventions
- [M1 macOS ARM64 syscalls gist](https://gist.github.com/zeusdeux/bb5b5b0aac1a39d4f9cec0d4f9a44ffb) -- Raw syscall example confirming x16 register and svc #0x80 convention
- [Reproducible codesigning on Apple Silicon](https://www.smileykeith.com/2021/10/05/codesign-m1/) -- Confirms linker auto ad-hoc signs arm64 binaries
- [GMP x18 bug report](https://gpgtools.tenderapp.com/discussions/problems/127546-patch-gmplib-to-not-use-reserved-x18-registers-on-darwin-apple-silicon) -- Real-world x18 crash evidence

### Tertiary (LOW confidence)

- None -- all findings verified against compiler output or test execution on target system

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All tools verified on target system with version numbers
- Architecture: HIGH - Every pattern verified by assembling, linking, and/or running test binaries on target
- Pitfalls: HIGH - Each pitfall documented from verified behavior (compiler output, test execution, or known bug reports)

**Research date:** 2026-02-26
**Valid until:** Indefinite for Darwin ABI fundamentals (stable since Apple Silicon launch 2020). Re-verify toolchain versions if Xcode updates.
