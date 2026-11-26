# The library p8p8 builds programs with

This is what a Prog8 program is compiled against: the standard library
modules, and for each machine its description and the modules that are its
own.  It is to p8p8 (a Prog8 compiler written in Prog8) what the C library
is to a C compiler.

Find the p8p8 compiler here: https://github.com/gillham/p8p8

```
p8c -lib <this directory> -target plus4 program.p8
```

## Layout

```
prog8lib/                  Prog8's standard library, exactly as upstream has it
    conv.p8, strings.p8, math.p8, ...      modules every machine shares
    c64/, cx16/, pet32/, c128/, ...        the machines Prog8 itself supports
common/                    shared modules that are added, or changed from upstream's
targets/                   one directory for each machine or target
    c64/target.properties                  a machine of Prog8: its description,
    c128/syslib.p8                         and any of its modules that are changed
    plus4/target.properties                a machine added here: its description
    plus4/syslib.p8, textio.p8, ...        and its own modules
    vic20plus3/target.properties           a variant: "library = ../vic20"
    llvm64/, llvm32/, llvm16/              the LLVM targets (not in upstream Prog8)
    cpm/target.properties                  a Z80 machine ("cpu = z80"): CP/M
    trs80/target.properties, textio.p8     a Z80 machine: the TRS-80 Model I and III
    trs80m4/target.properties, textio.p8   a Z80 machine: the TRS-80 Model 4 in its own mode
    z80/                                   the library of the Z80 machines (not a target)
    coco2/, coco3/                         6809 machines ("cpu = 6809"): the Color Computers
    coco2ram/                              the Color Computer 2 with 64 KB, the program with the ROMs switched out
    coco3ram/                              the Color Computer 3, the program with memory blocks of its own where BASIC is
    dragon32/, dragon64/                   6809 machines: the Dragons
    sim6809/target.properties, textio.p8   a 6809 machine: a bare 6809 in usim09batch
    m6809/                                 the library of the 6809 machines (not a target)
    dos/target.properties, textio.p8       an 8086 machine ("cpu = 8086"): MS-DOS, a .COM program
    i8086/                                 the library of the 8086 machines (not a target)
triples/                   platforms of the llvm32 target: one properties file each
VERSION                    which upstream commit prog8lib/ is
LICENSE
```

Nothing in `prog8lib/` is ever edited.  A new Prog8 release replaces that
directory and nothing else; everything that is not upstream's is in
`common/` and `targets/`, where it can be seen and compared.

## How a module is found

For `-target plus4`, an `%import textio` is looked for in this order:

