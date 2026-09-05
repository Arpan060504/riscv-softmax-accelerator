# `softmax_exp_accumulator` — Technical Documentation

## 1. What this module actually does

`softmax_exp_accumulator` is the third and final piece of the softmax chain built so far:

```
softmax(x)_i = exp(x_i - max(x)) / Σ_j exp(x_j - max(x))
                └──────┬──────┘     └─────────┬─────────┘
             streaming_max_reduce      softmax_exp_accumulator
                       +
              softmax_exp_pipeline
```

Given the `exp_out` stream from `softmax_exp_pipeline` (one FP32 value per cycle, N values total), this module does two things simultaneously:

1. **Stores** every exponential value into local memory (`exp_mem`), addressable later via `read_addr`.
2. **Accumulates** a running FP32 sum of all N exponentials, producing `Σ_j exp(y_j)` — the softmax denominator.

It does **not** perform the final division (`exp_i / sum`). That would be a fourth stage that reads back through `read_addr`/`exp_out` and divides each stored value by the finished `sum`. As built and tested, this module hands you the numerator values (already computed upstream) and the denominator (computed here) — the division itself is not implemented or exercised anywhere in what's been shown.

## 2. Why this exists — the intuition

Streaming architectures face the same structural problem here as they did for the max: you need the **complete** sum before you can divide any single element by it, but the elements arrive one at a time. So, exactly like `streaming_max_reduce`, this module:

- consumes the stream once, accumulating a running total as it goes (classic MAC-style accumulation, minus the multiply — this is pure streaming addition), and
- **also buffers every element** into `exp_mem`, so that a later stage can come back and read `exp_i` at any `read_addr` once `sum` is final, in order to compute `exp_i / sum`.

The buffering is what makes `read_addr`/`exp_out` meaningful: it's a random-access lookup port for "give me back the i-th exponential I stored," intended to feed a downstream divider. This is architecturally consistent with how `streaming_max_reduce` buffered raw inputs for its own second pass.

## 3. Interface

