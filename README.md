# The library p8p8 builds programs with

This is what a Prog8 program is compiled against: the standard library
modules, and for each machine its description and the modules that are its
own.  It is to p8p8 (a Prog8 compiler written in Prog8) what the C library
is to a C compiler.

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

## What is here that is not upstream's

- `targets/llvm64`, `llvm32`, `llvm16`: the library of the LLVM targets.
- `targets/atari`, `c64os`, `cx16os`, `f256`, `gametank`, `mega65`, `plus4`,
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
  | `targets/virtual/*`, `targets/amiga500/textio.p8`, `targets/amiga1200/textio.p8`, `targets/qemu68k/textio.p8` | additions for the LLVM branch |

- `common/shared_aligned_long_arena.p8`, `common/shared_hosted_compression.p8`:
  new shared modules.

## License

GPLv3 with Prog8's exception for the output of the compiler; see `LICENSE`.
Prog8 and its library are by Irmen de Jong, <https://github.com/irmen/prog8>.
