; Number conversion routines for the 8086 machines of p8p8: Prog8, with the routines that most programs carry in 8086 assembly.

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

asmsub hexadecimal(uword number @SI, ubyte bytes @CL) {
    ; ---- The hexadecimal digits of a number of 1, 2 or 4 bytes into string_out, two for
    ; each byte from the top one down, in 8086 assembly.  A digit is made with the
    ; decimal-adjust instruction and is a small letter from a on, as in hex_digits.
    %asm {{
        xor  ch, ch
        add  si, cx
        mov  di, _conv__string_out
    p8conv_hex_byte:
        dec  si
        mov  al, [si]
        mov  ah, al
        shr  al, 1
        shr  al, 1
        shr  al, 1
        shr  al, 1
        call  p8conv_hex_digit
        mov  al, ah
        call  p8conv_hex_digit
        loop  p8conv_hex_byte
        mov  byte [di], 0
        ret
    p8conv_hex_digit:
        and  al, 15
        add  al, 0x90
        daa
        adc  al, 0x40
        daa
        or  al, 0x20
        stosb
        ret
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

asmsub decimal(uword number @SI, uword out_ptr @DI, ubyte bytes @CL, ubyte digits @CH) {
    ; ---- The decimal digits of an unsigned number of 1, 2 or 4 bytes, in 8086 assembly: one
    ; routine for all the decimal conversions above.  number is where the number is,
    ; bytes its size, out_ptr where the text goes (it ends with 0), digits the least
    ; number of digits.
    ; The number (in DI and BX) is divided by 10 again and again; each remainder is a
    ; digit, which waits on the stack until the last one, the first of the text, is known.
    %asm {{
        push  bp
        mov  bp, 10
        xor  dx, dx
        mov  bx, [si]
        cmp  cl, 1
        jne  p8conv_decimal_wide
        xor  bh, bh
    p8conv_decimal_wide:
        cmp  cl, 4
        jne  p8conv_decimal_start
        mov  dx, [si+2]
    p8conv_decimal_start:
        mov  si, di
        mov  di, dx
        xor  ax, ax
        push  ax
    p8conv_decimal_digit:
        mov  ax, di
        xor  dx, dx
        div  bp
        mov  di, ax
        mov  ax, bx
        div  bp
        mov  bx, ax
        add  dl, 48
        push  dx
        test  ch, ch
        jz  p8conv_decimal_rest
        dec  ch
    p8conv_decimal_rest:
        mov  ax, bx
        or  ax, di
        jnz  p8conv_decimal_digit
        test  ch, ch
        jnz  p8conv_decimal_digit
    p8conv_decimal_out:
        pop  ax
        mov  [si], al
        inc  si
        test  al, al
        jnz  p8conv_decimal_out
        pop  bp
        ret
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

asmsub  str2uword(str string @SI) -> uword @AX {
    ; ---- the unsigned number that the decimal digits at the start of the string say
    %asm {{
        xor  bx, bx
    p8conv_str2uword_digit:
        lodsb
        sub  al, 48
        cmp  al, 10
        jae  p8conv_str2uword_end
        xor  ah, ah
        mov  cx, ax
        mov  ax, bx
        mov  dx, 10
        mul  dx
        add  ax, cx
        mov  bx, ax
        jmp  p8conv_str2uword_digit
    p8conv_str2uword_end:
        mov  ax, bx
        ret
    }}
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

asmsub  hex2uword(str string @SI) -> uword @AX {
    ; -- hexadecimal string (with or without '$') to uword.
    ;    stops parsing at the first character that's not a hex digit (except leading $)
    %asm {{
        xor  bx, bx
        cmp  byte [si], 36
        jne  p8conv_hex2uword_digit
        inc  si
    p8conv_hex2uword_digit:
        lodsb
        sub  al, 48
        jb  p8conv_hex2uword_end
        cmp  al, 10
        jb  p8conv_hex2uword_add
        or  al, 0x20
        sub  al, 49
        jb  p8conv_hex2uword_end
        cmp  al, 6
        jae  p8conv_hex2uword_end
        add  al, 10
    p8conv_hex2uword_add:
        mov  cl, 4
        shl  bx, cl
        or  bl, al
        jmp  p8conv_hex2uword_digit
    p8conv_hex2uword_end:
        mov  ax, bx
        ret
    }}
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
