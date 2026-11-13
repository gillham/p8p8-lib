; Prog8 definitions for the mecb68k M68k target

%option no_symbol_prefixing, ignore_unused
%import shared_m68k_memory_routines

mecb68k {
    %option force_output

    ; MECB 68008 addresses
    const long RAM_BASE         = $000000
    const long RAM_END          = $07ffff
    const long ROM_BASE         = $200000
    const long ROM_END          = $27ffff
    const long EX_ROM1_BASE     = $100000
    const long EX_ROM1_END      = $17ffff
    const long EX_ROM2_BASE     = $180000
    const long EX_ROM2_END      = $1fffff
    const long USERPROG_ORG     = $004000
    ; I/O ranges
    const long IO_BASE          = $300000       ; I/O base address
    const long IO1_BASE         = IO_BASE       ; First Motorola I/O card
    const long IO2_BASE         = IO_BASE+$20   ; Second Motorola I/O card

    ; First Motorola I/O card

    ; Motorola 6850 ACIA
    ;const long ACIA1            = IO1_BASE+$08  ; location of ACIA
    ;const long ACIA1_STATUS     = &ACIA1         ; status
    ;const long ACIA1_CONTROL    = &ACIA1         ; control
    ;const long ACIA1_DATA       = &ACIA1+1       ; data
    &ubyte ACIA1                = IO1_BASE+$08  ; location of ACIA
    &ubyte ACIA1_STATUS         = &ACIA1         ; status
    &ubyte ACIA1_CONTROL        = &ACIA1         ; control
    &ubyte ACIA1_DATA           = &ACIA1+1       ; data

    ; Motorola 6840 PTM (programmable timer module)
    const long PTM1             = IO1_BASE
    const long PTM1_CR13        = PTM1          ; W: timer control reg 1&3  R: nop
    const long PTM1_SR          = PTM1+1
    const long PTM1_CR2         = PTM1+1        ; W: control reg 2  R: status register (lsb selects tcr 1|3)
    ;
    const long PTM1_T1MSB       = PTM1+2        ; W: MSB buffer register R: timer 1 counter
    const long PTM1_T1LSB       = PTM1+3        ; W: timer 1 latches     R: LSB buffer register
    ;
    const long PTM1_T2MSB       = PTM1+4        ; W: MSB buffer register R: timer 2 counter
    const long PTM1_T2LSB       = PTM1+5        ; W: timer 2 latches     R: LSB buffer register
    ;
    const long PTM1_T3MSB       = PTM1+6        ; W: MSB buffer register R: timer 3 counter
    const long PTM1_T3LSB       = PTM1+7        ; W: timer 3 latches     R: LSB buffer register

    ; Motorola PIA
    const long PIA1BASE         = IO1_BASE+$10  ; PIA base address
    const long PIA1REGA         = PIA1BASE      ; data reg A
    const long PIA1DDRA         = PIA1BASE      ; data dir reg A
    const long PIA1CTLA         = PIA1BASE+1    ; control reg A
    const long PIA1REGB         = PIA1BASE+2    ; data reg B
    const long PIA1DDRB         = PIA1BASE+2    ; data dir reg B
    const long PIA1CTLB         = PIA1BASE+3    ; control reg B

    ; Second Motorola I/O card

    ; Motorola 6850 ACIA
    const long ACIA2            = IO2_BASE+$08  ; location of ACIA
    const long ACIA2_STATUS     = ACIA2         ; status
    const long ACIA2_CONTROL    = ACIA2         ; control
    const long ACIA2_DATA       = ACIA2+1       ; data

    ; Motorola 6840 PTM (programmable timer module)
    const long PTM2             = IO2_BASE
    const long PTM2_CR13        = PTM2          ; W: timer control reg 1&3  R: nop
    const long PTM2_SR          = PTM2+1
    const long PTM2_CR2         = PTM2+1        ; W: control reg 2  R: status register (lsb selects tcr 1|3)
    ;
    const long PTM2_T1MSB       = PTM2+2        ; W: MSB buffer register R: timer 1 counter
    const long PTM2_T1LSB       = PTM2+3        ; W: timer 1 latches     R: LSB buffer register
    ;
    const long PTM2_T2MSB       = PTM2+4        ; W: MSB buffer register R: timer 2 counter
    const long PTM2_T2LSB       = PTM2+5        ; W: timer 2 latches     R: LSB buffer register
    ;
    const long PTM2_T3MSB       = PTM2+6        ; W: MSB buffer register R: timer 3 counter
    const long PTM2_T3LSB       = PTM2+7        ; W: timer 3 latches     R: LSB buffer register

    ; Motorola PIA
    const long PIA2BASE         = IO2_BASE+$10  ; PIA base address
    const long PIA2REGA         = PIA2BASE      ; data reg A
    const long PIA2DDRA         = PIA2BASE      ; data dir reg A
    const long PIA2CTLA         = PIA2BASE+1    ; control reg A
    const long PIA2REGB         = PIA2BASE+2    ; data reg B
    const long PIA2DDRB         = PIA2BASE+2    ; data dir reg B
    const long PIA2CTLB         = PIA2BASE+3    ; control reg B

    ; I/O mapping for VDP
    const long VDP              = IO_BASE+$80   ; TMS9918A video display processor
    const long VDP_VRAM         = VDP+0         ; use for VRAM reads/writes
    const long VDP_REG          = VDP+1         ; control registers / address latch

    ; I/O mapping for OLED
    const long OLED             = IO_BASE+$88   ; OLED panel base address
    const long OLED_CMD         = OLED          ; OLED command address
    const long OLED_DTA         = OLED+1        ; OLED data address

    ; I/O mapping for I/O & RTC card
    const long RTC              = IO_BASE+$c0
    const long IO_PORT          = IO_BASE+$c1
    ;
    const long FN_CSR           = IO_BASE+$c2   ; Fujinet I/O port
    ;
    const long MECB_PPI         = IO_BASE+$20
    ;
    ; some characters for serial?
    ;
    ;const ubyte CR              = $0d           ; carriage return
    ;const ubyte LF              = $0a           ; linefeed
    ;const ubyte BELL            = $07           ; bell
    ;const ubyte EOT             = $00


    ; Send a character via ACIA
    sub chroutp(ubyte char) {
        while (mecb68k.ACIA1_STATUS & %00000001) == 0 {
        }
        mecb68k.ACIA1_DATA = char
    }

    ; Send a character via ACIA
    asmsub chroutx(ubyte char @D0) {
        %asm {{
1$:         btst.b  #1,mecb68k.ACIA1_STATUS     ; Read the ACIA TX status
            beq     1$                          ; Wait until ready
            move.b  d0,mecb68k.ACIA1_DATA       ; Send a character 
            rts
        }}
    }

    ; Read one character from TTY input (blocking)
    asmsub chrinx() -> ubyte @D0 {
        %asm {{
            suba.l  #4,sp
            movea.l  sp,a0       ; buffer = stack pointer (in A0 for input_data)
            moveq   #1,d1        ; maxlen = 1
            bsr     mecb68k.input_data
            move.b  (sp),d0
            adda.l  #4,sp
            rts
        }}
    }

    ;
    ; TODO: DEBUG: use TUTOR interfaces for some initial I/O
    ;

    ; Send a character via TUTOR firmware interface
    ; preserves a0/d1/d7 that TUTOR doesn't
    asmsub chrout(ubyte char @D0) {
        %asm {{
            move.l  d1, -(sp)   ; push d1
            move.l  d7, -(sp)   ; push d7
            move.l  a0, -(sp)   ; push a0 (*must* be preserved)
            move.b  #248, d7    ; load OUTCH function code
            trap    #14         ; call TUTOR firmware handler
            move.l  (sp)+, a0
            move.l  (sp)+, d7
            move.l  (sp)+, d1
            rts
        }}
    }

    ; Read one character from TUTOR input (blocking)
    asmsub chrin() -> ubyte @D0 {
        %asm {{
            move.b  #247, d7    ; load INCHE function code
            trap    #14         ; call TUTOR firmware handler
            rts
        }}
    }

    ; Check if at a character is available on ACIA1 input (non-zero means data available)
    asmsub keypressed() -> bool @Pz {
        %asm {{
            ; ACIA status register bit 0 ("Receive Data Register Full")
            ; is set when there is a byte to be read
            ; It is cleared after a read, a reset, or if DCD is high.
            btst.b  #0,mecb68k.ACIA1_STATUS     ; Read the ACIA RX status
            ; btst sets Z so we can just return
            rts
        }}
    }

    ; Read up to maxlen bytes from TTY input into buffer.
    ; Blocks until at least one byte is available. Does NOT add a trailing 0-byte.
    ; Returns the actual number of bytes read (may be less than maxlen).
    asmsub input_data(long buffer @A0, uword maxlen @D1) -> uword @D0 {
        %asm {{
            ; TODO check specific bit for available byte.
1$:         ;movea.w  #mecb68k.ACIA1_STATUS,a1
            move.l   (a1),d0
            tst.l    d0
            beq      1$                  ; wait for at least 1 byte
            ; d0 = available bytes, d1 = maxlen
            cmp.l    d1,d0               ; available - maxlen
            bls      2$                  ; if available <= maxlen, keep d0
            move.l   d1,d0               ; else cap at maxlen
2$:         ;movea.l  #mecb68k.TTY_DATA_PTR,a1
            move.l   a0,(a1)
            ;movea.l  #mecb68k.TTY_DATA_LEN,a1
            move.l   d0,(a1)
            ;movea.l  #mecb68k.TTY_CMD,a1
            ;move.l   #mecb68k.TTY_CMD_READ_BUFFER,(a1)
            rts
        }}
    }

    ; Print a null-terminated string to the TTY.
    ; Preserves all registers (no caller-saved registers clobbered).
    asmsub puts(str msg @A0) {
        %asm {{
            move.l  d0,-(sp)
            move.l  a0,-(sp)
.loop:
            move.b   (a0)+,d0
            beq      .done
            ;
            ; use TUTOR firmware for the moment.
            ;
            ;move.b   d0,mecb68k.ACIA1_DATA
            move.b  #248, d7    ; load OUTCH function code
            trap    #14         ; call TUTOR firmware handler
            bra.s    .loop
.done:
            move.l  (sp)+,a0
            move.l  (sp)+,d0
            rts
        }}
    }
}

