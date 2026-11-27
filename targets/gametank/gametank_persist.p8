; Saving to the cartridge's flash memory.
;
; Prog8 version of the GameTank SDK's src/gt/feature/persist/persist.c, with
; the names of the C SDK.
;
;   if gametank.save_write(&mydata, gametank.SAVE_SECTOR1, sizeof(mydata)) ...
;   gametank.save_read(gametank.SAVE_SECTOR1, &mydata, sizeof(mydata))
;   gametank.clear_save_sector()        ; all of the first sector is $ff again
;
; The saves are in ROM bank 254 (BANK_SAVE), as in the C SDK.  That is where
; the 2 MB flash has its two small sectors, and a sector is what gets erased:
;   SAVE_SECTOR1   $8000-$9fff of bank 254, 8 KB    clear_save_sector()
;   SAVE_SECTOR2   $a000-$bfff of bank 254, 8 KB    clear_save_sector2()
; Erasing in another bank takes much more with it: banks 252 and 253 are one
; sector together, and below them every four banks are one sector of 64 KB.
; So leave bank 254 to the saves: no %overlay 254, and no assets there other
; than the first contents of the saves.  (The second sector and the sizes are
; from the sector table of the GameTank emulator; the C SDK uses only the first.)
;
; Flash memory can only be written from 1 bits to 0 bits; erasing a sector
; makes all of it 1 bits ($ff) again.  So a byte can be written once after an
; erase.  The bank is $ff in a cartridge image that p8c wrote, so the first
; save needs no erase.  The usual way: write each save after the last one, and
; erase when the sector is full.
;
; While the flash erases or writes, none of the cartridge can be read: not the
; program either.  So the routines that do it are copied to ram and run there,
; with the interrupts off (also the vsync interrupt), and the program stands
; still meanwhile: some microseconds for each byte, but a second or so for an
; erase.  They wait for drawing that is going on first.
;
; What is written must be in ram, not in the cartridge.

%import gametank

