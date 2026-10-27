package main

import "fmt"

// dumpKernel prints the IF1 fetch sequence of one kernel: address and the
// clocks since the previous fetch.  Used to see where an iteration's time
// actually goes rather than inferring it.
func dumpKernel(name string) {
	for _, k := range kernels {
		if k.name != name {
			continue
		}
		prog, head := build(k)
		ev := run(prog, 6000)
		var prev uint64
		for i, e := range ev {
			d := uint64(0)
			if i > 0 {
				d = e.clk - prev
			}
			mark := ""
			if e.addr == head {
				mark = "  <-- loop head"
			}
			fmt.Printf("clk=%-6d addr=%04X  +%d%s\n", e.clk, e.addr, d, mark)
			prev = e.clk
			if i > 40 {
				return
			}
		}
	}
}
