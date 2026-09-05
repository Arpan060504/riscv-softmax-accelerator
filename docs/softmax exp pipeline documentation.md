# `softmax_exp_pipeline` — Technical Documentation

## 1. What this module actually does

`softmax_exp_pipeline` takes the same N-element FP32 stream that `streaming_max_reduce` consumes, and extends it one step further down the softmax chain:

```
softmax(x)_i = exp(x_i - max(x)) / sum_j exp(x_j - max(x))
```

It computes `exp(x_i - max(x))` for every element in the stream — i.e. the numerator of softmax, per element. It does **not** compute the sum or the final division; that would be a downstream accumulate-and-divide stage. This module is exactly the "max-shift, then exponentiate" half of softmax.

Structurally, it's a thin wrapper: it reuses `streaming_max_reduce` wholesale for the max/subtract work already documented separately, then bolts a 3-stage combinational `exp()` approximation onto its output.

## 2. Why this exists — the intuition

Hardware has no native `exp()` instruction. You cannot Taylor-expand `exp(y)` directly with a short polynomial and get good accuracy, because `exp()` changes over many orders of magnitude — a polynomial that's accurate near `y=0` is garbage at `y=-10`, and vice versa. The standard trick (used in essentially every hardware/software math library) is **range reduction**:

```
y = k·ln(2) + r          (k integer, r restricted to a small range)
exp(y) = exp(k·ln(2) + r) = 2^k · exp(r)
```

This splits an unbounded exponentiation into:
- a **cheap, exact** power-of-two scaling (`2^k`), which in floating point is just adding `k` to the exponent field — no multiplier needed, and
- a **cheap, approximate** exponential of a *small, bounded* value `r`, which a short polynomial (here, evidently linear: `exp(r) ≈ a·r + b`) can approximate accurately because `r` never leaves a narrow window.

The design comments state `exp_r_lut` operates over roughly `[0, 0.7]`, which lines up with reducing `r` into `[0, ln(2))` (`ln(2) ≈ 0.693`). That's the textbook range-reduction window.

## 3. Architecture — 4-stage pipeline

```
x_in ──▶ [Stage 1: streaming_max_reduce] ──▶ y = x_i - max(x)
                                              │
                                              ▼
                                 [Stage 2: exp_kr_reducer]
                                   y = k·ln(2) + r  →  outputs (k, r)
                                              │
                                              ▼
                                   [Stage 3: exp_r_lut]
                                   exp(r) ≈ a·r + b
                                              │
                                              ▼
                                [Stage 4: exp_power_of_two]
                                exp(y) = exp(r) · 2^k
                                              │
                                              ▼
                                        exp_out, exp_valid
```

| Stage | Module | Nature | Job |
|---|---|---|---|
| 1 | `streaming_max_reduce` | Sequential FSM (documented separately) | Buffer N inputs, compute max, emit `x_i - max` one per cycle |
| 2 | `exp_kr_reducer` | Combinational | Split `y` into integer `k` and remainder `r` |
| 3 | `exp_r_lut` | Combinational | Approximate `exp(r)` for the now-small `r` |
| 4 | `exp_power_of_two` | Combinational | Rescale by `2^k` via exponent-field manipulation, producing final `exp(y)` |

**Important structural fact:** stages 2–4 are all combinational and sit entirely inside a single clock cycle downstream of stage 1's registered output. That's why:

```verilog
assign exp_valid = reduced_valid;
```

works with no extra pipeline registers or valid-delay logic — `exp_out` becomes valid the same cycle `reduced_out` does, because it's just a longer combinational path off the same register. This means the module's overall latency and throughput are **identical** to bare `streaming_max_reduce` (2N+1 cycles, one output per cycle in the `REDUCE` phase) — the exp() machinery is "free" in cycle count, but not free in combinational depth (see §6).

## 4. Stage-by-stage detail

