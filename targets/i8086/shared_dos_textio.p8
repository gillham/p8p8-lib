; Prog8 definitions for the Text I/O console routines of MS-DOS (the dos and dosexe targets of p8p8).
;
; What is printed goes through the target file's routine: to the screen through the BIOS,
; in the text colours set here, or through DOS when the program's output is redirected.
; The cursor, the colours and the cells of the screen are the BIOS's video functions
; (int $10), which every display adapter has, in whatever text mode the screen is.  The
; keys come from the BIOS's keyboard functions.

%import shared_i8086_textio
%import shared_i8086_putchar_textio
%import shared_i8086_echo_input_textio

txt {
%option no_symbol_prefixing, ignore_unused

    const ubyte DEFAULT_WIDTH = 80
    const ubyte DEFAULT_HEIGHT = 25

    ; the codes of getkey() and waitkey() for the keys that differ between the machines.  A key without a character is 128
    ; plus its scan code: the function keys F1 to F10 are 187 to 196.
    const ubyte KEY_UP = 200
    const ubyte KEY_DOWN = 208
    const ubyte KEY_LEFT = 203
    const ubyte KEY_RIGHT = 205
    const ubyte KEY_HOME = 199
    const ubyte KEY_END = 207
    const ubyte KEY_PAGEUP = 201
    const ubyte KEY_PAGEDOWN = 209
    const ubyte KEY_INSERT = 210
    const ubyte KEY_DELETE = 211
    const ubyte KEY_F1 = 187
    const ubyte KEY_ENTER = 13
    const ubyte KEY_ESC = 27
    const ubyte KEY_BACKSPACE = 8
    const ubyte KEY_BREAK = 3           ; Ctrl-C

    ; the 16 colours of the text screen, for color(), color2(), setclr() and setcc(); a background is one of the first 8
    const ubyte BLACK = 0
    const ubyte BLUE = 1
    const ubyte GREEN = 2
    const ubyte CYAN = 3
    const ubyte RED = 4
    const ubyte MAGENTA = 5
    const ubyte BROWN = 6
    const ubyte LIGHT_GRAY = 7
    const ubyte DARK_GRAY = 8
    const ubyte LIGHT_BLUE = 9
    const ubyte LIGHT_GREEN = 10
    const ubyte LIGHT_CYAN = 11
    const ubyte LIGHT_RED = 12
    const ubyte LIGHT_MAGENTA = 13
    const ubyte YELLOW = 14
    const ubyte WHITE = 15

    bool reversed = false

asmsub last_cell() -> ubyte @DL, ubyte @DH {
    ; ---- the last column and the last row of the screen (79 and 24 mostly).  The rows are the EGA's and VGA's to tell;
    ;      an older adapter has 25.
    %asm {{
        push  es
        push  bp
        mov  ax, 0x1130
        xor  bh, bh
        mov  dl, 24
        int  0x10
        pop  bp
        pop  es
        mov  dh, dl
        push  dx
        mov  ah, 0x0f
        int  0x10
        pop  dx
        mov  dl, ah
        dec  dl
        ret
    }}
}

sub width() -> ubyte {
    ubyte col, row
    col, row = last_cell()
    return col + 1
}

sub height() -> ubyte {
    ubyte col, row
    col, row = last_cell()
    return row + 1
}

asmsub clear_window(ubyte lastcol @DL, ubyte lastrow @DH) {
    ; ---- blanks in the text colours from the top left to that cell
    %asm {{
        xor  cx, cx
        mov  bh, [p8dos_attr]
        mov  ax, 0x0600
        int  0x10
        ret
    }}
}

sub clear_screen() {
    ; ---- clear the screen in the text colours and move the cursor to the top left
    ubyte col, row
    col, row = last_cell()
    clear_window(col, row)
    plot(0, 0)
}

sub home() {
    plot(0, 0)
}

asmsub plot(ubyte col @DL, ubyte row @DH) {
    ; ---- move the cursor to the column and row (0, 0 is the top left)
    %asm {{
        mov  ah, 2
        xor  bh, bh
        int  0x10
        ret
    }}
}

asmsub get_cursor() -> ubyte @DL, ubyte @DH {
    ; ---- the cursor's column and row
    %asm {{
        mov  ah, 3
        xor  bh, bh
        int  0x10
        ret
    }}
}

sub get_column() -> ubyte {
    ubyte col, row
    col, row = get_cursor()
    return col
}

sub get_row() -> ubyte {
    ubyte col, row
    col, row = get_cursor()
    return row
}

sub column(ubyte col) {
    ; ---- move the cursor to the column (0 is the leftmost one) of the current line
    plot(col, get_row())
}

asmsub cursor_on() {
    ; ---- show the cursor: the two lowest lines of a character's cell
    %asm {{
        mov  ah, 1
        mov  cx, 0x0607
        int  0x10
        ret
    }}
}

asmsub cursor_off() {
    %asm {{
        mov  ah, 1
        mov  cx, 0x2000
        int  0x10
        ret
    }}
}

asmsub setchr(ubyte col @DL, ubyte row @DH, ubyte char @AL) {
    ; ---- put a character on the screen, in the colours that the cell has.  The cursor stays where it is.
    %asm {{
        mov  di, ax
        mov  si, dx
        mov  ah, 3
        xor  bh, bh
        int  0x10
        xchg  dx, si
        mov  ah, 2
        int  0x10
        mov  ax, di
        mov  ah, 0x0a
        xor  bh, bh
        mov  cx, 1
        int  0x10
        mov  dx, si
        mov  ah, 2
        int  0x10
        ret
    }}
}

asmsub setcc(ubyte col @DL, ubyte row @DH, ubyte char @AL, ubyte charcolor @BL) {
    ; ---- put a character with its colours (the foreground in the low four bits, the background above) on the screen
    %asm {{
        mov  di, ax
        mov  si, dx
        push  bx
        mov  ah, 3
        xor  bh, bh
        int  0x10
        xchg  dx, si
        mov  ah, 2
        int  0x10
        pop  bx
        mov  ax, di
        mov  ah, 9
        xor  bh, bh
        mov  cx, 1
        int  0x10
        mov  dx, si
        mov  ah, 2
        int  0x10
        ret
    }}
}

asmsub getcc(ubyte col @DL, ubyte row @DH) -> ubyte @AL, ubyte @AH {
    ; ---- the character and the colours of a cell of the screen
    %asm {{
        mov  si, dx
        mov  ah, 3
        xor  bh, bh
        int  0x10
        xchg  dx, si
        mov  ah, 2
        int  0x10
        mov  ah, 8
        int  0x10
        mov  di, ax
        mov  dx, si
        mov  ah, 2
        int  0x10
        mov  ax, di
        ret
    }}
}

sub getchr(ubyte col, ubyte row) -> ubyte {
    ubyte char, colors
    char, colors = getcc(col, row)
    return char
}

sub getclr(ubyte col, ubyte row) -> ubyte {
    ubyte char, colors
    char, colors = getcc(col, row)
    return colors
}

sub setclr(ubyte col, ubyte row, ubyte charcolor) {
    ; ---- give a cell of the screen other colours; its character stays
    setcc(col, row, getchr(col, row), charcolor)
}

asmsub attribute() -> ubyte @AL {
    ; ---- the colours that text is printed in: the foreground in the low four bits, the background above
    %asm {{
        mov  al, [p8dos_attr]
        ret
    }}
}

asmsub set_attribute(ubyte colors @AL) {
    %asm {{
        mov  [p8dos_attr], al
        ret
    }}
}

sub color(ubyte txtcol) {
    ; ---- the colour of the text that is printed from now on, 0-15
    set_attribute((attribute() & $f0) | (txtcol & 15))
}

sub color2(ubyte txtcol, ubyte bgcol) {
    ; ---- the colours of the text and of its background (0-7)
    set_attribute((bgcol & 7) << 4 | (txtcol & 15))
}

sub rvs_on() {
    ; ---- text and background change places
    if not reversed {
        reversed = true
        ubyte colors = attribute()
        set_attribute((colors & 7) << 4 | (colors >> 4) & 7)
    }
}

sub rvs_off() {
    if reversed {
        reversed = false
        ubyte colors = attribute()
        set_attribute((colors & 7) << 4 | (colors >> 4) & 7)
    }
}

sub bell() {
    chrout(7)
}

asmsub fill_cells(ubyte char @AL, ubyte charcolor @BL, uword count @CX) {
    ; ---- so many cells from the cursor on get the character and the colours; the cursor stays
    %asm {{
        mov  ah, 9
        xor  bh, bh
        int  0x10
        ret
    }}
}

asmsub fill_chars(ubyte char @AL, uword count @CX) {
    ; ---- so many cells from the cursor on get the character and keep their colours; the cursor stays
    %asm {{
        mov  ah, 0x0a
        xor  bh, bh
        int  0x10
        ret
    }}
}

sub clear_screenchars(ubyte character) {
    ; ---- fill the screen with a character; the colours stay
    ubyte col, row
    ubyte lastcol, lastrow
    col, row = get_cursor()
    lastcol, lastrow = last_cell()
    plot(0, 0)
    fill_chars(character, (lastcol as uword + 1) * (lastrow + 1))
    plot(col, row)
}

sub fill_screen(ubyte character, ubyte charcolor) {
    ; ---- fill the screen with a character in the given colours
    ubyte col, row
    ubyte lastcol, lastrow
    col, row = get_cursor()
    lastcol, lastrow = last_cell()
    plot(0, 0)
    fill_cells(character, charcolor, (lastcol as uword + 1) * (lastrow + 1))
    plot(col, row)
}

asmsub scroll_window(ubyte lastcol @DL, ubyte lastrow @DH, ubyte function @AH) {
    %asm {{
        xor  cx, cx
        mov  bh, [p8dos_attr]
        mov  al, 1
        int  0x10
        ret
    }}
}

sub scroll_up() {
    ; ---- the screen's text one line up; the last line is blank, in the text colours
    ubyte col, row
    col, row = last_cell()
    scroll_window(col, row, 6)
}

sub scroll_down() {
    ubyte col, row
    col, row = last_cell()
    scroll_window(col, row, 7)
}

sub getkey() -> ubyte {
    ; ---- the key pressed, or 0 when there is none, without waiting
    %ir {{
        syscall 217 (): r99100.b
        returnr.b r99100.b
    }}
}

sub waitkey() -> ubyte {
    ; ---- wait for the next key and return it; it is not shown
    %ir {{
        syscall 218 (): r99100.b
        returnr.b r99100.b
    }}
}
}
