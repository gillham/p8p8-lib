; Overlays in the Commander X16's banks of high memory (p8p8): what the thunks and stubs
; of the target file use.  p8c includes this file in a program with overlays.
;
; The RAM bank's register is the program's own while its main part runs: what it chooses
; there (its banked data) stays chosen, also across code that is in an overlay.  So the
; overlay's bank is in the window only while the overlay's code runs, and the bank the
; main program had is kept in p8_overlay_outside meanwhile:
;   into an overlay from the main program    outside = the bank; the overlay's bank;
;                                            afterwards the bank = outside
;   out of an overlay into the main program  the bank = outside; afterwards
;                                            outside = the bank; the overlay's bank
;   from one overlay into another            that one's bank, and afterwards this one's

p8_overlay_a        .byte  0    ; A on its way into or out of a subroutine
p8_overlay_p        .byte  0    ; and the flags, for a subroutine in assembly
p8_overlay_outside  .byte  0    ; the bank of the main program, while an overlay runs

; before a call out of an overlay: the main program's bank
p8_overlay_leave    .proc
        sta  p8_overlay_a
        lda  p8_overlay_outside
        sta  $00
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
        sta  $00
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
        sta  $00
        lda  p8_overlay_a
        rts
        .pend

p8_overlay_out_p    .proc
        php
        sta  p8_overlay_a
        pla
        sta  p8_overlay_p
        lda  p8_overlay_outside
        sta  $00
        lda  p8_overlay_p
        pha
        lda  p8_overlay_a
        plp
        rts
        .pend
