; Prog8 definitions for the Atari800XL
; Including memory registers, I/O registers, Basic and Kernal subroutines.

%option no_symbol_prefixing, ignore_unused

cbm {
    ; The names the Commodores have for these, for programs and modules shared with them.

    &ubyte  TIME_HI         = $12       ; the OS's clock, counted up 60 times a second (50 on a PAL machine)
    &ubyte  TIME_MID        = $13
    &ubyte  TIME_LO         = $14

    asmsub CHROUT(ubyte character @ A) {
        ; ---- print the ATASCII character where the cursor is, through the screen editor's
        ;      own entry (the E: handler's table in the ROM, the same in every OS).
        ;      A, X and Y are kept.
        %asm {{
            sta  _char
            txa
            pha
            tya
            pha
            jsr  _put
            pla
            tay
            pla
            tax
            lda  _char
            rts
_put        lda  atari.EDITRV+7
            pha
            lda  atari.EDITRV+6
            pha
            lda  _char
            rts

            .section BSS
_char       .byte ?
            .send BSS
            ; !notreached!
        }}
    }

    asmsub CHRIN() -> ubyte @A {
        ; ---- the next character of a line typed at the keyboard, as on the Commodores:
        ;      the first call reads a whole line with the screen editor, and this and the
        ;      next calls give its characters, a RETURN (13) last.  X and Y are kept.
        %asm {{
            stx  _savex
            sty  _savey
            lda  _reading
            bne  _next
            ; a record from IOCB 0, which is the editor
            ldx  #0
            lda  #5                 ; GET RECORD
            sta  atari.ICCOM
            lda  #<_line
            sta  atari.ICBAL
            lda  #>_line
            sta  atari.ICBAH
            lda  #size(_line)
            sta  atari.ICBLL
            stx  atari.ICBLH
            jsr  atari.CIOV
            lda  #0
            sta  _index
            inc  _reading
_next       ldx  _index
            inc  _index
            lda  _line,x
            cmp  #$9b
            beq  _last
            cpx  #size(_line)-1
            bcc  _done
_last       lda  #0
            sta  _reading
            lda  #13
_done       ldx  _savex
            ldy  _savey
            rts

            .section BSS
_reading    .byte ?
_index      .byte ?
_savex      .byte ?
_savey      .byte ?
_line       .fill 121
            .send BSS
            ; !notreached!
        }}
    }

    asmsub GETIN() -> bool @Pc, ubyte @A {
        ; ---- the key that is pressed (ATASCII), or 0 when there is none, without waiting.
        ;      X and Y are kept.
        %asm {{
            lda  atari.CH
            cmp  #$ff
            bne  +
            lda  #0
            clc
            rts
+           jsr  atari.waitkey
            clc
            rts
        }}
    }

    inline asmsub GETIN2() -> ubyte @A {
        ; -- just like GETIN, but omits the carry flag result value.
        %asm {{
            jsr  cbm.GETIN
        }}
    }

    asmsub STOP() -> bool @Pz, ubyte @A {
        ; ---- has the BREAK key been pressed since the last call?
        %asm {{
            lda  atari.BRKKEY
            bne  +
            lda  #$80
            sta  atari.BRKKEY
            lda  #0
+           rts
        }}
    }

    inline asmsub STOP2() -> bool @Pz {
        ; -- just like STOP, but omits the value in A
        %asm {{
            jsr  cbm.STOP
        }}
    }

    asmsub RDTIM() -> ubyte @ A, ubyte @ X, ubyte @ Y {
        ; ---- read the clock (A=lo,X=mid,Y=high), all three from the same moment
        %asm {{
-           lda  TIME_LO
            ldx  TIME_MID
            ldy  TIME_HI
            cmp  TIME_LO
            bne  -
            rts
        }}
    }

    asmsub RDTIM16() clobbers(X) -> uword @AY {
        ; --  like RDTIM() but only returning the lower 16 bits in AY for convenience
        %asm {{
            jsr  cbm.RDTIM
            pha
            txa
            tay
            pla
            rts
        }}
    }

    asmsub SETTIM(ubyte low @ A, ubyte middle @ X, ubyte high @ Y) {
        ; ---- set the clock
        %asm {{
            php
            sei
            sta  TIME_LO
            stx  TIME_MID
            sty  TIME_HI
            plp
            rts
        }}
    }
}

atari {

        &uword  NMI_VEC         = $FFFA     ; 6502 nmi vector
        &uword  RESET_VEC       = $FFFC     ; 6502 reset vector
        &uword  IRQ_VEC         = $FFFE     ; 6502 interrupt vector

        ; the OS's variables
        &uword  DOSVEC          = $0a       ; where a program goes to leave for DOS
        &ubyte  BRKKEY          = $11       ; 0 when BREAK has been pressed
        &ubyte  RTCLOK          = $12       ; three bytes, the last ($14) counted up every frame
        &ubyte  ATRACT          = $4d       ; write 0: the screen saver's colors do not start
        &ubyte  LMARGN          = $52       ; the text's left margin (the OS starts with 2; a program here with 0)
        &ubyte  RMARGN          = $53       ; and right margin (39)
        &ubyte  ROWCRS          = $54       ; the cursor's row
        &uword  COLCRS          = $55       ; and column
        &uword  SAVMSC          = $58       ; the address of the screen's memory
        &ubyte  SDMCTL          = $022f     ; 0: the screen off (and the CPU faster), 34: on
        &ubyte  COLOR0          = $02c4     ; the colors (hue * 16 + brightness), written to
        &ubyte  COLOR1          = $02c5     ;   the hardware every frame.  In the text mode:
        &ubyte  COLOR2          = $02c6     ;   COLOR1 the text's brightness, COLOR2 the
        &ubyte  COLOR3          = $02c7     ;   background, COLOR4 the border
        &ubyte  COLOR4          = $02c8
        &uword  RUNAD           = $02e0     ; where DOS starts a program it has loaded
        &ubyte  CRSINH          = $02f0     ; not 0: no cursor is shown
        &ubyte  CHBAS           = $02f4     ; the character set's page ($e0: the ROM's)
        &ubyte  CH              = $02fc     ; the key that is waiting (a key code), 255: none
        ; IOCB 0 (the others are 16 bytes further each)
        &ubyte  ICCOM           = $0342
        &ubyte  ICSTA           = $0343
        &ubyte  ICBAL           = $0344
        &ubyte  ICBAH           = $0345
        &ubyte  ICBLL           = $0348
        &ubyte  ICBLH           = $0349
        &ubyte  ICAX1           = $034a
        &ubyte  ICAX2           = $034b

        ; the hardware
        &ubyte  CONSOL          = $d01f     ; the START (bit 0), SELECT and OPTION keys, 0 when pressed
        &ubyte  RANDOM          = $d20a     ; a random byte
        &ubyte  WSYNC           = $d40a     ; write: wait for the end of the scan line
        &ubyte  VCOUNT          = $d40b     ; the scan line / 2

        ; the ROM's tables of its devices' routines (address - 1 of: open, close, get, put, status, special)
        const uword EDITRV      = $e400     ; E: the screen editor
        const uword SCRENV      = $e410     ; S: the screen
        const uword KEYBDV      = $e420     ; K: the keyboard

    extsub $e456 = CIOV(ubyte iocb @X) -> ubyte @Y      ; the OS's I/O call; X = IOCB number * 16, Y = the status
    extsub $e45c = SETVBV(ubyte what @A, uword address @XY)
    extsub $e474 = WARMSV()
    extsub $e477 = COLDSV()

    asmsub outchar(ubyte character @ A) {
        ; ---- print the ATASCII character (X and Y kept): cbm.CHROUT
        %asm {{
            jmp  cbm.CHROUT
        }}
    }

    asmsub waitkey() -> ubyte @A {
        ; ---- wait for a key and return it (ATASCII), without printing it: the K: handler's
        ;      get.  X and Y are kept.
        %asm {{
            txa
            pha
            tya
            pha
            jsr  _get
            sta  P8ZP_SCRATCH_REG
            pla
            tay
            pla
            tax
            lda  P8ZP_SCRATCH_REG
            rts
_get        lda  KEYBDV+5
            pha
            lda  KEYBDV+4
            pha
            rts
        }}
    }

    asmsub getkey() -> ubyte @A {
        ; ---- as waitkey()
        %asm {{
            jmp  waitkey
        }}
    }

    asmsub getchar() -> ubyte @A {
        ; ---- the next character of a typed line: cbm.CHRIN, with $9b for its end
        %asm {{
            jsr  cbm.CHRIN
            cmp  #13
            bne  +
            lda  #$9b
+           rts
        }}
    }
}

