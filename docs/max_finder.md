# `max_finder` — Streaming FP32 Maximum-Value Module

## 1. Purpose

`max_finder` is a synchronous hardware block that computes the **running maximum of a stream of IEEE-754 single-precision (FP32) values**, one value per valid cycle. It is designed as a building block for hardware Softmax (the "MAX" stage that every Softmax implementation needs before exponentiation, e.g. `M = max(x_0, ..., x_{N-1})`).

Instead of loading an entire vector into a wide register and reducing it combinationally, this module consumes values **serially**, one FP32 word per clock cycle (when `valid` is high), and updates a running maximum register. A `clear` pulse resets the running maximum so a new vector/row can begin without needing a full module reset.

## 2. Port List

| Port | Direction | Width | Description |
|---|---|---|---|
| `clk` | input | 1 | System clock |
| `rst` | input | 1 | Synchronous reset — forces `max_out` to 0 and re-arms `first_valid` |
| `clear` | input | 1 | Starts a **new** max computation (analogous to a "soft reset" between rows/vectors) |
| `valid` | input | 1 | Qualifies `data_in` — the module only samples `data_in` on cycles where `valid = 1` |
| `data_in` | input | 32 | FP32 value to compare against the running maximum |
| `max_out` | output | 32 | Registered running maximum (final result once the whole stream has been fed) |

## 3. FP32 Field Decomposition

Every incoming word is split (combinationally) into its three IEEE-754 fields:

```
data_in[31]    -> sign_in      (1 bit)
data_in[30:23] -> exponent_in  (8 bits, biased)
data_in[22:0]  -> fraction_in  (23 bits, mantissa)
```

The same decomposition is implicitly applied to `max_out` (the module reads `max_out[31]`, `max_out[30:23]`, `max_out[22:0]` directly for comparison instead of keeping separate decomposed registers).

This works because of a key property of the IEEE-754 format: **for numbers of the same sign, comparing the raw bit patterns of exponent-then-mantissa in order is equivalent to comparing the numeric values.** That's exactly what the module's comparison logic below exploits — it never converts to a real/fixed-point number, it just compares bit-fields directly.

## 4. Internal State

| Signal | Purpose |
|---|---|
| `first_valid` | 1-bit flag: "the next valid sample is the first element of a new max computation." Set by `clear`/`rst`, cleared after the first sample is accepted. |
| `max_out` | The only piece of "real" state — doubles as both the running maximum and the final output. |

There is no separate counter or FSM — the module's behavior is entirely captured by the `(rst, clear, valid, first_valid)` combination each cycle, evaluated in a single `always_ff` block.

## 5. Behavior / Control Flow

On every rising clock edge, exactly one of four mutually exclusive branches executes:

```
rst    ──► max_out = 0 ; first_valid = 1        (synchronous reset)
clear  ──► max_out = 0 ; first_valid = 1        (start new computation)
valid  ──► compare-and-update (see below)
else   ──► hold state (no clock enable listed, but no branch = no change)
```

`rst` has top priority, then `clear`, then `valid`. If none of `rst`, `clear`, `valid` are asserted, `max_out` and `first_valid` simply retain their values (implicit latch of state in `always_ff`).

### 5.1 First element of a run

```systemverilog
if (first_valid) begin
    max_out     <= data_in;   // accept unconditionally
    first_valid <= 1'b0;
end
```
The first sample after a `clear` is always accepted as-is — there's nothing to compare it to yet. This is what allows the module to correctly handle an all-negative input stream: the running max isn't seeded with `0x00000000` (which is `+0.0`, i.e. larger than any negative number), it's seeded with the first real sample.

### 5.2 Subsequent elements — sign-aware bitfield comparison

For every element after the first, `max_finder` implements FP32 comparison **without using a floating-point comparator**, via a three-way case split on sign:

**Case A — Different signs** (`sign_in != max_out[31]`)
```
if incoming is positive (sign_in == 0):  new value wins (any positive > any negative)
if incoming is negative:                  keep current max unchanged
```

**Case B — Both positive** (`sign_in == 0` and `max_out[31] == 0`)
Positive FP32 values compare correctly as **unsigned integers** when read as exponent‖mantissa, so:
```
if exponent_in >  max_out[30:23]:  new value wins
if exponent_in == max_out[30:23]:  compare fraction_in vs max_out[22:0]; larger fraction wins
if exponent_in <  max_out[30:23]:  keep current max
```

**Case C — Both negative** (`sign_in == 1` and `max_out[31] == 1`)
For negative numbers, larger magnitude = smaller value, so the comparison **inverts**:
```
if exponent_in <  max_out[30:23]:  new value wins (smaller magnitude = larger/less-negative value)
if exponent_in == max_out[30:23]:  compare fraction_in vs max_out[22:0]; SMALLER fraction wins
if exponent_in >  max_out[30:23]:  keep current max
```

This mirrors the standard trick for comparing IEEE-754 floats using integer logic: flip the comparison direction for negative values (equivalently, XOR/complement the bit pattern before an unsigned compare — this module instead just branches on sign explicitly).

