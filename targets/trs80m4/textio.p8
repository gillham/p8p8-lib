; Prog8 definitions for the Text I/O console routines on the TRS-80 Model 4 in its own
; mode (the trs80m4 target of p8p8), with TRSDOS 6 or LS-DOS 6.  The screen is 80 by 24.
; Text goes out through the DOS (the target file's console_out); the cursor and single
; characters on the screen go through the supervisor call @VDCTL (15), in Z80 assembly.
; There are no colors; reverse video is the DOS's codes 16 and 17.

%import shared_z80_textio
%import shared_z80_putchar_textio
%import shared_z80_input_textio

txt {
%option no_symbol_prefixing, ignore_unused

    const ubyte DEFAULT_WIDTH = 80
    const ubyte DEFAULT_HEIGHT = 24

    ; the codes of getkey() and waitkey() for the keys that differ between the machines (a key that a machine lacks gets
    ; one that no key gives: 248 up, 249 down, 250 left, 251 right, 252 escape, 253 backspace, 254 break)
    const ubyte KEY_UP = 11
    const ubyte KEY_DOWN = 10
    const ubyte KEY_LEFT = 8            ; also the backspace of line input
    const ubyte KEY_RIGHT = 9
    const ubyte KEY_ENTER = 13
    const ubyte KEY_ESC = 27            ; shift and the up arrow
    const ubyte KEY_BACKSPACE = 253
    const ubyte KEY_BREAK = 128

sub width() -> ubyte {
    return DEFAULT_WIDTH
}

sub height() -> ubyte {
    return DEFAULT_HEIGHT
}

sub clear_screen() {
    ; ---- the DOS's codes: 28 puts the cursor at the top left, 31 clears from there to the end
    chrout(28)
    chrout(31)
}

sub home() {
    chrout(28)
}

sub plot(ubyte col, ubyte row) {
    ; ---- moves the cursor (@VDCTL 3, the row in H and the column in L)
    %asm {{
        ld  a,(_txt_plot_row)
        ld  h,a
        ld  a,(_txt_plot_col)
        ld  l,a
        ld  b,3
        ld  a,15
        rst  $28
    }}
}

sub get_row() -> ubyte {
    ; ---- the cursor's row (@VDCTL 4 gives the row in H and the column in L)
    ubyte @shared found
    %asm {{
        ld  b,4
        ld  a,15
        rst  $28
        ld  a,h
        ld  (_txt_get_row_found),a
    }}
    return found
}

sub get_column() -> ubyte {
    ubyte @shared found
    %asm {{
        ld  b,4
        ld  a,15
        rst  $28
        ld  a,l
        ld  (_txt_get_column_found),a
    }}
    return found
}

sub column(ubyte col) {
    plot(col, get_row())
}

sub setchr(ubyte col, ubyte row, ubyte char) {
    ; ---- puts a character on the screen; the cursor stays (@VDCTL 2, the character in C)
    %asm {{
        ld  a,(_txt_setchr_row)
        ld  h,a
        ld  a,(_txt_setchr_col)
        ld  l,a
        ld  a,(_txt_setchr_char)
        ld  c,a
        ld  b,2
        ld  a,15
        rst  $28
    }}
}

sub getchr(ubyte col, ubyte row) -> ubyte {
    ; ---- the character on the screen (@VDCTL 1)
    ubyte @shared found
    %asm {{
        ld  a,(_txt_getchr_row)
        ld  h,a
        ld  a,(_txt_getchr_col)
        ld  l,a
        ld  b,1
        ld  a,15
        rst  $28
        ld  (_txt_getchr_found),a
    }}
    return found
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
    chrout(16)
}

sub rvs_off() {
    chrout(17)
}

sub bell() {
    ; ---- a short beep (@SOUND 104, B = the duration in bits 3-7 and the tone in bits 0-2)
    %asm {{
        ld  b,$23
        ld  a,104
        rst  $28
    }}
}

sub clear_screenchars(ubyte character) {
    ubyte row
    ubyte col
    for row in 0 to DEFAULT_HEIGHT - 1 {
        for col in 0 to DEFAULT_WIDTH - 1
            setchr(col, row, character)
    }
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
