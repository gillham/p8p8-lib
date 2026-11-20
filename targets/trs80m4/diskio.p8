; File I/O routines for the TRS-80 Model 4 (the trs80m4 target of p8p8): the supervisor
; calls of TRSDOS 6 and LS-DOS 6 (rst $28 with the number in A).  The routines that
; programs use are in shared_trsdos_diskio.

%import shared_trsdos_diskio

diskio {
    %option no_symbol_prefixing, ignore_unused

    const ubyte SVC_GET = 3             ; a byte from a file
    const ubyte SVC_PUT = 4             ; a byte to a file
    const ubyte SVC_CMNDR = 25          ; do a command of the DOS and come back
    const ubyte SVC_INIT = 58           ; open a file, new or not
    const ubyte SVC_OPEN = 59           ; open a file that is there
    const ubyte SVC_CLOSE = 60
    const ubyte SVC_REMOV = 57          ; remove the file that is open
    const ubyte SVC_FSPEC = 78          ; a name into a file control block

    ; (drive 0 by name: without it the DOS goes through every drive, and waits long for each that is empty)
    str directory_command = "DIR :0\r"

    sub svc(ubyte number, uword hl_value, uword de_value) -> ubyte {
        ; -- a supervisor call with HL and DE (and B 0: records of 256 bytes).
        ;    0 when it went well (the DOS says so with the zero flag), else its error code, or 255.
        ubyte @shared answer
        %asm {{
            ld  hl,(_diskio__svc__hl_value)
            ld  de,(_diskio__svc__de_value)
            ld  b,0
            ld  a,(_diskio__svc__number)
            rst  $28
            jr  z,p8dio_svc_fine
            or  a
            jr  nz,p8dio_svc_store
            ld  a,255
            jr  p8dio_svc_store
p8dio_svc_fine:
            xor  a
p8dio_svc_store:
            ld  (_diskio__svc__answer),a
        }}
        return answer
    }

    sub fspec(^^ubyte name, ^^ubyte fcb) -> bool {
        return svc(SVC_FSPEC, name, fcb) == 0
    }

    sub open_existing(^^ubyte fcb, ^^ubyte sector) -> bool {
        return svc(SVC_OPEN, sector, fcb) == 0
    }

    sub open_new(^^ubyte fcb, ^^ubyte sector) -> bool {
        return svc(SVC_INIT, sector, fcb) == 0
    }

    sub close_file(^^ubyte fcb) {
        ; (only when the DOS has it as open: the top bit of the control block's first byte)
        if fcb[0] & $80 != 0
            void svc(SVC_CLOSE, 0, fcb)
    }

    sub kill(^^ubyte fcb) -> bool {
        return svc(SVC_REMOV, 0, fcb) == 0
    }

    sub command(^^ubyte text) {
        void svc(SVC_CMNDR, text, 0)
    }

    sub get_byte(^^ubyte fcb) -> uword {
        ; -- the next byte of an open file, or $ffff at its end
        uword @shared data
        %asm {{
            ld  de,(_diskio__get_byte__fcb)
            ld  a,3
            rst  $28
            ld  hl,$ffff
            jr  nz,p8dio_get_store
            ld  l,a
            ld  h,0
p8dio_get_store:
            ld  (_diskio__get_byte__data),hl
        }}
        return data
    }

    sub put_byte(^^ubyte fcb, ubyte value) -> bool {
        ; -- a byte to an open file (it goes in C)
        bool @shared went
        %asm {{
            ld  de,(_diskio__put_byte__fcb)
            ld  a,(_diskio__put_byte__value)
            ld  c,a
            ld  a,4
            rst  $28
            ld  a,1
            jr  z,p8dio_put_store
            xor  a
p8dio_put_store:
            ld  (_diskio__put_byte__went),a
        }}
        return went
    }

    sub last_drive() -> ubyte {
        ; -- the drive of the file that was opened last for reading (the DOS has it in the control block)
        return read_fcb[6] & 7
    }
}
