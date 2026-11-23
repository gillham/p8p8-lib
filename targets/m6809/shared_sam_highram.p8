; The upper 32 KB of a 64 KB Color Computer 1 or 2 or Dragon 64 as memory for data (the
; highram module of the coco2, dragon32 and dragon64 targets of p8p8).
;
; On these machines BASIC's ROMs are at $8000-$feff, and with 64 KB there is RAM under
; them that a switch in the machine's address decoder (the SAM, at $ffde/$ffdf) puts in
; their place.  The program itself stays below $8000 with the ROMs on, so that the keys,
; the floats and the disk work as ever; the routines here switch the RAM in for the
; moment of an access, with interrupts off (BASIC's interrupt routine is in the ROM),
; and the ROMs back on after it.
;
; An address here is one in $8000-$feff (START, SIZE bytes).  The other side of get()
; and put() is the program's own memory below $8000.  present() says whether the
; machine has that RAM: it has not with 32 KB or less (a Dragon 32).

highram {
    %option no_symbol_prefixing, ignore_unused

    const uword START = $8000
    const uword SIZE = $7f00            ; up to $feff: the machine's own addresses follow

    sub present() -> bool {
        ; -- is there RAM under the ROMs?  A byte there is changed and read back, and put
        ;    back as it was; where the lower half shows again up there, it changes too.
        bool @shared found
        %asm {{
            pshs  cc
            orcc  #$50
            clr  _highram__present__found
            sta  $ffdf
            ldb  $8000
            lda  >$0000
            pshs  a
            comb
            stb  $8000
            cmpb  $8000
            bne  p8highram_present_end
            lda  >$0000
            cmpa  ,s
            bne  p8highram_present_end
            inc  _highram__present__found
            p8highram_present_end:
            comb
            stb  $8000
            leas  1,s
            sta  $ffde
            puls  cc
        }}
        return found
    }

    sub get(uword address, pointer dest, uword count) {
        ; -- count bytes from address in the upper memory to dest in the program's
        %asm {{
            ldx  _highram__get__address
            ldu  _highram__get__dest
            ldy  _highram__get__count
            beq  p8highram_get_end
            pshs  cc
            orcc  #$50
            sta  $ffdf
            p8highram_get_next:
            lda  ,x+
            sta  ,u+
            leay  -1,y
            bne  p8highram_get_next
            sta  $ffde
            puls  cc
            p8highram_get_end:
        }}
    }

    sub put(pointer src, uword address, uword count) {
        ; -- count bytes from src in the program's memory to address in the upper memory
        %asm {{
            ldx  _highram__put__src
            ldu  _highram__put__address
            ldy  _highram__put__count
            beq  p8highram_put_end
            pshs  cc
            orcc  #$50
            sta  $ffdf
            p8highram_put_next:
            lda  ,x+
            sta  ,u+
            leay  -1,y
            bne  p8highram_put_next
            sta  $ffde
            puls  cc
            p8highram_put_end:
        }}
    }

    sub getbyte(uword address) -> ubyte {
        ; -- the byte at address in the upper memory
        ubyte @shared value
        %asm {{
            ldx  _highram__getbyte__address
            pshs  cc
            orcc  #$50
            sta  $ffdf
            lda  ,x
            sta  $ffde
            puls  cc
            sta  _highram__getbyte__value
        }}
        return value
    }

    sub setbyte(uword address, ubyte value) {
        ; -- value into the byte at address in the upper memory
        %asm {{
            ldx  _highram__setbyte__address
            lda  _highram__setbyte__value
            pshs  cc
            orcc  #$50
            sta  $ffdf
            sta  ,x
            sta  $ffde
            puls  cc
        }}
    }

    sub fill(uword address, uword count, ubyte value) {
        ; -- count bytes of the upper memory from address on get the value
        %asm {{
            ldx  _highram__fill__address
            ldy  _highram__fill__count
            beq  p8highram_fill_end
            lda  _highram__fill__value
            pshs  cc
            orcc  #$50
            sta  $ffdf
            p8highram_fill_next:
            sta  ,x+
            leay  -1,y
            bne  p8highram_fill_next
            sta  $ffde
            puls  cc
            p8highram_fill_end:
        }}
    }

    sub move(uword from, uword target, uword count) {
        ; -- count bytes within the upper memory, from one address to another; the two may overlap
        %asm {{
            ldx  _highram__move__from
            ldu  _highram__move__target
            ldy  _highram__move__count
            beq  p8highram_move_end
            pshs  cc
            orcc  #$50
            sta  $ffdf
            cmpx  _highram__move__target
            bhs  p8highram_move_up
            tfr  y,d
            leax  d,x
            leau  d,u
            p8highram_move_back:
            lda  ,-x
            sta  ,-u
            leay  -1,y
            bne  p8highram_move_back
            bra  p8highram_move_done
            p8highram_move_up:
            lda  ,x+
            sta  ,u+
            leay  -1,y
            bne  p8highram_move_up
            p8highram_move_done:
            sta  $ffde
            puls  cc
            p8highram_move_end:
        }}
    }
}
