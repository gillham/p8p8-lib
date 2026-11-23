; Number conversion routines for the 6809 machines of p8p8: Prog8, with the routines that most programs carry in 6809 assembly.

%import strings

conv {

; ----- number conversions to decimal strings ----

    %option ignore_unused

    str  string_out = "????????????????????????????????????????????????????????????????"       ; result buffer for the string conversion routines
    str  hex_digits = "0123456789abcdef"

    alias str_u16 = str_uw
    alias str_i16 = str_w
    alias str_i32 = str_l
    alias str_uq = str_u64
    alias str_q = str_i64

sub  str_ub0(ubyte value) -> str {
    ; ---- convert the ubyte in decimal string form, with left padding 0s (3 positions total)
    decimal(&value, string_out, 1, 3)
    return string_out
}

sub  str_ub(ubyte value) -> str {
    ; ---- convert the ubyte in decimal string form, without left padding 0s
    internal_str_ub(value, string_out)
    return string_out
}

sub  str_b(byte value) -> str {
    ; ---- convert the byte in decimal string form, without left padding 0s
    ^^ubyte out_ptr = &string_out
    if value<0 {
        @(out_ptr) = '-'
        out_ptr++
        value = -value
    }
    internal_str_ub(value as ubyte, out_ptr)
    return string_out
}

private sub internal_str_ub(ubyte value, str out_ptr) {
    decimal(&value, out_ptr, 1, 1)
}

sub  str_ubhex  (ubyte value) -> str {
    ; ---- convert the ubyte in hex string form
    hexadecimal(&value, 1)
    return string_out
}

sub  str_ubbin  (ubyte value) -> str {
    ; ---- convert the ubyte in binary string form
    ^^ubyte out_ptr = &string_out
    repeat 8 {
        rol(value)
        if_cc
            @(out_ptr) = '0'
        else
            @(out_ptr) = '1'
        out_ptr++
    }
    @(out_ptr) = 0
    return string_out
}

sub  str_uwbin  (uword value) -> str {
    ; ---- convert the uword in binary string form
    ^^ubyte out_ptr = &string_out
    repeat 16 {
        rol(value)
        if_cc
            @(out_ptr) = '0'
        else
            @(out_ptr) = '1'
        out_ptr++
    }
    @(out_ptr) = 0
    return string_out
}

sub  str_uwhex  (uword value) -> str {
    ; ---- convert the uword in hexadecimal string form (4 digits)
    hexadecimal(&value, 2)
    return string_out
}

sub  str_ulhex  (long value) -> str {
    ; ---- convert the long in hexadecimal string form (8 digits)
    hexadecimal(&value, 4)
    return string_out
}

private sub hexadecimal(^^ubyte number, ubyte bytes) {
    ; ---- The hexadecimal digits of a number of 1, 2 or 4 bytes into string_out, two for
    ; each byte from the top one down, in 6809 assembly.  A digit is made with the
    ; decimal-adjust instruction and is a small letter from a on, as in hex_digits.
    %asm {{
        ldx  _conv__hexadecimal__number
        ldu  #_conv__string_out
        ldb  _conv__hexadecimal__bytes
        p8conv_hex_byte:
        lda  ,x
        lsra
        lsra
        lsra
        lsra
        bsr  p8conv_hex_digit
        lda  ,x+
        bsr  p8conv_hex_digit
        decb
        bne  p8conv_hex_byte
        clr  ,u
        bra  p8conv_hex_end
        p8conv_hex_digit:
        anda  #15
        adda  #$90
        daa
        adca  #$40
        daa
        ora  #$20
        sta  ,u+
        rts
        p8conv_hex_end:
    }}
}

sub  str_uqhex  (uquad value) -> str {
    ; ---- convert the uquad in hexadecimal string form (16 digits)
    ^^ubyte out_ptr = &string_out
    repeat 16 {
        @(out_ptr) = hex_digits[(value >> 60) as ubyte]
        out_ptr++
        value <<= 4
    }
    @(out_ptr) = 0
    return string_out
}

sub  str_uqbin  (uquad value) -> str {
    ; ---- convert the uquad in binary string form (64 digits)
    ^^ubyte out_ptr = &string_out
    repeat 64 {
        @(out_ptr) = '0' + ((value >> 63) as ubyte)
        out_ptr++
        value <<= 1
    }
    @(out_ptr) = 0
    return string_out
}

sub  str_uw0  (uword value) -> str {
    ; ---- convert the uword in decimal string form, with left padding 0s (5 positions total)
    decimal(&value, string_out, 2, 5)
    return string_out
}

sub  str_uw  (uword value) -> str {
    ; ---- convert the uword in decimal string form, without left padding 0s
    internal_str_uw(value, string_out)
    return string_out
}

sub  str_w  (word value) -> str {
    ; ---- convert the (signed) word into decimal string form, without left padding 0's
    ^^ubyte out_ptr = &string_out
    if value<0 {
        @(out_ptr) = '-'
        out_ptr++
        value = -value
    }
    internal_str_uw(value as uword, out_ptr)
    return string_out
}

private sub internal_str_uw(uword value, str out_ptr) {
    decimal(&value, out_ptr, 2, 1)
}

sub  str_l  (long value) -> str {
    ; ---- convert the (signed) long into decimal string form, without left padding 0's
    ^^ubyte out_ptr = &string_out
    if value<0 {
        @(out_ptr) = '-'
        out_ptr++
        value = -value      ; -2147483648 stays the same, but as an unsigned number that is 2147483648
    }
    internal_str_u32(value, out_ptr)
    return string_out
}

sub  str_u32  (long value) -> str {
    ; ---- convert the 32 bits of the long, read as an unsigned number, into decimal string form, without left padding 0's
    internal_str_u32(value, string_out)
    return string_out
}

private sub internal_str_u32(long value, str out_ptr) {
    decimal(&value, out_ptr, 4, 1)
}

private sub decimal(^^ubyte number, ^^ubyte out_ptr, ubyte bytes, ubyte digits) {
    ; ---- The decimal digits of an unsigned number of 1, 2 or 4 bytes, in 6809 assembly: one
    ; routine for all the decimal conversions above.  number is where the number is (it
    ; is used up), bytes its size, out_ptr where the text goes (it ends with 0), digits
    ; the least number of digits.
    ; The number is divided by 10 again and again, a bit at a time through all its
    ; bytes; each remainder is a digit, which waits on the stack until the last one,
    ; the first of the text, is known.
    %asm {{
        ldu  _conv__decimal__out_ptr
        clr  ,-s
        p8conv_decimal_digit:
        ldx  _conv__decimal__number
        ldb  _conv__decimal__bytes
        pshs  b
        clra
        p8conv_decimal_byte:
        ldb  #8
        p8conv_decimal_bit:
        lsl  ,x
        rola
        cmpa  #10
        blo  p8conv_decimal_less
        suba  #10
        inc  ,x
        p8conv_decimal_less:
        decb
        bne  p8conv_decimal_bit
        leax  1,x
        dec  ,s
        bne  p8conv_decimal_byte
        leas  1,s
        adda  #48
        pshs  a
        ldb  _conv__decimal__digits
        beq  p8conv_decimal_rest
        dec  _conv__decimal__digits
        p8conv_decimal_rest:
        ldx  _conv__decimal__number
        ldb  _conv__decimal__bytes
        clra
        p8conv_decimal_zero:
        ora  ,x+
        decb
        bne  p8conv_decimal_zero
        tsta
        bne  p8conv_decimal_digit
        tst  _conv__decimal__digits
        bne  p8conv_decimal_digit
        p8conv_decimal_out:
        puls  a
        sta  ,u+
        bne  p8conv_decimal_out
    }}
}

sub  str_i64  (quad value) -> str {
    ; ---- convert the (signed) quad into decimal string form, without left padding 0's
    ^^ubyte out_ptr = &string_out
    if value<0 {
        @(out_ptr) = '-'
        out_ptr++
        value = -value      ; -9223372036854775808 stays the same, but as an unsigned number that is 9223372036854775808
    }
    internal_str_u64(value as uquad, out_ptr)
    return string_out
}

sub  str_u64  (uquad value) -> str {
    ; ---- convert the uquad into decimal string form, without left padding 0's
    internal_str_u64(value, string_out)
    return string_out
}

private sub internal_str_u64(uquad value, str out_ptr) {
    ubyte[20] digits
    ubyte count = 0
    do {
        uquad quotient = value / 10
        digits[count] = (value - quotient*10) as ubyte
        count++
        value = quotient
    } until value==0
    while count!=0 {
        count--
        @(out_ptr) = digits[count]+'0'
        out_ptr++
    }
    @(out_ptr) = 0
}

sub  str_bool  (bool value) -> str {
    ; ---- convert the boolean into the string "true" or "false"
    if value
        return "true"
    return "false"
}

; ---- string conversion to numbers -----

sub  str2ubyte(str string) -> ubyte {
    ; -- returns in A the unsigned byte value of the string number argument in AY
    ;    the number may NOT be preceded by a + sign and may NOT contain spaces
    ;    (any non-digit character will terminate the number string that is parsed)
    return str2uword(string) as ubyte
}

sub  str2byte(str string) -> byte {
    ; -- returns in A the signed byte value of the string number argument in AY
    ;    the number may be preceded by a + or - sign but may NOT contain spaces
    ;    (any non-digit character will terminate the number string that is parsed)
    return str2word(string) as byte
}

sub  str2uword(str string) -> uword {
    ; ---- the unsigned number that the decimal digits at the start of the string say
    uword @shared result
    %asm {{
        ldx  _conv__str2uword__string
        ldd  #0
        pshs  d
        p8conv_str2uword_digit:
        ldb  ,x+
        subb  #48
        cmpb  #10
        bhs  p8conv_str2uword_end
        pshs  b
        ldd  1,s
        lslb
        rola
        lslb
        rola
        addd  1,s
        lslb
        rola
        addb  ,s+
        adca  #0
        std  ,s
        bra  p8conv_str2uword_digit
        p8conv_str2uword_end:
        puls  d
        std  _conv__str2uword__result
    }}
    return result
}

sub  str2word(str string) -> word {
    ; ---- the same with a sign before the digits
    uword magnitude
    if string[0] == '-' {
        string++
        magnitude = str2uword(string)
        return 0 - magnitude as word
    }
    if string[0] == '+'
        string++
    magnitude = str2uword(string)
    return magnitude as word
}

sub  hex2uword(str string) -> uword {
    ; -- hexadecimal string (with or without '$') to uword.
    ;    stops parsing at the first character that's not a hex digit (except leading $)
    uword @shared result
    %asm {{
        ldx  _conv__hex2uword__string
        ldd  #0
        pshs  d
        lda  ,x
        cmpa  #36
        bne  p8conv_hex2uword_digit
        leax  1,x
        p8conv_hex2uword_digit:
        lda  ,x+
        suba  #48
        blo  p8conv_hex2uword_end
        cmpa  #10
        blo  p8conv_hex2uword_add
        ora  #$20
        suba  #49
        blo  p8conv_hex2uword_end
        cmpa  #6
        bhs  p8conv_hex2uword_end
        adda  #10
        p8conv_hex2uword_add:
        pshs  a
        ldd  1,s
        lslb
        rola
        lslb
        rola
        lslb
        rola
        lslb
        rola
        orb  ,s+
        std  ,s
        bra  p8conv_hex2uword_digit
        p8conv_hex2uword_end:
        puls  d
        std  _conv__hex2uword__result
    }}
    return result
}

sub  hex2long(str string) -> long {
    ; -- hexadecimal string (with or without '$') to long.
    ;    stops parsing at the first character that's not a hex digit (except leading $)
    long result
    ubyte char
    if @(string)=='$'
        string++
    repeat {
        char = strings.lowerchar(@(string))
        if strings.isxdigit(char) {
            result <<= 4
            if char>='0' and char<='9'
                result |= char-'0'
            else
                result |= char-'a'+10
        } else
            return result
        string++
    }
}

sub  str2long(str string) -> long {
    ; -- convert a decimal string (terminated with a zero byte) into a long. Clobbers R0
    long result = 0
    bool negative = string[0] == '-'
    if negative or string[0]=='+'
        string++
    repeat {
        ubyte digit_char = @(string)
        if strings.isdigit(digit_char) {
            result = (result<<1) + (result<<3)  ; multiply by 10
            result += digit_char - '0'  ; add digit
        } else {
            break   ; Invalid character, stop processing
        }
        string++
    }

    if negative
        return -result
    else
        return result
}

sub  bin2uword(str string) -> uword {
    ; -- binary string (with or without '%') to uword.
    ;    stops parsing at the first character that's not a 0 or 1. (except leading %)
    uword result
    ubyte char
    if @(string)=='%'
        string++
    repeat {
        char = @(string)
        if char=='0' {
            result <<= 1
        } else if char=='1' {
            result <<= 1
            result |= 1
        } else
            return result
        string++
    }
}

sub  any2uword(str string) -> uword, ubyte {
    ; -- convert any number string (any prefix allowed) to uword.
    ;    returns the parsed word value, and the number of processed characters (including the prefix symbol)
    ubyte count
    when string[0] {
        '$' -> {
            count = 1
            while strings.isxdigit(string[count])
                count++
            return hex2uword(string), count
        }
        '%' -> {
            count = 1
            while string[count]=='0' or string[count]=='1'
                count++
            return bin2uword(string), count
        }
        else -> {
            count = 0
            while strings.isdigit(string[count])
                count++
            return str2uword(string), count
        }
    }
}
}
