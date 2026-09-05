# `streaming_max_reduce` — Technical Documentation

## 1. What this module actually does

`streaming_max_reduce` takes a stream of `N` FP32 values, one per clock cycle, and produces two things:

1. **`max_value`** — the maximum of all N inputs (IEEE-754 FP32).
2. **`reduced_out`** — a second stream, `N` values long, where each output is `x_i - max_value`, emitted **in the same order the inputs arrived**, one per cycle.

That's the whole functional spec. It is a two-pass streaming max-then-subtract engine.

## 2. Why this exists — the intuition

This block is the "max-shift" step of a numerically stable softmax. Softmax is:

```
softmax(x)_i = exp(x_i) / sum_j exp(x_j)
```

Computed directly, `exp(x_i)` overflows FP32 the moment `x_i` gets moderately large (`exp(89)` already exceeds FP32 range). The standard fix is the identity:

```
softmax(x)_i = exp(x_i - max(x)) / sum_j exp(x_j - max(x))
```

Subtracting the max before exponentiating guarantees the largest exponent argument is exactly `0` (`exp(0) = 1`), and every other argument is `≤ 0`, so nothing overflows. This module implements exactly that shift step — it does *not* compute exp() or the final softmax; it's a pre-processing building block that a downstream exp/accumulate/divide stage would consume.

## 3. Why it needs two passes (the core architectural decision)

The max of a stream can't be known until the *last* element has arrived. But every output needs that max. Since the module can't ask the upstream source to "replay" the stream, it has to remember every element itself:

- **Pass 1 (`INPUT` state):** consume all N inputs, store each one in local memory (`x_mem`), and simultaneously track the running max.
- **Pass 2 (`REDUCE` state):** now that the true max is known, re-read the buffered values one at a time and emit `x_i - max`.

This is the classic streaming-reduction trade: you pay `N × 32` bits of local storage to get single-pass ingestion. There is no way to avoid buffering the whole stream here — that's inherent to any max-then-subtract streaming primitive, not a design flaw.

## 4. Interface

| Signal | Dir | Width | Purpose |
|---|---|---|---|
| `clk`, `rst` | in | 1 | Synchronous, active-high reset |
| `start` | in | 1 | Pulse in `IDLE` to begin a new N-element transaction |
| `x_in` | in | 32 | FP32 input value |
| `x_valid` | in | 1 | Qualifies `x_in` during `INPUT` |
| `reduced_out` | out | 32 | FP32 result, `x_i - max` |
| `reduced_valid` | out | 1 | One-cycle pulse qualifying `reduced_out` |
| `max_value` | out | 32 | Final max, valid once `REDUCE` begins |
| `busy` | out | 1 | High for the entire transaction |
| `done` | out | 1 | One-cycle pulse on the final `REDUCE` output |

Note there is **no `x_ready` / backpressure signal**. The module assumes the producer feeds exactly N cycles of `x_valid` at whatever cadence it wants (it can idle, since only `x_valid` cycles count), but there is no way for the module to tell an upstream source "stop." That's fine for a testbench-driven design; it's a real limitation if this ever sits behind a source that can't be trusted to behave.

## 5. FSM walkthrough

```
IDLE ──start──▶ INPUT ──(N inputs received)──▶ WAIT_MAX ──▶ REDUCE ──(N outputs sent)──▶ IDLE
```

### `IDLE`
Deasserts `busy`. On `start`, resets `input_count`, sets `first_input = 1`, zeroes `current_max`, and moves to `INPUT`.

### `INPUT`
On every cycle where `x_valid` is high:
- `x_in` is stored into `x_mem[input_count]` — every element must be kept, since pass 2 needs it back.
- The running max is updated using the `max_finder` submodule, **except on the very first element**, which is loaded directly into `current_max`.

  This bypass matters: `current_max` resets to `32'h0` (positive zero). If the first real input is negative, comparing it against `0` would silently give the wrong "max" until a positive value showed up. Loading the first element unconditionally sidesteps that. This is a correct and necessary special case, not incidental.
