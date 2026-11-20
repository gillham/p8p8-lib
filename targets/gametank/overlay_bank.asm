; Overlays in the banks of a GameTank cartridge (p8p8): what the thunks and stubs of the
; target file use.  p8c includes this file in a program with overlays.
;
; The cartridge's bank is the program's own while its main part runs: what it chooses
; with cartbank (a bank of assets) stays chosen, also across code that is in an
; overlay.  So an overlay's bank is in the window only while its code runs, and the bank
; the main program had is kept in p8_overlay_outside meanwhile:
;   into an overlay from the main program    outside = the bank; the overlay's bank;
;                                            afterwards the bank = outside
;   out of an overlay into the main program  the bank = outside; afterwards
;                                            outside = the bank; the overlay's bank
;   from one overlay into another            that one's bank, and afterwards this one's
; The program is in ROM, so these bytes are with the variables.

        .section BSS
p8_overlay_a        .byte  ?    ; A on its way into or out of a subroutine
p8_overlay_p        .byte  ?    ; and the flags, for a subroutine in assembly
p8_overlay_outside  .byte  ?    ; the bank of the main program, while an overlay runs
        .send BSS

; before a call out of an overlay: the main program's bank
p8_overlay_leave    .proc
        sta  p8_overlay_a
        lda  p8_overlay_outside
        jsr  cartbank
        lda  p8_overlay_a
        rts
        .pend

; the same with the flags kept, for a subroutine in assembly
p8_overlay_leave_p  .proc
        php
        sta  p8_overlay_a
        pla
        sta  p8_overlay_p
        lda  p8_overlay_outside
        jsr  cartbank
        lda  p8_overlay_p
        pha
        lda  p8_overlay_a
        plp
        rts
        .pend

; after a call into an overlay from the main program: the main program's bank again
p8_overlay_out      .proc
        sta  p8_overlay_a
        lda  p8_overlay_outside
        jsr  cartbank
        lda  p8_overlay_a
        rts
        .pend

p8_overlay_out_p    .proc
        php
        sta  p8_overlay_a
        pla
        sta  p8_overlay_p
        lda  p8_overlay_outside
        jsr  cartbank
        lda  p8_overlay_p
        pha
        lda  p8_overlay_a
        plp
        rts
        .pend
