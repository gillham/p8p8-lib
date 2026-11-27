; Small things of the GameTank SDK's gametank.h and wait.s, with the names of
; the C SDK.  (gametank.wait() is in gametank.p8.)

%import gametank

gametank {
%option merge

    ; do nothing for 5 instructions (22 cycles with the call, as in C)
    asmsub nop5() {
        %asm {{
            nop
            nop
            nop
            nop
            nop
            rts
        }}
    }

    ; do nothing for 10 instructions (32 cycles with the call, as in C)
    asmsub nop10() {
        %asm {{
            nop
            nop
            nop
            nop
            nop
            nop
            nop
            nop
            nop
            nop
            rts
        }}
    }

    ; stop the cpu, until a reset
    inline asmsub stop() {
        %asm {{
            stp
        }}
    }

    ; Mark the start and the end of a stretch of code for the profiler of the
    ; GameTank emulator: id is 0-63.
    inline asmsub PROFILER_START(ubyte id @A) clobbers(X) {
        %asm {{
            ldx  #$80
            stx  gametank.VIA1PB
            sta  gametank.VIA1PB
        }}
    }

    inline asmsub PROFILER_END(ubyte id @A) clobbers(A,X) {
        %asm {{
            ldx  #$80
            stx  gametank.VIA1PB
            ora  #$40
            sta  gametank.VIA1PB
        }}
    }
}
