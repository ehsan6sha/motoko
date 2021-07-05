// This module is only enabled when compiling the RTS for IC or WASI.

use super::Memory;
use crate::constants::WASM_PAGE_SIZE;
use crate::rts_trap_with;
use crate::types::*;

use core::arch::wasm32;

/// Maximum live data retained in a GC.
pub(crate) static mut MAX_LIVE: Bytes<u32> = Bytes(0);

/// Amount of garbage collected so far.
pub(crate) static mut RECLAIMED: Bytes<u64> = Bytes(0);

/// Counter for total allocations
pub(crate) static mut ALLOCATED: Bytes<u64> = Bytes(0);

/// Heap pointer
pub(crate) static mut HP: u32 = 0;

/// Heap pointer after last GC
pub(crate) static mut LAST_HP: u32 = 0;

// Provided by generated code
extern "C" {
    pub(crate) fn get_heap_base() -> u32;
    pub(crate) fn get_static_roots() -> SkewedPtr;
}

#[no_mangle]
unsafe extern "C" fn init() {
    HP = get_heap_base() as u32;
    LAST_HP = HP;
}

#[no_mangle]
unsafe extern "C" fn get_max_live_size() -> Bytes<u32> {
    MAX_LIVE
}

#[no_mangle]
unsafe extern "C" fn get_reclaimed() -> Bytes<u64> {
    RECLAIMED
}

#[no_mangle]
unsafe extern "C" fn get_total_allocations() -> Bytes<u64> {
    ALLOCATED
}

#[no_mangle]
unsafe extern "C" fn get_heap_size() -> Bytes<u32> {
    Bytes(HP - get_heap_base())
}

/// Provides a `Memory` implementation, to be used in functions compiled for IC or WASI. The
/// `Memory` implementation allocates in Wasm heap with Wasm `memory.grow` instruction.
pub struct IcMemory;

impl Memory for IcMemory {
    #[inline]
    unsafe fn alloc_words(&mut self, n: Words<u32>) -> SkewedPtr {
        let bytes = n.to_bytes();
        // Update ALLOCATED
        ALLOCATED += Bytes(bytes.0 as u64);

        // Update heap pointer
        let old_hp = HP;
        let new_hp = old_hp + bytes.0;
        HP = new_hp;

        // Grow memory if needed
        grow_memory(new_hp as usize);

        skew(old_hp as usize)
    }
}

/// Page allocation. Ensures that the memory up to, but excluding, the given pointer is allocated.
#[inline(never)]
unsafe fn grow_memory(ptr: usize) {
    let page_size = u64::from(WASM_PAGE_SIZE.0);
    let total_pages_needed = (((ptr as u64) + page_size - 1) / page_size) as usize;
    let current_pages = wasm32::memory_size(0);
    if total_pages_needed > current_pages {
        if wasm32::memory_grow(0, total_pages_needed - current_pages) == core::usize::MAX {
            rts_trap_with("Cannot grow memory");
        }
    }
}
