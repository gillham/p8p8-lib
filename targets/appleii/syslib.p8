; Prog8 definitions for the Apple II(e).

%option no_symbol_prefixing, ignore_unused

;
; Compatibility functions for shared textio code.
;
cbm {
    ; The names the shared text routines call.  Characters are ASCII; the monitor wants
    ; the high bit set, and gives it on a key.

    asmsub CHRIN() -> ubyte @A {
        ; ---- the next character of a line typed at the keyboard, as on the Commodores:
        ;      the first call reads a whole line with the monitor's line editing (GETLN),
        ;      and this and the next calls give its characters, the RETURN (13) last.
        ;      X and Y are kept.
        %asm {{
            stx  _savex
            sty  _savey
            lda  _reading
            bne  _next
            jsr  appleii.GETLN1
            lda  #0
            sta  _index
            inc  _reading
_next       ldx  _index
            inc  _index
            lda  appleii.INBUF,x
            and  #$7f
            cmp  #13
            bne  +
            ldx  #0
            stx  _reading
+           ldx  _savex
            ldy  _savey
            rts

            .section BSS
_reading    .byte ?
_index      .byte ?
_savex      .byte ?
_savey      .byte ?
            .send BSS
            ; !notreached!
        }}
    }

    asmsub CHROUT(ubyte character @ A) {
        ; ---- print the character where the cursor is, through the monitor's output hook
        ;      (so an 80 column card or a printer gets it too).  A new line is 13 or 10.
        ;      Four of the Commodores' codes do here what they do there, for the text
        ;      routines the machines share: 147 clears the screen, 19 puts the cursor at
        ;      the top left, 18 and 146 turn inverse text on and off.  Inverse text has no
        ;      lower case: such a letter is shown as its capital.
        ;      A, X and Y are kept.
        %asm {{
            pha
            cmp  #10
            beq  _newline
            cmp  #147
            beq  _clear
            cmp  #19
            beq  _home
            cmp  #18
            beq  _inverse
            cmp  #146
            beq  _normal
            ora  #$80
            cmp  #$e0
            bcc  _out
            bit  appleii.INVFLG
            bmi  _out
            and  #$df           ; inverse (and flashing) text has no lower case: the capital
_out        jsr  appleii.COUT
            pla
            rts
_newline    lda  #$8d
            bne  _out
_clear      tya
            pha
            jsr  appleii.HOME
            pla
            tay
            pla
            rts
_home       lda  #0
            sta  appleii.CH
            jsr  appleii.TABV
            pla
            rts
_inverse    lda  #appleii.REVERSE_TEXT
            .byte  $2c          ; (BIT: the next instruction is passed by)
_normal     lda  #appleii.NORMAL_TEXT
            sta  appleii.INVFLG
            pla
            rts
        }}
    }

    asmsub GETIN() -> bool @Pc, ubyte @A {
        ; ---- the key that is pressed, or 0 when there is none, without waiting
        %asm {{
            lda  appleii.KBD
            bpl  _none
            bit  appleii.KBDSTRB
            and  #$7f
            clc
            rts
_none       lda  #0
            clc
            rts
        }}
    }

    inline asmsub GETIN2() -> ubyte @A {
        ; -- just like GETIN, but omits the carry flag result value.
        ;    just for convenience because GETIN is so often used to just read keyboard input,
        ;    where you don't have to deal with a potential error status
        %asm {{
            jsr  cbm.GETIN
        }}
    }

    asmsub STOP() -> bool @Pz, ubyte @A {
        ; ---- is the break key pressed?  On the Apple II that is Control-C, as in BASIC.
        ;      It is taken when it is the key that is waiting; any other key stays for
        ;      GETIN.  A is the key that is waiting, with its high bit set.
        %asm {{
            lda  appleii.KBD
            cmp  #$83
            bne  +
            sta  appleii.KBDSTRB
+           rts
        }}
    }

    inline asmsub STOP2() -> bool @Pz {
        ; -- just like STOP, but omits the key in A
        %asm {{
            jsr  cbm.STOP
        }}
    }

    asmsub PLOT(ubyte col @Y, ubyte row @A) {
        ; ---- put the cursor at the column and row (0,0 is the top left)
        %asm {{
            sty  appleii.CH
            jmp  appleii.TABV
        }}
    }
}