%import shared_sys_functions

sys {
    ; ------- lowlevel system routines --------

    const ubyte target = 8         ;  compilation target specifier.  255=virtual, 128=C128, 64=C64, 32=PET, 16=CommanderX16, 8=atari800XL, 7=Neo6502

    const ubyte SIZEOF_BOOL  = sizeof(bool)
    const ubyte SIZEOF_BYTE  = sizeof(byte)
    const ubyte SIZEOF_UBYTE = sizeof(ubyte)
    const ubyte SIZEOF_WORD  = sizeof(word)
    const ubyte SIZEOF_UWORD = sizeof(uword)
    const ubyte SIZEOF_LONG  = sizeof(long)
    const ubyte SIZEOF_POINTER = sizeof(&sys.wait)
    const ubyte SIZEOF_FLOAT = 0    ; undefined, no floats supported
    const byte  MIN_BYTE     = -128
    const byte  MAX_BYTE     = 127
    const ubyte MIN_UBYTE    = 0
    const ubyte MAX_UBYTE    = 255
    const word  MIN_WORD     = -32768
    const word  MAX_WORD     = 32767
    const uword MIN_UWORD    = 0
    const uword MAX_UWORD    = 65535
    ; MIN_FLOAT and MAX_FLOAT are defined in the floats module if imported


    asmsub  reset_system()  {
        ; Reset the system as when it is switched on.
        %asm {{
            jmp  atari.COLDSV
        }}
    }

    uword entropy_state

    sub entropy() -> uword {
        ; -- 16 bits to seed a random generator with (math.rndseed).  Every call gives
        ;    another number.  From: POKEY's random number register and the clock.
        ;    (Not in upstream's library: p8p8's own.)
        entropy_state ^= mkword(@($d20a), @($14))
        entropy_state ^= @($d20a)
        entropy_state += $9e37
        entropy_state ^= entropy_state << 7
        entropy_state ^= entropy_state >> 9
        entropy_state ^= entropy_state << 8
        return entropy_state
    }

    asmsub wait(uword jiffies @AY) {
        ; --- wait approximately the given number of jiffies (1/60th seconds; 1/50th on a PAL machine) (N or N+1)
        ;     note: the OS's vertical blank interrupt has to be active, as it counts the clock
        %asm {{
            stx  P8ZP_SCRATCH_B1
            sta  P8ZP_SCRATCH_W1
            sty  P8ZP_SCRATCH_W1+1

_loop       lda  P8ZP_SCRATCH_W1
            ora  P8ZP_SCRATCH_W1+1
            bne  +
            ldx  P8ZP_SCRATCH_B1
            rts

+           lda  cbm.TIME_LO
            sta  P8ZP_SCRATCH_B1
-           lda  cbm.TIME_LO
            cmp  P8ZP_SCRATCH_B1
            beq  -

            lda  P8ZP_SCRATCH_W1
            bne  +
            dec  P8ZP_SCRATCH_W1+1
+           dec  P8ZP_SCRATCH_W1
            jmp  _loop
        }}
    }

    asmsub waitvsync() clobbers(A) {
        ; --- wait till the next vertical blank: the OS's clock is counted up in it
        %asm {{
            lda  cbm.TIME_LO
-           cmp  cbm.TIME_LO
            beq  -
            rts
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
        return false
    }

}

cx16 {
    ; the sixteen virtual 16-bit registers that the CX16 has defined in the zeropage
    ; they are simulated on the Atari as well but their location in memory is different
    &uword r0  = $0600
    &uword r1  = $0602
    &uword r2  = $0604
    &uword r3  = $0606
    &uword r4  = $0608
    &uword r5  = $060a
    &uword r6  = $060c
    &uword r7  = $060e
    &uword r8  = $0610
    &uword r9  = $0612
    &uword r10 = $0614
    &uword r11 = $0616
    &uword r12 = $0618
    &uword r13 = $061a
    &uword r14 = $061c
    &uword r15 = $061e

    ; signed word versions
    &word r0s  = $0600
    &word r1s  = $0602
    &word r2s  = $0604
    &word r3s  = $0606
    &word r4s  = $0608
    &word r5s  = $060a
    &word r6s  = $060c
    &word r7s  = $060e
    &word r8s  = $0610
    &word r9s  = $0612
    &word r10s = $0614
    &word r11s = $0616
    &word r12s = $0618
    &word r13s = $061a
    &word r14s = $061c
    &word r15s = $061e

    ; signed long versions
    &long r0r1sl  = $0600
    &long r2r3sl  = $0604
    &long r4r5sl  = $0608
    &long r6r7sl  = $060c
    &long r8r9sl  = $0600
    &long r10r11sl = $0604
    &long r12r13sl = $0608
    &long r14r15sl = $060c

    ; ubyte versions (low and high bytes)
    &ubyte r0L  = $0600
    &ubyte r1L  = $0602
    &ubyte r2L  = $0604
    &ubyte r3L  = $0606
    &ubyte r4L  = $0608
    &ubyte r5L  = $060a
    &ubyte r6L  = $060c
    &ubyte r7L  = $060e
    &ubyte r8L  = $0610
    &ubyte r9L  = $0612
    &ubyte r10L = $0614
    &ubyte r11L = $0616
    &ubyte r12L = $0618
    &ubyte r13L = $061a
    &ubyte r14L = $061c
    &ubyte r15L = $061e

    &ubyte r0H  = $0601
    &ubyte r1H  = $0603
    &ubyte r2H  = $0605
    &ubyte r3H  = $0607
    &ubyte r4H  = $0609
    &ubyte r5H  = $060b
    &ubyte r6H  = $060d
    &ubyte r7H  = $060f
    &ubyte r8H  = $0611
    &ubyte r9H  = $0613
    &ubyte r10H = $0615
    &ubyte r11H = $0617
    &ubyte r12H = $0619
    &ubyte r13H = $061b
    &ubyte r14H = $061d
    &ubyte r15H = $061f

    ; signed byte versions (low and high bytes)
    &byte r0sL  = $0600
    &byte r1sL  = $0602
    &byte r2sL  = $0604
    &byte r3sL  = $0606
    &byte r4sL  = $0608
    &byte r5sL  = $060a
    &byte r6sL  = $060c
    &byte r7sL  = $060e
    &byte r8sL  = $0610
    &byte r9sL  = $0612
    &byte r10sL = $0614
    &byte r11sL = $0616
    &byte r12sL = $0618
    &byte r13sL = $061a
    &byte r14sL = $061c
    &byte r15sL = $061e

    &byte r0sH  = $0601
    &byte r1sH  = $0603
    &byte r2sH  = $0605
    &byte r3sH  = $0607
    &byte r4sH  = $0609
    &byte r5sH  = $060b
    &byte r6sH  = $060d
    &byte r7sH  = $060f
    &byte r8sH  = $0611
    &byte r9sH  = $0613
    &byte r10sH = $0615
    &byte r11sH = $0617
    &byte r12sH = $0619
    &byte r13sH = $061b
    &byte r14sH = $061d
    &byte r15sH = $061f

    ; boolean versions
    &bool r0bL  = $0600
    &bool r1bL  = $0602
    &bool r2bL  = $0604
    &bool r3bL  = $0606
    &bool r4bL  = $0608
    &bool r5bL  = $060a
    &bool r6bL  = $060c
    &bool r7bL  = $060e
    &bool r8bL  = $0610
    &bool r9bL  = $0612
    &bool r10bL = $0614
    &bool r11bL = $0616
    &bool r12bL = $0618
    &bool r13bL = $061a
    &bool r14bL = $061c
    &bool r15bL = $061e

    &bool r0bH  = $0601
    &bool r1bH  = $0603
    &bool r2bH  = $0605
    &bool r3bH  = $0607
    &bool r4bH  = $0609
    &bool r5bH  = $060b
    &bool r6bH  = $060d
    &bool r7bH  = $060f
    &bool r8bH  = $0611
    &bool r9bH  = $0613
    &bool r10bH = $0615
    &bool r11bH = $0617
    &bool r12bH = $0619
    &bool r13bH = $061b
    &bool r14bH = $061d
    &bool r15bH = $061f

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
        ; The text's left margin, which the OS starts with at 2, is 0 while the program
        ; runs, so that the screen is 40 columns for print() as it is for plot().
        ; The virtual registers start as 0.
        %asm {{
            cld
            lda  atari.LMARGN
            sta  cleanup_at_exit._margin
            cmp  atari.COLCRS
            bne  +
            lda  #0
            sta  atari.COLCRS       ; (the cursor was at the margin: the first line starts at the left too)
+           lda  #0
            sta  atari.LMARGN
            ldy  #31
-           sta  cx16.r0,y
            dey
            bpl  -
            rts
        }}
    }

    asmsub  init_system_phase2()  {
        %asm {{
            cld
            clc
            clv
            rts
        }}
    }

    asmsub  cleanup_at_exit() {
        ; executed when the main subroutine does rts
        %asm {{
            lda  _margin
            sta  atari.LMARGN
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
            .section BSS_NOCLEAR
_margin     .byte ?         ; (kept from before the variables are cleared)
            .send BSS_NOCLEAR

            ; !notreached!
        }}
    }
}
