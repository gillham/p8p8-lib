%import shared_m68k_math

math {
    %option no_symbol_prefixing, ignore_unused

    ; (the names that programs for a machine with its code in ROM use: here they are
    ;  the plain routines, so that such a program compiles as it is)
    alias rndseed_rom = math.rndseed
    alias rnd_rom = math.rnd
    alias rndw_rom = math.rndw
    alias randrange_rom = math.randrange
    alias randrangew_rom = math.randrangew
}