appleii {

    ; the monitor's zero page
    &ubyte WNDLFT = $20         ; the text window: left column, width, top row, bottom row + 1
    &ubyte WNDWDTH = $21
    &ubyte WNDTOP = $22
    &ubyte WNDBTM = $23
    &ubyte CH = $24             ; the cursor's column in the window
    &ubyte CV = $25             ; the cursor's row
    &uword BASL = $28           ; the address of the cursor's row
    &ubyte INVFLG = $32         ; $ff normal, $3f inverse, $7f flashing
    &ubyte PROMPT = $33         ; the prompt character of GETLN
    &uword CSWL = $36           ; the output hook
    &uword KSWL = $38           ; the input hook
    const ubyte REVERSE_TEXT = $3f
    const ubyte NORMAL_TEXT = $ff

    const uword Screen      = $0400     ; the first row; the rows are not in order (see txt.rowaddress)
    const uword INBUF       = $0200     ; the line GETLN reads

    ; the hardware
    &ubyte KBD              = $C000     ; the last key, bit 7 set when there is a new one
    &ubyte KBDSTRB          = $C010     ; any access: the key is taken
    &ubyte altcharset       = $C00F
    &ubyte speaker          = $C030     ; any access moves the speaker's cone

    ; the monitor's routines
    const uword ROM_INIT_S3 = $C300
    const uword COUT        = $FDED
    const uword COUT1       = $FDF0
    extsub $fb5b = TABV(ubyte row @ A) clobbers(A)      ; the cursor to the row, CH kept
    extsub $fc22 = VTAB() clobbers(A)                   ; the cursor to row CV
    extsub $fc58 = HOME() clobbers(A,Y)                 ; clear the window, cursor to its top left
    extsub $fc70 = SCROLL() clobbers(A,Y)               ; the window one row up, the last row cleared
    extsub $fc9c = CLREOL() clobbers(A,Y)               ; clear from the cursor to the end of the row
    extsub $fca8 = WAIT(ubyte count @A) clobbers(A)     ; (26 + 27*A + 5*A*A) / 2 microseconds
    extsub $fd0c = RDKEY() -> ubyte @A                  ; wait for a key (bit 7 set), cursor shown
    extsub $fd6f = GETLN1() -> ubyte @X                 ; read a line to INBUF without a prompt; X = its length
    extsub $fdf0 = cout1(ubyte character @ A)           ; print on the 40 column screen, past the output hook
    extsub $fe80 = SETINV() clobbers(Y)                 ; inverse text from now on
    extsub $fe84 = SETNORM() clobbers(Y)                ; normal text from now on
    extsub $ff3a = BELL() clobbers(A)

    ; 6502 standard vectors.
    &uword  NMI_VEC         = $FFFA     ; 6502 nmi vector
    &uword  RESET_VEC       = $FFFC     ; 6502 reset vector
    &uword  IRQ_VEC         = $FFFE     ; 6502 interrupt vector

    asmsub rom_init_slot(ubyte slot @A) {
        ; ---- start the firmware of the card in the slot (3: the 80 column card)
        %asm {{
            clc
            adc #$c0
            sta P8ZP_SCRATCH_PTR+1
            lda #$00
            sta P8ZP_SCRATCH_PTR
            jmp (P8ZP_SCRATCH_PTR)
        }}
    }
}

%import shared_sys_functions