gametank {
%option merge

    const ubyte BANK_SAVE = 254
    const uword SAVE_SECTOR1 = $8000
    const uword SAVE_SECTOR2 = $a000
    const uword SAVE_SECTOR_SIZE = $2000

    ubyte save_oldbank
    ubyte save_oldflags

    ; Erase the first save sector: $8000-$9fff of bank 254 is $ff afterwards.
    sub clear_save_sector() {
        void save_erase(SAVE_SECTOR1)
    }

    ; Erase the second save sector: $a000-$bfff of bank 254 is $ff afterwards.
    sub clear_save_sector2() {
        void save_erase(SAVE_SECTOR2)
    }

    ; Erase the save sector at SAVE_SECTOR1 or SAVE_SECTOR2.
    ; Returns true when all of it is $ff afterwards.
    sub save_erase(uword sector) -> bool {
        uword @zp ptr
        bool ok = true
        if sector != SAVE_SECTOR1 and sector != SAVE_SECTOR2
            return false
        save_begin()
        save_ram_erase(sector)
        ptr = sector
        repeat SAVE_SECTOR_SIZE {
            if @(ptr) != $ff {
                ok = false
                break
            }
            ptr++
        }
        save_end()
        return ok
    }

    ; Write count bytes from src, which must be in ram, to dest in bank 254
    ; ($8000-$bfff).  Only 1 bits can be made 0: write to where it is $ff.
    ; Returns true when the bytes are there afterwards.
    sub save_write(uword src, uword dest, ubyte count) -> bool {
        ubyte i
        bool ok = true
        if count == 0
            return true
        ; all of it in the banked part of the cartridge, and from ram
        if msb(dest) < $80 or msb(dest + count - 1) > $bf or msb(src + count - 1) >= $80
            return false
        save_begin()
        save_ram_write(src, dest, count)
        i = 0
        repeat count {
            if dest[i] != src[i] {
                ok = false
                break
            }
            i++
        }
        save_end()
        return ok
    }

    ; Copy count bytes from src in bank 254 to dest, in ram.  (Not in the C SDK:
    ; there a program changes to the bank and reads.)
    sub save_read(uword src, uword dest, ubyte count) {
        ubyte i
        if count == 0
            return
        save_oldbank = getrombank()
        rombank(BANK_SAVE)
        i = 0
        repeat count {
            dest[i] = src[i]
            i++
        }
        rombank(save_oldbank)
    }

    ; no drawing, no interrupts, and bank 254
    sub save_begin() {
        await_draw_queue_if_any()
        await_drawing()
        save_oldflags = sys.read_flags()
        sys.set_irqd()
        dma_flags = flagsMirror & ~(DMA_IRQ | DMA_NMI)
        save_oldbank = getrombank()
        rombank(BANK_SAVE)
    }

    sub save_end() {
        rombank(save_oldbank)
        dma_flags = flagsMirror
        if save_oldflags & 4 == 0
            sys.clear_irqd()
    }

    ; Erase the sector at an address of the bank that is there.
    ; Call with interrupts off (also the vsync interrupt).
    asmsub save_ram_erase(uword sector @AY) clobbers(A,X,Y) {
        %asm {{
            sta  P8ZP_SCRATCH_W1
            sty  P8ZP_SCRATCH_W1+1
            ldx  #_end-_rom-1
-           lda  _rom,x
            sta  gametank.save_ram_write.save_ramcode,x
            dex
            bpl  -
            jmp  gametank.save_ram_write.save_ramcode

_rom        .logical gametank.save_ram_write.save_ramcode
            lda  #$aa           ; unlock
            sta  $8aaa
            lda  #$55
            sta  $8555
            lda  #$80           ; erase
            sta  $8aaa
            lda  #$aa           ; unlock
            sta  $8aaa
            lda  #$55
            sta  $8555
            lda  #$30           ; this sector
            sta  (P8ZP_SCRATCH_W1)
            ; while it erases, a bit of what is read changes with every read
            ldx  #0
            ldy  #0
            lda  #64            ; give up after some 20 seconds
            sta  P8ZP_SCRATCH_B1
-           lda  (P8ZP_SCRATCH_W1)
            cmp  (P8ZP_SCRATCH_W1)
            beq  +
            inx
            bne  -
            iny
            bne  -
            dec  P8ZP_SCRATCH_B1
            bne  -
+           rts
            .here
_end
            .cerror _end-_rom > 64, "save_ram_erase does not fit in save_ramcode"
            ; !notreached!
        }}
    }

    ; Write count bytes (1-255) from src to dest, in the bank that is there.
    ; Call with interrupts off (also the vsync interrupt).
    asmsub save_ram_write(uword src @R0, uword dest @R1, ubyte count @A) clobbers(A,X,Y) {
        %asm {{
            sta  P8ZP_SCRATCH_REG
            lda  cx16.r0L
            sta  P8ZP_SCRATCH_W1
            lda  cx16.r0H
            sta  P8ZP_SCRATCH_W1+1
            lda  cx16.r1L
            sta  P8ZP_SCRATCH_W2
            lda  cx16.r1H
            sta  P8ZP_SCRATCH_W2+1
            ldx  #_end-_rom-1
-           lda  _rom,x
            sta  save_ramcode,x
            dex
            bpl  -
            jmp  save_ramcode

            .section BSS
save_ramcode    .fill  64       ; where the routines are while they run
            .send BSS

_rom        .logical save_ramcode
            lda  #$aa           ; unlock, and stay unlocked
            sta  $8aaa
            lda  #$55
            sta  $8555
            lda  #$20
            sta  $8aaa
            ldy  #0
_byte       lda  #$a0           ; write a byte
            sta  $8000
            lda  (P8ZP_SCRATCH_W1),y
            sta  (P8ZP_SCRATCH_W2),y
            ; it is there when it reads back the same
            ldx  #0
            stz  P8ZP_SCRATCH_B1        ; give up after some 0.3 seconds
-           lda  (P8ZP_SCRATCH_W2),y
            cmp  (P8ZP_SCRATCH_W1),y
            beq  +
            inx
            bne  -
            dec  P8ZP_SCRATCH_B1
            bne  -
            bra  _done
+           iny
            cpy  P8ZP_SCRATCH_REG
            bne  _byte
_done       lda  #$90           ; locked again
            sta  $8000
            lda  #$00
            sta  $8000
            rts
            .here
_end
            .cerror _end-_rom > 64, "save_ram_write does not fit in save_ramcode"
            ; !notreached!
        }}
    }
}
