; Floating point for a 68000 machine without an FPU (p8p8: the Amiga 500, the Atari ST,
; and the other 68000 targets with -floats soft).  This file is what "%import floats"
; reads there.
;
; A float is an IEEE single, as it is with an FPU.  The arithmetic is the routines of
; m68k_softfloat.asm, which the code generator calls; the functions here are written
; with it, in Prog8.  They are right to six or seven digits: every step rounds to a
; single, where an FPU works with more digits in between.
%option enable_floats, ignore_unused
%import textio

sys {
    %option merge, ignore_unused
    const float MAX_FLOAT = 3.40282346e+38
    const float MIN_FLOAT = -3.40282346e+38
}

txt {
    %option merge, ignore_unused
    alias print_f = floats.print
}

math {
    %option merge, ignore_unused
    alias lerpf = floats.lerp
    alias lerpf_fast = floats.lerp_fast
}

floats {
    %option no_symbol_prefixing, ignore_unused

    %asminclude "library:m68k_softfloat.asm"

    const float π = 3.141592653589793
    const float PI = π
    const float TWOPI = 2*π
    const float E = 2.718281828459045
    const float EPSILON = 1.401298464e-45   ; smallest positive single-precision float (2^-149)

    const float HALFPI = π / 2
    const float LN2 = 0.6931471805599453

    str str_buf = "?" * 31
    long rnd_state = 0

    sub print(float value) {
        txt.print(tostr(value))
    }

    sub tostr(float value) -> str {
        ; -- the number as text: what is before the point, and six digits after it
        ubyte at = 0
        long bits = peekl(&value)
        if bits & $7fffffff == 0 {
            str_buf[0] = '0'
            str_buf[1] = '.'
            str_buf[2] = '0'
            str_buf[3] = 0
            return str_buf
        }
        if bits < 0 {
            str_buf[0] = '-'
            at = 1
            value = -value
        }
        if bits & $7f800000 == $7f800000 {
            if bits & $007fffff != 0 {
                str_buf[0] = 'N'
                str_buf[1] = 'a'
                str_buf[2] = 'N'
                str_buf[3] = 0
                return str_buf
            }
            str_buf[at] = 'I'
            str_buf[at + 1] = 'n'
            str_buf[at + 2] = 'f'
            str_buf[at + 3] = 0
            return str_buf
        }
        long whole = value as long
        float fraction = value - (whole as float)
        ubyte[10] digits
        ubyte count = 0
        repeat {
            digits[count] = (whole % 10) as ubyte
            whole /= 10
            count++
            if whole == 0
                break
        }
        while count != 0 {
            count--
            str_buf[at] = '0' + digits[count]
            at++
        }
        str_buf[at] = '.'
        at++
        repeat 6 {
            fraction *= 10.0
            ubyte digit = fraction as ubyte
            str_buf[at] = '0' + digit
            at++
            fraction -= digit as float
        }
        str_buf[at] = 0
        return str_buf
    }

    sub parse(str value) -> float {
        ; -- the number that a text has: digits, a point, an exponent after e or E
        float result = 0.0
        bool negative = false
        ubyte at = 0
        while value[at] == ' '
            at++
        if value[at] == '+'
            at++
        else if value[at] == '-' {
            negative = true
            at++
        }
        while value[at] >= '0' and value[at] <= '9' {
            result = result * 10.0 + ((value[at] - '0') as float)
            at++
        }
        if value[at] == '.' {
            at++
            float place = 10.0
            while value[at] >= '0' and value[at] <= '9' {
                result += ((value[at] - '0') as float) / place
                place *= 10.0
                at++
            }
        }
        if value[at] == 'e' or value[at] == 'E' {
            at++
            bool down = false
            if value[at] == '+'
                at++
            else if value[at] == '-' {
                down = true
                at++
            }
            ubyte exponent = 0
            while value[at] >= '0' and value[at] <= '9' and exponent < 100 {
                exponent = exponent * 10 + (value[at] - '0')
                at++
            }
            float scale = 1.0
            repeat exponent
                scale *= 10.0
            if down
                result /= scale
            else
                result *= scale
        }
        if negative
            return -result
        return result
    }

    sub floor(float value) -> float {
        ; (from 2^23 on a single has no digits after the point)
        if abs(value) >= 8388608.0
            return value
        float whole = (value as long) as float
        if whole > value
            whole -= 1.0
        return whole
    }

    sub ceil(float value) -> float {
        if abs(value) >= 8388608.0
            return value
        float whole = (value as long) as float
        if whole < value
            whole += 1.0
        return whole
    }

    sub round(float value) -> float {
        ; -- to the nearest whole number; from halfway between two, to the even one (as an FPU has it)
        float whole = floor(value + 0.5)
        if whole - value == 0.5 and (whole as long) & 1 != 0
            whole -= 1.0
        return whole
    }

    sub sin(float angle) -> float {
        return sine(angle, 0)
    }

    sub cos(float angle) -> float {
        ; (the sine a quarter circle further on)
        return sine(angle, 1)
    }

    sub sine(float angle, ubyte ahead) -> float {
        ; -- the angle is brought to within an eighth of a circle of a multiple of a quarter;
        ;    there the series of the sine or of the cosine is short
        float quarters = floor(angle / HALFPI + 0.5)
        ; (a quarter circle in two parts, the first with few digits: the product with it
        ;  is exact, and so the rest keeps its digits for a large angle too)
        float r = (angle - quarters * 1.5703125) - quarters * 4.838267948966e-4
        ; (which quarter: the number modulo 4, also for a negative one)
        float fours = floor(quarters / 4.0)
        ubyte quadrant = ((quarters - fours * 4.0) as ubyte) + ahead
        float r2 = r * r
        float result
        if quadrant & 1 == 0
            result = r * (1.0 - r2 / 6.0 * (1.0 - r2 / 20.0 * (1.0 - r2 / 42.0 * (1.0 - r2 / 72.0))))
        else
            result = 1.0 - r2 / 2.0 * (1.0 - r2 / 12.0 * (1.0 - r2 / 30.0 * (1.0 - r2 / 56.0 * (1.0 - r2 / 90.0))))
        if quadrant & 2 != 0
            return -result
        return result
    }

    sub tan(float value) -> float {
        return sin(value) / cos(value)
    }

    sub atan(float value) -> float {
        if value < 0.0
            return -atan_positive(-value)
        return atan_positive(value)
    }

    sub atan_positive(float value) -> float {
        if value > 1.0
            return HALFPI - atan_small(1.0 / value)
        return atan_small(value)
    }

    sub atan_small(float value) -> float {
        ; -- of a number from 0 to 1
        float add = 0.0
        if value > 0.4142135623730951 {
            ; (the tangent of an eighth of a half circle: from there on it is counted from a quarter)
            add = π / 4
            value = (value - 1.0) / (value + 1.0)
        }
        float v2 = value * value
        return add + value * (1.0 - v2 * (1.0 / 3.0 - v2 * (1.0 / 5.0 - v2 * (1.0 / 7.0 - v2 * (1.0 / 9.0 - v2 * (1.0 / 11.0 - v2 / 13.0))))))
    }

    sub ln(float value) -> float {
        ; -- the number is 2 to its exponent times a number near 1, whose logarithm is a short series
        if value <= 0.0
            return 0.0
        long bits = peekl(&value)
        long exponent = ((bits >> 23) & 255) - 127
        pokel(&value, (bits & $007fffff) | $3f800000)
        if value > 1.4142135623730951 {
            value /= 2.0
            exponent++
        }
        float s = (value - 1.0) / (value + 1.0)
        float s2 = s * s
        return (exponent as float) * LN2 + 2.0 * s * (1.0 + s2 * (1.0 / 3.0 + s2 * (1.0 / 5.0 + s2 * (1.0 / 7.0 + s2 / 9.0))))
    }

    sub log2(float value) -> float {
        return ln(value) / LN2
    }

    sub exp(float value) -> float {
        ; -- e to the power: a power of 2 times e to a small rest
        if value > 88.7
            return sys.MAX_FLOAT
        if value < -87.0
            return 0.0
        float twos = floor(value / LN2 + 0.5)
        ; (the logarithm of 2 in two parts, as the quarter circle in sin)
        float r = (value - twos * 0.693359375) + twos * 2.12194440054690583e-4
        float result = 1.0 + r * (1.0 + r / 2.0 * (1.0 + r / 3.0 * (1.0 + r / 4.0 * (1.0 + r / 5.0 * (1.0 + r / 6.0 * (1.0 + r / 7.0))))))
        long bits = peekl(&result) + ((twos as long) << 23)
        pokel(&result, bits)
        return result
    }

    sub pow(float value, float power) -> float {
        if power == 0.0
            return 1.0
        if value == 0.0
            return 0.0
        if value < 0.0 {
            ; (a negative number to a whole power)
            float amount = exp(power * ln(-value))
            long whole = power as long
            if whole & 1 != 0
                return -amount
            return amount
        }
        return exp(power * ln(value))
    }

    sub atan2(float y, float x) -> float {
        float atn = atan(y / x)
        if x < 0
            atn += π
        if atn < 0
            atn += 2*π
        return atn
    }

    sub secant(float value) -> float { return 1.0 / cos(value) }
    sub csc(float value) -> float { return 1.0 / sin(value) }
    sub cot(float value) -> float { return 1.0 / tan(value) }

    sub rad(float angle) -> float {
        return angle * PI / 180.0
    }

    sub deg(float angle) -> float {
        return angle * 180.0 / PI
    }

    sub minf(float f1, float f2) -> float {
        if f1 < f2
            return f1
        return f2
    }

    sub maxf(float f1, float f2) -> float {
        if f1 > f2
            return f1
        return f2
    }

    sub clampf(float value, float minimum, float maximum) -> float {
        if value < minimum
            value = minimum
        if value < maximum
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
        return (1 - t) * v0 + t * v1
    }

    sub lerp_fast(float v0, float v1, float t) -> float {
        return v0 + t * (v1 - v0)
    }

    sub interpolate(float v, float inputMin, float inputMax, float outputMin, float outputMax) -> float {
        if outputMin == outputMax
            return outputMin
        v = (v - inputMin) / (inputMax - inputMin)
        return v * (outputMax - outputMin) + outputMin
    }

    sub rndseed(float seed) {
        rnd_state = peekl(&seed)
    }

    sub rnd() -> float {
        ; -- a number from 0 up to, but not, 1
        rnd_state = rnd_state * 1103515245 + 12345
        return ((rnd_state & $ffffff) as float) / 16777216.0
    }
}
