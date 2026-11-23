; Prog8 definitions for the Text I/O console routines on the bare 6809 of usim09batch (the sim6809 target of p8p8).
; The stream console of the llvm16 textio: text goes out as it comes, and the cursor is
; moved with ANSI sequences.  The keys come through the machine's own routines (the
; target file's key_poll), which here reads the simulator's serial port.

%import shared_m6809_stream_textio

txt {
%option no_symbol_prefixing, ignore_unused

    ; the codes of getkey() and waitkey() for the keys that differ between the machines (a key that a machine lacks gets
    ; one that no key gives: 248 up, 249 down, 250 left, 251 right, 252 escape, 253 backspace, 254 break)
    const ubyte KEY_UP = 5              ; Ctrl-E, as in WordStar
    const ubyte KEY_DOWN = 24           ; Ctrl-X
    const ubyte KEY_LEFT = 19           ; Ctrl-S
    const ubyte KEY_RIGHT = 4           ; Ctrl-D
    const ubyte KEY_ENTER = 13
    const ubyte KEY_ESC = 27
    const ubyte KEY_BACKSPACE = 8
    const ubyte KEY_BREAK = 3           ; Ctrl-C

sub getkey() -> ubyte {
    ; ---- the key pressed, or 0 when there is none, without waiting
    %ir {{
        syscall 217 (): r99100.b
        returnr.b r99100.b
    }}
}

sub waitkey() -> ubyte {
    ; ---- wait for the next key and return it; it is not shown
    %ir {{
        syscall 218 (): r99100.b
        returnr.b r99100.b
    }}
}
}
