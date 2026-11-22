# SISTEMAS-DIGITAIS-ULA

A sequential 4-bit Arithmetic Logic Unit (ALU) written in VHDL for an FPGA board. The user selects an operation and two 4-bit operands using the slide switches and a confirm button, and the result and status flags are shown on the LEDs.

## How it works

The design is controlled by a finite state machine with four states:

1. **Select operation:** set the operation code on the switches and press `confirm`.
2. **Operand A:** set the 4-bit value of A on the switches and press `confirm`.
3. **Operand B:** set the 4-bit value of B on the switches and press `confirm`.
4. **Execute:** the result and flags are displayed. Press `confirm` again to go back to step 1.

While waiting for input (steps 1 to 3), the LEDs play an idle "chaser" animation.

The `confirm` button goes through a debouncer, which produces a clean single-clock-cycle pulse for each press.

## Operations

| Code (`sel`) | Operation | Description |
|:---:|---|---|
| `000` | Count | Counts from A up to B, one step at a time, showing the counter on the result LEDs |
| `001` | Add | A + B |
| `010` | Subtract | A - B |
| `011` | Minimum | Smaller of A and B (signed comparison) |
| `100` | Maximum | Larger of A and B (signed comparison) |
| `101` | Average | (A + B) / 2 (signed) |
| `110` | OR | A OR B (bitwise) |
| `111` | AND | A AND B (bitwise) |

## Status flags

| LED | Flag | Meaning |
|---|---|---|
| LED7 | Zero | Result is `0000` |
| LED6 | Negative | Most significant bit of the result is 1 |
| LED5 | Overflow | Signed overflow in add/subtract |
| LED4 | Carry | Carry out of the 4-bit operation |

## Pin mapping

Defined in `ula_sd.ucf`.

| Signal | Board resource |
|---|---|
| `clk` | Main clock input |
| `reset` | Push button BTN_EAST |
| `confirm` | Push button BTN_SOUTH |
| `sel[3:0]` | Slide switches SW3 to SW0 |
| `resul[3:0]` | LED3 to LED0 |
| `led_zero`, `led_negative`, `led_overflow`, `led_carry` | LED7 to LED4 |

## Files

| File | Description |
|---|---|
| `ULA_SD.vhd` | Top-level entity: main FSM, ALU operations and idle animation |
| `debounce_ula.vhd` | Button debouncer and rising-edge pulse generator |
| `ula_sd.ucf` | Pin constraints for the FPGA board |

## Timing notes

The idle animation delay (12.5 million cycles per step) and the debouncer (25 million cycles of stable input) are counted in clock cycles. The values assume a 50 MHz clock, which gives roughly 0.25 s per animation step and 0.5 s of debounce time.

## Tools

Developed with the Xilinx ISE toolchain (VHDL + UCF constraints).

## How to use

1. Create an ISE project and add `ULA_SD.vhd`, `debounce_ula.vhd` and `ula_sd.ucf`.
2. Set `ULA_SD` as the top module.
3. Synthesize, implement and generate the programming file.
4. Program the board.
5. Press `reset`, then follow the sequence: operation, A, B, result.
