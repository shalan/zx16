# ZX16 Memory Map & Optional Page Window

**Status:** Proposed ISA / ABI annex (v2 map)  
**Scope:** Base address map (required), ABI rules, and an **optional** external page window.  
**Not in scope:** QSPI pinout, flash command set, PSRAM timing, or a full MMU.

---

## 1. Design principles

1. **64 KB flat CPU address space** (`0x0000`–`0xFFFF`), little-endian, byte-addressable.
2. **Base ISA and ABI must work on a machine that has no page window** and no external paged flash/PSRAM.
3. **On-chip memory is expensive** → platforms may use a **small SRAM** plus **fixed XIP flash**; that is a backend choice under the base map.
4. **The third 16 KB (`0x8000`–`0xBFFF`) is optional paging.** When absent, portable software simply never uses that range.
5. **Banking (when present) is not virtual memory.** It is address decode + MMIO select + software policy.
6. **`0xC000`–`0xFFFF` is reserved for MMIO and VRAM** (machine submap). Not general RAM.

---

## 2. Base memory map (normative for ISA & ABI)

This is all that **portable** software, the **standard ABI**, and **default toolchains** may assume.

| Range | Size | Role |
|:------|-----:|:-----|
| `0x0000`–`0x001F` | 32 B | Interrupt vector table |
| `0x0020`–`0x7FFF` | ~32 KB − 32 B | **General memory** — code, data, heap, stack |
| `0x8000`–`0xBFFF` | 16 KB | **Not part of the base ABI** — see §4 |
| `0xC000`–`0xFFFF` | 16 KB | **Reserved: MMIO + VRAM** (platform-defined) |

```text
0x0000 ┌──────────────────────────────┐
       │  IVT                         │  32 B
0x0020 ├──────────────────────────────┤
       │  General memory              │  through 0x7FFF
       │  (code / data / heap / stack)│  ★ base ISA & ABI only need this
0x8000 ├──────────────────────────────┤
       │  OPTIONAL page window        │  absent on minimal machines
0xC000 ├──────────────────────────────┤
       │  MMIO + VRAM (reserved)      │  always reserved, not general RAM
0xFFFF └──────────────────────────────┘
```

### 2.1 What “general memory” may be physically

The base map does **not** require that `0x0000`–`0x7FFF` be a single SRAM technology. A compliant machine may implement, for example:

| Subrange (example) | Backend |
|--------------------|---------|
| `0x0000`–`0x3FFF` | Fixed QSPI XIP flash |
| `0x4000`–`0x7FFF` | On-chip SRAM (8 KB or 16 KB decoded) |

Or a teaching sim may implement the whole low 32 KB as RAM.  
**Architecturally** it is one **general-memory region** for the ABI: addresses, SP, and relocatable code/data live here.

### 2.2 Reduced SRAM within general memory

If only **8 KB** of on-chip SRAM exists (e.g. decoded at `0x4000`–`0x5FFF`), RW data and the stack must stay in that implemented slice. Unimplemented holes in `0x0000`–`0x7FFF` are **implementation-defined** (open bus, alias, bus error). The ABI still uses the same **SP-at-top-of-implemented-RAM** idea (§3).

### 2.3 Device region

| Range | Rule |
|-------|------|
| `0xC000`–`0xFFFF` | Reserved for MMIO and VRAM. **No** portable `.text` / general `.data` / stack. Submap is machine-defined. |

---

## 3. Base ABI (no page window required)

These rules are **mandatory** for portable ZX16 software and default crt0/compiler output.

| Item | Base ABI rule |
|------|----------------|
| **Code / RO data** | Linked only in **general memory** (`0x0000`–`0x7FFF`), subject to machine flash/RAM split |
| **`.data` / `.bss` / heap** | Same; never in `0xC000`–`0xFFFF` |
| **Stack** | In general memory only; grows down |
| **SP reset** | One word past the top of **implemented** general RAM used for the stack (see below) |
| **PC reset** | `0x0000` (vector 0), or machine entry (e.g. `0x0020`) as documented by the profile |
| **Calls / leaf frames** | Standard `ra` / stack; **no** bank save/restore in the base ABI |
| **Libraries** | Must not reference `PAGE_*` or addresses ≥ `0x8000` unless built for an **extended** ABI |

### 3.1 Recommended SP reset (base)

When general memory for stack tops at `0x7FFF` (full low 32 KB usable as RAM, or SRAM filling `0x4000`–`0x7FFF`):

| Item | Value |
|------|--------|
| **SP** | `0x8000` |
| First `PUSH` | `0x7FFE`–`0x7FFF` |

If stack RAM ends lower (e.g. 8 KB at `0x4000`–`0x5FFF`):

| Item | Value |
|------|--------|
| **SP** | `0x6000` |
| First `PUSH` | `0x5FFE`–`0x5FFF` |

SP is **never** required to point into `0x8000`–`0xBFFF` or into MMIO.

### 3.2 What the base ABI must **not** assume

- Existence of `PAGE_SEL`, `PAGE_SRC`, or any paging MMIO  
- That loads/stores in `0x8000`–`0xBFFF` succeed  
- That external PSRAM or paged flash exists  
- That more than ~32 KB of general memory is available  

Programs that need the page window use an **optional extended profile** (§4–5), not the default ABI.

---

## 4. Optional region: `0x8000`–`0xBFFF`

| If the machine… | Then `0x8000`–`0xBFFF` is… |
|-----------------|----------------------------|
| **Minimal / base-only** | **Unimplemented or reserved.** Access is implementation-defined (bus error, open bus, ignore). **Portable code must not use it.** |
| **Extended (paging)** | A **page window**: fixed CPU window, bank selected by MMIO (§5). |