sys {
    ; ------- lowlevel system routines --------

    const ubyte target = 68         ;  compilation target specifier.

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


    sub  reset_system()  {
        %asm {{
            ;movea.l  #mecb68k.CTRL_REG_CMD,a1
            ;move.l   #mecb68k.CTRL_CMD_RESET,(a1)
            stop #$2000
        }}
    }

    sub poweroff_system() {
        %asm {{
            ;movea.l  #mecb68k.CTRL_REG_CMD,a1
            ;move.l   #mecb68k.CTRL_CMD_HALT,(a1)
            stop #0
        }}
    }

    sub die(ubyte code, str message) {
        ; -- kill the program: print death message to goldfish TTY, then exit.
        str @shared warning = iso:"\n\nPROGRAM DIED: "
        %asm {{
            lea  sys.die.warning,a0
.loop1:
            move.b  (a0)+,d0
            beq  .done1
            move.b  d0,mecb68k.ACIA1_DATA
            bra.s .loop1
.done1:
            move.l  sys.die.message,a0
.loop2:
            move.b  (a0)+,d0
            beq  .done2
            move.b  d0,mecb68k.ACIA1_DATA
            bra.s  .loop2
.done2:
            moveq  #10,d0
            move.b  d0,mecb68k.ACIA1_DATA
        }}
        exit(code)
    }

    sub wait(uword jiffies) {
        ; --- wait approximately the given number of jiffies (1/60th seconds)
        ; TODO implement the wait
    }


    sub exit(ubyte returnvalue) {
        ; -- exit the program with a return code in D0. When invoked from Prog8 via sys.exit(), all active defers in the call chain are unwound program-wide (LIFO) before system cleanup. sys.reset_system()/poweroff_system() do not run defers.
        %asm {{
            moveq.l  #0,d0
            move.b   sys.exit.returnvalue,d0
        }}
        poweroff_system()
    }

    sub set_carry() {
        %asm {{
            ; set both C (comparison carry) and X (rotate carry) bits
            moveq  #$11,d0
            move.w  d0,ccr
        }}
    }

    sub clear_carry() {
        %asm {{
            moveq  #0,d0
            move.w  d0,ccr
        }}
    }

    asmsub exec_version() -> uword @D0 {
        %asm {{
            moveq  #36,d0
            rts
        }}
    }

    sub clear_irqd() {
        %asm {{
            andi.w  #$f8ff,sr       ; privileged !
        }}
    }

    sub set_irqd() {
        %asm {{
            ori.w  #$0700,sr        ; privileged !
        }}
    }

    asmsub memcopy(long source @A0, long tgt @A1, long count @D0) {
        ; Copy bytes from source to target. Allows long count.
        ; Bulk of the work uses long-aligned longword copies;
        ; pre-alignment and remainder bytes use individual byte copies.
        %asm {{
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
            rts

.bytes:
            subq.l   #1,d2
.loop_b:
            move.b   (a0)+,(a1)+
            subq.l   #1,d2
            bne      .loop_b
            rts
        }}
    }

    inline asmsub progstart() -> long @A0 {
        %asm {{
            lea  prog8_program_start,a0
        }}
    }

    inline asmsub progend() -> long @A0 {
        %asm {{
            lea  prog8_program_end,a0
        }}
    }
}
