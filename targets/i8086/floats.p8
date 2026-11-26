; Prog8 definitions for floating point handling on the 8086 machines of p8p8, where a float is a 64-bit double
; (IEEE, as an 8087 has them and as the llvm64 target does).
;
; The arithmetic is the routines at the end of this file (p8f_add ...), which the code generator calls.  Each is
; there twice: with the 8087's instructions and without them.  Which a program has, the target file says
; (floats = 8087, software, or auto: both, and the program looks for an 8087 when it starts).
; Everything else is Prog8 on top of that, and so the same with and without the 8087: sin, cos, tan, atan, ln,
; log2, exp and pow are series here, good for about 15 digits.
; Floats print with up to 15 digits (the llvm64 target prints as many as tell the number apart, up to 17);
; rnd() takes its random bits from math.rndw().

%import math
%option enable_floats, ignore_unused

sys {
    %option merge       ; add some constants to sys

    const float  MAX_FLOAT = 1.7976931348623157e+308
    const float  MIN_FLOAT = -1.7976931348623157e+308
}

txt {
    %option merge       ; add function to txt

    alias print_f = floats.print
}

math {
    %option merge, ignore_unused       ; add functions to math

    alias lerpf = floats.lerp
    alias lerpf_fast = floats.lerp_fast
    alias interpolatef = floats.interpolate
}


