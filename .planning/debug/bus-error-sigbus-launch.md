---
status: diagnosed
trigger: "ARM64 assembly Tetris game crashes with Bus error: 10 (SIGBUS) immediately on launch"
created: 2026-02-26T00:00:00Z
updated: 2026-02-26T00:05:00Z
---

## Current Focus

hypothesis: CONFIRMED - _get_time_ms passes sp (which holds saved x29/x30) as the timeval buffer to gettimeofday, which overwrites the saved return address
test: Step through _get_time_ms instruction by instruction in lldb
expecting: gettimeofday writes tv_sec/tv_usec over saved x29/x30 at [sp], ldp restores garbage, ret jumps to garbage
next_action: Report root cause

## Symptoms

expected: Game launches and displays Tetris board in terminal
actual: Immediate crash with "Bus error: 10" (SIGBUS) / EXC_BAD_ACCESS
errors: SIGBUS signal, EXC_BAD_ACCESS (code=257)
reproduction: make asm-run (runs ./asm/bin/yetris-asm)
started: After rewriting main.s game loop

## Eliminated

- hypothesis: Crash before _main (dyld, constructor)
  evidence: Breakpoint at _main hits successfully; all init functions through _spawn_piece complete without error
  timestamp: 2026-02-26T00:03:00Z

- hypothesis: Stack frame corruption in render.s nested stp pattern
  evidence: Crash occurs at _get_time_ms (before any render calls). render.s never executes.
  timestamp: 2026-02-26T00:03:00Z

## Evidence

- timestamp: 2026-02-26T00:02:00Z
  checked: lldb run with stdout redirect, stepping through _main init sequence
  found: Crash occurs when stepping over "bl _get_time_ms" (8th init call). All prior calls (initscr, cbreak, noecho, init_colors, init_input, reset_board, spawn_piece) succeed with SP and FP intact.
  implication: Bug is in _get_time_ms, not in any other init function

- timestamp: 2026-02-26T00:04:00Z
  checked: Instruction-level stepping through _get_time_ms
  found: |
    Stack layout after prologue:
      SP = 0x16fdfea40 (decremented by 32)
      [SP+0]  = saved x29 (0x16fdfea60)
      [SP+8]  = saved x30 (0x1000009e4 = main+52, the return address)
      [SP+16] = frame pointer location (x29 set to SP+16 = 0x16fdfea50)

    Then: mov x0, sp  =>  x0 = 0x16fdfea40
    Then: bl _gettimeofday  =>  writes struct timeval to [x0]:
      [SP+0] = tv_sec  = 0x69a0aa21 (overwrites saved x29!)
      [SP+8] = tv_usec = 0x000bc42e (overwrites saved x30/lr!)

    Then: ldp x29,x30,[sp],#0x20  =>  restores GARBAGE:
      x29 = 0x69a0aa21 (was tv_sec)
      x30 = 0x000bc42e (was tv_usec)

    Then: ret  =>  jumps to x30 = 0x1000bc42e  =>  EXC_BAD_ACCESS (unmapped memory)
  implication: CONFIRMED ROOT CAUSE

## Resolution

root_cause: |
  In asm/timer.s _get_time_ms, the struct timeval buffer overlaps with the saved x29/x30 on the stack.

  The prologue does: stp x29,x30,[sp,#-32]!  => saves x29 at [SP+0], x30 at [SP+8]
  Then sets: x29 = sp + 16 (frame pointer at [SP+16])
  Then passes: x0 = sp  => gettimeofday writes timeval at [SP+0]

  struct timeval is { time_t tv_sec (8 bytes at +0), suseconds_t tv_usec (4 bytes at +8) }.
  gettimeofday writes tv_sec to [SP+0..7] and tv_usec to [SP+8..11], which overwrites
  the saved x29 and x30 that were stored at [SP+0] and [SP+8].

  When the epilogue does ldp x29,x30,[sp],#32 it restores the Unix timestamp as x29
  and microseconds as x30 (the return address), causing ret to jump to a garbage address.
fix:
verification:
files_changed: []
