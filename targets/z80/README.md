# The library of the Z80 machines

Not a target: there is no `target.properties` here.  The Z80 targets (`cpm`,
`trs80`, `trs80m4`) name this directory as their library (`library =
../z80`) and add a `textio` of their own, which is searched for first.

The modules began as those of the llvm16 target, which is why they are
Prog8 with `%ir` blocks for what the machine has to do (system calls).
Routines that many programs carry are being rewritten in Z80 assembly, for
size: so far the decimal and hexadecimal digits of numbers and the reading
of numbers in `conv`, and `length`, `ncopy` and `compare` in `strings`.

## Z80 assembly in a module

`%asm {{ ... }}` in a subroutine is written into the program as it stands,
for z88dk's z80asm.

- A variable is named as p8p8's Z80 code generator writes it: an underscore,
  then the scoped name with underscores for the dots.  The parameter `st` of
  `strings.length` is `_strings_length_st`.
- A subroutine's parameters are variables: the caller has stored them when
  the assembly runs.  A result is left in a variable marked `@shared` that
  the Prog8 code after the assembly returns.
- Labels are the program's as a whole, so each has a prefix of its module
  and routine (`p8str_length_next`).
- The code generator adds the `ret` at the end of the subroutine; the
  assembly falls through to it.
- There is no `asmsub` on the Z80 yet.

## Other files

- `z80-float.c`: linked with a program that uses floats (`float_source` in
  the target file).  The shortest digits of a float, reading one, and
  rounding to even, which z88dk's math32 library lacks or gets wrong.  It
  uses nothing of a particular machine.
