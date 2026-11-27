; inflate: unpack deflate data, for the GameTank.
;
; Bindings for zlib6502 by Piotr Fusik (https://github.com/pfusik/zlib6502).
; Its inflate is in zlib6502_inflate.asm, converted to 64tass syntax; it is not
; part of this library and has its own license: see that file and NOTICE.md.
;
; The data is a raw deflate stream (no zlib or gzip header), as the GameTank
; SDK's asset import and Python's zlib.compressobj(9, zlib.DEFLATED, -15) make.
;
; inflate uses the virtual registers R6-R10 (srcptr and destptr are R6 and R7),
; and 765 bytes of the program's variable memory.

zlib {
    %option overlay_safe

    &uword srcptr  = $0014      ; cx16.r6
    &uword destptr = $0016      ; cx16.r7

    ; unpack the deflate data at src to dest
    sub inflate(uword src, uword dest) {
        srcptr = src
        destptr = dest
        inflate_rom()
    }

    sub init() {
    }

    ; unpack the deflate data at srcptr to destptr
    asmsub inflate_rom() clobbers(A,X,Y) {
        %asm {{
inflate_zp      = cx16.r6       ; 10 bytes: R6-R10
            .section BSS
inflate_data    .fill  765
            .send BSS
            .include "zlib6502_inflate.asm"
            .cerror inflate_data_size != 765, "the size of inflate_data changed"
            ; !notreached!
        }}
    }
}
