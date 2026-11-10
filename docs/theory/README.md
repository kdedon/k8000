# Theory of operation

How each chip's RTL works and why it is shaped that way, for whoever
maintains it. Each document covers the pins and parameters, clocking and
reset, the blocks, the main transactions, timing and fit, what is
inferred, and how it is tested.

| chip | document | RTL |
|---|---|---|
| Z8001/Z8002 CPU, Z8003/Z8004 | [Z8000_CPU.md](Z8000_CPU.md) | `rtl/k800x_cpu/` |
| Z8010 MMU | [Z8010_MMU.md](Z8010_MMU.md) | `rtl/k8010_mmu/` |
| Z8030 SCC | [Z8030_SCC.md](Z8030_SCC.md) | `rtl/k8030_scc/` |
| Z8036 CIO | [Z8036_CIO.md](Z8036_CIO.md) | `rtl/k8036_cio/` |
| Z8070 FPU | [Z8070_FPU.md](Z8070_FPU.md) | `rtl/k8070_fpu/` |

Common to all five: one board master clock runs every flop; each chip
clock or strobe pin is seen as a one-master-clock edge pulse or sampled
level; bidirectional pins are in/out/enable triplets; chip modules carry
only the chip's real pins.

Results and fit numbers: [../STATUS.md](../STATUS.md). Design choices
resting on inference: [../DECISIONS.md](../DECISIONS.md).
