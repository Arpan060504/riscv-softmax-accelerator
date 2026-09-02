# riscv-softmax-accelerator

Parameterized FP32 Softmax accelerator with custom RISC-V instruction
support, scalable vector length, and memory-efficient intermediate data
reuse.

## Overview

This project implements a hardware accelerator for the Softmax function
in FP32 precision, designed for integration with a RISC-V processor via
a custom instruction. The accelerator is parameterized to support
variable vector lengths and reuses intermediate data to minimize memory
overhead.

## Features

- **FP32 Softmax datapath** — exponentiation, accumulation, reciprocal,
  and normalization stages
- **Custom RISC-V instruction support** — CPU issues a dedicated
  instruction to trigger accelerator execution
- **Parameterized / scalable vector length** — not fixed to a single
  input size
- **Memory-efficient intermediate data reuse** — reduces buffering and
  storage overhead during computation

## Architecture

```
RISC-V CPU
    │
    │ custom instruction
    ▼
┌──────────────────────┐
│ Softmax Accelerator  │
│                      │
│ exp                  │
│ accumulation         │
│ reciprocal           │
│ normalization        │
└──────────┬───────────┘
           │
           ▼
       Softmax output
```

## Status

Core Softmax datapath is functional in RTL. Current focus is on defining
the CPU–accelerator interface and building out RISC-V integration.

## Roadmap

```
STEP 1
✓ Softmax datapath working

STEP 2
→ Verify / characterize accuracy

STEP 3
→ Define accelerator interface

STEP 4
→ Build accelerator controller / FSM

STEP 5
→ Connect to RISC-V processor

STEP 6
→ Add custom instruction support

STEP 7
→ Run software workload on integrated system

STEP 8
→ Compare CPU-only Softmax vs hardware-accelerated Softmax
```

## Repository Structure

```
riscv-softmax-accelerator/
├── rtl/            # Verilog/SystemVerilog source for the accelerator
├── tb/             # Testbenches and verification environment
├── sw/             # RISC-V software / custom instruction usage examples
├── docs/           # Design notes, interface specs, diagrams
└── README.md
```

*(Update this section to match your actual directory layout.)*

## Getting Started

```bash
# Clone the repository
git clone https://github.com/<your-username>/riscv-softmax-accelerator.git
cd riscv-softmax-accelerator

# Run simulation (update with your actual toolchain/commands)
# e.g. make sim, vsim, verilator, etc.
```

## Evaluation

| Metric           | Software | Hardware |
|-------------------|----------|----------|
| Softmax latency    | —        | —        |
| Throughput         | —        | —        |
| FP operations      | —        | —        |
| Area               | —        | —        |
| Speedup            | 1×       | —        |

*(To be filled in once benchmarking against a software baseline is complete.)*

## License

This project is licensed under the MIT License.

Copyright (c) 2023–2027 Arpan Chandra, NIT Durgapur

Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be included
in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
