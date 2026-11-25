; Prog8 definitions for the Text I/O and Screen routines for the Apple II
; Characters are ASCII (the iso encoding).  On the screen the high bit is set for
; normal text: $80-$ff normal, $00-$3f inverse, $40-$7f flashing (on a IIe with the
; alternate character set: inverse lower case and MouseText).
; The 40 column screen.  The Apple II and II Plus have no lower case: they show such
; characters as other signs unless a lower case adapter is fitted.

%import syslib
%import conv
%import shared_cbm_textio_functions

txt {

    %option no_symbol_prefixing, ignore_unused

const ubyte DEFAULT_WIDTH = 40
const ubyte DEFAULT_HEIGHT = 24

asmsub chrout(ubyte character @ A) {
    ; ---- print the character where the cursor is; '\n' starts a new line
    %asm {{
        jmp  cbm.CHROUT
    }}
}

; clear_screen(), cls(), home(), nl(), spc(), rvs_on(), rvs_off(), print() and the number
; routines, and input_chars() are those of shared_cbm_textio_functions, which the
; Commodores have too: they go through cbm.CHROUT and cbm.CHRIN (see syslib).
; Inverse text shows upper case, digits and punctuation only, unless the IIe's
; alternate character set is on.

sub bell() {
    appleii.BELL()
}

sub color (ubyte txtcol) {
    ; the text screen has no colors
}

sub lowercase() {
    ; one character set
}

sub uppercase() {
    ; one character set
}

sub iso() {
    ; the characters are ASCII always
}

sub iso_off() {
}

asmsub column(ubyte col @A) {
    ; ---- set the cursor on the given column (starting with 0) on the current line
    %asm {{
        sta  appleii.CH
        rts
    }}
}

asmsub get_column() -> ubyte @Y {
    %asm {{
        ldy  appleii.CH
        rts
    }}
}

asmsub row(ubyte rownum @A) clobbers(A) {
    ; ---- set the cursor on the given row (starting with 0), in the column it is in
    %asm {{
        jmp  appleii.TABV
    }}
}

asmsub get_row() -> ubyte @X {
    %asm {{
        ldx  appleii.CV
        rts
    }}
}

asmsub get_cursor() -> ubyte @X, ubyte @Y {
    ; ---- the cursor's column and row
    %asm {{
        ldx  appleii.CH
        ldy  appleii.CV
        rts
    }}
}

asmsub plot(ubyte col @ Y, ubyte row @ X) clobbers(A) {
    ; ---- put the cursor at the column and row; 0,0 is the top left
    %asm {{
        sty  appleii.CH
        txa
        jmp  appleii.TABV
    }}
}

asmsub width() -> ubyte @A {
    ; -- returns the text screen width (number of columns)
    %asm {{
        lda  #DEFAULT_WIDTH
        rts
    }}
}

asmsub height() -> ubyte @A {
    ; -- returns the text screen height (number of rows)
    %asm {{
        lda  #DEFAULT_HEIGHT
        rts
    }}
}

sub size() -> ubyte, ubyte {
    ; -- returns the text screen width and height (number of columns and rows)
    return DEFAULT_WIDTH, DEFAULT_HEIGHT
}

asmsub waitkey() -> ubyte @A {
    ; ---- wait for a key and return it (ASCII), without a cursor and without printing it
    %asm {{
-       lda  appleii.KBD
        bpl  -
        bit  appleii.KBDSTRB
        and  #$7f
        rts
    }}
}

asmsub getkey() -> ubyte @A {
    ; ---- the key that is pressed (ASCII), or 0 when there is none, without waiting
    %asm {{
        jmp  cbm.GETIN
    }}
}

; ---- the screen's memory ----
; The 24 rows are not one after the other in memory: rowaddress() gives where a row starts.
; A character is stored with its high bit set (normal text).

asmsub rowaddress(ubyte row @Y) -> uword @AY {
    ; ---- the address of the first character of the row
    %asm {{
        lda  _rows_hi,y
        pha
        lda  _rows_lo,y
        tax
        pla
        tay
        txa
        rts
_rows_lo    .byte  $00, $80, $00, $80, $00, $80, $00, $80
            .byte  $28, $a8, $28, $a8, $28, $a8, $28, $a8
            .byte  $50, $d0, $50, $d0, $50, $d0, $50, $d0
_rows_hi    .byte  $04, $04, $05, $05, $06, $06, $07, $07
            .byte  $04, $04, $05, $05, $06, $06, $07, $07
            .byte  $04, $04, $05, $05, $06, $06, $07, $07
        ; !notreached!
    }}
}

asmsub setchr(ubyte col @X, ubyte row @Y, ubyte character @A) clobbers(A, Y) {
    ; ---- put the character on the screen at the given position; the cursor stays where it was.
    ;      0-127 is the ASCII character in normal text; 128-255 is the character 128 less
    ;      in inverse (as a screen code with its high bit set is on the Commodores), a
    ;      lower case letter as its capital.  A row off the screen is ignored.
    %asm {{
        cpy  #DEFAULT_HEIGHT
        bcs  _done
        cmp  #$80
        bcs  _inverse
        ora  #$80
        bne  _put
_inverse
        and  #$7f
        cmp  #$60
        bcc  +
        and  #$5f           ; lower case: the capital
+       cmp  #$40
        bcc  _put           ; $20-$3f: digits and punctuation, inverse as they are
        and  #$1f           ; $40-$5f: inverse capitals are $00-$1f
_put    pha
        lda  rowaddress._rows_lo,y
        sta  P8ZP_SCRATCH_W1
        lda  rowaddress._rows_hi,y
        sta  P8ZP_SCRATCH_W1+1
        txa
        tay
        pla
        sta  (P8ZP_SCRATCH_W1),y
_done   rts
    }}
}

asmsub getchr(ubyte col @A, ubyte row @Y) clobbers(Y) -> ubyte @ A {
    ; ---- the character on the screen at the given position: the ASCII character when it
    ;      is normal text, and with 128 added when it is inverse or flashing, so that
    ;      setchr() puts back what getchr() gave.  0 for a row off the screen.
    %asm {{
        cpy  #DEFAULT_HEIGHT
        bcc  +
        lda  #0
        rts
+       pha
        lda  rowaddress._rows_lo,y
        sta  P8ZP_SCRATCH_W1
        lda  rowaddress._rows_hi,y
        sta  P8ZP_SCRATCH_W1+1
        pla
        tay
        lda  (P8ZP_SCRATCH_W1),y
        bpl  _inverse
        and  #$7f
        rts
_inverse
        and  #$3f
        cmp  #$20
        bcs  +
        ora  #$40           ; $00-$1f are the capitals
+       ora  #$80
        rts
    }}
}

asmsub setclr(ubyte col @X, ubyte row @Y, ubyte color @A) {
    ; the text screen has no colors
    %asm {{
        rts
    }}
}

asmsub getclr(ubyte col @A, ubyte row @Y) -> ubyte @ A {
    ; the text screen has no colors
    %asm {{
        lda  #0
        rts
    }}
}

sub setcc(ubyte col, ubyte row, ubyte character, ubyte charcolor) {
    ; ---- set the character at the given position (there is no color)
    setchr(col, row, character)
}

asmsub clear_screenchars(ubyte character @ A) clobbers(A, X, Y) {
    ; ---- fill the screen with the character (ASCII, normal text); the cursor stays where it was
    %asm {{
        ora  #$80
        ldx  #DEFAULT_HEIGHT-1
_row    pha
        lda  rowaddress._rows_lo,x
        sta  P8ZP_SCRATCH_W1
        lda  rowaddress._rows_hi,x
        sta  P8ZP_SCRATCH_W1+1
        pla
        ldy  #DEFAULT_WIDTH-1
-       sta  (P8ZP_SCRATCH_W1),y
        dey
        bpl  -
        dex
        bpl  _row
        rts
    }}
}

asmsub fill_screen(ubyte character @ A, ubyte color @ Y) clobbers(A, X, Y) {
    ; ---- fill the screen with the character (there is no color)
    %asm {{
        jmp  clear_screenchars
    }}
}

asmsub clear_screencolors(ubyte color @ A) {
    ; the text screen has no colors
    %asm {{
        rts
    }}
}

sub scroll_up(bool alsocolors) {
    ; ---- scroll the whole screen 1 character up
    ;      contents of the bottom row are unchanged, you should refill/clear this yourself
    ubyte r
    for r in 1 to DEFAULT_HEIGHT-1
        sys.memcopy(rowaddress(r), rowaddress(r-1), DEFAULT_WIDTH)
}

sub scroll_down(bool alsocolors) {
    ; ---- scroll the whole screen 1 character down
    ;      contents of the top row are unchanged, you should refill/clear this yourself
    ubyte r
    for r in DEFAULT_HEIGHT-2 downto 0
        sys.memcopy(rowaddress(r), rowaddress(r+1), DEFAULT_WIDTH)
}

sub scroll_left(bool alsocolors) {
    ; ---- scroll the whole screen 1 character to the left
    ;      contents of the rightmost column are unchanged, you should clear/refill this yourself
    ubyte r
    for r in 0 to DEFAULT_HEIGHT-1 {
        uword line = rowaddress(r)
        ubyte c
        for c in 0 to DEFAULT_WIDTH-2
            line[c] = line[c+1]
    }
}

sub scroll_right(bool alsocolors) {
    ; ---- scroll the whole screen 1 character to the right
    ;      contents of the leftmost column are unchanged, you should clear/refill this yourself
    ubyte r
    for r in 0 to DEFAULT_HEIGHT-1 {
        uword line = rowaddress(r)
        ubyte c
        for c in DEFAULT_WIDTH-1 downto 1
            line[c] = line[c-1]
    }
}
}
