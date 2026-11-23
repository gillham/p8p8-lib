# The library of the 6809 machines

Not a target: there is no `target.properties` here.  The 6809 targets
(`coco2`, `coco3`, `sim6809`) name this directory as their library (`library
= ../m6809`) and add a `textio` of their own, which is searched for first.

The modules began as those of the llvm16 target: Prog8 with `%ir` blocks for
what the machine has to do (system calls).  Routines that many programs carry
are 6809 assembly, for size: the decimal and hexadecimal digits of numbers
and the reading of numbers in `conv`, and `length`, `ncopy` and `compare` in
`strings`.  `shared_coco_textio.p8` is the
`textio` of both Color Computers: the 32 by 16 text screen at $0400, with
BASIC's cursor address.  `shared_coco_diskio.p8` is their `diskio`: Disk
BASIC's files (the directory and the granule table handled here), through
the ROM's sector routine DSKCON alone.

`shared_sam_highram.p8` is the `highram` module of the Color Computer 2 and the
Dragons: the upper 32 KB of a 64 KB machine as memory for data, switched in
for the moment of each access.

## 6809 assembly in a module

`%asm {{ ... }}` in a subroutine is written into the program as it stands,
for lwasm.

- A variable is named as p8p8's 6809 code generator writes it: an underscore,
  then the scoped name with two underscores for each dot.  The parameter `st`
  of `strings.length` is `_strings__length__st`.
- The high byte of a word comes first.
- A subroutine's parameters are variables: the caller has stored them when
  the assembly runs.  A result is left in a variable marked `@shared` that
  the Prog8 code after the assembly returns.
- Labels are the program's as a whole, so each needs a prefix of its module
  and routine.  A label stands at the margin and ends with a colon.
- A branch is as it is written: the long form (`lbeq`) where the short one
  does not reach.
- The code generator adds the `rts` at the end of the subroutine; the
  assembly falls through to it.
- An `asmsub`, and an `extsub` at an address, name the 6809's registers:
  `A` and `B` for a byte, `D`, `X`, `Y` and `U` for a word, `Pc` for the
  carry.  An `asmsub` returns with `rts` itself (one declared `inline` has
  none and gets one).
- Floats are those of the BASIC in the machine's ROM (the target file's
  `float_...` keys say where its routines are); `shared_coco_floats.p8` is
  the Color Computers' `floats` module, `shared_dragon_floats.p8` the Dragons'
  (the same with the Dragon ROM's addresses).
