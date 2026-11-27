; Text with the GameTank SDK's 8 * 8 font, drawn by the blitter.
;
; Prog8 version of the GameTank SDK's src/gt/feature/text/text.c, with the
; names of the C SDK.  (txt, of textio, is the other way to print: a 5 * 6 font
; that the cpu draws into the framebuffer.)
;
;   gametank.text_init()
;   void gametank.text_load_font()          ; once: the font takes a sprite slot
;   ...
;   gametank.text_cursor_x = 8
;   gametank.text_cursor_y = 16
;   gametank.text_color = gametank.TEXT_COLOR_WHITE
;   gametank.text_print_string("hello\nworld")
;
; The font is a sprite sheet of 16 * 16 characters: the character codes 0-127
; in black in its upper half, and the same in white below.  Color 0 is not
; drawn, so text goes on top of what is there.  A line that gets longer than
; text_print_width goes on on the next one.
;
; Different from the C SDK: "\n" is a new line here (to text_print_line_start,
; and a line down).  In C "\n" only goes a line down and "\r" only to the start
; of the line; in Prog8 both are character 13.  Character 10 ("\x0a") still
; only goes a line down.
;
; bios8.gtg.deflate is the font of the GameTank SDK: see NOTICE.md.

%import gametank
%import gametank_draw
%import gametank_sprites

gametank {
%option merge

    const ubyte TEXT_COLOR_BLACK = 0
    const ubyte TEXT_COLOR_WHITE = 128

    const ubyte TEXT_CHAR_WIDTH = 8
    const ubyte TEXT_CHAR_HEIGHT = 8

    ubyte font_slot
    ubyte text_cursor_x
    ubyte text_cursor_y
    ubyte text_print_width
    ubyte text_print_line_start
    ubyte text_color
    ubyte font_offset_x
    ubyte font_offset_y

    sub text_init() {
        text_cursor_x = 0
        text_cursor_y = 0
        text_print_width = 128
        text_print_line_start = 0
        text_color = TEXT_COLOR_BLACK
    }

    ; Load the SDK's font into a free sprite slot, and print with it.
    ; Returns the slot, or SPRITE_SLOT_NONE when sprite ram is full.
    sub text_load_font() -> ubyte {
        text_set_font(allocate_sprite(&assets.bios8, 255))
        return font_slot
    }

    ; Print with the font that is in a sprite slot: a sheet in the layout of
    ; the SDK's font, that the program loaded itself.
    sub text_set_font(ubyte slot) {
        font_slot = slot
        font_offset_x = (slot & SPRITE_OFFSET_X_MASK) << 4
        font_offset_y = (slot & SPRITE_OFFSET_Y_MASK) << 3
    }

    ; Print a string at the cursor.  Waits for drawing that is going on first
    ; (the C SDK's does not), and for each of its own characters.
    sub text_print_string(str text) {
        ubyte ch
        await_draw_queue_if_any()
        await_drawing()
        dma_flags = (flagsMirror | DMA_GCARRY) & ~(DMA_COLORFILL_ENABLE | DMA_OPAQUE)
        banksMirror = bankflip | (font_slot & BANK_GRAM_MASK)
        bank_reg = banksMirror
        BLIT_WIDTH = TEXT_CHAR_WIDTH
        BLIT_HEIGHT = TEXT_CHAR_HEIGHT
        BLIT_VY = text_cursor_y
        repeat {
            ch = @(text)
            if ch == 0
                break
            text++
            when ch {
                ' ' -> text_cursor_x += TEXT_CHAR_WIDTH
                '\n' -> {
                    ; a new line (13, which is "\r" too in Prog8)
                    text_cursor_x = text_print_line_start
                    text_cursor_y += TEXT_CHAR_HEIGHT
                    BLIT_VY = text_cursor_y
                }
                10 -> {
                    ; only a line down
                    text_cursor_y += TEXT_CHAR_HEIGHT
                    BLIT_VY = text_cursor_y
                }
                else -> {
                    ch += text_color
                    if text_cursor_x >= text_print_width + text_print_line_start {
                        text_cursor_x -= text_print_width
                        text_cursor_y += TEXT_CHAR_HEIGHT
                        BLIT_VY = text_cursor_y
                    }
                    BLIT_VX = text_cursor_x
                    BLIT_GX = ((ch & $0f) << 3) | font_offset_x
                    BLIT_GY = ((ch & $f0) >> 1) | font_offset_y
                    BLIT_START = 1
                    text_cursor_x += TEXT_CHAR_WIDTH
                    wait()
                }
            }
        }
    }

    ; Write a number of 0-99 as two digits at s (no 0 after them).
    ; Nothing is written for a bigger number.
    sub text_sprint_num(uword s, ubyte num) {
        if num > 99
            return
        s[0] = num / 10 + '0'
        s[1] = num % 10 + '0'
    }
}

assets {
%option merge
bios8:
    %asmbinary "bios8.gtg.deflate"
}
