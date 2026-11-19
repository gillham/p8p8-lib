; The loader of a program with overlays, for the Commander X16 (p8p8).
;
; p8c writes two files for such a program: this loader as name.prg, and name.non with
; the main program and every overlay.  The loader moves itself into the "golden RAM" at
; $0400, where nothing it loads can land on it, reads the file and jumps to the
; program.  The file is a list of records in 64tass's nonlinear format:
;       length (2 bytes), address (2 bytes), that many bytes;    a length of 0 ends it
; A record of one byte at address 0 chooses the RAM bank, so that the record after it
; puts an overlay into that bank's window at $a000.
;
; (After X16 Golden Loader, https://github.com/gillham/GoldenLoader.)
;
; p8c assembles this file from a few lines that define
;       p8_entry        where the program begins
;       p8_file         a macro with the file's name as .text

SETLFS  = $ffba
SETNAM  = $ffbd
OPEN    = $ffc0
CLOSE   = $ffc3
CHKIN   = $ffc6
CLRCHN  = $ffcc
CHRIN   = $ffcf
CHROUT  = $ffd2
READST  = $ffb7
MACPTR  = $ff44

left    = $22           ; what is left of the record
ptr     = $24           ; where its next byte goes
count   = $26           ; how many bytes the ROM read in one go

* = $0801
        .word  (+), 2026
        .null  $9e, format(" %d ", start)
+       .word  0
start
        ldx  #0
-       lda  image,x
        sta  $0400,x
        lda  image+$100,x
        sta  $0500,x
        inx
        bne  -
        jmp  $0400

image   .logical $0400
        lda  #fname_end-fname
        ldx  #<fname
        ldy  #>fname
        jsr  SETNAM
        lda  #2
        ldx  #8
        ldy  #2
        jsr  SETLFS
        jsr  OPEN
        bcs  +
        ldx  #2
        jsr  CHKIN
        bcc  record
+       jmp  failed
record
        jsr  byte
        sta  left
        jsr  byte
        sta  left+1
        ora  left
        beq  done
        jsr  byte
        sta  ptr
        jsr  byte
        sta  ptr+1
        ; a few bytes (the bank's number above all) one by one, by this code: the ROM
        ; puts the bank back that was there when it was called
        lda  left+1
        bne  body
        lda  left
        cmp  #16
        bcc  slow
body
        lda  left+1
        beq  +
        lda  #255
        bra  ++
+       lda  left
+       ldx  ptr
        ldy  ptr+1
        clc
        jsr  MACPTR
        bcs  slow               ; (a device that cannot: one by one)
        stx  count
        sty  count+1
        txa
        ora  count+1
        bne  +
        jmp  failed             ; (the file ends inside a record)
+
        clc
        lda  ptr
        adc  count
        sta  ptr
        lda  ptr+1
        adc  count+1
        sta  ptr+1
        sec
        lda  left
        sbc  count
        sta  left
        lda  left+1
        sbc  count+1
        sta  left+1
        ora  left
        bne  body
        bra  record
slow
        jsr  byte
        sta  (ptr)
        inc  ptr
        bne  +
        inc  ptr+1
+       lda  left
        bne  +
        dec  left+1
+       dec  left
        lda  left
        ora  left+1
        bne  slow
        bra  record
done
        jsr  CLRCHN
        lda  #2
        jsr  CLOSE
        jmp  p8_entry
failed
        jsr  CLRCHN
        lda  #2
        jsr  CLOSE
        ldx  #0
-       lda  message,x
        beq  +
        jsr  CHROUT
        inx
        bne  -
+       rts
byte
        jsr  CHRIN
        pha
        jsr  READST
        and  #$82               ; (time out, or no such device)
        bne  +
        pla
        rts
+       pla
        pla
        pla
        bra  failed
message .null  "?cannot load the program's file", 13
fname   #p8_file
fname_end
        .cerror * > $0600, "the overlay loader is larger than two pages"
        .here
