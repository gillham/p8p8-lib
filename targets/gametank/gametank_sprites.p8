; Sprite sheets: loading them into sprite ram, and their frame tables.
;
; Prog8 version of the GameTank SDK's src/gt/gfx/sprites.c, and of
; direct_draw_sprite_frame() of draw_direct.c, with the names of the C SDK.
;
; Sprite ram is 8 pages of 256 * 256 pixels, each of 4 quadrants of 128 * 128.
; A sprite slot is what the drawing routines take: the page (0-7) plus
; SPRITE_OFFSET_X_MASK and/or SPRITE_OFFSET_Y_MASK for the quadrant where the
; sheet starts.  A sheet is deflate data of the 16384 bytes of one quadrant.
;
;   slot = gametank.allocate_sprite(&sheet, bank)       ; a free quadrant, loaded
;   gametank.set_sprite_frametable(slot, &frames, bank)
;   ...
;   gametank.direct_prepare_sprite_mode(slot)
;   gametank.direct_draw_sprite_frame(slot, 64, 64, frame, gametank.SPRITE_FLIP_NONE)
;
; Different from the C SDK: a sheet and a frame table are an address and the
; ROM bank where that is (255 = the fixed bank), there are no generated asset
; lists.  A sheet of more than one quadrant is loaded with get_sprite_slot()
; and one load_spritesheet() for each quadrant: see get_sprite_slot().
;
; A frame table is 8 bytes for each frame (the Frame struct of the C SDK):
;   0  x    where the frame is drawn, from the position that is asked for
;   1  y
;   2  w    size in pixels
;   3  h
;   4  gx   where the frame is in the sheet
;   5  gy
;   6  c    not used here
;   7  b    not used here

%import gametank
%import gametank_banking
%import gametank_draw
%import zlib