| Signal | Dir | Width | Purpose |
|---|---|---|---|
| `clk`, `rst` | in | 1 | Synchronous, active-high reset |
| `start` | in | 1 | Restarts accumulation (see §5 — note this is level-sensitive here, not an edge-triggered pulse like `streaming_max_reduce`'s `start`) |
| `exp_in` | in | 32 | FP32 exponential value from the exp pipeline |
| `exp_valid` | in | 1 | Qualifies `exp_in` |
| `read_addr` | in | `ADDR_WIDTH` | Address into the stored-exponential memory |
| `exp_out` | out | 32 | **Not** the exponential pipeline's output — this is `exp_mem[read_addr]`, a memory readback. Same name, different signal, in a different module. See §7 for why this is worth flagging. |
| `sum` | out | 32 | Running/final FP32 accumulated sum |
| `done` | out | 1 | Goes high once the N-th element has been accumulated — **and stays high** (see §5) |

## 4. Algorithm

There's no explicit FSM here — just a free-running counter (`count`) and a single always-block with priority-ordered conditions:

```
if (rst)          → sum=0, count=0, done=0
else if (start)   → sum=0, count=0, done=0        (re-arm for a new transaction)
else if (exp_valid):
    exp_mem[count] <= exp_in                        (buffer this element)
    sum            <= sum + exp_in                  (via fp32_adder, combinational)
    if (count == N-1):  done <= 1
    else:                count <= count + 1
```

This is a textbook streaming-accumulate: one FP32 add per valid input, one store per valid input, and a completion flag once the expected count is reached. It works in lockstep with the upstream `softmax_exp_pipeline` — it simply consumes whatever `(exp_in, exp_valid)` it's handed, at whatever rate they arrive, with no independent timing of its own.

## 5. Clock and control-signal usage — the details that matter

- **Every state change here is synchronous**, gated purely by `posedge clk`. There is no combinational output path from `exp_valid` to `sum` or `done` — both are registered, so they update one cycle after the triggering `exp_valid`, same convention as the upstream FSM-based modules.
- **`start` here is level-checked every cycle, not consumed as a one-shot pulse.** Contrast this with `streaming_max_reduce`, where `start` is only examined in the `IDLE` state and has no effect once a transaction is running. Here, if `start` is held high (or re-asserted) *during* an active accumulation, the module will reset `sum`/`count`/`done` on every such cycle, silently discarding whatever had been accumulated. The testbench never does this (it pulses `start` for exactly two cycles, well before any `exp_valid`), so this behavior is never exercised — but it's a real difference in interface contract between this module and the max-reduce FSM, and anyone composing these blocks needs to know `start` means something subtly different here.
- **`done` is sticky, not a one-cycle pulse.** Once `count == N-1` and `exp_valid` fires, `done` latches to `1` and *stays* `1` indefinitely — nothing in the always-block ever clears it except `rst` or a fresh `start`. This is a genuine inconsistency worth flagging: `streaming_max_reduce`'s `done` is a one-cycle pulse (explicitly defaulted to `0` at the top of its always-block, then pulsed for exactly one cycle), while this module's `done` is a level that stays asserted. A downstream consumer written to expect "done pulses once" (matching the upstream module's convention) would work fine — but one written to expect "done stays high until I explicitly acknowledge it" would only work with *this* module, not the one upstream. Mixing these two conventions in the same design is a plausible source of future integration bugs, even though nothing in the current testbench exposes it (it just does `wait(accumulator_done)` once and moves on).
- **`count` doesn't wrap or reset itself after the last element** — it holds at `N-1` until the next `start`/`rst`. Combined with the sticky `done`, the module simply sits in a completed, latched state after finishing, which is a sensible design as long as the next block in the chain knows to wait for a fresh `start` before expecting new activity.

## 6. Input/output timing relationship

For a transaction of size N, assuming `exp_valid` arrives every cycle (as it does when driven by `softmax_exp_pipeline`'s `REDUCE` phase):

```
cycle:      1      2      3    ...    N
exp_valid:  1      1      1    ...    1
exp_in:    e0     e1     e2    ...   e(N-1)
count:      0      1      2    ...   N-1
sum:       e0   e0+e1  e0+e1+e2 ... Σ all e_i   (registered, one cycle after each exp_in)
done:       0      0      0    ...    1  (then stays 1)
```

`sum` after the N-th cycle is the finished denominator; `exp_out` (the readback port) is available combinationally at any time afterward for any `read_addr` in `[0, N-1]`, since `exp_mem` retains its contents until the next `start`.

## 7. A naming problem worth calling out directly

This module's own `exp_out` port is a **completely different signal** from the `exp_out` produced by `softmax_exp_pipeline` one level up. In the pipeline, `exp_out` is the live exponential of the *current* streaming element. In the accumulator, `exp_out` is a *memory readback* of a *previously stored* element, addressed by `read_addr`. The integration testbench avoids confusion only because it renames the accumulator's port to `exp_mem_out` at the instantiation site — but that's a testbench-level workaround, not a fix. The underlying module still exports a port called `exp_out` that means something entirely different from the `exp_out` everywhere else in this design. This is a real readability/maintainability risk: anyone wiring these modules together from the port list alone (rather than the testbench's careful renaming) has a natural way to confuse the two.

## 8. Combinational path — a compounding concern

Documentation of `softmax_exp_pipeline` already flagged that stages 2–4 (`exp_kr_reducer` → `exp_r_lut` → `exp_power_of_two`) are chained combinationally within a single cycle off `streaming_max_reduce`'s registered output. This module adds a **fifth** combinational stage directly onto that same chain: `sum`'s next-state value depends on `exp_in` (the tail end of that four-stage chain) *plus* this module's own `fp32_adder`. So the full combinational path feeding the `sum` register on any given cycle is:

```
fp32_adder (max-subtract) → exp_kr_reducer → exp_r_lut → exp_power_of_two → fp32_adder (accumulate) → sum register
```

That's two FP32 adds and two other FP-ish combinational blocks in series, per clock period. Nothing in either testbench measures timing — both are purely functional (`iverilog`/`vvp`) simulations — so whether this critical path actually closes at any target clock frequency is completely unknown from what's been shown. This is the same caveat raised for the exp pipeline, now compounded by one more stage.

## 9. What the read/lookup port never gets tested

`read_addr` and `exp_out` (the memory readback) exist in the module and are wired all the way up to the integration testbench's top level (`exp_mem_out`), but the testbench **never drives `read_addr` to a non-default value and never checks `exp_mem_out` against anything.** The entire readback path — the mechanism presumably intended to let a future division stage retrieve each stored exponential — is present in the RTL and completely unverified. If there's a bug in the memory addressing (off-by-one, wrong width, wrong element on wraparound), nothing here would catch it.

## 10. The regression sweep — what actually matters in this data

The PowerShell sweep runs the full three-block pipeline (`streaming_max_reduce` → `softmax_exp_pipeline` → `softmax_exp_accumulator`) end-to-end across N = 2, 3, 4, 5, 7, 8, 13, 16, 17, 21, 27, 32, 35, 57, 64 — 15 sizes, all passing. That breadth is a genuine improvement over the earlier `softmax_exp_pipeline` testbench, which only ever ran one hardcoded N=7 vector: this sweep exercises small N, both parities, powers of two, and non-powers of two, giving real confidence in the counter/addressing logic across sizes.

**But look at the error trend, not just the pass/fail column:**

| N | DUT sum error | % of SUM_TOL (0.01) |
|---|---|---|
| 2 | 0.000000 | 0% |
| 3 | 0.000344 | 3% |
| 5 | 0.000386 | 4% |
| 8 | 0.000980 | 10% |
| 13 | 0.001718 | 17% |
| 21 | 0.002706 | 27% |
| 32 | 0.004122 | 41% |
| 57 | 0.007455 | 75% |
| 64 | 0.008590 | **86%** |

This is not random noise — it's monotonic and accelerating. The reason is visible in the raw `EXP[]` values printed in every run: the LUT approximation is **consistently biased high**. Every single approximated value in the logs exceeds its true reference (e.g. `0.368223` vs the true `0.367879`; `0.606920` vs `0.606531`) — never once is a value biased low. When every term in a sum shares the same sign of error, the total error grows roughly in proportion to N (or to how many times each biased value repeats), rather than partially cancelling the way independent random errors would. By N=64, the accumulated error has already consumed 86% of the fixed `SUM_TOL = 0.01` budget.

**This is the most actionable finding in this whole test suite.** A `riscv-softmax-accelerator` almost certainly needs to handle N in the hundreds (real transformer attention rows, vocabulary-sized logits, etc.), and this trend — extrapolated — says the sum-check would very plausibly start failing somewhere not far past N=64, using the exact same fixed tolerance that's currently passing. Two things should happen before trusting this at production scale:
1. **Fix or characterize the LUT's systematic bias.** A one-directional bias is usually fixable (it suggests a coefficient or rounding-direction issue in `exp_r_lut`, not fundamental to the range-reduction approach) and fixing it would flatten this curve dramatically.
2. **Stop using a fixed absolute tolerance for a sum whose term count varies by two orders of magnitude across the sweep.** `SUM_TOL = 0.01` was clearly picked to pass N≈2–8 comfortably; it was not derived from how the error should legitimately scale with N. A relative-error criterion, or a tolerance that explicitly scales with N, would surface this problem now instead of letting it slide until a much later, more expensive discovery.

## 11. Summary of the honest trade-offs

| Aspect | Verdict |
|---|---|
| Core accumulate-while-buffering approach | Correct pattern, consistent with how `streaming_max_reduce` handles the same two-pass problem. |
| `start`/`done` semantics vs. upstream modules | **Inconsistent.** `start` is level-sensitive here (edge-only upstream); `done` is sticky here (pulsed upstream). Neither is wrong in isolation, but the mismatch is a real integration hazard. |
| `exp_out` port naming | Collides in meaning with the upstream module's `exp_out`. Confusing, worth renaming (e.g. `mem_out`) before this goes further. |
| Read/lookup port (`read_addr`/`exp_out`) | Implemented but **completely untested** — the presumed downstream division path has zero verification coverage. |
| Combinational critical path | Now five FP-ish stages deep per cycle across the full chain; timing closure is unverified by simulation alone. |
| Regression breadth (N sweep) | A real strength — good coverage of the control/addressing logic across 15 sizes. |
| Numerical accuracy at scale | **The real concern.** Systematic (non-cancelling) bias in the exp approximation causes error to grow with N, and the fixed tolerance is already 86% consumed by N=64 — before this design has even been tested at the sizes it will likely need to handle. |

**Bottom line:** the control logic (counting, storing, accumulating, latched completion) is sound and well-exercised across a genuinely broad N sweep — that part of the verification story is solid. The number that should worry you is the error-vs-N trend: it's not a testbench artifact, it's a real systematic bias in the exponential approximation compounding as more terms get summed, and it's already most of the way to the tolerance boundary at the largest N tested. Extrapolating this design to realistic softmax sizes without first fixing the LUT bias or tightening/rescaling the tolerance is very likely to surface failures that this test suite, as currently tuned, is not positioned to catch early.
