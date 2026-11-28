; -- Long-sized arena / bump allocator for the llvm targets.
;    The allocator state is caller-owned: pass an Arena struct pointer to
;    every call, so any number of independent slabs can be managed at the
;    same time.
;    Allocations bump a pointer forward. Individual deallocations are not
;    supported; reset() frees everything in that arena at once.
;    Sizes are long values, and every allocation starts at a multiple of 8 bytes,
;    because the generated code expects floats, quads and pointers to be aligned to their size.

%option ignore_unused

arena {

    struct Arena {
        pointer base
        pointer next
        pointer end
    }

    sub init(^^Arena state, pointer base_addr, long size) {
        ; -- initialize the arena over the range [base_addr, base_addr + size)
        state.end = base_addr + size
        state.base = (base_addr + 7) & ~(7 as pointer)
        if state.base > state.end
            state.base = state.end
        state.next = state.base
    }

    sub alloc(^^Arena state, long size) -> pointer {
        ; -- allocate size bytes from the arena. Returns 0 if the slab is exhausted.
        ;    Sizes are rounded up to a multiple of 8, so that the next allocation is aligned as well.
        if size <= 0
            return 0
        size = (size + 7) & ~7
        if size > state.end - state.next
            return 0
        pointer result = state.next
        state.next += size
        return result
    }

    sub reset(^^Arena state) {
        ; -- reset the arena so the slab can be reused from the start
        state.next = state.base
    }
}
