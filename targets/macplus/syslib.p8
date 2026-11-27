; Prog8 definitions for a 68000 Macintosh (the macplus target of p8p8): an application
; for a Macintosh Plus or later with System 4.1 or later, its text in a window.

%option no_symbol_prefixing, ignore_unused
%import shared_m68k_memory_routines

macos {
    %option force_output

    ; ---- the text window ----
    ; A Macintosh has no text screen: the program opens a window and draws its text
    ; there, in Monaco 9, which has every character 6 points wide and 11 high.  What
    ; is on the screen is kept here too (screen, attributes), because a window has to
    ; be drawn again when something that covered it goes away.

    const ubyte COLUMNS = 80
    const ubyte ROWS = 25
    const uword CELLS = 2000
    const word CELL_WIDTH = 6
    const word CELL_HEIGHT = 11
    const word LEFT = 2                 ; where the text starts in the window
    const word TOP = 1
    const word ASCENT = 9               ; from a row's top to the line that its letters stand on
    const word WIDTH = 484              ; the window's inside
    const word HEIGHT = 277
    const long STACK_SIZE = 16384       ; how much stack the program has (see p8_sys_startup.init_system)

    long window                     ; the window (a WindowPtr)
    long region                     ; for ScrollRect to say what it could not move
    long found_window               ; the window that a click was in
    uword[4] rect                   ; a rectangle for the calls: top, left, bottom, right
    uword[4] limits                 ; where the window may be dragged to
    ubyte column                    ; where the next character goes
    ubyte row
    bool reverse                    ; white on black
    ubyte[CELLS] screen             ; the characters that are on the screen,
    ubyte[CELLS] attributes         ;   and which of them are white on black
    bool quit_at_end                ; true: the program's end closes the window at once (see finish)

    ; ---- events ----
    uword[8] event                  ; what (0), message (2), when (6), where (10), modifiers (14)
    ubyte[32] keys                  ; the keys that were typed and not read yet
    ubyte key_in
    ubyte key_out
    bool clicked                    ; the mouse was clicked in the window
    long polled                     ; when the events were last looked at

    ; ---- the file that the text is copied to ----
    ; When a file named "p8p8.out" is beside the application, everything that is
    ; written as text goes there too (a line ends with a carriage return, as a
    ; Macintosh's text files have it), and the program ends without waiting.  It is how
    ; a program is run with nobody there (p8p8's tests do).
    str echo_name = "\x08p8p8.out"
    bool unattended
    uword echo_ref
    uword echo_length
    ubyte[256] echo_buffer

    ; the File Manager's calls take a parameter block: its result at 16, the name's
    ; address at 18, the volume at 22, the file's reference at 24, the permission at
    ; 27, a long of many uses at 28, the buffer at 32, how much is asked for at 36 and
    ; how much it was at 40, the way to position at 44 and the position at 46.
    uword[40] pb

    const ubyte F_OPEN = 0
    const ubyte F_CLOSE = 1
    const ubyte F_READ = 2
    const ubyte F_WRITE = 3
    const ubyte F_CREATE = 4
    const ubyte F_DELETE = 5
    const ubyte F_SETEOF = 6
    const ubyte F_FLUSHVOL = 7
    const ubyte F_GETEOF = 8
    const ubyte F_SETFPOS = 9
    const ubyte F_GETFINFO = 10
    const ubyte F_SETFINFO = 11
    const ubyte F_RENAME = 12
    const ubyte F_GETFPOS = 13
    const ubyte F_GETVOL = 14
    const ubyte F_OPENRF = 15

    asmsub file_call(ubyte function @D0) -> word @D0 {
        ; -- one of the File Manager's calls (the F_ numbers) with the parameter block
        ;    macos.pb; the result is 0 or the system's error (a negative number)
        %asm {{
            movem.l d1-d2/a0-a1,-(sp)
            lea     macos.pb,a0
            and.w   #$00ff,d0
            lsl.w   #2,d0
            jsr     .calls(pc,d0.w)
            ext.l   d0
            movem.l (sp)+,d1-d2/a0-a1
            rts
.calls:
            dc.w    $a000,$4e75             ; _Open
            dc.w    $a001,$4e75             ; _Close
            dc.w    $a002,$4e75             ; _Read
            dc.w    $a003,$4e75             ; _Write
            dc.w    $a008,$4e75             ; _Create
            dc.w    $a009,$4e75             ; _Delete
            dc.w    $a012,$4e75             ; _SetEOF
            dc.w    $a013,$4e75             ; _FlushVol
            dc.w    $a011,$4e75             ; _GetEOF
            dc.w    $a044,$4e75             ; _SetFPos
            dc.w    $a00c,$4e75             ; _GetFileInfo
            dc.w    $a00d,$4e75             ; _SetFileInfo
            dc.w    $a00b,$4e75             ; _Rename
            dc.w    $a018,$4e75             ; _GetFPos
            dc.w    $a014,$4e75             ; _GetVol
            dc.w    $a00a,$4e75             ; _OpenRF
            ; !notreached!
        }}
    }

    sub clear_pb() {
        ubyte k
        for k in 0 to 39
            pb[k] = 0
    }

    sub echo_open() {
        clear_pb()
        pokel(&pb + 18, &echo_name)
        pb[13] = 2                          ; to write
        if file_call(F_OPEN) != 0
            return
        echo_ref = pb[12]
        void file_call(F_SETEOF)            ; (to the long at 28, which is 0)
        echo_length = 0
        unattended = true
    }

    sub echo(ubyte char) {
        if char == '\n'
            char = 13
        echo_buffer[lsb(echo_length)] = char
        echo_length++
        if echo_length == 256
            echo_flush()
    }

    sub echo_flush() {
        if echo_length == 0
            return
        pb[12] = echo_ref
        pokel(&pb + 32, &echo_buffer)
        pokel(&pb + 36, echo_length)
        pb[22] = 0                          ; after what was written before
        pokel(&pb + 46, 0)
        void file_call(F_WRITE)
        echo_length = 0
    }

    sub echo_close() {
        if not unattended
            return
        echo_flush()
        pb[12] = echo_ref
        void file_call(F_CLOSE)
        clear_pb()
        void file_call(F_FLUSHVOL)          ; (the volume that the application is on)
        unattended = false
    }

    ; ---- the Toolbox's calls: they change d0-d2 and a0-a1, and Prog8 wants d2 kept ----

    asmsub move_to(word h @D0, word v @D1) {
        %asm {{
            movem.l d2/a0-a1,-(sp)
            move.w  d0,-(sp)
            move.w  d1,-(sp)
            dc.w    $a893                   ; _MoveTo
            movem.l (sp)+,d2/a0-a1
            rts
        }}
    }

    asmsub draw_char(ubyte char @D0) {
        %asm {{
            movem.l d1-d2/a0-a1,-(sp)
            and.w   #$00ff,d0
            move.w  d0,-(sp)
            dc.w    $a883                   ; _DrawChar
            movem.l (sp)+,d1-d2/a0-a1
            rts
        }}
    }

    asmsub draw_text(pointer text @A0, uword count @D0) {
        %asm {{
            movem.l d1-d2/a1,-(sp)
            move.l  a0,-(sp)
            clr.w   -(sp)
            move.w  d0,-(sp)
            dc.w    $a885                   ; _DrawText
            movem.l (sp)+,d1-d2/a1
            rts
        }}
    }

    asmsub text_mode(uword mode @D0) {
        ; -- 0: black on white, 4: white on black
        %asm {{
            movem.l d1-d2/a0-a1,-(sp)
            move.w  d0,-(sp)
            dc.w    $a889                   ; _TextMode
            movem.l (sp)+,d1-d2/a0-a1
            rts
        }}
    }

    asmsub scroll_rect(word lines @D0) {
        ; -- what is in macos.rect moves up by so many rows of text
        %asm {{
            movem.l d1-d2/a0-a1,-(sp)
            pea     macos.rect
            clr.w   -(sp)
            muls    #macos.CELL_HEIGHT,d0
            neg.w   d0
            move.w  d0,-(sp)
            move.l  macos.region,-(sp)
            dc.w    $a8ef                   ; _ScrollRect
            movem.l (sp)+,d1-d2/a0-a1
            rts
        }}
    }

    asmsub erase_rect() {
        %asm {{
            movem.l d0-d2/a0-a1,-(sp)
            pea     macos.rect
            dc.w    $a8a3                   ; _EraseRect
            movem.l (sp)+,d0-d2/a0-a1
            rts
        }}
    }

    asmsub invert_rect() {
        %asm {{
            movem.l d0-d2/a0-a1,-(sp)
            pea     macos.rect
            dc.w    $a8a4                   ; _InvertRect
            movem.l (sp)+,d0-d2/a0-a1
            rts
        }}
    }

    asmsub next_event() -> bool @D0 {
        ; -- is there an event?  It is in macos.event then.  (Desk accessories get their
        ;    time here too.)
        %asm {{
            movem.l d1-d2/a0-a1,-(sp)
            dc.w    $a9b4                   ; _SystemTask
            clr.w   -(sp)
            move.w  #-1,-(sp)
            pea     macos.event
            dc.w    $a970                   ; _GetNextEvent
            moveq   #0,d0
            move.b  (sp)+,d0
            movem.l (sp)+,d1-d2/a0-a1
            rts
        }}
    }

    asmsub find_window() -> word @D0 {
        ; -- where the event's click was: 1 in the menu bar, 2 in a desk accessory's
        ;    window, 3 inside a window, 4 in a window's title bar; the window is in
        ;    macos.found_window
        %asm {{
            movem.l d1-d2/a0-a1,-(sp)
            clr.w   -(sp)
            move.l  macos.event+10,-(sp)
            pea     macos.found_window
            dc.w    $a92c                   ; _FindWindow
            move.w  (sp)+,d0
            ext.l   d0
            movem.l (sp)+,d1-d2/a0-a1
            rts
        }}
    }

    asmsub system_click() {
        %asm {{
            movem.l d0-d2/a0-a1,-(sp)
            pea     macos.event
            move.l  macos.found_window,-(sp)
            dc.w    $a9b3                   ; _SystemClick
            movem.l (sp)+,d0-d2/a0-a1
            rts
        }}
    }

    asmsub drag_window() {
        %asm {{
            movem.l d0-d2/a0-a1,-(sp)
            move.l  macos.found_window,-(sp)
            move.l  macos.event+10,-(sp)
            pea     macos.limits
            dc.w    $a925                   ; _DragWindow
            movem.l (sp)+,d0-d2/a0-a1
            rts
        }}
    }

    asmsub begin_update() {
        %asm {{
            movem.l d0-d2/a0-a1,-(sp)
            move.l  macos.window,-(sp)
            dc.w    $a922                   ; _BeginUpdate
            movem.l (sp)+,d0-d2/a0-a1
            rts
        }}
    }

    asmsub end_update() {
        %asm {{
            movem.l d0-d2/a0-a1,-(sp)
            move.l  macos.window,-(sp)
            dc.w    $a923                   ; _EndUpdate
            movem.l (sp)+,d0-d2/a0-a1
            rts
        }}
    }

    asmsub set_title(pointer title @A0) {
        ; -- the window's title: a string with its length in its first byte
        %asm {{
            movem.l d0-d2/a0-a1,-(sp)
            move.l  macos.window,-(sp)
            move.l  a0,-(sp)
            dc.w    $a91a                   ; _SetWTitle
            movem.l (sp)+,d0-d2/a0-a1
            rts
        }}
    }

    asmsub beep() {
        %asm {{
            movem.l d0-d2/a0-a1,-(sp)
            move.w  #6,-(sp)
            dc.w    $a9c8                   ; _SysBeep
            movem.l (sp)+,d0-d2/a0-a1
            rts
        }}
    }

    asmsub ticks() -> long @D0 {
        ; -- the system's clock, which counts 60 times a second
        %asm {{
            move.l  $16a.w,d0
            rts
        }}
    }

    asmsub exit_to_shell() {
        %asm {{
            dc.w    $a9f4                   ; _ExitToShell
            ; !notreached!
        }}
    }

    ; ---- text ----

    sub cell_rect(ubyte col, ubyte line, ubyte count) {
        ; -- macos.rect is what so many characters take from a place on
        rect[0] = (TOP + (line as word) * CELL_HEIGHT) as uword
        rect[1] = (LEFT + (col as word) * CELL_WIDTH) as uword
        rect[2] = rect[0] + CELL_HEIGHT as uword
        rect[3] = rect[1] + (count as uword) * CELL_WIDTH as uword
    }

    sub text_rect() {
        rect[0] = TOP as uword
        rect[1] = LEFT as uword
        rect[2] = (TOP + ROWS * CELL_HEIGHT) as uword
        rect[3] = (LEFT + COLUMNS * CELL_WIDTH) as uword
    }

    sub set_cell(ubyte col, ubyte line, ubyte char) {
        ; -- a character at a place; the cursor stays where it is
        if col >= COLUMNS or line >= ROWS
            return
        uword at = (line as uword) * COLUMNS + col
        screen[at] = char
        attributes[at] = reverse as ubyte
        move_to(LEFT + (col as word) * CELL_WIDTH, TOP + ASCENT + (line as word) * CELL_HEIGHT)
        draw_char(char)
    }

    sub set_reverse(bool on) {
        reverse = on
        if on
            text_mode(4)
        else
            text_mode(0)
    }

    sub line_down() {
        row++
        if row >= ROWS {
            row = ROWS - 1
            scroll()
        }
        if ticks() - polled > 15
            poll()
    }

    sub scroll() {
        text_rect()
        scroll_rect(1)
        sys.memcopy(&screen + COLUMNS, &screen, CELLS - COLUMNS)
        sys.memcopy(&attributes + COLUMNS, &attributes, CELLS - COLUMNS)
        uword at
        for at in CELLS - COLUMNS to CELLS - 1 {
            screen[at] = ' '
            attributes[at] = 0
        }
    }

    sub cls() {
        text_rect()
        erase_rect()
        uword at
        for at in 0 to CELLS - 1 {
            screen[at] = ' '
            attributes[at] = 0
        }
        column = 0
        row = 0
    }

    sub clear_to_eol() {
        cell_rect(column, row, COLUMNS - column)
        erase_rect()
        uword at = (row as uword) * COLUMNS + column
        ubyte k
        for k in column to COLUMNS - 1 {
            screen[at] = ' '
            attributes[at] = 0
            at++
        }
    }

    sub redraw() {
        ; -- the whole text again, from what is kept of it
        text_rect()
        erase_rect()
        ubyte line
        for line in 0 to ROWS - 1 {
            uword at = (line as uword) * COLUMNS
            ubyte start = 0
            while start < COLUMNS {
                ubyte kind = attributes[at + start]
                ubyte end = start + 1
                while end < COLUMNS and attributes[at + end] == kind
                    end++
                if kind != 0
                    text_mode(4)
                else
                    text_mode(0)
                move_to(LEFT + (start as word) * CELL_WIDTH, TOP + ASCENT + (line as word) * CELL_HEIGHT)
                draw_text(&screen + at + start, end - start)
                start = end
            }
        }
        set_reverse(reverse)
    }

    sub chrout(ubyte char) {
        ; -- a character where the cursor is.  '\n' starts a new line, 13 goes to the
        ;    line's start, 8 one place back, 9 to the next column that 8 divides, 7 beeps.
        if unattended
            echo(char)
        if char >= 32 {
            set_cell(column, row, char)
            column++
            if column >= COLUMNS {
                column = 0
                line_down()
            }
            return
        }
        when char {
            10 -> {
                column = 0
                line_down()
            }
            13 -> column = 0
            8 -> {
                if column > 0
                    column--
            }
            9 -> {
                column = (column | 7) + 1
                if column >= COLUMNS {
                    column = 0
                    line_down()
                }
            }
            7 -> beep()
            else -> {
            }
        }
    }

    ; ---- events ----

    sub poll() {
        ; -- what has happened since the last time: keys are kept for chrin(), the
        ;    window is drawn again or moved when that is asked for
        polled = ticks()
        while next_event() {
            when event[0] {
                1 -> click()
                3, 5 -> key()
                6 -> {
                    if mklong2(event[1], event[2]) == window {
                        begin_update()
                        redraw()
                        end_update()
                    }
                }
                else -> {
                }
            }
        }
    }

    sub click() {
        when find_window() {
            2 -> system_click()
            3 -> clicked = true
            4 -> {
                if found_window == window
                    drag_window()
            }
            else -> {
            }
        }
    }

    sub key() {
        ubyte char = lsb(event[2])
        if event[7] & $0100 != 0 {
            ; with the command key: . and Q end the program
            if char == '.' or char == 'q' or char == 'Q' {
                echo_close()
                exit_to_shell()
            }
            return
        }
        ubyte after = (key_in + 1) & 31
        if after != key_out {
            keys[key_in] = char
            key_in = after
        }
    }

    sub keypressed() -> bool {
        ; -- is there a key waiting?
        poll()
        return key_in != key_out
    }

    sub chrin() -> ubyte {
        ; -- wait for a key and return its character, without showing it; the place
        ;    where the cursor is shows black meanwhile.  The return and enter keys are
        ;    '\n', the delete key 8, the arrows 28 to 31 (left, right, up, down).
        cell_rect(column, row, 1)
        invert_rect()
        while key_in == key_out
            poll()
        cell_rect(column, row, 1)
        invert_rect()
        ubyte char = keys[key_out]
        key_out = (key_out + 1) & 31
        if char == 13 or char == 3
            char = '\n'
        return char
    }

    str finished = "\x1eFinished: press a key or click"

    sub finish() {
        ; -- the program's end.  The window would be gone at once, with what the program
        ;    wrote: it stays until a key is pressed or the mouse is clicked in it,
        ;    unless the program set macos.quit_at_end or runs unattended.
        if not unattended and not quit_at_end {
            set_title(&finished)
            key_out = key_in
            clicked = false
            while key_in == key_out and not clicked
                poll()
        }
        if unattended {
            ; (for what runs the machine to see that the program is done: the system's
            ;  eight bytes for anybody's use, Scratch8)
            echo_close()
            pokel($09fa, $50385038)         ; "P8P8"
            pokel($09fe, $444f4e45)         ; "DONE"
        }
        exit_to_shell()
    }
}

sys {
    ; ------- lowlevel system routines --------

    const ubyte target = 53         ;  compilation target specifier.

    const ubyte SIZEOF_BOOL  = sizeof(bool)
    const ubyte SIZEOF_BYTE  = sizeof(byte)
    const ubyte SIZEOF_UBYTE = sizeof(ubyte)
    const ubyte SIZEOF_WORD  = sizeof(word)
    const ubyte SIZEOF_UWORD = sizeof(uword)
    const ubyte SIZEOF_LONG  = sizeof(long)
    const ubyte SIZEOF_POINTER = sizeof(&sys.wait)
    const ubyte SIZEOF_FLOAT = sizeof(float)
    const byte  MIN_BYTE     = -128
    const byte  MAX_BYTE     = 127
    const ubyte MIN_UBYTE    = 0
    const ubyte MAX_UBYTE    = 255
    const word  MIN_WORD     = -32768
    const word  MAX_WORD     = 32767
    const uword MIN_UWORD    = 0
    const uword MAX_UWORD    = 65535
    const long  MIN_LONG     = -2147483648
    const long  MAX_LONG     = 2147483647
    ; MIN_FLOAT and MAX_FLOAT are defined in the floats module if imported




    ; ----- the command line -----
    ; An application is not started with words after its name: there are none.

    str args_none = ""

    sub argc() -> uword {
        ; -- returns the number of command line arguments, including the program name: always 1 here
        return 1
    }

    sub argv(uword index) -> str {
        ; -- returns the command line argument at the 0-based index: an empty string here
        return args_none
    }

    sub reset_system() {
        ; -- end the program (an application does not restart the machine)
        exit(0)
    }

    sub poweroff_system() {
        exit(0)
    }

    sub die(uword code, str message) {
        ; -- kill the program: print the message, then exit.
        str @shared warning = iso:"\n\nPROGRAM DIED: "
        ubyte k = 0
        while warning[k] != 0 {
            macos.chrout(warning[k])
            k++
        }
        k = 0
        while message[k] != 0 {
            macos.chrout(message[k])
            k++
        }
        macos.chrout('\n')
        exit(code as word)
    }

    sub wait(uword jiffies) {
        ; --- wait the given number of jiffies (1/60th seconds); the window is kept alive meanwhile
        long end = macos.ticks() + jiffies
        while macos.ticks() - end < 0
            macos.poll()
    }

    sub waitvsync() {
        ; -- wait for the next tick of the system's clock, which is the screen's frame
        long now = macos.ticks()
        while macos.ticks() == now {
        }
    }

    sub exit(word returnvalue) {
        ; -- exit the program (an application gives no return code). When invoked from Prog8 via sys.exit(), all active defers in the call chain are unwound program-wide (LIFO) before system cleanup.
        macos.finish()
    }

    sub set_carry() {
        %option noframe
        %asm {{
            ; set both C (comparison carry) and X (rotate carry) bits
            moveq  #$11,d0
            move.w  d0,ccr
        }}
    }

    sub clear_carry() {
        %option noframe
        %asm {{
            moveq  #0,d0
            move.w  d0,ccr
        }}
    }

    sub clear_irqd() {
        ; (the interrupts are the system's)
    }

    sub set_irqd() {
    }

    asmsub memcopy(long source @A0, long tgt @A1, long count @D0) {
        ; Copy bytes from source to target. Allows long count.
        ; Bulk of the work uses long-aligned longword copies;
        ; pre-alignment and remainder bytes use individual byte copies.
        %asm {{
            movem.l  d2-d3,-(sp)
            move.l   d0,d2
            beq      .done

            ; check if both addresses share the same alignment offset
            move.l   a0,d0
            move.l   a1,d3
            eor.l    d3,d0
            andi.l   #3,d0
            bne      .bytes

            ; same alignment: pre-align both to a long boundary
            move.l   a0,d3
            and.w    #3,d3             ; d3 = offset (0-3)
            beq      .bulk
.loop_pre:
            move.b   (a0)+,(a1)+
            subq.l   #1,d2             ; track remaining count
            beq      .done
            move.l   a0,d3
            andi.l   #3,d3
            bne      .loop_pre

.bulk:
            move.l   d2,d3
            lsr.l    #2,d3             ; d3 = longword count
            beq      .rem
.loop_l:
            move.l   (a0)+,(a1)+
            subq.l   #1,d3
            bne      .loop_l

.rem:
            andi.l   #3,d2
            beq      .done
.loop_rem:
            move.b   (a0)+,(a1)+
            subq.l   #1,d2
            bne      .loop_rem
.done:
            movem.l  (sp)+,d2-d3
            rts

.bytes:
.loop_b:
            move.b   (a0)+,(a1)+
            subq.l   #1,d2
            bne      .loop_b
            movem.l  (sp)+,d2-d3
            rts
        }}
    }

    inline asmsub progstart() -> long @A0 {
        %asm {{
            lea  prog8_program_start,a0
        }}
    }

    asmsub progend() -> long @A0 {
        ; (the end of the program's code and data; its variables are elsewhere in the heap)
        %asm {{
            lea     prog8_program_start,a0
            adda.l  2(a0),a0
            rts
        }}
    }

    asmsub stack_size() -> long @D0 {
        ; -- Return the amount of stack space still available, in bytes.
        %asm {{
            move.l  sp,d0
            sub.l   $130.w,d0               ; ApplLimit: where the heap may grow to
            rts
        }}
    }

    asmsub cpuAtLeast68020() -> bool @D0 {
        %asm {{
            moveq   #0,d0       ; a Macintosh Plus has a 68000
            rts
        }}
    }
}
