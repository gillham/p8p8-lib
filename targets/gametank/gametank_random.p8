; Random numbers, the same ones as the GameTank SDK's.
;
; MOST PROGRAMS SHOULD NOT USE THIS MODULE, but Prog8's own random numbers,
; in the math module.  On the GameTank the program is in ROM, so use their
; _rom versions:
;
;   %import math
;   math.rndseed_rom($00c2, $1137)      ; once, before the first number
;   b = math.rnd_rom()                  ; ubyte
;   w = math.rndw_rom()                 ; uword
;   b = math.randrange_rom(10)          ; 0 to 9
;   w = math.randrangew_rom(1000)       ; 0 to 999
;
; (math.rnd() and the others without _rom keep their seed in the code itself:
; a program in ROM that uses them does not assemble, "ROMable code: this writes
; into the program".)
;
; Why this module exists: it is a Prog8 version of the GameTank SDK's
; src/gt/feature/random/random.c, with the names of the C SDK, and it gives
; exactly the numbers that the C code gives, in the same order.  That is for a
; program converted from C that has to behave as its C version does: levels
; made from random numbers, replays, tests that compare the two.
;
; It is much slower than the math module: 16 rounds of a 16 bit xorshift for
; each number, as in C.
;
; Different from C: rnd_range() works out its remainder unsigned, so high must
; be more than low (p8c has no signed 16 bit remainder yet).

%import gametank

gametank {
%option merge

    word rnd_seed = 234

    sub xorshift16(word value) -> word {
        if value == 0
            value = 1
        value ^= (value & $07ff) << 5
        value ^= value >> 7             ; signed, as in C: the sign bit comes in
        value ^= (value & $0003) << 14
        return value
    }

    ; the next random number: any 16 bits.
    ; (set rnd_seed to start the sequence somewhere else; it is 234 at the start, as in C)
    sub rnd() -> word {
        repeat 16
            rnd_seed = xorshift16(rnd_seed)
        return rnd_seed
    }

    ; a random number from low to high-1 (high must be more than low)
    sub rnd_range(word low, word high) -> word {
        uword value = (rnd() & $7fff) as uword
        return ((value % ((high - low) as uword)) as word) + low
    }
}