1. the directories of `-srcdirs` (the program's own modules)
2. `targets/plus4/` (the machine's own modules)
3. `prog8lib/plus4/` (the machine's modules in Prog8, when it has any)
4. `common/` (shared modules added or changed here)
5. `prog8lib/` (the shared modules of Prog8)

So the first two layers lie over the standard library: a file in them is
used in place of the one of the same name further down, and whatever they
do not have comes from Prog8's library unchanged.

- A machine of Prog8 itself (`c64`, `cx16`) has its `target.properties` in
  `targets/`, and its modules are found in step 3.  A file in `targets/c128/`
  replaces Prog8's for that machine only.
- A variant of a machine (more memory, another load address) is a directory
  with only a `target.properties` that names the library it shares:
  `library = ../vic20`.
- Files that a machine's startup code includes (`.include "startup.asm"`) are
  found in its directory as well.

## The state of the targets

How far each one has been tried with p8p8.  "Builds" means that test programs
compile and assemble, with p8p8 and with the reference compiler's LLVM branch;
nothing more is claimed for those.

| Target | State |
|---|---|
| `c64`, `c128`, `cx16`, `pet32` | programs built by p8p8 are compared with the reference compiler's in emulators (C64, X16), and real programs have been run on all four |
| `plus4`, `vic20plus8`, `mega65`, `f256`, `gametank` | a real program (a game) built by p8p8 has been run on each |
| `llvm64` | p8p8 itself is built for it; compared with the reference compiler on macOS, Linux and Windows |
| `llvm32`, `llvm16` | test programs compared with the reference compiler (WebAssembly, the llvm-mos simulator and the C64) |
| `virtual` | test programs compared in the reference compiler's virtual machine |
| `cpm` | a Z80 machine, for p8p8's Z80 code generator, which is a beginning: the test programs print in tnylpo what they print on the host and what prog8c-llvm's CP/M build prints.  Its modules are those of `targets/z80`, which the Z80 machines share, with a `textio` and a `diskio` (files through the BDOS) of its own |
| `trs80` | a Z80 machine: the test programs print on a Model I and on a Model III (TRSDOS 1.3 and LDOS) in trs80gp what they print on the host; not tried on a real machine.  Its own `textio` and `diskio` (the DOS's calls; the file routines are `targets/z80/shared_trsdos_diskio.p8`), the rest from `targets/z80` |
| `trs80m4` | a Z80 machine: the test programs print on a Model 4 (TRSDOS 6) in trs80gp what they print on the host; not tried on a real machine |
| `sim6809` | a 6809 machine, for p8p8's 6809 code generator, which is a beginning: the test programs without floats print in usim09batch what they print on the host |
| `coco2`, `coco3` | 6809 machines: the same programs print in XRoar's Color Computer 2 and 3 what they print on the host; not tried on a real machine.  `coco3` also writes to the 40 and 80 column screens, and its `highram` is the memory beyond the 64 KB (384 KB of 512 KB) |
| `coco2ram` | the same programs (also built with `-varshigh 0`), and the file test, in XRoar's Color Computer 2 with 64 KB; not tried on a real machine |
| `coco3ram` | the same programs on the 80 column screen, in XRoar's Color Computer 3 with 128 KB and 512 KB; not tried on a real machine |
| `dragon32`, `dragon64` | 6809 machines: the same programs print in XRoar's Dragon 32 and Dragon 64 what they print on the host; not tried on a real machine; no `diskio` |
| `dos` | an 8086 machine, for p8p8's 8086 code generator, which is a beginning: the test programs without floats print in DOSBox-X what they print on the host; not tried on a real machine |
| `appleii` | the Apple II (the II Plus with `-cpu 6502`, the IIe, IIc and IIgs): the test programs without floats print in bobbin's enhanced IIe what the reference compiler's build for the same target prints, and the text screen's routines are checked there; not tried on a real machine or from a disk.  The program is a binary file for `$2000` with DOS 3.3's four bytes before it.  40 columns; no floats, no `diskio`, no graphics yet |
| `vic20`, `vic20plus3`, `vic20plus24`, `cx16os`, `mc64`, `sim6502` | builds; not run |
| `atari` | the Atari 8-bit computers with 48 KB or more (the 800XL): the test programs without floats leave in atari800's 800XL the text screen that the reference compiler's build for the same target leaves, and the text screen's routines, the clock and the keys' routines are checked there; not tried on a real machine or from a disk.  An `.xex` for `$2000` with its run address.  40 columns; no floats, no `diskio`, no graphics yet |
| `rp6502`, `w65c816sxb` | builds, for a program with `%launcher none` (these have no BASIC launcher); not run |
| `c64os` | **broken, being worked on**: does not build with either compiler, because its modules are older than the standard library they sit on |
| upstream's `amiga500`, `amiga1200`, `qemu68k` | 68000 machines: p8p8 has no code generator for them yet, so they can only be checked, not built.  Custom 68000 targets are left out of this library until it has one |

## What is here that is not upstream's

- `targets/llvm64`, `llvm32`, `llvm16`: the library of the LLVM targets.
- `triples/`: the triple profiles of the LLVM branch of Prog8 for the 32-bit
  hosted platforms (WebAssembly with WASI, ARM Linux, RISC-V Linux), as they
  are there.  p8p8 reads them for `-target llvm32 -triple <name>`.
- `targets/appleii`, `atari`, `c64os`, `cx16os`, `f256`, `gametank`, `mega65`, `plus4`,
  `vic20...` and the others that Prog8 does not have: custom targets, which
  start from the standard library's modules for a similar machine.
- `targets/c64`, `c128`, `cx16`, `pet32`: `target.properties` written for p8p8
  from the Prog8 compiler's sources (it has these machines built in).
- Changed copies of upstream files.  Each replaces the whole file, so when
  upstream changes the same file the copy has to be looked at again:

  | File | Why |
  |---|---|
  | `common/buffers.p8`, `common/wavfile.p8`, `common/shared_string_functions.p8`, `common/shared_sys_functions.p8`, `common/shared_cbm_textio_functions.p8` | changes for targets with wider pointers or another byte order, and fixes |
  | `targets/c128/syslib.p8` | the BASIC ROM banked out for programs above $3fff |
  | `targets/pet32/textio.p8`, `targets/pet32/syslib.p8`, `targets/c64/syslib.p8`, `targets/cx16/syslib.p8` | fixes, and the list of targets in `sys.target` |
  | `targets/qemu68k/syslib.p8` | the LLVM branch's: `sys.memcopy` copied a byte too few when source and target are aligned differently |
  | `targets/virtual/*`, `targets/amiga500/textio.p8`, `targets/amiga1200/textio.p8`, `targets/qemu68k/textio.p8` | additions for the LLVM branch |

- `common/shared_aligned_long_arena.p8`, `common/shared_hosted_compression.p8`:
  new shared modules.
- `targets/gametank/audio_fw.bin.rle`: the GameTank's audio firmware, from
  the GameTank SDK by Clyde Shaffer, included with his permission.  It is not
  under this repository's license; see `targets/gametank/NOTICE.md`.

## License

GPLv3 with Prog8's exception for the output of the compiler; see `LICENSE`.
One file is someone else's and has its own terms:
`targets/gametank/NOTICE.md`.
Prog8 and its library are by Irmen de Jong, <https://github.com/irmen/prog8>.
