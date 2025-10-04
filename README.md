# CPU PT32B00

![Static Badge](https://img.shields.io/badge/arch-pt32b00-darkgreen)
![Static Badge](https://img.shields.io/badge/cache-32KB-firebrick)
![GitHub top language](https://img.shields.io/github/languages/top/Jelka33/CPU-PT32B00-Hardware)
![GitHub License](https://img.shields.io/github/license/Jelka33/CPU-PT32B00-Hardware)

## A hardware implementation of the PT32B00 CPU in VHDL

Processor implementation for FPGAs. It follows the PT32B00 architecture
with separate instruction and data caches, each 16KiB in size,
and a 16-entry fully associative TLB for virtual memory.

Processor supports 50 Mhz clock, though it might achive even higher clockings.

It connects to peripherals with simple port IO and memory busses.

Port IO Bus:
* &rarr; Input Data
* &larr; Port Number
* &larr; Ouput Data
* &larr; Port Request
* &larr; Write Enable

Memory Bus:
* &rarr; Input Data
* &rarr; Memory Ready
* &larr; Address
* &larr; Output Data
* &larr; Memory Request
* &larr; Write Enable
* &larr; RAM Enable

## Peripherals

The cache and memory management unit can be controlled by port IO. The following
table presents the ports and their usage:

| Port | Usage |
|:----:|:------|
|0x00| Set/get the depth of the allocated RAM <br/> <i>All addresses past this depth will be treated as MMIO.</i>|
|0x01| Flush the whole TLB <br/> <i>The `out` instruction is used, but the data doesn't matter.</i>|
|0x02| Evict the corresponding TLB entry for the address <br/> <i>Using `out`, pass the address that belongs to a page whose entry should be evicted.</i>|
|0x03| Evict the corresponding instruction cacheline for the address <br/> <i>Using `out`, pass the address which is contained in the cacheline you wish to evict.</i>|
|0x04| Evict the corresponding data cacheline for the address <br/> <i>Using `out`, pass the address which is contained in the cacheline you wish to evict.</i>|
|0x05| Force cache write-back of the corresponding instruction cacheline for the address <br/> <i>Using `out`, pass the address which is contained in the cacheline you wish to write to RAM</i>|
|0x06| Force cache write-back of the corresponding data cacheline for the address <br/> <i>Using `out`, pass the address which is contained in the cacheline you wish to write to RAM</i>|

## Usage

All source files are found in the `/src` directory. The file `/src/cpu_pt32b00.vhdl`
is the top-level for the whole CPU.

Just add all the files to your project and instantiate the `cpu_pt32b00` entity.

## License

The code is distributed under the 3-Clause BSD License (see LICENSE.txt for more).

## Known Issues

The functionality of breakpoint/debug registers (DR) and single-step trap
is not yet implemented. Trying to use them will cause no behaviour.