- After the N-th input, the FSM moves to `WAIT_MAX`.

### `WAIT_MAX` — a one-cycle patch, not a "real" pipeline stage
This state exists purely because `current_max` is updated with a **non-blocking assignment** on the *same* cycle that the last input arrives. Non-blocking assignments don't take effect until the next clock edge, so at the moment the FSM would want to latch `current_max` into `max_value`, the register hasn't actually updated yet for the final comparison. `WAIT_MAX` burns one clock cycle to let that settle, then does `max_value <= current_max`.

This is a legitimate fix for a real NBA-timing hazard, but it's a patch, not an elegant one — it costs one extra cycle of latency on every transaction to work around an FSM structure that computes the max one cycle later than it "logically" finishes. A tighter design could fold this into the last `INPUT` cycle directly (e.g., compute the final max combinationally from `current_max` and the incoming `max_candidate` rather than waiting a cycle), but as implemented, the extra state is what makes it correct — removing it without restructuring the surrounding logic would reintroduce a stale-max bug.

### `REDUCE`
Each cycle: reads `x_mem[reduce_count]`, computes `x_mem[reduce_count] - max_value` via `fp32_adder`, drives it onto `reduced_out` with `reduced_valid = 1`. On the last index, also pulses `done` and returns to `IDLE`.

## 6. The subtraction trick

```verilog
assign neg_max = { ~max_value[31], max_value[30:0] };
```

IEEE-754 negation is just a sign-bit flip — no arithmetic needed. So `x - max` is computed as `x + (-max)` by flipping `max_value`'s sign bit and feeding both into a plain FP32 adder (`fp32_adder`). This is a legitimate, commonly used trick, but it has known blind spots that this design does **not** guard against:

- **NaN**: sign bit is meaningless for NaN payloads; flipping it doesn't change "not-a-number" but the trick assumes `max`/`x` are always well-formed finite numbers.
- **Zero**: flipping the sign of `+0` gives `-0`. Most adders treat `±0` as equal, but this is worth knowing if `fp32_adder`'s zero-handling is ever suspect.
- **Infinity**: not exercised anywhere in the testbench.

None of these are bugs in what's implemented — they're just outside the tested (and arguably outside the intended) envelope.

## 7. Dependencies this module does **not** implement

`max_finder` and `fp32_adder` are instantiated but their RTL isn't part of this file, so their correctness is an **assumption**, not something this module or its testbench verifies end-to-end:

- `max_finder(a, b) → max`: presumably compares two FP32 values. A naive "treat the 32 bits as an unsigned integer and compare" approach — which is a common shortcut for FP32 comparators — **only gives correct ordering when both values are positive**. For negative numbers, a larger bit pattern corresponds to a *more negative* value, so a correct FP32 comparator has to special-case sign. This test only proves `max_finder` gets the right answer on *this specific* mixed-sign dataset — it is not a proof of general correctness.
- `fp32_adder(a, b) → result`: assumed to do standard FP32 addition. Rounding, denormals, and overflow/underflow are never exercised because the testbench deliberately uses only exactly-representable integers.

If either submodule has a latent bug outside the ranges tested here, this testbench will not catch it. That's a real coverage gap, not a nitpick.

## 8. Testbench strategy — what it proves and what it doesn't

`tb_streaming_max_reduce` is parameterized by `N` (demonstrated here at `N = 57`).

**What it does well:**
- Uses a deterministic, non-trivial pattern (`(j*17) % 101 - 50`) instead of all-same or monotonic data, so the max isn't trivially at a fixed position.
- Forces known values at specific indices (`-20` first, `43` near the end) to pin down an expected max independent of `N`, while still letting the formula produce a naturally-occurring duplicate of that max elsewhere in the stream (seen in the log: `43` appears at both index 53 and index 55). That the module correctly reduces *both* occurrences to `0` is a genuinely good, non-obvious check — duplicate-max handling is a classic place reduction logic breaks.
- Checks three independent things: per-element `reduced_out`, the final `max_value`, and the output *count* (catching both wrong-value and wrong-count-of-outputs bugs).
- Round-trips through exact integer↔FP32 conversion so failures are diagnosed as an actual integer value, not a raw hex mismatch.

