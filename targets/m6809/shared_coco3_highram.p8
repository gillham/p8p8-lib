; The Color Computer 3's memory beyond the 64 KB that a program sees, as memory for
; data (the highram module of the coco3 target of p8p8).
;
; The machine's memory is blocks of 8 KB, of which eight are in the processor's 64 KB
; at a time: BASIC has blocks $38 to $3f there (the ROMs' code is in the upper four,
; copied into RAM), and a register for each 8 KB ($ffa0 to $ffa7) says which block it
; is.  The blocks that this module takes as its memory:
;
; - with 512 KB: blocks $00 to $2f, 384 KB, which BASIC does not use;
; - with 128 KB: blocks $30 to $35, 48 KB.  These are BASIC's high resolution
;   graphics screen (HSCREEN) and what belongs to it (HGET and HPUT's buffers, HPAINT's
;   stack): what a program keeps here is gone when BASIC draws there, and the reverse.
;   (With the coco3ram target the program itself has four of them: 16 KB are left.)
;
; An address here is a long, 0 to size() - 1, counted through those blocks.  The
; routines put the blocks they need at $a000 and $c000 for the moment of an access,
; with interrupts off (BASIC's code is there), and the blocks that were there (BASIC's,
; or the program's own with the coco3ram target) back after it.  The
; other side of get() and put() is the program's own memory, below $8000.
;
; (The Color Computer 2 and the Dragons have a highram module too, with the same
; routines: there an address is a word, from highram.START on.)

highram {
    %option no_symbol_prefixing, ignore_unused

    const long START = 0
    const uword BLOCK = $2000           ; a block's bytes

    ubyte first_block = 255             ; the first of the module's blocks (255: not looked at yet)
    ubyte blocks                        ; and how many they are

    ; for the routine in assembly below
    ubyte @shared low_block             ; the block at $a000 meanwhile
    ubyte @shared high_block            ; the block at $c000 meanwhile
    uword @shared from_address
    uword @shared target_address
    uword @shared byte_count
    ubyte @shared fill_value

    sub look() {
        ; -- how much memory the machine has: with 128 KB a block's number counts its
        ;    lower four bits only, so that block $00 is block $30 again
        if first_block != 255
            return
        ubyte @shared same
        %asm {{
            pshs  cc
            orcc  #$50
            clr  _highram__look__same
            lda  $ffa6
            pshs  a
            lda  #$30
            sta  $ffa6
            ldb  $c000
            pshs  b
            clra
            sta  $ffa6
            ldb  $c000
            pshs  b
            lda  #$a5
            sta  $c000
            lda  #$30
            sta  $ffa6
            lda  #$5a
            sta  $c000
            clra
            sta  $ffa6
            lda  $c000
            cmpa  #$a5
            beq  p8highram_look_apart
            inc  _highram__look__same
            p8highram_look_apart:
            puls  b
            stb  $c000
            lda  #$30
            sta  $ffa6
            puls  b
            stb  $c000
            puls  a
            sta  $ffa6
            puls  cc
        }}
        if same != 0 {
            first_block = $30
            blocks = 6
            ; (the coco3ram target: the program has blocks $30 to $33 as its own)
            if @($ffa4) & $3f == $30 {
                first_block = $34
                blocks = 2
            }
        }
        else {
            first_block = 0
            blocks = $30
        }
    }

    sub present() -> bool {
        ; -- every Color Computer 3 has some: see size()
        return true
    }

    sub size() -> long {
        ; -- the bytes of this memory: 393216 with 512 KB, 49152 with 128 KB (16384 there with coco3ram)
        look()
        return (blocks as long) << 13
    }

    sub transfer() {
        ; -- byte_count bytes (not 0) from from_address to target_address, upwards, with
        ;    low_block at $a000 and high_block at $c000
        %asm {{
            ldx  _highram__from_address
            ldu  _highram__target_address
            ldy  _highram__byte_count
            pshs  cc
            orcc  #$50
            lda  $ffa5
            ldb  $ffa6
            pshs  d
            lda  _highram__low_block
            sta  $ffa5
            lda  _highram__high_block
            sta  $ffa6
            p8highram_transfer_next:
            lda  ,x+
            sta  ,u+
            leay  -1,y
            bne  p8highram_transfer_next
            puls  d
            sta  $ffa5
            stb  $ffa6
            puls  cc
        }}
    }

    sub transfer_back() {
        ; -- the same downwards: the two addresses are the ends (the byte after the last)
        %asm {{
            ldx  _highram__from_address
            ldu  _highram__target_address
            ldy  _highram__byte_count
            pshs  cc
            orcc  #$50
            lda  $ffa5
            ldb  $ffa6
            pshs  d
            lda  _highram__low_block
            sta  $ffa5
            lda  _highram__high_block
            sta  $ffa6
            p8highram_back_next:
            lda  ,-x
            sta  ,-u
            leay  -1,y
            bne  p8highram_back_next
            puls  d
            sta  $ffa5
            stb  $ffa6
            puls  cc
        }}
    }

    sub get(long address, pointer dest, uword count) {
        ; -- count bytes from address in this memory to dest in the program's
        look()
        high_block = @($ffa6)
        while count != 0 {
            uword offset = lsw(address) & (BLOCK - 1)
            uword part = BLOCK - offset
            if part > count
                part = count
            low_block = first_block + lsb(address >> 13)
            from_address = $a000 + offset
            target_address = dest
            byte_count = part
            transfer()
            address += part
            dest += part
            count -= part
        }
    }

    sub put(pointer src, long address, uword count) {
        ; -- count bytes from src in the program's memory to address in this memory
        look()
        low_block = @($ffa5)
        while count != 0 {
            uword offset = lsw(address) & (BLOCK - 1)
            uword part = BLOCK - offset
            if part > count
                part = count
            high_block = first_block + lsb(address >> 13)
            from_address = src
            target_address = $c000 + offset
            byte_count = part
            transfer()
            address += part
            src += part
            count -= part
        }
    }

    sub getbyte(long address) -> ubyte {
        ; -- the byte at address in this memory
        ubyte value
        get(address, &value, 1)
        return value
    }

    sub setbyte(long address, ubyte value) {
        ; -- value into the byte at address in this memory
        put(&value, address, 1)
    }

    sub fill(long address, long count, ubyte value) {
        ; -- count bytes of this memory from address on get the value
        look()
        fill_value = value
        while count != 0 {
            uword offset = lsw(address) & (BLOCK - 1)
            uword part = BLOCK - offset
            if part > count
                part = lsw(count)
            high_block = first_block + lsb(address >> 13)
            target_address = $c000 + offset
            byte_count = part
            %asm {{
                ldu  _highram__target_address
                ldy  _highram__byte_count
                ldb  _highram__fill_value
                pshs  cc
                orcc  #$50
                lda  $ffa6
                pshs  a
                lda  _highram__high_block
                sta  $ffa6
                p8highram_fill_next:
                stb  ,u+
                leay  -1,y
                bne  p8highram_fill_next
                puls  a
                sta  $ffa6
                puls  cc
            }}
            address += part
            count -= part
        }
    }

    sub move(long from, long target, long count) {
        ; -- count bytes within this memory, from one address to another; the two may overlap
        look()
        uword offset
        uword other
        uword part
        if from >= target {
            while count != 0 {
                offset = lsw(from) & (BLOCK - 1)
                other = lsw(target) & (BLOCK - 1)
                part = BLOCK - offset
                if part > BLOCK - other
                    part = BLOCK - other
                if part > count
                    part = lsw(count)
                low_block = first_block + lsb(from >> 13)
                high_block = first_block + lsb(target >> 13)
                from_address = $a000 + offset
                target_address = $c000 + other
                byte_count = part
                transfer()
                from += part
                target += part
                count -= part
            }
            return
        }
        ; downwards, from the ends: a piece ends where a block of either side begins
        from += count
        target += count
        while count != 0 {
            offset = lsw(from - 1) & (BLOCK - 1)
            other = lsw(target - 1) & (BLOCK - 1)
            part = offset + 1
            if part > other + 1
                part = other + 1
            if part > count
                part = lsw(count)
            low_block = first_block + lsb((from - 1) >> 13)
            high_block = first_block + lsb((target - 1) >> 13)
            from_address = $a001 + offset
            target_address = $c001 + other
            byte_count = part
            transfer_back()
            from -= part
            target -= part
            count -= part
        }
    }
}