### Stage 1 — `streaming_max_reduce`
Unchanged from its standalone form: two-pass buffer-then-subtract, producing `reduced_out = x_i - max(x)` and forwarding `max_value`, `busy`, `done` straight through as this module's own outputs. See the separate `streaming_max_reduce` documentation for its FSM, timing, and known caveats — they all apply here unchanged, since this module doesn't touch that logic.

### Stage 2 — `exp_kr_reducer` (range reduction)
Not shown in the provided source, so its exact algorithm is inferred from its interface and the surrounding comments rather than verified directly. Given `k` is `signed [7:0]` and `r` is FP32, and the comment states `y = k·ln(2) + r`, this stage almost certainly:
1. Computes `k = round(y / ln(2))` (or floor, depending on convention),
2. Computes `r = y - k·ln(2)`.

Since `y ≤ 0` always for this specific pipeline (every `y` is `x_i - max(x)`, and `max(x)` is by definition the largest element), `k` is expected to always come out `≤ 0` in this use case, and `r` should land in `[0, ln(2))` as the LUT's documented input range suggests. **This is an assumption inferred from usage, not verified from RTL** — the actual reducer might behave differently for `y > 0`, which simply never occurs here because of how this module is wired (fed only by the max-subtract stage).

### Stage 3 — `exp_r_lut` (polynomial/LUT approximation)
Approximates `exp(r) ≈ a·r + b` for `r` in the small reduced range. Whether this is a true lookup table (piecewise-linear segments) or a single fixed-coefficient line is not shown — the module name suggests a LUT, and the observed accuracy (errors on the order of `1e-4`) is good enough that either a multi-segment LUT or a well-fit single line could plausibly produce it. This is the one place where the design's actual numerical accuracy lives, and it's the one place with the least visibility into its implementation.

### Stage 4 — `exp_power_of_two` (reconstruction)
Reconstructs `exp(y) = exp(r) · 2^k`. The efficient way to do this in FP32 — and the only way that makes sense given the module is purely combinational with no multiplier port — is to take `exp_r`'s bit pattern and add `k` directly to its raw exponent field (bits `[30:23]`), rather than performing a real floating-point multiply. This is a legitimate and common technique, exploiting the definition of the FP32 exponent, but it has a sharp edge: if `k` pushes the resulting exponent field below `0` or above `254`, this simple field-add approach silently produces garbage (denormal/underflow behavior isn't handled by field addition, and overflow into the `0xFF` exponent would look like infinity/NaN) unless the (unseen) module explicitly clamps or special-cases those ranges. Nothing in the visible code confirms that it does.

## 5. Test analysis — what this run actually proves

The testbench is meaningfully different in character from the `streaming_max_reduce` testbench, and worth calling out plainly:

**What it does well:**
- Compares against a genuine software reference (`$exp()` in real-number math), not just a hand-computed expected value — this is the right way to validate an *approximate* function.
- Deliberately includes a duplicate maximum (`3.0` appears twice) and specifically re-checks that `exp(0) == 1.0` exactly at both occurrences (`check_exp_zero`). This is a good, non-obvious check: max-subtraction guarantees at least one `y_i = 0` exactly, and any range-reduction bug (e.g., `exp_kr_reducer` mishandling `y=0` as a boundary case between two `k` values) would show up here. Both instances passed with exact `1.000000`.
- Includes a genuine negative value (`-1.0`) landing far from the max (`y = -4.0`), exercising a `k` value away from zero, not just small-`r`, `k=0` cases.
- All 7 outputs passed within the stated `0.02` absolute tolerance, with actual errors two orders of magnitude tighter (`~1e-4` to `~3e-4`), suggesting the approximation is considerably better than the tolerance the test demands.

