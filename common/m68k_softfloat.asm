; Floating point without an FPU, for the 68000 machines of p8p8 (the Amiga 500, the
; Atari ST, and any 68000 target built with -floats soft).
;
; A float is an IEEE single: a sign, eight bits of exponent (127 more than it is) and
; 23 bits of digits after a 1 that is not stored.  p8p8's 68000 code generator has a
; float in a data register as these 32 bits, and calls the routines here: the left
; operand in d0, the right one in d1, the result in d0.  They keep every register but
; d0, d1, a0 and a1.
;
; Results are rounded to the nearest float (a tie to the even one).  A number too
; small for a normal float is 0 (there are no denormals), one too large is infinity.
; A NaN is not looked for: what is infinite or not a number in is something large out.

; Where a subroutine's declaration names the FPU's registers FP0 to FP7 for its floats
; (an asmsub's parameters, the floats among several results), the floats are in the
; cells of p8f_fp here, four bytes each.

    section .bss,bss
    even
p8f_fp:
    ds.l    8

    section .text,code

; ---- d0 = d0 - d1, d0 = d0 + d1 ----

p8f_sub:
    bchg    #31,d1
p8f_add:
    movem.l d2-d6,-(sp)
    move.l  d0,d2
    swap    d2
    lsr.w   #7,d2
    and.w   #$ff,d2                 ; d2: the exponent of d0
    move.l  d1,d3
    swap    d3
    lsr.w   #7,d3
    and.w   #$ff,d3                 ; d3: the exponent of d1
    beq     .done                   ; d1 is 0: the result is d0
    tst.w   d2
    bne.s   .both
    move.l  d1,d0                   ; d0 is 0: the result is d1
    bra     .done
.both:
    cmp.w   d3,d2
    bhs.s   .ordered
    exg     d0,d1                   ; the one with the larger exponent in d0
    exg     d2,d3
.ordered:
    move.w  d2,d4
    sub.w   d3,d4                   ; d4: how far the smaller one is shifted
    cmp.w   #25,d4
    bhi     .done                   ; too small to count
    move.l  d0,d5                   ; d5: the result's sign (bit 31)
    move.l  d0,d6
    eor.l   d1,d6                   ; d6 bit 31: the signs differ
    and.l   #$007fffff,d0
    or.l    #$00800000,d0
    lsl.l   #6,d0                   ; the digits with six bits below them
    and.l   #$007fffff,d1
    or.l    #$00800000,d1
    lsl.l   #6,d1
    move.l  d1,d3
    lsr.l   d4,d1
    move.l  d1,a0
    lsl.l   d4,d1
    cmp.l   d3,d1
    sne     d3
    move.l  a0,d1
    tst.b   d3
    beq.s   .exact
    or.b    #1,d1                   ; (what was shifted out still counts for the rounding)
.exact:
    tst.l   d6
    bmi.s   .subtract
    add.l   d1,d0
    btst    #30,d0
    beq.s   .round
    lsr.l   #1,d0                   ; a carry: one place down
    bcc.s   .up
    or.b    #1,d0
.up:
    addq.w  #1,d2
    bra.s   .round
.subtract:
    sub.l   d1,d0
    beq     .zero
    bpl.s   .normal
    neg.l   d0
    bchg    #31,d5
.normal:
    btst    #29,d0
    bne.s   .round
    lsl.l   #1,d0
    subq.w  #1,d2
    bgt.s   .normal
    bra.s   .zero
.round:
    move.b  d0,d3
    and.b   #$3f,d3
    cmp.b   #$20,d3
    blo.s   .pack
    bhi.s   .round_up
    btst    #6,d0                   ; a tie: to the even one
    beq.s   .pack
.round_up:
    add.l   #$40,d0
    btst    #30,d0
    beq.s   .pack
    lsr.l   #1,d0
    addq.w  #1,d2
.pack:
    cmp.w   #255,d2
    bhs.s   .infinite
    lsr.l   #6,d0
    and.l   #$007fffff,d0
    swap    d2
    clr.w   d2
    lsl.l   #7,d2
    or.l    d2,d0
    and.l   #$80000000,d5
    or.l    d5,d0
.done:
    movem.l (sp)+,d2-d6
    rts
.zero:
    moveq   #0,d0
    bra.s   .done
.infinite:
    move.l  #$7f800000,d0
    and.l   #$80000000,d5
    or.l    d5,d0
    bra.s   .done

; ---- d0 = d0 * d1 ----

p8f_mul:
    movem.l d2-d6,-(sp)
    move.l  d0,d5
    eor.l   d1,d5                   ; d5 bit 31: the result's sign
    move.l  d0,d2
    swap    d2
    lsr.w   #7,d2
    and.w   #$ff,d2
    beq     .zero
    move.l  d1,d3
    swap    d3
    lsr.w   #7,d3
    and.w   #$ff,d3
    beq     .zero
    add.w   d3,d2
    sub.w   #127,d2                 ; d2: the exponent
    and.l   #$007fffff,d0
    or.l    #$00800000,d0
    and.l   #$007fffff,d1
    or.l    #$00800000,d1
    ; 24 bits by 24 bits as (a:b) * (c:d), a and c the upper 8 bits
    move.l  d0,d3
    swap    d3                      ; d3.w: a
    move.l  d1,d4
    swap    d4                      ; d4.w: c
    move.w  d3,d6
    mulu.w  d4,d6                   ; d6: a*c, the upper part
    mulu.w  d1,d3                   ; d3: a*d
    mulu.w  d0,d4                   ; d4: b*c
    add.l   d4,d3                   ; d3: the middle part (25 bits)
    mulu.w  d1,d0                   ; d0: b*d, the lower part
    move.l  d3,d4
    swap    d4
    clr.w   d4                      ; d4: the middle part's lower half, shifted up
    clr.w   d3
    swap    d3                      ; d3: its upper half
    add.l   d4,d0
    addx.l  d3,d6                   ; d6:d0 is the product, 48 bits
    ; its upper 32 bits, with whether anything was below them
    move.w  d0,d4
    swap    d6
    clr.w   d6
    clr.w   d0
    swap    d0
    or.l    d6,d0
    tst.w   d4
    beq.s   .exact
    or.b    #1,d0
.exact:
    tst.l   d0
    bmi.s   .top
    lsl.l   #1,d0                   ; (between 1 and 2: the first bit to the top)
    bra.s   .round
.top:
    addq.w  #1,d2
.round:
    cmp.b   #$80,d0
    blo.s   .pack
    bhi.s   .round_up
    btst    #8,d0
    beq.s   .pack
.round_up:
    add.l   #$100,d0
    bcc.s   .pack
    move.l  #$80000000,d0
    addq.w  #1,d2
.pack:
    tst.w   d2
    ble.s   .zero
    cmp.w   #255,d2
    bhs.s   .infinite
    lsr.l   #8,d0
    and.l   #$007fffff,d0
    swap    d2
    clr.w   d2
    lsl.l   #7,d2
    or.l    d2,d0
    and.l   #$80000000,d5
    or.l    d5,d0
.done:
    movem.l (sp)+,d2-d6
    rts
.zero:
    moveq   #0,d0
    bra.s   .done
.infinite:
    move.l  #$7f800000,d0
    and.l   #$80000000,d5
    or.l    d5,d0
    bra.s   .done

; ---- d0 = d0 / d1 ----

p8f_div:
    movem.l d2-d6,-(sp)
    move.l  d0,d5
    eor.l   d1,d5                   ; d5 bit 31: the result's sign
    move.l  d1,d3
    swap    d3
    lsr.w   #7,d3
    and.w   #$ff,d3
    beq     .infinite               ; by 0
    move.l  d0,d2
    swap    d2
    lsr.w   #7,d2
    and.w   #$ff,d2
    beq     .zero
    sub.w   d3,d2
    add.w   #127,d2                 ; d2: the exponent
    and.l   #$007fffff,d0
    or.l    #$00800000,d0
    and.l   #$007fffff,d1
    or.l    #$00800000,d1
    cmp.l   d1,d0
    bhs.s   .start
    lsl.l   #1,d0                   ; (so that the quotient is between 1 and 2)
    subq.w  #1,d2
.start:
    moveq   #0,d3                   ; d3: the quotient, 24 bits and one more
    moveq   #24,d4
.next:
    lsl.l   #1,d3
    cmp.l   d1,d0
    blo.s   .less
    sub.l   d1,d0
    addq.l  #1,d3
.less:
    lsl.l   #1,d0
    dbra    d4,.next
    ; round: the last bit is half a place, and what is left of the dividend counts
    lsr.l   #1,d3
    bcc.s   .pack
    tst.l   d0
    bne.s   .round_up
    btst    #0,d3
    beq.s   .pack
.round_up:
    addq.l  #1,d3
    btst    #24,d3
    beq.s   .pack
    lsr.l   #1,d3
    addq.w  #1,d2
.pack:
    tst.w   d2
    ble.s   .zero
    cmp.w   #255,d2
    bhs.s   .infinite
    move.l  d3,d0
    and.l   #$007fffff,d0
    swap    d2
    clr.w   d2
    lsl.l   #7,d2
    or.l    d2,d0
    and.l   #$80000000,d5
    or.l    d5,d0
.done:
    movem.l (sp)+,d2-d6
    rts
.zero:
    moveq   #0,d0
    bra.s   .done
.infinite:
    move.l  #$7f800000,d0
    and.l   #$80000000,d5
    or.l    d5,d0
    bra.s   .done

; ---- d0 = -1, 0 or 1: d0 is less than, the same as or more than d1 ----

p8f_cmp:
    move.l  d2,-(sp)
    move.l  d0,d2
    or.l    d1,d2
    add.l   d2,d2
    beq.s   .same                   ; both are 0, of either sign
    move.l  d0,d2
    eor.l   d1,d2
    bpl.s   .one_sign
    tst.l   d0                      ; the signs differ: the negative one is less
    bmi.s   .less
    bra.s   .more
.one_sign:
    cmp.l   d1,d0
    beq.s   .same
    bhi.s   .larger
    tst.l   d0                      ; d0 is the smaller amount: less when they are positive
    bmi.s   .more
    bra.s   .less
.larger:
    tst.l   d0
    bmi.s   .less
.more:
    moveq   #1,d0
    bra.s   .done
.less:
    moveq   #-1,d0
    bra.s   .done
.same:
    moveq   #0,d0
.done:
    move.l  (sp)+,d2
    rts

; ---- d0 = -1, 0 or 1: the sign of d0 ----

p8f_sgn:
    move.l  d0,d1
    add.l   d1,d1
    beq.s   .zero
    tst.l   d0
    bmi.s   .minus
    moveq   #1,d0
    rts
.minus:
    moveq   #-1,d0
    rts
.zero:
    moveq   #0,d0
    rts

; ---- d0 = the float of the long in d0 ----

p8f_fromsl:
    movem.l d2-d3,-(sp)
    move.l  d0,d3                   ; d3 bit 31: the sign
    beq.s   .done
    bpl.s   .positive
    neg.l   d0
.positive:
    move.w  #127+31,d2              ; d2: the exponent, when the first bit is at the top
.normal:
    tst.l   d0
    bmi.s   .round
    lsl.l   #1,d0
    subq.w  #1,d2
    bra.s   .normal
.round:
    cmp.b   #$80,d0
    blo.s   .pack
    bhi.s   .round_up
    btst    #8,d0
    beq.s   .pack
.round_up:
    add.l   #$100,d0
    bcc.s   .pack
    move.l  #$80000000,d0
    addq.w  #1,d2
.pack:
    lsr.l   #8,d0
    and.l   #$007fffff,d0
    swap    d2
    clr.w   d2
    lsl.l   #7,d2
    or.l    d2,d0
    and.l   #$80000000,d3
    or.l    d3,d0
.done:
    movem.l (sp)+,d2-d3
    rts

; ---- d0 = the long of the float in d0, what is after the point cut off ----

p8f_tosl:
    movem.l d2-d3,-(sp)
    move.l  d0,d3                   ; d3 bit 31: the sign
    move.l  d0,d2
    swap    d2
    lsr.w   #7,d2
    and.w   #$ff,d2
    sub.w   #127,d2                 ; d2: the exponent
    bmi.s   .zero                   ; less than 1
    cmp.w   #30,d2
    bhi.s   .most
    and.l   #$007fffff,d0
    or.l    #$00800000,d0
    sub.w   #23,d2
    bmi.s   .down
    lsl.l   d2,d0
    bra.s   .sign
.down:
    neg.w   d2
    lsr.l   d2,d0
.sign:
    tst.l   d3
    bpl.s   .done
    neg.l   d0
.done:
    movem.l (sp)+,d2-d3
    rts
.zero:
    moveq   #0,d0
    bra.s   .done
.most:
    move.l  #$7fffffff,d0           ; too large for a long: the largest there is
    tst.l   d3
    bpl.s   .done
    addq.l  #1,d0
    bra.s   .done

; ---- d0 = the square root of d0 (0 for a negative number) ----
; A first guess from the bits (half the exponent), then Newton's steps: y = (y + x/y) / 2.

p8f_sqrt:
    movem.l d2-d4,-(sp)
    move.l  d0,d2                   ; d2: x
    ble.s   .zero                   ; 0 or negative
    lsr.l   #1,d0
    add.l   #$1fc00000,d0
    move.l  d0,d3                   ; d3: y
    moveq   #3,d4
.step:
    move.l  d2,d0
    move.l  d3,d1
    bsr     p8f_div
    move.l  d3,d1
    bsr     p8f_add
    sub.l   #$00800000,d0           ; half of it
    move.l  d0,d3
    dbra    d4,.step
.done:
    movem.l (sp)+,d2-d4
    rts
.zero:
    moveq   #0,d0
    bra.s   .done