sys {
    ; ------- lowlevel system routines --------

    const ubyte target = 2         ;  compilation target specifier.  255=virtual, 128=C128, 64=C64, 32=PET, 25=Foenix F256, 16=CommanderX16, 8=atari800XL, 7=Neo6502, 6=wdcsxb6, 2=appleii

    const ubyte SIZEOF_BOOL  = sizeof(bool)
    const ubyte SIZEOF_BYTE  = sizeof(byte)
    const ubyte SIZEOF_UBYTE = sizeof(ubyte)
    const ubyte SIZEOF_WORD  = sizeof(word)
    const ubyte SIZEOF_UWORD = sizeof(uword)
    const ubyte SIZEOF_LONG  = sizeof(long)
    ;const ubyte SIZEOF_POINTER = sizeof(&sys.wait)
    const ubyte SIZEOF_FLOAT = 0    ; undefined, no floats supported
    const byte  MIN_BYTE     = -128
    const byte  MAX_BYTE     = 127
    const ubyte MIN_UBYTE    = 0
    const ubyte MAX_UBYTE    = 255
    const word  MIN_WORD     = -32768
    const word  MAX_WORD     = 32767
    const uword MIN_UWORD    = 0
    const uword MAX_UWORD    = 65535
    ; MIN_FLOAT and MAX_FLOAT are defined in the floats module if importec


    asmsub  reset_system()  {
        ; Soft-reset the system back to initial power-on status
        %asm {{
            sei
            jmp  (appleii.RESET_VEC)
        }}
    }

    sub wait(uword jiffies) {
        ; --- wait approximately the given number of jiffies (1/60th seconds): the monitor's
        ;     delay loop, timed for the 1 MHz machine (an accelerator makes it shorter)
        repeat jiffies
            appleii.WAIT(79)
    }

    asmsub waitvsync() clobbers(A) {
        ; --- wait a 60th of a second.  Only the IIe and later can tell where the screen's
        ;     beam is, so this is the delay loop and not the real vertical blank.
        %asm {{
            lda  #79
            jmp  appleii.WAIT
        }}
    }

    asmsub internal_stringcopy(uword source @R0, uword target @AY) clobbers (A,Y) {
        ; Called when the compiler wants to assign a string value to another string.
        %asm {{
		sta  P8ZP_SCRATCH_W1
		sty  P8ZP_SCRATCH_W1+1
		lda  cx16.r0
		ldy  cx16.r0+1
		jmp  prog8_lib.strcpy
        }}
    }

    sub disable_caseswitch() {
        ; no-op
    }

    sub enable_caseswitch() {
        ; no-op
    }

    asmsub exit(ubyte returnvalue @A) {
        ; -- immediately exit the program with a return code in the A register
        %asm {{
            sta  p8_sys_startup.cleanup_at_exit._exitcode
            ldx  prog8_lib.orig_stackpointer
            txs
            jmp  p8_sys_startup.cleanup_at_exit
        }}
    }

    asmsub exit2(ubyte resulta @A, ubyte resultx @X, ubyte resulty @Y) {
        ; -- immediately exit the program with result values in the A, X and Y registers.
        %asm {{
            sta  p8_sys_startup.cleanup_at_exit._exitcode
            stx  p8_sys_startup.cleanup_at_exit._exitcodeX
            sty  p8_sys_startup.cleanup_at_exit._exitcodeY
            ldx  prog8_lib.orig_stackpointer
            txs
            jmp  p8_sys_startup.cleanup_at_exit
        }}
    }

    asmsub exit3(ubyte resulta @A, ubyte resultx @X, ubyte resulty @Y, bool carry @Pc) {
        ; -- immediately exit the program with result values in the A, X and Y registers, and the Carry flag in the status register.
        %asm {{
            sta  p8_sys_startup.cleanup_at_exit._exitcode
            lda  #0
            rol  a
            sta  p8_sys_startup.cleanup_at_exit._exitcarry
            stx  p8_sys_startup.cleanup_at_exit._exitcodeX
            sty  p8_sys_startup.cleanup_at_exit._exitcodeY
            ldx  prog8_lib.orig_stackpointer
            txs
            jmp  p8_sys_startup.cleanup_at_exit
        }}
    }

    inline asmsub push_returnaddress(uword address @XY) {
        %asm {{
            ; push like JSR would:  address-1,  MSB first then LSB
            cpx  #0
            bne  +
            dey
+           dex
            tya
            pha
            txa
            pha
        }}
    }

    asmsub get_as_returnaddress(uword address @XY) -> uword @AX {
        %asm {{
            ; return the address like JSR would push onto the stack:  address-1,  MSB first then LSB
            cpx  #0
            bne  +
            dey
+           dex
            tya
            rts
        }}
    }

    sub cpu_is_65816() -> bool {
        ; Returns true when you have a 65816 cpu, false when it's a 6502.
        ; The SuperCPU expansion for the C64/C128 contains a 65816.
        %asm {{
			php
			clv
			.byte $e2, $ea  ; SEP #$ea, should be interpreted as 2 NOPs by 6502. 65c816 will set the Overflow flag.
			bvc +
			lda #1
			plp
			rts
+			lda #0
			plp
			rts
        }}
    }
}

