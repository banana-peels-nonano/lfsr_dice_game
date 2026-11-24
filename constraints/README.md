# Constraints

No board has been chosen yet, so there is no pin XDC here.

- `timing.xdc` is board-independent: just the 100 MHz `create_clock`. It is the file used for the Vivado run in `reports/vivado_results.md`. It also contains commented-out false-path lines that have not been verified yet.
- `template.xdc` lists every top-level port with a placeholder pin and is fully commented out. **Do not use it until each `<PIN>` has been replaced from your board's master XDC or schematic.**

## What is needed once the board is known

| item | where it comes from | affects |
|---|---|---|
| exact part number (e.g. `xc7s??...`) | board reference manual | Vivado project part |
| system clock pin and frequency | board master XDC | `create_clock` period, `CLK_HZ` parameter |
| clock I/O standard | board master XDC | `IOSTANDARD` |
| two push buttons: pins and polarity | schematic | `btn_new_game`, `btn_roll`, `BTN_ACTIVE_LOW` |
| seed switches: how many, pins | schematic | `sw_seed` width / tie-offs in `top_module` |
| LEDs: how many, pins | schematic | `led` mapping |
| 7-seg display: present? digits? segment and anode pins and polarity | schematic | `seg`, `dp`, `an`, `SEG_ACTIVE_LOW`, `AN_ACTIVE_LOW` |
| bank voltages | schematic | `IOSTANDARD` per pin (often LVCMOS33) |
| configuration settings | board manual | `CFGBVS` / `CONFIG_VOLTAGE` |

## Timing intent

- There is one clock domain. The only timing constraint needed is `create_clock` on `clk`.
- Buttons and switches are asynchronous inputs that go straight into 2-FF synchronisers marked `ASYNC_REG`. They need no input-delay constraints. If Vivado reports unconstrained input paths on them, `set_false_path -from [get_ports {btn_* sw_seed[*]}]` is the usual fix.
- LEDs and 7-seg outputs drive humans, so output delays do not matter. A `set_false_path -to` on them is acceptable if unconstrained-output warnings appear.
