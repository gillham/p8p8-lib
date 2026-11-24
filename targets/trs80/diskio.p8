; File I/O routines for the TRS-80 Model I and III (the trs80 target of p8p8): the calls
; of the DOS, which TRSDOS 2.3, TRSDOS 1.3 and LDOS 5 have at the same addresses.  The
; routines that programs use are in shared_trsdos_diskio.

%import shared_trsdos_diskio

diskio {
    %option no_symbol_prefixing, ignore_unused

    const uword DOS_COMMAND = $4419     ; do a command of the DOS and come back
    const uword DOS_FSPEC = $441c       ; a name into a file control block
    const uword DOS_INIT = $4420        ; open a file, new or not
    const uword DOS_OPEN = $4424        ; open a file that is there
    const uword DOS_CLOSE = $4428
    const uword DOS_KILL = $442c        ; remove the file that is open

    str directory_command = "DIR\r"

    sub dos(uword function, uword hl_value, uword de_value) -> ubyte {
        ; -- calls a routine of the DOS with HL and DE (and B 0: records of 256 bytes).
        ;    0 when it went well (the DOS says so with the zero flag), else its error code, or 255.
        ubyte @shared answer
        %asm {{
            ld  hl,p8dio_dos_back
            push  hl
            ld  hl,(_diskio__dos__function)
            push  hl
            ld  hl,(_diskio__dos__hl_value)
            ld  de,(_diskio__dos__de_value)
            ld  b,0
            ret
p8dio_dos_back:
            jr  z,p8dio_dos_fine
            or  a
            jr  nz,p8dio_dos_store
            ld  a,255
            jr  p8dio_dos_store
p8dio_dos_fine:
            xor  a
p8dio_dos_store:
            ld  (_diskio__dos__answer),a
        }}
        return answer
    }

    sub fspec(^^ubyte name, ^^ubyte fcb) -> bool {
        return dos(DOS_FSPEC, name, fcb) == 0
    }

    sub open_existing(^^ubyte fcb, ^^ubyte sector) -> bool {
        return dos(DOS_OPEN, sector, fcb) == 0
    }

    sub open_new(^^ubyte fcb, ^^ubyte sector) -> bool {
        return dos(DOS_INIT, sector, fcb) == 0
    }

    sub close_file(^^ubyte fcb) {
        ; (only when the DOS has it as open: the top bit of the control block's first byte)
        if fcb[0] & $80 != 0
            void dos(DOS_CLOSE, 0, fcb)
    }

    sub kill(^^ubyte fcb) -> bool {
        return dos(DOS_KILL, 0, fcb) == 0
    }

    ; (no call of these DOSes renames a file on every one of them: see rename in shared_trsdos_diskio)
    const bool HAS_RENAME = false

    sub dos_rename(^^ubyte fcb, ^^ubyte newspec) -> bool {
        return false
    }

    sub command(^^ubyte text) {
        void dos(DOS_COMMAND, text, 0)
    }

    sub get_byte(^^ubyte fcb) -> uword {
        ; -- the next byte of an open file (the ROM's routine at $0013), or $ffff at its end
        uword @shared data
        %asm {{
            ld  de,(_diskio__get_byte__fcb)
            call  $0013
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
        ; -- a byte to an open file (the ROM's routine at $001b)
        bool @shared went
        %asm {{
            ld  de,(_diskio__put_byte__fcb)
            ld  a,(_diskio__put_byte__value)
            call  $001b
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
