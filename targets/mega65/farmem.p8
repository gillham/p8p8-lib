; Copying and filling memory anywhere in the MEGA65's 28 bits of address, with its DMA
; controller.  An address is a long (p8p8's far memory, see the compiler's
; docs/DIFFERENCES.md).  A block stays inside one 64 KB bank: the controller counts in
; 16 bits.

farmem {
    %option ignore_unused

    ubyte[18] job           ; (the controller reads its orders from memory)

    ; Copy count bytes.  The two blocks may overlap.
    sub copy(long source, long target, uword count) {
        if count == 0
            return
        if target > source and target - source < count {
            ; (the end first, or the block would run over what is still to be copied)
            source += count - 1
            target += count - 1
            run($30, source, target, count)
        }
        else
            run($00, source, target, count)
    }

    ; Set count bytes to the value.
    sub fill(long target, uword count, ubyte value) {
        if count != 0
            run($03, value, target, count)
    }

    ; one order in the F018B form, with the megabytes of both ends given
    sub run(ubyte command, long source, long target, uword count) {
        job[0] = $0b
        job[1] = $80
        job[2] = (msw(source) >> 4) as ubyte
        job[3] = $81
        job[4] = (msw(target) >> 4) as ubyte
        job[5] = $00
        job[6] = command
        job[7] = lsb(count)
        job[8] = msb(count)
        job[9] = lsb(lsw(source))
        job[10] = msb(lsw(source))
        job[11] = lsb(msw(source)) & 15
        job[12] = lsb(lsw(target))
        job[13] = msb(lsw(target))
        job[14] = lsb(msw(target)) & 15
        job[15] = 0
        job[16] = 0
        job[17] = 0
        uword where = &job
        @($d702) = 0
        @($d704) = 0
        @($d701) = msb(where)
        @($d705) = lsb(where)       ; (this one starts it; the CPU waits until it is done)
    }
}