**Not handled:** NaN, ±Infinity, subnormals, and −0.0 vs +0.0 edge cases are not specially handled — the module assumes well-formed finite FP32 inputs (reasonable for a Softmax pre-max-subtraction datapath fed from a matrix multiply, but worth noting as a limitation).

## 6. Timing Diagram — Reading the Waveform

From `max_finder_waveform.png`:

| Signal | Behavior seen in waveform |
|---|---|
| `clk` | Free-running clock, ~10 ns period (matches testbench `#5` half-period) |
| `clear` | Brief 1-cycle pulses roughly every ~100–120 ns — these mark the **start of each new test vector** (Test 1 → Test 6 in the testbench) |
| `rst` | Held low throughout the visible window (reset already happened earlier) |
| `valid` | Toggles high for one cycle per element, with idle (low) gaps between sends — matches the testbench's `send_value` task, which asserts `valid` for exactly one clock and then drops it before the next value |
| `data_in[31:0]` | Streams through the raw FP32 hex codes for each test vector's elements, one per `valid` pulse (e.g. `C0E00000` = −7.0, `40E00000` = 7.0, `4110...` = 9.1) |
| `max_out[31:0]` | Updates one cycle *after* each accepted `data_in` sample (registered output) and **holds its final value** once a test vector's elements are exhausted — visible as `max_out` "settling" to values like `41200000` (10.0) and `41100000`/`4110...` (9.1) and staying there until the next `clear` |

The pattern of `max_out` jumping only on some `valid` pulses (not every one) is the visual signature of the comparison logic in action — it only updates when the new sample actually exceeds the current running maximum; otherwise it holds.

## 7. Testbench Coverage (`max_finder_tb.sv`)

| Test | Scenario | Elements | Expected Max |
|---|---|---|---|
| 1 | All positive | 9 values | 9.1 (`4111999A`) |
| 2 | All negative | 4 values | −1.0 (`BF800000`) — validates Case C (both-negative) logic |
| 3 | Mixed signs | 6 values | 5.0 (`40A00000`) — validates Case A (sign-crossing) logic |
| 4 | Max is the **first** element | 4 values | 10.0 (`41200000`) — validates the `first_valid` seeding path plus "hold" behavior |
| 5 | Max is the **last** element | 4 values | 10.0 (`41200000`) — validates continuous updating across a run |
| 6 | 9-element sequence (target Softmax row size) | 9 values | 9.0 (`41100000`) |

Each test:
1. Pulses `clear` for one cycle to reset `max_out` and re-arm `first_valid`.
2. Streams elements in via `send_value()` — asserts `data_in` + `valid` for one clock, then drops `valid`.
3. Waits one clock, then checks `max_out` against the expected FP32 result and prints `PASS`/`FAIL`.

The testbench comment on Test 6 ("This is the important test for your future Softmax") signals the module's intended role: it's the streaming MAX-reduction stage that would sit ahead of a subtract/exponentiate/normalize datapath (analogous to the VFMAX/MAX loop stage in Softmax hardware such as the VEXP paper's Snitch-based accelerator, but implemented here as a single-element-per-cycle streaming reducer rather than a 4-wide SIMD reducer).

## 8. Architecture Summary Diagram

```
                 ┌─────────────────────────────────────────┐
   data_in[31:0] │                                          │
   ───────────►──┤  sign/exp/frac split (combinational)     │
                 │                                          │
                 └───────────────┬─────────────┬────────────┘
                                  │             │
                          sign_in │   exponent_in, fraction_in
                                  ▼             ▼
                 ┌─────────────────────────────────────────┐
   valid ───────►│         Compare vs max_out fields        │
   clear ───────►│  (sign-aware 3-way branch: diff-sign /   │
   rst   ───────►│   both-pos / both-neg)                   │
   first_valid ─►│                                          │
                 └───────────────┬───────────────────────────┘
                                  │ update?
                                  ▼
                 ┌─────────────────────────────────────────┐
                 │   max_out register (32-bit, on clk)      │──────► max_out[31:0]
                 │   first_valid register (1-bit, on clk)   │
                 └─────────────────────────────────────────┘
```

## 9. Key Design Takeaways

- **One value per cycle, no combinational tree**: trades throughput for a very small, simple, easily-pipelined footprint — a natural match for a streaming SSR-style datapath (as opposed to a wide combinational N-input max tree).
- **No floating-point comparator IP needed**: exploits IEEE-754's monotonic bit-pattern ordering for same-signed values, using only integer `>`/`<`/`==` on the exponent and mantissa subfields.
- **`clear` vs `rst`**: `rst` is a hard, whole-module reset; `clear` is a lightweight "start next row" pulse — this is what lets the module be reused row-after-row (e.g., one row of an attention matrix after another) without stalling for a full reset cycle.
- **Latency**: `max_out` reflects the correct running max **one cycle after** the corresponding `valid` sample (standard registered-output latency); the final max for a full vector is available one cycle after the last valid element is accepted.
