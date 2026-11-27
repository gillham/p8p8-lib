prog8_math {
    %option no_symbol_prefixing, ignore_unused

	%asminclude "library:shared_m68k_prog8_math.asm"

    ; 32 bit multiplication, division and remainder for a 68000, which has these for 16
    ; bits only: upstream's routines for the Amiga 500 (m68k_prog8_longmath.asm) without
    ; their way through AmigaOS's utility.library.  Arguments in d0 and d1, results in
    ; d0 (and the remainder in d1).
    %asm {{
        ; d0 = d0 * d1  (signed or unsigned, keeping the low 32 bits)
        ; Uses four 16-bit partial products:  result = x0*y0 + (x0*y1 + x1*y0)<<16  (+ x1*y1<<32, dropped).
        p8_mulsi3:
            movem.l d2-d3,-(sp)
            move.w  d0,d2          ; d2 = x0 (low half of x)
            mulu.w  d1,d2          ; d2 = x0*y0
            move.l  d0,d3
            lsr.l   #8,d3
            lsr.l   #8,d3          ; d3 = x1 (high half of x)
            mulu.w  d1,d3          ; d3 = x1*y0
            swap    d1             ; d1 = y1 (high half of y)
            mulu.w  d0,d1          ; d1 = x0*y1
            add.l   d3,d1          ; d1 = x0*y1 + x1*y0  (the two cross terms)
            swap    d1
            clr.w   d1             ; d1 = (cross terms) << 16
            add.l   d1,d2          ; d2 = x0*y0 + cross<<16
            move.l  d2,d0
            movem.l (sp)+,d2-d3
            rts

        ; Unsigned 32/32 -> 32: d0 = dividend, d1 = divisor  ->  d0 = quotient, d1 = remainder.
        ; Plain shift-and-subtract long division, 32 iterations, no 32-bit divide needed.
        p8_udivmod32_sw:
            movem.l d2-d5,-(sp)
            move.l  d1,d2          ; d2 = divisor
            beq.s   .divz          ; divide by zero: quotient 0, remainder = dividend
            moveq   #31,d3         ; 32 bit positions to process
            move.l  d0,d4          ; d4 = dividend (shifted through to feed the bits)
            clr.l   d0             ; d0 = quotient (built up)
            clr.l   d5             ; d5 = remainder (built up)
        .loop:
            lsl.l   #1,d4          ; shift the next dividend bit out into the X flag
            roxl.l  #1,d5          ; remainder = (remainder<<1) | that dividend bit
            lsl.l   #1,d0          ; quotient <<= 1
            cmp.l   d2,d5
            blo.s   .next
            sub.l   d2,d5          ; remainder -= divisor
            addq.l  #1,d0          ; quotient |= 1
        .next:
            dbf     d3,.loop
            move.l  d5,d1          ; remainder
        .out:
            movem.l (sp)+,d2-d5
            rts
        .divz:
            move.l  d0,d1          ; remainder = dividend
            clr.l   d0             ; quotient = 0
            bra.s   .out

        ; Signed 32/32 -> 32: d0 = dividend, d1 = divisor  ->  d0 = quotient, d1 = remainder.
        ; Computed with absolute values, then the signs are corrected: the quotient takes
        ; the sign of (dividend xor divisor), the remainder takes the sign of the dividend
        ; (truncating division, like C).
        p8_sdivmod32_sw:
            movem.l d6-d7,-(sp)
            move.l  d0,d6          ; d6 = dividend (keep original for sign)
            move.l  d1,d7
            eor.l   d6,d7          ; d7 bit31 set if the two signs differ
            tst.l   d0
            bpl.s   .nabs
            neg.l   d0             ; d0 = |dividend|
        .nabs:
            tst.l   d1
            bpl.s   .dabs
            neg.l   d1             ; d1 = |divisor|
        .dabs:
            jsr     p8_udivmod32_sw  ; d0 = |quotient|, d1 = |remainder|
            tst.l   d7
            bpl.s   .qpos
            neg.l   d0             ; flip quotient sign if signs differed
        .qpos:
            tst.l   d6
            bpl.s   .rpos
            neg.l   d1             ; flip remainder sign to match dividend
        .rpos:
            movem.l (sp)+,d6-d7
            rts

p8_smult32:
        bra     p8_mulsi3
p8_umult32:
        bra     p8_mulsi3
p8_sdivmod32:
        bra     p8_sdivmod32_sw
p8_udivmod32:
        bra     p8_udivmod32_sw
    }}
}
