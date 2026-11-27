; Prog8 definitions for the Atari ST (the atarist target of p8p8): a GEMDOS program
; (.TOS) for a 68000 and TOS 1.04 or later, text through the VT-52 console.

%option no_symbol_prefixing, ignore_unused
%import shared_m68k_memory_routines

tos {
    %option force_output

    ; how much stack the program keeps (see p8_sys_startup.init_system)
    const long STACK_SIZE = 16384

    long basepage                   ; the program's base page (the command line is at $80 of it)
    long stack_low                  ; where the stack must not get to
    ubyte rez                       ; the screen's mode at the start: 0 low (40 columns, 16 colours),
                                    ; 1 medium (80 columns, 4 colours), 2 high (80 columns, black and white)

    ; the operating system's calls are traps with their arguments on the stack, the
    ; function's number last: GEMDOS is trap #1, the BIOS #13, the XBIOS #14.  They keep
    ; d3-d7 and a3-a7; Prog8's code wants d2 and a2 kept too.

    asmsub chrout(ubyte char @D0) {
        ; -- a character to the console (GEMDOS's Cconout, so that it goes where the
        ;    program's output was sent); the VT-52 codes do what they do
        %asm {{
            movem.l d1-d2/a0-a2,-(sp)
            and.w   #$ff,d0
            move.w  d0,-(sp)
            move.w  #2,-(sp)
            trap    #1
            addq.l  #4,sp
            movem.l (sp)+,d1-d2/a0-a2
            rts
        }}
    }

    asmsub textout(ubyte char @D0) {
        ; -- a character of text to the console: '\n' starts a new line
        %asm {{
            cmp.b   #10,d0
            bne     tos.chrout
            moveq   #13,d0
            bsr     tos.chrout
            moveq   #10,d0
            bra     tos.chrout
        }}
    }

    asmsub rawout(ubyte char @D0) {
        ; -- a character to the screen as the picture that it has in the font, the codes
        ;    below 32 too (the BIOS's Bconout to device 5)
        %asm {{
            movem.l d1-d2/a0-a2,-(sp)
            and.w   #$ff,d0
            move.w  d0,-(sp)
            move.w  #5,-(sp)
            move.w  #3,-(sp)
            trap    #13
            addq.l  #6,sp
            movem.l (sp)+,d1-d2/a0-a2
            rts
        }}
    }

    asmsub chrin() -> ubyte @D0 {
        ; -- wait for a key and return its character, without showing it (Cnecin).
        ;    The return key is '\n'.  A key without a character (the arrows, the
        ;    function keys) is 128 plus its scan code.
        %asm {{
            movem.l d1-d2/a0-a2,-(sp)
            move.w  #8,-(sp)
            trap    #1
            addq.l  #2,sp
            movem.l (sp)+,d1-d2/a0-a2
            tst.b   d0
            bne.s   .char
            swap    d0
            or.b    #$80,d0
            rts
.char:
            cmp.b   #13,d0
            bne.s   .done
            moveq   #10,d0
.done:
            and.l   #$ff,d0
            rts
        }}
    }

    asmsub keypressed() -> bool @D0 {
        ; -- is there a key waiting? (Cconis)
        %asm {{
            movem.l d1-d2/a0-a2,-(sp)
            move.w  #$0b,-(sp)
            trap    #1
            addq.l  #2,sp
            movem.l (sp)+,d1-d2/a0-a2
            and.l   #1,d0
            rts
        }}
    }

    asmsub hz200() -> long @D0 {
        ; -- the system's clock, which counts 200 times a second (it is read in
        ;    supervisor mode: the XBIOS's Supexec)
        %asm {{
            movem.l d1-d2/a0-a2,-(sp)
            pea     .read(pc)
            move.w  #38,-(sp)
            trap    #14
            addq.l  #6,sp
            move.l  .value(pc),d0
            movem.l (sp)+,d1-d2/a0-a2
            rts
.read:
            lea     .value(pc),a0
            move.l  $4ba.w,(a0)
            rts
.value:     dc.l    0
            ; !notreached!
        }}
    }

    asmsub vsync() {
        ; -- wait for the screen's next frame (the XBIOS's Vsync)
        %asm {{
            movem.l d0-d2/a0-a2,-(sp)
            move.w  #37,-(sp)
            trap    #14
            addq.l  #2,sp
            movem.l (sp)+,d0-d2/a0-a2
            rts
        }}
    }
}

sys {
    ; ------- lowlevel system routines --------

    const ubyte target = 52         ;  compilation target specifier.

    const ubyte SIZEOF_BOOL  = sizeof(bool)
    const ubyte SIZEOF_BYTE  = sizeof(byte)
    const ubyte SIZEOF_UBYTE = sizeof(ubyte)
    const ubyte SIZEOF_WORD  = sizeof(word)
    const ubyte SIZEOF_UWORD = sizeof(uword)
    const ubyte SIZEOF_LONG  = sizeof(long)
    const ubyte SIZEOF_POINTER = sizeof(&sys.wait)
    const ubyte SIZEOF_FLOAT = sizeof(float)
    const byte  MIN_BYTE     = -128
    const byte  MAX_BYTE     = 127
    const ubyte MIN_UBYTE    = 0
    const ubyte MAX_UBYTE    = 255
    const word  MIN_WORD     = -32768
    const word  MAX_WORD     = 32767
    const uword MIN_UWORD    = 0
    const uword MAX_UWORD    = 65535
    const long  MIN_LONG     = -2147483648
    const long  MAX_LONG     = 2147483647
    ; MIN_FLOAT and MAX_FLOAT are defined in the floats module if imported



    ; ----- the command line -----
    ; GEMDOS leaves what was typed after the program's name in the base page: its length
    ; at $80 and the text from $81, at most 125 characters.  The blanks become zeros
    ; once, and an argument is where it stands there.  The program's own name is not
    ; known to it: argument 0 is an empty string.

    bool args_split = false
    ubyte args_count = 0
    ubyte args_length = 0
    str args_none = ""

    sub split_arguments() {
        if args_split
            return
        args_split = true
        pointer text = tos.basepage + $81
        args_length = @(tos.basepage + $80)
        if args_length > 125
            args_length = 125
        @(text + args_length) = 0
        bool inside = false
        ubyte k
        for k in 0 to args_length {
            if @(text + k) <= 32 {
                @(text + k) = 0
                inside = false
            }
            else if not inside {
                inside = true
                args_count++
            }
        }
    }

    sub argc() -> uword {
        ; -- returns the number of command line arguments, including the program name (so normally at least 1)
        split_arguments()
        return args_count + 1
    }

    sub argv(uword index) -> str {
        ; -- returns the command line argument at the 0-based index (0 is the program name, which is empty
        ;    here), or an empty string when there is none
        split_arguments()
        if index == 0 or index > args_count
            return args_none
        pointer text = tos.basepage + $81
        ubyte number = 0
        bool inside = false
        ubyte k
        for k in 0 to args_length {
            if @(text + k) == 0
                inside = false
            else if not inside {
                inside = true
                number++
                if number == index
                    return text + k
            }
        }
        return args_none
    }

    sub reset_system() {
        ; -- end the program (a program of GEMDOS does not restart the machine)
        exit(0)
    }

    sub poweroff_system() {
        exit(0)
    }

    sub die(uword code, str message) {
        ; -- kill the program: print the message, then exit.
        str @shared warning = iso:"\r\n\r\nPROGRAM DIED: "
        ubyte k = 0
        while warning[k] != 0 {
            tos.chrout(warning[k])
            k++
        }
        k = 0
        while message[k] != 0 {
            tos.chrout(message[k])
            k++
        }
        tos.chrout(13)
        tos.chrout(10)
        exit(code as word)
    }

    uword entropy_state

    sub entropy() -> uword {
        ; -- 16 bits to seed a random generator with (math.rndseed).  Every call gives
        ;    another number.  From: the 200 Hz clock.
        ;    (Not in upstream's library: p8p8's own.)
        entropy_state ^= lsw(tos.hz200())
        entropy_state += $9e37
        entropy_state ^= entropy_state << 7
        entropy_state ^= entropy_state >> 9
        entropy_state ^= entropy_state << 8
        return entropy_state
    }

    sub wait(uword jiffies) {
        ; --- wait approximately the given number of jiffies (1/60th seconds)
        long end = tos.hz200() + (jiffies as long) * 10 / 3
        while tos.hz200() - end < 0 {
        }
    }

    sub waitvsync() {
        tos.vsync()
    }

    asmsub exit(word returnvalue @D0) {
        ; -- exit the program with a return code in D0 (GEMDOS's Pterm). When invoked from Prog8 via sys.exit(), all active defers in the call chain are unwound program-wide (LIFO) before system cleanup.
        %asm {{
            move.w  d0,-(sp)
            move.w  #$4c,-(sp)
            trap    #1
            ; !notreached!
        }}
    }

    sub set_carry() {
        %option noframe
        %asm {{
            ; set both C (comparison carry) and X (rotate carry) bits
            moveq  #$11,d0
            move.w  d0,ccr
        }}
    }

    sub clear_carry() {
        %option noframe
        %asm {{
            moveq  #0,d0
            move.w  d0,ccr
        }}
    }

    sub clear_irqd() {
        ; (a program runs in user mode: the interrupts are the system's)
    }

    sub set_irqd() {
    }

    asmsub memcopy(long source @A0, long tgt @A1, long count @D0) {
        ; Copy bytes from source to target. Allows long count.
        ; Bulk of the work uses long-aligned longword copies;
        ; pre-alignment and remainder bytes use individual byte copies.
        %asm {{
            movem.l  d2-d3,-(sp)
            move.l   d0,d2
            beq      .done

            ; check if both addresses share the same alignment offset
            move.l   a0,d0
            move.l   a1,d3
            eor.l    d3,d0
            andi.l   #3,d0
            bne      .bytes

            ; same alignment: pre-align both to a long boundary
            move.l   a0,d3
            and.w    #3,d3             ; d3 = offset (0-3)
            beq      .bulk
.loop_pre:
            move.b   (a0)+,(a1)+
            subq.l   #1,d2             ; track remaining count
            beq      .done
            move.l   a0,d3
            andi.l   #3,d3
            bne      .loop_pre

.bulk:
            move.l   d2,d3
            lsr.l    #2,d3             ; d3 = longword count
            beq      .rem
.loop_l:
            move.l   (a0)+,(a1)+
            subq.l   #1,d3
            bne      .loop_l

.rem:
            andi.l   #3,d2
            beq      .done
.loop_rem:
            move.b   (a0)+,(a1)+
            subq.l   #1,d2
            bne      .loop_rem
.done:
            movem.l  (sp)+,d2-d3
            rts

.bytes:
.loop_b:
            move.b   (a0)+,(a1)+
            subq.l   #1,d2
            bne      .loop_b
            movem.l  (sp)+,d2-d3
            rts
        }}
    }

    inline asmsub progstart() -> long @A0 {
        %asm {{
            lea  prog8_program_start,a0
        }}
    }

    inline asmsub progend() -> long @A0 {
        ; (the end of the program's variables: the stack is after it)
        %asm {{
            move.l  tos.stack_low,a0
        }}
    }

    asmsub stack_size() -> long @D0 {
        ; -- Return the amount of stack space still available, in bytes.
        %asm {{
            move.l  sp,d0
            sub.l   tos.stack_low,d0
            rts
        }}
    }

    asmsub cpuAtLeast68020() -> bool @D0 {
        %asm {{
            moveq   #0,d0       ; an ST has a 68000
            rts
        }}
    }
}
