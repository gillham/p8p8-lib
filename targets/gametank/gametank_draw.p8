; Drawing with the blitter, one blit at a time ("direct mode").
;
; Prog8 version of the GameTank SDK's src/gt/gfx/draw_direct.c and
; draw_direct.h, and the constants of gfx_sys.h, with the names of the C SDK.
; direct_prepare_box_mode() and DIRECT_DRAW_COLOR() are in gametank.p8.
;
;   gametank.direct_prepare_sprite_mode(slot)       ; once, then any number of:
;   gametank.DIRECT_DRAW_SPRITE(x, y, w, h, gx, gy)
;   gametank.await_drawing()                        ; before the next blit
;
; A sprite slot is a page of sprite ram (0-7), plus SPRITE_OFFSET_X_MASK and/or
; SPRITE_OFFSET_Y_MASK for the quadrant of that page where the sheet is.
;
; The blitter's registers (BLIT_VX and so on) can be set directly too: several
; blits that share a width, a height or a row then need fewer writes.
;
; direct_draw_sprite_frame() is in gametank_sprites.p8, with the frame tables.
; The direct_prepare_ routines wait for the draw queue first, in a program that
; has it (gametank_drawqueue.p8).

%import gametank

gametank {
%option merge

    const ubyte SCREEN_WIDTH = 128
    const ubyte SCREEN_HEIGHT = 128

    const ubyte BANK_GRAM_MASK = 7          ; the page of sprite ram, in the banking register

    const ubyte CLIP_MODE_NONE = 0
    const ubyte CLIP_MODE_X = 16
    const ubyte CLIP_MODE_Y = 32
    const ubyte CLIP_MODE_XY = 48

    const ubyte SPRITE_FLIP_NONE = 0
    const ubyte SPRITE_FLIP_X = 1
    const ubyte SPRITE_FLIP_Y = 2
    const ubyte SPRITE_FLIP_BOTH = 3

    const ubyte QUADRANT_0 = 0
    const ubyte QUADRANT_1 = 8
    const ubyte QUADRANT_2 = 16
    const ubyte QUADRANT_3 = 24

    const ubyte SPRITE_OFFSET_X_MASK = 8
    const ubyte SPRITE_OFFSET_Y_MASK = 16
    const ubyte SPRITE_OFFSET_XY_MASK = 24

    ; the part of the picture that a TV may not show
    const ubyte BORDER_BOTTOM_HEIGHT = 8
    const ubyte BORDER_TOP_HEIGHT = 7
    const ubyte BORDER_LEFT_WIDTH = 1
    const ubyte BORDER_RIGHT_WIDTH = 1

    ; where the selected sprite slot is in its page of sprite ram: 0 or 128
    ubyte direct_sprite_offset_x
    ubyte direct_sprite_offset_y

    ; Set the registers to draw sprites from a slot, with color 0 transparent.
    sub direct_prepare_sprite_mode(ubyte sprite) {
        await_draw_queue_if_any()   ; Make sure we don't intersect with the queued system.
        await_drawing()
        flagsMirror |= DMA_ENABLE | DMA_IRQ | DMA_GCARRY
        flagsMirror &= ~(DMA_COLORFILL_ENABLE | DMA_OPAQUE)
        dma_flags = flagsMirror
        banksMirror &= ~(BANK_RAM_MASK | BANK_SECOND_FRAMEBUFFER | BANK_GRAM_MASK)
        banksMirror |= bankflip | (sprite & BANK_GRAM_MASK) | BANK_CLIP_X | BANK_CLIP_Y
        bank_reg = banksMirror
        direct_set_sprite_offset(sprite)
    }

    ; Only select another sprite slot; the other settings stay.
    sub direct_quick_select_sprite(ubyte sprite) {
        banksMirror &= ~BANK_GRAM_MASK
        banksMirror |= sprite & BANK_GRAM_MASK
        bank_reg = banksMirror
        direct_set_sprite_offset(sprite)
    }

    ; Set the registers so that $4000-$7fff is the framebuffer that is drawn to.
    sub direct_prepare_array_mode() {
        await_draw_queue_if_any()
        await_drawing()
        flagsMirror |= DMA_CPU_TO_VRAM
        flagsMirror &= ~DMA_ENABLE
        dma_flags = flagsMirror
    }

    ; Set the registers so that $4000-$7fff is the sprite ram of a slot
    ; (the quadrant of its page: 128 * 128 bytes).
    sub direct_prepare_sprite_ram_array_mode(ubyte sprite) {
        await_draw_queue_if_any()
        await_drawing()
        flagsMirror |= DMA_ENABLE | DMA_IRQ | DMA_GCARRY
        flagsMirror &= ~(DMA_COLORFILL_ENABLE | DMA_OPAQUE | DMA_CPU_TO_VRAM)
        dma_flags = flagsMirror
        banksMirror &= ~(BANK_RAM_MASK | BANK_SECOND_FRAMEBUFFER | BANK_GRAM_MASK)
        banksMirror |= bankflip | (sprite & BANK_GRAM_MASK) | BANK_CLIP_X | BANK_CLIP_Y
        bank_reg = banksMirror
        direct_set_sprite_offset(sprite)
        ; a blit of nothing: the blitter keeps the quadrant that it read from last
        BLIT_COLOR = ~0
        BLIT_VX = 0
        BLIT_VY = 0
        BLIT_GX = direct_sprite_offset_x
        BLIT_GY = direct_sprite_offset_y
        BLIT_WIDTH = 0
        BLIT_HEIGHT = 0
        BLIT_START = 1
        flagsMirror &= ~DMA_ENABLE
        dma_flags = flagsMirror
        BLIT_START = 0          ; no interrupt is left waiting,
        draw_busy = false       ; and nothing to wait for
    }

    ; Tiled: a blit repeats the 16 * 16 pixels where its source starts.
    sub direct_tiled_mode(bool enabled) {
        if enabled
            flagsMirror &= ~DMA_GCARRY
        else
            flagsMirror |= DMA_GCARRY
        dma_flags = flagsMirror
    }

    ; Transparent: color 0 of a sprite is not drawn.
    sub direct_transparent_mode(bool enabled) {
        if enabled
            flagsMirror &= ~DMA_OPAQUE
        else
            flagsMirror |= DMA_OPAQUE
        dma_flags = flagsMirror
    }

    ; Clip at the edges of the screen (a CLIP_MODE_ constant), or wrap around.
    sub direct_clip_mode(ubyte mode) {
        banksMirror &= ~CLIP_MODE_XY
        banksMirror |= mode
        bank_reg = banksMirror
    }

    sub direct_set_sprite_offset(ubyte sprite) {
        direct_sprite_offset_x = (sprite & SPRITE_OFFSET_X_MASK) << 4
        direct_sprite_offset_y = (sprite & SPRITE_OFFSET_Y_MASK) << 3
    }

    ; Blit w * h pixels from (src_gx, src_gy) of the selected sprite slot to
    ; (dst_x, dst_y) of the screen.
    ; 128 added to w flips in x; the source is then counted from the other side
    ; of the sheet: pass  ~src_gx - (w-1)  as src_gx.  The same for h and src_gy.
    sub DIRECT_DRAW_SPRITE(ubyte dst_x, ubyte dst_y, ubyte w, ubyte h, ubyte src_gx, ubyte src_gy) {
        BLIT_VX = dst_x
        BLIT_VY = dst_y
        BLIT_GX = src_gx + direct_sprite_offset_x
        BLIT_GY = src_gy + direct_sprite_offset_y
        BLIT_WIDTH = w
        BLIT_HEIGHT = h
        draw_busy = true
        BLIT_START = 1
    }

    ; ---- the single steps, for blits that share some of their settings ----

    inline asmsub DIRECT_DRAW_START() clobbers(A) {
        %asm {{
            lda  #1
            sta  gametank.draw_busy
            sta  gametank.BLIT_START
        }}
    }

    inline asmsub DIRECT_DRAW_CLEAR_IRQ() {
        %asm {{
            stz  gametank.BLIT_START
        }}
    }

    inline asmsub DIRECT_SET_DEST_X(ubyte value @A) {
        %asm {{
            sta  gametank.BLIT_VX
        }}
    }

    inline asmsub DIRECT_SET_DEST_Y(ubyte value @A) {
        %asm {{
            sta  gametank.BLIT_VY
        }}
    }

    inline asmsub DIRECT_SET_SOURCE_X(ubyte value @A) clobbers(A) {
        %asm {{
            ora  gametank.direct_sprite_offset_x
            sta  gametank.BLIT_GX
        }}
    }

    inline asmsub DIRECT_SET_SOURCE_Y(ubyte value @A) clobbers(A) {
        %asm {{
            ora  gametank.direct_sprite_offset_y
            sta  gametank.BLIT_GY
        }}
    }

    inline asmsub DIRECT_SET_WIDTH(ubyte value @A) {
        %asm {{
            sta  gametank.BLIT_WIDTH
        }}
    }

    inline asmsub DIRECT_SET_HEIGHT(ubyte value @A) {
        %asm {{
            sta  gametank.BLIT_HEIGHT
        }}
    }

    inline asmsub DIRECT_SET_COLOR(ubyte value @A) clobbers(A) {
        %asm {{
            eor  #$ff
            sta  gametank.BLIT_COLOR
        }}
    }
}
