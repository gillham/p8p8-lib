; Overlays in the MEGA65's memory beyond the first 64 KB (p8p8).
;
; p8c includes this file in a program with overlays (%overlay n).  An overlay's code is
; kept in far memory (from p8_overlay_store on, one after the other) and runs in a
; window of main memory, one overlay at a time: a call into an overlay goes through
; "call" below, which copies the overlay into the window with the DMA controller when
; another one is there, calls the subroutine, and afterwards copies the overlay of its
; caller back in.  Overlays are code only, so nothing is ever written back.
;
; The first call reads the program's file of overlays (name.non, beside the program on
; drive 8) and puts each one into far memory.  The file is a list of records: length
; (2 bytes), address (2 bytes), that many bytes; a length of 0 ends it.  A record of
; one byte at p8_overlay_select says which overlay the next record is.
;
; p8c defines before the include:
;       p8_overlay_window       where an overlay runs
;       p8_overlay_size         the size of that window (whole pages)
;       p8_overlay_sizes        a table: the size of each overlay's code (words, overlay 1 first)
;       p8_overlay_select       the address of the records that name an overlay
;       p8_overlay_store        where the overlays are kept (28 bits, a multiple of 64 KB)
;       p8_overlay_file         a macro with the file's name as .text

p8_overlay      .proc

DMA_LIST_HIGH   = $d701
DMA_LIST_BANK   = $d702
DMA_LIST_MB     = $d704
DMA_LIST_LOW    = $d705         ; (writing this one starts the job)
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

; from the thunk of an ordinary subroutine, which looks itself whether the overlay is
; there: overlay A into the window, X and Y as they are
bring_keeping
        stx  save_x
        sty  save_y
        jsr  bring
        ldx  save_x
        ldy  save_y
        rts

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
        clc                     ; from far memory into the window
        jmp  transfer
+       rts

; overlay A between far memory and the window; carry set: into far memory
transfer
        php
        pha
        sec
        sbc  #1
        asl  a                  ; its size: only that much is copied
        tay
        lda  p8_overlay_sizes,y
        sta  job_count
        lda  p8_overlay_sizes+1,y
        sta  job_count+1
        ora  job_count
        bne  +
        pla                     ; (an overlay with nothing in it)
        plp
        rts
+       pla
        tax                     ; its place: the store, and a window's size for each one before it
        lda  #0
        sta  far_place
        lda  #<(p8_overlay_store >> 16)
        sta  far_place+1
-       dex
        beq  +
        clc
        lda  far_place
        adc  #>p8_overlay_size
        sta  far_place
        bcc  -
        inc  far_place+1
        bne  -
+       plp
        bcs  +
        ; source: far memory; target: the window
        lda  #(p8_overlay_store >> 20)
        sta  job_source_mb
        lda  #0
        sta  job_target_mb
        sta  job_source
        sta  job_target+2
        lda  far_place
        sta  job_source+1
        lda  far_place+1
        and  #15
        sta  job_source+2
        lda  #<p8_overlay_window
        sta  job_target
        lda  #>p8_overlay_window
        sta  job_target+1
        jmp  ++
+       lda  #(p8_overlay_store >> 20)
        sta  job_target_mb
        lda  #0
        sta  job_source_mb
        sta  job_target
        sta  job_source+2
        lda  far_place
        sta  job_target+1
        lda  far_place+1
        and  #15
        sta  job_target+2
        lda  #<p8_overlay_window
        sta  job_source
        lda  #>p8_overlay_window
        sta  job_source+1
+       lda  #0
        sta  DMA_LIST_BANK
        sta  DMA_LIST_MB
        lda  #>job
        sta  DMA_LIST_HIGH
        lda  #<job
        sta  DMA_LIST_LOW
        rts

; the program's file of overlays into far memory, once
load
        lda  #$80
        sta  loaded
        lda  #fname_end-fname
        ldx  #<fname
        ldy  #>fname
        jsr  SETNAM
        lda  #2
        ldx  #8
        ldy  #2
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
        sec                     ; from the window into far memory
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
        ldx  #0
-       lda  message_file,x
        beq  +
        jsr  CHROUT
        inx
        bne  -
+       ldx  prog8_lib.orig_stackpointer        ; the program ends here
        txs
        jmp  p8_sys_startup.cleanup_at_exit

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
far_place       .byte  0, 0     ; an overlay's place in far memory: the middle byte and the bank

; the DMA controller's orders (the F018B form, with the megabytes of both ends)
job             .byte  $0b
                .byte  $80
job_source_mb   .byte  0
                .byte  $81
job_target_mb   .byte  0
                .byte  $00
                .byte  $00      ; copy
job_count       .word  0
job_source      .byte  0, 0, 0
job_target      .byte  0, 0, 0
                .byte  0
                .word  0
        .pend