**What it doesn't cover — and here the gaps are more significant than in the max-reduce testbench:**
- **Single fixed test vector, not parameterizable by `N`.** Unlike the max-reduce testbench, `input_data` here is hand-written FP32 hex literals sized exactly for `N=7`. There's no generator, so this can't be re-run at other `N` without rewriting the vector by hand. Confidence in this design is really confidence in *one specific input set*.
- **`ABS_TOL = 0.02` is an absolute tolerance on values that are mathematically bounded in `(0, 1]`.** After max-subtraction, every `exp(y)` is at most `1.0`, and can be arbitrarily close to `0` for elements far below the max. An absolute tolerance doesn't protect against relative error blowing up for small values — for example, index 4's reference value is `0.018316`; the tolerance as written would still pass a hardware result of `0.03` (nearly double the true value, ~100% relative error) or even `0.0` (100% relative error the other way), because both are within `0.02` absolute distance. The design happens to be accurate enough that this gap didn't bite this time, but the *test* itself would not have caught a real accuracy regression concentrated in small-`exp(y)` outputs.
- **`k` is never stressed.** All test values are small integers/half-integers between `-1.0` and `3.0`. Range reduction's whole purpose is handling `y` values that require multiple wraps of `ln(2)` — large negative logits (very plausible in real softmax use, e.g. `y = -30`) are never tested, so a bug in `exp_kr_reducer` for large `|k|`, or a bug in `exp_power_of_two`'s field-add for extreme exponents, would go completely undetected here.
- **No test of the reconstruction stage's overflow/underflow edges.** As noted in §4, a naive exponent-field-add reconstruction has failure modes at the extremes of the FP32 exponent range. Nothing here approaches those extremes.
- **No back-to-back transaction, N=0/N=1, or non-contiguous `x_valid` testing** — same gaps as the underlying `streaming_max_reduce`, inherited unchanged since Stage 1 isn't retested here.

## 6. A timing concern worth flagging

Because stages 2–4 are chained combinationally with no registers between them, the actual combinational path for one output is: `fp32_adder` (inside Stage 1) → `exp_kr_reducer` → `exp_r_lut` → `exp_power_of_two`, all within a single clock period. Each of those is itself a non-trivial floating-point operation. This is fine functionally (correctness doesn't care about combinational depth) but it means the module's maximum clock frequency is set by the *sum* of four FP-ish operations in series, not by the single FP adder that gates `streaming_max_reduce` alone. If this pipeline is meant to run at a specific target frequency, that critical path is the thing to check with real synthesis timing — nothing in the testbench (which only checks functional correctness, not timing closure) would reveal a problem here.

## 7. Summary of the honest trade-offs

| Aspect | Verdict |
|---|---|
| Overall approach (range reduction: `y = k·ln2 + r`, `exp(y) = 2^k·exp(r)`) | The correct, standard technique — appropriate choice, not over-engineered. |
| Reuse of `streaming_max_reduce` for stage 1 | Clean composition; inherits that module's correctness *and* its documented gaps unchanged. |
| Zero-cost pipelining (`exp_valid = reduced_valid`) | Efficient in cycles, but pushes all cost into combinational depth — verify timing closure separately. |
| `exp(0) = 1` exact-boundary check | A genuinely good test; passed cleanly at both duplicate-max indices. |
| Numerical accuracy observed | Very good relative to the tolerance used — errors ~100x tighter than `ABS_TOL`. |
| Test tolerance methodology | A real weakness — absolute tolerance on a `(0,1]`-bounded quantity doesn't bound relative error for small outputs. |
| Range-reduction stress (`k` far from 0, extreme exponents) | Essentially untested. This is the least-verified part of the whole pipeline and also the part most likely to break on real (large-magnitude) logits. |
| Visibility into `exp_kr_reducer` / `exp_r_lut` / `exp_power_of_two` | None — all three are black boxes here; documentation of their behavior is inference from naming, comments, and one passing test, not verification. |

**Bottom line:** the architecture is textbook-correct and the one test run that exists passed convincingly. But "passed convincingly" is doing a lot of work here: it's one hand-picked input vector, with a loose absolute tolerance that wouldn't have caught a relative-accuracy problem, exercising none of the large-magnitude or extreme-exponent cases that real softmax logits (large negative values in particular) will actually produce. Before trusting this for real workloads, the next step should be a swept test — many random inputs across a wide dynamic range, checked with a *relative*-error criterion — specifically targeting `exp_kr_reducer` and `exp_power_of_two`'s behavior at large `|k|`.
