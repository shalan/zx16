# ZX16 Debug Annex v0.1

**Status:** Optional ISA extension (intended for machine **su26-ext** and silicon)  
**Base:** ZX16 Green Card (16-bit fixed ISA, SYS-type debug-related ops)  
**Out of scope:** UART framing, GDB RSP, Debug Module MMIO layout (machine docs)

This annex defines **Debug Mode** and a minimal set of **debug CSRs** plus **DRET**, so a host can halt, step, and resume with clear architectural state.

It is **not required** for a software UART monitor that only uses existing **EBREAK**, **STEP**, **EPC**, and **RETI**.

---

## 1. Debug Mode

### 1.1 Definition

The hart is either in **Normal Mode** or **Debug Mode**. In Debug Mode:

- No further **user program** instructions are committed until resume.
- Normal maskable interrupts are **not taken**.
- GPRs, memory, `dpc`, and `dcsr` remain accessible to a Debug Module (DM) or debug agent.
- Optional: PC is **parked** at an implementation-defined Debug ROM address; **resume still uses `dpc`**.

### 1.2 Entry

At an instruction boundary (or on EBREAK), the hart enters Debug Mode when any enabled cause in §1.3 fires. On entry:

| Action | Detail |
|--------|--------|
| `dcsr.cause` | Set to entry cause |
| `dpc` | Set per cause (below) |
| Debug Mode | Becomes active |
| User fetch/execute | Stops |

| Cause | `dcsr.cause` | `dpc` on entry |
|-------|--------------|----------------|
| External halt request (DM) | `1` | PC of the **next** instruction that would have run |
| **EBREAK** executed | `2` | Address of the **EBREAK** instruction |
| Single-step completed | `3` | PC of the instruction **after** the one just stepped |
| Trigger match (optional §5) | `4` | Matched PC (execute trigger, before execute) |
| Reset-halt (optional) | `5` | Implementation-defined reset PC (recommend `0x0020`) |

### 1.3 Exit — **DRET**

```
if hart not in Debug Mode:
    UNDEFINED          # recommend: illegal / nop; do not use as RETI
else:
    leave Debug Mode
    PC ← dpc & ~1      # force halfword alignment
    if dcsr.step = 1:
        execute exactly one instruction
        re-enter Debug Mode with cause = 3
        dpc ← PC after that instruction
```

---

## 2. Debug CSRs

Width: **16 bits**. Access from Normal Mode: **illegal** (implementation: trap or ignore; recommend trap/halt). Access from Debug Mode or via DM abstract command: **allowed**.

### 2.1 `dpc` (Debug PC)

| Bits | Name | Description |
|------|------|-------------|
| 15:0 | dpc | Resume address for **DRET**. Bit 0 is always 0. |

### 2.2 `dcsr` (Debug Control and Status)

| Bits | Name | R/W | Description |
|------|------|-----|-------------|
| 15:12 | cause | R | Last debug-entry cause (§1.2). |
| 11:4 | — | R | Reserved; read 0, writes ignored. |
| 3 | step | RW | 1 = single-step on next **DRET** resume. |
| 2 | ebreakm | RW | 1 = **EBREAK** enters Debug Mode; 0 = legacy EBREAK trap (vector / EPC). |
| 1 | stopcount | RW | 1 = machine timers do not advance in Debug Mode (if timers exist). |
| 0 | prv | R | Privilege at entry (v0.1: always 0). |

**Reset (su26-ext):** `dcsr = 0x0004` (`ebreakm = 1`, others 0); `dpc = 0x0020`.

### 2.3 `dscratch0` (optional)

| Bits | Description |
|------|-------------|
| 15:0 | Scratch register for debug sequences |

---

## 3. Instructions

### 3.1 Existing SYS instructions (clarified)

SYS encoding: `opcode[2:0] = 111`. Existing map unchanged:

| Instruction | [15:6] | func3[5:3] | opcode |
|-------------|--------|------------|--------|
| ECALL | svc | 000 | 111 |
| EBREAK | 0 | 001 | 111 |
| RETI | 0 | 010 | 111 |
| EI | 0 | 011 | 111 |
| DI | 0 | 100 | 111 |
| MFEPC | 0 | 101 | 111 |
| MTEPC | 0 | 110 | 111 |
| STEP | 0 | 111 | 111 |

