# What the Z80 machines share

Not a target: there is no `target.properties` here.  The Z80 targets (`cpm`
so far) name files of this directory in theirs.

- `z80-float.c`: linked with a program that uses floats (`float_source`).
  The shortest digits of a float, reading one, and rounding to even, which
  z88dk's math32 library lacks or gets wrong.  It uses nothing of a
  particular machine.
