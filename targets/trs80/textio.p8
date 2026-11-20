; Prog8 definitions for the Text I/O console routines on the TRS-80 Model I and III
; (the trs80 target of p8p8).  The screen is 64 by 16 characters at $3c00; text goes
; out through the ROM (the target file's console_out), which keeps the cursor's
; address at $4020.  The keys are the ROM's too.  There are no colors and no reverse
; video.

%import shared_llvm16_textio
%import shared_llvm16_putchar_textio
%import shared_llvm16_input_textio

txt {
%option no_symbol_prefixing, ignore_unused

    const ubyte DEFAULT_WIDTH = 64
    const ubyte DEFAULT_HEIGHT = 16

    const uword SCREEN = $3c00          ; the characters of the screen
    &uword cursor = $4020               ; where the ROM writes next: an address in the screen

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

sub plot(ubyte col, ubyte row) {
    cursor = SCREEN + (row as uword) * DEFAULT_WIDTH + col
}

sub column(ubyte col) {
    cursor = (cursor & $ffc0) | col
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
