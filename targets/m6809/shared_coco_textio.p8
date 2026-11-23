; Prog8 definitions for the Text I/O console routines on the Color Computer's 32x16 text
; screen at $0400 (the CoCo 1 and 2, and the CoCo 3 in its 32 column mode): the coco2 and
; coco3 targets of p8p8.  Text goes straight into the screen's memory (the target file's
; console_out), at the address that Color BASIC keeps as its cursor's, so that BASIC goes
; on where the program stopped.  The keys are the ROM's.
; The screen has no lower case: like BASIC, it shows lower case letters as inverse upper
; case.  It has no per-character colors.

%import shared_m6809_textio
%import shared_m6809_echo_input_textio

txt {
%option no_symbol_prefixing, ignore_unused

    const uword SCREEN = $0400
    &uword cursor = $0088           ; Color BASIC's cursor: the screen address where the next character goes
    const ubyte DEFAULT_WIDTH = 32
    const ubyte DEFAULT_HEIGHT = 16
    const ubyte COLUMNS = DEFAULT_WIDTH
    const ubyte ROWS = DEFAULT_HEIGHT

    ; the codes of getkey() and waitkey() for the keys that differ between the machines (a key that a machine lacks gets
    ; one that no key gives: 248 up, 249 down, 250 left, 251 right, 252 escape, 253 backspace, 254 break)
    const ubyte KEY_UP = 94
    const ubyte KEY_DOWN = 10
    const ubyte KEY_LEFT = 8            ; also the backspace of line input
    const ubyte KEY_RIGHT = 9
    const ubyte KEY_ENTER = 13
    const ubyte KEY_ESC = 252
    const ubyte KEY_BACKSPACE = 253
    const ubyte KEY_BREAK = 3

    ; 128 = print inverse characters, 0 = normal
    ubyte inverse_mode = 0

sub chrout(ubyte char) {
    %ir {{
        loadm.b r99100.b,[txt.chrout.char]
        syscall 2 (r99100.b)
    }}
    ; it stands just before the cursor now; inverse is bit 6 clear
    if inverse_mode != 0 and char >= 32 and char < 128
        @(cursor - 1) &= $bf
}

sub  print (str text) {
    pointer p = text
    while @(p) != 0 {
        chrout(@(p))
        p++
    }
}

sub getkey() -> ubyte {
    ; ---- the key pressed, or 0 when there is none, without waiting; each key press is reported once.
    ;      chrin() reads the keyboard the same way, so a key goes to whichever of them reads first.
    %ir {{
        syscall 217 (): r99100.b
        returnr.b r99100.b
    }}
}

sub waitkey() -> ubyte {
    ; ---- wait for a key and return it; it is not shown
    %ir {{
        syscall 218 (): r99100.b
        returnr.b r99100.b
    }}
}

sub width() -> ubyte {
    return COLUMNS
}

sub height() -> ubyte {
    return ROWS
}

sub  clear_screen() {
    sys.memset(SCREEN, COLUMNS as uword * ROWS, $60)
    home()
}

sub home() {
    cursor = SCREEN
}

sub column(ubyte col) {
    ; ---- move the cursor to the column (0 is the leftmost one) of the current line
    if col < COLUMNS
        cursor = (cursor & $ffe0) + col
}

sub get_column() -> ubyte {
    return lsb(cursor) & 31
}

sub get_row() -> ubyte {
    return lsb((cursor - SCREEN) >> 5)
}

sub  plot  (ubyte col, ubyte row) {
    ; ---- move the cursor to the position, 0,0 is the top left; a position off the screen is ignored
    if col < COLUMNS and row < ROWS
        cursor = SCREEN + row * (COLUMNS as uword) + col
}

sub rvs_on() {
    inverse_mode = 128
}

sub rvs_off() {
    inverse_mode = 0
}

sub color (ubyte txtcol) {
    ; the text screen has no per-character colors
}

sub bell() {
}

sub setchr (ubyte col, ubyte row, ubyte char) {
    ; ---- put the character on the screen at the position, not inverse (but lower case shows as inverse upper case);
    ;      0-31 show as 64-95, 128-255 are the graphics blocks. The cursor stays where it was.
    if col >= COLUMNS or row >= ROWS
        return
    if char < 64
        char += 64
    else if char >= 96 and char < 128
        char -= 96
    @(SCREEN + row * (COLUMNS as uword) + col) = char
}

sub getchr (ubyte col, ubyte row) -> ubyte {
    ; ---- the character on the screen at the position, the one setchr() puts there for 32-255; 255 off the screen.
    ;      Inverse letters (and lower case) give lower case, other inverse characters the normal one.
    if col >= COLUMNS or row >= ROWS
        return 255
    ubyte char = @(SCREEN + row * (COLUMNS as uword) + col)
    if char >= 128 or char >= 64 and char < 96
        return char
    if char >= 96
        return char - 64
    if char < 32
        return char + 96
    return char
}

sub setclr (ubyte col, ubyte row, ubyte color) {
    ; the text screen has no per-character colors
}

sub setcc(ubyte col, ubyte row, ubyte char, ubyte color) {
    ; ---- setchr(), as there are no per-character colors
    setchr(col, row, char)
}

sub clear_screenchars(ubyte character) {
    ; ---- fill the screen with the character, and put the cursor at the top left
    setchr(0, 0, character)
    sys.memset(SCREEN, COLUMNS as uword * ROWS, @(SCREEN))
    home()
}

sub fill_screen(ubyte character, ubyte color) {
    ; ---- clear_screenchars(), as there are no per-character colors
    clear_screenchars(character)
}
}