floats {

    ; what the code generator and the routines at the end of this file use
    ubyte[8] @shared fac            ; the float that a subroutine returns
    ubyte[8] @shared operand        ; a constant that an instruction works with
    ubyte @shared has87 = 0         ; an 8087 was found
    uword @shared status
    uword @shared control = $027f   ; the 8087's control word: results as doubles, to the nearest
    uword @shared control2
    ubyte[4] @shared whole          ; a long on its way to or from the 8087
    ubyte[12] @shared ra            ; a float taken apart: 8 bytes of its digits, the exponent (a word), the sign
    ubyte[12] @shared rb
    ubyte[24] @shared pm            ; a product's 16 bytes, and room for its carries
    ubyte[8] @shared fx
    ubyte[8] @shared fa
    ubyte[8] @shared ft
    float @shared one = 1.0
    float @shared half = 0.5

        const float  π         = 3.141592653589793
        const float  PI        = π
        const float  TWOPI     = 2*π
        const float  E         = 2.718281828459045
        const float  EPSILON   = 4.9E-324

        alias log = floats.ln


sub print(float value) {
    ; ---- prints the floating point value (without a newline and no leading spaces), as tostr() gives it
    void tostr(value)
    %ir {{
        load.p r99200.p,#floats.tostr.buffer
        syscall 3 (r99200.p)
        return
    }}
}

sub tostr(float value) -> str {
    ; ---- converts the floating point value to a string (no leading spaces), as the virtual target does:
    ;      with the fewest digits that read back as the same value, and in scientific notation below 0.001 and from 10000000 on
    str @shared buffer = " " * 31
    str @shared digits = " " * 31
    ubyte[17] mantissa
    ubyte length = 0
    ubyte count = 0
    ubyte index = 0
    word exponent = 0

    if value != value {
        add_text("NaN")
        return finish()
    }
    if peek(&value + 7) & $80 != 0 {
        add('-')
        value = -value
    }
    if value == 0.0 {
        add_text("0.0")
        return finish()
    }
    if value > sys.MAX_FLOAT {
        add_text("Infinity")
        return finish()
    }

    ; digits gets d.ddde+xx
    scientific()
    while digits[index] != 'e' {
        if digits[index] != '.' {
            mantissa[count] = digits[index]
            count++
        }
        index++
    }
    bool negative_exponent = digits[index+1] == '-'
    index += 2
    while digits[index] != 0 {
        exponent = exponent * 10 + (digits[index] - '0') as word
        index++
    }
    if negative_exponent
        exponent = -exponent
    while count > 1 and mantissa[count-1] == '0'
        count--

    if exponent >= -3 and exponent < 7 {
        if exponent < 0 {
            add_text("0.")
            repeat (-exponent - 1) as ubyte
                add('0')
            for index in 0 to count-1
                add(mantissa[index])
        } else {
            for index in 0 to lsb(exponent) {
                if index < count
                    add(mantissa[index])
                else
                    add('0')
            }
            add('.')
            if count > lsb(exponent) + 1 {
                for index in lsb(exponent) + 1 to count-1
                    add(mantissa[index])
            } else
                add('0')
        }
    } else {
        add(mantissa[0])
        add('.')
        if count > 1 {
            for index in 1 to count-1
                add(mantissa[index])
        } else
            add('0')
        add('E')
        if exponent < 0 {
            add('-')
            exponent = -exponent
        }
        if exponent >= 100
            add('0' + lsb(exponent / 100))
        if exponent >= 10
            add('0' + lsb(exponent / 10 % 10))
        add('0' + lsb(exponent % 10))
    }
    return finish()

    sub add(ubyte character) {
        buffer[length] = character
        length++
    }

    sub scientific() {
        ; -- the value (which is above 0) as 15 digits and a power of ten, into digits: "d.dddddddddddddde+xx"
        word exp10 = 0
        float v = value
        while v >= 1e16 {
            v /= 1e16
            exp10 += 16
        }
        while v >= 1e4 {
            v /= 1e4
            exp10 += 4
        }
        while v >= 10.0 {
            v /= 10.0
            exp10++
        }
        while v < 1e-15 {
            v *= 1e16
            exp10 -= 16
        }
        while v < 1e-3 {
            v *= 1e4
            exp10 -= 4
        }
        while v < 1.0 {
            v *= 10.0
            exp10--
        }
        ; sixteen digits as two whole numbers of eight, then the last one rounded away
        float scaled = v * 1e7
        long high = scaled as long
        long low = ((scaled - (high as float)) * 1e8 + 0.5) as long
        if low >= 100000000 {
            low -= 100000000
            high++
        }
        low = (low + 5) / 10
        if low >= 10000000 {
            low -= 10000000
            high++
        }
        if high >= 100000000 {
            high = 10000000
            low = 0
            exp10++
        }
        ubyte at = 15
        repeat 7 {
            digits[at] = '0' + lsb(low % 10)
            low /= 10
            at--
        }
        repeat 7 {
            digits[at] = '0' + lsb(high % 10)
            high /= 10
            at--
        }
        digits[1] = '.'
        digits[0] = '0' + lsb(high)
        digits[16] = 'e'
        digits[17] = '+'
        if exp10 < 0 {
            digits[17] = '-'
            exp10 = -exp10
        }
        at = 18
        if exp10 >= 100 {
            digits[at] = '0' + lsb(exp10 / 100)
            at++
        }
        digits[at] = '0' + lsb(exp10 / 10 % 10)
        digits[at + 1] = '0' + lsb(exp10 % 10)
        digits[at + 2] = 0
    }

    sub add_text(str text) {
        ubyte i = 0
        while text[i] != 0 {
            add(text[i])
            i++
        }
    }

    sub finish() -> str {
        buffer[length] = 0
        return buffer
    }
}

sub parse(str value) -> float {
    ; -- parse a string value of a number to float, as the virtual target does: spaces are left out, and the number
    ;    ends at the first other character that isn't one of +-0123456789.eE; 0.0 when that is no number
    str @shared buffer = " " * 255
    ubyte length = 0
    ubyte index = 0
    ubyte character
    repeat {
        character = value[index]
        if character == 0 or length == 255
            break
        if character != ' ' {
            if character not in "+-0123456789.eE"
                break
            buffer[length] = character
            length++
        }
        index++
        if index == 0
            break
    }
    buffer[length] = 0
    float result = 0.0
    bool negative = false
    bool point = false
    bool any = false
    word exp10 = 0
    index = 0
    if buffer[0] == '-' {
        negative = true
        index = 1
    }
    else if buffer[0] == '+'
        index = 1
    repeat {
        character = buffer[index]
        if character == '.' {
            if point
                break
            point = true
        }
        else if character >= '0' and character <= '9' {
            result = result * 10.0 + ((character - '0') as float)
            any = true
            if point
                exp10--
        }
        else
            break
        index++
    }
    if not any
        return 0.0
    if character == 'e' or character == 'E' {
        word given = 0
        bool down = false
        index++
        if buffer[index] == '-' {
            down = true
            index++
        }
        else if buffer[index] == '+'
            index++
        while buffer[index] >= '0' and buffer[index] <= '9' {
            if given < 1000
                given = given * 10 + (buffer[index] - '0')
            index++
        }
        if down
            exp10 -= given
        else
            exp10 += given
    }
    ; (a power of ten up to the 22nd is a float exactly: one step where that is enough)
    while exp10 > 0 {
        ubyte up = 22
        if exp10 < 22
            up = lsb(exp10)
        result *= power_of_ten(up)
        exp10 -= up
        if result > sys.MAX_FLOAT
            break
    }
    while exp10 < 0 {
        ubyte less = 22
        if exp10 > -22
            less = lsb(-exp10)
        result /= power_of_ten(less)
        exp10 += less
        if result == 0.0
            break
    }
    if negative
        return -result
    return result

    sub power_of_ten(ubyte n) -> float {
        float p = 1.0
        repeat n
            p *= 10.0
        return p
    }
}

sub rnd() -> float {
    ; -- a random float from 0.0 up to but not including 1.0, made of two math.rndw() values
    float high = math.rndw() as float
    float low = math.rndw() as float
    return (high * 65536.0 + low) / 4294967296.0
}

sub rndseed(float seed) {
    ; -- seeds the random generator of rnd(), which is the one of math.rndw() and math.rnd(), with the bits of the seed
    long low = peekl(&seed)
    long high = peekl(&seed + 4)
    math.rndseed(lsw(low) ^ msw(high), msw(low) ^ lsw(high))
}


const float LN2 = 0.6931471805599453

sub pow(float value, float power) -> float {
    ; -- the value to a power.  A negative value has one for a power that is a whole number.
    if power == 0.0
        return 1.0
    if value == 0.0
        return 0.0
    if value < 0.0 {
        float positive = exp(power * ln(-value))
        float halved = power / 2.0
        if floor(power) == power and floor(halved) != halved
            return -positive
        return positive
    }
    return exp(power * ln(value))
}

sub exp(float value) -> float {
    ; -- e to the power of the value: 2 to a whole power, times a series for the rest
    if value > 709.7
        return sys.MAX_FLOAT
    if value < -745.0
        return 0.0
    float k = floor(value / LN2 + 0.5)
    float r = value - k * LN2
    float sum = 1.0
    ubyte n
    for n in 14 downto 1
        sum = 1.0 + sum * r / (n as float)
    return scale2(sum, k as word)
}

sub scale2(float value, word power) -> float {
    ; -- the value times 2 to a whole power, by its exponent
    if value == 0.0
        return 0.0
    word e = ((peekw(&value + 6) >> 4) & $7ff) as word + power
    if e <= 0
        return 0.0
    if e >= 2047
        return sys.MAX_FLOAT
    pokew(&value + 6, (peekw(&value + 6) & $800f) | ((e as uword) << 4))
    return value
}

sub sin(float angle) -> float {
    ; -- the angle brought between -π/2 and π/2, then the series up to its 19th power
    float turns = floor(angle / TWOPI + 0.5)
    angle -= turns * TWOPI
    if angle > π/2
        angle = π - angle
    else if angle < -π/2
        angle = -π - angle
    float x2 = angle * angle
    float sum = 1.0
    ubyte n
    for n in 19 downto 3 step -2
        sum = 1.0 - sum * x2 / ((n as float) * ((n - 1) as float))
    return angle * sum
}

sub cos(float angle) -> float {
    return sin(angle + π/2)
}

sub tan(float value) -> float {
    return sin(value) / cos(value)
}

sub atan(float value) -> float {
    ; -- the value brought below tan(π/12), by 1/x and by an angle of π/6 taken off; then the series
    bool negative = value < 0.0
    if negative
        value = -value
    bool inverted = value > 1.0
    if inverted
        value = 1.0 / value
    bool shifted = value > 0.2679491924311227
    if shifted
        value = (value * 1.7320508075688772 - 1.0) / (1.7320508075688772 + value)
    float x2 = value * value
    float sum = 0.0
    ubyte n
    for n in 29 downto 1 step -2
        sum = 1.0 / (n as float) - sum * x2
    float angle = value * sum
    if shifted
        angle += π/6
    if inverted
        angle = π/2 - angle
    if negative
        return -angle
    return angle
}

sub asin(float value) -> float {
    ; -- arcsine, from -π/2 to π/2. Values outside of -1..1 count as -1 or 1.
    value = clampf(value, -1.0, 1.0)
    ; the half-angle form doesn't divide by 0 for -1 and 1, unlike atan(value / sqrt(1 - value*value))
    return 2.0 * atan(value / (1.0 + sqrt(1.0 - value*value)))
}

sub acos(float value) -> float {
    ; -- arccosine, from 0 to π. Values outside of -1..1 count as -1 or 1.
    return π/2 - asin(value)
}

; two-argument arctangent that returns an angle in the correct quadrant
; for the signs of x and y, normalized to the range [0, 2π]
sub atan2(float y, float x) -> float {
    float atn
    if x == 0 {
        atn = π/2
        if y == 0 return 0
        if y < 0 {
            atn += π
        }
    } else {
        atn = atan(y / x)
    }
    if x < 0 atn += π
    if atn < 0 atn += 2*π
    return atn
}

; reciprocal functions
sub secant(float value) -> float { return 1.0 / cos(value) }
sub csc(float value)    -> float { return 1.0 / sin(value) }
sub cot(float value)    -> float { return 1.0 / tan(value) }

sub ln(float value) -> float {
    ; -- the natural logarithm: of the number's power of 2, and a series for what is left (between √½ and √2)
    if value <= 0.0
        return sys.MIN_FLOAT
    word e = ((peekw(&value + 6) >> 4) & $7ff) as word - 1023
    pokew(&value + 6, (peekw(&value + 6) & $000f) | $3ff0)
    if value > 1.4142135623730951 {
        pokew(&value + 6, (peekw(&value + 6) & $000f) | $3fe0)
        e++
    }
    float s = (value - 1.0) / (value + 1.0)
    float s2 = s * s
    float sum = 0.0
    ubyte n
    for n in 21 downto 1 step -2
        sum = sum * s2 + 1.0 / (n as float)
    return 2.0 * s * sum + (e as float) * LN2
}

sub log2(float value) -> float {
    return ln(value) / LN2
}

sub rad(float angle) -> float {
    ; -- convert degrees to radians (d * pi / 180)
    return angle * PI / 180.0
}

sub deg(float angle) -> float {
    ; -- convert radians to degrees (d * (1/ pi * 180))
    return angle * 180.0 / PI
}

sub round(float value) -> float {
    ; -- rounds to the nearest whole number, and halfway values to the even one, like the virtual target
    float whole = floor(value + 0.5)
    if whole - value == 0.5 {
        float halved = whole / 2.0
        if floor(halved) != halved
            whole -= 1.0
    }
    return whole
}

sub floor(float value) -> float {
    %ir {{
        loadm.f fr0.f,[floats.floor.value]
        ffloor.f fr1.f,fr0.f
        returnr.f fr1.f
    }}
}

sub ceil(float value) -> float {
    %ir {{
        loadm.f fr0.f,[floats.ceil.value]
        fceil.f fr1.f,fr0.f
        returnr.f fr1.f
    }}
}


sub minf(float f1, float f2) -> float {
    if f1<f2
        return f1
    return f2
}


sub maxf(float f1, float f2) -> float {
    if f1>f2
        return f1
    return f2
}


sub clampf(float value, float minimum, float maximum) -> float {
    if value<minimum
        value=minimum
    if value<maximum
        return value
    return maximum
}

sub mod(float value, float divisor) -> float {
    return value - floor(value / divisor) * divisor
}

sub normalize(float value) -> float {
    return value
}

sub lerp(float v0, float v1, float t) -> float {
    ; Linear interpolation (LERP)
    ; Precise method, which guarantees v = v1 when t = 1.
    ; returns an interpolation between two inputs (v0, v1) for a parameter t in the closed unit interval [0, 1]
    return (1 - t) * v0 + t * v1
}

sub lerp_fast(float v0, float v1, float t) -> float {
    ; Linear interpolation (LERP)
    ; Imprecise (but slightly faster) method, which does not guarantee v = v1 when t = 1
    ; returns an interpolation between two inputs (v0, v1) for a parameter t in the closed unit interval [0, 1]
    return v0 + t * (v1 - v0)
}

sub interpolate(float v, float inputMin, float inputMax, float outputMin, float outputMax) -> float {
    ; Interpolate a value v in interval [inputMin, inputMax] to output interval [outputMin, outputMax]
    if outputMin==outputMax
        return outputMin
    v = (v - inputMin) / (inputMax - inputMin)
    return v * (outputMax - outputMin) + outputMin
}

    ; ---- the arithmetic that the code generator calls ----
    ;
    ; A routine works on the float that DI points at, with the one that SI points at, and may change every
    ; register.  p8f_mode says how they are written: 0 for the 8087 alone, 1 without it, 2 both ways, with
    ; has87 to choose.  (On an 8087 the processor must wait for it before each of its instructions and
    ; before it reads what one has stored: "fwait".)
    %asm {{
p8f_init:
%if p8f_mode != 1
        ; is there an 8087?  Its status and control words read as they must after "fninit".
        fninit
        mov  word [_floats__status], 0x5a5a
        fnstsw  [_floats__status]
        cmp  byte [_floats__status], 0
        jne  p8f_init_end
        fnstcw  [_floats__status]
        mov  ax, [_floats__status]
        and  ax, 0x103f
        cmp  ax, 0x003f
        jne  p8f_init_end
        fldcw  [_floats__control]
        mov  byte [_floats__has87], 1
p8f_init_end:
%endif
        ret

p8f_add:
%if p8f_mode == 2
        cmp  byte [_floats__has87], 0
        je  p8fs_add
%endif
%if p8f_mode != 1
        fwait
        fld  qword [di]
        fwait
        fadd  qword [si]
        fwait
        fstp  qword [di]
        fwait
        ret
%endif
%if p8f_mode != 0
p8fs_add:
        push  di
        call  p8fs_unpack_both
        jmp  p8fs_sum
%endif

p8f_sub:
%if p8f_mode == 2
        cmp  byte [_floats__has87], 0
        je  p8fs_sub
%endif
%if p8f_mode != 1
        fwait
        fld  qword [di]
        fwait
        fsub  qword [si]
        fwait
        fstp  qword [di]
        fwait
        ret
%endif
%if p8f_mode != 0
p8fs_sub:
        push  di
        call  p8fs_unpack_both
        xor  byte [_floats__rb+10], 0x80
        ; the sum of ra and rb, into where the address on the stack points
p8fs_sum:
        cmp  word [_floats__rb+8], 0
        je  p8fs_sum_pack
        cmp  word [_floats__ra+8], 0
        jne  p8fs_sum_both
        call  p8fs_swap
        jmp  p8fs_sum_pack
p8fs_sum_both:
        ; ra is the one with the larger exponent
        mov  ax, [_floats__ra+8]
        cmp  ax, [_floats__rb+8]
        jae  p8fs_sum_ordered
        call  p8fs_swap
p8fs_sum_ordered:
        ; rb's digits to the right until the exponents are the same; what leaves stays as the lowest bit
        mov  cx, [_floats__ra+8]
        sub  cx, [_floats__rb+8]
        jz  p8fs_sum_aligned
        cmp  cx, 64
        jb  p8fs_sum_shift
        xor  ax, ax
        mov  [_floats__rb+2], ax
        mov  [_floats__rb+4], ax
        mov  [_floats__rb+6], ax
        inc  ax
        mov  [_floats__rb], ax
        jmp  p8fs_sum_aligned
p8fs_sum_shift:
        xor  dx, dx
p8fs_sum_shift_bit:
        shr  word [_floats__rb+6], 1
        rcr  word [_floats__rb+4], 1
        rcr  word [_floats__rb+2], 1
        rcr  word [_floats__rb], 1
        jnc  p8fs_sum_shift_next
        mov  dl, 1
p8fs_sum_shift_next:
        loop  p8fs_sum_shift_bit
        or  [_floats__rb], dx
p8fs_sum_aligned:
        mov  al, [_floats__ra+10]
        cmp  al, [_floats__rb+10]
        jne  p8fs_sum_differ
        mov  ax, [_floats__rb]
        add  [_floats__ra], ax
        mov  ax, [_floats__rb+2]
        adc  [_floats__ra+2], ax
        mov  ax, [_floats__rb+4]
        adc  [_floats__ra+4], ax
        mov  ax, [_floats__rb+6]
        adc  [_floats__ra+6], ax
        jnc  p8fs_sum_pack
        ; one bit more than fits: to the right, with that bit at the top
        rcr  word [_floats__ra+6], 1
        rcr  word [_floats__ra+4], 1
        rcr  word [_floats__ra+2], 1
        rcr  word [_floats__ra], 1
        jnc  p8fs_sum_carried
        or  byte [_floats__ra], 1
p8fs_sum_carried:
        inc  word [_floats__ra+8]
        jmp  p8fs_sum_pack
p8fs_sum_differ:
        mov  ax, [_floats__rb]
        sub  [_floats__ra], ax
        mov  ax, [_floats__rb+2]
        sbb  [_floats__ra+2], ax
        mov  ax, [_floats__rb+4]
        sbb  [_floats__ra+4], ax
        mov  ax, [_floats__rb+6]
        sbb  [_floats__ra+6], ax
        jnc  p8fs_sum_normal
        ; rb was the greater one: the difference turned over, with the other sign
        not  word [_floats__ra]
        not  word [_floats__ra+2]
        not  word [_floats__ra+4]
        not  word [_floats__ra+6]
        add  word [_floats__ra], 1
        adc  word [_floats__ra+2], 0
        adc  word [_floats__ra+4], 0
        adc  word [_floats__ra+6], 0
        xor  byte [_floats__ra+10], 0x80
p8fs_sum_normal:
        call  p8fs_normalize
p8fs_sum_pack:
        pop  di
        jmp  p8fs_pack

        ; ra and rb change places
p8fs_swap:
        mov  bx, 10
p8fs_swap_next:
        mov  ax, [_floats__ra+bx]
        xchg  ax, [_floats__rb+bx]
        mov  [_floats__ra+bx], ax
        sub  bx, 2
        jns  p8fs_swap_next
        ret

        ; the float at DI into ra and the one at SI into rb
p8fs_unpack_both:
        push  si
        mov  si, di
        mov  bx, _floats__ra
        call  p8fs_unpack
        pop  si
        mov  bx, _floats__rb
        ; The float at SI taken apart, into the 12 bytes at BX: its digits as 64 bits with the first
        ; one at the top, the exponent as it is in the float (0: the number is zero), the sign.
p8fs_unpack:
        mov  ax, [si]
        mov  [bx], ax
        mov  ax, [si+2]
        mov  [bx+2], ax
        mov  ax, [si+4]
        mov  [bx+4], ax
        mov  ax, [si+6]
        mov  dx, ax
        and  dh, 0x80
        mov  [bx+10], dh
        mov  dx, ax
        and  ax, 0x000f
        or  al, 0x10
        mov  [bx+6], ax
        and  dx, 0x7ff0
        mov  cl, 4
        shr  dx, cl
        mov  [bx+8], dx
        jnz  p8fs_unpack_digits
        xor  ax, ax
        mov  [bx], ax
        mov  [bx+2], ax
        mov  [bx+4], ax
        mov  [bx+6], ax
        ret
p8fs_unpack_digits:
        mov  cx, 11
p8fs_unpack_bit:
        shl  word [bx], 1
        rcl  word [bx+2], 1
        rcl  word [bx+4], 1
        rcl  word [bx+6], 1
        loop  p8fs_unpack_bit
        ret

        ; ra's digits to the left until the first one is at the top
p8fs_normalize:
        mov  ax, [_floats__ra]
        or  ax, [_floats__ra+2]
        or  ax, [_floats__ra+4]
        or  ax, [_floats__ra+6]
        jz  p8fs_normalize_end
p8fs_normalize_bit:
        test  byte [_floats__ra+7], 0x80
        jnz  p8fs_normalize_end
        shl  word [_floats__ra], 1
        rcl  word [_floats__ra+2], 1
        rcl  word [_floats__ra+4], 1
        rcl  word [_floats__ra+6], 1
        dec  word [_floats__ra+8]
        jmp  p8fs_normalize_bit
p8fs_normalize_end:
        ret

        ; ra as a float at DI: rounded to 53 bits, to the nearest and a half to the even one
p8fs_pack:
        mov  bx, _floats__ra
        mov  ax, [bx]
        or  ax, [bx+2]
        or  ax, [bx+4]
        or  ax, [bx+6]
        jnz  p8fs_pack_number
p8fs_pack_zero:
        xor  ax, ax
        mov  [di], ax
        mov  [di+2], ax
        mov  [di+4], ax
        mov  [di+6], ax
        ret
p8fs_pack_number:
        mov  dx, [bx]
        and  dx, 0x07ff
        add  word [bx], 0x0400
        adc  word [bx+2], 0
        adc  word [bx+4], 0
        adc  word [bx+6], 0
        jnc  p8fs_pack_rounded
        mov  word [bx+6], 0x8000
        inc  word [bx+8]
p8fs_pack_rounded:
        cmp  dx, 0x0400
        jne  p8fs_pack_range
        and  byte [bx+1], 0xf7
p8fs_pack_range:
        mov  ax, [bx+8]
        cmp  ax, 0
        jle  p8fs_pack_zero
        cmp  ax, 0x07ff
        jl  p8fs_pack_fits
        ; too large: infinity
        xor  ax, ax
        mov  [di], ax
        mov  [di+2], ax
        mov  [di+4], ax
        mov  ax, 0x7ff0
        or  ah, [bx+10]
        mov  [di+6], ax
        ret
p8fs_pack_fits:
        mov  cx, 11
p8fs_pack_bit:
        shr  word [bx+6], 1
        rcr  word [bx+4], 1
        rcr  word [bx+2], 1
        rcr  word [bx], 1
        loop  p8fs_pack_bit
        mov  ax, [bx]
        mov  [di], ax
        mov  ax, [bx+2]
        mov  [di+2], ax
        mov  ax, [bx+4]
        mov  [di+4], ax
        mov  ax, [bx+6]
        and  ax, 0x000f
        mov  dx, [bx+8]
        mov  cl, 4
        shl  dx, cl
        or  ax, dx
        or  ah, [bx+10]
        mov  [di+6], ax
        ret
%endif

p8f_mul:
%if p8f_mode == 2
        cmp  byte [_floats__has87], 0
        je  p8fs_mul
%endif
%if p8f_mode != 1
        fwait
        fld  qword [di]
        fwait
        fmul  qword [si]
        fwait
        fstp  qword [di]
        fwait
        ret
%endif
%if p8f_mode != 0
p8fs_mul:
        push  di
        call  p8fs_unpack_both
        cmp  word [_floats__ra+8], 0
        je  p8fs_mul_zero
        cmp  word [_floats__rb+8], 0
        jne  p8fs_mul_number
p8fs_mul_zero:
        pop  di
        jmp  p8fs_pack_zero
p8fs_mul_number:
        mov  al, [_floats__rb+10]
        xor  [_floats__ra+10], al
        mov  ax, [_floats__ra+8]
        add  ax, [_floats__rb+8]
        sub  ax, 1022
        mov  [_floats__ra+8], ax
        ; the 128 bits of the product of the two times 64 bits, a word times a word at a time
        mov  di, _floats__pm
        mov  cx, 12
        xor  ax, ax
        rep stosw
        xor  si, si
p8fs_mul_outer:
        xor  di, di
p8fs_mul_inner:
        mov  ax, [_floats__ra+si]
        mul  word [_floats__rb+di]
        mov  bx, si
        add  bx, di
        add  [_floats__pm+bx], ax
        adc  [_floats__pm+bx+2], dx
        adc  word [_floats__pm+bx+4], 0
        adc  word [_floats__pm+bx+6], 0
        adc  word [_floats__pm+bx+8], 0
        add  di, 2
        cmp  di, 8
        jb  p8fs_mul_inner
        add  si, 2
        cmp  si, 8
        jb  p8fs_mul_outer
        ; its first bit is the top one or the one below that: then one place to the left
        test  byte [_floats__pm+15], 0x80
        jnz  p8fs_mul_top
        mov  bx, _floats__pm
        mov  cx, 8
        clc
p8fs_mul_left:
        rcl  word [bx], 1
        inc  bx
        inc  bx
        loop  p8fs_mul_left
        dec  word [_floats__ra+8]
p8fs_mul_top:
        ; the upper half are the digits; anything in the lower half stays as the lowest bit
        mov  ax, [_floats__pm+8]
        mov  [_floats__ra], ax
        mov  ax, [_floats__pm+10]
        mov  [_floats__ra+2], ax
        mov  ax, [_floats__pm+12]
        mov  [_floats__ra+4], ax
        mov  ax, [_floats__pm+14]
        mov  [_floats__ra+6], ax
        mov  ax, [_floats__pm]
        or  ax, [_floats__pm+2]
        or  ax, [_floats__pm+4]
        or  ax, [_floats__pm+6]
        jz  p8fs_mul_pack
        or  byte [_floats__ra], 1
p8fs_mul_pack:
        pop  di
        jmp  p8fs_pack
%endif

p8f_div:
%if p8f_mode == 2
        cmp  byte [_floats__has87], 0
        je  p8fs_div
%endif
%if p8f_mode != 1
        fwait
        fld  qword [di]
        fwait
        fdiv  qword [si]
        fwait
        fstp  qword [di]
        fwait
        ret
%endif
%if p8f_mode != 0
p8fs_div:
        push  di
        call  p8fs_unpack_both
        mov  al, [_floats__rb+10]
        xor  [_floats__ra+10], al
        cmp  word [_floats__ra+8], 0
        jne  p8fs_div_number
        pop  di
        jmp  p8fs_pack_zero
p8fs_div_number:
        cmp  word [_floats__rb+8], 0
        jne  p8fs_div_both
        ; by zero: infinity
        mov  word [_floats__ra+8], 0x07ff
        pop  di
        jmp  p8fs_pack_range
p8fs_div_both:
        mov  ax, [_floats__ra+8]
        sub  ax, [_floats__rb+8]
        add  ax, 1023
        mov  [_floats__ra+8], ax
        ; 64 bits of quotient, one at a time: what is left of ra (with a bit above it in DL) against rb
        xor  dl, dl
        call  p8fs_div_compare
        jnc  p8fs_div_start
        dec  word [_floats__ra+8]
        shl  word [_floats__ra], 1
        rcl  word [_floats__ra+2], 1
        rcl  word [_floats__ra+4], 1
        rcl  word [_floats__ra+6], 1
        rcl  dl, 1
p8fs_div_start:
        xor  ax, ax
        mov  [_floats__pm], ax
        mov  [_floats__pm+2], ax
        mov  [_floats__pm+4], ax
        mov  [_floats__pm+6], ax
        mov  cx, 64
p8fs_div_bit:
        shl  word [_floats__pm], 1
        rcl  word [_floats__pm+2], 1
        rcl  word [_floats__pm+4], 1
        rcl  word [_floats__pm+6], 1
        test  dl, dl
        jnz  p8fs_div_take
        call  p8fs_div_compare
        jc  p8fs_div_next
p8fs_div_take:
        mov  ax, [_floats__rb]
        sub  [_floats__ra], ax
        mov  ax, [_floats__rb+2]
        sbb  [_floats__ra+2], ax
        mov  ax, [_floats__rb+4]
        sbb  [_floats__ra+4], ax
        mov  ax, [_floats__rb+6]
        sbb  [_floats__ra+6], ax
        sbb  dl, 0
        or  byte [_floats__pm], 1
p8fs_div_next:
        shl  word [_floats__ra], 1
        rcl  word [_floats__ra+2], 1
        rcl  word [_floats__ra+4], 1
        rcl  word [_floats__ra+6], 1
        rcl  dl, 1
        loop  p8fs_div_bit
        ; (a rest stays as the lowest bit)
        mov  ax, [_floats__ra]
        or  ax, [_floats__ra+2]
        or  ax, [_floats__ra+4]
        or  ax, [_floats__ra+6]
        or  al, dl
        or  al, ah
        mov  ax, [_floats__pm]
        jz  p8fs_div_exact
        or  al, 1
p8fs_div_exact:
        mov  [_floats__ra], ax
        mov  ax, [_floats__pm+2]
        mov  [_floats__ra+2], ax
        mov  ax, [_floats__pm+4]
        mov  [_floats__ra+4], ax
        mov  ax, [_floats__pm+6]
        mov  [_floats__ra+6], ax
        pop  di
        jmp  p8fs_pack
        ; carry when ra's digits are less than rb's
p8fs_div_compare:
        mov  ax, [_floats__ra+6]
        cmp  ax, [_floats__rb+6]
        jne  p8fs_div_compared
        mov  ax, [_floats__ra+4]
        cmp  ax, [_floats__rb+4]
        jne  p8fs_div_compared
        mov  ax, [_floats__ra+2]
        cmp  ax, [_floats__rb+2]
        jne  p8fs_div_compared
        mov  ax, [_floats__ra]
        cmp  ax, [_floats__rb]
p8fs_div_compared:
        ret
%endif

        ; AL = 255, 0 or 1: the float at DI is less than, the same as, or more than the one at SI
p8f_cmp:
%if p8f_mode == 2
        cmp  byte [_floats__has87], 0
        je  p8fs_cmp
%endif
%if p8f_mode != 1
        fwait
        fld  qword [di]
        fwait
        fcomp  qword [si]
        fwait
        fstsw  [_floats__status]
        fwait
        mov  ah, [_floats__status+1]
        sahf
        mov  al, 0
        je  p8f_cmp_end
        mov  al, 1
        ja  p8f_cmp_end
        mov  al, 255
p8f_cmp_end:
        ret
%endif
%if p8f_mode != 0
p8fs_cmp:
        ; the signs first (a zero has none), then the rest as whole numbers from the top
        mov  bx, [di+6]
        mov  ax, bx
        and  ax, 0x7fff
        or  ax, [di+4]
        or  ax, [di+2]
        or  ax, [di]
        jnz  p8fs_cmp_first
        xor  bx, bx
p8fs_cmp_first:
        mov  dx, [si+6]
        mov  ax, dx
        and  ax, 0x7fff
        or  ax, [si+4]
        or  ax, [si+2]
        or  ax, [si]
        jnz  p8fs_cmp_second
        xor  dx, dx
p8fs_cmp_second:
        mov  ax, bx
        xor  ax, dx
        jns  p8fs_cmp_same_sign
        mov  al, 1
        test  bx, bx
        jns  p8fs_cmp_end
        mov  al, 255
p8fs_cmp_end:
        ret
p8fs_cmp_same_sign:
        mov  cx, bx
        and  bx, 0x7fff
        and  dx, 0x7fff
        cmp  bx, dx
        jne  p8fs_cmp_differ
        mov  ax, [di+4]
        cmp  ax, [si+4]
        jne  p8fs_cmp_differ
        mov  ax, [di+2]
        cmp  ax, [si+2]
        jne  p8fs_cmp_differ
        mov  ax, [di]
        cmp  ax, [si]
        jne  p8fs_cmp_differ
        xor  al, al
        ret
p8fs_cmp_differ:
        mov  al, 1
        ja  p8fs_cmp_sign
        mov  al, 255
p8fs_cmp_sign:
        test  cx, cx
        jns  p8fs_cmp_end
        neg  al
        ret
%endif

        ; the float at DI = the long in DX and AX
p8f_from_long:
%if p8f_mode == 2
        cmp  byte [_floats__has87], 0
        je  p8fs_from_long
%endif
%if p8f_mode != 1
        mov  [_floats__whole], ax
        mov  [_floats__whole+2], dx
        fwait
        fild  dword [_floats__whole]
        fwait
        fstp  qword [di]
        fwait
        ret
%endif
%if p8f_mode != 0
p8fs_from_long:
        mov  bl, dh
        and  bl, 0x80
        mov  [_floats__ra+10], bl
        jz  p8fs_from_long_positive
        not  dx
        neg  ax
        sbb  dx, -1
p8fs_from_long_positive:
        mov  [_floats__ra+6], dx
        mov  [_floats__ra+4], ax
        xor  ax, ax
        mov  [_floats__ra+2], ax
        mov  [_floats__ra], ax
        mov  word [_floats__ra+8], 1023+31
        call  p8fs_normalize
        jmp  p8fs_pack
%endif

        ; DX and AX = the float at SI as a long, towards zero
p8f_to_long:
%if p8f_mode == 2
        cmp  byte [_floats__has87], 0
        je  p8fs_to_long
%endif
%if p8f_mode != 1
        fwait
        fnstcw  [_floats__control2]
        fwait
        mov  ax, [_floats__control2]
        or  ah, 0x0c
        mov  [_floats__status], ax
        fldcw  [_floats__status]
        fwait
        fld  qword [si]
        fwait
        fistp  dword [_floats__whole]
        fwait
        fldcw  [_floats__control2]
        fwait
        mov  ax, [_floats__whole]
        mov  dx, [_floats__whole+2]
        ret
%endif
%if p8f_mode != 0
p8fs_to_long:
        mov  bx, _floats__ra
        call  p8fs_unpack
        mov  cx, 1023+31
        sub  cx, [_floats__ra+8]
        jns  p8fs_to_long_fits
        ; too large for a long: what the 8087 gives then
        xor  ax, ax
        mov  dx, 0x8000
        ret
p8fs_to_long_fits:
        mov  dx, [_floats__ra+6]
        mov  ax, [_floats__ra+4]
        cmp  cx, 32
        jb  p8fs_to_long_shift
        xor  ax, ax
        xor  dx, dx
        ret
p8fs_to_long_shift:
        jcxz  p8fs_to_long_sign
p8fs_to_long_bit:
        shr  dx, 1
        rcr  ax, 1
        loop  p8fs_to_long_bit
p8fs_to_long_sign:
        test  byte [_floats__ra+10], 0x80
        jz  p8fs_to_long_end
        not  dx
        neg  ax
        sbb  dx, -1
p8fs_to_long_end:
        ret
%endif

        ; the float at DI = its square root (0 for a negative one)
p8f_sqrt:
%if p8f_mode == 2
        cmp  byte [_floats__has87], 0
        je  p8fs_sqrt
%endif
%if p8f_mode != 1
        fwait
        fld  qword [di]
        fwait
        fsqrt
        fwait
        fstp  qword [di]
        fwait
        ret
%endif
%if p8f_mode != 0
p8fs_sqrt:
        mov  ax, [di+6]
        test  ax, ax
        js  p8fs_sqrt_zero
        and  ax, 0x7ff0
        jnz  p8fs_sqrt_number
p8fs_sqrt_zero:
        jmp  p8fs_pack_zero
p8fs_sqrt_number:
        ; a first guess with half the power of 2, then six times the mean of it and the number by it
        push  di
        mov  si, di
        mov  di, _floats__fa
        movsw
        movsw
        movsw
        movsw
        mov  si, _floats__fa
        mov  di, _floats__fx
        movsw
        movsw
        movsw
        movsw
        mov  ax, [_floats__fx+6]
        mov  dx, ax
        and  dx, 0x000f
        mov  cl, 4
        shr  ax, cl
        sub  ax, 1023
        sar  ax, 1
        add  ax, 1023
        shl  ax, cl
        or  ax, dx
        mov  [_floats__fx+6], ax
        mov  cx, 6
p8fs_sqrt_step:
        push  cx
        mov  si, _floats__fa
        mov  di, _floats__ft
        movsw
        movsw
        movsw
        movsw
        mov  di, _floats__ft
        mov  si, _floats__fx
        call  p8fs_div
        mov  di, _floats__fx
        mov  si, _floats__ft
        call  p8fs_add
        sub  word [_floats__fx+6], 0x0010
        pop  cx
        loop  p8fs_sqrt_step
        pop  di
        mov  si, _floats__fx
        movsw
        movsw
        movsw
        movsw
        ret
%endif

        ; the float at DI = the greatest whole number that is not above it
p8f_floor:
        mov  ax, [di+6]
        mov  bx, ax
        and  ax, 0x7ff0
        mov  cl, 4
        shr  ax, cl
        sub  ax, 1023
        jns  p8f_floor_large
        ; below 1: 0, or -1 for a negative number that is not zero
        and  bx, 0x7fff
        or  bx, [di+4]
        or  bx, [di+2]
        or  bx, [di]
        mov  bl, [di+7]
        mov  word [di], 0
        mov  word [di+2], 0
        mov  word [di+4], 0
        mov  word [di+6], 0
        jz  p8f_floor_end
        test  bl, 0x80
        jz  p8f_floor_end
        mov  word [di+6], 0xbff0
p8f_floor_end:
        ret
p8f_floor_large:
        cmp  ax, 52
        jae  p8f_floor_end
        ; the bits after the point go; DX notes whether there were any
        mov  cx, 52
        sub  cx, ax
        xor  dx, dx
        mov  si, di
p8f_floor_word:
        cmp  cx, 16
        jb  p8f_floor_bits
        or  dx, [si]
        mov  word [si], 0
        add  si, 2
        sub  cx, 16
        jmp  p8f_floor_word
p8f_floor_bits:
        mov  ax, 1
        shl  ax, cl
        dec  ax
        mov  bx, [si]
        and  bx, ax
        or  dx, bx
        not  ax
        and  [si], ax
        test  dx, dx
        jz  p8f_floor_end
        test  byte [di+7], 0x80
        jz  p8f_floor_end
        mov  si, _floats__one
        jmp  p8f_sub

        ; the least whole number that is not below it: down, with the sign turned over
p8f_ceil:
        xor  byte [di+7], 0x80
        push  di
        call  p8f_floor
        pop  di
        mov  ax, [di+6]
        and  ax, 0x7fff
        or  ax, [di+4]
        or  ax, [di+2]
        or  ax, [di]
        jz  p8f_ceil_end
        xor  byte [di+7], 0x80
p8f_ceil_end:
        ret

        ; the nearest whole number: a half more, and down
p8f_round:
        push  di
        mov  si, _floats__half
        call  p8f_add
        pop  di
        jmp  p8f_floor
    }}
}