**What it doesn't cover — and this matters more than the passing log suggests:**
- **Only exact integers.** No fractional values, no rounding cases, no denormals, no `±0`, no `±∞`, no NaN. A softmax pre-processing block that only works on integers is not actually validated for its real use case (softmax logits are not integers).
- **No `N = 0` or `N = 1` testing shown here.** The RTL's `INDEX_WIDTH` computation special-cases `N ≤ 1`, and the `INPUT` state's `input_count == N-1` comparison is untested at the boundary — for `N=0` in particular this comparison wraps around and the behavior is unverified.
- **Single transaction only.** The testbench runs one `start` → `done` cycle and finishes. Back-to-back transactions (`start` reasserted immediately after `done`, or `start` asserted while `busy`) are never exercised, so whether the FSM correctly ignores or correctly accepts a stacked `start` is unknown.
- **No timing stress.** `x_valid` is driven high every single cycle with no gaps. A producer that inserts idle cycles mid-stream (which the RTL should tolerate, since the FSM only advances on `x_valid`) is never actually tested.

None of this means the RTL is wrong — it means "all tests passed" here is a narrower claim than it sounds. It proves the control-path FSM logic and the integer arithmetic path are correct for this one dense, single-shot, integer-only transaction. It does not prove the block is production-ready for arbitrary FP32 logits or bursty producers.

## 9. Timing / cost

For a transaction of size `N`:

- `N` cycles to shift in all inputs (`INPUT`)
- `+1` cycle bubble (`WAIT_MAX`)
- `N` cycles to shift out all outputs (`REDUCE`)
- Total: **2N + 1 cycles** of active processing, plus reset/start overhead.

For `N = 57` this matches the simulation: the run finishes at 1,220,000 ps with a 10 ns clock period → 122 cycles, consistent with `2·57 + 1 = 115` processing cycles plus reset (3 cycles), the start pulse, and settling cycles at the end.

**Storage cost:** `x_mem` is `N × 32` bits of registers/distributed RAM. This scales linearly with `N` and, depending on synthesis target, may or may not infer block RAM — worth checking explicitly if `N` gets large, since a naive register-array implementation is expensive in LUTs on FPGA.

**Latency cost:** the design is fundamentally two-pass, so minimum latency to the *first* output is `N+1` cycles no matter what — you cannot start emitting `x_0 - max` until every element has been seen. This is inherent to the problem, not a defect of this implementation.

## 10. Summary of the honest trade-offs

| Aspect | Verdict |
|---|---|
| Core algorithm (buffer + two-pass max/subtract) | Correct approach for the problem — no way around buffering the stream. |
| First-element max bypass | Correct, necessary fix for the "compare against reset-zero" bug. |
| `WAIT_MAX` state | A working patch for an NBA timing hazard, at the cost of a cycle every transaction. |
| Duplicate-max handling | Verified correctly. |
| FP32 comparator/adder correctness | Assumed, not verified — the testbench's integer-only data can't expose typical FP32 comparator sign-handling bugs. |
| Edge cases (N=0/1, NaN, Inf, ±0, fractional values) | Untested here. |
| Backpressure / flow control | Absent by design — fine for a testbench source, a gap for a real upstream producer. |
| Test result at N=57 | All 57 per-element checks, the max check, and the output-count check passed. |

**Bottom line:** the control logic is sound and the one subtle timing bug (stale `current_max`) is correctly handled. The test suite proves that narrow case thoroughly but leaves the actual floating-point correctness — the part most likely to have real bugs — resting on unverified submodules and an integer-only dataset. If this block is headed toward real use, the next testbench should add fractional values, mixed-sign edge cases near zero, and at least one multi-transaction back-to-back run.
