# Deferred Items - Phase 02

## Out-of-Scope Issues Discovered

1. **Untracked render.s has assembler errors** (found during 02-02 Task 2)
   - `asm/render.s` is an untracked file with label naming errors (uses `_` prefixed labels for local branches instead of `L` prefixed assembler-local labels)
   - This prevents `make asm` from succeeding since the Makefile wildcard picks up all `.s` files
   - Belongs to plan 02-03 (rendering/input) -- will be fixed when that plan executes
   - Workaround: manual linking of committed files works correctly