| Instruction | Behavior under this annex |
|-------------|---------------------------|
| **EBREAK** | If `dcsr.ebreakm=1` and not in Debug Mode → enter Debug Mode (`cause=2`, `dpc`=EBREAK PC). If `ebreakm=0` → legacy trap using **EPC** / vector as Green Card. |
| **STEP** | Legacy single-step support. New software should prefer `dcsr.step` + **DRET**. Implementations may treat STEP as “set `dcsr.step`” only when annex is present. |
| **RETI** | Exit **normal** traps only (`PC←EPC`, `IE←1`). **Does not** exit Debug Mode when `dpc`/`dcsr` are implemented. |
| **ECALL** | Unchanged; not used for debug transport. |

### 3.2 **DRET** — Debug Return (new)

| Field | Bits | Value |
|-------|------|-------|
| opcode | 2:0 | `111` (SYS) |
| func3 | 5:3 | `111` (same major row as STEP) |
| svc / imm | 15:6 | **`0x3FE`** |

| STEP | DRET |
|------|------|
| `[15:6]=0`, `func3=111` | `[15:6]=0x3FE`, `func3=111` |

**Assembler:** `dret`  
**Machine code:** `0xFF9F`  
  - Check: bits[2:0]=111, [5:3]=111 → low 6 bits `111111` = `0x3F`; `[15:6]=0x3FE` → `0x3FE << 6 = 0xFF80`; `0xFF80 | 0x3F = 0xFFBF`…  

Recalculate carefully:
- opcode = 0b111 = bits 2:0  
- func3 = 0b111 = bits 5:3 → bits[5:0] = 0b111111 = 0x3F  
- [15:6] = 0x3FE = 0b11_1111_1110  
- word = (0x3FE << 6) | 0x3F = 0xFF80 | 0x3F = **0xFFBF**

**Semantics:** §1.3.

---

## 4. Priority at an instruction boundary

Evaluate in this order:

1. Reset  
2. **Debug halt request** → Debug Mode, cause = 1  
3. **Execute trigger** on next PC (if implemented) → Debug Mode, cause = 4  
4. Maskable interrupt if `IE=1` → normal trap (EPC/RETI path)  
5. Instruction fetch/execute  
   - **EBREAK** → §3.1  
   - End of insn with pending step → Debug Mode, cause = 3  

If haltreq and a maskable IRQ are both pending: **haltreq wins**.

---

## 5. Optional triggers (v0.1a)

Minimum: **two execute breakpoints**.

| CSR | Role |
|-----|------|
| `tselect` | Selects trigger 0 or 1 |
| `tdata1` | type = execute, enable |
| `tdata2` | Match address (halfword-aligned) |

On match **before** execute: Debug Mode, cause = 4, `dpc` ← match address.  
Load/store watchpoints: **v0.2**.

---

## 6. EPC / IE vs dpc / dcsr

| Path | Resume state | Resume insn |
|------|--------------|-------------|
| Normal trap / IRQ | **EPC**, **IE** | **RETI** |
| Debug Mode | **dpc**, **dcsr** | **DRET** |

EPC is **not** required to update on debug entry. DM may still read/write EPC for software convenience.

---

## 7. Compatibility

| Platform | Annex |
|----------|--------|
| **su26** (course handout) | Optional / off; course binaries need not use DRET |
| **su26-ext** | Recommended on; default `ebreakm=1` |
| Binaries without EBREAK/DRET | Unchanged if DM not asserting halt |

**Software monitor only (no DM):** may ignore this annex and use EBREAK + STEP + RETI + EPC exclusively.

**Hardware DM + UART:** should implement Debug Mode entry on haltreq and abstract access to `dpc`/`dcsr`/GPRs/memory; wire protocol is outside this annex.

---

## 8. Summary of ISA delta

| Item | Kind |
|------|------|
| Debug Mode | New architectural mode |
| `dpc`, `dcsr` | New CSRs |
| `dscratch0` | Optional CSR |
| **DRET** | New SYS encoding (`func3=111`, `[15:6]=0x3FE`, word **`0xFFBF`**) |
| EBREAK / STEP / RETI | Clarified, not removed |
| Triggers | Optional CSRs (v0.1a) |

**Not part of the ISA:** debug UART, DM MMIO, GDB RSP.

---

## 9. Revision history

| Ver | Notes |
|-----|--------|
| 0.1 | Debug Mode; dpc/dcsr; DRET encoding; priority; EBREAK/RETI/STEP clarification; optional execute triggers |

---

*ZX16 Debug Annex v0.1 — machines/docs/ZX16_DEBUG_ANNEX.md*
