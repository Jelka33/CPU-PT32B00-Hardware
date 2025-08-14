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
* -> Input Data
* <- Port Number
* <- Ouput Data
* <- Port Request
* <- Write Enable

Memory Bus:
* -> Input Data
* -> Memory Ready
* <- Address
* <- Output Data
* <- Memory Request
* <- Write Enable
* <- RAM Enable

## Usage

All source files are found in the `/src` directory. The file `/src/cpu_pt32b00.vhdl`
is the top-level for the whole CPU.

Just add all the files to your project and instantiate the `cpu_pt32b00` entity.

## License

The code is distributed under the 3-Clause BSD License (see LICENSE.txt for more).