cx16 {
; the sixteen virtual 16-bit registers in both normal unsigned mode and signed mode (s)
    &uword r0  = $0300
    &uword r1  = $0302
    &uword r2  = $0304
    &uword r3  = $0306
    &uword r4  = $0308
    &uword r5  = $030a
    &uword r6  = $030c
    &uword r7  = $030e
    &uword r8  = $0310
    &uword r9  = $0312
    &uword r10 = $0314
    &uword r11 = $0316
    &uword r12 = $0318
    &uword r13 = $031a
    &uword r14 = $031c
    &uword r15 = $031e

    ; signed word versions
    &word r0s  = $0300
    &word r1s  = $0302
    &word r2s  = $0304
    &word r3s  = $0306
    &word r4s  = $0308
    &word r5s  = $030a
    &word r6s  = $030c
    &word r7s  = $030e
    &word r8s  = $0310
    &word r9s  = $0312
    &word r10s = $0314
    &word r11s = $0316
    &word r12s = $0318
    &word r13s = $031a
    &word r14s = $031c
    &word r15s = $031e

    ; signed long versions
    &long r0r1sl = $0300
    &long r2r3sl = $0304
    &long r4r5sl = $0308
    &long r6r7sl = $030c
    &long r8r9sl = $0310
    &long r10r11sl = $0314
    &long r12r13sl = $0318
    &long r14r15sl = $031c

    ; ubyte versions (low and high bytes)
    &ubyte r0L  = $0300
    &ubyte r1L  = $0302
    &ubyte r2L  = $0304
    &ubyte r3L  = $0306
    &ubyte r4L  = $0308
    &ubyte r5L  = $030a
    &ubyte r6L  = $030c
    &ubyte r7L  = $030e
    &ubyte r8L  = $0310
    &ubyte r9L  = $0312
    &ubyte r10L = $0314
    &ubyte r11L = $0316
    &ubyte r12L = $0318
    &ubyte r13L = $031a
    &ubyte r14L = $031c
    &ubyte r15L = $031e

    &ubyte r0H  = $0301
    &ubyte r1H  = $0303
    &ubyte r2H  = $0305
    &ubyte r3H  = $0307
    &ubyte r4H  = $0309
    &ubyte r5H  = $030b
    &ubyte r6H  = $030d
    &ubyte r7H  = $030f
    &ubyte r8H  = $0311
    &ubyte r9H  = $0313
    &ubyte r10H = $0315
    &ubyte r11H = $0317
    &ubyte r12H = $0319
    &ubyte r13H = $031b
    &ubyte r14H = $031d
    &ubyte r15H = $031f

    ; signed byte versions (low and high bytes)
    &byte r0sL  = $0300
    &byte r1sL  = $0302
    &byte r2sL  = $0304
    &byte r3sL  = $0306
    &byte r4sL  = $0308
    &byte r5sL  = $030a
    &byte r6sL  = $030c
    &byte r7sL  = $030e
    &byte r8sL  = $0310
    &byte r9sL  = $0312
    &byte r10sL = $0314
    &byte r11sL = $0316
    &byte r12sL = $0318
    &byte r13sL = $031a
    &byte r14sL = $031c
    &byte r15sL = $031e

    &byte r0sH  = $0301
    &byte r1sH  = $0303
    &byte r2sH  = $0305
    &byte r3sH  = $0307
    &byte r4sH  = $0309
    &byte r5sH  = $030b
    &byte r6sH  = $030d
    &byte r7sH  = $030f
    &byte r8sH  = $0311
    &byte r9sH  = $0313
    &byte r10sH = $0315
    &byte r11sH = $0317
    &byte r12sH = $0319
    &byte r13sH = $031b
    &byte r14sH = $031d
    &byte r15sH = $031f

    ; boolean versions
    &bool r0bL  = $0300
    &bool r1bL  = $0302
    &bool r2bL  = $0304
    &bool r3bL  = $0306
    &bool r4bL  = $0308
    &bool r5bL  = $030a
    &bool r6bL  = $030c
    &bool r7bL  = $030e
    &bool r8bL  = $0310
    &bool r9bL  = $0312
    &bool r10bL = $0314
    &bool r11bL = $0316
    &bool r12bL = $0318
    &bool r13bL = $031a
    &bool r14bL = $031c
    &bool r15bL = $031e

    &bool r0bH  = $0301
    &bool r1bH  = $0303
    &bool r2bH  = $0305
    &bool r3bH  = $0307
    &bool r4bH  = $0309
    &bool r5bH  = $030b
    &bool r6bH  = $030d
    &bool r7bH  = $030f
    &bool r8bH  = $0311
    &bool r9bH  = $0313
    &bool r10bH = $0315
    &bool r11bH = $0317
    &bool r12bH = $0319
    &bool r13bH = $031b
    &bool r14bH = $031d
    &bool r15bH = $031f


    asmsub save_virtual_registers() clobbers(A,Y) {
        %asm {{
            ldy  #31
    -       lda  cx16.r0,y
            sta  _cx16_vreg_storage,y
            dey
            bpl  -
            rts

            .section BSS
    _cx16_vreg_storage
            .word ?,?,?,?,?,?,?,?
            .word ?,?,?,?,?,?,?,?
            .send BSS
            ; !notreached!
        }}
    }

    asmsub restore_virtual_registers() clobbers(A,Y) {
        %asm {{
            ldy  #31
    -       lda  save_virtual_registers._cx16_vreg_storage,y
            sta  cx16.r0,y
            dey
            bpl  -
            rts
        }}
    }
}

