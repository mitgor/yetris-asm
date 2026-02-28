# Phase 12: Deferred Items

## Pre-existing Issues (Not Caused by Current Changes)

1. **`_shuffle_bag` in random.s does not save x21 (callee-saved register)**
   - Line 50: `mov w21, w0` writes to callee-saved w21 without saving it in prologue
   - Only called from `_next_piece` which does not use x21, so no runtime impact
   - Technically an ABI violation -- a future caller that uses x21 across `bl _shuffle_bag` would see corruption
   - Fix: Add x21 to the stp prologue/epilogue pair (change `stp x20, x19` to include x21)
