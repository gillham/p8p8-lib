; Overlays in a RAM Expansion Unit (p8p8), for the C64 and the C128.
;
; p8c includes this file in a program with overlays (%overlay n).  An overlay's code is
; kept in the REU and runs in a window of main memory, one overlay at a time: a call
; into an overlay goes through "call" below, which fetches the overlay into the window
; when another one is there, calls the subroutine, and afterwards fetches the overlay
; of its caller back.  Overlays are code only, so nothing is ever written back.
;
; The first call reads the program's file of overlays (name.non, beside the program on
; the disk it was loaded from) and puts each one into the REU.  The file is a list of
; records: length (2 bytes), address (2 bytes), that many bytes; a length of 0 ends it.
; A record of one byte at p8_overlay_select says which overlay the next record is.
;
; Overlay n is in the REU from (n - 1) * $1000 on; what the program keeps in the REU
; itself belongs behind the last overlay.
;
; p8c defines before the include:
;       p8_overlay_window       where an overlay runs
;       p8_overlay_size         the size of that window
;       p8_overlay_select       the address of the records that name an overlay
;       p8_overlay_file         a macro with the file's name as .text

p8_overlay      .proc

REU_COMMAND     = $df01
REU_C64BASE     = $df02
REU_REUBASE     = $df04
REU_LENGTH      = $df07
REU_IRQMASK     = $df09
REU_CONTROL     = $df0a
SETLFS  = $ffba
SETNAM  = $ffbd
OPEN    = $ffc0
CLOSE   = $ffc3
CHKIN   = $ffc6
CLRCHN  = $ffcc
CHRIN   = $ffcf
CHROUT  = $ffd2
READST  = $ffb7

; from a thunk:  jsr p8_overlay.call / .byte overlay / .word subroutine
; A, X, Y and the flags go to the subroutine and come back from it as they are.
call
        php
        sta  save_a
        stx  save_x
        sty  save_y
        pla
        sta  save_p
        pla                     ; the thunk's three bytes are behind its jsr
        sta  thunk+1
        pla
        sta  thunk+2
        ldy  #3
-
thunk   lda  $ffff,y
        sta  wanted-1,y
        dey
        bne  -
        lda  wanted+1
        sta  target+1
        lda  wanted+2
        sta  target+2
        lda  current            ; what is in now comes back afterwards
        pha
        lda  wanted
        jsr  bring
        lda  save_p
        pha
        lda  save_a
        ldx  save_x
        ldy  save_y
        plp
target  jsr  $ffff
        php
        sta  save_a
        stx  save_x
        sty  save_y
        pla
        sta  save_p
        pla
        jsr  bring
        lda  save_p
        pha
        lda  save_a
        ldx  save_x
        ldy  save_y
        plp
        rts                     ; to where the thunk was called from

; overlay A into the window, unless it is there (0: whatever is there may stay)
bring
        cmp  #0
        beq  +
        cmp  current
        beq  +
        sta  current
        bit  loaded
        bmi  fetch
        jsr  load
fetch   lda  current
        ldx  #$91               ; from the REU into main memory, now
        jmp  transfer
+       rts

; overlay A between the REU and the window; X is the REU's command
transfer
        sec
        sbc  #1
        pha
        asl  a
        asl  a
        asl  a
        asl  a
        sta  REU_REUBASE+1
        pla
        lsr  a
        lsr  a
        lsr  a
        lsr  a
        sta  REU_REUBASE+2
        lda  #0
        sta  REU_REUBASE
        sta  REU_IRQMASK
        sta  REU_CONTROL
        lda  #<p8_overlay_window
        sta  REU_C64BASE
        lda  #>p8_overlay_window
        sta  REU_C64BASE+1
        lda  #<p8_overlay_size
        sta  REU_LENGTH
        lda  #>p8_overlay_size
        sta  REU_LENGTH+1
        stx  REU_COMMAND
        rts

; the program's file of overlays into the REU, once
load
        lda  #$80
        sta  loaded
        lda  #$55               ; is there an REU?  (its registers keep what is written)
        sta  REU_C64BASE
        cmp  REU_C64BASE
        bne  no_reu
        lda  #$aa
        sta  REU_C64BASE
        cmp  REU_C64BASE
        bne  no_reu
        lda  #fname_end-fname
        ldx  #<fname
        ldy  #>fname
        jsr  SETNAM
        lda  #2
        ldx  $ba                ; the device the program came from
        bne  +
        ldx  #8
+       ldy  #2
        jsr  SETLFS
        jsr  OPEN
        bcs  no_file
        ldx  #2
        jsr  CHKIN
        bcs  no_file
record
        jsr  byte
        sta  left
        jsr  byte
        sta  left+1
        ora  left
        beq  loaded_all
        jsr  byte
        sta  store+1
        jsr  byte
        sta  store+2
        cmp  #>p8_overlay_select
        bne  body
        lda  store+1
        cmp  #<p8_overlay_select
        bne  body
        jsr  byte               ; which overlay comes next
        sta  loading
        jmp  record
body
        jsr  byte
store   sta  $ffff
        inc  store+1
        bne  +
        inc  store+2
+       lda  left
        bne  +
        dec  left+1
+       dec  left
        lda  left
        ora  left+1
        bne  body
        lda  loading
        ldx  #$90               ; from main memory into the REU, now
        jsr  transfer
        jmp  record
loaded_all
        jsr  CLRCHN
        lda  #2
        jmp  CLOSE

byte
        jsr  CHRIN
        pha
        jsr  READST
        and  #$83               ; (time out, or no such device)
        bne  +
        pla
        rts
+       pla
no_file
        jsr  CLRCHN
        lda  #2
        jsr  CLOSE
        ldx  #message_file-message_reu
        .byte  $2c              ; (skips the next instruction)
no_reu
        ldx  #0
-       lda  message_reu,x
        beq  +
        jsr  CHROUT
        inx
        bne  -
+       ldx  prog8_lib.orig_stackpointer        ; the program ends here
        txs
        jmp  p8_sys_startup.cleanup_at_exit

message_reu     .null  13, "?overlays need a ram expansion unit", 13
message_file    .null  13, "?cannot load the program's overlays", 13
fname           #p8_overlay_file
fname_end

; (in the program's memory: a thunk's three bytes, and what the call keeps)
wanted          .byte  0, 0, 0
current         .byte  0        ; the overlay in the window (0: none yet)
loaded          .byte  0        ; $80 when the file has been read
loading         .byte  0
left            .word  0
save_a          .byte  0
save_x          .byte  0
save_y          .byte  0
save_p          .byte  0
        .pend