gametank {
%option merge

    ; the quadrants that a sheet takes, for get_sprite_slot()
    const ubyte PAGE_MASK_SINGLE = 1        ; 128 * 128
    const ubyte PAGE_MASK_WIDE = 3          ; 256 * 128
    const ubyte PAGE_MASK_TALL = 5          ; 128 * 256
    const ubyte PAGE_MASK_FULL = 15         ; 256 * 256

    const ubyte SPRITE_SLOT_COUNT = 32
    const ubyte SPRITE_SLOT_NONE = $ff      ; no room: what get_sprite_slot() and allocate_sprite() return then
    const ubyte SPRITE_SLOT_INVALID_MASK = %11100000    ; slot & this is not 0: not a slot

    ; the bytes of a frame, in a frame table and in sprite_temp_frame
    const ubyte FRAME_X = 0
    const ubyte FRAME_Y = 1
    const ubyte FRAME_W = 2
    const ubyte FRAME_H = 3
    const ubyte FRAME_GX = 4
    const ubyte FRAME_GY = 5
    const ubyte FRAME_C = 6
    const ubyte FRAME_B = 7
    const ubyte FRAME_SIZE = 8

    ; the frame that sprite_fetch_frame() got
    ubyte[FRAME_SIZE] sprite_temp_frame

    const ubyte HEAD_CORNER_NW = 16
    const ubyte HEAD_CORNER_NE = 32
    const ubyte HEAD_CORNER_SW = 64
    const ubyte HEAD_CORNER_SE = 128

    ; for each page of sprite ram: bits 0-3 the quadrants that are taken,
    ; bits 4-7 the quadrants where a sheet starts
    ubyte[8] bank_occupied
    ubyte[SPRITE_SLOT_COUNT] sprite_size_cache
    uword[SPRITE_SLOT_COUNT] frametable_addr
    ubyte[SPRITE_SLOT_COUNT] frametable_B

    ; Make $4000-$7fff the quadrant ramBank of sprite ram: the page (0-7) plus
    ; QUADRANT_0 to QUADRANT_3.  The blitter is off afterwards: put flagsMirror
    ; and banksMirror back when done.
    sub sprite_ram_select(ubyte ramBank) {
        flagsMirror = DMA_ENABLE
        dma_flags = flagsMirror
        ; a blit of one pixel: the blitter keeps the quadrant that it read from last
        BLIT_VX = 0
        BLIT_VY = 0
        BLIT_GX = (ramBank & 8) << 4
        BLIT_GY = (ramBank & 16) << 3
        BLIT_WIDTH = 1
        BLIT_HEIGHT = 1
        BLIT_START = 1
        BLIT_START = 0
        flagsMirror = 0
        dma_flags = flagsMirror
        banksMirror = bankflip | (ramBank & BANK_GRAM_MASK)
        bank_reg = banksMirror
    }

    ; Unpack the deflate data of a sheet, at spriteData in ROM bank srcBank,
    ; into the quadrant ramBank of sprite ram: the page (0-7) plus QUADRANT_0
    ; to QUADRANT_3.  There is no vsync interrupt while this runs.
    sub load_spritesheet(uword spriteData, ubyte srcBank, ubyte ramBank) {
        ubyte oldFlags = flagsMirror
        ubyte oldBanks = banksMirror
        push_rom_bank()
        change_rom_bank(srcBank)
        sprite_ram_select(ramBank)
        zlib.inflate(spriteData, SCREENRAM)
        flagsMirror = oldFlags
        banksMirror = oldBanks
        dma_flags = flagsMirror
        bank_reg = banksMirror
        pop_rom_bank()
    }

    ; Fill a quadrant of sprite ram with 0: the page (0-7) plus QUADRANT_0 to QUADRANT_3.
    sub clear_spritebank(ubyte bank) {
        ubyte oldFlags = flagsMirror
        ubyte oldBanks = banksMirror
        sprite_ram_select(bank)
        sys.memset(SCREENRAM, 16384, 0)
        flagsMirror = oldFlags
        banksMirror = oldBanks
        dma_flags = flagsMirror
        bank_reg = banksMirror
    }

    ; Find room for a sheet that takes the quadrants of size_mask (a PAGE_MASK_
    ; constant) and mark it as taken.  Returns the slot, or SPRITE_SLOT_NONE.
    ; Nothing is loaded.  The quadrants of the sheet, in the order of the bits
    ; of size_mask, go to  (slot & 7) | ((slot & SPRITE_OFFSET_XY_MASK) + QUADRANT_n):
    ; for a PAGE_MASK_FULL sheet that is QUADRANT_0 to QUADRANT_3 of page slot.
    sub get_sprite_slot(ubyte size_mask) -> ubyte {
        ubyte i
        for i in 0 to 7 {
            if bank_occupied[i] & size_mask == 0 {
                bank_occupied[i] |= size_mask | HEAD_CORNER_NW
                return took(i)
            }
            if size_mask == PAGE_MASK_FULL
                continue
            if size_mask != PAGE_MASK_WIDE {
                ; the sheet is one quadrant wide: the right half will do too
                if bank_occupied[i] & (size_mask << 1) == 0 {
                    bank_occupied[i] |= ((size_mask << 1) & %1010) | HEAD_CORNER_NE
                    return took(i | SPRITE_OFFSET_X_MASK)
                }
            }
            if size_mask != PAGE_MASK_TALL {
                ; the sheet is one quadrant high: the lower half will do too
                if bank_occupied[i] & (size_mask << 2) == 0 {
                    bank_occupied[i] |= ((size_mask << 2) & %1100) | HEAD_CORNER_SW
                    return took(i | SPRITE_OFFSET_Y_MASK)
                }
            }
            if size_mask == PAGE_MASK_SINGLE {
                if bank_occupied[i] & %1000 == 0 {
                    bank_occupied[i] |= %1000 | HEAD_CORNER_SE
                    return took(i | SPRITE_OFFSET_XY_MASK)
                }
            }
        }
        return SPRITE_SLOT_NONE

        sub took(ubyte slot) -> ubyte {
            sprite_size_cache[slot] = size_mask
            return slot
        }
    }

    ; Find room for a sheet of one quadrant and load it there.
    ; Returns the slot, or SPRITE_SLOT_NONE when sprite ram is full.
    sub allocate_sprite(uword spriteData, ubyte srcBank) -> ubyte {
        ubyte slot = get_sprite_slot(PAGE_MASK_SINGLE)
        if slot != SPRITE_SLOT_NONE
            load_spritesheet(spriteData, srcBank, slot)
        return slot
    }

    ; Give the room of a slot back.
    sub free_sprite(ubyte slot) {
        ubyte heads = bank_occupied[slot & 7] >> 4
        ubyte clear_mask = ~heads
        when slot & SPRITE_OFFSET_XY_MASK {
            0 -> {
                clear_mask &= %1111
                clear_mask |= 1
                if clear_mask & %0110 != %0110
                    clear_mask &= 7
            }
            SPRITE_OFFSET_X_MASK -> {
                clear_mask &= %1010
                clear_mask |= 2
                if sprite_size_cache[slot] == 1
                    clear_mask &= 7
            }
            SPRITE_OFFSET_Y_MASK -> {
                clear_mask &= %1100
                clear_mask |= 4
                if sprite_size_cache[slot] == 1
                    clear_mask &= 7
            }
            else -> clear_mask = %1000
        }
        clear_mask |= clear_mask << 4
        bank_occupied[slot & 7] &= ~clear_mask
    }

    ; Say where the frame table of a slot is: its address, and its ROM bank.
    sub set_sprite_frametable(ubyte sprite, uword frametable, ubyte frametable_bank) {
        frametable_B[sprite] = frametable_bank
        frametable_addr[sprite] = frametable
    }

    ; Copy a frame of the frame table of a slot to sprite_temp_frame.
    sub sprite_fetch_frame(ubyte sprite, ubyte frame) {
        uword @zp src
        ubyte i
        push_rom_bank()
        change_rom_bank(frametable_B[sprite])
        src = frametable_addr[sprite] + (frame as uword) * FRAME_SIZE
        for i in 0 to FRAME_SIZE-1 {
            sprite_temp_frame[i] = src[i]
        }
        pop_rom_bank()
    }

    ; Draw a frame of a slot at (dst_x, dst_y), flipped or not (a SPRITE_FLIP_
    ; constant).  The registers must be set to draw sprites:
    ; direct_prepare_sprite_mode().  Waits for a blit that is still going on,
    ; not for this one: await_drawing() does that.
    sub direct_draw_sprite_frame(ubyte sprite, ubyte dst_x, ubyte dst_y, ubyte frame, ubyte flip) {
        ubyte rx
        ubyte ry
        ubyte rgx
        ubyte rgy
        ubyte rw
        ubyte rh
        sys.set_irqd()
        sprite_fetch_frame(sprite, frame)
        rw = sprite_temp_frame[FRAME_W]
        rh = sprite_temp_frame[FRAME_H]
        rgx = sprite_temp_frame[FRAME_GX]
        if sprite & SPRITE_OFFSET_X_MASK != 0
            rgx |= 128
        if flip & SPRITE_FLIP_X != 0 {
            rx = dst_x - rw - sprite_temp_frame[FRAME_X] - 1
            rgx ^= $ff
            rgx -= rw - 1
            rw |= 128
        } else {
            rx = sprite_temp_frame[FRAME_X] + dst_x
        }
        rgy = sprite_temp_frame[FRAME_GY]
        if sprite & SPRITE_OFFSET_Y_MASK != 0
            rgy |= 128
        if flip & SPRITE_FLIP_Y != 0 {
            ry = dst_y - rh - sprite_temp_frame[FRAME_Y] - 1
            rgy ^= $ff
            rgy -= rh - 1
            rh |= 128
        } else {
            ry = sprite_temp_frame[FRAME_Y] + dst_y
        }
        await_drawing()
        direct_quick_select_sprite(sprite)
        BLIT_VX = rx
        BLIT_VY = ry
        BLIT_GX = rgx
        BLIT_GY = rgy
        BLIT_WIDTH = rw
        BLIT_HEIGHT = rh
        draw_busy = true
        BLIT_START = 1
    }
}
