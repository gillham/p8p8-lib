; Prog8 definitions for the Text I/O and Screen routines for the Atari 8-bit computers
; (the 800XL and the others with 48 KB or more).
; Characters are ATASCII (the atascii encoding); a new line is the character $9b.
; The screen is the OS's text mode (GRAPHICS 0): 40 columns and 24 rows, one color of
; text.  Its memory holds screen codes, which setchr() and getchr() convert, and is
; where the OS says it is (SAVMSC), which depends on the memory and the cartridge.

%import syslib
%import conv

txt {

    %option no_symbol_prefixing, ignore_unused

const ubyte DEFAULT_WIDTH = 40
const ubyte DEFAULT_HEIGHT = 24

    ; 128 = print inverse characters, 0 = normal
    ubyte inverse_mode = 0

asmsub chrout(ubyte character @ A) {
    ; ---- print the character where the cursor is (ATASCII; $9b is the new line), in
    ;      inverse after rvs_on().  A, X and Y are kept.
    %asm {{
        pha
        cmp  #$9b
        beq  +
        ora  txt.inverse_mode
+       jsr  cbm.CHROUT
        pla
        rts
    }}
}

sub clear_screen() {
    cbm.CHROUT(125)
}

sub cls() {
    cbm.CHROUT(125)
}

sub home() {
    plot(0, 0)
}

sub nl() {
    cbm.CHROUT($9b)
}

sub spc() {
    chrout(' ')
}

sub rvs_on() {
    inverse_mode = 128
}

sub rvs_off() {
    inverse_mode = 0
}

sub bell() {
    cbm.CHROUT(253)
}

sub color (ubyte txtcol) {
    ; ---- the brightness of the text (0-15; the whole screen has one).  The text has the
    ;      hue of the background: atari.COLOR2 is the background, atari.COLOR4 the border.
    atari.COLOR1 = txtcol & 15
}

sub color2 (ubyte txtcol, ubyte bgcol) {
    ; ---- the brightness of the text and the color of the background (hue * 16 + brightness)
    atari.COLOR1 = txtcol & 15
    atari.COLOR2 = bgcol
}

sub lowercase() {
    ; one character set, with both cases
}

sub uppercase() {
    ; one character set, with both cases
}

asmsub column(ubyte col @A) {
    ; ---- set the cursor on the given column (starting with 0) on the current line
    %asm {{
        sta  atari.COLCRS
        lda  #0
        sta  atari.COLCRS+1
        rts
    }}
}

asmsub get_column() -> ubyte @Y {
    %asm {{
        ldy  atari.COLCRS
        rts
    }}
}

asmsub row(ubyte rownum @A) {
    ; ---- set the cursor on the given row (starting with 0), in the column it is in
    %asm {{
        sta  atari.ROWCRS
        rts
    }}
}

asmsub get_row() -> ubyte @X {
    %asm {{
        ldx  atari.ROWCRS
        rts
    }}
}

asmsub get_cursor() -> ubyte @X, ubyte @Y {
    ; ---- the cursor's column and row
    %asm {{
        ldx  atari.COLCRS
        ldy  atari.ROWCRS
        rts
    }}
}

asmsub plot(ubyte col @ Y, ubyte row @ X) clobbers(A) {
    ; ---- put the cursor at the column and row; 0,0 is the top left
    %asm {{
        sty  atari.COLCRS
        stx  atari.ROWCRS
        lda  #0
        sta  atari.COLCRS+1
        rts
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

asmsub size() clobbers(A) -> ubyte @X, ubyte @Y {
    ; -- returns the text screen width in X and height in Y (number of columns and rows)
    %asm {{
        ldx  #DEFAULT_WIDTH
        ldy  #DEFAULT_HEIGHT
        rts
    }}
}

asmsub waitkey() -> ubyte @A {
    ; ---- wait for a key and return it (ATASCII), without printing it
    %asm {{
        jmp  atari.waitkey
    }}
}

asmsub getkey() -> ubyte @A {
    ; ---- the key that is pressed (ATASCII), or 0 when there is none, without waiting
    %asm {{
        jmp  cbm.GETIN
    }}
}

asmsub input_chars(^^ubyte buffer @ AY) clobbers(A) -> ubyte @ Y {
    ; ---- Input a line (max. 80 chars) from the keyboard, with the screen editor.
    ;      Returns length in Y. (string is terminated with a 0 byte as well)
    %asm {{
        sta  P8ZP_SCRATCH_W1
        sty  P8ZP_SCRATCH_W1+1
        ldy  #0
-       jsr  cbm.CHRIN
        cmp  #$0d
        beq  +
        cpy  #80
        beq  -              ; (the rest of a longer line is passed by)
        sta  (P8ZP_SCRATCH_W1),y
        iny
        bne  -
+       lda  #0
        sta  (P8ZP_SCRATCH_W1),y
        rts
    }}
}

    bool eof_exit = true      ; for code compatibility: the keyboard input never ends

    sub eof() -> bool {
        ; ---- always false: the keyboard input never ends
        return false
    }

asmsub  print (str text @ AY) clobbers(A,Y)  {
	; ---- print zero terminated string from A/Y
	; note: the compiler contains an optimization that will replace
	;       a call to this subroutine with a string argument of just one char,
	;       by just one call to CHROUT of that single char.
	%asm {{
		sta  P8ZP_SCRATCH_W2
		sty  P8ZP_SCRATCH_W2+1
		ldy  #0
-		lda  (P8ZP_SCRATCH_W2),y
		beq  +
		jsr  chrout
		iny
		bne  -
+		rts
	}}
}

asmsub  print_ub0  (ubyte value @ A) clobbers(A,X,Y)  {
	; ---- print the ubyte in A in decimal form, with left padding 0s (3 positions total)
	%asm {{
		jsr  conv.internal_ubyte2decimal
		pha
		tya
		jsr  chrout
		txa
		jsr  chrout
		pla
		jmp  chrout
	}}
}

asmsub  print_ub  (ubyte value @ A) clobbers(A,X,Y)  {
	; ---- print the ubyte in A in decimal form, without left padding 0s
	%asm {{
		jsr  conv.internal_ubyte2decimal
_print_byte_digits
		pha
		cpy  #'0'
		beq  +
		tya
		jsr  chrout
		txa
		jsr  chrout
		jmp  _ones
+       cpx  #'0'
        beq  _ones
        txa
        jsr  chrout
_ones   pla
		jmp  chrout
	}}
}

asmsub  print_b  (byte value @ A) clobbers(A,X,Y)  {
	; ---- print the byte in A in decimal form, without left padding 0s
	%asm {{
		pha
		cmp  #0
		bpl  +
		lda  #'-'
		jsr  chrout
+		pla
		jsr  conv.internal_byte2decimal
		jmp  print_ub._print_byte_digits
	}}
}

asmsub  print_ubhex  (ubyte value @ A, bool prefix @ Pc) clobbers(A,X,Y)  {
	; ---- print the ubyte in A in hex form (if Carry is set, a radix prefix '$' is printed as well)
	%asm {{
		bcc  +
		pha
		lda  #'$'
		jsr  chrout
		pla
+		jsr  conv.internal_ubyte2hex
		jsr  chrout
		tya
		jmp  chrout
	}}
}

asmsub  print_ubbin  (ubyte value @ A, bool prefix @ Pc) clobbers(A,X,Y)  {
	; ---- print the ubyte in A in binary form (if Carry is set, a radix prefix '%' is printed as well)
	%asm {{
		sta  P8ZP_SCRATCH_B1
		bcc  +
		lda  #'%'
		jsr  chrout
+		ldy  #8
-		lda  #'0'
		asl  P8ZP_SCRATCH_B1
		bcc  +
		lda  #'1'
+		jsr  chrout
		dey
		bne  -
		rts
	}}
}

asmsub  print_uwbin  (uword value @ AY, bool prefix @ Pc) clobbers(A,X,Y)  {
	; ---- print the uword in A/Y in binary form (if Carry is set, a radix prefix '%' is printed as well)
	%asm {{
		pha
		tya
		jsr  print_ubbin
		pla
		clc
		jmp  print_ubbin
	}}
}

asmsub  print_uwhex  (uword value @ AY, bool prefix @ Pc) clobbers(A,X,Y)  {
	; ---- print the uword in A/Y in hexadecimal form (4 digits)
	;      (if Carry is set, a radix prefix '$' is printed as well)
	%asm {{
		pha
		tya
		jsr  print_ubhex
		pla
		clc
		jmp  print_ubhex
	}}
}

asmsub  print_uw0  (uword value @ AY) clobbers(A,X,Y)  {
	; ---- print the uword in A/Y in decimal form, with left padding 0s (5 positions total)
	%asm {{
		jsr  conv.internal_uword2decimal
		ldy  #0
-		lda  conv.internal_uword2decimal.decTenThousands,y
        beq  +
		jsr  chrout
		iny
		bne  -
+		rts
	}}
}

asmsub  print_uw  (uword value @ AY) clobbers(A,X,Y)  {
	; ---- print the uword in A/Y in decimal form, without left padding 0s
	%asm {{
		jsr  conv.internal_uword2decimal
		ldy  #0
-		lda  conv.internal_uword2decimal.decTenThousands,y
		beq  _allzero
		cmp  #'0'
		bne  _gotdigit
		iny
		bne  -

_gotdigit
		jsr  chrout
		iny
		lda  conv.internal_uword2decimal.decTenThousands,y
		bne  _gotdigit
		rts
_allzero
        lda  #'0'
        jmp  chrout
	}}
}

asmsub  print_w  (word value @ AY) clobbers(A,X,Y)  {
	; ---- print the (signed) word in A/Y in decimal form, without left padding 0's
	%asm {{
		cpy  #0
		bpl  +
		pha
		lda  #'-'
		jsr  chrout
		tya
		eor  #255
		tay
		pla
		eor  #255
		clc
		adc  #1
		bcc  +
		iny
+		jmp  print_uw
	}}
}


sub print_l(long value) {
    ; ---- print the (signed) long in decimal form, without left padding 0's
    print(conv.str_l(value))
}

sub print_ulhex(long value, bool prefix) {
    ; ---- print the long in hexadecimal form (8 digits)
    if prefix
        chrout('$')
    print(conv.str_ulhex(value))
}

sub print_bool(bool value) {
    if value
        txt.print("true")
    else
        txt.print("false")
}

    alias print_u16 = print_uw
    alias print_i16 = print_w
    alias print_i32 = print_l

; ---- the screen's memory ----
; rowaddress() gives where a row starts.  A character is stored as its screen code:
; ATASCII 0-31 as 64-95, 32-95 as 0-63, 96-127 as they are; 128 more is inverse.

asmsub rowaddress(ubyte row @Y) -> uword @AY {
    ; ---- the address of the first character of the row
    %asm {{
        lda  atari.SAVMSC
        clc
        adc  _rows_lo,y
        pha
        lda  atari.SAVMSC+1
        adc  _rows_hi,y
        tay
        pla
        rts
_rows_lo    .byte  <range(0, 960, 40)
_rows_hi    .byte  >range(0, 960, 40)
        ; !notreached!
    }}
}

asmsub screencode(ubyte character @A) -> ubyte @A {
    ; ---- the screen code of an ATASCII character
    %asm {{
        pha
        and  #$7f
        cmp  #$20
        bcs  +
        pla
        ora  #$40           ; 0-31: 64-95
        rts
+       cmp  #$60
        bcs  +
        pla
        sec
        sbc  #$20           ; 32-95: 0-63
        rts
+       pla                 ; 96-127: the same
        rts
    }}
}

asmsub setchr(ubyte col @X, ubyte row @Y, ubyte character @A) clobbers(A, Y) {
    ; ---- put the ATASCII character on the screen at the given position (128-255: in
    ;      inverse); the cursor stays where it was.  A row off the screen is ignored.
    %asm {{
        cpy  #DEFAULT_HEIGHT
        bcs  _done
        jsr  screencode
        pha
        lda  atari.SAVMSC
        clc
        adc  rowaddress._rows_lo,y
        sta  P8ZP_SCRATCH_W1
        lda  atari.SAVMSC+1
        adc  rowaddress._rows_hi,y
        sta  P8ZP_SCRATCH_W1+1
        txa
        tay
        pla
        sta  (P8ZP_SCRATCH_W1),y
_done   rts
    }}
}

asmsub getchr(ubyte col @A, ubyte row @Y) clobbers(Y) -> ubyte @ A {
    ; ---- the ATASCII character on the screen at the given position (128-255: it is in
    ;      inverse).  0 for a row off the screen.
    %asm {{
        cpy  #DEFAULT_HEIGHT
        bcc  +
        lda  #0
        rts
+       pha
        lda  atari.SAVMSC
        clc
        adc  rowaddress._rows_lo,y
        sta  P8ZP_SCRATCH_W1
        lda  atari.SAVMSC+1
        adc  rowaddress._rows_hi,y
        sta  P8ZP_SCRATCH_W1+1
        pla
        tay
        lda  (P8ZP_SCRATCH_W1),y
        ; the screen code back to ATASCII
        pha
        and  #$7f
        cmp  #$40
        bcs  +
        pla
        clc
        adc  #$20           ; 0-63: 32-95
        rts
+       cmp  #$60
        bcs  +
        pla
        and  #$bf           ; 64-95: 0-31
        rts
+       pla
        rts
    }}
}

asmsub setclr(ubyte col @X, ubyte row @Y, ubyte color @A) {
    ; the text screen has one color (see color())
    %asm {{
        rts
    }}
}

asmsub getclr(ubyte col @A, ubyte row @Y) -> ubyte @ A {
    ; the text screen has one color (see color())
    %asm {{
        lda  #0
        rts
    }}
}

sub setcc(ubyte col, ubyte row, ubyte character, ubyte charcolor) {
    ; ---- set the character at the given position (there is no color of its own)
    setchr(col, row, character)
}

sub clear_screenchars(ubyte character) {
    ; ---- fill the screen with the ATASCII character; the cursor stays where it was
    sys.memset(rowaddress(0), DEFAULT_WIDTH as uword * DEFAULT_HEIGHT, screencode(character))
}

sub fill_screen(ubyte character, ubyte charcolor) {
    ; ---- fill the screen with the character (there is no color of its own)
    clear_screenchars(character)
}

sub clear_screencolors(ubyte charcolor) {
    ; the text screen has one color (see color())
}

sub scroll_up(bool alsocolors) {
    ; ---- scroll the whole screen 1 character up
    ;      contents of the bottom row are unchanged, you should refill/clear this yourself
    uword screen = rowaddress(0)
    sys.memcopy(screen + DEFAULT_WIDTH, screen, DEFAULT_WIDTH as uword * (DEFAULT_HEIGHT-1))
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