**ISA stance:** The range exists in the **address space diagram** as “optional external page window / reserved.”  
**ABI stance:** **Out of bounds** for the standard calling convention and default linker script (`MAX_GENERAL = 0x8000`).

Default linker / assembler for the base profile:

- Allow sections only in `0x0000`–`0x7FFF` (plus explicit device sections if any).  
- **Error** (or hard warning) if portable objects place symbols in `0x8000`–`0xBFFF` or `0xC000`–`0xFFFF` (except documented VRAM init tools).

---

## 5. Page window extension (optional)

Only for machines that implement paging. **Not required for ISA compliance or base ABI.**

### 5.1 Idea

When present, CPU addresses **`0x8000`–`0xBFFF`** hit one **16 KB window**.  
Physical slice is selected by MMIO — **decode + registers + software**, not an MMU.

### 5.2 Registers (extension; machine places them in `0xC000`–`0xFFFF`)

| Name | Access | Description |
|------|--------|-------------|
| **PAGE_SEL** | R/W | Bank index \(n\) |
| **PAGE_SRC** | R/W | `0` = external flash (XIP), `1` = PSRAM (others reserved) |

Optional: **PAGE_PROT**, **PAGE_STAT**.

Exact addresses are **machine-defined**. Base software never references them.

### 5.3 Decode equation (when implemented)

```text
WINDOW_BASE = 0x8000
WINDOW_SIZE = 0x4000          # 16 KB

if WINDOW_BASE <= addr <= WINDOW_BASE + WINDOW_SIZE - 1:
    offset = addr - WINDOW_BASE
    phys   = (PAGE_SEL * WINDOW_SIZE) + offset
    route phys to backend[PAGE_SRC]
```

### 5.4 Extended software rules (only if using the window)

1. Detect or know the machine has paging before use.  
2. Map (`PAGE_*`), then access; do not remap under `PC` in the window.  
3. ISRs that use the window save/restore page regs; prefer ISRs in general memory only.  
4. Flash-mapped writes: machine-defined; portable extended code still avoids them.  
5. May use a **separate** extended ABI/library (e.g. `memcpy_from_bank`) that is **not** linked into base binaries by default.

### 5.5 Optional 8+8 split

A machine may split the window into two 8 KB halves (e.g. flash + PSRAM). That remains an **extension** of the extension; base ABI still ignores `0x8000`–`0xBFFF`.

### 5.6 Fixed XIP in low memory (platform, not paging)

Mapping `0x0000`–`0x3FFF` to QSPI XIP is a **physical implementation of general memory / boot**, not the optional page window. It does not require `PAGE_SEL` and does not change the base ABI (code still runs at low addresses; stack still in SRAM).

---

## 6. Load model

### 6.1 Base (required)

| Artifact | Contents |
|----------|----------|
| Program image | Code/data for **general memory only** (`0x0000`–`0x7FFF`) |
| crt0 | Set SP per §3; copy `.data`, clear `.bss` within general memory |
| Devices | Programmed at runtime; not part of the portable image layout |

### 6.2 Extended (optional)

| Artifact | Contents |
|----------|----------|
| Bank payloads | Extra flash/PSRAM banks for the page window |
| VRAM overlay | Machine-specific high init |

Simulators may use a 64 KB array internally; **base tests** must pass with the page window **disabled** or returning errors on `0x8000`–`0xBFFF`.

---

## 7. Compliance summary

| Claim | Base machine | Extended (paging) machine |
|-------|--------------|---------------------------|
| Runs standard ABI binaries | **Required** | **Required** |
| Implements `0x8000`–`0xBFFF` page window | **No** | **Yes** |
| `PAGE_*` MMIO | **No** | **Yes** |
| General memory in `0x0000`–`0x7FFF` | **Yes** | **Yes** |
| `0xC000`–`0xFFFF` reserved for devices/VRAM | **Yes** | **Yes** |
| SP in page window | **Never** | **Never** (unsupported) |

**ISA/ABI correctness must be demonstrable with paging absent.**  
Paging is a **pure extension**: software and address-decode trickery on top of the base map.

---

## 8. Implementation checklist

| Layer | Base | Extension |
|-------|------|-----------|
| **RTL** | Decode general mem + device region | + window decode, `PAGE_*`, external mux |
| **ISS** | Low 32 KB + MMIO/VRAM model | + bank arrays; base tests with window off |
| **crt0 / ABI** | SP + data in general memory only | Optional bank helpers in a separate lib |
| **Linker** | `ORIGIN/LENGTH` only through `0x7FFF` | Optional `-T paged.ld` for extended apps |
| **Docs** | This §2–3 | This §4–5 + machine YAML |

---

## 9. Summary

| Region | Base ISA/ABI | Extension |
|--------|--------------|-----------|
| `0x0000`–`0x7FFF` | **Required** general memory | Same |
| `0x8000`–`0xBFFF` | **Ignored / unused** by portable code | Optional page window |
| `0xC000`–`0xFFFF` | **Reserved** MMIO+VRAM | Same + may host `PAGE_*` |

**The third 16 KB is optional.**  
The ABI and the ISA **must not assume it exists.**

---

## 10. Open machine-level choices

- Physical split of general memory (all RAM vs XIP + SRAM)  
- Implemented SRAM size and exact SP  
- Whether `0x8000`–`0xBFFF` is open-bus or page window  
- `PAGE_*` addresses, bank count, 16 KB vs 8+8  
- XIP wait states / I-cache  

---

*End of annex.*
