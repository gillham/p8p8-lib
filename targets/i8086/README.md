# The library of the 8086 machines

Not a target: there is no `target.properties` here.  The 8086 targets (`dos`)
name this directory as their library (`library = ../i8086`) and add a
`textio` of their own, which is searched for first.

The modules are those of the llvm16 target: Prog8 with `%ir` blocks for what
the machine has to do (system calls).  Nothing here is assembly but a few
lines of `syslib`.

## 8086 assembly in a module

`%asm {{ ... }}` in a subroutine is written into the program as it stands,
for nasm.

- A variable is named as p8p8's 8086 code generator writes it: an underscore,
  then the scoped name with two underscores for each dot.  The parameter `st`
  of `strings.length` is `_strings__length__st`.
- The program is one segment: no segment register may be left changed, and
  the direction flag is clear (`cld`) wherever the generator's own code runs.
- Every other register is free: the generator's code keeps nothing in a
  register from one statement to the next.
- A subroutine's parameters are variables: the caller has stored them when
  the assembly runs.  A result is left in a variable marked `@shared` that
  the Prog8 code after the assembly returns.
- Labels are the program's as a whole, so each needs a prefix of its module
  and routine.  A label stands at the margin and ends with a colon.
- Only what the 8086 has: the file is assembled with `cpu 8086`.  A
  conditional jump (`je name` alone on its line) that may not reach its
  label is made the opposite jump around a `jmp`.
- The code generator adds the `ret` at the end of the subroutine; the
  assembly falls through to it.
- An `asmsub`, and an `extsub` at an address, name the 8086's registers:
  `AL`, `AH`, `BL`, `BH`, `CL`, `CH`, `DL`, `DH` for a byte, `AX`, `BX`,
  `CX`, `DX`, `SI`, `DI`, `BP` for a word, `Pc` for the carry.  An `asmsub`
  returns with `ret` itself (one declared `inline` has none and gets one).
  A routine that only other assembly calls is not seen as used: call it
  from Prog8 code, or it may be left out of the program.
