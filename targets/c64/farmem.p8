; Copying and filling memory anywhere in the 24 bits of address of a C64 with a SuperCPU,
; with the 65816's block moves.  For programs compiled with -cpu 65816: an address is a
; long there (p8p8's far memory, see the compiler's docs/DIFFERENCES.md).  A block stays
; inside one 64 KB bank: the CPU counts in 16 bits.

farmem {
    %option ignore_unused

    ubyte[4] mover          ; (a block move has its two banks in the instruction)
    uword from
    uword dest
    uword amount

    ; Copy count bytes.  The two blocks may overlap.
    sub copy(long source, long target, uword count) {
        if count == 0
            return
        if target > source and target - source < count
            move(source, target, count, true)
        else
            move(source, target, count, false)
    }

    ; Set count bytes to the value.
    sub fill(long target, uword count, ubyte value) {
        if count == 0
            return
        @(target) = value
        if count > 1
            move(target, target + 1, count - 1, false)      ; (each byte from the one before it)
    }

    sub move(long source, long target, uword count, bool backward) {
        from = lsw(source)
        dest = lsw(target)
        amount = count - 1
        mover[0] = $54              ; mvn
        if backward {
            mover[0] = $44          ; mvp: from the ends
            from += amount
            dest += amount
        }
        mover[1] = lsb(msw(target))
        mover[2] = lsb(msw(source))
        mover[3] = $60              ; rts
        %asm {{
            .cpu "65816"
            php
            sei
            clc
            xce                     ; native mode, whatever it was
            php
            phb                     ; (a block move leaves the data bank at the target's)
            rep  #$30
            lda  p8b_farmem.p8v_amount
            ldx  p8b_farmem.p8v_from
            ldy  p8b_farmem.p8v_dest
            jsr  p8b_farmem.p8v_mover
            sep  #$30
            plb
            plp
            xce                     ; the mode the program was in
            plp
            .cpu "default"
        }}
    }
}
