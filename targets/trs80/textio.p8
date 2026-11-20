; Prog8 definitions for the Text I/O console routines on the TRS-80 Model I and III
; (the trs80 target of p8p8).  The screen is 64 by 16 characters at $3c00; text goes
; straight into it (the target file's console_out), at the address that the ROM keeps
; as its cursor's, $4020.  The keys are the ROM's.  There are no colors, no reverse
; video and no cursor on the screen.

%import shared_z80_textio
%import shared_z80_putchar_textio
%import shared_z80_input_textio

txt {
%option no_symbol_prefixing, ignore_unused

    const ubyte DEFAULT_WIDTH = 64
    const ubyte DEFAULT_HEIGHT = 16

    const ubyte COLUMNS = DEFAULT_WIDTH
    const ubyte ROWS = DEFAULT_HEIGHT

    const uword SCREEN = $3c00          ; the characters of the screen
    &uword cursor = $4020               ; where the ROM writes next: an address in the screen
    &ubyte cursor_shown = $4022         ; not 0 while the ROM shows the cursor (it keeps the character under it here)

    ; the codes of getkey() and waitkey() for the keys that differ between the machines (a key that a machine lacks gets
    ; one that no key gives: 248 up, 249 down, 250 left, 251 right, 252 escape, 253 backspace, 254 break)
    const ubyte KEY_UP = 91
    const ubyte KEY_DOWN = 10
    const ubyte KEY_LEFT = 8            ; also the backspace of line input
    const ubyte KEY_RIGHT = 9
    const ubyte KEY_ENTER = 13
    const ubyte KEY_ESC = 27            ; shift and the up arrow
    const ubyte KEY_BACKSPACE = 253
    const ubyte KEY_BREAK = 1

sub width() -> ubyte {
    return DEFAULT_WIDTH
}

sub height() -> ubyte {
    return DEFAULT_HEIGHT
}

sub clear_screen() {
    ; ---- the ROM's codes: 28 puts the cursor at the top left, 31 clears from there to the end
    chrout(28)
    chrout(31)
}

sub home() {
    chrout(28)
}

sub move_cursor(uword address) {
    ; ---- where the next character goes.  (The program shows no cursor: the target's console
    ;      routine writes into the screen's memory itself, and the ROM's cursor is off.)
    cursor = address
}

sub plot(ubyte col, ubyte row) {
    if col < COLUMNS and row < ROWS
        move_cursor(SCREEN + (row as uword) * DEFAULT_WIDTH + col)
}

sub column(ubyte col) {
    move_cursor((cursor & $ffc0) | col)
}

sub get_cursor() -> ubyte, ubyte {
    ; ---- the cursor's column and row
    return get_column(), get_row()
}

sub cursor_on() {
    ; ---- there is no cursor to show (see move_cursor)
}

sub cursor_off() {
}

sub get_column() -> ubyte {
    return lsb(cursor) & 63
}

sub get_row() -> ubyte {
    return lsb((cursor - SCREEN) >> 6)
}

sub setchr(ubyte col, ubyte row, ubyte char) {
    @(SCREEN + (row as uword) * DEFAULT_WIDTH + col) = char
}

sub getchr(ubyte col, ubyte row) -> ubyte {
    return @(SCREEN + (row as uword) * DEFAULT_WIDTH + col)
}

sub setclr(ubyte col, ubyte row, ubyte color) {
}

sub getclr(ubyte col, ubyte row) -> ubyte {
    return 0
}

sub setcc(ubyte col, ubyte row, ubyte char, ubyte color) {
    setchr(col, row, char)
}

sub color(ubyte txtcol) {
}

sub rvs_on() {
}

sub rvs_off() {
}

sub bell() {
}

sub clear_screenchars(ubyte character) {
    sys.memset(SCREEN, DEFAULT_WIDTH as uword * DEFAULT_HEIGHT, character)
}

sub fill_screen(ubyte character, ubyte color) {
    clear_screenchars(character)
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
