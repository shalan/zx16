# Vendored AMBA / peripheral IP

These files are a **minimal vendored subset** of NativeChips' Apache-2.0 IP, copied
unmodified for the ZX16 SoC. Do not edit here; update from upstream and re-copy.

| file(s) | upstream repo | commit |
|---|---|---|
| `amba.v`, `nc_mcu_fabric.v` | nc_amba (github.com/nativechips/nc_amba) | `c53274e` |
| `nc_uart.v`, `nc_fifo.v`, `nc_glitch_filter.v`, `nc_sync.v`, `nc_ticker.v` | nc_lib/nc_uart | `2a53809` |
| `nc_tmr.v` | nc_lib/nc_tmr (dep `nc_sync.v` shared with UART) | `2a53809` |

All are 32-bit AMBA (AHB-Lite + APB3). The ZX16 (16-bit) reaches them through the
`zx16_ahb16to32` adapter; see `rtl/soc/zx16_soc.v`. License: Apache-2.0 (NativeChips).
