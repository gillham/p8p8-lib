; The draw queue: blits that the blitter's interrupt starts one after another,
; while the program goes on.
;
; Prog8 version of the GameTank SDK's src/gt/gfx/draw_queue.c and draw_util.s,
; and of the queue's part of interrupt.s, with the names of the C SDK.
;
;   gametank.queue_clear_screen(32)
;   gametank.queue_draw_sprite(x, y, 16, 16, gx, gy, slot)
;   gametank.queue_draw_box(10, 100, 50, 8, 92)
;   ...
;   gametank.await_draw_queue()         ; everything is drawn
;   gametank.flip_pages()
;
; A queued blit takes the framebuffer that is drawn to at the time it is
; queued, so wait for the queue before flip_pages().  The direct_prepare_
; routines wait for the queue themselves.
;
; The queue is 250 blits; when it is full, queueing waits until it is empty.
; It is in ram bank 1, at $0200-$0aff: nothing of the program's own memory.
; The blit that is being queued is in rect and queue_flags_param, which are in
; the audio ram ($3200-$3208), where they can be read while ram bank 1 is there.
; All of this is as in the C SDK.
;
; The program must be in ram bank 0 when it queues a blit, and while the queue
; is not empty.  Ram bank 1 is there for some 60 cycles for each blit, twice.
; The vsync interrupt has its variables in ram bank 0, so a program with this
; module gets the vsync routine that is below, in place of the one of
; syslib.p8: it sees from the address where it interrupted whether ram bank 1
; is there, and goes to ram bank 0 for its work then.

%import gametank
%import gametank_draw
%import gametank_sprites

