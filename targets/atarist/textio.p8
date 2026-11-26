; Text output and input for the Atari ST (the atarist target of p8p8), through the
; console of GEMDOS, which is a VT-52 terminal: 40 columns and 16 colours in the low
; resolution, 80 columns and 4 colours in the medium one, 80 columns in black and
; white in the high one, 25 lines in all of them.  The mode is what it was when the
; program started (tos.rez).
;
; A colour is a number of the screen's palette.  As the desktop leaves it, 0 is white
; (the background) and the last colour of the mode is black (the text): 15, 3 or 1.
; color() takes any number from 0 to 15 and makes of it what the mode has: a number
; that the mode does not have loses its upper bits, and what is not 0 does not
; become 0 (so text in a colour is never text in the background's colour).

%import conv
%option ignore_unused

txt {
    const ubyte DEFAULT_WIDTH = 80
    const ubyte DEFAULT_HEIGHT = 25

    asmsub chrout(ubyte char @D0) {
        ; -- a character where the cursor is; '\n' starts a new line
        %asm {{
            bra     tos.textout
        }}
    }

    alias chrin = tos.chrin
    alias keypressed = tos.keypressed

    sub nl() {
        chrout('\n')
    }

    sub spc() {
        chrout(' ')
    }

    sub tab() {
        chrout('\t')
    }

    asmsub print(str text @A0) {
        %asm {{
            move.l  a2,-(sp)
            move.l  a0,a2
.loop:
            moveq   #0,d0
            move.b  (a2)+,d0
            beq.s   .done
            bsr     tos.textout
            bra.s   .loop
.done:
            move.l  (sp)+,a2
            rts
        }}
    }

    sub print_ub(ubyte value) {
        print(conv.str_ub(value))
    }

    sub print_ub0(ubyte value) {
        print(conv.str_ub0(value))
    }

    sub print_b(byte value) {
        print(conv.str_b(value))
    }

    sub print_uw(uword value) {
        print(conv.str_uw(value))
    }

    sub print_uw0(uword value) {
        print(conv.str_uw0(value))
    }

    sub print_w(word value) {
        print(conv.str_w(value))
    }

    sub print_l(long value) {
        print(conv.str_l(value))
    }

    sub print_ulhex(long value, bool prefix) {
        if prefix
            chrout('$')
        print(conv.str_ulhex(value))
    }

    sub print_uwhex(uword value, bool prefix) {
        if prefix
            chrout('$')
        print(conv.str_uwhex(value))
    }

    sub print_ubhex(ubyte value, bool prefix) {
        if prefix
            chrout('$')
        print(conv.str_ubhex(value))
    }

    sub print_ubbin(ubyte value, bool prefix) {
        if prefix
            chrout('%')
        print(conv.str_ubbin(value))
    }

    sub print_uwbin(uword value, bool prefix) {
        if prefix
            chrout('%')
        print(conv.str_uwbin(value))
    }

    sub print_bool(bool value) {
        if value
            print("true")
        else
            print("false")
    }

    sub input_chars(str buffer) -> ubyte {
        ; Input a string (max. 80 chars) from the keyboard. Returns length of input.
        ; User entered EOL is trimmed, and the string is terminated with a 0 byte.
        ubyte count
        while count < 80 {
            ubyte ch = tos.chrin()
            if ch == '\n' or ch == 0 {
                buffer[count] = 0
                return count
            }
            if ch == 8 or ch == 127 {
                if count > 0 {
                    count--
                    chrout(8)       ; move cursor back
                    chrout(' ')     ; overwrite with space
                    chrout(8)       ; move cursor back again
                }
            } else if ch >= 32 and ch < 127 {
                chrout(ch)
                buffer[count] = ch
                count++
            }
        }
        buffer[count] = 0
        return count
    }

    sub iso() {
        ; one character set
    }

    sub lowercase() {
        ; one character set
    }

    sub escape(ubyte code) {
        tos.chrout(27)
        tos.chrout(code)
    }

    sub cls() {
        escape('E')
    }

    sub clear_screen() {
        escape('E')
    }

    sub home() {
        escape('H')
    }

    sub rvs() {
        escape('p')
    }

    sub normal() {
        escape('q')
    }

    sub rvs_on() {
        escape('p')
    }

    sub rvs_off() {
        escape('q')
    }

    sub cursor_off() {
        escape('f')
    }

    sub cursor_on() {
        escape('e')
    }

    sub wrap(bool on) {
        ; -- does a line that reaches the right edge go on in the next one (as it does from
        ;    the program's start), or do its characters pile up in the last column
        if on
            escape('v')
        else
            escape('w')
    }

    sub clear_to_eol() {
        escape('K')
    }

    sub colors() -> ubyte {
        ; -- how many colours the screen's mode has: 16, 4 or 2
        when tos.rez {
            0 -> return 16
            1 -> return 4
            else -> return 2
        }
    }

    sub mode_color(ubyte col) -> ubyte {
        ; -- the colour that the mode has for one of the sixteen
        ubyte mask = colors() - 1
        ubyte reduced = col & mask
        if reduced == 0 and col & 15 != 0
            reduced = mask
        return reduced
    }

    sub color(ubyte txtcol) {
        ; -- the colour of the text
        escape('b')
        tos.chrout(32 + mode_color(txtcol))
    }

    sub bgcolor(ubyte bgcol) {
        ; -- the colour behind the text
        escape('c')
        tos.chrout(32 + mode_color(bgcol))
    }

    sub color2(ubyte txtcol, ubyte bgcol) {
        color(txtcol)
        bgcolor(bgcol)
    }

    sub bell() {
        tos.chrout(7)
    }

    sub width() -> ubyte {
        if tos.rez == 0
            return 40
        return 80
    }

    sub height() -> ubyte {
        return 25
    }

    sub size() -> ubyte, ubyte {
        return width(), height()
    }

    sub plot(ubyte col, ubyte row) {
        ; -- the cursor to a column and a row, both from 0
        escape('Y')
        tos.chrout(32 + row)
        tos.chrout(32 + col)
    }

    sub column(ubyte col) {
        ; -- the cursor to a column of its line
        tos.chrout(13)
        repeat col
            escape('C')
    }

    sub setchr(ubyte col, ubyte row, ubyte char) {
        ; -- a character at a place, as the picture that it has in the font; the cursor
        ;    is after it then
        plot(col, row)
        tos.rawout(char)
    }
}
