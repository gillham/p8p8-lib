; Text output and input for a 68000 Macintosh (the macplus target of p8p8): a window
; of 80 columns and 25 lines in Monaco 9, black on white, that the program opens at
; its start (see macos in syslib).  There are no colours: a Macintosh Plus has a black
; and white screen.  rvs_on() gives white on black.

%import conv
%option ignore_unused

txt {
    const ubyte DEFAULT_WIDTH = 80
    const ubyte DEFAULT_HEIGHT = 25

    alias chrout = macos.chrout
    alias chrin = macos.chrin
    alias keypressed = macos.keypressed

    sub nl() {
        chrout('\n')
    }

    sub spc() {
        chrout(' ')
    }

    sub tab() {
        chrout('\t')
    }

    sub print(str text) {
        ^^ubyte p = text
        while @(p) != 0 {
            macos.chrout(@(p))
            p++
        }
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
            ubyte ch = macos.chrin()
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

    sub cls() {
        macos.cls()
    }

    sub clear_screen() {
        macos.cls()
    }

    sub home() {
        macos.column = 0
        macos.row = 0
    }

    sub rvs() {
        macos.set_reverse(true)
    }

    sub normal() {
        macos.set_reverse(false)
    }

    sub rvs_on() {
        macos.set_reverse(true)
    }

    sub rvs_off() {
        macos.set_reverse(false)
    }

    sub cursor_off() {
        ; (the cursor is there only while chrin() waits)
    }

    sub cursor_on() {
    }

    sub clear_to_eol() {
        macos.clear_to_eol()
    }

    sub colors() -> ubyte {
        ; -- how many colours the screen has
        return 2
    }

    sub color(ubyte txtcol) {
        ; (black and white)
    }

    sub bgcolor(ubyte bgcol) {
    }

    sub color2(ubyte txtcol, ubyte bgcol) {
    }

    sub bell() {
        macos.beep()
    }

    sub width() -> ubyte {
        return macos.COLUMNS
    }

    sub height() -> ubyte {
        return macos.ROWS
    }

    sub size() -> ubyte, ubyte {
        return macos.COLUMNS, macos.ROWS
    }

    sub plot(ubyte col, ubyte row) {
        ; -- the cursor to a column and a row, both from 0
        if col < macos.COLUMNS
            macos.column = col
        if row < macos.ROWS
            macos.row = row
    }

    sub column(ubyte col) {
        ; -- the cursor to a column of its line
        if col < macos.COLUMNS
            macos.column = col
    }

    sub get_column() -> ubyte {
        return macos.column
    }

    sub get_row() -> ubyte {
        return macos.row
    }

    sub setchr(ubyte col, ubyte row, ubyte char) {
        ; -- a character at a place; the cursor stays where it is
        macos.set_cell(col, row, char)
    }

    sub setclr(ubyte col, ubyte row, ubyte color) {
        ; -- the colour of a place: there are none here (as on the PET: for programs
        ;    that are written for machines with colours too)
    }

    sub getclr(ubyte col, ubyte row) -> ubyte {
        ; -- the colour of a place: always 1
        return 1
    }

    sub setcc(ubyte col, ubyte row, ubyte char, ubyte charcolor) {
        ; -- a character at a place; the colour is not used
        macos.set_cell(col, row, char)
    }

    sub getchr(ubyte col, ubyte row) -> ubyte {
        ; -- the character that is at a place
        return macos.screen[(row as uword) * macos.COLUMNS + col]
    }
}