gametank {
%option merge

    const ubyte QUEUE_MAX = 250

    ubyte @shared queue_start       ; the next blit to start
    ubyte @shared queue_end         ; where the next blit is queued
    ubyte @shared queue_count
    ubyte @shared queue_pending     ; 1: a queued blit is going on

    ; the blit to queue, for queue_draw_sprite_rect()
    &ubyte queue_flags_param = $3200
    &ubyte rect_x  = $3201          ; on the screen
    &ubyte rect_y  = $3202
    &ubyte rect_w  = $3203
    &ubyte rect_h  = $3204
    &ubyte rect_gx = $3205          ; in the sprite sheet
    &ubyte rect_gy = $3206
    &ubyte rect_c  = $3207          ; the color of a box, inverted
    &ubyte rect_b  = $3208          ; the sprite slot

    ; Queue a blit of w * h pixels from (src_gx, src_gy) of a sprite slot to
    ; (dst_x, dst_y) of the screen, with color 0 transparent.
    sub queue_draw_sprite(ubyte dst_x, ubyte dst_y, ubyte w, ubyte h, ubyte src_gx, ubyte src_gy, ubyte sprite) {
        rect_x = dst_x
        rect_y = dst_y
        rect_w = w
        rect_h = h
        rect_gx = src_gx
        rect_gy = src_gy
        rect_b = sprite
        queue_draw_sprite_rect()
    }

    ; Queue the sprite blit that is in rect_x, rect_y, rect_w, rect_h, rect_gx,
    ; rect_gy and rect_b (the sprite slot).
    sub queue_draw_sprite_rect() {
        if queue_count >= QUEUE_MAX {
            sys.clear_irqd()
            await_drawing()
        }
        sys.set_irqd()
        if rect_b & SPRITE_OFFSET_X_MASK != 0
            rect_gx |= 128
        if rect_b & SPRITE_OFFSET_Y_MASK != 0
            rect_gy |= 128
        rect_b = (rect_b & BANK_GRAM_MASK) | bankflip | CLIP_MODE_XY
        queue_flags_param = DMA_GCARRY
        pushRect()
        if queue_pending == 0
            next_draw_queue()
        sys.clear_irqd()
    }

    ; Queue a box of w * h pixels in one color, clipped to the screen.
    sub queue_draw_box(ubyte dst_x, ubyte dst_y, ubyte w, ubyte h, ubyte color) {
        if dst_x > 127 or dst_y > 127 or w == 0 or h == 0
            return
        while queue_count >= QUEUE_MAX {
            sys.clear_irqd()
            await_drawing()
        }
        if (dst_x as uword) + w >= 128
            w = 128 - dst_x
        if (dst_y as uword) + h >= 128
            h = 128 - dst_y
        sys.set_irqd()
        rect_x = dst_x
        rect_y = dst_y
        rect_w = w
        rect_h = h
        rect_gx = 0
        rect_gy = 0
        rect_b = bankflip
        rect_c = ~color
        queue_flags_param = DMA_COLORFILL_ENABLE | DMA_OPAQUE
        pushRect()
        if queue_pending == 0
            next_draw_queue()
        sys.clear_irqd()
    }

    ; Queue a frame of a sprite slot at (dst_x, dst_y), flipped or not (a
    ; SPRITE_FLIP_ constant).  The slot needs a frame table: set_sprite_frametable().
    sub queue_draw_sprite_frame(ubyte sprite, ubyte dst_x, ubyte dst_y, ubyte frame, ubyte flip) {
        ubyte fw
        ubyte fh
        while queue_count >= QUEUE_MAX {
            sys.clear_irqd()
            await_drawing()
        }
        sys.set_irqd()
        queue_flags_param = DMA_GCARRY
        sprite_fetch_frame(sprite, frame)
        fw = sprite_temp_frame[FRAME_W]
        fh = sprite_temp_frame[FRAME_H]
        rect_b = (sprite & BANK_GRAM_MASK) | bankflip | CLIP_MODE_XY
        rect_gx = sprite_temp_frame[FRAME_GX]
        if sprite & SPRITE_OFFSET_X_MASK != 0
            rect_gx |= 128
        if flip & SPRITE_FLIP_X != 0 {
            rect_x = dst_x - fw - sprite_temp_frame[FRAME_X] - 1
            rect_gx ^= $ff
            rect_gx -= fw - 1
            rect_w = fw | 128
        } else {
            rect_x = sprite_temp_frame[FRAME_X] + dst_x
            rect_w = fw
        }
        rect_gy = sprite_temp_frame[FRAME_GY]
        if sprite & SPRITE_OFFSET_Y_MASK != 0
            rect_gy |= 128
        if flip & SPRITE_FLIP_Y != 0 {
            rect_y = dst_y - fh - sprite_temp_frame[FRAME_Y] - 1
            rect_gy ^= $ff
            rect_gy -= fh - 1
            rect_h = fh | 128
        } else {
            rect_y = sprite_temp_frame[FRAME_Y] + dst_y
            rect_h = fh
        }
        pushRect()
        if queue_pending == 0
            next_draw_queue()
        sys.clear_irqd()
    }

    ; Queue 4 boxes over the part of the picture that a TV may not show.
    sub queue_clear_border(ubyte color) {
        queue_draw_box(0, 0, SCREEN_WIDTH-BORDER_RIGHT_WIDTH, BORDER_TOP_HEIGHT, color)
        queue_draw_box(0, BORDER_TOP_HEIGHT, BORDER_LEFT_WIDTH, SCREEN_HEIGHT-BORDER_TOP_HEIGHT, color)
        queue_draw_box(BORDER_LEFT_WIDTH, SCREEN_HEIGHT-BORDER_BOTTOM_HEIGHT, SCREEN_WIDTH-BORDER_LEFT_WIDTH, BORDER_BOTTOM_HEIGHT, color)
        queue_draw_box(SCREEN_WIDTH-BORDER_RIGHT_WIDTH, 0, BORDER_RIGHT_WIDTH, SCREEN_HEIGHT-BORDER_BOTTOM_HEIGHT, color)
    }

    ; Queue a box over the picture, without its border.
    sub queue_clear_screen(ubyte color) {
        queue_draw_box(1, 7, SCREEN_WIDTH-2, SCREEN_HEIGHT-15, color)
    }

    ; Wait until everything that is queued is drawn.
    sub await_draw_queue() {
        sys.set_irqd()
        if queue_pending != 0
            await_drawing()
        while queue_end != queue_start {
            next_draw_queue()
            sys.clear_irqd()
            await_drawing()
        }
        dma_flags = flagsMirror | DMA_ENABLE
        BLIT_START = 0
        dma_flags = flagsMirror
        queue_pending = 0
        sys.clear_irqd()
    }

    ; Put rect and queue_flags_param at the end of the queue.
    ; Call with interrupts off.
    asmsub pushRect() clobbers(A,X,Y) {
        %asm {{
            ldy  gametank.queue_end
            inc  gametank.queue_end
            inc  gametank.queue_count
            lda  gametank.banksMirror
            tax                         ; X stays this until ram bank 0 is back: draw_queue_nmi needs it
            ora  #$40
            sta  gametank.BANKREG       ; ram bank 1: no variable, no stack until it is 0 again
pushRect_bank1_first
            lda  gametank.rect_b
            sta  gametank.Q_BankReg,y
            lda  gametank.rect_x
            sta  gametank.Q_VX,y
            lda  gametank.rect_y
            sta  gametank.Q_VY,y
            lda  gametank.rect_gx
            sta  gametank.Q_GX,y
            lda  gametank.rect_gy
            sta  gametank.Q_GY,y
            lda  gametank.rect_w
            sta  gametank.Q_WIDTH,y
            lda  gametank.rect_h
            sta  gametank.Q_HEIGHT,y
            lda  gametank.rect_c
            sta  gametank.Q_Color,y
            lda  gametank.queue_flags_param
            sta  gametank.Q_DMAFlags,y
pushRect_bank1_last
            stx  gametank.BANKREG       ; ram bank 0 again
            rts
        }}
    }

    ; Start the blit at the start of the queue.
    ; Call with interrupts off, and only when the queue is not empty.
    asmsub next_draw_queue() clobbers(A,X,Y) {
        %asm {{
            stz  gametank.BANKREG
            lda  #1
            sta  gametank.queue_pending
            ; the blitter on, to take the values
            lda  gametank.flagsMirror
            ora  #gametank.DMA_ENABLE
            sta  gametank.DMAFLAGS
            ldy  gametank.queue_start
            lda  #$40
            sta  gametank.BANKREG       ; ram bank 1: no variable, no stack until it is 0 again
next_bank1_first
            lda  gametank.Q_VX,y
            sta  gametank.BLIT_VX
            lda  gametank.Q_VY,y
            sta  gametank.BLIT_VY
            lda  gametank.Q_GX,y
            sta  gametank.BLIT_GX
            lda  gametank.Q_GY,y
            sta  gametank.BLIT_GY
            lda  gametank.Q_WIDTH,y
            sta  gametank.BLIT_WIDTH
            lda  gametank.Q_HEIGHT,y
            sta  gametank.BLIT_HEIGHT
            lda  gametank.Q_Color,y
            sta  gametank.BLIT_COLOR
            ldx  gametank.Q_DMAFlags,y
            lda  gametank.Q_BankReg,y
            and  #$3f
next_bank1_last
            sta  gametank.BANKREG       ; ram bank 0 again
            sta  gametank.banksMirror
            txa
            ora  gametank.frameflip
            ora  #gametank.DMA_ENABLE | gametank.DMA_NMI | gametank.DMA_IRQ
            sta  gametank.flagsMirror
            sta  gametank.DMAFLAGS
            inc  gametank.queue_start
            lda  #1
            sta  gametank.draw_busy
            sta  gametank.BLIT_START
            dec  gametank.queue_count
            rts
        }}
    }

    %asm {{
; the queue, in ram bank 1: 256 bytes for each value of a blit
Q_DMAFlags = $0200
Q_VX       = $0300
Q_VY       = $0400
Q_GX       = $0500
Q_GY       = $0600
Q_WIDTH    = $0700
Q_HEIGHT   = $0800
Q_Color    = $0900
Q_BankReg  = $0a00

; The interrupt of the blitter (a blit is done), in place of the one of
; syslib.p8, which jumps here when this module is in the program: start the
; next queued blit, if there is one.
draw_queue_irq
            pha
            phx
            phy
            stz  gametank.BLIT_START
            stz  gametank.queue_pending
            stz  gametank.draw_busy
            stz  gametank.blit_active
            lda  gametank.queue_start
            cmp  gametank.queue_end
            beq  +
            jsr  gametank.next_draw_queue
+           ply
            plx
            pla
            rti

; The vsync interrupt, in place of the one of syslib.p8, which jumps here when
; this module is in the program.  It does the same, also when it interrupts
; pushRect or next_draw_queue while ram bank 1 is there: the address on the
; stack says so.  It goes to ram bank 0 for the variables then, and back; the
; stack (which is the one of ram bank 1 then) is not used in between.
draw_queue_nmi
            pha
            phx
            tsx                 ; $0101,x: X  $0102,x: A  $0103,x: flags  $0104,x: where it interrupted
            ; in pushRect, with ram bank 1?
            lda  $0104,x
            cmp  #<gametank.pushRect.pushRect_bank1_first
            lda  $0105,x
            sbc  #>gametank.pushRect.pushRect_bank1_first
            bcc  _notpush
            lda  #<gametank.pushRect.pushRect_bank1_last
            cmp  $0104,x
            lda  #>gametank.pushRect.pushRect_bank1_last
            sbc  $0105,x
            bcc  _notpush
            lda  $0101,x        ; its X: the banking register's value with ram bank 0
            bra  _bank1
_notpush    ; in next_draw_queue, with ram bank 1?
            lda  $0104,x
            cmp  #<gametank.next_draw_queue.next_bank1_first
            lda  $0105,x
            sbc  #>gametank.next_draw_queue.next_bank1_first
            bcc  _bank0
            lda  #<gametank.next_draw_queue.next_bank1_last
            cmp  $0104,x
            lda  #>gametank.next_draw_queue.next_bank1_last
            sbc  $0105,x
            bcc  _bank0
            lda  #0             ; the banking register is $40 there
_bank1      sta  gametank.BANKREG       ; ram bank 0: no stack until ram bank 1 is back
            stz  gametank.frameflag
            inc  cbm.TIME_LO
            bne  +
            inc  cbm.TIME_MID
            bne  +
            inc  cbm.TIME_HI
+           ora  #$40
            sta  gametank.BANKREG       ; ram bank 1 again
            plx
            pla
            rti
_bank0      stz  gametank.frameflag
            inc  cbm.TIME_LO
            bne  +
            inc  cbm.TIME_MID
            bne  +
            inc  cbm.TIME_HI
+           plx
            pla
            rti

; what the direct_prepare_ routines call when this module is in the program
draw_queue_await
            jmp  gametank.await_draw_queue
    }}
}