p8_sys_startup {
    ; program startup and shutdown machinery. Needs to reside in normal system ram.

    asmsub  init_system()  {
        ; Initializes the machine to a sane starting state.
        ; Called automatically by the loader program logic.
        %asm {{
            cld
            ; the virtual registers start as 0
            ldy  #31
            lda  #0
-           sta  cx16.r0,y
            dey
            bpl  -
            clc
            clv
            rts
        }}
    }

    asmsub  init_system_phase2()  {
        %asm {{
            rts     ; no phase 2 steps on the appleii
        }}
    }

    asmsub  cleanup_at_exit() {
        ; executed when the main subroutine does rts
        ; (the prodos target's program is a system program, which nothing called: it
        ;  ends with ProDOS's QUIT.  The target files have the assembler define p8_prodos.)
        %asm {{
            .if p8_prodos != 0
            jsr  $bf00
            .byte  $65
            .word  _quit
_quit       .byte  4, 0, 0, 0, 0, 0, 0
            .endif
            lda  _exitcarry
            lsr  a
            lda  _exitcode
            ldx  _exitcodeX
            ldy  _exitcodeY
            rts

            .section BSS
_exitcarry  .byte ?
_exitcode   .byte ?
_exitcodeX  .byte ?
_exitcodeY  .byte ?
            .send BSS

            ; !notreached!
        }}
    }

}
