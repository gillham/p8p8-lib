; Prog8 definitions for the Text I/O console routines of the coco3 target of p8p8: the
; Color Computer 3's text screens.  Text goes straight into the screen's memory (the
; target file's console_out), on whichever screen is on:
;
; - the 40 and the 80 column screen (BASIC's WIDTH 40 and WIDTH 80, or set_width()
;   here), of 24 lines, with small letters and with an attribute for each character:
;   color() sets the one of the characters that follow.  The screen is a block of
;   memory that is not among the 64 KB a program sees: the routines here put it at
;   $e000 for as long as they read or write it, with interrupts off.
; - the 32 column screen of the Color Computer 2 (WIDTH 32), of 16 lines, where small
;   letters show as inverse capitals and there are no colors.
;
; The cursor is BASIC's own, so BASIC goes on where the program stopped.  The keys
; are the ROM's.  The ROM routines that set_width() calls are the Color Computer 3's
; (its Super Extended Color BASIC of 1986; the PAL ROM has them at the same places).

%import shared_m6809_textio
%import shared_m6809_echo_input_textio

txt {
%option no_symbol_prefixing, ignore_unused

    const uword SCREEN = $0400          ; the 32 column screen
    const uword WIDE_SCREEN = $e000     ; the 40 and 80 column screen, while it is mapped in
    const ubyte DEFAULT_WIDTH = 80      ; the largest screen (a program's arrays for a screen go by these)
    const ubyte DEFAULT_HEIGHT = 24
    const ubyte NARROW_WIDTH = 32       ; the 32 column screen
    const ubyte NARROW_HEIGHT = 16

    &uword cursor = $0088               ; BASIC's cursor on the 32 column screen: where the next character goes
    &ubyte wide = $00e7                 ; BASIC's WIDTH: 0 the 32 column screen, 1 the 40 column one, 2 the 80 column one
    &uword wide_cursor = $fe00          ; BASIC's cursor on the 40 and 80 column screen, as BASIC has the screen at $2000
    &ubyte wide_column = $fe02
    &ubyte wide_row = $fe03
    &ubyte wide_columns = $fe04
    &ubyte wide_rows = $fe05
    &ubyte attribute = $fe08            ; of the characters that are written: see color()

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
    ubyte @shared kept_flags

sub chrout(ubyte char) {
    %ir {{
        loadm.b r99100.b,[txt.chrout.char]
        syscall 2 (r99100.b)
    }}
    ; on the 32 column screen it stands just before the cursor now; inverse is bit 6 clear
    if wide == 0 and inverse_mode != 0 and char >= 32 and char < 128
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

sub set_width(ubyte columns) {
    ; ---- BASIC's WIDTH: 32, 40 or 80 columns.  The screen is cleared.  Another number does nothing.
    when columns {
        32 -> {
            %asm {{
                jsr  $f652
            }}
        }
        40 -> {
            %asm {{
                jsr  $f65c
            }}
        }
        80 -> {
            %asm {{
                jsr  $f679
            }}
        }
    }
}

sub screen_on() {
    ; ---- the 40 and 80 column screen at $e000, and no interrupts until screen_off()
    %asm {{
        tfr  cc,a
        sta  _txt__kept_flags
        orcc  #$50
        lda  #$36
        sta  $ffa7
    }}
}

sub screen_off() {
    %asm {{
        lda  #$3f
        sta  $ffa7
        lda  _txt__kept_flags
        tfr  a,cc
    }}
}

sub width() -> ubyte {
    if wide == 0
        return NARROW_WIDTH
    return wide_columns
}

sub height() -> ubyte {
    if wide == 0
        return NARROW_HEIGHT
    return wide_rows
}

sub  clear_screen() {
    if wide == 0 {
        sys.memset(SCREEN, NARROW_WIDTH as uword * NARROW_HEIGHT, $60)
        home()
    }
    else
        chrout(12)
}

sub home() {
    plot(0, 0)
}

sub column(ubyte col) {
    ; ---- move the cursor to the column (0 is the leftmost one) of the current line
    if wide == 0 {
        if col < NARROW_WIDTH
            cursor = (cursor & $ffe0) + col
    }
    else
        plot(col, wide_row)
}

sub get_column() -> ubyte {
    if wide == 0
        return lsb(cursor) & 31
    return wide_column
}

sub get_row() -> ubyte {
    if wide == 0
        return lsb((cursor - SCREEN) >> 5)
    return wide_row
}

sub  plot  (ubyte col, ubyte row) {
    ; ---- move the cursor to the position, 0,0 is the top left; a position off the screen is ignored
    if wide == 0 {
        if col < NARROW_WIDTH and row < NARROW_HEIGHT
            cursor = SCREEN + row * (NARROW_WIDTH as uword) + col
        return
    }
    if col < wide_columns and row < wide_rows {
        wide_column = col
        wide_row = row
        wide_cursor = $2000 + (row * (wide_columns as uword) + col) * 2
    }
}

sub rvs_on() {
    ; ---- inverse characters: on the 40 and 80 column screen the two colors of the attribute change places
    if inverse_mode == 0
        swap_colors()
    inverse_mode = 128
}

sub rvs_off() {
    if inverse_mode != 0
        swap_colors()
    inverse_mode = 0
}

sub swap_colors() {
    if wide != 0
        attribute = (attribute & $c0) | ((attribute & 7) << 3) | ((attribute >> 3) & 7)
}

sub color (ubyte txtcol) {
    ; ---- the color of the characters that follow, on the 40 and 80 column screen: one of the
    ;      eight foreground colors (0 to 7: palette registers 8 to 15)
    if wide != 0
        attribute = (attribute & $c7) | ((txtcol & 7) << 3)
}

sub background (ubyte backcol) {
    ; ---- the background of the characters that follow, on the 40 and 80 column screen (0 to 7:
    ;      palette registers 0 to 7)
    if wide != 0
        attribute = (attribute & $f8) | (backcol & 7)
}

sub bell() {
}

sub setchr (ubyte col, ubyte row, ubyte char) {
    ; ---- put the character on the screen at the position, with the attribute of now. The cursor stays where it was.
    ;      (On the 32 column screen: not inverse, but small letters show as inverse capitals; 0-31 show as 64-95,
    ;      128-255 are the graphics blocks.)
    if wide != 0 {
        if col < wide_columns and row < wide_rows {
            pointer cell = WIDE_SCREEN + (row * (wide_columns as uword) + col) * 2
            ubyte shade = attribute
            screen_on()
            @(cell) = char
            @(cell + 1) = shade
            screen_off()
        }
        return
    }
    if col >= NARROW_WIDTH or row >= NARROW_HEIGHT
        return
    if char < 64
        char += 64
    else if char >= 96 and char < 128
        char -= 96
    @(SCREEN + row * (NARROW_WIDTH as uword) + col) = char
}

sub getchr (ubyte col, ubyte row) -> ubyte {
    ; ---- the character on the screen at the position; 255 off the screen.
    ;      (On the 32 column screen: inverse letters give small letters, other inverse characters the normal one.)
    ubyte char
    if wide != 0 {
        if col >= wide_columns or row >= wide_rows
            return 255
        pointer spot = WIDE_SCREEN + (row * (wide_columns as uword) + col) * 2
        screen_on()
        char = @(spot)
        screen_off()
        return char
    }
    if col >= NARROW_WIDTH or row >= NARROW_HEIGHT
        return 255
    char = @(SCREEN + row * (NARROW_WIDTH as uword) + col)
    if char >= 128 or char >= 64 and char < 96
        return char
    if char >= 96
        return char - 64
    if char < 32
        return char + 96
    return char
}

sub setclr (ubyte col, ubyte row, ubyte charcol) {
    ; ---- the foreground color (0 to 7) of the character at the position, on the 40 and 80 column screen
    if wide != 0 and col < wide_columns and row < wide_rows {
        pointer spot = WIDE_SCREEN + (row * (wide_columns as uword) + col) * 2 + 1
        ubyte shade
        screen_on()
        shade = @(spot)
        @(spot) = (shade & $c7) | ((charcol & 7) << 3)
        screen_off()
    }
}

sub setcc(ubyte col, ubyte row, ubyte char, ubyte charcol) {
    ; ---- setchr() and setclr() in one
    setchr(col, row, char)
    setclr(col, row, charcol)
}

sub clear_screenchars(ubyte character) {
    ; ---- fill the screen with the character, and put the cursor at the top left
    if wide != 0 {
        ubyte row
        ubyte col
        for row in 0 to wide_rows - 1 {
            for col in 0 to wide_columns - 1
                setchr(col, row, character)
        }
        home()
        return
    }
    setchr(0, 0, character)
    sys.memset(SCREEN, NARROW_WIDTH as uword * NARROW_HEIGHT, @(SCREEN))
    home()
}

sub fill_screen(ubyte character, ubyte charcol) {
    ; ---- clear_screenchars() with the color for what follows
    color(charcol)
    clear_screenchars(character)
}
}
