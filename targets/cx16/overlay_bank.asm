; Overlays in the Commander X16's banks of high memory (p8p8): what the thunks of the
; target file keep while they change the bank.  p8c includes this file in a program
; with overlays.  (A thunk is written for each subroutine, so a call costs no more than
; the instructions that change the bank and put it back.)

p8_overlay_a    .byte  0        ; A on its way into or out of a subroutine
p8_overlay_p    .byte  0        ; and the flags, for a subroutine in assembly
