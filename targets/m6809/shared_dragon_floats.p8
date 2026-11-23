; Prog8 definitions for floating point handling on the Dragon (the dragon32 and
; dragon64 targets of p8p8; the Color Computers' module with the Dragon ROM's addresses): the floats of the BASIC in its ROM, five bytes in Microsoft's
; format with about nine digits, and that ROM's routines for them (where they are, the
; target file says).  The square root of a float is the sqrt builtin function, as on the
; other targets.
; A float prints and converts to a string as BASIC prints one (tostr() and print()),
; without the blank that BASIC puts before a number that is not negative.
; What the ROM takes as an error ends the program with BASIC's message: a division by
; zero (?/0 ERROR), a number that is too large (?OV ERROR), the logarithm or the square
; root of a negative number (?FC ERROR).
; rnd() takes its random bits from math.rndw().

%import math
%option enable_floats, ignore_unused

sys {
    %option merge       ; add some constants to sys

    const float  MAX_FLOAT = 1.7014118345e+38
    const float  MIN_FLOAT = -1.7014118345e+38
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

        const float  π         = 3.141592653589793
        const float  PI        = π
        const float  TWOPI     = 2*π
        const float  E         = 2.718281828459045
        const float  EPSILON   = 2.938735878e-39

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
    ; ---- converts the floating point value to a string, as BASIC prints it (without the blank before it)
    str @shared buffer = " " * 31
    %asm {{
        ldx  #_floats__tostr__value
        jsr  $93bf
        jsr  $9587
        ldx  #$03da
        lda  ,x
        cmpa  #32
        bne  p8flt_tostr_copy
        leax  1,x
        p8flt_tostr_copy:
        ldu  #_floats__tostr__buffer
        p8flt_tostr_next:
        lda  ,x+
        sta  ,u+
        bne  p8flt_tostr_next
    }}
    return buffer
}

sub parse(str value) -> float {
    ; ---- the number that a text says, as BASIC reads one; it stops at what is not part of a number.
    ;      Blanks are left out, and an exponent's e may be a small letter.
    float @shared result
    str @shared buffer = " " * 40
    ubyte length = 0
    ubyte index = 0
    ubyte character
    repeat {
        character = value[index]
        if character == 0 or length == 40
            break
        if character != ' ' {
            if character == 'e'
                character = 'E'
            if character not in "+-0123456789.E"
                break
            buffer[length] = character
            length++
        }
        index++
        if index == 0
            break
    }
    buffer[length] = 0
    %asm {{
        ldx  $a6
        pshs  x
        ldx  #_floats__parse__buffer
        stx  $a6
        jsr  >$00a5
        jsr  $94bd
        puls  x
        stx  $a6
        ldx  #_floats__parse__result
        jsr  $93e0
    }}
    return result
}

sub rnd() -> float {
    ; -- a random float from 0.0 up to but not including 1.0, from a math.rndw() value (a 32-bit float can't hold more bits)
    return (math.rndw() as float) / 65536.0
}

sub rndseed(float seed) {
    ; -- seeds the random generator of rnd(), which is the one of math.rndw() and math.rnd(), with the bits of the seed
    long bits = peekl(&seed)
    math.rndseed(lsw(bits), msw(bits))
}


sub pow(float value, float power) -> float {
    %ir {{
        loadm.f fr0.f,[floats.pow.value]
        loadm.f fr1.f,[floats.pow.power]
        fpow.f fr0.f,fr1.f
        returnr.f fr0.f
    }}
}

sub exp(float value) -> float {
    ; -- e to the power of the value
    return pow(E, value)
}

sub sin(float angle) -> float {
    %ir {{
        loadm.f fr0.f,[floats.sin.angle]
        fsin.f fr1.f,fr0.f
        returnr.f fr1.f
    }}
}

sub cos(float angle) -> float {
    %ir {{
        loadm.f fr0.f,[floats.cos.angle]
        fcos.f fr1.f,fr0.f
        returnr.f fr1.f
    }}
}

sub tan(float value) -> float {
    %ir {{
        loadm.f fr0.f,[floats.tan.value]
        ftan.f fr1.f,fr0.f
        returnr.f fr1.f
    }}
}

sub atan(float value) -> float {
    %ir {{
        loadm.f fr0.f,[floats.atan.value]
        fatan.f fr1.f,fr0.f
        returnr.f fr1.f
    }}
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
    %ir {{
        loadm.f fr0.f,[floats.ln.value]
        fln.f fr1.f,fr0.f
        returnr.f fr1.f
    }}
}

sub log2(float value) -> float {
    %ir {{
        loadm.f fr0.f,[floats.log2.value]
        flog.f fr1.f,fr0.f
        returnr.f fr1.f
    }}
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
    %ir {{
        loadm.f fr0.f,[floats.round.value]
        fround.f fr1.f,fr0.f
        returnr.f fr1.f
    }}
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

}
