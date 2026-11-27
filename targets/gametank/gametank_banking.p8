; The cartridge's ROM bank ($8000-$bfff), the way the GameTank SDK does it.
;
; Prog8 version of the GameTank SDK's src/gt/banking.c, with the names of the
; C SDK.  The bank numbers are those of gametank.rombank(): 128-255 are the
; banks of a ROM cartridge, and 255 is also the fixed bank at $c000.
;
;   gametank.push_rom_bank()            ; remember the bank that is there now
;   gametank.change_rom_bank(130)       ; work in another one
;   ...
;   gametank.pop_rom_bank()             ; and back
;
; push_rom_bank() and pop_rom_bank() keep the banks in their own stack of 8, so
; unlike gametank.push_rombank() and pop_rombank() the two calls do not have to
; be in the same subroutine.  A ninth push overwrites the oldest one.

%import gametank

gametank {
%option merge

    const ubyte BANK_STACK_SIZE = 8         ; must be a power of 2
    const ubyte BANK_WRAP_MASK = BANK_STACK_SIZE-1

    &ubyte romBankMirror = $01              ; the bank that is there now (cartbank sets it)
    ubyte[BANK_STACK_SIZE] romBankStack
    ubyte romBankStackIdx

    ; go to a bank, unless it is there already
    sub change_rom_bank(ubyte banknum) {
        if banknum != romBankMirror
            rombank(banknum)
    }

    sub push_rom_bank() {
        romBankStackIdx = (romBankStackIdx + 1) & BANK_WRAP_MASK
        romBankStack[romBankStackIdx] = romBankMirror
    }

    sub pop_rom_bank() {
        change_rom_bank(romBankStack[romBankStackIdx])
        if romBankStackIdx == 0
            romBankStackIdx = BANK_STACK_SIZE
        romBankStackIdx--
    }
}
